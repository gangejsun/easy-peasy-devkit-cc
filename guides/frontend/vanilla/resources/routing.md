<!-- epcc-pack: frontend/vanilla v3.14.0 -->
# 라우팅 — 단일 진입점, 그리고 화면을 떠날 때 무엇이 죽는가

소유: `src/router/index.js`의 `createRouter` · `src/router/links.js`의 `interceptLinks` ·
`src/router/return-to.js`의 `safeReturnTo`. 소유하지 않는 것 — 로딩·빈·에러 렌더는
`resources/loading-error-states.md`, DOM 헬퍼는 `resources/component-patterns.md`, 전역 상태는
`resources/state-management.md`. 로그인 화면·토큰 보관·세션 갱신은 이음매의 `auth-and-session`
슬롯이고, 이 파일은 `session`·`requireSession`을 **부르기만** 한다.

## 1. 결정 트리 — 이 값을 URL에 둘 것인가

URL은 이 축에서 **유일하게 새로고침을 견디는 저장소**다. 위에서부터 처음 맞는 칸에서 멈춘다.

| 이 값은… | 두는 곳 | 왜 |
| --- | --- | --- |
| 링크로 공유되어야 한다 | 경로 세그먼트 (`/tasks/:id`) | 주소창이 곧 상태다 |
| 새로고침·뒤로가기에서 살아 있어야 한다 | 쿼리 (`?filter=open`) | 히스토리 항목이 그것을 기억한다 |
| 로그인 후 돌아갈 자리 | 쿼리 — **단 `safeReturnTo`를 통과한 값만** (§5) | 검증 없이 실으면 오픈 리다이렉트다 |
| 스크롤 위치 | `history.state` (§7) | 항목마다 다르므로 전역이 아니다 |

**URL에서 읽은 값은 신뢰 입력이 아니다.** `params`도 쿼리도 사용자가 손으로 고칠 수 있다 —
경계에서 `safeParse`로 검증하고(`resources/types-and-testing.md`), 복귀 경로는 §5로 보낸다.

## 2. 라우터 (`src/router/index.js`)

**각 라우트의 `render(params)`는 정리 함수를 반환한다.** 프레임워크가 없으므로 라우터가 다음
화면을 그리기 전에 부를 수 있는 것은 그 반환값뿐이다. `start()`도 자신의 해지 함수를 돌려준다.

```js
// src/router/index.js — 매칭과 수명
/**
 * @typedef {(params: Record<string, string>) => (() => void)} RouteRender
 * @typedef {{ path: string, render: RouteRender }} Route
 */

/** @param {Route[]} routes @returns {{ start(): () => void, navigate(path: string): void }} */
export function createRouter(routes) {
  /** @type {(() => void) | null} */
  let dispose = null;
  let running = false;

  /** @returns {void} */
  function renderCurrent() {
    if (dispose) dispose();          // 이전 화면의 정리가 다음 화면의 렌더보다 먼저다
    dispose = null;
    for (const route of routes) {
      const params = matchPath(route.path, window.location.pathname);
      if (params === null) continue;
      dispose = route.render(params);
      return;
    }
  }
}
```

- **정리를 먼저 부르고 그린다.** 뒤집으면 이전 화면의 구독이 새 컨테이너에 한 번 더 쓴다
- `matchPath`는 `/tasks/:id`의 세그먼트를 맞춰 보고 `'*'`는 무엇이든 맞는다 — `'*'` 라우트가
  **배열의 마지막**에 있어야 404가 다른 경로를 삼키지 않는다
- `running` 플래그가 없으면 `stop()` 뒤의 `navigate()`가 **떼어낸 컨테이너에 화면을 다시
  그린다**. 정리 함수는 라우터를 멈추는 것까지가 계약이다 <!-- verified: happy-dom@20.11.6 에서 stop() 후 navigate() 가 렌더를 수행하는 것을 관측하고 플래그로 막았다 -->

## 3. 링크 인터셉트 (`src/router/links.js`) — 목록은 줄일 수 없다

`<a href>`를 통째로 가로채면 「새 탭으로 열기」가 조용히 깨진다 — **하나만 빠져도** 그렇다.

```js
// src/router/links.js
/** @param {Element} root @param {(path: string) => void} navigate @returns {() => void} */
export function interceptLinks(root, navigate) {
  /** @param {Event} event @returns {void} */
  const onClick = (event) => {
    const e = /** @type {MouseEvent} */ (event);
    if (e.defaultPrevented || e.button !== 0) return;                 // 가운데·오른쪽 클릭
    if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;     // ⌘·Ctrl·Shift·Alt
    const from = /** @type {Element | null} */ (e.target);
    const anchor = from?.closest('a[href]');
    if (!(anchor instanceof HTMLAnchorElement)) return;
    if (anchor.hasAttribute('target') || anchor.hasAttribute('download')) return;
    const url = new URL(anchor.href, window.location.origin);
    if (url.origin !== window.location.origin) return;                // 외부 출처·mailto:
    e.preventDefault();
    navigate(url.pathname + url.search + url.hash);
  };
  root.addEventListener('click', onClick);
  return () => root.removeEventListener('click', onClick);
}
```

