# API Route Handlers

## Route Handler Basics

Next.js App Router의 Route Handler는 `app/api/` 디렉토리에 `route.ts` 파일로 정의한다.

### 파일 구조

```
app/api/
├── users/
│   ├── route.ts            # GET (목록), POST (생성)
│   └── [id]/
│       └── route.ts        # GET (상세), PUT (수정), DELETE (삭제)
├── posts/
│   ├── route.ts
│   └── [id]/
│       └── route.ts
└── webhooks/
    └── payment/
        └── route.ts        # POST (외부 웹훅)
```

### 기본 패턴

```typescript
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { z } from "zod";

// GET /api/users
export async function GET(request: NextRequest) {
  try {
    const supabase = await createClient();
    const { searchParams } = request.nextUrl;
    const page = Number(searchParams.get("page") ?? "1");
    const limit = Number(searchParams.get("limit") ?? "10");
    const offset = (page - 1) * limit;

    const { data, error, count } = await supabase
      .from("users")
      .select("*", { count: "exact" })
      .range(offset, offset + limit - 1)
      .order("created_at", { ascending: false });

    if (error) {
      return NextResponse.json({ error: error.message }, { status: 500 });
    }

    return NextResponse.json({ data, total: count, page, limit });
  } catch (error) {
    return NextResponse.json(
      { error: "Internal Server Error" },
      { status: 500 }
    );
  }
}

// POST /api/users
export async function POST(request: NextRequest) {
  try {
    const supabase = await createClient();
    const body = await request.json();

    const schema = z.object({
      email: z.string().email(),
      name: z.string().min(1).max(100),
    });
    const validated = schema.parse(body);

    const { data, error } = await supabase
      .from("users")
      .insert(validated)
      .select()
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
// app/api/users/[id]/route.ts
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

interface RouteParams {
  params: Promise<{ id: string }>;
}

// GET /api/users/:id
export async function GET(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  const supabase = await createClient();

  const { data, error } = await supabase
    .from("users")
    .select("*")
    .eq("id", id)
    .single();

  if (error || !data) {
    return NextResponse.json({ error: "Not Found" }, { status: 404 });
  }

  return NextResponse.json(data);
}

// PUT /api/users/:id
export async function PUT(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  const supabase = await createClient();
  const body = await request.json();

  const { data, error } = await supabase
    .from("users")
    .update(body)
    .eq("id", id)
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return NextResponse.json(data);
}

// DELETE /api/users/:id
export async function DELETE(request: NextRequest, { params }: RouteParams) {
  const { id } = await params;
  const supabase = await createClient();

  const { error } = await supabase.from("users").delete().eq("id", id);

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 400 });
  }

  return new NextResponse(null, { status: 204 });
}
```

---

## Response Helpers

일관된 응답 형식을 위한 헬퍼 함수:

```typescript
// lib/api/response.ts
import { NextResponse } from "next/server";

export function successResponse<T>(data: T, status = 200) {
  return NextResponse.json(data, { status });
}

export function errorResponse(message: string, status = 500) {
  return NextResponse.json({ error: message }, { status });
}

export function validationErrorResponse(errors: z.ZodError) {
  return NextResponse.json(
    {
      error: "Validation Error",
      details: errors.errors.map((e) => ({
        field: e.path.join("."),
        message: e.message,
      })),
    },
    { status: 400 }
  );
}
```

---

## Authentication in Route Handlers

```typescript
export async function GET(request: NextRequest) {
  const supabase = await createClient();

  const {
    data: { user },
    error: authError,
  } = await supabase.auth.getUser();

  if (authError || !user) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  // user.id를 활용한 쿼리 (RLS가 자동 적용됨)
  const { data } = await supabase.from("profiles").select("*");

  return NextResponse.json(data);
}
```

---

## CORS & Headers

```typescript
// 특정 Route Handler에서 CORS 설정
export async function GET(request: NextRequest) {
  const data = { message: "Hello" };

  return NextResponse.json(data, {
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    },
  });
}

// OPTIONS preflight
export async function OPTIONS() {
  return new NextResponse(null, {
    status: 204,
    headers: {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization",
    },
  });
}
```

---

## Webhook Handling

```typescript
// app/api/webhooks/payment/route.ts
import { NextRequest, NextResponse } from "next/server";
import { headers } from "next/headers";

export async function POST(request: NextRequest) {
  const body = await request.text();
  const headersList = await headers();
  const signature = headersList.get("x-webhook-signature");

  // 서명 검증
  if (!verifySignature(body, signature)) {
    return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
  }

  const payload = JSON.parse(body);

  // 웹훅 처리 로직
  await processWebhook(payload);

  return NextResponse.json({ received: true });
}
```

---

## Anti-Patterns

```typescript
// bad: Route Handler에 비즈니스 로직 직접 작성
export async function POST(request: NextRequest) {
  const body = await request.json();
  // 100줄의 비즈니스 로직, 여러 DB 쿼리, 외부 API 호출...
}

// bad: 에러 처리 누락
export async function GET() {
  const supabase = await createClient();
  const { data } = await supabase.from("users").select("*");
  return NextResponse.json(data); // error 체크 안함
}

// bad: 입력 검증 없이 사용
export async function PUT(request: NextRequest) {
  const body = await request.json();
  await supabase.from("users").update(body); // 검증 없이 직접 사용
}
```
