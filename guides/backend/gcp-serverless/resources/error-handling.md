<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# 에러 처리 — 던져진 것을 하나로 접고, 상태는 한 표에서만 온다

이 파일이 소유하는 것은 **gRPC 오류를 판별하는 자리**(`src/firestore/errors.ts`)와 **무엇이
던져졌든 `AppError`로 접고 도메인 코드를 HTTP 상태로 바꾸는 표**(`src/http/errors.ts`) 둘이다.
`AppError` 자체와 응답 봉투, `app.onError` 배선은 **이음매가 소유한다**(`src/errors.ts` ·
`src/http/handlers.ts`) — 봉투는 축이 아니라 조합이 정한다. 토큰 검증 실패를 왜 한 부류로
접는지는 `identity-tokens.md`가 소유한다.

**이 축에는 백업이 없다.** 소유권 판정은 애플리케이션 층에만 있고, 에러 응답이 「그 문서는
있지만 네 것이 아니다」를 알려 주는 순간 그 응답 자체가 존재 증명이 된다.

## 1. 무엇이 던져지는가 — 분류와 처리 순서

`toAppError`는 **위에서 아래로** 판정한다. 순서가 계약이다 — `AppError` 검사를 뒤로 미루면
서비스가 의도해서 던진 `NOT_FOUND`가 기본 분기의 `INTERNAL`에 먹힌다.

| 순서 | 던져진 것 | 어디서 오는가 | 접히는 코드 | 상태 |
| --- | --- | --- | --- | --- |
| 1 | `AppError` | 서비스 · 리포지토리 · `verifyIdToken` · `decodeCursor` | **그대로 통과한다** | 표대로 |
| 2 | `ZodError` | 본문·쿼리·커서·문서 재파싱 | `VALIDATION_FAILED` + `fieldErrors` | 422 |
| 3 | gRPC **5** `NOT_FOUND` | Firestore | `NOT_FOUND` | 404 |
| 4 | gRPC **6** `ALREADY_EXISTS` | Firestore | `CONFLICT` | 409 |
| 5 | gRPC **10** `ABORTED` | Firestore (트랜잭션 경합, 재시도 소진) | `CONFLICT` | 409 |
| 6 | gRPC **3** `INVALID_ARGUMENT` | Firestore (문서가 크기 한도 초과 등) | `VALIDATION_FAILED` | 422 |
| 7 | gRPC **9** `FAILED_PRECONDITION` | Firestore (거의 항상 인덱스 누락) | **`INTERNAL`** — 4xx로 접지 않는다 | 500 |
| 8 | 그 밖의 **전부** | 어디서든 | `INTERNAL` | 500 |

**9와 10이 갈리는 이유가 이 표의 요점이다.** 둘 다 인프라 원인이지만 **10은 다시 보내면 되고
9는 배포를 고치기 전까지 영원히 실패한다.** 9를 4xx로 내보내면 클라이언트가 자기 입력을 고치려
들고 인덱스 누락은 아무의 대시보드에도 오르지 않는다. **모르는 것을 통과시키는 기본값은 없다.**

<!-- verified: 에뮬레이터 1.19.8에서 1100 KiB 문서가 gRPC 3 `longer than 1048487 bytes`로 거부됨(C2 관측). 실 GCP 미검증 -->
**3은 9와 정반대다.** 코드 3은 **클라이언트가 보낸 것이 한도를 넘었다**는 뜻이고 — 문서 하나가
1 MiB(1048487바이트)를 넘으면 여기로 온다 — 호출자가 본문을 줄여 고칠 수 있다. 이것을 500으로
접으면 **고칠 수 있는 것을 고칠 수 없는 것으로 오인하게 만든다.**

## 2. gRPC 코드 판별 (`src/firestore/errors.ts`)

이 파일은 **HTTP를 모른다.** 리포지토리(`src/firestore/tasks.ts`)가 부르는데, `http/` 아래에 두면
데이터 계층이 HTTP 모듈을 끌어오고 그 계층의 테스트가 앱을 세워야만 돌게 된다.

<!-- verified: @grpc/grpc-js 1.14.4 build/src/constants.d.ts와 google-gax 5 build/src/status.d.ts 두 열거가 동일 — 5·6·9·10 -->
숫자는 `@grpc/grpc-js`와 `google-gax`의 설치본 열거에서 확인했다 — 두 열거가 같은 값을 준다.
<!-- verified: firestore 9.0.0을 로컬 gRPC 서버에 붙여 Commit이 각 상태를 반환하게 하고 클라이언트가 받은 객체를 계측 -->
그리고 클라이언트가 받는 것은 `GoogleError`가 **아니라** 평범한 `Error`에 `code`·`details`가
붙은 객체였다(`err.constructor.name === 'Error'`) — **`instanceof`로는 판별할 수 없다.**

