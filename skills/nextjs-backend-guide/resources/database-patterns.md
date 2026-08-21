# Data Access — Supabase Client & Query Patterns

> **Table design is out of scope for this file.** Columns, keys, indexes, naming, and
> relationships are owned by the **T1 data-modeling card** at
> **`.claude/rules/data-modeling.md`**. It auto-loads only on DB paths (`supabase/**`,
> `**/migrations/**`, `db/**`, `prisma/**`, `drizzle/**`) — under `app/api/**` it will
> **not** be in context, so open that file directly before creating or altering a table,
> and do not copy its content here. This file covers clients and query patterns only.

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

## Typed queries

Regenerate types after every migration and pass them to the client (`<Database>` above) —
then `data` rows, `insert()` payloads, and column names are all checked at compile time:

```bash
npx supabase gen types typescript --local > types/database.ts
```

## Read patterns

```ts
const supabase = await createClient()

// Always list columns explicitly — never select('*') in handlers
const { data, error } = await supabase
  .from('notes')
  .select('id, title, created_at')
  .order('created_at', { ascending: false })
  .limit(20)
if (error) return fromSupabaseError(error)

// Exactly one row expected → single(): PGRST116 when it does not match exactly one row
const { data: note, error: noteError } = await supabase
  .from('notes').select('id, title, content').eq('id', id).eq('user_id', user.id).single()
if (noteError) return fromSupabaseError(noteError)

// Zero-or-one expected → maybeSingle(): data is null on 0 rows, no error
const { data: maybe, error: maybeError } = await supabase
  .from('notes').select('id').eq('slug', slug).maybeSingle()
if (maybeError) return fromSupabaseError(maybeError)

// Pagination: range is inclusive; count comes back alongside data
const from = (page - 1) * perPage
const { data: pageRows, error: pageError, count } = await supabase
  .from('notes').select('id, title', { count: 'exact' })
  .range(from, from + perPage - 1)
if (pageError) return fromSupabaseError(pageError)

// Count only, no rows
const { count: total, error: countError } = await supabase
  .from('notes').select('id', { count: 'exact', head: true })
if (countError) return fromSupabaseError(countError)
```

## Filter cheatsheet (the ones that get misused)

The snippets below omit error handling to keep the focus on filter shape — real code always
destructures and checks `error` (Core Principle 5 in SKILL.md).

```ts
.eq('status', 'published')   .neq('status', 'draft')       // equality
.gt/.gte/.lt/.lte('view_count', n)                              // comparisons — chain two for a range
.in('status', ['published', 'featured'])                   // value is in a list
.like('title', '%plan%')     .ilike('title', '%plan%')     // ilike = case-insensitive (usually what you want)
.is('deleted_at', null)                                    // NULL check — .eq(col, null) matches nothing
.contains('tags', ['ts', 'api'])                           // array/jsonb column contains ALL of these
.containedBy('tags', allowed)                              // column is a subset of the list
.or('status.eq.draft,status.eq.review')                    // OR — one PostgREST filter string
```

Full-text search takes a **query syntax that must match the chosen `type`** — mixing them
silently searches for the wrong thing:

```ts
// Operator syntax (to_tsquery): & | ! <-> — for queries YOU build. Omit `type`.
.textSearch('title', "'note' & 'api'")
// User-typed input (websearch_to_tsquery): natural language, quoted phrases, `or`, `-word`
.textSearch('title', 'note api or "rate limit" -draft', { type: 'websearch' })
```

`websearch` never parses `&`/`|` — it treats them as noise. Use it for anything a user typed
(it cannot raise a syntax error), the operator form only for queries you build. Either way
the column needs a `tsvector` + GIN index.

Frequent mistakes: `.eq(col, null)` instead of `.is()`; `.like` when you meant
case-insensitive `.ilike`; `.contains` ("has all of") confused with `.in` ("is one of").

## Relational reads (embedded selects)

Foreign-key relationships can be embedded instead of hand-written joins:

```ts
// note + its author's profile (FK: notes.user_id → profiles.id)
const { data, error } = await supabase
  .from('notes')
  .select('id, title, author:profiles(id, display_name)')
if (error) return fromSupabaseError(error)

// one-to-many: profile with its notes, newest first
const { data: profile, error: profileError } = await supabase
  .from('profiles')
  .select('id, display_name, notes(id, title, created_at)')
  .eq('id', userId)
  .order('created_at', { referencedTable: 'notes', ascending: false })
  .single()
if (profileError) return fromSupabaseError(profileError)
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
const { data, error } = await supabase
  .from('notes')
  .select('id, title, author:profiles(display_name)')
if (error) return fromSupabaseError(error)
```

Indexes make these queries hold up — DDL lives in migrations (design per the T1 card;
the `notes` schema these examples assume is in `resources/complete-example.md`):

