<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# 입력 검증 — 이벤트와 환경변수를 경계에서 잘라낸다

Zod 4 스키마 · API Gateway HTTP API v2 이벤트 파싱 · 환경변수의 콜드 스타트 검증을 소유한다.
검증 실패를 상태 코드로 옮기는 표(`ERROR_STATUS`)와 `fieldErrors`는 `resources/error-handling.md`
(`src/http/errors.ts`)가 소유하고, `AppError`와 응답 봉투 `respond`는 **이음매**가
(`src/http/app-error.ts` · `src/http/respond.ts`) 소유한다. 키 설계와 쿼리는
`resources/data-modeling.md` · `resources/data-access.md`에 있다.

## 1. 무엇을 어디서 검증하는가

**입력의 출처가 검증 자리와 실패 시점을 정한다.** 배포가 정하는 값은 콜드 스타트에,
요청자가 보낸 값은 요청마다 검증한다.

| 입력 | 이벤트/프로세스 필드 | 검증 자리 | 실패 시점 | 결과 |
| --- | --- | --- | --- | --- |
| 환경변수 | `process.env` | `EnvSchema` (모듈 최상위) | **콜드 스타트** | 함수가 뜨지 않는다 |
| 본문 | `event.body` | `parseBody` | 요청 | `VALIDATION_FAILED` 400 |
| 쿼리 | `event.queryStringParameters` | `parseQuery` | 요청 | `VALIDATION_FAILED` 400 |
| 경로 | `event.pathParameters` | `pathParam` | 요청 | `VALIDATION_FAILED` 400 |
| 주체(누구인가) | `event.requestContext.authorizer` | `requireAuth` (이음매) | 요청 | `UNAUTHENTICATED` 401 |

판단은 세 줄로 끝난다.

- **요청자가 값을 고를 수 있는가** → 스키마를 통과시킨다. 통과 전 값은 `unknown`으로 둔다
- **배포가 값을 고정하는가** → `src/env.ts` 한 곳에서만 읽는다. 앱 코드는 `env`만 본다
- **소유자 id인가** → **입력에서 읽지 않는다.** `requireAuth(event).id`만 쓴다.
  이 축에는 데이터 계층 정책 엔진이 없어 애플리케이션 층이 실질적 유일 경계다 —
  본문·쿼리의 `ownerId`를 신뢰하면 그 자리가 곧 유출이다

미지 키 처리도 여기서 갈린다. **본문은 거부(`z.strictObject`), 쿼리는 제거(`z.object`)** 다.
본문의 미지 키는 클라이언트가 계약을 잘못 안 것이니 알려주는 편이 낫고, 쿼리 문자열에는
추적 파라미터가 늘 섞여 들어와 거부하면 정상 요청이 죽는다.

## 2. 환경변수 (`src/env.ts`) — 콜드 스타트에 실패시킨다

<!-- file: src/env.ts -->
```ts
// src/env.ts
import { z } from 'zod';

export const EnvSchema = z.object({
  TABLE_NAME: z.string().min(1),
  AWS_REGION: z.string().min(1),
  LOG_LEVEL: z.enum(['DEBUG', 'INFO', 'WARN', 'ERROR']).default('INFO'),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('production'),
});

export type Env = z.infer<typeof EnvSchema>;

const parsed = EnvSchema.safeParse(process.env);
if (!parsed.success) {
  throw new Error(`환경변수 검증 실패\n${z.prettifyError(parsed.error)}`);
}

export const env: Env = parsed.data;
```

**`safeParse`를 모듈 최상위에서 돌린다.** 핸들러 안에서 검증하면 잘못된 배포가 첫 요청까지
살아 있고, 그 첫 요청은 사용자다. 최상위에서 던지면 초기화가 실패해 함수가 아예 뜨지 않는다.
`AppError`가 아니라 생짜 `Error`를 던지는 것도 같은 이유다 — 이 시점에는 응답할 요청이 없고
`respond`도 아직 없다.

`TABLE_NAME`은 CDK가 `environment`로 넘긴다(`resources/deploy-and-iam.md`).
`AWS_REGION`은 Lambda 런타임이 채운다 <!-- unverified -->.

**Lambda 환경변수는 비밀 저장소가 아니다.** 값이 CloudFormation 템플릿과 콘솔에 그대로
보이므로 API 키·서명 키는 Secrets Manager/SSM에 두고 **ARN만** 환경변수로 넘긴다.
스키마에 담는 것은 그 ARN이지 비밀 자체가 아니다.

