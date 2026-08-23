<!-- epcc-pack: frontend/vue v3.12.0 -->
# Component Patterns

Vue 3 `<script setup lang="ts">` SFC를 어디에 두고, 언제 공통으로 올리고, 무엇을
소유하게 할지에 대한 규칙.

## 1. 세 가지 층위

| 층위 | 위치 | 아는 것 | 모르는 것 |
| --- | --- | --- | --- |
| Page | `features/<f>/pages/` | 라우트 파라미터, 쿼리 컴포저블, 레이아웃 조립 | 세부 마크업 |
| Feature component | `features/<f>/components/` | 이 기능의 도메인 타입 | 다른 기능, 라우팅 |
| Common component | `components/common/`, `components/layout/` | 시각적 계약(props·slots)만 | 도메인, 페칭, 라우팅 |

규칙: **의존은 아래로만 흐른다.** 공통 컴포넌트는 `features/`를 import하지 않는다.
이 방향이 깨지면 공통 컴포넌트가 특정 기능에 묶여 재사용이 끝난다.

## 2. 새로 만들기 전에 검색한다 (탐색 의무)

중복 컴포넌트의 대부분은 "추출하지 않아서"가 아니라 **"있는 줄 몰라서"** 생긴다.
공통 후보를 만들기 전에 최소 두 가지 축으로 검색한다.

```bash
# ① 이름 축 — 하려는 역할의 흔한 이름들
rg -il "pageshell|emptystate|datatable|modal|drawer|badge" src/components src/features --glob '*.vue'

# ② 마크업 축 — 이미 쓰고 있는 클래스 조합
rg -l "rounded-lg border .* bg-white" src/components --glob '*.vue'

# ③ 공통 디렉토리 목록 훑기 (30초면 끝난다)
ls src/components/common src/components/layout
```

검색해서 **비슷하지만 부족한** 것을 찾았다면, 새로 만들지 말고 prop이나 슬롯을 하나 늘린다.
새 파일은 기존 것을 확장할 수 없다고 판단했을 때에만 만들고, 그 판단 근거를 PR에 적는다.

## 3. 추출 시점

- 같은 마크업 덩어리가 **세 번째** 등장하면 추출한다 (두 번은 우연, 세 번은 패턴)
- 두 개 **이상의 기능**이 같은 UI를 쓰면 두 번째에 바로 `components/common/`으로 올린다
- 한 기능 안에서만 반복되면 `features/<f>/components/`에 둔다 — 성급한 공통화는
  props가 폭발한 "만능 컴포넌트"를 만든다
- 추출 대상은 **마크업과 스타일**이다. 데이터 페칭·라우팅은 함께 올리지 않는다

## 4. SFC 파일 규약

- 파일 하나에 컴포넌트 하나, 파일명은 `PascalCase.vue`. 템플릿에서 쓰는 이름과 같다
- 블록 순서는 `<script setup lang="ts">` → `<template>` 고정. `<style>` 블록은 두지 않는다
- **`<script setup>`은 값을 export할 수 없다** (`export const FOO = 1` → 컴파일 에러
  `cannot contain ES module exports`). 타입 전용 export(`export type`)는 컴파일되지만,
  여러 파일이 공유하는 타입·상수는 찾기 쉽게 같은 디렉토리의 `.ts` 파일이 소유한다
  (§8의 `Column`이 그 예다) — 규칙의 근거는 컴파일 제약이 아니라 소재의 일관성이다
- 컴포넌트는 import만 하면 템플릿에 등록된다 — `components: {}` 옵션은 없다

```vue
<script setup lang="ts">
// src/components/layout/PageShell.vue — 레이아웃과 여백만 소유한다
defineProps<{ title: string }>();
</script>

<template>
  <div class="mx-auto w-full max-w-5xl px-6 py-8">
    <header class="mb-6 flex items-center justify-between">
      <h1 class="text-xl font-semibold text-slate-900">{{ title }}</h1>
      <slot name="actions" />
    </header>
    <slot />
  </div>
</template>
```

❌ 공통 셸이 도메인을 알면 다음 기능에서 재사용할 수 없다. 아래는 하지 않는다:

```vue
<script setup lang="ts">
const props = defineProps<{ taskId: string }>();
const { data } = useTaskQuery(props.taskId);   // 페칭
const router = useRouter();                     // 라우팅
</script>
```

## 5. props 선언 — 타입으로만

```vue
<script setup lang="ts">
// src/components/common/Button.vue
import { computed } from 'vue';
import { buttonClass, type ButtonSize, type ButtonVariant } from './button-variants';

const props = withDefaults(
  defineProps<{ variant?: ButtonVariant; size?: ButtonSize; loading?: boolean }>(),
  { variant: 'primary', size: 'md', loading: false },
);
const classes = computed(() => buttonClass(props.variant, props.size));
</script>

<template>
  <button :class="classes" :disabled="loading">
    <span v-if="loading" class="mr-2 size-3 animate-spin rounded-full border-2 border-current border-t-transparent" />
    <slot />
  </button>
</template>
```

- 런타임 선언(`props: { size: { type: String } }`) 대신 **타입 선언**을 쓴다. 타입이 곧 계약이고
  `vue-tsc`가 사용처를 검사한다
- 기본값은 `withDefaults`로 준다. 기본값 없는 선택 prop은 `undefined`가 되므로 이후 계산이
  전부 그것을 다뤄야 한다. **단 boolean은 예외다** — Vue의 Boolean 캐스팅이 부재 prop을
  `false`로 만들어 준다. 그래도 명시하는 편이 읽는 사람에게 계약을 보여준다
- **props를 구조 분해하지 않는다.** `props.variant`로 읽어야 반응성이 유지된다
- 상태를 boolean 여러 개로 쪼개지 않고 union으로 모은다 (`status: 'idle' | 'loading' | 'error'`) —
  `isLoading && isError`처럼 불가능한 조합이 타입에서 사라진다

## 6. emits와 v-model

```vue
<script setup lang="ts">
// src/components/common/SearchInput.vue
const emit = defineEmits<{ submit: [value: string]; clear: [] }>();
const keyword = defineModel<string>({ default: '' });   // v-model — Vue 3.4+

function onSubmit() { emit('submit', keyword.value); }
</script>

<template>
  <form class="flex gap-2" @submit.prevent="onSubmit">
    <input v-model="keyword" class="h-10 flex-1 rounded-md border px-3 text-sm" />
    <button type="button" @click="keyword = ''; emit('clear')">지우기</button>
  </form>
</template>
```

- `defineEmits<{ name: [args] }>()`의 튜플 표기가 현재 형태다 — 인자 타입이 그대로 검사된다
- `defineModel()`이 반환하는 것은 **Ref**다. 스크립트에서는 `.value`, 템플릿에서는 그냥 쓴다
- 부모가 값을 소유해야 하면 `v-model`, 부모가 "일이 일어났다"만 알면 되면 `emit`

## 7. 슬롯

```vue
<script setup lang="ts">
// src/components/common/FormField.vue — 라벨·에러·설명의 배치와 접근성 연결을 소유한다
import { computed } from 'vue';

const props = defineProps<{ label: string; inputId: string; error?: string; hint?: string }>();
const hintId = computed(() => (props.hint ? `${props.inputId}-hint` : undefined));
const errorId = computed(() => (props.error ? `${props.inputId}-error` : undefined));
const describedBy = computed(() =>
  [hintId.value, errorId.value].filter(Boolean).join(' ') || undefined,
);
</script>

<template>
  <div class="space-y-1.5">
    <label :for="inputId" class="block text-sm font-medium text-slate-700">{{ label }}</label>
    <slot :described-by="describedBy" />
    <p v-if="hint && !error" :id="hintId" class="text-xs text-slate-500">{{ hint }}</p>
    <p v-if="error" :id="errorId" role="alert" class="text-xs text-danger-600">{{ error }}</p>
  </div>
</template>
```

```vue
<!-- 호출부 — 입력 종류가 늘어나도 FormField는 바뀌지 않는다 -->
<FormField label="제목" input-id="title" :error="fieldErrors.title?.[0]" hint="2자 이상">
  <template #default="{ describedBy }">
    <input id="title" :aria-describedby="describedBy" class="h-10 w-full rounded-md border px-3" />
  </template>
</FormField>
```

