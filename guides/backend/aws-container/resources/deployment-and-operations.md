<!-- epcc-pack: backend/aws-container v3.12.0 -->
# 배포와 운영 — 이미지, 배포 순서, 헬스체크, 성능

컨테이너 이미지를 만들고, 마이그레이션과 앱을 **분리해서** 내보내고, 뜬 뒤에 관측하는 구간을
다룬다. 여기 있는 것은 전부 인프라 층의 일이므로 `src/`는 이 파일의 내용을 알지 못한다.

## 멀티스테이지 Dockerfile

```dockerfile
# syntax=docker/dockerfile:1
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci                                  # devDependencies 포함 — 빌드에 필요하다
COPY . .
RUN npm run build                           # tsc → dist/

FROM node:22-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production
RUN apk add --no-cache curl                 # 헬스체크용. 없으면 wget -q -O- 를 쓴다
ADD https://truststore.pki.rds.amazonaws.com/global-bundle.pem /etc/ssl/rds/global-bundle.pem
ENV DB_CA_PATH=/etc/ssl/rds/global-bundle.pem
COPY package*.json ./
RUN npm ci --omit=dev                       # 런타임 의존성만
COPY --from=build /app/dist ./dist
COPY --from=build /app/drizzle ./drizzle    # 마이그레이션 태스크가 같은 이미지를 쓴다
USER node                                   # 비루트 실행
EXPOSE 8080
CMD ["node", "dist/index.js"]               # exec 형식 — 셸 형식이면 SIGTERM을 못 받는다
```

- **`CMD`는 반드시 exec 형식**이다. 셸 형식(`CMD node dist/index.js`)이면 PID 1이 `/bin/sh`가
  되어 SIGTERM이 Node에 전달되지 않고, 배포마다 연결이 강제로 끊긴다
- 베이스 이미지는 벤더 중립으로 둔다. AWS 전용 베이스를 쓰면 온프레미스 이관이 이미지
  재작성이 된다 (`resources/portability-boundaries.md`)
- `drizzle/`를 런타임 이미지에 넣는 이유는 아래 배포 순서 때문이다 — **같은 이미지가 앱과
  마이그레이션 태스크 양쪽으로 실행된다.** 두 이미지를 따로 만들면 버전이 어긋난다

## 로컬 패리티 (`docker-compose.yml`)

```yaml
services:
  db:
    image: postgres:16-alpine            # 운영 RDS와 같은 메이저
    environment: { POSTGRES_USER: app, POSTGRES_PASSWORD: local, POSTGRES_DB: app }
    ports: ['5432:5432']
    volumes: ['./docker/init-test-db.sql:/docker-entrypoint-initdb.d/10-test-db.sql:ro']
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U app -d app']
      interval: 2s
      timeout: 3s
      retries: 20
  app:
    build: .
    environment:                         # env 스키마의 필수 키를 하나도 빠뜨리지 않는다
      DATABASE_URL: postgres://app:local@db:5432/app
      DB_SSL: 'false'                    # 루프백 평문 — DB_CA_PATH가 필요 없다
      CORS_ORIGINS: http://localhost:5173
      OIDC_ISSUER: ${OIDC_ISSUER}
      OIDC_JWKS_URL: ${OIDC_JWKS_URL}
      OIDC_AUDIENCE: ${OIDC_AUDIENCE}
      OIDC_AUTHORIZE_BASE: ${OIDC_AUTHORIZE_BASE}
      SPA_CALLBACK_URL: http://localhost:5173/auth/callback
      SPA_LOGOUT_URL: http://localhost:5173/
      AUTH_STATE_SECRET: local-only-secret-at-least-32-characters
      S3_BUCKET: local-bucket
    depends_on:
      db: { condition: service_healthy }
    ports: ['8080:8080']
```

**compose는 env 스키마의 첫 번째 테스트다.** 필수 키가 하나라도 빠지면 앱 컨테이너가
`process.exit(1)`로 즉시 죽는다 — 스키마에 키를 추가할 때마다 이 블록도 같이 고친다.
`depends_on.condition: service_healthy`가 없으면 앱이 DB보다 먼저 떠서 첫 쿼리가 깨진다.

```bash
docker compose up -d --wait && TOKEN=<Cognito 액세스 토큰>     # 스모크 체크
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/healthz      # 200 (인증 없음)
curl -s -o /dev/null -w '%{http_code}\n' localhost:8080/api/tasks    # 401 (토큰 없음)
curl -s -X POST localhost:8080/api/tasks -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"title":"첫 작업"}' | jq
```

