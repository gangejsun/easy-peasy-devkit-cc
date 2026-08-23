<!-- epcc-seam: react-vite+aws-container/backend v3.12.0 -->
# API 엔드포인트와 에러 처리

Hono 4 라우트의 표준 형태, 요청/응답 계약, 상태 코드 매핑, 전역 에러 처리를 다룬다.
클라이언트는 React SPA 하나뿐이므로 **모든 응답은 JSON**이다 — 페이지 리다이렉트는 없다.

## 앱 조립 (`src/app.ts`)

미들웨어 등록 순서가 곧 실행 순서다. 헬스체크는 인증보다 **앞에** 둔다.

```ts
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { bodyLimit } from 'hono/body-limit'
import { sql } from 'drizzle-orm'
import { env } from '@/config/env'
import { db } from '@/db/client'
import { AppError, onError, notFound } from '@/http/errors'
import { requestContext } from '@/http/logger'
import { requireAuth } from '@/http/auth'
import type { AppEnv } from '@/http/types'
import { authRoutes } from '@/routes/auth'
import { tasksRoutes } from '@/routes/tasks'

export const app = new Hono<AppEnv>()

app.use('*', requestContext)                       // requestId 부여 + 접근 로그
app.get('/healthz', (c) => c.json({ status: 'ok' }))            // 인증 없음 (liveness)
app.get('/readyz', async (c) => {                                // DB 연결 확인 (readiness)
  await db.execute(sql`select 1`)
  return c.json({ status: 'ready' })
})

app.use('/api/*', cors({
  origin: env.CORS_ORIGINS,                        // SPA 출처 목록 (와일드카드 금지)
  allowHeaders: ['Content-Type', 'Authorization'],
  allowMethods: ['GET', 'POST', 'PATCH', 'DELETE'],
  maxAge: 600,
}))
app.use('/api/*', bodyLimit({
  maxSize: 1024 * 1024,                            // 1MB — ALB 뒤라도 앱이 스스로 자른다
  onError: () => { throw new AppError(413, 'PAYLOAD_TOO_LARGE', '요청 본문이 너무 큽니다') },
}))

app.route('/api/auth', authRoutes)                 // 공개 — 로그인 URL은 로그인 전에 받는다
app.use('/api/*', requireAuth)                     // 이 아래에 등록된 것만 인증이 걸린다
app.route('/api/tasks', tasksRoutes)

app.notFound(notFound)
app.onError(onError)
```

**등록 순서가 곧 인증 경계다.** Hono는 등록 순서대로 실행하고, 핸들러가 `next()` 없이
Response를 반환하면 체인이 끝난다. 그래서 `requireAuth` **앞에** 등록된 `/healthz`와
`/api/auth/*`는 인증을 만나지 않고, 뒤에 등록된 `/api/tasks`는 반드시 만난다. `requireAuth`를
`/healthz`보다 앞에 올리는 순간 ALB 헬스체크가 401을 받아 태스크가 순환한다.

`AppEnv`는 `c.get`/`c.set`의 타입을 만든다. 프로젝트 전역에 한 번만 선언한다.

```ts
// src/http/types.ts
import type { AuthUser } from '@/http/auth'
export type AppEnv = { Variables: { user: AuthUser; requestId: string } }
```

## 핸들러의 표준 형태

핸들러는 네 줄짜리 어댑터다: **파싱 → 서비스 호출 → 상태 코드 선택 → 봉투 반환**.
분기·SQL·권한 판정이 핸들러에 들어오면 서비스로 내린다.

```ts
// src/routes/tasks.ts
import { Hono } from 'hono'
import { jsonBody, queryParams, pathParam } from '@/http/validate'
import { CreateTaskInput, ListTasksQuery, TaskIdParam, UpdateTaskInput } from '@/schemas/tasks'
import * as tasks from '@/services/tasks'
import type { AppEnv } from '@/http/types'

export const tasksRoutes = new Hono<AppEnv>()

tasksRoutes.get('/', async (c) => {
  const q = queryParams(c, ListTasksQuery)
  const page = await tasks.listTasks(c.get('user').sub, q)
  return c.json({ data: page.items, nextCursor: page.nextCursor })
})

tasksRoutes.post('/', async (c) => {
  const body = await jsonBody(c, CreateTaskInput)
  const created = await tasks.createTask(c.get('user').sub, body)
  return c.json({ data: created }, 201)
})

tasksRoutes.patch('/:id', async (c) => {
  const { id } = pathParam(c, TaskIdParam)
  const body = await jsonBody(c, UpdateTaskInput)
  return c.json({ data: await tasks.updateTask(c.get('user').sub, id, body) })
})

tasksRoutes.delete('/:id', async (c) => {
  const { id } = pathParam(c, TaskIdParam)
  await tasks.deleteTask(c.get('user').sub, id)     // 0행이면 서비스가 404를 던진다
  return c.body(null, 204)
})
```

소유자는 항상 `c.get('user').sub`다. 본문·쿼리에 실려 온 `ownerId`는 읽지 않는다.

