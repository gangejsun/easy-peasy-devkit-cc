<!-- epcc-pack-ledger: backend/aws-container v3.12.0 -->

# aws-container 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 **이음매가 새로 정의하면
중복**이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 **이음매가 반드시 제공해야**
한다. 라이브러리 API는 대상이 아니다 — 프로젝트 로컬 심볼만 싣는다.

## provides — 이 팩이 정의한다

**「형태」 열은 병렬 저작이 시그니처를 추측하지 않게 한다.** 소유 파일만 적어 두면 형제
클러스터는 그 파일을 열 수 없으므로 호출 형태를 지어낸다 — 2026-08-23 실측(node-api)에서
`getTask(ownerId, id)`를 다른 클러스터가 `getTask(id, ownerId)`로 불렀고 **두 인자가 모두
`string`이라 TypeScript도 게이트도 잡지 못해** 단건 조회가 전부 404가 됐다. 같은 실측에서
`shutdown(server)`를 「시그널을 거는 함수」로 오해해 부팅 톱레벨에서 부르는 예제가 나왔고
서버가 800ms 만에 죽었다. 그래서 이 표에는 **인자 이름과 순서 · 반환 · 실패 시 던지는 것 ·
호출자가 배선할 의무**를 적는다. 이 팩은 특히 위험하다: `dataLayerPolicyEngine: false`라
애플리케이션 층의 소유권 필터가 유일한 경계인데 소유권 쿼리 5개가 전부 **`ownerId`를 첫
인자로** 받고 두 번째 인자도 `string`이다. 게이트는 형태가 `이름(...)`으로 시작하면 실제
정의의 인자 개수와 대조한다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `pool` · `db` | data-access.md | `pool: Pool`(pg) · `db = drizzle(pool, { schema })` — 둘 다 `src/db/client.ts`의 **모듈 스코프 싱글턴**이고 이 저장소의 유일 인스턴스다. 요청마다 새로 만들지 않는다. 종료 시 `await pool.end()`를 SIGTERM 핸들러 **안에서** 부른다 | pg Pool + Drizzle 인스턴스 (싱글턴) |
| `tasks` · `tags` | data-access.md | `tasks = pgTable('tasks', { id uuid PK · ownerId text · title text · body text(기본 `''`) · archivedAt timestamptz(null = 활성) · createdAt · updatedAt })` + `tasks_owner_created_idx(ownerId, createdAt, id)` · unique `tasks_owner_title_key(ownerId, title)` · `tags = pgTable('tags', { id uuid PK · ownerId text · taskId uuid → tasks.id cascade · name text })` + `tags_owner_task_idx` · unique `tags_task_name_key(taskId, name)`. **자식 테이블도 `ownerId`를 직접 들고 있다** | Drizzle 테이블 정의 (마이그레이션의 원본) |
| `Task` · `NewTask` | data-access.md | `type Task = typeof tasks.$inferSelect` → `{ id: string; ownerId: string; title: string; body: string; archivedAt: Date \| null; createdAt: Date; updatedAt: Date }` · `type NewTask = typeof tasks.$inferInsert` → 같은 필드에서 `ownerId`·`title`만 필수이고 `id`·`body`·`archivedAt`·`createdAt`·`updatedAt`은 선택(DB 기본값). 행 타입을 손으로 다시 쓰지 않는다 | 테이블에서 추론한 도메인 타입 |
| `findOwnedTask` | data-access.md | `findOwnedTask(ownerId: string, id: string): Promise<Task \| null>` — **소유자가 첫 인자**다 (두 인자 모두 `string`이라 뒤바꿔도 컴파일된다). 0행이면 **던지지 않고 `null`을 반환**한다 — 404 변환은 호출자(서비스·핸들러 층)의 몫 | 소유권 필터 조회 |
| `listOwnedTasks` | data-access.md | `listOwnedTasks(ownerId: string, limit: number, cursor?: { createdAt: Date; id: string }, archived?: boolean): Promise<Task[]>` — 소유자가 첫 인자. **`limit + 1`행까지 반환**한다(다음 페이지 유무 판단용 — 호출자가 잘라 쓴다). `archived` 미지정 = 활성 행만, `true` = 보관 행만. 0행은 빈 배열이며 예외가 아니다 | 커서 목록 조회 |
| `updateOwnedTask` | data-access.md | `updateOwnedTask(ownerId: string, id: string, patch: UpdateTaskInput): Promise<Task \| null>` — 소유자가 첫 인자, `id`가 둘째(둘 다 `string`). `patch`는 파싱된 요청 타입만 받는다 — `Partial<NewTask>`를 넘기면 `ownerId`가 `set`에 실려 **행이 타인에게 넘어간다**. 0행이면 **던지지 않고 `null`** | 영향 행 확인 변이 |
| `deleteOwnedTask` | data-access.md | `deleteOwnedTask(ownerId: string, id: string): Promise<number>` — 소유자가 첫 인자. **반환이 행이 아니라 삭제된 행 수**다. `0`이 정상 반환값이고 그때 호출자가 404를 만든다 — 반환을 버리면 남의 `id`에도 204가 나간다 | 영향 행 확인 변이 |
| `replaceTaskTags` | data-access.md | `replaceTaskTags(ownerId: string, taskId: string, names: string[]): Promise<(typeof tags.$inferSelect)[] \| null>` — 소유자가 첫 인자. `db.transaction` 하나로 소유권 확인 → 기존 태그 삭제 → 재삽입을 끝낸다. 반환 3분기: 소유 아님·부재 → `null`, `names`가 빈 배열 → `[]`, 그 외 → 삽입된 `tags` 행 배열. `tx`를 콜백 밖으로 넘기지 않는다 | 트랜잭션 변이 |
| `env` · `publicEnvKeys` | input-validation.md | `env: z.infer<typeof EnvSchema>` — 검증된 `process.env`(공개 17키 + 비밀 2키). **모듈 로드 시점에 검증하고 실패하면 `process.exit(1)`** 이라 import만으로 프로세스가 죽을 수 있다(테스트는 `testEnv`를 먼저 채운다) · `publicEnvKeys: string[]` = `Object.keys(PublicEnv.shape)` — 로그 화이트리스트 기준이며 `DATABASE_URL`·`AUTH_STATE_SECRET`은 들어 있지 않다 | 검증된 환경변수 단일 진입점 |
| `CreateTaskInput` · `UpdateTaskInput` | input-validation.md | `CreateTaskInput` = `TaskFields.extend({ body: … .default('') })` → 파싱 결과 `{ title: string; body: string }`(`body` 미지정 시 `''`) · `UpdateTaskInput` = `TaskFields.partial().refine(키 1개 이상)` → `{ title?: string; body?: string }`이고 **빈 객체는 거절**된다. 둘 다 `strictObject` 계열이라 미지 키를 거절하고, **값과 동명 타입을 함께 export**하므로 타입 자리에 `CreateTaskInput`을 그대로 쓴다 | 요청 DTO |
| `ListTasksQuery` · `TaskIdParam` | input-validation.md | `ListTasksQuery` → 파싱 후 `{ limit: number(1~100, 기본 20); cursor?: string(≤200, base64url `"<iso>\|<uuid>"`); archived?: boolean }` — 쿼리 문자열이 원본이라 `coerce`·`stringbool`을 거친 **변환 후** 타입이다(`z.input`이 아니다) · `TaskIdParam` → `{ id: string }`(uuid 검증). 둘 다 값과 동명 타입을 함께 export한다 | 쿼리·경로 DTO |
| `jsonBody` | input-validation.md | `jsonBody<T extends ZodType>(c: Context, schema: T): Promise<z.infer<T>>` — 인자 순서는 (컨텍스트, 스키마)이고 **`async`라 `await` 필수**다. 실패는 반환값이 아니라 throw: 본문이 JSON이 아니면 `AppError(400, 'BAD_REQUEST')`, 스키마 위반이면 `AppError(422, 'VALIDATION_FAILED')` + `fieldErrors` | 파싱 헬퍼 |
| `queryParams` | input-validation.md | `queryParams<T extends ZodType>(c: Context, schema: T): z.infer<T>` — **동기다**(`await`를 붙이지 않는다). `c.req.query()`를 파싱한다. 위반 시 `AppError(422, 'VALIDATION_FAILED')`를 던진다 | 파싱 헬퍼 |
| `pathParam` | input-validation.md | `pathParam<T extends ZodType>(c: Context, schema: T): z.infer<T>` — **동기다**. `c.req.param()`을 파싱한다. 위반 시 `AppError(422, 'VALIDATION_FAILED')`를 던진다 | 파싱 헬퍼 |
| `ObjectStorage` | portability-boundaries.md | **`src/storage/index.ts`** — `interface ObjectStorage { put(key: string, body: Uint8Array, contentType: string): Promise<void>; presignGet(key: string, expiresInSec: number): Promise<string> }` — `expiresInSec`는 **초** 단위다. 앱 코드가 import하는 유일한 저장소 타입이고 AWS SDK를 아는 것은 구현(`src/storage/s3.ts`)뿐. 저장 키는 서버가 만든다(`tasks/<ownerId>/<uuid>`) | 저장소 포트 (앱이 보는 유일한 타입) |
| `s3Storage` | portability-boundaries.md | **`src/storage/s3.ts`** — `ObjectStorage` 구현. `env.S3_BUCKET`·`S3_ENDPOINT`를 읽고 **`presignGet`의 `expiresInSec`는 초**다. 앱 코드는 이 심볼이 아니라 `ObjectStorage` 타입에 의존한다 — 배선(어느 구현을 쓸지)은 조립 지점이 정한다 | S3 어댑터 |
| `log` | portability-boundaries.md | `log.info(fields: Record<string, unknown>): void` — `debug`·`info`·`warn`·`error` 네 메서드가 같은 시그니처다. **인자는 문자열이 아니라 객체**이고 메시지는 `msg` 필드에 넣는다(`log.info({ msg: 'listening', port })`). `env.LOG_LEVEL` 미만은 방출되지 않는다. 토큰·`DATABASE_URL`·PII·객체 스프레드(`{ ...user }`)를 넣지 않는다 | 구조화 로깅 |
| `logBootConfig` | portability-boundaries.md | `logBootConfig(): void` — 인자 없음. **호출자가 배선한다**: `src/index.ts`에서 `serve()` 직후 **1회만** 부른다. `publicEnvKeys`에 있는 키만 찍으므로 비밀은 구조적으로 오를 수 없다 | 구조화 로깅 |
| `requestContext` | portability-boundaries.md | `requestContext = createMiddleware<AppEnv>(async (c, next) => …)` — **직접 호출하는 함수가 아니라 배선하는 Hono 미들웨어**다: 라우트 등록보다 **먼저** `app.use(requestContext)`. `c.set('requestId', …)`와 응답 헤더 `x-request-id`를 세우고 `await next()` 뒤에 접근 로그 한 줄을 낸다. 들어온 `x-request-id`는 `/^[\w-]{1,64}$/`를 통과할 때만 재사용한다 | 구조화 로깅 |
| `testEnv` | testing.md | `testEnv: Record<string, string>` — **값이 전부 문자열인 상수 객체**다(변환은 env 스키마가 한다). 두 vitest 설정이 `test: { env: testEnv }`로 공유한다. `globalSetup`은 워커 밖에서 돌므로 통합 설정 파일 최상단에 `Object.assign(process.env, testEnv)`를 **추가로** 써야 한다 — 빠뜨리면 `@/config/env`가 `exit(1)`로 Vitest를 메시지 없이 끝낸다. `OIDC_ISSUER`·`OIDC_AUDIENCE`는 테스트 토큰의 `iss`·`client_id`와 같아야 한다 | 테스트 환경변수 픽스처 |

