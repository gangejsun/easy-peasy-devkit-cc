<!-- epcc-pack: frontend/vanilla v3.14.0 -->
# 로딩·빈·에러 — 다섯 상태와, 취소하지 않으면 되살아나는 앞 응답

소유: `src/state/resource.js`의 `createResource`와 `src/state/render.js`의 `renderState`.
소유하지 않는 것 — 실제 API 호출(`fetchTasks`·`createTask`)은 이음매의 `data-fetching` 슬롯이고,
도메인 스토어는 `resources/state-management.md`, 라우트 수명은 `resources/routing.md`, 목록
마크업은 `resources/component-patterns.md`가 소유한다.

## 1. 결정 트리 — 지금 컨테이너에 무엇이 있어야 하는가

상태는 **다섯**이다. 넷으로 줄이면 「아직 부르지 않았다」와 「부르는 중이다」가 한 칸에
들어가고, 그 순간 첫 페인트에 무엇을 그릴지가 계약에서 사라진다.

| 상태 | 언제 | 화면 |
| --- | --- | --- |
| `idle` | `load()`를 아직 부르지 않았다 | **아무것도 그리지 않는다** (뷰가 없으면 비운 채로 둔다) |
| `loading` | 요청이 나갔고 아직 안 왔다 | 스켈레톤·스피너. 이전 데이터를 남기지 않는다 |
| `empty` | **성공했고** 결과가 0건이다 | 「아직 작업이 없다」 + 만들기 동선 |
| `error` | 요청이 실패했다 | 「불러오지 못했다」 + 다시 시도 버튼 |
| `ready` | 성공했고 결과가 있다 | 목록 |

- **`empty`와 `error`를 한 칸에 넣지 않는다.** 0건은 정상이고 할 일은 만들기, 실패는 비정상이고
  할 일은 다시 시도다. 같은 화면으로 그리면 빈 목록이 고장으로 읽힌다
- **취소는 상태가 아니다.** 떠난 화면의 결과는 아무도 보지 않으므로 `abort()`는 통지하지 않는다

## 2. 리소스 (`src/state/resource.js`)

**`fetcher`가 `AbortSignal`을 받는 것이 계약이다.** 새 `load()`는 진행 중인 것을 먼저
취소하고, 취소된 요청의 결과는 도착해도 버린다.

```js
// src/state/resource.js
import { createStore } from '../store/create.js';

/**
 * @template T
 * @typedef {{ status: 'idle' | 'loading' | 'empty' | 'error' | 'ready', data?: T, error?: Error }} ResourceState
 */

/**
 * @template T
 * @param {(signal: AbortSignal) => Promise<T>} fetcher
 * @param {{ isEmpty?: (data: T) => boolean }} [options]
 * @returns {{ subscribe(fn: (state: ResourceState<T>) => void): () => void, load(): void, abort(): void }}
 */
export function createResource(fetcher, options = {}) {
  const isEmpty = options.isEmpty ?? ((/** @type {T} */ d) => Array.isArray(d) && d.length === 0);
  const store = createStore(/** @type {ResourceState<T>} */ ({ status: 'idle' }));
  /** @type {AbortController | null} */
  let inflight = null;

  /** @returns {void} */
  function abort() { inflight?.abort(); inflight = null; }

  /** @returns {void} */
  function load() {
    abort();                                  // 진행 중인 것을 먼저 취소한다
    const ctl = new AbortController();
    inflight = ctl;
    store.set({ status: 'loading' });
    fetcher(ctl.signal).then(
      (data) => {
        if (ctl.signal.aborted) return;       // 늦게 온 앞 응답을 버린다
        inflight = null;
        store.set(isEmpty(data) ? { status: 'empty' } : { status: 'ready', data });
      },
      (cause) => {
        if (ctl.signal.aborted) return;
        inflight = null;
        store.set({ status: 'error', error: cause instanceof Error ? cause : new Error(String(cause)) });
      },
    );
  }

  return { subscribe: (fn) => store.subscribe(fn), load, abort };
}
```

- **`ctl`을 클로저에 가둔다.** `inflight`를 다시 읽으면 다음 `load()`가 이미 바꿔 놓은 뒤라
  판정이 틀린다 — 경합을 고치는 코드가 경합을 만든다
