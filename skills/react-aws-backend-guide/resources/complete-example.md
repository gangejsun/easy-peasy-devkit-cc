# 완전 예제 — `notes` 리소스 한 바퀴

마이그레이션 → 스키마 → 쿼리 → 서비스 → 핸들러 → 테스트를 **하나의 도메인**으로 관통한다.
새 리소스는 이 순서를 그대로 따른다. 목표: 로그인한 사용자가 자신의 노트를 목록
조회(커서 페이지네이션)·생성·수정·삭제하고, 소유자별 제목은 유일하다.

## 1. 스키마 정의 → 마이그레이션 생성

```ts
// src/db/schema.ts
import { index, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core'

export const notes = pgTable('notes', {
  id: uuid('id').primaryKey().defaultRandom(),
  ownerId: text('owner_id').notNull(),
  title: text('title').notNull(),
  body: text('body').notNull().default(''),
  archivedAt: timestamp('archived_at', { withTimezone: true }),      // null = 활성
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  index('notes_owner_created_idx').on(t.ownerId, t.createdAt, t.id),  // 정렬 키 전체를 덮는다
  uniqueIndex('notes_owner_title_key').on(t.ownerId, t.title),
])

export type Note = typeof notes.$inferSelect
export type NewNote = typeof notes.$inferInsert
```

설계 판단(정규화, 키, 인덱스 구성)은 `.claude/rules/data-modeling.md`를, 정본 스키마
(`tags` 포함)는 `resources/data-access.md`를 따른다.

```bash
docker compose up -d --wait db
npx drizzle-kit generate      # → drizzle/0001_wild_notes.sql
```

```sql
-- drizzle/0001_wild_notes.sql  (생성물 — 읽고 검토한다. 손으로 먼저 쓰지 않는다)
CREATE TABLE "notes" (
  "id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
  "owner_id" text NOT NULL,
  "title" text NOT NULL,
  "body" text DEFAULT '' NOT NULL,
  "archived_at" timestamp with time zone,
  "created_at" timestamp with time zone DEFAULT now() NOT NULL,
  "updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE INDEX "notes_owner_created_idx" ON "notes" USING btree ("owner_id","created_at","id");
CREATE UNIQUE INDEX "notes_owner_title_key" ON "notes" USING btree ("owner_id","title");
```

```bash
npx drizzle-kit migrate       # 로컬 적용 → 통합 테스트가 이 SQL을 그대로 쓴다
```

## 2. 요청 스키마 (Zod)

정본 정의는 `resources/input-validation.md`의 `src/schemas/notes.ts`다. 이 예제가 쓰는 형태:

```ts
// src/schemas/notes.ts
import { z } from 'zod'

export const NoteIdParam = z.object({ id: z.uuid() })

const NoteFields = z.strictObject({              // 기본값 없는 정의가 원본이다
  title: z.string().trim().min(1).max(120),
  body: z.string().max(20_000),
})
export const CreateNoteInput = NoteFields.extend({ body: NoteFields.shape.body.default('') })
export const UpdateNoteInput = NoteFields.partial().refine(     // ← Create.partial()이 아니다
  (v) => Object.keys(v).length > 0, { error: '변경할 필드가 최소 하나 필요합니다' },
)
export const ListNotesQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().max(200).optional(),
  archived: z.stringbool().optional(),
})

export type CreateNoteInput = z.infer<typeof CreateNoteInput>
export type UpdateNoteInput = z.infer<typeof UpdateNoteInput>
export type ListNotesQuery = z.infer<typeof ListNotesQuery>
```

`CreateNoteInput.partial()`로 만들면 `.default('')`가 살아남아 `{ title: 'x' }` PATCH가
`{ title: 'x', body: '' }`로 파싱되고 → `set({ ...patch })`가 **본문을 지운다.**

## 3. 쿼리 — 모든 함수가 `ownerId`를 받는다

