<!-- epcc-pack: backend/node-api v3.13.0 -->
# 파일 구성과 앱 조립 — 계층 경계 · Express 5 배선

이 파일이 소유하는 것: 계층 경계(`routers → services → db`)와 그 강제 수단 · `makeApp` ·
`notFound` · 미들웨어 순서 · 라우터 마운트 지점 · 비동기 핸들러 규약. 소유하지 않는 것:
**라우터 본문·응답 봉투·`errorHandler`·`AppError`는 이음매가 소유한다** (`src/http/routers/` ·
`src/http/error-handler.ts` · `src/http/app-error.ts`). 쿼리는 `resources/data-access.md`, 환경변수는
`resources/input-validation.md`, 프로세스 수명(부팅 로그·종료·헬스체크 본문)은 `resources/operations.md`.

## 1. 판단 — 새 코드를 어느 계층에 두는가

| 그 코드가 하는 일 | 두는 곳 | 받아도 되는 것 |
| --- | --- | --- |
| 요청을 읽고 응답 봉투를 만든다 | `src/http/routers/` (이음매) | `Request` · `Response` · `NextFunction` |
| 여러 쿼리를 묶고 트랜잭션 경계를 정한다 | `src/services/` | 평범한 인자 (`ownerId` · DTO) |
| 한 테이블에 대한 쿼리 한 덩어리 | `src/db/` | 평범한 인자만 |
| 요청 형태 검증 | `src/schemas/` + `src/http/parse.ts` | Zod 스키마 |
| 프로세스 관심사 (로거·헬스·종료) | `src/ops/` | — |
| 앱을 조립한다 (마운트·순서) | `src/app.ts` | — |
| 프로세스를 띄운다 (`listen`·시그널) | `src/index.ts` | — |

판단이 갈리면 **"이 코드를 테스트하는 데 HTTP 서버가 필요한가"**를 묻는다. 필요 없다면
서비스나 db다. `src/app.ts`가 `listen`을 부르지 않는 이유도 같다 — 테스트가 포트를 잡지 않고
`makeApp()`을 supertest에 그대로 넘길 수 있다 (`resources/testing.md`).

## 2. 계층은 한 방향으로만 흐른다

`routers → services → db`. 역방향 import(`db/`가 `http/`를 부르는 것)는 쿼리 테스트에 서버를
요구하게 만들고, 결국 데이터 계층이 요청 객체를 인자로 받는 형태로 무너진다.

**예외는 하나다**: `src/db/`는 `src/http/app-error`를 import해도 된다. `AppError`는 HTTP
어댑터가 아니라 상태 코드를 모르는 도메인 에러 타입이고(매핑은 `ERROR_STATUS`가 한다),
`src/http/` 아래 있는 것은 이음매가 소유하는 파일들의 배치를 L0가 못박은 결과다.

규율만으로는 지켜지지 않으므로 검사를 붙인다.

```json
// package.json — scripts 발췌
"scripts": {
  "lint:layers": "! grep -rn \"from '[.][.]/http/\" src/db | grep -v http/app-error"
}
```

**차단 확인**: `src/db/tasks.ts`에 `import { errorHandler } from '../http/error-handler'`를
심고 돌리면 그 줄을 출력하며 종료 코드 1, 지우면 0이었다. 이 파일이 도는 것과 잡는 것은
다르므로 결함을 심어 확인한 뒤에 CI에 넣는다.

## 3. 앱 조립 (`src/app.ts`)

`makeApp()`은 앱을 **조립만** 한다. 요청도 받지 않고 포트도 잡지 않는다.

