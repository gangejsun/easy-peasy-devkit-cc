<!-- epcc-seam: vue+node-api v3.13.0 -->
# API 엔드포인트 — 라우터 형태와 응답 봉투

이 파일이 소유하는 코드 파일은 셋이다: `src/http/app-error.ts` · `src/http/error-handler.ts` ·
`src/http/routers/tasks.ts`. 이 셋은 **봉투가 조합의 함수**라서 이음매에 있다. 상태 매핑표
(`ERROR_STATUS`)와 정규화(`toAppError`)는 `resources/error-handling.md`, 파싱 헬퍼는
`resources/input-validation.md`, 마운트 순서는 `resources/project-structure.md`가 소유한다.
토큰 검증과 `requireAuth`는 `resources/auth-boundaries.md`다.

## 1. 판단 — 이 요청을 어떤 응답으로 답하는가

프론트는 Vue SPA이고 서버는 별도 오리진이므로 경계는 HTTP 하나뿐이다. 그래서 아래 표가
프론트가 파싱하는 형태 전부다 — 한 칸이라도 어긋나면 화면이 갈라진다.

| 하려는 일 | 메서드 · 경로 | 성공 | 본문 |
| --- | --- | --- | --- |
| 목록 | `GET /api/tasks` | 200 | `{ data: Task[], nextCursor }` |
| 단건 | `GET /api/tasks/:id` | 200 | `{ data: Task }` |
| 생성 | `POST /api/tasks` | 201 + `Location` | `{ data: Task }` |
| 수정 | `PATCH /api/tasks/:id` | 200 | `{ data: Task }` |
| 삭제 | `DELETE /api/tasks/:id` | 204 | 없음 |
| 그 밖의 전부 (실패) | — | 4xx·5xx | `{ error: { code, message, details? }, requestId }` |

**성공 봉투는 라우터가, 실패 봉투는 `errorHandler`가 만든다.** 두 곳이다 — 하지만 실패 쪽이
한 곳인 것이 요점이다. 라우터가 실패 봉투를 직접 쓰기 시작하면 같은 실패가 자리마다 다른
모양으로 나가고, 프론트는 분기를 늘린다.

## 2. 성공 봉투 — 값을 그대로 돌려주지 않는다

배열이나 원시값을 최상위에 두지 않는다. `data` 한 겹이 있으면 나중에 `nextCursor`·`meta`를
더할 때 프론트의 파싱이 깨지지 않는다.

```ts
// src/http/routers/tasks.ts — 성공 봉투 네 형태
// ❌ 배열을 최상위에 둔다 — 페이지 정보를 실을 자리가 없다
res.json(rows);
// ✅ 계약의 네 형태
res.json({ data: task });                                   // 단건 200
res.json({ data, nextCursor });                             // 목록 200
res.status(201).location(`/api/tasks/${task.id}`).json({ data: task });  // 생성
res.sendStatus(204);                                        // 삭제 — 본문 없음
```

<!-- verified: express@5.2.1 + supertest@7.2.2 실행 — 네 형태를 실제 요청으로 관측했다. 생성 응답의 Location이 `/api/tasks/<생성 id>`, 삭제 응답은 status 204 · res.text가 빈 문자열이었다 -->
`res.status(201).json(body)`를 쓴다. `res.json(201, body)`는 Express 5에서 예외 없이
**상태 200 + 본문 `201`**을 보낸다 — 조용히 틀리는 형태다.

## 3. 에러 봉투와 `AppError` (`src/http/app-error.ts`)

계약의 실패 봉투는 `error` 안에 `code`·`message`·`details`(선택), 최상위에 `requestId`다.
`AppError`는 그중 앞 셋을 나르는 도메인 타입이고 **HTTP 상태를 모른다** — 상태는
`ERROR_STATUS` 한 표가 정한다.

<!-- file: src/http/app-error.ts -->
```ts
export class AppError extends Error {
  readonly code: string;
  readonly details?: Record<string, string[]>;

  constructor(code: string, message: string, details?: Record<string, string[]>) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.details = details;
  }
}
```

생성자 인자 순서는 `(code, message, details?)`다. `parseBody`가 이 순서로 던지고
(`resources/input-validation.md`), `toAppError`도 그렇다 — 바꾸면 팩 전체가 어긋난다.

