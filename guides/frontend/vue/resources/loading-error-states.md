<!-- epcc-pack: frontend/vue v3.12.0 -->
# Loading · Empty · Error States

데이터를 그리는 모든 화면은 최소 세 갈래를 갖는다. 성공 경로만 구현한 화면은 느린
네트워크, 만료된 세션, 빈 계정에서 흰 화면이 된다.

## 1. 세 상태 + 배경 갱신

```vue
<script setup lang="ts">
// src/features/tasks/pages/TaskListPage.vue
import { computed } from 'vue';
import { useTasksQuery } from '@/features/tasks/api/useTasksQuery';   // 이음매가 제공한다
import ListSkeleton from '@/components/common/ListSkeleton.vue';
import EmptyState from '@/components/common/EmptyState.vue';
import ErrorState from '@/components/common/ErrorState.vue';
import TaskTable from '../components/TaskTable.vue';

const { data, isPending, isError, error, isFetching, refetch } = useTasksQuery();
const tasks = computed(() => data.value ?? []);
</script>

<template>
  <ListSkeleton v-if="isPending" :rows="5" />
  <ErrorState v-else-if="isError" :error="error" @retry="refetch" />
  <EmptyState v-else-if="tasks.length === 0" title="아직 작업이 없습니다"
              description="첫 작업을 만들어 보세요" />
  <template v-else>
    <div v-if="isFetching" class="h-0.5 animate-pulse bg-brand-500" role="status" />
    <TaskTable :rows="tasks" />
  </template>
</template>
```

순서가 중요하다. `isError`를 먼저 보면 재시도 중에도 에러 화면이 남고, 빈 상태를 먼저
보면 로딩 중에 "데이터 없음"이 번쩍인다. 세 갈래는 반드시 `v-if` 계열이다 — `v-show`로
쓰면 세 트리가 동시에 마운트되어 로딩 중에도 목록이 데이터를 읽으려 든다.

Vue Query의 반환값은 **Ref들을 담은 평범한 객체**다. 그래서 구조 분해해도 반응성이
살아 있다 (Pinia 스토어와 다르다 — `state-management.md` §4). 대신 스크립트에서 값을
읽을 때는 `.value`가 필요하고, 템플릿에서는 자동으로 언랩된다.

`enabled: false`로 비활성화한 쿼리는 예외다 — 요청이 뜬 적이 없으므로 `isPending`이
영구히 true다. 이 규칙을 그대로 적용하면 스켈레톤이 사라지지 않는다 (§오용 목록).

## 2. 로딩 표현 선택

| 상황 | 표현 |
| --- | --- |
| 첫 진입, 레이아웃을 아는 목록/카드 | 스켈레톤 (레이아웃 시프트가 없다) |
| 첫 진입, 크기를 모르는 영역 | 중앙 스피너 + 최소 높이 확보 |
| 데이터가 이미 있는 재요청 | 상단 얇은 진행바 또는 살짝 흐리게 — 화면을 치우지 않는다 |
| 버튼 클릭 후 뮤테이션 | 버튼 안 스피너 + `disabled` (더블 서브밋 차단) |
| 200ms 안에 끝날 것 | 아무것도 표시하지 않는다 (깜빡임이 더 나쁘다) |

```vue
<script setup lang="ts">
// src/components/common/ListSkeleton.vue — 실제 레이아웃과 같은 박스 크기를 갖는다
withDefaults(defineProps<{ rows?: number }>(), { rows: 3 });
</script>

<template>
  <div class="space-y-3" role="status" aria-label="불러오는 중">
    <div v-for="i in rows" :key="i" class="h-16 animate-pulse rounded-card bg-surface-muted" />
  </div>
</template>
```

## 3. 빈 상태와 에러 상태는 공통 컴포넌트 하나씩이다

두 컴포넌트는 `src/components/common/`에 **한 번만** 정의하고 모든 화면이 같은 props로
부른다. 화면마다 다른 모양으로 부르면 시그니처가 갈라져 타입이 먼저 깨진다.

```vue
<script setup lang="ts">
// src/components/common/EmptyState.vue
withDefaults(defineProps<{ title?: string; description?: string }>(),
             { title: '표시할 항목이 없습니다' });
</script>

<template>
  <div class="rounded-card border border-dashed border-surface-border p-10 text-center">
    <p class="text-sm font-medium text-slate-900">{{ title }}</p>
    <p v-if="description" class="mt-1 text-sm text-slate-500">{{ description }}</p>
    <div v-if="$slots.action" class="mt-4 flex justify-center"><slot name="action" /></div>
  </div>
</template>
```

