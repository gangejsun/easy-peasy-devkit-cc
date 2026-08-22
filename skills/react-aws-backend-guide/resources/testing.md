# 테스트 (Vitest + docker compose 로컬 패리티)

이 스택의 이점은 **로컬이 운영과 같다**는 것이다. `docker compose`가 PostgreSQL 16을 그대로
띄우므로 마이그레이션과 쿼리를 흉내내지 않고 **실제로 실행해** 검증한다.

## 3계층

| 계층 | 대상 | DB | 속도 | 위치 |
| --- | --- | --- | --- | --- |
| 1. 순수 | Zod 스키마, 경로 검증, 커서 인코딩, 도메인 계산 | 없음 | ms | `tests/unit/` |
| 2. 핸들러 | 라우팅·파싱·에러 봉투·인증 분기 | 쿼리 모듈 대역 | 수십 ms | `tests/handler/` |
| 3. 통합 | 마이그레이션·실제 SQL·소유권 격리·제약 위반 | 실 PostgreSQL | 초 | `tests/integration/` |

**소유권 격리는 반드시 3계층에서 검증한다.** 데이터 계층 방어선이 없으므로 "남의 행이 안
나온다"는 사실은 실제 SQL로만 증명된다.

## 테스트 데이터베이스는 개발 DB와 분리한다

`docker-compose.yml` 전문은 `resources/deployment-and-operations.md`에 있다. 테스트가 요구하는
것은 **`app_test`가 실제로 존재한다**는 사실 하나이고, `db` 서비스에 초기화 스크립트를
물려 두면 개발자가 손으로 만들 일이 없다.

```sql
-- docker/init-test-db.sql  (compose가 /docker-entrypoint-initdb.d 에 마운트한다)
CREATE DATABASE app_test OWNER app;
```

- 테스트는 **별도 데이터베이스**(`app_test`)를 쓴다. `afterEach`가 `TRUNCATE`를 돌리므로
  개발 DB를 가리키면 작업 중인 데이터가 사라진다
- **초기화 스크립트는 데이터 볼륨이 처음 만들어질 때만 실행된다.** 이미 볼륨이 있다면
  `docker compose exec db createdb -U app app_test`를 한 번 돌리거나 `down -v`로 다시 만든다 —
  건너뛰면 통합 테스트가 "데이터베이스 없음"으로 죽고 원인이 마이그레이션 실패처럼 보인다

## Vitest 설정 — 먼저 env를 채운다

`@/app`이나 `@/db/client`를 import하는 순간 `@/config/env`가 부팅 검증을 돌리고, 필수 키가
없으면 `process.exit(1)`이 **테스트 워커를 통째로 죽인다.**

```ts
// tests/test-env.ts — 두 vitest 설정이 공유한다. 값은 전부 문자열이다 (env 스키마가 변환한다)
export const testEnv = {
  NODE_ENV: 'test', DB_SSL: 'false', S3_BUCKET: 'test-bucket',
  DATABASE_URL: 'postgres://app:local@localhost:5432/app_test',
  CORS_ORIGINS: 'http://localhost:5173',
  OIDC_ISSUER: 'https://issuer.test',                 // 테스트 토큰의 iss와 같아야 한다
  OIDC_JWKS_URL: 'https://issuer.test/jwks.json',     // 로컬 JWKS 주입 → 호출되지 않는다
  OIDC_AUDIENCE: 'test-client',                       // 테스트 토큰의 client_id와 같아야 한다
  OIDC_AUTHORIZE_BASE: 'https://auth.test',
  SPA_CALLBACK_URL: 'http://localhost:5173/auth/callback',
  SPA_LOGOUT_URL: 'http://localhost:5173/',
  AUTH_STATE_SECRET: 'test-secret-at-least-32-characters-long',
}
```

