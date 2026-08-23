<!-- epcc-seam: vue+node-api v3.13.0 -->
# Data Fetching — HTTP 클라이언트부터 쿼리 컴포저블까지

이 파일이 **와이어 계약을 코드로 옮긴 자리**다. 봉투 해석 · 에러 정규화 · 커서 소비 ·
캐시 무효화가 여기 있다. 3상태 렌더링은 `resources/loading-error-states.md`, 스토어
경계는 `resources/state-management.md`, 앱 배선은 `resources/complete-example.md` §5다.

경계는 **하나뿐이다** — SPA와 별도 API 서버 사이의 HTTP 하나. 서버 컴포넌트가 없으니
"서버 전용 모듈이 클라이언트 번들에 섞이는" 사고도 없다. 대신 **모든 요청이 인증 헤더를
스스로 붙여야 하고**, 그 의무는 §3의 단일 모듈에 갇혀 있어야 한다.

## 1. 새 요청을 어디에 두는가

| 하려는 일 | 두는 곳 | 이유 |
| --- | --- | --- |
| 헤더·타임아웃·에러 정규화 | `src/api/http.ts` (§3) | 앱 전체에 하나. 두 번째가 생기면 인증 헤더가 갈라진다 |
| `/api/tasks`를 부르는 함수 | `src/features/tasks/api/tasks.ts` (§4) | 경로 문자열과 쿼리 파라미터 조립이 한 곳에 모인다 |
| 화면이 쓰는 목록/단건 | 쿼리 컴포저블 (§5) | 캐시 키·재요청·GC를 Vue Query가 갖는다 |
| 생성·수정·삭제 | 뮤테이션 컴포저블 (§6) | 무효화 대상을 뮤테이션이 안다 |
| 응답 필드 확인 | `tasks.parse.ts`의 `parseTask`·`parseTaskList` | 팩이 소유한다. 이음매는 호출만 한다 |
| 전역 재시도·staleTime | `src/api/queryClient.ts` | 재시도 판정이 에러 코드의 함수다 — `complete-example.md` §5 |

컴포넌트에서 `fetch`를 직접 부르지 않는다 — 토큰·에러 형식·베이스 URL이 화면마다
다시 발명된다. 이 금지는 팩의 `http-in-api-layer` 정책이 기계로 잡는다.

## 2. 도메인 타입과 에러 봉투 (`src/types/task.ts` · `src/api/errors.ts`)

계약 §1은 성공 봉투를 `{ data }`(+목록은 `nextCursor`), §2는 실패 봉투를
`{ error: { code, message, details? }, requestId }`로 고정한다.

<!-- file: src/types/task.ts -->
```ts
// src/types/task.ts
export interface Task {
  id: string;
  title: string;
  createdAt: string;              // ISO 8601 문자열. Date로 변환하는 곳은 화면이다
  status: 'open' | 'done';        // 선택이 아니다 — 팩의 component-patterns.md §10이 값을 비교한다
}
```

<!-- file: src/api/errors.ts -->
```ts
// src/api/errors.ts
// 서버가 보내는 코드(계약 §4)와 클라이언트가 스스로 만드는 코드를 한 유니온에 둔다.
export type ApiErrorCode =
  | 'VALIDATION_FAILED' | 'UNAUTHENTICATED' | 'FORBIDDEN' | 'NOT_FOUND'
  | 'CONFLICT' | 'PAYLOAD_TOO_LARGE' | 'INTERNAL'
  | 'NETWORK_ERROR' | 'TIMEOUT' | 'BAD_SHAPE';   // ← 서버는 이 셋을 보내지 않는다

export class ApiError extends Error {
  readonly code: string;
  readonly status: number;                        // 전송 실패는 0
  readonly requestId?: string;                    // 서버 로그와 맞추는 유일한 열쇠
  readonly details?: Record<string, string[]>;    // VALIDATION_FAILED에만 실린다

  constructor(code: string, message: string,
              meta: { status?: number; requestId?: string; details?: Record<string, string[]> } = {}) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = meta.status ?? 0;
    this.requestId = meta.requestId;
    this.details = meta.details;
  }
}
```

`code`가 `ApiErrorCode`가 아니라 `string`인 이유: 유니온 밖의 코드가 와도 **던지는 데
실패하면 안 된다.** 좁히기는 소비처(`switch`)가 한다.

