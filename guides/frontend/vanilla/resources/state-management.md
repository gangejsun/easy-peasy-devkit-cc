<!-- epcc-pack: frontend/vanilla v3.14.0 -->
# 상태 관리 — 모듈 스코프 스토어와, 반환되지 않으면 새는 해지 함수

소유: `src/store/create.js`의 `createStore`·`derive`와 `src/store/tasks.js`의 `tasksStore`.
소유하지 않는 것 — 스토어가 다루는 `Task` 타입은 `resources/types-and-testing.md`,
구독을 소비하는 컴포넌트(`mountTaskList`)는 `resources/component-patterns.md`,
비동기 적재의 3상태(`createResource`)는 `resources/loading-error-states.md`가 소유한다.
서버에서 값을 가져오는 일 자체는 이음매의 `data-fetching` 슬롯이다.

## 1. 결정 트리 — 이 상태를 어디에 두는가

**기본값은 스토어가 아니다.** 프레임워크가 없으므로 스토어를 하나 만들 때마다 해지해야 할
구독이 하나 늘어난다. 위에서부터 처음 맞는 칸에서 멈춘다.

| 이 상태는… | 두는 곳 | 왜 |
| --- | --- | --- |
| 새로고침·공유·뒤로가기에서 살아 있어야 한다 | URL (`resources/routing.md`) | 링크가 곧 상태다 |
| 한 함수 안에서 생겼다 사라진다 | 지역 변수 | 구독이 없으면 해지도 없다 |
| 한 컴포넌트의 열림/닫힘·포커스 | 그 컴포넌트의 클로저 | 밖에서 읽을 사람이 없다 |
| 요청 하나의 진행·실패 | `createResource` | 3상태와 취소가 이미 묶여 있다 |
| **두 곳 이상이 같은 값을 읽고, 한 곳이 쓴다** | 모듈 스코프 스토어 | 여기서부터가 스토어다 |
| 로그인 여부 | 이음매의 `session` | 축이 정하지 않는다 |

「나중에 필요할지도 모르니 스토어에」는 이 축에서 특히 비싸다 — 해지를 잊은 구독은
테스트에서 보이지 않고 라우트 전환마다 쌓인다.

## 2. 스토어 팩토리 (`src/store/create.js`)

`@template T`가 이 파일의 전부다. **빠뜨리면 스토어에 담긴 값이 전부 `any`가 되고**,
`checkJs`가 켜져 있어도 오탈자 하나 잡지 못한다.

```js
// src/store/create.js
/**
 * @template T
 * @param {T} initial
 * @returns {{ get(): T, set(next: T | ((prev: T) => T)): void, subscribe(fn: (value: T) => void): () => void }}
 */
export function createStore(initial) {
  let value = initial;
  /** @type {Set<(value: T) => void>} */
  const listeners = new Set();

  return {
    get: () => value,
    set(next) {
      const resolved = typeof next === 'function'
        ? /** @type {(prev: T) => T} */ (next)(value)
        : next;
      if (Object.is(resolved, value)) return;
      value = resolved;
      for (const fn of listeners) fn(value);
    },
    subscribe(fn) {
      listeners.add(fn);
      fn(value);
      return () => listeners.delete(fn);
    },
  };
}
```

세 가지가 계약이다.

- **`subscribe`는 등록 즉시 현재 값으로 한 번 부른다.** 그래서 마운트 코드에 「첫 렌더」와
  「이후 갱신」 두 경로가 생기지 않는다 — 구독이 곧 렌더다
- **`subscribe`의 반환값은 해지 함수다.** 이 축에는 언마운트 훅이 없다. 반환하지 않으면
  해지할 방법 자체가 사라진다
- **동일성 비교는 `Object.is`, 즉 참조 비교다.** 새 객체 리터럴은 내용이 같아도 통지한다.
  그래서 §5의 「한 번의 `set`」이 중요해진다

같은 팩토리를 `@param {*}`로 얼버무린 판과 나란히 두면 차이가 드러난다 — 오탈자
`store.get().items[0].titel`이 제네릭 판에서는 `TS2551`로 잡히고 `*` 판에서는 **오류가
하나도 나지 않는다.** <!-- verified: typescript@7.0.2 checkJs+strict 로 두 판을 같은 파일에서 대조 실행 -->

## 3. 구독과 해지 — 만든 쪽이 반환하고, 받은 쪽이 보관한다

기계는 **반환하는 것**은 볼 수 있지만 **호출자가 그것을 버리는 것**은 보지 못한다.
해지 함수를 받아 놓고 쓰지 않는 것이 이 축의 대표적 누수다.

```js
// ❌ 해지 함수를 버렸다 — 이 구독은 페이지가 닫힐 때까지 산다
tasksStore.subscribe((s) => { root.textContent = String(s.items.length); });

// ✅ 보관하고, 정리 함수가 그것을 부른다
function mountCounter(root) {
  const offTasks = tasksStore.subscribe((s) => { root.textContent = String(s.items.length); });
  return () => offTasks();
}
```

