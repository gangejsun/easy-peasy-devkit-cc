<!-- epcc-seam: vue+node-api v3.13.0 -->
# Complete Example — 목록 조회 + 생성 관통

작업 목록을 읽고 새 작업을 만드는 기능 하나를 처음부터 끝까지 조립한다. **새 심볼을
만들지 않는다** — 팩이 정의한 것과 `resources/data-fetching.md`·`resources/auth-and-session.md`가
정의한 것만 쓴다. 여기서 이름이 하나라도 새로 필요해졌다면 앞의 두 파일이 덜 채워진 것이다.

## 1. 이 예제가 관통하는 것

| 층 | 파일 | 소유 |
| --- | --- | --- |
| 도메인 타입 | `src/types/task.ts` | 이음매 (data-fetching §2) |
| 전송 | `src/api/http.ts` · `src/api/errors.ts` | 이음매 (data-fetching §2·§3) |
| 세션 | `src/auth/session.ts` · `src/auth/useAuth.ts` | 이음매 (auth-and-session §2·§4) |
| 요청·키 | `src/features/tasks/api/tasks.ts` | 이음매 (data-fetching §4) |
| 컴포저블 | `useTasksQuery.ts` · `useCreateTaskMutation.ts` | 이음매 (data-fetching §5·§6) |
| 응답 좁히기 | `src/features/tasks/api/tasks.parse.ts` | 팩 (types-and-testing §4) |
| 공통 UI | `ListSkeleton` · `EmptyState` · `ErrorState` · `DataTable` · `FormField` · `Button` · `PageShell` | 팩 |
| 화면 | `TaskListPage.vue` · `TaskCreateForm.vue` | 이 파일 |

## 2. 목록 화면 (`src/features/tasks/pages/TaskListPage.vue`)

3상태(로딩·빈·에러)와 커서 페이지네이션이 한 화면에서 만난다. 순서를 바꾸면
로딩 중에 "데이터 없음"이 번쩍이거나 재시도 중에 에러 화면이 남는다.

```vue
<script setup lang="ts">
// src/features/tasks/pages/TaskListPage.vue
import { computed } from 'vue';
import { useRoute } from 'vue-router';
import { useTasksQuery } from '@/features/tasks/api/useTasksQuery';
import type { Task } from '@/types/task';
import type { Column } from '@/components/common/table-types';
import PageShell from '@/components/layout/PageShell.vue';
import ListSkeleton from '@/components/common/ListSkeleton.vue';
import EmptyState from '@/components/common/EmptyState.vue';
import ErrorState from '@/components/common/ErrorState.vue';
import DataTable from '@/components/common/DataTable.vue';
import Button from '@/components/common/Button.vue';
import TaskCreateForm from '../components/TaskCreateForm.vue';

const route = useRoute();
// 필터는 URL이 소유한다 (팩 state-management.md §8). 그 값이 그대로 쿼리 키가 된다
const filter = computed(() => ({
  status: route.query.status === 'done' ? ('done' as const) : undefined,
  limit: 20,
}));

const { data, isPending, isError, error, isFetching,
        refetch, fetchNextPage, hasNextPage, isFetchingNextPage } = useTasksQuery(filter);

const tasks = computed<Task[]>(() => data.value ?? []);
const columns: Column<Task>[] = [
  { key: 'title', header: '제목', value: (t) => t.title },
  { key: 'status', header: '상태', value: (t) => (t.status === 'done' ? '완료' : '진행 중'), class: 'w-24' },
];
</script>

<template>
  <PageShell title="작업">
    <template #actions><TaskCreateForm /></template>

    <ListSkeleton v-if="isPending" :rows="5" />
    <ErrorState v-else-if="isError" :error="error" @retry="refetch" />
    <EmptyState v-else-if="tasks.length === 0" title="아직 작업이 없습니다"
                description="첫 작업을 만들어 보세요" />
    <template v-else>
      <div v-if="isFetching" class="h-0.5 animate-pulse bg-brand-500" role="status" />
      <DataTable :rows="tasks" :columns="columns" />
      <Button v-if="hasNextPage" variant="secondary" size="md" class="mt-4"
              :disabled="isFetchingNextPage" @click="fetchNextPage()">
        더 보기
      </Button>
    </template>
  </PageShell>
</template>
```

`data`는 페이지 봉투가 아니라 **평탄한 `Task[]`**다 — `useTasksQuery`의 `select`가
그렇게 만든다. `hasNextPage`가 false가 되는 근거는 계약 §3의 `nextCursor: null`이다.

## 3. 생성 폼 (`src/features/tasks/components/TaskCreateForm.vue`)

계약 §2의 `details`(`Record<string, string[]>`)를 필드 아래로 옮기는 자리다.