## requires — 이음매가 제공해야 한다

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 이음매가
고른 패키지에서 오므로 import 문에 이름이 등장하는지로 판정한다. 이 팩의 requires는
전부 프로젝트 심볼이다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `app` | 프로젝트 | Hono 앱 인스턴스 (서브 앱 마운트 지점) | 라우트 조립 순서가 조합의 함수 |
| `AppEnv` | 프로젝트 | `c.get`/`c.set` 타입 바인딩 | 컨텍스트에 싣는 것이 인증 방식에 달렸다 |
| `AppError` | 프로젝트 | `new AppError(status: number, code: string, message: string, details?: Record<string, string[]>)` — **인자 순서는 (숫자 `status`, 문자열 `code`, 문자열 `message`)**이고 **뒤 두 인자가 모두 `string`이라 뒤바꿔도 컴파일된다** — 뒤바뀌면 와이어 코드 자리에 한국어 문장이 실려 나간다. `code`는 클라이언트가 분기하는 상수(팩이 쓰는 값: `BAD_REQUEST`·`VALIDATION_FAILED`·`NOT_FOUND`·`FORBIDDEN`), `message`는 사람용 문장이다. 넷째 `details`는 선택이며 팩은 `z.flattenError(err).fieldErrors`를 싣는다. 필드 `status`·`code`·`message`·`details`를 그대로 노출해 `onError`가 봉투로 옮긴다. `@/http/errors`에서 export한다 | 에러 코드표가 와이어 계약의 함수 |
| `onError` | 프로젝트 | 전역 에러 → 봉투 매핑 | 응답 봉투가 와이어 계약의 함수 |
| `requireAuth` | 프로젝트 | 인증 미들웨어 | 토큰 검증 방식이 백엔드 인증 차원의 함수 |
| `AuthUser` | 프로젝트 | 검증된 주체(`sub` 등) | 위와 같다 |
| `safeReturnPath` | 프로젝트 | `safeReturnPath(input: string): string` — 인자 1개, **동기이고 던지지 않는다**. 거절은 예외가 아니라 **fallback `'/'` 반환**이므로 반환값을 반드시 리다이렉트에 쓴다(원본 입력을 쓰면 차단이 무효다). 차단하고 `'/'`로 바꾸는 것: 스킴 상대 `//evil.com` · 역슬래시 `/\evil.com`(브라우저가 `/`로 취급) · 절대 URL `https://evil.com` · `javascript:` 등 스킴 붙은 값 · 경로 탈출 `/..//evil.com` · 제어문자 삽입 `/tasks\n/x`. 통과시키는 것: `/` 한 개로 시작하는 내부 경로와 그 쿼리(`/tasks/42?tab=1` → 원문 그대로). `@/http/return-path`에서 export한다 | 로그인 흐름이 프론트엔드 축과의 계약 |
| `isUniqueViolation` | 프로젝트 | SQLSTATE → 도메인 에러 판별 | 409 매핑이 와이어 계약의 함수 |
| `insertTask` | 프로젝트 | `insertTask(ownerId: string, input: CreateTaskInput): Promise<Task>` — **소유자가 첫 인자**다. 이 팩 쿼리 층의 규약이며 `provides`의 형제 5종(`findOwnedTask(ownerId, id)`·`listOwnedTasks(ownerId, limit, …)`·`updateOwnedTask(ownerId, id, patch)`·`deleteOwnedTask(ownerId, id)`·`replaceTaskTags(ownerId, taskId, names)`)이 전부 같은 순서다 — **둘째 인자 이름만 `id`/`taskId`로 갈릴 뿐 첫 인자가 소유자라는 것은 예외가 없다.** 둘째 인자는 id가 아니라 **파싱된 `CreateTaskInput`**(`{ title, body }`)이고 `ownerId`를 그 객체에 넣지 않는다 — 넣으면 클라이언트가 소유자를 정한다. 삽입된 행 하나를 반환하며(`row.id` 사용) 형제와 달리 **`null`을 반환하지 않는다**. 제목 중복은 삼키지 않고 **SQLSTATE `23505`를 그대로 던진다** — 409 변환은 `isUniqueViolation`을 쓰는 호출자 몫이다. 형제 쿼리와 같은 모듈 `@/db/queries/tasks`에서 export한다 | **비대칭**: 조회·수정·삭제 쿼리는 팩이 소유하는데 생성만 이음매(완전 예제)에 있다. 원본 `react-aws-backend-guide`에서 승계한 구조이며 이번 재배치가 만든 것이 아니다 |

## 알려진 공백 (추출 시점에 승계, 수리하지 않음)

| 항목 | 상태 |
| --- | --- |
| `insertTask`의 소재 | `data-access.md`가 CRUD 중 C만 빠뜨렸다. 팩으로 옮기는 것이 옳으나 본문 개선은 이번 범위 밖이다 — 지금은 `requires`로 선언해 조립 후 미정의가 되지 않게 한다 |
| 이음매 완전 예제의 재정의 | `complete-example.md`가 `tasks`·`Task`·`findOwnedTask` 등을 **같은 파일 경로·같은 시그니처로** 다시 보여준다. 자기완결 관통 예제라는 의도이며 시그니처가 같으므로 중복 정의 FAIL은 아니다. 게이트는 원장의 소비처로 인정한다 |
