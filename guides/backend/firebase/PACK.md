<!-- epcc-pack: backend/firebase v3.14.0 verified 2026-08-24 firebase-admin@14 firebase-functions@7 firebase@12 firebase-tools@15 zod@4 typescript@7 vitest@4 @types/node@26 @firebase/rules-unit-testing@5 -->

# firebase 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가 있는
조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

각 조각은 `<!-- pack-slot: 이름 -->` ~ `<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀
있어 프론트엔드 축이 무엇이든 그대로 성립한다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
functions/
├── src/
│   ├── index.ts             # 함수 export만 — 로직을 두지 않는다 (배포 분석이 이 파일을 읽는다)
│   ├── params.ts            # defineString/defineSecret — 구성 값을 선언하는 **유일한** 파일
│   ├── firestore/
│   │   ├── client.ts        # initializeApp + getFirestore (모듈 최상위, 콜드 스타트 밖)
│   │   ├── model.ts         # TaskDoc · TaskStatus · COLLECTION · taskConverter
│   │   └── tasks.ts         # 작업 리포지토리 — 트랜잭션으로 존재+소유를 확인한다
│   ├── schemas/
│   │   └── task.ts          # Zod 스키마 + parseCallable
│   ├── http/
│   │   ├── app-error.ts     # AppError — **이음매가 소유한다**
│   │   ├── https.ts         # toHttpsError — **이음매가 소유한다**
│   │   └── auth.ts          # AuthUser · authFor — **이음매가 소유한다**
│   └── obs/
│       └── logger.ts        # firebase-functions/logger 재노출 · withErrors · requireUid
├── test/
│   ├── setup.ts             # vitest setupFiles — emulatorEnv()가 src/ import보다 먼저 돈다
│   ├── emulator.ts          # emulatorEnv · withRulesTest · RULES — 실 프로젝트로 새지 않게 하는 유일한 장치
│   ├── rules.test.ts        # 규칙 단위 테스트 — **security-rules.md 소유** (한 경로에 한 소유자)
│   ├── tasks.test.ts        # 함수(onCall) 회귀 — testing-and-deploy.md 소유
│   └── repo.test.ts         # 리포지토리 직접 호출 회귀 — data-access.md 소유
├── vitest.config.mts        # setupFiles · fileParallelism:false. `.mts`인 이유는 type:commonjs
└── .env / .env.local / .secret.local   # **gitignore 대상.** CLI가 .env.local을 자동 생성하고 .env를 이긴다

scripts/
└── check-indexes.mjs        # 배포 전 유일한 로컬 인덱스 검증 (firebase deploy는 인증이 먼저다)

firestore.rules              # 규칙 — tasks 블록은 read/create/update/delete를 따로 쓴다
firestore.indexes.json       # 복합 인덱스 — 쿼리를 바꾸면 여기도 바뀐다. **순수 JSON이다**
firebase.json                # 에뮬레이터 스위트 구성 — 하네스가 여기서 포트를 읽는다
```

**경계가 둘이고 서로 다른 코드 경로를 막는다.** Security Rules는 **클라이언트 SDK의 직접
접근**을, 애플리케이션 검사는 **Cloud Functions**를 막는다. `firebase-admin`은 규칙을
**완전히 우회하므로**, 함수 안에서 소유권을 확인하지 않으면 규칙이 아무리 촘촘해도
그 경로는 무방비다. 두 경계 중 하나만 보고 「정책 엔진이 있으니 안전하다」고 쓰면
정확히 그 구멍이 남는다.

**`src/http/`의 세 파일은 이음매 소유다.** 팩은 그것들을 부르기만 한다.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
## Core Principles

1. **경계가 둘이고, 서로 다른 코드 경로를 막는다.** Security Rules는 클라이언트 SDK의 직접 접근만
   막는다. `firebase-admin`은 규칙을 **완전히 우회한다** <!-- verified: 파일럿 C1 에뮬레이터 실행 — 규칙이 전면 거부인 상태에서 클라이언트 SDK는 permission-denied, admin SDK는 성공 -->
