# Complete Examples

## Example 1: Server Component Page with Data Fetching

```typescript
// app/(main)/posts/page.tsx
import { createClient } from "@/lib/supabase/server";
import PostCard from "@/components/post/PostCard";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "게시글 목록",
  description: "최신 게시글을 확인하세요",
};

interface PostsPageProps {
  searchParams: Promise<{
    page?: string;
    q?: string;
  }>;
}

export default async function PostsPage({ searchParams }: PostsPageProps) {
  const { page = "1", q } = await searchParams;
  const supabase = await createClient();
  const offset = (Number(page) - 1) * 10;

  let query = supabase
    .from("posts")
    .select("id, title, content, created_at, author:profiles(name, avatar_url)", {
      count: "exact",
    })
    .eq("published", true);

  if (q) {
    query = query.ilike("title", `%${q}%`);
  }

  const { data: posts, count } = await query
    .order("created_at", { ascending: false })
    .range(offset, offset + 9);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">게시글</h1>
        <span className="text-muted-foreground">총 {count ?? 0}개</span>
      </div>

      {posts && posts.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {posts.map((post) => (
            <PostCard key={post.id} post={post} />
          ))}
        </div>
      ) : (
        <div className="text-center py-12 text-muted-foreground">
          게시글이 없습니다
        </div>
      )}
    </div>
  );
}
```

---

## Example 2: Reusable Component with Tailwind + shadcn/ui

```typescript
// components/post/PostCard.tsx
import Link from "next/link";
import Image from "next/image";
import { cn } from "@/lib/utils";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import type { Post } from "@/types/post";

interface PostCardProps {
  post: Post & {
    author?: { name: string; avatar_url: string | null };
  };
  variant?: "default" | "compact";
  className?: string;
}

export default function PostCard({
  post,
  variant = "default",
  className,
}: PostCardProps) {
  return (
    <Link href={`/posts/${post.id}`}>
      <Card
        className={cn(
          "hover:shadow-md transition-shadow cursor-pointer",
          variant === "compact" && "border-0 shadow-none",
          className
        )}
      >
        <CardHeader className="pb-2">
          <div className="flex items-center justify-between">
            <CardTitle className="text-lg line-clamp-1">
              {post.title}
            </CardTitle>
            {post.published && (
              <Badge variant="secondary" className="text-xs">
                공개
              </Badge>
            )}
          </div>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground text-sm line-clamp-2">
            {post.content}
          </p>
          {post.author && (
            <div className="flex items-center gap-2 mt-3">
              {post.author.avatar_url && (
                <Image
                  src={post.author.avatar_url}
                  alt={post.author.name}
                  width={24}
                  height={24}
                  className="rounded-full"
                />
              )}
              <span className="text-xs text-muted-foreground">
                {post.author.name}
              </span>
            </div>
          )}
        </CardContent>
      </Card>
    </Link>
  );
}
```

---

## Example 3: Client Component with State + Server Action

```typescript
// components/post/LikeButton.tsx
"use client";

import { useState, useTransition } from "react";
import { Heart } from "lucide-react";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { toggleLike } from "@/lib/actions/post";

interface LikeButtonProps {
  postId: string;
  initialLiked: boolean;
  initialCount: number;
}

export default function LikeButton({
  postId,
  initialLiked,
  initialCount,
}: LikeButtonProps) {
  const [liked, setLiked] = useState(initialLiked);
  const [count, setCount] = useState(initialCount);
  const [isPending, startTransition] = useTransition();

  function handleToggle() {
    // Optimistic update
    setLiked(!liked);
    setCount(liked ? count - 1 : count + 1);

    startTransition(async () => {
      const result = await toggleLike(postId);
      if (!result.success) {
        // Rollback
        setLiked(liked);
        setCount(count);
      }
    });
  }

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={handleToggle}
      disabled={isPending}
      className="gap-1"
    >
      <Heart
        className={cn(
          "h-4 w-4",
          liked && "fill-red-500 text-red-500"
        )}
      />
      <span className="text-xs">{count}</span>
    </Button>
  );
}
```

---

## Example 4: Layout with Header Navigation

```typescript
// app/(main)/layout.tsx
import Header from "@/components/layout/Header";

export default function MainLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen flex-col">
      <Header />
      <main className="flex-1">{children}</main>
    </div>
  );
}
```

```typescript
// components/layout/Header.tsx
import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { Button } from "@/components/ui/button";
import UserMenu from "@/components/layout/UserMenu";

export default async function Header() {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();

  return (
    <header className="sticky top-0 z-50 border-b bg-background/95 backdrop-blur">
      <div className="container mx-auto flex h-14 items-center justify-between px-4">
        <Link href="/" className="text-lg font-bold">
          EasyPeasyClaudeCodeDevkit
        </Link>

        <nav className="hidden md:flex items-center gap-6">
          <Link
            href="/deals"
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            딜 목록
          </Link>
          <Link
            href="/search"
            className="text-sm text-muted-foreground hover:text-foreground transition-colors"
          >
            검색
          </Link>
        </nav>

        <div className="flex items-center gap-2">
          {user ? (
            <UserMenu user={user} />
          ) : (
            <Button asChild size="sm">
              <Link href="/login">로그인</Link>
            </Button>
          )}
        </div>
      </div>
    </header>
  );
}
```

