<!-- epcc-seam: vue+node-api v3.13.0 -->
# Auth & Session — 토큰 보관 · 재발급 · 복귀 경로 · 폐기

인증 **방식**은 백엔드 축의 함수다. 이 파일이 그 방식을 프론트에 고정한다: 토큰을 어디에
두는가 · 401을 누가 처리하는가 · 로그아웃이 무엇을 비우는가 · 로그인 후 어디로 돌아가는가.

라우터 가드의 **자리와 형태**는 팩(`resources/routing.md` §4)이 소유하고, 이 파일은 그
가드가 부르는 `useAuth`를 제공한다. 복귀 경로 **검증 함수**(`safeReturnTo`)도 팩이
소유한다 — 여기서 다시 정의하지 않고 §5에서 **소비만** 한다.

> **계약에 없는 값**: 와이어 계약(`contract.md`)은 봉투·페이지네이션·에러 코드·인가 실패
> 표면만 고정한다. 로그인·재발급·로그아웃 **엔드포인트와 토큰 전달 방식은 계약에 없다.**
> 아래는 이 조합의 기본값이며 백엔드와 반드시 맞춘다. <!-- unverified: 계약 문서에 해당 절이 없다 — 프로젝트가 정하는 값 -->

## 1. 토큰을 어디에 두는가

| 보관 위치 | XSS로 탈취되는가 | CSRF에 노출되는가 | 새로고침에 살아남는가 | 판정 |
| --- | --- | --- | --- | --- |
| `localStorage` | **된다** — 스크립트가 읽는다 | 아니오 | 예 | 쓰지 않는다 |
| `sessionStorage` | **된다** | 아니오 | 탭 한정 | 쓰지 않는다 |
| 자바스크립트 변수(메모리) | 실행 중 프로세스에서만 | 아니오 | 아니오 | **액세스 토큰** |
| `httpOnly` 쿠키 | 아니오 | 예 — `SameSite`로 막는다 | 예 | **재발급 토큰** |

**액세스 토큰은 메모리, 재발급 토큰은 `httpOnly` 쿠키.** 새로고침하면 액세스 토큰이
사라지지만 §2의 `refreshSession()`이 쿠키로 즉시 복구한다 — 이것이 팩의 가드가
`await auth.ensureReady()`를 부르는 이유다. 복구가 끝나기 전에 판정하면 새로고침마다
로그인 화면으로 튕긴다.

`VITE_*` 환경변수에 토큰·서명 키를 넣지 않는다. 빌드 시점에 번들 문자열로 인라인되어
공개된다 (팩의 `no-secret-env-prefix` 정책).

## 2. 세션 모듈 (`src/auth/session.ts`)

토큰의 소유자다. `http.ts`와 `useAuth.ts` 둘 다 이 모듈을 통해서만 토큰을 만진다.
재발급 요청 자체는 원시 `fetch`를 쓴다 — `http.ts`를 부르면 401 처리가 자기 자신을 부른다.

<!-- file: src/auth/session.ts -->
```ts
// src/auth/session.ts
import { config } from '@/config';

let accessToken: string | null = null;
let refreshing: Promise<boolean> | null = null;

export function getAccessToken(): string | null {
  return accessToken;
}

export function setAccessToken(next: string | null): void {
  accessToken = next;
}

export function clearSession(): void {
  accessToken = null;
  refreshing = null;
}

// 단일 비행: 동시에 401을 받은 요청 N개가 재발급을 N번 돌리면, 재발급 토큰을 회전시키는
// 서버에서 뒤늦은 응답이 앞선 토큰을 무효화해 사용자가 임의로 튕긴다.
// 첫 호출만 실제 요청을 만들고 나머지는 같은 Promise를 기다린다.
export function refreshSession(): Promise<boolean> {
  refreshing ??= runRefresh().finally(() => { refreshing = null; });
  return refreshing;
}

async function runRefresh(): Promise<boolean> {
  try {
    const res = await fetch(`${config.apiBaseUrl}/api/auth/refresh`, {
      method: 'POST',
      credentials: 'include',        // httpOnly 재발급 쿠키를 싣는다
    });
    if (!res.ok) return false;       // 실패는 던지지 않는다 — 호출자가 불리언으로 분기한다
    const body = (await res.json()) as { data?: { accessToken?: unknown } };
    const token = body.data?.accessToken;
    if (typeof token !== 'string' || token === '') return false;
    accessToken = token;
    return true;
  } catch {
    return false;                    // 네트워크 실패도 "재발급 못 함"이다
  }
}
```