2. **소유권은 쿼리 안에 있다.** 함수 경로에는 규칙이 없으므로 `where('ownerId','==',ownerId)`가 유일한
   경계다. 문서 ID만으로 읽으면 남의 것도 읽히므로 `getTask`는 읽은 뒤 소유를 확인하고 아니면 `null`이다.
3. **확인과 쓰기는 한 트랜잭션 안에 있다.** 나누면 그 사이에 소유자가 바뀐다. `delete()`는 없는 문서에도 성공하므로 `deleteTask`도 예외가 아니다.
4. **시각은 서버가 만든다.** `FieldValue.serverTimestamp()`는 **센티널**이라 쓰기 반환값에 값이 없다 —
   확인하려면 문서를 다시 읽는다 <!-- verified: 파일럿 C1 실측 — `instanceof Timestamp === false`, `set()` 반환은 `_writeTime`뿐 -->
5. **구성은 `params` 하나가 소유한다.** 모듈 최상위에서 선언하고 `.value()`는 **핸들러 안에서** 부른다 — 최상위 호출은 배포 분석 단계에서 터진다.
6. **문서 모델이다 — 조인이 없다.** 질의 형태가 곧 인덱스이고, `where`+`orderBy` 조합을 바꾸면
   `firestore.indexes.json`이 함께 바뀐다. 정규화·외래키 관용구는 이 축에서 휴면이다.
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

```ts
// functions/src/index.ts — 2세대 진입점
import { onCall, type CallableRequest } from 'firebase-functions/v2/https';
import { withErrors, requireUid } from './obs/logger';
// functions/src/obs/logger.ts — 구조적 로거 재노출 (`logger`는 여기서만 나온다)
export * as logger from 'firebase-functions/logger';
// functions/src/firestore/client.ts — 모듈 최상위, 콜드 스타트 밖
import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue, Timestamp } from 'firebase-admin/firestore';
// functions/src/params.ts · functions/src/schemas/task.ts
import { defineString, defineSecret } from 'firebase-functions/params';
import { z } from 'zod';
```

`HttpsError`도 `firebase-functions/v2/https`에서 오지만 그것을 던지는 `toHttpsError`는 **이음매 소유**(`src/http/https.ts`)이고 팩은 `withErrors`를 통해 부르기만 한다.

### 1세대와 헷갈리는 자리

| 1세대 관용구 | 이 축(2세대)의 형태 |
| --- | --- |
| `import * as functions from 'firebase-functions'` → `functions.https.onCall` | 서브경로에서 직접 — `import { onCall } from 'firebase-functions/v2/https'` |
| 핸들러 인자 `(data, context)` · `context.auth.uid` | 인자 **하나** `(request: CallableRequest)` · `request.data` · `request.auth?.uid` (`requireUid`가 뽑는다) |
| `functions.config().svc.key` | `params`의 `defineString`/`defineSecret` · 핸들러 안에서 `.value()` |
| `functions.region('…').https.onCall(h)` | 첫 인자가 옵션 — `onCall({ region, concurrency, minInstances }, h)` |
| `admin.firestore()` · `admin.firestore.FieldValue` | `firebase-admin/firestore`의 `getFirestore()` · `FieldValue` |
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

```
[A] 클라이언트 SDK 경로 (firebase@12)
브라우저 ──직접 read/write──▶ ║ Security Rules ║ ──▶ Firestore
                              rulesForTasks · isOwner   ← 이 경계는 [A]만 막는다

[B] 함수 경로 (firebase-admin@14)
브라우저 ──onCall──▶ withErrors ─▶ requireUid ─▶ parseCallable ─▶ 리포지토리 ─▶ db ─▶ Firestore
                        │             │              │        listTasks·getTask   (규칙 평가 없음)
                        │             │              │        createTask·updateTask·deleteTask
       AppError→toHttpsError    UNAUTHENTICATED  VALIDATION_FAILED   │
                                                                     ▼
                              ║ 애플리케이션 검사 — where('ownerId'…) · runTransaction 확인 ║
                                                        ← 이 경계는 [B]만 막는다
```

**규칙은 [B]를 지나가지 않는다.** admin SDK가 관리자 자격으로 붙으므로 `rulesForTasks`가 아무리 촘촘해도
함수 안에서 소유를 확인하지 않으면 [B]는 무방비다. 반대로 애플리케이션 검사는 [A]를 보지 못한다 — SDK로
직접 붙는 요청은 함수 코드를 한 줄도 지나지 않는다. 어느 경로가 열려 있는지는 이음매의
`clientAccessPolicy`가 선언한다.

