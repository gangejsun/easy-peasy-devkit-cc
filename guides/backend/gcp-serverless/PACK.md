<!-- epcc-pack: backend/gcp-serverless v3.14.0 verified 2026-08-24 hono@4 @hono/node-server@2 @google-cloud/firestore@9 jose@6 zod@4 typescript@7 vitest@4 @types/node@26 -->

# gcp-serverless 축 팩 — 허브 조각

조립 시 `SKILL.md`로 옮겨지는 조각들이다. 각 조각은 `<!-- pack-slot: 이름 -->` ~
`<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀 조합이 바뀌어도 그대로 쓰인다.
파일 끝의 「이음매가 채울 것」 표에 있는 슬롯만 이음매가 새로 쓴다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── main.ts                  # 부팅만 — startServer() + SIGTERM 핸들러 안에서 shutdown(server)
├── app.ts                   # createApp(): 라우터 마운트 + installErrorHandlers + /healthz
├── settings.ts              # 프로세스 환경을 읽는 **유일한 파일** (모듈 최상위에서 검증·실패)
├── errors.ts                # AppError — **이음매가 소유한다.** 프레임워크를 import하지 않는다
├── schemas/
│   ├── task.ts              # zod 스키마 + TaskStatus (값은 소문자 'open'·'done')
│   └── errors.ts            # fieldErrors — zod 오류를 필드 맵으로
├── firestore/
│   ├── client.ts            # Firestore 인스턴스 — 모듈 최상위, 프로세스당 하나
│   ├── converter.ts         # taskConverter — 읽을 때 스키마를 다시 파싱한다
│   ├── tasks.ts             # 작업 리포지토리 — HTTP를 모른다. ownerId → taskId 순서
│   ├── cursor.ts            # encodeCursor · decodeCursor — 커서는 신뢰 입력이 아니다
│   └── errors.ts            # gRPC 코드 판별(3·5·6·9·10) — HTTP를 모른다
├── identity/
│   └── verify.ts            # verifyIdToken · jwks — Identity Platform ID 토큰
├── http/
│   ├── errors.ts            # ERROR_STATUS · toAppError (hono를 import한다)
│   ├── handlers.ts          # installErrorHandlers — **이음매가 소유한다**
│   ├── auth.ts              # currentUser · AuthUser — **이음매가 소유한다**
│   └── routes.ts            # apiRouter — **이음매가 소유한다**
├── obs/
│   └── log.ts               # log() — stdout에 JSON 한 줄. severity 키를 쓴다
└── services/
    └── tasks.ts             # 도메인 규칙. 리포지토리를 부르고 AppError를 던진다

firestore.indexes.json       # 복합 인덱스 선언 — 없으면 목록 쿼리가 런타임에 죽는다
firestore.rules              # 전면 거부 — 이 축은 클라이언트가 Firestore에 직접 붙지 않는다
vitest.config.ts             # 테스트 환경 + 에뮬레이터 env 주입 (settings 가 모듈 최상위에서 파싱하므로 beforeAll 은 늦다)
Dockerfile                   # Cloud Run 컨테이너. PORT를 환경에서 읽고 0.0.0.0에 바인딩한다

test/
├── helpers.ts               # appFetch · withEmulator
├── schemas.test.ts          # 스키마 단위 — 부분 수정·미지 키·빈 객체
├── errors.test.ts           # gRPC 코드 판별과 상태 매핑
└── tasks.test.ts            # 소유권 회귀 — 긍정·부정을 같은 테스트에 건다
```

**계층은 한 방향이다**: `routes → services → firestore`. 리포지토리가 `Context`를 받거나
HTTP 상태를 알면 그 계층은 이미 무너진 것이다 — 테스트가 HTTP를 세워야만 돌게 된다.

**`src/http/`의 세 파일(`handlers.ts`·`auth.ts`·`routes.ts`)과 `src/errors.ts`는 이음매
소유다.** 팩은 그것들을 부르기만 한다. 조립 전에는 정의가 없는 것이 정상이고, 게이트가
`--assembly`와 함께 그 충족을 검사한다.
<!-- /pack-slot -->

<!-- pack-slot: quick-start-axis -->
## Quick Start

