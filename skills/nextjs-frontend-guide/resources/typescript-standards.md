# TypeScript Standards

## 핵심 규칙

- **strict 모드** 활성화 (`tsconfig.json`)
- **`any` 금지** → `unknown` 또는 구체적 타입 사용
- **`@/` alias** 필수 (상대경로 금지)
- **`function` 키워드** 컴포넌트 선언
- **Props 타입**은 컴포넌트와 같은 파일에 정의

---

## Type vs Interface

```typescript
// interface: 컴포넌트 Props, 객체 형태
interface UserCardProps {
  user: User;
  className?: string;
  onSelect?: (id: string) => void;
}

// type: 유니온, 유틸리티, 단순 타입 별칭
type Status = "active" | "pending" | "closed";
type Nullable<T> = T | null;
type AsyncReturnType<T extends (...args: unknown[]) => Promise<unknown>> =
  Awaited<ReturnType<T>>;
```

---

## No `any` Type

```typescript
// bad
function processData(data: any) { /* ... */ }
const result: any = await fetchData();

// good: unknown + 타입 가드
function processData(data: unknown) {
  if (typeof data === "string") {
    return data.toUpperCase();
  }
  if (isUser(data)) {
    return data.name;
  }
  throw new Error("Unexpected data type");
}

// good: 구체적 타입
const result: ApiResponse<User> = await fetchData();
```

---

## Type Imports

```typescript
// good: type 키워드로 타입만 import
import type { User, Post } from "@/types";
import type { Database } from "@/types/database";

// good: 값과 타입 혼합 시
import { createClient } from "@/lib/supabase/server";
import type { SupabaseClient } from "@supabase/supabase-js";
```

---

## Component Props

```typescript
// Props는 컴포넌트와 같은 파일에 정의
interface PostCardProps {
  post: Post;
  variant?: "default" | "compact";
  className?: string;
  onDelete?: (id: string) => void;
}

function PostCard({ post, variant = "default", className, onDelete }: PostCardProps) {
  return (
    <div className={cn("rounded-lg border", className)}>
      {/* ... */}
    </div>
  );
}

export default PostCard;
```

### Children Props

```typescript
interface LayoutProps {
  children: React.ReactNode;
  sidebar?: React.ReactNode;
}

function TwoColumnLayout({ children, sidebar }: LayoutProps) {
  return (
    <div className="grid grid-cols-12 gap-6">
      <main className="col-span-8">{children}</main>
      {sidebar && <aside className="col-span-4">{sidebar}</aside>}
    </div>
  );
}
```

---

## Function Return Types

명시적 반환 타입은 공개 API와 복잡한 로직에 사용:

```typescript
// 서비스 함수: 명시적 반환 타입 권장
async function getUser(id: string): Promise<User | null> {
  const supabase = await createClient();
  const { data } = await supabase
    .from("users")
    .select("*")
    .eq("id", id)
    .single();
  return data;
}

// Server Action: 반환 타입 명시
type ActionResult = { success: true } | { success: false; error: string };

async function deletePost(id: string): Promise<ActionResult> {
  // ...
}

// 컴포넌트: 반환 타입 생략 가능 (JSX.Element 자동 추론)
function PostCard({ post }: PostCardProps) {
  return <div>{post.title}</div>;
}
```

---

## Utility Types

```typescript
// Partial - 모든 속성을 선택적으로
type UpdateUserInput = Partial<User>;

// Pick - 특정 속성만 선택
type UserSummary = Pick<User, "id" | "name" | "avatarUrl">;

// Omit - 특정 속성 제외
type CreateUserInput = Omit<User, "id" | "createdAt" | "updatedAt">;

// Required - 선택적 속성을 필수로
type RequiredProfile = Required<Pick<User, "name" | "bio">>;

// Record - 키-값 쌍
type StatusColors = Record<Status, string>;
const statusColors: StatusColors = {
  active: "green",
  pending: "yellow",
  closed: "gray",
};

// Readonly
type ImmutableUser = Readonly<User>;
```

---

## Type Guards

```typescript
// 기본 타입 가드
function isString(value: unknown): value is string {
  return typeof value === "string";
}

// 객체 타입 가드
function isUser(value: unknown): value is User {
  return (
    typeof value === "object" &&
    value !== null &&
    "id" in value &&
    "email" in value
  );
}

// Discriminated Union
type ApiResult<T> =
  | { success: true; data: T }
  | { success: false; error: string };

function handleResult<T>(result: ApiResult<T>) {
  if (result.success) {
    // result.data 접근 가능 (타입 좁혀짐)
    console.log(result.data);
  } else {
    // result.error 접근 가능
    console.error(result.error);
  }
}
```

---

## Supabase Generated Types

```bash
npx supabase gen types typescript --project-id <id> > src/types/database.ts
```

```typescript
import type { Database } from "@/types/database";

// 테이블 Row 타입
type User = Database["public"]["Tables"]["users"]["Row"];
type Post = Database["public"]["Tables"]["posts"]["Row"];

// Insert/Update 타입
type InsertPost = Database["public"]["Tables"]["posts"]["Insert"];
type UpdatePost = Database["public"]["Tables"]["posts"]["Update"];

// 타입 안전한 Supabase 클라이언트
import { createClient } from "@supabase/supabase-js";
const supabase = createClient<Database>(url, key);
```

---

## Null/Undefined Handling

```typescript
// Optional chaining
const name = user?.profile?.name;

// Nullish coalescing
const displayName = user?.name ?? "Anonymous";

// Non-null assertion (확실한 경우에만)
const element = document.getElementById("root")!;

// 타입 좁히기
function renderUser(user: User | null) {
  if (!user) return <EmptyState />;
  return <UserCard user={user} />;  // user는 여기서 non-null
}
```

---

## Naming Conventions

| 대상 | 규칙 | 예시 |
|------|------|------|
| 컴포넌트/타입/인터페이스 | PascalCase | `UserCard`, `PostResponse` |
| 함수/변수 | camelCase | `formatPrice`, `userName` |
| 상수 | UPPER_SNAKE_CASE | `MAX_RETRIES`, `API_URL` |
| 타입 접미사 | 역할 반영 | `Props`, `State`, `Input`, `Response` |
| Zustand 스토어 | use~Store | `useAuthStore`, `useCartStore` |
| 훅 | use~ | `useDebounce`, `useMediaQuery` |
