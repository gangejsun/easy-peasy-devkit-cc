<!-- epcc-pack-ledger: frontend/vue v3.12.0 -->

# vue 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 **이음매가 다시 정의하면
중복 정의**이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 **이음매가 반드시
제공해야** 한다. 라이브러리 API는 원장 대상이 아니다 — 프로젝트 로컬 심볼만 싣는다.

## provides — 이 팩이 정의한다

`export` 선언문이 있는 심볼만 이 표에 싣는다. SFC 컴포넌트는 `.vue` 파일의 **기본
export**라 `export const` 선언이 없으므로 아래 별도 절에 둔다 — 같은 표에 섞으면
기계 대조가 정의문을 찾지 못한다.

「형태」 열은 소유 파일만으로는 알 수 없는 것을 적는다: **인자 이름과 순서** · 타입 ·
반환 · 실패 시 던지는 것 · 호출자가 배선할 의무. 병렬 저작 실측(2026-08-23)에서 형제
클러스터가 형제 파일을 읽지 못한 채 원장의 소유자 정보만 보고 시그니처를 **추측**했고,
같은 타입 인자 둘의 순서가 뒤집힌 호출과 "배선하는 함수 / 수행하는 함수"의 오해가
타입 검사와 게이트를 모두 통과해 치명 결함 2건이 됐다. 그래서 형태를 여기 못 박는다 —
게이트가 빈 칸을 FAIL로 막고, 형태가 선언한 인자 개수를 실제 정의와 대조한다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `cn` | styling.md | **`src/lib/cn.ts`** — `cn(...inputs: ClassValue[]): string` — 가변인자. `clsx`로 조립한 뒤 `twMerge`가 충돌하는 유틸리티 중 **뒤에 온 것**만 남긴다 (`px-4 px-6` → `px-6`) | 클래스 병합 유틸 |
| `ButtonVariant` | styling.md | **`src/components/common/button-variants.ts`** — `type ButtonVariant = 'primary' \| 'secondary' \| 'danger' \| 'ghost'` — `variants` 표의 키와 1:1(`Record<ButtonVariant, string>`)이라 값을 늘리면 표도 함께 늘려야 컴파일된다 | 변형(variant) 타입 |
| `ButtonSize` | styling.md | **`src/components/common/button-variants.ts`** — `type ButtonSize = 'sm' \| 'md' \| 'lg'` — `sizes` 표(`h-*`·`px-*`·`text-*`)의 키. 높이·여백·타이포를 이 세 값이 통째로 정한다 | 크기 타입 |
| `buttonClass` | styling.md | **`src/components/common/button-variants.ts`** — `buttonClass(variant: ButtonVariant, size: ButtonSize): string` — **순서는 variant 먼저, size 나중.** 두 유니온이 서로 겹치지 않아 뒤바꾸면 컴파일이 막는다. 반환은 base + variant + size를 `cn`으로 병합한 완전한 클래스 문자열 | 변형 표 → 클래스 문자열 |
| `Column` | component-patterns.md | **`src/components/common/table-types.ts`** — `type Column<T> = { key: string; header: string; value: (row: T) => string; class?: string }` — `class`만 선택이다. `value`는 **문자열 셀 전용**(리치 셀은 `cell-<key>` 슬롯이 덮는다)이고 `key`가 슬롯 이름과 `<th>`/`<td>`의 `:key`를 동시에 정한다. 소비처 `DataTable`은 `generic="T extends { id: string }"`로 제약한다 | 제네릭 표 컬럼 정의 타입 |
| `toUserMessage` | loading-error-states.md | **`src/lib/toUserMessage.ts`** — `toUserMessage(error: unknown): string` — **던지지 않는다.** `ApiError`의 `NETWORK_ERROR`·`TIMEOUT`만 이 팩이 문구를 갖고, 그 밖의 코드도 `ApiError`가 아닌 값도 모두 일반 폴백 문구로 떨어진다. 서버 원문 메시지를 그대로 반환하지 않는다 | 에러 → 사용자 문구 (전송 계층 코드 + 폴백) |
| `routes` | routing.md | **`src/router/routes.ts`** — `const routes: RouteRecordRaw[]` — 루트 레코드 **1개**(`path: '/'` + `component: DefaultLayout`)에 자식이 달린 단일 트리. 같은 파일이 `declare module 'vue-router'`로 `RouteMeta { requiresAuth?: boolean; title?: string }`를 확장한다. 캐치올은 v4 문법 `:pathMatch(.*)*` | 라우트 레코드 트리 |
| `router` | routing.md | `const router: Router` — `createWebHistory(config.basePath)`로 만든 **앱 유일 인스턴스**. 이 모듈이 `beforeEach`(인증 가드)와 `onError`(청크 유실 → 전체 리로드)를 함께 배선하므로, 소비처는 `useRouter()`로 얻어 쓰기만 하고 전역 가드를 더 달지 않는다 | 라우터 인스턴스 (전역 가드·onError 포함) |
| `safeReturnTo` | routing.md | **`src/lib/safeReturnTo.ts`** — `safeReturnTo(raw: unknown, fallback = '/tasks'): string` — **차단(→ `fallback` 반환)**: 문자열이 아니거나 빈 문자열 · 타 오리진(`https://evil`·`//evil`) · 정규화된 `pathname`이 `//` 또는 `/\`로 시작하는 값(`/..//evil.example`) · `new URL` 파싱 실패. **통과**: 같은 오리진의 `pathname + search + hash`를 **경로 문자열로만** 반환한다(절대 URL을 돌려주지 않는다). 호출자 의무: 결과는 `router.replace`/`push`에만 넘긴다 — `window.location`에 넘기면 검증이 무의미해진다. `fallback` 인자는 **검증하지 않으므로** 리터럴만 준다 | 복귀 경로 검증 (외부 URL 차단) |
| `STORAGE_KEY` | state-management.md | `const STORAGE_KEY = 'ui-preferences'` (string 리터럴) — 이 키를 읽고 쓰는 곳은 셋뿐이다: `useUiStore`의 `restore()`와 저장 `watch`, 그리고 `clearClientState`. 리터럴을 다시 적지 않는다 | 로컬 스토리지 키 — `clearClientState`가 같은 상수를 쓴다 |
| `useUiStore` | state-management.md | `useUiStore(): { isSidebarOpen: Ref<boolean>; density: Ref<Density>; toggleSidebar(): void; setDensity(next: Density): void; reset(): void }` — 무인자. `Density`는 `'comfortable' \| 'compact'`(스토어 파일 로컬 타입, export하지 않는다). **setup 스토어라 `$reset()`이 없다** — 초기화는 `reset()`. 호출자 의무: `app.use(createPinia())` **이후 함수 본문 안에서** 부르고, 상태·getter는 `storeToRefs()`로 꺼낸다(직접 구조 분해하면 반응성이 끊긴다) | 클라이언트 전역 상태 스토어 |
| `clearClientState` | state-management.md | **`src/stores/clearClientState.ts`** — `clearClientState(): void` — 무인자. `useUiStore().reset()`과 `localStorage.removeItem(STORAGE_KEY)`만 한다. **서버 캐시(`queryClient.clear()`)는 건드리지 않는다** — 폐기 순서는 이음매의 세션 리소스가 소유한다. 스토어를 추가하면 이 함수에 그 스토어의 `reset()` 호출을 함께 추가한다 | 로그아웃 시 클라이언트 상태 초기화 |
| `config` | types-and-testing.md | **`src/config.ts`** — `const config: { readonly apiBaseUrl: string; readonly basePath: string }` (`as const`) — `apiBaseUrl`은 `VITE_API_BASE_URL`이 비면 **모듈 평가 시점(부팅)에 throw**한다(첫 사용까지 미루지 않는다). `basePath`는 `import.meta.env.BASE_URL`. `import.meta.env`가 등장하는 유일한 파일이고 비밀은 넣지 않는다 | 환경 값을 읽는 유일한 모듈 |
| `assertTask` | types-and-testing.md | **`src/features/tasks/api/tasks.parse.ts`** — `assertTask(v: unknown): asserts v is Task` — **반환값이 없는 단언 함수**다(`if (assertTask(x))`처럼 쓸 수 없다). `id`·`title`이 `string`인지만 보고 어긋나면 `ApiError('BAD_SHAPE', '응답 형식이 계약과 다릅니다.')`를 던진다. `status`·`createdAt`은 검사하지 않는다 | 응답 좁히기 — 도메인 타입은 `requires`의 `Task` |
| `parseTask` | types-and-testing.md | **`src/features/tasks/api/tasks.parse.ts`** — `parseTask(v: unknown): Task` — `assertTask`를 통과시킨 **같은 객체를 그대로** 반환한다(복사·정규화 없음). 실패 시 `assertTask`가 던진 `ApiError('BAD_SHAPE')`가 그대로 올라온다 | 응답 좁히기 (단건) |
| `parseTaskList` | types-and-testing.md | **`src/features/tasks/api/tasks.parse.ts`** — `parseTaskList(v: unknown): Task[]` — 배열이 아니면 `ApiError('BAD_SHAPE', '목록 응답이 배열이 아닙니다.')`, 원소가 어긋나면 `parseTask`가 던진다. **봉투를 벗기지 않는다** — 페이지 봉투를 그대로 넘기면 여기서 실패하므로 벗기는 일은 호출부(이음매의 쿼리 컴포저블)가 한다 | 응답 좁히기 (목록) |
| `handlers` | types-and-testing.md | **`src/test/msw/handlers.ts`** — `const handlers: RequestHandler[]` (msw v2) — `http.get('*/tasks')` → `HttpResponse.json([])`, `http.post('*/tasks')` → 201 + `{ id: 't1', status: 'open', ...body }`. 경로가 `*` 접두 와일드카드라 baseUrl과 무관하게 매치된다. **응답 봉투는 이음매의 계약**이므로 조립 시 본문을 그 계약으로 교체한다 | msw 기본 핸들러 |
| `server` | types-and-testing.md | **`src/test/setup.ts`** — `const server: SetupServerApi` — `setupServer(...handlers)`의 **테스트 전역 단일 인스턴스**. 같은 파일이 `listen({ onUnhandledRequest: 'error' })`·`resetHandlers()`·`close()`를 `beforeAll`/`afterEach`/`afterAll`에 건다. 개별 테스트는 `server.use(...)`로 그 테스트에서만 덮고 직접 `listen`/`close`를 부르지 않는다 | msw 테스트 서버 |
| `mountWithProviders` | types-and-testing.md | **`src/test/mountWithProviders.ts`** — `mountWithProviders(component: Component, options: Options = {}): { wrapper: VueWrapper; router: Router; queryClient: QueryClient }` — `Options`는 `MountingOptions<Record<string, unknown>>`. pinia · `createMemoryHistory` 라우터 · `VueQueryPlugin`(테스트마다 **새** `QueryClient`, `retry: false`·`gcTime: 0`)을 심고, 호출자의 `options.global.plugins`를 **뒤에 이어 붙여** 병합한다. 호출자 의무: 라우터를 쓰는 화면은 마운트 후 `await router.isReady()` | 테스트 마운트 하네스 |

