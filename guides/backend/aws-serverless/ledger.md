<!-- epcc-pack-ledger: backend/aws-serverless v3.13.0 -->

# aws-serverless 팩 — 심볼 원장 (L0 선언본)

저작 전에 메인 세션이 선언한 계약이다. 클러스터를 갈라 병렬로 써도 중복 정의와 **시그니처
추측**이 생기지 않게 하는 유일한 장치다.

## provides — 이 팩이 정의한다

**「형태」 열은 의무다.** 소유 파일만 배정하고 형태를 비우면 형제 클러스터가 시그니처를
추측한다 — 실측(2026-08-23, node-api)에서 `getTask(ownerId, id)`를 다른 클러스터가
`getTask(id, ownerId)`로 불렀고 두 인자가 모두 `string`이라 TypeScript도 게이트도
잡지 못해 모든 단건 조회가 404가 됐다. 인자 **순서** · 반환 · 실패 시 던지는 것 ·
**호출자가 배선해야 하는 것**을 함께 적는다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `Task` | data-modeling.md | **`src/keys.ts`** — `{ pk: string; sk: string; id: string; title: string; status: 'open' \| 'done'; ownerId: string; createdAt: string; gsi1pk?: string; gsi1sk?: string }` — **키 속성이 아이템에 산다** (DynamoDB는 코드 생성이 없다) | 도메인 아이템 |
| `keys` | data-modeling.md | **`src/keys.ts`** — `keys.task(ownerId, id) => { pk, sk }` · `keys.taskList(ownerId) => { pk, skPrefix }` · `keys.taskGsi1(ownerId, status, id) => { gsi1pk, gsi1sk }` · `keys.statusList(ownerId, status) => { gsi1pk, gsi1skPrefix }` · `keys.newId() => string` — **전부 소유자가 먼저다.** `taskGsi1`은 3인자 중 둘이 `string`이니 순서가 생명이다. 키 조립은 여기 한 곳에서만 한다 | 키 조립 유틸 |
| `TABLE` | data-modeling.md | **`src/keys.ts`** — `const TABLE: string` — `env.TABLE_NAME`에서 온다 | 단일 테이블 이름 |
| `ddb` | data-access.md | **`src/db/client.ts`** — `DynamoDBDocumentClient` 싱글턴. **핸들러 밖(모듈 최상위)에서 만든다** — 콜드 스타트 밖 초기화 | 문서 클라이언트 |
| `listTasks` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, q: { limit: number; cursor?: string; status?: TaskStatus }) => Promise<{ items: Task[]; cursor?: string }>` — Query만 쓴다(Scan 금지) | 목록 |
| `getTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, id: string) => Promise<Task \| null>` — **소유자가 먼저다** | 단건 |
| `putTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, input: TaskCreate) => Promise<Task>` — **`input`의 `title`과 `status`를 모두 옮긴다.** `status`를 하드코딩하면 GSI 파티션까지 고정돼 그 값으로 만든 아이템이 목록에서 영영 사라진다(감사 A·C 실측). `ownerId`만 세션에서 온다. `ConditionExpression`으로 덮어쓰기 방지, 충돌은 `AppError('CONFLICT')` | 생성 |
| `updateTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, id: string, patch: TaskUpdate) => Promise<Task>` — 조건부 갱신. 조건 실패는 `AppError('NOT_FOUND')` | 수정 |
| `deleteTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, id: string) => Promise<void>` — 조건부 삭제. 조건 실패는 `AppError('NOT_FOUND')` | 삭제 |
| `encodeCursor` | data-access.md | **`src/db/tasks.ts`** — `(key: Record<string, unknown>) => string` — `LastEvaluatedKey`를 불투명 문자열로 | 커서 인코딩 |
| `decodeCursor` | data-access.md | **`src/db/tasks.ts`** — `(cursor: string) => Record<string, unknown>` — 실패는 `AppError('VALIDATION_FAILED')` | 커서 디코딩 |
| `EnvSchema` | input-validation.md | **`src/env.ts`** — `ZodObject` — `safeParse(process.env)`로 **모듈 최상위(콜드 스타트)**에 적용 | 환경변수 스키마 |
| `env` | input-validation.md | **`src/env.ts`** — `Env` — `TABLE_NAME` · `LOG_LEVEL` · `NODE_ENV` · `AWS_REGION` | 검증된 환경 값 |
| `TaskCreateSchema` | input-validation.md | **`src/schemas/task.ts`** — `z.strictObject` — 미지 키를 **거부**한다 | 생성 본문 |
| `TaskUpdateSchema` | input-validation.md | **`src/schemas/task.ts`** — 부분 업데이트. `.default()`를 겹치지 않는다 | 수정 본문 |
| `TaskQuerySchema` | input-validation.md | **`src/schemas/task.ts`** — `z.object` — 미지 키를 **제거**한다 | 목록 쿼리 |
| `parseBody` | input-validation.md | **`src/http/parse.ts`** — `<S extends z.ZodType>(schema: S, event: APIGatewayProxyEventV2) => z.output<S>` — 본문이 없거나 JSON이 아니면 `AppError('VALIDATION_FAILED')` | 본문 파싱 |
| `parseQuery` | input-validation.md | **`src/http/parse.ts`** — `<S extends z.ZodType>(schema: S, event: APIGatewayProxyEventV2) => z.output<S>` — `queryStringParameters`가 `null`일 수 있다 | 쿼리 파싱 |
| `pathParam` | input-validation.md | **`src/http/parse.ts`** — `(event: APIGatewayProxyEventV2, name: string) => string` — 없으면 `AppError('VALIDATION_FAILED')` | 경로 파라미터 |
| `Env` | input-validation.md | **`src/env.ts`** — `z.infer<typeof EnvSchema>` | |
| `TaskCreate` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskCreateSchema>` | |
| `TaskUpdate` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskUpdateSchema>` | |
| `TaskQuery` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskQuerySchema>` | |
| `TaskStatusSchema` | input-validation.md | **`src/schemas/task.ts`** — `z.enum(['open', 'done'])` — `TaskStatus`가 여기서 파생되고 두 요청 스키마가 이것을 재사용한다 | 상태 열거 |
| `TaskStatus` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskStatusSchema>` = `'open' \| 'done'` | |
| `ERROR_STATUS` | error-handling.md | **`src/http/errors.ts`** — `Record<string, number>` — 도메인 코드 → HTTP 상태. **유일한 매핑표** | 상태 매핑 |
| `toAppError` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => AppError` — 응답 어댑터가 **반드시 먼저 호출한다** | 정규화 |
| `isConditionalCheckFailed` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => boolean` — `ConditionalCheckFailedException` **그리고** `TransactionCanceledException`의 `CancellationReasons[i].Code === 'ConditionalCheckFailed'`. 이름만 보면 트랜잭션 안의 조건 실패를 놓쳐 500이 된다 (C1 실측) | 조건 실패 판별 |
| `isThroughputExceeded` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => boolean` — `ProvisionedThroughputExceededException` · `RequestLimitExceeded` · **`ThrottlingException`**(온디맨드 테이블이 쓰는 이름) · `$metadata.httpStatusCode === 429`. 근거는 SDK 자신의 `THROTTLING_ERROR_CODES` (C1 실측) | 스로틀 판별 |
| `isInvalidRequest` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => boolean` — `ValidationException`. 요청이 DynamoDB의 문법·제약과 맞지 않을 때 온다. **`toAppError`가 400으로 접는다** — 매핑이 없으면 커서를 다른 인덱스에 재사용하는 평범한 오용이 5xx가 된다 (감사 A 실측) | 요청 형식 오류 판별 |
| `fieldErrors` | error-handling.md | **`src/http/errors.ts`** — `(e: ZodError) => Record<string, string[]>` | 필드 오류 |
| `logger` | handler-patterns.md | **`src/obs/logger.ts`** — `Logger` (powertools). **모듈 최상위에서 만든다** — 요청 스코프 값은 `addContext`로 붙인다 | 구조적 로거 |
| `ApiHandler` | handler-patterns.md | `(e: APIGatewayProxyEventV2, c: Context) => Promise<APIGatewayProxyResultV2>` — **`@types/aws-lambda`의 `Handler`를 쓰지 않는다.** `Handler`의 반환이 `void \| Promise<T>`라 `await h(...)`가 TS2322다 (tsc 5.9.3 재현). 좁힌 형태는 `Handler`에 대입 가능하다 | 핸들러 타입 별칭 |
| `withContext` | handler-patterns.md | **`src/obs/logger.ts`** — `(h: ApiHandler) => ApiHandler` — 요청 ID·콜드 스타트를 로거에 붙이고 미처리 예외를 로깅한 뒤 **다시 던진다**. **핸들러를 감싸 export한다.** 봉투로 바꾸는 것은 핸들러 안의 `try/catch` + `respond.fail`이지 이 래퍼가 아니다 | 핸들러 래퍼 |
| `isColdStart` | handler-patterns.md | **`src/obs/logger.ts`** — `() => boolean` — 첫 호출에서만 `true`. 모듈 최상위 플래그를 읽는다 | 콜드 스타트 판별 |
| `TaskTable` | deploy-and-iam.md | **`infra/table.ts`** — CDK `Construct` 서브클래스. `new TaskTable(scope, id)` — 단일 테이블 + GSI1을 만든다 | 테이블 스택 |
| `grantTaskAccess` | deploy-and-iam.md | **`infra/table.ts`** — `(fn: NodejsFunction, table: TaskTable, mode: 'read' \| 'write' \| 'batch') => void` — **함수별 최소 권한.** 테이블 전체 권한을 주지 않는다. `'batch'`는 `BatchGetItem`·`BatchWriteItem`·`TransactWriteItems`·`ConditionCheckItem`을 더한다 — **배치·트랜잭션을 실제로 부르는 함수에만** 준다(감사 A: 두 모드만으로는 팩이 가르치는 배치 패턴이 런타임 AccessDenied가 된다) | IAM 부여 |
| `invokeHandler` | testing.md | **`test/invoke.ts`** — `(h: ApiHandler, event: Partial<APIGatewayProxyEventV2>) => Promise<APIGatewayProxyResultV2>` — 테스트에서 핸들러를 직접 태운다. **이벤트는 얕게 병합된다** — `authFor`가 `requestContext`를 주면 기본 `requestContext`를 통째로 덮으므로 `requestId`·`http`까지 담아 돌려줘야 한다 | 테스트 하네스 |

## requires — 이음매가 제공해야 한다

`프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 import 문에 이름이 등장하는지로
판정한다. **팩이 호출하는 심볼에는 호출 시그니처를 적는다** — 적지 않으면 이음매가
인자 순서를 추측한다(게이트가 FAIL로 막는다).

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `AppError` | 프로젝트 | `new AppError(code: string, message: string, details?: Record<string, string[]>)` — **뒤 두 인자가 모두 `string`이니 순서가 생명이다.** 코드표에 반드시 포함: `VALIDATION_FAILED` · **`UNAUTHENTICATED`**(`requireAuth`가 던진다 — 빠지면 401이 500으로 나간다) · `NOT_FOUND` · `CONFLICT` · `FORBIDDEN` · `THROTTLED` · `INTERNAL`. `src/http/app-error.ts`에 둔다 | 에러 코드표와 필드 오류 형태가 와이어 계약의 함수 |
| `respond` | 프로젝트 | `respond(result: unknown, init?: { status?: number }) => APIGatewayProxyResultV2` · `respond.fail(e: unknown) => APIGatewayProxyResultV2` — **`toAppError`로 먼저 정규화하고 `ERROR_STATUS`로 상태를 정한다.** `src/http/respond.ts`에 둔다 | 응답 봉투가 와이어 계약의 함수 |
| `requireAuth` | 프로젝트 | `requireAuth(event: APIGatewayProxyEventV2) => AuthUser` — 동기. 실패는 `AppError('UNAUTHENTICATED')`. `src/http/require-auth.ts`에 둔다. **미들웨어가 아니라 핸들러 첫 줄에서 부르는 함수다** (Lambda에는 미들웨어 체인이 없다) | 토큰 검증 방식이 조합의 함수 |
| `AuthUser` | 프로젝트 | 최소 `{ id: string; roles: string[] }` — Cognito 클레임에서 뽑는다 | 위와 같다 |
| `authFor` | 프로젝트 | `authFor(ownerId: string, roles?: string[]) => Partial<APIGatewayProxyEventV2>` — 테스트가 `invokeHandler`에 넘길 이벤트 조각(권한 부여자 클레임)을 만든다. **동기** | 클레임 형태가 인증 방식의 함수 |
| `routes` | 프로젝트 | CDK에서 API Gateway 라우트를 함수에 매핑하는 선언. `routes(scope, { table })` 형태를 가정한다 | 라우트↔함수 매핑이 조합의 함수 |

