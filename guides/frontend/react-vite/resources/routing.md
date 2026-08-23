<!-- epcc-pack: frontend/react-vite v3.12.0 -->
# Routing (React Router v7 · 라이브러리 모드)

Vite SPA에서 React Router를 **라이브러리로만** 쓴다 — 프레임워크 모드나 파일 기반
라우팅을 도입하지 않고, 라우트 객체 트리를 코드로 직접 선언한다.

## 1. 라우트 트리 (`src/routes/routes.tsx`)

```tsx
import { createBrowserRouter } from 'react-router';
import { RootLayout } from './RootLayout';
import { RequireAuth } from './RequireAuth';

export const router = createBrowserRouter([
  {
    path: '/',
    element: <RootLayout />,
    errorElement: <RouteErrorBoundary />,
    children: [
      { index: true, element: <Navigate to="/tasks" replace /> },
      { path: 'login', lazy: () => import('@/auth/pages/LoginPage') },
      // OIDC redirect_uri와 **같은 경로**여야 한다 (auth-and-session.md §2).
      // 이 라우트가 없으면 issuer가 되돌려 보낸 콜백이 404 화면에 떨어져 로그인이 끝나지 않는다
      { path: 'auth/callback', lazy: () => import('@/auth/pages/AuthCallbackPage') },
      {
        element: <RequireAuth />,               // path 없는 레이아웃 라우트 = 인증 게이트
        children: [
          {
            path: 'tasks',
            children: [
              { index: true, lazy: () => import('@/features/tasks/pages/TaskListPage') },
              { path: ':taskId', lazy: () => import('@/features/tasks/pages/TaskDetailPage') },
            ],
          },
          { path: 'settings', lazy: () => import('@/features/settings/pages/SettingsPage') },
        ],
      },
      { path: '*', element: <NotFoundPage /> },
    ],
  },
]);
```

```tsx
// main.tsx — 중첩 순서는 auth-and-session.md §4와 **동일**하다 (두 곳이 어긋나면 안 된다)
<AuthProvider userManager={userManager} onSigninCallback={onSigninCallback}>
  <AuthWiring>                                {/* 토큰 공급자 장착 — 빠지면 헤더 없이 요청이 나간다 */}
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </AuthWiring>
</AuthProvider>
```

`lazy`가 가리키는 모듈은 라우트 속성을 내보낸다 — 화면 컴포넌트는 `Component`라는
이름으로 export한다.

```tsx
// features/tasks/pages/TaskListPage.tsx
export function Component() { /* ... */ }
Component.displayName = 'TaskListPage';
```

- 라우트 트리는 **한 파일**에 모은다. 여러 곳에 흩어지면 어떤 경로가 보호되는지 볼 수 없다
- 중첩은 URL 구조가 아니라 **공유 레이아웃**을 기준으로 만든다
- `element`가 없는 라우트(레이아웃 라우트)는 게이트·컨텍스트 주입에 쓴다

## 2. 레이아웃과 `<Outlet />`

```tsx
export function RootLayout() {
  return (
    <div className="min-h-screen bg-slate-50">
      <AppHeader />
      <main className="mx-auto max-w-5xl px-6 py-8">
        <Outlet />   {/* 자식 라우트가 여기 렌더된다 */}
      </main>
    </div>
  );
}
```

부모 레이아웃에서 자식으로 값을 내려야 하면 `<Outlet context={value} />` +
`useOutletContext<T>()`를 쓴다. 전역 스토어보다 결합이 얕다.

## 3. 보호 라우트

```tsx
export function RequireAuth() {
  const { isLoading, isAuthenticated } = useAuth();
  const location = useLocation();

  if (isLoading) return <FullPageSpinner />;      // 세션 복구 중 — 판정 전에 튕기지 않는다
  if (!isAuthenticated) {
    const returnTo = location.pathname + location.search;
    return <Navigate to={`/login?returnTo=${encodeURIComponent(returnTo)}`} replace />;
  }
  return <Outlet />;
}
```

- `isLoading` 동안 리다이렉트하면 새로고침마다 로그인 화면이 번쩍인다
- `replace`를 쓴다 — 그렇지 않으면 뒤로가기가 보호 라우트로 되돌아가 루프가 된다
- **복귀 경로는 반드시 내부 경로인지 검증한다.** `//evil.com`, `/\evil.com`, 제어문자가
  섞인 값은 브라우저에서 외부 URL로 파싱된다. 문자열 prefix 검사(`startsWith('/')`)만으로는
  막히지 않는다

