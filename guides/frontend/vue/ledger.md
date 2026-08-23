<!-- epcc-pack-ledger: frontend/vue v3.12.0 -->

# vue 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 **이음매가 다시 정의하면
중복 정의**이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 **이음매가 반드시
제공해야** 한다. 라이브러리 API는 원장 대상이 아니다 — 프로젝트 로컬 심볼만 싣는다.

## provides — 이 팩이 정의한다

`export` 선언문이 있는 심볼만 이 표에 싣는다. SFC 컴포넌트는 `.vue` 파일의 **기본
export**라 `export const` 선언이 없으므로 아래 별도 절에 둔다 — 같은 표에 섞으면
기계 대조가 정의문을 찾지 못한다.

| 심볼 | 정의 파일 | 성격 |
| --- | --- | --- |
| `cn` | styling.md | 클래스 병합 유틸 |
| `ButtonVariant` | styling.md | 변형(variant) 타입 |
| `ButtonSize` | styling.md | 크기 타입 |
| `buttonClass` | styling.md | 변형 표 → 클래스 문자열 |
| `Column` | component-patterns.md | 제네릭 표 컬럼 정의 타입 |
| `toUserMessage` | loading-error-states.md | 에러 → 사용자 문구 (전송 계층 코드 + 폴백) |
| `routes` | routing.md | 라우트 레코드 트리 |
| `router` | routing.md | 라우터 인스턴스 (전역 가드·onError 포함) |
| `safeReturnTo` | routing.md | 복귀 경로 검증 (외부 URL 차단) |
| `STORAGE_KEY` | state-management.md | 로컬 스토리지 키 — `clearClientState`가 같은 상수를 쓴다 |
| `useUiStore` | state-management.md | 클라이언트 전역 상태 스토어 |
| `clearClientState` | state-management.md | 로그아웃 시 클라이언트 상태 초기화 |
| `config` | types-and-testing.md | 환경 값을 읽는 유일한 모듈 |
| `assertTask` | types-and-testing.md | 응답 좁히기 — 도메인 타입은 `requires`의 `Task` |
| `parseTask` | types-and-testing.md | 응답 좁히기 (단건) |
| `parseTaskList` | types-and-testing.md | 응답 좁히기 (목록) |
| `handlers` | types-and-testing.md | msw 기본 핸들러 |
| `server` | types-and-testing.md | msw 테스트 서버 |
| `mountWithProviders` | types-and-testing.md | 테스트 마운트 하네스 |

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
| `useCreateTaskMutation` | 프로젝트 | 생성 뮤테이션 컴포저블. `{ mutate, isPending }`을 반환하고 `mutate(input, { onError })`를 받는다 | 요청 본문과 무효화 대상이 와이어 계약의 함수 |
| `useAuth` | 프로젝트 | `{ isAuthenticated: Ref<boolean>; ensureReady: () => Promise<void> }` | 인증 방식이 백엔드 축의 함수다. **형태를 팩이 못 박는 이유**: 가드는 렌더가 아니라 비동기 함수이므로 "로딩 플래그"가 아니라 **await할 수 있는 것**이 필요하고, 가드가 await할 수 있어야 하고 이후 이음매의 화면이 반응형으로 읽으므로 상태는 `Ref`여야 한다 |

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
