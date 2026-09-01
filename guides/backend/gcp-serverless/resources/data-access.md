<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# 데이터 접근 — 소유권은 쿼리 안에 있고, 변이는 트랜잭션 안에 있다

이 파일이 소유하는 것은 `src/firestore/`의 넷이다 — `client.ts` · `converter.ts` · `tasks.ts` ·
`cursor.ts`. 문서 형태·컬렉션 배치·복합 인덱스 선언은 `data-modeling.md`, 스키마 타입은
`input-validation.md`, gRPC 오류 판별과 상태 매핑은 `error-handling.md`가 소유한다.

**이 파일이 이 축의 보안 경계다.** 규칙은 전면 거부이고 서버는 서비스 계정으로 붙어 그것을
우회한다(`data-modeling.md` 3절의 측정) — `where('ownerId', …)`를 빠뜨린 쿼리는 뒤에서 막히지
않고 그대로 남의 문서를 준다.

## 1. 어느 함수를 언제 쓰는가

**리포지토리는 HTTP를 모른다.** `Context`를 받지 않고 상태 코드를 알지 못한다 — 도메인 코드를 던지거나 `null`을 돌려줄 뿐이다.

| 하려는 것 | 함수 | 없거나 남의 것이면 | 왜 그렇게 다른가 |
| --- | --- | --- | --- |
| 목록 | `listTasks(ownerId, q)` | 그냥 안 담긴다 | 경계가 `where`에 있어 애초에 읽지 않는다 |
| 단건 조회 | `getTask(ownerId, taskId)` | **`null`** (예외 아님) | 「없음」은 정상 흐름이다. 404로 만들지는 위 계층이 정한다 |
| 생성 | `createTask(ownerId, data)` | — | `ownerId`는 인자에서만 온다. 본문에서 오지 않는다 |
| 수정 | `updateTask(ownerId, taskId, patch)` | **`AppError('NOT_FOUND', …)`** | 변이는 「아무것도 안 함」과 구분돼야 한다 |
| 삭제 | `deleteTask(ownerId, taskId)` | **`AppError('NOT_FOUND', …)`** | 확인 없는 `delete()`는 **없는 문서에도 성공한다**(6절) |

**인자 순서는 예외 없이 `ownerId` → `taskId`다.** 둘 다 `string`이라 뒤집혀도 컴파일된다 —
실측에서 이 실수 하나로 모든 단건 조회가 404가 됐다. 임포트는 허브의 Common Imports에 있다.

## 2. 클라이언트는 프로세스당 하나 (`src/firestore/client.ts`)

Cloud Run은 **상주 프로세스**다. 요청마다 `new Firestore()`를 만들면 gRPC 채널이 요청 수만큼 쌓이고, 모듈 최상위에 두면 그 채널이 요청 사이에 살아 재사용된다.

<!-- file: src/firestore/client.ts -->
```ts
// src/firestore/client.ts
import { Firestore } from '@google-cloud/firestore';
import { settings } from '../settings.js';

const emulator = settings.FIRESTORE_EMULATOR_HOST;
const [emulatorHost, emulatorPort] = emulator ? emulator.split(':') : [];

/** 프로세스당 하나. 이 인스턴스가 gRPC 채널을 들고 있다 — 요청 안에서 만들지 않는다. */
export const firestore = new Firestore(
  emulatorHost
    ? { projectId: settings.GCP_PROJECT_ID, host: emulatorHost, port: Number(emulatorPort), ssl: false }
    : { projectId: settings.GCP_PROJECT_ID },
);
```

**환경은 `settings`를 통해서만 읽는다**(`input-validation.md`) — 이 파일은 정책 예외가 아니다.

<!-- verified: @google-cloud/firestore 9.0.0으로 host/port/ssl:false만 주고 FIRESTORE_EMULATOR_HOST 환경변수를 지운 채 에뮬레이터에 쓰기·읽기 성공 -->
**에뮬레이터 접속은 이 세 옵션만으로 된다.** `ssl: false`이면 SDK가 자격 증명을 요구하지 않아
ADC 없이 붙는다 — 환경변수 자동 감지에 기대지 않는다. 격리는 `testing-and-deploy.md`가 소유한다.

