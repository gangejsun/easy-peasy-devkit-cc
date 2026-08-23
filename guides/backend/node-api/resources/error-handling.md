<!-- epcc-pack: backend/node-api v3.13.0 -->
# 에러 처리 — 도메인 코드에서 HTTP 상태까지

이 파일이 소유하는 코드 파일은 `src/http/errors.ts` 하나다: 상태 코드 표 · Prisma 에러
판별 · `ZodError` 정규화 · 알 수 없는 throw의 정규화. `AppError` 클래스와 봉투를 방출하는
`errorHandler`는 **이음매가 소유한다** (`src/http/app-error.ts` · `src/http/routers/`) —
봉투 형태가 축이 아니라 조합의 함수라서다. 미들웨어 순서는 `project-structure.md`가 정한다.

## 1. 실패를 만나면 어느 층이 무엇을 하는가

| 층 | 실패 예 | 그 층이 하는 일 | 최종 상태 |
| --- | --- | --- | --- |
| 스키마 (`parseBody`) | 잘못된 본문 | `AppError('VALIDATION_FAILED', …)` 던짐 | 400 |
| 쿼리 함수 (`db/tasks.ts`) | 0행 변경 | `AppError('NOT_FOUND')` 던짐 | 404 |
| 쿼리 함수 | 유일성 충돌 | **아무것도 안 한다** — Prisma가 `P2002`를 던진다 | 409 |
| 서비스 | 도메인 규칙 위반 | 코드표에 있는 코드로 `AppError` | 표 참조 |
| 에러 미들웨어 (이음매) | 위 전부 + 예상 밖 | `toAppError` → `ERROR_STATUS` → 봉투 | — |

원칙은 셋이다. **① 실패는 반환값이 아니라 예외다** — Express 5가 동기 throw와 거부된
프로미스를 둘 다 에러 미들웨어로 자동 전달하므로 `Result` 타입을 손으로 나를 이유가 없다.
**② 상태 코드를 아는 층은 하나다** — 쿼리 함수도 서비스도 숫자를 모르고 코드만 던진다.
**③ 잡아서 다시 던지지 않는다** — `catch (e) { throw e }`는 스택만 흐린다.

`try/catch`를 쓸 자리는 둘뿐이다: 라이브러리 실패를 도메인 코드로 **번역**할 때, 그리고
자원을 반드시 닫아야 할 때. 그 밖에는 그냥 올려보낸다.

## 2. 코드 표와 정규화 (`src/http/errors.ts`)

<!-- file: src/http/errors.ts -->
```ts
import { Prisma } from '@prisma/client';
import { z } from 'zod';
import { AppError } from './app-error';

export const ERROR_STATUS: Record<string, number> = {
  VALIDATION_FAILED: 400,
  UNAUTHENTICATED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  PAYLOAD_TOO_LARGE: 413,
  INTERNAL: 500,
};

// express.json()이 던지는 오류. AppError가 아니므로 정규화하지 않으면 전부 500이 된다
function bodyParserType(e: unknown): string | undefined {
  const c = e as { type?: unknown; status?: unknown };
  return e instanceof Error && typeof c.type === 'string' && typeof c.status === 'number'
    ? c.type
    : undefined;
}

export function isUniqueViolation(e: unknown): e is Prisma.PrismaClientKnownRequestError {
  return e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002';
}

export function isRecordNotFound(e: unknown): e is Prisma.PrismaClientKnownRequestError {
  return e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2025';
}

export function fieldErrors(e: z.ZodError): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const issue of e.issues) {
    const key = issue.path.length === 0 ? '_' : issue.path.join('.');
    (out[key] ??= []).push(issue.message);
  }
  return out;
}

export function toAppError(e: unknown): AppError {
  if (e instanceof AppError) return e;
  if (e instanceof z.ZodError) {
    return new AppError('VALIDATION_FAILED', '요청이 유효하지 않습니다', fieldErrors(e));
  }
  switch (bodyParserType(e)) {
    case 'entity.parse.failed':
      return new AppError('VALIDATION_FAILED', '요청 본문이 올바른 JSON이 아닙니다');
    case 'entity.too.large':
      return new AppError('PAYLOAD_TOO_LARGE', '요청 본문이 너무 큽니다');
  }
  if (isUniqueViolation(e)) return new AppError('CONFLICT', '이미 존재하는 값입니다');
  if (isRecordNotFound(e)) return new AppError('NOT_FOUND', '대상을 찾을 수 없습니다');
  return new AppError('INTERNAL', '서버 오류가 발생했습니다');
}
```

