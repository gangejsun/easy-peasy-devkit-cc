<!-- epcc-pack: backend/aws-serverless v3.13.0 verified 2026-08-23 @aws-sdk/client-dynamodb@3 @aws-sdk/lib-dynamodb@3 @aws-lambda-powertools/logger@2 aws-cdk-lib@2 constructs@10 zod@4 typescript@5 vitest@2 esbuild@0.28 @types/aws-lambda@8 @types/node@22 aws-jwt-verify@5 -->

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
## Core Principles

1. **소유권은 파티션 키에 있다.** 정책 엔진이 없으므로 `pk`에 소유자를 넣고 조건식으로
   확인한다. 읽어와서 `.filter()`로 거르는 형태는 이미 남의 아이템을 읽은 뒤이고,
   **조건식 없는 `DeleteCommand`는 없는 아이템에도 성공한다** — 성공은 「지웠다」가
   아니라 「끝났을 때 없다」는 뜻이다 (`data-access.md` 4절 · `data-modeling.md` 5절).
2. **접근 패턴 표를 먼저 채운다.** 단일 테이블 설계에서 키는 질의의 함수다. 엔티티부터
   그리면 나중에 `Scan`으로 메우게 되고, 그때는 키를 바꿀 수 없다 (`data-modeling.md` 1절).
3. **클라이언트는 모듈 최상위에서 만든다.** 핸들러 안에서 만들면 호출마다 새 연결이 서고
   콜드 스타트 밖으로 뺄 수 있던 비용이 매 요청에 붙는다. 반대로 **요청마다 달라지는 값은
   최상위에 두지 않는다** — 그 값은 다음 호출로 샌다 (`data-access.md` 2절 · `handler-patterns.md` 1절).
4. **미들웨어 체인이 없다.** `requireAuth`는 미들웨어가 아니라 **핸들러 첫 줄에서 부르는
   함수**이고, 래퍼는 `withContext` 하나로 끝낸다. 래퍼를 쌓으면 어느 층이 응답을 만들었는지
   추적이 끊긴다 (`handler-patterns.md` 4절).
5. **함수가 권한의 단위다.** 라우트마다 함수를 나눠야 최소 권한이 성립한다. 한 함수에
   전 라우트를 붙이면 그 함수의 IAM 정책은 모든 동작의 합집합이 된다 (`deploy-and-iam.md` 3절).
6. **환경은 콜드 스타트에 실패시킨다.** `src/env.ts`가 모듈 최상위에서 `safeParse`하므로
   잘못된 환경은 부팅 실패다. 요청 시점에 터지면 절반이 살아 있는 함수가 된다
   (`input-validation.md` 2절).
7. **상태 매핑은 `ERROR_STATUS` 한 표뿐이다.** 핸들러마다 상태를 고르면 같은 실패가
   경로마다 다른 코드로 나간다 (`error-handling.md` 2절).
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

```ts
// 이벤트·컨텍스트 타입 — V2다. body·queryStringParameters·pathParameters는 선택 필드다
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2, Context } from 'aws-lambda';

// DynamoDB — 저수준 클라이언트를 Document 클라이언트로 감싸 한 번만 만든다
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';
import { GetCommand, QueryCommand, PutCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';

// 검증 — 경계마다 스키마. 환경변수도 같은 도구로 본다
import { z } from 'zod';

// 관측 — powertools는 아무것도 가리지 않는다. 무엇을 싣는지는 호출자가 정한다
import { Logger } from '@aws-lambda-powertools/logger';

// 인프라(infra/) — 런타임 코드와 같은 저장소, 다른 번들
import { App, Duration, RemovalPolicy, Stack } from 'aws-cdk-lib';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { Architecture, Runtime } from 'aws-cdk-lib/aws-lambda';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import { LogGroup, RetentionDays } from 'aws-cdk-lib/aws-logs';
import { Construct } from 'constructs';

// 표준 라이브러리 — 커서 인코딩과 ID 생성
import { Buffer } from 'node:buffer';
import { randomUUID } from 'node:crypto';
```

**상대 import에 확장자를 붙이지 않는다** — 모듈 해석이 `bundler`이고 번들은 esbuild가 한다.
`import { ddb } from './client'`이지 `'./client.js'`가 아니다.

**`routes`·`AppError`·`respond`·`requireAuth`는 이음매가 소유한다.** 팩은 부르기만 하고,
조립 전에는 정의가 없는 것이 정상이다.
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
## HTTP 상태 매핑과 반복되는 안티패턴

`ERROR_STATUS`가 **유일한 매핑표**다. 읽을 때는 `ERROR_STATUS[code] ?? 500` 형태를 쓴다 —
모르는 코드에서 `undefined`가 상태 자리에 들어가면 응답 자체가 깨진다.

| 도메인 코드 | 상태 | 언제 |
| --- | --- | --- |
| `VALIDATION_FAILED` | 400 | 스키마·형식 위반 · `ValidationException` · 커서 디코드 실패 |
| `UNAUTHENTICATED` | 401 | 토큰이 없거나 검증에 실패했다 |
| `FORBIDDEN` | 403 | 주체는 확인됐지만 **역할이 모자란다** |
| `NOT_FOUND` | 404 | 내 파티션에 없다 — **남의 아이템도 여기다** |
| `CONFLICT` | 409 | 이미 있는 것을 또 만들려 했다 (`putTask`의 `attribute_not_exists`) |
| `INTERNAL` | 500 | `toAppError`가 접은 나머지 전부 |

- ❌ **남의 아이템에 403을 준다** — 403은 존재를 누설한다. `FORBIDDEN`은 **역할 부족에만**
  쓰고, 소유자 조건에 걸리지 않은 아이템은 **없는 것**으로 취급한다.
- ❌ **`ConditionalCheckFailedException`을 한 코드로 접는다** — 같은 예외가 `putTask`에서는
  409이고 `updateTask`·`deleteTask`에서는 404다. **어느 조건식이 걸렸는지가 코드를 정한다**
  (`error-handling.md` 4절).
- ❌ **SDK 예외를 `instanceof`로 가른다** — v3는 `name`으로 가른다.
  `isConditionalCheckFailed`가 그 유일한 자리다.
- ❌ **핸들러가 상태 코드를 직접 고른다** — `respond`(이음매)와 `ERROR_STATUS`를 우회하면
  봉투가 둘이 된다.
- ❌ **예외를 그대로 응답에 싣는다** — SDK 메시지에 테이블명·키 구조가 들어 있다.
  `toAppError`로 먼저 정규화하고, 진단은 `logger`로만 남긴다. **powertools는 아무것도
  가리지 않으므로** 토큰·본문 전문을 로그에 넣지 않는다 (`handler-patterns.md` 7절).
<!-- /pack-slot -->

## 이음매가 채울 것

| 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| `api-endpoints` | 라우트↔함수 매핑과 응답 봉투. 봉투는 와이어 계약이 정한다 |
| `auth-boundaries` | Cognito 토큰 검증과 클레임 추출. 인증 방식은 프론트 축에 달렸다 |
| `complete-example` | IaC → 테이블 → 접근 패턴 → 쿼리 → 핸들러 → 테스트 관통 |
