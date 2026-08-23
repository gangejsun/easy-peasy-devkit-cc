<!-- epcc-pack-ledger: frontend/nextjs v3.12.0 -->

# nextjs 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 이음매가 다시 정의하면
중복이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 이음매가 반드시 제공해야
한다. 라이브러리 API는 대상이 아니다.

## provides — 이 팩이 정의한다

**「형태」는 시그니처 전문이다.** 이 열이 없던 동안 원장은 **소유자만** 알려줬고, 형제
파일을 읽을 수 없는 저자는 시그니처를 **추측했다** — 2026-08-23 병렬 저작 실측에서 치명
결함 2건이 정확히 이 구멍에서 나왔다. 인자 두 개가 모두 `string`이라 순서를 뒤집어 부른
호출을 TypeScript도 게이트도 잡지 못했고(전 단건 조회 404), 「배수를 수행하는 함수」를
「배선하는 함수」로 오해한 예제가 출하됐다(서버가 800ms 만에 종료). 그래서 인자 이름과
**순서** · 타입 · 반환 · 실패 시 던지는 것 · 호출자가 배선해야 할 의무를 적는다.
**이 축은 서버/클라이언트 경계가 있으므로 심볼마다 어느 경계에서 쓰는 것인지를 함께
적는다** — 여기서 틀리면 빌드가 아니라 런타임이나 비밀 노출로 나타난다. 게이트가 빈
「형태」와 **정의 대비 인자 개수 불일치**를 FAIL로 막는다. 한 행 = 한 심볼이다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `cn` | styling.md | `cn(...inputs: ClassValue[]): string` — 가변인자 유틸(인자 1개 = rest) · `clsx`로 조건부 병합 후 `twMerge`로 Tailwind 충돌 해소 · 순수 함수라 서버·클라이언트 **양쪽** | 클래스 병합 유틸 · 변형 컴포넌트 |
| `Badge` | styling.md | `<Badge variant?={'default'\|'outline'\|'destructive'} className?={string} {...React.HTMLAttributes<HTMLSpanElement>} />` — `<span>` 렌더 · `variant` 기본값 `'default'` · 훅이 없어 **양쪽**에서 렌더되지만 `onClick` 등 핸들러 prop을 주려면 Client Component 안이어야 한다 | 클래스 병합 유틸 · 변형 컴포넌트 |
| `PageHeader` | component-patterns.md | `<PageHeader title={string} backHref?={string} rightSlot?={React.ReactNode} />` — **Server Component**(훅 없음) · `children` 받지 않는다 · `backHref`가 없으면 뒤로가기 자리를 빈 칸으로 채운다 · 헤더 높이·타이틀 폰트는 이 컴포넌트만 정의하고 페이지는 props로만 제어한다 | 공통 UI·레이아웃 |
| `PageSection` | component-patterns.md | `<PageSection title={string} action?={React.ReactNode}>{children}</PageSection>` — **Server Component**(훅 없음) · `children` **필수** · `action`은 제목 우측 슬롯 | 공통 UI·레이아웃 |
| `EmptyState` | component-patterns.md | `<EmptyState title={string} description?={string} action?={React.ReactNode} />` — **Server Component**(훅 없음) · `children` 없다 · 「0건」 전용이며 에러 표시가 아니다 | 공통 UI·레이아웃 |
| `SearchInput` | component-patterns.md | `<SearchInput onSearch={(query: string) => void} defaultValue?={string} ref?={React.Ref<HTMLInputElement>} />` — `onSearch`가 **필수 함수 prop**이라 **Client Component 경계 안에서만** 쓸 수 있다(Server → Client 함수 전달 금지) · React 19이므로 `ref`는 일반 prop(`forwardRef` 불필요) · 본문은 가이드에서 생략됨 | 공통 UI·레이아웃 |
| `CollapsiblePanel` | component-patterns.md | `<CollapsiblePanel title={string}>{children}</CollapsiblePanel>` — `'use client'` · `children` **필수**이고 **Server Component를 그대로 통과시킨다**(children으로 받은 트리는 서버에 남는다) · 초기값 열림(`useState(true)`)이며 외부에서 열림 상태를 제어하는 prop은 없다 | 공통 UI·레이아웃 |
| `useUiStore` | state-management.md | `useUiStore<T>(selector: (state: UiState) => T): T` — `'use client'` 전용 훅 · selector 인자 1개(전체 구독 형태를 제공하지 않는다) · `UiStoreProvider` 밖에서 부르면 `Error('useUiStore must be used within UiStoreProvider')`를 **던진다** | 클라이언트 전역 상태 |
| `UiState` | state-management.md | `interface UiState { sidebarOpen: boolean; toggleSidebar: () => void }` — 두 필드 모두 **필수** · 상태와 그 상태를 바꾸는 액션을 같은 타입에 둔다(외부 `setState` 금지) | 클라이언트 전역 상태 |
| `createUiStore` | state-management.md | `createUiStore(init?: { sidebarOpen?: boolean }): StoreApi<UiState>` — 훅이 아니라 vanilla `createStore` **팩토리** · 인자 1개(선택, 실제 타입은 `Partial<Pick<UiState, 'sidebarOpen'>>`) · 호출자 의무: **트리마다 1회만** 부른다(`UiStoreProvider`의 `useRef`가 그 자리다) — 모듈 최상위에서 부르면 서버 요청 간 공유된다 | 클라이언트 전역 상태 |
| `UiStoreProvider` | state-management.md | `<UiStoreProvider>{children}</UiStoreProvider>` — `'use client'` · props는 `children: React.ReactNode` 하나뿐(초기값 prop 없음) · 호출자 의무: 루트 `layout.tsx`(또는 해당 세그먼트 layout)에서 감싼다 — 감싸지 않으면 `useUiStore`가 던진다 · Provider가 클라이언트여도 `children`으로 받은 Server Component는 서버에 남는다 | 클라이언트 전역 상태 |
| `useCartStore` | state-management.md | `useCartStore<T>(selector: (s: CartState) => T): T` — `'use client'` 전용 훅 · `CartState = { items: CartItem[]; add(item: CartItem): void; remove(id: string): void; clear(): void }` · 모듈 최상위 `create()`라 **서버에서는 요청 간 공유**된다(순수 클라이언트 상태에만 허용) · §5는 같은 훅을 `persist({ name: 'cart-storage' })`로 감싼 형태로 다시 보인다 | 스토어 예제 |
| `CartItem` | state-management.md | `interface CartItem { id: string; name: string; qty: number }` — 세 필드 모두 **필수** · `id`는 `remove(id)`의 키이자 리스트 key이므로 안정적이어야 한다 | 스토어 예제 |
| `CartBadge` | state-management.md | `<CartBadge />` — `'use client'` · props 없음 · 마운트 전에는 `<Skeleton className="h-6 w-10" />`를 렌더한다(persist 복원값과 서버 첫 렌더의 hydration 불일치 방지) — 자리표시자 크기를 바꾸면 레이아웃이 튄다 | 스토어 예제 |
| `CartSummary` | state-management.md | `<CartSummary />` — `'use client'` · props 없음 · `useCartStore`를 selector로 구독하고 여러 조각은 `useShallow`로 묶는다(매번 새 객체 → 무한 리렌더 방지) | 스토어 예제 |
| `useQueryParams` | state-management.md | `useQueryParams(): { searchParams: ReadonlyURLSearchParams; setQueryParam: (key: string, value: string \| null) => void }` — `'use client'` · **인자 없음** · **`setQueryParam`의 순서는 (키, 값)이고 둘 다 문자열 계열이라 뒤집어도 타입이 통과한다** · 값이 비었거나 `null`이면 키를 지우고, `key`가 `'page'`가 아니면 `page`도 함께 지운다 · `router.replace(…, { scroll: false })`라 히스토리를 쌓지 않는다 · 호출자 의무: `useSearchParams()`를 쓰므로 `<Suspense>` 경계 안이어야 한다 | URL 상태 · 폼 |
| `ProfileForm` | state-management.md | `<ProfileForm defaultValues?={ProfileFormData} />` — `'use client'` · props는 `defaultValues` 하나(선택) · `ProfileFormData = z.infer<typeof profileSchema>` = `{ name: string; email: string }` · 제출은 Server Action `updateProfile(data)`에 위임한다(RHF는 클라이언트 검증만) · 스키마에 `.default()`를 쓰지 않는다 | URL 상태 · 폼 |
| `DeleteTaskButton` | state-management.md | `<DeleteTaskButton taskId={string} />` — `'use client'` · props는 `taskId` 하나(필수) · `startTransition` 안에서 `deleteTask(taskId)`를 부르고 **실패를 반환값 `result.error`로 받는다**(throw하면 `error.tsx`로 새어 나간다) · `isPending` 동안 버튼을 잠근다 | URL 상태 · 폼 |
| `useDebounce` | performance.md | `useDebounce<T>(value: T, delay = 300): T` — `'use client'` 전용 훅 · 인자 2개이고 둘째는 선택(기본 300ms) · 값·지연이 바뀔 때마다 타이머를 재설정하고 cleanup으로 해제한다 | 성능 패턴 |
| `SearchBar` | performance.md | `<SearchBar />` — `'use client'` · props 없음 · `useQueryParams` + `useDebounce(query, 300)` 조합으로 300ms 정지 후에만 `q`를 갱신한다(서버 재조회는 URL 변경이 유발) · 호출자 의무: `useSearchParams()` 경유이므로 `<Suspense>` 안에 둔다 | 성능 패턴 |
| `TaskStats` | performance.md | `<TaskStats tasks={Task[]} />` — `'use client'` · props는 `tasks` 하나(필수) · 서버에서 조회한 `Task[]`를 props로 받는다(스토어 복제 금지) · 내부 `TaskRow`는 같은 파일 전용이며 export하지 않는다 | 성능 패턴 |
| `LiveStatus` | performance.md | `<LiveStatus statusUrl={string} />` — `'use client'` · props는 `statusUrl` 하나(필수) · 5초마다 `router.refresh()`를 걸고 언마운트 시 인터벌·`AbortController`·리스너를 전부 해제한다 · `statusUrl`은 데이터 계층 **밖**의 외부 API에만 쓴다 | 성능 패턴 |
| `EditToggle` | performance.md | `<EditToggle content={string} />` — `'use client'` · props는 `content` 하나(필수) · `dynamic(…, { ssr: false })`를 쓰므로 **이 컴포넌트 파일 자체가 `'use client'`여야 한다**(Server Component에서 `ssr: false`는 Next.js 15에서 런타임 에러) | 성능 패턴 |
| `Task` | file-organization.md | `interface Task { id: string; title: string; done: boolean; created_at: string }` — 네 필드 모두 **필수** · `created_at`은 snake_case의 ISO 문자열(Date 아님) · `lib/queries/`가 export하는 것을 재사용하고 컴포넌트·`types/`에서 다시 정의하지 않는다 | 도메인 타입·컴포넌트 배치 예제 |
| `TaskCard` | file-organization.md | `<TaskCard task={Task} className?={string} />` — **Server Component**(훅 없음) · `task` 필수·`className` 선택 · `children` 없다 · 본문은 가이드에서 생략됨 | 도메인 타입·컴포넌트 배치 예제 |
| `AppHeader` | routing.md | `<AppHeader />` — **async Server Component** · props 없음 · 내부에서 `await getCurrentUser()`를 부르므로 `'use client'` 파일에서 import할 수 없다 · 사용자 객체 전체가 아니라 필요한 필드만(`user.email`) 클라이언트 잎으로 내린다 | 레이아웃 · 메타데이터 |
| `metadata` | routing.md | `const metadata: Metadata` — 라우팅 파일(`page.tsx`·`layout.tsx`)의 **정적** 모듈 export(함수 아님) · 서버 전용 · 같은 파일에서 `generateMetadata`와 함께 쓸 수 없다 · 루트 layout에 `title.template`이 있으면 `title`만 채운다 | 레이아웃 · 메타데이터 |
| `generateMetadata` | routing.md | `generateMetadata({ params }: PageProps): Promise<Metadata>` — 인자 1개(라우트 props) · `async` 필수이고 `params`는 **Promise라 `await`해야 한다** · 라우팅 파일의 모듈 export이며 서버에서만 실행된다 | 레이아웃 · 메타데이터 |