## 3. 본문·쿼리 스키마 (`src/schemas/task.ts`)

<!-- file: src/schemas/task.ts -->
```ts
// src/schemas/task.ts
import { z } from 'zod';

export const TaskStatusSchema = z.enum(['open', 'done']);
export type TaskStatus = z.output<typeof TaskStatusSchema>;

export const TaskCreateSchema = z.strictObject({
  title: z.string().trim().min(1).max(200),
  status: TaskStatusSchema.default('open'),
});

export const TaskUpdateSchema = z
  .strictObject({
    title: z.string().trim().min(1).max(200).optional(),
    status: TaskStatusSchema.optional(),
  })
  .refine((v) => Object.keys(v).length > 0, { message: '수정할 필드를 최소 하나 보낸다' });

export const TaskQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().min(1).optional(),
  status: TaskStatusSchema.optional(),
});

export type TaskCreate = z.output<typeof TaskCreateSchema>;
export type TaskUpdate = z.output<typeof TaskUpdateSchema>;
export type TaskQuery = z.output<typeof TaskQuerySchema>;
```

세 스키마가 서로 다른 생성자를 쓰는 이유는 미지 키 정책이 다르기 때문이다.

| 생성자 | 미지 키 | 쓰는 자리 | 확인한 동작 |
| --- | --- | --- | --- |
| `z.strictObject` | **거부** (`unrecognized_keys`) | 본문 | `{title,ownerId}` → 400, `ownerId` 필드 오류 <!-- verified: zod 4.4.3 실행, safeParse 출력 --> |
| `z.object` | **제거** | 쿼리 | `{ownerId:'…'}` → `{limit:20}` <!-- verified: zod 4.4.3 실행 --> |
| `z.looseObject` | 보존 | 쓰지 않는다 | 검증되지 않은 값이 그대로 통과한다 |

`limit`에 `z.coerce.number()`가 붙은 것은 쿼리 문자열의 값이 **항상 문자열**이기 때문이다.
`.default(20)`이 여기서는 안전하다 — 목록 조회는 부분 수정이 아니라 **완전한 질의**라
보내지 않은 값에 기본을 채우는 것이 정확히 의도한 바다. 4절이 그 반대 경우다.

`cursor`는 `resources/data-access.md`의 `decodeCursor`가 해석하는 불투명 문자열이므로
여기서는 길이만 본다. 형식 판단은 디코더 한 곳에 둔다.

## 4. 부분 업데이트 — `.partial()`은 `.default()`를 지우지 않는다

**이 축에서 가장 비싼 검증 결함이다.** 문법은 완벽하고 타입도 통과하며, 드러나는 것은
사용자가 제목만 고쳤는데 상태가 `open`으로 돌아갔다는 신고뿐이다.

```ts
// ❌ src/schemas/task.ts — 생성 스키마를 .partial()로 재사용한다
export const TaskUpdateSchema = TaskCreateSchema.partial();
// ❌ 보낸 것 {}                  → 받은 것 {"status":"open"}
// ❌ 보낸 것 {"title":"고침"}     → 받은 것 {"title":"고침","status":"open"}
```

`.partial()`은 각 필드를 `ZodOptional`로 감싸지만 안쪽 `ZodDefault`를 벗기지 않는다 —
래퍼는 `optional(default(enum))`이 되고, 키가 없으면 기본값이 채워진다. 위 출력은 실행
결과 그대로다 <!-- verified: zod 4.4.3, TaskCreateSchema.partial().safeParse 출력 -->.
그 값이 `updateTask(ownerId, id, patch)`의 `UpdateExpression`에 실려 **보내지 않은 필드를
덮어쓴다.**

수정 스키마는 생성 스키마에서 파생시키지 말고 **`.optional()` 필드로 따로 선언한다**(3절).
그러면 같은 세 입력이 이렇게 나온다.

| 입력 | 결과 | 확인 |
| --- | --- | --- |
| `{}` | 400 — `_: ["수정할 필드를 최소 하나 보낸다"]` | `.refine`이 잡는다 <!-- verified: 실행 출력 --> |
| `{"title":"고침"}` | `{"title":"고침"}` — **`status`가 붙지 않는다** | <!-- verified: 실행 출력 --> |
| `{"title":"고침","zzz":1}` | 400 — `zzz: ["허용되지 않는 필드다"]` | strict가 유지된다 <!-- verified: 실행 출력 --> |