<!-- file: src/firestore/errors.ts -->
```ts
// src/firestore/errors.ts
// gRPC 상태 코드다. HTTP 상태가 아니다 — 이 파일은 HTTP를 모른다.
const GRPC_INVALID_ARGUMENT = 3;
const GRPC_NOT_FOUND = 5;
const GRPC_ALREADY_EXISTS = 6;
const GRPC_FAILED_PRECONDITION = 9;
const GRPC_ABORTED = 10;

function grpcCode(err: unknown): number | null {
  if (typeof err !== 'object' || err === null) return null;
  const code = (err as { code?: unknown }).code;
  // Node의 시스템 오류도 code를 갖지만 문자열이다 ('ECONNREFUSED'). 숫자만 받는다.
  return typeof code === 'number' ? code : null;
}

export function isInvalidArgument(err: unknown): boolean { return grpcCode(err) === GRPC_INVALID_ARGUMENT; }
export function isNotFound(err: unknown): boolean { return grpcCode(err) === GRPC_NOT_FOUND; }
export function isAlreadyExists(err: unknown): boolean { return grpcCode(err) === GRPC_ALREADY_EXISTS; }
export function isFailedPrecondition(err: unknown): boolean { return grpcCode(err) === GRPC_FAILED_PRECONDITION; }
export function isAborted(err: unknown): boolean { return grpcCode(err) === GRPC_ABORTED; }
```

<!-- verified: 가드를 지운 돌연변이로 8절 테스트를 돌려 초록임을 관측 — === 가 이미 문자열을 거른다 -->
`typeof code === 'number'` 가드는 **이중 방어다** — 지우고 돌려도 초록이었다. `===`가 이미
`'ECONNREFUSED' === 5`를 거짓으로 만든다. 그래도 남긴다: 비교가 `==`로 느슨해지면 `'5' == 5`가
참이 되고, `number | null` 반환 타입이 그 실수를 타입 검사가 보는 자리로 옮긴다.

**메시지 문자열로 판정하지 않는다.**

```ts
// ❌ SDK가 메시지 형식을 바꾸면 조용히 죽는다. 로케일·상세 문구는 계약이 아니다
if (String(err).includes('NOT_FOUND')) return notFound();
// ❌ 이것도 같은 결함이다 — details는 백엔드가 만든 산문이다
if ((err as { details?: string }).details?.startsWith('no entity')) return notFound();
// ✅ 코드는 wire 계약이다
if (isNotFound(err)) return notFound();
```

## 3. `ERROR_STATUS` — 상태가 사는 유일한 자리

도메인 코드에서 HTTP 상태로 가는 표는 **하나뿐이다.** 라우터가 제자리에서 `c.json(…, 404)`를
쓰기 시작하면 같은 코드가 경로마다 다른 상태로 나가고, 그 차이는 아무도 되돌리지 못한다.

| 도메인 코드 | 상태 | 왜 그 값인가 |
| --- | --- | --- |
| `VALIDATION_FAILED` | **422** | 본문은 파싱됐고 필드가 틀렸다. 400은 「JSON이 아니다」와 구분되지 않는데, 클라이언트는 그 둘에 다르게 반응해야 한다 |
| `UNAUTHENTICATED` | **401** | 자격 증명이 없거나 유효하지 않다. `verifyIdToken`의 모든 실패가 여기로 온다 |
| `FORBIDDEN` | **403** | 신원은 확인됐고 **역할·스코프**가 모자란다. 소유권 실패는 여기가 **아니다**(7절) |
| `NOT_FOUND` | **404** | 없거나, 있어도 남의 것이다 — 둘을 구분하지 않는다 |
| `CONFLICT` | **409** | 중복 생성(gRPC 6)과 경합 소진(gRPC 10). 클라이언트가 **다시 보낼 수 있는** 유일한 부류다 |
| `INTERNAL` | **500** | 나머지 전부. 인덱스 누락(gRPC 9)도 여기다 |

**표에 없는 코드는 500이다.** 첨자만 쓰면 오타 난 코드에서 `undefined`가 상태 자리에 들어가고,
그 런타임 오류가 다시 500으로 접혀 **원래 코드가 사라진다.** 그래서 표를 직접 읽지 않고
**`statusFor(code)`만 쓴다** — 이음매도 팩도 예외가 없다(4절).

