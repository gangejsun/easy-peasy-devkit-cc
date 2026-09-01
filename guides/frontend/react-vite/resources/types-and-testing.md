<!-- epcc-pack: frontend/react-vite v3.12.0 -->
# TypeScript 표준 · 프론트엔드 테스트

## 목차

1. tsconfig 기준선
2. 환경변수 타입
3. API 경계에서 타입 좁히기
4. 도메인 타입 작성
5. 테스트 도구와 배치
6. 렌더 헬퍼
7. 테스트 패턴
8. 오용 목록

---

## 1. tsconfig 기준선

```jsonc
// tsconfig.json (app 부분)
{
  "compilerOptions": {
    "strict": true,
    "noUncheckedIndexedAccess": true,   // arr[0]이 T | undefined가 된다 — 인덱싱 사고를 잡는다
    "noUnusedLocals": true,
    "noFallthroughCasesInSwitch": true,
    "verbatimModuleSyntax": true,       // 타입 import는 반드시 `import type`
    "jsx": "react-jsx",                 // React 17+ 변환 — 파일마다 React import 불필요
    "moduleResolution": "bundler",
    "baseUrl": ".",
    "paths": { "@/*": ["src/*"] }
  }
}
```

```ts
// vite.config.ts — 별칭은 두 곳에 모두 있어야 한다 (타입체크와 번들은 별개다)
resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } }
```

`npm run typecheck`(= `tsc --noEmit`)를 CI와 `build` 스크립트에 넣는다. Vite는 타입을
검사하지 않고 트랜스파일만 하므로, 타입 오류는 빌드를 통과한다.

## 2. 환경변수 타입

```ts
// src/vite-env.d.ts
/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_BASE_URL: string;
  readonly VITE_OIDC_AUTHORITY: string;
  readonly VITE_OIDC_CLIENT_ID: string;
  readonly VITE_OIDC_LOGOUT_URL: string;   // issuer 고유 로그아웃 URL (auth-and-session.md §6)
}
interface ImportMeta { readonly env: ImportMetaEnv }
```

<!-- file: src/config.ts -->
```ts
// src/config.ts — 앱 코드(http.ts·oidcConfig.ts 포함)는 import.meta.env를 직접 읽지 않는다.
// 값을 **호출부에서 리터럴 키로 읽어** 넘긴다 — 함수 안에서 import.meta.env[name]을 하면
// Vite의 정적 치환이 일어나지 않아 프로덕션 빌드에서 전부 undefined가 된다.
function required(name: string, value: string | undefined): string {
  if (!value) throw new Error(`환경변수 ${name}이(가) 설정되지 않았습니다.`);
  return value;
}

export const config = {
  apiBaseUrl: required('VITE_API_BASE_URL', import.meta.env.VITE_API_BASE_URL),
  oidc: {
    authority: required('VITE_OIDC_AUTHORITY', import.meta.env.VITE_OIDC_AUTHORITY),
    clientId: required('VITE_OIDC_CLIENT_ID', import.meta.env.VITE_OIDC_CLIENT_ID),
    logoutUrl: required('VITE_OIDC_LOGOUT_URL', import.meta.env.VITE_OIDC_LOGOUT_URL),
  },
} as const;
```

부팅 시점에 던지면 누락이 즉시 드러난다. 첫 사용 시점까지 미루면 특정 화면에 들어가야만
발견된다. 이 파일이 `import.meta.env`가 등장하는 **유일한 곳**이다.

## 3. API 경계에서 타입 좁히기

`await res.json()`은 `any`다. 여기서 타입 단언만 하면 서버 계약이 바뀌어도 컴파일이
통과하고, 오류는 화면 깊은 곳에서 터진다. 경계에 **좁히기 함수**를 두고, `http` 클라이언트의
`parse` 옵션으로 넘겨 **실제로 호출되게** 한다.

```ts
// features/tasks/api/tasks.types.ts
export function assertTask(v: unknown): asserts v is Task {
  const t = v as Record<string, unknown> | null;
  if (!t || typeof t.id !== 'string' || typeof t.title !== 'string') {
    throw new ApiError(500, 'BAD_SHAPE', '응답 형식이 계약과 다릅니다.');
  }
}
export const parseTask = (v: unknown): Task => { assertTask(v); return v; };

// ✅ 호출부 — 좁히기가 요청 경로 위에 놓인다
http.getPage<Task>('/tasks?limit=20', { parse: parseTask });

// ❌ parse 없이 호출 — 클라이언트 내부에서 `as T`가 되어 서버가 필드를 지워도 조용히 통과
http.getPage<Task>('/tasks?limit=20');
```