| 계약 코드 | 상태 | 화면이 할 일 |
| --- | --- | --- |
| `VALIDATION_FAILED` | 400 | `details`를 필드 아래 표시. 재시도 버튼 없음 |
| `UNAUTHENTICATED` | 401 | 화면이 다루지 않는다 — §3의 재발급 1회가 처리한다 |
| `FORBIDDEN` | 403 | 역할 부족. 재시도 버튼 없음 |
| `NOT_FOUND` | 404 | **「없거나 내 것이 아니다」 한 화면**(계약 §5). 403과 구분하지 않는다 |
| `CONFLICT` | 409 | 목록을 무효화하고 다시 읽게 한다 |
| `PAYLOAD_TOO_LARGE` | 413 | 입력 크기를 알린다 |
| `INTERNAL` | 500 | 일반 문구 + `requestId` 표시. 재시도 가능 |
| `NETWORK_ERROR`·`TIMEOUT` | — | 팩의 `toUserMessage`가 문구를 갖는다 |
| `BAD_SHAPE` | — | 계약 파손. 재시도해도 결과가 같다 |

## 3. HTTP 클라이언트 (`src/api/http.ts`)

`fetch`가 등장하는 유일한 파일이다. 세 가지를 이 파일이 독점한다: **타임아웃 ·
에러 정규화 · 401 재발급 1회**. 재발급의 단일 비행은 `@/auth/session`이 갖는다
(`resources/auth-and-session.md` §2).

<!-- file: src/api/http.ts -->
```ts
// src/api/http.ts
import { config } from '@/config';
import { ApiError } from './errors';
import { getAccessToken, refreshSession, clearSession } from '@/auth/session';

const TIMEOUT_MS = 15_000;

async function send(path: string, init: RequestInit): Promise<Response> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  const token = getAccessToken();
  try {
    return await fetch(`${config.apiBaseUrl}${path}`, {
      ...init,
      signal: ctrl.signal,
      credentials: 'include',              // 재발급 쿠키. 서버 CORS가 허용해야 한다
      headers: {
        'Content-Type': 'application/json',
        ...(token ? { Authorization: `Bearer ${token}` } : {}),
        ...init.headers,
      },
    });
  } catch {
    // fetch는 네트워크 실패와 중단을 같은 예외로 던진다 — signal로 가른다
    throw ctrl.signal.aborted
      ? new ApiError('TIMEOUT', '요청이 시간 안에 끝나지 않았습니다.')
      : new ApiError('NETWORK_ERROR', '서버에 연결하지 못했습니다.');
  } finally {
    clearTimeout(timer);
  }
}

function toApiError(body: unknown, status: number): ApiError {
  const env = (body ?? {}) as { error?: { code?: unknown; message?: unknown; details?: unknown }; requestId?: unknown };
  const requestId = typeof env.requestId === 'string' ? env.requestId : undefined;
  if (typeof env.error?.code !== 'string') return new ApiError('BAD_SHAPE', '에러 봉투가 계약과 다릅니다.', { status, requestId });
  const message = typeof env.error.message === 'string' ? env.error.message : '요청을 처리하지 못했습니다.';
  return new ApiError(env.error.code, message, { status, requestId, details: env.error.details as Record<string, string[]> | undefined });
}

async function request(path: string, init: RequestInit): Promise<Record<string, unknown> | null> {
  let res = await send(path, init);
  if (res.status === 401) {
    // 재발급은 요청당 정확히 1회. 재귀하지 않는다 — 실패하면 원래 401을 그대로 올린다
    if (!(await refreshSession())) {
      clearSession();
      throw toApiError(await res.json().catch(() => null), 401);
    }
    res = await send(path, init);
  }
  if (res.status === 204) return null;                       // 계약 §1: 삭제는 본문이 없다
  const text = await res.text();
  let body: unknown = null;
  if (text !== '') {
    try { body = JSON.parse(text); }
    catch { throw new ApiError('BAD_SHAPE', '응답이 JSON이 아닙니다.', { status: res.status }); }
  }
  if (!res.ok) throw toApiError(body, res.status);
  if (body === null || typeof body !== 'object' || !('data' in body)) {
    throw new ApiError('BAD_SHAPE', '응답 봉투에 data가 없습니다.', { status: res.status });
  }
  return body as Record<string, unknown>;
}

export const http = {
  get: async (path: string, init?: RequestInit): Promise<unknown> => (await request(path, { ...init, method: 'GET' }))?.data ?? null,
  post: async (path: string, init?: RequestInit): Promise<unknown> => (await request(path, { ...init, method: 'POST' }))?.data ?? null,
  patch: async (path: string, init?: RequestInit): Promise<unknown> => (await request(path, { ...init, method: 'PATCH' }))?.data ?? null,
  delete: async (path: string, init?: RequestInit): Promise<unknown> => (await request(path, { ...init, method: 'DELETE' }))?.data ?? null,
  // 네 메서드는 봉투를 벗기므로 nextCursor를 볼 수 없다. 목록만 봉투째 받는다
  page: async (path: string, init?: RequestInit): Promise<{ data: unknown; nextCursor: string | null }> => {
    const env = await request(path, { ...init, method: 'GET' });
    return { data: env?.data ?? null, nextCursor: typeof env?.nextCursor === 'string' ? env.nextCursor : null };
  },
};
```