## 3. converter — 읽는 자리에서 다시 파싱한다 (`src/firestore/converter.ts`)

문서는 **코드 밖에서 바뀐다.** 콘솔에서 고친 문서, 이전 스키마로 쓰인 문서, 절반만 지나간 마이그레이션이 같은 컬렉션에 섞인다 — 신뢰 입력이 아니다.

<!-- file: src/firestore/converter.ts -->
```ts
// src/firestore/converter.ts
import type { DocumentData, FirestoreDataConverter, QueryDocumentSnapshot, WithFieldValue } from '@google-cloud/firestore';
import { Task } from '../schemas/task.js';

export const taskConverter: FirestoreDataConverter<Task> = {
  /** `id`는 문서 ID다 — 데이터에도 넣으면 두 값이 갈린다. */
  toFirestore(task: WithFieldValue<Task>): DocumentData {
    const { id: _id, ...fields } = task as Task;
    return fields;
  },
  /** 문서는 코드 밖에서 바뀔 수 있다 — 읽는 자리에서 다시 파싱한다. */
  fromFirestore(snap: QueryDocumentSnapshot): Task {
    return Task.parse({ ...snap.data(), id: snap.id });
  },
};
```

```ts
// ❌ 컴파일된다. 값은 셋 다 거짓이다 — 캐스팅은 아무것도 확인하지 않는다
const task = snap.data() as Task;
// ✅ converter를 붙인 참조에서 읽으면 파싱을 거친다
const task2 = (await tasksRef.doc(taskId).get()).data();
```

<!-- verified: 에뮬레이터에 { title: 42, status: 'archived' } 문서를 converter 없이 직접 쓰고 두 경로로 읽어 계측 -->

| 같은 문서를 읽은 방식 | 관측 |
| --- | --- |
| `snap.data() as Task` | `typeof title === 'number'` · `status === 'archived'`(열거 밖) · **`id === undefined`** |
| `taskConverter`를 거쳐 | `ZodError` — `title:invalid_type`, `status:invalid_value` |
| **대조군**: 정상 문서를 converter로 | 통과하고 `id`가 문서 ID로 채워졌다(`createdAt`은 `Timestamp`) |

대조군이 없으면 converter가 「전부 던지는 것」과 구분되지 않는다. `id`가 `undefined`인 것이 특히 조용하다 — 그 값이 다음 요청의 `taskId`가 되면 존재하지 않는 문서를 가리킨다.

## 4. 소유권은 쿼리 안에 있다 (`src/firestore/tasks.ts`)

`withConverter`를 붙인 참조는 **한 곳에서만** 만들어 export한다. 다른 파일이 맨 `firestore.collection('tasks')`를 만들면 그 경로만 원시 문서를 받는다.

**이 절이 파일 전문을 싣는다** — 변이 네 함수의 근거는 6절이 설명하되 코드는 여기 한 번만 있다. 두 블록으로 나누면 어느 쪽도 완전 파일이 아니게 되고, 그러면 이 모듈은 타입체크도 실행 검사도 받지 못한다.

