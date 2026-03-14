---
name: nextjs-frontend-guide
description: |
  [Preset: nextjs-supabase] Next.js App Router frontend development guide. Covers Server/Client Component patterns, Tailwind CSS v4 + shadcn/ui styling, App Router routing, Zustand state management, performance optimization, and TypeScript standards. Use when creating or modifying components, pages, layouts, styling, data fetching, routing, state management, or any frontend code.
  Use ONLY when the active preset matches.
---

# Frontend Development Guidelines

Next.js App Router 기반 프론트엔드 개발 가이드. Server/Client Component, Tailwind + shadcn/ui 스타일링, Zustand 상태 관리 패턴을 다룬다.

## Quick Start

### New Component Checklist

- [ ] Server Component 기본 (상태/이벤트 필요 시만 `"use client"`)
- [ ] `function` 키워드로 컴포넌트 선언
- [ ] Props 타입을 같은 파일에 정의
- [ ] Tailwind 클래스 + `cn()` 유틸로 스타일링
- [ ] shadcn/ui 컴포넌트 활용 (가능한 경우)
- [ ] `@/` 경로 alias 사용
- [ ] `any` 타입 금지
- [ ] default export

### New Page Checklist

- [ ] `app/` 디렉토리에 `page.tsx` 생성
- [ ] Server Component로 데이터 패칭
- [ ] `loading.tsx`로 로딩 UI 제공
- [ ] `error.tsx`로 에러 UI 제공
- [ ] 적절한 메타데이터 설정
- [ ] 레이아웃 필요 시 `layout.tsx` 추가

---

## Architecture Overview

```
Server (Node.js)
├── Server Components (default)    -- 데이터 패칭, SEO, 번들 0
│   └── async function Page()      -- DB 직접 접근 가능
├── Server Actions ("use server")  -- 데이터 변경
└── Layouts/Templates              -- 공유 UI

Client (Browser)
├── Client Components ("use client")  -- 상태, 이벤트, 브라우저 API
├── Zustand stores                    -- 글로벌 클라이언트 상태
└── Custom hooks                      -- 재사용 가능 로직
```

---

## Directory Structure

```
src/
├── app/                     # Next.js App Router
│   ├── (auth)/              # 인증 관련 페이지
│   ├── (main)/              # 메인 레이아웃 페이지
│   │   ├── layout.tsx
│   │   ├── deals/
│   │   │   ├── page.tsx
│   │   │   ├── loading.tsx
│   │   │   └── [id]/
│   │   │       └── page.tsx
│   │   └── my/
│   │       └── page.tsx
│   ├── layout.tsx           # 루트 레이아웃
│   └── page.tsx             # 홈페이지
├── components/
│   ├── ui/                  # shadcn/ui (자동 생성)
│   ├── deal/                # 딜 관련 컴포넌트
│   ├── user/                # 유저 관련 컴포넌트
│   ├── payment/             # 결제 관련 컴포넌트
│   └── layout/              # Header, Footer 등
├── hooks/                   # 커스텀 훅
├── stores/                  # Zustand 스토어
├── types/                   # 공유 타입
└── constants/               # 상수
```

---

## Core Principles (8 Key Rules)

### 1. Server Component 기본, Client는 필요 시만

```typescript
// Server Component (기본) - "use client" 없음
export default async function PostList() {
  const supabase = await createClient();
  const { data: posts } = await supabase.from("posts").select("*");
  return <div>{/* render posts */}</div>;
}

// Client Component - 상태/이벤트 필요 시에만
"use client";
export default function LikeButton({ postId }: LikeButtonProps) {
  const [liked, setLiked] = useState(false);
  // ...
}
```

### 2. `function` 키워드로 컴포넌트 선언

```typescript
// good
function UserCard({ user }: UserCardProps) {
  return <div>{user.name}</div>;
}
export default UserCard;

// bad
const UserCard: React.FC<UserCardProps> = ({ user }) => {
  return <div>{user.name}</div>;
};
```