```ts
// vitest.config.ts  — 1·2계층 (빠름, 병렬)
import path from 'node:path'
import { defineConfig } from 'vitest/config'
import { testEnv } from './tests/test-env'

export default defineConfig({
  resolve: { alias: { '@': path.resolve(__dirname, 'src') } },
  test: {
    environment: 'node',
    env: testEnv,                    // 없으면 @/config/env가 워커를 exit(1)로 끝낸다
    include: ['tests/unit/**/*.test.ts', 'tests/handler/**/*.test.ts'],
  },
})

// vitest.integration.config.ts — 3계층 (실 DB, 직렬). 위 설정에서 다른 부분만:
Object.assign(process.env, testEnv)  // globalSetup은 워커가 아니라 이 프로세스에서 돈다
  test: {
    env: testEnv,
    include: ['tests/integration/**/*.test.ts'],
    globalSetup: ['tests/integration/global-setup.ts'],
    setupFiles: ['tests/integration/setup.ts'],
    fileParallelism: false,          // 같은 DB를 여러 파일이 동시에 비우면 서로를 깬다
    testTimeout: 20_000,
  },
```

- **`test.env`는 워커에만 적용된다.** `globalSetup`은 설정 파일과 같은 프로세스에서 돌므로
  `Object.assign(process.env, testEnv)`가 따로 필요하다 — 없으면 마이그레이션 단계에서
  `@/config/env`가 `exit(1)`을 불러 **Vitest가 실패 메시지 없이 종료된다**
- 두 설정 모두 `resolve.alias`에 `@`를 등록한다. tsconfig의 paths를 Vitest는 읽지 않는다

```json
{
  "scripts": {
    "test": "vitest run",
    "test:integration": "docker compose up -d --wait db && vitest run -c vitest.integration.config.ts",
    "db:migrate": "drizzle-kit migrate"
  }
}
```

**`--wait`가 없으면 경합한다.** `docker compose up -d db`는 컨테이너 *기동 시작*만 보장해
`globalSetup`의 마이그레이션이 초기화 중인 PostgreSQL에 붙는다. `--wait`는 compose의
`healthcheck` 통과까지 기다린다 — 헬스체크 정의가 곧 계약이다.

## 1계층 — 순수 테스트

값이 들어가고 값이 나오는 것만 테스트한다. 가장 싸고 가장 자주 깨진다.

```ts
// tests/unit/return-path.test.ts
import { expect, it } from 'vitest'
import { safeReturnPath } from '@/http/return-path'

it.each([
  ['/notes/42?tab=1', '/notes/42?tab=1'],
  ['//evil.com', '/'],              // 스킴 상대 URL
  ['/\\evil.com', '/'],             // 역슬래시는 브라우저가 /로 취급한다
  ['https://evil.com', '/'],
  ['/notes\n/x', '/'],              // 제어문자 삽입
])('safeReturnPath: %s → %s', (i, expected) => expect(safeReturnPath(i)).toBe(expected))
```

Zod 스키마도 같은 방식으로 고정한다 — 미지 키·상한 초과 거절, 기본값 적용, 그리고
**`UpdateNoteInput.safeParse({})`가 실패하는지**(빈 PATCH 거절 = 남은 기본값 없음).

## 2계층 — 핸들러 테스트

`app.request()`로 서버 없이 호출한다. **검증기와 쿼리 모듈만 대역으로** 바꾼다.

```ts
// tests/handler/notes.post.test.ts
import { describe, expect, it, vi } from 'vitest'

vi.mock('@/db/queries/notes', () => ({
  insertNote: vi.fn(async (ownerId: string, input: { title: string }) =>
    ({ id: 'n1', ownerId, title: input.title, body: '', createdAt: new Date() })),
}))
vi.mock('@/http/auth', async (orig) => ({
  ...(await orig<typeof import('@/http/auth')>()),
  requireAuth: async (c: any, next: any) => {           // 서명 검증만 대역으로 대체
    c.set('user', { sub: 'user-1', groups: [] })
    await next()
  },
}))

const { app } = await import('@/app')
const post = (body: unknown) => app.request('/api/notes', {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
})

describe('POST /api/notes', () => {
  it('검증을 통과하면 201과 data 봉투를 반환한다', async () => {
    const res = await post({ title: '첫 노트' })
    expect(res.status).toBe(201)
    expect((await res.json()).data.title).toBe('첫 노트')
  })
  it('title이 비면 422와 필드 오류를 반환한다', async () => {
    const res = await post({ title: '' })
    expect(res.status).toBe(422)
    const body = await res.json()
    expect(body.error.code).toBe('VALIDATION_FAILED')
    expect(body.error.details.title).toBeDefined()
  })
})
```

