<!-- epcc-pack: backend/firebase v3.14.0 -->
# 데이터 접근 — `firebase-admin` 은 Security Rules 를 우회한다

이 파일은 `functions/src/firestore/client.ts` 와 `functions/src/firestore/tasks.ts` 를
소유한다. 문서 형태(`TaskDoc` · `TaskStatus` · `COLLECTION` · `taskConverter`)는
`functions/src/firestore/model.ts` — `resources/data-modeling.md` 가 소유한다. Zod 스키마와
`TaskCreate` · `TaskUpdate` · `TaskQuery` 는 `functions/src/schemas/task.ts`
(`resources/input-validation.md`), `AppError` 는 이음매의 `functions/src/http/app-error.ts` 다.
함수 표면(`onCall` · `withErrors` · `requireUid`)은 `resources/functions-patterns.md`.

**규칙은 이 경로를 막지 않는다.** `allow read, write: if false` 아래에서 클라이언트 SDK 는
`permission-denied` 를 받지만 admin SDK 는 성공한다. 이 파일의 `ownerId` 검사가 함수
경로의 **유일한** 경계다.

## 1. 결정 트리 — 무엇이 이 읽기·쓰기를 막는가

| 이 코드가 도는 곳 | 규칙이 막는가 | 그러면 무엇이 막는가 |
| --- | --- | --- |
| 브라우저·앱의 클라이언트 SDK (`firebase@12`) | 막는다 | `firestore.rules` (`resources/security-rules.md`) |
| Cloud Functions 의 `firebase-admin` | **막지 않는다** | 이 파일의 `ownerId` 검사뿐 |

무엇을 쓸지는 **쓰기 전에 읽어야 하는가**로 갈린다.

| 하려는 것 | 쓰는 것 | 왜 |
| --- | --- | --- |
| 목록 | `listTasks` — `where('ownerId')` + 복합 정렬 | 컬렉션 전체를 도는 쿼리는 남의 문서를 함께 집는다 |
| 단건 | `getTask` — 읽은 뒤 `ownerId` 비교, 다르면 `null` | 문서 ID 를 아는 것만으로는 권한이 아니다 |
| 존재·소유를 본 뒤 쓰기 | `runTransaction` | 확인과 쓰기 사이에 소유자가 바뀔 수 있다 |

## 2. 클라이언트는 모듈 최상위가 소유한다 (`functions/src/firestore/client.ts`)

핸들러 **밖**에서 만든다. 콜드 스타트에서 한 번 돌고 뒤따르는 모든 호출이 재사용한다 —
실측에서 같은 인스턴스가 6회 연속 호출을 같은 모듈 인스턴스로 처리했다.

<!-- file: functions/src/firestore/client.ts -->
```ts
// functions/src/firestore/client.ts
import { getApps, initializeApp } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';

// 모듈 최상위 — 콜드 스타트에서 한 번 돌고, 뒤따르는 모든 호출이 재사용한다.
if (getApps().length === 0) {
  initializeApp();
}

export const db: Firestore = getFirestore();
```

`getApps().length === 0` 가드가 있는 이유는 **두 번째 호출이 조용하기 때문**이다.
<!-- verified: firebase-admin 14.3.0 실행 — 무인자 두 번은 던지지 않고 첫 app 을 돌려준다(apps=1). 옵션을 양쪽에 주고 값이 다르면 'app/duplicate-app'. 한쪽만 옵션을 주면 설치본 lifecycle.js 가 autoInit 불일치를 먼저 보아 'app/invalid-app-options' 다 -->
**두 호출이 모두 옵션을 넘겼고 그 옵션이 다르면** `app/duplicate-app`, **한쪽이 무인자면**
`app/invalid-app-options` 다. 위 `client.ts` 는 **무인자**라 실제로 만나는 것은 후자다 —
다른 파일이 옵션을 주며 초기화하는 순간 터진다. 같은 형태끼리는 조용히 한쪽이 무시되므로
초기화 지점을 이 파일 하나로 고정하는 것이 유일한 방어다.

