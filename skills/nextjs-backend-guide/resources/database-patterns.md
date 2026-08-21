# Data Access — Supabase Client & Query Patterns

> **Table design is out of scope for this file.** Columns, keys, indexes, naming, and
> relationships are owned by the **T1 data-modeling card (hub rule)** — consult it before
> creating or altering any table, and do not copy its content here. This file covers
> client construction and query patterns only.

## Client matrix

| Client | File | Key | RLS | Use in |
| --- | --- | --- | --- | --- |
| Server client | `lib/supabase/server.ts` | anon | enforced | Route Handlers, Server Actions, Server Components |
| Admin client | `lib/supabase/admin.ts` | service role | **bypassed** | Webhooks, cron, admin tasks only — see `auth-boundaries.md` |
| Browser client | (frontend guide) | anon | enforced | Client Components only |

## Server client — per-request, cookie-bound

```ts
// lib/supabase/server.ts
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import type { Database } from '@/types/database'

export async function createClient() {
  const cookieStore = await cookies() // async in Next.js 15

  return createServerClient<Database>(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
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

Call `await createClient()` inside every handler/action — never at module scope.
(Newer Supabase projects may name the keys publishable/secret; the pattern is identical.)

## Typed queries

Generate types after every migration and pass them to the client (`<Database>` above):

```bash
npx supabase gen types typescript --local > types/database.ts
```

With types in place, `data` rows, `insert()` payloads, and column names are all checked
at compile time.

## Read patterns

```ts
const supabase = await createClient()

// Always list columns explicitly — never select('*') in handlers
const { data, error } = await supabase
  .from('notes')
  .select('id, title, created_at')
  .order('created_at', { ascending: false })
  .limit(20)

// Exactly one row expected → single(): 0 rows is an error (PGRST116 → map to 404)
const { data: note, error: e1 } = await supabase
  .from('notes').select('id, title, content').eq('id', id).single()

// Zero-or-one expected → maybeSingle(): data is null on 0 rows, no error
const { data: maybe } = await supabase
  .from('notes').select('id').eq('slug', slug).maybeSingle()

// Pagination: range is inclusive; count comes back alongside data
const from = (page - 1) * perPage
const { data: pageRows, count } = await supabase
  .from('notes')
  .select('id, title', { count: 'exact' })
  .range(from, from + perPage - 1)

// Count only, no rows
const { count: total } = await supabase
  .from('notes').select('id', { count: 'exact', head: true })
```

## Filter cheatsheet (the ones that get misused)

```ts
.eq('status', 'published')   .neq('status', 'draft')       // equality
.gt/.gte/.lt/.lte('view_count', n)                              // comparisons — chain two for a range
.in('status', ['published', 'featured'])                   // value is in a list
.like('title', '%plan%')     .ilike('title', '%plan%')     // ilike = case-insensitive (usually what you want)
.is('deleted_at', null)                                    // NULL check — .eq(col, null) matches nothing
.contains('tags', ['ts', 'api'])                           // array/jsonb column contains ALL of these
.containedBy('tags', allowed)                              // column is a subset of the list
.or('status.eq.draft,status.eq.review')                    // OR — one PostgREST filter string
.textSearch('title', "'note' & 'api'", { type: 'websearch' }) // full-text; needs tsvector + GIN index
```

Frequent mistakes: `.eq(col, null)` instead of `.is()`; `.like` when you meant
case-insensitive `.ilike`; `.contains` ("has all of") confused with `.in` ("is one of").

## Relational reads (embedded selects)

Foreign-key relationships can be embedded instead of hand-written joins:

```ts
// note + its author's profile (FK: notes.user_id → profiles.id)
const { data } = await supabase
  .from('notes')
  .select('id, title, author:profiles(id, display_name)')

// one-to-many: profile with its notes, newest first
const { data: profile } = await supabase
  .from('profiles')
  .select('id, display_name, notes(id, title, created_at)')
  .eq('id', userId)
  .order('created_at', { referencedTable: 'notes', ascending: false })
  .single()