## 배포 순서 — 마이그레이션은 별도 일회성 태스크다

앱 부팅에서 `migrate()`를 부르면 동시에 뜨는 Fargate 태스크들이 같은 마이그레이션을
경합한다. 순서를 파이프라인이 강제한다.

```
① 이미지 빌드·푸시 (태그 = 커밋 SHA)
② 마이그레이션 태스크 1개 실행:  RunTask(overrides: command = ["npx","drizzle-kit","migrate"])
   └ 종료 코드가 0이 아니면 여기서 배포를 멈춘다 (서비스는 아직 구 버전 그대로다)
③ 서비스 업데이트 (롤링): 새 태스크가 헬스체크를 통과해야 구 태스크가 빠진다
④ 실패 시 서비스만 롤백한다 — 스키마는 되돌리지 않는다
```

- **④가 성립하려면 마이그레이션이 항상 하위 호환**이어야 한다. 구 버전 코드가 새 스키마에서
  돌아야 롤백이 가능하다. 그래서 파괴적 변경을 나눈다: ① 컬럼 추가 → ② 백필 + 신구 코드
  동시 지원 → ③ NOT NULL 승격·구 컬럼 제거 (`resources/data-access.md`)
- 마이그레이션 태스크는 **앱과 같은 이미지·같은 태그**로 돌린다. 다른 이미지를 쓰면
  "코드는 새 버전, 스키마는 다른 커밋"이 되는 경로가 생긴다
- 태스크가 여러 번 재시도돼도 안전해야 한다. `drizzle-kit migrate`는 적용 기록을 보고
  건너뛰므로 재실행이 안전하다 — 손으로 쓴 일회성 SQL을 끼워 넣으면 이 성질이 깨진다

## 헬스체크와 그레이스풀 셧다운

| 경로 | 보는 것 | 누가 | 실패했을 때 |
| --- | --- | --- | --- |
| `/healthz` | 프로세스가 살아 있는가 (DB 미접속) | ALB 타깃 그룹, ECS | 태스크 교체 |
| `/readyz` | DB까지 붙는가 (`select 1`) | 배포 검증·모니터링 | 알람 (교체는 하지 않는다) |

**ALB 헬스체크에 `/readyz`를 걸지 않는다.** RDS 페일오버 몇 초에 모든 태스크가 동시에
불건전 판정을 받아 전량 교체되고, 그 재기동이 DB 부하를 다시 밀어 올린다.

```
SIGTERM 수신 → 새 연결 수락 중단 → 진행 중 요청 종료 대기 → pool.end() → exit(0)
```

- ECS `stopTimeout`(기본 30초)을 서버의 드레인 타임아웃(`resources/portability-boundaries.md`의
  10초)보다 **길게** 잡는다. 반대면 정리 도중 SIGKILL이 온다
- ALB의 **deregistration delay**(기본 300초)를 요청 최대 처리 시간 수준으로 줄인다. 길면
  배포마다 이미 빠진 태스크를 기다리고, 너무 짧으면 처리 중인 요청이 끊긴다
- 컨테이너 헬스체크는 `CMD-SHELL curl -fsS localhost:8080/healthz || exit 1` 형태로 둔다

## 커넥션 풀 사이징

```
동시 연결 상한 = (태스크 수 최대치 × DB_POOL_MAX) + 마이그레이션 태스크 + 운영 접속 여유
이 값이 RDS의 max_connections 를 넘으면, 오토스케일이 곧 장애다
```

- 오토스케일 **상한**으로 계산한다. 평시 태스크 수로 계산하면 트래픽이 몰리는 순간
  스케일 아웃이 DB 연결 거부를 만든다 — 장애가 부하가 아니라 배포 설정에서 온다
- `DB_POOL_MAX`는 크게 잡을수록 좋은 값이 아니다. PostgreSQL은 연결마다 프로세스를 쓰므로
  유휴 연결이 메모리를 먹는다. 태스크당 5~10에서 시작해 대기 시간을 보고 조정한다
- 태스크 수를 크게 늘려야 한다면 풀을 키우는 대신 **RDS Proxy 같은 연결 풀러를 인프라
  층에** 둔다. 앱은 호스트가 프록시인지 인스턴스인지 모른다
- `connectionTimeoutMillis`(5초)를 남겨 둔다. 풀이 마르면 무한 대기가 아니라 **빠른 실패**가
  낫다 — 대기가 쌓이면 ALB 타임아웃까지 모든 요청이 함께 죽는다

