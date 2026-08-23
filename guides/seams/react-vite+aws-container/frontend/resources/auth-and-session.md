<!-- epcc-seam: react-vite+aws-container/frontend v3.12.0 -->
# Auth & Session (OIDC 표준 · Cognito를 issuer로)

이 프로젝트는 Cognito를 **OIDC issuer로만** 사용한다. 벤더 SDK에 결합하지 않고 표준
흐름(Authorization Code + PKCE, discovery, JWT 액세스 토큰)만 쓴다 — 향후 자체 호스팅
issuer(Keycloak 등)로 옮길 때 `authority` URL 교체와 어댑터 한 파일 수정으로 끝나야 한다.

## 1. 흐름

```
SPA → /authorize (code_challenge)        → issuer 로그인 화면
    ← /auth/callback?code=...&state=...   ← 이 경로가 라우트 트리에 있어야 한다 (routing.md §1)
    → /token (code + code_verifier)      → access_token · id_token · refresh_token
    → API 호출: Authorization: Bearer <access_token>
                                          API가 서명·issuer·audience·만료·권한을 검증
```

- **Authorization Code + PKCE만 쓴다.** Implicit 흐름(`response_type=token`)은 폐기됐다
- SPA는 공개 클라이언트다 — **client secret을 두지 않는다.** 번들에 넣는 순간 비밀이 아니다
- 프론트는 토큰을 **운반**만 한다. 해석해서 권한을 판정하지 않는다

## 2. 설정과 UserManager (`src/auth/oidcConfig.ts`)

`react-oidc-context`의 `AuthProvider`는 설정 props 대신 **`UserManager` 인스턴스**를 받을 수
있다. 인스턴스를 직접 만들면 갱신·로그아웃 유틸이 훅 밖에서도 같은 세션을 다룰 수 있다.

```ts
import { UserManager, WebStorageStateStore, InMemoryWebStorage,
         type UserManagerSettings } from 'oidc-client-ts';
import { config } from '@/config';         // import.meta.env를 직접 읽지 않는다

export const oidcSettings: UserManagerSettings = {
  authority: config.oidc.authority,                          // issuer URL (discovery 기준점)
  client_id: config.oidc.clientId,
  redirect_uri: `${window.location.origin}/auth/callback`,
  post_logout_redirect_uri: window.location.origin,
  response_type: 'code',
  scope: 'openid profile email',
  automaticSilentRenew: true,
  // ① 토큰 보관 위치는 여기 한 줄이다 — 기본값은 메모리
  userStore: new WebStorageStateStore({ store: new InMemoryWebStorage() }),
  // ② PKCE verifier와 state는 리다이렉트를 건너 살아남아야 한다. 메모리에 두면
  //    콜백에서 code 교환이 통째로 실패한다 — 수명이 짧으므로 sessionStorage가 맞다
  stateStore: new WebStorageStateStore({ store: window.sessionStorage }),
};

export const userManager = new UserManager(oidcSettings);

// 콜백 후 URL에서 code/state를 지운다 (히스토리·리퍼러 유출 방지)
export const onSigninCallback = () =>
  window.history.replaceState({}, '', window.location.pathname);
```

여기에 issuer 고유 문자열(사용자 풀 ID, 리전, 벤더 호스팅 UI 경로)을 **코드에 박지 않는다.**
전부 환경변수 → `config`로 빼면 issuer 교체가 배포 설정 변경이 된다.

## 3. 토큰 보관 위치

| 위치 | 새로고침 생존 | XSS로 읽힘 | 판단 |
| --- | --- | --- | --- |
| 메모리(`InMemoryWebStorage`) | ✗ (무음 로그인으로 복구) | 실행 중에만 | **기본값 — 위 §2 코드가 이것이다** |
| `sessionStorage` | ○ (탭 한정) | ○ | 무음 로그인이 막힌 환경에서만 |
| `localStorage` | ○ (탭·창 공유) | ○ (가장 오래 노출) | 권장하지 않음 |

- 기본은 **메모리 보관 + 조용한 갱신**이다. 새로고침하면 토큰이 사라지고, issuer 세션
  쿠키를 이용한 무음 로그인(`prompt=none` 숨은 iframe 또는 refresh token)으로 복구한다.
  **서드파티 쿠키 차단 환경에서는 이 복구가 실패**하므로 로그인 화면으로 되돌아간다