## 4. `toAppError` (`src/http/errors.ts`)

에러 핸들러가 **가장 먼저** 부르는 함수다. 건너뛴 경로가 하나라도 있으면 그 경로의 봉투만
모양이 달라지고 클라이언트는 두 형식을 파싱해야 한다.

<!-- file: src/http/errors.ts -->
```ts
// src/http/errors.ts
import { ZodError } from 'zod';
import { AppError } from '../errors.js';
import { fieldErrors } from '../schemas/errors.js';
import { isAborted, isAlreadyExists, isFailedPrecondition, isInvalidArgument, isNotFound } from '../firestore/errors.js';
import { log } from '../obs/log.js';

/** 도메인 코드 → HTTP 상태. 유일한 매핑표다. */
export const ERROR_STATUS: Record<string, number> = {
  VALIDATION_FAILED: 422,
  UNAUTHENTICATED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INTERNAL: 500,
};

/** 상태를 얻는 유일한 경로다. 첨자 접근은 정책이 금지한다. */
export function statusFor(code: string): number {
  return ERROR_STATUS[code] ?? 500;
}

export function toAppError(err: unknown): AppError {
  if (err instanceof AppError) return err;

  if (err instanceof ZodError) {
    return new AppError('VALIDATION_FAILED', '입력이 올바르지 않다', fieldErrors(err));
  }

  if (isNotFound(err)) return new AppError('NOT_FOUND', '작업을 찾을 수 없다');
  if (isAlreadyExists(err)) return new AppError('CONFLICT', '이미 존재하는 작업이다');
  if (isAborted(err)) return new AppError('CONFLICT', '경합으로 처리하지 못했다. 다시 시도한다');
  if (isInvalidArgument(err)) return new AppError('VALIDATION_FAILED', '요청이 한도를 넘었다');

  if (isFailedPrecondition(err)) {
    // 거의 항상 복합 인덱스 누락이다 — 배포 결함이지 사용자 입력 문제가 아니다.
    // 진단은 로그에만 남기고 응답은 500으로 접는다.
    log('error', 'firestore failed precondition', { grpcCode: 9 });
    return new AppError('INTERNAL', '요청을 처리하지 못했다');
  }

  log('error', 'unhandled error', { kind: err instanceof Error ? err.name : typeof err });
  return new AppError('INTERNAL', '요청을 처리하지 못했다');
}
```

`AppError`는 이음매가 `src/errors.ts`에 정의하고, `installErrorHandlers`는 `toAppError(err)`로
정규화한 뒤 **`statusFor(appErr.code)`로 상태를 정한다 — 이것이 상태를 얻는 유일한 경로이고
`ERROR_STATUS` 첨자 접근은 `?? 500`을 붙였더라도 정책이 금지한다.** 표를 여는 순간 그 자리가
새 매핑의 출발점이 된다. **팩은 상태를 응답에 쓰지 않는다** — 봉투가 조합의 함수이기 때문이다.

## 5. 원본 메시지를 응답에 싣지 않는다

8번 줄이 `err.message`를 옮기지 않는 이유는 **원본이 우리가 고르지 않은 문자열**이기 때문이다.

<!-- verified: 로컬 gRPC 서버가 details를 반환하게 하고 클라이언트의 err.message를 계측 — SDK가 "<코드> <이름>: " 접두만 붙이고 백엔드 문자열을 그대로 잇는다 -->
- Firestore SDK는 백엔드가 준 `details`를 **가공 없이** `err.message`에 잇는다
<!-- verified: 에뮬레이터가 보낸 details에 프로젝트 식별자(`dev~demo-tasks`)와 문서 경로가 그대로 들어 있음을 관측(C2). 실 GCP 백엔드의 문구는 미검증 -->
- 그 문구에는 **프로젝트 식별자와 문서 경로가 그대로 들어 있다** — 에뮬레이터에서 관측했다
<!-- verified: zod 4.4.3에서 ZodError.message가 issues 배열의 JSON 덤프임을 관측 -->
- `ZodError.message`는 **issue 배열 전체의 JSON 덤프**다. 그대로 실으면 스키마 내부 구조가
  통째로 나가고, 클라이언트가 파싱할 형식이 둘이 된다

`INTERNAL`의 메시지는 **고정 문자열**이다. 진단은 `log`로 남기되 토큰·문서 전문·이메일은 싣지
않는다 — 로그도 유출 경로다.

