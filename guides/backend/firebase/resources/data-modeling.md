<!-- epcc-pack: backend/firebase v3.14.0 -->
# Firestore 데이터 모델링 — 문서 형태가 곧 규칙의 입력이다

이 파일은 **컬렉션 배치 · 문서 형태(`TaskDoc`) · 컨버터 · 복합 인덱스 · 한도**를 소유한다.
보안 규칙이 여기서 정한 **필드 이름을 문자열로 그대로 참조**하므로, 이 형태가 흔들리면
`resources/security-rules.md`가 통째로 틀린다. 읽기·쓰기 함수(`listTasks`·`createTask` …)는
`resources/data-access.md`가, 입력 스키마는 `resources/input-validation.md`가 소유한다.

## 1. 결정 트리 — 최상위 컬렉션인가 하위 컬렉션인가

| 질문 | 그렇다 | 아니다 |
| --- | --- | --- |
| 소유자를 바꿀 수 있는가 (이관·공유) | 최상위 `tasks/{taskId}` | 다음 질문 |
| 소유자 밖에서 횡단 질의가 필요한가 (관리자 목록·집계) | 최상위 | 다음 질문 |
| 부모 문서와 **함께 지워져야** 하는가 | 어느 쪽도 자동으로 지워주지 않는다 — 아래 실측 | 하위 `users/{uid}/tasks/{taskId}` |

이 팩은 **최상위 `tasks`**를 고정한다. 소유권이 경로가 아니라 `ownerId` 필드에 있으면
문서를 옮기지 않고 이관할 수 있고, 규칙 경로가 `match /tasks/{taskId}` 하나로 닫힌다.

**하위 컬렉션은 부모를 따라 지워지지 않는다.** 에뮬레이터 실측: `users/u1`을 지운 뒤
`users/u1/tasks`를 질의하면 부모는 `exists=false`인데 하위 문서는 **그대로 1건 남아 있다**.
경로만으로 소유권을 표현하면 이 고아 문서에는 소유자가 없다. 하위 컬렉션을 고르더라도
`ownerId`는 문서 안에 **함께** 둔다 — 규칙과 쿼리가 둘 다 필드를 본다.

`collectionGroup('tasks')`는 부모가 무엇이든 같은 이름의 컬렉션을 전부 횡단한다. 실측에서
서로 다른 사용자의 하위 컬렉션 2건이 한 결과로 돌아왔다 — **하위 컬렉션이 격리를 주지
않는다는 증거다.** 격리는 `where('ownerId', '==', ownerId)`가 만든다.

## 2. 문서 형태 (`functions/src/firestore/model.ts`)

`id`는 **문서 ID의 사본**이다. 쿼리 결과를 그대로 직렬화할 수 있고, 규칙이
`request.resource.data.id == taskId`로 사본과 실물의 일치를 강제할 수 있다.

<!-- file: functions/src/firestore/model.ts -->
```ts
// functions/src/firestore/model.ts
import type {
  DocumentData,
  FirestoreDataConverter,
  PartialWithFieldValue,
  QueryDocumentSnapshot,
  Timestamp,
} from 'firebase-admin/firestore';

// 컬렉션 이름을 조립하는 유일한 자리. 규칙의 `match /tasks/{taskId}`와 짝이다 —
// 여기와 규칙 경로가 갈라지면 규칙은 아무도 쓰지 않는 컬렉션을 지킨다.
export const COLLECTION = 'tasks';

// 규칙·스키마·쿼리가 **같은 리터럴 집합**을 쓴다. 늘릴 때 firestore.rules의
// `d.status in ['open', 'done']`도 함께 고친다 — 기계가 짝을 맞춰 주지 않는다.
export type TaskStatus = 'open' | 'done';

export interface TaskDoc {
  id: string;
  title: string;
  status: TaskStatus;
  ownerId: string;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export const taskConverter: FirestoreDataConverter<TaskDoc> = {
  toFirestore(task: PartialWithFieldValue<TaskDoc>): DocumentData {
    return { ...task };
  },
  fromFirestore(snap: QueryDocumentSnapshot): TaskDoc {
    const stored = snap.data() as Omit<TaskDoc, 'id'>;
    // 문서 ID가 권위다. 저장된 `id`가 어긋나도 스냅숏 쪽을 쓴다.
    return { ...stored, id: snap.id };
  },
};
```

`id: 'WRONG'`으로 저장한 문서 `c2`를 컨버터로 읽으면 `id`가 `'c2'`로 돌아온다. 컨버터 없이
`snap.data()`를 쓰면 저장된 `'WRONG'`이 그대로 흘러나온다.
<!-- verified: Firestore 에뮬레이터에 실제로 쓰고 읽어 대조 (firebase-admin@14.3.0) -->

`createdAt`은 서버가 찍는다. 함수 인스턴스의 시계도 믿지 않는다 — 인스턴스마다 다르다.

