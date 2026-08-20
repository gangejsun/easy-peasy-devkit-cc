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

---

## Shared Layout Components (반복 UI 추출)

같은 종류의 화면(상세/목록/설정 등)에 **상단 헤더(뒤로가기 + 타이틀)·하단 액션바·빈 상태 등 반복 UI**가 등장하면 인라인 복제 금지. 즉시 공통 컴포넌트로 추출한다.

### Rule of Three (3회 반복 시 즉시 추출)

신규 페이지 작성 시 다음을 자가 점검한다:

1. 동일 형태의 헤더/푸터/카드를 **2개 이상 페이지**에서 작성하고 있는가? → 다음 페이지에서 동일 형태가 또 등장하면 **즉시 추출**
2. 이미 비슷한 컴포넌트가 `components/layout/`, `components/common/`에 존재하는가? → 새로 만들기 전에 grep으로 확인

### 표준 위치

| 컴포넌트 종류        | 경로                 | 예시                                                           |
| -------------------- | -------------------- | -------------------------------------------------------------- |
| 페이지 공통 레이아웃 | `components/layout/` | `PageHeader`, `PageContainer`, `BackButton`, `BottomActionBar` |
| 도메인 무관 재사용   | `components/common/` | `EmptyState`, `ErrorBoundary`, `LoadingSpinner`                |
| shadcn primitive     | `components/ui/`     | shadcn add로 생성된 원자 컴포넌트만                            |

### PageHeader 예시 (인라인 중복 → 공통화)

```typescript
// components/layout/page-header.tsx
import { ChevronLeft } from "lucide-react";
import Link from "next/link";

interface PageHeaderProps {
  title: string;
  backHref?: string;
  rightSlot?: React.ReactNode;
}

export function PageHeader({ title, backHref, rightSlot }: PageHeaderProps) {
  return (
    <header className="sticky top-0 z-10 flex h-14 items-center justify-between border-b bg-background px-4">
      {backHref ? (
        <Link href={backHref} aria-label="뒤로가기">
          <ChevronLeft className="h-6 w-6" />
        </Link>
      ) : <span className="w-6" />}
      <h1 className="text-base font-semibold">{title}</h1>
      <div className="w-6">{rightSlot}</div>
    </header>
  );
}

// 사용처: 상세/설정/프로필 등 모든 sub 페이지가 동일 인터페이스 공유
// app/posts/[id]/page.tsx
<PageHeader title="게시글" backHref="/posts" />
// app/settings/page.tsx
<PageHeader title="설정" backHref="/" />
```

### 디자인 토큰 일관성

헤더 높이·타이틀 폰트 크기·여백은 페이지마다 임의 지정 금지. `tailwind.config` 또는 `globals.css`의 토큰(`h-14`, `text-base font-semibold` 등)을 PageHeader에 **한 곳에서만** 정의하고, 페이지는 props로만 제어한다.

추가 정의가 필요한 토큰(예: 모바일 헤더 전용 높이)은 `ui-ux-design` 스킬로 생성된 디자인 시스템 문서(`dev/docs/design/`)와 정합해야 한다.

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

// bad: 같은 헤더(뒤로가기 + 타이틀)를 페이지마다 인라인 복제
export default function PostDetail() {
  return (
    <>
      <header className="sticky top-0 ..."> {/* 다른 페이지에도 동일 구조 */}
        <Link href="/posts"><ChevronLeft /></Link>
        <h1 className="text-base font-semibold">게시글</h1>
      </header>
      {/* ... */}
    </>
  );
}
// good: components/layout/page-header.tsx로 추출 → <PageHeader title="게시글" backHref="/posts" />

// bad: 헤더 높이·폰트를 페이지마다 다르게 (h-12 / h-14 / h-16 혼재, text-lg / text-base 혼재)
// good: PageHeader 한 곳에서 토큰 정의, 페이지는 props만 전달
```
