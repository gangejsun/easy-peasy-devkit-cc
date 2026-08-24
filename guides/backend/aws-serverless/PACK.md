<!-- epcc-pack: backend/aws-serverless v3.13.0 verified 2026-08-23 @aws-sdk/client-dynamodb@3 @aws-sdk/lib-dynamodb@3 @aws-lambda-powertools/logger@2 aws-cdk-lib@2 constructs@10 zod@4 typescript@5 vitest@2 esbuild@0 @types/aws-lambda@8 @types/node@22 aws-jwt-verify@5 -->

# aws-serverless 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 그대로 삽입할 축-지역 조각이다. 각 조각은
`<!-- pack-slot: 이름 -->` 사이에 있고 축 안에서 닫혀 있다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── env.ts                   # `src/` 안에서 프로세스 환경을 읽는 유일한 파일 (콜드 스타트에 검증·실패)
├── keys.ts                  # 단일 테이블 키 조립 — pk/sk를 만드는 유일한 자리
├── db/
│   ├── client.ts            # DocumentClient 싱글턴 — **모듈 최상위**에서 만든다
│   └── tasks.ts             # Query/조건부 쓰기. 이벤트도 응답도 모른다
├── schemas/
│   └── task.ts              # Zod 스키마 — 본문·쿼리
├── http/
│   ├── parse.ts             # parseBody/parseQuery/pathParam — 이벤트에서 값을 꺼낸다
│   ├── errors.ts            # ERROR_STATUS 표 · DynamoDB 에러 판별 · ZodError 정규화
│   ├── app-error.ts         # AppError — **이음매가 소유한다**
│   ├── respond.ts           # 봉투 방출 — **이음매가 소유한다**
│   └── require-auth.ts      # requireAuth · AuthUser — **이음매가 소유한다**
├── obs/
│   └── logger.ts            # powertools 로거 · withContext 래퍼 · 콜드 스타트 플래그
├── handlers/                # 라우트당 함수 하나. export const handler = withContext(...)
└── services/                # 여러 쿼리를 묶는 도메인 로직
infra/
├── app.ts                   # CDK 엔트리
├── table.ts                 # TaskTable 구성 (단일 테이블 + GSI1)
└── routes.ts                # 라우트↔함수 매핑 — **이음매가 소유한다**
test/
└── invoke.ts                # 핸들러를 직접 태우는 하네스
```

**계층은 한 방향으로만 흐른다**: `handlers → services → db`. 예외는 **둘**이다 —
`http/app-error.ts`(도메인 실패의 공통 타입)와 `http/errors.ts`(SDK 예외 판별기).
둘 다 HTTP를 모르는 순수 모듈이라 `db/`가 import해도 방향이 뒤집히지 않는다.
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

**모듈 해석은 `bundler`** — 상대 import에 확장자를 붙이지 않는다. 번들은 esbuild가 하고
Lambda에는 번들 결과가 올라간다.

**이벤트는 `APIGatewayProxyEventV2`다.** `body` · `queryStringParameters` ·
`pathParameters`는 **선택 필드**이지 `| null`이 아니다 (`| null`은 V1의 형태다 —
`@types/aws-lambda@8.10.162` 대조). 양쪽에 안전한 `?? {}` · `?.` 형태로 꺼낸다.

**서버리스가 바꾸는 것 셋.** ① 상주 커넥션이 없다 — 클라이언트는 모듈 최상위에서 만들어
콜드 스타트 밖에 두고, 관계형 DB로 바꾸면 커넥션 풀링이 필수 주제가 된다. ② 미들웨어
체인이 없다 — `requireAuth`는 미들웨어가 아니라 **핸들러 첫 줄에서 부르는 함수**다.
③ 함수가 권한의 단위다 — 라우트마다 함수를 나눠야 최소 권한이 성립한다.

**데이터 계층 정책 엔진이 없다.** DynamoDB에는 RLS 같은 강제가 없고 IAM 조건 키는 범용
대체가 아니다 — **애플리케이션 층이 실질적 유일 경계**이고 소유자는 파티션 키에 들어간다.
BaaS 축의 "이중 방어" 서술을 옮기면 정확히 반대 지침이 된다.

**T1 데이터 모델링 카드는 휴면한다.** 그 카드는 관계형 전제이고 `paths:`도 매칭되지
않는다 — 단일 테이블 설계·접근 패턴 우선은 `resources/data-modeling.md`가 소유한다.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
<!-- L2가 채운다 — L0의 선언 원장만으로 조립한다 -->
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
<!-- L2가 채운다 -->
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
<!-- L2가 채운다 -->
<!-- /pack-slot -->

## 이음매가 채울 것

| 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| `api-endpoints` | 라우트↔함수 매핑과 응답 봉투. 봉투는 와이어 계약이 정한다 |
| `auth-boundaries` | Cognito 토큰 검증과 클레임 추출. 인증 방식은 프론트 축에 달렸다 |
| `complete-example` | IaC → 테이블 → 접근 패턴 → 쿼리 → 핸들러 → 테스트 관통 |
