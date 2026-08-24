<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# 에러 처리 — 모든 실패를 하나의 표로 모은다

도메인 코드 → HTTP 상태 매핑표(`ERROR_STATUS`) · DynamoDB 예외 판별 · `ZodError` 정규화를
`src/http/errors.ts` 한 파일로 소유한다. `AppError`와 봉투를 만드는 `respond`는 **이음매**가
(`src/http/app-error.ts` · `src/http/respond.ts`) 소유하고 여기서는 소비만 한다. 요청 로깅과
미처리 예외 포착은 `resources/handler-patterns.md`, 조건식을 거는 자리는
`resources/data-access.md`다.

## 1. 어느 코드로 내보낼지 판단한다

**실패의 출처가 코드를 정한다.** 같은 예외가 자리에 따라 다른 코드가 되므로(§4) 판단은
"무엇이 실패했는가"가 아니라 "**무엇을 요구했는가**"에서 시작한다.

| 실패 | 도메인 코드 | 상태 | 재시도 |
| --- | --- | --- | --- |
| 스키마·형식이 틀렸다 | `VALIDATION_FAILED` | 400 | 아니다 |
| 토큰이 없거나 검증에 실패했다 | `UNAUTHENTICATED` | 401 | 아니다 |
| 주체는 맞지만 역할이 모자란다 | `FORBIDDEN` | 403 | 아니다 |
| 내 소유 아이템이 없다 · **남의 아이템이다** | `NOT_FOUND` | 404 | 아니다 |
| 이미 있는 것을 또 만들려 했다 | `CONFLICT` | 409 | 아니다 |
| DynamoDB가 스로틀했다 | `THROTTLED` | 429 | **그렇다** |
| 그 밖의 전부 | `INTERNAL` | 500 | 호출자 판단 |

표에서 읽어야 할 것 셋. **`FORBIDDEN`은 역할 부족에만 쓴다** — 남의 아이템에 403으로
답하면 미인가 사용자가 id를 훑어 리소스 존재를 열거한다. **`THROTTLED`만 재시도 대상이다**
— API Gateway는 Lambda를 재시도하지 않으므로 429를 받은 클라이언트가 다시 보내는 것이
유일한 복구 경로다. **`INTERNAL`의 메시지는 고정 문구**이고 원인은 로그에만 남긴다.

## 2. 단일 매핑표와 정규화 (`src/http/errors.ts`)

<!-- file: src/http/errors.ts -->
```ts
// src/http/errors.ts
import { z } from 'zod';
import { AppError } from './app-error';

export const ERROR_STATUS: Record<string, number> = {
  VALIDATION_FAILED: 400,
  UNAUTHENTICATED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  THROTTLED: 429,
  INTERNAL: 500,
};

const THROTTLE_NAMES = new Set([
  'ProvisionedThroughputExceededException',
  'RequestLimitExceeded',
  'ThrottlingException',
]);

function awsName(e: unknown): string | undefined {
  const n = (e as { name?: unknown } | null)?.name;
  return typeof n === 'string' ? n : undefined;
}

function awsStatus(e: unknown): number | undefined {
  const s = (e as { $metadata?: { httpStatusCode?: unknown } } | null)?.$metadata?.httpStatusCode;
  return typeof s === 'number' ? s : undefined;
}

function cancellationCodes(e: unknown): string[] {
  const r = (e as { CancellationReasons?: unknown } | null)?.CancellationReasons;
  if (!Array.isArray(r)) return [];
  return r.map((x) => (x as { Code?: unknown })?.Code).filter((c): c is string => typeof c === 'string');
}

export function isConditionalCheckFailed(e: unknown): boolean {
  if (awsName(e) === 'ConditionalCheckFailedException') return true;
  return awsName(e) === 'TransactionCanceledException' && cancellationCodes(e).includes('ConditionalCheckFailed');
}

export function isThroughputExceeded(e: unknown): boolean {
  const n = awsName(e);
  return (n !== undefined && THROTTLE_NAMES.has(n)) || awsStatus(e) === 429;
}

export function isInvalidRequest(e: unknown): boolean {
  return awsName(e) === 'ValidationException';
}

export function fieldErrors(e: z.ZodError): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  const push = (k: string, m: string) => { (out[k] ??= []).push(m); };
  for (const issue of e.issues) {
    if (issue.code === 'unrecognized_keys') {
      for (const k of issue.keys) push(k, '허용되지 않는 필드다');
      continue;
    }
    push(issue.path.length > 0 ? issue.path.map(String).join('.') : '_', issue.message);
  }
  return out;
}

export function toAppError(e: unknown): AppError {
  if (e instanceof AppError) return e;
  if (e instanceof z.ZodError) {
    return new AppError('VALIDATION_FAILED', '요청이 스키마와 맞지 않는다', fieldErrors(e));
  }
  if (isConditionalCheckFailed(e)) {
    return new AppError('CONFLICT', '리소스 상태가 조건과 맞지 않는다');
  }
  if (isThroughputExceeded(e)) {
    return new AppError('THROTTLED', '잠시 후 다시 시도한다');
  }
  if (isInvalidRequest(e)) {
    return new AppError('VALIDATION_FAILED', '요청 형태가 올바르지 않다');
  }
  return new AppError('INTERNAL', '요청을 처리하지 못했다');
}
```

