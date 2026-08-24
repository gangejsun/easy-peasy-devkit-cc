<!-- epcc-pack: backend/firebase v3.14.0 -->
# 함수 패턴 — 2세대 `onCall` · `onRequest` 와 인증 컨텍스트

이 파일은 `functions/src/obs/logger.ts` 와 `functions/src/index.ts` 를 소유한다. Firestore
접근(`db` · `listTasks` · `runTransaction`)은 `functions/src/firestore/` —
`resources/data-access.md` 가 소유한다. Zod 스키마와 `parseCallable` 은
`functions/src/schemas/task.ts`, `defineString`/`defineSecret` 파라미터는
`functions/src/params.ts` 로 둘 다 `resources/input-validation.md` 의 몫이다.
`AppError` · `toHttpsError` · `AuthUser` · `authFor` 는 이음매가
`functions/src/http/` 에서 소유한다 — 팩은 부르기만 한다.

**`onCall` 은 토큰을 검증하지만 토큰이 없는 호출을 막지는 않는다.** 핸들러는 그대로
돌고 `request.auth` 만 비어 있다. 주체를 확인하는 것은 `requireUid` 다.

## 1. 결정 트리 — `onCall` 인가 `onRequest` 인가

| 봉투 | `onCall` | `onRequest` |
| --- | --- | --- |
| 요청 본문 | `{ "data": ... }` 로 감싸야 한다 (아니면 400 `INVALID_ARGUMENT`) | 날것 그대로 |
| 성공 응답 | `{ "result": ... }` | 핸들러가 쓰는 것 그대로 |
| 인증 | `Authorization: Bearer <ID 토큰>` 을 SDK 가 검증해 `request.auth` 로 넣는다 | 아무 것도 하지 않는다 — 헤더가 날것으로 온다 |
| 미처리 예외 | 500 `{"error":{"message":"INTERNAL","status":"INTERNAL"}}` — 메시지를 접는다 | 500 `Internal Server Error` (평문) |
| 메서드 | POST 만 (GET 은 400) | 전부 |
| CORS | 기본이 **모든 origin 허용** | `cors` 옵션대로 |

<!-- verified: 함수 에뮬레이터에 실제 호출 — 위 표의 상태 코드·본문은 curl/fetch 응답 원문이다. 미처리 예외의 메시지에 넣어 둔 표식 문자열이 응답에 나타나지 않는 것을 확인했고, 같은 경로로 HttpsError 의 메시지는 그대로 도착하는 것을 대조군으로 확인했다 -->
**프론트가 Firebase 클라이언트 SDK 를 쓰면 `onCall`**, 웹훅·서드파티 콜백처럼 봉투를
정할 수 없는 상대가 부르면 `onRequest` 다. 그 선택과 와이어 봉투는 조합의 몫이라
이음매의 `api-endpoints` 슬롯이 확정한다.

## 2. 인증 컨텍스트 — 없을 때는 `null` 이 아니라 `undefined` 다

| 호출 | `request.auth` | 결과 |
| --- | --- | --- |
| 토큰 없음 | `undefined` | 핸들러가 **그대로 돈다**, 200 |
| 유효한 ID 토큰 | `{ uid, token }` | `token` 에 커스텀 클레임이 평평하게 얹힌다 (`role` · `roles`) |
| 검증 불가 토큰 (실서비스) | 핸들러가 아예 돌지 않는다 | 401 `{"error":{"message":"Unauthenticated","status":"UNAUTHENTICATED"}}` |
| JWT 형태가 **아닌** 토큰 (에뮬레이터) | 핸들러가 돌지 않는다 | 401 — 양성 대조군 |
| **JWT 형태 위조 토큰** (에뮬레이터) | `uid` 가 **페이로드에 적힌 값** · 클레임도 원문 그대로 | **200** |

