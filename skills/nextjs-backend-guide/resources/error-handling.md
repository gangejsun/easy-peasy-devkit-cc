# Error Handling

## Error Handling Strategy

Next.js는 계층별로 다른 에러 처리 메커니즘을 제공한다.

| 계층 | 에러 처리 방식 |
|------|--------------|
| Server Component | `error.tsx` boundary |
| Route Handler | try-catch + HTTP 상태코드 |
| Server Action | 결과 객체 반환 (throw 안함) |
| Client Component | React Error Boundary |
| Global | `global-error.tsx` |

---

## Custom Error Types

```typescript
// lib/errors.ts
export class AppError extends Error {
  constructor(
    public code: string,
    message: string,
    public statusCode: number = 500,
    public details?: unknown
  ) {
    super(message);
    this.name = "AppError";
  }
}

export class ValidationError extends AppError {
  constructor(message: string, details?: unknown) {
    super("VALIDATION_ERROR", message, 400, details);
    this.name = "ValidationError";
  }
}

export class NotFoundError extends AppError {
  constructor(resource: string) {
    super("NOT_FOUND", `${resource} not found`, 404);
    this.name = "NotFoundError";
  }
}

export class UnauthorizedError extends AppError {
  constructor(message = "Unauthorized") {
    super("UNAUTHORIZED", message, 401);
    this.name = "UnauthorizedError";
  }
}

export class ForbiddenError extends AppError {
  constructor(message = "Forbidden") {
    super("FORBIDDEN", message, 403);
    this.name = "ForbiddenError";
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super("CONFLICT", message, 409);
    this.name = "ConflictError";
  }
}
```

---

## Route Handler Error Handling

```typescript
import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { AppError } from "@/lib/errors";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const validated = createPostSchema.parse(body);
    const post = await createPost(validated);
    return NextResponse.json(post, { status: 201 });
  } catch (error) {
    return handleApiError(error);
  }
}

// 공통 에러 핸들러
function handleApiError(error: unknown) {
  if (error instanceof z.ZodError) {
    return NextResponse.json(
      {
        error: "Validation Error",
        details: error.errors.map((e) => ({
          field: e.path.join("."),
          message: e.message,
        })),
      },
      { status: 400 }
    );
  }

  if (error instanceof AppError) {
    return NextResponse.json(
      { error: error.message, code: error.code },
      { status: error.statusCode }
    );
  }

  console.error("Unexpected error:", error);
  return NextResponse.json(
    { error: "Internal Server Error" },
    { status: 500 }
  );
}
```

---

## Server Action Error Handling

Server Action에서는 throw 대신 결과 객체를 반환한다.

```typescript
"use server";

type ActionResult<T = void> =
  | { success: true; data?: T }
  | { success: false; error: string; fieldErrors?: Record<string, string[]> };

export async function updateProfile(
  formData: FormData
): Promise<ActionResult> {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();

    if (!user) {
      return { success: false, error: "로그인이 필요합니다" };
    }

    const result = schema.safeParse({
      name: formData.get("name"),
      bio: formData.get("bio"),
    });

    if (!result.success) {
      return {
        success: false,
        error: "입력값을 확인해주세요",
        fieldErrors: result.error.flatten().fieldErrors,
      };
    }

    const { error } = await supabase
      .from("profiles")
      .update(result.data)
      .eq("id", user.id);

    if (error) {
      return { success: false, error: "프로필 업데이트에 실패했습니다" };
    }

    revalidatePath("/profile");
    return { success: true };
  } catch {
    return { success: false, error: "예상치 못한 오류가 발생했습니다" };
  }
}
```

---

## Page-Level Error Boundary

```typescript
// app/posts/error.tsx
"use client";

interface ErrorPageProps {
  error: Error & { digest?: string };
  reset: () => void;
}

export default function ErrorPage({ error, reset }: ErrorPageProps) {
  return (
    <div className="flex flex-col items-center justify-center min-h-[400px] gap-4">
      <h2 className="text-xl font-semibold">문제가 발생했습니다</h2>
      <p className="text-muted-foreground">{error.message}</p>
      <button
        onClick={reset}
        className="px-4 py-2 bg-primary text-primary-foreground rounded-md"
      >
        다시 시도
      </button>
    </div>
  );
}
```

### Global Error

```typescript
// app/global-error.tsx
"use client";

export default function GlobalError({
  error,
  reset,
}: {
  error: Error & { digest?: string };
  reset: () => void;
}) {
  return (
    <html>
      <body>
        <h2>Something went wrong!</h2>
        <button onClick={reset}>Try again</button>
      </body>
    </html>
  );
}
```

---

## Not Found Handling

```typescript
// app/posts/[id]/page.tsx
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export default async function PostPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: post } = await supabase
    .from("posts")
    .select("*")
    .eq("id", id)
    .single();

  if (!post) {
    notFound(); // 자동으로 not-found.tsx를 렌더링
  }

  return <PostDetail post={post} />;
}

// app/posts/[id]/not-found.tsx
export default function NotFound() {
  return (
    <div className="flex flex-col items-center justify-center min-h-[400px]">
      <h2 className="text-xl font-semibold">게시글을 찾을 수 없습니다</h2>
    </div>
  );
}
```

---

## Supabase Error Handling

```typescript
import { PostgrestError } from "@supabase/supabase-js";

function handleSupabaseError(error: PostgrestError): AppError {
  // 일반적인 Supabase/PostgreSQL 에러 매핑
  switch (error.code) {
    case "23505": // unique_violation
      return new ConflictError("이미 존재하는 데이터입니다");
    case "23503": // foreign_key_violation
      return new AppError("REFERENCE_ERROR", "참조된 데이터가 없습니다", 400);
    case "42501": // insufficient_privilege (RLS)
      return new ForbiddenError("접근 권한이 없습니다");
    case "PGRST116": // not found (single row)
      return new NotFoundError("Resource");
    default:
      return new AppError("DB_ERROR", error.message, 500);
  }
}
```

---

## Logging

```typescript
// lib/logger.ts
type LogLevel = "info" | "warn" | "error";

function log(level: LogLevel, message: string, context?: Record<string, unknown>) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...context,
  };

  if (level === "error") {
    console.error(JSON.stringify(entry));
  } else if (level === "warn") {
    console.warn(JSON.stringify(entry));
  } else {
    console.log(JSON.stringify(entry));
  }
}

export const logger = {
  info: (msg: string, ctx?: Record<string, unknown>) => log("info", msg, ctx),
  warn: (msg: string, ctx?: Record<string, unknown>) => log("warn", msg, ctx),
  error: (msg: string, ctx?: Record<string, unknown>) => log("error", msg, ctx),
};
```