## 3. 리포지토리 (`functions/src/firestore/tasks.ts`)

축의 보안 원시함수라 전문을 싣는다. 인자 순서는 전 함수에서 **`ownerId` → `taskId`** 이고
둘 다 `string` 이라 뒤집혀도 타입이 잡지 못한다.

<!-- file: functions/src/firestore/tasks.ts -->
```ts
// functions/src/firestore/tasks.ts
import { FieldPath, FieldValue, Timestamp, type Query } from 'firebase-admin/firestore';
import { db } from './client.js';
import { COLLECTION, taskConverter, type TaskDoc } from './model.js';
import type { TaskCreate, TaskQuery, TaskUpdate } from '../schemas/task.js';
import { AppError } from '../http/app-error.js';

const col = () => db.collection(COLLECTION).withConverter(taskConverter);

export function encodeCursor(createdAt: Timestamp, taskId: string): string {
  return Buffer.from(JSON.stringify([createdAt.toMillis(), taskId]), 'utf8').toString('base64url');
}

// Firestore 타임스탬프의 상한(9999-12-31T23:59:59.999Z). 범위 밖 값은 startAfter 가
// AppError 가 아닌 생 Error 로 거절해 400 이어야 할 응답이 500 이 된다.
const MAX_CURSOR_MS = 253402300799999;

export function decodeCursor(cursor: string): { createdAt: Timestamp; taskId: string } {
  let parsed: unknown;
  try {
    parsed = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
  } catch {
    throw new AppError('VALIDATION_FAILED', 'cursor is not decodable');
  }
  if (!Array.isArray(parsed) || typeof parsed[0] !== 'number' || typeof parsed[1] !== 'string') {
    throw new AppError('VALIDATION_FAILED', 'cursor shape is wrong');
  }
  const [ms, taskId] = parsed as [number, string];
  if (!Number.isSafeInteger(ms) || ms < 0 || ms > MAX_CURSOR_MS || taskId.length === 0) {
    throw new AppError('VALIDATION_FAILED', 'cursor value is out of range');
  }
  return { createdAt: Timestamp.fromMillis(ms), taskId };
}

export async function listTasks(ownerId: string, q: TaskQuery): Promise<{ items: TaskDoc[]; cursor?: string }> {
  let query: Query<TaskDoc> = col().where('ownerId', '==', ownerId);
  if (q.status) query = query.where('status', '==', q.status);
  // createdAt 이 같은 문서가 여럿이면 정렬이 흔들린다 — 문서 ID 로 동점을 깬다.
  query = query.orderBy('createdAt', 'desc').orderBy(FieldPath.documentId(), 'desc').limit(q.limit);
  if (q.cursor !== undefined) {
    const c = decodeCursor(q.cursor);
    try {
      query = query.startAfter(c.createdAt, c.taskId);
    } catch {
      throw new AppError('VALIDATION_FAILED', 'cursor is not usable for this query');
    }
  }
  const items = (await query.get()).docs.map((d) => d.data());
  const last = items.length === q.limit ? items[items.length - 1] : undefined;
  return { items, cursor: last ? encodeCursor(last.createdAt, last.id) : undefined };
}

export async function getTask(ownerId: string, taskId: string): Promise<TaskDoc | null> {
  const task = (await col().doc(taskId).get()).data();
  if (!task || task.ownerId !== ownerId) return null;
  return task;
}

export async function createTask(ownerId: string, input: TaskCreate): Promise<TaskDoc> {
  const ref = col().doc();
  await ref.set({
    id: ref.id,
    title: input.title,
    status: input.status,
    ownerId,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  const created = (await ref.get()).data();
  if (!created) throw new AppError('INTERNAL', 'created document vanished');
  return created;
}

export async function updateTask(ownerId: string, taskId: string, patch: TaskUpdate): Promise<TaskDoc> {
  const ref = col().doc(taskId);
  await db.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).data();
    if (!current || current.ownerId !== ownerId) throw new AppError('NOT_FOUND', 'task not found');
    tx.update(ref, { ...patch, updatedAt: FieldValue.serverTimestamp() });
  });
  const after = (await ref.get()).data();
  if (!after) throw new AppError('NOT_FOUND', 'task not found');
  return after;
}

export async function deleteTask(ownerId: string, taskId: string): Promise<void> {
  const ref = col().doc(taskId);
  await db.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).data();
    if (!current || current.ownerId !== ownerId) throw new AppError('NOT_FOUND', 'task not found');
    tx.delete(ref);
  });
}
```

