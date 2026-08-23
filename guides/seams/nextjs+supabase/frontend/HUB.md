---
name: frontend-guide
description: "[Preset: nextjs-supabase] Next.js App Router frontend development guide. Covers Server/Client Component patterns, Tailwind CSS v4 + shadcn/ui styling, App Router routing, Zustand state management, performance optimization, and TypeScript standards. Use when creating or modifying components, pages, layouts, styling, data fetching, routing, state management, or any frontend code. Use ONLY when the active preset matches."
---
<!-- epcc-guide-baseline: verified 2026-08-21 next@15 react@19 typescript@5 tailwindcss@4 zod@4 @supabase/ssr@0 @supabase/supabase-js@2 zustand@5 react-hook-form@7 @hookform/resolvers@5 class-variance-authority@0 clsx@2 tailwind-merge@3 lucide-react@1 -->

Next.js 15(App Router) + React 19 + TypeScript strict + Tailwind CSS v4 + shadcn/ui
+ Zustand + Supabase(@supabase/ssr) 프론트엔드 표준 가이드.

## Quick Start

### New Component

- [ ] Server Component로 시작 — 상호작용(이벤트·훅·브라우저 API)이 필요할 때만 `'use client'`
- [ ] 배치 결정: 한 라우트 전용이면 `app/<route>/_components/`, 공유면 `components/`
- [ ] 새 공통 컴포넌트를 만들기 전 `components/layout/`·`components/common/`을 grep으로 확인 — 있으면 재사용
- [ ] 같은 UI가 2회 반복되면 추출을 검토하고, 3회면 반드시 공통 컴포넌트로 추출 (Core Principle 3)
- [ ] Props는 `interface XxxProps`로 파일 상단에 정의 (TypeScript strict, `any` 금지)
- [ ] 기존 shadcn/ui 컴포넌트(`components/ui/`)를 먼저 재사용 — 없으면 CLI로 추가
- [ ] 스타일은 Tailwind 유틸리티 + `cn()` 조합, 시맨틱 토큰(`bg-background` 등) 우선
- [ ] 데이터 표시 컴포넌트면 로딩·빈·에러 3상태 처리 확인

### New Page (Route)

- [ ] `app/(main)/<경로>/page.tsx` 생성 — 폴더 구조가 곧 URL (괄호 그룹은 URL에 미포함)
- [ ] 데이터 조회는 Server Component에서 `lib/queries/` 함수 호출로 (컴포넌트 인라인 데이터 쿼리 금지)
- [ ] 인증 확인(`auth.getUser()`)은 예외 — 페이지·레이아웃에서 직접 호출한다 (쿼리 계층 경유 아님)
- [ ] `params`·`searchParams`는 Promise — 반드시 `await` (Next.js 15)
- [ ] `loading.tsx` 또는 `<Suspense>`로 로딩 UI 정의
- [ ] `error.tsx`로 에러 경계 정의 (`'use client'` 필수)
- [ ] 보호 라우트면 `middleware.ts` matcher 포함 확인 + 페이지에서 `getUser()` 재확인
- [ ] `metadata` 또는 `generateMetadata` 정의
- [ ] 형제 라우트와 공유하는 UI는 상위 `layout.tsx`로 추출

## Architecture Overview

```
Browser
  │ 요청
  ▼
middleware.ts ── @supabase/ssr 세션 갱신 + 보호 라우트 1차 게이트
  ▼
Next.js 15 App Router (React 19)
  ├─ Server Component (기본) ──→ lib/queries/* ──→ Supabase (PostgreSQL)
  │      └─ lib/supabase/server.ts (cookie 기반 세션, getUser)
  ├─ Client Component ('use client') ── 이벤트·폼·Zustand 구독
  │      └─ 변이는 Server Action 호출 → revalidatePath → 서버 리렌더
  └─ layout.tsx 계층 ── 라우트 간 공유 UI
```

책임 경계:

- **Server Component**: 데이터 조회, 접근 제어 재확인, 정적 마크업 — 렌더링의 기본형
- **Client Component**: 이벤트 핸들링, 폼 상태, 브라우저 API, Zustand 구독 — 최소 잎 단위
- **Zustand**: 클라이언트 전역 UI 상태 전용 (서버 데이터 복제 금지)
- **Supabase**: 인증(Auth) + 데이터(PostgreSQL). 접근은 `@supabase/ssr` 클라이언트로만
- **Server Action / Route Handler의 내부 로직(검증·권한·에러 설계)**: backend-guide 관할