## 응답 봉투 계약

| 종류 | 형태 |
| --- | --- |
| 단건 성공 | `{ "data": { ... } }` |
| 목록 성공 | `{ "data": [ ... ], "nextCursor": "<cursor>" \| null }` |
| 삭제 성공 | 본문 없음 (204) |
| 실패 | `{ "error": { "code": "...", "message": "...", "details"?: ... }, "requestId": "..." }` |

- `code`는 기계가 읽고 `message`는 사람이 읽는다. SPA는 **`code`로만 분기**한다
- `details`는 검증 실패(422)에만 담는다 — 필드별 메시지 맵
- `requestId`는 모든 에러 응답에 넣는다. 사용자가 이 값을 알려주면 로그에서 바로 찾는다

## 페이지네이션은 커서로 한다

`offset`은 행이 삽입되면 항목이 밀려 중복·누락이 생긴다. `(created_at, id)` 튜플 커서를 쓴다.

- 요청 스키마 `ListTasksQuery`(`limit`·`cursor`·`archived`)의 정본 정의는
  `resources/input-validation.md`에 있다 — 여기서 다시 선언하지 않는다
- `cursor`는 `base64url("<iso>|<uuid>")`이며 **상한(`.max(200)`)이 있는 문자열**이다.
  커서도 클라이언트가 보낸 값이므로 길이 제한과 디코드 실패 처리(400)가 있어야 한다
- 응답의 `nextCursor`가 `null`이면 마지막 페이지다. 쿼리 구현은 `resources/data-access.md`,
  인코딩·디코딩은 `resources/complete-example.md`의 서비스 층에 있다

## 에러 코드표

| `error.code` | 상태 | 의미 | 발생 지점 |
| --- | --- | --- | --- |
| `BAD_REQUEST` | 400 | JSON 파싱 실패, 쿼리 형식 오류 | `validate.ts` |
| `UNAUTHORIZED` | 401 | 토큰 없음·만료·서명/발급자 불일치 (**사유 미구분**) | `auth.ts` |
| `FORBIDDEN` | 403 | 인증됐으나 역할·스코프 부족 (소유권 아님) | 서비스 |
| `NOT_FOUND` | 404 | 리소스 부재 **또는** 미인가 접근 (동일 응답) | 서비스 |
| `CONFLICT` | 409 | unique 제약 위반, 상태 전이 충돌 | 서비스 / DB |
| `VALIDATION_FAILED` | 422 | Zod 스키마 위반 | `validate.ts` |
| `PAYLOAD_TOO_LARGE` | 413 | 본문 크기 초과 | 본문 크기 가드 |
| `INTERNAL` | 500 | 예상 못 한 예외 | `onError` |

코드는 이 표에서만 고른다. 새 코드가 필요하면 표에 먼저 추가한다 — SPA가 분기하는 계약이다.

## AppError와 전역 처리 (`src/http/errors.ts`)

```ts
import type { Context } from 'hono'
import { HTTPException } from 'hono/http-exception'
import { log } from '@/http/logger'

export type ErrorStatus = 400 | 401 | 403 | 404 | 409 | 413 | 422 | 500
export type ErrorCode =
  | 'BAD_REQUEST' | 'UNAUTHORIZED' | 'FORBIDDEN' | 'NOT_FOUND'
  | 'CONFLICT' | 'VALIDATION_FAILED' | 'PAYLOAD_TOO_LARGE' | 'INTERNAL'

export class AppError extends Error {
  constructor(
    readonly status: ErrorStatus,
    readonly code: ErrorCode,
    message: string,
    readonly details?: unknown,
  ) { super(message) }
}

// 프레임워크가 던진 HTTPException의 상태 → 계약상의 코드. 표에 없는 상태는 500으로 접는다
const FRAMEWORK_CODES: Partial<Record<number, ErrorCode>> = {
  400: 'BAD_REQUEST', 401: 'UNAUTHORIZED', 403: 'FORBIDDEN',
  404: 'NOT_FOUND', 409: 'CONFLICT', 413: 'PAYLOAD_TOO_LARGE',
}

export const notFound = (c: Context) =>
  c.json({ error: { code: 'NOT_FOUND', message: 'Not found' }, requestId: c.get('requestId') }, 404)

export const onError = (err: Error, c: Context) => {
  const requestId = c.get('requestId')
  if (err instanceof AppError) {
    if (err.status >= 500) log.error({ msg: err.message, code: err.code, requestId })
    if (err.status === 401) c.header('WWW-Authenticate', 'Bearer')   // 표준 챌린지 헤더
    return c.json({ error: { code: err.code, message: err.message, details: err.details }, requestId },
      err.status)
  }
  if (err instanceof HTTPException) {                       // 프레임워크가 던진 것
    const code = FRAMEWORK_CODES[err.status]
    if (!code) {
      log.error({ msg: 'unmapped framework error', status: err.status, requestId })
      return c.json({ error: { code: 'INTERNAL', message: 'Internal Server Error' }, requestId }, 500)
    }
    if (err.status === 401) c.header('WWW-Authenticate', 'Bearer')
    return c.json({ error: { code, message: err.message }, requestId }, err.status as ErrorStatus)
  }
  log.error({ msg: 'unhandled error', error: String(err), stack: err.stack, requestId })
  return c.json({ error: { code: 'INTERNAL', message: 'Internal Server Error' }, requestId }, 500)
}
```