`runRefresh`가 던지지 않는 이유: 호출자는 `http.ts`의 401 분기와 가드의 `ensureReady`
둘뿐이고, 둘 다 필요한 것은 예외가 아니라 **참/거짓**이다. 여기서 던지면 "세션이 없다"가
"요청이 실패했다"와 같은 모양이 되어 화면이 로그인 대신 에러를 그린다.

## 3. 401 재발급 1회 — 배선과 그 경계

배선은 `http.ts`의 `request()`에 있다(`resources/data-fetching.md` §3). 규칙 셋:

1. **재귀하지 않는다.** 재시도는 `send()`를 한 번 더 부르는 것이지 `request()`를 다시
   부르는 것이 아니다. 재귀하면 서버가 계속 401을 주는 동안 무한 루프가 된다
2. **재발급이 실패하면 `clearSession()` 후 원래 401을 그대로 올린다.** 새 에러를 만들면
   `requestId`가 사라져 서버 로그와 맞출 수 없다
3. **화면은 401을 다루지 않는다.** 개별 화면에 갱신·로그아웃 분기를 두면 같은 로직이
   화면 수만큼 생긴다 (팩의 `loading-error-states.md` §4와 같은 규칙)

<!-- verified: 실제 node:http 서버 + 40ms 지연 재발급으로 실행 계측 — 아래 3행은 그 출력이다 -->

| 시나리오 | 재발급 요청 | 자원 요청 | 결과 |
| --- | --- | --- | --- |
| 두 요청이 **동시에** 401 | **1회** | 4회 (각 401 + 재시도) | 둘 다 성공 |
| 유효한 토큰으로 재요청 | 0회 | 1회 | 성공 |
| 재발급이 401을 반환 | 1회 | 1회 (재귀 없음) | `ApiError('UNAUTHENTICATED')`, `requestId` 보존 |

`refreshing ??=`를 지운 결함 픽스처로 같은 시험을 돌리면 동시 401 2건에서 재발급이
**2회** 돌아 첫 행의 단언이 깨진다 — 이 장치가 실제로 무언가를 막고 있다는 증명이다.

## 4. `useAuth` (`src/auth/useAuth.ts`)

팩의 가드가 `useAuth().ensureReady()`와 `.isAuthenticated.value`를 부른다. 형태를 바꾸면
가드가 깨진다. `useQueryClient()`를 쓰지 않는 것이 중요하다 — 가드는 컴포넌트 setup이
아니라서 주입을 받을 수 없다. 그래서 모듈 전역 `queryClient`를 직접 import한다.

<!-- file: src/auth/useAuth.ts -->
```ts
// src/auth/useAuth.ts
import { ref, type Ref } from 'vue';
import { http } from '@/api/http';
import { queryClient } from '@/api/queryClient';
import { clearClientState } from '@/stores/clearClientState';       // 팩 소유
import { getAccessToken, setAccessToken, clearSession, refreshSession } from './session';

// 모듈 전역이다 — 컴포넌트마다 새 상태를 만들면 헤더와 가드가 서로 다른 값을 본다
const isAuthenticated = ref(getAccessToken() !== null);
let ready: Promise<void> | null = null;

export function useAuth(): {
  isAuthenticated: Ref<boolean>;
  ensureReady: () => Promise<void>;
  login: (input: { email: string; password: string }) => Promise<void>;
  logout: () => Promise<void>;
} {
  return { isAuthenticated, ensureReady, login, logout };
}

// 가드 진입마다 await된다 — 같은 Promise를 재사용해 중복 호출을 안전하게 만든다
function ensureReady(): Promise<void> {
  ready ??= (async () => { isAuthenticated.value = await refreshSession(); })();
  return ready;
}

async function login(input: { email: string; password: string }): Promise<void> {
  const data = await http.post('/api/auth/login', { body: JSON.stringify(input) });
  const token = (data as { accessToken?: unknown } | null)?.accessToken;
  if (typeof token !== 'string') throw new Error('로그인 응답에 accessToken이 없습니다.');
  setAccessToken(token);
  isAuthenticated.value = true;
}

async function logout(): Promise<void> {
  // 서버 호출이 실패해도 로컬은 반드시 비운다 — finally가 그 보장이다
  try { await http.post('/api/auth/logout'); } finally {
    isAuthenticated.value = false;
    clearSession();          // ① 토큰부터 버린다 — 이후 어떤 재요청도 인증되지 않는다
    queryClient.clear();     // ② 서버 캐시 (다음 사용자가 이전 사용자의 목록을 보지 않게)
    clearClientState();      // ③ 클라이언트 스토어 + localStorage (팩 소유)
  }
}
```