`Component`·`metadata`·`generateMetadata`·`middleware`는 프레임워크가 이름을 정하는
export다 — 파일마다 다른 본문을 갖는 것이 정상이므로 중복 판정에서 제외한다.

## requires — 이음매가 제공해야 한다

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 import 문에
이름이 등장하는지로 판정한다. `교차축`은 **상대 축 팩**이 정의하므로 이 가이드가 아니라
반대편 가이드에서 찾는다 — 조립 후에도 이 가이드 안에는 정의가 없는 것이 정상이다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `getCurrentUser` | 프로젝트 | `getCurrentUser(): Promise<AuthUser \| null>` — **인자 없음**이고 `async`라 `await` 필수 · 미인증은 throw가 아니라 `null` 반환(호출부가 `user ? … : …`로 분기한다) · **서버 경계 전용**이라 이것을 부르는 컴포넌트는 async Server Component가 된다(`'use client'` 파일에서 import 불가) · `Promise<AuthUser \| null>` — 서버에서 검증된 사용자 | 인증 주체 확인 방식이 백엔드 축의 함수 |
| `AuthUser` | 프로젝트 | `{ id, email }` | 위와 같다 |
| `getTasks` | 프로젝트 | `getTasks(filter?: { id?: string }): Promise<Task[]>` — **호출부 불일치 있음**: `PACK.md`는 무인자 `getTasks()`(2곳, 「RLS가 본인 행만 반환 — userId 인자 불필요」), `typescript-standards.md`는 `getTasks({ id })` 1곳. **무인자가 정본**이고 인자는 **선택 필터**로 본다(선택 인자 1개면 양쪽 호출이 모두 컴파일된다) · **인자는 userId가 아니다** — 주체는 RLS가 정하므로 이음매가 첫 인자를 소유자 id로 구현하면 안 된다 · 빈 결과는 `null`이 아니라 `[]`(호출부가 `.length`·`.map`을 바로 쓴다) · 목록 쿼리 함수 | 데이터 액세스 계층이 이음매 소유 |
| `TaskList` | 프로젝트 | 목록 렌더 컴포넌트 | 페칭 방식에 종속 |
| `ActionState` | 프로젝트 | Server Action 반환 계약 | 액션 경계가 조합의 함수 |
| `Database` | 교차축 | DB 스키마에서 생성한 타입 | **백엔드 축 팩**이 생성 절차를 소유한다 (`backend/supabase`의 `database-patterns.md`). 프론트 가이드 안에 정의가 없는 것이 정상이다 |

## 추출 시 이 팩에서 제거한 것

축-지역이 아니라고 판정해 이음매로 옮겼다. 되돌리려면 이 표가 근거다.

| 옮긴 것 | 원래 위치 | 간 곳 |
| --- | --- | --- |
| §6 보호 라우트 (미들웨어 세션 갱신 포함) | `routing.md` L133-213 | 이음매 `auth-and-session.md` |
| §7 생성 타입 (`supabase gen types`) | `typescript-standards.md` L115-134 | **백엔드 축 팩** `backend/supabase/database-patterns.md` |
| 백엔드 클라이언트 직접 호출 4곳 | `routing.md` · `typescript-standards.md` | `getCurrentUser`·`getTasks` 위임으로 치환 (requires에 선언) |

## 알려진 공백 (추출 시점에 승계, 수리하지 않음)

| 항목 | 상태 |
| --- | --- |
| `Task` 3중 정의 | 팩 `file-organization.md`, 이음매 `data-fetching.md`·`complete-example.md`. **필드가 완전히 동일**하고 형식만 다르므로 시그니처 충돌은 아니다. 원본 `nextjs-frontend-guide`에서 승계 |
