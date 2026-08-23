<!-- epcc-pack-ledger: frontend/react-vite v3.12.0 -->

# react-vite 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 **이음매가 다시 정의하면
중복 정의**이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 **이음매가 반드시
제공해야** 한다. 라이브러리 API는 원장 대상이 아니다 — 프로젝트 로컬 심볼만 싣는다.

## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 성격 |
| --- | --- | --- |
| `cn` | styling.md | 클래스 병합 유틸 |
| `ButtonProps` | styling.md | 변형(variant) 타입 |
| `Button` | component-patterns.md | 공통 UI |
| `Field` | component-patterns.md | 공통 UI |
| `DataTable` | component-patterns.md | 공통 UI |
| `PageShell` | component-patterns.md | 공통 레이아웃 |
| `EmptyState` · `EmptyStateProps` | loading-error-states.md | 빈 상태 |
| `ErrorState` · `ErrorStateProps` | loading-error-states.md | 에러 상태 |
| `ListSkeleton` | loading-error-states.md | 로딩 상태 |
| `toUserMessage` | loading-error-states.md | 에러 → 사용자 문구 |
| `useUiStore` · `UiState` | state-management.md | 클라이언트 전역 상태 |
| `createSidebarSlice` · `SidebarSlice` | state-management.md | 스토어 슬라이스 |
| `createFilterSlice` · `FilterSlice` | state-management.md | 스토어 슬라이스 |
| `clearClientState` | state-management.md | 로그아웃 시 클라이언트 상태 초기화 |
| `router` | routing.md | 라우트 트리 |
| `RootLayout` | routing.md | 전역 셸 |
| `RequireAuth` | routing.md | 인증 게이트 레이아웃 라우트 |
| `RouteErrorBoundary` | routing.md | 라우트 에러 경계 |
| `safeReturnTo` | routing.md | 복귀 경로 검증 (외부 URL 차단) |
| `config` | types-and-testing.md | 환경 값을 읽는 유일한 모듈 |
| `assertTask` · `parseTask` | types-and-testing.md | 응답 좁히기 — 도메인 타입은 `requires`의 `Task` |
| `handlers` · `renderWithProviders` | types-and-testing.md | 테스트 하네스 |

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
| `http` | 프로젝트 | `http.get/post/patch/delete(path, init?)` — 봉투를 벗겨 데이터를 반환 | 응답 봉투 형태가 와이어 계약의 함수 |
| `ApiError` | 프로젝트 | `code`·`status`·`details`를 갖는 에러 클래스 | 에러 코드표가 와이어 계약의 함수 |
| `Page` | 프로젝트 | `Page<T> = { items: T[]; nextCursor: string \| null }` | 페이지네이션 모델이 와이어 계약의 함수 |
| `useTasksQuery` | 프로젝트 | 목록 쿼리 훅 | 페칭 계층이 이음매 소유 |
| `useAuth` | 라이브러리 | `{ isLoading, isAuthenticated }`를 반환하는 훅 | 인증 라이브러리 선택이 백엔드 축의 함수. 이 이음매는 `react-oidc-context`에서 가져온다 |

## 알려진 공백 (추출 시점에 승계, 수리하지 않음)

| 심볼 | 상태 |
| --- | --- |
| `FullPageSpinner` | routing.md에서 3회 소비되나 팩·이음매 어디에도 정의가 없다. **원본 `react-aws-frontend-guide`에도 없던 기존 결함**이며, 이번 재배치는 이를 드러냈을 뿐 만들지 않았다. 게이트가 REVIEW로 보고한다 |
