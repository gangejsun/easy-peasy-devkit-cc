# Routing Guide

## Next.js App Router

파일 시스템 기반 라우팅. `app/` 디렉토리 구조가 URL 구조를 결정한다.

---

## 기본 라우팅

```
app/
├── page.tsx          →  /
├── about/
│   └── page.tsx      →  /about
├── posts/
│   ├── page.tsx      →  /posts
│   └── [id]/
│       └── page.tsx  →  /posts/:id
```

### 기본 페이지

```typescript
// app/posts/page.tsx
export default async function PostsPage() {
  return <div>Posts List</div>;
}
```

### Dynamic Route

```typescript
// app/posts/[id]/page.tsx
interface PostPageProps {
  params: Promise<{ id: string }>;
}

export default async function PostPage({ params }: PostPageProps) {
  const { id } = await params;
  // id를 사용하여 데이터 패칭
  return <div>Post {id}</div>;
}
```

### Catch-all Route

```typescript
// app/docs/[...slug]/page.tsx  → /docs/a, /docs/a/b, /docs/a/b/c
interface DocsPageProps {
  params: Promise<{ slug: string[] }>;
}

export default async function DocsPage({ params }: DocsPageProps) {
  const { slug } = await params;
  // slug = ["a", "b", "c"]
  return <div>Docs: {slug.join("/")}</div>;
}
```

---

## Route Groups

URL에 영향 없이 라우트를 논리적으로 그룹화:

```
app/
├── (auth)/              # URL에 (auth) 포함되지 않음
│   ├── layout.tsx       # auth 전용 레이아웃 (로그인 페이지 등)
│   ├── login/
│   │   └── page.tsx     →  /login
│   └── signup/
│       └── page.tsx     →  /signup
├── (main)/              # URL에 (main) 포함되지 않음
│   ├── layout.tsx       # 메인 레이아웃 (Header, Footer 포함)
│   ├── deals/
│   │   └── page.tsx     →  /deals
│   └── my/
│       └── page.tsx     →  /my
```

---

## Layouts

### Root Layout

```typescript
// app/layout.tsx
import type { Metadata } from "next";
import "@/app/globals.css";

export const metadata: Metadata = {
  title: "EasyPeasyClaudeCodeDevkit",
  description: "AI Native Dev Harness",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="ko">
      <body className="min-h-screen bg-background font-sans antialiased">
        {children}
      </body>
    </html>
  );
}
```

### Nested Layout

```typescript
// app/(main)/layout.tsx
import Header from "@/components/layout/Header";
import Footer from "@/components/layout/Footer";

export default function MainLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="flex min-h-screen flex-col">
      <Header />
      <main className="flex-1 container mx-auto px-4 py-8">
        {children}
      </main>
      <Footer />
    </div>
  );
}
```

---

## Navigation

### Link 컴포넌트

```typescript
import Link from "next/link";

// 기본 링크
<Link href="/posts">게시글 목록</Link>

// 동적 링크
<Link href={`/posts/${post.id}`}>{post.title}</Link>

// 활성 상태 감지
"use client";
import { usePathname } from "next/navigation";

function NavLink({ href, children }: { href: string; children: React.ReactNode }) {
  const pathname = usePathname();
  const isActive = pathname === href;

  return (
    <Link
      href={href}
      className={cn(
        "text-sm font-medium transition-colors",
        isActive ? "text-foreground" : "text-muted-foreground hover:text-foreground"
      )}
    >
      {children}
    </Link>
  );
}
```

### Programmatic Navigation

```typescript
"use client";
import { useRouter } from "next/navigation";

function LoginForm() {
  const router = useRouter();

  async function handleSubmit() {
    // ... 로그인 로직
    router.push("/");           // 이동
    router.replace("/");        // 이동 (히스토리 교체)
    router.back();              // 뒤로가기
    router.refresh();           // 서버 컴포넌트 새로고침
  }
}
```

### Server-Side Redirect

```typescript
import { redirect } from "next/navigation";

export default async function ProtectedPage() {
  const user = await getUser();
  if (!user) {
    redirect("/login");
  }
  return <Dashboard user={user} />;
}
```

---

## Search Params

```typescript
// app/posts/page.tsx
interface PostsPageProps {
  searchParams: Promise<{
    page?: string;
    q?: string;
    category?: string;
  }>;
}

export default async function PostsPage({ searchParams }: PostsPageProps) {
  const { page = "1", q, category } = await searchParams;
  // 필터링/페이지네이션에 활용
}
```

### Client에서 Search Params 조작

```typescript
"use client";
import { useSearchParams, useRouter, usePathname } from "next/navigation";

function SearchBar() {
  const searchParams = useSearchParams();
  const router = useRouter();
  const pathname = usePathname();

  function handleSearch(query: string) {
    const params = new URLSearchParams(searchParams.toString());
    if (query) {
      params.set("q", query);
    } else {
      params.delete("q");
    }
    params.set("page", "1"); // 검색 시 1페이지로
    router.push(`${pathname}?${params.toString()}`);
  }
}
```

---

## Metadata

```typescript
// 정적 메타데이터
export const metadata: Metadata = {
  title: "게시글 목록",
  description: "최신 게시글을 확인하세요",
};

// 동적 메타데이터
export async function generateMetadata({
  params,
}: {
  params: Promise<{ id: string }>;
}): Promise<Metadata> {
  const { id } = await params;
  const post = await getPost(id);

  return {
    title: post?.title ?? "게시글",
    description: post?.content?.slice(0, 160),
  };
}
```

---

## Anti-Patterns

```typescript
// bad: <a> 태그 사용 (클라이언트 사이드 네비게이션 안됨)
<a href="/posts">Posts</a>
// good:
<Link href="/posts">Posts</Link>

// bad: Client Component에서 불필요한 router.push
// Server Component에서 redirect 사용 가능한 경우
"use client";
router.push("/login");
// good:
redirect("/login"); // Server Component/Action에서

// bad: 하드코딩된 URL
<Link href="https://mysite.com/posts">
// good:
<Link href="/posts">
```
