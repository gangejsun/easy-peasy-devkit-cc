<!-- epcc-pack: backend/aws-container v3.12.0 -->
# 이식 가능한 경계 — AWS는 인프라 층에만 둔다

이 백엔드는 언젠가 온프레미스로 옮겨질 수 있다. 그래서 **AWS 종속은 인프라 층에 가두고
`src/` 아래 애플리케이션 코드는 벤더 중립으로 유지한다.** 이관이 "재배포"가 될지
"재작성"이 될지는 이 경계 하나로 갈린다.

## 판단 기준표

| 관심사 | 앱 코드(`src/`)가 아는 것 | 인프라 층(`infra/`, 배포)이 아는 것 |
| --- | --- | --- |
| 런타임 | `PORT`로 HTTP 리슨, SIGTERM 종료 | ECS/Fargate, ALB, 타깃 그룹, 오토스케일 |
| 데이터베이스 | `DATABASE_URL` 하나, 표준 PostgreSQL SQL | RDS 인스턴스, 파라미터 그룹, 백업, 서브넷 |
| 인증 | `OIDC_ISSUER` / `OIDC_JWKS_URL` / `OIDC_AUDIENCE` | Cognito 사용자 풀, 앱 클라이언트, 도메인 |
| 파일 저장 | `ObjectStorage` 포트 + `S3_ENDPOINT` | S3 버킷, 정책, 수명 주기 |
| 로깅 | stdout에 구조화 JSON 한 줄 | CloudWatch Logs 드라이버, 보존 기간, 구독 필터 |
| 설정·비밀 | `env` 모듈 하나 | Secrets Manager, 태스크 정의 주입 |
| 큐·비동기 | (도입 시) 포트 인터페이스 | SQS, 이벤트 브리지 |

**규칙 한 줄**: `src/` 안에서 AWS 제품명이 등장하는 곳은 `src/storage/` 어댑터뿐이다.

## 1. 런타임 — 표준 HTTP 서버

<!-- file: src/index.ts -->
```ts
// src/index.ts
import { serve } from '@hono/node-server'
import { app } from '@/app'
import { env } from '@/config/env'
import { pool } from '@/db/client'
import { log } from '@/http/logger'

const server = serve({ fetch: app.fetch, port: env.PORT })
log.info({ msg: 'listening', port: env.PORT })

const shutdown = () => {
  server.close(async () => { await pool.end(); process.exit(0) })
  setTimeout(() => process.exit(1), 10_000).unref()   // 드레인이 안 끝나면 강제 종료
}
process.on('SIGTERM', shutdown)
process.on('SIGINT', shutdown)
```

- 함수형 런타임 전용 어댑터(핸들러 시그니처, 콜드스타트 가정)를 쓰지 않는다. 같은
  이미지가 ECS·K8s·온프레미스 Docker에서 그대로 돈다
- Dockerfile의 `CMD`는 **exec 형식**(`CMD ["node", "dist/index.js"]`)으로 쓴다. 셸 형식이면
  `node`가 SIGTERM을 받지 못해 배포마다 연결이 끊긴다
- `/healthz`(liveness, DB 불필요)와 `/readyz`(DB `select 1`)를 분리한다. ALB는 `/healthz`를
  본다 — DB 순단으로 태스크를 재시작시키지 않기 위해서다
- 비루트 사용자로 실행하고, 이미지에 AWS 전용 베이스를 쓰지 않는다

## 2. 데이터베이스 — Aurora 전용 기능 회피

온프레미스 PostgreSQL과 **동일 엔진**을 유지한다. 앱이 보는 것은 접속 문자열 하나다.

쓰지 않는다:

- **Aurora Data API**(`@aws-sdk/client-rds-data`) — HTTP로 SQL을 보내는 AWS 전용 경로다.
  Drizzle의 `node-postgres` 드라이버로 표준 접속만 쓴다
- **IAM 데이터베이스 인증**(RDS signer로 임시 토큰 생성) — 앱 코드에 AWS 자격증명 로직이
  들어온다. 비밀번호를 Secrets Manager에서 env로 주입받는 방식이 이식 가능하다
