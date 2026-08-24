<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# Identity Platform ID 토큰 검증 — 서버 앞단이 유일한 경계다

이 파일이 소유하는 것은 **무엇이 유효한 자격 증명인가**와 **그것을 어떻게 검증하는가**뿐이다
(`src/identity/verify.ts`). 토큰이 **어떻게 도착하는가**(베어러 헤더 · 세션 쿠키) · 로그인 흐름 ·
`currentUser` 미들웨어 배선 · 역할은 **이음매가 소유한다**(`src/http/auth.ts`). 검증 실패를 어떤
상태 코드로 내보내는지는 `error-handling.md`가 소유한다.

**이 축에는 백업이 없다.** Firestore Security Rules는 전면 거부이고 서버는 서비스 계정으로 붙어
규칙을 통째로 우회한다. 이 함수가 내주는 `sub`가 곧 `ownerId`이고, 여기가 뚫리면 뒤에 아무것도 없다.

## 1. 무엇을 받는 함수인가 — 토큰 판단표

Google이 발급한 JWT는 여러 종류이고 **전부 RS256에 전부 `googleapis.com` 계열 키로 서명된다.**
구분은 `iss`와 `aud`뿐이다. 섞으면 서비스 계정 토큰으로 사용자 API를 부를 수 있다.

| 토큰 | `iss` | `aud` | 서명 키셋 | `verifyIdToken`이 받는가 |
| --- | --- | --- | --- | --- |
| **Identity Platform ID 토큰** (최종 사용자) | `https://securetoken.google.com/<projectId>` | `<projectId>` | `securetoken@system.gserviceaccount.com` | **받는다 — 이 함수의 유일한 대상** |
| **IAM ID 토큰** (서비스 간 호출) | `https://accounts.google.com` | 호출 대상 서비스 URL (`https://tasks-….a.run.app`) | `federated-signon` 키셋 | **거부한다** |
| Firebase 커스텀 토큰 | 서비스 계정 이메일 | `…identitytoolkit…verifyCustomToken` | 서비스 계정 비공개 키 | 거부한다 — 교환 전의 재료다 |
| OAuth 액세스 토큰 | (JWT가 아니다) | — | — | 거부한다 — 서명 검증 대상이 아니다 |

**서비스 간 호출을 받으려면 별도의 경계를 만든다.** 같은 함수에 두 발급자를 허용하는 순간
`aud`가 서로 다른 두 값을 동시에 인정해야 하고, 그때부터 두 검사 중 느슨한 쪽이 유효 경계가 된다.
Cloud Run의 IAM 인증은 애초에 애플리케이션 코드가 아니라 **서비스 IAM 정책**에서 판정하는 것이 맞다.

## 2. 키셋은 모듈 최상위에 둔다

Cloud Run은 **상주 프로세스**다 — 컨테이너가 요청 사이에 살아 있으므로 모듈 최상위 인스턴스의
캐시가 실제로 산다. `createRemoteJWKSet`의 반환값은 그 자체가 캐시이고, 요청마다 만들면 캐시가
매번 버려져 **모든 요청이 Google에 왕복**한다.

<!-- verified: 자체 키쌍 + 로컬 JWKS 서버로 대리. 검증 17회 동안 서버가 받은 요청 1건 -->
실측: 모듈 최상위 인스턴스 하나로 토큰 17개를 검증하는 동안 JWKS 서버가 받은 HTTP 요청은 **1건**이었다.

```ts
// ❌ 요청마다 새 키셋 — 캐시가 매번 버려진다
app.use(async (c, next) => {
  const jwks = createRemoteJWKSet(JWKS_URL);   // ❌ 요청 수만큼 왕복한다
  await next();
});
```

## 3. `verifyIdToken` (`src/identity/verify.ts`)

<!-- file: src/identity/verify.ts -->
```ts
// src/identity/verify.ts
import { createRemoteJWKSet, jwtVerify } from 'jose';
import { AppError } from '../errors.js';
import { settings } from '../settings.js';

const JWKS_URL = new URL(
  'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
);

/** 프로세스당 하나. 이 값 자체가 키 캐시다 — 요청 안에서 만들지 않는다. */
export const jwks = createRemoteJWKSet(JWKS_URL);

const ISSUER = `https://securetoken.google.com/${settings.IDENTITY_PLATFORM_PROJECT_ID}`;

