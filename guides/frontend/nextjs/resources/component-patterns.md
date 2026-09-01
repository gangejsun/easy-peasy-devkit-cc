<!-- epcc-pack: frontend/nextjs v3.12.0 -->
# Component Patterns

컴포넌트 설계 표준: Server/Client 경계, 반복 UI 추출, props 컨벤션,
그리고 로딩·빈·에러 3상태 처리(이 파일에 병합).

## 1. Server / Client 결정 기준

| 필요한 것 | 종류 |
| --- | --- |
| 데이터 조회, 세션 확인, 정적 마크업 | Server Component (기본) |
| `onClick` 등 이벤트 핸들러 | Client Component |
| `useState` / `useActionState` 등 훅 | Client Component |
| 브라우저 API (localStorage, IntersectionObserver…) | Client Component |
| Zustand 스토어 구독 | Client Component |

원칙: **기본은 서버.** `'use client'`는 상호작용이 실제로 일어나는
최소 단위(잎 컴포넌트)에만 선언한다. 페이지·레이아웃 파일에는 원칙적으로 붙이지 않는다.

## 2. 경계 설계 패턴

### `'use client'`는 전이된다

`'use client'` 파일이 import하는 모든 모듈은 클라이언트 번들에 포함된다.
`next/headers`를 쓰는 서버 코드(데이터 클라이언트 모듈 등)는 클라이언트 컴포넌트에서
import하면 빌드 에러가 나지만, **일반 서버 코드는 에러 없이 조용히 번들될 수 있다** —
서버 전용 모듈(`lib/queries/` 등)은 파일 상단에 `import 'server-only'`를 선언해
실수를 빌드 에러로 승격시킨다. 서버 데이터는 항상 **props로** 넘긴다.

### Server Component를 children으로 통과시키기

클라이언트 래퍼가 필요해도 내부 콘텐츠는 서버에 남길 수 있다.

```tsx
// app/(main)/tasks/page.tsx (Server Component)
<CollapsiblePanel title="Tasks">
  <TaskList tasks={tasks} />   {/* Server Component인 채로 통과 */}
</CollapsiblePanel>
```

<!-- file: components/common/collapsible-panel.tsx -->
```tsx
// components/common/collapsible-panel.tsx (Client Component)
'use client'

import { useState } from 'react'

interface CollapsiblePanelProps {
  title: string
  children: React.ReactNode
}

export function CollapsiblePanel({ title, children }: CollapsiblePanelProps) {
  const [open, setOpen] = useState(true)
  return (
    <section className="rounded-xl border">
      <button onClick={() => setOpen((o) => !o)} className="w-full p-4 text-left font-semibold">
        {title}
      </button>
      {open && <div className="border-t p-4">{children}</div>}
    </section>
  )
}
```

### 경계를 넘는 props는 직렬화 가능해야 한다

Server → Client로는 JSON 직렬화 가능한 값과 Server Action 참조만 전달한다.
일반 함수·클래스 인스턴스·데이터 클라이언트 객체는 전달 금지.

## 3. 반복 UI 추출 (2회 검토 · 3회 필수) — 필수 규칙의 심화

같은 마크업 패턴이 **2회 등장하면 추출을 검토하고, 3회면 반드시 추출**한다.
추출 목적지는 반복의 범위로 결정한다.

| 반복 범위 | 목적지 |
| --- | --- |
| 한 라우트 내부 | `app/<route>/_components/` |
| 페이지 골격 공통 (헤더·컨테이너·하단 액션바) | `components/layout/` — `PageHeader`, `PageContainer`, `BottomActionBar` |
| 도메인 무관 본문 UI (섹션 골격, 빈 상태, 카드) | `components/common/` — `PageSection`, `EmptyState` |
| 특정 도메인의 공유 컴포넌트 (여러 라우트에서 사용) | `components/<domain>/` |
| 라우트 세그먼트 전체의 공통 틀 (네비·사이드바 배치) | 해당 세그먼트의 `layout.tsx` |
| 원시 UI 요소 (버튼·입력·다이얼로그) | shadcn/ui 재사용 (`components/ui/`) |