**새 엔드포인트를 추가할 때**
1. 요청 스키마를 `src/schemas/task.ts`에 정의한다 — 본문과 쿼리 **양쪽에 `.strict()`**
2. 리포지토리 함수를 `src/firestore/tasks.ts`에 추가한다 — 첫 인자는 **항상 `ownerId`**, 그다음 `taskId`
3. 소유권을 **쿼리의 `where('ownerId', '==', ownerId)`**에 넣는다 (읽은 뒤 거르지 않는다)
4. 변이(수정·삭제)는 `firestore.runTransaction()` 안에서 읽고 확인한 뒤 쓴다
5. 새 필터·정렬 조합이 생기면 `firestore.indexes.json`에 복합 인덱스를 선언한다
6. 도메인 규칙은 `src/services/tasks.ts`에서 `AppError(<코드>, …)`로 던진다 — 코드가 `ERROR_STATUS`에 있어야 한다

**새 컬렉션/문서 타입을 추가할 때**
1. zod 스키마와 파생 타입을 `src/schemas/`에 만든다 — `.strict()`로 미지 키를 거부한다
2. `ownerId`를 **문서 필드로** 저장한다 (문서 ID에 인코딩하면 쿼리가 그것을 읽지 못한다)
3. converter를 만들고 `fromFirestore`에서 스키마를 **다시 파싱한다**
4. `withConverter()`를 붙인 컬렉션 참조를 **한 곳에서만** 만들어 export한다
5. 목록 정렬은 `createdAt` + `__name__` **두 키**로 — 동시각 문서가 페이지 경계에서 새거나 겹친다
6. 복합 인덱스를 `firestore.indexes.json`에 선언하고, 에뮬레이터 테스트에 `withEmulator()`로 격리를 건다
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

**Cloud Run 컨테이너(상주 프로세스) 하나가 전부다.** 요청 사이에 프로세스가 살아 있다는 전제 위에 이 축의 결정 넷이 선다 — Firestore 클라이언트 재사용 · JWKS 캐시 · SIGTERM 배수 · 동시성.

| 구성 요소 | 책임 | 사는 곳 |
| --- | --- | --- |
| Cloud Run 컨테이너 | `settings.PORT`에 `0.0.0.0`으로 바인딩, SIGTERM 후 **10초** 배수 | `src/main.ts` |
| Hono 앱 (`createApp`) | 라우터 마운트 · `installErrorHandlers` · `/healthz` | `src/app.ts` |
| Firestore 클라이언트 | 서비스 계정(ADC)으로 붙는다. **모듈 최상위 단일 인스턴스** | `src/firestore/client.ts` |
| Identity Platform 검증 | ID 토큰을 JWKS로 검증한다. 키셋도 모듈 최상위 하나 | `src/identity/verify.ts` |
| `settings` | 환경을 읽는 **유일한 파일.** 부팅 시점에 검증하고 실패한다 | `src/settings.ts` |

**계층은 한 방향이다**: `routes → services → firestore` — 리포지토리는 HTTP를 모르고 `Context`를 받지 않는다. **`src/http/`의 `handlers.ts`·`auth.ts`·`routes.ts`와 `src/errors.ts`는 이음매 소유다** (응답 봉투와 자격 증명이 도착하는 방식은 축이 아니라 조합이 정한다). **정책 엔진이 없다** — `firestore.rules`는 전면 거부이고 서버는 서비스 계정으로 붙어 규칙을 통째로 우회한다: 애플리케이션 층이 **유일한 경계**이고 소유권 필터 누락이 곧 데이터 유출이다.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
## Core Principles (5 Key Rules)

### 1. 입력은 `.strict()` 스키마를 통과한 것만 쓴다
미지 키를 허용하면 오타 난 필터가 **조용히 무시된 채 정상 목록**으로 응답된다. 본문과 쿼리 양쪽에 건다.

```ts
// ❌ 미지 키가 통과한다 — 오타 난 status 파라미터가 필터 없는 전체 목록을 준다
const q = z.object({ limit: z.number() }).parse(raw);
// ✅ 스키마가 거부한다
const q = TaskQuery.parse(raw);
```

### 2. 부재와 권한 없음을 같은 응답으로 낸다
남의 문서에 `403`을, 없는 문서에 `404`를 주면 **그 차이가 곧 존재 증명**이다. 주체는 `currentUser`가 심은 검증된 `sub`에서만 온다 — 본문·쿼리의 `ownerId`는 자격 증명이 아니라 입력이다.

