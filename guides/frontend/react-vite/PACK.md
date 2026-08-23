<!-- epcc-pack: frontend/react-vite v3.12.0 verified 2026-08-22 react@18 vite@5 typescript@5 react-router@7 @tanstack/react-query@5 zustand@5 tailwindcss@3.4 react-error-boundary@6 sonner@2 msw@2 vitest@3 clsx@2 tailwind-merge@2 eslint-plugin-import@2 -->

# react-vite 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가
있는 조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

각 조각은 `<!-- pack-slot: 이름 -->` ~ `<!-- /pack-slot -->` 사이에 있고, 축 안에서
닫혀 있어 백엔드 축이 무엇이든 그대로 성립한다. 조합의 함수인 것은 여기 없다 —
파일 끝의 표가 이음매의 몫을 명시한다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── main.tsx                 # createRoot + Provider 조립 (Auth · AuthWiring · Query · Router)
├── config.ts                # import.meta.env를 읽는 **유일한** 파일 (타입 붙여 내보낸다)
├── routes/
│   ├── routes.tsx           # 라우트 객체 트리 (단일 소스, /auth/callback 포함)
│   ├── RootLayout.tsx       # 전역 셸: 헤더 · 네비 · <Outlet />
│   └── RequireAuth.tsx      # 인증 게이트 레이아웃 라우트
├── api/
│   ├── http.ts              # fetch 래퍼 · 봉투 해석 · 인증 헤더 · ApiError 정규화
│   └── tokenProvider.ts     # 액세스 토큰 공급자 (auth 모듈이 주입한다)
├── auth/                    # oidcConfig · AuthWiring · session · endSession · groups · pages/
├── features/
│   └── tasks/
│       ├── api/             # 엔드포인트 함수 + 쿼리 키 + 쿼리/뮤테이션 훅
│       ├── components/      # 이 기능에서만 쓰는 컴포넌트
│       └── pages/           # 라우트가 가리키는 화면
├── components/
│   ├── common/              # 2개 이상 기능이 공유하는 UI ← 새로 만들기 전 여기부터 검색
│   └── layout/              # PageShell · Sidebar · SectionHeader
├── stores/                  # Zustand 스토어 (서버 데이터 반입 금지)
├── lib/                     # cn() · 포매터 · 순수 유틸
└── types/                   # 여러 기능이 공유하는 타입
```
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
### 1. 서버 데이터는 TanStack Query가 소유한다 — 전역 스토어에 복제하지 않는다

서버 응답을 Zustand에 옮겨 담으면 캐시가 둘이 되고, 무효화·재요청·가비지 컬렉션을 직접
구현하게 된다. Zustand는 서버가 모르는 상태(모달 열림, 사이드바 접힘)만 갖는다.

```tsx
// ✅ 서버 상태는 쿼리, 클라이언트 상태는 스토어
const { data: tasks, isPending } = useTasksQuery(filter);
const isSidebarOpen = useUiStore((s) => s.isSidebarOpen);

// ❌ 서버 응답을 스토어로 옮겨 담는다 — 캐시 이중화
useEffect(() => { fetchTasks().then(setTasksInStore); }, []);
const tasks = useTaskStore((s) => s.tasks);
```

### 2. HTTP는 `src/api/` 계층에서만 — 컴포넌트가 직접 호출하지 않는다

컴포넌트가 직접 `fetch`하면 인증 헤더·에러 정규화·베이스 URL이 화면마다 갈라진다.
이 경계는 규율이 아니라 **lint 규칙으로 강제**한다 (`resources/data-fetching.md` 참고).

```tsx
// ✅ 요청 함수 → 쿼리 훅 → 컴포넌트
export const useTasksQuery = (f: TaskFilter) =>
  useQuery({ queryKey: taskKeys.list(f), queryFn: () => listTasks(f) });

// ❌ 컴포넌트 안의 원시 fetch — 토큰도 에러 형식도 여기서 다시 발명된다
const res = await fetch(`${import.meta.env.VITE_API_BASE_URL}/tasks`);
```

### 3. 반복 UI는 공통 컴포넌트로 추출하되, 만들기 전에 먼저 검색한다

중복의 다수는 추출 실패가 아니라 **탐색 실패**에서 생긴다. 새 공통 컴포넌트를 만들기 전에
`src/components/common/`과 `src/components/layout/`을 반드시 검색한다.

```bash
rg -l "PageShell|EmptyState|DataTable" src/components   # 이름으로
rg -l "rounded-lg border bg-white p-6" src/components    # 클래스 조합으로
```

```tsx
// ✅ 토큰(높이·타이포·여백)은 공통 컴포넌트 한 곳이 소유하고, 사용처는 props로만 제어
<Button size="sm" variant="danger">삭제</Button>

// ❌ 사용처에서 토큰을 덮어써 공통 컴포넌트가 껍데기가 된다
<Button className="h-11 px-6 text-base font-bold">삭제</Button>
```
### 5. 브라우저 번들에 비밀은 없다

`VITE_*` 변수는 빌드 시점에 문자열로 인라인되어 번들에 그대로 남는다. API 키·서명 키·
관리자 자격증명은 전부 API 서버가 보관하고, 프론트는 그 서버의 엔드포인트를 부른다.

```ts
// ✅ 공개해도 되는 값만 노출하고, 읽는 곳은 src/config.ts 하나다
import { config } from '@/config';
const baseUrl = config.apiBaseUrl;          // 공개 URL
const authority = config.oidc.authority;    // 공개 issuer