- **`ctl.signal.aborted` 검사는 이음매에 대한 방어다.** 이음매가 `signal`을 `fetch`에 넘기지
  않아도(정책 `seam-signal-passed`가 겨누는 결함) 늦은 응답이 화면을 덮지 않는다
  <!-- verified: signal 을 무시하는 fetcher 로 vitest 실행 — 마지막 응답만 남는 것을 관측 -->
- 상태 객체를 **통째로 교체**하므로 `Object.is` 비교에서 모든 전이가 통지된다

## 3. 경합 — 취소가 없으면 앞 응답이 뒤 응답을 덮는다

**이 결함은 재현이 어렵다.** 앞 요청이 느릴 때만 나오고 개발 기계에서는 둘 다 즉시 돌아온다 —
「관찰되지 않는다」가 「없다」의 근거가 되지 않는다.

```js
// ❌ 양성 대조군 — 취소 없이 두 번 부르면 도착 순서가 최종 상태를 정한다
const load = () => fetcher(new AbortController().signal).then((d) => { latest = d; });
load();              // 40ms 걸린다  (/tasks?filter=all)
load();              // 0ms 에 온다  (/tasks?filter=open)
// → latest 는 resp-1(뒤) 이었다가 resp-0(앞) 으로 덮인다
```

앞 요청에 40ms 지연을, 뒤 요청에 0ms를 주고 실행했다. 취소가 없으면 도착 순서가
`resp-1` → `resp-0`이라 **화면에는 앞 요청의 결과가 남는다.** 같은 지연으로
`createResource`를 돌리면 `abort()`가 앞 요청을 끊어 `resp-1`만 남는다.
<!-- verified: vitest@4.1.11 + happy-dom@20.11.6 에서 두 판을 같은 지연으로 대조 실행 -->

사용자에게는 **필터를 눌렀는데 이전 필터의 목록이 보이는 것**으로, 라우트를 빠르게 오갈 때는 **떠난 화면의 데이터가 다음 화면에 뜨는 것**으로 나타난다.

## 4. 상태 렌더 (`src/state/render.js`)

```js
// src/state/render.js
/**
 * @template T
 * @param {Element} container
 * @param {import('./resource.js').ResourceState<T>} state
 * @param {{ idle?: () => Node, loading: () => Node, empty: () => Node,
 *           error: (error: Error) => Node, ready: (data: T) => Node }} views
 * @returns {void}
 */
export function renderState(container, state, views) {
  switch (state.status) {
    case 'idle':
      container.replaceChildren(...(views.idle ? [views.idle()] : []));
      return;
    case 'loading': container.replaceChildren(views.loading()); return;
    case 'empty': container.replaceChildren(views.empty()); return;
    case 'error': container.replaceChildren(views.error(state.error ?? new Error('unknown'))); return;
    case 'ready': container.replaceChildren(views.ready(/** @type {T} */ (state.data))); return;
  }
}
```

- **`idle`만 선택이다.** 뷰가 없으면 컨테이너를 **비운 채로 둔다** — 첫 페인트에 스피너를
  띄우지 않는 화면이 흔하다. 나머지 넷은 필수라 하나만 빠져도 tsc가 잡는다
- **`replaceChildren`이 이전 화면을 지우는 유일한 지점이다.** 문자열이 아니라 `Node`를 넘기므로
  `el`·`fromTemplate`의 이스케이프 계약이 이어진다 (`.innerHTML` 대입은 정책이 금지한다)
- `state.data`가 선택 필드라 `ready` 가지에 단언이 한 번 필요하다 — **원장이 못박은 형태를
  따른 결과**이고, 판별 유니온으로 바꾸면 사라진다 (L0의 몫이다)

## 5. 에러 뷰에 `error.message`를 그대로 싣지 않는다

**허브와 원장은 이 규칙만 적고 이유를 싣지 않는다. 이유가 여기 있다.**

```js
// src/main.js — 라우트의 views (발췌)
// ❌ 서버 메시지가 그대로 화면에 붙는다: "500 at /srv/app/api/tasks.js:42 (db=prod-eu-1)"
error: (cause) => message(`불러오지 못했다: ${cause.message}`),
// ✅ 사용자에게는 행동을, 진단은 콘솔·원격 로깅으로
error: (cause) => { console.error('[tasks]', cause); return message('작업을 불러오지 못했다'); },
```