```tsx
// Bad: 페이지마다 반복되는 섹션 골격 (3번째 복사-붙여넣기)
<div className="rounded-xl border bg-card p-6">
  <div className="mb-4 flex items-center justify-between">
    <h2 className="text-lg font-semibold">Tasks</h2>
    <Button size="sm">추가</Button>
  </div>
  …
</div>
```

```tsx
// Good: 골격은 한 곳에, 차이는 props로
// components/common/page-section.tsx (Server Component — 훅 불필요)
interface PageSectionProps {
  title: string
  action?: React.ReactNode
  children: React.ReactNode
}

export function PageSection({ title, action, children }: PageSectionProps) {
  return (
    <section className="rounded-xl border bg-card p-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-lg font-semibold">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  )
}
```

추출 시 규칙:

- 변형이 필요하면 boolean props 증식(`isSmall`, `isDanger`…) 대신
  `variant` prop 하나로 통제한다 (CVA 패턴 — resources/styling.md)
- 공통 레이아웃(`layout.tsx`)은 내비게이션 간 리렌더되지 않는다 —
  페이지 상태에 의존하는 UI는 layout이 아니라 page 쪽에 둔다
- 2회 미만 반복을 미리 추상화하지 않는다 (사변적 일반화 금지)

### 공통 레이아웃 시스템 — PageHeader

상세/설정/프로필 같은 sub 페이지의 상단 헤더(뒤로가기 + 타이틀)는 대표적인 반복 UI다.
**새 공통 컴포넌트를 만들기 전에 `components/layout/`·`components/common/`을
grep으로 확인한다** — 이미 있으면 재사용하고, 없을 때만 추가한다.

<!-- file: components/layout/page-header.tsx -->
```tsx
// components/layout/page-header.tsx
import { ChevronLeft } from 'lucide-react'
import Link from 'next/link'

interface PageHeaderProps {
  title: string
  backHref?: string
  rightSlot?: React.ReactNode
}

export function PageHeader({ title, backHref, rightSlot }: PageHeaderProps) {
  return (
    <header className="sticky top-0 z-10 flex h-14 items-center justify-between border-b bg-background px-4">
      {backHref ? (
        <Link href={backHref} aria-label="뒤로가기">
          <ChevronLeft className="h-6 w-6" />
        </Link>
      ) : (
        <span className="w-6" />
      )}
      <h1 className="text-base font-semibold">{title}</h1>
      <div className="w-6">{rightSlot}</div>
    </header>
  )
}
```

```tsx
// 사용처: 모든 sub 페이지가 동일 인터페이스를 공유한다
<PageHeader title="할 일" backHref="/tasks" />
<PageHeader title="설정" backHref="/" rightSlot={<SaveButton />} />
```

```tsx
// Bad: 같은 헤더를 페이지마다 인라인 복제 —
// 높이·폰트가 페이지마다 어긋나기 시작한다 (h-12/h-14/h-16, text-lg/text-base 혼재)
<header className="sticky top-0 …">
  <Link href="/tasks"><ChevronLeft /></Link>
  <h1 className="text-lg font-semibold">할 일</h1>
</header>
```

디자인 토큰 일관성:

- 헤더 높이·타이틀 폰트·여백(`h-14`, `text-base font-semibold` 등)은
  **PageHeader 한 곳에서만** 정의한다 — 페이지는 props로만 제어
- 추가 토큰이 필요하면(예: 모바일 헤더 전용 높이) 디자인 시스템 산출물
  (`dev/docs/design/`, ui-ux-design 스킬 생성)과 정합해야 한다

## 4. Props·타입 컨벤션