`taskConverter`는 `db`와 리포지토리 사이에 있다 — `fromFirestore`가 `id`를 스냅숏에서 채우므로 컨버터를
건너뛴 `snap.data()`는 `id` 없는 객체를 흘린다. 목록의 커서는 `encodeCursor`/`decodeCursor`가 감싼다.
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
## Error Codes and Antipatterns

`AppError`의 도메인 코드와 `HttpsError` 코드의 대응이다. **옮기는 함수(`toHttpsError`)는 이음매가 소유하고**, 팩은 이 대응을 가정한 채 `AppError`만 던진다.

| 도메인 코드 (`AppError`) | `HttpsError` 코드 | 언제 |
| --- | --- | --- |
| `VALIDATION_FAILED` | `invalid-argument` | `parseCallable` 실패 · `decodeCursor` 실패 |
| `UNAUTHENTICATED` | `unauthenticated` | `requireUid`가 `request.auth`를 못 찾음 |
| `NOT_FOUND` | `not-found` | `updateTask`·`deleteTask`의 존재+소유 확인 실패 |
| `FORBIDDEN` | `permission-denied` | 역할이 모자람 (`AuthUser.roles`) |
| `CONFLICT` | `already-exists` | 유일 제약 위반 |
| `INTERNAL` | `internal` | 미처리 예외 — `withErrors`가 로깅 후 일반 문구로 접는다 |

| 반복되는 안티패턴 | 왜 비싼가 |
| --- | --- |
| 원본 예외를 그대로 `HttpsError`에 실어 보냄 | Firestore 경로·필드명이 클라이언트로 샌다. `withErrors`가 접는 이유다 |
| 없는 문서를 `FORBIDDEN`으로 답함 | 남의 문서 존재 여부가 코드 차이로 새어 나간다. 둘 다 `NOT_FOUND`다 |
| 소유권 실패를 `getTask`에서 예외로 던짐 | 계약은 `null`이다. 던지면 호출자의 분기가 갈린다 |
<!-- /pack-slot -->

<!-- pack-slot: quick-start-axis -->
## Quick Start — 기능 하나 추가하기

순서가 곧 의존이다. 뒤 단계가 앞 단계의 이름을 참조하므로 거꾸로 가면 두 번 고친다.

| # | 단계 | 여는 파일 | 확정할 것 |
| --- | --- | --- | --- |
| 1 | 문서 형태 | `functions/src/firestore/model.ts` | `TaskDoc` 필드 · `TaskStatus` 리터럴 · `COLLECTION` · `taskConverter` |
| 2 | 규칙 | `firestore.rules` | `rulesForTasks`에 `read`/`create`/`update`/`delete`를 **따로**. `isOwner`는 `resource`와 `request.resource` **양쪽**을 본다 |
| 3 | 인덱스 | `firestore.indexes.json` | 새 `where`+`orderBy` 조합마다 복합 인덱스 한 줄 |
| 4 | 리포지토리 | `functions/src/firestore/tasks.ts` | `listTasks`·`getTask`·`createTask`·`updateTask`·`deleteTask` — 인자는 **`ownerId` → `taskId`** 순서 |
| 5 | 스키마 | `functions/src/schemas/task.ts` | `TaskCreateSchema`·`TaskUpdateSchema`·`TaskQuerySchema` · `parseCallable` |
| 6 | 함수 | `functions/src/index.ts` (+ `obs/logger.ts`) | `withErrors(…)`로 감싼 `onCall` export만. 로직을 두지 않는다 |
| 7 | 테스트 | `functions/test/rules.test.ts` · `functions/test/tasks.test.ts` (`functions/test/emulator.ts`) | `withRulesTest`로 규칙, `emulatorEnv`로 배선. 긍정·부정을 **같은 `it`** 안에 짝으로 |

4단계의 두 불변식이 이 축에서 가장 자주 깨진다.

