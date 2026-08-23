<!-- epcc-seam: react-vite+aws-container/backend v3.12.0 -->
# 인증과 권한 (OIDC/JWKS + 애플리케이션 층 소유권)

Cognito는 **토큰 발급자**일 뿐이다. 백엔드는 표준 OIDC 검증만 하므로 발급자를 Keycloak 등으로
바꿔도 `OIDC_ISSUER` / `OIDC_JWKS_URL` / `OIDC_AUDIENCE` 세 값만 바뀐다.

## 토큰 흐름

```
SPA ──(Authorization Code + PKCE)──► Cognito Hosted UI ──► access token / id token
SPA ──(Authorization: Bearer <access token>)──► ALB ──► Hono: JWKS로 서명 검증
```

- 백엔드는 **액세스 토큰만** 받는다. 토큰을 발급하지도, 세션을 저장하지도 않는다 (무상태)
- 토큰은 `Authorization` 헤더로만 받는다. **쿼리 문자열 토큰은 거부한다** — URL은 ALB
  액세스 로그·브라우저 히스토리·리퍼러에 남는다
- SPA는 토큰을 메모리에 두고 리프레시로 갱신한다. `localStorage`는 XSS 한 번에 전부 털린다

## `requireAuth` (`src/http/auth.ts`)

**키 소스를 주입받는 팩토리 하나**로 쓴다. 운영은 원격 JWKS, 테스트는 로컬 JWKS를 넣으므로
검증 경로가 테스트에서도 그대로 돈다 (`resources/testing.md`).

```ts
import { createMiddleware } from 'hono/factory'
import { createRemoteJWKSet, jwtVerify, type JWTPayload, type JWTVerifyGetKey } from 'jose'
import { env } from '@/config/env'
import { AppError } from '@/http/errors'
import type { AppEnv } from '@/http/types'

export type AuthUser = { sub: string; email?: string; groups: string[] }
export type TokenVerifier = (token: string) => Promise<AuthUser>

// 실패 사유를 구분하지 않는다 — 만료·서명 불일치·발급자 불일치 모두 같은 응답
const unauthorized = () => new AppError(401, 'UNAUTHORIZED', 'Authentication required')

export const makeJwksVerifier = (keys: JWTVerifyGetKey): TokenVerifier => async (token) => {
  const { payload } = await jwtVerify(token, keys, {
    issuer: env.OIDC_ISSUER,
    algorithms: ['RS256'],            // 허용 알고리즘 고정 (alg 혼동 공격 차단)
    clockTolerance: 5,
  })
  if (!isIntendedAudience(payload) || !payload.sub) throw unauthorized()
  return {
    sub: payload.sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    groups: readGroups(payload),
  }
}

export const makeRequireAuth = (verify: TokenVerifier) =>
  createMiddleware<AppEnv>(async (c, next) => {
    const header = c.req.header('Authorization')
    const token = header?.startsWith('Bearer ') ? header.slice(7).trim() : undefined
    if (!token) throw unauthorized()
    let user: AuthUser
    try {
      user = await verify(token)
    } catch {
      throw unauthorized()            // 사유는 여기서 전부 하나로 합쳐진다
    }
    c.set('user', user)
    await next()
  })

// 운영 기본값: 원격 JWKS는 모듈 스코프에서 1회만 만든다 (공개키 캐시 + 자동 갱신)
export const verifyWithJwks = makeJwksVerifier(createRemoteJWKSet(new URL(env.OIDC_JWKS_URL)))
export const requireAuth = makeRequireAuth(verifyWithJwks)
```

### 대상(audience) 확인은 발급자마다 클레임이 다르다

**Cognito 액세스 토큰에는 `aud`가 없다.** 클라이언트 식별자가 `client_id`에 들어 있고,
`aud`는 ID 토큰에만 있다. 다른 IdP(Keycloak 등)는 액세스 토큰에도 `aud`를 넣는다.
그래서 두 이름을 모두 받아들이되 **일치는 반드시 요구한다**.

```ts
function isIntendedAudience(p: JWTPayload): boolean {
  const claim = p.aud ?? (p as Record<string, unknown>).client_id
  const ok = Array.isArray(claim) ? claim.includes(env.OIDC_AUDIENCE) : claim === env.OIDC_AUDIENCE
  if (!ok) return false
  // Cognito는 token_use로 토큰 종류를 구분한다. 없는 발급자도 있으므로 있을 때만 본다.
  const use = (p as Record<string, unknown>).token_use
  return typeof use === 'string' ? use === 'access' : true
}
```