`details`는 `Record<string, string[]>`이고 **검증 실패에서만** 실린다. 프론트가 필드 옆에
붙이는 값이라 키는 폼 필드 이름과 같아야 하고, 스키마 전체에 걸린 오류는 키 `_`로 온다.
`code`가 `Record<string, number>`의 키로 조회되므로 계약의 일곱 코드를 반드시 쓴다:
`VALIDATION_FAILED` · `UNAUTHENTICATED` · `FORBIDDEN` · `NOT_FOUND` · `CONFLICT` ·
`PAYLOAD_TOO_LARGE` · `INTERNAL`. 표에 없는 코드는 타입 오류가 아니라 조용히 500이 된다.

## 4. 방출은 한 곳에서 한다 (`src/http/error-handler.ts`)

<!-- file: src/http/error-handler.ts -->
```ts
import { randomUUID } from 'node:crypto';
import 'pino-http';   // req.log · req.id 선언 병합 (http.IncomingMessage)
import type { ErrorRequestHandler, Request } from 'express';
import { ERROR_STATUS, toAppError } from './errors';

// pino-http가 요청마다 req.id를 붙인다. 없더라도 requestId는 계약상 항상 실려야 하므로
// 여기서 만든다 — 사용자가 문의에 실을 값이 응답에서 빠지면 추적이 끊긴다.
function requestIdOf(req: Request): string {
  return req.id === undefined ? randomUUID() : String(req.id);
}

export const errorHandler: ErrorRequestHandler = (err, req, res, next) => {
  if (res.headersSent) { next(err); return; }
  const e = toAppError(err);
  const status = ERROR_STATUS[e.code] ?? 500;
  req.log?.[status >= 500 ? 'error' : 'warn']({ err, code: e.code }, 'request failed');
  res.status(status).json({
    error: { code: e.code, message: e.message, ...(e.details ? { details: e.details } : {}) },
    requestId: requestIdOf(req),
  });
};
```

**인자는 정확히 넷이다.** Express는 arity로만 에러 미들웨어를 판별한다 — 3인자로 줄이면
등록은 되지만 에러 흐름에서 호출되지 않는다.
<!-- verified: express@5.2.1 실행 — 3인자 use를 단 앱에 throw를 보내니 그 미들웨어를 건너뛰고 Express 기본 처리기가 500 + text/html을 돌려줬다 -->
`import 'pino-http'` 한 줄이 `req.log`와 `req.id`의 타입을 들여온다 — 값을 쓰지 않는 import라
지우기 쉬운데, 지우면 두 속성이 `Request`에 없어 컴파일이 깨진다.
<!-- verified: pino-http@10.5.0 + typescript@5.9.3 — 이 import 없이 tsc --strict가 TS2339 "Property 'log' does not exist on type 'Request'"로 실패했고, 넣으면 통과했다 -->

**`toAppError`를 건너뛰면 안 된다.** 이 미들웨어에 도착하는 것의 다수는 `AppError`가 아니다.
정규화 없이 `err.code`를 바로 읽은 형태와 정규화한 형태에 **같은 입력**(`{bad`)을 보냈다:

<!-- verified: express@5.2.1 실행 — 두 미들웨어를 각각 마운트한 앱에 잘못된 JSON을 보내 응답을 그대로 관측 -->
| 형태 | 상태 | 본문 |
| --- | --- | --- |
| `err.code`를 바로 읽음 | 500 | `{"error":{"code":"INTERNAL","message":"Expected property name or '}' in JSON at position 1 …"}}` |
| `toAppError(err)` 먼저 | 400 | `{"error":{"code":"VALIDATION_FAILED","message":"요청 본문이 올바른 JSON이 아닙니다"}}` |

첫 줄이 두 번 틀렸다. 클라이언트 잘못이 5xx로 집계되고, **파서의 내부 메시지가 응답에 그대로
나갔다.** 정규화는 상태 코드 문제만이 아니라 유출 차단이다.

## 5. `tasksRouter` (`src/http/routers/tasks.ts`)

