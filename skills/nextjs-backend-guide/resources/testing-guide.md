# Testing Guide

## Testing Strategy

| 테스트 유형 | 대상 | 도구 |
|------------|------|------|
| Unit Test | 서비스 로직, 유틸 함수 | Vitest/Jest |
| Integration Test | Route Handler, Server Action | Vitest/Jest + Supabase 모킹 |
| E2E Test | 전체 플로우 | Playwright |

---

## Setup

```typescript
// vitest.config.ts
import { defineConfig } from "vitest/config";
import react from "@vitejs/plugin-react";
import path from "path";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "node",
    globals: true,
    setupFiles: ["./tests/setup.ts"],
  },
  resolve: {
    alias: {
      "@": path.resolve(__dirname, "./src"),
    },
  },
});
```

---

## Unit Testing

### 서비스 로직 테스트

```typescript
// lib/services/__tests__/user.test.ts
import { describe, it, expect, vi, beforeEach } from "vitest";
import { createUser, getUserById } from "@/lib/services/user";

// Supabase 모킹
vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(() => ({
    from: vi.fn(() => ({
      insert: vi.fn(() => ({
        select: vi.fn(() => ({
          single: vi.fn(() => ({
            data: { id: "1", email: "test@example.com", name: "Test" },
            error: null,
          })),
        })),
      })),
      select: vi.fn(() => ({
        eq: vi.fn(() => ({
          single: vi.fn(() => ({
            data: { id: "1", email: "test@example.com", name: "Test" },
            error: null,
          })),
        })),
      })),
    })),
  })),
}));

describe("User Service", () => {
  it("should create a user", async () => {
    const user = await createUser({
      email: "test@example.com",
      name: "Test",
    });

    expect(user).toBeDefined();
    expect(user.email).toBe("test@example.com");
  });

  it("should get user by id", async () => {
    const user = await getUserById("1");

    expect(user).toBeDefined();
    expect(user.id).toBe("1");
  });
});
```

### 유틸 함수 테스트

```typescript
// lib/utils/__tests__/format.test.ts
import { describe, it, expect } from "vitest";
import { formatPrice, slugify } from "@/lib/utils/format";

describe("formatPrice", () => {
  it("should format Korean won", () => {
    expect(formatPrice(10000)).toBe("10,000원");
  });

  it("should handle zero", () => {
    expect(formatPrice(0)).toBe("0원");
  });
});

describe("slugify", () => {
  it("should convert to URL-safe slug", () => {
    expect(slugify("Hello World")).toBe("hello-world");
  });
});
```

---

## Route Handler Testing

```typescript
// app/api/posts/__tests__/route.test.ts
import { describe, it, expect, vi } from "vitest";
import { GET, POST } from "@/app/api/posts/route";
import { NextRequest } from "next/server";

// Supabase 모킹
const mockSupabase = {
  from: vi.fn(),
  auth: { getUser: vi.fn() },
};

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(() => mockSupabase),
}));

describe("GET /api/posts", () => {
  it("should return posts list", async () => {
    const mockPosts = [
      { id: "1", title: "Post 1" },
      { id: "2", title: "Post 2" },
    ];

    mockSupabase.from.mockReturnValue({
      select: vi.fn().mockReturnValue({
        order: vi.fn().mockReturnValue({
          range: vi.fn().mockResolvedValue({
            data: mockPosts,
            error: null,
            count: 2,
          }),
        }),
      }),
    });

    const request = new NextRequest("http://localhost/api/posts?page=1&limit=10");
    const response = await GET(request);
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.data).toHaveLength(2);
    expect(body.total).toBe(2);
  });

  it("should handle database errors", async () => {
    mockSupabase.from.mockReturnValue({
      select: vi.fn().mockReturnValue({
        order: vi.fn().mockReturnValue({
          range: vi.fn().mockResolvedValue({
            data: null,
            error: { message: "Connection failed" },
            count: null,
          }),
        }),
      }),
    });

    const request = new NextRequest("http://localhost/api/posts");
    const response = await GET(request);

    expect(response.status).toBe(500);
  });
});

describe("POST /api/posts", () => {
  it("should create a post with valid data", async () => {
    mockSupabase.auth.getUser.mockResolvedValue({
      data: { user: { id: "user-1" } },
      error: null,
    });

    mockSupabase.from.mockReturnValue({
      insert: vi.fn().mockReturnValue({
        select: vi.fn().mockReturnValue({
          single: vi.fn().mockResolvedValue({
            data: { id: "1", title: "New Post" },
            error: null,
          }),
        }),
      }),
    });

    const request = new NextRequest("http://localhost/api/posts", {
      method: "POST",
      body: JSON.stringify({ title: "New Post", content: "Content" }),
    });

    const response = await POST(request);
    expect(response.status).toBe(201);
  });

  it("should return 400 for invalid data", async () => {
    const request = new NextRequest("http://localhost/api/posts", {
      method: "POST",
      body: JSON.stringify({ title: "" }), // 빈 제목
    });

    const response = await POST(request);
    expect(response.status).toBe(400);
  });
});
```

