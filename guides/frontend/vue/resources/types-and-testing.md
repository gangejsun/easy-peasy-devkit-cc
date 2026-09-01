<!-- epcc-pack: frontend/vue v3.12.0 -->
# TypeScript 표준 · 프론트엔드 테스트


## 1. tsconfig 기준선과 타입 검사

```jsonc
// tsconfig.app.json
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,   // arr[0]이 T | undefined가 된다 — 인덱싱 사고를 잡는다
    "noUnusedLocals": true,
    "noFallthroughCasesInSwitch": true,
    "verbatimModuleSyntax": true,       // 타입 import는 반드시 `import type`
    "moduleResolution": "bundler",
    "jsx": "preserve",                  // .vue 안에서 tsx를 쓰지 않아도 이 값이 안전하다
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  },
  "include": ["src/**/*.ts", "src/**/*.vue", "env.d.ts"]
}
```

```ts
// vite.config.ts — 별칭은 두 곳에 모두 있어야 한다 (타입 검사와 번들은 별개다)
resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } }
```

**타입 검사는 `vue-tsc --noEmit`이다.** 순수 `tsc`는 `.vue` 파일을 읽지 못해 컴포넌트가
통째로 검사에서 빠진다. `npm run typecheck`를 CI와 `build` 스크립트에 넣는다 — Vite는
트랜스파일만 하므로 타입 오류는 빌드를 통과한다.

## 2. 환경변수 타입

```ts
// env.d.ts
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string;
}
interface ImportMeta { readonly env: ImportMetaEnv }
```

`declare module '*.vue'` 셰이딩을 **넣지 않는다.** 순수 `tsc`·vue-tsc 1.x·Volar 없는
편집기에서는 이 선언이 모든 컴포넌트의 props·emits를 `any`로 덮어 타입 검사를 살아 있는
채로 무력화한다. vue-tsc 2 이후에는 SFC의 실제 타입이 이겨 무해하지만, 그래도 불필요하고
도구를 바꾸는 순간 되살아나는 함정이라 두지 않는다.

<!-- file: src/config.ts -->
```ts
// src/config.ts — import.meta.env가 등장하는 유일한 파일
function required(name: string, value: string | undefined): string {
  if (!value) throw new Error(`환경변수 ${name}이(가) 설정되지 않았습니다.`);
  return value;
}

export const config = {
  apiBaseUrl: required('VITE_API_BASE_URL', import.meta.env.VITE_API_BASE_URL),
  basePath: import.meta.env.BASE_URL,   // Vite가 주는 배포 기준 경로 — 라우터가 쓴다
} as const;
```

값을 **호출부에서 리터럴 키로 읽어** 넘긴다. 함수 안에서 `import.meta.env[name]`으로
읽으면 Vite의 정적 치환이 일어나지 않아 프로덕션 빌드에서 전부 `undefined`가 된다.
부팅 시점에 던지므로 누락이 즉시 드러난다 — 첫 사용 시점까지 미루면 특정 화면에
들어가야만 발견된다. 비밀은 여기에 넣지 않는다: `VITE_*`는 번들에 인라인된다.

## 3. 컴포넌트 props 타입

- `defineProps<T>()`에 넘기는 타입은 **import한 타입도 된다** (Vue 3.3+). `PropType`은 필요 없다
- 기본값은 `withDefaults`로 준다. 선택 prop의 타입은 `?:`이고 기본값과 짝을 맞춘다
- 판별 유니온으로 불가능한 조합을 없앤다: `{ status: 'done'; completedAt: string } | { status: 'open'; completedAt?: never }`
- `any`를 쓰지 않는다. 모르는 값은 `unknown`으로 받고 좁힌다
- `enum` 대신 리터럴 유니온 + `as const` 객체를 쓴다 (번들에 런타임 코드가 남지 않는다)
- 컴포넌트 인스턴스 타입이 필요하면 `InstanceType<typeof MyComponent>`를 쓴다

## 4. API 경계에서 타입 좁히기