export type IdTokenClaims = {
  sub: string;
  email?: string;
  email_verified?: boolean;
};

export async function verifyIdToken(token: string): Promise<IdTokenClaims> {
  let payload;
  try {
    ({ payload } = await jwtVerify(token, jwks, {
      algorithms: ['RS256'],
      issuer: ISSUER,
      audience: settings.IDENTITY_PLATFORM_PROJECT_ID,
      requiredClaims: ['sub', 'exp', 'iat'],
      clockTolerance: 60,
    }));
  } catch {
    // 부류를 구분하지 않는다 — 아래 5절
    throw new AppError('UNAUTHENTICATED', '인증에 실패했다');
  }

  const sub = payload.sub;
  if (typeof sub !== 'string' || sub.length === 0) {
    throw new AppError('UNAUTHENTICATED', '인증에 실패했다');
  }

  return {
    sub,
    email: typeof payload.email === 'string' ? payload.email : undefined,
    email_verified: payload.email_verified === true,
  };
}
```

`AppError`는 이음매가 `src/errors.ts`에 정의한다(`ERROR_STATUS`에서 `UNAUTHENTICATED` → 401).
`settings`는 `src/settings.ts`가 소유한다 — **이 파일은 환경을 직접 읽지 않는다.**

## 4. 가드 하나씩이 무엇을 막는가 — 변이 대조

옵션을 하나씩 빼고 같은 토큰을 다시 태워 **그 가드가 없으면 실제로 통과하는지** 관측했다.
통과하지 않는 가드는 이중 방어이고, 통과하는 가드는 **유일한 방벽**이다.

<!-- verified: 자체 RS256 키쌍 + 로컬 JWKS로 대리. 각 행을 옵션 제거 전후로 1회씩 실행 -->

| 뺀 것 | 그러면 통과하는 토큰 | 관측 | 성격 |
| --- | --- | --- | --- |
| `issuer` | `iss`가 `accounts.google.com`인 IAM 토큰류 | **PASS** | 유일한 방벽 |
| `audience` | 다른 프로젝트가 수신자인 토큰 | **PASS** | 유일한 방벽 |
| `requiredClaims`의 `exp` | **`exp`가 아예 없는 토큰** | **PASS** | 유일한 방벽 |
| `sub` 빈 문자열 가드 | `sub: ""` | **jose가 통과시킨다** | 유일한 방벽 |
| `algorithms` | 공개키를 HMAC 비밀로 삼은 HS256 | 여전히 REJECT (`ERR_JOSE_NOT_SUPPORTED`) | 이중 방어 |

**두 줄이 특히 중요하다.**

<!-- verified: jose 6.2.10 설치본에 exp 없는 토큰을 태워 관측 — requiredClaims 없이 통과 -->
- **jose는 `exp`를 기본으로 요구하지 않는다.** `exp`가 없는 토큰은 만료가 없는 토큰이고, 옵션 없이는
  그것이 정상 통과한다. `requiredClaims: ['sub', 'exp', 'iat']`가 그 하나를 막는 유일한 줄이다
<!-- verified: sub: "" 토큰이 jwtVerify를 통과하는 것을 관측 (payload.sub === "") -->
- **jose는 `sub: ""`를 「있음」으로 센다.** `requiredClaims`에 `sub`를 넣어도 빈 문자열은 통과한다.
  빈 `ownerId`는 소유권 필터를 무력화하므로 명시적 길이 검사가 필요하다

`algorithms`는 관측상 유일한 방벽이 아니었지만(원격 키셋이 대칭 알고리즘 요청 자체를 거부한다)
**남긴다** — 그 방어는 jose 내부 구현의 성질이고 우리 계약이 아니다.

## 5. 실패 부류를 하나로 접는다

jose는 실패 원인을 코드로 구분해 준다. **그 구분을 클라이언트에게 전달하지 않는다.**

| jose 오류 코드 | 실제 원인 | 클라이언트가 받는 것 |
| --- | --- | --- |
| `ERR_JWT_EXPIRED` | 만료 | `UNAUTHENTICATED` |
| `ERR_JWT_CLAIM_VALIDATION_FAILED` | `iss`·`aud`·`nbf`·필수 클레임 누락 | `UNAUTHENTICATED` |
| `ERR_JWKS_NO_MATCHING_KEY` | 미지 `kid` — 공격자 키·회전 직후 | `UNAUTHENTICATED` |
| `ERR_JOSE_ALG_NOT_ALLOWED` | `alg: none` · 알고리즘 혼동 | `UNAUTHENTICATED` |
| `ERR_JWS_INVALID` | JWT 형태가 아님 | `UNAUTHENTICATED` |

「만료됐다」와 「서명이 틀렸다」를 구분해 알리면 공격자는 **어느 축을 고치면 되는지**를 알게 된다.
만료 응답은 「이 토큰은 한때 유효했다」는 확인이고, 발급자 불일치 응답은 프로젝트 ID 추측의 채점표다.

**진단은 서버 로그에만 남긴다.** `log('warn', 'id token rejected', { reason: err.code })` —
`reason`에 jose의 코드만 싣고 **토큰 원문·페이로드·이메일은 싣지 않는다.** 로그는 유출 경로다.

## 6. 시계 오차와 키 회전

**`clockTolerance: 60`.** 컨테이너 시계와 Google 발급 시계가 몇 초 어긋나면 방금 발급된 토큰의
`iat`·`nbf`가 미래가 되어 정상 로그인이 거부된다. 60초는 그 오차를 흡수하되 만료된 토큰의 수명을
의미 있게 늘리지는 않는 폭이다.

<!-- verified: iat/nbf를 30초 미래로 둔 토큰은 통과, 600초 미래는 ERR_JWT_CLAIM_VALIDATION_FAILED로 거부 -->
실측: `iat`·`nbf`가 **30초** 미래인 토큰은 통과하고, **600초** 미래인 토큰은 거부됐다.

**키 회전.** Google은 키를 여러 개 동시에 게시하고 겹치는 구간을 두고 갈아탄다.

<!-- verified: securetoken@system.gserviceaccount.com 키셋을 실제로 조회 (2026-08-24) -->
- 실 엔드포인트를 조회한 시점에 **RS256 공개키 4개가 동시에** 게시돼 있었고, 응답 헤더는
  `cache-control: public, max-age=19348, must-revalidate`였다(약 5.4시간)
<!-- unverified: 실 GCP 프로젝트 없음 — 회전 주기와 겹침 구간의 실제 길이는 관측하지 못했다 -->
- 회전 **주기** 자체와 겹침 구간의 길이는 확인하지 못했다

jose의 캐시 거동은 로컬 키셋 서버로 대리 관측했다.

<!-- verified: 로컬 JWKS 서버의 키를 갈아끼우고 kid를 바꿔 재검증, 서버가 받은 요청 수를 계측 -->
| 상황 | 관측 |
| --- | --- |
| 캐시에 없는 `kid`가 오면 | 키셋을 **다시 받아** 검증에 성공한다 (추가 왕복 1회) |
| 기본 `cooldownDuration`(30초) 안에 다시 오면 | 재조회가 억제돼 `ERR_JWKS_NO_MATCHING_KEY`로 거부된다 |
| 키셋에서 **사라진** 키로 서명한 토큰 | 캐시가 살아 있는 동안 **계속 통과한다** |

마지막 줄이 운영상의 진실이다 — **키 폐기는 즉시 반영되지 않는다.** 반영 상한은 `cacheMaxAge`
(기본 10분)이고, 그동안 폐기된 키의 서명이 유효하다. 이것이 문제라면 `cacheMaxAge`를 줄이는
것이지 코드를 고치는 것이 아니다. 겹침 구간을 넉넉히 두는 Google의 게시 방식이 30초 쿨다운을
견딜 수 있게 해 주는 쪽이다.

## 7. 주체는 `sub`다

`sub`는 Identity Platform이 발급하는 불변 사용자 ID이고, **그것이 그대로 `ownerId`가 된다.**

| 클레임 | 소유권 키로 쓰는가 | 왜 |
| --- | --- | --- |
| `sub` | **쓴다** | 계정 수명 동안 불변이다 |
| `email` | 쓰지 않는다 | 사용자가 바꿀 수 있고, 해지된 주소는 **재사용**된다 |
| `email_verified` | 쓰지 않는다 | 소유권이 아니라 신뢰 수준이다 |
| `phone_number` | 쓰지 않는다 | 이메일과 같은 이유다 |

`email`을 `ownerId`로 삼은 시스템은 사용자가 주소를 바꾸는 순간 자기 문서를 잃고, 그 주소를
넘겨받은 다른 사람이 **그 문서를 갖는다.** 되돌릴 수 없는 결정이므로 처음에 정한다.

인가 판정의 근거는 **검증된 토큰에서만** 온다. 요청 본문·쿼리·헤더의 사용자 식별자는 자격 증명이
아니라 입력이다 — `ownerId`를 본문에서 받는 순간 남의 문서를 만들거나 읽을 수 있다.

## 8. 검증 없이 디코드하지 않는다

JWT의 페이로드는 **서명을 확인하지 않아도 읽힌다.** base64url일 뿐 암호가 아니다.

```ts
// ❌ 서명을 확인하지 않은 페이로드 — 공격자가 손으로 쓴 값이다
const claims = JSON.parse(atob(token.split('.')[1]));
const ownerId = claims.sub;                    // ❌ 아무 값이나 들어온다
// ❌ jose의 decodeJwt도 서명을 확인하지 않는다
const ownerId2 = decodeJwt(token).sub;         // ❌ 같은 결함이다
// ✅ 검증을 통과한 클레임만 쓴다
const { sub } = await verifyIdToken(token);
```

「로깅용으로만 디코드한다」도 하지 않는다. 검증 전 값이 로그에 들어가면 그 로그로 판단하는
사람이 그것을 사실로 읽는다.

## 오용 목록 ① — firebase-admin 관용구 → jose 대조표

이 축은 `@google-cloud/firestore`로 붙고 **`firebase-admin`을 쓰지 않는다**(정책 `no-firebase-admin`).
`firebase` 축의 코드를 그대로 옮기면 두 축의 보안 경계가 섞인다 — 그쪽은 규칙이 클라이언트를 막는
전제 위에 있고, 이 축은 규칙이 전면 거부다.

| 구 습관 (firebase-admin) | 현재 형태 (jose 6) |
| --- | --- |
| `admin.auth().verifyIdToken(t)` | `verifyIdToken(t)` — `jwtVerify` + `createRemoteJWKSet` |
| SDK가 `iss`·`aud`를 암묵적으로 정해 준다 | `issuer`·`audience`를 **명시한다** — 안 쓰면 검사되지 않는다 |
| `checkRevoked: true` 옵션 | 대응물이 없다. 폐기 확인은 별도 왕복이 필요하다 |
| `decodedToken.uid` | `claims.sub` — 이름이 다르다 |
| 앱 초기화(`initializeApp`)가 전제 | 초기화가 없다. 키셋 인스턴스 하나가 전부다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 최종 사용자 ID 토큰 vs IAM ID 토큰 | `iss`로 가른다. 후자는 이 함수가 아니라 서비스 IAM이 판정한다 |
| `sub` vs `email` | 소유권 키는 `sub`뿐. `email`은 표시용이다 |
| `verifyIdToken` vs `decodeJwt` | 후자는 서명을 보지 않는다 — 신뢰 결정에 쓰지 않는다 |
| `clockTolerance` vs `maxTokenAge` | 앞은 시계 오차 흡수, 뒤는 `iat` 기준 수명 상한. 목적이 다르다 |
| 모듈 최상위 `jwks` vs 요청 안 생성 | 상주 프로세스에서만 캐시가 산다 — 최상위가 유일한 자리다 |
| 실패 부류 구분 vs 하나로 접기 | 로그는 구분하고 **응답은 접는다** |