`aud`/`client_id` 확인을 생략하면 **같은 사용자 풀의 다른 앱에 발급된 토큰**이 이 API에서
그대로 통과한다.

### 역할 클레임은 어댑터 한 곳에서 정규화한다

```ts
function readGroups(p: JWTPayload): string[] {
  const raw = (p as Record<string, unknown>)[env.OIDC_GROUPS_CLAIM]   // 기본 'cognito:groups'
  return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === 'string') : []
}

export const requireGroup = (group: string) =>
  createMiddleware<AppEnv>(async (c, next) => {
    if (!c.get('user').groups.includes(group)) {
      throw new AppError(403, 'FORBIDDEN', '이 작업에 필요한 권한이 없습니다')
    }
    await next()
  })
```

발급자 고유 클레임 이름은 `env`로 뺀다. Keycloak은 `realm_access.roles`처럼 중첩이므로
이관 시 **이 함수 하나만** 고친다.

## 401은 JSON, 리다이렉트는 없다

클라이언트가 SPA 하나뿐이라 이 백엔드에는 페이지 경로가 없다. 미인증 응답은 항상
인증 오류 봉투다. 로그인 화면으로 보낼지는 **SPA가** 401을 보고 결정한다.

401일 때만 표준 챌린지 헤더(`WWW-Authenticate: Bearer`)를 붙인다. 이 분기는 **`onError`
안에만** 있다 (`resources/api-endpoints.md`의 `src/http/errors.ts`) — 미들웨어나 핸들러에서
따로 헤더를 붙이면 401 응답 경로가 둘로 갈라진다.

## 권한 판정은 서비스 층에서, 필터는 쿼리에서

이 스택에는 행 수준 정책 엔진이 없다. **애플리케이션 층이 유일한 경계다.**

```ts
// src/services/tasks.ts
export async function updateTask(ownerId: string, id: string, patch: UpdateTaskInput) {
  const updated = await updateOwnedTask(ownerId, id, patch)   // 소유권이 WHERE에 있다
  if (!updated) throw new AppError(404, 'NOT_FOUND', 'Task not found')
  return updated
}
```

```ts
// ❌ 존재를 누설한다 — id를 훑으면 남의 리소스 목록이 만들어진다
const task = await findTask(id)
if (!task) throw new AppError(404, 'NOT_FOUND', '...')
if (task.ownerId !== ownerId) throw new AppError(403, 'FORBIDDEN', '...')
```

- **부재와 미인가는 동일한 404**다. 403은 소유권이 아닌 축(관리자 전용 엔드포인트 등)에만
- 소유자는 언제나 검증된 토큰의 `sub`다. 본문·쿼리·헤더의 `ownerId`는 읽지 않는다

관리자 조회가 필요하면 `ownerId` 조건을 빼는 대신 **별도 파일의 별도 함수**로 분리한다.
같은 함수에 `isAdmin` 플래그를 넣지 않는다 — 플래그 하나가 잘못 흘러오면 전 테이블이 열린다.

```ts
// src/db/queries/admin-tasks.ts — 소유자 조건이 없는 유일한 파일 (파일 단위로 격리한다)
export async function findAnyTask(id: string) {
  const [row] = await db.select().from(tasks).where(eq(tasks.id, id)).limit(1)
  return row ?? null
}

// src/routes/admin.ts — 이 서브 앱 전체가 requireGroup('admin') 뒤에 있다
export const adminRoutes = new Hono<AppEnv>()
adminRoutes.use('*', requireGroup('admin'))
adminRoutes.get('/tasks/:id', async (c) => {
  const task = await findAnyTask(pathParam(c, TaskIdParam).id)
  if (!task) throw new AppError(404, 'NOT_FOUND', 'Task not found')   // 부재도 미인가도 404
  return c.json({ data: task })
})
```

`grep -rn "admin-tasks" src/`가 곧 감사 목록이다 — `queries/tasks.ts`에는 소유자 인자 없는 함수가 **하나도 없어야 한다.**