```ts
// functions/src/firestore/tasks.ts
const snap = await db.collection(COLLECTION).withConverter(taskConverter)
  .where('ownerId', '==', ownerId)
  .orderBy('createdAt', 'desc')
  .limit(q.limit)
  .get();

// 확인과 쓰기가 한 트랜잭션 안에 있다
await db.runTransaction(async (tx) => {
  const cur = await tx.get(ref);
  if (!cur.exists || cur.data()!.ownerId !== ownerId) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
  tx.update(ref, { ...patch, updatedAt: FieldValue.serverTimestamp() });
});
```
<!-- /pack-slot -->

<!-- pack-slot: anti-patterns-axis -->
## Anti-Patterns

| 실수 | 대가 |
| --- | --- |
| **「규칙이 있으니 안전하다」** — 규칙을 잠갔으니 함수는 소유권을 확인하지 않아도 된다고 본다 | `firebase-admin`은 규칙을 **완전히 우회한다**. 함수 경로가 통째로 무방비가 된다 — 이 축에서 가장 비싼 한 줄 <!-- verified: 파일럿 C1 에뮬레이터 실행 — 규칙이 전면 거부인 상태에서 admin SDK 쓰기가 성공 --> |
| `allow write:` 하나로 묶는다 | 생성과 수정의 불변식이 달라 둘 중 하나가 반드시 헐거워지고, 삭제에는 `request.resource`가 `null`이라 **본인 삭제도 거부**된다 <!-- verified: 파일럿 C1 실측 — Null value error --> |
| `update` 규칙에서 `request.resource`만 본다 | 병합된 전체 문서라 `ownerId`가 보인다 — 소유자를 남에게 넘기는 수정이 통과한다 |
| 에뮬레이터가 통과했으니 인덱스가 맞다고 본다 | **두 실패 모드를 가른다.** ⓐ **복합 인덱스 누락** — 에뮬레이터는 강제하지 않고 실서비스에서 **그 쿼리만** `FAILED_PRECONDITION`으로 죽는다 <!-- verified: 인덱스 목록을 비워도 두 복합 쿼리가 전부 통과. 양성 대조군으로 `in` 31개는 INVALID_ARGUMENT, 규칙 파손은 컴파일 오류로 보고되므로 관측 장치는 켜져 있다 (감사 B1·B2 실측) --> ⓑ **`firestore.indexes.json` 문법 오류** — 에뮬레이터는 **읽지도 않아 침묵**하지만 `firebase deploy`는 `loadCJSON`·`validateSpec`에서 **배포 전체를 중단**시킨다 <!-- verified: firebase-tools 15.28.1 소스 실행 — loadCJSON throw, firestore/api.js:63 validateSpec (감사 B1) --> |
| `createTask`가 `status`를 하드코딩한다 | 클라이언트가 보낸 값이 조용히 사라지고, 그 값으로 만든 문서가 목록 필터에서 영영 빠진다 |
| `getTask(taskId, ownerId)`로 부른다 | 둘 다 `string`이라 타입 검사도 게이트도 못 잡는다. 단건 조회가 전부 빈 결과가 된다 |
| `TaskUpdateSchema`의 선택 필드에 `.default()`를 겹친다 | 보내지 않은 필드가 기본값으로 저장을 덮어쓴다 |
| `emulatorEnv` 없이 테스트를 돌린다 | 실 프로젝트 자격으로 붙어 운영 데이터에 쓴다 |
| 부모 문서를 지우면 하위 컬렉션도 사라진다고 본다 | 하위 컬렉션은 **고아로 남고** 부모는 `exists=false`다 — 정리는 명시적으로 한다 <!-- verified: 파일럿 C1 실측 --> |
<!-- /pack-slot -->

## 이음매가 채울 것

| 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| `api-endpoints` | onCall/onRequest 선택 + 요청/응답 봉투. **프론트가 SDK로 직접 읽는 조합이면 엔드포인트 수 자체가 달라진다** |
| `auth-boundaries` | 커스텀 클레임·역할과 **클라이언트 직접 접근 허용 여부**(`clientAccessPolicy`). 그 값이 주 경계를 규칙과 함수 중 어디에 둘지 바꾼다 |
| `complete-example` | 규칙 → 인덱스 → 문서 쓰기 → 쿼리 → 함수 → 테스트 관통 |
