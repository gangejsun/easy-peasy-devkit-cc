<!-- epcc-pack: frontend/vue v3.12.0 -->
# Routing (Vue Router 4)

Vite SPA에서 라우트 레코드를 **코드로 직접 선언**한다. 파일 기반 라우팅 플러그인을
도입하지 않는다 — 어떤 경로가 보호되는지 한 파일에서 볼 수 있어야 한다.

## 1. 라우트 레코드 (`src/router/routes.ts`)

```ts
// src/router/routes.ts
import type { RouteRecordRaw } from 'vue-router';
import DefaultLayout from '@/layouts/DefaultLayout.vue';

// meta에 타입을 준다. 없으면 any가 되어 `requiresAuht` 같은 오타가 그대로 통과한다
declare module 'vue-router' {
  interface RouteMeta {
    requiresAuth?: boolean;
    title?: string;
  }
}

export const routes: RouteRecordRaw[] = [
  {
    path: '/',
    component: DefaultLayout,          // 레이아웃은 부모 라우트가 소유한다
    children: [
      { path: '', redirect: { name: 'tasks' } },
      // 로그인 화면 자체는 이음매가 제공한다 — 여기서는 경로만 잡는다
      { path: 'login', name: 'login', component: () => import('@/features/auth/pages/LoginPage.vue') },
      {
        path: 'tasks',
        meta: { requiresAuth: true },   // 자식에게 병합되어 내려간다
        children: [
          { path: '', name: 'tasks', component: () => import('@/features/tasks/pages/TaskListPage.vue') },
          {
            path: ':taskId',
            name: 'task-detail',
            props: true,                // 라우트 파라미터를 prop으로 — 컴포넌트가 라우터를 모른다
            component: () => import('@/features/tasks/pages/TaskDetailPage.vue'),
          },
        ],
      },
      // v4의 캐치올 문법. `path: '*'`는 v3 문법이고 v4에서는 매치되지 않는다
      { path: ':pathMatch(.*)*', name: 'not-found', component: () => import('@/features/errors/pages/NotFoundPage.vue') },
    ],
  },
];
```

- 라우트 트리는 **한 파일**에 모은다. 흩어지면 어떤 경로가 보호되는지 볼 수 없다
- 중첩은 URL 구조가 아니라 **공유 레이아웃**을 기준으로 만든다
- 모든 라우트에 `name`을 준다 — 경로 문자열이 코드에 흩어지면 경로 변경이 전수 수정이 된다
- `props: true`로 파라미터를 넘기면 그 화면을 라우터 없이 테스트할 수 있다

## 2. 라우터 생성 (`src/router/index.ts`)

```ts
// src/router/index.ts
import { createRouter, createWebHistory } from 'vue-router';
import { config } from '@/config';
import { routes } from './routes';
import { safeReturnTo } from '@/lib/safeReturnTo';
import { useAuth } from '@/auth/useAuth';        // 이음매가 제공하는 컴포저블

export const router = createRouter({
  history: createWebHistory(config.basePath),    // 서브 경로 배포 시 Vite의 base와 같은 값
  routes,
  scrollBehavior: (to, from, saved) => saved ?? (to.hash ? { el: to.hash } : { top: 0 }),
});
```

`createWebHashHistory()`는 쓰지 않는다 — 해시 URL은 공유·SEO·`hash` 앵커를 동시에 망친다.
진짜 경로를 쓰는 대가는 §6의 호스팅 설정 하나뿐이다.

## 3. 레이아웃과 `<RouterView />`

```vue
<script setup lang="ts">
// src/layouts/DefaultLayout.vue
import { RouterView } from 'vue-router';
import AppHeader from '@/components/layout/AppHeader.vue';
</script>

<template>
  <div class="min-h-screen bg-slate-50">
    <AppHeader />
    <main class="mx-auto max-w-5xl px-6 py-8">
      <!-- 자식 라우트가 여기 렌더된다. 라우트가 바뀌면 컴포넌트가 새로 마운트된다 -->
      <!-- loading-error-states.md §6이 지시한 배치 — 레이아웃이 RouterView를 감싼다 -->
      <ErrorBoundary>
        <RouterView v-slot="{ Component, route }">
          <component :is="Component" :key="route.path" />
        </RouterView>
      </ErrorBoundary>
    </main>
  </div>
</template>
```

`:key`가 **같은 컴포넌트를 재사용하는 파라미터 변경**(`/tasks/1` → `/tasks/2`)에서 컴포넌트를
새로 마운트시킨다. key가 없으면 `setup()`이 다시 돌지 않아 이전 작업의 데이터가 남는다 —
Vue Router에서 가장 흔한 "왜 안 바뀌지" 사고다.

**`route.path`를 쓴다. `route.fullPath`가 아니다.** `fullPath`는 쿼리스트링과 해시를
포함하므로 필터 변경(`?status=open`)·정렬 변경·해시 앵커 이동마다 페이지가 파괴·재생성된다.
그러면 입력 중이던 폼이 날아가고, 배경 갱신 설계(`resources/loading-error-states.md` §1의
`isFetching` 얇은 바)도 무력해진다 — 재마운트에는 유지할 "기존 화면"이 없기 때문이다.
상태를 유지하고 싶다면 key를 빼는 대신 파라미터를 `watch`한다.