전 필드를 검사할 필요는 없다. **화면이 반드시 의존하는 필드**만 확인해도 대부분의
계약 파손이 여기서 걸린다. 응답을 화면이 실제로 읽는 엔드포인트에는 `parse`를 빠뜨리지 않는다.

## 4. 도메인 타입 작성

```ts
// ✅ 판별 유니온 — 불가능한 조합이 타입에서 사라진다 (완료 시각은 done일 때만 존재한다)
type TicketStatus = 'open' | 'in_progress' | 'done';
type Ticket =
  | { id: string; title: string; status: 'done'; completedAt: string }
  | { id: string; title: string; status: 'open' | 'in_progress'; completedAt?: never };

// ✅ 누락 분기를 컴파일 에러로 만든다
function label(s: TicketStatus): string {
  switch (s) {
    case 'open': return '대기';
    case 'in_progress': return '진행 중';
    case 'done': return '완료';
    default: { const _never: never = s; return _never; }
  }
}
```

- `any`를 쓰지 않는다. 모르는 값은 `unknown`으로 받고 좁힌다
- `enum` 대신 리터럴 유니온 + `as const` 객체를 쓴다 (번들에 런타임 코드가 남지 않는다)
- 서버 응답 타입(`TaskResponse`)과 화면 모델(`Task`)이 다르면 매핑 함수를 API 계층에 둔다
- 컴포넌트 props는 `ComponentPropsWithoutRef<'button'>` 확장으로 네이티브 속성을 상속받는다

## 5. 테스트 도구와 배치

| 대상 | 도구 | 위치 |
| --- | --- | --- |
| 순수 함수·유틸 | Vitest | `src/lib/x.test.ts` |
| 훅(쿼리/뮤테이션 포함) | Vitest + Testing Library `renderHook` | 훅 파일 옆 |
| 컴포넌트 | Vitest + React Testing Library + `user-event` | 컴포넌트 파일 옆 |
| HTTP | MSW (`setupServer`)로 네트워크 계층에서 모킹 | `src/test/msw/` |

```ts
// vitest.config.ts
test: { environment: 'jsdom', setupFiles: ['./src/test/setup.ts'], globals: true }
```

<!-- file: src/test/setup.ts -->
```ts
// src/test/setup.ts
import '@testing-library/jest-dom/vitest';
import { server } from './msw/server';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));  // 모킹 안 된 요청은 실패시킨다
afterEach(() => { server.resetHandlers(); cleanup(); });
afterAll(() => server.close());
```

<!-- file: src/test/msw/handlers.ts -->
```ts
// src/test/msw/handlers.ts — MSW v2 API
import { http, HttpResponse } from 'msw';

// 핸들러도 **봉투 계약**을 지켜야 한다. 여기서 형태가 틀리면 테스트만 통과하고 실물이 깨진다
export const handlers = [
  http.get('*/tasks', () => HttpResponse.json({ data: [], nextCursor: null })),
  http.post('*/tasks', async ({ request }) => {
    const body = (await request.json()) as { title: string };
    return HttpResponse.json({ data: { id: 't1', ...body, status: 'open' } }, { status: 201 });
  }),
  // 실패 케이스는 server.use()로 그 테스트에서만 덮는다
  // HttpResponse.json({ error: { code: 'VALIDATION_FAILED', message: '...',
  //   details: { title: ['2자 이상'] } }, requestId: 'req_1' }, { status: 422 })
];
```

`fetch`를 직접 스텁하지 않고 MSW를 쓰는 이유: `http.ts`의 헤더 조립·에러 정규화까지
함께 검증되므로, 테스트가 통과하면 실제 경로도 통과한다.

## 6. 렌더 헬퍼

<!-- file: src/test/renderWithProviders.tsx -->
```tsx
// src/test/renderWithProviders.tsx
export function renderWithProviders(ui: ReactNode, { route = '/' } = {}) {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: { retry: false, gcTime: 0 },   // 재시도 끄지 않으면 실패 테스트가 느려진다
      mutations: { retry: false },
    },
  });
  const router = createMemoryRouter([{ path: '*', element: <>{ui}</> }], {
    initialEntries: [route],
  });
  return {
    queryClient,
    ...render(<QueryClientProvider client={queryClient}><RouterProvider router={router} /></QueryClientProvider>),
  };
}
```

