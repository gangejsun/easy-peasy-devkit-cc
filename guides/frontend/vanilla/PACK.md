<!-- epcc-pack: frontend/vanilla v3.14.0 verified 2026-08-24 vite@8 zod@4 vitest@4 happy-dom@20 typescript@7 -->

# vanilla 축 팩 — 허브 조각

조립 시 `SKILL.md`로 옮겨지는 조각들이다. 각 조각은 `<!-- pack-slot: 이름 -->` ~
`<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀 조합이 바뀌어도 그대로 쓰인다.
파일 끝의 「이음매가 채울 것」 표에 있는 슬롯만 이음매가 새로 쓴다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
index.html                   # 단일 진입점. <template> 마크업과 **@layer 순서 선언**이 여기 산다
vite.config.js               # defineConfig 를 **vitest/config** 에서 가져온다 (vite 쪽은 test 키에서 TS2769)
jsconfig.json                # **checkJs: true** — JSDoc 주석을 타입으로 검사한다
src/
├── main.js                  # 부팅만 — config 로드 → 라우터 start() → 정리 함수 보관
├── config.js                # 빌드 시점 환경 값을 zod 로 파싱하는 **유일한 파일**
├── schemas/
│   └── task.js              # TaskSchema · TaskStatus · parseTask (값은 소문자 'open'·'done')
├── store/
│   ├── create.js            # createStore · derive — @template 이 없으면 값이 전부 any 다
│   └── tasks.js             # tasksStore — items 와 byId 를 같은 set 안에서 바꾼다
├── dom/
│   ├── el.js                # el · fromTemplate — 문자열 자식은 textContent 로 넣는다
│   └── delegate.js          # delegate(root, type, selector, handler) → 해지 함수
├── components/
│   ├── task-list.js         # mountTaskList — **반환이 정리 함수다** (언마운트 훅이 없다)
│   └── task-list.css        # 이 컴포넌트가 소유하는 토큰은 여기 한 곳에서만 정의한다
├── routes/
│   └── tasks.js             # 라우트 화면 모듈 — render(params) 는 **정리 함수를 반환한다**
├── router/
│   ├── index.js             # createRouter — 각 라우트 render 는 정리 함수를 반환한다
│   ├── links.js             # interceptLinks — 수정자 키·가운데 클릭·target 은 가로채지 않는다
│   └── return-to.js         # safeReturnTo — 보안 원시함수. 벡터 12건을 통과시킨다
├── state/
│   ├── resource.js          # createResource — fetcher 가 AbortSignal 을 받는 것이 계약이다
│   └── render.js            # renderState — 에러 뷰에 서버 메시지를 그대로 싣지 않는다
├── api/
│   └── tasks.js             # fetchTasks · createTask — **이음매가 소유한다**
├── auth/
│   └── session.js           # session · requireSession — **이음매가 소유한다**
└── styles/
    ├── tokens.css           # 전역 커스텀 프로퍼티 (@layer tokens)
    └── base.css             # 리셋과 요소 기본값 (@layer base)

test/
├── setup.js                 # happy-dom 환경 준비
├── schemas.test.js          # 스키마 단위 — 부분 수정 · 미지 키 · 빈 객체
├── return-to.test.js        # 복귀 경로 — **차단과 정상 통과를 같은 파일에서 단언한다**
└── task-list.test.js        # 컴포넌트 — 정리 함수가 실제로 해지하는지까지 단언한다
```

**프레임워크가 없으므로 정리(cleanup)가 계약이다.** 언마운트 훅이 없다 — 구독·리스너·
`AbortController`를 만든 함수는 **해지 함수를 반환해야 하고**, 호출자는 그것을 보관해야
한다. 반환하지 않는 함수는 누수를 만들고, 그 누수는 테스트에서 보이지 않는다.

**`src/api/`와 `src/auth/`는 이음매 소유다.** 팩은 그것들을 부르기만 한다. 조립 전에는
정의가 없는 것이 정상이고, 게이트가 `--assembly`와 함께 그 충족을 검사한다.

