<!-- epcc-pack: frontend/vue v3.12.0 -->
# State Management (Pinia 2 + 상태 배치 기준)

이 스택에는 상태를 둘 수 있는 자리가 넷이다. **잘못된 자리를 고르는 것**이 대부분의
상태 관리 문제의 원인이므로, 도구 사용법보다 배치 기준이 먼저다.

## 1. 결정 트리

```
서버가 소유한 데이터인가?            → Vue Query (전역 스토어 금지)
URL로 공유·복원되어야 하는가?        → route.query / route.params
한 컴포넌트와 그 자식만 쓰는가?      → ref / reactive (필요하면 provide/inject)
그 외 앱 전역에서 필요한가?          → Pinia 스토어
```

| 상태 | 자리 | 이유 |
| --- | --- | --- |
| 작업 목록, 사용자 프로필 | Vue Query | 서버가 진실. 무효화·재요청이 필요 |
| 목록 필터·정렬 | URL | 공유·새로고침·뒤로가기가 공짜 |
| 폼 입력값 | 로컬 `ref` | 제출 전까지 아무도 볼 필요 없음 |
| 모달 열림/닫힘 | 로컬 또는 Pinia | 여러 화면에서 열 수 있으면 Pinia |
| 사이드바 접힘, 테마, 목록 밀도 | Pinia | 앱 전역 UI 선호 |
| 액세스 토큰 | 인증 모듈 (메모리) | 이음매의 세션 리소스가 소유한다 |

**서버 데이터를 Pinia에 넣지 않는다.** 넣는 순간 신선도·무효화·낙관적 롤백을 손으로
만들게 되고, 그건 이미 Vue Query가 하는 일이다.

## 2. 설치

```ts
// src/main.ts — 플러그인 등록. 가드가 스토어를 쓴다고 해서 순서를 맞출 필요는 없다:
// vue-router 4의 초기 내비게이션은 비동기라 모든 use()가 끝난 뒤에 가드 본문이 돈다.
// 그래도 아래 순서로 고정한다 — 읽는 사람이 의존 방향을 한눈에 보게
import { createApp } from 'vue';
import { createPinia } from 'pinia';
import { VueQueryPlugin } from '@tanstack/vue-query';
import App from './App.vue';
import { router } from './router';
import './assets/main.css';

const app = createApp(App);
// loading-error-states.md §6의 ①: 경계를 빠져나온 것을 마지막으로 받는다
app.config.errorHandler = (err) => { console.error(err); };
app.use(createPinia()).use(router).use(VueQueryPlugin).mount('#app');
```

## 3. 스토어 작성 — setup 스토어

```ts
// src/stores/ui.ts
import { defineStore } from 'pinia';
import { ref, watch } from 'vue';

export const STORAGE_KEY = 'ui-preferences';   // clearClientState가 같은 상수를 쓴다
type Density = 'comfortable' | 'compact';

// 복원은 스토어 밖 순수 함수로 — 형태가 어긋난 저장값이 스토어를 오염시키지 않게 한다
function restore(): { isSidebarOpen: boolean; density: Density } {
  const fallback = { isSidebarOpen: true, density: 'comfortable' as Density };
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return fallback;
    const parsed = JSON.parse(raw) as Partial<typeof fallback>;
    return {
      isSidebarOpen: typeof parsed.isSidebarOpen === 'boolean' ? parsed.isSidebarOpen : true,
      density: parsed.density === 'compact' ? 'compact' : 'comfortable',
    };
  } catch { return fallback; }
}

export const useUiStore = defineStore('ui', () => {
  const saved = restore();
  const isSidebarOpen = ref(saved.isSidebarOpen);
  const density = ref<Density>(saved.density);

  function toggleSidebar() { isSidebarOpen.value = !isSidebarOpen.value; }
  function setDensity(next: Density) { density.value = next; }
  // setup 스토어에는 $reset()이 없다 — 직접 만든다 (§7이 이 함수를 부른다)
  function reset() { isSidebarOpen.value = true; density.value = 'comfortable'; }

  // 저장 대상을 명시한다. **토큰·개인정보·서버 데이터는 저장하지 않는다** —
  // localStorage는 XSS에 그대로 읽힌다
  watch([isSidebarOpen, density], ([open, d]) =>
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ isSidebarOpen: open, density: d })));

  return { isSidebarOpen, density, toggleSidebar, setDensity, reset };
});
```

- 스토어 id(`'ui'`)는 전역 유일해야 한다 — 겹치면 뒤에 등록된 것이 조용히 이긴다
- `ref`로 만든 상태, `computed`로 만든 getter, 함수로 만든 액션을 **모두 반환**한다.
  반환하지 않은 것은 스토어 밖에서 보이지 않는다
