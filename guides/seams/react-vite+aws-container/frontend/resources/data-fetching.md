<!-- epcc-seam: react-vite+aws-container/frontend v3.12.0 -->
# Data Fetching (REST API + TanStack Query v5)

SPA에는 서버 런타임이 없다. 모든 데이터는 자체 운영 REST API로의 HTTP 호출이며,
그 호출은 **정확히 세 층**을 거친다.

```
컴포넌트 → 쿼리/뮤테이션 훅 → 엔드포인트 함수 → http 클라이언트 → API
(화면)     (캐시 정책)        (URL·본문 계약)     (봉투 해석·에러 정규화)
```

## 0. 백엔드 응답 계약 (이 파일 전체의 전제)

| 종류 | 몸통 |
| --- | --- |
| 단건 성공 | `{ "data": { … } }` |
| 목록 성공 | `{ "data": [ … ], "nextCursor": "<cursor>" \| null }` |
| 삭제 성공 | 204, 본문 없음 |
| 실패 | `{ "error": { "code", "message", "details"? }, "requestId" }` |

- 페이지네이션은 **커서**다. 요청에 `limit`/`cursor`, 응답에 `nextCursor`(`null`이면 마지막).
  `total`도 `page`도 **없다** — 총 건수와 페이지 번호 UI는 이 백엔드로 만들 수 없다
- `details`는 **422에만** 오고 값은 필드별 **문자열 배열**(`{ "title": ["2자 이상"] }`)이다
- 화면은 `code`로 분기한다(`status`는 로깅용). **미인가 접근은 404로 온다**(존재 누설 방지) —
  403은 역할·스코프 부족에만 쓰인다

## 1. HTTP 클라이언트 (`src/api/http.ts`)

```ts
import { config } from '@/config';
import { getAccessToken } from './tokenProvider';
import { refreshOnce, handleSessionExpired } from '@/auth/session';

/** 백엔드 에러 코드표와 1:1 + 클라이언트 전용 코드. 화면 분기의 유일한 축이다 */
export type ApiErrorCode =
  | 'BAD_REQUEST' | 'UNAUTHORIZED' | 'FORBIDDEN' | 'NOT_FOUND' | 'CONFLICT'
  | 'VALIDATION_FAILED' | 'PAYLOAD_TOO_LARGE' | 'INTERNAL'    // ← 서버가 보내는 값
  | 'NETWORK_ERROR' | 'TIMEOUT' | 'BAD_SHAPE';                // ← 클라이언트가 만드는 값

/** 422의 `details` 형태: 필드 이름 → 메시지 배열 */
export type FieldErrors = Record<string, string[]>;
export type Page<T> = { items: T[]; nextCursor: string | null };

export class ApiError extends Error {
  readonly details?: FieldErrors;   // 422의 필드별 메시지
  readonly requestId?: string;      // 에러 화면에 노출한다 — 서버 로그와 잇는 유일한 끈
  constructor(readonly status: number, readonly code: ApiErrorCode, message: string,
              opts: { details?: FieldErrors; requestId?: string } = {}) {
    super(message);
    this.name = 'ApiError';
    this.details = opts.details;
    this.requestId = opts.requestId;
  }
}

type RequestOptions<T> = {
  body?: unknown; signal?: AbortSignal; auth?: boolean;
  /** 경계에서 좁히기. 넘기지 않으면 `as T`가 되어 계약 파손이 화면 깊은 곳에서 터진다 */
  parse?: (u: unknown) => T;
};

type Envelope = { data?: unknown; nextCursor?: string | null; requestId?: string;
                  error?: { code?: string; message?: string; details?: FieldErrors } };

async function request(method: string, path: string, opts: RequestOptions<unknown> = {},
                       retried = false): Promise<Envelope | null> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
  // 토큰은 auth 모듈이 주입한 공급자에서 읽는다 — http가 인증 구현을 import하지 않는다
  if (opts.auth !== false) {
    const token = await getAccessToken();
    if (token) headers.Authorization = `Bearer ${token}`;
  }

  // 취소와 타임아웃을 **결합**한다. `??`로 고르면 쿼리가 signal을 넘길 때 타임아웃이 죽는다
  const signal = AbortSignal.any(
    [opts.signal, AbortSignal.timeout(15_000)].filter(Boolean) as AbortSignal[]);

  const res = await fetch(`${config.apiBaseUrl}${path}`, {
    method, headers, signal,
    body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
  }).catch((e: unknown) => {
    const timeout = e instanceof DOMException && e.name === 'TimeoutError';
    throw new ApiError(0, timeout ? 'TIMEOUT' : 'NETWORK_ERROR', '연결에 실패했습니다.');
  });

  if (res.status === 204) return null;                     // 삭제 성공 — 본문이 없다
  const payload = (await res.json().catch(() => null)) as Envelope | null;

  if (res.status === 401) {
    // 재시도 깊이를 시그니처가 강제한다 — 재귀가 아니라 정확히 1회 (auth-and-session.md §5)
    if (!retried && (await refreshOnce())) return request(method, path, opts, true);
    await handleSessionExpired();
  }
  if (!res.ok) {
    const e = payload?.error;
    throw new ApiError(res.status, (e?.code as ApiErrorCode) ?? 'INTERNAL',
      e?.message ?? res.statusText, { details: e?.details, requestId: payload?.requestId });
  }
  return payload ?? {};
}

async function unwrap<T>(method: string, path: string, opts: RequestOptions<T> = {}): Promise<T> {
  const env = await request(method, path, opts as RequestOptions<unknown>);
  return opts.parse ? opts.parse(env?.data) : (env?.data as T);
}

export const http = {
  get: <T>(p: string, o?: RequestOptions<T>) => unwrap<T>('GET', p, o),
  /** 목록 전용 — `{ data, nextCursor }` 봉투를 `Page<T>`로 바꾼다 */
  getPage: async <T>(p: string, o?: RequestOptions<T>): Promise<Page<T>> => {
    const env = await request('GET', p, o as RequestOptions<unknown>);
    const rows = Array.isArray(env?.data) ? env.data : [];
    return { items: o?.parse ? rows.map(o.parse) : (rows as T[]), nextCursor: env?.nextCursor ?? null };
  },
  post: <T>(p: string, body: unknown, o?: RequestOptions<T>) => unwrap<T>('POST', p, { ...o, body }),
  patch: <T>(p: string, body: unknown, o?: RequestOptions<T>) => unwrap<T>('PATCH', p, { ...o, body }),
  delete: async (p: string, o?: RequestOptions<void>): Promise<void> => { await request('DELETE', p, o); },
};
```