- 슬롯이 있는지 분기하려면 `v-if="$slots.actions"`를 쓴다 — 빈 래퍼 여백이 남지 않는다
- 슬롯 타입은 `defineSlots<{ actions?: (p: { task: Task }) => unknown }>()`로 선언한다
- 옵션이 늘어날 때 props를 계속 추가하는 대신 자리를 연다. `type="select" :options ...`처럼
  입력 종류마다 prop이 늘어나는 컴포넌트는 다음 요구가 오면 또 늘어난다

## 8. 제네릭 컴포넌트

```ts
// src/components/common/table-types.ts
// `<script setup>`은 export할 수 없으므로 공유 타입은 SFC 밖에 둔다
export type Column<T> = {
  key: string;
  header: string;
  value: (row: T) => string;   // 문자열 셀. 리치 셀은 `cell-<key>` 슬롯으로 덮는다
  class?: string;
};
```

```vue
<script setup lang="ts" generic="T extends { id: string }">
// src/components/common/DataTable.vue
import type { Column } from './table-types';

defineProps<{ rows: T[]; columns: Column<T>[] }>();
</script>

<template>
  <table class="w-full text-sm">
    <thead>
      <tr class="border-b border-surface-border text-left text-xs text-slate-500">
        <th v-for="c in columns" :key="c.key" class="py-2" :class="c.class">{{ c.header }}</th>
      </tr>
    </thead>
    <tbody>
      <tr v-for="row in rows" :key="row.id" class="border-b border-surface-border last:border-0">
        <td v-for="c in columns" :key="c.key" class="py-3" :class="c.class">
          <slot :name="'cell-' + c.key" :row="row">{{ c.value(row) }}</slot>
        </td>
      </tr>
    </tbody>
  </table>
</template>
```

`generic="T extends { id: string }"`가 key 규칙을 타입으로 강제한다 — 인덱스 key가 들어올
자리가 없다. `v-for`의 `:key`는 서버가 준 안정적인 식별자를 쓴다. 인덱스를 쓰면 정렬·삭제·
낙관적 삽입에서 입력 상태가 잘못된 행에 붙는다.

## 9. 디자인 토큰 소유권과 속성 폴스루

공통 컴포넌트가 자기 **높이·타이포·여백·모서리**를 단독으로 정의한다. 사용처는
`variant`/`size` props로만 고른다. Vue에서는 이 규칙이 React보다 더 강하게 성립한다:
호출부가 준 `class`는 루트 엘리먼트의 `class`에 **이어 붙기만 하고** `cn()`의
tailwind-merge를 거치지 않는다. `p-4`와 `p-8`이 함께 남아 승자를 CSS 파일 순서가 정한다.

- 폴스루로 넘겨도 되는 것: 충돌하지 않는 **위치성 조정**(`mt-4`, `w-full`, `col-span-2`)
- 넘기면 안 되는 것: 컴포넌트가 이미 소유한 토큰(`h-*`, `px-*`, `text-*`, `rounded-*`)
- 루트가 여럿이면 폴스루 대상이 정해지지 않아 속성이 조용히 사라진다 — 루트를 하나로 두거나
  `defineOptions({ inheritAttrs: false })` 후 `v-bind="$attrs"`를 직접 붙인다

## 10. 파생 상태는 `computed`로 계산한다

`ref` + `watch`로 props에서 값을 파생시키면 소스가 둘이 되고 한 틱 늦은 값이 렌더된다.

```vue
<script setup lang="ts">
import { computed } from 'vue';
const props = defineProps<{ tasks: Task[] }>();

// ✅ 파생값은 computed — 캐시되고 의존성을 자동 추적한다
const visible = computed(() => props.tasks.filter((t) => t.status !== 'done'));
</script>
```

❌ 아래는 하지 않는다. `watch`는 **외부 세계와의 동기화**(요청 취소, 타이머, 저장)에만 쓴다:

```vue
<script setup lang="ts">
const visible = ref<Task[]>([]);
watch(() => props.tasks, (t) => { visible.value = t.filter((x) => x.status !== 'done'); },
      { immediate: true });
</script>
```