**`ValidationException`은 500이 아니라 400이다.** 요청이 DynamoDB의 문법·제약과 맞지
않을 때 오고, **평범한 클라이언트 오용이 이 부류다** — 다른 인덱스에서 받은 커서를 다시
보내면 `The provided starting key does not match the range key predicate`가 온다
<!-- verified: DynamoDB Local 3.3.1 실행. resources/data-access.md §5의 같은 벡터 -->.
매핑이 없으면 페이지 넘김의 흔한 실수가 5xx로 나가 경보를 울린다. **대가**: 같은 이름이
코드 결함(잘못 조립한 `UpdateExpression`)에서도 오고 400은 경보를 울리지 않는다. 그래서
클라이언트 유래는 **앱 계층에서 먼저 거부한다**(커서 재고정 검사) — 어댑터에 도달한
`ValidationException`이 늘면 읽을 곳은 로그가 아니라 그 검사다.

**`toAppError`의 마지막 줄이 이 파일의 존재 이유다.** 알 수 없는 값은 전부 `INTERNAL`로
접힌다 — `catch (e)`가 받는 것은 `unknown`이고 문자열도 `undefined`도 올 수 있다.
`e.message`를 그대로 내보내면 테이블 이름·ARN·쿼리 조각이 클라이언트로 새어 나간다.

이 파일은 `@aws-sdk/*`를 import하지 않는다. `name` 문자열만 보므로 `src/http/`가
데이터 계층에 의존하지 않고, 번들에 SDK가 한 번 더 끌려오지도 않는다.

## 3. DynamoDB 예외는 `name`으로 가른다

SDK v3의 예외는 `name`·`$metadata`·`__type`을 갖는다. DynamoDB Local 3.3.1에 실제 조건부
쓰기를 던져 받은 객체가 이렇다 <!-- verified: DynamoDB Local 3.3.1 + @aws-sdk/lib-dynamodb 3.1116.0 실행, 객체 덤프 -->.

| 필드 | 값 | 쓸 수 있는가 |
| --- | --- | --- |
| `name` | `'ConditionalCheckFailedException'` | **판별 근거로 쓴다** |
| `__type` | `'com.amazonaws.dynamodb.v20120810#ConditionalCheckFailedException'` | 내부 필드다. 손으로 만든 객체에는 없다 |
| `$metadata.httpStatusCode` | `400` | 스로틀(429) 판별의 보조 근거 |
| `$fault` | `'client'` | 재시도 판단에 쓰지 않는다 |
| `code` | `undefined` — **v2 관용구다** | 쓰면 항상 `false`가 된다 |

스로틀 이름 세 개는 SDK 자신의 재시도 분류기가 쓰는 목록이다(`@smithy/core`의
`THROTTLING_ERROR_CODES`). 같은 파일의 `isThrottlingError`가 `$metadata.httpStatusCode === 429`도
함께 보므로 `isThroughputExceeded`도 그 조건을 넣었다
<!-- verified: @smithy/core dist-es/submodules/retry/service-error-classification/constants.js:10-25 및 service-error-classification.js:19-21 대조 -->.
**다만 스로틀은 실물로 확인하지 못했다** — DynamoDB Local은 스로틀하지 않으므로 이름
목록은 위 SDK 소스 대조로만 뒷받침된다.

`instanceof ConditionalCheckFailedException`은 **SDK가 만든 예외에 대해서만** 같은 판정을
준다. `[Symbol.hasInstance]`가 이름 비교로 떨어지기 전에 `ServiceException.isInstance`를
먼저 부르고, 그것은 프로토타입 체인이 아니면 **`$fault`와 `$metadata`가 둘 다 있고
`$fault`가 `'client'`나 `'server'`일 것**을 요구하기 때문이다
<!-- verified: @smithy/smithy-client 4.4.5 dist-es/exceptions.js:9-31 직접 대조 -->.
그래서 `{ name: 'ConditionalCheckFailedException' }`처럼 **이름만 있는 객체는
`instanceof`에서 false**다 — §6의 테스트가 쓰는 것이 정확히 그 객체다. `name` 문자열만
보는 쪽이 두 형태 모두에서 같은 답을 내고, 덤으로 SDK를 import하지 않아도 된다.

## 4. 같은 예외가 409도 되고 404도 된다

