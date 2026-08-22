# 완전 예제 — Tasks 기능 (목록 조회 + 생성)

기능 하나가 타입 선언부터 화면까지 어떻게 이어지는지를 파일 순서 그대로 보여준다.
새 기능을 만들 때 이 순서(타입 → 요청 함수 → 키 → 훅 → 화면 → 라우트)를 그대로 따른다.
백엔드 계약(봉투 `{ data }`, 커서 페이지네이션, `code` 분기)은 `data-fetching.md` §0에 있다.

```
src/features/tasks/
├── api/
│   ├── tasks.types.ts     # 요청/응답 계약 + 경계 좁히기
│   ├── tasks.api.ts       # 엔드포인트 함수
│   ├── tasks.keys.ts      # 쿼리 키 팩토리
│   └── tasks.hooks.ts     # useInfiniteQuery / useMutation
├── components/
│   ├── TaskTable.tsx
│   └── CreateTaskDialog.tsx
└── pages/
    └── TaskListPage.tsx
```

## 1. 계약 (`api/tasks.types.ts`)

```ts
import { ApiError } from '@/api/http';

export type TaskStatus = 'open' | 'in_progress' | 'done';

export type Task = {
  id: string;
  title: string;
  status: TaskStatus;
  assigneeName: string | null;
  createdAt: string;      // ISO 8601 — Date 변환은 표시 직전에만
};

/** 화면이 소유하는 필터. `page`는 없다 — 백엔드는 커서만 준다 */
export type TaskFilter = { status: TaskStatus | 'all'; limit?: number };
export type CreateTaskInput = { title: string; assigneeId?: string };

/** 경계 좁히기 — http 클라이언트의 `parse` 옵션에 넘긴다 (types-and-testing.md §3) */
export function assertTask(v: unknown): asserts v is Task {
  const t = v as Record<string, unknown> | null;
  if (!t || typeof t.id !== 'string' || typeof t.title !== 'string') {
    throw new ApiError(500, 'BAD_SHAPE', '응답 형식이 계약과 다릅니다.');
  }
}
export const parseTask = (v: unknown): Task => { assertTask(v); return v; };
```

목록 응답 타입을 따로 만들지 않는다. 봉투 해석은 `http.getPage`가 하고, 화면은
`Page<Task>`(= `{ items, nextCursor }`)만 본다.

## 2. 엔드포인트 함수 (`api/tasks.api.ts`)

```ts
import { http, type Page } from '@/api/http';
import { parseTask } from './tasks.types';
import type { CreateTaskInput, Task, TaskFilter } from './tasks.types';

const toQuery = (f: TaskFilter, cursor?: string) => {
  const q = new URLSearchParams();
  if (f.status !== 'all') q.set('status', f.status);
  q.set('limit', String(f.limit ?? 20));
  if (cursor) q.set('cursor', cursor);        // 첫 페이지에는 붙이지 않는다
  return q.toString();
};

export const listTasks = (f: TaskFilter, cursor?: string, signal?: AbortSignal): Promise<Page<Task>> =>
  http.getPage<Task>(`/tasks?${toQuery(f, cursor)}`, { signal, parse: parseTask });

export const createTask = (input: CreateTaskInput) =>
  http.post<Task>('/tasks', input, { parse: parseTask });
```

URL 조립이 이 파일 밖으로 새지 않는다. 화면은 `/tasks`도 `cursor`라는 이름도 모른다.

## 3. 쿼리 키 (`api/tasks.keys.ts`)

```ts
import type { TaskFilter } from './tasks.types';

export const taskKeys = {
  all: ['tasks'] as const,
  lists: () => [...taskKeys.all, 'list'] as const,
  list: (f: TaskFilter) => [...taskKeys.lists(), f] as const,
  details: () => [...taskKeys.all, 'detail'] as const,
  detail: (id: string) => [...taskKeys.details(), id] as const,
};
```

`data-fetching.md` §2와 **같은 파일, 같은 내용**이다. 팩토리가 두 벌이 되면 무효화 쪽 키와
조회 쪽 키가 조용히 갈라진다. 커서는 키에 넣지 않는다 — 페이지들은 한 캐시 항목 안에 모인다.

## 4. 훅 (`api/tasks.hooks.ts`)

```ts
import { keepPreviousData, useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { createTask, listTasks } from './tasks.api';
import { taskKeys } from './tasks.keys';
import type { TaskFilter } from './tasks.types';

export function useTasksQuery(filter: TaskFilter) {
  return useInfiniteQuery({
    queryKey: taskKeys.list(filter),
    queryFn: ({ pageParam, signal }) => listTasks(filter, pageParam, signal),
    initialPageParam: undefined as string | undefined,      // v5에서 필수
    getNextPageParam: (last) => last.nextCursor ?? undefined,  // null이면 마지막 페이지
    staleTime: 30_000,
    placeholderData: keepPreviousData,   // 필터 전환 시 목록이 사라지지 않는다
  });
}

export function useCreateTaskMutation() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: createTask,
    onSuccess: (created) => {
      // 이 변이가 낡게 만드는 키: 모든 목록 쿼리 (필터가 무엇이든)
      qc.invalidateQueries({ queryKey: taskKeys.lists() });
      qc.setQueryData(taskKeys.detail(created.id), created);
    },
  });
}
```

