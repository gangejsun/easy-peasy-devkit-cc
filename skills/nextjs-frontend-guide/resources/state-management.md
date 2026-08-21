# State Management

로컬/전역 구분 기준, Zustand 구독 패턴, 폼 상태 경계(useActionState vs RHF).

## 1. 상태 분류 — 어디에 둘 것인가

| 상태 종류 | 도구 |
| --- | --- |
| 단일 컴포넌트의 UI 상태 (열림/닫힘, 입력값) | `useState` |
| 형제 몇 개가 공유하는 좁은 범위 상태 | 상위 컴포넌트로 끌어올리기 (lifting) |
| URL로 공유·북마크되어야 하는 상태 (필터·탭·페이지네이션) | `searchParams` |
| 여러 트리에서 쓰는 전역 클라이언트 상태 (사이드바·테마·장바구니) | Zustand |
| 서버 데이터 (DB의 내용) | Server Component 페칭 — **스토어 복제 금지** |
| 폼 제출 진행/결과/낙관적 값 | `useActionState` / `useOptimistic` |

원칙: **아래로 내려갈수록 비용이 크다.** `useState`로 충분한 상태를 Zustand에 올리지 않는다.
전역 스토어 도입은 "3개 이상의 무관한 트리가 같은 상태를 구독"할 때만 정당하다.

## 2. Zustand 기본형

```ts
// stores/cart-store.ts
import { create } from 'zustand'

export interface CartItem {
  id: string
  name: string
  qty: number
}

interface CartState {
  items: CartItem[]
  add: (item: CartItem) => void
  remove: (id: string) => void
  clear: () => void
}

export const useCartStore = create<CartState>()((set) => ({
  items: [],
  add: (item) => set((s) => ({ items: [...s.items, item] })),
  remove: (id) => set((s) => ({ items: s.items.filter((i) => i.id !== id) })),
  clear: () => set({ items: [] }),
}))
```

- 상태와 그 상태를 바꾸는 액션을 **같은 스토어 안에** 정의한다 — 외부에서 `setState` 직접 호출 금지
- `create<State>()(…)` 커리드 형태를 쓴다 (TypeScript 추론)

## 3. 구독은 selector로 — 전체 구독 금지

```tsx
'use client'

import { useShallow } from 'zustand/react/shallow'
import { useCartStore } from '@/stores/cart-store'

// Good: 필요한 조각만 — 그 조각이 바뀔 때만 리렌더
const items = useCartStore((s) => s.items)
const add = useCartStore((s) => s.add)

// Good: 여러 조각을 객체로 뽑을 때는 useShallow (매번 새 객체 → 무한 리렌더 방지)
const { add, remove } = useCartStore(useShallow((s) => ({ add: s.add, remove: s.remove })))

// Bad: 스토어 전체 구독 — 모든 변경에 리렌더
const store = useCartStore((s) => s)
```

- 파생값은 스토어에 저장하지 말고 selector에서 계산한다:
  `useCartStore((s) => s.items.length)`

## 4. App Router 주의 — 스토어 생성 위치

모듈 최상위 `create()` 스토어는 서버에서 **모든 요청이 공유**한다.

- **전역 `create()` 허용**: 서버 렌더 결과에 영향을 주지 않는 순수 클라이언트 UI 상태
  (사이드바 열림, 클라이언트 전용 토글). 초기값이 사용자·요청과 무관할 때만
- **Provider 패턴 필수**: 요청별 초기값(사용자 데이터 등)으로 시작하는 스토어

```ts
// stores/ui-store.ts — vanilla 스토어 팩토리
import { createStore } from 'zustand/vanilla'

export interface UiState {
  sidebarOpen: boolean
  toggleSidebar: () => void
}

export const createUiStore = (init?: Partial<Pick<UiState, 'sidebarOpen'>>) =>
  createStore<UiState>()((set) => ({
    sidebarOpen: init?.sidebarOpen ?? false,
    toggleSidebar: () => set((s) => ({ sidebarOpen: !s.sidebarOpen })),
  }))
```

