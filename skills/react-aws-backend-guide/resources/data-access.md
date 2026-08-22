# 데이터 액세스 (Drizzle ORM + RDS PostgreSQL)

쿼리와 마이그레이션 **실행** 패턴만 다룬다.

> **테이블 설계 규칙은 여기 없다.** 정규화·키·제약·인덱스 설계는 T1 규칙 카드
> `.claude/rules/data-modeling.md`가 소유한다. 이 카드는 `drizzle/**`, `db/**`,
> `**/migrations/**`를 편집할 때 자동으로 로드되지만 **`src/**` 안에서 쿼리를 고칠 때는
> 매칭되지 않는다** — 그럴 때는 위 경로를 직접 열어서 읽는다.

## 클라이언트는 싱글턴 하나 (`src/db/client.ts`)

```ts
import { readFileSync } from 'node:fs'
import { drizzle } from 'drizzle-orm/node-postgres'
import { Pool } from 'pg'
import { env } from '@/config/env'
import * as schema from '@/db/schema'

// RDS 서버 인증서는 Amazon 사설 루트가 발급한다 — Node 기본 신뢰 저장소에 없다
const ca = env.DB_CA_PATH ? readFileSync(env.DB_CA_PATH, 'utf8') : undefined

export const pool = new Pool({
  connectionString: env.DATABASE_URL,
  max: env.DB_POOL_MAX,                 // Fargate 태스크 수 × max ≤ RDS max_connections
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
  ssl: env.DB_SSL ? { rejectUnauthorized: true, ca } : undefined,
})

export const db = drizzle(pool, { schema })
```

- 요청마다 `new Pool()`을 만들지 않는다 — 연결이 폭증해 RDS가 새 연결을 거부한다
- 종료 시 `await pool.end()`를 SIGTERM 핸들러에 넣는다 (`src/index.ts`)
- 커넥션 수 상한은 **태스크 수 × `DB_POOL_MAX`** 로 계산한다. 오토스케일 상한을 넘기면
  스케일 아웃이 곧 장애다

### TLS는 `rejectUnauthorized: true` 하나로 끝나지 않는다

`rejectUnauthorized: true`만 켜고 배포하면 첫 접속이 `SELF_SIGNED_CERT_IN_CHAIN`으로
실패한다. Amazon RDS의 루트 인증서가 Node 기본 신뢰 저장소에 없기 때문이다. 여기서 개발자가
`false`로 되돌리면 **중간자 공격에 그대로 열린다** — 암호화는 되지만 상대가 누구인지 확인하지
않는 연결이다. 올바른 해법은 번들을 이미지에 넣고 경로를 주입하는 것이다.

```dockerfile
ADD https://truststore.pki.rds.amazonaws.com/global-bundle.pem /etc/ssl/rds/global-bundle.pem
ENV DB_CA_PATH=/etc/ssl/rds/global-bundle.pem
```

온프레미스로 옮기면 같은 `DB_CA_PATH`에 사내 CA 번들 경로를 넣는다 — **앱 코드는 무변경**이다.
로컬 `docker compose`는 `DB_SSL=false`(평문 루프백)이므로 이 경로가 필요 없다.

## 스키마 정의 (마이그레이션의 원본)

이 블록이 **테이블 정의의 정본**이다. 다른 리소스 파일의 `notes` 인용은 이 정의를 가리킨다.

```ts
// src/db/schema.ts
import { index, pgTable, text, timestamp, uniqueIndex, uuid } from 'drizzle-orm/pg-core'

export const notes = pgTable('notes', {
  id: uuid('id').primaryKey().defaultRandom(),
  ownerId: text('owner_id').notNull(),          // 토큰의 sub — IdP 교체를 대비해 text
  title: text('title').notNull(),
  body: text('body').notNull().default(''),
  archivedAt: timestamp('archived_at', { withTimezone: true }),   // null = 활성
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => [
  index('notes_owner_created_idx').on(t.ownerId, t.createdAt, t.id),
  uniqueIndex('notes_owner_title_key').on(t.ownerId, t.title),
])

export const tags = pgTable('tags', {
  id: uuid('id').primaryKey().defaultRandom(),
  ownerId: text('owner_id').notNull(),          // 자식 테이블도 소유자를 직접 들고 있는다
  noteId: uuid('note_id').notNull().references(() => notes.id, { onDelete: 'cascade' }),
  name: text('name').notNull(),
}, (t) => [
  index('tags_owner_note_idx').on(t.ownerId, t.noteId),
  uniqueIndex('tags_note_name_key').on(t.noteId, t.name),
])

export type Note = typeof notes.$inferSelect
export type NewNote = typeof notes.$inferInsert
```

