# State Management (Zustand v5 + 상태 배치 기준)

이 스택에는 상태를 둘 수 있는 자리가 넷이다. **잘못된 자리를 고르는 것**이 대부분의
상태 관리 문제의 원인이므로, 도구 사용법보다 배치 기준이 먼저다.

## 1. 결정 트리

```
서버가 소유한 데이터인가?            → TanStack Query (전역 스토어 금지)
URL로 공유·복원되어야 하는가?        → useSearchParams / 경로 파라미터
한 컴포넌트와 그 자식만 쓰는가?      → useState / useReducer
그 외 앱 전역에서 필요한가?          → Zustand 스토어
```

| 상태 | 자리 | 이유 |
| --- | --- | --- |
| 작업 목록, 사용자 프로필 | TanStack Query | 서버가 진실. 무효화·재요청이 필요 |
| 목록 필터·정렬·페이지 | URL | 공유·새로고침·뒤로가기가 공짜 |
| 폼 입력값 | 로컬 `useState` | 제출 전까지 아무도 볼 필요 없음 |
| 모달 열림/닫힘 | 로컬 또는 Zustand | 여러 화면에서 열 수 있으면 Zustand |
| 사이드바 접힘, 테마, 목록 밀도 | Zustand (+persist) | 앱 전역 UI 선호 |
| 액세스 토큰 | 인증 모듈 (메모리) | `auth-and-session.md` 참고 |

**서버 데이터를 Zustand에 넣지 않는다.** 넣는 순간 신선도·무효화·낙관적 롤백을 손으로
만들게 되고, 그건 이미 Query가 하는 일이다.

## 2. 스토어 작성 (`src/stores/uiStore.ts`)

```ts
import { create } from 'zustand';
import { persist, createJSONStorage } from 'zustand/middleware';

type UiState = {
  isSidebarOpen: boolean;
  density: 'comfortable' | 'compact';
  toggleSidebar: () => void;
  setDensity: (d: UiState['density']) => void;
  reset: () => void;
};

const initial = { isSidebarOpen: true, density: 'comfortable' as const };

export const useUiStore = create<UiState>()(
  persist(
    (set) => ({
      ...initial,
      toggleSidebar: () => set((s) => ({ isSidebarOpen: !s.isSidebarOpen })),
      setDensity: (density) => set({ density }),
      reset: () => set(initial),
    }),
    {
      name: 'ui-preferences',
      storage: createJSONStorage(() => localStorage),
      partialize: (s) => ({ isSidebarOpen: s.isSidebarOpen, density: s.density }), // 액션 제외
    },
  ),
);
```

- `create<T>()(...)` — 타입 인자를 주고 **한 번 더 호출**하는 커링 형태여야 TS 추론이 맞는다
- 액션을 상태와 같은 객체에 둔다 (별도 훅으로 빼지 않는다)
- `persist`에는 반드시 `partialize`를 써서 저장 대상을 명시한다. **토큰·개인정보·서버
  데이터는 절대 넣지 않는다** — localStorage는 XSS에 그대로 읽힌다
- 로그아웃에서 부를 `reset()`을 처음부터 만들어 둔다

## 3. 구독은 셀렉터로 좁힌다

```tsx
// ✅ 필요한 조각만 구독 — 다른 필드가 바뀌어도 리렌더되지 않는다
const isSidebarOpen = useUiStore((s) => s.isSidebarOpen);
const toggleSidebar = useUiStore((s) => s.toggleSidebar);

// ✅ 여러 값을 한 번에 — 객체를 새로 만들므로 useShallow가 필수
const { density, isSidebarOpen } = useUiStore(
  useShallow((s) => ({ density: s.density, isSidebarOpen: s.isSidebarOpen })),
);

// ❌ 스토어 전체 구독 — 어떤 필드가 바뀌어도 리렌더
const store = useUiStore();

// ❌ 셀렉터가 매번 새 객체를 반환하는데 useShallow가 없다 — 무한 리렌더
const { density } = useUiStore((s) => ({ density: s.density }));
```

## 4. React 밖에서 읽고 쓰기

렌더 트리 밖(HTTP 인터셉터, 이벤트 핸들러 유틸)에서는 `getState()`/`setState()`를 쓴다.
훅이 아니므로 구독하지 않고 **호출 시점의 값**을 읽는다.

```ts
// 401 처리에서 전역 스토어를 정리
useUiStore.getState().reset();

// 구독이 필요하면 subscribe (cleanup 반환)
const unsub = useUiStore.subscribe((s) => console.log(s.density));
```

렌더 중에는 절대 `getState()`를 쓰지 않는다 — 변경을 감지하지 못해 화면이 낡는다.

## 5. 스토어를 쪼개는 기준

- 도메인 단위로 나눈다: `uiStore`, `draftStore`, `notificationStore`
- 하나의 스토어가 20개 이상 필드를 갖거나 서로 무관한 관심사가 섞이면 분리한다
- 스토어끼리 import 하지 않는다. 조합이 필요하면 컴포넌트나 훅에서 두 스토어를 각각 읽는다
- 앱에 스토어가 하나뿐이고 필드가 5개 미만이면, 그건 Context로도 충분하다는 신호다

### 슬라이스로 나누기

