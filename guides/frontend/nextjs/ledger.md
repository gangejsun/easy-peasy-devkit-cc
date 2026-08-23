<!-- epcc-pack-ledger: frontend/nextjs v3.12.0 -->

# nextjs 팩 — 심볼 원장

게이트가 기계 대조하는 표다. `provides`는 이 팩이 정의하므로 이음매가 다시 정의하면
중복이고, `requires`는 이 팩이 소비하지만 정의하지 않으므로 이음매가 반드시 제공해야
한다. 라이브러리 API는 대상이 아니다.

## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 성격 |
| --- | --- | --- |
| `cn` · `Badge` | styling.md | 클래스 병합 유틸 · 변형 컴포넌트 |
| `PageHeader` · `PageSection` · `EmptyState` · `SearchInput` · `CollapsiblePanel` | component-patterns.md | 공통 UI·레이아웃 |
| `useUiStore` · `UiState` · `createUiStore` · `UiStoreProvider` | state-management.md | 클라이언트 전역 상태 |
| `useCartStore` · `CartItem` · `CartBadge` · `CartSummary` | state-management.md | 스토어 예제 |
| `useQueryParams` · `ProfileForm` · `DeleteTaskButton` | state-management.md | URL 상태 · 폼 |
| `useDebounce` · `SearchBar` · `TaskStats` · `LiveStatus` · `EditToggle` | performance.md | 성능 패턴 |
| `Task` · `TaskCard` | file-organization.md | 도메인 타입·컴포넌트 배치 예제 |
| `AppHeader` · `metadata` · `generateMetadata` | routing.md | 레이아웃 · 메타데이터 |

`Component`·`metadata`·`generateMetadata`·`middleware`는 프레임워크가 이름을 정하는
export다 — 파일마다 다른 본문을 갖는 것이 정상이므로 중복 판정에서 제외한다.

## requires — 이음매가 제공해야 한다

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 import 문에
이름이 등장하는지로 판정한다. `교차축`은 **상대 축 팩**이 정의하므로 이 가이드가 아니라
반대편 가이드에서 찾는다 — 조립 후에도 이 가이드 안에는 정의가 없는 것이 정상이다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `getCurrentUser` | 프로젝트 | `Promise<AuthUser \| null>` — 서버에서 검증된 사용자 | 인증 주체 확인 방식이 백엔드 축의 함수 |
| `AuthUser` | 프로젝트 | `{ id, email }` | 위와 같다 |
| `getTasks` | 프로젝트 | 목록 쿼리 함수 | 데이터 액세스 계층이 이음매 소유 |
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