<!-- file: src/firestore/tasks.ts -->
```ts
// src/firestore/tasks.ts
import { Timestamp, type CollectionReference, type Query } from '@google-cloud/firestore';
import { firestore } from './client.js';
import { taskConverter } from './converter.js';
import { decodeCursor, encodeCursor } from './cursor.js';
import { AppError } from '../errors.js';
import type { Task, TaskCreate, TaskQuery, TaskUpdate } from '../schemas/task.js';

export const tasksRef: CollectionReference<Task> = firestore
  .collection('tasks')
  .withConverter(taskConverter);

export async function listTasks(
  ownerId: string,
  q: TaskQuery,
): Promise<{ items: Task[]; nextCursor: string | null }> {
  let query: Query<Task> = tasksRef.where('ownerId', '==', ownerId);
  if (q.status) query = query.where('status', '==', q.status);
  query = query.orderBy('createdAt', 'desc').orderBy('__name__', 'desc');
  if (q.cursor) {
    const { createdAt, taskId } = decodeCursor(q.cursor);
    query = query.startAfter(createdAt, taskId);
  }
  const items = (await query.limit(q.limit).get()).docs.map((d) => d.data());
  const last = items.at(-1);
  const nextCursor = last && items.length === q.limit ? encodeCursor(last.createdAt, last.id) : null;
  return { items, nextCursor };
}

export async function createTask(ownerId: string, data: TaskCreate): Promise<Task> {
  const ref = tasksRef.doc();                              // ID를 먼저 받는다
  const task: Task = { id: ref.id, ownerId, title: data.title,
                       status: data.status, createdAt: Timestamp.now() };
  await ref.create(task);                                  // converter가 id를 데이터에서 뺀다
  return task;
}

export async function getTask(ownerId: string, taskId: string): Promise<Task | null> {
  const task = (await tasksRef.doc(taskId).get()).data();
  if (!task || task.ownerId !== ownerId) return null;      // ID만으로 읽으면 남의 것을 준다
  return task;
}

export async function updateTask(ownerId: string, taskId: string, patch: TaskUpdate): Promise<Task> {
  const ref = tasksRef.doc(taskId);
  return firestore.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).data();
    if (!current || current.ownerId !== ownerId) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
    const next: Task = { ...current, ...patch };
    tx.set(ref, next);
    return next;
  });
}

export async function deleteTask(ownerId: string, taskId: string): Promise<void> {
  const ref = tasksRef.doc(taskId);
  await firestore.runTransaction(async (tx) => {
    const current = (await tx.get(ref)).data();
    if (!current || current.ownerId !== ownerId) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
    tx.delete(ref);
  });
}
```

**읽고 나서 `.filter(t => t.ownerId === …)`로 거르는 형태는 남의 문서를 이미 읽은 뒤다** — 읽기 비용도 노출도 발생했고 이 축에 백업이 없다.

**두 정렬 키와 인덱스 선언은 한 결정이다** — `orderBy`를 고치면 `firestore.indexes.json`도 같은 커밋에서 고친다(`data-modeling.md` 4절).

## 5. 커서 페이지네이션 (`src/firestore/cursor.ts`)

**커서는 신뢰 입력이 아니다.** 디코드 실패는 예외가 아니라 검증 실패이고, 내부 정렬 키를 그대로 노출하면 그것이 와이어 계약이 되어 정렬을 못 바꾼다.

<!-- file: src/firestore/cursor.ts -->
```ts
// src/firestore/cursor.ts
import { Timestamp } from '@google-cloud/firestore';
import { AppError } from '../errors.js';

export function encodeCursor(createdAt: Timestamp, taskId: string): string {
  const raw = JSON.stringify([createdAt.seconds, createdAt.nanoseconds, taskId]);
  return Buffer.from(raw, 'utf8').toString('base64url');
}

export function decodeCursor(cursor: string): { createdAt: Timestamp; taskId: string } {
  let p: unknown = null;
  try { p = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8')); } catch { /* 아래에서 거부한다 */ }
  // 형태 검사를 생략하지 않는다 — 디코드와 JSON.parse는 [1,2,3]이나 {"a":1}에도 성공한다.
  if (!Array.isArray(p) || p.length !== 3 ||
      typeof p[0] !== 'number' || typeof p[1] !== 'number' || typeof p[2] !== 'string') {
    throw new AppError('VALIDATION_FAILED', '커서가 올바르지 않다', { cursor: ['형식이 올바르지 않다'] });
  }
  return { createdAt: new Timestamp(p[0], p[1]), taskId: p[2] };
}
```

<!-- verified: 위 구현에 왕복 1건과 손상 입력 5건('', 'not-base64!!', [1,2,3], {"a":1}, [1,2])을 태워 관측 -->
왕복은 값을 그대로 돌려주고 손상 입력 다섯은 전부 `VALIDATION_FAILED`로 거부됐다 — 형태 검사가
없으면 `[1,2,3]`이 `startAfter`에 들어가고 SDK의 오류가 `INTERNAL`로 접혀 원인이 사라진다.

<!-- verified: firestore-emulator 1.19.8에 createdAt이 동일한 문서 7개를 심고 두 정렬로 각각 페이지를 끝까지 넘겨 받은 ID를 셌다 -->

| 같은 `createdAt` 문서 7개를 `limit: 2`로 넘기면 | 받은 행 | 고유 | 누락 | 중복 |
| --- | --- | --- | --- | --- |
| `('createdAt','desc')` **하나** | 2 | 2 | **5** | 0 |
| `('createdAt','desc')` + `('__name__','desc')` | 7 | 7 | **0** | 0 |

