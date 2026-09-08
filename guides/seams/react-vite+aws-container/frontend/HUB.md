---
name: frontend-guide
description: "[Preset: react-vite × aws-container] React 18 + Vite 5 SPA frontend guide covering common-layout extraction, TanStack Query v5 server state, Zustand client state, React Router v7 protected routes, Tailwind styling, and OIDC/Cognito tokens and 401 handling. Use when creating or modifying components, pages, layouts, styling, routing, REST API clients, data fetching, caching, state, or auth/session code. Use ONLY when the active preset matches."
---
<!-- epcc-guide-baseline: verified 2026-08-22 react@18 vite@5 typescript@5 react-router@7 @tanstack/react-query@5 zustand@5 tailwindcss@3.4 react-oidc-context@3 oidc-client-ts@3 react-error-boundary@6 sonner@2 msw@2 vitest@3 clsx@2 tailwind-merge@2 eslint-plugin-import@2 -->

# React + Vite SPA Frontend Guide

이 가이드는 **브라우저에서만 실행되는 SPA**를 다룬다. 서버 런타임이 없으므로 모든 데이터는
자체 운영 REST API에서 HTTP로 가져오고, 번들에 들어간 모든 것은 공개된다고 가정한다.

## Quick Start

### 새 화면(라우트) 추가

- [ ] `src/components/common/`과 `src/components/layout/`을 **먼저 검색**해 재사용할 셸·폼·테이블을 확인
- [ ] `src/routes/routes.tsx`의 라우트 객체 트리에 경로 추가 — 인증이 필요하면 `RequireAuth` 하위에 중첩
- [ ] 화면 컴포넌트는 `src/features/<feature>/pages/`에 두고 라우트의 `lazy`로 코드 분할
- [ ] 데이터는 `src/features/<feature>/api/`의 쿼리 훅으로만 가져온다 (컴포넌트 안에서 `fetch` 금지)
- [ ] 로딩·빈·에러 3상태를 모두 렌더링 (`isPending` / 항목 0건 / `isError`)
- [ ] 권한에 따라 UI를 숨겼다면, 서버의 **403·404** 응답 처리도 함께 구현 (숨김은 UX일 뿐이다)
- [ ] 스타일은 Tailwind 유틸리티로 작성하고, 같은 조합이 세 번째 반복되면 공통 컴포넌트로 승격
- [ ] `npm run typecheck && npm run lint && npm run test` 통과 확인

### 새 API 연동(쿼리/뮤테이션) 추가

- [ ] 백엔드의 요청/응답 계약을 확인하고 `src/features/<f>/api/tasks.types.ts`에 타입 + 좁히기 함수 선언
- [ ] 요청 함수는 `src/api/http.ts`의 공용 클라이언트만 사용 (URL·인증 헤더 직접 조립 금지)
- [ ] 쿼리 키를 `<feature>Keys` 팩토리에 추가 (문자열 리터럴을 화면에 흩뿌리지 않는다)
- [ ] 목록은 커서 페이지네이션 — `useInfiniteQuery`(`initialPageParam`·`getNextPageParam`).
      `page`/`total`은 백엔드에 없다
- [ ] 쓰기는 `useMutation` — 훅 이름은 `use<Thing>Query` / `use<Thing>Mutation`
- [ ] 뮤테이션 `onSuccess`에서 영향받는 키를 `invalidateQueries({ queryKey })`로 무효화
- [ ] 에러는 `error.code`로 분기 (`UNAUTHORIZED`는 세션, `FORBIDDEN`/`NOT_FOUND`는 인가,
      `VALIDATION_FAILED`는 `details`의 필드 메시지)
- [ ] `staleTime`을 데이터 성격에 맞게 지정 (기본 0은 화면에 복귀할 때마다 재요청한다)
- [ ] 비밀·서명 로직이 프론트에 들어가지 않았는지 확인 (`VITE_*`는 전부 공개 값이다)

## Architecture Overview

```
[Browser SPA]  React 18 · Vite 5 번들 · 정적 호스팅         ← 신뢰할 수 없는 실행 환경
      │ HTTPS + Authorization: Bearer <access_token>
      ▼
[REST API]     Hono on ECS/Fargate · ALB 뒤                 ← 유일한 신뢰 경계
      ├── 인증 검증(JWT 서명·issuer·audience·만료)
      ├── 인가 강제(소유권·역할) — 미인가는 404로 응답        ← 프론트엔드는 이걸 흉내만 낸다
      └── Drizzle ORM → RDS PostgreSQL
      ▲
[OIDC Issuer]  Cognito (표준 OIDC) — Authorization Code + PKCE
```