```ts
// ❌ 남의 것임을 알려 준다 — 문서 ID를 훑으면 존재 목록이 만들어진다
if (doc.ownerId !== ownerId) throw new AppError('FORBIDDEN', '권한이 없다');
// ✅ 부재와 구분되지 않는다
if (doc.ownerId !== ownerId) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
```

### 3. 소유권은 쿼리의 `where`에 있다

```ts
// ❌ 전부 읽고 나서 거른다 — 이 축에 백업이 없다. 노출도 읽기 비용도 이미 발생했다
const all = await tasksRef.get();
// ✅ 경계는 쿼리 안에 있다
const snap = await tasksRef.where('ownerId', '==', ownerId).limit(q.limit).get();
```

### 4. `ownerId` → `taskId` 인자 순서를 전 함수에서 고정한다

```ts
// ❌ 둘 다 string이라 뒤집혀도 컴파일된다 — 실측에서 모든 단건 조회가 404가 됐다
const task = await getTask(taskId, ownerId);
// ✅ 소유자가 먼저다
const task = await getTask(ownerId, taskId);
```

### 5. 변이는 트랜잭션 안에서 읽고 확인한 뒤 쓴다

```ts
// ❌ delete()는 없는 문서에도 성공한다 — 확인이 없으면 남의 것을 지우라는 요청도 성공이다
await tasksRef.doc(taskId).delete();
// ✅ 같은 트랜잭션에서 읽고 ownerId를 확인한 뒤 쓴다 (전체 형태는 data-access.md가 갖는다)
await firestore.runTransaction(async (tx) => { /* get → ownerId 확인 → delete */ });
```
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

**경로 별칭을 두지 않는다** — 상대 경로에 **`.js` 확장자**를 붙인다(아래는 `src/` 최상위 기준). 별칭은 빌드·테스트·컨테이너 세 곳에 따로 설정해야 해서 한 곳이 어긋나면 조용히 다른 파일을 가리킨다.

```ts
import { Hono } from 'hono';
import { serve } from '@hono/node-server';
import { Firestore, Timestamp } from '@google-cloud/firestore';
import { createRemoteJWKSet } from 'jose';
import { z } from 'zod';
// 팩이 정의한다 (원장 provides)
import { settings } from './settings.js';
import { Task, TaskCreate, TaskUpdate, TaskQuery, TaskStatus } from './schemas/task.js';
import { fieldErrors } from './schemas/errors.js';
import { firestore } from './firestore/client.js';
import { taskConverter } from './firestore/converter.js';
import { tasksRef, listTasks, getTask, createTask, updateTask, deleteTask } from './firestore/tasks.js';
import { isInvalidArgument, isNotFound, isAlreadyExists, isFailedPrecondition, isAborted } from './firestore/errors.js';
import { verifyIdToken, jwks, type IdTokenClaims } from './identity/verify.js';
import { statusFor, toAppError } from './http/errors.js';   // 상태는 statusFor 만 — 첨자 접근은 정책이 막는다
import { log } from './obs/log.js';
// 이음매가 정의한다 (원장 requires)
import { AppError } from './errors.js';
import { installErrorHandlers } from './http/handlers.js';
import { currentUser, type AuthUser } from './http/auth.js';
import { apiRouter } from './http/routes.js';
```
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
## HTTP Status Mapping

`ERROR_STATUS`(`src/http/errors.ts`)가 **유일한 매핑표**다. 조회는 `statusFor(code)`으로 한다 — 맨 첨자 접근은 코드표에 없는 코드에서 `undefined`를 상태 자리에 넣고, 그 런타임 오류가 다시 500으로 접혀 **원래 코드가 로그에서 사라진다.** `toAppError`를 **먼저** 부른다: 정규화 전 원본 메시지에는 프로젝트 ID와 문서 경로가 들어 있다.