<!-- verified: 1·2·3행과 5행은 같은 위조 토큰 바이트를 두 곳에 보내 잰 값이다 — firebase-functions 7.3.2 핸들러를 에뮬레이터 밖 express 에 직접 물리면 401 `Auth token was rejected`(verifications.auth=INVALID), 같은 바이트를 함수 에뮬레이터로 보내면 200 이었다. 4행이 양성 대조군이다(에뮬레이터도 JWT 형태가 아니면 401). Auth 에뮬레이터로 진짜 사용자를 만들어 커스텀 클레임을 붙인 진짜 토큰과 대조했다 -->
`requireUid` 가 `req.auth` 가 아니라 **`req.auth?.uid`** 를 보는 이유는 3행 때문이다.
**그러나 `req.auth?.uid` 는 5행을 막지 못한다** — 위조 토큰에는 `uid` 가 멀쩡히 들어 있다.
서명 검증은 런타임의 몫이고 **에뮬레이터는 그것을 하지 않는다.**

**그러므로 에뮬레이터에서 초록인 것이 인증이 된다는 뜻이 아니다.** 실측에서 서명이
쓰레기인 위조 토큰으로 `tasksCreate` 를 불렀더니 200 과 함께 `ownerId: "hacker"` 문서가
Firestore 에 **실제로 저장됐다** — 공격자가 `uid` 를 고른 것이다. 같은 바이트를 실서비스
코드 경로에 보내면 401 이므로 이것은 **에뮬레이터 한정 갈림**이지만, 결과적으로
**에뮬레이터로 도는 테스트는 소유권 경계를 증명하지 못한다.** 그 테스트가 증명하는 것은
「주어진 `uid` 에 대해 쿼리가 옳게 좁혀지는가」까지이고, 「그 `uid` 가 진짜인가」는
증명 범위 밖이다. 뽑은 `uid` 는 그대로 쿼리 경계로 내려간다 — admin SDK 는 규칙을
우회하므로 이 한 줄이 문서 접근의 유일한 경계다.

```ts
// functions/src/firestore/tasks.ts — 경계가 닫히는 자리
let query: Query<TaskDoc> = col().where('ownerId', '==', ownerId);
```

## 3. 래퍼와 에러 봉투 (`functions/src/obs/logger.ts`)

`onCall` 은 미처리 예외를 `INTERNAL` 로 접어 준다. 안전하지만 **원인도 함께 사라지므로**
접히기 전에 로깅하는 자리가 필요하다.

<!-- file: functions/src/obs/logger.ts -->
```ts
// functions/src/obs/logger.ts
import * as fnLogger from 'firebase-functions/logger';
import type { CallableRequest } from 'firebase-functions/v2/https';
import { AppError } from '../http/app-error.js';
import { toHttpsError } from '../http/https.js';

export const logger = fnLogger;

export function requireUid(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new AppError('UNAUTHENTICATED', 'sign-in required');
  return uid;
}

export function withErrors<T>(
  h: (req: CallableRequest) => Promise<T>,
): (req: CallableRequest) => Promise<T> {
  return async (req) => {
    try {
      return await h(req);
    } catch (e) {
      if (e instanceof AppError) throw toHttpsError(e);
      logger.error('unhandled handler failure', {
        uid: req.auth?.uid ?? null,
        err: e instanceof Error ? e.message : String(e),
      });
      throw toHttpsError(new AppError('INTERNAL', 'internal error'));
    }
  };
}
```

`console.log` 를 쓰지 않는 이유는 취향이 아니다. `logger` 의 두 번째 인자는 구조적
필드로 실려 Cloud Logging 에서 질의할 수 있지만, `console.log` 는 한 줄 문자열로
뭉개져 `uid` 로 걸러낼 수 없다.

`HttpsError` 의 코드는 HTTP 상태와 클라이언트 `error.code` 양쪽을 정한다.

| `HttpsError` 코드 | HTTP | 클라이언트가 보는 `error.code` |
| --- | --- | --- |
| `invalid-argument` · `failed-precondition` · `out-of-range` | 400 | `functions/invalid-argument` … |
| `unauthenticated` | 401 | `functions/unauthenticated` |
| `permission-denied` | 403 | `functions/permission-denied` |
| `not-found` | 404 | `functions/not-found` |
| `already-exists` · `aborted` | 409 | `functions/already-exists` … |
| `resource-exhausted` | 429 | `functions/resource-exhausted` |
| `internal` · `unknown` · `data-loss` | 500 | `functions/internal` … |

