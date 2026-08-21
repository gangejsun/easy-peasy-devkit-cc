# Auth & Middleware Boundaries

Where identity is verified, where authorization is decided, and where it is enforced.

## The three defense layers

| Layer | Job | What it must NOT do |
| --- | --- | --- |
| 1. Middleware | refresh the session token; redirect signed-out visitors from protected pages | decide per-resource permissions |
| 2. Handler / Action | `getUser()` + app-level authorization + ownership rules | trust `getSession()` or client-sent ids |
| 3. Postgres RLS | enforce row access even when layers 1–2 have bugs | be the only check (empty results make bad UX) |

Middleware redirects are **UX**, handler checks are **authorization**, RLS is
**enforcement**. All three exist at once; removing any one is a finding.

## Middleware — session refresh

Server Components can't write cookies, so refreshed tokens must be persisted by
middleware on every matched request:

```ts
// middleware.ts
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
// lib/supabase/middleware.ts
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
            supabaseResponse.cookies.set(name, value, options),
          )
        },
      },
    },
  )

  // Do NOT run other code between createServerClient and getUser() —
  // getUser() is the call that refreshes an expired token.
  const { data: { user } } = await supabase.auth.getUser()

  const isPublic =
    request.nextUrl.pathname.startsWith('/login') ||
    request.nextUrl.pathname.startsWith('/auth')
  if (!user && !isPublic) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    // Preserve the blocked path so sign-in can return the user (consumed in the
    // sign-in action below — which validates it against open redirects)
    url.searchParams.set('redirect', request.nextUrl.pathname)
    return NextResponse.redirect(url)
  }

  // Return supabaseResponse as-is. If you must build a new response, copy
  // supabaseResponse.cookies onto it — dropping them logs users out randomly.
  return supabaseResponse
}
```

## Auth flow — sign-in / sign-up / sign-out

Auth mutations are Server Actions. Return **generic** failure messages — Supabase Auth's
`error.message` can leak account state (e.g. whether an email is registered).

```ts
// app/(auth)/login/actions.ts
'use server'

import { z } from 'zod'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import type { ActionResult } from '@/lib/api/types'

const signInSchema = z.object({
  email: z.email(),
  password: z.string().min(1),
  redirect: z.string().optional(), // saved by middleware, relayed via a hidden input
})

export async function signIn(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const parsed = signInSchema.safeParse({
    email: formData.get('email'),
    password: formData.get('password'),
    redirect: formData.get('redirect') ?? undefined,
  })
  if (!parsed.success) {
    return { ok: false, fieldErrors: z.flattenError(parsed.error).fieldErrors }
  }

  const supabase = await createClient()
  const { error } = await supabase.auth.signInWithPassword({
    email: parsed.data.email,
    password: parsed.data.password,
  })
  if (error) return { ok: false, formError: 'Invalid email or password' } // generic on purpose

  // Open-redirect guard: internal paths only — '//evil.com' and '/\evil.com' both
  // parse as external URLs in browsers, so reject anything but a plain '/path'
  const to = parsed.data.redirect
  const safe = to !== undefined && to.startsWith('/')
    && !to.startsWith('//') && !to.startsWith('/\\')
  redirect(safe ? to : '/')
}
```

- **Return path:** middleware stored the blocked path in `?redirect=` (see above); the
  login page copies it into a hidden `<input name="redirect">`, and the action consumes
  it — the internal-path check above is what prevents an open redirect.
- `signUp` follows the same shape via `supabase.auth.signUp`, then redirects to a
  "verify your email" page. Keep profile fields in a `profiles` row — not in
  `user_metadata` (user-editable, see the roles table below).
- `signOut` is a plain form action: `await supabase.auth.signOut()`, then
  `redirect('/login')`.
- **Client `onAuthStateChange`** is needed only when a Client Component must react to
  session changes it did not cause (sign-out in another tab, token expiry mid-session):
  the listener calls `router.refresh()` so Server Components re-render. It is a UI
  freshness tool, never an authorization mechanism.