마지막 줄이 이 파일의 보안 표면이다. **원래 메시지를 버리고 고정 문자열로 대체한다** —
`TypeError: prisma.task.findMany is not a function` 같은 메시지가 응답에 실리면 내부 구조와
의존성이 그대로 나간다. `TypeError('x is not a function')`을 던진 핸들러가
`{"error":{"code":"INTERNAL","message":"서버 오류가 발생했습니다"}}` 500을 돌려줬다. <!-- verified: express 5.2.1 통합 실행 — 래퍼 없는 async 핸들러의 throw가 errorHandler를 거쳐 500 -->
원문은 버리는 것이 아니라 **로그로 간다** (7절).

`bodyParserType` 분기가 없으면 **핸들러에 닿기도 전의 실패가 전부 500이 된다.**
`express.json()`은 라우터 앞에서 돌고 자기 오류를 던지는데, 그것들은 `AppError`도
`ZodError`도 아니다. 잘못된 JSON 한 줄이 5xx 경보를 올리게 되고, 클라이언트 잘못이
서버 장애로 집계된다. 두 오류는 `type` 문자열로 갈린다 — 클래스로 판별하지 않는 이유는
`PayloadTooLargeError`가 `express`에서 export되지 않기 때문이다.

| 입력 | 던져지는 것 | 분기 전 | 분기 후 |
| --- | --- | --- | --- |
| `{bad` | `SyntaxError` · `type:'entity.parse.failed'` · `status:400` | 500 `INTERNAL` | **400 `VALIDATION_FAILED`** |
| 1.2MB 본문 | `PayloadTooLargeError` · `type:'entity.too.large'` · `status:413` | 500 `INTERNAL` | **413 `PAYLOAD_TOO_LARGE`** |
<!-- verified: express 5.2.1 실행 — express.json({limit:'100kb'})에 두 입력을 보내 위 형태와 상태를 모두 관측 -->

`err.status`를 그대로 응답 상태로 쓰지 않고 도메인 코드로 번역하는 것은 규율이다.
**상태를 아는 층은 `ERROR_STATUS` 하나여야** 하고, 라이브러리가 정한 숫자를 통과시키기
시작하면 그 규율이 라이브러리마다 갈라진다.

`ERROR_STATUS`를 `Record<string, number>`로 두고 `?? 500`으로 조회하는 것은 의도다.
이음매가 조합 고유 코드(`PAYMENT_REQUIRED` 등)를 추가할 수 있어야 하고, 표에 없는 코드가
타입 오류가 아니라 **500으로 안전하게 떨어져야** 한다.

## 3. Prisma 에러 판별 — `P2002` · `P2025`

`PrismaClientKnownRequestError`는 `code` 문자열을 들고 온다. 아래 대응은 설치본
(`@prisma/client` 6.19.3)에서 코드 → 원인 매핑을 직접 대조해 만들었다.

| 코드 | Prisma 내부 이름 | 뜻 | 이 팩의 처리 |
| --- | --- | --- | --- |
| `P2002` | `UniqueConstraintViolation` | 유일 제약 위반 | 409 `CONFLICT` |
| `P2025` | `MISSING_RECORD` 계열 | 대상 행이 없음 | 404 `NOT_FOUND` |
| `P2003` | `ForeignKeyConstraintViolation` | 참조 무결성 위반 | 409 또는 400 — 조합이 정한다 |
| `P2000` | `LengthMismatch` | 값이 열 길이를 넘음 | 400 — Zod `.max()`가 먼저 잡아야 한다 |
| `P2034` | `TransactionWriteConflict` | 트랜잭션 쓰기 충돌 | 재시도 대상 — 500으로 떨구지 않는다 |
| `P2037` | `TooManyConnections` | 커넥션 고갈 | 503 — 풀 사이징은 `operations.md` |

