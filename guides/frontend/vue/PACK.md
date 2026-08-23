<!-- epcc-pack: frontend/vue v3.12.0 verified 2026-08-23 vue@3 vite@5 typescript@5 vue-router@4 pinia@2 tailwindcss@3.4 @tanstack/vue-query@5 vitest@2 @vue/test-utils@2 msw@2 clsx@2 tailwind-merge@2 -->

# vue 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가
있는 조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

각 조각은 `<!-- pack-slot: 이름 -->` ~ `<!-- /pack-slot -->` 사이에 있고, 축 안에서
닫혀 있어 백엔드 축이 무엇이든 그대로 성립한다. 조합의 함수인 것은 여기 없다 —
파일 끝의 표가 이음매의 몫을 명시한다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── main.ts                  # createApp + 플러그인 등록 (pinia · router · VueQueryPlugin)
├── App.vue                  # <RouterView /> 하나만 — 화면 셸은 레이아웃 라우트가 갖는다
├── config.ts                # import.meta.env를 읽는 **유일한** 파일 (타입 붙여 내보낸다)
├── env.d.ts                 # ImportMetaEnv 선언 (`*.vue` 셰이딩은 넣지 않는다)
├── router/
│   ├── routes.ts            # 라우트 레코드 트리 (단일 소스) + RouteMeta 타입 확장
│   └── index.ts             # createRouter + 전역 가드 + onError
├── layouts/
│   └── DefaultLayout.vue    # 전역 셸: 헤더 · 네비 · <RouterView />
├── api/                     # HTTP 클라이언트 — **이음매가 소유한다** (팩은 소비만 한다)
├── features/
│   └── tasks/
│       ├── api/             # 엔드포인트 함수 + 쿼리 키 + 쿼리/뮤테이션 컴포저블
│       ├── components/      # 이 기능에서만 쓰는 SFC
│       └── pages/           # 라우트가 가리키는 화면
├── components/
│   ├── common/              # 2개 이상 기능이 공유하는 UI ← 새로 만들기 전 여기부터 검색
│   └── layout/              # PageShell · ListSkeleton
├── stores/                  # Pinia 스토어 (서버 데이터 반입 금지)
├── composables/             # use* 재사용 로직 (SFC 밖으로 뺀 반응성)
├── lib/                     # cn() · safeReturnTo() · 순수 유틸
└── types/                   # 여러 기능이 공유하는 타입
```
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
### 1. 서버 데이터는 Vue Query가 소유한다 — Pinia에 복제하지 않는다

서버 응답을 Pinia에 옮겨 담으면 캐시가 둘이 되고, 무효화·재요청·가비지 컬렉션을 직접
구현하게 된다. Pinia는 서버가 모르는 상태(사이드바 접힘, 목록 밀도)만 갖는다.

```ts
// ✅ 서버 상태는 쿼리, 클라이언트 상태는 스토어
const { data: tasks, isPending } = useTasksQuery(filter);
const { isSidebarOpen } = storeToRefs(useUiStore());

// ❌ 서버 응답을 스토어 state로 옮겨 담는다 — 캐시 이중화
state: () => ({ tasks: [] as Task[] }),
```

### 2. HTTP는 기능의 `api/` 계층에서만 — 컴포넌트가 직접 호출하지 않는다

SFC가 직접 네트워크를 부르면 인증 헤더·에러 정규화·베이스 URL이 화면마다 갈라진다.
컴포넌트는 컴포저블만 부르고, 요청 함수는 `features/<f>/api/`에 모은다.

```ts
// ✅ 요청 함수 → 쿼리 컴포저블 → 컴포넌트
const { data, isPending } = useTasksQuery(filter);

// ❌ 컴포넌트 안의 원시 요청 — 토큰도 에러 형식도 여기서 다시 발명된다
const res = await window.fetch('/tasks');
```

### 3. 반복 UI는 공통 컴포넌트로 추출하되, 만들기 전에 먼저 검색한다

중복의 다수는 추출 실패가 아니라 **탐색 실패**에서 생긴다. 새 공통 컴포넌트를 만들기 전에
`src/components/common/`과 `src/components/layout/`을 반드시 검색한다.

```bash
rg -l "PageShell|EmptyState|DataTable" src/components --glob '*.vue'
rg -l "rounded-lg border bg-white p-6" src/components --glob '*.vue'
```

```vue
<!-- ✅ 토큰(높이·타이포·여백)은 공통 컴포넌트 한 곳이 소유하고, 사용처는 props로만 고른다 -->
<Button size="sm" variant="danger">삭제</Button>

<!-- ❌ 사용처가 class로 토큰을 덮어쓴다 — size prop이 무의미해진다 -->
<Button class="h-11 px-6 text-base font-bold">삭제</Button>
```

### 5. 반응성은 참조로 흐른다 — 구조 분해가 그것을 끊는다

`ref`·`reactive`·Pinia 스토어는 **프록시**다. 값을 꺼내 변수에 담는 순간 그 변수는
그 시점의 스냅샷이고 다시는 갱신되지 않는다. 실패가 예외가 아니라 "화면이 안 바뀜"으로
나타나기 때문에 이 축에서 가장 늦게 발견되는 결함이다.

```ts
// ✅ 참조를 유지한다 — 스토어는 storeToRefs, props는 props.x로 접근
const { density } = storeToRefs(useUiStore());
const label = computed(() => props.task.title);