### 3. Tailwind + `cn()` 유틸로 스타일링

```typescript
import { cn } from "@/lib/utils";

function Button({ className, variant, ...props }: ButtonProps) {
  return (
    <button
      className={cn(
        "px-4 py-2 rounded-md font-medium",
        variant === "primary" && "bg-primary text-primary-foreground",
        variant === "outline" && "border border-input",
        className
      )}
      {...props}
    />
  );
}
```

### 4. shadcn/ui 컴포넌트 활용

```typescript
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
```

### 5. `@/` 경로 alias 필수

```typescript
// good
import { cn } from "@/lib/utils";
import { Button } from "@/components/ui/button";
import type { User } from "@/types/user";

// bad
import { cn } from "../../lib/utils";
import { Button } from "../ui/button";
```

### 6. Zustand로 클라이언트 상태 관리

```typescript
// stores/useAuthStore.ts
import { create } from "zustand";

interface AuthState {
  user: User | null;
  setUser: (user: User | null) => void;
}

export const useAuthStore = create<AuthState>((set) => ({
  user: null,
  setUser: (user) => set({ user }),
}));
```

### 7. loading.tsx / error.tsx로 상태 처리

```typescript
// app/posts/loading.tsx
export default function Loading() {
  return <PostListSkeleton />;
}

// app/posts/error.tsx
"use client";
export default function Error({ error, reset }: { error: Error; reset: () => void }) {
  return <ErrorDisplay error={error} onRetry={reset} />;
}
```

### 8. Props 타입은 같은 파일에 정의

```typescript
interface PostCardProps {
  post: Post;
  onLike?: (id: string) => void;
  className?: string;
}

function PostCard({ post, onLike, className }: PostCardProps) {
  // ...
}
```

---

## Common Imports

```typescript
// Next.js
import Link from "next/link";
import Image from "next/image";
import { redirect } from "next/navigation";
import { Suspense } from "react";

// Supabase (Server)
import { createClient } from "@/lib/supabase/server";

// Supabase (Client)
import { createClient } from "@/lib/supabase/client";

// Utils
import { cn } from "@/lib/utils";

// shadcn/ui
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";

// Zustand
import { useAuthStore } from "@/stores/useAuthStore";

// Types
import type { Post } from "@/types/post";
```

---

## Modern Component Template

```typescript
// components/post/PostCard.tsx
import Link from "next/link";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import type { Post } from "@/types/post";

interface PostCardProps {
  post: Post;
  className?: string;
}

export default function PostCard({ post, className }: PostCardProps) {
  return (
    <Card className={cn("hover:shadow-md transition-shadow", className)}>
      <CardHeader>
        <div className="flex items-center justify-between">
          <CardTitle className="text-lg">{post.title}</CardTitle>
          {post.published && <Badge>공개</Badge>}
        </div>
      </CardHeader>
      <CardContent>
        <p className="text-muted-foreground line-clamp-2">{post.content}</p>
        <Link
          href={`/posts/${post.id}`}
          className="text-primary text-sm mt-2 inline-block"
        >
          자세히 보기
        </Link>
      </CardContent>
    </Card>
  );
}
```

---

## Navigation Guide

| Need to... | Read this |
|------------|-----------|
| Create components | [component-patterns.md](resources/component-patterns.md) |
| Fetch data | [data-fetching.md](resources/data-fetching.md) |
| Organize files | [file-organization.md](resources/file-organization.md) |
| Style components | [styling-guide.md](resources/styling-guide.md) |
| Set up routing | [routing-guide.md](resources/routing-guide.md) |
| Handle loading/errors | [loading-and-error-states.md](resources/loading-and-error-states.md) |
| Manage state | [state-management.md](resources/state-management.md) |
| Optimize performance | [performance.md](resources/performance.md) |
| TypeScript standards | [typescript-standards.md](resources/typescript-standards.md) |
| See full examples | [complete-examples.md](resources/complete-examples.md) |