<!-- verified: 실제 node:http 서버 대상 실행 — 닫힌 포트→NETWORK_ERROR, 200ms 지연→TIMEOUT(208ms), 비JSON 본문·data 없는 200·error 없는 500→모두 BAD_SHAPE, 400→VALIDATION_FAILED(details 보존), 204→null -->
전송 실패를 `ApiError`로 정규화하는 것이 **팩의 전제다**: `toUserMessage`는
`NETWORK_ERROR`·`TIMEOUT`만 문구를 갖는다. raw `TypeError`를 흘리면 폴백 문구만 남는다.

## 4. 엔드포인트 함수와 쿼리 키 (`src/features/tasks/api/tasks.ts`)

<!-- file: src/features/tasks/api/tasks.ts -->
```ts
// src/features/tasks/api/tasks.ts
import { http } from '@/api/http';
import { parseTask, parseTaskList } from './tasks.parse';   // 팩 소유 (types-and-testing.md §4)
import type { Task } from '@/types/task';

export interface TaskFilter { status?: 'open' | 'done'; limit?: number }
export interface TaskPage { items: Task[]; nextCursor: string | null }

// 키는 한 곳에서만 만든다. 화면이 배열 리터럴을 직접 쓰면 무효화가 조용히 빗나간다
export const taskKeys = {
  all: ['tasks'] as const,
  list: (filter: TaskFilter) => ['tasks', 'list', filter] as const,
  detail: (id: string) => ['tasks', 'detail', id] as const,
};

export async function fetchTaskPage(filter: TaskFilter, cursor?: string): Promise<TaskPage> {
  const q = new URLSearchParams();
  if (filter.status) q.set('status', filter.status);
  q.set('limit', String(filter.limit ?? 20));
  if (cursor) q.set('cursor', cursor);           // 계약 §3: limit · cursor (page·skip은 없다)
  const page = await http.page(`/api/tasks?${q.toString()}`);
  return { items: parseTaskList(page.data), nextCursor: page.nextCursor };
}

export async function createTask(input: { title: string }): Promise<Task> {
  return parseTask(await http.post('/api/tasks', { body: JSON.stringify(input) }));
}
```

`parseTaskList`는 **봉투를 벗기지 않는다** — `page.data`를 넘긴다. 봉투째 넘기면
`ApiError('BAD_SHAPE', '목록 응답이 배열이 아닙니다.')`가 그 자리에서 터진다.

## 5. 목록 쿼리 — 커서를 평탄한 배열로 (`useTasksQuery.ts`)

계약은 커서 페이지네이션인데 팩은 `data`가 `Ref<Task[] | undefined>`이기를 요구한다.
둘을 잇는 것이 `select`다 — 내부는 `useInfiniteQuery`, 바깥은 평탄한 배열이다.

<!-- file: src/features/tasks/api/useTasksQuery.ts -->
```ts
// src/features/tasks/api/useTasksQuery.ts
import { computed, toValue, type MaybeRefOrGetter } from 'vue';
import { useInfiniteQuery } from '@tanstack/vue-query';
import { fetchTaskPage, taskKeys, type TaskFilter } from './tasks';

export function useTasksQuery(filter?: MaybeRefOrGetter<TaskFilter>) {
  const current = computed<TaskFilter>(() => toValue(filter) ?? {});   // 무인자 호출도 정상
  return useInfiniteQuery({
    queryKey: computed(() => taskKeys.list(current.value)),   // 키가 ref여야 필터 변경에 재요청한다
    queryFn: ({ pageParam }) => fetchTaskPage(current.value, pageParam),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.nextCursor ?? undefined, // null이면 마지막 페이지
    select: (data) => data.pages.flatMap((p) => p.items),     // ← 화면은 Task[]만 본다
    staleTime: 30_000,
  });
}
```