<!-- file: src/http/routers/tasks.ts -->
```ts
import { Router, type Request } from 'express';
import { AppError } from '../app-error';
import { parseBody, parseQuery } from '../parse';
import { requireAuth, type AuthUser } from '../require-auth';
import { TaskCreateSchema, TaskQuerySchema, TaskUpdateSchema } from '../../schemas/task';
import { deleteTask, getTask, insertTask, listTasks, updateTask } from '../../db/tasks';

// requireAuth 뒤에만 마운트되므로 req.user는 있다. 그래도 `!` 단언을 쓰지 않는다 —
// 마운트를 빠뜨리면 단언은 TypeError(500)로 새고, 이 함수는 401로 닫힌다 (실측: 5절 아래).
function actor(req: Request): AuthUser {
  if (!req.user) throw new AppError('UNAUTHENTICATED', '인증에 실패했습니다');
  return req.user;
}

export const tasksRouter = Router();
tasksRouter.use(requireAuth);

tasksRouter.get('/', async (req, res) => {
  const q = parseQuery(TaskQuerySchema, req);
  const page = await listTasks(actor(req).id, q);
  const hasMore = page.length > q.limit;
  const data = hasMore ? page.slice(0, q.limit) : page;
  res.json({ data, nextCursor: hasMore ? data[data.length - 1].id : null });
});

tasksRouter.post('/', async (req, res) => {
  const input = parseBody(TaskCreateSchema, req);
  const task = await insertTask(actor(req).id, input);
  res.status(201).location(`/api/tasks/${task.id}`).json({ data: task });
});

tasksRouter.get('/:id', async (req, res) => {
  const task = await getTask(actor(req).id, req.params.id);
  if (!task) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다');
  res.json({ data: task });
});

tasksRouter.patch('/:id', async (req, res) => {
  const patch = parseBody(TaskUpdateSchema, req);
  const task = await updateTask(actor(req).id, req.params.id, patch);
  res.json({ data: task });
});

tasksRouter.delete('/:id', async (req, res) => {
  await deleteTask(actor(req).id, req.params.id);
  res.sendStatus(204);
});
```

`tasksRouter.use(requireAuth)`를 **라우터 첫 줄에** 건다. 라우트마다 인자로 끼우면 새 라우트를
추가할 때 빠뜨릴 수 있고, 빠뜨린 라우트는 조용히 공개된다 — 실패 방향이 열림이다.

`try/catch`도 `next(err)`도 없다. Express 5는 async 핸들러의 거부를 에러 미들웨어로 자동
전달한다. `parseBody`/`parseQuery`는 **반환값**을 쓴다 — `req.query`에 대입하면 반영되지 않는다.

<!-- verified: express@5.2.1 실행 — requireAuth를 뺀 라우터 두 벌에 인증 없이 요청. `actor(req)`는 401 UNAUTHENTICATED, `req.user!.id`는 500 INTERNAL이었다 -->
`actor()`가 있는 판과 `req.user!`를 쓴 판에서 `requireAuth`를 빼고 인증 없이 때려 봤다.
앞은 401, 뒤는 **500**이다. 뒤는 남의 행을 주지는 않았지만 실패가 서버 오류로 집계된다.

## 6. 커서 페이지네이션 응답

계약의 페이지네이션은 커서다 — 요청 파라미터는 `limit`과 `cursor`, 응답 필드는 `nextCursor`다.
오프셋(`page`·`skip`)은 쓰지 않는다: 목록이 자주 바뀌면 페이지 경계에서 행이 중복되거나
누락된다. 쿼리 함수가 `take: limit + 1`로 한 행 더 받아 오므로, 라우터가 할 일은
**잘라내고 마지막 id를 실어 보내는 것**뿐이다.

```ts
// src/http/routers/tasks.ts — 목록 핸들러 발췌
// ❌ 별도 count 쿼리로 총 개수를 세어 totalPages를 만든다 — 매 요청 스캔이 한 번 더 늘어난다
const total = await countTasks(owner);
// ✅ 한 행 더 받아 다음 쪽 유무를 판정한다. 마지막 쪽에서 nextCursor는 null이다
const hasMore = page.length > q.limit;
const data = hasMore ? page.slice(0, q.limit) : page;
res.json({ data, nextCursor: hasMore ? data[data.length - 1].id : null });
```

<!-- verified: express@5.2.1 + supertest@7.2.2 실행 — 5행을 limit=2로 3쪽 순회. 2·2·1건이 왔고 id 5개가 중복 없이 모였으며 마지막 쪽의 nextCursor가 null이었다 -->
`limit=0`은 `TaskQuerySchema`의 `.min(1)`이 400으로 막고, `?utm_source=x`처럼 미지의 쿼리 키는
`z.object`가 **제거**한다(거부하지 않는다). 본문은 반대로 `z.strictObject`가 거부한다.

## 7. CORS — 별도 오리진이라는 전제 (`src/http/cors.ts`)

Vue SPA는 자기 오리진에서 서빙되고 이 서버는 다른 오리진이다. 그래서 CORS는 선택이 아니라
경계 자체다. **허용 오리진은 코드가 아니라 `env`에서 온다** — 스테이징·프로덕션이 다르다.

