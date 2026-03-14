# Middleware Guide

## Next.js Middleware

Next.js 미들웨어는 `src/middleware.ts`에 정의하며, 모든 요청 전 Edge Runtime에서 실행된다.

---

## 기본 구조

```typescript
// src/middleware.ts
import { type NextRequest, NextResponse } from "next/server";
import { updateSession } from "@/lib/supabase/middleware";

export async function middleware(request: NextRequest) {
  return await updateSession(request);
}

export const config = {
  matcher: [
    /*
     * Match all request paths except:
     * - _next/static (static files)
     * - _next/image (image optimization)
     * - favicon.ico
     * - public files (images, etc.)
     */
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
```

---

## Supabase Auth Middleware

```typescript
// lib/supabase/middleware.ts
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

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
          cookiesToSet.forEach(({ name, value, options }) =>
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

  // 세션 갱신 (중요: getUser()를 호출해야 쿠키가 갱신됨)
  const {
    data: { user },
  } = await supabase.auth.getUser();

  // 보호된 경로 접근 시 인증 체크
  const isProtectedRoute = request.nextUrl.pathname.startsWith("/my");
  const isAuthRoute =
    request.nextUrl.pathname.startsWith("/login") ||
    request.nextUrl.pathname.startsWith("/signup");

  if (isProtectedRoute && !user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    url.searchParams.set("redirect", request.nextUrl.pathname);
    return NextResponse.redirect(url);
  }

  if (isAuthRoute && user) {
    const url = request.nextUrl.clone();
    url.pathname = "/";
    return NextResponse.redirect(url);
  }

  return supabaseResponse;
}
```

---

## Route Protection Patterns

### 경로 그룹별 보호

```typescript
const protectedRoutes = ["/my", "/settings", "/admin"];
const authRoutes = ["/login", "/signup", "/forgot-password"];
const publicRoutes = ["/", "/deals", "/search"];

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  // Supabase 세션 갱신
  const response = await updateSession(request);

  // 추가 보호 로직이 필요한 경우
  const supabase = createMiddlewareClient(request, response);
  const { data: { user } } = await supabase.auth.getUser();

  // Admin 경로 보호
  if (pathname.startsWith("/admin")) {
    if (!user) {
      return NextResponse.redirect(new URL("/login", request.url));
    }
    // 관리자 권한 체크 (메타데이터 활용)
    const isAdmin = user.user_metadata?.role === "admin";
    if (!isAdmin) {
      return NextResponse.redirect(new URL("/", request.url));
    }
  }

  return response;
}
```

---

## Header Manipulation

```typescript
export async function middleware(request: NextRequest) {
  const response = NextResponse.next();

  // 보안 헤더 추가
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("Referrer-Policy", "origin-when-cross-origin");

  // 커스텀 헤더
  response.headers.set("X-Request-Id", crypto.randomUUID());

  return response;
}
```

---

## Rate Limiting (간단한 구현)

```typescript
const rateLimitMap = new Map<string, { count: number; timestamp: number }>();

function isRateLimited(ip: string, limit = 100, windowMs = 60000): boolean {
  const now = Date.now();
  const record = rateLimitMap.get(ip);

  if (!record || now - record.timestamp > windowMs) {
    rateLimitMap.set(ip, { count: 1, timestamp: now });
    return false;
  }

  record.count++;
  return record.count > limit;
}

export async function middleware(request: NextRequest) {
  // API 경로에만 rate limiting 적용
  if (request.nextUrl.pathname.startsWith("/api")) {
    const ip = request.headers.get("x-forwarded-for") ?? "anonymous";

    if (isRateLimited(ip)) {
      return NextResponse.json(
        { error: "Too Many Requests" },
        { status: 429 }
      );
    }
  }

  return NextResponse.next();
}
```

**참고**: 프로덕션에서는 Vercel의 Rate Limiting이나 외부 서비스(Upstash 등)를 사용하는 것이 좋다.

---

## Matcher Configuration

```typescript
export const config = {
  matcher: [
    // 특정 경로만 매칭
    "/api/:path*",
    "/my/:path*",
    "/admin/:path*",

    // 정적 파일 제외하고 모든 경로
    "/((?!_next/static|_next/image|favicon.ico).*)",
  ],
};
```

---

## Anti-Patterns

```typescript
// bad: 미들웨어에서 무거운 작업 수행 (Edge Runtime 제한)
export async function middleware(request: NextRequest) {
  // DB 직접 연결 불가 (Edge Runtime에서는 Supabase REST API만 가능)
  const prisma = new PrismaClient(); // 동작하지 않음
}

// bad: 모든 경로에서 인증 체크 (정적 파일 포함)
export async function middleware(request: NextRequest) {
  const user = await getUser(); // matcher 미설정으로 불필요한 체크
}

// bad: 미들웨어에서 복잡한 비즈니스 로직
export async function middleware(request: NextRequest) {
  // 미들웨어는 라우팅/리다이렉트/헤더 조작만 담당
  // 비즈니스 로직은 Route Handler나 Server Action에서 처리
}
```
