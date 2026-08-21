# Data Fetching

표준 페칭 계층과 경계, Next.js 15 캐싱 특성, 변이 후 갱신 패턴.

## 1. 표준 페칭 계층

```
Server Component (page.tsx · 서버 하위 컴포넌트)
  └→ lib/queries/*.ts        ← 유일한 조회 진입점
       └→ lib/supabase/server.ts (createServerClient)
            └→ Supabase (PostgreSQL)
```

**금지 경계 (컴포넌트 직접 호출 금지):**

- 컴포넌트(서버든 클라이언트든)에서 `supabase.from(…)` 인라인 호출 금지 — 반드시 `lib/queries/` 경유
- 클라이언트 컴포넌트에서 서버 데이터 조회 금지 — 서버 데이터는 Server Component가
  페칭해 props로 내린다 (예외는 §9: realtime 구독·인증 상태 UI)
- 별도 클라이언트 페칭 라이브러리 추가 금지 — 이 스택의 표준은 Server Component 페칭이다

**금지 범위 명확화 — 인증 확인은 데이터 조회가 아니다.** 금지되는 것은 **행 조회**(`supabase.from(…)`)다.
`createClient()` + `auth.getUser()`로 세션을 확인하는 것은 페이지·레이아웃·Server Action에서
**직접 호출해도 된다** — 쿼리 계층으로 감싸지 않는다 (리다이렉트 판단은 라우트의 책임이다).

## 2. Supabase 서버 클라이언트

```ts
// lib/supabase/server.ts
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'

export async function createClient() {
  const cookieStore = await cookies()          // Next.js 15: cookies()는 async

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll: () => cookieStore.getAll(),
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options))
          } catch {
            // Server Component에서 호출되면 쓰기가 불가하다 — 무시해도 된다.
            // 세션 갱신은 middleware가 담당한다 (resources/routing.md)
          }
        },
      },
    }
  )
}
```

- 서버 클라이언트는 **요청마다 새로 생성**한다 — 전역 변수 캐시 금지 (세션 혼입 위험)
- 사용자 확인은 항상 `supabase.auth.getUser()` — `getSession()`은 서버에서 신뢰하지 않는다

## 3. 쿼리 함수 규약 (`lib/queries/`)

```ts
// lib/queries/tasks.ts
import { createClient } from '@/lib/supabase/server'

export interface Task { id: string; title: string; done: boolean; created_at: string }

export async function getTasks(): Promise<Task[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('tasks')
    .select('id, title, done, created_at')   // 필요한 컬럼만 명시 (select('*') 지양)
    .order('created_at', { ascending: false })
    .limit(50)

  if (error) throw error                      // error.tsx 경계가 처리
  return data
}
```

- 파일은 도메인별로 나눈다: `lib/queries/tasks.ts`, `lib/queries/profiles.ts`
- 반환 타입을 명시하고, 그 타입을 export해 컴포넌트가 재사용하게 한다
- 에러는 throw — 컴포넌트에서 try/catch 하지 않는다 (폼 에러만 예외, §7)
- 테이블 설계·RLS 정책은 backend-guide 관할 — 여기서는 조회 패턴만 다룬다

## 4. 페이지에서의 사용: 병렬 페칭과 요청 내 dedupe

```tsx
// 순차 await는 워터폴을 만든다 — 독립 쿼리는 병렬로
const [tasks, profile] = await Promise.all([getTasks(), getProfile()])
```

```ts
// 같은 요청 안에서 여러 컴포넌트가 부르는 쿼리는 React cache()로 dedupe
import { cache } from 'react'

export const getProfile = cache(async (): Promise<Profile | null> => {/* … */})
```

## 5. 검색·필터·페이지네이션 — `searchParams`를 서버 쿼리로 번역

URL이 상태다(resources/state-management.md의 URL 상태 절). 페이지는 `searchParams`를
await해 쿼리 인자로 넘기고, 쿼리 함수가 그것을 Supabase 조건으로 옮긴다.