```

Embedding requires a real FK between the tables (design per the T1 card).

## N+1 prevention & indexes

```ts
// Bad — one query per row (N+1): listing 50 notes fires 51 queries
const { data: notes } = await supabase.from('notes').select('id, title, user_id')
for (const note of notes ?? []) {
  await supabase.from('profiles').select('display_name').eq('id', note.user_id).single()
}

// Good — one round trip with an embedded select (previous section)
const { data } = await supabase
  .from('notes')
  .select('id, title, author:profiles(display_name)')
```

Indexes make these queries hold up — DDL lives in migrations (design per the T1 card):

```sql
-- Composite: FK + the sort order the list endpoint uses
create index notes_user_id_created_at_idx on notes (user_id, created_at desc);

-- Partial: index only the rows a hot filter actually touches
create index notes_active_idx on notes (created_at desc) where archived_at is null;
```

Every FK column gets an index (joins and cascade deletes scan it); a partial index
stays small and serves filters like `where archived_at is null` exactly.

## Write patterns

```ts
// Insert and read back the created row in one round trip
const { data: created, error } = await supabase
  .from('notes')
  .insert({ title, content, user_id: user.id })
  .select('id, title, created_at')
  .single()

// Update scoped by filter — RLS additionally guarantees only permitted rows match
const { data: updated } = await supabase
  .from('notes')
  .update({ title: newTitle })
  .eq('id', id)
  .select('id, title')
  .single()

// Delete
const { error: delError } = await supabase.from('notes').delete().eq('id', id)

// Upsert on a unique column
const { error: upError } = await supabase
  .from('user_settings')
  .upsert({ user_id: user.id, theme: 'dark' }, { onConflict: 'user_id' })
```

Always set ownership columns (`user_id`) from `user.id` on the server — never accept
them from the request body.

## Multi-step mutations → RPC (Postgres functions)

supabase-js has **no transaction API**. Any mutation that must be atomic across
statements belongs in a Postgres function called via `.rpc()`:

```sql
-- supabase/migrations/xxxx_archive_note.sql
create or replace function archive_note(p_note_id uuid)
returns void
language plpgsql
security invoker            -- keeps RLS applied as the calling user
as $$
begin
  update notes set archived_at = now() where id = p_note_id;
  insert into note_events (note_id, kind) values (p_note_id, 'archived');
end;
$$;
```

```ts
const { error } = await supabase.rpc('archive_note', { p_note_id: id })
```

Default to `security invoker`. `security definer` bypasses RLS — treat it like the
service-role key: only with an explicit reason, documented at the definition site.

## Storage — server-side file handling

Buckets are private by default; access control on `storage.objects` is RLS.

```ts
const supabase = await createClient()

// Upload under a user-id prefix so storage policies can match the folder
const path = `${user.id}/${crypto.randomUUID()}.pdf`
const { error: upErr } = await supabase.storage
  .from('attachments')
  .upload(path, file, { contentType: 'application/pdf', upsert: false })

// Time-limited access to a private object
const { data: signed } = await supabase.storage
  .from('attachments')
  .createSignedUrl(path, 60 * 10) // 10 minutes

// Remove
await supabase.storage.from('attachments').remove([path])
```

```sql
-- Storage policy: users touch only their own folder in this bucket
create policy "own_folder" on storage.objects for all
  using (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'attachments'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
```

Store the object `path` in your table, not a signed URL — signed URLs expire.

## Realtime — backend responsibilities

Subscribing happens in the frontend; the backend's job is to make events available
and keep them access-controlled:

```sql
-- Migration: emit change events for a table
alter publication supabase_realtime add table notes;
```

- `postgres_changes` deliveries respect the table's RLS — clients only receive rows
  they are allowed to `select`. RLS off = broadcast to everyone; never enable
  replication on a table without RLS.
- Mutations made through your handlers/actions are picked up automatically — no extra
  server code is needed to "send" a change event.
- For high-fanout or derived events, prefer Realtime Broadcast over `postgres_changes`;
  see the official Supabase Realtime docs before adopting it.