구독이 둘 이상이면 배열에 모아 한 번에 푼다. 정리 함수는 **여러 번 불려도 안전해야 한다** —
`Set.delete`는 없는 원소에 조용히 `false`를 돌려주므로 이 구현이 그 조건을 만족한다.
`mountTaskList`처럼 위임 해지까지 함께 반환하는 컴포넌트도 같은 형태를 쓴다.

```js
// 구독 여러 개를 하나의 정리 함수로 묶는다
const offs = [
  tasksStore.subscribe((s) => { list.textContent = String(s.items.length); }),
  openCount.subscribe((n) => { badge.textContent = String(n); }),
];
return () => offs.forEach((off) => off());
```

## 4. 파생 값 (`src/store/create.js`)

파생은 **읽기 전용이다.** `set`을 만들지 않는 것이 설계다 — 만들면 같은 진실이 두 곳에
생기고, 둘이 갈라진 순간 어느 쪽이 맞는지 판정할 근거가 없다.

```js
// src/store/create.js
/**
 * @template T, U
 * @param {{ get(): T, subscribe(fn: (value: T) => void): () => void }} store
 * @param {(value: T) => U} selector
 * @returns {{ get(): U, subscribe(fn: (value: U) => void): () => void }}
 */
export function derive(store, selector) {
  return {
    get: () => selector(store.get()),
    subscribe(fn) {
      let prev = /** @type {U | undefined} */ (undefined);
      let primed = false;
      return store.subscribe((value) => {
        const next = selector(value);
        if (primed && Object.is(next, prev)) return;
        prev = next;
        primed = true;
        fn(next);
      });
    },
  };
}
```

`derive`의 해지 함수는 **원본 스토어의 해지 함수를 그대로 돌려준다.** 파생을 해지하면
원본 구독도 함께 풀린다 — 파생마다 별도의 수명을 관리할 필요가 없다.

**선택자는 원시값을 돌려주는 것이 기본이다.** `Object.is` 비교이므로 매번 새 배열을
만드는 선택자는 아무것도 걸러내지 못한다.

```js
// ❌ 호출마다 새 배열이라 원본이 바뀔 때마다 통지가 나간다
const openTasks = derive(tasksStore, (s) => s.items.filter((t) => t.status === 'open'));

// ✅ 개수·플래그·id 배열의 길이처럼 비교 가능한 값으로 좁힌다
const openCount = derive(tasksStore, (s) => s.items.filter((t) => t.status === 'open').length);
```

목록 자체가 필요하면 파생하지 말고 구독 안에서 그때그때 계산한다. 렌더 함수는 어차피
전체를 다시 그린다.

## 5. 도메인 스토어 (`src/store/tasks.js`)

`items`(순서)와 `byId`(조회)를 **함께** 둔다. 단건 갱신이 목록 순회를 요구하지 않게 하려는
것이고, 그 대가로 **두 필드가 항상 같은 `set` 안에서 바뀌어야 한다.** 나눠서 두 번 부르면
그 사이에 구독자가 반쪽 상태를 렌더한다.

```js
// src/store/tasks.js
import { createStore } from './create.js';
/** @typedef {import('../schemas/task.js').Task} Task */
/** @typedef {{ items: Task[], byId: Record<string, Task> }} TasksState */

export const tasksStore = createStore(/** @type {TasksState} */ ({ items: [], byId: {} }));
```

갱신은 같은 모듈 안의 이름 있는 함수로 감싼다 — 호출처마다 `set`의 형태를 다시 쓰면
`byId` 갱신을 빠뜨리는 곳이 반드시 하나 생긴다. **이 둘이 스토어의 공개 쓰기 표면이다**:
컴포넌트도, 이음매의 `fetchTasks`·`createTask` 결과도 여기로 들어온다. `tasksStore.set`을
모듈 밖에서 직접 부르는 자리가 생기면 그 자리가 다음 결함이다.

```js
// src/store/tasks.js — 목록 교체와 단건 upsert
/** @param {Task[]} tasks @returns {void} */
export const replaceTasks = (tasks) => tasksStore.set({
  items: tasks,
  byId: Object.fromEntries(tasks.map((t) => [t.id, t])),
});

/** @param {Task} task @returns {void} */
export const upsertTask = (task) => tasksStore.set((prev) => {
  const exists = task.id in prev.byId;
  return {
    items: exists ? prev.items.map((t) => (t.id === task.id ? task : t)) : [...prev.items, task],
    byId: { ...prev.byId, [task.id]: task },
  };
});
```

- **스토어에 들어가는 것은 이미 파싱된 `Task`다.** 경계 파서(`parseTask`)를 통과하지 않은
  값을 넣으면 `TasksState`의 타입 주장이 그 순간 거짓이 된다
- **갱신 함수 형태(`set((prev) => …)`)를 쓴다.** `get()` 후 `set()`을 따로 부르면 그 사이의
  다른 갱신을 덮어쓴다
- `status`는 소문자 `'open'`·`'done'`이다 — `TaskStatus`가 정한 **값**을 그대로 쓴다

## 6. 스토어를 쓰지 말 자리

