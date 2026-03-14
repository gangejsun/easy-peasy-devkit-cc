# Performance

## Server Component 최적화 (가장 중요)

Server Component는 자체가 성능 최적화. 번들 크기 0, 서버에서 렌더링.

**원칙**: Client Component 최소화 = 최고의 성능 최적화.

---

## Next.js Image

```typescript
import Image from "next/image";

// 고정 크기
<Image
  src="/hero.jpg"
  alt="Hero"
  width={800}
  height={400}
  priority  // LCP 이미지에 사용
/>

// 반응형 (fill)
<div className="relative aspect-video">
  <Image
    src={post.imageUrl}
    alt={post.title}
    fill
    className="object-cover rounded-lg"
    sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
  />
</div>

// 외부 이미지 (next.config.ts 설정 필요)
// next.config.ts
const config = {
  images: {
    remotePatterns: [
      { hostname: "*.supabase.co" },
    ],
  },
};
```

---

## Dynamic Import (Code Splitting)

무거운 컴포넌트를 필요할 때만 로드:

```typescript
import dynamic from "next/dynamic";

// Client Component를 동적 로드
const HeavyEditor = dynamic(() => import("@/components/editor/RichEditor"), {
  loading: () => <div className="h-64 bg-muted animate-pulse rounded-lg" />,
  ssr: false, // 서버에서 렌더링하지 않음
});

// 조건부 로드
function PostPage({ post }: { post: Post }) {
  const [editing, setEditing] = useState(false);

  return (
    <div>
      {editing ? (
        <HeavyEditor content={post.content} />
      ) : (
        <div>{post.content}</div>
      )}
    </div>
  );
}
```

---

## useMemo & useCallback

### useMemo - 비싼 계산에만

```typescript
"use client";

import { useMemo } from "react";

function PostStats({ posts }: { posts: Post[] }) {
  // good: 비싼 계산
  const stats = useMemo(() => {
    return {
      total: posts.length,
      published: posts.filter((p) => p.published).length,
      avgLength: posts.reduce((sum, p) => sum + p.content.length, 0) / posts.length,
    };
  }, [posts]);

  return <div>총 {stats.total}개, 공개 {stats.published}개</div>;
}
```

### useCallback - 자식에 전달하는 함수에

```typescript
"use client";

import { useCallback } from "react";

function PostList({ posts }: { posts: Post[] }) {
  // good: 자식 컴포넌트에 전달하는 핸들러
  const handleDelete = useCallback(async (id: string) => {
    await deletePost(id);
  }, []);

  return (
    <div>
      {posts.map((post) => (
        <PostCard key={post.id} post={post} onDelete={handleDelete} />
      ))}
    </div>
  );
}
```

### 불필요한 메모이제이션 피하기

```typescript
// bad: 단순한 계산에 useMemo
const fullName = useMemo(() => `${firstName} ${lastName}`, [firstName, lastName]);
// good: 직접 계산
const fullName = `${firstName} ${lastName}`;

// bad: 외부에 전달하지 않는 핸들러에 useCallback
const handleClick = useCallback(() => setOpen(true), []);
// good: 직접 정의
const handleClick = () => setOpen(true);
```

---

## React.memo

리렌더링이 비싼 컴포넌트에만 사용:

```typescript
import { memo } from "react";

const ExpensiveChart = memo(function ExpensiveChart({
  data,
}: {
  data: ChartData[];
}) {
  // 복잡한 렌더링 로직
  return <canvas>{/* ... */}</canvas>;
});
```

---

## Debounce

검색 입력 등 빈번한 이벤트에 디바운스:

```typescript
// hooks/useDebounce.ts
import { useState, useEffect } from "react";

export function useDebounce<T>(value: T, delay = 300): T {
  const [debouncedValue, setDebouncedValue] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debouncedValue;
}

// 사용
"use client";

function SearchBar() {
  const [query, setQuery] = useState("");
  const debouncedQuery = useDebounce(query, 300);

  useEffect(() => {
    if (debouncedQuery) {
      // API 호출
    }
  }, [debouncedQuery]);

  return <Input value={query} onChange={(e) => setQuery(e.target.value)} />;
}
```

---

## Memory Leak Prevention

```typescript
"use client";

import { useEffect } from "react";

function DataPoller({ id }: { id: string }) {
  useEffect(() => {
    // 인터벌 정리
    const interval = setInterval(() => {
      fetchData(id);
    }, 5000);
    return () => clearInterval(interval);
  }, [id]);

  useEffect(() => {
    // AbortController로 fetch 취소
    const controller = new AbortController();

    fetch(`/api/data/${id}`, { signal: controller.signal })
      .then((res) => res.json())
      .then(setData)
      .catch(() => {});

    return () => controller.abort();
  }, [id]);

  useEffect(() => {
    // 이벤트 리스너 정리
    const handler = () => console.log("resize");
    window.addEventListener("resize", handler);
    return () => window.removeEventListener("resize", handler);
  }, []);
}
```

---

## List Rendering

```typescript
// good: 안정적인 key 사용
{posts.map((post) => (
  <PostCard key={post.id} post={post} />
))}

// bad: 인덱스를 key로 사용 (리스트가 변경될 때 문제)
{posts.map((post, index) => (
  <PostCard key={index} post={post} />
))}
```

---

## 성능 체크리스트

- [ ] Server Component를 기본으로 사용하고 있는가?
- [ ] `"use client"` 경계가 최소한인가?
- [ ] Image 컴포넌트에 적절한 `sizes`와 `priority`를 설정했는가?
- [ ] 무거운 컴포넌트를 `dynamic()`으로 분리했는가?
- [ ] useEffect에서 cleanup을 하고 있는가?
- [ ] 검색/필터에 debounce를 적용했는가?
- [ ] 불필요한 useMemo/useCallback을 제거했는가?
