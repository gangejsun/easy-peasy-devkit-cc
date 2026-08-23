<!-- epcc-pack: frontend/nextjs v3.12.0 -->
# Routing

App Router 라우트 정의·중첩 레이아웃·내비게이션·metadata. 보호 라우트와 세션 갱신은 `resources/auth-and-session.md`.

## 1. 파일 컨벤션

| 파일 | 역할 |
| --- | --- |
| `page.tsx` | 라우트의 UI — 이 파일이 있어야 URL로 접근 가능 |
| `layout.tsx` | 하위 세그먼트를 감싸는 공유 UI — 내비게이션 간 리렌더되지 않음 |
| `loading.tsx` | 세그먼트 로딩 UI (자동 Suspense 경계) |
| `error.tsx` | 세그먼트 에러 경계 (`'use client'` 필수) |
| `not-found.tsx` | `notFound()` 호출 시 표시되는 UI |
| `template.tsx` | layout과 같지만 내비게이션마다 재마운트 (진입 애니메이션 등) |
| `route.ts` | Route Handler (API) — backend-guide 관할 |

## 2. 동적 라우트 — `params`·`searchParams`는 Promise

```tsx
// app/(main)/tasks/[id]/page.tsx — URL: /tasks/<id>
import { notFound } from 'next/navigation'
import { getTask } from '@/lib/queries/tasks'

interface PageProps {
  params: Promise<{ id: string }>
  searchParams: Promise<{ [key: string]: string | string[] | undefined }>
}

export default async function TaskDetailPage({ params }: PageProps) {
  const { id } = await params            // Next.js 15: 반드시 await
  const task = await getTask(id)
  if (!task) notFound()
  return <TaskDetail task={task} />
}
```

- `[id]` — 단일 세그먼트, `[...slug]` — catch-all, `[[...slug]]` — 옵셔널 catch-all
- 존재하지 않는 리소스는 `notFound()` 호출 → 가장 가까운 `not-found.tsx` 표시

## 3. 라우트 그룹과 프라이빗 폴더

```
app/
├── (auth)/                        # 괄호 = URL에 미포함, 그룹별 layout 분리용
│   ├── layout.tsx                 # 인증 전용 레이아웃 (앱 크롬 없음)
│   └── login/page.tsx             # URL: /login
└── (main)/
    ├── layout.tsx                 # 앱 전용 레이아웃 (헤더·사이드바)
    └── tasks/
        ├── page.tsx               # URL: /tasks
        └── _components/           # 밑줄 접두사 = 라우팅에서 제외 (콜로케이션용)
```

- 라우트 그룹 `(name)`: URL 구조를 바꾸지 않고 레이아웃 경계를 나눈다
- 프라이빗 폴더 `_name`: 라우트 전용 컴포넌트·유틸을 라우트 옆에 두되 URL에서 제외

## 4. 중첩 레이아웃

```tsx
// app/(main)/layout.tsx — (main) 그룹의 모든 페이지가 공유
import { AppSidebar } from '@/components/layout/app-sidebar'
import { AppHeader } from '@/components/layout/app-header'

export default function MainLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <AppSidebar />
      <div className="flex-1">
        <AppHeader />
        {children}
      </div>
    </div>
  )
}
```

- 레이아웃은 중첩된다: 루트 layout → 그룹 layout → 페이지
- 레이아웃은 내비게이션 간 상태를 유지하고 리렌더되지 않는다 —
  현재 페이지에 의존하는 UI(활성 메뉴 강조)는 `usePathname`을 쓰는 클라이언트 잎으로 분리

### 인증 조건부 헤더 — 서버에서 분기한다

로그인 여부에 따라 사용자 메뉴/로그인 버튼을 가르는 헤더는 **Server Component**로 만든다.
클라이언트에서 세션을 조회하면 첫 렌더에 로그인 버튼이 잠깐 보였다가 바뀐다(깜빡임).

```tsx
// components/layout/app-header.tsx (Server Component — 'use client' 없음)
import Link from 'next/link'
import { getCurrentUser } from '@/lib/auth'    // 인증 계층 — 백엔드 축이 구현한다
import { Button } from '@/components/ui/button'
import { UserMenu } from './user-menu'          // 'use client' — 드롭다운·로그아웃 버튼

export async function AppHeader() {
  const user = await getCurrentUser()          // 서버에서 확인 — 클라이언트 조회는 깜빡임을 만든다

  return (
    <header className="flex h-14 items-center justify-between border-b px-4">
      <Link href="/" className="font-semibold">Tasks</Link>
      {user ? (
        <UserMenu email={user.email ?? ''} />                {/* 직렬화 가능한 값만 전달 */}
      ) : (
        <Button asChild size="sm"><Link href="/login">로그인</Link></Button>
      )}
    </header>
  )
}
```

- `user` 객체 전체를 클라이언트로 넘기지 말고 필요한 필드만 props로 내린다
- 역할·권한 표시는 `user.user_metadata`가 아니라 서버에서 조회한 프로필 행을 근거로 한다
  (`user_metadata`는 사용자가 수정할 수 있다 — 권한 판정 금지, backend-guide 관할)

## 5. 내비게이션

```tsx
// 선언적 이동 — 기본
<Link href="/tasks" className="underline-offset-4 hover:underline">Tasks</Link>

// 클라이언트 컴포넌트에서 프로그래매틱 이동
const router = useRouter()
router.push('/tasks')       // 히스토리 추가
router.replace('/login')    // 히스토리 대체
router.refresh()            // 현재 라우트의 서버 컴포넌트 재실행

// 서버 코드(Server Component·Server Action)에서
redirect('/login')          // throw 기반 — 호출 이후 코드는 실행되지 않음
```

- `<a>` 태그로 내부 이동 금지 — 항상 `<Link>`
- 현재 경로는 `usePathname()`, 쿼리는 `useSearchParams()` (둘 다 클라이언트 훅)

## 6. Metadata

```tsx
// 정적
import type { Metadata } from 'next'

export const metadata: Metadata = {
  title: 'Tasks',
  description: '할 일 목록',
}

// 동적 — 데이터 기반
export async function generateMetadata({ params }: PageProps): Promise<Metadata> {
  const { id } = await params
  const task = await getTask(id)
  return { title: task?.title ?? 'Task' }
}
```

- 루트 `layout.tsx`에 `title.template`(`'%s | 서비스명'`)을 두면 페이지는 title만 채우면 된다