- **refresh token은 어떤 경우에도 `localStorage`에 두지 않는다.** 액세스 토큰보다 수명이
  길어 탈취 시 피해가 크다
- 저장소를 바꾸는 결정은 보안 검토 대상이다. 코드 한 줄로 바뀌지만 위험 등급이 바뀐다

## 4. 토큰 공급자 — HTTP 계층과의 결합 끊기

`http.ts`가 인증 라이브러리를 직접 import하면 인증 구현 교체가 HTTP 계층 수정으로 번진다.
**단방향 주입**으로 끊는다.

```ts
// src/api/tokenProvider.ts — http.ts는 이 파일만 안다
type TokenGetter = () => Promise<string | null>;
let getter: TokenGetter = async () => null;

export const setTokenGetter = (fn: TokenGetter) => { getter = fn; };
export const getAccessToken = () => getter();
```

```tsx
// src/auth/AuthWiring.tsx — setTokenGetter를 부르는 유일한 지점.
// 이 컴포넌트가 Provider 트리에 없으면 모든 요청이 인증 헤더 없이 나간다.
export function AuthWiring({ children }: { children: ReactNode }) {
  const auth = useAuth();
  useEffect(() => {
    setTokenGetter(async () => {
      if (auth.user && !auth.user.expired) return auth.user.access_token ?? null;
      // 갱신 결과를 **반환값에서** 읽는다. 클로저의 auth.user는 아직 만료된 옛 객체다
      const renewed = await auth.signinSilent().catch(() => null);
      return renewed?.access_token ?? auth.user?.access_token ?? null;
    });
  }, [auth]);
  return <>{children}</>;
}
```

```tsx
// src/main.tsx — 이 중첩 순서를 routing.md와 동일하게 유지한다
<AuthProvider userManager={userManager} onSigninCallback={onSigninCallback}>
  <AuthWiring>                                {/* 토큰 공급자 장착 — 첫 요청보다 앞서야 한다 */}
    <QueryClientProvider client={queryClient}>
      <RouterProvider router={router} />
    </QueryClientProvider>
  </AuthWiring>
</AuthProvider>
```

세션이 가장 바깥이고, 그 안에 토큰 배선, 그 안에 캐시, 마지막이 라우터다. 순서를 뒤집어
`QueryClientProvider`를 밖에 두면 쿼리가 토큰 배선보다 먼저 떠서 첫 요청이 401이 된다.

## 5. 401 처리 — 한 곳에서만

```ts
// src/auth/session.ts — 갱신과 만료 처리가 사는 유일한 파일
import { userManager } from './oidcConfig';

export async function renewSession(): Promise<boolean> {
  const user = await userManager.signinSilent().catch(() => null);
  return Boolean(user?.access_token);
}

let inFlight: Promise<boolean> | null = null;
/** 단일 비행: 여러 요청이 동시에 401을 받아도 갱신은 한 번만 */
export function refreshOnce(): Promise<boolean> {
  inFlight ??= renewSession().finally(() => { inFlight = null; });
  return inFlight;
}

export async function handleSessionExpired(): Promise<void> {
  await userManager.removeUser().catch(() => null);
  const returnTo = window.location.pathname + window.location.search;  // 내부 경로 — 입력값이 아니다
  window.location.replace(`/login?returnTo=${encodeURIComponent(returnTo)}`);
}
```

호출부는 `http.ts`의 `request()` 안 **한 곳**뿐이다 (`data-fetching.md` §1).

```ts
if (res.status === 401) {
  if (!retried && (await refreshOnce())) return request(method, path, opts, true);
  await handleSessionExpired();
}
```

- 재시도는 **정확히 1회**다. 이 보장은 주석이 아니라 `retried` 파라미터가 만든다 —
  `request()`를 조건 없이 재귀 호출하면 갱신이 계속 성공/실패하며 로그인 루프가 된다
- 401 처리를 화면마다 복사하지 않는다. 화면은 401을 볼 일이 없어야 한다

## 6. 로그아웃 — 순서가 중요하다