<!-- verified: pinia + VueQueryPlugin을 심은 실제 앱에서 실행 — ensureReady를 4회 불러도 재발급 요청은 1회, 로그인 후 인증 요청 성공, 로그아웃 후 캐시 undefined·density 초기화·localStorage null·후속 요청 UNAUTHENTICATED -->
**순서가 계약이다.** ②를 ①보다 먼저 하면, 캐시를 비우는 순간 화면에 남아 있던 쿼리가
아직 유효한 토큰으로 재요청을 보내 캐시가 다시 채워진다. 서버 캐시(`queryClient`)와
클라이언트 스토어(`clearClientState`)를 **둘 다** 비운다 — 하나만 비우면 다음 사용자가
이전 사용자의 화면 조각을 본다.

## 5. 로그인 화면과 복귀 경로 (`src/features/auth/pages/LoginPage.vue`)

가드는 차단한 경로를 `query.returnTo`에 담아 보낸다. 그 값은 **URL에서 온 밖의 값**이므로
팩의 `safeReturnTo`를 통과시킨 결과만 `router.replace`에 넘긴다.

```vue
<script setup lang="ts">
// src/features/auth/pages/LoginPage.vue
import { ref } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import { useAuth } from '@/auth/useAuth';
import { safeReturnTo } from '@/lib/safeReturnTo';     // 팩 소유 — 여기서 다시 만들지 않는다
import { toUserMessage } from '@/lib/toUserMessage';   // 팩 소유
import Button from '@/components/common/Button.vue';

const route = useRoute();
const router = useRouter();
const { login } = useAuth();
const email = ref(''), password = ref(''), isPending = ref(false), message = ref('');

async function onSubmit() {
  isPending.value = true; message.value = '';
  try {
    await login({ email: email.value, password: password.value });
    await router.replace(safeReturnTo(route.query.returnTo));   // ← 검증은 여기 한 번뿐
  } catch (e) {
    message.value = toUserMessage(e);     // 실패 사유를 구분하지 않는다 (계정 존재 누설)
  } finally {
    isPending.value = false;
  }
}
</script>

<template>
  <form class="mx-auto max-w-sm space-y-4" @submit.prevent="onSubmit">
    <input v-model="email" type="email" autocomplete="username" class="w-full rounded border px-3 py-2" />
    <input v-model="password" type="password" autocomplete="current-password" class="w-full rounded border px-3 py-2" />
    <p v-if="message" class="text-sm text-red-600" role="alert">{{ message }}</p>
    <Button :disabled="isPending" variant="primary" size="md">로그인</Button>
  </form>
</template>
```

`security-vectors.md` A절 12벡터를 **이 화면의 코드에 그대로** 통과시킨 결과다.