- Pinia 2에는 내장 persist가 없다. 위처럼 `watch` 하나로 끝나면 플러그인을 들이지 않는다
- 로그아웃에서 부를 `reset()`을 처음부터 만들어 둔다

옵션 스토어 표기도 있다. **같은 스토어의 다른 표기이므로 둘을 동시에 두지 않는다.**
`$reset()`이 공짜로 생기는 대신 액션에서 다른 컴포저블을 쓰기 어렵다.

```ts
// src/stores/ui.ts — 옵션 표기 (setup 표기를 쓰면 이 형태는 두지 않는다)
export const useUiStore = defineStore('ui', {
  state: () => ({ isSidebarOpen: true, density: 'comfortable' as Density }),
  getters: { isCompact: (s) => s.density === 'compact' },
  actions: { toggleSidebar() { this.isSidebarOpen = !this.isSidebarOpen; } },
});
```

## 4. 구독 — `storeToRefs`가 필수다

스토어 인스턴스는 **reactive 프록시**다. 구조 분해하면 그 시점의 값이 복사되어 다시는
갱신되지 않는다. 예외를 던지지 않고 "화면이 안 바뀜"으로만 나타나므로 가장 늦게 발견된다.

```ts
// ✅ 상태·getter는 storeToRefs로 꺼낸다 — Ref로 유지되어 반응성이 산다
const ui = useUiStore();
const { isSidebarOpen, density } = storeToRefs(ui);
// ✅ 액션은 그냥 꺼내도 된다 — 함수는 스토어에 바인딩되어 있다
const { toggleSidebar, setDensity } = ui;
```

❌ 아래는 화면이 첫 값에 얼어붙는다:

```ts
const { isSidebarOpen } = useUiStore();
```

- 템플릿에서는 `ui.isSidebarOpen`처럼 스토어를 통째로 써도 된다 — 프록시 접근이라 반응한다
- `storeToRefs`는 상태와 getter만 Ref로 감싸고 액션은 건드리지 않는다
- 스크립트에서는 `.value`, 템플릿에서는 자동 언랩 — 이 비대칭이 `.value` 누락의 원인이다

## 5. 여러 필드를 한 번에 바꾸기

```ts
// 구독자를 한 번만 깨운다. 부분 갱신을 하나의 전이로 묶고 싶을 때 쓴다
useUiStore().$patch({ isSidebarOpen: false, density: 'compact' });
```

`$patch`는 얕은 병합이다. 중첩 객체를 통째로 넘기면 안쪽이 교체되므로, 중첩이 필요하면
함수형(`$patch((s) => { ... })`)을 쓰거나 애초에 스토어를 평평하게 유지한다.

## 6. 컴포넌트 밖에서 스토어 쓰기

라우터 가드, HTTP 인터셉터, 이벤트 유틸에서도 `useUiStore()`를 부를 수 있다. 조건은
하나다: **`app.use(createPinia())`가 이미 실행됐어야 한다.**

```ts
// ✅ 함수 안에서 부른다 — 호출 시점에는 pinia가 설치되어 있다
function collapseSidebar() {
  useUiStore().isSidebarOpen = false;
}
```

❌ 모듈 최상위에서 부르면 `getActivePinia()` 오류로 앱이 뜨지 않는다:

```ts
const ui = useUiStore();
function collapseSidebar() { ui.isSidebarOpen = false; }
```

테스트에서는 pinia가 없으므로 `beforeEach(() => setActivePinia(createPinia()))`로 심는다
(`types-and-testing.md` §7).

## 7. 로그아웃 시 초기화

세션이 끝나면 **서버 캐시와 클라이언트 스토어를 모두** 비운다. 하나만 비우면 다음
사용자가 이전 사용자의 화면 조각을 본다.

이 함수는 이름 그대로 **클라이언트 스토어만** 책임진다. 서버 캐시 폐기(`queryClient.clear()`)와
순서 통제는 이음매의 세션 리소스가 소유한다 — 두 곳에서 캐시를 비우면 어느 쪽이 실제로
도는지 추적이 어려워진다.

```ts
// src/stores/clearClientState.ts — 스토어를 추가하면 이 목록에도 추가한다
import { useUiStore, STORAGE_KEY } from './ui';

export function clearClientState() {
  useUiStore().reset();     // 모든 스토어에 reset()이 있어야 하는 이유
  localStorage.removeItem(STORAGE_KEY);   // 리터럴 중복 금지 — 한쪽만 바뀌면 조용히 안 지워진다
}
```

## 8. URL을 상태로 쓴다