첫 줄이 양성 대조군이다. `startAfter(createdAt)` 하나로는 **같은 값을 가진 나머지가 전부
건너뛰어진다** — 7개 중 5개가 둘째 페이지에서 사라졌다. 오름차순이었다면 같은 문서가 반복해 나온다.

## 6. 변이는 트랜잭션 안에서 읽고 확인한 뒤 쓴다

코드는 **4절이 전문으로 싣는다**(사본을 두지 않는다). 여기서 읽을 것은 형태 셋이다.

| 함수 | 경계 | 틀리면 |
| --- | --- | --- |
| `createTask` | `data.title`과 `data.status`를 **모두** 옮긴다 | `status`를 하드코딩하면 클라이언트가 보낸 값이 조용히 사라진다 |
| `getTask` | 읽은 뒤 `ownerId`를 **확인**한다 | 문서 ID만으로 읽으면 남의 작업을 준다 |
| `updateTask` · `deleteTask` | `runTransaction` 안에서 **읽고 확인한 뒤 쓴다** | 확인과 쓰기를 나누면 그 사이에 소유자가 바뀐 문서를 덮어쓴다 |

<!-- verified: 에뮬레이터에서 없는 문서 ID에 delete()를 호출해 writeTime을 받은 것을 관측. 대조군 delete({exists:true})는 gRPC 5로 거부됐다 -->
**`delete()`는 없는 문서에도 성공한다.** 없는 ID에 불렀더니 예외 없이 `writeTime`이 돌아왔고,
대조군 `delete({ exists: true })`는 **gRPC 5**로 거부됐다. 성공은 「지웠다」가 아니라 「끝났을 때
없다」는 뜻이다 — 확인 없이 부르면 남의 것을 지우라는 요청도 성공이 된다.

<!-- verified: 소유권 확인과 쓰기 사이에 300ms를 두고 그 사이에 경쟁 쓰기를 넣어 두 구현의 최종 문서 상태를 계측 -->

| 확인 뒤 300 ms에 경쟁 쓰기를 넣으면 | 그 사이 문서가 삭제될 때 | 그 사이 소유자가 `bob`이 될 때 |
| --- | --- | --- |
| ❌ 트랜잭션 없이 `get` → `set` | 문서가 **되살아났다** | `bob`의 문서를 `alice`의 값으로 **덮어썼다** |
| ✅ `runTransaction` | 삭제된 채로 남았다 | `bob`의 값이 살아남았다 |

<!-- verified: 같은 시나리오에서 경쟁 쓰기가 반환되기까지 걸린 시간을 계측 — 트랜잭션 없이 4ms, 트랜잭션과 함께 316ms -->
**막아 주는 것은 재시도가 아니라 직렬화다.** 경쟁 쓰기가 돌아오기까지 트랜잭션이 없을 때는
**4 ms**, 있을 때는 **316 ms**가 걸렸다 — 트랜잭션의 읽기가 문서를 잡아 경쟁 쓰기가 커밋을
기다렸다. 재시도가 소진되면 gRPC 10이 올라오고 그것은 `CONFLICT`다(`error-handling.md`).

## 7. 차단을 증명한다 (`test/tasks.test.ts`)

**부정 단언만 있는 테스트는 차단 장치가 아니다.** 「남의 것을 읽으면 `null`」만 걸면 함수를 통째로 `return null`로 바꿔도 초록이다. 긍정 짝을 **같은 `it` 안에** 건다.