**타입은 주석에만 있다.** `jsconfig.json`의 `checkJs`가 켜져 있어야 그 주석이 검사된다 —
꺼져 있으면 `@param`·`@returns`는 **주장일 뿐 아무것도 강제하지 않는다.**
<!-- /pack-slot -->

<!-- pack-slot: quick-start-axis -->
## Quick Start

**새 컴포넌트**

- [ ] 만들기 전에 `src/components/`를 검색한다 — 같은 역할의 것이 있으면 재사용한다
- [ ] `mount<Name>(root, store)` 형태로 쓰고 **정리 함수를 반환한다** (언마운트 훅이 없다)
- [ ] DOM은 `el`·`fromTemplate`로 만든다 — 문자열 자식은 `textContent`로 들어간다
- [ ] 목록의 이벤트는 `delegate(root, type, selector, handler)`로 뿌리에 위임하고 받은 해지 함수를 정리 함수에서 부른다
- [ ] 내보내는 함수마다 `@param`·`@returns`를 단다 — 없으면 암묵 `any`가 되어 검사를 벗어난다
- [ ] 테스트에서 정리 함수를 부른 뒤 이벤트를 한 번 더 쏘아 핸들러가 불리지 않음을 단언한다
- [ ] `npx tsc -p jsconfig.json --noEmit` — `checkJs`가 꺼져 있으면 위의 주석은 장식이다

**새 라우트**

- [ ] `createRouter`의 routes에 `{ path, render }`를 더하고 `render(params)`가 **정리 함수를 반환하게** 한다
- [ ] `params`는 URL에서 왔다 — 신뢰 입력이 아니므로 경계에서 `safeParse`로 검증한다
- [ ] 데이터는 `createResource(fetcher)`로 받고 `fetcher`가 받은 `AbortSignal`을 그대로 `fetch`에 넘긴다
- [ ] 라우트를 떠날 때 `abort()`가 불리는지 테스트에서 단언한다
- [ ] 로딩·빈·에러를 `renderState`로 나눈다 — 빈은 에러가 아니고, 에러 뷰에 서버 메시지를 그대로 싣지 않는다
- [ ] 보호 라우트면 `requireSession(navigate, safeReturnTo(raw))` — 복귀 경로 검증을 건너뛰면 오픈 리다이렉트가 된다
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

**서버 런타임이 없다.** 배포물은 정적 파일이고 렌더는 전부 브라우저에서 일어난다 — SSR도
라우트 핸들러도 없고, 내려간 값은 사용자가 읽고 고칠 수 있다.

| 구성 요소 | 무엇을 소유하는가 |
| --- | --- |
| `index.html` + `src/router/` | **단일 진입점.** 모든 경로가 같은 문서로 들어오고 History API가 화면을 가른다. 각 라우트의 `render`가 정리 함수를 반환한다 |
| `src/store/` | **모듈 스코프 스토어.** 반응성이 없다 — `subscribe`가 해지 함수를 돌려주고 그 콜백 안에서 DOM을 직접 고친다 |
| `src/dom/` | **DOM 헬퍼.** `el`·`fromTemplate`이 요소 생성의, `delegate`가 이벤트 배선의 유일한 경로다 — 이스케이프와 해지가 함께 따라온다 |
| `src/schemas/` · `src/config.js` | **zod 경계.** 네트워크·`localStorage`·URL의 값이 앱으로 들어오는 문이 여기 하나다 |
| `src/state/` | **상태 기계.** `createResource`가 `AbortSignal`을 fetcher에 주고 `renderState`가 로딩·빈·에러·완료를 갈라 그린다 |
| `jsconfig.json` + `tsc` | **`checkJs` 검사기.** 타입 선언이 JSDoc 주석에만 있으므로 이것이 그 주석을 강제하는 유일한 장치다 |