## Directory Structure

```
app/
├── layout.tsx              # 루트 레이아웃 (globals.css·폰트·Provider)
├── globals.css             # Tailwind v4 진입점 (@import "tailwindcss")
├── (auth)/                 # 라우트 그룹 — URL에 미포함
│   ├── layout.tsx          # 인증 화면 전용 레이아웃 (앱 크롬 없음)
│   └── login/page.tsx      # URL: /login
└── (main)/                 # 앱 본체 그룹
    ├── layout.tsx          # 헤더·사이드바 등 앱 공통 크롬
    ├── page.tsx            # URL: /
    └── tasks/
        ├── page.tsx        # Server Component (데이터 페칭) — URL: /tasks
        ├── loading.tsx     # 라우트 로딩 UI
        ├── error.tsx       # 라우트 에러 경계
        ├── actions.ts      # Server Actions (변이)
        └── _components/    # 이 라우트 전용 컴포넌트 (라우팅 제외)
components/
├── ui/                     # shadcn/ui 생성 컴포넌트 (CLI로 추가)
├── layout/                 # 페이지 골격 공통 (PageHeader·사이드바 등)
├── common/                 # 도메인 무관 재사용 (PageSection·EmptyState 등)
└── <domain>/               # 도메인별 공유 컴포넌트 (여러 라우트에서 쓸 때)
lib/
├── supabase/               # client.ts · server.ts · middleware.ts
├── queries/                # 데이터 조회 함수 (서버 전용, 유일한 조회 진입점)
└── utils.ts                # cn() 등
stores/                     # Zustand 스토어 + Provider
hooks/ · types/ · constants/  # 상세는 resources/file-organization.md
middleware.ts               # 세션 갱신 + 보호 라우트 matcher
```

프로젝트에 실제 구조가 이미 있으면 그것을 우선한다.

## Core Principles (6 Key Rules)

### 1. Server Component가 기본 — `'use client'`는 상호작용 잎에만

```tsx
// Good: 페이지는 서버에서 페칭, 상호작용 부분만 클라이언트
// app/(main)/tasks/page.tsx
export default async function TasksPage() {
  const tasks = await getTasks()
  return <TaskList tasks={tasks} />        // 데이터는 props로 주입
}

// Bad: 페이지 전체를 'use client'로 만들어 서버 페칭 포기
'use client'
export default function TasksPage() { /* useEffect로 페칭… */ }
```

### 2. 서버 데이터는 서버에서 — 컴포넌트의 Supabase 직접 조회 금지

```tsx
// Good: Server Component → lib/queries → props
const tasks = await getTasks()             // lib/queries/tasks.ts 경유

// Bad: 클라이언트 컴포넌트에서 직접 조회
useEffect(() => {
  createClient().from('tasks').select()... // 경계 위반
}, [])
```

예외는 두 가지뿐이다. ① 인증 확인 — `auth.getUser()`는 페이지·레이아웃·액션에서 직접 호출한다
(쿼리 계층 경유 대상이 아니다). ② 클라이언트의 realtime 구독·인증 상태 UI.
resources/data-fetching.md 참조.

### 3. 반복 UI는 공통 컴포넌트·레이아웃으로 추출 (2회 검토 · 3회 필수)

```tsx
// Bad: 같은 섹션 골격을 페이지마다 복사 (3번째 중복)
<div className="rounded-xl border bg-card p-6">
  <h2 className="mb-4 text-lg font-semibold">Tasks</h2>…</div>

// Good: 차이는 props로, 골격은 한 곳에
<PageSection title="Tasks">{children}</PageSection>
```

라우트 전체가 공유하는 틀(헤더·네비)은 `layout.tsx`로 — resources/component-patterns.md 참조.

### 4. 요청 API는 Promise — `params`·`searchParams`·`cookies()`는 await

```tsx
// Good (Next.js 15)
export default async function Page({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params
}

// Bad: 동기 접근 (구버전 방식 — 타입 에러)
export default function Page({ params }: { params: { id: string } }) {
  const id = params.id
}
```

### 5. 상태는 계층으로 — 서버 상태는 props, 전역 클라이언트 상태만 Zustand

```tsx
// Good: 필요한 조각만 selector로 구독
const open = useUiStore((s) => s.sidebarOpen)

// Bad: 스토어 전체 구독(모든 변경에 리렌더) + 서버 데이터를 스토어에 복제
const store = useUiStore((s) => s)
```