<!-- file: src/app.ts -->
```ts
// src/app.ts
import express, { type Express, type RequestHandler } from 'express';
import { AppError } from './http/app-error';
import { errorHandler } from './http/error-handler';
import { healthz, readyz } from './ops/health';
import { tasksRouter } from './http/routers/tasks';

export const notFound: RequestHandler = (_req, _res, next) => {
  next(new AppError('NOT_FOUND', 'Route not found'));
};

export function makeApp(): Express {
  const app = express();
  app.disable('x-powered-by');

  app.get('/healthz', healthz);          // 파서·인증보다 앞 — 의존성이 죽어도 답해야 한다
  app.get('/readyz', readyz);

  app.use(express.json({ limit: '1mb' }));
  app.use('/api/tasks', tasksRouter);    // requireAuth는 라우터가 건다

  app.use(notFound);                     // 매칭 실패 → AppError
  app.use(errorHandler);                 // 봉투 방출 — 반드시 마지막
  return app;
}
```

**실행 확인**(Express 5.2.1): `/healthz` 200 · `/api/tasks/…` 200 · 매칭 실패한
`/api/tasks/no-such`와 `/nope` 모두 에러 봉투로 404. 요청 로거(`resources/operations.md`)를 넣을 자리는
헬스 엔드포인트 **뒤**, 라우터 **앞**이다 — 헬스 폴링이 로그를 채우지 않는다.

`app.use(express.json())`을 라우터보다 앞에 두지 않으면 핸들러에서 `req.body`가 `undefined`다.
반대로 전역에 두면 파일 업로드 라우트까지 JSON 파서를 지나므로, 그런 라우트가 생기면
`app.use('/api/tasks', express.json(), tasksRouter)`처럼 마운트 지점으로 좁힌다.

## 4. 미들웨어 순서 — 틀리면 봉투가 사라진다

Express는 등록 순서대로 훑는다. **`notFound`는 모든 라우터 뒤, `errorHandler` 앞이다.**

같은 앱에서 순서만 바꿔 실측한 결과:

| 배치 | `/nope` 응답 |
| --- | --- |
| `…라우터 → notFound → errorHandler` | `404` + JSON 봉투 |
| `…라우터 → errorHandler → notFound` | `500` + Express 기본 **HTML 오류 페이지** |
| 에러 핸들러를 `(err, req, res)` 3인자로 선언 | `500` + HTML — 일반 미들웨어로 등록된다 |

세 번째가 조용한 함정이다. Express는 **인자 개수 4개**만으로 에러 미들웨어를 식별한다.
`next`를 안 쓴다고 지우면 그 함수는 에러를 영영 못 본다 — `_next`로 이름만 바꿔 남긴다.

봉투를 방출하는 곳은 `errorHandler` 하나다. 라우터가 직접 `res.status(400).json(...)`을
하면 같은 실패가 자리에 따라 다른 모양으로 나간다.

## 5. 라우터 마운트와 Express 5 경로 문법

라우터 파일은 이음매가 소유한다. `makeApp`이 정하는 것은 **마운트 지점**뿐이다.

```ts
// src/app.ts — 도메인이 늘어나면 마운트 줄만 늘어난다
app.use('/api/tasks', tasksRouter);
app.use('/api/users', usersRouter);
```

Express 5의 경로 매처가 바뀌어 4에서 쓰던 와일드카드·선택 파라미터 표기가 **부팅 시 예외**를
던진다. 라우트를 등록하는 시점에 터지므로 배포 직후 전체가 죽는다.

<!-- verified: express@5.2.1 실행 — app.get('*')·app.get('/:id?')가 PathError를 던졌다 -->

| 표기 | Express 5.2.1에서 |
| --- | --- |
| `'*'` | `PathError: Missing parameter name at index 1` |
| `'/*splat'` | 정상 — 이름 붙은 와일드카드를 쓴다 |
| `'/:id?'` | `PathError: Unexpected ? at index 4` |
| `'/tasks{/:id}'` | 정상 — 중괄호가 선택 구간이다 |

`notFound`를 쓰면 catch-all 라우트가 애초에 필요 없다. 위 표는 기존 코드를 옮겨올 때 본다.