응답 본문은 `unknown`이다. 여기서 단언만 하면 서버 계약이 바뀌어도 컴파일이 통과하고,
오류는 화면 깊은 곳에서 터진다. 경계에 **좁히기 함수**를 두고 요청 경로 위에 놓는다.

<!-- file: src/features/tasks/api/tasks.parse.ts -->
```ts
// src/features/tasks/api/tasks.parse.ts
import { ApiError } from '@/api/errors';   // 이음매가 제공한다
import type { Task } from '@/types/task';  // 도메인 타입도 이음매가 정의한다

export function assertTask(v: unknown): asserts v is Task {
  const t = v as Record<string, unknown> | null;
  if (!t || typeof t.id !== 'string' || typeof t.title !== 'string') {
    throw new ApiError('BAD_SHAPE', '응답 형식이 계약과 다릅니다.');
  }
}

export const parseTask = (v: unknown): Task => { assertTask(v); return v; };
export const parseTaskList = (v: unknown): Task[] => {
  if (!Array.isArray(v)) throw new ApiError('BAD_SHAPE', '목록 응답이 배열이 아닙니다.');
  return v.map(parseTask);
};
```

```ts
// 이음매의 쿼리 컴포저블 안에서 — 좁히기가 요청 경로 위에 놓인다
const raw: unknown = await http.get('/tasks');
const tasks = parseTaskList(raw);
```

전 필드를 검사할 필요는 없다. **화면이 반드시 의존하는 필드**만 확인해도 대부분의 계약
파손이 여기서 걸린다. 응답을 화면이 실제로 읽는 엔드포인트에는 좁히기를 빠뜨리지 않는다.

> `Task`와 `ApiError`는 이 팩이 정의하지 않는다(`ledger.md`의 `requires`). 이 팩이
> 소유하는 것은 **좁히기를 어디에 두고 실패를 어떻게 던지는가**이고, 실제 필드와 에러
> 코드는 와이어 계약이 정한다.

## 5. 테스트 도구와 배치

| 대상 | 도구 | 위치 |
| --- | --- | --- |
| 순수 함수·유틸 | Vitest 2 | `src/lib/x.test.ts` |
| 컴포저블 | 껍데기 컴포넌트에 마운트해 검증 (`mount(defineComponent({ setup: () => (useX(), () => null) }))`) | 컴포저블 파일 옆 |
| 컴포넌트 | Vitest + `@vue/test-utils` 2 | 컴포넌트 파일 옆 |
| Pinia 스토어 | Vitest + `setActivePinia` | 스토어 파일 옆 |
| HTTP | msw 2 (`setupServer`)로 네트워크 계층에서 모킹 | `src/test/msw/` |

```ts
// vite.config.ts — Vitest 설정은 여기에 둔다. 별도 vitest.config.ts를 만들면 vue() 플러그인을
// 거기서 다시 등록해야 하고, 빠뜨리면 .vue import 자체가 파싱되지 않는다
//
// defineConfig는 반드시 'vitest/config'에서 가져온다. 'vite'의 것에는 test 키가 없어
// strict TS에서 타입 오류가 나고, 이 팩이 CI에 넣으라고 한 vue-tsc --noEmit이 빨개진다
import { defineConfig } from 'vitest/config';

plugins: [vue()],
test: { environment: 'jsdom', setupFiles: ['./src/test/setup.ts'], globals: true },
```

<!-- file: src/test/msw/handlers.ts -->
```ts
// src/test/msw/handlers.ts — msw v2 API
import { http, HttpResponse } from 'msw';

// 응답 **봉투 형태는 이음매의 계약**이다. 여기서 형태가 틀리면 테스트만 통과하고 실물이 깨진다 —
// 이음매를 붙일 때 이 본문을 그 계약으로 교체한다
export const handlers = [
  http.get('*/tasks', () => HttpResponse.json([])),
  http.post('*/tasks', async ({ request }) => {
    const body = (await request.json()) as { title: string };
    return HttpResponse.json({ id: 't1', status: 'open', ...body }, { status: 201 });
  }),
];
```