<!-- verified: happy-dom(origin=https://app.example) + 실제 vue-router로 replace까지 실행. 아래 표는 그 출력 -->

| 입력 | `safeReturnTo` 반환 | 도달 라우트 | 판정 |
| --- | --- | --- | --- |
| `//evil.example` · `/\evil.example` · `https://evil.example` | `/tasks` | tasks | 차단 |
| `javascript:alert(1)` · `\tjavascript:alert(1)` | `/tasks` | tasks | 차단 |
| `/..//evil.example` · `/../..//evil.example` | `/tasks` | tasks | 차단 |
| `''` · `null` · `42` | `/tasks` | tasks | 차단 |
| `%2f%2fevil.example` | `/%2f%2fevil.example` | not-found | 외부 이동 없음 (아래) |
| `/tasks\n\rSet-Cookie: x=1` | `/tasksSet-Cookie:%20x=1` | not-found | 외부 이동 없음 (아래) |
| `/tasks?filter=open#top` · `/tasks/123` | 입력 그대로 | tasks | **통과 — 정상값** |

마지막 두 벡터는 fallback으로 떨어지지 않는다. `%2f`는 `pathname`에서 디코드되지 않고
제어문자는 URL 파서가 제거하므로, 결과는 **같은 오리진의 없는 경로**가 되어 404 화면에
닿는다 — `replace` 후 `location.href`가 `app.example`을 벗어나지 않았다. <!-- verified: 위 실행에서 location.href를 매 벡터마다 출력해 대조했다 -->
값이 `router.replace`가 아니라 `window.location`이나 서버의 `Location` 헤더로 갔다면
판정이 달라진다 — 팩이 못 박은 호출자 의무(`router.replace`/`push`에만 넘긴다)가 그래서 있다.

## 6. 인가 UI는 신뢰 경계가 아니다

이 조합의 백엔드에는 **데이터 계층 정책 엔진이 없다.** 소유권은 서버의 애플리케이션
층이 유일하게 강제하고, 프론트가 하는 일은 전부 UX다. 그래서 두 가지가 함께 있어야 한다.

- **숨김에는 실패 처리가 따라붙는다.** 버튼을 숨겼다면, 그 동작이 API로 직접 호출됐을 때
  받는 응답도 처리해야 한다. 숨김만 있고 실패 처리가 없으면 사용자는 아무 반응 없는
  화면을 본다
- **404를 한 화면으로 처리한다.** 계약 §5에서 소유권 실패는 403이 아니라 **404**로 온다.
  `NOT_FOUND` 분기 하나가 "없는 작업"과 "남의 작업"을 모두 덮는다 — 둘을 구분하려 들면
  구분할 정보가 응답에 없어서 실패한다

```ts
// 상세 화면의 분기 — 없음과 남의 것을 가르지 않는다
const notFound = computed(() => (error.value as ApiError | null)?.code === 'NOT_FOUND');
```

## 오용 목록 ① — 세션 관용구 대조표

| 구 습관 | 현재 형태 (이 조합) |
| --- | --- |
| `localStorage.setItem('token', ...)` | 액세스 토큰은 메모리(`session.ts`), 재발급 토큰은 `httpOnly` 쿠키 |
| 각 화면이 401을 잡아 로그인으로 보냄 | `http.ts` 한 곳. 화면은 401을 모른다 |
| 401마다 재발급 후 `request()` 재귀 호출 | `send()`를 한 번 더 부른다. 재귀는 무한 루프가 된다 |
| 로그아웃에서 `localStorage.clear()` | `clearSession()` → `queryClient.clear()` → `clearClientState()` 순서 |
| 가드에서 `if (!token) redirect` | `await ensureReady()` **후에** `isAuthenticated.value`를 본다 |
| 로그인 실패를 "없는 계정"·"비밀번호 틀림"으로 구분 | 한 문구로 일반화한다 — 구분하면 계정 존재가 누설된다 |
| `returnTo`를 `startsWith('/')`로 검사 | `safeReturnTo()` — prefix 검사는 `//host`를 통과시킨다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `ensureReady()` vs `isAuthenticated` | 앞은 **await할 것**(가드), 뒤는 **읽을 것**(화면). 가드에서 뒤만 보면 새로고침마다 튕긴다 |
| `isAuthenticated` vs `isAuthenticated.value` | 템플릿은 앞(자동 언랩), 스크립트는 뒤. 스크립트에서 앞을 쓰면 Ref 객체라 항상 truthy다 |
| `clearSession()` vs `clearClientState()` | 앞은 토큰(이음매), 뒤는 UI 스토어·localStorage(팩). 둘 다 필요하다 |
| `queryClient.clear()` vs `invalidateQueries()` | 로그아웃은 `clear()`(폐기), 데이터 변경은 `invalidateQueries()`(재요청) |
| 401 `UNAUTHENTICATED` vs 403 `FORBIDDEN` | 앞은 토큰 문제(재발급 대상), 뒤는 역할 부족(재발급해도 같다) |
| 403 `FORBIDDEN` vs 404 `NOT_FOUND` | 역할 부족이 앞, **소유권 실패는 뒤**. 403으로 소유권을 다루면 계약과 어긋난다 |
| 라우트 가드 vs 서버 인가 | 가드는 UX, 판정은 서버. 가드를 통과하지 못해도 API는 호출 가능하다 |