읽어야 할 다섯 가지가 이 파일에 눌려 있다.

**`delete()` 는 없는 문서에도 성공한다.**
<!-- verified: 에뮬레이터 실행 — 존재하지 않는 문서에 delete() 가 WriteResult(_writeTime) 를 돌려주며 resolve 했다. delete({ exists: true }) 는 code 5 NOT_FOUND 로 거절했다 -->
그래서 `deleteTask` 가 트랜잭션 안에서 존재와 소유를 보지 않으면 **남의 문서를 지우라는
요청에도 성공으로 답한다** — 확인 없는 삭제는 실패를 보고할 방법이 없다.

**트랜잭션 함수는 여러 번 돈다.**
<!-- verified: 에뮬레이터 실행 — 같은 문서에 동시 트랜잭션 8건을 걸자 트랜잭션 함수가 25회 실행됐고(재시도 17회) 최종값은 8로 정확했다. 트랜잭션 없이 같은 경합을 돌리면 최종값이 1이었다(갱신 7건 소실) -->
그러므로 트랜잭션 본문에 **부수효과를 두지 않는다** — 재시도 횟수만큼 일어난다. 읽기는
쓰기보다 앞에 온다(`… require all reads to be executed before all writes.` 로 거절).

**커서는 `createdAt` 만으로 만들면 문서를 잃는다.**
<!-- verified: 에뮬레이터 실행 — createdAt 값이 3종뿐인 문서 24건을 limit 5 로 끝까지 넘겼을 때, 합성 커서는 24건 전부(중복 0 · 누락 0), createdAt 만의 커서는 15건만 반환하고 9건을 영영 건너뛰었다 -->
동점 무리가 페이지 경계에 걸리면 `startAfter(createdAt)` 가 그것을 통째로 건너뛴다.
`orderBy` 를 하나 더 걸어 동점을 깨고 커서도 두 값으로 만든다.

**`createdAt` 에 함수 인스턴스의 시각을 넣지 않는다.** `FieldValue.serverTimestamp()` 는
센티널이라 `set()` 직후 반환값에 값이 없다 — `createTask` 가 쓰기 뒤 문서를 다시 읽는 이유다.

**커서 검증을 빠뜨리면 목록이 500 이 된다.** 형태만 보고 **범위를 안 보면** `[0,""]` ·
`[1e15,"x"]` · `[-62135596801000,"x"]` 가 `startAfter` 까지 가 생 `Error` 를 내고, `withErrors`
가 그것을 `INTERNAL` 로 접어 **인증된 아무 사용자나 목록을 500 으로 만든다.**

## 4. 배치와 대량 쓰기 — 에뮬레이터가 강제하지 않는 한도

먼저 **관측 장치가 거절을 보고하는지** 확인한 뒤 한도를 쟀다.

| 시도 | 에뮬레이터 결과 |
| --- | --- |
| 양성 대조군: 2MB 필드 1건 / 1KB 필드 1건 | `REJECTED code=3 INVALID_ARGUMENT … longer than 1048487 bytes.` / `OK` |
| `WriteBatch` 499 · 500 · 501 · 1000 · 2000건 | **전부 `OK`** |

