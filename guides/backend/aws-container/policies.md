<!-- epcc-pack-policies: backend/aws-container v3.12.0 -->

# aws-container 팩 — 파일 간 불변식

이 팩이 **선언한 정책을 이음매가 지키는지** 게이트가 대조한다. 실측에서 감사 지적의
최대 부류(57건 중 26건)가 "정책을 선언한 곳과 강제하는 곳이 다르고 둘을 맞춰볼 의무가
없다"였다 — 이 파일이 그 의무다.

> **이 축의 전제**: 데이터 계층에 행 수준 정책 엔진이 없다. 아래 소유권 관련 정책은
> 편의가 아니라 **유일한 방어선**이다. 정책 엔진이 있는 축(BaaS)의 팩에서 이 절을
> 복사해 오면 강도가 반대로 뒤집힌다.

## 기계 검사 (게이트 `check_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간
아님. 아래 항목은 전부 **추출 시점에 사전 제작 이음매로 시험해 위반 0을 확인**했다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 설명 |
| --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | seam | `process\.env` | `SKILL.md` | 앱 코드는 `process.env`를 직접 읽지 않는다. 검증된 `env` 모듈만 import한다 — 누락이 첫 요청이 아니라 부팅에서 죽어야 한다. **허브(`SKILL.md`)는 예외다** — env 모듈 자신의 정의를 ✅ 예시로 싣기 때문이고, 이는 정책의 반례가 아니라 정책이 가리키는 그 지점이다 (게이트 최초 실행에서 위양성으로 확인) |
| `boot-time-env-validation` | require | guide | `safeParse\(process\.env\)` | — | 부팅 검증은 `safeParse` + `process.exit(1)` 한 형태만. `parse`의 예외는 어느 키가 빠졌는지를 로그에서 잃는다 |
| `no-vendor-sdk-in-app` | forbid | guide | `aws-jwt-verify\|CognitoJwtVerifier` | `portability-boundaries.md`, `deployment-and-operations.md` | 벤더 전용 검증 라이브러리는 이관을 코드 재작성으로 만든다. 표준 OIDC/JWKS(`jose`)를 쓴다 |
| `db-layer-knows-no-http` | forbid | file:`data-access.md` | `\bContext\b\|\bc\.req\b` | — | `db/queries/`는 Hono `Context`를 모른다. 역방향 import는 계층을 무너뜨린다 |
| `ownership-in-query` | require | guide | `eq\([a-z]+\.ownerId` | — | 조회·변이 모든 쿼리에 소유자 조건을 넣는다. 데이터 계층이 백업해 주지 않는다 |
| `mutation-returning` | require | guide | `\.returning\(\)` | — | 0행 변이를 성공으로 응답하지 않는다 — "지웠다는데 남아 있는" 버그의 원천 |

`대상`이 `guide`면 조립된 가이드 전체(팩 + 이음매), `seam`이면 이음매 파일만,
`file:<이름>`이면 그 파일만 본다. `require`는 조립 후 최소 1회 등장이면 충족이다.

## 사람이 지킬 것 (기계로 판정 불가 — 시험에서 위양성 확인됨)

- **소유자 조건이 없는 쿼리는 별도 파일로 격리한다.** `src/db/queries/admin-*.ts`가
  유일한 예외이고 그 서브 앱 전체가 역할 가드 뒤에 있어야 한다. 같은 함수에 `isAdmin`
  플래그를 넣지 않는다 — 플래그 하나가 잘못 흘러오면 전 테이블이 열린다.
  *(정규식으로 잡으면 이 정당한 격리 파일이 위반으로 찍힌다 — 추출 시점에 확인)*
- **공개 경로를 인증 미들웨어보다 먼저 등록한다.** 등록 순서대로 실행되므로
  `/healthz`가 뒤에 오면 헬스체크가 401로 죽는다. 순서는 정규식으로 판정할 수 없다
- **부재와 미인가는 동일한 응답이다.** 403과 404를 구분하면 미인가 사용자가 리소스
  존재를 열거할 수 있다. 403은 소유자 아닌 축(역할 부족)에만 쓴다
- **에러 메시지에 DB 제약명·SQL·스택을 담지 않는다** — 스키마가 새어 나간다
- **마이그레이션을 서버 부팅에서 실행하지 않는다** — 태스크 여러 개가 동시에 경합한다