**`src/api/`와 `src/auth/`는 이음매 소유다** — 팩은 `fetchTasks`·`createTask`·`session`·
`requireSession`을 부르기만 하고 형태는 `ledger.md`의 requires 표가 못박는다. 팩이 양보하지
않는 것 둘: **응답은 `parseTask`로 파싱한다** · **`AbortSignal`을 `fetch`에 넘긴다**.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
## Core Principles (5 Key Rules)

### 1. 반복 UI는 만들기 전에 찾는다 — 그 다음 추출한다

중복의 다수는 추출 실패가 아니라 **탐색 실패**다. 공통 컴포넌트를 새로 만들기 전에
`src/components/`를 검색하고, 그 컴포넌트가 소유하는 토큰은 **그 CSS 한 곳에서만** 정의한다.
```js
// ❌ 새 화면마다 목록 마운트를 다시 짠다 — 검색하지 않았다
function mountArchivedList(root, store) { /* mountTaskList 와 90% 같다 */ }
// ✅ 먼저 찾는다:  rg "export function mount" src/components/
const stopList = mountTaskList(root, tasksStore); // 값은 --task-row-height 로만 바꾼다
```
### 2. 마운트하는 것은 정리 함수를 반환한다

언마운트 훅이 없다. 만든 쪽이 해지 함수를 반환하고 받은 쪽이 보관하는 것까지가 계약이다.
```js
// ❌ 구독만 하고 끝낸다 — 라우트를 나가도 이 구독은 남는다
export function mountTaskList(root, store) { store.subscribe(onChange); }
// ✅ 만든 것을 전부 되돌리는 함수를 돌려준다 — /** @returns {() => void} */
const off = [store.subscribe(onChange), delegate(root, 'click', '[data-task-id]', onRow)];
const cleanup = () => off.forEach((fn) => fn());  // 호출자가 이것을 보관하고 부른다
```
### 3. `innerHTML`을 쓰지 않는다

자동 이스케이프가 없다 — 작업 제목 한 줄이 XSS가 되고 뒤에서 막아 주는 층이 없다.
```js
// ❌ 제목에 들어온 태그가 그대로 해석된다
row.innerHTML = `<span class="title">${task.title}</span>`;
// ✅ 문자열은 textContent 로만, 반복 마크업은 <template> 복제로
const frag = fromTemplate('task-row');
frag.querySelector('.task-list__title').textContent = task.title;
```
### 4. JSDoc은 주장이고 `safeParse`가 검증이다

`@type`은 컴파일 시점 주석이라 런타임에 아무 일도 하지 않는다 — `tsc`는 믿고 통과시킨다.
```js
// ❌ 주장일 뿐이다 — 틀린 모양은 화면에서 처음 드러난다
/** @type {Task} */
const task = await res.json();
// ✅ 경계에서 파싱한다 (응답 · localStorage · URL)
const task = parseTask(await res.json());
```
### 5. 환경은 `config` 한 곳에서 읽는다

`src/config.js`가 모듈 최상위에서 파싱하므로 값이 틀리면 **첫 요청이 아니라 부팅이 실패한다**.
```js
// ❌ 기준 URL을 부르는 곳마다 적는다 — 검증도, 바꿀 자리도 하나가 아니다
const res = await fetch('https://api.example.com/tasks', { signal });
// ✅ 검증된 값 하나를 읽는다 (import { config } from '../config.js')
const res = await fetch(`${config.VITE_API_BASE}/tasks`, { signal });
```
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

**경로 별칭(`@/`)을 쓰지 않는다.** 번들러 설정과 `jsconfig.json`의 `paths`가 갈라지면 Vite는
해소하는데 검사기는 못 찾는다. 상대 경로로 적고 **확장자 `.js`를 항상 붙인다**.
```js
// src/components/ 기준. 필요한 것만 골라 쓴다
import { config } from '../config.js';
import { TaskSchema, TaskCreateSchema, parseTask } from '../schemas/task.js';
import { tasksStore } from '../store/tasks.js';
import { el, fromTemplate } from '../dom/el.js';
import { delegate } from '../dom/delegate.js';
import { createResource } from '../state/resource.js';
import { renderState } from '../state/render.js';
import { createRouter } from '../router/index.js';
import { interceptLinks } from '../router/links.js';
import { safeReturnTo } from '../router/return-to.js';
// 이음매 소유 — 조립 전에는 정의가 없는 것이 정상이다
import { fetchTasks, createTask } from '../api/tasks.js';
import { session, requireSession } from '../auth/session.js';
```
<!-- /pack-slot -->