- `aurora_*` 계열 함수·뷰, Aurora 전용 확장, Babelfish
- 리더 엔드포인트를 앱이 직접 고르는 분기 — 읽기 분리는 접속 문자열 하나를 더 두는 것으로
  충분하고, 그 값은 인프라가 정한다

RDS Proxy는 **인프라 층에 머무는 예**다. 앱은 호스트가 프록시인지 인스턴스인지 모른다.

## 3. 인증 — 표준 OIDC/JWKS

`jose`로 검증하고 발급자 정보는 전부 env다. Keycloak 전환 시 바뀌는 것:

| 값 | Cognito | Keycloak |
| --- | --- | --- |
| `OIDC_ISSUER` | `https://cognito-idp.<region>.amazonaws.com/<poolId>` | `https://<host>/realms/<realm>` |
| `OIDC_JWKS_URL` | `<issuer>/.well-known/jwks.json` | `<issuer>/protocol/openid-connect/certs` |
| 대상 클레임 | `client_id` (액세스 토큰) | `aud` |
| 그룹 클레임 | `cognito:groups` | `realm_access.roles` |

**코드가 바뀌는 곳은 클레임 정규화 함수 하나뿐**이다 (`resources/auth-and-permissions.md`).
`aws-jwt-verify`, `amazon-cognito-identity-js`, Cognito Admin SDK는 `src/`에 들이지 않는다.
사용자 생성·비밀번호 재설정 같은 관리 작업이 필요하면 별도 운영 스크립트로 분리한다.

## 4. 파일 저장 — S3 API를 포트 뒤에 둔다

S3 **프로토콜**은 MinIO가 그대로 구현한다. 그래서 SDK 사용 자체는 문제가 아니고,
**엔드포인트를 설정 가능하게 두고 어댑터 한 파일에 가두는 것**이 계약이다.

앱 코드가 보는 타입과 그것을 구현하는 어댑터는 **다른 파일**이다. 한 파일에 두면
`@aws-sdk`가 앱 코드의 import 그래프에 들어와 포트를 두는 의미가 사라진다.

<!-- file: src/storage/index.ts -->
```ts
// src/storage/index.ts — 앱 코드가 보는 유일한 타입
export interface ObjectStorage {
  put(key: string, body: Uint8Array, contentType: string): Promise<void>
  presignGet(key: string, expiresInSec: number): Promise<string>
}
```

<!-- file: src/storage/s3.ts -->
```ts
// src/storage/s3.ts — 유일하게 AWS SDK를 아는 파일
import { S3Client, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3'
import { getSignedUrl } from '@aws-sdk/s3-request-presigner'
import { env } from '@/config/env'
import type { ObjectStorage } from '@/storage'

const client = new S3Client({
  region: env.AWS_REGION,                     // 이 어댑터 설정의 일부 — 앱 로직은 리전을 모른다
  endpoint: env.S3_ENDPOINT,                  // 미설정 → AWS 기본, 설정 → MinIO 등
  forcePathStyle: Boolean(env.S3_ENDPOINT),   // MinIO는 path-style이 필요하다
})

export const s3Storage: ObjectStorage = {
  async put(key, body, contentType) {
    await client.send(new PutObjectCommand({
      Bucket: env.S3_BUCKET, Key: key, Body: body, ContentType: contentType,
    }))
  },
  async presignGet(key, expiresInSec) {
    // 서명 URL의 수명은 **초**다. 분으로 착각하면 60배 긴 URL이 나간다
    return getSignedUrl(client, new GetObjectCommand({ Bucket: env.S3_BUCKET, Key: key }),
                        { expiresIn: expiresInSec })
  },
}
```

`AWS_REGION`은 env 스키마에서 **선택 값**이다 (`resources/input-validation.md`). 온프레미스
MinIO에서는 비워 두고 `S3_ENDPOINT`만 준다 — 필수로 잡으면 AWS가 아닌 배포가 부팅에서 죽는다.