```ts
// src/lib/safeReturnTo.ts
export function safeReturnTo(raw: string | null, fallback = '/'): string {
  if (!raw) return fallback;
  try {
    const url = new URL(raw, window.location.origin);
    if (url.origin !== window.location.origin) return fallback;  // //host, https://host 차단
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

`safeReturnTo`는 **소비하는 화면이 있어야 의미가 있다.** 복귀 경로를 읽는 곳은 로그인
페이지와 콜백 페이지 둘뿐이고, 둘 다 이 함수를 통과시킨 값만 `navigate`에 넘긴다.

```tsx
// src/auth/pages/LoginPage.tsx
export function Component() {
  const auth = useAuth();
  const [params] = useSearchParams();
  const navigate = useNavigate();
  const target = safeReturnTo(params.get('returnTo'));   // 검증은 여기서 딱 한 번

  useEffect(() => {
    if (auth.isAuthenticated) navigate(target, { replace: true });   // 라우터 안에서만 이동한다
  }, [auth.isAuthenticated, target, navigate]);

  if (auth.isLoading) return <FullPageSpinner />;
  return <Button onClick={() => auth.signinRedirect({ state: { returnTo: target } })}>로그인</Button>;
}
Component.displayName = 'LoginPage';
```

```tsx
// src/auth/pages/AuthCallbackPage.tsx — AuthProvider가 code를 교환하는 동안의 화면
export function Component() {
  const auth = useAuth();
  const navigate = useNavigate();

  useEffect(() => {
    if (auth.isLoading || !auth.isAuthenticated) return;
    const raw = (auth.user?.state as { returnTo?: string } | undefined)?.returnTo ?? null;
    navigate(safeReturnTo(raw), { replace: true });     // state는 왕복해 온 값 → 반드시 재검증
  }, [auth.isLoading, auth.isAuthenticated, auth.user, navigate]);

  if (auth.error) return <ErrorState title="로그인에 실패했습니다" message={auth.error.message} />;
  return <FullPageSpinner />;
}
Component.displayName = 'AuthCallbackPage';
```

- 복귀 이동에 **`window.location.assign`/`href`를 쓰지 않는다.** 검증을 우회하는 통로가
  되고, 전체 새로고침으로 캐시와 인증 상태가 날아간다. 내부 이동은 언제나 `navigate`다
- `returnTo`는 URL 쿼리든 OIDC `state`든 **밖에서 돌아온 값**이다. 출처가 우리 코드처럼
  보여도 그대로 믿지 않는다

이 게이트는 **UX 장치이지 보안 장치가 아니다.** 라우트를 통과하지 못해도 API는 여전히
호출 가능하며, 실제 차단은 서버가 한다 (`auth-and-session.md` 참고).

## 4. 라우트 에러 처리

```tsx
export function RouteErrorBoundary() {
  const error = useRouteError();

  if (isRouteErrorResponse(error)) {
    return <ErrorState title={`${error.status}`} message={error.statusText} />;
  }
  if (error instanceof ApiError) {
    // 분기는 code로 한다. NOT_FOUND는 "없는 리소스"와 "남의 리소스"를 함께 뜻한다
    return <ErrorState title="요청을 처리할 수 없습니다" message={toUserMessage(error)} />;
  }
  return <ErrorState title="문제가 발생했습니다" onRetry={() => window.location.reload()} />;
}
```

`errorElement`는 **렌더 중 발생한 예외**를 잡는다. 쿼리 에러를 여기까지 올리려면
쿼리에 `throwOnError: true`를 켜야 한다 — 기본은 `isError`로 화면 안에서 처리한다.

## 5. URL을 상태로 쓴다

목록의 필터·정렬은 컴포넌트 상태가 아니라 URL에 둔다. 공유·새로고침·뒤로가기가
공짜로 동작하고, 그 값이 그대로 쿼리 키가 된다.

```tsx
const [searchParams, setSearchParams] = useSearchParams();
const filter: TaskFilter = {
  status: (searchParams.get('status') as TaskFilter['status']) ?? 'all',
};

// 필터 변경 — 히스토리를 더럽히지 않도록 replace
const setStatus = (status: TaskFilter['status']) =>
  setSearchParams({ status }, { replace: true });