**QueryClient는 테스트마다 새로 만든다.** 공유하면 앞 테스트의 캐시가 뒤 테스트의
로딩 상태를 없애 버려 실패가 산발적으로 나타난다. Zustand 스토어도
`beforeEach(() => useUiStore.getState().reset())`으로 되돌린다.

## 7. 테스트 패턴

```tsx
// 라우트 모듈은 화면을 `Component`로 export한다 (routing.md §1) — 이름을 바꿔 import한다
import { Component as TaskListPage } from '@/features/tasks/pages/TaskListPage';

it('작업을 생성하면 목록이 갱신된다', async () => {
  const user = userEvent.setup();
  renderWithProviders(<TaskListPage />, { route: '/tasks' });

  // 로딩 → 데이터: findBy*는 나타날 때까지 기다린다
  expect(await screen.findByRole('heading', { name: '작업' })).toBeInTheDocument();

  await user.click(screen.getByRole('button', { name: '새 작업' }));
  await user.type(screen.getByLabelText('제목'), '보고서 작성');
  await user.click(screen.getByRole('button', { name: '저장' }));

  expect(await screen.findByText('보고서 작성')).toBeInTheDocument();
});
```

- 쿼리 우선순위: `getByRole` > `getByLabelText` > `getByText` > `getByTestId`(최후)
- 사용자 관점으로 단언한다. 훅 내부 상태·호출 횟수를 검사하지 않는다
- 비동기는 `findBy*`/`waitFor`로 기다린다. `act()`를 직접 부르지 않는다
- 에러 경로를 반드시 하나는 테스트한다 — `server.use()`로 그 테스트에서만 500을 돌려준다

## 8. 오용 목록

### ① 관용구 대조표

| 옛 습관 | 현재 형태 |
| --- | --- |
| `jest.fn()` / `jest.mock()` | `vi.fn()` / `vi.mock()` (`globals: true`면 `describe/it/expect`는 그대로) |
| MSW v1 `rest.get(url, (req, res, ctx) => res(ctx.json(x)))` | MSW v2 `http.get(url, () => HttpResponse.json(x))` |
| `@testing-library/jest-dom` 루트 import | `@testing-library/jest-dom/vitest` |
| `fireEvent.change(input, ...)` | `await userEvent.type(input, ...)` — 실제 입력 이벤트 순서를 재현한다 |
| `import React from 'react'` 습관적 추가 | `jsx: "react-jsx"`에서는 불필요 |
| `const enum` / `enum` | 리터럴 유니온 + `as const` |

### ② 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `getBy*` vs `queryBy*` vs `findBy*` | `getBy`는 있어야 함(없으면 즉시 실패), `queryBy`는 **없음을 단언할 때만**, `findBy`는 비동기로 나타날 때 |
| `as T` vs 타입 가드 | 단언은 컴파일러를 침묵시킬 뿐 런타임을 바꾸지 않는다. 외부 데이터에는 가드를 쓴다 |
| `unknown` vs `any` | 외부 입력은 `unknown`으로 받는다. `any`는 전염되어 타입 검사를 무력화한다 |
| `interface` vs `type` | props·객체 모양은 아무거나. 유니온·매핑·조건부 타입은 `type`만 가능 |
| `import type` vs `import` | `verbatimModuleSyntax`에서는 타입 전용 import에 `type`이 필수 — 없으면 런타임 import가 남는다 |
| `?.`/`??`로 뭉개기 vs 타입 좁히기 | 옵셔널 체이닝을 줄줄이 붙이는 것은 타입이 틀렸다는 신호다. 경계에서 좁히면 아래는 깨끗해진다 |
| 훅 테스트 vs 컴포넌트 테스트 | 훅이 복잡한 캐시·무효화 로직을 가지면 `renderHook`. 그 외에는 컴포넌트 테스트가 더 많은 것을 잡는다 |
| MSW 핸들러 전역 등록 vs `server.use()` | 기본 성공 응답은 전역. 특정 테스트의 실패 케이스는 `server.use()`로 그 테스트에서만 덮는다 |
