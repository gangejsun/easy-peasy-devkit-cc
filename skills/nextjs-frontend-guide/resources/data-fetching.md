# Data Fetching

## Server Component Data Fetching (기본 패턴)

Server Component에서 직접 데이터를 패칭하는 것이 기본 패턴.
번들 크기 0, 워터폴 방지, 보안 (API 키 노출 없음).

```typescript
// app/posts/page.tsx
import { createClient } from "@/lib/supabase/server";

export default async function PostsPage() {
  const supabase = await createClient();

  const { data: posts, error } = await supabase
    .from("posts")
    .select("id, title, created_at, author:profiles(name)")
    .eq("published", true)
    .order("created_at", { ascending: false });

  if (error) {
    throw new Error("게시글을 불러오는데 실패했습니다");
  }

  return (
    <div className="space-y-4">
      {posts.map((post) => (
        <PostCard key={post.id} post={post} />
      ))}
    </div>
  );
}
```

---

## Parallel Data Fetching

여러 데이터를 동시에 패칭하여 워터폴 방지:

```typescript
export default async function DashboardPage() {
  const supabase = await createClient();

  // 병렬 패칭 (Promise.all)
  const [postsResult, statsResult, notificationsResult] = await Promise.all([
    supabase.from("posts").select("*").limit(5),
    supabase.rpc("get_dashboard_stats"),
    supabase.from("notifications").select("*").eq("read", false).limit(10),
  ]);

  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <section className="lg:col-span-2">
        <RecentPosts posts={postsResult.data ?? []} />
      </section>
      <aside className="space-y-6">
        <StatsPanel stats={statsResult.data} />
        <NotificationList notifications={notificationsResult.data ?? []} />
      </aside>
    </div>
  );
}
```

---

## Streaming with Suspense

독립적인 데이터 섹션을 Suspense로 감싸면 점진적 로딩 가능:

```typescript
import { Suspense } from "react";
import PostListSkeleton from "@/components/post/PostListSkeleton";
import StatsSkeleton from "@/components/dashboard/StatsSkeleton";

export default function DashboardPage() {
  return (
    <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
      <section className="lg:col-span-2">
        <Suspense fallback={<PostListSkeleton />}>
          <RecentPosts />
        </Suspense>
      </section>
      <aside>
        <Suspense fallback={<StatsSkeleton />}>
          <DashboardStats />
        </Suspense>
      </aside>
    </div>
  );
}

// 각 컴포넌트가 독립적으로 데이터 패칭
async function RecentPosts() {
  const supabase = await createClient();
  const { data } = await supabase.from("posts").select("*").limit(5);
  return <PostList posts={data ?? []} />;
}

async function DashboardStats() {
  const supabase = await createClient();
  const { data } = await supabase.rpc("get_dashboard_stats");
  return <StatsPanel stats={data} />;
}
```

---

## Client-Side Data Fetching

Client Component에서 데이터 패칭이 필요한 경우 (실시간, 사용자 인터랙션 후):

```typescript
"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function SearchResults({ query }: { query: string }) {
  const [results, setResults] = useState<Post[]>([]);
  const [loading, setLoading] = useState(false);
  const supabase = createClient();

  useEffect(() => {
    if (!query) {
      setResults([]);
      return;
    }

    setLoading(true);
    const search = async () => {
      const { data } = await supabase
        .from("posts")
        .select("*")
        .ilike("title", `%${query}%`)
        .limit(20);

      setResults(data ?? []);
      setLoading(false);
    };

    search();
  }, [query, supabase]);

  if (loading) return <SearchSkeleton />;
  return <ResultList results={results} />;
}
```

---

## Revalidation

### Time-based

```typescript
// next.config.ts에서 전역 설정
// 또는 fetch에서 개별 설정

// Server Component에서 cache 제어
export const revalidate = 60; // 60초마다 revalidation

export default async function PostsPage() {
  // ...
}
```

### On-demand

```typescript
// Server Action에서
"use server";
import { revalidatePath, revalidateTag } from "next/cache";

export async function createPost(formData: FormData) {
  // ... 생성 로직
  revalidatePath("/posts");        // 경로 기반
  revalidateTag("posts");           // 태그 기반
}
```

---

## Data Fetching Decision Tree

| 상황 | 방식 |
|------|------|
| 페이지 초기 데이터 | Server Component async fetch |
| SEO 필요 데이터 | Server Component |
| 사용자 인터랙션 후 패칭 | Client Component + useEffect |
| 실시간 데이터 | Supabase Realtime (Client) |
| 폼 제출 후 데이터 변경 | Server Action + revalidation |
| 독립적 섹션 병렬 로딩 | Suspense + async 컴포넌트 |
| 검색/필터 | Client Component 또는 searchParams |

---

## searchParams for Server-Side Filtering

```typescript
// app/posts/page.tsx
interface PostsPageProps {
  searchParams: Promise<{
    page?: string;
    q?: string;
    sort?: string;
  }>;
}

export default async function PostsPage({ searchParams }: PostsPageProps) {
  const { page = "1", q, sort = "newest" } = await searchParams;
  const supabase = await createClient();
  const offset = (Number(page) - 1) * 10;

  let query = supabase
    .from("posts")
    .select("*", { count: "exact" })
    .eq("published", true);

  if (q) {
    query = query.ilike("title", `%${q}%`);
  }

  query = query
    .order("created_at", { ascending: sort === "oldest" })
    .range(offset, offset + 9);

  const { data, count } = await query;

  return (
    <div>
      <SearchForm defaultQuery={q} />
      <PostList posts={data ?? []} />
      <Pagination total={count ?? 0} page={Number(page)} limit={10} />
    </div>
  );
}
```

---

## Anti-Patterns

```typescript
// bad: Server Component에서 불필요하게 Client로 전환
"use client";
export default function PostList() {
  const [posts, setPosts] = useState([]);
  useEffect(() => {
    fetch("/api/posts").then(r => r.json()).then(setPosts);
  }, []);
  // Server Component에서 직접 패칭하면 됨
}

// bad: 워터폴 패칭
export default async function Page() {
  const posts = await getPosts();         // 1초
  const user = await getUser();           // 1초 (순차 대기)
  const stats = await getStats();         // 1초 (순차 대기)
  // 총 3초 → Promise.all로 1초로 줄일 수 있음
}

// bad: 에러 처리 없이 패칭
const { data } = await supabase.from("posts").select("*");
return <div>{data.map(/* */)}</div>; // data가 null일 수 있음
```