`ConditionalCheckFailedException`은 "조건식이 거짓이었다"만 말한다. **어떤 조건을 걸었는지는
호출부만 알므로** 변환은 데이터 계층에서 한다.

| 호출 | 조건식 | 실패의 뜻 | 던질 것 |
| --- | --- | --- | --- |
| `putTask` | `attribute_not_exists(pk)` | 이미 있다 | `AppError('CONFLICT', …)` |
| `updateTask` | `attribute_exists(pk)` | 내 파티션에 없다 | `AppError('NOT_FOUND', …)` |
| `deleteTask` | `attribute_exists(pk)` | 내 파티션에 없다 | `AppError('NOT_FOUND', …)` |

```ts
// src/db/tasks.ts — 호출부가 뜻을 붙인다
try {
  await ddb.send(new DeleteCommand({ TableName: TABLE, Key: keys.task(ownerId, id),
    ConditionExpression: 'attribute_exists(pk)' }));
} catch (e) {
  if (isConditionalCheckFailed(e)) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
  throw e;
}
```

세 호출 모두 실물에서 `isConditionalCheckFailed(e) === true`를 받았고 변환을 거치면
409·404·404로 갈라진다 <!-- verified: DynamoDB Local 3.3.1에 put/update/delete 3종 조건부 쓰기 실행 -->.
변환을 빠뜨리면 `toAppError`가 전부 409로 접는다 — 그 409는 "배선이 빠졌다"는 신호다.

**소유자가 파티션 키에 있으므로 조건 실패는 남의 아이템 존재를 말해 주지 않는다.**
`keys.task(ownerId, id)`는 그 소유자의 파티션만 가리키니 남의 것을 지우려는 요청은
"없다"에서 멈춘다. 404가 존재 은닉과 사실 진술을 동시에 만족하는 것은 **키 설계 덕이지
응답 코드를 골라서가 아니다** — 소유자를 `FilterExpression`으로 걸면 이 성질이 무너진다.

**트랜잭션 안의 조건 실패는 이름이 다르다.** 취소되면 `TransactionCanceledException`이 오고
사유는 `CancellationReasons[i].Code`에 있다 — 실측값
`[{"Code":"ConditionalCheckFailed"},{"Code":"None"}]`
<!-- verified: DynamoDB Local 3.3.1에 TransactWriteCommand 실행, 에러 덤프 -->.
이름만 보는 판별기는 이것을 놓쳐 500을 낸다. §2의 `cancellationCodes`가 그 자리다.

## 5. `ZodError` → 필드 오류 봉투

`fieldErrors`는 `issue.path`를 점으로 이어 키로 쓰고, `unrecognized_keys`는 경로가 비어
있으므로 `issue.keys`의 이름들로 편다. 경로가 없는 나머지는 `_`로 모은다.

| 입력 | `fieldErrors` 결과 |
| --- | --- |
| `{"title":123}` | `{"title":["Invalid input: expected string, received number"]}` |
| `{"title":"a","zzz":1}` | `{"zzz":["허용되지 않는 필드다"]}` |
| `[1,2]` | `{"_":["Invalid input: expected object, received array"]}` |
| `{items:[{t:1},{t:2}]}` | `{"items.0.t":[…],"items.1.t":[…]}` — 인덱스가 남는다 |

마지막 행이 `z.flattenError(e).fieldErrors`를 쓰지 않는 이유다 — 그쪽은 같은 입력을
`{"items":[…,…]}`로 접어 **몇 번째 항목이 틀렸는지를 지우고**, 최상위 오류를 별도
`formErrors`에 두므로 `fieldErrors`만 쓰면 미지 키 오류가 통째로 사라진다
<!-- verified: zod 4.4.3에서 두 함수 출력 대조. flattenError 출력에 formErrors 존재 -->.

**봉투에 요청 값을 싣지 않는다.** Zod 4의 기본 메시지는 타입·한계만 말한다 — 300자짜리
비밀 문자열을 `title`(`max(200)`)로 보내도 메시지는
`Too big: expected string to have <=200 characters`였고 입력값은 어디에도 없었다
<!-- verified: zod 4.4.3, TaskCreateSchema와 같은 형태로 실행 -->. 다만 `z.strictObject`의
미지 키 오류는 **보낸 키 이름을 그대로 되돌려준다** — 값이 아니라 이름이지만, 직접 만든
메시지에 입력값을 넣기 시작하면 이 성질이 깨진다.

## 6. 로깅과 응답 — 새는 곳을 하나로 줄인다

핸들러는 봉투를 직접 만들지 않는다. `respond.fail`이 `toAppError`로 정규화한 뒤
`ERROR_STATUS`에서 상태를 읽는 유일한 자리다.