로컬은 `useState`, URL 공유 상태는 `searchParams` — resources/state-management.md 참조.

### 6. 스타일은 Tailwind 유틸리티 + `cn()` — 인라인 style·개별 CSS 파일 금지

```tsx
// Good: 조건부 클래스는 cn()으로 조합
<div className={cn('rounded-lg border p-4', isActive && 'border-primary')} />

// Bad: 인라인 style + 전역 CSS에 커스텀 클래스 추가
<div style={{ borderRadius: 8, padding: 16 }} className="custom-card" />
```

## Common Imports

```tsx
// ── 서버 코드 (Server Component · Server Action)
import { createClient } from '@/lib/supabase/server'
import { cookies, headers } from 'next/headers'
import { revalidatePath } from 'next/cache'
import { redirect, notFound } from 'next/navigation'
import { cache } from 'react'

// ── 클라이언트 컴포넌트 ('use client' 파일)
import { useState, useActionState, useOptimistic, useTransition } from 'react'
import { useRouter, usePathname, useSearchParams } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'
import { useUiStore } from '@/stores/ui-store-provider'

// ── 공용 UI
import Link from 'next/link'
import Image from 'next/image'
import { cn } from '@/lib/utils'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Skeleton } from '@/components/ui/skeleton'
```

## Component Templates

### Server Component (기본형)

```tsx
import { getTasks } from '@/lib/queries/tasks'

export async function TasksPanel() {
  const tasks = await getTasks()             // RLS가 본인 행만 반환 — userId 인자 불필요
  if (tasks.length === 0) return <p className="text-sm text-muted-foreground">아직 항목이 없습니다.</p>
  return <ul className="space-y-2">{tasks.map((t) => <li key={t.id}>{t.title}</li>)}</ul>
}
```

### Client Component (상호작용형)

```tsx
'use client'

import { useState } from 'react'
import { cn } from '@/lib/utils'

interface ToggleChipProps { label: string; onToggle?: (on: boolean) => void }

export function ToggleChip({ label, onToggle }: ToggleChipProps) {
  const [on, setOn] = useState(false)
  const handleClick = () => { setOn(!on); onToggle?.(!on) }
  return (
    <button onClick={handleClick} className={cn('rounded-full border px-3 py-1 text-sm', on && 'bg-primary text-primary-foreground')}>
      {label}
    </button>
  )
}
```

## Navigation Guide

| 하려는 일 | 읽을 파일 |
| --- | --- |
| 컴포넌트 생성, Server/Client 경계 결정, props 설계 | resources/component-patterns.md |
| 반복 UI 추출, 공통 레이아웃(PageHeader)·섹션 컴포넌트 | resources/component-patterns.md |
| 로딩·빈·에러 3상태 처리 (스켈레톤·에러 경계) | resources/component-patterns.md |
| 데이터 페칭, 쿼리 계층(lib/queries), 캐싱·재검증, 변이 후 갱신 | resources/data-fetching.md |
| 서버 측 검색·필터·페이지네이션(count·range), 낙관적 UI(useOptimistic) | resources/data-fetching.md |
| 페이지·레이아웃 추가, 동적 라우트, 보호 라우트, 인증 조건부 헤더, metadata | resources/routing.md |
| 클라이언트 상태 설계, Zustand 스토어·Provider·persist, RHF+Zod 폼 경계 | resources/state-management.md |
| URL 상태(searchParams 읽기·쓰기), 버튼형 변이의 pending 처리(useTransition) | resources/state-management.md |
| 스타일링, Tailwind v4 토큰, shadcn/ui 추가·변형(CVA), 다크 모드 | resources/styling.md |
| 이미지·dynamic import·메모이제이션·디바운스 등 성능 최적화 | resources/performance.md |
| 타입 설계, any 제거, 유틸리티 타입, null 처리, 네이밍 | resources/typescript-standards.md |
| 보호 라우트, 미들웨어 세션 갱신, 서버에서 현재 사용자 읽기 | resources/auth-and-session.md |
| 파일 배치·파일명 규칙, 디렉토리 구조, import 순서, export 방식, 파일 내부 작성 순서 | resources/file-organization.md |
| 기능 하나를 처음부터 끝까지 (목록 + 생성 관통 예제) | resources/complete-example.md |