목록의 필터·정렬은 컴포넌트 상태가 아니라 URL에 둔다. 공유·새로고침·뒤로가기가 공짜로
동작하고, 그 값이 그대로 쿼리 키가 된다.

```vue
<script setup lang="ts">
import { computed } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const route = useRoute();
const router = useRouter();

// route.query 값은 string | null | (string | null)[] 이다 — 반드시 좁힌다
const status = computed<'all' | 'open' | 'done'>(() => {
  const raw = route.query.status;
  return raw === 'open' || raw === 'done' ? raw : 'all';
});

function setStatus(next: 'all' | 'open' | 'done') {
  // 필터 변경은 replace — 히스토리에 필터 조작이 쌓이지 않게 한다
  router.replace({ query: { ...route.query, status: next === 'all' ? undefined : next } });
}

// 쿼리 키에 반응형 값을 그대로 넣는다. computed를 넣어야 URL이 바뀔 때 재요청된다
const { data, isPending } = useTasksQuery(status);
</script>
```

Vue Query v5의 Vue 어댑터는 `queryKey`에 담긴 `ref`/`computed`를 추적한다. 값을
`.value`로 풀어 넣으면 그 순간의 스냅샷이 키가 되어 **필터를 바꿔도 재요청이 없다.**

## 9. 스토어를 쪼개는 기준

- 도메인 단위로 나눈다: `ui`, `draft`, `notification`
- 하나의 스토어가 20개 이상 필드를 갖거나 서로 무관한 관심사가 섞이면 분리한다
- 스토어끼리 import 하지 않는다. 조합이 필요하면 컴포넌트나 컴포저블에서 각각 읽는다
- 앱에 스토어가 하나뿐이고 필드가 5개 미만이면, 그건 `provide/inject`로도 충분하다는 신호다

## 오용 목록 ① — Vuex → Pinia 관용구 대조표

| Vuex 습관 | Pinia 2 형태 |
| --- | --- |
| `new Vuex.Store({ state, mutations, actions })` | `defineStore('id', () => …)` — **mutations가 없다** |
| `commit('setDensity', v)` | 액션 안에서 `density.value = v` 직접 대입 |
| `dispatch('load')` | `store.load()` 직접 호출 |
| `mapState` / `mapGetters` | `storeToRefs(store)` |
| `getters: { n: (s) => … }` | setup 스토어에서는 `computed(() => …)` |
| `store.state.density` | `store.density` — state·getter·action이 한 평면에 있다 |
| 모듈 `namespaced: true` | 스토어를 파일 단위로 여러 개 만든다 (중첩 없음) |
| `this.$store` | `useXStore()` 호출 |
| `store.replaceState(...)` | 직접 만든 `reset()` 또는 옵션 스토어의 `$reset()` |

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `storeToRefs(store)` vs `const { x } = store` | 상태·getter는 반드시 `storeToRefs`. 액션만 꺼낼 때는 직접 구조 분해가 맞다 |
| Pinia 스토어 vs Vue Query 반환값 | **Vue Query 반환값은 구조 분해해도 안전하다** — 그것은 프록시가 아니라 Ref들을 담은 평범한 객체다. 스토어는 프록시라 위험하다. 같은 문법이 한쪽에서만 깨지는 이유가 이것이다 |
| `ref` vs `reactive` (스토어 내부) | setup 스토어에서는 `ref`. `reactive` 객체를 반환하면 `storeToRefs`가 무의미해지고 재대입도 막힌다 |
| `$patch` vs 개별 대입 | 여러 필드를 한 전이로 묶어 구독을 한 번만 깨우려면 `$patch` |
| `$reset()` vs 직접 만든 `reset()` | `$reset()`은 **옵션 스토어 전용**이다. setup 스토어에서 부르면 런타임 오류 |
| `store.$subscribe` vs `watch` | 스토어 전체의 변경 로그가 필요하면 `$subscribe`. 특정 필드에 반응하려면 `watch` |
| Pinia vs Vue Query | 서버에 원본이 있으면 Query. 서버가 존재조차 모르는 값이면 Pinia |
| Pinia vs URL | 새로고침·링크 공유로 복원돼야 하면 URL. 세션 안에서만 의미 있으면 Pinia |
| Pinia vs `provide/inject` | inject는 **하위 트리 국소 주입**(폼 컨텍스트, 테마)에 맞다. 앱 어디서나 읽는 값은 Pinia |
| 쿼리 키에 `computed` vs `.value` | 반응형 파라미터는 `computed`를 그대로 넘긴다. `.value`로 풀면 재요청이 사라진다 |
| 액션을 스토어에 vs 컴포넌트에 | 여러 곳에서 같은 전이가 일어나면 스토어 액션. 한 화면에서만 쓰는 전이는 컴포넌트에 둔다 |