<!-- file: src/http/cors.ts -->
```ts
import type { RequestHandler } from 'express';
import { AppError } from './app-error';
import { env } from '../env';

const ALLOWED = new Set(env.WEB_ORIGINS);

export const cors: RequestHandler = (req, res, next) => {
  const origin = req.get('origin');
  if (origin && ALLOWED.has(origin)) {
    res.setHeader('Access-Control-Allow-Origin', origin);
    res.setHeader('Access-Control-Allow-Credentials', 'true');
    res.setHeader('Vary', 'Origin');
  }
  if (req.method === 'OPTIONS') {
    res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE');
    res.setHeader('Access-Control-Allow-Headers', 'authorization,content-type');
    res.setHeader('Access-Control-Max-Age', '600');
    res.sendStatus(204);
    return;
  }
  next();
};

// 재발급처럼 쿠키로 인증하는 라우트가 직접 부른다. CORS 헤더는 응답을 읽는 것만 막고
// 요청 실행 자체는 막지 못하기 때문이다 (auth-boundaries 5절).
export function requireAllowedOrigin(req: Parameters<RequestHandler>[0]): void {
  const origin = req.get('origin');
  if (origin !== undefined && !ALLOWED.has(origin)) {
    throw new AppError('FORBIDDEN', '허용되지 않은 오리진입니다');
  }
}
```

`makeApp()`에서 `express.json()`보다 **앞**에 마운트한다. 프리플라이트에는 본문이 없고,
파서 오류가 프리플라이트를 막으면 브라우저는 원인을 CORS 실패로만 보고한다.

<!-- verified: express@5.2.1 + supertest@7.2.2 실행 — 허용 오리진의 OPTIONS는 204 + ACAO/ACAC + Vary: Origin, 허용 밖 오리진은 ACAO 헤더 자체가 없었다 -->
`Vary: Origin`이 없으면 캐시(프록시·CDN)가 한 오리진의 응답을 다른 오리진에 준다.
`Access-Control-Allow-Origin: *`와 `credentials: true`는 **함께 쓸 수 없다** — 브라우저가
거부하므로 오리진을 되비추는 형태여야 하고, 그래서 허용 목록이 필수다.

## 오용 목록 ① — Express 4 → Express 5 관용구 대조표 (봉투 관점)

| 구 습관 (Express 4) | 현재 형태 (Express 5.2.1) |
| --- | --- |
| `res.json(201, body)` | `res.status(201).json(body)` — 2인자는 상태 200 + 본문 `201`을 보낸다 |
| `asyncHandler(fn)`으로 감싸 봉투 유지 | 그냥 던진다. 거부 프로미스가 `errorHandler`까지 간다 |
| `app.use('*', notFound)` | `app.use(notFound)` — `'*'`는 path-to-regexp 8에서 부팅 실패다 |
| `router.get('/:id?', h)` | `router.get('/tasks{/:id}', h)` — `?` 선택 파라미터 문법이 없다 |
| 에러 미들웨어를 3인자로 선언 | 4인자. 3인자는 에러 흐름에서 호출되지 않는다 |
| `req.query = TaskQuerySchema.parse(req.query)` | `const q = parseQuery(TaskQuerySchema, req)` — 대입은 반영되지 않는다 |
| `res.send(err.message)`로 실패 응답 | 코드만 던지고 봉투는 `errorHandler`가 만든다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `res.json({ data })` vs `res.json(rows)` | 언제나 `data` 한 겹. 배열을 최상위에 두면 `nextCursor`를 실을 자리가 없다 |
| `res.sendStatus(204)` vs `res.status(204).json({})` | 삭제는 `sendStatus`. 204에 본문을 실으면 프론트의 JSON 파싱이 깨진다 |
| `next(err)` vs `throw err` | 핸들러 안에서는 같다. `next(err)`는 `res.headersSent` 위임에만 쓴다 |
| `toAppError(err)` vs `err instanceof AppError` | 미들웨어에서는 언제나 `toAppError`. 갈래를 직접 세면 새 예외 종류를 놓친다 |
| `errorHandler`의 `details` vs `message` | 필드별 오류만 `details`. 사람이 읽을 한 줄은 `message` |
| `router.use(requireAuth)` vs 라우트마다 인자로 | 라우터 단위로 건다. 라우트마다 걸면 새 라우트가 조용히 공개된다 |
| `Access-Control-Allow-Origin: *` vs 되비추기 | 자격 증명을 쓰면 `*`가 불가하다. 허용 목록에서 골라 되비춘다 |
| `limit` 상한 없음 vs `.max(100)` | 상한이 없으면 한 요청으로 테이블 전체를 읽는 경로가 생긴다 |
