<!-- epcc-seam: vue+node-api v3.13.0 -->
# 인증/미들웨어 경계 — 베어러 토큰과 재발급

이 파일이 소유하는 코드 파일은 셋이다: `src/http/tokens.ts` · `src/http/require-auth.ts` ·
`src/http/routers/auth.ts`. 그리고 테스트 인증 헤더 `authFor`(`src/test/auth.ts`)를 준다.
봉투·`errorHandler`·CORS는 `resources/api-endpoints.md`, 소유권 쿼리는
`resources/data-access.md`, 상태 매핑표는 `resources/error-handling.md`가 소유한다.

> **이 축에는 데이터 계층 정책 엔진이 없다.** 애플리케이션이 신뢰된 연결로 PostgreSQL에
> 붙으므로 이 파일의 미들웨어와 쿼리의 `where`가 **유일한 경계다.** "데이터 계층이 백업하니
> 이중 방어"는 여기서 거짓이고, 그렇게 쓰면 안전하다고 착각하게 만든다.

## 1. 판단 — 세션 쿠키가 아니라 베어러 토큰인 이유

인증 방식은 백엔드 축이 정하지 않는다. **프론트 축에 서버 런타임이 있는가**가 가른다. 이
조합의 프론트는 Vue SPA다 — 브라우저가 이 API 오리진을 **직접** 때리고, 자격 증명을 숨겨 줄
중간 런타임이 없다.

| 축 조건 | 자연스러운 방식 | 그 이유 |
| --- | --- | --- |
| 프론트에 서버 런타임이 있다 (SSR·BFF) | 세션 쿠키 | 쿠키가 같은 오리진 안에 머문다 |
| **프론트가 SPA이고 오리진이 다르다 (이 조합)** | **베어러 토큰** | 세션 쿠키를 쓰려면 교차 사이트 쿠키 + CSRF 방어가 전부 필요해진다 |
| 서버 간 호출 | 서명된 서비스 토큰 | 브라우저가 없다 |

베어러 토큰의 이점은 **CSRF가 원천적으로 없다**는 것이다. 브라우저가 `Authorization`을 스스로
붙이지 않으므로 공격자 페이지의 요청에는 토큰이 실리지 않는다. 대가는 반대쪽에 있다 — JS가
토큰을 들고 있어야 해서 XSS 한 번이면 샌다. 그래서 둘로 나눈다: **액세스 토큰은 짧게(15분)
살고, 재발급 토큰은 JS가 볼 수 없는 httpOnly 쿠키에 둔다.** 액세스 토큰을 프론트 어디에
두는가는 프론트 이음매가 소유한다.

## 2. 액세스 토큰 (`src/http/tokens.ts`)

HS256 JWT를 자체 발급한다. 서명·해시는 `node:crypto`가 하고 이 파일이 쓰는 것은 **인코딩과
검사 순서**다. RS256·JWKS·외부 IdP가 필요해지면 이 파일을 검증 라이브러리로 갈아 끼운다 —
`requireAuth`가 보는 표면은 `verifyAccessToken` 하나뿐이라 그 교체가 국소적이다.

먼저 `src/env.ts`의 `EnvSchema`에 세 줄을 더한다. 비밀은 코드에 두지 않는다.

```ts
// src/env.ts — EnvSchema에 더하는 줄 (발췌)
  AUTH_JWT_SECRET: z.string().min(32, '32자 이상이어야 합니다'),
  AUTH_ACCESS_TTL_SEC: z.coerce.number().int().min(60).max(3600).default(900),
  WEB_ORIGINS: z.string().min(1).transform((s) => s.split(',').map((o) => o.trim())).pipe(z.array(z.url()).min(1)),
```