<!-- verified: 상태 코드는 설치본 firebase-functions/lib/common/providers/https.js 의 errorCodeMap 을 그대로 읽었고, code 접두사와 details 전달은 firebase@12 클라이언트 SDK 로 에뮬레이터를 호출해 확인했다 — permission-denied 는 code 'functions/permission-denied' 와 details {"field":["ownerId"]} 로 도착했고, 미처리 예외는 'functions/internal' 에 details 가 undefined 였다 -->
`details` 는 **`HttpsError` 로 던진 것만** 클라이언트에 도달한다. 미처리 예외로 새어 나간
값은 접히면서 사라지므로, 클라이언트가 봐야 하는 정보는 반드시 `AppError` 에 실어
`toHttpsError` 를 태운다.

## 4. export 표면 (`functions/src/index.ts`)

배포 분석이 이 파일을 읽는다. **로직을 두지 않고** 감싼 핸들러만 내보낸다. 그리고
**`params.ts` 를 반드시 여기서 import 한다** — 분석은 이 파일에서 도달 가능한 모듈만
훑으므로, import 하지 않으면 선언한 파라미터가 매니페스트에 실리지 않는다.

<!-- file: functions/src/index.ts -->
```ts
// functions/src/index.ts
import { setGlobalOptions } from 'firebase-functions/v2';
import { onCall } from 'firebase-functions/v2/https';
import { REGION, WEBHOOK_KEY, config } from './params.js';
import { requireUid, withErrors } from './obs/logger.js';
import { parseCallable, TaskCreateSchema, TaskQuerySchema, TaskUpdateSchema } from './schemas/task.js';
import { createTask, deleteTask, getTask, listTasks, updateTask } from './firestore/tasks.js';
import { AppError } from './http/app-error.js';
import { z } from 'zod';

// REGION 은 Expression 이다 — .value() 를 부르지 않고 그대로 넘긴다.
setGlobalOptions({ region: REGION, maxInstances: 20, concurrency: 80 });

const IdSchema = z.strictObject({ taskId: z.string().min(1) });
const UpdateArgs = z.strictObject({ taskId: z.string().min(1), patch: TaskUpdateSchema });

export const tasksList = onCall(withErrors(async (req) => {
  const uid = requireUid(req);
  const q = parseCallable(TaskQuerySchema, req.data);
  const { TASKS_PAGE_MAX: pageMax } = config(); // 핸들러 안에서 — 최상위 호출은 배포 분석을 깬다
  return await listTasks(uid, { ...q, limit: Math.min(q.limit, pageMax) });
}));

export const tasksGet = onCall(withErrors(async (req) => {
  const uid = requireUid(req);
  const { taskId } = parseCallable(IdSchema, req.data);
  const task = await getTask(uid, taskId);
  if (!task) throw new AppError('NOT_FOUND', 'task not found');
  return task;
}));

export const tasksCreate = onCall({ secrets: [WEBHOOK_KEY] }, withErrors(async (req) => {
  const uid = requireUid(req);
  return await createTask(uid, parseCallable(TaskCreateSchema, req.data));
}));

export const tasksUpdate = onCall(withErrors(async (req) => {
  const uid = requireUid(req);
  const { taskId, patch } = parseCallable(UpdateArgs, req.data);
  return await updateTask(uid, taskId, patch);
}));

export const tasksDelete = onCall(withErrors(async (req) => {
  const uid = requireUid(req);
  const { taskId } = parseCallable(IdSchema, req.data);
  await deleteTask(uid, taskId);
  return { deleted: true };
}));
```

순서가 곧 경계다. **`requireUid` → `parseCallable` → 리포지토리.** `ownerId` 는 언제나
인증 컨텍스트에서 오고 요청 본문에서는 오지 않는다 — 본문에서 받으면 클라이언트가
남의 `ownerId` 를 적어 보낼 수 있다.

파라미터 배선이 실제로 매니페스트에 도달하는지는 **선언이 아니라 실행으로** 확인한다.

| `index.ts` 가 `params.ts` 를 | 매니페스트 `params` | `tasksCreate.secretEnvironmentVariables` | `tasksList.region` |
| --- | --- | --- | --- |
| import 하지 않음 (리전 하드코딩) | **0건** | `null` | `["asia-northeast3"]` |
| 위 코드처럼 import | **3건** — `TASKS_REGION` · `TASKS_PAGE_MAX` · `TASKS_WEBHOOK_KEY` | `[{"key":"TASKS_WEBHOOK_KEY"}]` | `"{{ params.TASKS_REGION }}"` |