```vue
<script setup lang="ts">
// src/components/common/ErrorState.vue
import { computed } from 'vue';
import { toUserMessage } from '@/lib/toUserMessage';
import Button from './Button.vue';

const props = defineProps<{
  title?: string;
  message?: string;
  error?: unknown;      // 넘기면 문구를 여기서 뽑는다
  retryable?: boolean;  // false면 재시도 버튼을 그리지 않는다 (권한 없음·없는 리소스가 그렇다)
}>();
defineEmits<{ retry: [] }>();

const text = computed(() => props.message ?? toUserMessage(props.error));
</script>

<template>
  <div role="alert" class="rounded-card border border-surface-border p-10 text-center">
    <p class="text-sm font-medium text-slate-900">{{ title ?? '문제가 발생했습니다' }}</p>
    <p class="mt-1 text-sm text-slate-500">{{ text }}</p>
    <Button v-if="retryable !== false" variant="secondary" class="mt-4" @click="$emit('retry')">
      다시 시도
    </Button>
  </div>
</template>
```

빈 상태는 두 종류이고, 문구가 달라야 한다.

- **아직 없음**: "첫 작업을 만들어 보세요" + 생성 버튼(`#action` 슬롯)
- **필터 결과 없음**: "조건에 맞는 작업이 없습니다" + 필터 초기화 버튼

## 4. 에러 → 사용자 문구

에러 **코드표는 이 팩이 정의하지 않는다.** 코드 목록과 상태 코드 매핑은 와이어 계약의
함수이므로 이음매가 준다. 이 팩이 소유하는 것은 두 가지뿐이다: 클라이언트가 스스로
만드는 전송 계층 코드와, 무엇이 와도 화면이 무너지지 않게 하는 **폴백**.

```ts
// src/lib/toUserMessage.ts
import { ApiError } from '@/api/errors';   // 이음매가 제공한다

export function toUserMessage(error: unknown): string {
  if (error instanceof ApiError) {
    switch (error.code) {
      // 서버까지 가지 못한 실패 — 이 두 코드는 HTTP 클라이언트가 만든다
      case 'NETWORK_ERROR':
      case 'TIMEOUT':
        return '연결에 실패했습니다. 네트워크를 확인해 주세요.';
      default:
        // 이음매의 코드표에 있는 코드별 문구를 여기에 덧붙인다.
        // 서버 원문 메시지를 그대로 노출하지 않는다 — 내부 구조가 새어 나간다
        return '요청을 처리하지 못했습니다. 잠시 후 다시 시도해 주세요.';
    }
  }
  return '문제가 발생했습니다. 잠시 후 다시 시도해 주세요.';
}
```

규칙 셋은 코드표와 무관하게 성립한다.

- **권한 없음·없는 리소스는 재시도 대상이 아니다.** 버튼을 주면 사용자가 계속 눌러
  서버 로그만 더럽힌다 — `:retryable="false"`로 버튼을 지운다
- **요율 제한도 자동 재시도하지 않는다.** 백오프 없이 다시 던지면 제한을 더 세게 때린다
- **인증 실패는 화면이 아니라 HTTP 계층 한 곳이 처리한다.** 개별 화면에 갱신·로그아웃
  분기를 두면 같은 로직이 화면 수만큼 생긴다

## 5. `<Suspense>`와 `async setup`은 쓰지 않는다

Vue 3의 `<Suspense>`는 아직 실험적 기능으로 표시되어 있고, `<script setup>`에 top-level
`await`를 쓰면 그 컴포넌트는 **반드시** 상위 `<Suspense>` 안에 있어야 한다. 그 결과:

- 로딩 상태의 소유자가 컴포넌트 밖으로 나가 3상태 규칙(§1)과 자리가 어긋난다
- `await` 이후의 코드에서는 현재 인스턴스 컨텍스트가 사라져 `onMounted` 등록이 실패한다
- 실패 경로가 `errorCaptured`로만 오므로 "재시도" UI를 그 자리에서 만들 수 없다

데이터 로딩은 쿼리의 `isPending`으로 화면 안에서 처리한다. `<Suspense>`는 이 스택에서
쓰지 않는다.

## 6. 에러 경계 — `onErrorCaptured`

렌더 중 던져진 예외를 잡는 그물이다. 세 층위로 둔다.

```vue
<script setup lang="ts">
// src/components/common/ErrorBoundary.vue
import { ref, onErrorCaptured } from 'vue';
import ErrorState from './ErrorState.vue';

const caught = ref<unknown>(null);

onErrorCaptured((err) => {
  caught.value = err;
  return false;      // 여기서 끝낸다 — 상위로 전파하지 않는다
});

function retry() { caught.value = null; }
</script>

<template>
  <ErrorState v-if="caught" :error="caught" @retry="retry" />
  <!-- v-if/v-else 분기 전환이 이미 언마운트 후 재마운트를 강제한다 — 인위적 key는 필요 없다 -->
  <slot v-else />
</template>
```

- ① 앱 최상단: `app.config.errorHandler`로 무엇을 놓쳐도 흰 화면은 막는다
- ② 레이아웃: `<RouterView>`를 `<ErrorBoundary>`로 감싼다
- ③ 위젯: 대시보드 카드 하나가 죽어도 나머지는 산다