```ts
// lib/queries/tasks.ts
export interface TaskPage { tasks: Task[]; total: number; totalPages: number }

const PAGE_SIZE = 20

export async function searchTasks(query: string, page: number): Promise<TaskPage> {
  const supabase = await createClient()
  const offset = (page - 1) * PAGE_SIZE

  let builder = supabase
    .from('tasks')
    .select('id, title, done, created_at', { count: 'exact' })   // count로 총 개수 동시 조회
    .order('created_at', { ascending: false })
    .range(offset, offset + PAGE_SIZE - 1)                       // 끝 인덱스는 포함(inclusive)

  if (query) builder = builder.ilike('title', `%${query}%`)      // 부분 일치 검색

  const { data, count, error } = await builder
  if (error) throw error

  const total = count ?? 0
  return { tasks: data, total, totalPages: Math.max(1, Math.ceil(total / PAGE_SIZE)) }
}
```

```tsx
// app/(main)/tasks/page.tsx — searchParams는 Promise (Next.js 15)
interface TasksPageProps { searchParams: Promise<{ q?: string; page?: string }> }

export default async function TasksPage({ searchParams }: TasksPageProps) {
  const { q = '', page = '1' } = await searchParams
  const { tasks, totalPages } = await searchTasks(q, Number(page) || 1)
  return <TaskList tasks={tasks} /* 페이지네이션 UI에 totalPages 전달 */ />
}
```

- `count: 'exact'`는 매 요청 전체 카운트를 센다 — 큰 테이블에서 느리면 `'planned'`(추정치)나
  무한 스크롤(다음 페이지 존재 여부만 확인)로 바꾼다
- 페이지 범위를 벗어나면 빈 배열이 온다 — 에러가 아니라 빈 상태로 처리한다
- 사용자 입력은 `ilike`·`eq` 같은 빌더 메서드에 **값으로** 넘긴다 (원시 문자열 이어붙이기 금지).
  URL 쓰기 쪽은 `useQueryParams`(state-management), 디바운스는 performance

## 6. Next.js 15 캐싱 특성

- Supabase 클라이언트 경유 조회는 **동적** — 요청마다 실행된다 (쿠키 접근 때문)
- `fetch()`도 Next.js 15부터 기본 **no-store** — 캐시하려면 명시적으로 옵트인
- 변이 후 갱신은 서버에서: Server Action 안에서 `revalidatePath('/tasks')` 또는 `revalidateTag(…)`
- 클라이언트 수동 갱신은 `router.refresh()` — 현재 라우트의 서버 컴포넌트를 다시 실행한다
  (클라이언트 상태는 유지)

## 7. 변이 (프론트엔드 계약)

변이는 **Server Action**으로 한다. 폼 → `useActionState` → 액션 →
`revalidatePath` → 서버 리렌더가 표준 루프다. 클라이언트 재페칭 코드는 필요 없다.

```tsx
// app/(main)/tasks/_components/new-task-form.tsx
'use client'

import { useActionState } from 'react'
import { createTask, type ActionState } from '../actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

const initialState: ActionState = { error: null }

export function NewTaskForm() {
  const [state, formAction, isPending] = useActionState(createTask, initialState)

  return (
    <form action={formAction} className="flex gap-2">
      <Input name="title" placeholder="할 일" required disabled={isPending} />
      <Button type="submit" disabled={isPending}>{isPending ? '추가 중…' : '추가'}</Button>
      {state.error && <p className="text-sm text-destructive">{state.error}</p>}
    </form>
  )
}
```

- 제출 중 상태는 `isPending`으로 — 버튼 비활성화 필수
- 실패는 액션의 **반환값**으로 받아 인라인 표시 (throw하면 error.tsx로 가버린다)
- 액션이 완료되면 성공·실패와 무관하게 비제어 폼이 리셋된다 — 실패 시 입력 보존(`values` →
  `defaultValue` 재주입)과 필드 단위 에러(`fieldErrors`)는 resources/complete-example.md 참조