- **`owner_id`가 선행 컬럼인 인덱스**를 반드시 둔다. 모든 조회가 소유자로 필터되므로
  이 인덱스가 없으면 전 테이블 스캔이 된다
- **인덱스 컬럼은 정렬 키와 끝까지 일치시킨다.** 커서 정렬이 `(created_at, id)`인데 인덱스가
  `(owner_id, created_at)`에서 끊기면 동점 구간에서 정렬이 인덱스로 해결되지 않는다
- **자식 테이블에도 `owner_id`를 둔다.** 부모를 조인해야만 소유자를 알 수 있는 구조면
  `IN` 조회처럼 조인 없는 경로에서 필터를 빠뜨리게 된다
- 시각은 항상 `withTimezone: true` (`timestamptz`). 타임존 없는 컬럼은 배포 리전이
  바뀌는 순간 의미가 달라진다
- `$inferSelect` / `$inferInsert`로 타입을 뽑아 쓴다 — 행 타입을 손으로 다시 쓰지 않는다

## 쿼리는 항상 `ownerId`를 받는다 (`src/db/queries/notes.ts`)

이 계층에 인증 개념은 없다. 대신 **소유자 인자 없이는 호출조차 못 하게** 시그니처로 강제한다.

```ts
import { and, desc, eq, isNotNull, isNull, sql } from 'drizzle-orm'
import { db } from '@/db/client'
import { notes } from '@/db/schema'
import type { UpdateNoteInput } from '@/schemas/notes'

export async function findOwnedNote(ownerId: string, id: string) {
  const [row] = await db.select().from(notes)
    .where(and(eq(notes.id, id), eq(notes.ownerId, ownerId)))
    .limit(1)
  return row ?? null
}

export async function listOwnedNotes(
  ownerId: string, limit: number,
  cursor?: { createdAt: Date; id: string }, archived?: boolean,
) {
  return db.select().from(notes)
    .where(and(
      eq(notes.ownerId, ownerId),
      cursor
        ? sql`(${notes.createdAt}, ${notes.id}) < (${cursor.createdAt}, ${cursor.id})`
        : undefined,                                   // undefined는 and()가 무시한다
      archived ? isNotNull(notes.archivedAt) : isNull(notes.archivedAt),  // 미지정 = 활성만
    ))
    .orderBy(desc(notes.createdAt), desc(notes.id))
    .limit(limit + 1)                                  // +1로 다음 페이지 유무를 판단
}
```

`(created_at, id) < (...)` 는 PostgreSQL의 행 값 비교다. 커서 페이지네이션의 동점 처리를
한 조건으로 끝낸다. `notes_owner_created_idx`가 `(owner_id, created_at, id)`이므로 정렬 키
전체를 인덱스가 받는다 — 뒤쪽 두 컬럼이 빠지면 동점 구간에서 정렬이 다시 수행된다.

## 변이는 영향 행을 확인한다

**이 계층의 대표 함정**: 소유권 필터가 걸린 `update`/`delete`는 남의 리소스에 대해
"에러 없이 0행"을 반환한다. 결과를 버리면 그 요청은 성공으로 응답된다.