`onErrorCaptured`가 **잡는 것**: 자손 컴포넌트의 렌더·라이프사이클 훅·watcher·템플릿
이벤트 핸들러에서 던져진 예외. **잡지 못하는 것**: 자기 자신의 `setup` 예외,
`setTimeout` 콜백, `await` 없이 흘려보낸 Promise 거부, 뮤테이션의 `mutate()` 실패.
이들은 각각의 자리에서 잡는다.

## 7. 폼 검증 에러

필드별 메시지의 형태(`details`)는 이음매의 계약이 정한다. 이 팩은 그것을 **필드 아래에
그리는 자리**만 정한다 — 검증 실패를 토스트로 띄우면 어느 칸이 틀렸는지 알 수 없다.

```vue
<script setup lang="ts">
import { ref } from 'vue';
import { ApiError } from '@/api/errors';
import { useCreateTaskMutation } from '@/features/tasks/api/useCreateTaskMutation';
import { toUserMessage } from '@/lib/toUserMessage';
import FormField from '@/components/common/FormField.vue';

const title = ref('');
const fieldErrors = ref<Record<string, string[]>>({});
const banner = ref<string | null>(null);
const { mutate, isPending } = useCreateTaskMutation();

function submit() {
  fieldErrors.value = {};
  banner.value = null;
  mutate({ title: title.value }, {
    onError: (e: unknown) => {
      // details가 있으면 필드 아래로, 없으면 폼 상단 배너로 — 문구는 한 곳에서 만든다
      if (e instanceof ApiError && e.details) fieldErrors.value = e.details;
      else banner.value = toUserMessage(e);
    },
  });
}
</script>

<template>
  <form class="space-y-4" @submit.prevent="submit">
    <p v-if="banner" role="alert" class="text-sm text-danger-600">{{ banner }}</p>
    <FormField label="제목" input-id="title" :error="fieldErrors.title?.[0]" hint="2자 이상">
      <input id="title" v-model="title" class="h-10 w-full rounded-md border px-3 text-sm" />
    </FormField>
    <button type="submit" :disabled="isPending" class="h-10 rounded-md bg-brand-600 px-4 text-white">
      저장
    </button>
  </form>
</template>
```

클라이언트 검증은 **UX 선행 안내**이고 최종 판정은 서버다. 클라이언트에만 규칙을 두면
API를 직접 호출하는 경로에서 우회되고, 서버에만 두면 왕복이 잦아진다 — 둘 다 둔다.

## 오용 목록 — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `isPending` vs `isFetching` | `isPending`은 "보여줄 데이터가 아직 없다" → 스켈레톤으로 대체. `isFetching`은 "요청이 떠 있다" → 기존 화면 유지 + 얇은 인디케이터 |
| `isPending` vs `isLoading` (v5) | v5의 `isLoading`은 `isPending && isFetching`이다. 첫 로딩 분기는 `isPending` |
| `enabled: false` 쿼리의 `isPending` | 비활성 쿼리는 `isPending`이 **영구 true**라 스켈레톤이 사라지지 않는다 → `isLoading`으로 분기하거나 파라미터 없는 상태를 별도 안내 화면으로 그린다 |
| 쿼리 반환값 구조 분해 vs 스토어 구조 분해 | 쿼리 반환값은 Ref들의 객체라 안전. Pinia 스토어는 프록시라 `storeToRefs`가 필요 |
| 스크립트의 `.value` vs 템플릿의 자동 언랩 | 템플릿에서 `.value`를 붙이면 `undefined`가 되고, 스크립트에서 빼면 Ref 객체 자체가 truthy라 **분기가 항상 참**이 된다 |
| `v-if` 3분기 vs `v-show` | 3상태는 항상 `v-if`. `v-show`는 죽은 트리를 남겨 로딩 중에도 자식이 데이터를 읽는다 |
| `<Suspense>` vs `isPending` | 이 스택에서는 `isPending`. §5 참고 |
| `onErrorCaptured` vs `isError` | 예상 가능한 실패(권한 없음, 없는 리소스)는 `isError` 분기. 예상 못 한 렌더 예외만 경계 |
| `onErrorCaptured` 반환값 | `false`를 반환해야 전파가 멈춘다. 아무것도 반환하지 않으면 상위 경계와 전역 핸들러가 같은 에러를 또 잡는다 |
| `throwOnError` vs 기본값 | 기본(false)이 표준이다. 여러 쿼리를 한 화면에서 묶어 한 번에 실패 처리할 때만 켠다 |
| 에러 배너 vs 인라인 에러 vs 필드 에러 | 화면 전체가 못 뜨면 인라인 에러 화면. 방금 누른 동작의 실패는 폼 상단 배너. 필드 검증은 필드 아래 |
| `role="status"` vs `role="alert"` | 로딩 알림은 `status`(공손). 실패 알림은 `alert`(즉시 읽힘) |
| `refetch()` vs `invalidateQueries()` | 이 쿼리 하나를 다시 부르면 `refetch`. 변경 후 관련 쿼리를 통째로 낡게 만들려면 `invalidateQueries` |
