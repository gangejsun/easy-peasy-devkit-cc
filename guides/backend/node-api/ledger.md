<!-- epcc-pack-ledger: backend/node-api v3.13.0 -->

# node-api 팩 — 심볼 원장 (L0 선언본)

**저작 전에 메인 세션이 선언한 계약이다.** `provides`의 정의 파일 배정은 **소유 배정**이고,
클러스터를 갈라 병렬로 써도 중복 정의가 생기지 않게 하는 유일한 장치다. L1은 자기
클러스터에 배정된 심볼만 정의하고, 벗어나면 게이트의 `--pack`이 팬인에서 잡는다.

`requires`는 이 팩이 소비하지만 정의하지 않는다 — **이음매가 제공해야** 한다.
라이브러리 API는 원장 대상이 아니다.

## provides — 이 팩이 정의한다

`export` 선언문이 있는 심볼만 싣는다.

**「형태」 열은 의무다.** 소유 파일만 배정하고 형태를 비우면 병렬 저작에서 형제 클러스터가
시그니처를 **추측한다** — 실측(2026-08-23)에서 `getTask(ownerId, id)`를 다른 클러스터가
`getTask(id, ownerId)`로 불렀고, 두 인자가 모두 `string`이라 **TypeScript가 잡지 못해**
모든 단건 조회가 404가 됐다. `requires` 표에는 이 열이 처음부터 있었는데 `provides`에는
없었던 것이 원인이다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `makeApp` | project-structure.md | **`src/app.ts`** — `() => Express` — `listen`하지 않는다 | Express 5 앱 조립 (라우터 마운트 · 미들웨어 순서) |
| `notFound` | project-structure.md | **`src/app.ts`** — `RequestHandler` (3인자) — 에러 미들웨어 **앞**에 마운트 | 404 미들웨어 — 에러 미들웨어 **앞**에 둔다 |
| `prisma` | data-access.md | **`src/db/client.ts`** — `PrismaClient` 싱글턴 | PrismaClient 싱글턴 (이 팩에서 유일한 인스턴스) |
| `listTasks` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, q: { limit: number; cursor?: string; status?: TaskStatus }) => Promise<TaskView[]>` | 목록 조회 (소유권 필터 + 커서 페이지네이션) |
| `getTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, id: string) => Promise<TaskView \| null>` — **소유자가 먼저다** | 단건 조회 (소유권 필터 포함) |
| `insertTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, input: TaskCreate) => Promise<TaskView>` | 생성 |
| `updateTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, id: string, patch: TaskUpdate) => Promise<TaskView>` — 0행이면 `AppError('NOT_FOUND')` | 수정 — **영향 행 수를 확인한다** |
| `deleteTask` | data-access.md | **`src/db/tasks.ts`** — `(ownerId: string, id: string) => Promise<void>` — 0행이면 `AppError('NOT_FOUND')` | 삭제 — **영향 행 수를 확인한다** |
| `TaskView` | data-access.md | **`src/db/tasks.ts`** — `Prisma.TaskGetPayload<{ select: typeof fields }>` — `ownerId`를 담지 않는다 | 쿼리 5개의 반환 타입(`select`로 좁힌 형태). **이음매의 `tasksRouter`가 핸들러를 타이핑하려면 이름이 있어야 한다** — 익명이면 소비자가 `Awaited<ReturnType<typeof getTask>>`를 써야 한다 |
| `EnvSchema` | input-validation.md | **`src/env.ts`** — `ZodObject` — `safeParse(process.env)`로 부팅 시점에 적용 | 환경변수 스키마 |
| `env` | input-validation.md | **`src/env.ts`** — `Env` (검증된 값). `PORT`·`LOG_LEVEL`·`NODE_ENV`·`DATABASE_URL`·`DRAIN_DELAY_MS`·`SHUTDOWN_TIMEOUT_MS` | 검증된 환경 값 — `process.env`를 읽는 유일한 자리 |
| `TaskCreateSchema` | input-validation.md | **`src/schemas/task.ts`** — `z.strictObject` — 미지 키를 **거부**한다 | 생성 요청 본문 |
| `TaskUpdateSchema` | input-validation.md | **`src/schemas/task.ts`** — 부분 업데이트. `.default()`를 겹치지 않는다 | 수정 요청 본문 (부분 업데이트) |
| `TaskQuerySchema` | input-validation.md | **`src/schemas/task.ts`** — `z.object` — 미지 키를 **제거**한다 (쿼리는 거부하지 않는다) | 목록 쿼리 문자열 |
| `Env` | input-validation.md | **`src/env.ts`** — `z.infer<typeof EnvSchema>` | `z.infer<typeof EnvSchema>` |
| `TaskCreate` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskCreateSchema>` | 생성 본문 타입 — **이음매의 `tasksRouter`가 핸들러를 타이핑한다** |
| `TaskUpdate` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskUpdateSchema>` | 수정 본문 타입 |
| `TaskQuery` | input-validation.md | **`src/schemas/task.ts`** — `z.output<typeof TaskQuerySchema>` | 목록 쿼리 타입 |
| `parseBody` | input-validation.md | **`src/http/parse.ts`** — `<S>(schema: S, req: Request) => z.output<S>` — 실패는 `AppError('VALIDATION_FAILED', …, fieldErrors)` | 요청 본문 파싱 헬퍼 — 실패를 `AppError`로 정규화 |
| `parseQuery` | input-validation.md | **`src/http/parse.ts`** — `<S>(schema: S, req: Request) => z.output<S>` — **반환값을 쓴다**. `req.query`에 대입하지 않는다 | 쿼리 문자열 파싱 헬퍼 |
| `ERROR_STATUS` | error-handling.md | **`src/http/errors.ts`** — `Record<string, number>` — 도메인 코드 → HTTP 상태. **유일한 매핑표** | 도메인 에러 코드 → HTTP 상태 표 |
| `toAppError` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => AppError` — `errorHandler`가 **반드시 먼저 호출한다** | 알 수 없는 throw → `AppError` 정규화 |
| `isUniqueViolation` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => boolean` — Prisma `P2002` | Prisma `P2002` 판별 |
| `isRecordNotFound` | error-handling.md | **`src/http/errors.ts`** — `(e: unknown) => boolean` — Prisma `P2025` | Prisma `P2025` 판별 |
| `fieldErrors` | error-handling.md | **`src/http/errors.ts`** — `(e: ZodError) => Record<string, string[]>` | `ZodError` → `Record<string, string[]>` |
| `testDb` | testing.md | **`src/test/db.ts`** — `PrismaClient` — 워커별 스키마로 격리 | 테스트 DB 연결 (스키마별 격리) |
| `resetDb` | testing.md | **`src/test/db.ts`** — `() => Promise<void>` — 테스트 간 정리 | 테스트 간 정리 |
| `seedTask` | testing.md | **`src/test/db.ts`** — `(ownerId: string, patch?: Partial<Task>) => Promise<Task>` | 픽스처 생성 |
| `shutdown` | operations.md | **`src/ops/shutdown.ts`** — `(server: Server) => Promise<void>` — **배수를 수행한다**. 시그널 배선이 아니다 (`process.on('SIGTERM', () => void shutdown(server))`) | SIGTERM 처리 — 연결 배수 후 종료 |
| `healthz` | operations.md | **`src/ops/health.ts`** — `RequestHandler` — liveness. 의존성을 보지 않는다 | liveness |
| `readyz` | operations.md | **`src/ops/health.ts`** — `RequestHandler` — readiness. 배수 중이면 503 | readiness — 의존성 확인 뒤 준비 완료 |
| `logger` | operations.md | **`src/ops/logger.ts`** — `pino.Logger` — 요청 스코프는 `req.log`를 쓴다 | 구조적 로거 (pino) |
| `beginDrain` | operations.md | **`src/ops/health.ts`** — `() => void` — `readyz`를 503으로 내린다 | 배수 시작 플래그. **`shutdown`(쓰는 쪽)과 `readyz`(읽는 쪽)가 모듈이 갈려 진입점이 필요하다** — 없애면 배수 중에도 `readyz`가 200을 돌려줘 liveness ≠ readiness가 무너진다 (C3 검토) |

## requires — 이음매가 제공해야 한다

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 이음매가 고른
패키지에서 오므로 import 문에 이름이 등장하는지로 판정한다. `생성물`은 도구가 만들므로
검사하지 않는다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `Task` | 생성물 | `prisma generate`가 `@prisma/client`에 만든다. `id` · `title` · `status: 'open' \| 'done'` · `ownerId` · `createdAt` | 스키마 파일에서 도구가 만든다 — 팩도 이음매도 손으로 쓰지 않는다 |
| `AppError` | 프로젝트 | `src/http/app-error.ts`에 둔다. `new AppError(code, message, details?)` · 필드 `code: string` · `details?: Record<string, string[]>`. **코드표에 반드시 포함할 것**: `VALIDATION_FAILED`(`parseBody`가 던진다) · `NOT_FOUND` · `CONFLICT`(`isUniqueViolation`) · `FORBIDDEN` · `INTERNAL`. 빠지면 `ERROR_STATUS`가 조용히 500으로 떨어진다 | 에러 코드표와 필드 오류 형태가 와이어 계약의 함수 |
| `errorHandler` | 프로젝트 | `src/http/error-handler.ts`에 둔다. Express 5 에러 미들웨어 `(err, req, res, next)` — `ERROR_STATUS`로 상태를 정하고 **봉투를 방출한다**. `makeApp`이 마지막에 마운트한다 | 응답 봉투 형태가 와이어 계약의 함수 |
| `requireAuth` | 프로젝트 | `src/http/require-auth.ts`에 둔다. `RequestHandler` — 검증된 주체를 `req.user`에 싣는다. 실패는 `AppError('UNAUTHENTICATED')` | **토큰 검증 방식이 조합의 함수다** — 프론트 축에 서버 런타임이 있으면 세션 쿠키, SPA면 베어러 토큰이 된다 |
| `AuthUser` | 프로젝트 | 최소 `{ id: string }`. `Express.Request['user']`에 선언 병합으로 붙인다 | 위와 같다 |
| `authFor` | 프로젝트 | `authFor(ownerId: string) => Record<string, string>` — supertest `.set()`에 넘길 인증 헤더 객체를 만든다. **테스트 전용**이고 앱 코드가 부르지 않는다 | 헤더냐 쿠키냐가 `auth-boundaries`의 함수다. 산문으로만 있으면 조립 후 게이트가 잡지 못한다 (감사 C) |
| `tasksRouter` | 프로젝트 | `express.Router()` — 이 팩의 쿼리·스키마를 소비해 엔드포인트와 봉투를 만든다. `makeApp`이 `/api/tasks`에 마운트한다 | 핸들러 형태와 봉투가 조합의 함수 (`seamSlots`의 `api-endpoints`) |

## 알려진 공백

없다. 축-지역 필수 슬롯 6개가 모두 채워지고, 비어 보이는 것(API 엔드포인트 · 인증 경계 ·
완전 예제)은 공백이 아니라 `pack.json`의 `seamSlots`가 선언한 **이음매의 몫**이다.

## 예제에 등장하는 앱 심볼 (프로젝트가 만든다)

`provides`도 `requires`도 아니다 — 팩이 정의하지 않고 이음매가 줄 것도 아니며, 소비자
프로젝트가 자기 도메인으로 작성한다. 예제에서 이름만 등장하므로 조립 후에도 정의가 없는
것이 정상이다.

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `usersRouter` | project-structure.md (마운트 예시) | 다른 도메인 라우터 |
| `TaskService` | project-structure.md (계층 예시) | 서비스 계층 예시 |
| `archiveTask` | data-access.md §7 (트랜잭션 경계 예제) | 서비스 계층 예시. `src/services/task-service.ts`에 있고 팩 안에 소비처가 없다 — **이음매의 `complete-example`이 소비한다.** 게이트는 이것을 유령 정의 REVIEW로 보고하며, 그 정당화가 이 행이다 |