<!-- verified: firebase-functions 7.3.2 의 runtime/loader.js 로 두 빌드를 각각 loadStack 하고 stackToWire 로 매니페스트를 뽑아 대조했다. 위 행이 음성 대조군이다 -->
`secrets: [WEBHOOK_KEY]` 는 **그 비밀을 읽는 함수에만** 건다 — 안 걸면 파라미터는 선언돼도
그 함수의 런타임에 주입되지 않는다. `.value()` 는 언제나 핸들러 안이다.

**여기 있는 다섯 개는 배치의 예시이지 확정된 명단이 아니다.** 어떤 함수를 노출할지와
요청·응답 봉투는 이음매의 `api-endpoints` 슬롯이 정한다 — 프론트가 클라이언트 SDK 로
Firestore 를 직접 읽는 조합이면 `tasksList` · `tasksGet` 은 아예 없어지고 규칙이 그
자리를 대신한다. 이 파일이 고정하는 것은 **한 함수 안의 순서**뿐이다.

## 5. 전역 초기화와 콜드 스타트

핸들러 **밖**의 코드는 콜드 스타트에서 한 번 돌고 그 인스턴스가 사는 동안 재사용된다.
<!-- verified: 함수 에뮬레이터 실행 — 모듈 적재 시 만든 난수 ID 가 6회 연속 호출에서 동일했고, 모듈 적재 후 경과 시간이 48ms → 902ms 로 늘어나는 동안 호출 카운터가 1→6 으로 누적됐다 -->
그래서 Firestore 클라이언트는 `functions/src/firestore/client.ts` 의 모듈 최상위에서
만든다(`resources/data-access.md`). 핸들러 안에서 만들면 호출마다 다시 만든다.

같은 이유로 **`functions/src/params.ts` 의 `.value()` 는 핸들러 안에서 부른다.** 모듈
최상위에서 부르면 배포 분석 단계가 값 없이 모듈을 적재하다 터진다. 선언은 최상위,
읽기는 핸들러 안이다 — 선언 형태는 `resources/input-validation.md` 가 소유한다.

앱 초기화를 두 번 부르는 것은 **예외가 아니라 침묵**으로 끝날 수 있다. 같은 옵션이면
첫 번째 app 이 조용히 돌아오고 두 번째 옵션이 버려진다. 초기화 지점을 `client.ts`
하나로 두는 것이 유일한 방어다.

## 6. 리전 · 동시성 · 최소 인스턴스 · 재시도 의미

| 옵션 | 값 | 무엇이 걸리는가 |
| --- | --- | --- |
| `region` | `setGlobalOptions` 로 한 번 | Firestore 위치와 멀면 왕복이 그만큼 늘어난다 |
| `concurrency` | 기본 80 (CPU ≥ 1), CPU < 1 이면 1 · 최대 1000 | 한 인스턴스가 요청 여러 개를 **동시에** 처리한다 |
| `minInstances` | 안 주면 플랫폼 기본값 <!-- unverified: 설치본 타입·주석에 기본값 언급이 없다. 에뮬레이터는 인스턴스를 만들지 않아 계측 경로가 없다 --> | 콜드 스타트를 없애는 대신 놀아도 과금된다 |
| `maxInstances` | — | 하류(Firestore·외부 API)를 지켜 주는 상한 |

<!-- verified: concurrency 기본값과 상한은 설치본 firebase-functions/lib/v2/options.d.ts 의 주석을 그대로 읽었다 -->
**`concurrency` 가 1보다 크면 모듈 전역이 요청 사이에 공유된다.** 전역에 요청별 상태를
담으면 다른 사용자의 값이 섞인다. 전역에는 클라이언트처럼 **상태 없는 것만** 둔다.
<!-- unverified: 옵션의 존재·기본값·상한까지만 설치본 타입 표면으로 확인했다. 「전역이 실제로 공유된다」는 실서비스 거동이고 에뮬레이터는 동시성을 구현하지 않아 여기서 계측하지 못했다 -->

