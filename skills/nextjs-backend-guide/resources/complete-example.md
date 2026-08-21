# Complete Example — Notes Endpoint, End to End

One feature ("notes": list + create, plus item update/delete) traced through every
layer: migration → schema → Route Handler → Server Action → test.
The flow to internalize: **validate → authenticate → process → respond.**

## 1. Migration — table, constraints, RLS, realtime

Structural design (columns, keys, naming) follows the **T1 data-modeling card**;
shown here is only what this example needs.

```sql
-- supabase/migrations/20260821000000_create_notes.sql
create table notes (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references auth.users (id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 200),
  content    text not null default '' check (char_length(content) <= 10000),
  tags       text[] not null default '{}'
             check (array_length(tags, 1) is null or array_length(tags, 1) <= 20),
  created_at timestamptz not null default now()
);

create index notes_user_id_created_at_idx on notes (user_id, created_at desc);

alter table notes enable row level security;

create policy "notes_select_own" on notes for select
  using ((select auth.uid()) = user_id);
create policy "notes_insert_own" on notes for insert
  with check ((select auth.uid()) = user_id);
create policy "notes_update_own" on notes for update
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);
create policy "notes_delete_own" on notes for delete
  using ((select auth.uid()) = user_id);

alter publication supabase_realtime add table notes;
```

Note how every Zod rule below has a constraint twin here (title 1–200, content ≤10000,
tags ≤20) — that is the DB-constraint-duplication rule in action.

Then regenerate types: `npx supabase gen types typescript --local > types/database.ts`

## 2. Validation schema (shared by handler, action, tests)

```ts
// lib/validations/note.ts
import { z } from 'zod'

export const createNoteSchema = z.object({
  title: z.string().trim().min(1, { error: 'Title is required' }).max(200),
  content: z.string().max(10_000).default(''),
  tags: z.array(z.string().trim().min(1)).max(20).default([]),
})

// Updates: every field optional, same rules when present
export const updateNoteSchema = createNoteSchema.partial()

export const noteListQuerySchema = z.object({
  page: z.coerce.number().int().min(1).default(1),
  perPage: z.coerce.number().int().min(1).max(100).default(20),
})

export type CreateNoteInput = z.infer<typeof createNoteSchema>
```

## 3. Route Handler

Uses the `ok`/`fail`/`fromSupabaseError` helpers from `lib/api/errors.ts`
(full source in `resources/validation-and-errors.md`).

```ts
// app/api/notes/route.ts
import { NextRequest } from 'next/server'
import { z } from 'zod'
import { createClient } from '@/lib/supabase/server'
import { ok, fail, fromSupabaseError } from '@/lib/api/errors'
import { createNoteSchema, noteListQuerySchema } from '@/lib/validations/note'

export async function GET(request: NextRequest) {
  // validate
  const parsed = noteListQuerySchema.safeParse(
    Object.fromEntries(request.nextUrl.searchParams),
  )
  if (!parsed.success) {
    return fail(400, 'validation_error', 'Invalid query parameters',
      z.flattenError(parsed.error).fieldErrors)
  }

  // authenticate
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return fail(401, 'unauthenticated', 'Sign in required')

  // process (RLS scopes rows to this user; the eq() makes intent explicit)
  const { page, perPage } = parsed.data
  const from = (page - 1) * perPage
  const { data, error, count } = await supabase
    .from('notes')
    .select('id, title, tags, created_at', { count: 'exact' })
    .eq('user_id', user.id)
    .order('created_at', { ascending: false })
    .range(from, from + perPage - 1)
  if (error) return fromSupabaseError(error)

  // respond
  return ok({ items: data, page, perPage, total: count })
}

export async function POST(request: NextRequest) {
  // validate
  let body: unknown
  try {
    body = await request.json()
  } catch {
    return fail(400, 'invalid_json', 'Request body must be valid JSON')
  }
  const parsed = createNoteSchema.safeParse(body)
  if (!parsed.success) {
    return fail(400, 'validation_error', 'Invalid input',
      z.flattenError(parsed.error).fieldErrors)
  }

  // authenticate
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return fail(401, 'unauthenticated', 'Sign in required')

  // process — ownership comes from the verified user, never the body
  const { data, error } = await supabase
    .from('notes')
    .insert({ ...parsed.data, user_id: user.id })
    .select('id, title, content, tags, created_at')
    .single()
  if (error) return fromSupabaseError(error)

  // respond
  return ok(data, 201)
}
```

### Item routes — PATCH / DELETE with the ownership double defense