`e.meta`에는 원인이 담긴다 — `P2002`면 `{ target: ['ownerId', 'title'] }`, `P2025`면
`{ modelName: 'Task', cause: 'No record was found for an update.' }` 형태다.
<!-- verified: 감사 A 실측 (@prisma/client 6.19.3 + 실 PostgreSQL). meta의 cause 문자열은 클라이언트 번들이 아니라 쿼리 엔진이 만든다 — 설치본 grep으로는 확인되지 않으며 엔진 버전에 따라 문구가 바뀐다 -->
**`cause` 문구는 계약이 아니다.** 쿼리 엔진이 만들고 버전마다 바뀌므로 **문자열을 파싱해
분기하지 마라** — 분기는 언제나 `code`로 한다.

**`meta`를 응답에 그대로 싣지 않는다**: `target`의 열 이름은 스키마 정보이고, 어떤 조합이
충돌했는지가 곧 다른 사용자의 데이터 존재 증명이 된다. `modelName`은 내부 모델명을
그대로 노출한다. 필드 단위 안내가 필요하면 `target`을 클라이언트가 아는 필드명으로
**번역해서** 넣는다.

`P2000`이 표에 있는 이유는 그것이 **도달하면 안 되는 코드**여서다. 길이 초과가 DB까지
갔다는 것은 `input-validation.md`의 `.max(200)`이 그 경로에 없었다는 뜻이다.

## 4. `ZodError` 정규화 — `fieldErrors`

`z.flattenError`가 있는데 직접 도는 이유가 있다. **`flattenError`는 한 층만 본다** —
경로가 `['nested','n']`인 이슈를 키 `nested`에 넣고 `.n`을 잃는다. <!-- verified: zod 4.4.3 실행 — 중첩·배열 경로를 담은 ZodError로 flattenError/treeifyError/직접순회를 대조 --> 중첩 객체나
배열 항목의 오류를 클라이언트가 필드에 붙일 수 없게 된다. `issue.path.join('.')`은
`tags.0` · `nested.n` 같은 도달 가능한 키를 만든다.

`e.message`를 응답에 쓰지 않는다. Zod 4의 `ZodError.message`는 **issue 배열을 통째로
직렬화한 JSON 문자열**이라 <!-- verified: zod 4.4.3 실행 — ZodError.message를 출력해 issue 배열 JSON임을 확인 --> 그대로 실으면 응답이 수 KB가 되고 내부 스키마
구조가 노출된다. 사람이 읽을 형태가 필요한 자리(부팅 로그 등)는 `z.prettifyError(e)`다.

아래는 `{ "title": "", "dueAt": "nope" }` 로 `POST /api/tasks` 한 실제 응답이다 —
`fieldErrors`의 출력만 떼어 보인 것이고 봉투 전체는 아니다:

```json
{"error":{"code":"VALIDATION_FAILED","details":{
  "title":["제목은 비울 수 없습니다"],"dueAt":["Invalid ISO datetime"]}}}
```

`path`가 빈 이슈(스키마 전체에 걸린 `.refine()`, `strictObject`의 미지 키)는 키 `_`로
모인다. 클라이언트는 이 키를 폼 전체 오류로 렌더링한다.

## 5. 존재를 누설하지 않는다 — 404와 403

**이 축에는 데이터 계층 정책 엔진이 없다.** 행 수준 보안이 백업해주지 않으므로
애플리케이션의 판정이 유일한 경계이고, **판정 결과를 상태 코드로 말하는 순간 그것이
정보가 된다.**

```ts
// ❌ 남의 작업에 403을 주면 id를 훑는 것만으로 어떤 id가 실재하는지 알 수 있다
const task = await prisma.task.findUnique({ where: { id } });
if (!task) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다');
if (task.ownerId !== user.id) throw new AppError('FORBIDDEN', '권한이 없습니다');
```