```ts
// src/db/queries/notes.ts
import { and, desc, eq, isNotNull, isNull, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { notes } from '@/db/schema'
import type { CreateNoteInput, UpdateNoteInput } from '@/schemas/notes'

export type Cursor = { createdAt: Date; id: string }

export async function insertNote(ownerId: string, input: CreateNoteInput) {
  // ownerId를 뒤에 둔다 — 앞에 두면 input의 동명 키가 덮어쓴다
  const [row] = await db.insert(notes).values({ ...input, ownerId }).returning()
  return row
}
export async function findOwnedNote(ownerId: string, id: string) {
  const [row] = await db.select().from(notes)
    .where(and(eq(notes.id, id), eq(notes.ownerId, ownerId))).limit(1)
  return row ?? null
}
export async function listOwnedNotes(
  ownerId: string, limit: number, cursor?: Cursor, archived?: boolean,
) {
  return db.select().from(notes)
    .where(and(
      eq(notes.ownerId, ownerId),
      cursor ? sql`(${notes.createdAt}, ${notes.id}) < (${cursor.createdAt}, ${cursor.id})`
             : undefined,
      archived ? isNotNull(notes.archivedAt) : isNull(notes.archivedAt),   // 미지정 = 활성만
    ))
    .orderBy(desc(notes.createdAt), desc(notes.id))
    .limit(limit + 1)                       // 다음 페이지 유무 판단용 1행
}
// patch 타입을 Partial<NewNote>로 열면 patch.ownerId가 실려 소유권이 이전된다
export async function updateOwnedNote(ownerId: string, id: string, patch: UpdateNoteInput) {
  const [row] = await db.update(notes).set({ ...patch, updatedAt: new Date() })
    .where(and(eq(notes.id, id), eq(notes.ownerId, ownerId))).returning()
  return row ?? null                        // null = 없거나 내 것이 아니다
}
export async function deleteOwnedNote(ownerId: string, id: string) {
  const rows = await db.delete(notes)
    .where(and(eq(notes.id, id), eq(notes.ownerId, ownerId))).returning({ id: notes.id })
  return rows.length                        // 0 = 없거나 내 것이 아니다
}
```

## 4. 서비스 — 도메인 규칙과 실패 매핑

```ts
// src/services/notes.ts
import { AppError } from '@/http/errors'
import { isUniqueViolation } from '@/db/errors'
import * as q from '@/db/queries/notes'
import type { CreateNoteInput, ListNotesQuery, UpdateNoteInput } from '@/schemas/notes'

const encodeCursor = (n: { createdAt: Date; id: string }) =>
  Buffer.from(`${n.createdAt.toISOString()}|${n.id}`).toString('base64url')

function decodeCursor(raw?: string): q.Cursor | undefined {
  if (!raw) return undefined
  const [iso, id] = Buffer.from(raw, 'base64url').toString('utf8').split('|')
  const createdAt = new Date(iso ?? '')
  if (Number.isNaN(createdAt.getTime()) || !id) throw new AppError(400, 'BAD_REQUEST', 'bad cursor')
  return { createdAt, id }
}

export async function listNotes(ownerId: string, query: ListNotesQuery) {
  const rows = await q.listOwnedNotes(
    ownerId, query.limit, decodeCursor(query.cursor), query.archived)
  const hasMore = rows.length > query.limit
  const items = hasMore ? rows.slice(0, query.limit) : rows
  return { items, nextCursor: hasMore ? encodeCursor(items[items.length - 1]!) : null }
}

export async function createNote(ownerId: string, input: CreateNoteInput) {
  try {
    return await q.insertNote(ownerId, input)
  } catch (err) {
    if (isUniqueViolation(err, 'notes_owner_title_key')) {
      throw new AppError(409, 'CONFLICT', '같은 제목의 노트가 이미 있습니다')
    }
    throw err                                  // 모르는 실패는 삼키지 않는다
  }
}

const notFound = () => new AppError(404, 'NOT_FOUND', 'Note not found')   // 부재 = 미인가

export async function getNote(ownerId: string, id: string) {
  const note = await q.findOwnedNote(ownerId, id)
  if (!note) throw notFound()
  return note
}
export async function updateNote(ownerId: string, id: string, patch: UpdateNoteInput) {
  const updated = await q.updateOwnedNote(ownerId, id, patch)
  if (!updated) throw notFound()               // 0행을 성공으로 응답하지 않는다
  return updated
}
export async function deleteNote(ownerId: string, id: string) {
  if ((await q.deleteOwnedNote(ownerId, id)) === 0) throw notFound()
}
```

## 5. 라우트와 배선

```ts
// src/routes/notes.ts
import { Hono } from 'hono'
import { jsonBody, pathParam, queryParams } from '@/http/validate'
import { CreateNoteInput, ListNotesQuery, NoteIdParam, UpdateNoteInput } from '@/schemas/notes'
import * as notes from '@/services/notes'
import type { AppEnv } from '@/http/types'

export const notesRoutes = new Hono<AppEnv>()

notesRoutes.get('/', async (c) => {
  const page = await notes.listNotes(c.get('user').sub, queryParams(c, ListNotesQuery))
  return c.json({ data: page.items, nextCursor: page.nextCursor })
})
notesRoutes.post('/', async (c) => {
  const created = await notes.createNote(c.get('user').sub, await jsonBody(c, CreateNoteInput))
  return c.json({ data: created }, 201)
})
notesRoutes.get('/:id', async (c) => {
  const { id } = pathParam(c, NoteIdParam)
  return c.json({ data: await notes.getNote(c.get('user').sub, id) })
})
notesRoutes.patch('/:id', async (c) => {
  const { id } = pathParam(c, NoteIdParam)
  const patch = await jsonBody(c, UpdateNoteInput)
  return c.json({ data: await notes.updateNote(c.get('user').sub, id, patch) })
})
notesRoutes.delete('/:id', async (c) => {
  const { id } = pathParam(c, NoteIdParam)
  await notes.deleteNote(c.get('user').sub, id)
  return c.body(null, 204)
})
```