**에러는 던지고, 매핑은 한 곳에서만 한다.** 핸들러마다 try/catch를 두면 봉투가 갈라진다.

`err.getResponse()`를 그대로 반환하지 않는 이유: 프레임워크의 응답에는 `error.code`도
`requestId`도 없어 "SPA는 `code`로만 분기한다"는 계약이 그 경로에서만 깨진다. **상태 코드만
취하고 본문은 우리 봉투로 다시 만든다.** 반대로 모든 `HTTPException`을 `BAD_REQUEST`로
뭉개면 413 응답에 `BAD_REQUEST` 코드가 실려 코드표의 413 행이 영영 생성되지 않는다 —
`bodyLimit`처럼 상태를 스스로 정하는 미들웨어는 위 표에 상태를 등록하거나(`FRAMEWORK_CODES`)
`app.ts`처럼 `onError` 옵션으로 `AppError`를 던지게 해서 계약 안으로 들여온다.

## PostgreSQL 에러를 도메인 응답으로 바꾼다

드라이버 에러를 그대로 500으로 흘리지 않는다. 제약 위반은 사용자가 고칠 수 있는 409다.

```ts
// src/db/errors.ts
export function isUniqueViolation(err: unknown, constraint?: string): boolean {
  const e = err as { code?: string; constraint?: string }
  return e?.code === '23505' && (constraint === undefined || e.constraint === constraint)
}

// 서비스에서
try {
  return await insertTask(ownerId, input)
} catch (err) {
  if (isUniqueViolation(err, 'tasks_owner_title_key')) {
    throw new AppError(409, 'CONFLICT', '같은 제목의 작업이 이미 있습니다')
  }
  throw err                                    // 모르는 에러는 삼키지 않고 올린다
}
```

주요 SQLSTATE: `23505` unique 위반(409), `23503` FK 위반(409 또는 422), `23514` check
위반(422), `22P02` 잘못된 텍스트→타입 변환(400 — 대개 Zod에서 먼저 걸러야 한다).

## 본문 크기와 타임아웃

- 본문 크기 상한을 전역으로 건다: `bodyLimit`(`hono/body-limit`)을 `/api/*`에 등록한다.
  **기본 `onError`는 우리 봉투를 모른다** — 위 `app.ts`처럼 `AppError(413, 'PAYLOAD_TOO_LARGE')`를
  던지는 `onError`를 넘겨야 413이 코드표대로 나간다. ALB 뒤라도 애플리케이션이 스스로 자른다
- ALB idle timeout보다 짧은 요청 타임아웃을 서비스 층에 둔다. 외부 호출에는
  `AbortSignal.timeout(ms)`를 넘긴다 — 응답 없는 의존성이 워커를 잠그지 않게 한다

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `c.json(null, 204)` | 204는 본문이 없다 → `c.body(null, 204)`를 쓴다 |
| `c.req.param('id')` vs `c.req.query('id')` | 경로 세그먼트는 `param`, `?id=`는 `query`. 둘 다 문자열이므로 Zod로 파싱한다 |
| `await c.req.json()` 직접 사용 | 본문 없음·깨진 JSON에서 그냥 throw된다 → `jsonBody(c, Schema)`로 감싸 400 봉투를 만든다 |
| `c.req.query()` vs `c.req.queries()` | 단일 값은 `query()`, 반복 키(`?tag=a&tag=b`)는 `queries()`가 배열을 준다 |
| `throw new HTTPException(404)` | 프레임워크 에러다 — 도메인 실패는 `AppError`를 던져 `code`를 계약에 맞춘다 |
| `app.use(mw)` vs `app.use('/api/*', mw)` | 경로 없는 `use`는 모든 경로에 걸린다 → 헬스체크까지 인증이 걸려 ALB가 태스크를 죽인다 |
| 공개 라우트를 `requireAuth` 뒤에 마운트 | 로그인 URL을 받으려면 먼저 로그인해야 하는 데드락이 된다 → `/api/auth`는 `requireAuth` **앞**에 등록한다 |
| `app.route()` vs `app.mount()` | Hono 서브 앱 결합은 `route()`. `mount()`는 다른 프레임워크의 핸들러를 붙일 때만 |
| 에러 응답에 `err.message` 그대로 노출 | 500 계열은 고정 문구만 내보내고 원문은 로그로 보낸다 |
| 200 + `{ ok: false }` | SPA의 fetch 래퍼가 성공으로 처리한다 → 실패는 반드시 4xx/5xx 상태로 |
| 핸들러마다 try/catch | 봉투가 제각각이 된다 → `onError` 하나로 모은다 |