## 5. 화면 (`pages/TaskListPage.tsx`)

```tsx
import { useState } from 'react';
import { useSearchParams } from 'react-router';
import { PageShell } from '@/components/layout/PageShell';
import { Button } from '@/components/common/Button';
import { EmptyState } from '@/components/common/EmptyState';
import { ErrorState } from '@/components/common/ErrorState';
import { ListSkeleton } from '@/components/common/ListSkeleton';
import { useTasksQuery } from '../api/tasks.hooks';
import type { TaskFilter } from '../api/tasks.types';
import { CreateTaskDialog } from '../components/CreateTaskDialog';
import { TaskTable } from '../components/TaskTable';

export function Component() {
  const [params, setParams] = useSearchParams();
  const [isDialogOpen, setDialogOpen] = useState(false);

  // 필터는 URL이 소유한다(공유·새로고침·뒤로가기가 공짜). 커서는 넣지 않는다 — 불투명 값이다
  const filter: TaskFilter = { status: (params.get('status') as TaskFilter['status']) ?? 'all' };
  const query = useTasksQuery(filter);
  const setStatus = (status: TaskFilter['status']) => setParams({ status }, { replace: true });

  return (
    <PageShell title="작업" actions={<Button onClick={() => setDialogOpen(true)}>새 작업</Button>}>
      <StatusTabs value={filter.status} onChange={setStatus} />
      <TaskListBody query={query} filter={filter}
        onCreate={() => setDialogOpen(true)} onResetFilter={() => setStatus('all')} />
      <CreateTaskDialog open={isDialogOpen} onClose={() => setDialogOpen(false)} />
    </PageShell>
  );
}
Component.displayName = 'TaskListPage';

// 같은 파일 아래쪽 — 밖에서 쓰지 않는 하위 컴포넌트는 파일을 나누지 않는다.
// 3상태 분기를 여기 모으면 이른 반환으로 타입이 좁혀져 `data?.pages ?? []`가 필요 없다
function TaskListBody({ query, filter, onCreate, onResetFilter }: {
  query: ReturnType<typeof useTasksQuery>;
  filter: TaskFilter;
  onCreate: () => void;
  onResetFilter: () => void;
}) {
  const { data, isPending, isError, error, isFetching, refetch,
          fetchNextPage, hasNextPage, isFetchingNextPage } = query;

  if (isPending) return <ListSkeleton rows={5} />;
  if (isError) return <ErrorState error={error} onRetry={refetch} />;

  const tasks = data.pages.flatMap((p) => p.items);      // 커서 페이지들을 하나로 편다
  if (tasks.length === 0) {
    return filter.status === 'all' ? (
      <EmptyState title="아직 작업이 없습니다" description="새 작업을 만들어 시작하세요."
        action={<Button onClick={onCreate}>새 작업</Button>} />
    ) : (
      <EmptyState title="조건에 맞는 작업이 없습니다"
        action={<Button variant="secondary" onClick={onResetFilter}>필터 초기화</Button>} />
    );
  }
  return (
    <>
      {isFetching && !isFetchingNextPage && <TopProgressBar />}
      <TaskTable rows={tasks} />
      {/* 페이지 번호가 아니라 "더 보기"다 — 백엔드가 주는 것은 nextCursor뿐이다 */}
      {hasNextPage && (
        <Button variant="secondary" className="mt-4 w-full"
          disabled={isFetchingNextPage} onClick={() => fetchNextPage()}>
          {isFetchingNextPage ? '불러오는 중…' : '더 보기'}
        </Button>
      )}
    </>
  );
}
```

## 6. 생성 폼 (`components/CreateTaskDialog.tsx`)