<!-- file: src/http/tokens.ts -->
```ts
import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import { AppError } from './app-error';
import { env } from '../env';

export type AccessClaims = { sub: string; roles: string[]; iat: number; exp: number };

// 헤더를 상수로 굳힌다. 토큰이 실어 온 alg를 읽어 분기하지 않으므로 alg=none·알고리즘
// 혼동이 도달할 경로 자체가 없다.
const HEADER = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
const deny = () => new AppError('UNAUTHENTICATED', '인증에 실패했습니다');

function mac(data: string): Buffer {
  return createHmac('sha256', env.AUTH_JWT_SECRET).update(data).digest();
}

export function signAccessToken(sub: string, roles: string[] = []): string {
  const iat = Math.floor(Date.now() / 1000);
  const claims: AccessClaims = { sub, roles, iat, exp: iat + env.AUTH_ACCESS_TTL_SEC };
  const data = `${HEADER}.${Buffer.from(JSON.stringify(claims)).toString('base64url')}`;
  return `${data}.${mac(data).toString('base64url')}`;
}

export function verifyAccessToken(token: string): AccessClaims {
  const [h, p, s, ...rest] = token.split('.');
  if (!h || !p || !s || rest.length > 0) throw deny();
  if (h !== HEADER) throw deny();
  const got = Buffer.from(s, 'base64url');
  const want = mac(`${h}.${p}`);
  // 길이를 먼저 보는 이유: timingSafeEqual은 길이가 다르면 RangeError를 던진다.
  // HMAC-SHA256은 언제나 32바이트이므로 길이 불일치는 그 자체로 위조이고, 여기서
  // 새는 정보는 없다. 값 비교는 상수 시간으로 한다.
  if (got.length !== want.length || !timingSafeEqual(got, want)) throw deny();
  let c: AccessClaims;
  try { c = JSON.parse(Buffer.from(p, 'base64url').toString('utf8')) as AccessClaims; }
  catch { throw deny(); }
  if (typeof c.sub !== 'string' || c.sub === '') throw deny();
  if (typeof c.exp !== 'number' || c.exp * 1000 <= Date.now()) throw deny();
  return { sub: c.sub, roles: Array.isArray(c.roles) ? c.roles : [], iat: c.iat, exp: c.exp };
}

export function newRefreshToken(): { token: string; hash: string } {
  const token = randomBytes(32).toString('base64url');   // CSPRNG. Math.random을 쓰지 않는다
  return { token, hash: hashRefreshToken(token) };
}

export function hashRefreshToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}
```

<!-- verified: node v24.7.0 + express@5.2.1 + supertest@7.2.2 실행 — 서명 왕복, 페이로드 변조, alg=none 헤더로 교체, 만료 토큰, 스킴 오류(`Basic`), 토큰 없는 `Bearer` 6입력을 실제 요청으로 보내 전부 401 UNAUTHENTICATED를 관측 -->
검증 실패는 **사유를 구분하지 않는다.** 여섯 가지 실패가 전부 같은 401과 같은 문구로 나가고
`details`도 없다 — 어느 검사에서 걸렸는지 알려주면 공격자가 형태를 좁힌다.

`timingSafeEqual`은 길이가 다르면 `RangeError: Input buffers must have the same byte length`를
던진다. <!-- verified: node v24.7.0 실행 — 31바이트와 32바이트 버퍼로 호출해 예외 문구를 관측 --> 그래서 길이 검사가 먼저 온다. 재발급 토큰은 **원문을 저장하지 않는다** —
`sha256` 해시만 넣어 DB 유출이 곧 세션 탈취가 되지 않게 한다.

## 3. `requireAuth`와 `AuthUser` (`src/http/require-auth.ts`)

