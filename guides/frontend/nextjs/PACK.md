<!-- epcc-pack: frontend/nextjs v3.12.0 verified 2026-08-21 next@15 react@19 typescript@5 tailwindcss@4 zod@4 zustand@5 react-hook-form@7 @hookform/resolvers@5 class-variance-authority@0 clsx@2 tailwind-merge@3 lucide-react@1 -->

# nextjs 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가
있는 조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

> **이 축의 특징**: Next.js는 **서버 런타임을 내장**한다. 백엔드 축이 BaaS여도 서버 코드는
> 여기(Route Handlers·Server Actions)에 산다. 이음매를 만들 때 이 값을 백엔드 쪽에
> 반드시 전달한다 — 핸들러가 어디 사는지가 백엔드 가이드 전체의 전제다.

<!-- pack-slot: quick-start-axis -->
### New Component

- [ ] Server Component로 시작 — 상호작용(이벤트·훅·브라우저 API)이 필요할 때만 `'use client'`
- [ ] 배치 결정: 한 라우트 전용이면 `app/<route>/_components/`, 공유면 `components/`
- [ ] 새 공통 컴포넌트를 만들기 전 `components/layout/`·`components/common/`을 grep으로 확인 — 있으면 재사용
- [ ] 같은 UI가 2회 반복되면 추출을 검토하고, 3회면 반드시 공통 컴포넌트로 추출 (Core Principle 3)
- [ ] Props는 `interface XxxProps`로 파일 상단에 정의 (TypeScript strict, `any` 금지)
- [ ] 기존 shadcn/ui 컴포넌트(`components/ui/`)를 먼저 재사용 — 없으면 CLI로 추가
- [ ] 스타일은 Tailwind 유틸리티 + `cn()` 조합, 시맨틱 토큰(`bg-background` 등) 우선
- [ ] 데이터 표시 컴포넌트면 로딩·빈·에러 3상태 처리 확인

<!-- /pack-slot -->

<!-- pack-slot: directory-structure -->
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

<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
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

<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
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

<!-- /pack-slot -->

<!-- pack-slot: component-templates -->
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

<!-- /pack-slot -->

## 이음매가 채울 것 — 이 팩에 없는 것

| 허브 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| Architecture Overview | 데이터 출처와 신뢰 경계가 백엔드 축에 달렸다 |
| Quick Start "New Page (Route)" | 페이지가 데이터를 어떻게 가져오는지가 백엔드 축에 달렸다 |
| Core Principle "서버 데이터는 서버에서" | 원칙은 보편이나 **무엇을 직접 조회하면 안 되는가**(BaaS SDK·REST 클라이언트)가 백엔드 축에 달렸다. 이 규칙은 반드시 넣는다 |
| Common Imports의 데이터 액세스·인증 행 | 클라이언트 생성 방식이 백엔드 축에 달렸다 |
| Navigation Guide | 팩 리소스 행은 `pack.json`이 제공한다 |
