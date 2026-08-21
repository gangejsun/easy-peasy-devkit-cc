# Backend Testing

Tooling: **Vitest** for unit/handler/action tests, the **Supabase CLI local stack**
for integration and RLS tests.

## Setup

```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config'
import path from 'node:path'

export default defineConfig({
  test: { environment: 'node' }, // backend tests run in node, not jsdom
  resolve: { alias: { '@': path.resolve(__dirname, '.') } },
})
```

Test files live next to the code (`route.test.ts`, `actions.test.ts`) or under
`tests/` mirroring the source tree — follow the project's existing convention.

## Layer 1 — Zod schemas (pure, no mocks)

The cheapest tests with the highest defect yield. Cover: valid input, each rule's
failure, defaults, and trimming.

```ts
import { describe, expect, it } from 'vitest'
import { createNoteSchema } from '@/lib/validations/note'

describe('createNoteSchema', () => {
  it('accepts a valid payload and applies defaults', () => {
    const result = createNoteSchema.safeParse({ title: 'Hello' })
    expect(result.success).toBe(true)
    if (result.success) {
      expect(result.data.content).toBe('')
      expect(result.data.tags).toEqual([])
    }
  })

  it('rejects a whitespace-only title', () => {
    expect(createNoteSchema.safeParse({ title: '   ' }).success).toBe(false)
  })

  it('rejects a title over 200 chars', () => {
    expect(createNoteSchema.safeParse({ title: 'x'.repeat(201) }).success).toBe(false)
  })
})
```

## Layer 2 — Route Handlers with a mocked Supabase client

Import the exported `GET`/`POST` and call them with a real `NextRequest`. Mock only
the module boundary: `@/lib/supabase/server`.

**This is the canonical `queryResult` helper.** Define it once in a shared test helper
(`tests/helpers/supabase.ts`) and import it everywhere — a per-file copy that omits a
builder method breaks the moment a handler chains that method.

```ts
// tests/helpers/supabase.ts
import { vi } from 'vitest'

// Chainable, thenable builder mock — awaiting any chain resolves to `result`
export function queryResult(result: { data?: unknown; error?: unknown; count?: number }) {
  const builder: Record<string, unknown> = {}
  const methods = ['select', 'insert', 'update', 'upsert', 'delete', 'eq', 'neq', 'in', 'is',
    'ilike', 'or', 'order', 'range', 'limit', 'single', 'maybeSingle']
  for (const m of methods) builder[m] = vi.fn(() => builder)
  ;(builder as { then?: unknown }).then = (resolve: (v: unknown) => void) =>
    resolve({ data: null, error: null, count: null, ...result })
  return builder
}
```

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { NextRequest } from 'next/server'
import { queryResult } from '@/tests/helpers/supabase'

const { mockClient } = vi.hoisted(() => ({
  mockClient: { auth: { getUser: vi.fn() }, from: vi.fn() },
}))

vi.mock('@/lib/supabase/server', () => ({
  createClient: vi.fn(async () => mockClient),
}))

import { POST } from '@/app/api/notes/route'

const post = (body: unknown) =>
  POST(new NextRequest('http://test/api/notes', { method: 'POST', body: JSON.stringify(body) }))

describe('POST /api/notes', () => {
  beforeEach(() => vi.clearAllMocks())

  it('returns 400 for an invalid body (before auth or DB work)', async () => {
    const res = await post({ title: '' })
    expect(res.status).toBe(400)
    expect(mockClient.auth.getUser).not.toHaveBeenCalled()
  })

  it('returns 401 without a verified user', async () => {
    mockClient.auth.getUser.mockResolvedValue({ data: { user: null }, error: null })
    const res = await post({ title: 'Hi' })
    expect(res.status).toBe(401)
  })

  it('creates a note for a signed-in user', async () => {
    mockClient.auth.getUser.mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null })
    mockClient.from.mockReturnValue(queryResult({ data: { id: 'n1', title: 'Hi' } }))
    const res = await post({ title: 'Hi' })
    expect(res.status).toBe(201)
    expect((await res.json()).data.title).toBe('Hi')
  })

  it('maps a unique violation to 409', async () => {
    mockClient.auth.getUser.mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null })
    mockClient.from.mockReturnValue(queryResult({ error: { code: '23505', message: 'dup' } }))
    const res = await post({ title: 'Hi' })
    expect(res.status).toBe(409)
  })
})
```

For dynamic routes, pass params as a resolved promise:

```ts
const res = await GET(new NextRequest('http://test/api/notes/n1'), {
  params: Promise.resolve({ id: '6f1e...uuid' }),
})
```

## Layer 3 — Server Actions

Call the action directly with a `FormData`; mock the Next.js cache/navigation modules.

```ts
import { describe, expect, it, vi } from 'vitest'

vi.mock('next/cache', () => ({ revalidatePath: vi.fn(), revalidateTag: vi.fn() }))
vi.mock('next/navigation', () => ({
  redirect: vi.fn(() => { throw new Error('NEXT_REDIRECT') }),
}))
// plus the same '@/lib/supabase/server' mock as Layer 2

import { createNote } from '@/app/notes/actions'

it('returns fieldErrors for an empty title', async () => {
  const fd = new FormData()
  fd.set('title', '')
  const result = await createNote(null, fd)
  expect(result.ok).toBe(false)
  if (!result.ok) expect(result.fieldErrors?.title).toBeDefined()
})
```

Assert `revalidatePath` was called on the success path — a forgotten revalidate is a
real bug class that unit tests catch for free.

## Layer 4 — RLS integration tests (local Supabase)

Policies are security code; test them against a real database. Requires
`supabase start` (local stack) and seeded test users in `supabase/seed.sql`.

```ts
// tests/rls/notes.test.ts — run with the local stack up
import { createClient } from '@supabase/supabase-js'
import { describe, expect, it } from 'vitest'

const url = process.env.SUPABASE_URL ?? 'http://127.0.0.1:54321'
const anonKey = process.env.SUPABASE_ANON_KEY!

async function signIn(email: string) {
  const client = createClient(url, anonKey)
  const { error } = await client.auth.signInWithPassword({ email, password: 'password123' })
  if (error) throw error
  return client
}

describe('notes RLS', () => {
  it('a user reads only their own notes', async () => {
    const alice = await signIn('alice@test.local')
    const { data: { user } } = await alice.auth.getUser()
    const { data } = await alice.from('notes').select('id, user_id')
    expect(data?.every((n) => n.user_id === user!.id)).toBe(true)
  })

  it('inserting as another user is rejected (42501)', async () => {
    const alice = await signIn('alice@test.local')
    const { error } = await alice
      .from('notes')
      .insert({ title: 'spoof', user_id: '00000000-0000-0000-0000-000000000099' })
    expect(error?.code).toBe('42501')
  })
})
```

SQL-level alternative: the Supabase CLI runs pgTAP tests from `supabase/tests/` via
`supabase test db` — useful for asserting policies/constraints without a JS harness.

## What NOT to test

- Supabase/PostgREST internals (query building, cookie plumbing) — test your mapping
  of their results, not their behavior.
- Next.js routing itself — invoking the exported handler function is enough.
- Schemas re-tested through every handler test — one schema suite + handler tests for
  the 400 branch is sufficient.