<!-- file: src/http/require-auth.ts -->
```ts
import type { RequestHandler } from 'express';
import { AppError } from './app-error';
import { verifyAccessToken } from './tokens';

export type AuthUser = { id: string; roles: string[] };

declare global {
  namespace Express {
    interface Request { user?: AuthUser }
  }
}

export const requireAuth: RequestHandler = (req, _res, next) => {
  const raw = req.get('authorization') ?? '';
  const [scheme, token] = raw.split(' ');
  if (scheme?.toLowerCase() !== 'bearer' || !token) {
    throw new AppError('UNAUTHENTICATED', '인증에 실패했습니다');
  }
  const claims = verifyAccessToken(token);
  req.user = { id: claims.sub, roles: claims.roles };
  next();
};

export function requireRole(role: string): RequestHandler {
  return (req, _res, next) => {
    if (!req.user?.roles.includes(role)) throw new AppError('FORBIDDEN', '권한이 없습니다');
    next();
  };
}
```

`user`를 **선택 속성으로** 선언한다. 필수로 선언하면 `requireAuth`가 걸리지 않은 라우터에서도
타입이 "있다"고 말해 주고, 그 거짓말이 정확히 인가 사고가 나는 자리다. 소비 측은 `!` 단언
대신 던지는 접근자(`actor()`, `resources/api-endpoints.md` 5절)를 쓴다 — 실측에서 두 형태는
401과 500으로 갈렸다.

주체는 **검증된 토큰에서만** 온다. 요청 본문·쿼리·헤더의 `ownerId`는 공격자가 고르는 값이다.
`TaskCreateSchema`가 `z.strictObject`인 것이 그 두 번째 층이다 — 본문에 `ownerId`를 실으면
전개 순서를 논하기 전에 400으로 거부된다.
<!-- verified: express@5.2.1 + zod@4.4.3 실행 — `{ title:'침입', ownerId:'owner-2' }`를 POST 하니 400 VALIDATION_FAILED, 타인 행의 ownerId는 그대로였다 -->

## 4. 역할은 403, 소유권은 404

둘을 섞으면 안전 장치가 정보 누설 장치가 된다. 판단 기준은 하나다 — **그 응답을 받은 사람이
그 사실만으로 새로 알게 되는 것이 있는가.**

| 상황 | 응답 | 왜 |
| --- | --- | --- |
| 토큰이 없거나 검증 실패 | 401 `UNAUTHENTICATED` | 누구인지 모른다 |
| 남의 `Task`를 조회·수정·삭제 | 404 `NOT_FOUND` | 403이면 그 id가 실재한다는 답이 된다 |
| 역할이 모자란 관리자 경로 | 403 `FORBIDDEN` | 경로의 존재는 이미 공개 정보다 |

```ts
// src/http/routers/admin.ts — 역할이 필요한 라우터
// ❌ 소유권 실패를 403으로 낸다 — id를 훑으면 어떤 id가 실재하는지 알 수 있다
if (task.ownerId !== actor(req).id) throw new AppError('FORBIDDEN', '권한이 없습니다');
// ✅ 역할 검사만 403이다. 소유권은 쿼리 조건이고 결과가 없으면 404다
adminRouter.use(requireAuth, requireRole('admin'));
```

## 5. 로그인 · 재발급 · 로그아웃 (`src/http/routers/auth.ts`)

계약은 이렇게 정한다 — 프론트가 401을 받으면 **1회 재발급을 시도하고, 재실패면 로그인으로
보낸다.**