<!-- verified: 위 표는 같은 commitN() 하네스로 잰 값이다. 하네스가 서버 거절을 실제로 보고한다는 것을 2MB 대조군으로 먼저 확인했으므로, 건수 한도의 통과는 '측정 못 함'이 아니라 '강제하지 않음'이다 -->
**에뮬레이터는 배치 건수 한도를 강제하지 않는다.** 실서비스의 `WriteBatch` 상한은 500이라
로컬에서 초록이던 코드가 배포 후에만 깨진다. 넘길 가능성이 있으면 처음부터
`BulkWriter` 를 쓴다 — 원자성을 포기하는 대신 건수 제한이 없다
<!-- verified: 에뮬레이터 실행 — BulkWriter 로 1200건을 쓰고 count() 로 1200 을 확인했다 (3.5초) -->
(1200건 3.5초). 원자성이 필요하면 500 이하로 쪼갠다.

## 5. 차단 증명 (`functions/test/repo.test.ts`)

리포지토리를 **직접 부르는** 회귀다(발췌 — 전문은 `functions/test/repo.test.ts`).
`functions/test/tasks.test.ts` 는 `onCall` 진입점 회귀이고 `resources/testing-and-deploy.md`
소유이므로 여기서 같은 경로를 채우지 않는다. **부정 단언만 있으면 차단 장치가 아니다** —
각 `it` 안에 긍정 짝을 함께 건다.

```ts
// functions/test/repo.test.ts
describe('소유권 경계 — admin SDK 를 막는 것은 이 검사뿐이다', () => {
  it('단건: 주인은 받고 남은 못 받는다', async () => {
    const mine = await createTask(ALICE, { title: 'alice', status: 'open' });
    expect((await getTask(ALICE, mine.id))?.id).toBe(mine.id);
    expect(await getTask(BOB, mine.id)).toBeNull();
  });

  it('삭제: 주인은 지우고 남은 NOT_FOUND 를 받는다', async () => {
    const his = await createTask(BOB, { title: 'b', status: 'open' });
    await expect(deleteTask(ALICE, his.id)).rejects.toThrow(/not found/);
    expect((await getTask(BOB, his.id))?.id).toBe(his.id);
    await deleteTask(BOB, his.id);
    expect(await getTask(BOB, his.id)).toBeNull();
  });

  it('페이지네이션: 끝까지 넘겨 중복 0 · 누락 0, 위조 커서는 거부', async () => {
    const owner = 'pager-' + Date.now();
    const made: string[] = [];
    for (let i = 0; i < 7; i++) made.push((await createTask(owner, { title: 'p', status: 'open' })).id);
    const seen: string[] = [];
    let cursor: string | undefined;
    do {
      const p = await listTasks(owner, { limit: 3, ...(cursor ? { cursor } : {}) });
      seen.push(...p.items.map((t) => t.id));
      cursor = p.cursor;
    } while (cursor);
    expect([...seen].sort()).toEqual([...made].sort());
  });

  it('커서: 조작된 입력은 전부 VALIDATION_FAILED 다 (500 이 아니라)', async () => {
    const owner = 'vec-' + Date.now();
    await createTask(owner, { title: 'v', status: 'open' });
    const enc = (v: unknown) => Buffer.from(JSON.stringify(v), 'utf8').toString('base64url');
    expect((await listTasks(owner, { limit: 1 })).items).toHaveLength(1); // ✅ 긍정 짝
    for (const bad of ['', 'zzzz', enc([0, '']), enc([1e15, 'x']),
                       enc([-62135596801000, 'x']), enc([1e400, 'x']), enc([1.5, 'x'])]) {
      await expect(listTasks(owner, { limit: 3, cursor: bad })).rejects.toMatchObject({ code: 'VALIDATION_FAILED' });
    }
  });
});
```

각 가드를 **실제로 지워서** 스위트가 빨개지는지 확인했다.

