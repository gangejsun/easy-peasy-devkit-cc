<!-- epcc-pack: frontend/vanilla v3.14.0 -->
# 컴포넌트 패턴 — 마운트가 정리 함수를 돌려주는 것까지가 컴포넌트다

소유: `src/dom/el.js`의 `el`·`fromTemplate` · `src/dom/delegate.js`의 `delegate` ·
`src/components/task-list.js`의 `mountTaskList`. 소유하지 않는 것 — 클래스 이름 규약과
`--task-row-height` 같은 컴포넌트 토큰은 `resources/styling.md`, 스토어와 `upsertTask`는
`resources/state-management.md`, 라우트 전환은 `resources/routing.md`, 적재 중·빈·에러
화면은 `resources/loading-error-states.md`, 데이터 조달은 이음매의 `data-fetching`이다.

## 1. 결정 트리 — 이 DOM을 무엇으로 만드는가

위에서부터 처음 맞는 칸에서 멈춘다. **기본은 「만들지 않는다」다** — 이미 있는 노드를
`querySelector`로 찾아 고치는 쪽이 언제나 싸고, 포커스·스크롤을 지킨다.

| 만들 것 | 쓸 것 | 왜 |
| --- | --- | --- |
| 반복되는 행·카드 | `fromTemplate('task-row')` | 마크업이 `index.html`에 남아 검색·검토·번역이 된다 |
| 사용자 입력이 들어가는 텍스트 | `textContent` · `el`의 문자열 자식 | 자동 이스케이프가 없다 |
| 사용자 입력이 들어가는 `href`·`src` | 스킴을 **먼저 검사한다** | `el`은 검사하지 않는다 — `javascript:`는 `textContent`로 막히지 않는다 |
| 목록 항목의 클릭·입력 | `delegate(root, …)` **한 번** | 항목마다 달면 해지 대상이 N개가 된다 |

## 2. 요소 생성과 템플릿 복제 (`src/dom/el.js`)

`el`은 **문자열 자식을 텍스트 노드로만** 넣는다. 이 축에서 이스케이프가 사는 유일한
자리이고, 뒤에서 막아 주는 층이 없다.

<!-- file: src/dom/el.js -->
```js
// src/dom/el.js
/**
 * @param {string} tag
 * @param {Record<string, unknown>} [props]
 * @param {(Node | string)[]} [children]
 * @returns {HTMLElement}
 */
export function el(tag, props = {}, children = []) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key.startsWith('on') && typeof value === 'function') {
      node.addEventListener(key.slice(2).toLowerCase(), /** @type {EventListener} */ (value));
    } else if (value != null && value !== false) {
      node.setAttribute(key, String(value));
    }
  }
  for (const child of children) {
    node.append(typeof child === 'string' ? document.createTextNode(child) : child);
  }
  return node;
}

/**
 * @param {string} id
 * @returns {DocumentFragment}
 */
export function fromTemplate(id) {
  const tpl = document.getElementById(id);
  if (!(tpl instanceof HTMLTemplateElement)) {
    throw new Error(`<template id="${id}"> 가 문서에 없다`);
  }
  return /** @type {DocumentFragment} */ (tpl.content.cloneNode(true));
}
```

`el('span', {}, ['<img src=x onerror="alert(1)">'])`는 자식 **요소가 0개**다. 반면 `props`는
손대지 않은 채 속성이 되므로 — `el('a', { href: 'javascript:…' })`의 `href`는 그대로 남는다 —
**`props`에 사용자 입력을 싣지 않는 것이 규칙**이다(경로 검증은 `resources/routing.md`).
<!-- verified: happy-dom@20.11.6 에서 childElementCount===0 과 getAttribute('href') 를 단언으로 관측 -->

반복 마크업은 `<template>`에서 복제한다. 위 파일의 `fromTemplate`은 **복제본**을 주므로 원본이 남고,
마크업이 `index.html`에 있으면 검색·검토·번역이 되며 문자열 조립이 사라진다.

```html
<!-- index.html — 행 마크업. 클래스 이름 규약은 resources/styling.md 소유다 -->
<template id="task-row">
  <li class="task-list__row">
    <button class="task-list__toggle" type="button" aria-pressed="false">완료 전환</button>
    <span class="task-list__title"></span>
  </li>
</template>
```

## 3. 이벤트 위임 (`src/dom/delegate.js`)

**인자 순서가 이 팩에서 가장 위험한 자리다.** `type`과 `selector`가 **둘 다 문자열**이라
뒤바꿔도 `tsc`가 통과시키고 런타임 오류도 없다 — 그냥 아무 일도 일어나지 않는다.

<!-- file: src/dom/delegate.js -->
```js
// src/dom/delegate.js
/**
 * @param {Element} root
 * @param {string} type
 * @param {string} selector
 * @param {(event: Event, target: Element) => void} handler
 * @returns {() => void}
 */
export function delegate(root, type, selector, handler) {
  /** @param {Event} event */
  const onEvent = (event) => {
    const from = event.target;
    if (!(from instanceof Element)) return;
    const target = from.closest(selector);
    if (target && root.contains(target)) handler(event, target);
  };
  root.addEventListener(type, onEvent);
  return () => root.removeEventListener(type, onEvent);
}
```