**`onCall` · `onRequest` 에는 `retry` 옵션이 없다** <!-- verified: 설치본 타입 표면 — https.d.ts 에 retry 출현 0건, options.d.ts 의 EventHandlerOptions 에는 있고 DocumentOptions 가 그것을 extends 한다 -->. `retry` 는 이벤트
트리거(`onDocumentWritten` 등)의 것이고, 켜면 같은 이벤트가 **여러 번** 도착하므로 핸들러가
멱등해야 한다. **HTTP 트리거가 자동 재시도되지 않는다**는 것은 옵션이 없다는 사실에서 따라
나오는 해석이지 계측한 값이 아니다 <!-- unverified: 재시도는 플랫폼 거동이라 에뮬레이터에 계측 경로가 없다 -->.

혼동하기 쉬운 것은 **트랜잭션 재시도가 함수 재시도와 다른 층**이라는 점이다. 트랜잭션은
함수가 한 번 도는 동안에도 안에서 여러 번 실행된다.

```ts
// functions/test/repo.test.ts — 경합 블록 (발췌 — 전문은 functions/test/repo.test.ts)
await Promise.all(Array.from({ length: 8 }, async () => {
  await db.runTransaction(async (tx) => {
    runs.push('x');                                   // 재시도마다 늘어난다
    const n = (await tx.get(ref)).get('n') as number;
    await new Promise((r) => setTimeout(r, 50));
    tx.update(ref, { n: n + 1, updatedAt: FieldValue.serverTimestamp() });
  });
}));
expect((await ref.get()).get('n')).toBe(8);   // 갱신 손실 0
expect(runs.length).toBeGreaterThan(8);       // 함수가 8번보다 많이 돌았다
```

<!-- verified: 에뮬레이터 실행 — 동시 8건에서 트랜잭션 본문이 25회 실행됐고(재시도 17회) 최종값은 8이었다. 같은 테스트에서 트랜잭션을 read-then-write 로 바꾸면 최종값이 1로 떨어져 빨개진다 -->
그래서 **트랜잭션 본문에 부수효과를 두지 않는다.** 로그·메일·과금을 안에 넣으면 재시도
횟수만큼 일어난다. 위 두 단언은 짝이다 — 손실 0만 재면 트랜잭션을 지워도 통과할 수
있고, 재시도만 재면 정확성을 재지 못한다.

## 오용 목록 ① — 1세대 `firebase-functions` → 2세대 관용구 대조표

| 구 습관 (1세대) | 현재 형태 (2세대 · `firebase-functions@7`) |
| --- | --- |
| `functions.https.onCall((data, context) => ...)` | `onCall((request) => ...)` — `request.data` 와 `request.auth` 로 합쳐졌다 |
| `context.auth.uid` | `request.auth?.uid` — 없을 때 `undefined` 라 옵셔널 체이닝이 필요하다 |
| `functions.region('...').https.onCall(...)` | `setGlobalOptions({ region })` 또는 옵션 객체 |
| `functions.config().svc.key` | `defineString`/`defineSecret` (`functions/src/params.ts`) |
| 인스턴스당 요청 1건이 전제 | `concurrency` 기본 80 — 전역 공유를 전제해야 한다 |
| `import * as functions from 'firebase-functions'` 단일 진입 | `firebase-functions/v2/https` 등 경로별 import |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `if (!request.auth)` vs `if (!request.auth?.uid)` | 앞은 uid 없는 껍데기 컨텍스트를 통과시킨다. 언제나 `uid` 를 본다 |
| `onCall` 의 CORS vs `onRequest` 의 `cors` | `onCall` 은 모든 origin 에 열려 있다 — origin 은 경계가 아니고 토큰이 경계다 |
| `HttpsError` vs 평범한 `Error` | 앞은 코드·메시지·`details` 가 클라이언트까지 가고, 뒤는 전부 `INTERNAL` 로 접힌다 |
| `retry` 옵션 vs 트랜잭션 재시도 | 앞은 이벤트 트리거 전용이고, 뒤는 HTTP 함수 안에서도 일어난다 |
| `minInstances` vs `concurrency` | 앞은 콜드 스타트를, 뒤는 인스턴스당 처리량을 바꾼다. 비용이 붙는 쪽은 앞이다 |
| 모듈 최상위 `.value()` vs 핸들러 안 `.value()` | 선언은 최상위, 읽기는 핸들러 안. 최상위에서 읽으면 배포 분석이 터진다 |