```tsx
// stores/ui-store-provider.tsx — 요청(트리)마다 스토어 1개 생성
'use client'

import { createContext, useContext, useRef } from 'react'
import { useStore } from 'zustand'
import { createUiStore, type UiState } from './ui-store'

type UiStoreApi = ReturnType<typeof createUiStore>

const UiStoreContext = createContext<UiStoreApi | undefined>(undefined)

export function UiStoreProvider({ children }: { children: React.ReactNode }) {
  const storeRef = useRef<UiStoreApi | null>(null)
  if (!storeRef.current) storeRef.current = createUiStore()
  return <UiStoreContext.Provider value={storeRef.current}>{children}</UiStoreContext.Provider>
}

export function useUiStore<T>(selector: (state: UiState) => T): T {
  const store = useContext(UiStoreContext)
  if (!store) throw new Error('useUiStore must be used within UiStoreProvider')
  return useStore(store, selector)
}
```

Provider는 루트 `layout.tsx`(또는 필요한 세그먼트의 layout)에서 감싼다.
Provider 자체가 클라이언트 컴포넌트여도 `children`으로 받은 서버 컴포넌트는 서버에 남는다.

## 5. persist — localStorage 유지가 필요할 때

```ts
import { create } from 'zustand'
import { persist } from 'zustand/middleware'

export const useCartStore = create<CartState>()(
  persist(
    (set) => ({
      items: [],
      add: (item) => set((s) => ({ items: [...s.items, item] })),
      remove: (id) => set((s) => ({ items: s.items.filter((i) => i.id !== id) })),
      clear: () => set({ items: [] }),
    }),
    { name: 'cart-storage' }              // localStorage 키
  )
)
```

**Hydration 주의**: 서버 첫 렌더는 초기값, 브라우저는 복원값 — 불일치가 생긴다.
persist된 값에 의존하는 UI는 마운트 확인 후 렌더한다.

```tsx
const [mounted, setMounted] = useState(false)
useEffect(() => setMounted(true), [])
if (!mounted) return <Skeleton className="h-6 w-10" />   // 서버와 동일한 자리표시자
```

## 6. 폼 상태 — 기본은 useActionState, 예외만 RHF+Zod

폼은 **`useActionState` + Server Action이 기본**이다 (resources/data-fetching.md의 변이 절).
React Hook Form + `zodResolver`는 **복잡한 클라이언트 측 실시간 검증**이 필요할 때만
도입한다 — 필드 간 의존 검증, 입력 즉시 피드백, 동적 필드 배열 같은 경우.

```tsx
'use client'

import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { updateProfile } from '../actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

const profileSchema = z.object({
  name: z.string().min(1, '이름은 필수입니다'),
  email: z.email('유효한 이메일을 입력하세요'),      // Zod v4: z.email()
  bio: z.string().max(500).optional(),
})

type ProfileFormData = z.infer<typeof profileSchema>

export function ProfileForm({ defaultValues }: { defaultValues?: ProfileFormData }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ProfileFormData>({ resolver: zodResolver(profileSchema), defaultValues })

  return (
    <form onSubmit={handleSubmit((data) => updateProfile(data))} className="space-y-4">
      <Input {...register('name')} placeholder="이름" />
      {errors.name && <p className="text-sm text-destructive">{errors.name.message}</p>}
      <Input type="email" {...register('email')} placeholder="이메일" />
      {errors.email && <p className="text-sm text-destructive">{errors.email.message}</p>}
      <Button type="submit" disabled={isSubmitting}>저장</Button>
    </form>
  )
}
```

- 제출 자체는 여전히 Server Action으로 — RHF는 클라이언트 검증·필드 상태만 담당
  (서버 측 재검증은 backend-guide 관할)
- **폼 스키마에 `.default()`를 쓰지 않는다** — zodResolver의 입력/출력 타입이 어긋나
  `useForm` 제네릭과 마찰이 생긴다. 기본값은 `defaultValues`로 준다

## 7. 안티패턴

- **서버 데이터 복제**: 쿼리 결과를 스토어에 넣으면 stale 사본이 생긴다.
  서버 데이터는 props로 흐르고, 갱신은 `revalidatePath`/`router.refresh()`가 담당한다
- **스토어 안에서 페칭**: 스토어 액션에서 데이터를 fetch해 상태에 담는 패턴 금지 —
  조회는 Server Component의 일이다 (resources/data-fetching.md)
- **전체 구독**: `useCartStore((s) => s)` — selector 없는 구독은 모든 변경에 리렌더
- **파생값 저장**: `totalCount` 같은 계산값을 상태로 두지 않는다 — selector로 계산
- **스토어 남발**: 도메인마다 스토어를 쪼개되, 화면 하나를 위한 스토어는 만들지 않는다
