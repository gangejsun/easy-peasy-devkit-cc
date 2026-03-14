# Component Patterns

## Server vs Client Components

### Server Component (기본)

```typescript
// 기본적으로 모든 컴포넌트는 Server Component
// "use client" 선언이 없으면 서버에서 렌더링됨

import { createClient } from "@/lib/supabase/server";
import type { Post } from "@/types/post";

export default async function PostList() {
  const supabase = await createClient();
  const { data: posts } = await supabase
    .from("posts")
    .select("*")
    .eq("published", true);

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
      {posts?.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
    </div>
  );
}
```

### Client Component ("use client" 필요 시)

다음 경우에만 Client Component 사용:
- `useState`, `useEffect`, `useRef` 등 React 훅
- 이벤트 핸들러 (onClick, onChange 등)
- 브라우저 API (localStorage, window 등)
- 서드파티 클라이언트 라이브러리
- Zustand 스토어 접근

```typescript
"use client";

import { useState } from "react";
import { Button } from "@/components/ui/button";

interface CounterProps {
  initialCount?: number;
}

export default function Counter({ initialCount = 0 }: CounterProps) {
  const [count, setCount] = useState(initialCount);

  return (
    <div className="flex items-center gap-2">
      <Button onClick={() => setCount((c) => c - 1)}>-</Button>
      <span className="text-lg font-medium">{count}</span>
      <Button onClick={() => setCount((c) => c + 1)}>+</Button>
    </div>
  );
}
```

---

## Component Declaration

`function` 키워드를 선호한다 (프로젝트 컨벤션).

```typescript
// good: function 키워드
function UserAvatar({ user, size = "md" }: UserAvatarProps) {
  return (
    <Image
      src={user.avatarUrl ?? "/default-avatar.png"}
      alt={user.name}
      width={size === "md" ? 40 : 24}
      height={size === "md" ? 40 : 24}
      className="rounded-full"
    />
  );
}
export default UserAvatar;

// bad: arrow function + React.FC
const UserAvatar: React.FC<UserAvatarProps> = ({ user }) => {
  // ...
};
```

---

## Component Structure

권장 순서:

```typescript
"use client"; // 1. 클라이언트 지시어 (필요 시)

import { useState, useCallback } from "react"; // 2. React imports
import { Button } from "@/components/ui/button"; // 3. UI imports
import { cn } from "@/lib/utils";                // 4. Utility imports
import type { Post } from "@/types/post";         // 5. Type imports

// 6. Props 타입 정의
interface PostFormProps {
  initialData?: Post;
  onSubmit: (data: Post) => void;
  className?: string;
}

// 7. 컴포넌트 함수
function PostForm({ initialData, onSubmit, className }: PostFormProps) {
  // 8. State
  const [title, setTitle] = useState(initialData?.title ?? "");

  // 9. Handlers
  const handleSubmit = useCallback(/* ... */);

  // 10. Render
  return (
    <form className={cn("space-y-4", className)}>
      {/* ... */}
    </form>
  );
}

// 11. Export
export default PostForm;
```

---

## Composition Pattern: Server + Client

Server Component가 데이터를 패칭하고, Client Component에 props로 전달:

```typescript
// app/posts/[id]/page.tsx (Server Component)
import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import PostDetail from "@/components/post/PostDetail";
import LikeButton from "@/components/post/LikeButton";

export default async function PostPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: post } = await supabase
    .from("posts")
    .select("*, author:profiles(name, avatar_url)")
    .eq("id", id)
    .single();

  if (!post) notFound();

  return (
    <div>
      <PostDetail post={post} />        {/* Server Component */}
      <LikeButton postId={post.id} />   {/* Client Component */}
    </div>
  );
}
```

---

## Conditional Rendering

```typescript
// good: 조건부 렌더링
function StatusBadge({ status }: { status: string }) {
  const variants: Record<string, string> = {
    active: "bg-green-100 text-green-800",
    pending: "bg-yellow-100 text-yellow-800",
    closed: "bg-gray-100 text-gray-800",
  };

  return (
    <span className={cn("px-2 py-1 rounded-full text-xs font-medium", variants[status])}>
      {status}
    </span>
  );
}

// good: 리스트 렌더링
function PostGrid({ posts }: { posts: Post[] }) {
  if (posts.length === 0) {
    return (
      <div className="text-center text-muted-foreground py-12">
        게시글이 없습니다
      </div>
    );
  }

  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {posts.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
    </div>
  );
}
```

---

## Export Patterns

```typescript
// 페이지 컴포넌트: default export 필수
export default function PostPage() { /* ... */ }

// 일반 컴포넌트: default export 권장
export default function PostCard({ post }: PostCardProps) { /* ... */ }

// 여러 컴포넌트를 export하는 경우: named export
export function PostCardSkeleton() { /* ... */ }
export function PostCardCompact({ post }: PostCardProps) { /* ... */ }
```

---

## Anti-Patterns

```typescript
// bad: 불필요한 "use client"
"use client"; // 상태도, 이벤트도, 브라우저 API도 없음
export default function StaticContent() {
  return <div>Just static text</div>;
}

// bad: Server Component에서 useState
export default function Page() {
  const [count, setCount] = useState(0); // 에러!
}

// bad: any 타입 사용
function UserCard({ user }: { user: any }) { /* ... */ }

// bad: 상대 경로 import
import { Button } from "../../components/ui/button";

// bad: arrow function 컴포넌트
const UserCard = ({ user }: UserCardProps) => { /* ... */ };
```