`src/app.ts`에서 `app.use('/api/*', requireAuth)` **다음 줄에**
`app.route('/api/notes', notesRoutes)`로 마운트한다 (공개 라우트인 `/api/auth`만 그 앞이다).
Hono는 등록 순서대로 실행하므로 순서가 뒤집히면 이 리소스가 인증 없이 공개된다.

## 6. 테스트

2계층(핸들러: 파싱·에러 봉투·인증 분기)은 `app.request()`로 쓴다 (`resources/testing.md`).
여기서는 더 중요한 3계층을 보인다: **소유권 격리는 실제 SQL로만 증명된다.**

```ts
// tests/integration/notes.test.ts  (3계층: 실 DB)
import { describe, expect, it } from 'vitest'
import { createNote, getNote, updateNote, deleteNote } from '@/services/notes'

const ALICE = '11111111-1111-1111-1111-111111111111'
const BOB = '22222222-2222-2222-2222-222222222222'

describe('notes 서비스', () => {
  it('생성한 노트를 소유자만 읽는다', async () => {
    const created = await createNote(ALICE, { title: '회의록', body: '' })
    await expect(getNote(ALICE, created.id)).resolves.toMatchObject({ title: '회의록' })
    await expect(getNote(BOB, created.id)).rejects.toMatchObject({ status: 404 })
  })
  it('남의 노트 수정·삭제는 404다 (0행을 성공으로 응답하지 않는다)', async () => {
    const created = await createNote(ALICE, { title: '개인 메모', body: '' })
    await expect(updateNote(BOB, created.id, { title: 'x' })).rejects.toMatchObject({ status: 404 })
    await expect(deleteNote(BOB, created.id)).rejects.toMatchObject({ status: 404 })
    await expect(getNote(ALICE, created.id)).resolves.toBeDefined()   // 그대로 남아 있다
  })
  it('제목만 바꾸는 PATCH가 본문을 지우지 않는다', async () => {
    const created = await createNote(ALICE, { title: '초안', body: '지켜야 할 본문' })
    const updated = await updateNote(ALICE, created.id, { title: '수정본' })
    expect(updated.body).toBe('지켜야 할 본문')     // Create.partial()이면 여기서 ''가 된다
  })
  it('같은 소유자의 제목 중복은 409다', async () => {
    await createNote(ALICE, { title: '중복', body: '' })
    await expect(createNote(ALICE, { title: '중복', body: '' }))
      .rejects.toMatchObject({ status: 409, code: 'CONFLICT' })
  })
})
```

세 번째 테스트가 이 예제에서 가장 자주 깨지는 회귀를 잡는다: PATCH 스키마에 기본값이 남으면
**모든 부분 수정이 조용히 전체 덮어쓰기가 된다.** 손으로 확인하는 curl 스모크 체크와 컨테이너
빌드·배포 순서는 `resources/deployment-and-operations.md`에 있다.

## 오용 목록 — 이 예제를 복사할 때 깨지는 지점

| 복사하며 흔히 어긋나는 것 | 지켜야 할 형태 |
| --- | --- |
| 쿼리 함수에서 `ownerId` 인자를 빼고 재사용 | 첫 인자 `ownerId`는 시그니처의 일부다. 빼는 순간 경계가 사라진다 |
| 서비스에서 `.returning()` 결과를 확인하지 않음 | `null`/`0`이면 404. 확인 없이 204를 반환하면 남의 id 호출이 성공한다 |
| 중복 확인을 `select` 후 `insert`로 구현 | 동시 요청 두 개가 모두 통과한다. unique 인덱스 + `23505` → 409 |
| `limit` 없이 목록 반환 | `limit + 1` 패턴을 유지한다. 상한 없는 목록은 행이 늘면 타임아웃한다 |
| `id`를 클라이언트가 지정 | `defaultRandom()`이 만든다. 입력 스키마에 `id`를 넣지 않는다 (`strictObject`가 거절) |
| `updatedAt`을 갱신하지 않음 | `set({ ...patch, updatedAt: new Date() })` — 기본값은 삽입에만 적용된다 |
| 커서를 검증 없이 디코드 | 손상된 커서는 400으로 거절한다. 그냥 `new Date(undefined)`를 넘기면 쿼리가 조용히 빈다 |
| 보호 라우트를 `requireAuth` 앞에 마운트 | `c.get('user')`가 `undefined`가 되고 인증 없이 공개된다 (반대로 `/api/auth`는 앞이 맞다) |
| PATCH 스키마를 `Create.partial()`로 | 남아 있는 `.default()`가 미지정 필드를 덮어쓴다 → 기본값 없는 base에서 갈라 만든다 |
| 핸들러에 SQL·권한 분기를 직접 작성 | 핸들러는 파싱·호출·상태 코드만. 규칙은 서비스, SQL은 쿼리 모듈 |