## 6. 비동기 핸들러 — 래퍼를 만들지 않는다

<!-- verified: express@5.2.1 실행 — async 핸들러의 throw가 errorHandler에 도달해 404 봉투가 나갔다 -->
Express 5는 핸들러가 돌려준 거부 프로미스를 **자동으로** `next(err)`로 넘긴다. Express 4에서
쓰던 `asyncHandler`·`express-async-errors` 류 래퍼는 이 축에서 불필요하다.

```ts
// src/http/routers/tasks.ts — 이음매가 소유하는 파일 (형태만)
// ✅ 던지기만 하면 errorHandler까지 간다
router.get('/:id', requireAuth, async (req, res) => {
  const task = await getTask(req.user.id, req.params.id);
  if (!task) throw new AppError('NOT_FOUND', 'Task not found');
  res.json({ data: task });
});
```

단 **콜백 안에서 던진 것은 전달되지 않는다.** `setTimeout(() => { throw … })`이나 이벤트
리스너 안의 예외는 프로세스를 죽인다. 비동기 작업은 반드시 프로미스로 돌려 `await`한다.

## 7. 부팅 (`src/index.ts`)

`index.ts`가 하는 일은 셋이다 — 조립 · `listen` · **시그널 배선**. 로직을 여기 두면 테스트에서
포트를 잡지 않고는 못 부른다. `src/index.ts`의 정본은 이 절이다 —
`resources/operations.md`는 `shutdown` 본문을 소유하고 이 파일을 다시 그리지 않는다.

<!-- file: src/index.ts -->
```ts
// src/index.ts
import { makeApp } from './app';
import { env } from './env';
import { logger } from './ops/logger';
import { shutdown } from './ops/shutdown';

const server = makeApp().listen(env.PORT, () => logger.info({ port: env.PORT }, 'listening'));

process.on('SIGTERM', () => { void shutdown(server); });
process.on('SIGINT', () => { void shutdown(server); });
```

**`shutdown(server)`를 톱레벨에서 부르지 않는다.** `shutdown`은 시그널을 거는 함수가 아니라
**배수를 수행하는** 함수다(`(server: Server) => Promise<void>`). 톱레벨에서 부르면 부팅과
동시에 배수가 돌아 프로세스가 1초도 못 살고, **종료 코드가 0이라 크래시 루프가 정상 종료
반복으로 보인다.** 실행 확인: 그 형태는 `listening`을 찍기도 전에 `draining`·`complete`를 찍고
exit 0으로 죽었다. 핸들러 안에서 부르면 `listening` 뒤에 살아 있다가 SIGTERM에만 배수한다.

포트는 `env`에서 온다 — `process.env`를 읽는 파일은 `src/env.ts` 하나다. 부팅 로그는
`console`이 아니라 구조적 로거로 남긴다. `console`은 레벨도 요청 상관관계도 없어 운영에서
검색되지 않는다. `shutdown`은 배수할 대상이 필요하므로 서버 핸들을 받는다 — 본문(SIGTERM
처리·연결 배수)과 시그니처의 정본은 `resources/operations.md`다.

## 8. 본문 파서가 던지는 오류

`express.json()`은 잘못된 본문에 대해 라우터에 닿기 전에 던진다. **실측한 오류 형태**:

| 입력 | `err.name` | `err.status` | `err.type` |
| --- | --- | --- | --- |
| `{bad` | `SyntaxError` | `400` | `entity.parse.failed` |
| `limit` 초과 본문 | `PayloadTooLargeError` | `413` | `entity.too.large` |

이 오류들은 `AppError`가 아니므로 정규화하지 않으면 전부 500으로 떨어진다 — 클라이언트 잘못이
서버 오류로 보고되고, 알람이 잘못 울린다. 정규화는 `toAppError`가 하고 매핑표는
`ERROR_STATUS`가 가진다 (`resources/error-handling.md`). `makeApp`은 파서를 **어디에** 둘지만 정한다.