## 로그인 · 가입 · 로그아웃 · 복귀 경로

인증 화면은 Cognito Hosted UI가 담당하고, 백엔드는 **URL을 만들어 주는 역할**만 한다.
바로 이 지점이 오픈 리다이렉트가 생기는 곳이다.

```ts
// src/routes/auth.ts — 공개 라우트다. app.ts에서 requireAuth **앞에** 마운트한다:
//   app.route('/api/auth', authRoutes)   →   app.use('/api/*', requireAuth)
import { createHmac, timingSafeEqual } from 'node:crypto'
import { Hono } from 'hono'
import { env } from '@/config/env'
import { AppError } from '@/http/errors'
import { safeReturnPath } from '@/http/return-path'
import type { AppEnv } from '@/http/types'

export const authRoutes = new Hono<AppEnv>()

authRoutes.get('/login-url', (c) => {
  const returnTo = safeReturnPath(c.req.query('returnTo'))     // ← 반드시 서버에서 검증
  const url = new URL('/oauth2/authorize', env.OIDC_AUTHORIZE_BASE)
  url.searchParams.set('response_type', 'code')
  url.searchParams.set('client_id', env.OIDC_AUDIENCE)
  url.searchParams.set('redirect_uri', env.SPA_CALLBACK_URL)   // 고정 값 — 입력에서 받지 않는다
  url.searchParams.set('scope', 'openid email')
  url.searchParams.set('state', signState({ returnTo }))       // 서명해서 위조를 막는다
  return c.json({ data: { url: url.toString(), returnTo } })
})

// 콜백에서 state를 되돌려 준다 — 서명이 맞아야만 복귀 경로가 나온다
authRoutes.get('/return-path', (c) => {
  const claims = verifyState(c.req.query('state'))
  if (!claims) throw new AppError(400, 'BAD_REQUEST', 'state가 올바르지 않습니다')
  return c.json({ data: { returnTo: claims.returnTo } })
})
```

**`signState`에는 반드시 짝이 되는 검증이 있어야 한다.** 서명만 하고 콜백에서 확인하지
않으면 서명은 장식이다. 토큰 교환은 SPA가 PKCE로 직접 하므로 백엔드의 몫은 이 한 쌍뿐이다.

```ts
// src/routes/auth.ts (계속)
const mac = (payload: string) =>
  createHmac('sha256', env.AUTH_STATE_SECRET).update(payload).digest('base64url')

export function signState(claims: { returnTo: string }): string {
  const payload = Buffer.from(JSON.stringify({ ...claims, iat: Date.now() })).toString('base64url')
  return `${payload}.${mac(payload)}`
}

export function verifyState(raw: string | undefined, maxAgeMs = 10 * 60_000) {
  const [payload, sig] = (raw ?? '').split('.')
  if (!payload || !sig) return null
  const expected = Buffer.from(mac(payload))
  const got = Buffer.from(sig)
  // 길이를 먼저 맞춘다 — timingSafeEqual은 길이가 다르면 예외를 던진다
  if (got.length !== expected.length || !timingSafeEqual(got, expected)) return null
  try {
    const c = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8'))
    if (typeof c.iat !== 'number' || Date.now() - c.iat > maxAgeMs) return null   // 재생 창을 좁힌다
    return { returnTo: safeReturnPath(c.returnTo) }        // 복호 후에도 경로를 다시 검증한다
  } catch {
    return null
  }
}
```

- 비교는 `===`가 아니라 `timingSafeEqual`이다 — 문자열 비교는 일치 길이를 시간으로 흘린다
- 서명 안의 값도 **꺼낸 뒤 다시 검증한다.** 서명은 "우리가 만들었다"만 증명하지, 그 값이
  지금도 안전한 경로라는 것을 증명하지 않는다 (검증 규칙이 나중에 강화될 수도 있다)

`signUp`은 같은 authorize URL에서 경로만 `/signup`으로 바뀌므로 위 규칙이 그대로 적용된다.
**로그아웃은 다르다.** Cognito `/logout`은 `client_id`와 `logout_uri`만 받는다 —
`response_type`·`redirect_uri`·`state`를 쓰지 않으며, `logout_uri`는 앱 클라이언트에
**사전 등록된 sign-out URL과 정확히 일치**해야 한다.

