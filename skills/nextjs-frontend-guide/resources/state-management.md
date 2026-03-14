# State Management

## State 종류 구분

| 종류 | 관리 방법 | 예시 |
|------|----------|------|
| **Server State** | Server Component + Supabase | DB 데이터, API 응답 |
| **URL State** | searchParams, pathname | 필터, 페이지네이션, 검색어 |
| **Form State** | React Hook Form / useActionState | 폼 입력값, 검증 에러 |
| **UI State** | useState | 모달 열림/닫힘, 토글 |
| **Global Client State** | Zustand | 로그인 사용자, 장바구니, 테마 |

**원칙**: Server State는 서버에서 관리, 클라이언트 상태는 최소화.

---

## Zustand

### 기본 스토어

```typescript
// stores/useAuthStore.ts
import { create } from "zustand";
import type { User } from "@/types/user";

interface AuthState {
  user: User | null;
  isLoading: boolean;
  setUser: (user: User | null) => void;
  setLoading: (loading: boolean) => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  isLoading: true,
  setUser: (user) => set({ user }),
  setLoading: (isLoading) => set({ isLoading }),
}));
```

### 컴포넌트에서 사용

```typescript
"use client";

import { useAuthStore } from "@/stores/useAuthStore";

function UserGreeting() {
  const user = useAuthStore((state) => state.user);

  if (!user) return null;
  return <span>안녕하세요, {user.name}님</span>;
}
```

### 선택적 구독 (성능 최적화)

```typescript
// good: 필요한 상태만 구독
const user = useAuthStore((state) => state.user);
const setUser = useAuthStore((state) => state.setUser);

// bad: 전체 스토어 구독 (불필요한 리렌더링)
const { user, isLoading, setUser } = useAuthStore();
```

---

## Zustand 패턴

### Computed Values

```typescript
// stores/useCartStore.ts
import { create } from "zustand";

interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

interface CartState {
  items: CartItem[];
  addItem: (item: Omit<CartItem, "quantity">) => void;
  removeItem: (id: string) => void;
  updateQuantity: (id: string, quantity: number) => void;
  clearCart: () => void;
  // Computed (getter처럼 사용)
  getTotalPrice: () => number;
  getTotalItems: () => number;
}

export const useCartStore = create<CartState>((set, get) => ({
  items: [],

  addItem: (item) =>
    set((state) => {
      const existing = state.items.find((i) => i.id === item.id);
      if (existing) {
        return {
          items: state.items.map((i) =>
            i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i
          ),
        };
      }
      return { items: [...state.items, { ...item, quantity: 1 }] };
    }),

  removeItem: (id) =>
    set((state) => ({
      items: state.items.filter((i) => i.id !== id),
    })),

  updateQuantity: (id, quantity) =>
    set((state) => ({
      items: state.items.map((i) =>
        i.id === id ? { ...i, quantity } : i
      ),
    })),

  clearCart: () => set({ items: [] }),

  getTotalPrice: () =>
    get().items.reduce((sum, item) => sum + item.price * item.quantity, 0),

  getTotalItems: () =>
    get().items.reduce((sum, item) => sum + item.quantity, 0),
}));
```

### Persist (localStorage)

```typescript
import { create } from "zustand";
import { persist } from "zustand/middleware";

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({
      theme: "system" as "light" | "dark" | "system",
      setTheme: (theme) => set({ theme }),
    }),
    {
      name: "theme-storage", // localStorage 키
    }
  )
);
```

---

## URL State (searchParams)

필터, 정렬, 페이지네이션은 URL에 저장하면 공유 가능하고 브라우저 뒤로가기가 동작.

### Server Component에서 읽기

```typescript
// app/posts/page.tsx
export default async function PostsPage({
  searchParams,
}: {
  searchParams: Promise<{ page?: string; sort?: string }>;
}) {
  const { page = "1", sort = "newest" } = await searchParams;
  // 서버에서 필터링된 데이터 패칭
}
```

### Client Component에서 조작

```typescript
"use client";

import { useRouter, useSearchParams, usePathname } from "next/navigation";
import { useCallback } from "react";

function useQueryParams() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();

  const setQueryParam = useCallback(
    (key: string, value: string | null) => {
      const params = new URLSearchParams(searchParams.toString());
      if (value === null) {
        params.delete(key);
      } else {
        params.set(key, value);
      }
      router.push(`${pathname}?${params.toString()}`);
    },
    [router, pathname, searchParams]
  );

  return { searchParams, setQueryParam };
}
```

---

## Form State

### React Hook Form + Zod

```typescript
"use client";

import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";

const profileSchema = z.object({
  name: z.string().min(1, "이름은 필수입니다"),
  email: z.string().email("유효한 이메일을 입력하세요"),
  bio: z.string().max(500).optional(),
});

type ProfileFormData = z.infer<typeof profileSchema>;

function ProfileForm({ defaultValues }: { defaultValues?: ProfileFormData }) {
  const {
    register,
    handleSubmit,
    formState: { errors, isSubmitting },
  } = useForm<ProfileFormData>({
    resolver: zodResolver(profileSchema),
    defaultValues,
  });

  async function onSubmit(data: ProfileFormData) {
    // Server Action 또는 API 호출
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
      <div>
        <Label htmlFor="name">이름</Label>
        <Input id="name" {...register("name")} />
        {errors.name && (
          <p className="text-sm text-destructive mt-1">{errors.name.message}</p>
        )}
      </div>
      <div>
        <Label htmlFor="email">이메일</Label>
        <Input id="email" type="email" {...register("email")} />
        {errors.email && (
          <p className="text-sm text-destructive mt-1">{errors.email.message}</p>
        )}
      </div>
      <Button type="submit" disabled={isSubmitting}>
        {isSubmitting ? "저장 중..." : "저장"}
      </Button>
    </form>
  );
}
```

---

## State 선택 가이드

| 질문 | Yes → |
|------|-------|
| DB에서 가져온 데이터? | Server Component에서 직접 패칭 |
| URL에 반영되어야 할 데이터? (필터, 페이지) | searchParams |
| 폼 입력값과 검증? | React Hook Form / useActionState |
| 모달, 토글 등 로컬 UI 상태? | useState |
| 여러 컴포넌트에서 공유하는 클라이언트 상태? | Zustand |
| 브라우저 새로고침 후에도 유지? | Zustand + persist |

---

## Anti-Patterns

```typescript
// bad: Server State를 Zustand에 저장
const usePostStore = create((set) => ({
  posts: [],
  fetchPosts: async () => {
    const res = await fetch("/api/posts");
    set({ posts: await res.json() });
  },
}));
// good: Server Component에서 직접 패칭

// bad: URL에 저장해야 할 상태를 useState로 관리
const [page, setPage] = useState(1);
// good: searchParams 사용 (공유 가능, 뒤로가기 동작)

// bad: 전역 스토어를 남용 (모든 상태를 Zustand에)
// good: Zustand는 정말 전역이 필요한 클라이언트 상태에만 사용
```