```ts
// functions/src/firestore/tasks.ts (발췌)
// ❌ 클라이언트·함수 인스턴스의 시각을 문서에 넣는다
await ref.set({ id: ref.id, title, status, ownerId, createdAt: new Date() });
// ✅ 서버가 커밋 시점에 찍는다 — 규칙도 `request.time`으로 이 값을 강제할 수 있다
await ref.set({
  id: ref.id, title, status, ownerId,
  createdAt: FieldValue.serverTimestamp(),
  updatedAt: FieldValue.serverTimestamp(),
});
```

컨버터를 통과해도 `FieldValue.serverTimestamp()`는 `createdAt: Timestamp` 자리에 들어간다 —
`set()`이 받는 타입이 `WithFieldValue<TaskDoc>`이기 때문이다.
<!-- verified: typescript@7.0.2 + firebase-admin@14.3.0으로 tsc 통과(캐스트 없이) -->

## 3. 소유자 필드 — 하나의 필드가 두 경계를 동시에 먹인다

`ownerId`는 장식이 아니라 **두 경계의 공통 입력**이다.

| 경계 | 무엇을 보는가 | 없으면 |
| --- | --- | --- |
| Security Rules (브라우저) | `resource.data.ownerId == request.auth.uid` | 클라이언트가 남의 문서를 읽는다 |
| 애플리케이션 검사 (Cloud Functions) | `where('ownerId', '==', ownerId)` | admin SDK가 규칙을 우회하므로 **경계가 아예 없다** |

```ts
// functions/src/firestore/tasks.ts (발췌) — db는 ./client가 소유한다
const tasks = db.collection(COLLECTION).withConverter(taskConverter);
// ✅ 소유권은 쿼리 안에 있다. 문서 ID만으로 읽으면 남의 것도 읽힌다.
const page = await tasks
  .where('ownerId', '==', ownerId)
  .orderBy('createdAt', 'desc')
  .limit(20)
  .get();
```

`ownerId`는 **인증 컨텍스트에서만** 온다. 요청 본문에서 받으면 위조 필드가 된다 —
그 검증은 `resources/input-validation.md`가 소유한다.

## 4. 복합 인덱스 (`firestore.indexes.json`)

`where` 등식 + 다른 필드 `orderBy`는 **복합 인덱스**를 요구한다. 이 팩이 쓰는 두 쿼리에
각각 하나씩 필요하다 — `(ownerId, status, createdAt)` 하나로 `(ownerId, createdAt)` 쿼리를
덮을 수 없다. 인덱스는 **선행 필드부터** 맞아야 하고 `status` 등식이 빠지면 접두가 어긋난다.
<!-- unverified: 접두 규칙은 문서 지식이다. 에뮬레이터가 인덱스를 강제하지 않아 실측 불가 -->