```ts
authRoutes.get('/logout-url', (c) => {
  const url = new URL('/logout', env.OIDC_AUTHORIZE_BASE)
  url.searchParams.set('client_id', env.OIDC_AUDIENCE)
  url.searchParams.set('logout_uri', env.SPA_LOGOUT_URL)   // 등록된 고정 값 — 입력이 아니다
  return c.json({ data: { url: url.toString() } })
})
```

복귀 경로를 `logout_uri`에 싣지 않는다. 입력값은 등록 목록에 없어 거절되고, 그 URL들을 전부
등록하면 오픈 리다이렉트 목록을 IdP에 만드는 셈이다 — 복귀 경로는 SPA가 로컬에 기억한다.

```ts
// src/http/return-path.ts
const CONTROL_CHARS = /[\u0000-\u001F\u007F]/

export function safeReturnPath(raw: string | undefined, fallback = '/'): string {
  if (!raw) return fallback
  if (CONTROL_CHARS.test(raw)) return fallback        // 개행·탭은 브라우저가 제거 후 재파싱한다
  if (!raw.startsWith('/')) return fallback           // 절대 URL·스킴 상대 거절
  try {
    const u = new URL(raw, 'https://internal.invalid')
    if (u.origin !== 'https://internal.invalid') return fallback   // //host, /\host 를 잡는다
    return u.pathname + u.search + u.hash
  } catch {
    return fallback
  }
}
```

**문자열 prefix 검사만으로는 부족하다.** `//evil.com`과 `/\evil.com`은 `/`로 시작하지만 브라우저는
외부 URL로 파싱한다(`\`는 특수 스킴에서 `/`와 같다). **파싱 후 origin이 유지되는지**를 확인해야
잡히며, `%09`·`%0A` 제어문자 삽입도 같은 이유로 먼저 거른다.

인증 실패 응답은 일반화한다: 없는 계정과 틀린 비밀번호를 구분해 알리면 계정 존재가 열거된다.
그 화면은 Hosted UI의 몫이고, 백엔드는 **토큰 검증 실패 사유를 구분하지 않는 것**으로 같은 원칙을 지킨다.

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| ID 토큰 vs 액세스 토큰 | API 호출은 **액세스 토큰**. ID 토큰은 SPA가 사용자 표시용으로 쓰는 것이며 API 인가에 쓰지 않는다 |
| `aws-jwt-verify` vs `jose` | 표준 OIDC 검증은 `jose` — 발급자 교체 가능. 전자는 Cognito 전용이라 이식 경계를 깬다 |
| `decodeJwt()` vs `jwtVerify()` | `decodeJwt`는 **서명을 확인하지 않는다**. 인가 판단에 절대 쓰지 않는다 (디버깅 전용) |
| `createRemoteJWKSet` vs 키 하드코딩 | 발급자는 키를 회전한다. 원격 JWKS + 캐시를 쓰고, 오프라인 테스트에만 `createLocalJWKSet` |
| 미들웨어를 요청마다 생성 | `createRemoteJWKSet`은 모듈 스코프에서 1회 — 핸들러 안에서 만들면 매 요청 키를 새로 받는다 |
| `app.use('*', requireAuth)` | `/healthz`까지 401이 되어 ALB가 태스크를 순환시킨다 → `/api/*`에만, 공개 라우트 등록 뒤에 건다 |
| 로그아웃 URL을 authorize와 같은 규칙으로 | Cognito `/logout`은 `client_id` + `logout_uri`만 받는다. `redirect_uri`·`state`·`response_type`은 무시되고 `logout_uri`는 사전 등록 값과 정확히 일치해야 한다 |
| 401 vs 403 | 401은 "누구인지 모른다", 403은 "알지만 역할이 부족하다". **소유권 실패는 둘 다 아니고 404** |
| `c.get('user')` 옵셔널 취급 | `requireAuth` 뒤에서는 항상 존재한다. `?.`로 감싸면 인증 없는 경로에 붙었다는 사실이 가려진다 |
| `exp` 수동 비교 | `jwtVerify`가 이미 검증한다. 별도 비교는 clockTolerance와 어긋나 이중 기준을 만든다 |
| 요청 본문의 `userId` 신뢰 | 소유자는 `c.get('user').sub`뿐이다. 본문 값은 곧 계정 위장 |