```ts
// test/tasks.test.ts  (파일에는 아래 둘 외에 5절의 커서 테스트와 목록 격리 테스트가 더 있다)
import { describe, expect, it } from 'vitest';
import { createTask, deleteTask, getTask, updateTask } from '../src/firestore/tasks.js';
import { withEmulator } from './helpers.js';   // testing-and-deploy.md가 소유한다

const ALICE = 'alice-sub';
const BOB = 'bob-sub';

describe('소유권 경계', () => {
  it('남의 작업은 null — 소유자는 자기 것을 보낸 그대로 받는다', () => withEmulator(async () => {
    const task = await createTask(ALICE, { title: '내 작업', status: 'done' });
    expect(task.status).toBe('done');                      // ✅ status를 하드코딩하면 빨개진다
    expect(await getTask(BOB, task.id)).toBeNull();
    // ✅ 긍정 짝이 없으면 getTask를 통째로 `return null`로 바꿔도 초록이다
    expect((await getTask(ALICE, task.id))?.title).toBe('내 작업');
  }));

  it('남의 작업은 수정도 삭제도 NOT_FOUND — 자기 것은 반영되고 지워진다', () => withEmulator(async () => {
    const task = await createTask(ALICE, { title: '원본', status: 'open' });
    expect(task.status).toBe('open');                      // ✅ 'done' 하드코딩도 막는 대조군
    await expect(updateTask(BOB, task.id, { title: '탈취' })).rejects.toMatchObject({ code: 'NOT_FOUND' });
    await expect(deleteTask(BOB, task.id)).rejects.toMatchObject({ code: 'NOT_FOUND' });
    expect((await getTask(ALICE, task.id))?.title).toBe('원본');       // ✅ 정말 남았는가
    expect((await updateTask(ALICE, task.id, { title: '수정' })).title).toBe('수정');
    await deleteTask(ALICE, task.id);
    expect(await getTask(ALICE, task.id)).toBeNull();                  // ✅ 정말 지워지는가
  }));
});
```

나머지 둘은 5절의 커서 테스트(동시각 문서 7개를 누락·중복 없이 넘긴다)와 목록 격리 테스트
(`listTasks`가 남의 작업을 담지 않고 자기 것은 전부 담는다)로, 파일 전체가 **4개**다.

<!-- verified: 위 4개를 에뮬레이터에서 돌려 기준선 초록을 확인하고, 구현에 돌연변이 8종을 하나씩 심어 재실행 -->
실측: 기준선 4개는 초록이었고 **돌연변이 8종이 전부 빨간색을 냈다** — `getTask`의 소유권 검사
제거(1 실패) · `getTask`를 항상 `null`로(2) · `createTask`가 `status` 하드코딩(1) · `createTask`가
`ownerId`를 무시(3) · `orderBy('__name__')` 제거(1) · `deleteTask`를 맨 `delete()`로(1) ·
`where('ownerId')` 제거(2) · `updateTask`의 소유권 검사 제거(1).

## 오용 목록 ① — 다른 SDK·다른 축의 관용구 → 이 축의 형태

| 구 습관 | 현재 형태 (이 축) |
| --- | --- |
| `admin.firestore()`로 인스턴스를 얻는다 | `firestore`(`src/firestore/client.ts`) — `firebase-admin`은 정책이 막는다 |
| `snap.data() as Task` | converter를 붙인 참조에서 읽는다 — 캐스팅은 3절에서 셋을 거짓말했다 |
| 읽고 나서 `.filter(t => t.ownerId === …)` | `where('ownerId', '==', ownerId)` — 거를 때는 이미 읽은 뒤다 |
| `offset`/`skip` 페이지네이션 | 커서. `offset`은 건너뛴 문서까지 과금되고 삽입에 흔들린다 |
| `orderBy('createdAt')` 하나로 페이지를 나눈다 | `__name__`을 2차 키로 붙인다 — 5절에서 7개 중 5개가 사라졌다 |
| `get` → 확인 → `update` | `runTransaction` 안에서 셋 다. 6절에서 문서가 되살아났다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `getTask(ownerId, taskId)` vs 뒤집힌 순서 | 둘 다 `string`이라 타입 검사가 잡지 못한다. **소유자가 먼저다** |
| `null` 반환 vs `AppError` | 조회는 `null`(정상 흐름), 변이는 `NOT_FOUND`(요청이 이루어지지 않았다) |
| `runTransaction` vs `batch` | 배치는 **읽지 않는다** — 소유권 확인이 필요하면 트랜잭션이다 |
| `startAfter` vs `startAt` | 커서는 **다음** 항목부터다. `startAt`은 경계 문서를 두 페이지에 걸친다 |
| `ref.create()` vs `ref.set()` | `create`는 이미 있으면 gRPC 6으로 실패한다. 생성에는 `create`가 맞다 |
