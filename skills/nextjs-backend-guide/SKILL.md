---
name: nextjs-backend-guide
description: |
  [Preset: nextjs-supabase] Next.js App Router backend development guide. Covers API Route Handlers, Server Actions, Supabase data access, Zod validation, middleware, and error handling patterns. Use when creating or modifying Route Handlers, Server Actions, Supabase queries, input validation, middleware, backend testing, or any server-side logic.
  Use ONLY when the active preset matches.
---

# Backend Development Guidelines

Next.js App Router 기반 백엔드 개발 가이드. API Route Handler, Server Action, Supabase 데이터 접근 패턴을 다룬다.

## Quick Start

### New Route Handler Checklist

- [ ] `app/api/{resource}/route.ts` 생성
- [ ] NextRequest/NextResponse 패턴 사용
- [ ] Zod 스키마로 입력 검증
- [ ] Supabase 서버 클라이언트로 데이터 접근
- [ ] 에러 처리 (try-catch + 적절한 HTTP 상태코드)
- [ ] RLS 정책 확인
- [ ] 테스트 작성

### New Server Action Checklist

- [ ] `"use server"` 선언
- [ ] Zod 스키마로 입력 검증
- [ ] Supabase 서버 클라이언트 사용
- [ ] `revalidatePath`/`revalidateTag`로 캐시 갱신
- [ ] 에러 시 적절한 반환값 (throw 대신 결과 객체)
- [ ] 테스트 작성

---

## Architecture Overview

```
HTTP Request
    |
Next.js Middleware (auth, redirect)
    |
    +-- Route Handler (app/api/)     -- REST API, 외부 연동
    |       |
    |   Service Logic (lib/)
    |       |
    |   Supabase Client
    |
    +-- Server Action ("use server") -- Form mutation, 데이터 변경
            |
        Service Logic (lib/)
            |
        Supabase Client
```

**핵심**: Route Handler는 외부 API 제공 시, Server Action은 UI에서 직접 호출하는 데이터 변경 시 사용.

See [resources/architecture-overview.md](resources/architecture-overview.md)

---

## Directory Structure

```
src/
├── app/
│   └── api/                # Route Handlers
│       ├── users/
│       │   └── route.ts    # GET, POST
│       └── users/[id]/
│           └── route.ts    # GET, PUT, DELETE
├── lib/
│   ├── supabase/
│   │   ├── client.ts       # 브라우저용 클라이언트
│   │   ├── server.ts       # 서버용 클라이언트
│   │   └── admin.ts        # Service Role 클라이언트 (관리자)
│   └── actions/            # Server Actions
│       ├── user.ts
│       └── post.ts
├── types/                  # 공유 타입
└── constants/              # 상수
```

---

## Core Principles (7 Key Rules)

### 1. Route Handler는 라우팅만, 로직은 분리

```typescript
// bad: Route Handler에 비즈니스 로직
export async function POST(request: NextRequest) {
  const body = await request.json();
  // 200줄의 로직...
}

// good: 서비스 함수로 분리
export async function POST(request: NextRequest) {
  const body = await request.json();
  const result = await createUser(body);
  return NextResponse.json(result, { status: 201 });
}
```

### 2. Server Action 우선 (UI 데이터 변경)

```typescript
// good: form mutation은 Server Action
"use server";

export async function updateProfile(formData: FormData) {
  const name = formData.get("name") as string;
  // ...
}
```

### 3. Supabase Client 서버/클라이언트 구분

```typescript
// Server Component / Route Handler / Server Action
import { createClient } from "@/lib/supabase/server";

// Client Component
import { createClient } from "@/lib/supabase/client";
```

### 4. Zod로 모든 입력 검증

```typescript
import { z } from "zod";

const createUserSchema = z.object({
  email: z.string().email(),
  name: z.string().min(1).max(100),
});
```

### 5. RLS 활용 + 서버 사이드 보안

Supabase RLS 정책으로 행 단위 접근 제어. 서버 클라이언트는 인증된 사용자 컨텍스트를 자동 전달.

### 6. 에러 처리 일관성

```typescript
// Route Handler
try {
  const data = schema.parse(body);
  const result = await service(data);
  return NextResponse.json(result);
} catch (error) {
  if (error instanceof z.ZodError) {
    return NextResponse.json({ error: error.errors }, { status: 400 });
  }
  return NextResponse.json({ error: "Internal Server Error" }, { status: 500 });
}
```

### 7. 테스트 필수

Route Handler, Server Action, 서비스 로직 모두 테스트 작성.

---

## Common Imports

```typescript
// Next.js
import { NextRequest, NextResponse } from "next/server";
import { revalidatePath, revalidateTag } from "next/cache";
import { cookies } from "next/headers";
import { redirect } from "next/navigation";

// Supabase
import { createClient } from "@/lib/supabase/server";

// Validation
import { z } from "zod";
```

---

## HTTP Status Codes

| Code | Use Case |
|------|----------|
| 200 | Success |
| 201 | Created |
| 204 | No Content (DELETE 성공) |
| 400 | Bad Request (검증 실패) |
| 401 | Unauthorized (미인증) |
| 403 | Forbidden (권한 없음) |
| 404 | Not Found |
| 409 | Conflict (중복) |
| 500 | Server Error |

---

## Anti-Patterns

- Route Handler에 비즈니스 로직 200줄
- `any` 타입 사용
- Zod 검증 없이 입력 사용
- 클라이언트 컴포넌트에서 서버 Supabase 클라이언트 사용
- try-catch 없는 async 코드
- RLS 미설정 상태로 데이터 접근
- `process.env` 직접 접근 (env 검증 없이)

---

## Navigation Guide

| Need to... | Read this |
|------------|-----------|
| Understand architecture | [architecture-overview.md](resources/architecture-overview.md) |
| Create Route Handlers | [api-routes.md](resources/api-routes.md) |
| Create Server Actions | [server-actions.md](resources/server-actions.md) |
| Use Supabase | [supabase-patterns.md](resources/supabase-patterns.md) |
| Validate input | [validation-patterns.md](resources/validation-patterns.md) |
| Create middleware | [middleware-guide.md](resources/middleware-guide.md) |
| Handle errors | [error-handling.md](resources/error-handling.md) |
| Database access | [database-patterns.md](resources/database-patterns.md) |
| Write tests | [testing-guide.md](resources/testing-guide.md) |
| See full examples | [complete-examples.md](resources/complete-examples.md) |