<!-- file: src/test/setup.ts -->
```ts
// src/test/setup.ts
import { setupServer } from 'msw/node';
import { handlers } from './msw/handlers';

export const server = setupServer(...handlers);

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));   // 모킹 안 된 요청은 실패시킨다
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

msw의 `http`와 API 클라이언트의 `http`는 이름이 겹친다. 테스트 파일은 API 클라이언트를
import하지 않으므로 실제 충돌은 없지만, 한 파일에서 둘 다 필요하면 별칭을 준다.
`fetch`를 직접 스텁하지 않는 이유: msw를 쓰면 클라이언트의 헤더 조립과 에러 정규화까지
함께 검증되므로, 테스트가 통과하면 실제 경로도 통과한다.

## 6. 마운트 헬퍼

<!-- file: src/test/mountWithProviders.ts -->
```ts
// src/test/mountWithProviders.ts
import { mount, type MountingOptions } from '@vue/test-utils';
import { createPinia } from 'pinia';
import { createRouter, createMemoryHistory } from 'vue-router';
import { VueQueryPlugin, QueryClient } from '@tanstack/vue-query';
import type { Component } from 'vue';
import { routes } from '@/router/routes';

type Options = MountingOptions<Record<string, unknown>>;

export function mountWithProviders(component: Component, options: Options = {}) {
  // 테스트마다 새 QueryClient를 만든다. 공유하면 앞 테스트의 캐시가 뒤 테스트의 로딩
  // 상태를 없애 실패가 산발적으로 나타난다
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },   // 재시도를 끄지 않으면 실패 테스트가 느려진다
      mutations: { retry: false },
    },
  });
  const router = createRouter({ history: createMemoryHistory(), routes });
  const wrapper = mount(component, {
    ...options,
    global: {
      ...options.global,
      // 병합이지 덮어쓰기가 아니다 — 호출자가 global.plugins를 주면 pinia·router·query가
      // 통째로 사라진다 (스프레드를 뒤에 두면 정확히 그렇게 된다)
      plugins: [
        createPinia(), router, [VueQueryPlugin, { queryClient }],
        ...(options.global?.plugins ?? []),
      ],
    },
  });
  return { wrapper, router, queryClient };
}
```

## 7. 테스트 패턴

```ts
// src/features/tasks/pages/TaskListPage.test.ts
import { flushPromises } from '@vue/test-utils';
import { mountWithProviders } from '@/test/mountWithProviders';
import { http, HttpResponse } from 'msw';
import { server } from '@/test/setup';
import TaskListPage from './TaskListPage.vue';

it('목록이 비어 있으면 빈 상태를 그린다', async () => {
  const { wrapper, router } = mountWithProviders(TaskListPage);
  await router.isReady();          // 라우터를 쓰는 화면은 첫 해석을 기다린다
  await flushPromises();           // 대기 중인 마이크로태스크(쿼리 해석)를 모두 흘린다

  expect(wrapper.text()).toContain('아직 작업이 없습니다');
});

it('요청이 실패하면 에러 상태와 재시도 버튼을 그린다', async () => {
  server.use(http.get('*/tasks', () => HttpResponse.error()));   // 이 테스트에서만 덮는다
  const { wrapper } = mountWithProviders(TaskListPage);
  await flushPromises();

  expect(wrapper.get('[role="alert"]').text()).toContain('연결에 실패했습니다');
  await wrapper.get('button').trigger('click');   // trigger는 await해야 DOM이 갱신된다
});
```

```ts
// src/stores/ui.test.ts — 스토어마다 pinia를 새로 심는다. 심지 않으면 앞 테스트 상태가 샌다
beforeEach(() => setActivePinia(createPinia()));

