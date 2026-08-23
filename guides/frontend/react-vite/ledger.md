<!-- epcc-pack-ledger: frontend/react-vite v3.12.0 -->

# react-vite 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 **이음매가 다시 정의하면
중복 정의**이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 **이음매가 반드시
제공해야** 한다. 라이브러리 API는 원장 대상이 아니다 — 프로젝트 로컬 심볼만 싣는다.

## provides — 이 팩이 정의한다

「형태」는 소유 파일과 함께 **호출 계약**을 싣는 열이다. 소유자만 적고 시그니처를 비우면
형제 클러스터가 정의를 열어 볼 수 없어 **추측한다.** 병렬 저작 실측(2026-08-23)에서
치명 결함 2건이 정확히 이 구멍에서 나왔다 — 같은 타입 인자 둘의 **순서**가 뒤집힌 호출은
TypeScript도 게이트도 잡지 못했고(모든 단건 조회가 404), 배수를 *수행*하는 함수를 배선을
*거는* 함수로 오해한 예제가 부팅 톱레벨에 놓여 서버가 800ms 만에 죽었다. 그래서 이 열에는
인자 이름과 순서 · 반환 · **실패 시 던지는 것** · 호출자가 배선할 의무를 적는다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `cn` | styling.md | `cn(...inputs: ClassValue[]): string` — 가변인자. `clsx` → `twMerge` 순서라 **뒤에 온 충돌 클래스가 이긴다** (`px-4 px-6` → `px-6`). 던지지 않는다 | 클래스 병합 유틸 |
| `ButtonProps` | styling.md | `ComponentPropsWithoutRef<'button'> & { variant?: 'primary' \| 'secondary' \| 'danger' \| 'ghost'; size?: 'sm' \| 'md' \| 'lg' }` — 두 필드 모두 선택이고 기본값은 `Button`이 준다. 유니온은 `keyof typeof variants`/`keyof typeof sizes`로 파생되므로 맵에 키를 더하면 타입이 자동으로 늘어난다 | 변형(variant) 타입 |
| `Button` | component-patterns.md | `<Button variant?='primary' size?='md' className? {...button 속성}>{children}</Button>` — props는 `ButtonProps`. 높이·여백·타이포 토큰은 이 컴포넌트가 단독 소유한다. `className`은 `cn()`의 마지막 인자라 호출부가 이기지만 **위치성 조정(`mt-4`·`w-full`)까지만** 허용 — 규약이지 강제가 아니다 | 공통 UI |
| `Field` | component-patterns.md | `<Field label={string} htmlFor={string} error?={string} hint?={string}>{입력 요소}</Field>` — `label`·`htmlFor`·`children` 필수. **호출자 의무: children 입력의 `id`가 `htmlFor`와 같아야** 라벨·`aria-describedby` 연결이 성립한다. `error`가 있으면 `hint`는 렌더되지 않는다 | 공통 UI |
| `DataTable` | component-patterns.md | `<DataTable rows={T[]} columns={Column<T>[]} empty?={ReactNode}/>` — 제네릭 `T extends { id: string }`(row.id가 key). `Column<T> = { key: string; header: ReactNode; cell: (row: T) => ReactNode; className?: string }`. `rows`가 비면 `empty`만 렌더한다 | 공통 UI |
| `PageShell` | component-patterns.md | `<PageShell title={ReactNode} actions?={ReactNode}>{children}</PageShell>` — 슬롯만 갖는다. 페칭·라우팅·도메인 타입을 알지 않는다 (안다면 그건 §3의 ❌ 예시다) | 공통 레이아웃 |
| `EmptyState` · `EmptyStateProps` | loading-error-states.md | `EmptyStateProps = { title?: string; description?: string; action?: ReactNode }` — 전 필드 선택. `title` 기본값 `'표시할 항목이 없습니다'`. `action`이 없으면 버튼 영역 자체가 렌더되지 않는다 | 빈 상태 |
| `ErrorState` · `ErrorStateProps` | loading-error-states.md | `ErrorStateProps = { title?: string; message?: string; error?: unknown; onRetry?: () => void }` — 전 필드 선택. `title` 기본값 `'문제가 발생했습니다'`, `message`를 비우면 `toUserMessage(error)`로 채운다. **`onRetry`를 넘기지 않으면 재시도 버튼이 사라진다** — 403·404·429가 그 경우다. `error`가 `ApiError`면 `requestId`를 함께 표시한다 | 에러 상태 |
| `ListSkeleton` | loading-error-states.md | `<ListSkeleton rows={number}/>` — `rows` **필수**(기본값 없음). `role="status"`와 `aria-label`을 자체 소유하므로 호출부가 다시 붙이지 않는다 | 로딩 상태 |
| `toUserMessage` | loading-error-states.md | `toUserMessage(error: unknown): string` — 던지지 않는다. `ApiError`면 `error.code`로 분기하고, 알 수 없는 코드는 `status === 429`면 요율 문구, 아니면 `error.message`를 그대로 쓴다. `ApiError`가 아니면 일반 문구 | 에러 → 사용자 문구 |
| `useUiStore` · `UiState` | state-management.md | `useUiStore(selector: (s: UiState) => T): T` — 렌더 중에는 훅으로만, 렌더 밖에서는 `useUiStore.getState()`/`.setState()`/`.subscribe(fn)`(구독 해제 함수 반환). 여러 필드를 한 셀렉터로 고르면 `useShallow` 필수(없으면 무한 리렌더). `UiState`는 상태와 액션을 한 객체에 담고 **`reset(): void`을 반드시 포함한다** — 로그아웃 경로가 그것을 부른다 | 클라이언트 전역 상태 |
| `createSidebarSlice` · `SidebarSlice` | state-management.md | `createSidebarSlice: StateCreator<SidebarSlice & FilterSlice, [], [], SidebarSlice>` — 합치는 곳이 `(set, get, store)` 셋을 넘기지만 본문은 `set`만 쓴다. `SidebarSlice = { isSidebarOpen: boolean; toggleSidebar: () => void }`, `isSidebarOpen` 초기값 `true`. 첫 타입 인자는 **합쳐진 전체 상태**여야 `get()`에서 다른 슬라이스가 보인다 | 스토어 슬라이스 |
| `createFilterSlice` · `FilterSlice` | state-management.md | `createFilterSlice: StateCreator<SidebarSlice & FilterSlice, [], [], FilterSlice>` — 본문은 `(set, get)`를 쓴다. `FilterSlice = { savedFilters: string[]; addFilter: (name: string) => void }`, `savedFilters` 초기값 `[]`. `addFilter`는 **중복 이름을 조용히 무시한다**(던지지도, 알리지도 않는다) | 스토어 슬라이스 |
| `clearClientState` | state-management.md | `clearClientState(): void` — 인자 없음. **클라이언트 스토어만** 비운다(`useUiStore.getState().reset()`). **서버 캐시(QueryClient) 폐기와 순서 통제는 로그아웃 절차가 소유한다 — 이 함수에 넣지 않는다.** 스토어를 추가하면 이 함수에 `reset()` 한 줄을 더한다 | 로그아웃 시 클라이언트 상태 초기화 |
| `router` | routing.md | `router: ReturnType<typeof createBrowserRouter>` — 이 앱의 **유일한 인스턴스**이고 `<RouterProvider router={router}/>`에만 넘긴다. 트리는 한 파일에 모으고 `path: '*'`는 최상위 children의 마지막에 둔다. `loader`/`action`을 쓰지 않는다 — 서버 상태의 단일 소유자는 TanStack Query다 | 라우트 트리 |
| `RootLayout` | routing.md | `<RootLayout/>` — props 없음. 헤더와 `<main>`을 그리고 `<Outlet/>` 자리를 소유한다. 최상위 라우트의 `element`로만 쓴다 | 전역 셸 |
| `RequireAuth` | routing.md | `<RequireAuth/>` — props 없음. `useAuth()`를 스스로 읽어 `isLoading`이면 `<FullPageSpinner/>`, 미인증이면 `<Navigate to={'/login?returnTo=' + encodeURIComponent(pathname + search)} replace/>`, 통과하면 `<Outlet/>`. **`path` 없는 레이아웃 라우트로만 배치한다**(children을 감싸야 의미가 있다). UX 게이트이지 보안 경계가 아니다 — 실제 차단은 서버가 한다 | 인증 게이트 레이아웃 라우트 |
| `RouteErrorBoundary` | routing.md | `<RouteErrorBoundary/>` — props 없음. `useRouteError()`로 에러를 직접 읽으므로 라우트의 **`errorElement`로만** 쓴다(일반 자식으로 두면 컨텍스트가 없다). 잡는 것은 **렌더 중 예외**뿐 — 쿼리 에러는 그 쿼리에 `throwOnError: true`가 있어야 여기 도달한다 | 라우트 에러 경계 |
| `safeReturnTo` | routing.md | `safeReturnTo(raw, fallback = '/'): string` — 순서는 **(검증할 원시값, 대체 경로)**이고 `raw: string \| null`, `fallback` 기본값 `'/'`. 던지지 않는다(`new URL` 실패도 `fallback`). **차단→`fallback`**: `//host` · `https://host` · `/\host` · `javascript:` · `/..//host`(정규화 뒤 다시 프로토콜-상대가 되는 경우). **통과**: `/tasks/42?x=1#a` 같은 내부 경로는 `pathname + search + hash`로 그대로 돌아온다. 반환값은 `navigate()`에만 넘긴다 — `window.location.assign`은 검증을 우회한다 | 복귀 경로 검증 (외부 URL 차단) |
| `config` | types-and-testing.md | `config: { apiBaseUrl: string; oidc: { authority: string; clientId: string; logoutUrl: string } }`(`as const`) — 모듈 로드(부팅) 시점에 평가되고, 값이 비면 그 자리에서 `Error('환경변수 …')`를 **던진다**. `import.meta.env`가 등장하는 **유일한 모듈**이며 값은 리터럴 키로 읽어야 Vite 정적 치환이 일어난다 | 환경 값을 읽는 유일한 모듈 |
| `assertTask` · `parseTask` | types-and-testing.md | `assertTask(v: unknown): asserts v is Task` — 반환값이 없는 단언 함수이고 실패하면 `throw new ApiError(500, 'BAD_SHAPE', …)`. `parseTask(v: unknown): Task` — 같은 검사 뒤 값을 그대로 반환한다. **`http`의 `parse` 옵션에 넘기는 쪽은 `parseTask`다**(단언 함수는 값을 돌려주지 않는다) | 응답 좁히기 — 도메인 타입은 `requires`의 `Task` |
| `handlers` · `renderWithProviders` | types-and-testing.md | `handlers: RequestHandler[]` — MSW v2 배열이며 **봉투 계약**을 지켜야 한다(성공 `{ data, nextCursor }`, 실패 `{ error: { code, message, details? }, requestId }`). `renderWithProviders(ui: ReactNode, opts?: { route?: string }): RenderResult & { queryClient }` — 두 번째 인자는 선택이고 기본 `{ route: '/' }`. **호출마다 새 QueryClient**를 만든다(`retry: false`, `gcTime: 0`) — 공유하지 않는다 | 테스트 하네스 |

