# Loading & Error States

## Next.js 내장 패턴

Next.js App Router는 파일 컨벤션으로 로딩/에러 UI를 제공한다.

| 파일 | 역할 |
|------|------|
| `loading.tsx` | 로딩 중 표시할 UI (Suspense boundary 자동 생성) |
| `error.tsx` | 에러 발생 시 표시할 UI (Error boundary 자동 생성) |
| `not-found.tsx` | 404 페이지 |

---

## loading.tsx

```typescript
// app/posts/loading.tsx
export default function PostsLoading() {
  return (
    <div className="space-y-4">
      {Array.from({ length: 5 }).map((_, i) => (
        <div
          key={i}
          className="h-24 rounded-lg bg-muted animate-pulse"
        />
      ))}
    </div>
  );
}
```

### Skeleton 컴포넌트 패턴

```typescript
// components/post/PostCardSkeleton.tsx
import { Card, CardContent, CardHeader } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";

export default function PostCardSkeleton() {
  return (
    <Card>
      <CardHeader>
        <Skeleton className="h-6 w-3/4" />
      </CardHeader>
      <CardContent className="space-y-2">
        <Skeleton className="h-4 w-full" />
        <Skeleton className="h-4 w-2/3" />
      </CardContent>
    </Card>
  );
}

// components/post/PostListSkeleton.tsx
import PostCardSkeleton from "./PostCardSkeleton";

export default function PostListSkeleton() {
  return (
    <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
      {Array.from({ length: 6 }).map((_, i) => (
        <PostCardSkeleton key={i} />
      ))}
    </div>
  );
}
```

---

## error.tsx

```typescript
// app/posts/error.tsx
"use client"; // error.tsx는 반드시 Client Component

import { Button } from "@/components/ui/button";

interface ErrorProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function PostsError({ error, reset }: ErrorProps) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
      <div className="text-center space-y-2">
        <h2 className="text-xl font-semibold">문제가 발생했습니다</h2>
        <p className="text-muted-foreground">
          {error.message || "데이터를 불러오는 중 오류가 발생했습니다"}
        </p>
      </div>
      <Button onClick={reset} variant="outline">
        다시 시도
      </Button>
    </div>
  );
}
```

---

## not-found.tsx

```typescript
// app/posts/[id]/not-found.tsx
import Link from "next/link";
import { Button } from "@/components/ui/button";

export default function PostNotFound() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
      <h2 className="text-xl font-semibold">게시글을 찾을 수 없습니다</h2>
      <p className="text-muted-foreground">
        삭제되었거나 존재하지 않는 게시글입니다
      </p>
      <Button asChild variant="outline">
        <Link href="/posts">목록으로 돌아가기</Link>
      </Button>
    </div>
  );
}
```

### notFound() 호출

```typescript
// app/posts/[id]/page.tsx
import { notFound } from "next/navigation";

export default async function PostPage({ params }: PostPageProps) {
  const { id } = await params;
  const post = await getPost(id);

  if (!post) {
    notFound(); // not-found.tsx 렌더링
  }

  return <PostDetail post={post} />;
}
```

---

## Suspense Boundaries

수동으로 Suspense boundary를 추가하여 세밀한 로딩 제어:

```typescript
import { Suspense } from "react";

export default function DashboardPage() {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      {/* 메인 콘텐츠 - 독립적 로딩 */}
      <div className="lg:col-span-2">
        <Suspense fallback={<PostListSkeleton />}>
          <RecentPosts />
        </Suspense>
      </div>

      {/* 사이드바 - 독립적 로딩 */}
      <aside className="space-y-6">
        <Suspense fallback={<StatsSkeleton />}>
          <DashboardStats />
        </Suspense>
        <Suspense fallback={<NotificationSkeleton />}>
          <Notifications />
        </Suspense>
      </aside>
    </div>
  );
}
```

---

## Client Component 로딩 상태

### useTransition (Server Action)

```typescript
"use client";

import { useTransition } from "react";
import { Button } from "@/components/ui/button";
import { Loader2 } from "lucide-react";

function SubmitButton({ action }: { action: () => Promise<void> }) {
  const [isPending, startTransition] = useTransition();

  return (
    <Button
      onClick={() => startTransition(action)}
      disabled={isPending}
    >
      {isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
      {isPending ? "처리 중..." : "제출"}
    </Button>
  );
}
```

### useActionState (Form)

```typescript
"use client";

import { useActionState } from "react";
import { createPost } from "@/lib/actions/post";

function PostForm() {
  const [state, formAction, isPending] = useActionState(createPost, null);

  return (
    <form action={formAction}>
      <input name="title" required />
      {state?.error && (
        <p className="text-sm text-destructive mt-1">{state.error}</p>
      )}
      {state?.fieldErrors?.title && (
        <p className="text-sm text-destructive mt-1">
          {state.fieldErrors.title[0]}
        </p>
      )}
      <Button type="submit" disabled={isPending}>
        {isPending ? "게시 중..." : "게시"}
      </Button>
    </form>
  );
}
```

---

## Empty State

```typescript
function EmptyState({
  title,
  description,
  action,
}: {
  title: string;
  description: string;
  action?: React.ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center py-12 text-center">
      <h3 className="text-lg font-semibold">{title}</h3>
      <p className="text-muted-foreground mt-1">{description}</p>
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

// 사용
<EmptyState
  title="게시글이 없습니다"
  description="첫 번째 게시글을 작성해보세요"
  action={
    <Button asChild>
      <Link href="/posts/new">게시글 작성</Link>
    </Button>
  }
/>
```

---

## Anti-Patterns

```typescript
// bad: 조기 반환으로 로딩 표시 (레이아웃 시프트 발생)
"use client";
function PostList() {
  const [loading, setLoading] = useState(true);
  if (loading) return <Spinner />;  // 전체 레이아웃이 사라짐
  return <div>...</div>;
}
// good: loading.tsx 또는 Suspense 사용

// bad: 에러 무시
const { data } = await supabase.from("posts").select("*");
// data가 null일 수 있음!
// good: 에러 처리
const { data, error } = await supabase.from("posts").select("*");
if (error) throw new Error("게시글을 불러올 수 없습니다");
```