| 가로채지 않는 것 | 무엇이 깨지는가 |
| --- | --- |
| ⌘·Ctrl·Shift·Alt · `e.button !== 0` | 새 탭·새 창으로 열기, 가운데 클릭 |
| `target` · `download` | `_blank`가 같은 탭에서 열리고, 파일이 저장되지 않는다 |
| 다른 오리진 | 외부 링크가 앱 안에서 404가 된다. `mailto:`·`tel:`도 여기서 걸린다 |

`e.defaultPrevented`를 먼저 보면 **다른 핸들러가 이미 처리한 클릭을 두 번 처리하지 않는다.**
`anchor.href`는 DOM이 이미 절대 URL로 만들어 둔 값이라 상대 경로도 오리진 비교에 걸린다.
이 판정을 `safeReturnTo`로 대신할 수 없다 — 저쪽은 **문자열**을, 이쪽은 **요소**를 본다.

## 4. 보호 라우트 — 강제 지점은 팩 안에 있다

`requireSession(navigate, returnTo)`의 **`returnTo`는 이미 검증된 값이다.** 검증을 이음매에
맡기면 정책 `safe-return-to`가 그것을 볼 수 없다 — 통과시키는 **호출자**가 여기다.

```js
// src/main.js — 보호 라우트 (라우트 화면은 routes 배열에 인라인으로 둔다)
/** @param {Record<string, string>} _params @returns {() => void} */
function renderTasks(_params) {
  const here = window.location.pathname + window.location.search;
  // ❌ 검증 없이 현재 주소를 그대로 싣는다 — 이음매가 그것을 로그인 URL 쿼리에 넣는다
  // if (!requireSession(router.navigate, here)) return () => {};
  // ✅ 강제 지점이 팩 안에 있다
  if (!requireSession(router.navigate, safeReturnTo(here))) return () => {};

  const resource = createResource(fetchTasks);
  const off = resource.subscribe((state) => renderState(outlet, state, views));
  resource.load();
  return () => { off(); resource.abort(); };   // 라우트를 떠나면 진행 중인 요청이 죽는다
}
```

- **미인증이면 빈 정리 함수를 반환한다.** 되돌릴 것이 없어도 `undefined`를 돌려주면 라우터가
  다음 전환에서 터진다
- 반환하는 정리 함수가 **구독 해지와 `abort()`를 둘 다** 부른다 — 이 클러스터의 결합점이고
  자세한 것은 `resources/loading-error-states.md` §8이다
- 로그인 화면이 `?returnTo=`를 **읽는** 쪽은 이음매 소유이고, 이음매도 같은 함수를 통과시켜야
  한다 (`pack.json`의 `auth-and-session` 슬롯이 의무로 적는다)

## 5. 복귀 경로 검증 (`src/router/return-to.js`)

**이 저장소에서 오픈 리다이렉트가 세 번 재발한 자리다.** `startsWith('/')`만으로도,
`new URL()`의 origin 비교만으로도 **부족하다.** 아래 네 층이 각각 다른 것을 막는다.

<!-- file: src/router/return-to.js -->
```js
// src/router/return-to.js
/**
 * 로그인 후 되돌아갈 경로를 검증한다. 내부 경로만 돌려주고, 아니면 '/'를 돌려준다.
 * **던지지 않는다** — 호출자가 실패를 잡아 우회할 길을 만들지 않기 위해서다.
 *
 * @param {unknown} raw
 * @returns {string}
 */
export function safeReturnTo(raw) {
  const fallback = '/';
  if (typeof raw !== 'string' || raw === '') return fallback;
  if (/[\u0000-\u001f\u007f]/.test(raw)) return fallback;
  if (!raw.startsWith('/')) return fallback;
  try {
    const url = new URL(raw, window.location.origin);
    if (url.origin !== window.location.origin) return fallback;
    const path = url.pathname;
    if (!path.startsWith('/') || path.startsWith('//') || path.startsWith('/\\')) return fallback;
    return path + url.search + url.hash;
  } catch {
    return fallback;
  }
}
```