하나의 스토어 안에서 관심사를 나눠야 할 때는 슬라이스 함수로 쪼갠 뒤 합친다.
파일이 갈라져도 스토어 인스턴스는 하나이므로 액션끼리 `get()`으로 참조할 수 있다.

```ts
// src/stores/slices/sidebar.ts
import type { StateCreator } from 'zustand';

export type SidebarSlice = {
  isSidebarOpen: boolean;
  toggleSidebar: () => void;
};

export const createSidebarSlice: StateCreator<SidebarSlice & FilterSlice, [], [], SidebarSlice> =
  (set) => ({
    isSidebarOpen: true,
    toggleSidebar: () => set((s) => ({ isSidebarOpen: !s.isSidebarOpen })),
  });
```

```ts
// src/stores/slices/filter.ts
export type FilterSlice = {
  savedFilters: string[];
  addFilter: (name: string) => void;
};

export const createFilterSlice: StateCreator<SidebarSlice & FilterSlice, [], [], FilterSlice> =
  (set, get) => ({
    savedFilters: [],
    addFilter: (name) => {
      if (get().savedFilters.includes(name)) return;    // 다른 슬라이스 상태도 읽을 수 있다
      set((s) => ({ savedFilters: [...s.savedFilters, name] }));
    },
  });
```

```ts
// src/stores/uiStore.ts — 합치는 곳 (§2의 단일 스토어가 커졌을 때 이 형태로 **옮긴다**.
// 같은 스토어의 다른 조립 방식이므로 두 정의를 동시에 두지 않는다)
export type UiState = SidebarSlice & FilterSlice & { reset: () => void };

export const useUiStore = create<UiState>()((set, get, store) => ({
  ...createSidebarSlice(set, get, store),
  ...createFilterSlice(set, get, store),
  // reset은 합치는 곳이 소유한다 — 슬라이스로 나눈 뒤에도 로그아웃 경로가 깨지지 않는다
  reset: () => set({ isSidebarOpen: true, savedFilters: [] }),
}));
```

`StateCreator`의 첫 타입 인자는 **합쳐진 전체 상태**, 마지막 인자는 이 슬라이스가
기여하는 부분이다. 이 둘을 같게 쓰면 `get()`에서 다른 슬라이스가 보이지 않는다.
어느 조립 방식이든 `reset()`은 반드시 존재해야 한다 — 로그아웃이 그것을 부른다(§6).

## 6. 로그아웃 시 초기화

세션이 끝나면 **서버 캐시와 클라이언트 스토어를 모두** 비운다. 하나만 비우면 다음
사용자가 이전 사용자의 화면 조각을 본다.

이 함수는 이름 그대로 **클라이언트 스토어만** 책임진다. 서버 캐시 폐기와 순서 통제는
로그아웃 절차가 소유한다 (`resources/auth-and-session.md` §6) — 두 곳에서 캐시를 비우면
어느 쪽이 실제로 도는지 추적이 어려워진다.

```ts
// src/stores/clearClientState.ts — 스토어를 추가하면 이 목록에도 추가한다
export function clearClientState() {
  useUiStore.getState().reset();     // 모든 스토어에 reset()이 있어야 하는 이유
}
```

## 오용 목록 ① — v4 → v5 관용구 대조표

| v4 습관 | v5 형태 |
| --- | --- |
| `import create from 'zustand'` | `import { create } from 'zustand'` — 기본 export가 제거됐다 |
| `useStore(selector, shallow)` (두 번째 인자) | `useStore(useShallow(selector))` — `equalityFn` 인자가 제거됐다 |
| `import { shallow } from 'zustand/shallow'` 직접 비교 | `import { useShallow } from 'zustand/react/shallow'` |
| 커스텀 비교 함수가 꼭 필요한 경우 | `createWithEqualityFn`을 `zustand/traditional`에서 import |
| `persist`의 `getStorage: () => localStorage` | `storage: createJSONStorage(() => localStorage)` |
| `create<T>((set) => ...)` | `create<T>()((set) => ...)` — 커링 형태 |

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| Zustand vs TanStack Query | 서버에 원본이 있으면 Query. 서버가 존재조차 모르는 값이면 Zustand |
| Zustand vs URL 상태 | 새로고침·링크 공유로 복원돼야 하면 URL. 세션 안에서만 의미 있으면 Zustand |
| Zustand vs Context | Context는 **주입**(테마·현재 사용자처럼 잘 안 변하는 값)에 강하고, 자주 바뀌는 값에는 하위 트리 전체 리렌더 비용이 붙는다. 자주 바뀌는 전역 값은 Zustand + 셀렉터 |
| `set({...})` vs `set((s) => ({...}))` | 이전 값에 의존하면 함수형. 그냥 덮어쓰면 객체형 |
| `set`의 병합 vs 교체 | Zustand의 `set`은 **얕은 병합**이다. 중첩 객체는 병합되지 않으므로 직접 펼쳐서 넣어야 한다 |
| `getState()` vs 훅 셀렉터 | 렌더 중에는 항상 훅. 렌더 밖(인터셉터·타이머·이벤트 유틸)에서만 `getState()` |
| `persist` 대상 vs 비대상 | UI 선호는 저장. 토큰·개인정보·서버 데이터는 저장 금지 |
| 액션을 스토어에 vs 컴포넌트에 | 여러 곳에서 같은 전이가 일어나면 스토어 액션으로. 한 화면에서만 쓰는 전이는 컴포넌트에 둔다 |