- **봉투 해석은 이 파일에만 있다.** 화면과 훅은 `data`가 벗겨진 값과 `Page<T>`만 본다
- 에러를 `ApiError` 하나로 정규화하고 `requestId`를 보존한다 — 화면은 `e.code`만 보면 되고,
  사용자가 화면에 뜬 요청 ID를 알려주면 서버 로그에서 그 요청 하나를 찾을 수 있다

## 2. 엔드포인트 함수와 쿼리 키

```ts
// features/tasks/api/tasks.api.ts — URL·쿼리스트링 조립이 이 파일 밖으로 새지 않는다.
// toQuery(f, cursor)는 status·limit·cursor를 조립한다 (전체 구현은 full-example.md §2)
export const listTasks = (f: TaskFilter, cursor?: string, signal?: AbortSignal): Promise<Page<Task>> =>
  http.getPage<Task>(`/tasks?${toQuery(f, cursor)}`, { signal, parse: parseTask });

export const createTask = (input: CreateTaskInput) =>
  http.post<Task>('/tasks', input, { parse: parseTask });   // parse가 경계에서 좁힌다
```

```ts
// features/tasks/api/tasks.keys.ts — 키는 팩토리 한 곳에서만 만든다
export const taskKeys = {
  all: ['tasks'] as const,
  lists: () => [...taskKeys.all, 'list'] as const,
  list: (f: TaskFilter) => [...taskKeys.lists(), f] as const,
  details: () => [...taskKeys.all, 'detail'] as const,
  detail: (id: string) => [...taskKeys.details(), id] as const,
};
```

계층형 키의 이유: `invalidateQueries({ queryKey: taskKeys.lists() })` 한 번이 필터가
무엇이든 모든 목록 쿼리를 무효화한다. 키를 문자열로 흩뿌리면 이 접두사 매칭이 불가능해진다.
커서는 키에 넣지 않는다 — 페이지들은 `useInfiniteQuery`가 한 캐시 항목 안에 모은다.

## 3. 쿼리 훅 — 목록은 커서 무한 쿼리

```ts
export function useTasksQuery(filter: TaskFilter) {
  return useInfiniteQuery({
    queryKey: taskKeys.list(filter),
    queryFn: ({ pageParam, signal }) => listTasks(filter, pageParam, signal),
    initialPageParam: undefined as string | undefined,   // 첫 요청에는 cursor 없음
    getNextPageParam: (last) => last.nextCursor ?? undefined,  // null이면 더 없음
    staleTime: 30_000,            // 30초 안에는 화면 복귀해도 재요청하지 않는다
    placeholderData: keepPreviousData, // 필터 전환 시 이전 목록 유지 (깜빡임 방지)
  });
}
```