| 층 | 막는 것 | 지우면 어떻게 되는가 |
| --- | --- | --- |
| 제어문자 거부 | `/tasks\n\rSet-Cookie: x=1` | URL 파서가 제어문자를 **조용히 지워** `/tasksSet-Cookie:%20x=1`을 돌려준다. SPA 라우터에는 없는 경로지만 이음매가 같은 문자열을 서버 `Location`에 실으면 응답 분리가 된다 |
| `startsWith('/')` | `javascript:` · `https://` · 상대 경로 | 스킴·호스트가 파서까지 간다 (다음 층이 잡지만 층을 겹친다) |
| `url.origin` 비교 | `/\evil.example` | `new URL()`이 역슬래시를 슬래시로 정규화해 **호스트가 `evil.example`이 된다** |
| `pathname`의 `'//'` 검사 | `/..//evil.example` | 파서가 origin을 통과시킨 **뒤** 점 세그먼트를 정규화해 결과가 다시 `//evil.example`이 된다 |

**세 번째와 네 번째가 둘 다 필요하다.** origin 비교만 남기면 `/..//evil.example`이, `pathname`
검사만 남기면 `/\evil.example`이 통과한다. 게이트의 `check_security_shapes`가 네 번째를 강제한다.

## 6. 벡터 판정 — 지워 보고 확인했다

`assets/security-vectors.md`의 A절 12건을 **실제로 먹여** 확인했다. 판정 기준은 「fallback으로
떨어진다」가 아니라 **「결과가 자기 오리진을 벗어나지 않는다」**이다.

| 벡터 | 입력 | 출력 | 판정 |
| --- | --- | --- | --- |
| A1·A2·A3·A4 | `//evil.example` · `/\evil.example` · `https://evil.example` · `javascript:alert(1)` | `'/'` | 차단 |
| A5·A6 | `/..//evil.example` · `/../..//evil.example` | `'/'` | 차단 |
| A7·A8·A9 | `%2f%2fevil.example` · `/tasks\n\rSet-Cookie: x=1` · `\tjavascript:alert(1)` | `'/'` | 차단 |
| A10 | `''` · `null` · `42` (문자열이 아닌 입력) | `'/'` | 차단 |
| A11·A12 | `/tasks?filter=open#top` · `/tasks/123` | 입력 그대로 | **통과 — 여기서 막히면 기능이 죽는다** |

<!-- verified: node 22 로 12건 + null·숫자 2건을 실행. pack-smoke.sh 의 unsafe() 판정식을 그대로 썼다 -->

**양성 대조군**을 함께 돌렸다 — 「전부 차단」이라는 고장난 구현도 위 표의 앞 네 행에서는
초록이기 때문이다. 층을 지운 판을 같은 벡터에 먹이면 접두사 검사만 남긴 판은 **A1·A2·A8을
그대로 반환**하고, origin 비교만 남긴 판은 **A5·A6을 `//evil.example`로 반환**한다. A11·A12는
네 판 모두 통과했다 — 그래서 마지막 행이 「막지 않는다」의 증명이다.
<!-- verified: 4개 변이판을 같은 벡터 러너에 통과시켜 FAIL 3건 / 2건 / 0건 / 0건 을 관측 -->

## 7. 404와 스크롤 복원

**404는 라우트다.** 매칭 실패를 `if`로 특수 처리하면 정리 계약 밖으로 새는 화면이 생긴다 —
배열 마지막의 `'*'`가 그 자리이고, 다른 라우트와 똑같이 정리 함수를 반환한다.

```js
// src/router/index.js — start() · navigate() 와 스크롤
start() {
  window.history.scrollRestoration = 'manual';   // 브라우저의 자동 복원과 다투지 않는다
  /** @param {PopStateEvent} e @returns {void} */
  const onPop = (e) => {
    renderCurrent();
    const state = /** @type {{ scrollY?: number } | null} */ (e.state);
    window.scrollTo(0, state?.scrollY ?? 0);     // 뒤로가기는 있던 자리로
  };
  window.addEventListener('popstate', onPop);
  running = true;
  renderCurrent();
  return () => { running = false; window.removeEventListener('popstate', onPop); if (dispose) dispose(); };
}
// navigate() 안 — 떠나는 항목에 위치를 새기고 새 항목을 쌓는다
window.history.replaceState({ scrollY: window.scrollY }, '', here);
window.history.pushState({ scrollY: 0 }, '', to);
renderCurrent();
window.scrollTo(0, 0);                                               // 새 화면은 위에서 시작한다
```

- **떠나기 직전의 `replaceState`가 핵심이다.** 위치를 히스토리 **항목**에 새기지 않고 모듈
  변수에 두면 여러 단계 뒤로가기에서 전부 같은 값이 나온다. `'manual'`을 켜지 않으면
  브라우저의 자동 복원과 우리 `scrollTo`가 겹쳐 화면이 튄다
