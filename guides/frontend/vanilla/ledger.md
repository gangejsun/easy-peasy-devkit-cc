<!-- epcc-pack-ledger: frontend/vanilla v3.14.0 -->

# vanilla 팩 — 심볼 원장 (L0 선언본)

저작 전에 메인 세션이 선언한 계약이다. 클러스터를 갈라 병렬로 써도 중복 정의와 **시그니처
추측**이 생기지 않게 하는 유일한 장치다.

**「형태」 열은 의무다.** 소유 파일만 배정하고 형태를 비우면 형제 클러스터가 시그니처를
추측한다 — 실측(node-api)에서 인자 둘이 모두 같은 타입이라 검사기도 게이트도 잡지 못해
모든 단건 조회가 404가 됐다. 인자 **순서** · 반환 · 실패 시 무엇을 하는가 ·
**호출자가 배선해야 하는 것**을 함께 적는다.

**「정의 파일」은 문서의 소유이지 코드의 경로가 아니다.** 그래서 형태 열에 **소스 경로를
못박는다** — firebase 실측에서 클러스터마다 다른 루트를 가정해 조립본의 상대 import가
해소되지 않았다. **게이트는 심볼이 팩 어딘가에 정의만 되어 있으면 통과시킨다.**

## 이 팩에서 특히 위험한 자리 넷

1. **타입 검사가 주석에 달려 있다.** 언어가 JavaScript이므로 `@param`·`@returns`·`@typedef`가
   **유일한 타입 선언**이고, `checkJs`를 켠 tsc가 그것을 읽는다. 주석을 빠뜨린 함수는
   **암묵 `any`가 되어 조용히 검사를 벗어난다** — 「타입이 없다」가 아니라 「검사되지 않는다」다
2. **런타임 경계에서 다시 파싱한다.** JSDoc은 **컴파일 시점 주석일 뿐 런타임에 아무것도
   하지 않는다.** 네트워크·`localStorage`·URL에서 온 값에 `@type`을 붙이는 것은 주장이지
   검증이 아니다 — zod의 `safeParse`가 그 자리를 채운다
3. **정리(cleanup)를 반환하지 않으면 새는다.** 프레임워크가 없으므로 언마운트 훅이 없다.
   구독·이벤트 리스너·`AbortController`를 만든 함수가 **해지 함수를 반환하는 것이 계약**이다
4. **`innerHTML`은 한 줄로 XSS가 된다.** 프레임워크의 자동 이스케이프가 없다 —
   `textContent`와 `<template>`이 기본이고 `innerHTML`은 정책이 금지한다

## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `config` | types-and-testing.md | **`src/config.js`** **여기가 유일한 정의다** — `import.meta.env`를 zod로 파싱한 결과. `VITE_API_BASE`(URL) · `VITE_ENV`. **모듈 최상위에서 파싱한다** — 실패가 부팅 실패여야 한다(첫 요청 시점에 터지면 화면 절반이 살아 있다). **환경을 읽는 유일한 파일이다** | 검증된 환경 값 |
| `TaskStatus` | types-and-testing.md | **`src/schemas/task.js`** — `z.enum(['open', 'done'])`. **값은 소문자 `'open'`·`'done'`이다.** 와이어·DOM 속성·테스트 단언에 쓰는 것은 **값**이지 이름이 아니다 — 이 칸을 비워 두었더니 형제 클러스터가 대문자로 추측해 차단 증명 테스트가 항상 빨갰다(fastapi 실측) | 상태 열거 |
| `TaskSchema` | types-and-testing.md | **`src/schemas/task.js`** — `z.object({ id, ownerId, title, status, createdAt })`. `createdAt`은 **문자열(ISO)로 받고 `Date`로 바꾸지 않는다** — 직렬화 경계를 하나로 둔다. `.strict()` | 도메인 스키마 |
| `Task` (타입) | types-and-testing.md | **`src/schemas/task.js`** — `/** @typedef {import('zod').z.infer<typeof TaskSchema>} Task */`. **손으로 쓴 `@typedef`를 스키마와 나란히 두지 않는다** — 두 벌이 되면 반드시 갈라진다. 스키마에서 도출한다 | 도메인 타입 |
| `TaskCreateSchema` | types-and-testing.md | **`src/schemas/task.js`** — `title`(1~200) · `status`(기본 `'open'`). `.strict()` | 생성 입력 |
| `TaskUpdateSchema` | types-and-testing.md | **`src/schemas/task.js`** — `TaskCreateSchema`의 부분형. **선택 필드에 기본값을 두지 않는다** — 두면 부분 수정이 보내지 않은 필드를 덮어쓴다 | 수정 입력 |
| `parseTask` | types-and-testing.md | **`src/schemas/task.js`** — `(raw: unknown) => Task` — `TaskSchema.safeParse`를 쓰고 실패하면 **던진다**. **경계에서 부르는 것이 계약이다**(응답·`localStorage`·URL). 성공 경로에서 `@type` 주석만 붙이는 것은 검증이 아니다 | 경계 파서 |
| `createStore` | state-management.md | **`src/store/create.js`** — `/** @template T */ (initial: T) => { get(): T, set(next: T \| ((prev: T) => T)): void, subscribe(fn: (value: T) => void): () => void }` — **`subscribe`는 해지 함수를 반환한다**(호출자가 그것을 보관·호출해야 한다). `set`은 얕은 동일성으로 비교해 같으면 통지하지 않는다. **`@template`이 없으면 스토어 값이 전부 `any`가 된다** | 스토어 팩토리 |
| `tasksStore` | state-management.md | **`src/store/tasks.js`** — `createStore`로 만든 인스턴스. 상태는 `{ items: Task[], byId: Record<string, Task> }`. **`byId`를 따로 두는 이유는 갱신이 목록 순회를 요구하지 않게 하는 것**이고, 두 필드가 **같은 `set` 안에서** 함께 바뀌어야 한다 — 나누면 구독자가 반쪽 상태를 본다 | 도메인 스토어 |
| `derive` | state-management.md | **`src/store/create.js`** — `/** @template T,U */ (store, selector: (value: T) => U) => { get(): U, subscribe(fn: (value: U) => void): () => void }` — 파생 값. `set`이 **없다**(파생은 쓰기 대상이 아니다) | 파생 |
| `el` | component-patterns.md | **`src/dom/el.js`** — `(tag: string, props?: Record<string, unknown>, children?: (Node \| string)[]) => HTMLElement` — 문자열 자식은 **`textContent`로 넣는다**(절대 `innerHTML`이 아니다). `props`의 `on*` 키는 리스너로, `class`·`data-*`는 속성으로 배선한다 | 요소 생성 |
| `fromTemplate` | component-patterns.md | **`src/dom/el.js`** — `(id: string) => DocumentFragment` — `<template id>`를 복제한다. 반복 렌더의 기본 수단이고, 마크업이 HTML에 남아 검색·검토가 된다 | 템플릿 복제 |
| `delegate` | component-patterns.md | **`src/dom/delegate.js`** — `(root: Element, type: string, selector: string, handler: (event: Event, target: Element) => void) => () => void` — **인자 순서: 뿌리 → 이벤트 종류 → 선택자 → 핸들러.** `type`과 `selector`가 **둘 다 문자열이라 순서가 생명이다.** 반환은 **해지 함수**다. 목록 항목마다 리스너를 다는 대신 뿌리 하나에 단다 | 이벤트 위임 |
| `mountTaskList` | component-patterns.md | **`src/components/task-list.js`** — `(root: Element, store: typeof tasksStore) => () => void` — 대표 컴포넌트. **반환은 정리 함수**이고 구독 해지 + 위임 해지를 모두 부른다. 프레임워크가 없으므로 이 반환값이 유일한 언마운트 경로다 | 대표 컴포넌트 |
| `createRouter` | routing.md | **`src/router/index.js`** — `(routes: { path: string, render: (params: Record<string, string>) => (() => void) }[]) => { start(): () => void, navigate(path: string): void }` — 각 라우트의 `render`는 **정리 함수를 반환한다**. `start()`는 `popstate`를 걸고 첫 렌더를 수행하며 **자신의 해지 함수를 반환한다** | 라우터 |
| `interceptLinks` | routing.md | **`src/router/links.js`** — `(root: Element, navigate: (path: string) => void) => () => void` — 내부 링크 클릭을 가로챈다. **가로채지 않을 것을 명시한다**: 수정자 키(⌘·Ctrl·Shift·Alt) · 가운데 클릭 · `target` 속성 · 외부 출처 · `download`. 하나라도 빠지면 새 탭으로 열기가 깨진다 | 링크 인터셉트 |
| `safeReturnTo` | routing.md | **`src/router/return-to.js`** — `(raw: unknown) => string` — 로그인 후 복귀 경로를 검증해 **내부 경로만** 돌려주고, 아니면 `'/'`를 돌려준다(던지지 않는다). **이 저장소에서 오픈 리다이렉트가 세 번 재발한 자리다**: `//host` · `/\host` · 제어문자 삽입 · 백슬래시 · 인코딩된 스킴이 브라우저에서 외부 URL로 파싱된다. `startsWith('/')`나 origin 비교만으로는 **부족하다**. `assets/security-vectors.md`의 벡터 12건을 전부 통과시키고 결과를 보고에 싣는다 | 보안 원시함수 |
| `createResource` | loading-error-states.md | **`src/state/resource.js`** — `/** @template T */ (fetcher: (signal: AbortSignal) => Promise<T>) => { subscribe(fn: (state: { status: 'idle' \| 'loading' \| 'empty' \| 'error' \| 'ready', data?: T, error?: Error }) => void): () => void, load(): void, abort(): void }` — **`fetcher`가 `AbortSignal`을 받는 것이 계약이다.** 새 `load()`는 진행 중인 것을 먼저 취소한다 — 취소하지 않으면 늦게 온 앞 응답이 뒤 응답을 덮어쓴다. `'empty'`는 성공했고 결과가 0건인 상태이며 `'error'`와 **다르게** 렌더된다 | 3상태 기계 |
| `renderState` | loading-error-states.md | **`src/state/render.js`** — `(container: Element, state: Parameters<…>, views: { loading: () => Node, empty: () => Node, error: (e: Error) => Node, ready: (d: unknown) => Node }) => void` — 컨테이너를 비우고 상태에 맞는 뷰를 넣는다. **에러 뷰에 `error.message`를 그대로 싣지 않는다** — 서버 메시지에 내부 경로가 들어 있다 | 3상태 렌더 |
| `taskListStyles` | styling.md | **`src/components/task-list.css`** — 대표 컴포넌트의 CSS. **컴포넌트가 소유하는 토큰(높이·여백·타이포)은 이 파일 한 곳에서만 정의**하고 사용처는 커스텀 프로퍼티로만 제어한다 | 컴포넌트 스타일 |