## 알려진 공백

없다. 축-지역 필수 슬롯 6개가 모두 채워지고, 비어 보이는 것(API 엔드포인트 · 인증 경계 ·
완전 예제)은 `pack.json`의 `seamSlots`가 선언한 이음매의 몫이다.

## 예제에 등장하는 앱 심볼 (프로젝트가 만든다)

`provides`도 `requires`도 아니다. 예제에서 이름만 등장하므로 조립 후에도 정의가 없는 것이 정상이다.

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `TaskService` | handler-patterns.md (계층 예시) | 서비스 계층 예시 |

## 게이트 REVIEW의 정당화 (침묵 통과 금지)

| REVIEW | 판정 |
| --- | --- |
| `grantTaskAccess`·`invokeHandler` 호출 형태 혼재 | **오탐.** 둘 다 여러 줄 호출이라 게이트의 한 줄 스캔이 인자 없는 호출로 읽는다. 실제 호출은 각각 3인자·2인자로 원장 형태와 일치한다 |
| `TaskQuery` 단회 등장 | **정상.** 이음매의 핸들러가 `parseQuery(TaskQuerySchema, event)`의 반환을 타이핑할 때 쓴다 — 팩 안에 소비처가 없는 것이 맞다 (`TaskCreate`·`TaskUpdate`도 같다) |
| `usersTable` | deploy-and-iam.md (최소 권한 대조 예시) | 다른 도메인 테이블 |