`.refine`으로 빈 객체를 막는 것은 형식이 아니라 의미 때문이다. `{}`를 통과시키면 0개 필드
갱신이 성공 응답으로 나가고, 클라이언트는 저장됐다고 믿는다.

## 5. 이벤트에서 값 꺼내기 (`src/http/parse.ts`)

<!-- file: src/http/parse.ts -->
```ts
// src/http/parse.ts
import { Buffer } from 'node:buffer';
import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { z } from 'zod';
import { AppError } from './app-error';
import { fieldErrors } from './errors';

function decodeBody(event: APIGatewayProxyEventV2): string {
  const raw = event.body;
  if (raw === undefined || raw === null || raw === '') {
    throw new AppError('VALIDATION_FAILED', '요청 본문이 비어 있다');
  }
  return event.isBase64Encoded ? Buffer.from(raw, 'base64').toString('utf8') : raw;
}

export function parseBody<S extends z.ZodType>(schema: S, event: APIGatewayProxyEventV2): z.output<S> {
  let json: unknown;
  try {
    json = JSON.parse(decodeBody(event));
  } catch (e) {
    if (e instanceof AppError) throw e;
    throw new AppError('VALIDATION_FAILED', '요청 본문이 JSON이 아니다');
  }
  const r = schema.safeParse(json);
  if (r.success) return r.data;
  throw new AppError('VALIDATION_FAILED', '요청 본문이 스키마와 맞지 않는다', fieldErrors(r.error));
}

export function parseQuery<S extends z.ZodType>(schema: S, event: APIGatewayProxyEventV2): z.output<S> {
  const r = schema.safeParse(event.queryStringParameters ?? {});
  if (r.success) return r.data;
  throw new AppError('VALIDATION_FAILED', '쿼리 문자열이 스키마와 맞지 않는다', fieldErrors(r.error));
}

export function pathParam(event: APIGatewayProxyEventV2, name: string): string {
  const v = event.pathParameters?.[name];
  if (typeof v !== 'string' || v.trim() === '') {
    throw new AppError('VALIDATION_FAILED', `경로 파라미터 ${name}이 없다`);
  }
  return v;
}
```

세 함수 모두 **이벤트 필드가 없을 수 있다**는 전제로 쓴다. `@types/aws-lambda@8.10.162`의
V2 이벤트에서 `body` · `queryStringParameters` · `pathParameters`는 셋 다 선택 필드(`?:`)다
<!-- verified: node_modules/@types/aws-lambda/trigger/api-gateway-proxy.d.ts:219-231 직접 대조 -->.
`?? {}`와 `?.`는 값이 `undefined`든 `null`이든 같은 자리로 떨어뜨린다 — 어느 쪽이 오는지
런타임에서 확인하지 않아도 안전한 형태를 고른 것이다.

`catch` 블록의 `if (e instanceof AppError) throw e;`가 없으면 `decodeBody`가 던진
"본문이 비어 있다"가 JSON 파싱 실패로 둔갑한다. `try`가 감싸는 범위를 좁게 보는 습관이
여기서 값을 한다.

`Buffer.from(raw, 'base64')`는 API Gateway가 바이너리로 판정한 요청을 위한 것이다.
`isBase64Encoded`를 무시하면 base64 문자열이 그대로 `JSON.parse`에 들어가 400이 된다.

## 6. 핸들러 배선과 테스트

핸들러는 **첫 줄에서 주체를, 다음 줄에서 입력을** 얻는다. Lambda에는 미들웨어 체인이
없으므로 이 순서를 강제하는 것은 규율뿐이다.

```ts
// src/handlers/tasks-update.ts
export const handler = withContext(async (event) => {
  try {
    const user = requireAuth(event);
    const id = pathParam(event, 'id');
    const patch = parseBody(TaskUpdateSchema, event);
    return respond(await updateTask(user.id, id, patch));
  } catch (e) {
    return respond.fail(e);
  }
});
```

**`try/catch`를 빼면 이 절의 검증이 통째로 무의미해진다.** `withContext`는 미처리 예외를
로깅한 뒤 **다시 던지므로**(원장의 형태 열), 감싸지 않으면 `requireAuth`의 401 ·
`parseBody`의 400 · `updateTask`의 404가 **전부 Lambda 실패로 접혀 5xx**로 나간다.
봉투로 바꾸는 것은 래퍼가 아니라 핸들러 안의 `respond.fail`이다 —
`resources/error-handling.md` §6이 같은 형태를 쓴다.