```ts
// patch 타입은 UpdateNoteInput으로 좁힌다 — Partial<NewNote>가 아니다
export async function updateOwnedNote(ownerId: string, id: string, patch: UpdateNoteInput) {
  const [row] = await db.update(notes)
    .set({ ...patch, updatedAt: new Date() })
    .where(and(eq(notes.id, id), eq(notes.ownerId, ownerId)))
    .returning()
  return row ?? null                     // null → 서비스가 404를 던진다
}

export async function deleteOwnedNote(ownerId: string, id: string) {
  const rows = await db.delete(notes)
    .where(and(eq(notes.id, id), eq(notes.ownerId, ownerId)))
    .returning({ id: notes.id })
  return rows.length                     // 0 → 404
}
```

```ts
// ❌ 결과를 버린다 — 남의 id로 호출해도 204가 나간다
await db.delete(notes).where(and(eq(notes.id, id), eq(notes.ownerId, ownerId)))
```

`insert`도 마찬가지로 `.returning()` 결과를 응답에 쓴다. 클라이언트가 보낸 입력을 되돌려
주면 DB 기본값(`id`, `createdAt`)이 빠진 응답이 나간다.

**`patch` 타입을 `Partial<NewNote>`로 열어 두지 않는다.** 그러면 `patch.ownerId`가 `set`에
실릴 수 있고, 소유권 필터를 통과한 요청 하나가 **행을 타인에게 넘긴다**. 파싱된 요청 타입
(`UpdateNoteInput`)만 받으면 `ownerId`·`id`·`createdAt`은 애초에 타입에 없다.

## 트랜잭션

여러 테이블을 함께 바꾸면 트랜잭션으로 묶는다. **`tx`를 콜백 밖으로 새게 하지 않는다.**

```ts
import { and, eq } from 'drizzle-orm'
import { db } from '@/db/client'
import { notes, tags } from '@/db/schema'

export async function replaceNoteTags(ownerId: string, noteId: string, names: string[]) {
  return db.transaction(async (tx) => {
    const [note] = await tx.select({ id: notes.id }).from(notes)
      .where(and(eq(notes.id, noteId), eq(notes.ownerId, ownerId))).limit(1)
    if (!note) return null                          // 소유권 확인도 트랜잭션 안에서

    // 소유자 조건은 자식 테이블 변이에도 그대로 붙인다 (부모 확인이 대신해 주지 않는다)
    await tx.delete(tags).where(and(eq(tags.ownerId, ownerId), eq(tags.noteId, noteId)))
    if (names.length === 0) return []
    return tx.insert(tags).values(names.map((name) => ({ ownerId, noteId, name }))).returning()
  })
}
```

- 트랜잭션 안에서 HTTP 호출·긴 대기를 하지 않는다 (연결을 잡은 채 풀이 마른다)
- 롤백은 콜백에서 throw하면 자동이다 — `tx.rollback()`을 직접 부를 일은 드물다

## N+1을 만들지 않는다

```ts
import { and, eq, inArray } from 'drizzle-orm'
import { db } from '@/db/client'
import { tags } from '@/db/schema'

// ❌ 목록 길이만큼 쿼리가 나간다
for (const note of rows) note.tags = await findTags(note.id)

// ✅ 한 번에 가져와 메모리에서 묶는다 — 소유자 조건은 배치 조회에도 그대로 있다
const tagRows = await db.select().from(tags)
  .where(and(eq(tags.ownerId, ownerId), inArray(tags.noteId, rows.map((r) => r.id))))
const byNote = new Map<string, typeof tagRows>()
for (const t of tagRows) byNote.set(t.noteId, [...(byNote.get(t.noteId) ?? []), t])
```

**`IN` 목록이 내 행에서 나왔다는 사실은 소유권 필터가 아니다.** id가 한 번이라도 외부 입력
(요청 본문의 배열, 캐시, 다른 쿼리 결과)에서 오면 그 조회는 소유자 조건 없는 조회가 된다.
`rows`가 안전해 보여도 조건을 붙여 둔다 — 재사용될 때 안전성이 따라가지 않는다.

관계를 자주 함께 읽는다면 `db.query.notes.findMany({ with: { tags: true } })`(relations
선언 필요)로 바꾼다. 어느 쪽이든 **쿼리 수가 목록 길이에 비례하면 안 된다.**

