<!-- epcc-seam: nextjs+supabase/backend v3.12.0 -->
# 서버 클라이언트 — 요청 단위 · 쿠키 결합

> `supabase` 축 팩의 `database-patterns.md`에서 분리됐다. 클라이언트를 **어떻게**
> 만드는가는 호스트 런타임(쿠키 접근 방식)의 함수이므로 이음매가 소유한다.

## Server client — per-request, cookie-bound

```ts
// lib/supabase/server.ts
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { publicEnv } from '@/lib/env.public'   // NOT lib/env.ts — that one is server-only
import type { Database } from '@/types/database'

export async function createClient() {
  const cookieStore = await cookies() // async in Next.js 15

  return createServerClient<Database>(
    publicEnv.NEXT_PUBLIC_SUPABASE_URL,
    publicEnv.NEXT_PUBLIC_SUPABASE_ANON_KEY,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            )
          } catch {
            // Called from a Server Component (cookies are read-only there).
            // Safe to ignore because middleware refreshes the session.
          }
        },
      },
    },
  )
}
```

Call `await createClient()` inside every handler/action — never at module scope. (Newer
Supabase projects may name the keys publishable/secret; the pattern is identical.) The URL
and anon key come from `lib/env.public.ts`, not the `server-only` `lib/env.ts`, because
client-creation modules also sit in browser graphs (`resources/validation-and-errors.md`).