```sql
-- Composite: FK + the sort order the list endpoint uses
create index notes_user_id_created_at_idx on notes (user_id, created_at desc);

-- Partial: index only the rows a hot filter actually touches
create index notes_active_idx on notes (created_at desc) where archived_at is null;
```

Every FK column gets an index (joins and cascade deletes scan it); a partial index stays
small and serves a filter like `where archived_at is null` exactly.

## Write patterns

```ts
// Insert and read back the created row in one round trip
const { data: created, error: insertError } = await supabase
  .from('notes').insert({ title, content, user_id: user.id })
  .select('id, title, created_at').single()
if (insertError) return fromSupabaseError(insertError)

// Update: scope by id AND the verified owner — RLS is a backup, not the only defense
const { data: updated, error: updateError } = await supabase
  .from('notes').update({ title: newTitle })
  .eq('id', id).eq('user_id', user.id)
  .select('id, title').single()          // PGRST116 (missing or not yours) → 404
if (updateError) return fromSupabaseError(updateError)

// Delete: same owner filter + .select(), so "deleted" differs from "matched nothing"
const { data: deleted, error: deleteError } = await supabase
  .from('notes').delete().eq('id', id).eq('user_id', user.id).select('id')
if (deleteError) return fromSupabaseError(deleteError)
if (!deleted?.length) return fail(404, 'not_found', 'Resource not found')

// Upsert on a unique column
const { error: upsertError } = await supabase
  .from('user_settings').upsert({ user_id: user.id, theme: 'dark' }, { onConflict: 'user_id' })
if (upsertError) return fromSupabaseError(upsertError)
```

Set ownership columns (`user_id`) from `user.id` on the server — never from the request
body — and filter every mutation by that owner. RLS is the backup, not the only defense: a
`delete()` without `.select()` reports success even when it removed nothing.

## Multi-step mutations → RPC (Postgres functions)

supabase-js has **no transaction API**. Any mutation that must be atomic across
statements belongs in a Postgres function called via `.rpc()`:

```sql
-- supabase/migrations/xxxx_archive_note.sql
create or replace function archive_note(p_note_id uuid)
returns void
language plpgsql
security invoker            -- keeps RLS applied as the calling user
set search_path = ''        -- required: resolve every object by schema (see below)
as $$
begin
  update public.notes set archived_at = now() where id = p_note_id;
  insert into public.note_events (note_id, kind) values (p_note_id, 'archived');
end;
$$;
```

```ts
const { error } = await supabase.rpc('archive_note', { p_note_id: id })
if (error) return fromSupabaseError(error)
```

Default to `security invoker`. `security definer` bypasses RLS — treat it like the
service-role key: only with an explicit reason, documented at the definition site.

**Every function gets `set search_path = ''`** (Supabase's `function_search_path_mutable`
lint). A mutable `search_path` lets a caller prepend a schema they control and shadow
`notes` or `auth.uid()` with their own object — under `security definer` that runs as the
function owner. Empty `search_path` means unqualified names resolve to nothing, so qualify
everything: `public.notes`, `auth.uid()`, `extensions.gen_random_uuid()`.

## Storage — server-side file handling

Buckets are private by default; access control on `storage.objects` is RLS.

```ts
const supabase = await createClient()

// Upload under a user-id prefix so storage policies can match the folder
const path = `${user.id}/${crypto.randomUUID()}.pdf`
const { error: upErr } = await supabase.storage
  .from('attachments').upload(path, file, { contentType: 'application/pdf', upsert: false })

// Time-limited access to a private object, then removal
const { data: signed, error: signErr } = await supabase.storage
  .from('attachments').createSignedUrl(path, 60 * 10) // 10 minutes
const { error: rmErr } = await supabase.storage.from('attachments').remove([path])
```

```sql
-- Storage policy: users touch only their own folder in this bucket
create policy "own_folder" on storage.objects for all
  using (bucket_id = 'attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text);
```

Store the object `path` in your table, not a signed URL — signed URLs expire. Storage calls
return `{ data, error }` too and every one must be checked; a `StorageError` carries no
Postgres `code`, so map it explicitly rather than via `fromSupabaseError`.

## Realtime — backend responsibilities

Subscribing happens in the frontend; the backend makes events available and keeps them
access-controlled:

```sql
-- Migration: emit change events for a table
alter publication supabase_realtime add table notes;
```

- `postgres_changes` deliveries respect the table's RLS — clients receive only rows they may
  `select`. RLS off = broadcast to everyone; never replicate a table without RLS.
- Mutations through your handlers/actions are picked up automatically — no extra server code "sends" a change event.
- For high-fanout or derived events, prefer Realtime Broadcast over `postgres_changes`.