<!-- verified: 실제 서버 + createApp 마운트 실행 — limit=2로 5행을 3회에 나눠 받았고 data는 ["t1","t2"]→["t1","t2","t3","t4"]→5건, hasNextPage가 마지막에서 false, 필터 변경 시 요청 1회 추가 -->
`getNextPageParam`이 `undefined`를 반환해야 `hasNextPage`가 false가 된다 — `null`을
그대로 돌려주면 "커서가 null인 페이지"를 한 번 더 요청한다.

## 6. 생성 뮤테이션과 무효화 (`useCreateTaskMutation.ts`)

<!-- file: src/features/tasks/api/useCreateTaskMutation.ts -->
```ts
// src/features/tasks/api/useCreateTaskMutation.ts
import { useMutation, useQueryClient } from '@tanstack/vue-query';
import { createTask, taskKeys } from './tasks';

export function useCreateTaskMutation() {
  const queryClient = useQueryClient();
  const m = useMutation({
    mutationFn: createTask,
    // 접두 일치다 — taskKeys.all은 list·detail을 모두 덮는다
    onSuccess: () => { void queryClient.invalidateQueries({ queryKey: taskKeys.all }); },
  });
  return { mutate: m.mutate, isPending: m.isPending };
}
```

`mutate`는 **값을 반환하지 않고 던지지도 않는다.** 실패는 `mutate(input, { onError })`의
콜백으로만 온다 — 팩의 `onErrorCaptured` 경계는 뮤테이션 실패를 잡지 못하므로 `onError`를
빠뜨리면 아무도 잡지 않는다. `mutateAsync`는 쓰지 않는다: 거부한 Promise가 흐른다.

<!-- verified: 실행 — mutate() 반환값은 undefined, isPending은 Ref, 검증 실패에서 onError가 ApiError(VALIDATION_FAILED, details={title:[...]})를 받았다 -->
무효화 비용: `useInfiniteQuery`를 무효화하면 **적재된 페이지 전부**를 다시 읽는다.
페이지 3장을 연 상태의 생성 1건이 목록 요청 3건이 됐다.

## 오용 목록 ① — React Query → Vue Query 관용구 대조표

이 축의 최대 위험이다. React 예제를 옮기면 타입이 통과하면서 반응성만 죽는다.

| 구 습관 (React Query) | 현재 형태 (`@tanstack/vue-query` v5) |
| --- | --- |
| `from '@tanstack/react-query'` | `from '@tanstack/vue-query'` — 팩 정책 `no-react-query`가 기계로 막는다 |
| `const { data } = useQuery(...)`를 값으로 읽기 | `data`는 `Ref`다. 스크립트에서는 `data.value`, 템플릿에서는 자동 언랩 |
| `queryKey: ['tasks', filter]` (평범한 배열) | 필터가 반응형이면 `computed(() => ...)`로 감싼다. 정적 배열은 갱신되지 않는다 |
| `enabled: !!id` | `enabled: computed(() => !!id.value)` — 불리언 리터럴은 첫 값에 얼어붙는다 |
| `useQueryClient()`를 이벤트 핸들러에서 호출 | setup 본문에서 한 번 꺼내 둔다. 핸들러는 setup 컨텍스트가 아니다 |
| `isLoading` | `isPending`(첫 로딩) · `isFetching`(배경 갱신 포함). v5에서 이름이 갈렸다 <!-- verified: @tanstack/vue-query@5.102.0 반환 객체에 isPending·isFetching 실재, 실행 확인 --> |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `http.get` vs `http.page` | `nextCursor`가 필요하면 `page`. 단건·생성·삭제는 `get`/`post`/`delete` |
| `data` vs `data.pages` | 화면은 항상 `data`(평탄한 `Task[]`). `select`를 지우면 팩의 3상태 예시가 통째로 깨진다 |
| `isPending` vs `isFetching` | 스켈레톤은 `isPending`, 배경 갱신 바는 `isFetching`. `enabled: false`인 쿼리는 `isPending`이 영구 true다 |
| `invalidateQueries` vs `refetch` | 키로 넓게 무효화하는 것이 앞, 이 화면 하나만 다시 읽는 것이 뒤 |
| `taskKeys.all` vs `taskKeys.list(f)` | 무효화는 `all`(접두 일치), 구독은 `list(f)`. 반대로 쓰면 다른 필터의 캐시가 남는다 |
| `ApiError.status` vs `ApiError.code` | 화면 분기는 **항상 `code`**. `status`는 로그·리포트용이다 |
| 404를 "없음"으로만 처리 | 계약 §5에서 404는 **없거나 남의 것**이다. 소유권 실패가 403으로 오지 않는다 |