```vue
<script setup lang="ts">
// src/features/tasks/components/TaskCreateForm.vue
import { ref } from 'vue';
import { ApiError } from '@/api/errors';
import { useCreateTaskMutation } from '@/features/tasks/api/useCreateTaskMutation';
import { toUserMessage } from '@/lib/toUserMessage';
import FormField from '@/components/common/FormField.vue';
import Button from '@/components/common/Button.vue';

const title = ref('');
const fieldErrors = ref<Record<string, string[]>>({});
const formMessage = ref('');
const { mutate, isPending } = useCreateTaskMutation();

function onSubmit() {
  fieldErrors.value = {};
  formMessage.value = '';
  // mutate는 값을 반환하지 않고 던지지도 않는다 — 실패는 onError로만 온다
  mutate({ title: title.value }, {
    onError: (e: unknown) => {
      if (e instanceof ApiError && e.code === 'VALIDATION_FAILED' && e.details) {
        fieldErrors.value = e.details;      // 필드별 오류는 필드 아래로
      } else {
        formMessage.value = toUserMessage(e);  // 그 밖은 폼 전체 문구로
      }
    },
  });
  title.value = '';
}
</script>

<template>
  <form class="flex items-end gap-2" @submit.prevent="onSubmit">
    <FormField label="제목" input-id="new-task-title" :error="fieldErrors.title?.[0]">
      <template #default="{ describedBy }">
        <input id="new-task-title" v-model="title" :aria-describedby="describedBy"
               class="h-10 w-64 rounded-md border px-3" />
      </template>
    </FormField>
    <Button variant="primary" size="md" :disabled="isPending">추가</Button>
    <p v-if="formMessage" class="text-sm text-red-600" role="alert">{{ formMessage }}</p>
  </form>
</template>
```

성공 시 무효화는 `useCreateTaskMutation`이 한다. 화면은 `refetch`를 부르지 않는다 —
두 곳에서 재요청을 걸면 생성 1건에 목록 요청이 두 배로 늘어난다.

## 4. 상세 화면의 404 — 없거나 내 것이 아니다

계약 §5에서 소유권 실패는 403이 아니라 404다. 두 경우를 가르는 정보가 응답에 없으므로
**한 화면**으로 처리한다. `retryable="false"`로 재시도 버튼을 지운다 — 다시 눌러도 같다.

```ts
// src/features/tasks/pages/TaskDetailPage.vue — <script setup> 발췌
const missing = computed(() => (error.value as ApiError | null)?.code === 'NOT_FOUND');
```

❌ 아래는 잘못된 분기다. 403은 역할 부족일 때만 오므로 소유권 실패를 영원히 놓친다.

```ts
// ❌ 소유권 실패를 403으로 기다린다 — 이 조합에서는 오지 않는다
const forbidden = computed(() => (error.value as ApiError | null)?.code === 'FORBIDDEN');
```

## 5. 배선 (`src/api/queryClient.ts` · `src/main.ts`)

<!-- file: src/api/queryClient.ts -->
```ts
// src/api/queryClient.ts — 앱 전역 인스턴스. 로그아웃이 컴포넌트 밖에서 이것을 비운다
import { QueryClient } from '@tanstack/vue-query';

// 결과가 바뀔 수 없는 실패는 재시도하지 않는다. 401이 여기까지 올라왔다면
// http.ts의 재발급이 실패했다는 뜻이라 다시 시도할 이유가 없다
const TERMINAL = ['UNAUTHENTICATED', 'FORBIDDEN', 'NOT_FOUND', 'VALIDATION_FAILED', 'BAD_SHAPE'];

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30_000,
      retry: (count, error) => count < 2 && !TERMINAL.includes((error as { code?: string })?.code ?? ''),
    },
  },
});
```

<!-- verified: 실행 계측 — 404 NOT_FOUND는 요청 1회로 끝났고 500 INTERNAL은 3회(최초 + 재시도 2회) 시도했다 -->

<!-- file: src/main.ts -->
```ts
// src/main.ts
import { createApp } from 'vue';
import { createPinia } from 'pinia';
import { VueQueryPlugin } from '@tanstack/vue-query';
import { router } from '@/router';                 // 팩 소유 — 전역 가드가 이미 붙어 있다
import { queryClient } from '@/api/queryClient';
import App from './App.vue';
import './index.css';

createApp(App)
  .use(createPinia())                              // 가드가 스토어를 쓰므로 router보다 먼저
  .use(router)
  .use(VueQueryPlugin, { queryClient })            // 새 QueryClient를 만들지 않는다
  .mount('#app');
```