```ts
export async function logout(queryClient: QueryClient) {
  queryClient.cancelQueries();      // ① 떠 있는 요청 취소 (응답이 캐시를 되살리지 못하게)
  queryClient.clear();              // ② 서버 캐시 전부 폐기 — 다음 사용자가 이전 데이터를 못 본다
  clearClientState();               // ③ Zustand 스토어 reset (state-management.md §6)
  await endSessionAtIssuer();       // ④ issuer 세션 종료 (여기서 이 탭을 떠난다)
}
```

`clear()`를 생략하면 다음 로그인 사용자가 **이전 사용자의 캐시된 목록**을 잠깐 본다.
이것은 실측에서 자주 발견되는 정보 노출이며, 재현이 어려워 오래 남는다.

**issuer 차이가 드러나는 유일한 지점이 로그아웃이다.** 표준 RP-initiated logout은
`end_session_endpoint`로 `id_token_hint`와 `post_logout_redirect_uri`를 보낸다. 그런데
**Cognito는 discovery 문서에 `end_session_endpoint`를 노출하지 않는다** — 조건 분기로
확인할 대상이 아니라 이 issuer의 고정된 사실이다. 그래서 벤더 `/logout` URL을 쓰고,
그 분기를 어댑터 한 파일에 가둔다.

```ts
// src/auth/endSession.ts — issuer 고유 코드가 사는 유일한 파일
import { userManager } from './oidcConfig';
import { config } from '@/config';

export async function endSessionAtIssuer(): Promise<void> {
  // 벤더 /logout은 id_token_hint를 요구하지 않으므로 로컬 토큰을 먼저 지워도 된다.
  await userManager.removeUser();
  const url = new URL(config.oidc.logoutUrl);          // VITE_OIDC_LOGOUT_URL
  url.searchParams.set('client_id', config.oidc.clientId);
  url.searchParams.set('logout_uri', window.location.origin);
  window.location.assign(url.toString());              // 이 탭을 떠난다
}
```

`end_session_endpoint`를 제공하는 issuer로 옮기면 이 함수 본문을
`await userManager.signoutRedirect()` **한 줄**로 바꾼다. 이때 순서가 뒤집힌다 —
`signoutRedirect()`는 `id_token_hint`를 붙이기 위해 저장된 id_token이 필요하므로
`removeUser()`를 **먼저 부르면 안 된다**. 먼저 부르면 힌트 없는 로그아웃 요청이 나가고
issuer 세션이 살아남아, 다시 로그인하면 화면만 깜빡이고 그대로 통과한다.

## 7. 인가는 프론트의 책임이 아니다

백엔드에는 데이터 층의 행 단위 정책 엔진이 없다 — **API 서버의 명시적 검사만이 유일한
방어선**이다. 프론트의 역할은 그 판정을 예상해 UI를 정돈하는 것까지다.

이 백엔드에는 권한 목록을 주는 `/me` 엔드포인트가 없다. 역할은 issuer가 토큰에 넣어 준
그룹 클레임에서 온다 — 서버는 같은 클레임을 **검증한 토큰에서 다시 읽어** 강제하고,
프론트는 같은 값을 **표시 목적으로만** 읽는다.

```ts
// src/auth/groups.ts — issuer 고유 클레임 이름이 사는 유일한 파일 (백엔드 정규화와 짝)
const GROUPS_CLAIM = 'cognito:groups';
export const readGroups = (profile: Record<string, unknown> | undefined): string[] => {
  const raw = profile?.[GROUPS_CLAIM];
  return Array.isArray(raw) ? raw.filter((v): v is string => typeof v === 'string') : [];
};

// src/auth/useCan.ts — UI 힌트 전용. 이 값이 true여도 서버가 다시 판정한다
export type Ability = 'task:delete' | 'task:assign';
const ABILITY_GROUPS: Record<Ability, string[]> = {
  'task:delete': ['admin', 'manager'],
  'task:assign': ['admin', 'manager', 'member'],
};
export function useCan(ability: Ability): boolean {
  const { user } = useAuth();
  return readGroups(user?.profile).some((g) => ABILITY_GROUPS[ability].includes(g));
}
```

```tsx
// ✅ 숨기되, 서버 판정을 그대로 존중한다
const canDelete = useCan('task:delete');
{canDelete && <DeleteButton onError={(e) => toast.error(toUserMessage(e))} />}  // 403/404 대비

// ❌ 클레임을 읽은 것을 "검사를 마쳤다"고 간주 — 서명 검증도 없고, 콘솔에서 우회도 자유롭다
if (jwtDecode<{ role: string }>(token).role === 'admin') { await http.delete(url); }
```