`requireAuth`는 검증기를 주입받는 팩토리라, 대역 없이 키 소스만 바꿔 **진짜 검증 경로**를 돌릴 수도 있다 (아래).

## 3계층 — 실 DB 통합 테스트

```ts
// tests/integration/global-setup.ts — 스위트 전체에서 1회
import { migrate } from 'drizzle-orm/node-postgres/migrator'
import { db, pool } from '@/db/client'

export default async function setup() {
  await migrate(db, { migrationsFolder: './drizzle' })   // 실제 마이그레이션을 그대로 적용
  return async () => { await pool.end() }
}

// tests/integration/setup.ts — 테스트마다 격리
import { afterEach } from 'vitest'
import { sql } from 'drizzle-orm'
import { env } from '@/config/env'

// 개발 DB를 TRUNCATE하지 않는다. 접속 문자열은 비밀이므로 메시지에 싣지 않는다
if (!env.DATABASE_URL.endsWith('/app_test')) throw new Error('tests must target app_test')

afterEach(async () => {
  // 마이그레이션 기록은 drizzle 스키마에 있으므로 public만 비우면 된다
  await db.execute(sql`
    DO $$ DECLARE t text;
    BEGIN
      FOR t IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
      LOOP EXECUTE format('TRUNCATE TABLE %I RESTART IDENTITY CASCADE', t); END LOOP;
    END $$;`)
})
```

```ts
// tests/integration/notes.ownership.test.ts
import { describe, expect, it } from 'vitest'
import { insertNote, findOwnedNote, updateOwnedNote, deleteOwnedNote } from '@/db/queries/notes'

const ALICE = '11111111-1111-1111-1111-111111111111'
const BOB = '22222222-2222-2222-2222-222222222222'
const note = (title: string) => ({ title, body: '' })      // insertNote는 파싱된 입력을 받는다

describe('소유권 격리', () => {
  it('다른 사용자의 노트는 조회되지 않는다', async () => {
    const row = await insertNote(ALICE, note('alice의 노트'))
    expect(await findOwnedNote(BOB, row.id)).toBeNull()
  })
  it('다른 사용자의 노트 수정은 0행이다', async () => {
    const row = await insertNote(ALICE, note('alice의 노트'))
    expect(await updateOwnedNote(BOB, row.id, { title: 'hijacked' })).toBeNull()
    expect((await findOwnedNote(ALICE, row.id))!.title).toBe('alice의 노트')
  })
  it('다른 사용자의 노트 삭제는 0행이다', async () => {
    const row = await insertNote(ALICE, note('alice의 노트'))
    expect(await deleteOwnedNote(BOB, row.id)).toBe(0)
  })
  it('같은 사용자의 제목 중복은 23505로 거절된다', async () => {
    await insertNote(ALICE, note('중복'))
    await expect(insertNote(ALICE, note('중복'))).rejects.toMatchObject({ code: '23505' })
    await expect(insertNote(BOB, note('중복'))).resolves.toBeDefined()   // 사용자별 유일
  })
})
```

새 리소스마다 이 네 가지(조회·수정·삭제·제약)를 복제한다. **소유권 필터 누락은 리뷰보다 이
테스트가 더 확실하게 잡는다.**

## 실제 토큰으로 인증 경로를 테스트하려면

**로컬 키쌍으로 서명하고 그 공개키를 검증기에 그대로 꽂는다.** 네트워크 없이 `jwtVerify`
경로 전체(서명·발급자·대상·만료)가 운영과 동일하게 돈다.