## getUser() vs getSession() (the rule, in full)

- `getSession()` returns the session **from the cookie as-is** — it does attempt a
  refresh when the token is expired, but the server never verifies the cookie's claims,
  so a tampered or forged payload passes. Acceptable only as a UI hint on the client.
- `getUser()` sends the JWT to the Auth server for verification and refresh. It is the
  **only** acceptable identity check in middleware, Route Handlers, Server Actions,
  and Server Components.
- Check identity **in the handler/action itself**, even for routes the middleware
  already gates — middleware matchers drift, and Server Actions bypass page routing.

## Authorization patterns

**Ownership** — set and check on the server; RLS backs it up:

```ts
const { data: { user } } = await supabase.auth.getUser()
if (!user) return fail(401, 'unauthenticated', 'Sign in required')

// Ownership columns come from the verified user, never from the request body
await supabase.from('notes').insert({ ...parsed.data, user_id: user.id })
```

**Roles** — two safe sources, one forbidden source:

| Source | Safe? | Why |
| --- | --- | --- |
| `profiles.role` column (read via DB) | yes | server-controlled, RLS-protected |
| `user.app_metadata.role` | yes | writable only via service role / Auth admin |
| `user.user_metadata.*` | **never** | end-user editable via `updateUser()` |

```ts
const { data: profile } = await supabase
  .from('profiles').select('role').eq('id', user.id).single()
if (profile?.role !== 'admin') return fail(403, 'forbidden', 'Not allowed')
```

## RLS policies — the enforcement layer

Every table gets RLS enabled in the same migration that creates it. A table without
RLS is readable and writable by anyone holding the anon key.

```sql
alter table notes enable row level security;

-- Per-operation policies; wrap auth.uid() in (select ...) so Postgres caches it
create policy "notes_select_own" on notes for select
  using ((select auth.uid()) = user_id);

create policy "notes_insert_own" on notes for insert
  with check ((select auth.uid()) = user_id);

create policy "notes_update_own" on notes for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "notes_delete_own" on notes for delete
  using ((select auth.uid()) = user_id);
```

- `using` filters which rows an operation may touch; `with check` validates the row
  being written. `update` needs both.
- Public-read tables get an explicit `for select using (true)` policy — "public" is a
  decision recorded in a policy, not the absence of one.
- RLS silently filters reads (no error). Writes that violate a policy fail with
  `42501` → map to 403 (`resources/validation-and-errors.md`).
- Test policies with signed-in test users (`resources/testing.md`), not by eyeballing.

## Service-role admin client — the escape hatch

```ts
// lib/supabase/admin.ts
import { createClient } from '@supabase/supabase-js'
import type { Database } from '@/types/database'

// Server-only. Bypasses RLS entirely. No cookies, no user context.
export function createAdminClient() {
  return createClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!, // never NEXT_PUBLIC_*
    { auth: { autoRefreshToken: false, persistSession: false } },
  )
}
```

Rules:

- Allowed call sites: webhook handlers, cron/queued jobs, explicit admin endpoints
  that have **already** verified an admin role via layer 2.
- Never as a convenience to "make RLS stop blocking me" — that is a policy bug to fix.
- Inputs are still validated with Zod; RLS is gone, so app-level checks are the only
  guard left on this path.
- The key lives only in server env (`SUPABASE_SERVICE_ROLE_KEY`); importing
  `lib/supabase/admin.ts` from any client component is a security incident.

## Server Actions are public endpoints

Every exported Server Action is an HTTP endpoint callable by anyone with the request
shape — the surrounding page's auth guard does not protect it.

- `getUser()` + authorization **inside every action**, no exceptions.
- Never branch security on hidden form fields or `prevState` — both are client input.
- Ownership ids come from `user.id`, never from `formData`.