## 마이그레이션 워크플로

```bash
docker compose up -d --wait db          # postgres:16 기동 후 healthy까지 대기
npx drizzle-kit generate                # schema.ts 차이 → drizzle/NNNN_*.sql 생성
$EDITOR drizzle/0003_*.sql              # 생성된 SQL을 반드시 읽는다
npx drizzle-kit migrate                 # 로컬 DB에 적용
npm run test:integration                # 실 DB로 회귀 확인
```

```ts
// drizzle.config.ts
import { defineConfig } from 'drizzle-kit'

export default defineConfig({
  schema: './src/db/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: { url: process.env.DATABASE_URL! },
})
```

**운영 적용**: 배포 파이프라인에서 마이그레이션 전용 일회성 태스크로 실행한다. 앱 부팅에서
`migrate()`를 부르면 동시에 뜨는 Fargate 태스크들이 같은 마이그레이션을 경합한다.

**파괴적 변경은 나눈다**: ① nullable 컬럼 추가 + 배포 → ② 백필 + 신구 코드 동시 지원 →
③ NOT NULL 승격 + 구 컬럼 제거. 한 번에 하면 롤백 불가 지점이 생긴다.

## 오용 목록 (버전 관용구 대조표)

| 구 습관 (drizzle-kit 0.20 이하 / 잘못된 사용) | 현재 형태 |
| --- | --- |
| `drizzle-kit generate:pg` | `drizzle-kit generate` (dialect는 설정 파일에서) |
| 설정의 `driver: 'pg'` | `dialect: 'postgresql'` |
| `dbCredentials: { connectionString }` | `dbCredentials: { url }` |
| 인덱스 콜백이 객체 반환 `(t) => ({ idx: index(...) })` | 배열 반환 `(t) => [index(...).on(t.col)]` |
| `drizzle-kit push`로 운영 스키마 변경 | 운영은 `generate` → 리뷰 → `migrate`. `push`는 로컬 실험 전용 |
| 손으로 SQL 먼저 쓰고 schema.ts를 나중에 맞춤 | schema.ts가 원본 — SQL은 항상 `generate` 산출물 |
| `timestamp('at')` (타임존 없음) | `timestamp('at', { withTimezone: true })` |
| `drizzle(pool)` 을 요청마다 생성 | 모듈 스코프 싱글턴 1개 |

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `db.select()` vs `db.query.<t>.findMany()` | 전자는 SQL에 가깝고 조인·집계에 유리, 후자는 relations 선언이 있어야 하고 중첩 로딩에 유리 |
| `eq(notes.ownerId, ownerId)` 누락 | 소유자 조건 없는 쿼리는 이 스택에서 곧 데이터 유출 — 리뷰에서 가장 먼저 본다 |
| `inArray(...)` 단독 사용 | id 목록이 내 행에서 왔다는 것은 필터가 아니다 → `and(eq(t.ownerId, ownerId), inArray(...))` |
| `set(patch)`의 patch 타입을 `Partial<NewNote>`로 | `ownerId`가 실려 소유권이 이전된다 → 파싱된 요청 타입으로 좁힌다 |
| `ssl: { rejectUnauthorized: false }` | 검증 없는 TLS는 중간자에 열린다 → `ca`에 RDS 번들(`DB_CA_PATH`)을 넣고 `true`를 유지한다 |
| `.limit(1)` 없는 단건 조회 | 전체를 끌어와 첫 행만 쓰게 된다 |
| `sql` 템플릿에 문자열 연결 | `sql\`... ${value}\`` 는 바인딩되지만 `sql.raw('...' + v)`는 주입 경로다 |
| `and(...)`에 `false`/`null` 섞기 | 조건 없음은 `undefined`로 넘긴다 — `and()`가 자동으로 제외한다 |
| `.returning()` 생략 | 변이 성공 여부를 알 수 없다. 0행이 성공으로 응답된다 |
| Aurora 전용 함수·Data API | 사용 금지 — 온프레미스 PostgreSQL과 동일 엔진을 유지한다 (`portability-boundaries.md`) |