`useUiStore`는 state-management.md에 **두 번** 나타난다 — setup 표기(§3 본문)와 옵션
표기(§3 말미)다. 같은 스토어의 다른 조립 방식이므로 프로젝트에는 하나만 둔다.

## 공통 컴포넌트 (SFC 기본 export)

`.vue` 파일은 컴포넌트를 기본 export한다. 이름 대조는 심볼이 아니라 **파일 경로**로 한다.
이음매가 같은 이름의 컴포넌트를 다시 만들면 중복이다.

| 컴포넌트 | 정의 파일 | 경로 |
| --- | --- | --- |
| `Button` | component-patterns.md | `src/components/common/Button.vue` |
| `SearchInput` | component-patterns.md | `src/components/common/SearchInput.vue` |
| `FormField` | component-patterns.md | `src/components/common/FormField.vue` |
| `DataTable` | component-patterns.md | `src/components/common/DataTable.vue` |
| `PageShell` | component-patterns.md | `src/components/layout/PageShell.vue` |
| `ListSkeleton` | loading-error-states.md | `src/components/common/ListSkeleton.vue` |
| `EmptyState` | loading-error-states.md | `src/components/common/EmptyState.vue` |
| `ErrorState` | loading-error-states.md | `src/components/common/ErrorState.vue` |
| `ErrorBoundary` | loading-error-states.md | `src/components/common/ErrorBoundary.vue` |
| `DefaultLayout` | routing.md | `src/layouts/DefaultLayout.vue` |