## 4. 네비게이션 가드

인증 **주체**는 이음매가 준다. 이 팩은 가드의 자리와 형태만 소유한다.

```ts
// src/router/index.ts — 전역 가드는 이 파일 하나에만 둔다
router.beforeEach(async (to) => {
  if (!to.meta.requiresAuth) return true;       // meta는 부모→자식으로 병합되어 있다

  const auth = useAuth();
  await auth.ensureReady();                     // 세션 복구가 끝나기 전에 판정하면 새로고침마다 튕긴다
  if (auth.isAuthenticated.value) return true;

  return { name: 'login', query: { returnTo: to.fullPath }, replace: true };
});
```

- v4 가드는 `next()`를 부르지 않는다. `true`(통과) · `false`(취소) · 라우트 위치(리다이렉트)를
  **반환**한다. `next`와 반환을 섞으면 가드가 두 번 실행된다
- `replace: true`가 없으면 뒤로가기가 보호 라우트로 되돌아가 루프가 된다
- 가드 안에서 컴포저블을 부르는 것은 **함수 본문 안일 때만** 안전하다. 모듈 최상위에서
  부르면 pinia·앱이 아직 없다
- 이 게이트는 **UX 장치이지 보안 장치가 아니다.** 라우트를 통과하지 못해도 API는 여전히
  호출 가능하며 실제 차단은 서버가 한다

## 5. 복귀 경로 검증

`returnTo`는 URL 쿼리에서 온 **밖에서 들어온 값**이다. `//evil.example`, `/\evil.example`,
제어문자가 섞인 값은 브라우저에서 외부 URL로 파싱된다. `startsWith('/')` 검사로는 막히지 않는다.