```js
// ❌ 순서를 뒤바꿨다 — 'click' 이 선택자로, 선택자가 이벤트 종류로 간다. 조용히 죽는다
delegate(root, '[data-task-id]', 'click', onRow);
// ✅ 뿌리 → 이벤트 종류 → 선택자 → 핸들러
const offRow = delegate(root, 'click', '[data-task-id]', onRow);
```

핸들러가 받는 `target`은 `event.target`(눌린 `<button>`)이 아니라 `closest`가 찾은 **행**이고,
`root.contains(target)`은 `closest`가 뿌리 밖까지 올라간 경우를 막는다.

## 4. 행을 갈아 끼우지 않고 고친다 (`src/components/task-list.js`)

디핑이 없다. 그래서 「상태가 바뀌면 컨테이너를 통째로 다시 그린다」가 이 축에서는
**스크롤·포커스·입력값을 날리는 결함**이다 — 있는 행은 고치고, 사라진 행만 지운다.

<!-- file: src/components/task-list.js -->
```js
// src/components/task-list.js
import { el, fromTemplate } from '../dom/el.js';
import { delegate } from '../dom/delegate.js';
import { upsertTask } from '../store/tasks.js';
/** @typedef {import('../schemas/task.js').Task} Task */

/** @param {Task} task @returns {HTMLElement} */
function createRow(task) {
  const row = fromTemplate('task-row').querySelector('.task-list__row');
  if (!(row instanceof HTMLElement)) throw new Error('task-row 템플릿에 .task-list__row 가 없다');
  row.dataset.taskId = task.id;
  return row;
}

/** @param {HTMLElement} row @param {Task} task @returns {void} */
function patchRow(row, task) {
  const title = row.querySelector('.task-list__title');
  if (title) title.textContent = task.title;
  row.classList.toggle('task-list__row--done', task.status === 'done');
  row.querySelector('.task-list__toggle')?.setAttribute('aria-pressed', String(task.status === 'done'));
}

/** @param {HTMLElement} list @param {Task[]} tasks @returns {void} */
function syncRows(list, tasks) {
  /** @type {Map<string, HTMLElement>} */
  const stale = new Map();
  for (const node of list.children) {
    if (node instanceof HTMLElement && node.dataset.taskId) stale.set(node.dataset.taskId, node);
  }
  for (const task of tasks) {
    const row = stale.get(task.id) ?? createRow(task);
    stale.delete(task.id);
    patchRow(row, task);
    list.append(row);   // 이미 문서에 있는 노드면 append 는 '옮긴다' — 순서가 맞춰진다
  }
  for (const gone of stale.values()) gone.remove();
}

/**
 * @param {Element} root
 * @param {typeof import('../store/tasks.js').tasksStore} store
 * @returns {() => void}
 */
export function mountTaskList(root, store) {
  const list = el('ul', { class: 'task-list' });
  root.replaceChildren(list);

  const offStore = store.subscribe((state) => syncRows(list, state.items));

  const offClick = delegate(root, 'click', '[data-task-id]', (_event, target) => {
    const id = /** @type {HTMLElement} */ (target).dataset.taskId;
    const task = id ? store.get().byId[id] : undefined;
    if (task) upsertTask({ ...task, status: task.status === 'open' ? 'done' : 'open' });
  });

  return () => {
    offStore();
    offClick();
  };
}
```

## 5. 마운트와 정리 계약 (`src/components/task-list.js`)

전문은 4절이 싣는다. `subscribe`가 **등록 즉시 현재 값으로 한 번 방출**하므로 `mountTaskList`에
「첫 렌더」가 따로 없다 — 초기 렌더를 손으로 한 번 더 부르면 **두 번 그려진다.**
반환값은 **정리 함수**다. 버리면 스토어 구독과 위임 리스너가 남아 누수가 된다.

- **반환값이 유일한 언마운트 경로다.** 라우트의 `render`는 이 값을 그대로 돌려주면 된다
- **정리 함수는 만든 것을 전부 되돌린다.** 하나만 부르면 나머지 절반이 남고 그 절반은
  테스트에서 보이지 않는다 — §7이 그것을 잡는 장치다
- **쓰기는 `upsertTask`로 한다**(`store.set` 직접 호출은 `byId` 갱신을 빠뜨린다)

## 6. 공통 컴포넌트 — 만들기 전에 찾는다

**중복의 다수는 추출 실패가 아니라 탐색 실패다.** 이 축에는 컴포넌트를 찾아 주는
레지스트리가 없다. 새 컴포넌트 파일을 만들기 전에 아래를 **반드시** 돌린다.

```bash
rg -n "mount" src/components/                # 이미 있는 마운트 함수를 전부 본다
rg "class=\"task-" index.html src/           # 이 컴포넌트의 마크업이 이미 있는가
```

찾은 것이 90% 같으면 매개변수를 하나 늘린다. 다른 것이 여백·높이·글자 크기뿐이면 새
컴포넌트가 아니라 **토큰 값의 차이**이고 `--task-row-height`로만 바꾼다(`resources/styling.md`).