| 도메인 코드 | 상태 | 언제 |
| --- | --- | --- |
| `VALIDATION_FAILED` | 422 | zod 파싱 실패 · 손상된 커서(`decodeCursor`)  · gRPC 3(문서 크기 한도 초과)|
| `UNAUTHENTICATED` | 401 | `verifyIdToken` 실패 — 만료·서명·발급자를 **구분하지 않는다** |
| `FORBIDDEN` | 403 | 신원은 확인됐고 **역할·스코프**가 모자랄 때만 — 소유권 실패는 404다 |
| `NOT_FOUND` | 404 | 없는 문서 **그리고 남의 문서** — 둘을 구분하지 않는다 |
| `CONFLICT` | 409 | gRPC 6(`isAlreadyExists`) · gRPC 10(`isAborted`, 재시도 소진) |
| `INTERNAL` | 500 | 그 밖의 전부. gRPC 9(`isFailedPrecondition`)도 여기다 — 대개 인덱스 누락이고 배포 결함이지 사용자 입력 문제가 아니다 |
<!-- /pack-slot -->

<!-- pack-slot: anti-patterns-axis -->
## Anti-Patterns

| 안티패턴 | 이 축에서 무엇이 되는가 | 대신 |
| --- | --- | --- |
| `firebase-admin`을 끌어와 `getFirestore()`나 `verifyIdToken()`을 쓴다 | `firebase` 축 팩과 코드가 겹치고 두 축의 보안 경계가 섞인다 — 그쪽은 규칙이 클라이언트를 막는 전제 위에 있고 이 축은 규칙이 전면 거부다 | `@google-cloud/firestore` + `jose`. 정책 `no-firebase-admin`이 FAIL로 막는다 |
| 「규칙이 지켜 준다」·「데이터 계층이 백업한다」·「이중 방어」 | 서버는 서비스 계정으로 붙어 규칙을 **통째로 우회한다.** 이 축에 두 번째 층은 없다 | 애플리케이션 층이 유일한 경계다. 소유권 검사 누락 = 데이터 유출 |
| 컬렉션을 읽고 나서 자바스크립트에서 소유자를 거른다 | 남의 문서를 **이미 읽은 뒤**이고, 읽기 비용이 컬렉션 크기에 비례한다 | 소유권은 `where('ownerId', '==', ownerId)`에 둔다 |
| 필터 + 정렬 조합을 인덱스 선언 없이 배포한다 | 프로덕션에서 gRPC 9로 죽는다. **에뮬레이터는 인덱스를 요구하지 않아 테스트가 통과한다** | `firestore.indexes.json`에 선언하고 배포 산출물에 포함한다 |
| 요청마다 `new Firestore()`·`createRemoteJWKSet()`을 만들거나, 톱레벨에서 `shutdown(server)`를 부른다 | 앞은 gRPC 채널이 쌓이고 매 요청이 Google에 왕복한다. 뒤는 컨테이너가 부팅 직후 종료된다 | 모듈 최상위 단일 인스턴스 · `SIGTERM` 핸들러 **안에서** 배수(10초) |
| 라우터가 `Authorization` 헤더를 직접 파싱한다 | 경계가 둘이 되고, 두 검사는 반드시 어긋난다 | `currentUser`가 심은 주체만 읽는다. 검증은 `verifyIdToken` 하나뿐이다 |
| 리포지토리가 `Context`를 받거나 HTTP 상태를 안다 | 계층이 무너져 데이터 계층 테스트가 HTTP를 세워야만 돈다 | `routes → services → firestore` 한 방향 |
| `ownerId`를 요청 본문에서 받는다 | 남의 이름으로 문서를 만들거나 남의 문서를 읽는다 | 검증된 토큰의 `sub`에서만 온다 |
<!-- /pack-slot -->

> **아래 슬롯은 L2가 쓴다** (L0는 디렉토리 트리만 동결한다):
> `core-principles-axis` · `common-imports-axis` · `architecture-overview` ·
> `http-status-and-antipatterns` · `quick-start-axis` · `anti-patterns-axis`.

## 이음매가 채울 것

| 슬롯 | 무엇을 |
| --- | --- |
| `api-endpoints` | Hono 라우터 형태 · 요청/응답 봉투 · 에러 봉투 방출 |
| `auth-boundaries` | 토큰이 어떻게 도착하는가(베어러 vs 세션 쿠키) · `currentUser` 배선 · 로그인/로그아웃 흐름 |
| `complete-example` | 인덱스 → 스키마 → converter → 리포지토리 → 서비스 → 라우터 → 테스트 관통 |
