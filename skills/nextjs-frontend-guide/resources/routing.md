# Routing

App Router 라우트 정의·중첩 레이아웃·보호 라우트·metadata.

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
// app/tasks/[id]/page.tsx
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
├── (marketing)/          # 괄호 = URL에 미포함, 그룹별 layout 분리용
│   ├── layout.tsx        # 마케팅 전용 레이아웃 (예: 랜딩 헤더)
│   └── about/page.tsx    # URL: /about
├── (app)/
│   ├── layout.tsx        # 앱 전용 레이아웃 (예: 사이드바)
│   └── tasks/page.tsx    # URL: /tasks
└── tasks/_components/    # 밑줄 접두사 = 라우팅에서 제외 (콜로케이션용)
```

- 라우트 그룹 `(name)`: URL 구조를 바꾸지 않고 레이아웃 경계를 나눈다
- 프라이빗 폴더 `_name`: 라우트 전용 컴포넌트·유틸을 라우트 옆에 두되 URL에서 제외

## 4. 중첩 레이아웃

```tsx
// app/(app)/layout.tsx — (app) 그룹의 모든 페이지가 공유
import { AppSidebar } from '@/components/layout/app-sidebar'

export default function AppLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex min-h-screen">
      <AppSidebar />
      <div className="flex-1">{children}</div>
    </div>
  )
}
```

- 레이아웃은 중첩된다: 루트 layout → 그룹 layout → 페이지
- 레이아웃은 내비게이션 간 상태를 유지하고 리렌더되지 않는다 —
  현재 페이지에 의존하는 UI(활성 메뉴 강조)는 `usePathname`을 쓰는 클라이언트 잎으로 분리

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

## 6. 보호 라우트 (Supabase Auth)

3중 방어: **미들웨어(1차 게이트) → 페이지 재확인 → RLS(최종 방어선, backend-guide)**.

```ts
// middleware.ts (프로젝트 루트)
import { type NextRequest } from 'next/server'
import { updateSession } from '@/lib/supabase/middleware'

export async function middleware(request: NextRequest) {
  return await updateSession(request)
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)'],
}
```

```ts
// lib/supabase/middleware.ts — 세션 갱신 + 미로그인 리다이렉트
import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'

export async function updateSession(request: NextRequest) {
  let supabaseResponse = NextResponse.next({ request })

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll()
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
          supabaseResponse = NextResponse.next({ request })
          cookiesToSet.forEach(({ name, value, options }) =>
            supabaseResponse.cookies.set(name, value, options)
          )
        },
      },
    }
  )

  // 중요: createServerClient와 getUser() 사이에 다른 로직을 넣지 않는다
  const { data: { user } } = await supabase.auth.getUser()

  const isPublic =
    request.nextUrl.pathname.startsWith('/login') ||
    request.nextUrl.pathname.startsWith('/auth')

  if (!user && !isPublic) {
    const url = request.nextUrl.clone()
    url.pathname = '/login'
    return NextResponse.redirect(url)
  }

  return supabaseResponse                    // 반드시 이 응답 객체를 그대로 반환
}
```

```tsx
// 보호 페이지에서의 재확인 (미들웨어만 믿지 않는다)
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'

export default async function TasksPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')
  // …
}
```

규칙:

- 사용자 확인은 **항상 `getUser()`** — 서버에서 `getSession()`의 사용자 정보는 신뢰하지 않는다
- 미들웨어의 `supabaseResponse`를 가공 없이 반환한다 — 쿠키가 유실되면 세션이 끊긴다
- 로그인/콜백 경로는 리다이렉트 대상에서 제외한다 (무한 루프 방지)

## 7. Metadata

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
