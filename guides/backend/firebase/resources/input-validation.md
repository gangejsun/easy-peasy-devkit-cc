<!-- epcc-pack: backend/firebase v3.14.0 -->
# 입력 검증 — 스키마와 구성 파라미터

`functions/src/schemas/task.ts`(Zod 스키마 · `parseCallable`)와 `functions/src/params.ts`
(`defineString`/`defineInt`/`defineSecret` · 부팅 검증)를 소유한다.

에러 코드표(`AppError`)와 `HttpsError`로의 번역은 **이음매가 소유한다**
(`functions/src/http/app-error.ts` · `functions/src/http/https.ts`). 핸들러 래퍼(`withErrors`)와
주체 추출(`requireUid`)은 `resources/functions-patterns.md`, 문서 형태는
`resources/data-modeling.md`가 소유한다. 스키마의 증명은 `resources/testing-and-deploy.md`에 있다.

## 1. 결정 트리 — 어느 값을 어디서 막는가

**이 축의 경계는 둘이고 서로 다른 코드 경로를 막는다.** Security Rules는 클라이언트 SDK만
막고, `firebase-admin`은 규칙을 완전히 우회한다. 함수 경로에서는 **아래 표가 유일한 경계다.**

| 값의 출처 | 막는 자리 | 도구 | 실패하면 |
| --- | --- | --- | --- |
| `request.data` (호출 본문) | 핸들러 첫 줄 | `parseCallable(스키마, req.data)` | `AppError('VALIDATION_FAILED')` |
| `request.auth.uid` (주체) | 핸들러 첫 줄 | `requireUid(req)` | `AppError('UNAUTHENTICATED')` |
| 커서·목록 파라미터 | 같은 스키마 | `TaskQuerySchema` | 위와 같다 |
| 배포 시 주입되는 구성 | 인스턴스당 1회 | `config()` | 첫 호출에서 `INTERNAL` |
| 클라이언트 SDK 직접 쓰기 | `firestore.rules` | 규칙 | `permission-denied` |

**`ownerId`는 어느 스키마에도 넣지 않는다.** 본문에서 받는 순간 클라이언트가 소유자를
고를 수 있게 된다. 소유자는 `requireUid(req)`가 인증 컨텍스트에서만 만든다.

## 2. 스키마 (`functions/src/schemas/task.ts`)

<!-- file: functions/src/schemas/task.ts -->
```ts
import { z } from 'zod';
import { AppError } from '../http/app-error';

export const TaskStatusSchema = z.enum(['open', 'done']);

export const TaskCreateSchema = z.strictObject({
  title: z.string().trim().min(1).max(200),
  status: TaskStatusSchema.default('open'),
});

export const TaskUpdateSchema = z
  .strictObject({
    title: z.string().trim().min(1).max(200).optional(),
    status: TaskStatusSchema.optional(),
  })
  .refine((p) => Object.keys(p).length > 0, { message: '수정할 필드가 최소 하나는 필요하다' });

export const TaskQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().min(1).optional(),
  status: TaskStatusSchema.optional(),
});

export type TaskCreate = z.output<typeof TaskCreateSchema>;
export type TaskUpdate = z.output<typeof TaskUpdateSchema>;
export type TaskQuery = z.output<typeof TaskQuerySchema>;

export function parseCallable<S extends z.ZodType>(schema: S, data: unknown): z.output<S> {
  const r = schema.safeParse(data);
  if (r.success) return r.data;
  const { fieldErrors, formErrors } = z.flattenError(r.error);
  const details: Record<string, string[]> = { ...fieldErrors } as Record<string, string[]>;
  if (formErrors.length > 0) details['_'] = formErrors;
  throw new AppError('VALIDATION_FAILED', '입력이 스키마와 다르다', details);
}
```

`TaskStatusSchema`의 리터럴 집합은 `firestore.rules`의 `d.status in ['open', 'done']`과
**같은 목록이다.** 늘릴 때 두 곳을 함께 고친다 — 규칙은 TypeScript를 보지 않는다.