// ❌ 프록시에서 값을 뜯어낸다 — 화면이 첫 값에 얼어붙는다
const { density } = useUiStore();
const { task } = reactive({ task: initialTask });
```

### 6. 브라우저 번들에 비밀은 없다

`VITE_*` 변수는 빌드 시점에 문자열로 인라인되어 번들에 그대로 남는다. 서명 키·관리자
자격증명은 전부 서버가 보관하고, 프론트는 그 서버의 엔드포인트를 부른다.

```ts
// ✅ 공개해도 되는 값만 노출하고, 읽는 곳은 src/config.ts 하나다
import { config } from '@/config';
const baseUrl = config.apiBaseUrl;
```

### 7. 모든 데이터 화면은 로딩·빈·에러 3상태를 갖는다

성공 경로만 구현한 화면은 느린 네트워크와 만료된 세션에서 빈 화면이 된다. 3상태는
선택이 아니라 화면의 최소 계약이다.

```vue
<!-- ✅ 세 갈래를 모두 그린다. 순서를 바꾸면 로딩 중에 "데이터 없음"이 번쩍인다 -->
<ListSkeleton v-if="isPending" :rows="5" />
<ErrorState v-else-if="isError" :error="error" @retry="refetch" />
<EmptyState v-else-if="tasks.length === 0" title="아직 작업이 없습니다" />
<DataTable v-else :rows="tasks" :columns="columns" />
```
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
```ts
// Vue 3 — 컴파일러 매크로(defineProps·defineEmits·defineSlots·defineModel·
// withDefaults·defineOptions)는 **import하지 않는다**. `<script setup>`이 컴파일 시점에 처리한다
import { ref, shallowRef, reactive, computed, watch, watchEffect, nextTick,
         onMounted, onUnmounted, onErrorCaptured, toRef, toRefs,
         type Ref, type Component } from 'vue';

// 라우팅 (Vue Router 4)
import { RouterLink, RouterView, useRoute, useRouter, createRouter,
         createWebHistory, createMemoryHistory, type RouteRecordRaw } from 'vue-router';

// 서버 상태 (TanStack Query v5 — Vue 어댑터. 'react-query'가 아니다)
import { useQuery, useMutation, useQueryClient,
         VueQueryPlugin, QueryClient } from '@tanstack/vue-query';

// 클라이언트 전역 상태 (Pinia 2)
import { defineStore, storeToRefs, createPinia, setActivePinia } from 'pinia';

// 프로젝트 내부 (이 팩이 소유하는 것만 — HTTP 클라이언트는 이음매가 덧붙인다)
import { config } from '@/config';
import { cn } from '@/lib/cn';
```
<!-- /pack-slot -->

<!-- pack-slot: component-template -->
## Component Template

```vue
<script setup lang="ts">
// src/features/tasks/components/TaskCard.vue
// 기능 컴포넌트이므로 도메인 타입을 안다. components/common/은 반대로 features/를 import하지 않는다
import { computed } from 'vue';
import { cn } from '@/lib/cn';
import type { Task } from '@/types/task';

const props = withDefaults(
  defineProps<{ task: Task; dense?: boolean }>(),
  { dense: false },
);
defineEmits<{ select: [id: string] }>();
defineSlots<{ actions?: (props: { task: Task }) => unknown }>();

// props는 반응성 객체다 — 구조 분해하지 않고 props.x로 읽는다
const rootClass = computed(() =>
  cn('rounded-lg border border-slate-200 bg-white', props.dense ? 'p-3' : 'p-4'),
);
const createdLabel = computed(() =>
  new Intl.DateTimeFormat('ko-KR', { dateStyle: 'medium' }).format(new Date(props.task.createdAt)),
);
</script>

<template>
  <article :class="rootClass" @click="$emit('select', task.id)">
    <h3 class="text-sm font-semibold text-slate-900">{{ task.title }}</h3>
    <p class="mt-1 text-xs text-slate-500">{{ createdLabel }}</p>
    <div v-if="$slots.actions" class="mt-3 flex gap-2">
      <slot name="actions" :task="task" />
    </div>
  </article>
</template>
```

- `<style>` 블록이 없다 — Tailwind가 유일한 스타일 체계다 (`resources/styling.md`)
- 루트가 하나이므로 호출부가 준 `class`·`aria-*`·리스너가 자동으로 이 `<article>`에 붙는다
- 공통 컴포넌트는 `useRouter()`·`useQuery()`를 호출하지 않는다 (재사용을 막는다)
<!-- /pack-slot -->

## 이음매가 채울 것 — 이 팩에 없는 것

| 허브 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| Architecture Overview | 신뢰 경계와 데이터 출처가 백엔드 축에 달렸다 |
| Quick Start 체크리스트 2개 | 페이지네이션 모델·에러 코드 분기가 와이어 계약에 달렸다 |
| Core Principle 4 "인가는 신뢰 경계가 아니다" | 원칙은 보편이나 **미인가 응답이 403인지 404인지**가 백엔드 축에 달렸다. 이 규칙은 반드시 넣는다 (번호 4가 비어 있는 이유다) |
| Common Imports의 HTTP 클라이언트·인증 행 | 인증 방식과 봉투 해석이 백엔드 축에 달렸다 |
| Navigation Guide | 팩 리소스 행은 `pack.json`이 제공하고, 이음매 리소스 행은 이음매가 추가한다 |