- 자격증명은 코드에 넣지 않는다. AWS에서는 태스크 역할이, 온프레미스에서는 env 자격증명이
  기본 제공자 체인으로 잡힌다
- 저장 키는 서버가 만든다(`tasks/<ownerId>/<uuid>`). 클라이언트가 보낸 파일명을 키로 쓰면
  경로 조작과 덮어쓰기가 열린다

## 5. 로깅 — stdout 구조화 JSON

CloudWatch SDK로 직접 쓰지 않는다. 컨테이너는 stdout에 한 줄씩 뱉고, **수집은 인프라의 일**이다
(ECS는 awslogs 드라이버, 온프레미스는 Fluent Bit·Loki 등).

```ts
// src/http/logger.ts
import { createMiddleware } from 'hono/factory'
import { env, publicEnvKeys } from '@/config/env'
import type { AppEnv } from '@/http/types'

const ORDER = { debug: 10, info: 20, warn: 30, error: 40 } as const
type Level = keyof typeof ORDER

function emit(level: Level, fields: Record<string, unknown>) {
  if (ORDER[level] < ORDER[env.LOG_LEVEL as Level]) return
  process.stdout.write(JSON.stringify({ ts: new Date().toISOString(), level, ...fields }) + '\n')
}

export const log = {
  debug: (f: Record<string, unknown>) => emit('debug', f),
  info: (f: Record<string, unknown>) => emit('info', f),
  warn: (f: Record<string, unknown>) => emit('warn', f),
  error: (f: Record<string, unknown>) => emit('error', f),
}

// 부팅 시 1회 — 화이트리스트가 아니라 목록 밖의 키는 구조적으로 오를 수 없다
// (src/index.ts에서 serve() 직후 호출한다)
export function logBootConfig() {
  const cfg = Object.fromEntries(
    publicEnvKeys.map((k) => [k, (env as Record<string, unknown>)[k]]),
  )
  log.info({ msg: 'boot config', config: cfg })   // DATABASE_URL·AUTH_STATE_SECRET은 목록에 없다
}
```

"찍지 말아야 할 것을 지운다"가 아니라 **"찍어도 되는 것만 고른다"**로 뒤집는 것이 핵심이다.
블랙리스트는 env 키가 하나 늘 때마다 갱신을 요구하고, 잊으면 조용히 비밀이 나간다.

```ts
// requestId 부여 + 접근 로그 (src/http/logger.ts)
export const requestContext = createMiddleware<AppEnv>(async (c, next) => {
  const incoming = c.req.header('x-request-id')
  const requestId = incoming && /^[\w-]{1,64}$/.test(incoming) ? incoming : crypto.randomUUID()
  c.set('requestId', requestId)
  c.header('x-request-id', requestId)
  const started = performance.now()
  await next()
  log.info({ msg: 'request', method: c.req.method, path: c.req.path,
    status: c.res.status, ms: Math.round(performance.now() - started), requestId })
})
```

- 외부에서 온 `x-request-id`는 검증 후 쓴다 — 로그 인젝션 경로다
- 토큰·비밀번호·`DATABASE_URL`·`AUTH_STATE_SECRET`·전체 요청 본문을 로그에 넣지 않는다
- **PII도 같은 금지 목록에 있다**: 이메일·전화번호·이름·주소·IP. `AuthUser`가 `email`을 들고
  있으므로 `log.info({ user })` 한 줄이면 이메일이 로그 수집기와 보존 기간 전체에 복제된다.
  사용자 식별은 `sub`만 찍는다 — `log.info({ msg: '...', sub: c.get('user').sub })`
- 객체를 통째로 펼치지 않는다(`{ ...user }`, `{ ...row }`). 지금은 안전해도 **컬럼이 하나
  추가되는 순간** 그 값이 로그에 실린다. 찍을 필드를 이름으로 나열한다
- 메시지는 `msg` 필드에 두고 나머지는 구조화 필드로. 문자열 연결 로그는 검색이 안 된다

## 6. 설정과 비밀 — env 단일 진입점