## 3. 부분 수정 — `.partial()`은 기본값을 지우지 않는다

**`TaskUpdateSchema`를 `TaskCreateSchema.partial()`로 유도하지 않는다.** `partial()`은 필드를
선택적으로 만들 뿐 `.default()`를 벗기지 않아, 보내지 않은 필드가 기본값으로 되살아난다.
`status`를 손대지 않은 제목 수정이 `done`인 작업을 조용히 `open`으로 되돌린다.

<!-- verified: zod@4.4.3 파싱 결과를 직접 대조 (순수 함수라 Node 런타임과 무관) -->
```ts
// ❌ 유도하면 안 보낸 status가 채워진다 — 실행 확인: {"title":"t","status":"open"}
const Bad = TaskCreateSchema.partial();
Bad.parse({ title: 't' });
// ❌ .optional() 과 .default() 를 겹쳐도 같다 — 순서를 바꿔도 채워진다
z.object({ status: TaskStatusSchema.optional().default('open') }).parse({});
// ✅ 수정 스키마는 따로 선언한다 — 실행 확인: {"title":"t"}
TaskUpdateSchema.parse({ title: 't' });
```

빈 객체(`{}`)는 Zod가 **통과시킨다** — 선택 필드뿐이므로 위반이 없다. `.refine`으로 막지
않으면 아무것도 바꾸지 않는 수정이 `updatedAt`만 올리고 성공으로 답한다.

## 4. 미지 키 — 세 객체 타입이 서로 다르게 행동한다

| 스키마 | 미지 키를 | `{ title:'t', ownerId:'attacker' }` 파싱 결과 |
| --- | --- | --- |
| `z.strictObject` | **거부** | `unrecognized_keys`, `issue.keys = ['ownerId']` <!-- verified: zod@4.4.3 실행 --> |
| `z.object` | **조용히 제거** | `{ title:'t', status:'open' }` — 통과한다 <!-- verified: zod@4.4.3 실행 --> |
| `z.looseObject` | 통과시킨다 | `ownerId: 'attacker'`가 그대로 남는다 <!-- verified: zod@4.4.3 실행 --> |

**쓰기 본문은 `z.strictObject`다.** `z.object`가 제거해 주니 안전해 보이지만, 제거는
**조용하다** — 클라이언트가 `ownerId`를 보내고 200을 받으면 소유자를 바꿨다고 믿는다.
거부해야 그 오해가 첫 요청에서 끝난다. 반대로 `TaskQuerySchema`는 `z.object`다: 목록
쿼리스트링에는 추적 파라미터 같은 무해한 잉여가 섞이므로 제거가 맞다.

**예외가 하나 있다 — `strictObject`를 보안 통제로 믿지 않는다.** `JSON.parse`가 만든
`__proto__` 키는 `Object.keys`에 보이는데도 통과한다(값은 버려지고 프로토타입도 오염되지
않는다). 침묵이 계측 실패가 아님은 **양성 대조군**이 보증한다: 같은 스키마·같은 경로에서
`xyz`·`constructor`·`toString`은 전부 `unrecognized_keys`로 거부됐다.
<!-- verified: zod@4.4.3에서 JSON.parse('{"title":"t","__proto__":{"isAdmin":true}}') 통과 · 대조군 3종 거부를 함께 계측 -->

필수 필드가 빠진 `{}`는 `invalid_type`(`expected: 'string'`)으로 거부된다. `null`·문자열·
숫자·배열도 전부 `invalid_type`(`expected: 'object'`)이다 — 배열은 객체로 취급되지 않는다.

## 5. `onCall` 본문 검증 — `request.data`는 신뢰 입력이 아니다

`onCall`은 Authorization 헤더의 ID 토큰을 검증하지만 **토큰이 없는 요청을 막지는 않는다.**
인증 없이 부른 요청도 함수 안까지 들어온다 — 에뮬레이터 로그가
`{"verifications":{"app":"MISSING","auth":"MISSING"},...,"message":"Callable request verification passed"}`
를 남기고 핸들러를 실행했다. <!-- verified: firebase-functions@7.3.2 · 에뮬레이터에 무토큰 POST -->