```ts
// ✅ 소유권을 조회 조건에 넣고, 없으면 없는 것이다 — 두 실패가 한 응답으로 합쳐진다
const task = await getTask(user.id, id);   // 소유자가 먼저다 — 두 인자가 다 string이라 tsc가 안 잡는다
if (!task) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다');
```

`FORBIDDEN`이 표에 남아 있는 것은 쓸 자리가 따로 있어서다. **존재가 이미 알려진 뒤의
권한 실패**에만 쓴다 — 자기 작업이지만 보관 상태라 수정할 수 없다거나, 역할이 모자라
관리자 목록에 접근할 수 없는 경우다. 판단 기준은 하나다: **403을 받은 사람이 그 사실만으로
새로 알게 되는 것이 있는가.** 있으면 404다.

인증 실패도 같다. `UNAUTHENTICATED`의 메시지는 "비밀번호가 틀렸습니다"가 아니라
"인증에 실패했습니다"다 — 사유를 구분하면 계정 존재 여부가 응답에서 읽힌다.

## 6. 방출은 한 곳에서 한다

봉투를 만드는 코드는 저장소에 하나여야 한다. 라우터가 직접 `res.status(400).json(...)`을
하면 같은 실패가 자리마다 다른 모양으로 나가고, 클라이언트는 분기를 늘린다.

`errorHandler`(이음매 소유)가 지켜야 할 계약은 **다섯**이다.

- **인자가 정확히 4개여야 한다.** Express는 arity로 에러 미들웨어를 판별한다 — 3개짜리
  함수는 에러 흐름에서 **호출되지 않고 조용히 건너뛰어진다.** 쓰지 않는 `next`도 지운다.
  <!-- verified: express 5.2.1 실행 — 3-arity 미들웨어는 에러 흐름을 건너뛰고 404 처리만 했다 -->
- **`app.use(errorHandler)`는 맨 마지막이다.** 404 미들웨어(`notFound`)보다 뒤다.
- **`res.headersSent`를 먼저 본다.** 응답이 나간 뒤의 실패는 덮어쓸 수 없으므로
  `next(err)`로 Express 기본 처리기에 넘겨 연결을 닫는다.
  <!-- verified: express 5.2.1 실행 — 응답 후 throw 시 200이 유지되고 스택이 stderr로 갔다 -->
- **`toAppError(err)`로 먼저 정규화한다.** 이 미들웨어에 도착하는 것의 다수는 `AppError`가
  **아니다** — `ZodError` · Prisma 오류 · `express.json()`의 파서 오류 · 예상 밖의 `TypeError`가
  모두 여기로 온다. 정규화를 건너뛰고 `err.code`를 바로 읽으면 그 전부가 500이 된다.
- **상태는 `ERROR_STATUS`에서만 읽는다**: `ERROR_STATUS[e.code] ?? 500`. 정규화된 `e`에서
  읽어야 한다 — 원본 `err.status`를 쓰면 위 규율이 무너진다.

```ts
// src/http/routers/tasks.ts — 이음매 소유. 라우터는 성공 봉투만 만든다
router.get('/:id', requireAuth, async (req, res) => {
  const task = await getTask(req.user.id, req.params.id);
  if (!task) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다');
  res.json({ data: task });
});
```

`try/catch`도 `next(err)`도 없다. Express 5는 거부된 프로미스를 자동 전달하므로
<!-- verified: express 5.2.1 + @prisma/client 6.19.3 통합 실행 — 래퍼 없는 async 핸들러가 던진 P2002/P2025/TypeError가 각각 409/404/500으로 나왔다 -->
`asyncHandler` 류 래퍼가 필요 없다 — `async` 핸들러가 던진 `P2002`가 래퍼 없이
409로 나왔다.

## 7. 로그와 응답을 분리한다

응답은 좁히고 로그는 넓힌다. 둘의 목적이 반대다 — 응답은 호출자가 **행동을 고치는 데
필요한 것만**, 로그는 운영자가 **재현하는 데 필요한 전부**다.