테스트는 **긍정과 부정을 같은 `it` 안에 짝으로** 건다. 부정 단언만 걸면 스키마를
`z.never()`로 바꿔도 초록이다 — 전부 400이기 때문이다.

```ts
// test/schemas.task.test.ts
it('부분 수정은 보내지 않은 필드를 건드리지 않는다', () => {
  expect(TaskUpdateSchema.parse({ title: '고침' })).toEqual({ title: '고침' }); // ✅ 긍정
  expect(TaskUpdateSchema.safeParse({}).success).toBe(false);                   // ✅ 부정
  expect(TaskUpdateSchema.safeParse({ title: 'x', zzz: 1 }).success).toBe(false);
});
```

## 오용 목록 ① — Express + Zod 3 관용구 → Lambda(HTTP API v2) + Zod 4 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `express.json()` 미들웨어가 본문을 파싱해 준다 | `event.body`는 문자열이거나 없다. `parseBody`가 직접 `JSON.parse`한다 |
| `req.query.limit`이 이미 파싱돼 있다 | 값이 전부 문자열이다 — `z.coerce.number()`로 강제한다 |
| `app.use(validate(schema))` 검증 미들웨어 | 미들웨어 체인이 없다. 핸들러 첫 줄에서 함수를 부른다 |
| 검증 미들웨어가 `req.body`를 덮어쓴다 | `parseBody`의 **반환값**만 쓴다. 이벤트는 수정하지 않는다 |
| `dotenv`로 `.env`를 읽는다 | 환경변수는 CDK가 함수에 주입한다. `src/env.ts`가 검증만 한다 |
| `z.object({...}).strict()` | `z.strictObject({...})` — 생성자로 정한다 (`.strict()`도 아직 있다) <!-- verified: zod 4.4.3에서 o.strict === function --> |
| `schema.deepPartial()` | **없어졌다.** 중첩 부분 갱신은 스키마를 따로 선언한다 <!-- verified: zod 4.4.3에서 o.deepPartial === undefined --> |
| `z.string({ required_error: '…' })` | **조용히 무시된다.** `z.string({ error: '…' })`를 쓴다 <!-- verified: zod 4.4.3, required_error 전달 시 기본 메시지가 나온다 --> |
| `err.errors` 배열을 순회 | `err.issues`다. `err.errors`는 `undefined` <!-- verified: zod 4.4.3 실행 --> |
| `z.string().email()` | `z.email()` — 상위 함수로 옮겼다 (구 형태도 아직 동작한다) <!-- verified: zod 4.4.3에서 둘 다 function --> |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `TaskCreateSchema.partial()` vs 독립 `.optional()` 선언 | 원본에 `.default()`가 하나라도 있으면 `.partial()`은 **쓸 수 없다** — 4절 |
| `z.strictObject` vs `z.object` | 본문은 strict(계약 위반을 알린다), 쿼리는 object(추적 파라미터가 섞인다) |
| `z.object` vs `z.looseObject` | `looseObject`는 검증되지 않은 키를 통과시킨다 — 입력 경계에서는 쓰지 않는다 |
| `.default(v)` vs `.optional()` | 완전한 질의(목록 쿼리)에는 `.default()`, 부분 수정에는 `.optional()` |
| `z.infer` vs `z.output` | 변환이 없으면 같다. `.transform()`·`.coerce`가 붙은 스키마의 **결과** 타입은 `z.output` |
| `.min(1)` vs `.trim().min(1)` | `"   "`는 `.min(1)`만으로는 통과한다. 문자열 본문에는 `.trim()`을 먼저 건다 |
| `event.body` 없음 vs `'null'` 문자열 | 전자는 "본문이 비어 있다", 후자는 `JSON.parse`가 `null`을 만들어 스키마 오류가 된다 |
| `queryStringParameters` vs `rawQueryString` | 후자는 원문 문자열이다. 같은 키가 여럿이면 전자는 쉼표로 합쳐진 값 하나만 준다 |
| `parseQuery`의 `?limit=` 빈 값 | `z.coerce.number()`가 `''`를 `0`으로 만든다 — `.min(1)`이 없으면 통과한다 <!-- verified: zod 4.4.3, coerce.number().safeParse('') === 0 --> |
| `pathParam` vs 스키마 검증 | `pathParam`은 존재만 본다. id 형식 제약이 필요하면 반환값을 스키마에 다시 통과시킨다 |