```ts
// app/api/notes/[id]/route.ts (imports as above, plus updateNoteSchema)
type RouteContext = { params: Promise<{ id: string }> }

export async function PATCH(request: NextRequest, { params }: RouteContext) {
  const { id } = await params
  const parsed = updateNoteSchema.safeParse(await request.json().catch(() => null))
  if (!parsed.success) {
    return fail(400, 'validation_error', 'Invalid input',
      z.flattenError(parsed.error).fieldErrors)
  }

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return fail(401, 'unauthenticated', 'Sign in required')

  const { data, error } = await supabase
    .from('notes')
    .update(parsed.data)
    .eq('id', id)
    .eq('user_id', user.id)   // explicit ownership filter — RLS is the backup, not the only guard
    .select('id, title, content, tags')
    .single()                 // PGRST116 (0 rows: missing or not yours) → 404
  if (error) return fromSupabaseError(error)
  return ok(data)
}

export async function DELETE(_request: NextRequest, { params }: RouteContext) {
  const { id } = await params
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return fail(401, 'unauthenticated', 'Sign in required')

  const { data, error } = await supabase
    .from('notes')
    .delete()
    .eq('id', id)
    .eq('user_id', user.id)   // explicit ownership filter — RLS is the backup
    .select('id')             // confirm what was deleted — [] means nothing was
  if (error) return fromSupabaseError(error)
  if (!data?.length) return fail(404, 'not_found', 'Resource not found') // missing or RLS-hidden: same 404
  return ok({ deleted: true })
}
```

## 4. Server Action (same mutation, form-facing)

```ts
// app/notes/actions.ts
'use server'

import { z } from 'zod'
import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'
import { createNoteSchema } from '@/lib/validations/note'
import type { ActionResult } from '@/lib/api/types'

export async function createNote(
  _prev: ActionResult | null,
  formData: FormData,
): Promise<ActionResult> {
  const parsed = createNoteSchema.safeParse({
    title: formData.get('title'),
    content: formData.get('content') ?? '',
  })
  if (!parsed.success) {
    return { ok: false, fieldErrors: z.flattenError(parsed.error).fieldErrors }
  }

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { ok: false, formError: 'Sign in required' }

  const { error } = await supabase
    .from('notes')
    .insert({ ...parsed.data, user_id: user.id })
  if (error) {
    console.error('[createNote]', error)
    return { ok: false, formError: 'Something went wrong. Please try again.' }
  }

  revalidatePath('/notes')
  return { ok: true }
}
```

The consuming form wires this through `useActionState(createNote, null)` —
component patterns belong to the frontend guide.

## 5. Test

```ts
// app/api/notes/route.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { NextRequest } from 'next/server'

const { mockClient } = vi.hoisted(() => ({
  mockClient: { auth: { getUser: vi.fn() }, from: vi.fn() },
}))
vi.mock('@/lib/supabase/server', () => ({
  createClient: vi.fn(async () => mockClient),
}))

import { POST } from '@/app/api/notes/route'

function queryResult(result: { data?: unknown; error?: unknown }) {
  const builder: Record<string, unknown> = {}
  for (const m of ['select', 'insert', 'eq', 'order', 'range', 'single']) {
    builder[m] = vi.fn(() => builder)
  }
  ;(builder as { then?: unknown }).then = (resolve: (v: unknown) => void) =>
    resolve({ data: null, error: null, count: null, ...result })
  return builder
}

const post = (body: unknown) =>
  POST(new NextRequest('http://test/api/notes', { method: 'POST', body: JSON.stringify(body) }))

describe('POST /api/notes', () => {
  beforeEach(() => vi.clearAllMocks())

  it('400: invalid body never reaches auth or DB', async () => {
    expect((await post({ title: '' })).status).toBe(400)
    expect(mockClient.auth.getUser).not.toHaveBeenCalled()
  })

  it('401: no verified user', async () => {
    mockClient.auth.getUser.mockResolvedValue({ data: { user: null }, error: null })
    expect((await post({ title: 'Hi' })).status).toBe(401)
  })

  it('201: creates and returns the note', async () => {
    mockClient.auth.getUser.mockResolvedValue({ data: { user: { id: 'user-1' } }, error: null })
    mockClient.from.mockReturnValue(queryResult({ data: { id: 'n1', title: 'Hi' } }))
    const res = await post({ title: 'Hi' })
    expect(res.status).toBe(201)
    expect((await res.json()).data.id).toBe('n1')
  })
})
```

## Recap checklist

- [ ] Migration: constraints duplicate every Zod rule; RLS enabled with 4 policies
- [ ] One schema file feeds the handler, the action, and the tests
- [ ] Handler order: validate → authenticate → process → respond
- [ ] Ownership (`user_id`) always from `getUser()`, never from input
- [ ] PATCH/DELETE scope by `id` **and** `user_id`; DELETE confirms rows via `.select()`
- [ ] Errors mapped through `fromSupabaseError`; nothing internal leaks
- [ ] Action returns `ActionResult` and revalidates; handler returns the envelope
- [ ] Tests cover 400 / 401 / 201 (+ RLS integration per `resources/testing.md`)