## requires — 이음매가 제공해야 한다

`프로젝트`는 이음매가 정의해야 하고, `라이브러리`는 import 문에 이름이 등장하는지로
판정한다. **팩이 호출하는 심볼에는 호출 시그니처를 적는다** — 적지 않으면 이음매가
인자 순서를 추측한다(게이트가 FAIL로 막는다).

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `fetchTasks` | 프로젝트 | `(signal: AbortSignal) => Promise<Task[]>` — **`signal`을 받아 `fetch`에 넘기는 것이 계약이다**(`createResource`가 그것을 준다). 응답은 신뢰 입력이 아니므로 **`parseTask`(팩 제공)로 항목마다 파싱한다**. 실패는 `Error`를 던진다. `src/api/tasks.js`에 둔다 | 봉투·엔드포인트·인증 헤더가 조합의 함수 |
| `createTask` | 프로젝트 | `(input: import('../schemas/task.js').TaskCreate, signal?: AbortSignal) => Promise<Task>` — **입력을 보내기 전에 `TaskCreateSchema`로 파싱한다.** 성공은 **생성된 `Task`**를 돌려준다(204가 아니다 — 스토어가 그것을 넣는다) | 위와 같다 |
| `session` | 프로젝트 | `{ get(): { userId: string } \| null, subscribe(fn): () => void }` — 보호 라우트가 `get()`으로 판정한다. **`subscribe`는 해지 함수를 반환한다**(팩의 정리 계약과 같다). `src/auth/session.js`에 둔다 | 토큰 보관 위치와 갱신이 백엔드 축의 함수 |
| `requireSession` | 프로젝트 | `(navigate: (path: string) => void, returnTo: string) => boolean` — 미인증이면 **`safeReturnTo`(팩 제공)를 통과시킨 `returnTo`**를 실어 로그인으로 보내고 `false`를 돌려준다. **복귀 경로를 검증하지 않고 실으면 오픈 리다이렉트가 된다** | 로그인 경로와 흐름이 조합의 함수 |

## 알려진 공백

없다. 축-지역 필수 슬롯이 모두 채워지고, 비어 보이는 것(데이터 페칭 · 인증/세션 ·
완전 예제)은 `pack.json`의 `seamSlots`가 선언한 이음매의 몫이다.

## 예제에 등장하는 앱 심볼 (프로젝트가 만든다)

`provides`도 `requires`도 아니다. 예제에서 이름만 등장하므로 조립 후에도 정의가 없는 것이
정상이다. **함수·클래스만이 아니라 CSS 커스텀 프로퍼티·데이터 속성도 등재한다** — 예제가
도입한 이름이 어디에도 선언되지 않으면 독자가 그것을 팩이 제공하는 것으로 읽는다.

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `--task-row-height` | styling.md · component-patterns.md | 컴포넌트가 소유하는 토큰 예시 |
| `data-task-id` | component-patterns.md (이벤트 위임의 대상 식별) | 위임 핸들러가 읽는 데이터 속성 |