---

## Server Action Testing

```typescript
// lib/actions/__tests__/post.test.ts
import { describe, it, expect, vi } from "vitest";
import { createPost } from "@/lib/actions/post";

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(() => ({
    auth: {
      getUser: vi.fn().mockResolvedValue({
        data: { user: { id: "user-1" } },
        error: null,
      }),
    },
    from: vi.fn(() => ({
      insert: vi.fn(() => ({
        select: vi.fn(() => ({
          single: vi.fn().mockResolvedValue({
            data: { id: "1", title: "Test" },
            error: null,
          }),
        })),
      })),
    })),
  })),
}));

vi.mock("next/cache", () => ({
  revalidatePath: vi.fn(),
}));

describe("createPost action", () => {
  it("should create a post successfully", async () => {
    const formData = new FormData();
    formData.set("title", "Test Post");
    formData.set("content", "Test Content");

    const result = await createPost(formData);

    expect(result.success).toBe(true);
  });

  it("should return validation error for empty title", async () => {
    const formData = new FormData();
    formData.set("title", "");
    formData.set("content", "Content");

    const result = await createPost(formData);

    expect(result.success).toBe(false);
    expect(result.error).toBeDefined();
  });
});
```

---

## Testing Patterns

### Test Data Factory

```typescript
// tests/factories/user.ts
export function createMockUser(overrides?: Partial<User>): User {
  return {
    id: crypto.randomUUID(),
    email: "test@example.com",
    name: "Test User",
    created_at: new Date().toISOString(),
    ...overrides,
  };
}

export function createMockPost(overrides?: Partial<Post>): Post {
  return {
    id: crypto.randomUUID(),
    title: "Test Post",
    content: "Test Content",
    author_id: crypto.randomUUID(),
    published: false,
    created_at: new Date().toISOString(),
    ...overrides,
  };
}
```

### Supabase Mock Helper

```typescript
// tests/helpers/supabase-mock.ts
export function createSupabaseMock() {
  const mock = {
    from: vi.fn(),
    auth: {
      getUser: vi.fn(),
      signInWithPassword: vi.fn(),
      signUp: vi.fn(),
      signOut: vi.fn(),
    },
    storage: {
      from: vi.fn(),
    },
    rpc: vi.fn(),
  };

  // 체이닝 헬퍼
  mock.from.mockImplementation(() => ({
    select: vi.fn().mockReturnThis(),
    insert: vi.fn().mockReturnThis(),
    update: vi.fn().mockReturnThis(),
    delete: vi.fn().mockReturnThis(),
    eq: vi.fn().mockReturnThis(),
    single: vi.fn().mockResolvedValue({ data: null, error: null }),
    order: vi.fn().mockReturnThis(),
    range: vi.fn().mockResolvedValue({ data: [], error: null, count: 0 }),
  }));

  return mock;
}
```

---

## Coverage Targets

| 영역 | 목표 |
|------|------|
| 서비스 로직 | 80%+ |
| Route Handler | 주요 경로 커버 |
| Server Action | 주요 경로 커버 |
| 유틸 함수 | 90%+ |
| E2E | Happy path 커버 |