| 항목 | 응답 | 로그 |
| --- | --- | --- |
| 도메인 코드 (`CONFLICT`) | 싣는다 | 싣는다 |
| 필드 오류 (`details`) | 싣는다 | 싣는다 |
| 원본 예외 메시지·스택 | **버린다** | 싣는다 |
| Prisma `meta` | 버린다 | 싣는다 |
| 요청 상관 ID | 싣는다 | 싣는다 |
| 토큰·비밀·`DATABASE_URL` | 버린다 | **버린다** |

5xx는 `logger.error`, 4xx는 `logger.warn` 이하로 남긴다. 400을 error로 남기면 잘못된
클라이언트 하나가 경보를 가리고, 500을 남기지 않으면 사용자 제보로만 알게 된다.
`logger`는 `operations.md`가 소유한다 — 저장소 어디서도 `console`을 쓰지 않는다.
요청 상관 관계는 `pino-http`가 붙이므로 에러 미들웨어에서 `req.log`를 쓰면 이어진다.

## 오용 목록 ① — Express 4 → Express 5 관용구 대조표

설치본(express 5.2.1)에서 실행으로 대조했다. 옛 형태는 대부분 그대로 동작하기 때문에
컴파일도 테스트도 통과하며 조용히 남는다.

| 구 습관 (Express 4) | 현재 형태 (Express 5) |
| --- | --- |
| `asyncHandler(fn)` 래퍼로 거부를 잡음 | 필요 없다 — 거부된 프로미스가 자동 전달된다 <!-- verified: express 5.2.1 실행 확인 --> |
| `.catch(next)`를 모든 async 핸들러에 붙임 | 그냥 던진다 |
| `req.query = validated` 로 덮어씀 | setter가 없어 반영되지 않는다 — ESM은 `TypeError`, CJS는 **조용히 무시**. 반환값을 지역 변수로 받는다 <!-- verified: express 5.2.1 실행 — CJS/ESM 양쪽 관측 --> |
| `?a[b]=1` 이 `{a:{b:'1'}}`로 파싱된다고 가정 | 기본 파서가 중첩을 만들지 않는다 — 키가 `"a[b]"`다 <!-- verified: express 5.2.1 실행 확인 --> |
| `next(err)`를 호출해 에러를 올림 | 던진다. `next(err)`는 `headersSent` 위임에만 쓴다 |
| 에러 미들웨어를 3-arity로 선언 | 4-arity가 아니면 에러 흐름에서 호출되지 않는다 |
| `res.status(500).send(err.message)` | 코드만 던지고 봉투는 `errorHandler`가 만든다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `404 NOT_FOUND` vs `403 FORBIDDEN` | 존재 자체가 비밀이면 404. 403은 존재가 이미 알려진 뒤의 권한 실패에만 |
| `401 UNAUTHENTICATED` vs `403 FORBIDDEN` | 401은 "누구인지 모른다", 403은 "누구인지 알지만 안 된다" |
| `P2002` vs `P2025` | 충돌(409)과 부재(404). `update`가 두 코드를 다 던질 수 있다 |
| `P2025` vs `count === 0` | Prisma는 `update`/`delete`에서만 `P2025`를 던진다. `updateMany`/`deleteMany`는 조용히 0행이므로 **영향 행 수를 직접 봐야 한다** (`data-access.md`) |
| `e.code` vs `e.name` | 분기는 `code`(`P2002`). `name`은 전부 `PrismaClientKnownRequestError`로 같다 |
| `z.flattenError` vs 직접 순회 | 중첩·배열 필드가 있으면 직접 순회. `flattenError`는 한 층에서 경로를 잃는다 |
| `err.message` vs `z.prettifyError(err)` | `ZodError.message`는 issue 배열 JSON이다. 사람이 읽을 곳에는 `prettifyError` |
| `toAppError` vs `instanceof AppError` 직접 검사 | 정규화는 미들웨어 한 곳에서 `toAppError`로. 라우터에서 갈래를 세면 새 예외 종류가 늘 때마다 놓친다 |