정적 호스팅은 **모든 미매칭 경로를 `index.html`로 되돌려야** 한다. 이 설정이 없으면
새로고침·딥링크·`/auth/callback`이 전부 404가 된다 (`resources/routing.md` §6).

| 관심사 | 소유자 | 프론트엔드의 역할 |
| --- | --- | --- |
| 비즈니스 규칙·검증 | API 서버 | 같은 규칙을 UX용으로 미리 보여줄 뿐, 최종 판정은 서버 응답 |
| 인가(누가 무엇을) | API 서버 | 버튼 숨김·라우트 게이트 = 편의. 403·404를 반드시 처리 |
| 세션·토큰 발급 | OIDC Issuer | 토큰 보관·첨부·갱신·폐기 |
| 서버 데이터 캐시 | TanStack Query | 단일 캐시. 다른 곳에 복제하지 않는다 |
| 화면 상태 | Zustand / URL / `useState` | 서버가 모르는 상태만 |

**서버 코드가 없다**는 점이 이 스택의 전제다. "서버에서만 실행되는 모듈"이라는 도피처가
없으므로, 비밀·서명·정책 판정은 전부 API 서버로 밀어내는 것 외에 선택지가 없다.

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

## Core Principles (6 Key Rules)

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

### 4. 인가는 신뢰 경계가 아니다 — 숨기는 것은 UX, 막는 것은 서버

번들은 누구나 내려받아 읽을 수 있고, 라우트 게이트는 콘솔에서 우회된다. UI 게이트는
"실수로 누르지 않게" 하는 장치이며, 실제 권한은 매 요청마다 API가 판정한다.

```tsx
// ✅ 숨기되, 서버 판정을 신뢰하고 실패 응답을 처리한다
{canDelete && <Button onClick={remove}>삭제</Button>}
// mutation.onError: toast.error(toUserMessage(e));
// 이 백엔드는 **남의 리소스를 404로** 돌려준다(존재 누설 방지). 403은 역할 부족에만 온다

// ❌ 토큰 클레임만 보고 "권한 검사를 마쳤다"고 간주 — 서버가 다시 확인하지 않으면 무방비
if (jwtDecode(token).role === 'admin') await http.delete(`/tasks/${id}`);
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

## Common Imports

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

// 인증 (OIDC 표준 — 특정 IdP SDK가 아니다)
import { AuthProvider, useAuth } from 'react-oidc-context';
import { UserManager, WebStorageStateStore, InMemoryWebStorage } from 'oidc-client-ts';

// 에러 바운더리 · 토스트 (패키지를 고정한다 — 화면마다 다른 것을 쓰지 않는다)
import { ErrorBoundary } from 'react-error-boundary';
import { toast } from 'sonner';

// 프로젝트 내부
import { http, ApiError, type Page } from '@/api/http';
import { config } from '@/config';
import { cn } from '@/lib/cn';
```

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

## Navigation Guide

| 하려는 일 | 읽을 파일 |
| --- | --- |
| 컴포넌트 만들기 · 반복 UI를 공통으로 추출 · 디자인 토큰 소유 규칙 | `resources/component-patterns.md` |
| 목록/상세 데이터 가져오기 · 쿼리 키 · 캐시 무효화 · API 클라이언트 | `resources/data-fetching.md` |
| HTTP 호출 경계를 lint로 강제하기 | `resources/data-fetching.md` |
| 라우트 추가 · 중첩 레이아웃 · 보호 라우트 · 로그인/콜백 화면 · 딥링크(history fallback) | `resources/routing.md` |
| 전역 상태 도입 여부 판단 · Zustand 스토어 작성 · 구독 최적화 | `resources/state-management.md` |
| Tailwind 클래스 작성 · 변형(variant) 정의 · 금지 패턴 | `resources/styling.md` |
| 로딩 스켈레톤 · 빈 상태 · 에러 바운더리 · 에러 분류 | `resources/loading-error-states.md` |
| 로그인/로그아웃 · 토큰 보관 · 401 처리 · 캐시 정리 · issuer 교체 | `resources/auth-and-session.md` |
| TypeScript 설정 · API 타입 좁히기 · 환경변수 타입 | `resources/types-and-testing.md` |
| 컴포넌트/훅 테스트 · HTTP 모킹 · 스토어 초기화 | `resources/types-and-testing.md` |
| 기능 하나를 목록 조회 + 생성까지 처음부터 끝까지 | `resources/complete-example.md` |
