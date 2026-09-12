---
name: frontend-guide
description: Vue 3 + Vite SPA frontend guide for a Node/Express REST API backend. Covers SFC patterns, Tailwind styling, Vue Router, Pinia, TanStack Vue Query over a cursor-paginated response envelope, token auth with one-shot 401 refresh, validated return paths, and loading/empty/error states. Use when creating or modifying components, pages, routing, styling, state, API calls, auth screens, or frontend tests.
---
<!-- epcc-seam: vue+node-api v3.13.0 -->

## Quick Start

> `dev/docs/api/wire-contract.md`가 있으면 봉투·에러 코드·페이지네이션은 거기가 정본이다. 없는데 프론트·백엔드를 함께 새로 만드는 중이면 `workflow-routing.md`의 「기능 하나의 안쪽 순서」 1·2를 먼저 한다.

### 새 데이터 화면을 만든다

- [ ] 라우트를 `src/router/routes.ts`에 추가한다 — 보호가 필요하면 `meta.requiresAuth`
- [ ] 요청 함수와 쿼리 키를 `src/features/<f>/api/`에 둔다 (`resources/data-fetching.md` §4)
- [ ] 쿼리 컴포저블을 만든다 — 목록은 커서(`limit`·`cursor`), 응답은 `{ data, nextCursor }`
- [ ] 응답을 `parseTask`/`parseTaskList`로 좁힌다 — 계약 파손을 경계에서 잡는다
- [ ] 3상태를 모두 그린다: `isPending` → `isError` → 빈 → 성공 (순서를 바꾸지 않는다)
- [ ] 필터·정렬은 컴포넌트 상태가 아니라 URL 쿼리에 둔다 — 그 값이 쿼리 키가 된다
- [ ] 반복 UI는 `src/components/common/`을 **먼저 검색**하고, 없을 때만 새로 만든다
- [ ] 테스트에서 `server.use()`로 계약 봉투를 덮고 긍정·부정을 같은 `it`에 건다

### 새 API 호출을 붙인다

- [ ] `src/api/http.ts`의 `get`/`post`/`patch`/`delete`를 쓴다 — 컴포넌트에서 `fetch` 금지
- [ ] 목록이라 `nextCursor`가 필요하면 `http.page()`를 쓴다
- [ ] 실패는 `ApiError`다. 화면 분기는 `status`가 아니라 **`code`**로 한다
- [ ] 401은 화면이 다루지 않는다 — `http.ts`가 재발급을 1회 시도하고 실패하면 올린다
- [ ] 소유권 실패는 404다. 403과 구분하지 않고 한 화면으로 처리한다
- [ ] 검증 실패의 `details`(`Record<string, string[]>`)를 필드 아래로 옮긴다
- [ ] 변경 뮤테이션은 `onSuccess`에서 `invalidateQueries({ queryKey: taskKeys.all })`

## Architecture Overview

| 층 | 무엇 | 신뢰 |
| --- | --- | --- |
| 브라우저 (Vue 3 SPA) | 라우팅 · 렌더 · 캐시 · 인가 **표시** | 신뢰하지 않는다 |
| HTTP 경계 | `Authorization: Bearer` + `httpOnly` 재발급 쿠키 | — |
| Node/Express API | 검증 · 인증 · **소유권 판정** · 응답 봉투 | 유일한 판정자 |

- **경계가 하나뿐이다.** 서버 컴포넌트도 Server Action도 없다 — 모든 데이터는 브라우저의
  `fetch` 한 통로로 들어온다. 그래서 인증 헤더·에러 정규화·타임아웃이 `src/api/http.ts`
  **한 파일**에 갇혀 있어야 하고, 거기서 새면 화면마다 다시 발명된다
- **백엔드에 데이터 계층 정책 엔진이 없다.** 애플리케이션 층이 유일한 경계이므로 프론트의
  인가 UI는 신뢰 경계가 아니다 — 숨김은 UX이고 판정은 서버다