- 이유는 **XSS가 아니다.** `textContent`로 넣으므로 태그는 해석되지 않는다 — 문제는 **정보
  노출**이다. 서버 메시지에는 내부 경로·스택·호스트명·쿼리 조각이 들어 있고, 이 축에는
  **그것을 걸러 줄 서버 층이 없다** (배포물이 정적 파일이라 응답이 브라우저까지 그대로 온다)
- 상태 코드도 그대로 쓰지 않는다. `401`은 「다시 로그인해야 한다」로, `5xx`는 「잠시 후 다시」로
  옮긴다 — 사용자가 할 수 있는 행동이 화면에 있어야 한다
- **`error` 뷰가 `Error`를 받는 것은 그리라는 뜻이 아니라 분기하라는 뜻이다**

## 6. 재시도 — 버튼이 먼저다

기본은 **사용자가 누르는 재시도**다. `resource.load()`를 다시 부르면 §2의 취소가 그대로
적용돼 중복 요청이 남지 않는다.

```js
// src/main.js — 에러 뷰의 다시 시도
error: () => el('div', { class: 'state-error' }, [
  '작업을 불러오지 못했다',
  el('button', { onclick: () => resource.load() }, ['다시 시도']),
]),
```

자동 재시도가 필요하면 **`fetcher`를 감싼다.** 감싸는 층도 `signal`을 받으므로 대기 중에도
취소가 통해야 한다 — 그러지 않으면 라우트를 떠난 뒤에도 백오프가 계속 돈다.

```js
// src/main.js — 취소를 지키는 대기와 백오프
/** @param {number} ms @param {AbortSignal} signal @returns {Promise<void>} */
function sleep(ms, signal) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    signal.addEventListener('abort', () => { clearTimeout(timer); reject(signal.reason); }, { once: true });
  });
}

/** @template T @param {(s: AbortSignal) => Promise<T>} fetcher @param {number} attempts @returns {(s: AbortSignal) => Promise<T>} */
function withBackoff(fetcher, attempts = 3) {
  return async (signal) => {
    for (let i = 1; ; i += 1) {
      try { return await fetcher(signal); }
      catch (cause) {
        if (signal.aborted || i >= attempts) throw cause;
        await sleep(200 * 2 ** (i - 1), signal);   // 200 · 400 — 상한이 있다
      }
    }
  };
}
```

`setTimeout`만 걸고 `signal`을 듣지 않으면 취소가 **다음 시도가 시작될 때까지 미뤄진다.**
실행에서 확인했다: 대기 중 `abort()`가 즉시 통하고 `fetcher` 호출은 1회에서 멈춘다.
<!-- verified: vitest 로 3회 재시도 성공과 대기 중 취소(호출 1회) 를 각각 관측 -->

**모든 실패를 다시 시도하지 않는다.** `400`·`404`·`422`는 다시 보내도 같은 답이 온다 —
어떤 실패가 일시적인지는 응답 봉투를 아는 **이음매가 판정한다**.

## 7. 낙관적 갱신을 하지 말 자리

낙관적 갱신은 **되돌리기가 있을 때만** 성립한다. 이 축에는 그것을 대신해 주는 층이 없다.

| 하지 않는다 | 왜 |
| --- | --- |
| 목록에 임시 행을 넣고 응답을 기다린다 | 실패하면 지울 근거가 없다. `upsertTask`에는 삭제가 없고, 임시 id가 서버 id와 갈린다 |
| 체크박스를 먼저 켜고 요청을 보낸다 | 실패 시 이전 값을 복원하려면 스냅숏을 들고 있어야 하고, 그 사이 도착한 다른 갱신을 덮는다 |
| 갱신 후 목록 전체를 다시 `load()` | 사용자가 스크롤·포커스를 잃는다. 응답이 준 `Task`를 `upsertTask`로 넣는다 |

**예외는 하나다**: 버튼 비활성화·스피너는 상태가 아니라 **입력 잠금**이라 스토어에 넣지 않는다.

## 8. 라우트 수명이 요청 수명이다 (`test/resource.test.js`)