## 오용 목록 ① — Express 4 → Express 5 관용구 대조표

| 구 습관 (Express 4) | 현재 형태 (Express 5.2.1) |
| --- | --- |
| `app.get('*', notFound)` <!-- verified: 실행 — PathError --> | `app.use(notFound)` (라우트가 아니라 미들웨어로) |
| `router.get('/:id?')` <!-- verified: 실행 — PathError --> | `router.get('/tasks{/:id}')` |
| `asyncHandler(fn)` 래퍼로 감싸기 <!-- verified: 실행 — 래퍼 없이 404 봉투 도달 --> | 그냥 `async` 핸들러. 거부 프로미스가 자동 전달된다 |
| `res.json(201, body)` 2인자 호출 <!-- verified: express@5.2.1 실행 — 상태 200, 본문 `201` --> | `res.status(201).json(body)`. 2인자 호출은 예외 없이 **상태 200 + 본문 `201`**을 보낸다 — 조용히 틀린다 |
| `app.del('/x', h)` <!-- verified: 실행 — typeof app.del === 'undefined' --> | `app.delete('/x', h)` |
| `req.param('id')` <!-- verified: 실행 — express.request.param이 undefined --> | `req.params.id` · `req.query.id` |
| `res.redirect('back')` <!-- verified: express@5.2.1 실행 — 302 Location: back --> | 특수 처리가 없어져 문자열 `back`으로 그대로 이동한다. 복귀가 필요하면 **서버가 정한 고정 경로**로 보낸다 |
| `app.use(bodyParser.json())` | `app.use(express.json())` — 별도 패키지가 필요 없다 |

**요청에서 온 값을 `Location`에 싣지 않는다.** 헤더·쿼리·본문은 공격자가 정하므로 절대 URL·
프로토콜 상대(`//host`)·`javascript:`가 그대로 통과한다 — 오픈 리다이렉트다. 이 축은 JSON API라
리다이렉트 자체가 드물고, 로그인 후 복귀 경로가 필요한 조합이면 그 검증은 이음매의
`auth-boundaries` 슬롯이 소유한다. 굳이 여기서 다룬다면 문자열 prefix나 origin 비교로는 부족하다:
정규화 **후의 출력 경로**를 검증해야 `/..//host`가 막힌다.

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `app.use(fn)` vs `app.use(path, fn)` | 인자가 하나면 **모든** 요청을 지난다. 마운트 지점을 좁히려면 경로를 앞에 준다 |
| `notFound` vs `errorHandler` | 앞은 "매칭된 라우트가 없다"를 에러로 **바꾸는** 3인자 미들웨어, 뒤는 그 에러를 봉투로 **바꾸는** 4인자 미들웨어. 순서는 언제나 이 순이다 |
| `next(err)` vs `throw err` | 동기·`async` 핸들러 안에서는 둘이 같다. 콜백 안이라면 `throw`는 전달되지 않으므로 `next(err)`만 통한다 |
| `makeApp()` vs `app.listen()` | 조립과 부팅을 나눈다. 테스트는 `makeApp()`을 supertest에 넘기고 포트를 잡지 않는다 |
| `src/services/` vs `src/db/` | 쿼리 하나로 끝나면 `db/`. 트랜잭션 경계나 여러 쿼리 조합이 생기면 `services/`(예: `TaskService`) |
| `req.query.limit` vs 검증된 값 | Express 5의 기본 쿼리 파서는 `simple`이라 값이 `string` 또는 `string[]`이다. 숫자를 기대하는 코드는 `TaskQuerySchema`를 지난 값만 쓴다 |
| 라우터에서 `res.status(400).json(...)` vs `throw new AppError(...)` | 봉투를 두 곳에서 만들지 않는다. 라우터는 던지기만 하고 방출은 `errorHandler`가 한다 |