## 6. zod 오류 정규화 — `path`가 비는 자리가 있다

`fieldErrors`는 `src/schemas/errors.ts`가 소유한다(`input-validation.md`) — 이 파일은 부르기만 한다.

| 무엇이 틀렸나 | 관측된 `issue.path` | `fieldErrors`의 키 |
| --- | --- | --- |
| `title`이 빈 문자열 | `['title']` | `title` <!-- verified: zod 4.4.3에 빈 문자열을 태워 관측 --> |
| 배열 항목 안의 필드 | `['items', 0, 'title']` | `items.0.title` — **인덱스를 지우지 않는다** <!-- verified: zod 4.4.3의 issue.path를 직접 출력 --> |
| `.strict()`가 미지 키를 거부 | **`[]` (빈 배열)** | 붙일 필드가 없다 <!-- verified: zod 4.4.3의 unrecognized_keys issue에서 path가 빈 배열임을 관측 --> |

마지막 줄이 함정이다. zod 4의 `unrecognized_keys` issue는 **어느 필드가 문제인지를 `path`에
담지 않는다**(문제는 객체 전체다). 필드 맵만 보는 폼은 그 오류를 못 붙이고 사용자는 「저장이
안 되는데 빨간 글씨가 없는」 상태에 빠진다 — `fieldErrors` 외에 **객체 수준 메시지**가 필요하다.

<!-- verified: zod 4.4.3에서 'errors' in err === false 를 관측 -->
`ZodError`는 **`.issues`만 갖는다.** zod 3의 `.errors`는 없어졌고, 접근하면 `undefined`다 —
타입 검사가 잡아 주지만 `any`를 거친 경로에서는 런타임까지 살아 나간다.

## 7. 존재를 누설하지 않는다

**남의 문서를 만졌을 때 `FORBIDDEN`을 주면 그 응답이 곧 「그 문서는 있다」는 확인이다.**
이 축에는 정책 엔진이 없다 — `firestore.rules`는 전면 거부이고 서버는 서비스 계정으로 붙어
규칙을 우회하므로, 여기서 새는 정보를 뒤에서 막아 주는 층이 없다.

| 요청 | 실제 상황 | 응답 |
| --- | --- | --- |
| `GET /api/tasks/{id}` | 그런 문서가 없다 | **404** |
| `GET /api/tasks/{id}` | 있지만 `ownerId`가 다르다 | **404** — 위와 **완전히 같은 봉투** |
| `PATCH` · `DELETE` | 있지만 `ownerId`가 다르다 | **404** (`AppError('NOT_FOUND', …)`) |
| 어느 것이든 | 토큰이 없거나 유효하지 않다 | **401** |
| 인증은 됐고 역할이 모자라다 | 관리자 전용 경로 등 | **403** — 소유권이 아니라 **역할** 판정이다 |

`FORBIDDEN`이 코드표에 있는 이유는 셋째 줄이 아니라 **마지막 줄** 때문이다 — 역할은 리소스의
존재와 무관하므로 403이 아무것도 누설하지 않는다. **메시지도 같아야 한다**: 상태를 맞춰 놓고
본문 문구로 다시 알려 주면 접은 것이 아니다.

## 8. 차단을 증명한다 (`test/errors.test.ts`)

**부정 단언만 있는 테스트는 차단 장치가 아니다** — `toAppError`를 통째로 `NOT_FOUND` 반환으로
바꿔도 「5는 NOT_FOUND가 된다」는 초록이다. 같은 `it` 안에 **접히면 안 되는 것이 접히지 않는지**를 짝으로 건다.