- **파일 하나 = 마운트 함수 하나 = 클래스 접두사 하나.** `src/components/task-list.js`가
  `.task-list*`를 소유한다. 갈리면 CSS를 지울 때 무엇이 죽는지 모른다
- **스토어를 import하지 않고 `(root, store)`로 받는다.** 정리 함수 반환에는 예외가 없다

## 7. 정리를 증명하는 테스트 (`test/task-list.test.js`)

**「해지 함수를 반환한다」는 단언은 차단 증명이 아니다.** 정리 **전에는 반응하고** 정리
**후에는 반응하지 않는다**를 같은 `it` 안에 짝으로 건다.

<!-- file: test/task-list.test.js -->
```js
// test/task-list.test.js
import { it, expect } from 'vitest';
import { el } from '../src/dom/el.js';
import { mountTaskList } from '../src/components/task-list.js';
import { tasksStore, replaceTasks } from '../src/store/tasks.js';

/** @type {import('../src/schemas/task.js').Task} */
const base = { id: 't1', ownerId: 'u1', title: '보고서 초안', status: 'open', createdAt: '2026-08-24T03:00:00Z' };

/** @returns {HTMLElement} */
function fixture() {
  const tpl = /** @type {HTMLTemplateElement} */ (el('template', { id: 'task-row' }));
  tpl.content.append(el('li', { class: 'task-list__row' }, [
    el('button', { class: 'task-list__toggle', type: 'button' }),
    el('span', { class: 'task-list__title' }),
  ]));
  const root = el('div');
  document.body.append(tpl, root);
  replaceTasks([]);
  return root;
}

it('mountTaskList 의 정리 함수가 구독과 위임을 모두 끊는다', () => {
  const root = fixture();
  const stop = mountTaskList(root, tasksStore);

  replaceTasks([base]);
  const row = /** @type {HTMLElement} */ (root.querySelector('[data-task-id="t1"]'));
  expect(row.querySelector('.task-list__title')?.textContent).toBe('보고서 초안');
  row.click();
  expect(tasksStore.get().byId.t1.status).toBe('done');

  replaceTasks([{ ...base, status: 'done' }]);
  expect(root.querySelectorAll('[data-task-id]')).toHaveLength(1);
  expect(root.querySelector('[data-task-id="t1"]')).toBe(row);

  stop();

  replaceTasks([{ ...base, title: '바뀐 제목' }]);
  expect(row.querySelector('.task-list__title')?.textContent).toBe('보고서 초안');
  row.click();
  expect(tasksStore.get().byId.t1.status).toBe('open');
});
```

`stop()` 앞의 단언이 없으면 뒤의 두 단언은 「전부 고장」과 구별되지 않는다. **돌연변이 다섯이
전부 빨개진다**: `offStore()` 삭제 · `offClick()` 삭제 · `delegate` 반환을 `() => {}`로 교체 ·
`syncRows`의 행 재사용 제거 · `syncRows`를 `list.replaceChildren(...)`으로 대체.
<!-- verified: vitest@4.1.11 + happy-dom@20.11.6 · typescript@7.0.2(checkJs+strict) 로 5회 대조 실행 -->
픽스처가 `tpl.content.append(...)`를 쓰는 이유는 `createElement('template')`이 만든 요소에 그냥
`append`한 자식이 `content`에 들어가는지가 환경마다 갈리기 때문이다. <!-- unverified: 실 브라우저 미실행 · happy-dom@20.11.6 에서 template.append 가 content 로 흡수되는 것만 관측했다 -->

## 오용 목록 ① — React·Vue 습관 → 직접 DOM 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `useEffect(… return cleanup)` · `onUnmounted` | 없다. `mountTaskList`가 반환한 것을 호출자가 부른다 |
| `dangerouslySetInnerHTML` · `v-html` | 대응물이 없다. 반복 마크업은 `fromTemplate` + `textContent` |
| `key={task.id}`로 재조정을 맡긴다 | `row.dataset.taskId` + `Map`으로 직접 짝짓는다 |
| 상태가 바뀌면 컨테이너를 다시 렌더 | `syncRows` — 있는 행은 고치고 사라진 행만 지운다 |
| `onClick={…}`을 항목마다 | `delegate(root, 'click', '[data-task-id]', …)` 한 번 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `delegate(root, type, selector, h)` vs `(root, selector, type, h)` | **언제나 앞.** 둘 다 문자열이라 뒤바꿔도 검사기가 통과시킨다 |
| `event.target` vs 핸들러의 `target` | 실제로 눌린 노드는 앞, `closest`가 찾은 행은 뒤. 배선에 쓰는 것은 뒤 |
| `textContent` vs `props`에 값 싣기 | 사용자 입력은 **언제나 앞**. `href`·`src`는 스킴 검사 없이 뒤로 가지 않는다 |
| `store.set(...)` vs `upsertTask(...)` | 컴포넌트에서는 **언제나 뒤** |
| id로 `querySelector` vs `Map`에 모으기 | **언제나 뒤.** 서버 문자열을 선택자 문법에 넣으면 따옴표 하나로 깨진다 |