```tsx
export function CreateTaskDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  const [title, setTitle] = useState('');
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});   // Record<string, string[]>
  const { mutate, isPending } = useCreateTaskMutation();

  const submit = (e: FormEvent) => {
    e.preventDefault();
    setFieldErrors({});
    // 클라이언트 검증은 선행 안내일 뿐 — 최종 판정은 서버의 422다
    if (title.trim().length < 2) {
      setFieldErrors({ title: ['제목은 2자 이상이어야 합니다.'] });
      return;
    }
    mutate(
      { title: title.trim() },
      {
        onSuccess: () => { setTitle(''); onClose(); },   // 무효화는 훅의 onSuccess가 이미 처리
        onError: (err) => {
          if (err instanceof ApiError && err.code === 'VALIDATION_FAILED' && err.details) {
            setFieldErrors(err.details);                 // 필드 → 메시지 **배열**
          } else {
            toast.error(toUserMessage(err));             // 403/404 포함 — 숨김은 UX, 판정은 서버
          }
        },
      },
    );
  };

  if (!open) return null;
  return (
    <Dialog onClose={onClose} title="새 작업">
      <form onSubmit={submit} className="space-y-4">
        <Field label="제목" htmlFor="title" error={fieldErrors.title?.[0]}>
          <input id="title" value={title} onChange={(e) => setTitle(e.target.value)}
            className="h-10 w-full rounded-md border border-surface-border px-3 text-sm"
            aria-invalid={Boolean(fieldErrors.title)} autoFocus />
        </Field>
        <div className="flex justify-end gap-2">
          <Button type="button" variant="secondary" onClick={onClose}>취소</Button>
          {/* disabled가 없으면 더블 클릭으로 두 건이 생성된다 */}
          <Button type="submit" disabled={isPending}>{isPending ? '저장 중…' : '저장'}</Button>
        </div>
      </form>
    </Dialog>
  );
}
```

## 7. 라우트 등록 (`src/routes/routes.tsx`)

```tsx
{ element: <RequireAuth />, children: [    // 인증 게이트 — UX 장치이며 보안은 서버가 한다
  { path: 'tasks', lazy: () => import('@/features/tasks/pages/TaskListPage') },
] }
```

## 8. 흐름 요약

```
URL(?status=open)
  → filter 객체                    (커서는 URL에 없다)
  → taskKeys.list(filter)          쿼리 키
  → useTasksQuery                  캐시 조회 / 필요 시 GET /tasks?status=open&limit=20
  → http.getPage                   Bearer 토큰 부착 · { data, nextCursor } 봉투 해석 · parseTask
  → 3상태 렌더                     스켈레톤 / 에러 / 빈 / 표
  → [더 보기] fetchNextPage        GET /tasks?...&cursor=<nextCursor>

[저장 클릭]
  → useCreateTaskMutation          POST /tasks → { data: Task }
  → onSuccess                      invalidateQueries(taskKeys.lists())
  → 화면에 붙어 있는 목록 쿼리 재요청 → 새 행이 나타난다
```

## 오용 목록 — 이 예제에서 실제로 어긋나는 지점

| 어긋난 형태 | 왜 문제인가 / 올바른 형태 |
| --- | --- |
| 화면에서 `fetch('/tasks')` 직접 호출 | 토큰 부착·에러 정규화·베이스 URL이 화면마다 갈라진다 → 요청 함수 + 훅을 거친다 |
| `page`/`total`로 페이지네이션 구현 | 백엔드는 `nextCursor`만 준다. 총 건수·페이지 번호 UI는 만들 수 없다 → "더 보기" 또는 무한 스크롤 |
| 응답을 `res.data` 없이 그대로 사용 | 성공 봉투는 `{ data }`다. 벗기는 일은 `http.ts` 한 곳에서만 한다 |
| `err.fieldErrors` 같은 평평한 필드 에러 기대 | 실패 봉투는 `{ error: { code, message, details } }`이고 `details`는 422에만, 값은 **배열**이다 |
| `queryKey: ['tasks', filter]`를 화면에 직접 작성 | 무효화 쪽 키와 어긋나 목록이 갱신되지 않는다 → 항상 `taskKeys` 팩토리 |
| 생성 후 `invalidateQueries` 누락 | 저장은 성공했는데 목록이 그대로다. "새로고침하면 보여요"의 정체 |
| `invalidateQueries({ queryKey: taskKeys.list(filter) })` | 현재 필터의 목록만 갱신된다. 다른 탭으로 옮기면 낡은 목록 → `taskKeys.lists()`로 접두사 무효화 |
| `initialPageParam` 누락 | v5의 `useInfiniteQuery`에서 필수다. 빠지면 첫 요청이 시작되지 않는다 |
| 생성 성공 후 `setTasks([...tasks, created])` | 서버 캐시를 로컬 상태로 복제한 것. Query가 이미 하는 일이다 |
| 성공 콜백을 훅과 화면 양쪽에 중복 작성 | 무효화는 훅의 `onSuccess`(항상 필요), 화면 닫기는 호출부의 `onSuccess`(그 화면만) — 책임을 나눈다 |
| 필터를 `useState`로 보관 | 새로고침·링크 공유·뒤로가기에서 사라진다 → `useSearchParams` |
| 로딩 분기 없이 `data?.pages ?? []` | 로딩과 "결과 없음"이 같은 화면이 된다 → 이른 반환으로 좁힌다 |
| `placeholderData` 없이 필터 전환 | 매 전환마다 목록이 사라졌다 다시 그려져 깜빡인다 |
| 403/404 응답을 무시하고 버튼만 숨김 | 숨김은 UX일 뿐 우회 가능하다. 남의 리소스는 404로 오므로 그 문구까지 준비한다 |
