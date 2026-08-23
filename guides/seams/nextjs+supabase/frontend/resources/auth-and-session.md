<!-- epcc-seam: nextjs+supabase/frontend v3.12.0 -->
# 인증과 세션 — 보호 라우트 · 미들웨어 세션 갱신

> 이 파일은 `nextjs` 축 팩의 `routing.md` §6에서 분리됐다. 라우팅 메커니즘은 축이지만
> **인증 주체가 누구인가**는 백엔드 축의 함수이므로 이음매가 소유한다.


3중 방어: **미들웨어(1차 게이트) → 페이지 재확인 → RLS(최종 방어선, backend-guide)**.

```ts
// middleware.ts (프로젝트 루트)
import { type NextRequest } from 'next/server'
import { updateSession } from '@/lib/supabase/middleware'

export async function middleware(request: NextRequest) {
  return await updateSession(request)
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
```

```ts
// lib/supabase/middleware.ts — 세션 갱신 + 미로그인 리다이렉트
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // 중요: createServerClient와 getUser() 사이에 다른 로직을 넣지 않는다
  const { data: { user } } = await supabase.auth.getUser()

  const isPublic =
    request.nextUrl.pathname.startsWith('/login') ||
    request.nextUrl.pathname.startsWith('/auth')

  if (!user && !isPublic) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    return NextResponse.redirect(url)
  }

  return supabaseResponse                    // 반드시 이 응답 객체를 그대로 반환
}
```

```tsx
// app/(main)/tasks/page.tsx — 보호 페이지에서의 재확인 (미들웨어만 믿지 않는다)
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function TasksPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  // …
}
```

규칙:

- 사용자 확인은 **항상 `getUser()`** — 서버에서 `getSession()`의 사용자 정보는 신뢰하지 않는다
- 미들웨어의 `supabaseResponse`를 가공 없이 반환한다 — 쿠키가 유실되면 세션이 끊긴다
- 로그인/콜백 경로는 리다이렉트 대상에서 제외한다 (무한 루프 방지)


## 서버에서 현재 사용자 읽기

`nextjs` 축 팩의 `routing.md`·`typescript-standards.md`가 이 두 심볼을 소비한다. 팩은
데이터 클라이언트를 직접 알지 않으므로 **인증 계층의 정의는 이음매가 소유한다** — 백엔드
축을 바꾸면 이 파일만 바뀌고 팩은 그대로다.

```ts
// lib/auth.ts
import { createClient } from '@/lib/supabase/server'

export type AuthUser = { id: string; email: string | null }

/** Server Component·Route Handler·Server Action에서 쓴다. 세션이 없으면 null. */
export async function getCurrentUser(): Promise<AuthUser | null> {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()   // getSession() 아님 — 서버는 항상 getUser()
  return user ? { id: user.id, email: user.email ?? null } : null
}
```

`getSession()`은 쿠키를 그대로 신뢰하므로 서버에서 쓰지 않는다 — `getUser()`가 발급자에
검증을 요청한다 (backend-guide의 인증 경계 절과 같은 규칙이다).