단건은 평범한 `useQuery`이고, 봉투가 벗겨진 값이 그대로 `data`다. 목록 화면에서 항목을
펴는 것도 한 줄이다: `const tasks = data.pages.flatMap((p) => p.items)`.

`staleTime` 기준선:

| 데이터 성격 | staleTime | 예 |
| --- | --- | --- |
| 거의 안 변함 | `Infinity` 또는 1시간 | 코드 목록, 권한 정의 |
| 사람이 가끔 고침 | 30초~5분 | 프로젝트 설정, 목록 화면 |
| 실시간에 가까움 | 0 + `refetchInterval` | 대시보드 카운터 |

`gcTime`(기본 5분)은 **화면에서 사라진 뒤 캐시가 버려지기까지의 시간**이다.
`staleTime`(신선도)과 다른 축이라는 점을 혼동하지 않는다.

## 4. 뮤테이션과 무효화

```ts
// useMutation의 onSuccess (전체 훅은 full-example.md §4)
onSuccess: (created) => {
  qc.invalidateQueries({ queryKey: taskKeys.lists() });   // 목록 전체 무효화
  qc.setQueryData(taskKeys.detail(created.id), created);  // 상세는 응답으로 즉시 채움
},
```

- **무효화 누락이 이 계층의 대표 결함이다.** 생성/수정/삭제를 추가할 때마다
  "이 변이가 낡게 만드는 쿼리 키가 무엇인가"를 적고, 그 키를 전부 무효화한다
- 서버가 변경된 리소스를 응답으로 돌려주면 `setQueryData`로 재요청 한 번을 아낀다
- 낙관적 업데이트는 `onMutate`에서 `cancelQueries` → 스냅샷 → `setQueryData`, `onError`에서
  복원, `onSettled`에서 무효화 — 네 단계를 다 구현하지 않을 거면 하지 않는다

## 5. QueryClient 기본값 (`src/main.tsx`)

```ts
const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: (failureCount, error) => {
        // 4xx는 재시도해도 결과가 같다. 429도 포함 — 자동 재시도는 폭주를 키운다
        if (error instanceof ApiError && error.status >= 400 && error.status < 500) return false;
        return failureCount < 2;    // 네트워크 실패(status 0)와 5xx만 재시도
      },
      refetchOnWindowFocus: true,
    },
    mutations: { retry: false },   // 쓰기 재시도는 중복 생성을 만든다
  },
});
```

**429는 자동 재시도하지 않는다.** `Retry-After`를 존중하는 백오프 없이 다시 던지면 요율
제한을 더 세게 때린다 — 사용자에게 안내하고 수동 재시도 버튼을 준다
(`loading-error-states.md` §4와 같은 정책. 두 파일이 어긋나면 안 된다).

## 6. 경계를 lint로 강제한다

"서버 전용 모듈"이라는 도피처가 없으므로 — 번들은 하나이고 전부 공개된다 — 경계는
**규율이 아니라 빌드 실패로** 강제한다.

```js
// eslint.config.js (플랫 설정)
import importPlugin from 'eslint-plugin-import';  // 등록 없이 규칙만 쓰면 설정 로드 자체가 실패한다
const useClient = 'src/api/http.ts의 클라이언트를 사용하세요.';

export default [
  {
    files: ['src/**/*.{ts,tsx}'],
    ignores: ['src/api/**'],
    plugins: { import: importPlugin },
    rules: {
      // ① 원시 fetch 금지 — 전역 식별자에만 걸린다
      'no-restricted-globals': ['error', { name: 'fetch', message: useClient }],
      // ② HTTP 라이브러리 금지 — globals 규칙은 import를 막지 못한다
      'no-restricted-imports': ['error', { paths: [{ name: 'axios', message: useClient }] }],
      // ③ 방향 규칙: 공통 층은 기능을 모른다 + 기능끼리 교차 import 금지
      //    (기능을 추가할 때마다 마지막 형태의 zone을 하나씩 늘린다)
      'import/no-restricted-paths': ['error', { zones: [
        { target: './src/components', from: './src/features' },
        { target: './src/lib', from: './src/features' },
        { target: './src/features/tasks', from: './src/features', except: ['./tasks'] },
      ] }],
    },
  },
];
```

```jsonc
// package.json — lint 실패가 빌드 실패가 되게 한다
{ "scripts": { "build": "npm run typecheck && eslint . --max-warnings 0 && vite build" } }
```

추가로 CI에서 비밀 유입을 막는다 — 이 이름들이 소스에 등장하는 순간 실패시킨다.