- 실제 스크롤 위치·복원 타이밍은 **실 브라우저에서 검증하지 못했다** — happy-dom은
  `history.state`에 값이 실리는 것까지만 보여 준다
  <!-- unverified: 저작 환경에 브라우저가 없다. happy-dom 은 scrollY 가 항상 0이라 값의 왕복만 대리 확인된다 -->

## 8. 차단을 증명하는 테스트 (`test/return-to.test.js`)

**공격 입력이 전부 `'/'`가 된다는 단언만으로는 차단 장치가 아니다.** 함수 본문을
`return '/'` 한 줄로 바꿔도 초록이기 때문이다. 정상 경로를 **같은 파일, 같은 `it`** 안에 짝으로 건다.

<!-- file: test/return-to.test.js -->
```js
// test/return-to.test.js
import { describe, it, expect } from 'vitest';
import { safeReturnTo } from '../src/router/return-to.js';

describe('safeReturnTo', () => {
  it('내부 경로는 통과시키고 밖으로 나가는 형태는 전부 막는다', () => {
    expect(safeReturnTo('/tasks?filter=open#top')).toBe('/tasks?filter=open#top');
    expect(safeReturnTo('/tasks/123')).toBe('/tasks/123');

    for (const attack of [
      '//evil.example', '/\\evil.example', 'https://evil.example', 'javascript:alert(1)',
      '/..//evil.example', '/../..//evil.example', '%2f%2fevil.example',
      '/tasks\n\rSet-Cookie: x=1', '\tjavascript:alert(1)', '', null, 42,
    ]) {
      expect(safeReturnTo(attack)).toBe('/');
    }
  });

  it('점 세그먼트를 정규화한 뒤의 출력을 본다', () => {
    const url = new URL('/..//evil.example', window.location.origin);
    expect(url.origin).toBe(window.location.origin);   // origin 비교는 이것을 통과시킨다
    expect(url.pathname).toBe('//evil.example');       // 정규화 후 출력이 밖을 가리킨다
    expect(safeReturnTo('/..//evil.example')).toBe('/');
    expect(safeReturnTo('/tasks/../done')).toBe('/done');
  });
});
```

두 번째 `it`이 이 파일에서 가장 비싼 단언이다. **브라우저의 `URL` 파서가 스스로 만든 값**을
읽으므로 우리가 넣은 값을 되읽는 순환 검증이 아니고, `//`를 보는 층을 지우면 마지막 두
단언이 즉시 빨개진다. `/tasks/../done`은 정규화가 **정상 경로에도** 일어난다는 대조군이다.
<!-- verified: vitest@4.1.11 + happy-dom@20.11.6 에서 통과, 층을 지운 변이판에서 실패를 관측 -->

`test/router.test.js`도 **가로챈 링크와 가로채지 않은 링크를 같은 `it`에서** 단언한다.
happy-dom에서 가로채지 않은 링크는 실제로 페이지를 따라가려 하므로, 문서 레벨에 기본 동작을
삼키는 리스너를 두고 `e.defaultPrevented`를 읽는다.
<!-- verified: 수정자 키 검사를 지운 변이판에서 그 it 이 빨개지는 것을 관측 -->

## 오용 목록 ① — React Router · Vue Router 습관 → History API 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `<Link to="/tasks">` | 평범한 `<a href="/tasks">` + `interceptLinks`가 위임으로 가로챈다 |
| `useParams()` | `render(params)`가 받는 인자. **URL에서 왔으므로 신뢰 입력이 아니다** |
| `useNavigate()` | `router.navigate(path)` — 라우터 인스턴스를 모듈에서 가져온다 |
| `<Route element={…}>`가 언마운트를 처리 | `render`가 **정리 함수를 반환**하고 라우터가 그것을 부른다 |
| `<Navigate to="/login" />`로 보호 | `requireSession(navigate, safeReturnTo(raw))` 후 빈 정리 함수 반환 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `pushState` vs `replaceState` | 새 화면이면 앞, **떠나는 항목에 스크롤을 새길 때**는 뒤 |
| `safeReturnTo` vs `interceptLinks`의 origin 비교 | 앞은 문자열을, 뒤는 `<a>` 요소를 판정한다. 서로 대신하지 못한다 |
| `url.origin` vs `url.pathname` | **둘 다 본다.** 하나만 보면 §5 표의 나머지 한 줄이 뚫린다 |
| `'*'` 라우트 vs 매칭 실패 `if` | 언제나 앞 — 정리 계약 밖으로 새는 화면을 만들지 않는다 |
| `render`가 `undefined` 반환 vs `() => {}` | 아무것도 만들지 않았어도 뒤. 라우터가 그것을 부른다 |