Secrets Manager는 **주입 수단**일 뿐이다. 앱은 런타임에 비밀 저장소를 조회하지 않는다.

```ts
// infra/lib/service-stack.ts — 앱 코드가 아니다. src/에서 절대 import하지 않는다
taskDefinition.addContainer('api', {
  image: ecs.ContainerImage.fromAsset('.'),
  environment: { PORT: '8080', OIDC_ISSUER: issuerUrl, S3_BUCKET: bucket.bucketName },
  secrets: { DATABASE_URL: ecs.Secret.fromSecretsManager(dbSecret, 'url') },
  logging: ecs.LogDrivers.awsLogs({ streamPrefix: 'api' }),
  portMappings: [{ containerPort: 8080 }],
})
```

온프레미스에서는 같은 키를 K8s Secret이나 `.env` 파일로 주면 끝이다. **앱은 차이를 모른다.**

## 이관 체크리스트 (온프레미스로 옮길 때 실제로 바뀌는 것)

- [ ] 컨테이너 오케스트레이터: ECS 태스크 정의 → K8s Deployment (같은 이미지)
- [ ] 접속 문자열: RDS 엔드포인트 → 내부 PostgreSQL 호스트 (`DATABASE_URL`만)
- [ ] TLS 신뢰 앵커: RDS 번들 → 사내 CA 번들 (`DB_CA_PATH` 값만, 코드 무변경)
- [ ] IdP: `OIDC_*` 세 값 교체 + 그룹 클레임 정규화 함수 1개 수정
- [ ] 객체 저장소: `S3_ENDPOINT` 설정 + 자격증명 env (어댑터 코드 무변경)
- [ ] 로그 수집기: awslogs 드라이버 → Fluent Bit 등 (앱 무변경)
- [ ] 비밀 주입: Secrets Manager → K8s Secret (env 키 이름 동일)
- [ ] 마이그레이션: 같은 `drizzle-kit migrate`를 일회성 Job으로

## 경계를 CI로 강제한다

규율만으로는 유지되지 않는다. 이 세 줄이 비어 있어야 한다.

```bash
grep -rn "@aws-sdk" src/ --include=*.ts | grep -v "^src/storage/"      # 저장소 어댑터 외 금지
grep -rn "aws-cdk-lib\|aws-jwt-verify\|amazon-cognito" src/            # 인프라·벤더 SDK 금지
grep -rn "process\.env" src/ --include=*.ts | grep -v "src/config/env.ts"   # env 단일 진입점
```

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| Secrets Manager SDK 런타임 조회 vs env 주입 | 주입이 기본. 런타임 조회는 부팅 지연·IAM 종속·장애면을 늘린다 |
| CloudWatch `PutLogEvents` SDK vs stdout | 컨테이너는 stdout만 안다. 수집은 로그 드라이버의 일 |
| `aws-jwt-verify` vs `jose` | 표준 OIDC 검증만 쓴다. 전자는 발급자를 코드에 못 박는다 |
| Aurora Data API vs `node-postgres` | 표준 프로토콜 접속만. Data API는 이관 시 데이터 액세스 층 전량 재작성 |
| IAM DB 인증 vs 비밀번호 주입 | 비밀번호를 주입받는다. IAM 인증은 앱에 AWS 자격증명 로직을 들인다 |
| S3 SDK 직접 호출 vs `ObjectStorage` 포트 | 포트 뒤에 둔다. 어댑터가 한 파일이면 MinIO 전환이 설정 변경으로 끝난다 |
| `AWS_REGION`을 앱 로직 분기에 사용 | 리전은 인프라 값이다. 앱이 리전으로 동작을 바꾸면 온프레미스에서 갈 곳이 없다 |
| ALB에 인증을 위임 vs 앱에서 검증 | 앱이 스스로 검증한다. 프록시가 바뀌면 인증이 통째로 사라지는 구성은 만들지 않는다 |
| CDK 상수를 `src/`에서 import | 방향은 항상 `infra/` → 컨테이너 환경변수. 역방향 import는 이관 시 순환 의존이 된다 |