- 클레임 읽기는 **표시·정돈용**이다. 신뢰 경계는 API 서버 한 곳뿐이며, 이 백엔드에는
  행 수준 정책 엔진이 없으므로 UI를 숨기는 것이 방어에 보태는 것은 **0**이다
- 남의 리소스 접근은 **404**로 돌아온다(존재 누설 방지). 403은 역할·스코프 부족에만 쓴다 —
  두 경우의 문구가 달라야 한다 (`loading-error-states.md` §4)
- 관리자 전용 화면도 코드 분할된 청크로 존재한다 — 누구나 내려받을 수 있음을 전제하고,
  민감한 정보는 컴포넌트가 아니라 그 컴포넌트가 부르는 API 응답에만 담는다

## 8. issuer 교체 체크리스트

- [ ] `VITE_OIDC_AUTHORITY`만 바꿔 로그인·콜백·갱신이 동작하는가
- [ ] issuer 고유 문자열이 `endSession.ts`·`groups.ts` 밖에 있는가 (`rg -i "cognito|amazonaws" src/`)
- [ ] 새 issuer가 `end_session_endpoint`를 노출하면 `endSession.ts`를 `signoutRedirect()`로 바꿨는가
- [ ] 새 issuer의 `redirect_uri`(`/auth/callback`)·`post_logout_redirect_uri`가 허용 목록에 있는가
- [ ] 그룹 클레임 이름이 바뀌면 `groups.ts`와 백엔드의 `OIDC_GROUPS_CLAIM`을 함께 고쳤는가

## 오용 목록 — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `access_token` vs `id_token` | API의 `Authorization` 헤더에는 **access_token**. id_token은 "이 사용자가 누구인가"를 프론트에 알려주는 용도이며 API 인증에 쓰면 audience가 맞지 않는다 |
| 토큰 디코드 vs 토큰 검증 | 프론트의 디코드는 **표시용**이다. 서명·issuer·audience·만료 검증은 서버만 한다. 디코드 결과로 접근을 허용하는 것은 검증이 아니다 |
| 라우트 가드 vs 서버 인가 | 가드는 UX(잘못된 화면 진입 방지). 실제 차단은 매 API 요청에서 서버가 한다 |
| `isLoading` vs `isAuthenticated` | 세션 복구 중(`isLoading`)에 `!isAuthenticated`로 리다이렉트하면 새로고침마다 로그인 화면이 번쩍인다. 로딩을 먼저 분기한다 |
| 조용한 갱신 vs 리다이렉트 재인증 | 만료 임박은 `signinSilent`. 갱신이 실패하면 미루지 말고 전체 리다이렉트로 다시 로그인시킨다 |
| `removeUser()` vs `signoutRedirect()` | 전자는 **로컬 토큰만** 지운다 — issuer 세션이 살아 있어 다시 로그인하면 즉시 통과한다. 완전한 로그아웃은 후자까지 가되, 순서는 §6 |
| `auth.settings`에서 discovery 읽기 | `settings`는 순수 설정 객체(`UserManagerSettings`)다. 메타데이터 서비스가 들어 있지 않으므로 `auth.settings.metadataService`는 존재하지 않는다. 필요하면 `.well-known/openid-configuration`을 직접 `fetch`한다 |
| `userStore` vs `stateStore` | 토큰은 `userStore`(메모리), PKCE verifier·state는 `stateStore`(sessionStorage). 둘을 같은 값으로 두면 메모리 선택이 로그인 자체를 깬다 |
| 로그아웃 시 `clear()` vs `invalidateQueries()` | 무효화는 데이터를 남기고 다시 가져온다. 로그아웃에는 **`clear()`** — 남으면 정보 노출 |
| `client secret` 사용 vs PKCE | SPA에는 secret을 둘 자리가 없다. 백엔드가 대신 보관하는 흐름이 아니라면 PKCE가 유일한 답 |
| 다중 탭 동기화 | 한 탭에서 로그아웃하면 다른 탭도 정리되어야 한다. `storage` 이벤트나 `BroadcastChannel`로 로그아웃 신호를 보내고, 받는 쪽도 6절의 순서를 그대로 실행한다 |