```ts
// src/http/routers/auth.ts — 쿠키 설정과 세 엔드포인트
// 프로덕션에서만 교차 사이트다. SameSite=None은 Secure를 요구하고, Secure 쿠키는 평문
// http로 되돌아오지 않는다 — 개발은 프론트 개발 서버가 /api를 프록시해 같은 오리진으로
// 만들고 lax를 쓴다.
const CROSS_SITE = env.NODE_ENV === 'production';

function setRefreshCookie(res: Response, token: string): void {
  res.cookie(RT, token, {
    httpOnly: true, secure: CROSS_SITE, sameSite: CROSS_SITE ? 'none' : 'lax',
    path: '/api/auth', maxAge: 14 * 864e5,
  });
}

authRouter.post('/login', async (req, res) => {
  const { email, password } = parseBody(LoginSchema, req);
  const user = authenticate(email, password);   // 실패는 AppError('UNAUTHENTICATED')
  setRefreshCookie(res, await issueRefreshToken(user.id));
  res.json({ data: { accessToken: signAccessToken(user.id, user.roles), expiresIn: env.AUTH_ACCESS_TTL_SEC } });
});

authRouter.post('/refresh', async (req, res) => {
  requireAllowedOrigin(req);                    // 쿠키 인증 라우트의 CSRF 방어
  const raw = readCookie(req, RT);
  if (!raw) throw new AppError('UNAUTHENTICATED', '인증에 실패했습니다');
  const { ownerId, token } = await rotateRefreshToken(raw);   // 회전 + 재사용 탐지
  setRefreshCookie(res, token);
  res.json({ data: { accessToken: signAccessToken(ownerId), expiresIn: env.AUTH_ACCESS_TTL_SEC } });
});

authRouter.post('/logout', requireAuth, async (req, res) => {
  const raw = readCookie(req, RT);
  if (raw) await revokeRefreshToken(raw);       // 패밀리 전체를 무효화한다
  res.clearCookie(RT, { path: '/api/auth' });
  res.sendStatus(204);
});
```

**회전과 재사용 탐지가 짝이다.** 재발급마다 새 토큰을 내주고 옛 토큰을 소진 표시한다. 소진된
토큰이 다시 오면 사본이 돌아다닌다는 뜻이므로 **패밀리 전체를 무효화**한다 — 탈취자든 원
사용자든 둘 다 로그인 화면으로 간다. 그것이 의도다.

```ts
// src/services/auth-service.ts — 재발급 토큰은 해시만 저장한다
export async function issueRefreshToken(ownerId: string, familyId?: string): Promise<string> {
  const { token, hash } = newRefreshToken();
  await prisma.refreshToken.create({
    data: { tokenHash: hash, ownerId, familyId: familyId ?? hash,
            expiresAt: new Date(Date.now() + 14 * 864e5) },
  });
  return token;   // 원문은 쿠키로만 나간다. 저장소에는 어디에도 남지 않는다
}
```

`rotateRefreshToken`·`revokeRefreshToken`도 같은 표를 다루는 이 파일의 함수다 — 조회는 언제나
`hashRefreshToken(raw)`로 한다.

`requireAllowedOrigin`은 CORS와 다른 일을 한다. CORS 응답 헤더가 막는 것은 브라우저가
**응답을 읽는 것**뿐이고 요청 실행 자체는 막지 못하므로, 쿠키만으로 인증되는 이 한 라우트는
서버에서 `Origin`을 직접 본다. 액세스 토큰을 쓰는 나머지 라우트에는 이 검사가 필요 없다.

<!-- verified: express@5.2.1 + supertest@7.2.2 실행 — 로그인→재발급→새 토큰으로 200, 허용 밖 Origin은 403, 회전된 토큰 재사용은 401, 그 뒤 패밀리 무효화로 후속 재발급도 401, 쿠키 없는 재발급 401, 로그아웃 뒤 재발급 401을 관측 -->
로그인 실패는 **사유를 구분하지 않는다**: 없는 계정과 틀린 비밀번호가 같은 401·같은 문구로
나간다. 구분하면 응답만으로 계정 존재를 열거할 수 있다. 실측에서 두 입력의 상태·문구가
같음을 단언했다.

프로덕션 모드의 실제 `Set-Cookie`는 `rt=…; Max-Age=1209600; Path=/api/auth; HttpOnly; Secure;
SameSite=None`이었고, 그 쿠키는 평문 http 요청에 **되돌아오지 않았다**(재발급 401).
<!-- verified: express@5.2.1 + superagent 쿠키 자 실행 — NODE_ENV=production으로 로그인해 Set-Cookie를 관측하고, 같은 에이전트의 후속 재발급이 쿠키 없이 401을 받았다. 브라우저의 localhost 예외는 이 저장소에서 확인하지 못했다 -->