```ts
// functions/src/index.ts (발췌) — 진입점 이름은 L0가 고정한다 (tasksCreate ≠ createTask)
export const tasksCreate = onCall(
  { region: REGION, secrets: [WEBHOOK_KEY], maxInstances: 10 },
  withErrors(async (req) => {
    const uid = requireUid(req);                             // ① 주체
    const input = parseCallable(TaskCreateSchema, req.data); // ② 본문
    logger.info('task.create', { uid, pageMax: config().TASKS_PAGE_MAX });
    return createTask(uid, input);                           // ③ ownerId는 uid에서만 온다
  }),
);
```

진입점(`tasksCreate`)과 리포지토리(`createTask`)는 **이름이 다르다.** 겹치면 테스트가
어느 쪽을 import하는지 갈리고, 실측에서 그 이유로 스위트가 적재조차 되지 않았다.

순서가 곧 응답 코드다. 무토큰 요청은 401 `UNAUTHENTICATED`, 미지 키가 섞인 요청은 400
`INVALID_ARGUMENT`로 접힌다 — 에뮬레이터에 실제로 쏴서 확인했다.
<!-- verified: emulators:exec + fetch로 401/400/200 응답 본문 계측 -->

`z.flattenError`가 만드는 `fieldErrors`는 `Record<string, string[]>`라 `AppError`의 세 번째
인자에 그대로 들어간다. 미지 키는 필드가 아니므로 `formErrors`로 간다 — 그래서 `'_'` 키에
따로 담는다.

## 6. 구성 파라미터 (`functions/src/params.ts`)

<!-- file: functions/src/params.ts -->
```ts
import { defineInt, defineSecret, defineString } from 'firebase-functions/params';
import { z } from 'zod';

export const REGION = defineString('TASKS_REGION', { default: 'asia-northeast3' });
export const PAGE_MAX = defineInt('TASKS_PAGE_MAX', { default: 100 });
export const WEBHOOK_KEY = defineSecret('TASKS_WEBHOOK_KEY');

const ConfigSchema = z.strictObject({
  TASKS_PAGE_MAX: z.number().int().min(1).max(1000),
  TASKS_WEBHOOK_KEY: z.string().min(16),
});
export type Config = z.output<typeof ConfigSchema>;

let cached: Config | undefined;

export function config(): Config {
  if (cached) return cached;
  const r = ConfigSchema.safeParse({
    TASKS_PAGE_MAX: PAGE_MAX.value(),
    TASKS_WEBHOOK_KEY: WEBHOOK_KEY.value(),
  });
  if (!r.success) {
    const flat = JSON.stringify(z.flattenError(r.error).fieldErrors);
    throw new Error(`구성이 유효하지 않다: ${flat}`);
  }
  cached = r.data;
  return cached;
}
```

**선언은 모듈 최상위, 호출은 핸들러 안이다.** `defineX`가 최상위에 있어야 배포 매니페스트의
`params` 배열에 실린다 — 선언만으로 실리고, 옵션에 쓰지 않아도 실린다.
<!-- verified: FUNCTIONS_MANIFEST_OUTPUT_PATH로 매니페스트를 뽑아 params 3건 확인 -->

리전처럼 **함수 옵션에 들어가는 값은 `.value()`를 부르지 않고 Param 객체를 그대로 넘긴다.**
그래야 매니페스트에 `"{{ params.TASKS_REGION }}"`이라는 CEL 식으로 실려 배포 시점에 해소된다.

## 7. 부팅 시점 실패 — 최상위 `.value()`가 실제로 하는 일

배포 전 **분석 단계**(`FUNCTIONS_CONTROL_API=true`로 `index.js`를 통째로 import한다)에서
`.value()`가 어떻게 행동하는지는 파라미터 종류마다 다르다.