## requires — 이음매가 제공해야 한다

이음매가 이 목록을 채우지 못하면 팩의 예제가 실행 불가가 된다. 게이트가 조립 후 대조한다.

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 이음매가
고른 패키지에서 오므로 export가 아니라 **import 문에 그 이름이 등장하는지**로 판정한다.
둘을 같은 규칙으로 검사하면 라이브러리 바인딩이 영원히 미정의로 잡힌다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `Task` | 프로젝트 | `{ id: string; title: string; createdAt: string; status: 'open' \| 'done' }` (`@/types/task`). **`status`는 선택이 아니다** — `component-patterns.md` §10이 값을 비교하므로 빠지면 TS2339로 깨진다 | 도메인 어휘는 계약이 정한다 (`pack.json`의 `exampleDomain`) |
| `http` | 프로젝트 | `http.get/post/patch/delete(path, init?)` — 봉투를 벗겨 `unknown`을 반환. 네트워크 실패·타임아웃을 `ApiError('NETWORK_ERROR')`·`ApiError('TIMEOUT')`으로 정규화할 의무가 있다 (`loading-error-states.md` §5가 이를 전제한다) | 응답 봉투 형태가 와이어 계약의 함수 |
| `ApiError` | 프로젝트 | `new ApiError(code, message)` · 필드 `code: string` · `details?: Record<string, string[]>`. **코드표에 반드시 포함할 것**: `NETWORK_ERROR`·`TIMEOUT`(HTTP 클라이언트가 만든다) · `BAD_SHAPE`(팩의 `parseTask`가 던진다) — 빠지면 `toUserMessage`가 조용히 일반 폴백으로 떨어진다 | 에러 코드표와 필드 오류 형태가 와이어 계약의 함수 |
| `useTasksQuery` | 프로젝트 | `useTasksQuery(filter?: MaybeRefOrGetter<Filter>)` — **인자는 선택이다** (팩이 무인자로도 호출한다). 반환의 `data`는 `Ref<Task[] \| undefined>`여야 한다 — 페이지 봉투(`Ref<Page<Task>>`)를 주면 3상태 예시가 통째로 깨진다 | 페칭 계층이 이음매 소유 |
| `useCreateTaskMutation` | 프로젝트 | `useCreateTaskMutation(): { mutate: (input: { title: string }, opts?: { onError?: (e: unknown) => void }) => void; isPending: Ref<boolean> }` — 컴포저블 자체는 **인자 없음** · **`mutate`의 순서는 (본문, 옵션)이고 둘 다 평범한 객체라 뒤바꿔도 타입이 통과한다** · `mutate`는 값을 반환하지 않고(팩이 `await`하지 않는다) 실패를 `onError` 콜백으로만 알린다 — `loading-error-states.md` §6이 「`onErrorCaptured`가 잡지 못하는 것」에 `mutate()` 실패를 명시하므로, **거부한 Promise를 흘리면 아무도 잡지 않는다** · `onError`의 인자는 `unknown`이고 팩이 `e instanceof ApiError && e.details`로 좁히므로 검증 실패는 `ApiError`여야 한다 · `isPending`은 값이 아니라 `Ref<boolean>`(템플릿 `:disabled`에서 자동 언랩) · 생성 뮤테이션 컴포저블. `{ mutate, isPending }`을 반환하고 `mutate(input, { onError })`를 받는다 | 요청 본문과 무효화 대상이 와이어 계약의 함수 |
| `useAuth` | 프로젝트 | `useAuth(): { isAuthenticated: Ref<boolean>; ensureReady: () => Promise<void> }` — **인자 없음** · `ensureReady()`도 인자 없고 가드 진입마다 `await`되므로 **중복 호출이 안전**해야 한다(이미 복구됐으면 즉시 resolve) · `isAuthenticated`는 값이 아니라 `Ref`라 스크립트에서 `.value`로 읽는다(빼면 Ref 객체가 항상 truthy) · 호출자 의무: **가드 함수 본문 안에서만** 부른다 — 모듈 최상위에서 부르면 pinia·앱이 아직 없다 | 인증 방식이 백엔드 축의 함수다. **형태를 팩이 못 박는 이유**: 가드는 렌더가 아니라 비동기 함수이므로 "로딩 플래그"가 아니라 **await할 수 있는 것**이 필요하고, 가드가 await할 수 있어야 하고 이후 이음매의 화면이 반응형으로 읽으므로 상태는 `Ref`여야 한다 |

## 알려진 공백

없다. 이 팩의 필수 축-지역 슬롯 6개는 모두 채워져 있고, 비어 보이는 것(데이터 페칭·
인증/세션·완전 예제)은 공백이 아니라 `pack.json`의 `seamSlots`가 선언한 **이음매의 몫**이다.

## 예제에 등장하는 앱 컴포넌트 (프로젝트가 만든다)

`provides`도 `requires`도 아니다 — 팩이 정의하지 않고 이음매가 줄 것도 아니며,
**소비자 프로젝트가 자기 도메인으로 작성하는** 화면이다. 예제에서 이름만 등장하므로
조립 후에도 가이드 안에 정의가 없는 것이 정상이다. 게이트의 심볼 검사는 `.vue` 기본
import를 보지 못하므로 기계가 잡지 못한다 — 그래서 여기 적어 둔다.

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `AppHeader` | routing.md (레이아웃 예시) | 앱 셸 |
| `TaskTable` | loading-error-states.md (3상태 예시의 성공 분기) | 도메인 화면 |
| `TaskListPage` | types-and-testing.md (§7 테스트가 마운트) | 도메인 화면 |