| 지운 것 | 결과 |
| --- | --- |
| `listTasks` 의 `where('ownerId','==',ownerId)` | 2건 실패 (목록 · 페이지네이션) |
| `getTask` 의 소유 확인 | 1건 실패 (단건) |
| `deleteTask` 의 트랜잭션 안 존재·소유 확인 | 1건 실패 (삭제) |
| `updateTask` 의 트랜잭션 안 존재·소유 확인 | 1건 실패 (수정) |
| `createTask` 가 `input.status` 를 버리고 `'open'` 고정 | 1건 실패 (생성) |
| 커서 정렬에서 `FieldPath.documentId()` | 1건 실패 (페이지네이션) |
| `decodeCursor` 의 형태 검증 | 1건 실패 (커서 벡터) |
| `decodeCursor` 의 범위 검증 전체 | 1건 실패 (커서 벡터) |
| 범위 검증에서 상한 `ms > MAX_CURSOR_MS` 만 | 1건 실패 (커서 벡터) |
| `taskId.length === 0` **또는** `startAfter` 의 try/catch **하나만** | 죽지 않는다 — 둘이 서로를 덮는다. **둘 다** 지우면 1건 실패 |
| `if (q.cursor !== undefined)` 를 `if (q.cursor)` 로 | 1건 실패 — 빈 커서가 조용히 1페이지가 된다 |
| `deleteTask` 의 `runTransaction` 을 read-then-write 로 | **죽지 않는다** — 아래를 본다 |

표의 마지막 두 줄이 요점이다. **커서 방어 두 겹은 서로를 덮으므로 하나씩 지워서는
죽지 않는다** — 그래도 둘 다 둔다. 그리고 **단독 행위자 스위트는 트랜잭션을 죽이지
못한다**: 트랜잭션이 지키는 것은 소유권이 아니라 **확인과 쓰기 사이의 창**이고 그 창은
경합을 만들어야 열린다. 그래서 경합 블록이 따로 있다.

## 오용 목록 ① — 클라이언트 SDK(`firebase@12`) → admin SDK(`firebase-admin@14`) 관용구 대조표

두 SDK 는 이름이 겹치는데 형태가 다르다. 클라이언트 예제를 함수에 붙여넣으면 대부분
`TS2305`(export 없음)로 죽지만, `Timestamp` 처럼 **양쪽에 다 있는 이름**은 조용히 어긋난다.

| 구 습관 (클라이언트 SDK) | 현재 형태 (admin SDK) |
| --- | --- |
| `import { collection } from 'firebase/firestore'` | admin 에 `collection` export 가 없다 — `db.collection('tasks')` |
| `query(col, where(...), orderBy(...))` 함수 조합 | `col.where(...).orderBy(...)` 메서드 체인 |
| `serverTimestamp()` | `FieldValue.serverTimestamp()` |
| `Timestamp` (`firebase/firestore`) | `Timestamp` (`firebase-admin/firestore`) — **다른 클래스다** <!-- verified: 두 모듈을 같은 프로세스에서 import 해 `cs.Timestamp === ad.Timestamp` 가 false 임을 확인 --> |
| 규칙이 막아 주므로 소유권 검사가 없어도 된다 | 규칙이 admin 을 막지 않는다 — `where('ownerId')` 가 유일한 경계 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `set()` vs `update()` | `set()` 은 문서를 통째로 덮는다(`{a,b}` 에 `set({a})` → `{a}`). 부분 수정은 `update()` 나 `set(…, { merge: true })` |
| `update()` vs `delete()` 의 없는 문서 | `update()` 는 code 5 `NOT_FOUND`, `delete()` 는 **성공한다** |
| `startAfter(스냅숏)` vs `startAfter(값들)` | 스냅숏은 문서를 다시 읽어야 하고, 값 목록은 `orderBy` 개수와 **정확히** 같아야 한다 (초과 시 `Too many cursor values specified.`) |
