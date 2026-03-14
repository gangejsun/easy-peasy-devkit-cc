# Database Patterns

## Supabase Query Basics

### Select (읽기)

```typescript
import { createClient } from "@/lib/supabase/server";

// 전체 조회
const { data, error } = await supabase.from("posts").select("*");

// 특정 컬럼만 조회 (성능 최적화)
const { data } = await supabase
  .from("posts")
  .select("id, title, created_at");

// 관계 조회 (JOIN)
const { data } = await supabase
  .from("posts")
  .select(`
    id,
    title,
    content,
    author:profiles(id, name, avatar_url)
  `);

// 단일 행 조회
const { data: post } = await supabase
  .from("posts")
  .select("*")
  .eq("id", id)
  .single();
```

### Insert (생성)

```typescript
// 단일 삽입
const { data, error } = await supabase
  .from("posts")
  .insert({ title: "Hello", content: "World", author_id: userId })
  .select()
  .single();

// 다중 삽입
const { data, error } = await supabase
  .from("tags")
  .insert([
    { name: "javascript" },
    { name: "typescript" },
    { name: "react" },
  ])
  .select();
```

### Update (수정)

```typescript
const { data, error } = await supabase
  .from("posts")
  .update({ title: "Updated Title", updated_at: new Date().toISOString() })
  .eq("id", postId)
  .select()
  .single();
```

### Delete (삭제)

```typescript
const { error } = await supabase
  .from("posts")
  .delete()
  .eq("id", postId);
```

### Upsert

```typescript
const { data, error } = await supabase
  .from("profiles")
  .upsert({
    id: userId,
    name: "John",
    updated_at: new Date().toISOString(),
  })
  .select()
  .single();
```

---

## Filtering

```typescript
// 동등 비교
.eq("status", "published")
.neq("status", "draft")

// 비교 연산
.gt("price", 1000)      // greater than
.gte("price", 1000)     // greater than or equal
.lt("price", 5000)      // less than
.lte("price", 5000)     // less than or equal

// 범위
.gte("price", 1000).lte("price", 5000)

// IN
.in("status", ["published", "featured"])

// LIKE
.like("title", "%search%")
.ilike("title", "%search%")  // case-insensitive

// IS NULL
.is("deleted_at", null)

// 배열 포함
.contains("tags", ["javascript"])
.containedBy("tags", ["javascript", "typescript", "react"])

// 텍스트 검색
.textSearch("title", "search query", { type: "websearch" })
```

---

## Pagination

```typescript
async function getPaginatedPosts(page: number, limit: number) {
  const supabase = await createClient();
  const offset = (page - 1) * limit;

  const { data, error, count } = await supabase
    .from("posts")
    .select("*", { count: "exact" })
    .eq("published", true)
    .order("created_at", { ascending: false })
    .range(offset, offset + limit - 1);

  return {
    data: data ?? [],
    total: count ?? 0,
    page,
    limit,
    totalPages: Math.ceil((count ?? 0) / limit),
  };
}
```

---

## Complex Queries

### 관계 필터링

```typescript
// 특정 작성자의 게시글
const { data } = await supabase
  .from("posts")
  .select(`
    *,
    author:profiles!inner(name)
  `)
  .eq("author.name", "John");
```

### 집계 (Count)

```typescript
const { count } = await supabase
  .from("posts")
  .select("*", { count: "exact", head: true })
  .eq("published", true);
```

### RPC (Stored Procedure)

```typescript
// Supabase에 정의된 함수 호출
const { data, error } = await supabase.rpc("get_popular_posts", {
  limit_count: 10,
  min_likes: 5,
});
```

---

## Transaction-like Operations

Supabase REST API는 네이티브 트랜잭션을 지원하지 않지만, RPC로 서버 사이드 트랜잭션을 구현할 수 있다.

```sql
-- Supabase SQL Editor에서 함수 생성
CREATE OR REPLACE FUNCTION transfer_points(
  from_user_id UUID,
  to_user_id UUID,
  amount INT
)
RETURNS void AS $$
BEGIN
  UPDATE profiles SET points = points - amount WHERE id = from_user_id;
  UPDATE profiles SET points = points + amount WHERE id = to_user_id;

  IF (SELECT points FROM profiles WHERE id = from_user_id) < 0 THEN
    RAISE EXCEPTION 'Insufficient points';
  END IF;
END;
$$ LANGUAGE plpgsql;
```

```typescript
// 클라이언트에서 호출
const { error } = await supabase.rpc("transfer_points", {
  from_user_id: senderId,
  to_user_id: receiverId,
  amount: 100,
});
```

---

## Query Optimization

### 필요한 컬럼만 조회

```typescript
// bad: 모든 컬럼 조회
const { data } = await supabase.from("posts").select("*");

// good: 필요한 컬럼만 조회
const { data } = await supabase
  .from("posts")
  .select("id, title, created_at, author:profiles(name)");
```

### N+1 방지

```typescript
// bad: N+1 쿼리
const { data: posts } = await supabase.from("posts").select("*");
for (const post of posts) {
  const { data: author } = await supabase
    .from("profiles")
    .select("*")
    .eq("id", post.author_id)
    .single();
}

// good: JOIN으로 한 번에 조회
const { data: posts } = await supabase
  .from("posts")
  .select("*, author:profiles(id, name, avatar_url)");
```

### 인덱스 활용

자주 필터링/정렬하는 컬럼에 인덱스를 생성:

```sql
CREATE INDEX idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX idx_posts_author_id ON posts(author_id);
CREATE INDEX idx_posts_status ON posts(status) WHERE status = 'published';
```

---

## Type Safety with Generated Types

```bash
# Supabase 타입 생성
npx supabase gen types typescript --project-id <project-id> > src/types/database.ts
```

```typescript
import type { Database } from "@/types/database";

type Post = Database["public"]["Tables"]["posts"]["Row"];
type InsertPost = Database["public"]["Tables"]["posts"]["Insert"];
type UpdatePost = Database["public"]["Tables"]["posts"]["Update"];

// 타입 안전한 클라이언트
import { createClient } from "@supabase/supabase-js";

const supabase = createClient<Database>(url, key);
```