`Component`는 원장 대상이 아니다 — React Router가 이름을 정하는 lazy 라우트 export라
파일마다 다른 본문을 갖는 것이 정상이다.

## requires — 이음매가 제공해야 한다

이음매가 이 목록을 채우지 못하면 팩의 예제가 실행 불가가 된다. 게이트가 조립 후 대조한다.

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 이음매가
고른 패키지에서 오므로 export가 아니라 **import 문에 그 이름이 등장하는지**로 판정한다.
둘을 같은 규칙으로 검사하면 라이브러리 바인딩이 영원히 미정의로 잡힌다 (추출 시점에 확인).

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `Task` | 프로젝트 | 도메인 엔티티 타입 | 도메인 어휘는 계약이 정한다 (`pack.json`의 `exampleDomain`) |
| `http` | 프로젝트 | `http.get/post/patch/delete(path, init?)` — 봉투를 벗겨 데이터를 반환. **`http.getPage<T>(path, opts?: { parse?: (v: unknown) => T })`도 필요하다** — `types-and-testing.md` §4가 부르고, `parse`를 넘기지 않으면 클라이언트 내부에서 `as T`가 되어 서버가 필드를 지워도 조용히 통과한다 | 응답 봉투 형태가 와이어 계약의 함수 |
| `ApiError` | 프로젝트 | `new ApiError(status: number, code: string, message: string)` — **2·3번 인자가 둘 다 `string`이라 순서만이 구분이고 뒤바꿔도 타입이 통과한다: (code, message)**. `code`·`status`·`details`·`requestId`를 갖는 에러 클래스 — `details`는 422의 필드별 메시지 `Record<string, string[]>`, `requestId`는 실패 봉투의 값이고 `ErrorState`가 그것을 화면에 띄운다. 팩은 3인자 생성만 하고 `details`·`requestId`는 읽기만 한다 — **이음매가 봉투에서 채워야 두 필드가 `undefined`가 되지 않는다** | 에러 코드표가 와이어 계약의 함수 |
| `Page` | 프로젝트 | `Page<T> = { items: T[]; nextCursor: string \| null }` | 페이지네이션 모델이 와이어 계약의 함수 |
| `useTasksQuery` | 프로젝트 | `useTasksQuery(filter: TaskFilter): { data: { pages: Page<Task>[] }; isPending: boolean; isError: boolean; error: unknown; isFetching: boolean; refetch: () => void }` — 인자 1개(필터 객체). **`useInfiniteQuery` 결과여야 한다**: 팩이 `data.pages.flatMap((p) => p.items)`로 펴므로 `data`가 배열이거나 `data.items`면 예제가 깨진다. `isPending`(캐시에 데이터 없음)과 `isFetching`(배경 갱신)은 **별개 필드**이고, `error`는 `ErrorState`·`toUserMessage`로 그대로 넘어가므로 실패는 `ApiError`로 정규화돼야 한다. 목록 쿼리 훅 | 페칭 계층이 이음매 소유 |
| `useAuth` | 라이브러리 | `useAuth(): { isLoading: boolean; isAuthenticated: boolean; user?: { state?: unknown }; error?: { message: string }; signinRedirect: (args?: { state?: unknown }) => Promise<void> }` — **인자 없음**. `{ isLoading, isAuthenticated }`를 반환하는 훅이며, 팩은 `isLoading`을 **먼저** 보고 판정 전에는 튕기지 않는다(순서를 뒤집으면 새로고침마다 로그인으로 간다). `signinRedirect`에 넘긴 `state`는 콜백에서 `user.state`로 되돌아오므로 **밖에서 돌아온 값**이다 — `safeReturnTo`로 재검증한 뒤에만 `navigate`에 넘긴다 | 인증 라이브러리 선택이 백엔드 축의 함수. 이 이음매는 `react-oidc-context`에서 가져온다 |

## 알려진 공백 (추출 시점에 승계, 수리하지 않음)

| 심볼 | 상태 |
| --- | --- |
| `FullPageSpinner` | routing.md에서 3회 소비되나 팩·이음매 어디에도 정의가 없다. **원본 `react-aws-frontend-guide`에도 없던 기존 결함**이며, 이번 재배치는 이를 드러냈을 뿐 만들지 않았다. 게이트가 REVIEW로 보고한다 |