<!-- pack-slot: anti-patterns-axis -->
## Anti-Patterns — 이 축에서 실제로 관찰되는 것

| 부류 | 관찰되는 형태 | 이 축의 사실 |
| --- | --- | --- |
| 프레임워크 습관 | 값을 바꾸면 화면이 따라 바뀐다고 기대한다 | 반응성이 없다 — `set` 뒤 `subscribe` 콜백에서 DOM을 직접 고친다 |
| 프레임워크 습관 | 상태가 바뀔 때마다 컨테이너를 통째로 다시 그린다 | 디핑이 없다 — 전체 교체는 스크롤·포커스·입력값을 날린다. `byId`로 바뀐 행만 고친다 |
| 프레임워크 습관 | 목록에 `key`만 주면 맞춰진다고 본다 | 맞춰 주는 것이 없다 — `data-task-id`로 직접 찾는다 |
| 프레임워크 습관 | 정리를 프레임워크가 알아서 부른다고 본다 | 부르는 것은 호출자다 — `mount*`의 반환값을 담지 않으면 샌다 |
| 해지 함수 유실 | `mountTaskList(root, tasksStore);` — 반환을 받지 않는다 | 드나들 때마다 구독과 위임 리스너가 한 벌씩 더 돈다 |
| 해지 함수 유실 | 라우트의 `render`가 아무것도 반환하지 않는다 | 라우터가 부를 정리가 없다 — 반환이 `createRouter`의 계약이다 |
| 해지 함수 유실 | 라우트를 떠나며 `abort()`를 부르지 않는다 | 늦게 온 앞 응답이 다음 화면의 컨테이너를 덮어쓴다 |
| 해지 함수 유실 | 테스트가 마운트만 하고 정리 함수를 부르지 않는다 | 누수가 초록 뒤에 남는다 — 정리 후 이벤트를 한 번 더 쏘아 단언한다 |
| 검증 대신 주장 | 응답·`localStorage` 값에 `@type`을 붙이고 끝낸다 | tsc가 믿고 통과시킨다 — `parseTask`·`safeParse`가 그 자리다 |
| 검증 대신 주장 | URL 파라미터를 `@type {string}`으로 받고 그대로 쓴다 | 복귀 경로면 오픈 리다이렉트가 된다 — `safeReturnTo`를 통과시킨다 |
| 검증 대신 주장 | JSDoc을 빠뜨린 export | 「타입이 없다」가 아니라 **검사되지 않는다** — 암묵 `any`다 |
| 인자 순서 | `delegate`의 `type`·`selector`를 바꿔 쓴다 | 둘 다 문자열이라 검사기가 못 잡는다 — 조용히 아무 일도 안 일어난다 |
<!-- /pack-slot -->

> **아래 슬롯은 L2가 쓴다** (L0는 디렉토리 트리만 동결한다):
> `core-principles-axis` · `common-imports-axis` · `architecture-overview` ·
> `quick-start-axis` · `anti-patterns-axis`.

## 이음매가 채울 것

| 슬롯 | 무엇을 |
| --- | --- |
| `data-fetching` | 실제 API 호출 · 봉투 파싱 · 캐시. **응답을 `parseTask`로 파싱하고 `AbortSignal`을 `fetch`에 넘긴다** |
| `auth-and-session` | 토큰·세션 보관과 갱신 · 로그인/로그아웃 흐름 · 보호 라우트 판정. **복귀 경로는 `safeReturnTo`를 반드시 통과시킨다** |
| `complete-example` | 스키마 → 스토어 → 컴포넌트 → 라우트 → 테스트 관통 |