```bash
! rg -n "VITE_[A-Z_]*(SECRET|PASSWORD|PRIVATE|TOKEN|CREDENTIAL)" src/
```

## 7. 하지 않는 것

- **라우터 loader로 데이터를 가져오지 않는다.** 캐시는 TanStack Query 하나다 (`routing.md`)
- **`useEffect` + `fetch` + `useState`를 쓰지 않는다.** 취소·경쟁 조건·중복 요청·재시도를
  직접 구현하게 된다
- **`import.meta.env`를 직접 읽지 않는다.** 환경 값은 `src/config.ts` 한 곳에서 읽어 타입을
  붙인 뒤 내보낸다 (`types-and-testing.md` §2). `http.ts`·`oidcConfig`도 예외가 아니다
- **`page`/`total`을 쓰지 않는다.** 백엔드는 커서만 준다 — 번호 페이지네이션은 만들 수 없다

## 오용 목록 ① — v4 → v5 관용구 대조표

| v4 습관 | v5 형태 |
| --- | --- |
| `useQuery(key, fn, options)` | `useQuery({ queryKey, queryFn, ...options })` — 객체 시그니처만 |
| `cacheTime` | `gcTime` |
| `isLoading`으로 "데이터 없음" 판정 | `isPending` (v5의 `isLoading`은 `isPending && isFetching`) · `status: 'loading'` → `'pending'` |
| `useQuery`의 `onSuccess`/`onError`/`onSettled` | **제거됨.** 부수효과는 컴포넌트에서 `data`/`error`를 보고 처리하거나 뮤테이션으로 옮긴다 |
| `keepPreviousData: true` | `placeholderData: keepPreviousData` (함수를 import해서 전달) |
| `useErrorBoundary: true` | `throwOnError: true` |
| `invalidateQueries(key)` | `invalidateQueries({ queryKey: key })` — 필터는 객체로만 |
| `query.remove()` | `queryClient.removeQueries({ queryKey })` |
| `useInfiniteQuery`에 `initialPageParam` 없음 | v5에서 **필수**다. 빠지면 첫 페이지 요청이 시작되지 않는다 |

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `isPending` vs `isFetching` vs `isRefetching` | `isPending`은 캐시에 데이터가 아직 없음(첫 로딩 → 스켈레톤). `isFetching`은 요청이 떠 있음(배경 갱신 → 상단 얇은 인디케이터). `isRefetching`은 데이터가 있는 상태의 재요청 |
| `enabled: false`인 쿼리의 `isPending` | 비활성 쿼리는 `isPending`이 **영구 true**다. "첫 분기는 `isPending`" 규칙을 그대로 쓰면 스켈레톤이 영원히 남는다 → `isLoading`(= `isPending && isFetching`)으로 분기하거나 비활성 상태를 먼저 따로 그린다 |
| `invalidateQueries` vs `refetchQueries` | 무효화는 "낡았다"고 표시만 하고 **화면에 붙어 있는 쿼리만** 다시 부른다(기본). `refetchQueries`는 비활성 쿼리까지 강제로 부른다 — 대부분의 경우 무효화가 맞다 |
| `setQueryData` vs `invalidateQueries` | 서버 응답이 그 리소스의 최종 형태이면 `setQueryData`. 서버가 다른 필드까지 바꿨을 수 있으면 무효화 |
| `resetQueries` vs `removeQueries` | `reset`은 초기 상태로 되돌리고 활성 쿼리를 다시 부른다. `remove`는 캐시에서 지운다(로그아웃 시엔 `queryClient.clear()`) |
| `enabled: false` vs 조건부 훅 호출 | 훅은 조건부로 호출할 수 없다. 파라미터가 준비되지 않았으면 `enabled: !!id` |
| `placeholderData` vs `initialData` | `initialData`는 **진짜 데이터로 캐시에 저장**되어 신선도 타이머가 시작된다. `placeholderData`는 캐시에 저장되지 않는 임시 표시용 |
| `mutate` vs `mutateAsync` | 기본은 `mutate` + `onSuccess`/`onError` 콜백. `mutateAsync`는 `await`가 필요할 때만 쓰고 **반드시 try/catch로 감싼다**(안 잡으면 unhandled rejection) |
| 쿼리 키에 필터 객체 vs 직렬화 문자열 | 객체를 그대로 넣는다. Query가 구조적 해시로 비교하므로 키 순서는 문제되지 않는다. 직접 `JSON.stringify` 하면 접두사 무효화가 깨진다 |
| `error.status`로 분기 vs `error.code`로 분기 | 분기는 **`code`**로 한다. 같은 404가 "없는 리소스"와 "남의 리소스"를 모두 뜻하므로 상태 코드만으로는 문구를 고를 수 없다 |