- **서버 상태는 Vue Query, 클라이언트 상태는 Pinia.** 두 영역이 겹치면 캐시가 둘이 된다
- **와이어 계약이 정하는 것**: 봉투(`{ data }` · `nextCursor`) · 커서 페이지네이션 ·
  에러 코드표 · 인가 실패 표면(401/403/**404**). 이 넷이 이음매 리소스 3종의 내용이다

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

## Core Principles (7 Key Rules)

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

### 4. 인가 UI는 신뢰 경계가 아니다 — 그리고 실패는 404로 온다

이 조합의 백엔드에는 데이터 계층 정책 엔진이 없다. 소유권을 강제하는 곳은 서버의
애플리케이션 층 **하나뿐**이고, 프론트가 숨기는 것은 전부 UX다. 그래서 **숨김에는 반드시
그에 대응하는 실패 응답 처리가 따라붙는다.**

그리고 이 조합에서 소유권 실패는 403이 아니라 **404**로 온다(계약 §5) — 존재를 누설하지
않기 위해서다. 「없는 것」과 「남의 것」을 가르는 정보는 응답에 없다.

```ts
// ✅ 404 하나로 "없거나 내 것이 아니다"를 처리한다
const missing = computed(() => (error.value as ApiError | null)?.code === 'NOT_FOUND');

// ❌ 소유권 실패를 403으로 기다린다 — 이 조합에서는 오지 않아 영원히 빈 화면이 남는다
const forbidden = computed(() => (error.value as ApiError | null)?.code === 'FORBIDDEN');
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

## Common Imports

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
// 이 조합의 이음매 — HTTP 경계는 하나다 (SPA ↔ 별도 API 서버)
// 커서 페이징은 useInfiniteQuery로 받아 select로 평탄화한다 (resources/data-fetching.md §5)
import { http } from '@/api/http';
import { ApiError } from '@/api/errors';
import { queryClient } from '@/api/queryClient';
import { useAuth } from '@/auth/useAuth';
import { useTasksQuery } from '@/features/tasks/api/useTasksQuery';
import { useCreateTaskMutation } from '@/features/tasks/api/useCreateTaskMutation';
import { safeReturnTo } from '@/lib/safeReturnTo';
import type { Task } from '@/types/task';
```

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

## Navigation Guide

| 하려는 일 | 읽을 파일 |
| --- | --- |
| SFC 만들기 · props/emits/슬롯 타입 선언 · 반복 UI를 공통으로 추출 · 제네릭 컴포넌트 · 디자인 토큰 소유 규칙 | `resources/component-patterns.md` |
| Tailwind 클래스 작성 · :class와 cn() 구분 · 변형(variant) 정의 · scoped CSS·인라인 style 금지 | `resources/styling.md` |
| 전역 상태 도입 여부 판단 · Pinia 스토어 작성 · storeToRefs 구독 · 컴포넌트 밖에서 스토어 쓰기 · URL을 상태로 | `resources/state-management.md` |
| 라우트 추가 · 중첩 레이아웃 · 네비게이션 가드 · 복귀 경로 검증 · 라우트/청크 에러 · 지연 로딩 · 딥링크(history fallback) | `resources/routing.md` |
| 로딩 스켈레톤 · 빈 상태 · 에러 상태 · onErrorCaptured 경계 · Suspense를 쓰지 않는 이유 · 폼 검증 에러 표시 | `resources/loading-error-states.md` |
| vue-tsc 설정 · 컴포넌트 props 타입 · 환경변수 타입 · API 응답 좁히기 · Vitest + @vue/test-utils 컴포넌트/스토어 테스트 · msw HTTP 모킹 | `resources/types-and-testing.md` |
| HTTP 클라이언트 작성 · 에러 정규화(`ApiError`) · 쿼리/뮤테이션 컴포저블 · 쿼리 키 · 캐시 무효화 · 커서 페이지네이션 소비 | `resources/data-fetching.md` |
| 토큰 보관 위치 · 401 재발급 1회 · 로그인/로그아웃 · 복귀 경로 검증 소비 · 로그아웃 시 캐시·스토어 폐기 순서 | `resources/auth-and-session.md` |
| 목록 조회 + 생성을 처음부터 끝까지 · 3상태와 커서 페이징 조립 · 검증 오류 표시 · main.ts 배선 · 긍정/부정 짝 테스트 | `resources/complete-example.md` |