```ts
// tests/handler/auth.test.ts
import { Hono } from 'hono'
import { expect, it } from 'vitest'
import { SignJWT, createLocalJWKSet, exportJWK, generateKeyPair } from 'jose'
import { makeJwksVerifier, makeRequireAuth } from '@/http/auth'
import { onError } from '@/http/errors'
import type { AppEnv } from '@/http/types'

const { privateKey, publicKey } = await generateKeyPair('RS256')
const jwk = { ...(await exportJWK(publicKey)), kid: 'test', alg: 'RS256', use: 'sig' }
const jwks = createLocalJWKSet({ keys: [jwk] })

const sign = (over: { iss?: string; exp?: string; client_id?: string } = {}) =>
  new SignJWT({ token_use: 'access', client_id: over.client_id ?? 'test-client' })
    .setProtectedHeader({ alg: 'RS256', kid: 'test' })
    .setIssuer(over.iss ?? 'https://issuer.test').setSubject('user-1')
    .setIssuedAt().setExpirationTime(over.exp ?? '5m')
    .sign(privateKey)

const app = new Hono<AppEnv>()
app.use('*', makeRequireAuth(makeJwksVerifier(jwks)))   // ← 로컬 JWKS가 실제로 연결되는 지점
app.get('/me', (c) => c.json({ data: { sub: c.get('user').sub } }))
app.onError(onError)

const call = (token?: string) =>
  app.request('/me', token ? { headers: { Authorization: `Bearer ${token}` } } : {})

it('유효한 토큰은 통과한다', async () =>
  expect((await (await call(await sign())).json()).data.sub).toBe('user-1'))

it.each([
  ['만료', await sign({ exp: '-1m' })],
  ['다른 발급자', await sign({ iss: 'https://evil.test' })],
  ['다른 client_id', await sign({ client_id: 'other-app' })],
  ['토큰 없음', undefined],
])('%s → 동일한 401 UNAUTHORIZED 봉투', async (_label, token) => {
  const res = await call(token)
  expect(res.status).toBe(401)
  expect((await res.json()).error.code).toBe('UNAUTHORIZED')
  expect(res.headers.get('WWW-Authenticate')).toBe('Bearer')
})
```

네 경우가 **같은 상태·같은 코드·같은 메시지**를 내야 한다. 사유가 응답에서 갈리면 공격자가
"대상이 다른 유효 토큰"과 "서명 위조"를 구분할 수 있게 된다.

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `app.request()` vs supertest | Hono는 `app.request()`로 충분하다. 서버를 띄우면 포트 경합과 종료 누수가 생긴다 |
| `test.env` 없이 `@/app` import | `config/env`가 `exit(1)`을 부르고 워커가 죽는다 → 두 설정 모두 `env`를 채우고, `globalSetup`은 워커 밖이므로 설정 파일에서 `Object.assign(process.env, ...)` |
| `docker compose up -d db` (`--wait` 없음) | 기동 시작만 보장한다 → 마이그레이션이 초기화 중인 DB와 경합한다 |
| `drizzle-kit push` vs `migrate` (테스트) | 테스트는 `migrate` — 운영에 나갈 SQL을 그대로 검증해야 의미가 있다 |
| 통합 테스트 병렬 실행 | 같은 DB를 공유하면 TRUNCATE가 서로를 지운다 → `fileParallelism: false` 또는 워커별 DB |
| `beforeEach` 삽입 vs 픽스처 파일 | 테스트가 필요한 행만 그 테스트 안에서 만든다. 공유 시드는 테스트 간 결합을 만든다 |
| DB 모킹 vs 실 DB | 쿼리 정확성(소유권·제약·인덱스)은 모킹으로 증명되지 않는다. 모킹은 2계층까지만 |
| `vi.mock` 호이스팅 | `vi.mock`은 import보다 먼저 끌어올려진다 → 대역이 필요한 모듈은 `await import()`로 나중에 로드 |
| `expect(res.body)` | `app.request()`는 표준 `Response`를 준다 → `await res.json()` |
| 테스트가 개발 DB를 가리킴 | `DATABASE_URL`이 `app_test`인지 `setup.ts`에서 단언한다. 아니면 개발 데이터가 사라진다 |