<!-- file: test/errors.test.ts -->
```ts
// test/errors.test.ts
import { describe, expect, it } from 'vitest';
import { statusFor, toAppError } from '../src/http/errors.js';
import { isNotFound } from '../src/firestore/errors.js';

// 관측된 형태를 그대로 흉내 낸 픽스처다: code는 number, details는 백엔드 문자열,
// message는 "<코드> <이름>: <details>". 이 형태의 근거는 2절의 계측이다.
const grpcErr = (code: number, name: string, details: string) =>
  Object.assign(new Error(`${code} ${name}: ${details}`), { code, details });

describe('toAppError', () => {
  it('gRPC 5만 NOT_FOUND로 접는다 — 문자열 code는 접지 않는다', () => {
    expect(toAppError(grpcErr(5, 'NOT_FOUND', 'no entity to update')).code).toBe('NOT_FOUND');
    // ✅ 긍정 짝이 없으면 「전부 NOT_FOUND」인 구현도 통과한다
    const sys = Object.assign(new Error('connect ECONNREFUSED'), { code: 'ECONNREFUSED' });
    expect(isNotFound(sys)).toBe(false);
    expect(toAppError(sys).code).toBe('INTERNAL');
    // 비교가 == 로 느슨해지면 이 줄이 빨개진다
    expect(isNotFound({ code: '5' })).toBe(false);
  });

  it('9만 5xx로 남고 10·3은 4xx로 접힌다', () => {
    expect(statusFor(toAppError(grpcErr(9, 'FAILED_PRECONDITION', 'index')).code)).toBe(500);
    // ✅ 대조군 둘: 10은 재시도로, 3은 본문을 줄여서 호출자가 고칠 수 있다
    expect(statusFor(toAppError(grpcErr(10, 'ABORTED', 'contention')).code)).toBe(409);
    expect(statusFor(toAppError(grpcErr(3, 'INVALID_ARGUMENT', 'longer than 1048487 bytes')).code)).toBe(422);
  });

  it('원본 문자열이 응답 메시지로 새지 않는다', () => {
    const appErr = toAppError(grpcErr(13, 'INTERNAL', 'app: "s~acme-prod-42" path <tasks/x>'));
    // ✅ 긍정 짝: 메시지가 비어 있으면 아래 not.toContain은 무의미하다
    expect(appErr.message.length).toBeGreaterThan(0);
    expect(appErr.message).not.toContain('acme-prod-42');
    expect(statusFor('NO_SUCH_CODE')).toBe(500);
  });
});
```

<!-- verified: 돌연변이 5종을 심고 vitest로 실행 — 4종에서 빨개졌다(살아남은 하나는 2절) -->
실측: 돌연변이를 심어 **차단을 확인했다** — 전부 `NOT_FOUND` 반환(2 실패) · 9를 4xx로 접음(1) ·
`INTERNAL`이 원본 메시지 전달(1) · `===`를 `==`로 느슨하게(1)에서 빨개졌다.
<!-- verified: firestore 9.0.0 + 로컬 gRPC 서버에서 runTransaction의 Commit이 ABORTED를 받게 하고 서버가 센 호출 수와 경과 시간을 계측 -->
gRPC 10이 여기까지 온다는 것은 SDK가 **Commit을 5회 재시도하고 12.3초를 쓴 뒤**였다 — 이미
재시도가 소진된 예외이므로 애플리케이션이 다시 감싸 재시도하지 않는다.

## 오용 목록 ① — 구 관용구 → 현재 형태 대조표

| 구 습관 | 현재 형태 (이 축) |
| --- | --- |
| `err instanceof GoogleError`로 판별 | 통하지 않는다 — 실측에서 받은 것은 평범한 `Error`였다. `typeof err.code === 'number'`로 좁힌다 |
| `err.message.includes('NOT_FOUND')` | `isNotFound(err)` — 메시지는 계약이 아니다 |
| `err.code === 'not-found'`(firebase-admin 문자열 코드) | 숫자 `5`다. 이 축은 `@google-cloud/firestore`로 붙는다 |
| zod 3의 `err.errors` | `err.issues` — zod 4에서 `.errors`는 사라졌다 <!-- verified: zod 4.4.3에서 'errors' in err === false --> |
| 라우터마다 `c.json({...}, 404)` | `AppError` 하나만 던진다. 상태는 `statusFor`가 정한다 |
| `catch (e) { return c.json({ error: e.message }) }` | `toAppError(e)` — 원본 문자열은 우리 것이 아니다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| gRPC 코드 vs HTTP 상태 | 둘 다 정수라 섞인다. `5`는 NOT_FOUND이지 `500`이 아니다 |
| gRPC **9** vs gRPC **10** | 9는 고칠 때까지 영원히 실패한다(500) · 10은 다시 보내면 된다(409) |
| `FORBIDDEN` vs `NOT_FOUND` | 소유권 실패는 404. 403은 **역할** 판정에만 쓴다 |
| `ERROR_STATUS[code]` vs `statusFor(code)` | 표는 직접 열지 않는다. 첨자는 `?? 500`을 붙여도 금지다 |
| `src/firestore/errors.ts` vs `src/http/errors.ts` | 앞은 HTTP를 모른다. 리포지토리가 부르는 것은 앞뿐이다 |
| `VALIDATION_FAILED`(422) vs 파싱 실패(400) | 본문이 JSON이 아니면 스키마에 닿지도 못한다 — 다른 사건이다 |