it('reset()이 초기값으로 되돌린다', () => {
  const ui = useUiStore();
  ui.toggleSidebar();
  ui.reset();
  expect(ui.isSidebarOpen).toBe(true);
});
```

- 셀렉터는 접근성 속성에 건다: `wrapper.get('[role="alert"]')`, `wrapper.get('[aria-label="작업 삭제"]')`.
  `data-testid`는 최후 수단이다 — 접근성 속성에 걸면 셀렉터가 곧 접근성 검사가 된다
- 사용자 관점으로 단언한다. 컴포저블 내부 상태·호출 횟수를 검사하지 않는다
- 에러 경로를 반드시 하나는 테스트한다 — `server.use()`로 그 테스트에서만 실패시킨다
- 자식 컴포넌트를 스텁하지 않는다(`shallow: true`). 스텁하면 슬롯·props 계약이 검사되지 않는다

## 8. 오용 목록

### ① 관용구 대조표

| 옛 습관 | 현재 형태 |
| --- | --- |
| `tsc --noEmit` | `vue-tsc --noEmit` — `tsc`는 `.vue`를 읽지 못한다 |
| `declare module '*.vue'` 셰이딩 추가 | 넣지 않는다 — 컴포넌트 타입이 전부 `any`가 된다 |
| `props: { x: { type: String as PropType<T> } }` | `defineProps<{ x: T }>()` |
| `jest.fn()` / `jest.mock()` | `vi.fn()` / `vi.mock()` (`globals: true`면 `describe/it/expect`는 그대로) |
| msw v1 `rest.get(url, (req, res, ctx) => res(ctx.json(x)))` | msw v2 `http.get(url, () => HttpResponse.json(x))` |
| `@vue/test-utils` v1 `wrapper.setData(...)` | `<script setup>` 컴포넌트에는 동작하지 않는다 — props나 스토어로 주입한다 |
| `wrapper.find(...).trigger('click')` 후 즉시 단언 | `await wrapper.get(...).trigger('click')` |
| `wrapper.vm.someInternal` 검사 | `<script setup>`은 바인딩을 노출하지 않는다 — 렌더 결과로 단언한다 |
| `localVue` / `createLocalVue` (VTU v1) | `global: { plugins, stubs, provide }` |
| `enum` / `const enum` | 리터럴 유니온 + `as const` |

### ② 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `vue-tsc` vs `tsc` | 컴포넌트를 검사하려면 언제나 `vue-tsc` |
| `defineProps` 타입 선언 vs 런타임 선언 | 타입 선언이 기본. 런타임 검증(`validator`)이 꼭 필요할 때만 런타임 선언 |
| `mount` vs `shallowMount` | 기본은 `mount`. 자식 트리가 무거워 테스트가 느려질 때만 좁힌다 |
| `wrapper.get` vs `wrapper.find` | `get`은 없으면 즉시 실패(존재를 전제할 때), `find`는 **없음을 단언할 때** |
| `nextTick()` vs `flushPromises()` | DOM 갱신 한 틱만 기다리면 `nextTick`. 대기 중인 Promise(쿼리 해석)까지 흘리려면 `flushPromises` |
| `await trigger(...)` vs 그냥 호출 | `trigger`는 Promise를 반환한다. `await` 없이 단언하면 갱신 전 DOM을 본다 |
| `setActivePinia` 있음 vs 없음 | 스토어를 직접 테스트할 때 필수. 컴포넌트 테스트는 `global.plugins`의 pinia로 충분하다 |
| `unknown` vs `any` | 외부 입력은 `unknown`으로 받는다. `any`는 전염되어 타입 검사를 무력화한다 |
| `import type` vs `import` | `verbatimModuleSyntax`에서는 타입 전용 import에 `type`이 필수 — 없으면 런타임 import가 남는다 |
| `interface` vs `type` | props·객체 모양은 아무거나. 유니온·매핑·조건부 타입은 `type`만 가능 |
| `?.`/`??`로 뭉개기 vs 타입 좁히기 | 옵셔널 체이닝을 줄줄이 붙이는 것은 타입이 틀렸다는 신호다. 경계에서 좁히면 아래는 깨끗해진다 |
| msw 전역 핸들러 vs `server.use()` | 기본 성공 응답은 전역. 특정 테스트의 실패 케이스는 `server.use()`로 그 테스트에서만 덮는다 |