```ts
// src/lib/safeReturnTo.ts
export function safeReturnTo(raw: unknown, fallback = '/tasks'): string {
  if (typeof raw !== 'string' || raw === '') return fallback;
  try {
    const url = new URL(raw, window.location.origin);
    if (url.origin !== window.location.origin) return fallback;   // //host, https://host 차단
    // origin 검사만으로는 부족하다: `/..//evil.example` 처럼 점 세그먼트가 선행 `/`를
    // 삼키면 정규화 결과가 다시 프로토콜-상대 경로(`//host`)가 된다. 입력이 아니라
    // **출력**을 검증한다.
    const p = url.pathname;
    if (!p.startsWith('/') || p.startsWith('//') || p.startsWith('/\\')) return fallback;
    return p + url.search + url.hash;
  } catch {
    return fallback;
  }
}
```

`safeReturnTo`는 **소비하는 화면이 있어야 의미가 있다.** 복귀 경로를 읽는 곳은 이음매의
로그인 화면 하나뿐이고, 그 화면은 이 함수를 통과시킨 값만 `router.replace`에 넘긴다.

```ts
// 이음매의 로그인 화면에서 — 검증은 여기서 딱 한 번
const target = safeReturnTo(route.query.returnTo);
await router.replace(target);
```

내부 이동에 `window.location.assign`/`href`를 쓰지 않는다. 검증을 우회하는 통로가 되고,
전체 새로고침으로 캐시와 인증 상태가 날아간다.

**예외는 하나뿐이다** — §6의 청크 유실 복구. 새 번들을 받아야 하므로 전체 리로드가
목적 자체다. 그때도 **1회 가드를 반드시 건다**(아래) — 없으면 새 번들도 같은 라우트를
쪼갠 배포에서 리로드 → 재내비게이션 → 청크 실패가 무한 반복된다.

## 6. 라우트 에러

Vue Router에는 라우트별 에러 컴포넌트가 없다. 실패는 두 종류이고 자리가 다르다.

```ts
// src/router/index.ts — ① 내비게이션 자체의 실패 (지연 로딩 청크 유실이 대부분이다)
router.onError((error, to) => {
  const chunkMissing = /dynamically imported module|Importing a module script failed/i;
  if (chunkMissing.test(String((error as Error).message))) {
    // 배포로 옛 청크가 사라진 경우다. 이때만 전체 새로고침이 정당하다 — SPA 내부 이동으로는
    // 회복할 수 없고, 그대로 두면 사용자는 아무 반응 없는 링크를 계속 누른다
    window.location.assign(to.fullPath);
  }
});
```

② 화면 안에서 던져진 예외는 `onErrorCaptured` 경계가 잡는다
(`loading-error-states.md` §6). 데이터 실패는 예외가 아니라 쿼리의 `isError`로 처리한다.

## 7. 지연 로딩

- 모든 화면은 `component: () => import(...)`로 나눈다. 레이아웃과 자주 쓰는 공통
  컴포넌트는 정적 import로 둔다 — 쪼갤수록 첫 화면에서 요청 수가 늘어난다
- 전환 중 빈 화면이 보이면 `<RouterView>`를 `<Suspense>`로 감싸는 대신, 화면 컴포넌트가
  즉시 자기 스켈레톤을 그리게 한다 (§`loading-error-states.md` §5의 이유)
- 링크 hover에서 미리 받고 싶으면 `queryClient.prefetchQuery`가 아니라 라우트의
  `component` 팩토리를 직접 호출한다

## 8. 정적 호스팅의 딥링크 (history fallback)

`createWebHistory`는 진짜 경로(`/tasks/42`)를 쓴다. 정적 호스팅은 그 경로에 해당하는
파일이 없으므로, **모든 미매칭 경로를 `index.html`로 되돌려 주지 않으면 새로고침과
딥링크가 404가 된다.**

| 호스팅 | 설정 |
| --- | --- |
| nginx | `location / { try_files $uri $uri/ /index.html; }` |
| 오브젝트 스토리지 + CDN | 403·404 응답을 `/index.html`(응답 코드 **200**)로 치환하는 오류 문서 규칙 |
| 리라이트 규칙 파일을 쓰는 정적 호스트 | `/* → /index.html 200` 한 줄 |
| 로컬 미리보기 | `npm run preview`는 기본으로 fallback을 한다 — 배포 환경도 같은지 반드시 확인한다 |

- **API가 같은 오리진인지 다른 오리진인지는 백엔드 축이 정한다.** 같은 오리진의
  `/api/*`로 서빙되면 그 경로를 fallback 규칙보다 **먼저** 매칭시킨다. 다른 오리진이면
  이 항목은 해당 없다 — fallback이 삼킬 API 경로가 애초에 없다
- `index.html`은 `Cache-Control: no-cache`로, 해시가 붙은 자산은 장기 캐시로 서빙한다.
  index를 캐시하면 배포 후에도 옛 번들을 가리켜 §6의 청크 유실이 상시화된다

## 오용 목록 ① — Vue Router 3 → 4 관용구 대조표

| 옛 습관 (v3) | v4 형태 |
| --- | --- |
| `new VueRouter({ mode: 'history' })` | `createRouter({ history: createWebHistory() })` |
| `mode: 'hash'` | `createWebHashHistory()` |
| `path: '*'` 캐치올 | `path: '/:pathMatch(.*)*'` — v4는 와일드카드를 파라미터로 표현한다 |
| `beforeEach((to, from, next) => next())` | `next` 없이 `true`·`false`·라우트 위치를 **반환** |
| `this.$router` / `this.$route` | `useRouter()` / `useRoute()` — 둘은 다른 컴포저블이다 |
| `router.push()`의 콜백 인자 | Promise를 반환한다 — `await router.push(...)` |
| `<router-link tag="li">` | `<RouterLink custom v-slot="{ navigate, isActive }">` |
| `<router-link>`의 `exact` | `<RouterLink>`의 `isExactActive` 슬롯 값 |
| `route.query` 값이 `string`이라고 가정 | `string \| null \| (string \| null)[]` — 반드시 좁힌다 |
| `router.app` / `router.options.routes` 변형 | `router.addRoute()` / `router.removeRoute()` |
| `component: X` 하나만 있는 이름 뷰 | `components: { default: X, sidebar: Y }` |

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `useRoute()` vs `useRouter()` | 읽기(현재 경로·파라미터)는 `useRoute`, 이동은 `useRouter` |
| `<RouterLink>` vs `router.push` | 사용자가 누르는 이동은 항상 `<RouterLink>`(새 탭·우클릭·접근성이 따라온다). `router.push`는 **이벤트 이후**의 프로그램적 이동 |
| `push` vs `replace` | 로그인 리다이렉트·필터 변경처럼 되돌아가면 안 되는 이동은 `replace` |
| `route.params` vs `route.query` | 리소스 식별자는 경로 파라미터(`/tasks/:taskId`), 화면 옵션(필터·정렬)은 쿼리스트링 |
| `props: true` vs `useRoute().params` | 컴포넌트를 라우터에서 떼어내려면 `props`. 라우트 전체가 필요할 때만 `useRoute` |
| 전역 `beforeEach` vs 라우트별 `beforeEnter` | 앱 전체 규칙(인증)은 전역 하나. 특정 라우트만의 조건은 `beforeEnter` |
| `to.meta` vs `to.matched` | v4는 부모 레코드의 meta를 `to.meta`로 **병합**해 준다. `matched`를 훑는 것은 v3 습관이다 |
| `:key="route.fullPath"` vs key 없음 | 같은 컴포넌트를 재사용하는 파라미터 변경에서 초기화가 필요하면 key. 스크롤·입력을 보존해야 하면 key 대신 `watch` |
| `<KeepAlive>` vs 매번 재생성 | 탭 전환처럼 되돌아올 것이 확실한 화면만 `<KeepAlive>`. 목록/상세는 쿼리 캐시가 이미 그 일을 한다 |
| `router.onError` vs `onErrorCaptured` | 내비게이션·청크 로딩 실패는 `onError`. 렌더된 화면 안의 예외는 `onErrorCaptured` |
| `redirect` vs `alias` | 주소를 바꾸려면 `redirect`. 같은 화면을 두 주소로 보이려면 `alias` |