<!-- file: firestore.indexes.json -->
```json
{
  "indexes": [
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" },
        { "fieldPath": "__name__", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" },
        { "fieldPath": "__name__", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

**여기가 이 축에서 가장 비싼 함정이다. 에뮬레이터는 인덱스를 강제하지도, 이 파일을
검증하지도 않는다.** 실측 두 가지:

- `"indexes": []`인 채로 `where(ownerId) + where(status) + orderBy(createdAt desc)`를 던지면
  에뮬레이터는 **전부 통과시킨다**. 실서비스에서만 그 쿼리가 실패한다.
- `"order"` 대신 `"direction": "UP"`처럼 **틀린 키**를 넣은 파일로 에뮬레이터를 띄워도
  경고 한 줄 없이 정상 기동한다. 이 파일의 오류는 **배포에서만** 드러난다.

그래서 인덱스는 "테스트가 초록이니 됐다"로 판정할 수 없다. 쿼리를 바꾸면 이 파일도 같은
커밋에서 바꾸고, **인덱스를 먼저 배포한 뒤 함수를 배포한다** — 순서는
`resources/testing-and-deploy.md`가 소유한다.

## 5. 비정규화의 대가

문서 모델에는 조인이 없다. 목록 화면이 다른 문서의 값을 필요로 하면 **복사**가 답이고,
복사한 순간 **두 벌을 함께 갱신할 의무**가 생긴다.

| 방식 | 읽기 | 쓰기 | 언제 |
| --- | --- | --- | --- |
| 매번 개별 조회 | 문서 수만큼 읽기 | 싸다 | 목록이 짧고 갱신이 잦다 |
| 값을 복사(비정규화) | 1회 | 원본 갱신 시 **팬아웃 전부** | 목록이 길고 원본이 거의 안 바뀐다 |
| 카운터를 따로 둔다 | 1회 | `FieldValue.increment` | 개수만 필요하다 |

```ts
// functions/src/firestore/tasks.ts (발췌) — 문서와 카운터를 한 원자 단위로 옮긴다
await db.runTransaction(async (tx) => {
  const snap = await tx.get(ref);                    // 읽기를 **전부 먼저**
  if (!snap.exists || snap.get('ownerId') !== ownerId) throw new AppError('NOT_FOUND', '없음');
  tx.update(ref, { status: 'done', updatedAt: FieldValue.serverTimestamp() });
  tx.update(counter, { openCount: FieldValue.increment(-1) });
});
```

트랜잭션은 **모든 읽기가 모든 쓰기보다 앞**이어야 한다. 순서를 뒤집으면 실측에서
`Firestore transactions require all reads to be executed before all writes.`로 즉시 실패한다.
`FieldValue.increment(1)`은 값이 아니라 변환 센티널(`NumericIncrementTransform`)이라
읽지 않고 더한다 — 그래서 카운터에는 경합이 없다.

## 6. 한도 — 전부 에뮬레이터 실측이다

| 한도 | 실측값 | 어떻게 쟀나 |
| --- | --- | --- |
| 문서 전체 크기 | **1,048,576 bytes** — 초과 시 `INVALID_ARGUMENT: maximum entity size is 1048576 bytes` | 400 KB 필드 3개 |
| 단일 필드 값 | **1,048,487 bytes** — `The value of property "title" is longer than 1048487 bytes` | 1 MiB 문자열 1개 |
| `in` 비교값 | **30개** — 31개부터 `'IN' supports up to 30 comparison values.` | 값 개수를 늘려가며 |
| `array-contains` | 쿼리당 **1회** — `Only a single array-contains clause is allowed in a query` | 두 번 건 쿼리 |
| 자동 문서 ID | 20자 | `col.doc().id` |
| 배치 쓰기 건수 | 에뮬레이터는 **1000건도 통과시킨다** — 한도를 강제하지 않는다 | 500·501·1000건 배치 |
| 문서당 쓰기 속도 | 에뮬레이터가 강제하지 않아 **실측 불가** <!-- unverified: 실서비스의 소프트 한도는 여기서 잴 수 없다 --> | — |

마지막 두 줄이 요점이다. **에뮬레이터가 통과시킨 것은 "한도 안"이라는 뜻이 아니다.**
배치 크기와 핫 문서(같은 문서에 몰리는 쓰기)는 여기서 절대 잡히지 않는다 — 카운터를
문서 하나에 몰아 두는 설계는 에뮬레이터에서 영원히 초록이다.

## 오용 목록 ① — 관계형 스키마 → Firestore 문서 모델 관용구 대조표

| 구 습관 (관계형) | 현재 형태 (Firestore) |
| --- | --- |
| 조인으로 소유자 확인 | `ownerId`를 문서에 두고 `where('ownerId', '==', ownerId)` |
| `ON DELETE CASCADE` | 없다. 하위 컬렉션은 부모 삭제 후에도 남는다(실측) — 지우는 코드를 직접 쓴다 |
| 인덱스는 DB가 알아서 | `firestore.indexes.json`에 손으로 적고 **먼저 배포**한다 |
| `COUNT(*)` | 카운터 문서 + `FieldValue.increment` |
| `NOW()` / `DEFAULT CURRENT_TIMESTAMP` | `FieldValue.serverTimestamp()` |
| `WHERE a IN (…)` 값 제한 없음 | `in`은 값 30개까지(실측) |
| 스키마가 열을 강제 | 문서는 무엇이든 받는다 — 강제는 규칙(`hasOnly`)과 Zod 두 곳에서 |
| 정규화가 기본 | 목록 읽기 비용이 문서 수에 비례하므로 복사가 기본, 갱신 의무가 대가 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 하위 컬렉션 vs `ownerId` 필드 | 하위 컬렉션은 격리가 아니다(`collectionGroup`이 뚫는다). 소유권은 언제나 필드 |
| `snap.data()` vs 컨버터 | 컨버터 없이 읽으면 저장된 `id`가 문서 ID와 어긋나도 그대로 나온다 |
| `FieldValue.serverTimestamp()` vs `Timestamp.now()` | 앞은 서버가 커밋 때 찍고, 뒤는 **호출한 인스턴스**의 시계다 |
| `orderBy` 하나 vs 복합 인덱스 | 등식 `where`가 하나라도 붙으면 다른 필드 `orderBy`는 인덱스를 요구한다 |
| 에뮬레이터 통과 vs 인덱스 존재 | 에뮬레이터는 인덱스도, `firestore.indexes.json`의 문법도 검사하지 않는다(실측) |
| `increment` vs 읽고-더해-쓰기 | `increment`는 센티널이라 읽지 않는다. 읽고 쓰면 경합이 생기고 트랜잭션이 필요해진다 |
| 배치 vs 트랜잭션 | 배치는 원자적 쓰기만, 트랜잭션은 **읽은 값에 근거한** 쓰기. 존재·소유 확인은 후자 |