**`AbortController`의 수명이 라우터의 수명에 묶인다.** 라우트의 `render`가 리소스를 만들고,
반환하는 정리 함수가 구독 해지와 `abort()`를 **둘 다** 부른다 — `resources/routing.md` §4와
같은 형태다. 하나라도 빠지면 떠난 화면의 응답이 다음 화면의 컨테이너에 그려진다.

<!-- file: test/resource.test.js -->
```js
// test/resource.test.js
import { describe, it, expect, vi } from 'vitest';
import { createResource } from '../src/state/resource.js';

/** @param {number[]} delays @returns {(signal: AbortSignal) => Promise<string[]>} */
function delayedFetcher(delays) {
  let call = 0;
  return (signal) => {
    const i = call; call += 1;
    return new Promise((resolve, reject) => {
      const t = setTimeout(() => resolve([`resp-${i}`]), delays[i]);
      signal.addEventListener('abort', () => { clearTimeout(t); reject(new Error('aborted')); });
    });
  };
}

describe('createResource', () => {
  it('앞 요청을 취소하므로 뒤 응답만 남는다 (앞이 더 늦게 온다)', async () => {
    const res = createResource(delayedFetcher([40, 0]));
    /** @type {string[]} */ const seen = [];
    /** @type {string[]} */ let data = [];
    const off = res.subscribe((s) => { seen.push(s.status); if (s.status === 'ready' && s.data) data = s.data; });
    res.load();
    res.load();
    await new Promise((r) => setTimeout(r, 80));
    expect(data).toEqual(['resp-1']);                              // 앞 응답이 덮지 않았다
    expect(seen).toEqual(['idle', 'loading', 'loading', 'ready']); // idle 로 시작한다
    off();
  });

  it('abort() 후에는 아무 상태도 더 나오지 않는다', async () => {
    const res = createResource(delayedFetcher([30]));
    const fn = vi.fn();
    res.subscribe(fn); res.load(); res.abort();
    await new Promise((r) => setTimeout(r, 60));
    expect(fn.mock.calls.map((c) => c[0].status)).toEqual(['idle', 'loading']);
  });
});
```

첫 `it`이 이 파일에서 가장 비싼 단언이다. **`data`(차단됐다)와 `seen`(정상 전이가 다 일어났다)을
같은 `it`에서** 본다 — `seen`이 없으면 `load()`를 통째로 지운 구현도 초록이다. `load()` 앞의
`abort()`를 지우면 `data`가 `resp-0`으로 빨개지고, `empty` 판정을 지우면 0건 테스트가 빨개진다.
<!-- verified: 두 변이판을 각각 vitest run 으로 돌려 실패를 관측 -->

## 오용 목록 ① — TanStack Query · SWR 습관 → `createResource` 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `useQuery(['tasks'], fn)` | `createResource(fetchTasks)` + `subscribe`. 캐시는 없다 |
| `isLoading` · `isError` 불리언 조합 | `status` 한 칸. 조합이 불가능한 상태를 표현할 수 없다 |
| `data?.length === 0`을 뷰에서 판정 | `'empty'` 상태가 그 자리다 — 뷰가 판정하면 파일마다 갈린다 |
| `refetch()` | `load()` — 진행 중인 것을 먼저 취소한다 |
| 훅이 언마운트에 알아서 취소 | **아무도 취소하지 않는다.** 라우트 정리 함수가 `abort()`를 부른다 |
| `useMutation`의 `onMutate` 롤백 | 낙관적 갱신을 쓰지 않는다 (§7) |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `'empty'` vs `'error'` | 성공했고 0건이면 앞. 요청이 실패했으면 뒤 |
| `'idle'` vs `'loading'` | `load()` 전이면 앞. 첫 페인트에 스피너를 띄우지 않는 화면이 여기다 |
| `abort()` vs 아무것도 안 함 | 라우트를 떠나면 언제나 앞. 늦은 응답은 다음 화면을 덮는다 |
| `signal`을 `fetch`에 넘기기 vs 받기만 하기 | 넘겨야 취소가 실제로 통한다 — 이음매의 의무다 |
| 자동 백오프 vs 다시 시도 버튼 | 사용자가 기다리고 있으면 뒤. 백그라운드 갱신이면 앞 |
| `error.message` 렌더 vs 고정 문구 | **언제나 뒤.** 메시지는 콘솔·원격 로깅으로 보낸다 (§5) |