```ts
// src/handlers/tasks-delete.ts
export const handler = withContext(async (event) => {
  try {
    const user = requireAuth(event);
    await deleteTask(user.id, pathParam(event, 'id'));
    return respond(null, { status: 204 });
  } catch (e) {
    return respond.fail(e);
  }
});
```

로그에는 원인을, 응답에는 코드를 보낸다. 상태가 500일 때만 원본을 실어 CloudWatch에서
질의 가능한 형태로 남긴다 — 400·404를 전부 error로 찍으면 경보가 사용자 오타에 울린다.

```ts
// src/http/respond.ts — 이음매가 소유한다. 로깅 위치만 보인다
const app = toAppError(e);
const status = ERROR_STATUS[app.code] ?? 500;
if (status >= 500) logger.error('unhandled', { code: app.code, err: e });
else logger.warn('rejected', { code: app.code });
```

테스트는 **긍정과 부정을 같은 `it` 안에** 건다. `expect(404)`만 걸린 테스트는 쿼리를
통째로 `return null`로 바꿔도 초록이다 — 전부 404이기 때문이다.

```ts
// test/errors.test.ts
it('조건 실패는 뜻에 따라 갈리고, 모르는 것은 접힌다', () => {
  expect(toAppError({ name: 'ConditionalCheckFailedException' }).code).toBe('CONFLICT'); // ✅ 긍정
  expect(toAppError(new AppError('NOT_FOUND', 'x')).code).toBe('NOT_FOUND');             // ✅ 통과
  expect(toAppError({ name: 'ValidationException' }).code).toBe('VALIDATION_FAILED');    // ✅ 긍정
  expect(toAppError({ name: 'ResourceNotFoundException' }).code).toBe('INTERNAL');       // ✅ 접힘
  expect(toAppError(new Error('table arn secret')).message).not.toContain('arn');        // ✅ 부정
});
```

## 오용 목록 ① — Express + SDK v2 관용구 → Lambda + SDK v3 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `app.use((err, req, res, next) => …)` 에러 미들웨어 | 미들웨어 체인이 없다. 핸들러가 `try/catch`로 `respond.fail(e)`를 부른다 |
| `err.code === 'ConditionalCheckFailedException'` (v2) | `err.name`이다. v3 예외에 `code`는 없다 <!-- verified: 실물 에러 덤프에 code 없음 --> |
| `err.statusCode` | `err.$metadata.httpStatusCode` <!-- verified: 실물 에러 덤프 --> |
| `err.retryable` | `err.$retryable` — 조건 실패에는 `undefined`다 <!-- verified: 실물 에러 덤프 --> |
| `AWS.DynamoDB.DocumentClient` 콜백/`.promise()` | `ddb.send(new PutCommand(…))`가 Promise를 돌려준다 |
| `res.status(500).json({ error: err.message })` | `respond.fail(e)` 하나로 모은다. 원본 메시지는 로그에만 |
| `error.errors` 로 Zod 오류를 순회 | `error.issues`다. `error.errors`는 `undefined` <!-- verified: zod 4.4.3 실행 --> |
| `error.flatten().fieldErrors` 를 그대로 봉투에 | `formErrors`가 버려진다 — 미지 키 오류가 사라진다 (5절) |
| `process.exit(1)` 로 치명적 오류 처리 | 모듈 최상위에서 `throw` — 초기화 실패로 함수가 뜨지 않는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `CONFLICT`(409) vs `NOT_FOUND`(404) | 조건식이 `attribute_not_exists`면 409, `attribute_exists`면 404 (4절) |
| `ConditionalCheckFailedException` vs `TransactionCanceledException` | 트랜잭션 안의 조건 실패는 후자다. 사유는 `CancellationReasons[].Code` |
| `ResourceNotFoundException` vs `NOT_FOUND` | 전자는 **테이블이 없다**는 뜻 — 배포 오류이므로 500이다 |
| `$fault === 'client'` vs 재시도 가능 | 조건 실패도 `client`다. 재시도 판단은 `THROTTLE_NAMES`·429로 한다 |
| `toAppError` vs `catch`에서 직접 분기 | 도메인 뜻이 있으면 호출부에서 `AppError`로 바꾼다. `toAppError`는 최후 정규화다 |
| `z.flattenError` vs `z.treeifyError` | 평평한 봉투에는 앞, 중첩 구조를 그대로 보낼 때는 뒤. 배열 인덱스는 앞이 지운다 |
| `z.prettifyError` 를 응답에 | 사람이 읽는 여러 줄 문자열이다. 부팅 로그용이고 봉투에는 `fieldErrors`를 쓴다 |
| `logger.error` vs `logger.warn` | 500만 error. 400·404를 error로 찍으면 경보가 사용자 오타에 울린다 |
| `AppError(code, message)` 인자 순서 | 뒤 두 인자가 모두 `string`이라 바꿔 써도 컴파일된다 — 코드가 먼저다 |