## 느린 쿼리와 N+1을 실제로 본다

애플리케이션에 계측이 없으면 "느리다"는 보고가 추측으로 끝난다. 두 축을 켠다.

**DB 쪽**: RDS 파라미터 그룹의 `log_min_duration_statement`(예: 500ms)와 `auto_explain`
확장을 켜면 느린 쿼리와 실행 계획이 로그로 나온다. `pg_stat_statements`로 호출 횟수 ×
평균 시간이 큰 쿼리를 찾는다 — **총합이 큰 쿼리가 범인이고, 한 번 느린 쿼리는 대개 아니다.**

**앱 쪽**: 요청 로그에 요청당 쿼리 수를 실어 N+1을 눈에 보이게 만든다.

```ts
// 요청 스코프 카운터를 requestContext에 얹는다 (src/http/logger.ts)
log.info({ msg: 'request', method: c.req.method, path: c.req.path,
  status: c.res.status, ms, queries: c.get('queryCount'), requestId })
```

- 목록 엔드포인트의 `queries`가 **항목 수에 비례해 늘면 N+1**이다. 상수여야 한다
  (`resources/data-access.md`의 배치 조회)
- 커서 페이지네이션이 인덱스를 타는지 `EXPLAIN`으로 확인한다. `Seq Scan on tasks`가 보이면
  소유자 인덱스가 없거나 정렬 키와 어긋난 것이다
- 지표는 요청 수·p95 지연·5xx 비율·풀 대기 시간 네 개로 시작한다. 대시보드를 먼저 늘리면
  아무도 보지 않는 그래프가 생긴다

## 온프레미스에서 달라지는 지점

| 관심사 | AWS | 온프레미스 |
| --- | --- | --- |
| 오케스트레이션 | ECS 서비스 + 태스크 정의 | K8s Deployment (**같은 이미지**) |
| 마이그레이션 실행 | `RunTask` 일회성 태스크 | K8s Job (같은 이미지, 같은 command) |
| 헬스체크 | ALB 타깃 그룹 + 컨테이너 헬스체크 | Service/Ingress + liveness·readiness probe |
| 드레인 | deregistration delay | `terminationGracePeriodSeconds` + preStop |
| DB TLS 신뢰 | RDS 번들 (`DB_CA_PATH`) | 사내 CA 번들 (**같은 키**) |
| 로그 | awslogs 드라이버 → CloudWatch | Fluent Bit·Loki (앱은 stdout만 안다) |
| 비밀 주입 | Secrets Manager → 태스크 정의 | K8s Secret → env (키 이름 동일) |

**바뀌는 것은 전부 이 파일과 `infra/`에 있다.** `src/`에서 고칠 파일이 생긴다면 경계가
새고 있다는 뜻이므로, 이관 전에 `resources/portability-boundaries.md`의 CI 검사부터 돌린다.

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 부팅 시 `migrate()` vs 별도 태스크 | 부팅 실행은 동시에 뜨는 태스크들이 경합한다 → 배포 파이프라인의 일회성 태스크 |
| `/readyz`를 ALB 헬스체크로 | DB 순단에 전 태스크가 교체된다 → ALB는 `/healthz`, `/readyz`는 알람용 |
| `CMD node dist/index.js` (셸 형식) | PID 1이 셸이 되어 SIGTERM이 전달되지 않는다 → exec 형식 `["node","dist/index.js"]` |
| 단일 스테이지 이미지 | devDependencies와 소스가 운영 이미지에 남는다 → build/runtime 분리 + `--omit=dev` |
| 앱과 마이그레이션에 다른 이미지 | 코드와 스키마 버전이 어긋난다 → 같은 태그, command만 다르게 |
| 롤백할 때 스키마도 되돌리기 | 마이그레이션 롤백은 데이터 손실 경로다 → 하위 호환 마이그레이션 + 서비스만 롤백 |
| `DB_POOL_MAX`를 키워 대기 해소 | 연결이 늘면 RDS가 먼저 한계에 닿는다 → 상한 계산 후 풀러를 인프라 층에 |
| 평시 태스크 수로 연결 계산 | 오토스케일 상한으로 계산한다. 아니면 스케일 아웃이 곧 장애다 |
| APM 없이 "느린 것 같다" | `pg_stat_statements` + 요청당 쿼리 수 로그. 총합이 큰 쿼리부터 본다 |