// ❌ 번들에 그대로 박히는 비밀 — 접두사만 붙였을 뿐 보호되지 않는다
const key = import.meta.env.VITE_DB_PASSWORD;
```

### 6. 모든 데이터 화면은 로딩·빈·에러 3상태를 갖는다

성공 경로만 구현한 화면은 느린 네트워크와 만료된 세션에서 빈 화면이 된다. 3상태는
선택이 아니라 화면의 최소 계약이다.

```tsx
// ✅ 세 갈래를 모두 반환 (목록은 커서 무한 쿼리 — 페이지들을 펴서 쓴다)
if (isPending) return <ListSkeleton rows={5} />;
if (isError) return <ErrorState error={error} onRetry={refetch} />;
const tasks = data.pages.flatMap((p) => p.items);
if (tasks.length === 0) return <EmptyState action={<CreateTaskButton />} />;
return <TaskTable rows={tasks} />;

// ❌ 옵셔널 체이닝으로 세 상태를 뭉갠다 — 에러와 빈 상태가 구분되지 않는다
return <TaskTable rows={data?.pages.flatMap((p) => p.items) ?? []} />;
```
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
```tsx
// React 18
import { useState, useMemo, useCallback, forwardRef, type ReactNode } from 'react';

// 라우팅 (React Router v7 — 'react-router-dom'이 아니라 'react-router')
import { Link, NavLink, Outlet, Navigate, useNavigate, useParams,
         useSearchParams, useLocation, useRouteError, isRouteErrorResponse } from 'react-router';
import { createBrowserRouter, RouterProvider } from 'react-router';

// 서버 상태 (TanStack Query v5)
import { useQuery, useInfiniteQuery, useMutation, useQueryClient, keepPreviousData,
         QueryClient, QueryClientProvider, QueryErrorResetBoundary } from '@tanstack/react-query';

// 클라이언트 전역 상태 (Zustand v5)
import { create } from 'zustand';
import { useShallow } from 'zustand/react/shallow';

// 프로젝트 내부 (이 팩이 소유하는 것만 — HTTP 클라이언트는 이음매가 덧붙인다)
import { config } from '@/config';
import { cn } from '@/lib/cn';
```
<!-- /pack-slot -->

<!-- pack-slot: component-template -->
## Component Template

```tsx
// src/features/tasks/components/TaskCard.tsx
// 기능 컴포넌트이므로 도메인 타입을 안다. components/common/은 반대로 features/를 import하지 않는다
import { forwardRef, type ComponentPropsWithoutRef, type ReactNode } from 'react';
import { cn } from '@/lib/cn';
import { formatDate } from '@/lib/format';
import type { Task } from '../api/tasks.types';

type TaskCardProps = ComponentPropsWithoutRef<'article'> & {
  task: Task;
  /** 액션 영역은 주입받는다 — 공통 컴포넌트가 기능 로직을 알지 않게 한다 */
  actions?: ReactNode;
};

/**
 * 목록의 항목 하나. 데이터 페칭도 라우팅도 하지 않는다 —
 * 필요한 것은 전부 props로 받는다.
 */
export const TaskCard = forwardRef<HTMLElement, TaskCardProps>(
  ({ task, actions, className, ...rest }, ref) => (
    <article
      ref={ref}
      className={cn('rounded-lg border border-slate-200 bg-white p-4', className)}
      {...rest}
    >
      <h3 className="text-sm font-semibold text-slate-900">{task.title}</h3>
      <p className="mt-1 text-xs text-slate-500">{formatDate(task.createdAt)}</p>
      {actions && <div className="mt-3 flex gap-2">{actions}</div>}
    </article>
  ),
);
TaskCard.displayName = 'TaskCard';
```

- React 18에는 ref 자동 전달이 없다 — DOM ref를 노출하려면 `forwardRef`가 필요하다
- 공통 컴포넌트는 `useNavigate`·`useQuery`를 호출하지 않는다 (재사용을 막는다)
- `className`을 마지막에 `cn()`으로 병합해 호출부가 여백만 미세 조정할 수 있게 한다
<!-- /pack-slot -->

## 이음매가 채울 것 — 이 팩에 없는 것

| 허브 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| Architecture Overview | 신뢰 경계와 데이터 출처가 백엔드 축에 달렸다 |
| Quick Start 체크리스트 2개 | 페이지네이션 모델·에러 코드 분기가 와이어 계약에 달렸다 |
| Core Principle "인가는 신뢰 경계가 아니다" | 원칙은 보편이나 **미인가 응답이 403인지 404인지**가 백엔드 축에 달렸다. 이 규칙은 반드시 넣는다 |
| Common Imports의 HTTP 클라이언트·인증 행 | 인증 방식과 봉투 해석이 백엔드 축에 달렸다 |
| Navigation Guide | 팩 리소스 행은 `pack.json`이 제공하고, 이음매 리소스 행은 이음매가 추가한다 |