---

## Example 5: Form with React Hook Form + Zod + Server Action

```typescript
// components/post/CreatePostForm.tsx
"use client";

import { useForm } from "react-hook-form";
import { zodResolver } from "@hookform/resolvers/zod";
import { z } from "zod";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { createPost } from "@/lib/actions/post";

const schema = z.object({
  title: z.string().min(1, "제목을 입력하세요").max(200),
  content: z.string().min(1, "내용을 입력하세요"),
  published: z.boolean().default(false),
});

type FormData = z.infer<typeof schema>;

export default function CreatePostForm() {
  const router = useRouter();
  const {
    register,
    handleSubmit,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<FormData>({
    resolver: zodResolver(schema),
    defaultValues: { published: false },
  });

  const published = watch("published");

  async function onSubmit(data: FormData) {
    const formData = new FormData();
    formData.set("title", data.title);
    formData.set("content", data.content);
    if (data.published) formData.set("published", "on");

    const result = await createPost(formData);
    if (result?.error) {
      // 에러 처리
      return;
    }
    // redirect는 Server Action 내에서 처리됨
  }

  return (
    <form onSubmit={handleSubmit(onSubmit)} className="space-y-6">
      <div className="space-y-2">
        <Label htmlFor="title">제목</Label>
        <Input id="title" {...register("title")} placeholder="게시글 제목" />
        {errors.title && (
          <p className="text-sm text-destructive">{errors.title.message}</p>
        )}
      </div>

      <div className="space-y-2">
        <Label htmlFor="content">내용</Label>
        <Textarea
          id="content"
          {...register("content")}
          rows={10}
          placeholder="내용을 입력하세요"
        />
        {errors.content && (
          <p className="text-sm text-destructive">{errors.content.message}</p>
        )}
      </div>

      <div className="flex items-center gap-2">
        <Switch
          checked={published}
          onCheckedChange={(checked) => setValue("published", checked)}
        />
        <Label>바로 공개</Label>
      </div>

      <div className="flex gap-2">
        <Button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "게시 중..." : "게시"}
        </Button>
        <Button
          type="button"
          variant="outline"
          onClick={() => router.back()}
        >
          취소
        </Button>
      </div>
    </form>
  );
}
```

---

## Example 6: Zustand Store with Persist

```typescript
// stores/useCartStore.ts
import { create } from "zustand";
import { persist } from "zustand/middleware";

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
  clearCart: () => void;
  getTotalPrice: () => number;
}

export const useCartStore = create<CartState>()(
  persist(
    (set, get) => ({
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
        set((state) => ({ items: state.items.filter((i) => i.id !== id) })),
      clearCart: () => set({ items: [] }),
      getTotalPrice: () =>
        get().items.reduce((sum, item) => sum + item.price * item.quantity, 0),
    }),
    { name: "cart-storage" }
  )
);
```

---

## Example 7: Loading/Error/NotFound Pages

```typescript
// app/(main)/posts/loading.tsx
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent, CardHeader } from "@/components/ui/card";

export default function PostsLoading() {
  return (
    <div className="space-y-6">
      <Skeleton className="h-8 w-48" />
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {Array.from({ length: 6 }).map((_, i) => (
          <Card key={i}>
            <CardHeader>
              <Skeleton className="h-5 w-3/4" />
            </CardHeader>
            <CardContent className="space-y-2">
              <Skeleton className="h-4 w-full" />
              <Skeleton className="h-4 w-2/3" />
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}

// app/(main)/posts/error.tsx
"use client";

import { Button } from "@/components/ui/button";
import { AlertCircle } from "lucide-react";

export default function PostsError({
  error,
  reset,
}: {
  error: Error;
  reset: () => void;
}) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
      <AlertCircle className="h-12 w-12 text-destructive" />
      <h2 className="text-xl font-semibold">문제가 발생했습니다</h2>
      <p className="text-muted-foreground text-center max-w-md">
        {error.message}
      </p>
      <Button onClick={reset} variant="outline">
        다시 시도
      </Button>
    </div>
  );
}

// app/(main)/posts/[id]/not-found.tsx
import Link from "next/link";
import { Button } from "@/components/ui/button";
import { FileQuestion } from "lucide-react";

export default function PostNotFound() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
      <FileQuestion className="h-12 w-12 text-muted-foreground" />
      <h2 className="text-xl font-semibold">게시글을 찾을 수 없습니다</h2>
      <Button asChild variant="outline">
        <Link href="/posts">목록으로</Link>
      </Button>
    </div>
  );
}
```