const { data } = useTasksQuery(filter);   // URL → 쿼리 키
```

**커서는 URL에 넣지 않는다.** 백엔드의 페이지네이션은 불투명 커서이므로 URL에 실어도
공유·복원의 의미가 없고, 페이지 번호도 존재하지 않는다. 다음 페이지 상태는
`useInfiniteQuery`가 캐시 안에서 소유한다 (`data-fetching.md` §3).

## 6. 정적 호스팅의 딥링크 (history fallback)

`createBrowserRouter`는 진짜 경로(`/tasks/42`)를 쓴다. 정적 호스팅은 그 경로에 해당하는
파일이 없으므로, **모든 미매칭 경로를 `index.html`로 되돌려 주지 않으면 새로고침과
딥링크가 404가 된다.** `/auth/callback`도 예외가 아니어서, 이 설정이 빠지면 로그인 자체가
끝나지 않는다.

| 호스팅 | 설정 |
| --- | --- |
| S3 + CloudFront | 배포의 사용자 지정 오류 응답에서 403·404 → `/index.html`, 응답 코드 **200**. 또는 뷰어 요청 CloudFront Function으로 확장자 없는 경로를 `/index.html`로 재작성 |
| nginx | `location / { try_files $uri $uri/ /index.html; }` |
| 로컬 미리보기 | `vite preview`는 기본으로 fallback을 한다 — 배포 환경도 같은지 반드시 확인한다 |

- API는 **다른 오리진**(ALB)이다. fallback 규칙이 `/api/*`를 삼키지 않는지 확인한다
- `index.html`은 `Cache-Control: no-cache`로, 해시가 붙은 자산은 장기 캐시로 서빙한다.
  index를 캐시하면 배포 후에도 옛 번들을 가리켜 화면이 통째로 깨진다

## 7. 이 스택에서 하지 않는 것

- **`loader` / `action`으로 데이터를 읽고 쓰지 않는다.** 서버 상태의 단일 소유자는
  TanStack Query다. 둘을 섞으면 같은 데이터에 두 개의 캐시·두 개의 무효화 경로가 생긴다.
  라우터는 "어떤 화면을 보여줄지"만 담당한다
- 프리페치가 필요하면 loader가 아니라 링크 hover에서 `queryClient.prefetchQuery`를 부른다
- `<a href="/tasks">`를 쓰지 않는다 — 전체 페이지 새로고침이 되어 앱 상태와 캐시가 날아간다

## 오용 목록 ① — 버전 관용구 대조표

| 옛 습관 (v5/v6) | v7 형태 |
| --- | --- |
| `import { Link } from 'react-router-dom'` | `import { Link } from 'react-router'` — v7에서 패키지가 통합됐다 |
| `<Switch>` / `<Route component={X}>` (v5) | `<Routes>` / `element={<X />}`, 또는 라우트 객체의 `Component` |
| `useHistory().push(...)` (v5) | `useNavigate()('/path')` |
| `<Redirect to="/x" />` (v5) | `<Navigate to="/x" replace />` |
| `useRouteMatch()` (v5) | `useMatch(pattern)` |
| `<NavLink activeClassName="on">` (v5) | `<NavLink className={({ isActive }) => cn(base, isActive && 'on')}>` |
| JSX `<Route>` 트리만 사용 | `createBrowserRouter([...])` 객체 트리 — `errorElement`·`lazy` 등 데이터 API가 여기서만 동작한다 |
| `React.lazy` + `<Suspense>`로 화면 분할 | 라우트의 `lazy` 속성 — 라우터가 전환 중 분할 로딩을 처리한다 |

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `<Link>` vs `useNavigate` | 사용자가 누르는 이동은 항상 `<Link>`(새 탭·우클릭·접근성이 따라온다). `useNavigate`는 **이벤트 이후**의 프로그램적 이동(저장 성공 후 상세로) |
| `navigate(path)` vs `navigate(path, { replace: true })` | 로그인 리다이렉트·폼 제출 후처럼 되돌아가면 안 되는 이동은 `replace` |
| `useParams` vs `useSearchParams` | 리소스 식별자는 경로 파라미터(`/tasks/:taskId`), 화면 옵션(필터·정렬·페이지)은 쿼리스트링 |
| 레이아웃 라우트 vs 래퍼 컴포넌트 | 인증 게이트·공유 셸처럼 **URL을 갖지 않는 계층**은 `path` 없는 라우트 + `<Outlet />`. 화면 안 일부만 감싸는 것은 그냥 컴포넌트 |
| `errorElement` vs 컴포넌트 내 `isError` | 화면 전체가 못 뜨는 경우만 `errorElement`. 목록 위젯 하나가 실패한 경우는 그 자리에서 `isError` 분기 |
| `index: true` vs `path: ''` | 부모 경로에 정확히 일치할 때 보여줄 자식은 `index: true`. `path: ''`는 의도가 흐려지고 중첩에서 어긋난다 |
| `path: '*'` 위치 | 최상위 children의 **마지막**에 둔다. 중첩 안쪽에 두면 그 하위 트리의 미스만 잡는다 |