<!-- verified: firebase-functions@7.3.2 params/types.js:19-26,320-325 대조 + 분석 단계 실행 -->

| 최상위에서 부르면 | 종류 | 실측 결과 |
| --- | --- | --- |
| `WEBHOOK_KEY.value()` | `defineSecret` | **분석 단계가 예외로 죽는다** — `Cannot access the value of secret "TASKS_WEBHOOK_KEY" during function deployment.` 매니페스트가 만들어지지 않는다 |
| `REGION.value()` | `defineString` | **경고만 찍고 `""`를 반환한다.** 선언한 `default`도 무시된다 — `region: [""]`가 매니페스트에 박혀 배포가 성공한다 |
| `PAGE_MAX.value()` | `defineInt` | 같은 경고 뒤 `0` |

```ts
// ❌ 시크릿은 배포를 죽이고, 문자열·정수는 조용히 빈 값으로 배포된다
const key = WEBHOOK_KEY.value();
const region = REGION.value();
```

**조용한 쪽이 더 위험하다.** 시크릿은 배포가 멈추니 즉시 안다. `defineString`은 빈 리전으로
배포까지 끝난다. 그래서 구성 검증을 `config()`로 **핸들러 안에서 인스턴스당 한 번** 돌린다 —
2세대 함수는 실행 사이에 인스턴스를 재사용하므로 첫 호출 이후에는 비용이 없고, 잘못된 구성은
첫 요청에서 `INTERNAL`로 끊긴다. 값을 짧은 시크릿으로 바꿔 실제로 500과
`{"TASKS_WEBHOOK_KEY":["Too small: expected string to have >=16 characters"]}`를 받았다.
<!-- verified: .secret.local을 short로 바꿔 에뮬레이터에 요청 → 500 INTERNAL 계측 -->

## 오용 목록 ① — Zod 3 → Zod 4 관용구 대조표

| 구 습관 (Zod 3) | 현재 형태 (Zod 4) |
| --- | --- |
| `z.object({...}).strict()` | `z.strictObject({...})` |
| `z.object({...}).passthrough()` | `z.looseObject({...})` |
| `err.flatten()` | `z.flattenError(err)` |
| `err.format()` | `z.treeifyError(err)` |
| `z.string().nonempty()` | `z.string().min(1)` |
| `issue.code === 'invalid_enum_value'` | `issue.code === 'invalid_value'` |
| `z.infer<typeof S>`만 쓴다 | 변환이 있으면 `z.output<S>`(출력) / `z.input<S>`(입력)을 가른다 |
| `schema._type`으로 타입을 캔다 | `z.output<S>` — 제네릭 경계는 `S extends z.ZodType` |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `z.strictObject` vs `z.object` | 쓰기 본문은 앞(미지 키 거부), 목록 쿼리는 뒤(잉여 제거) |
| `TaskCreateSchema.partial()` vs 별도 선언 | 기본값이 하나라도 있으면 **반드시 별도 선언** |
| `.optional()` vs `.default()` | 수정 스키마는 앞만. 겹치면 안 보낸 필드가 저장을 덮는다 |
| 최상위 `.value()` vs 핸들러 안 `.value()` | 선언은 최상위, 호출은 핸들러 안. 옵션에 넣을 값은 Param 객체 그대로 |
| `secrets: [WEBHOOK_KEY]` 누락 | 배열에 없으면 런타임 `.value()`가 "No value found for secret" |
| `req.data.ownerId` vs `requireUid(req)` | 소유자는 언제나 뒤. 본문의 `ownerId`는 거부 대상이다 |
| `z.coerce.number()`가 숫자만 받는다 | 아니다. `[7]`→7 · `true`→1 · `' 42 '`→42로 조용히 통과한다 <!-- verified: zod@4.4.3 실행 · z.union으로 좁히면 앞 둘이 거부됨을 대조 --> |
| Security Rules가 막아 준다 | 규칙은 클라이언트 SDK만 막는다. 함수는 admin이라 **이 파일이 유일한 경계**다 |