## 오용 목록 ① — Options API·Vue 2 관용구 대조표

| 옛 습관 | Vue 3 `<script setup lang="ts">` 형태 |
| --- | --- |
| `export default defineComponent({ ... })` 래핑 | `<script setup lang="ts">` 자체가 타입 추론을 준다 |
| `data() { return { n: 0 } }` | `const n = ref(0)` |
| `computed: { double() { return this.n * 2 } }` | `const double = computed(() => n.value * 2)` |
| `props: { task: { type: Object as PropType<Task> } }` | `defineProps<{ task: Task }>()` |
| `this.$emit('select', id)` | `const emit = defineEmits<{ select: [id: string] }>()` → `emit('select', id)` |
| `mounted()` / `beforeDestroy()` | `onMounted(...)` / `onUnmounted(...)` |
| `this.$refs.input` | `const input = ref<HTMLInputElement \| null>(null)` + 템플릿 `ref="input"` |
| `.sync` 수식어 | `v-model:propName` (또는 `defineModel('propName')`) |
| `slot="x"` / `slot-scope="p"` | `<template #x="p">` |
| `filters: { … }` | 제거됐다 — `computed` 또는 메서드 |
| `$listeners` | `$attrs`에 병합됐다 |
| `Vue.component('AppButton', …)` 전역 등록 | import하면 자동 등록된다 |
| `functional: true` | 일반 SFC — 함수형 컴포넌트의 성능 이점이 사라졌다 |
| `mixins: [...]` | 컴포저블(`composables/useX.ts`) — 이름 충돌이 드러난다 |
| 여러 루트를 감싸는 `<div>` | 다중 루트가 허용된다 (대신 §9의 폴스루 주의) |

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `ref` vs `reactive` | 기본은 `ref`. `reactive`는 객체 전용이고 **재대입이 불가능**하며 구조 분해에서 즉시 깨진다. 큰 불변 데이터는 `shallowRef` |
| `computed` vs `watch` vs `watchEffect` | 값을 만들면 `computed`. 값 변화에 **부수효과**를 걸면 `watch`(무엇이 바뀌었는지 알아야 할 때). 의존성을 자동 수집해도 되는 부수효과는 `watchEffect` |
| `props.x` vs `const { x } = props` | 구조 분해는 값을 복사해 반응성을 끊는다. 꼭 떼어내야 하면 `toRef(props, 'x')` |
| `toRef` vs `toRefs` vs `unref` | 하나면 `toRef`, 객체 전체면 `toRefs`, "Ref일 수도 아닐 수도"는 `unref` |
| `v-if` vs `v-show` | `v-if`는 마운트/언마운트(컴포넌트 상태가 사라진다). 자주 토글되고 상태를 유지해야 하면 `v-show`(CSS만 바뀐다). 로딩 3상태는 **항상 `v-if`** — 죽은 트리가 남으면 안 된다 |
| `v-for`의 `:key`가 인덱스 vs `id` | 서버 목록은 항상 `id`. 인덱스는 절대 재정렬·삽입되지 않는 정적 배열에서만 |
| `v-if`와 `v-for`를 같은 요소에 | 금지다 — 우선순위가 헷갈린다. 바깥에 `<template v-for>`를 두고 안에서 `v-if` |
| `nextTick()` vs `watch(..., { flush: 'post' })` | 한 번 기다리면 `await nextTick()`. 매번 DOM 갱신 후에 돌아야 하는 감시자는 `flush: 'post'` |
| 슬롯 기본값 vs `v-if="$slots.x"` | 대체 콘텐츠가 있으면 `<slot>기본</slot>`. 래퍼 자체를 지워야 하면 `$slots` 검사 |
| 공통 컴포넌트에 컴포저블 주입 vs props 주입 | 공통 컴포넌트가 `useQuery`/`useRouter`를 부르는 순간 특정 기능 전용이 된다 |
| 컴포넌트 분리 vs 파일 분리 | 기준은 파일 수가 아니라 **재사용 범위**다. 밖에서 쓰지 않는 조각은 같은 파일의 템플릿 안에 둔다 |