- 버튼형 변이(삭제·토글)는 `useTransition` — resources/state-management.md
- 액션 내부의 검증·권한·에러 설계는 backend-guide 관할 — 프론트는 호출 계약만 안다

## 8. 낙관적 UI — `useOptimistic`

서버 왕복(액션 실행 + revalidate + 리렌더)을 기다리지 않고 결과를 **먼저** 그린다. 액션이
끝나면 React가 낙관적 값을 버리고 서버가 준 실제 목록으로 되돌린다 — 롤백 코드가 필요 없다.

```tsx
// app/(main)/tasks/_components/task-list-optimistic.tsx
'use client'

import { useOptimistic, useTransition } from 'react'
import { toggleTask } from '../actions'
import type { Task } from '@/lib/queries/tasks'

export function TaskListOptimistic({ tasks }: { tasks: Task[] }) {
  const [, startTransition] = useTransition()
  const [optimisticTasks, toggleOptimistic] = useOptimistic(
    tasks,                                       // 서버가 준 실제 목록이 언제나 기준값
    (current: Task[], id: string) =>             // 낙관적 갱신 규칙
      current.map((t) => (t.id === id ? { ...t, done: !t.done } : t))
  )

  const handleToggle = (id: string) => {
    startTransition(async () => {
      toggleOptimistic(id)                       // 즉시 반영 (transition 안에서만 호출 가능)
      await toggleTask(id)                       // 액션이 revalidatePath로 실제 목록 갱신
    })
  }

  return (
    <ul className="space-y-2">
      {optimisticTasks.map((task) => (
        <li key={task.id}>
          <button onClick={() => handleToggle(task.id)}>{task.done ? '✓' : '○'} {task.title}</button>
        </li>
      ))}
    </ul>
  )
}
```

- `useOptimistic`의 첫 인자는 **props로 받은 서버 데이터**여야 한다 — `useState`로 복제하면
  revalidate 결과가 반영되지 않는다
- 갱신 함수는 `startTransition`(또는 form action) 안에서만 호출된다
- 액션이 실패하면 낙관적 값이 사라지며 원래 상태로 돌아간다 — 사용자에게 알려야 하므로
  실패 메시지는 액션 반환값으로 별도 표시한다

## 9. 브라우저 클라이언트의 허용 용도

```ts
// lib/supabase/client.ts
import { createBrowserClient } from '@supabase/ssr'

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )
}
```

클라이언트 컴포넌트에서 브라우저 클라이언트를 쓰는 경우는 두 가지뿐이다.
① **인증 UI**: 로그인/로그아웃 호출, `onAuthStateChange` 구독.
② **Realtime 구독**: 변경 알림을 받아 `router.refresh()`를 트리거.

```tsx
// app/(main)/tasks/_components/tasks-realtime.tsx
'use client'                                   // Realtime은 "알림"으로만 — 재조회는 서버가 한다

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

export function TasksRealtime() {
  const router = useRouter()

  useEffect(() => {
    const supabase = createClient()
    const channel = supabase
      .channel('tasks-changes')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'tasks' },
        () => router.refresh())
      .subscribe()
    return () => { supabase.removeChannel(channel) }
  }, [router])

  return null                                  // 렌더할 UI 없음 — 구독 전용 잎 컴포넌트
}
```

이 두 경우 외의 데이터 조회는 §1의 금지 경계를 따른다.

## 10. 스트리밍 — 느린 쿼리는 Suspense로 분리

```tsx
// 최상위에서 모든 쿼리를 await하면 가장 느린 쿼리가 전체를 막는다 —
// 느린 부분을 서버 하위 컴포넌트로 옮기고 Suspense로 감싸면 셸이 먼저 그려진다.
export default async function DashboardPage() {
  const profile = await getProfile()          // 빠른 쿼리는 즉시
  return (
    <main>
      <ProfileHeader profile={profile} />
      <Suspense fallback={<Skeleton className="h-40 w-full" />}>
        <SlowStatsPanel />                    {/* 내부에서 await getStats() */}
      </Suspense>
    </main>
  )
}
```