- Props 타입은 `interface XxxProps`로 컴포넌트 파일 상단에 선언 — export는 재사용될 때만
- `children`은 `React.ReactNode`
- 서버 데이터의 타입은 `lib/queries/`가 export하는 타입을 import해 재사용 (중복 정의 금지)
- 이벤트 핸들러 prop은 `onXxx`, 내부 핸들러는 `handleXxx`
- React 19: `ref`는 일반 prop이다 — `forwardRef` 래핑 불필요

```tsx
interface SearchInputProps {
  defaultValue?: string
  ref?: React.Ref<HTMLInputElement>   // React 19: ref as prop
  onSearch: (query: string) => void
}

export function SearchInput({ defaultValue, ref, onSearch }: SearchInputProps) {
  // …
}
```

## 5. 로딩·빈·에러 3상태

데이터를 표시하는 모든 화면은 **로딩·빈·에러** 3가지 상태를 처리해야 완성이다.

### 로딩 — 라우트 단위는 `loading.tsx`, 부분 단위는 `<Suspense>`

```tsx
// app/(main)/tasks/loading.tsx — 라우트 전환 시 자동 표시 (자동 Suspense 경계)
import { Skeleton } from '@/components/ui/skeleton'

export default function TasksLoading() {
  return (
    <div className="space-y-3 p-6">
      <Skeleton className="h-8 w-40" />
      <Skeleton className="h-24 w-full" />
      <Skeleton className="h-24 w-full" />
    </div>
  )
}
```

- 스켈레톤은 실제 콘텐츠의 형태를 닮게 만든다 (스피너 단독 사용 지양)
- 페이지 일부만 느리면 그 부분을 별도 서버 컴포넌트로 분리해
  `<Suspense fallback={…}>`로 감싼다 — resources/data-fetching.md의 스트리밍 절 참조

### 빈 상태 — "0건"은 에러가 아니다

빈 상태는 화면마다 반복되는 대표적 UI다 — §3의 규칙대로 `components/common/`에 추출한다.

<!-- file: components/common/empty-state.tsx -->
```tsx
// components/common/empty-state.tsx (Server Component — 훅 불필요)
interface EmptyStateProps {
  title: string
  description?: string
  action?: React.ReactNode        // 다음 행동 유도 버튼·링크
}

export function EmptyState({ title, description, action }: EmptyStateProps) {
  return (
    <div className="rounded-lg border border-dashed p-8 text-center">
      <p className="text-sm text-muted-foreground">{title}</p>
      {description && <p className="mt-1 text-xs text-muted-foreground">{description}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  )
}
```

```tsx
// 사용처: 조기 반환으로 빈 상태를 먼저 처리한다
if (tasks.length === 0) {
  return <EmptyState title="아직 등록된 항목이 없습니다." description="위 폼에서 첫 항목을 추가해 보세요." />
}
```

빈 상태에는 다음 행동 안내(첫 항목 추가 유도 등)를 함께 표시한다 — `description`이나 `action`이 그 자리다.

### 에러 — `error.tsx` 경계

```tsx
// app/(main)/tasks/error.tsx — 이 세그먼트에서 throw된 에러를 잡는다
'use client'

import { Button } from '@/components/ui/button'

interface TasksErrorProps {
  error: Error & { digest?: string }
  reset: () => void
}

export default function TasksError({ error, reset }: TasksErrorProps) {
  return (
    <div className="p-8 text-center">
      <p className="text-sm text-destructive">목록을 불러오지 못했습니다.</p>
      <Button variant="outline" onClick={reset} className="mt-4">
        다시 시도
      </Button>
    </div>
  )
}
```

- `error.tsx`는 반드시 `'use client'`
- 쿼리 함수는 에러를 throw한다 → 가장 가까운 `error.tsx`가 잡는다 (컴포넌트 내 try/catch 지양)
- **폼 제출 에러는 경계로 보내지 않는다** — `useActionState`의 반환값으로
  인라인 표시한다 (resources/data-fetching.md의 변이 절 참조)
