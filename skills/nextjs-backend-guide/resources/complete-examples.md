# Complete Examples

## Example 1: Full CRUD Route Handler

### Route Handler

```typescript
// app/api/posts/route.ts
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { z } from "zod";

const createPostSchema = z.object({
  title: z.string().min(1, "제목은 필수입니다").max(200),
  content: z.string().min(1, "내용은 필수입니다"),
  tags: z.array(z.string()).optional().default([]),
  published: z.boolean().optional().default(false),
});

const querySchema = z.object({
  page: z.coerce.number().int().positive().default(1),
  limit: z.coerce.number().int().min(1).max(100).default(10),
  sort: z.enum(["newest", "oldest"]).default("newest"),
  q: z.string().optional(),
});

export async function GET(request: NextRequest) {
  try {
    const supabase = await createClient();
    const params = Object.fromEntries(request.nextUrl.searchParams);
    const { page, limit, sort, q } = querySchema.parse(params);
    const offset = (page - 1) * limit;

    let query = supabase
      .from("posts")
      .select("id, title, created_at, author:profiles(name, avatar_url)", {
        count: "exact",
      })
      .eq("published", true);

    if (q) {
      query = query.ilike("title", `%${q}%`);
    }

    query = query.order("created_at", {
      ascending: sort === "oldest",
    });

    const { data, error, count } = await query.range(
      offset,
      offset + limit - 1
    );

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({
      data,
      total: count,
      page,
      limit,
      totalPages: Math.ceil((count ?? 0) / limit),
    });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors }, { status: 400 });
    }
    return NextResponse.json(
      { error: "Internal Server Error" },
      { status: 500 }
    );
  }
}

export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();

    const {
      data: { user },
    } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
    }

    const body = await request.json();
    const validated = createPostSchema.parse(body);

    const { data, error } = await supabase
      .from("posts")
      .insert({ ...validated, author_id: user.id })
      .select("id, title, created_at")
      .single();

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json(data, { status: 201 });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json({ error: error.errors }, { status: 400 });
    }
    return NextResponse.json(
      { error: "Internal Server Error" },
      { status: 500 }
    );
  }
}
```

### Dynamic Route

```typescript
// app/api/posts/[id]/route.ts
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { z } from "zod";

interface RouteParams {
  params: Promise<{ id: string }>;
}

const updatePostSchema = z.object({
  title: z.string().min(1).max(200).optional(),
  content: z.string().min(1).optional(),
  tags: z.array(z.string()).optional(),
  published: z.boolean().optional(),
});

export async function GET(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("posts")
    .select(`
      *,
      author:profiles(id, name, avatar_url),
      comments(id, content, created_at, user:profiles(name))
    `)
    .eq("id", id)
    .single();

  if (error || !data) {
    return NextResponse.json({ error: "Not Found" }, { status: 404 });
  }

  return NextResponse.json(data);
}

export async function PUT(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const body = await request.json();
  const validated = updatePostSchema.parse(body);

  const { data, error } = await supabase
    .from("posts")
    .update({ ...validated, updated_at: new Date().toISOString() })
    .eq("id", id)
    .eq("author_id", user.id) // 본인 글만 수정 가능
    .select()
    .single();

  if (error || !data) {
    return NextResponse.json(
      { error: "Not found or unauthorized" },
      { status: 404 }
    );
  }

  return NextResponse.json(data);
}

export async function DELETE(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { error } = await supabase
    .from("posts")
    .delete()
    .eq("id", id)
    .eq("author_id", user.id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return new NextResponse(null, { status: 204 });
}
```

---

## Example 2: Server Action with Form

### Server Action

```typescript
// lib/actions/post.ts
"use server";

import { createClient } from "@/lib/supabase/server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";

type ActionResult<T = void> =
  | { success: true; data?: T }
  | { success: false; error: string; fieldErrors?: Record<string, string[]> };

const createPostSchema = z.object({
  title: z.string().min(1, "제목을 입력하세요").max(200),
  content: z.string().min(1, "내용을 입력하세요"),
  published: z.preprocess((val) => val === "on", z.boolean().default(false)),
});

export async function createPost(
  formData: FormData
): Promise<ActionResult<{ id: string }>> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { success: false, error: "로그인이 필요합니다" };
  }

  const result = createPostSchema.safeParse({
    title: formData.get("title"),
    content: formData.get("content"),
    published: formData.get("published"),
  });

  if (!result.success) {
    return {
      success: false,
      error: "입력값을 확인해주세요",
      fieldErrors: result.error.flatten().fieldErrors,
    };
  }

  const { data, error } = await supabase
    .from("posts")
    .insert({ ...result.data, author_id: user.id })
    .select("id")
    .single();

  if (error) {
    return { success: false, error: "게시글 생성에 실패했습니다" };
  }

  revalidatePath("/posts");
  redirect(`/posts/${data.id}`);
}

export async function deletePost(postId: string): Promise<ActionResult> {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) {
    return { success: false, error: "로그인이 필요합니다" };
  }

  const { error } = await supabase
    .from("posts")
    .delete()
    .eq("id", postId)
    .eq("author_id", user.id);

  if (error) {
    return { success: false, error: "삭제에 실패했습니다" };
  }

  revalidatePath("/posts");
  return { success: true };
}
```

### Server Component (Page)

```typescript
// app/posts/new/page.tsx
import { createPost } from "@/lib/actions/post";

export default function NewPostPage() {
  return (
    <div className="max-w-2xl mx-auto p-6">
      <h1 className="text-2xl font-bold mb-6">새 게시글</h1>
      <form action={createPost} className="space-y-4">
        <div>
          <label htmlFor="title" className="block text-sm font-medium mb-1">
            제목
          </label>
          <input
            id="title"
            name="title"
            required
            className="w-full border rounded-md px-3 py-2"
          />
        </div>
        <div>
          <label htmlFor="content" className="block text-sm font-medium mb-1">
            내용
          </label>
          <textarea
            id="content"
            name="content"
            rows={10}
            required
            className="w-full border rounded-md px-3 py-2"
          />
        </div>
        <div className="flex items-center gap-2">
          <input type="checkbox" id="published" name="published" />
          <label htmlFor="published">바로 공개</label>
        </div>
        <button
          type="submit"
          className="bg-primary text-primary-foreground px-4 py-2 rounded-md"
        >
          게시
        </button>
      </form>
    </div>
  );
}
```

---

## Example 3: Middleware + Auth Flow

```typescript
// src/middleware.ts
import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

const PROTECTED_ROUTES = ["/my", "/settings", "/posts/new"];
const AUTH_ROUTES = ["/login", "/signup"];

export async function middleware(request: NextRequest) {
  const response = await updateSession(request);
  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
```

```typescript
// lib/supabase/middleware.ts
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

const PROTECTED_ROUTES = ["/my", "/settings", "/posts/new"];
const AUTH_ROUTES = ["/login", "/signup"];

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          supabaseResponse = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { pathname } = request.nextUrl;

  // 보호된 경로: 미인증 시 로그인 페이지로
  if (PROTECTED_ROUTES.some((route) => pathname.startsWith(route)) && !user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("redirect", pathname);
    return NextResponse.redirect(url);
  }

  // 인증 경로: 이미 로그인한 경우 홈으로
  if (AUTH_ROUTES.some((route) => pathname.startsWith(route)) && user) {
    return NextResponse.redirect(new URL("/", request.url));
  }

  return supabaseResponse;
}
```