| 상황 | 대신 |
| --- | --- |
| 서버에서 막 받은 응답의 로딩·에러 | `createResource` — 3상태와 취소가 함께 온다 |
| 현재 라우트·쿼리 파라미터 | URL이 원본이다. 스토어에 복사하면 뒤로가기와 갈라진다 |
| DOM에서 읽을 수 있는 값 (`input.value`·스크롤 위치) | 필요할 때 읽는다. 미러링은 동기화 버그를 만든다 |
| 파생 가능한 값 (개수·필터 결과·정렬) | `derive`. 별도 필드로 저장하면 갱신을 잊는다 |
| 로그인 사용자 | 이음매의 `session` |
| 한 번 쓰고 버리는 폼 초안 | 지역 변수. 스토어에 두면 다음 방문에 남는다 |

## 7. 해지를 증명하는 테스트 (`test/store.test.js`)

**「해지 함수를 반환한다」는 단언은 차단 증명이 아니다.** 반환값이 함수인 것과 그 함수가
실제로 통지를 끊는 것은 다르다. 긍정 경로(해지 전에는 받는다)를 **같은 `it` 안에** 짝으로 건다.

<!-- file: test/store.test.js -->
```js
// test/store.test.js
import { describe, it, expect, vi } from 'vitest';
import { createStore, derive } from '../src/store/create.js';

describe('createStore', () => {
  it('구독은 즉시 한 번 받고, 해지 후에는 받지 않는다', () => {
    const store = createStore(0);
    /** @type {number[]} */
    const seen = [];
    const off = store.subscribe((v) => seen.push(v));
    expect(seen).toEqual([0]);
    store.set(1);
    expect(seen).toEqual([0, 1]);
    off();
    store.set(2);
    expect(seen).toEqual([0, 1]);
    expect(store.get()).toBe(2);
  });

  it('같은 값 대입은 통지하지 않는다', () => {
    const store = createStore('open');
    const fn = vi.fn();
    store.subscribe(fn);
    store.set('open');
    expect(fn).toHaveBeenCalledTimes(1);
    store.set('done');
    expect(fn).toHaveBeenCalledTimes(2);
  });
});

describe('derive', () => {
  it('선택값이 바뀔 때만 통지하고, 해지가 원본까지 끊는다', () => {
    const store = createStore({ items: [1], other: 'a' });
    const len = derive(store, (s) => s.items.length);
    const fn = vi.fn();
    const off = len.subscribe(fn);
    store.set({ items: [1], other: 'b' });
    expect(fn).toHaveBeenCalledTimes(1);
    store.set({ items: [1, 2], other: 'b' });
    expect(fn).toHaveBeenCalledTimes(2);
    off();
    store.set({ items: [], other: 'b' });
    expect(fn).toHaveBeenCalledTimes(2);
  });
});
```

`off()` 뒤의 `store.get()`이 `2`인 것을 함께 단언하는 이유는, 해지가 **스토어를 멈추는 것이
아니라 이 구독만 끊는 것**임을 고정하기 위해서다. 두 번째 `it`에서 `Object.is` 비교를
지우면 첫 단언이 즉시 빨개진다. <!-- verified: vitest@4.1.11 + happy-dom@20.11.6 으로 두 형태 대조 실행 -->

## 오용 목록 ① — Redux · Zustand 습관 → 모듈 스코프 스토어 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `dispatch({ type: 'ADD' })` + 리듀서 | `upsertTask(task)` — 이름 있는 함수가 곧 액션이다 |
| `useSelector(s => s.x)` | `derive(store, (s) => s.x)` + `subscribe` |
| `useStore()` 훅으로 구독 | `subscribe`가 반환한 해지 함수를 정리 함수에 넣는다 |
| 훅이 언마운트에 알아서 해지 | **아무도 해지하지 않는다.** 반환값을 보관하는 것이 계약이다 |
| `createSlice`로 스토어 하나에 전부 | 도메인마다 모듈 하나. `src/store/tasks.js` |
| `immer`로 초안 변형 | 새 객체를 만든다 — `Object.is` 비교가 그것을 전제한다 |
| `<Provider>`로 주입 | 모듈 import. SPA에 트리가 하나뿐이라 주입할 대상이 없다 |
| `subscribeWithSelector` 미들웨어 | `derive`가 그 자리다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `store.set(v)` vs `store.set((prev) => …)` | 이전 값을 읽어야 하면 언제나 뒤 |
| `derive` vs 구독 안에서 계산 | 원시값으로 좁혀지면 앞, 배열·객체를 만들면 뒤 |
| `subscribe` vs `get` | 값이 바뀔 때 반응해야 하면 앞, 지금 한 번 읽으면 뒤 |
| 모듈 스코프 스토어 vs 컴포넌트 클로저 | 읽는 곳이 둘 이상이면 앞 |
| 스토어 vs URL | 새로고침·공유에서 살아야 하면 URL |
| `items` vs `byId` | 순서·렌더는 앞, 단건 조회·존재 판정은 뒤. **쓸 때는 항상 둘 다** |
| `off()` 호출 vs 참조만 보관 | 보관은 절반이다. 정리 함수가 실제로 부르는지까지가 계약이다 |