## 6. 테스트 인증 헤더 (`src/test/auth.ts`)

팩의 테스트는 `authFor(ownerId)`를 `.set()`에 그대로 넘긴다. 헤더냐 쿠키냐가 조합의 함수라서
이 헬퍼가 이음매에 있다. **`requireAuth`를 모킹하지 않는다** — 모킹하면 정작 검증해야 할 인가
배선이 테스트에서 빠진다.

<!-- file: src/test/auth.ts -->
```ts
import { signAccessToken } from '../http/tokens';

export function authFor(ownerId: string, roles: string[] = []): Record<string, string> {
  return { Authorization: `Bearer ${signAccessToken(ownerId, roles)}` };
}
```

동기 함수인 것이 계약이다 — `request(app).get(url).set(authFor('owner-1'))` 한 줄에 들어가야
하고, 서명이 비동기면 모든 테스트에 `await`가 번진다. `createHmac`이 동기라 그대로 성립한다.

## 오용 목록 ① — 세션 쿠키 관용구 → 이 조합의 형태

같은 오리진 SSR에서 옮겨온 습관이다. 문법은 전부 통과하고 브라우저에서만 드러난다.

| 구 습관 (같은 오리진 세션) | 현재 형태 (교차 오리진 SPA) |
| --- | --- |
| 액세스 토큰까지 쿠키에 담는다 | 액세스 토큰은 `Authorization` 헤더. 쿠키는 재발급 토큰만 |
| `sameSite: 'strict'`로 두고 끝낸다 | 교차 사이트에서는 쿠키가 아예 안 간다 — `'none'` + `Secure` |
| `sameSite: 'none'`만 켠다 | `Secure` 없는 `None`은 브라우저가 버린다. 둘은 짝이다 |
| CORS를 `origin: true`로 열어 둔다 | `credentials`를 쓰면 `*`가 불가하다. 허용 목록에서 골라 되비춘다 |
| 재발급 토큰을 원문으로 저장 | `sha256` 해시만 저장. DB 유출이 세션 탈취가 되지 않게 한다 |
| 로그아웃에서 쿠키만 지운다 | 서버의 토큰 패밀리도 무효화한다. 쿠키 삭제는 클라이언트 힌트일 뿐이다 |
| 토큰 비교에 `===` | `timingSafeEqual`. 서명 비교는 상수 시간으로 한다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 401 `UNAUTHENTICATED` vs 403 `FORBIDDEN` | 401은 "누구인지 모른다", 403은 "누구인지 알지만 역할이 모자라다" |
| 403 `FORBIDDEN` vs 404 `NOT_FOUND` | 소유권 실패는 언제나 404. 403은 존재가 이미 공개된 경로에만 |
| `router.use(requireAuth)` vs 라우트별 인자 | 라우터 단위로 건다. 라우트별은 새 라우트가 조용히 공개된다 |
| `req.user!.id` vs 던지는 접근자 | 단언은 마운트를 빠뜨렸을 때 500으로 샌다. 접근자는 401로 닫힌다 |
| 액세스 토큰 수명 vs 재발급 토큰 수명 | 앞은 분 단위(15분), 뒤는 일 단위(14일) + 회전. 같은 값으로 두면 둘로 나눈 이유가 사라진다 |
| 재발급 회전 vs 고정 토큰 | 회전 + 재사용 탐지. 고정 토큰은 한 번 새면 만료까지 유효하다 |
| CORS 허용 목록 vs `Origin` 서버 검사 | 앞은 브라우저가 응답을 읽는 것을, 뒤는 요청 실행을 막는다. 쿠키 인증 라우트는 **둘 다** |
| `verifyAccessToken` 실패 사유 노출 vs 일반화 | 언제나 일반화. 어느 검사에서 걸렸는지 알려주면 위조 형태가 좁혀진다 |