`VueQueryPlugin`에 `queryClient`를 **넘긴다.** 넘기지 않으면 플러그인이 자기 인스턴스를
만들고, 로그아웃의 `queryClient.clear()`는 아무도 구독하지 않는 쪽을 비운다 — 화면에는
이전 사용자의 목록이 그대로 남는다.

## 6. 테스트 — 긍정과 부정을 같은 `it`에 (`TaskListPage.test.ts`)

팩의 msw 기본 핸들러는 봉투가 없는 본문을 돌려준다. 이 조합의 계약은 `{ data, nextCursor }`
이므로 **테스트마다 `server.use()`로 계약 형태를 덮는다.**

<!-- file: src/features/tasks/pages/TaskListPage.test.ts -->
```ts
// src/features/tasks/pages/TaskListPage.test.ts
import { flushPromises } from '@vue/test-utils';
import { http as mock, HttpResponse } from 'msw';
import { server } from '@/test/setup';
import { mountWithProviders } from '@/test/mountWithProviders';
import TaskListPage from './TaskListPage.vue';

const row = { id: 't1', title: '내 작업', createdAt: '2026-01-01T00:00:00.000Z', status: 'open' };

it('계약 봉투는 그리고, 봉투가 깨지면 에러 상태로 떨어진다', async () => {
  server.use(mock.get('*/api/tasks', () => HttpResponse.json({ data: [row], nextCursor: null })));
  const ok = mountWithProviders(TaskListPage);
  await ok.router.isReady();
  await flushPromises();
  expect(ok.wrapper.text()).toContain('내 작업');              // 긍정: 성공 경로가 실제로 그려진다
  expect(ok.wrapper.find('[role="alert"]').exists()).toBe(false);

  // data가 배열이 아니다 → parseTaskList가 ApiError('BAD_SHAPE')를 던진다
  server.use(mock.get('*/api/tasks', () => HttpResponse.json({ data: { oops: true } })));
  const bad = mountWithProviders(TaskListPage);
  await bad.router.isReady();
  await flushPromises();
  expect(bad.wrapper.get('[role="alert"]').text()).toContain('문제가 발생했습니다');  // 부정
});
```

긍정 단언이 같은 `it` 안에 있어야 부정 단언이 "차단"인지 "전부 고장"인지 갈린다.
에러 단언만 있으면 `useTasksQuery`를 통째로 `throw`로 바꿔도 초록이다.

## 오용 목록 ① — 조립 관용구 대조표

| 구 습관 | 현재 형태 (이 조합) |
| --- | --- |
| 화면에서 `await http.get(...)` 후 `ref`에 담기 | 쿼리 컴포저블. 담으면 캐시·무효화·GC를 직접 만들게 된다 |
| 생성 후 `refetch()` 호출 | 뮤테이션의 `onSuccess`에서 `invalidateQueries` |
| `page`·`offset` 파라미터로 페이지 넘김 | `limit`·`cursor` (계약 §3). 오프셋은 목록이 바뀌면 행이 중복·누락된다 |
| `mutate(...).then(...)` / `await mutate(...)` | `mutate(input, { onError })`. 반환값이 없다 |
| 실패를 `try/catch`로 감싼 `mutateAsync` | `onError` 콜백. 거부한 Promise를 흘리지 않는다 |
| `catch (e) { alert(e.message) }` | `toUserMessage(e)` — 서버 원문은 내부 구조를 노출한다 |
| msw 핸들러가 배열을 그대로 반환 | `{ data: [...], nextCursor: null }` 봉투로 덮는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `PageShell` vs `DefaultLayout` | 화면 제목·여백은 앞(화면이 쓴다), 앱 셸·`RouterView`는 뒤(라우트가 쓴다) |
| `EmptyState` vs `ErrorState` | 서버가 "0건"이라 답하면 앞, 답하지 못했으면 뒤. `data`가 `undefined`인 것은 빈 상태가 아니다 |
| `ErrorState`의 `retryable` | 기본은 재시도 가능. `NOT_FOUND`·`FORBIDDEN`·`VALIDATION_FAILED`에는 `false` |
| `fetchNextPage` vs `refetch` | 다음 커서를 더 읽는 것이 앞, 가진 페이지를 다시 읽는 것이 뒤 |
| `mountWithProviders` vs `mount` | 라우터·pinia·쿼리를 쓰는 화면은 항상 앞. 뒤로 마운트하면 컴포저블이 주입을 찾지 못한다 |
| `router.isReady()` vs `flushPromises()` | 라우트 첫 해석이 앞, 쿼리 마이크로태스크가 뒤. **둘 다** 필요하다 |
| 새 `QueryClient` vs 주입된 것 | 테스트는 매번 새로, 앱은 `main.ts`의 하나. 앱에서 새로 만들면 로그아웃이 비우는 대상이 어긋난다 |
