<!-- epcc-seam: nextjs+supabase/frontend v3.12.0 -->
# Complete Example — Tasks (목록 + 생성)

기능 하나를 처음부터 끝까지: 할 일 **목록 조회 + 새 항목 생성**.
Server Component 페칭 → Server Action 변이 → `revalidatePath` 갱신의 전체 루프.

## 0. 전제

- `tasks` 테이블: `id uuid pk` · `user_id uuid` · `title text` · `done boolean` · `created_at timestamptz`
- RLS로 본인 행만 접근 가능 — 테이블·RLS·검증 설계는 backend-guide 관할
- `lib/supabase/server.ts`·`middleware.ts`는 구성 완료 상태
  (각각 resources/data-fetching.md, resources/routing.md)

## 1. 파일 구성

```
app/(main)/tasks/
├── page.tsx                    # Server Component — 목록 페칭 + 조립
├── loading.tsx                 # 라우트 로딩 스켈레톤
├── error.tsx                   # 라우트 에러 경계
├── actions.ts                  # Server Actions — 생성·삭제·토글
└── _components/
    ├── task-list.tsx           # Server Component — 목록 + 빈 상태
    └── new-task-form.tsx       # Client Component — 폼 + useActionState
lib/queries/tasks.ts            # 조회 함수 + 타입
components/common/empty-state.tsx  # 공통 빈 상태 (resources/component-patterns.md §5)
```

## 2. 쿼리 계층 — `lib/queries/tasks.ts`

```ts
import { createClient } from '@/lib/supabase/server'

export interface Task {
  id: string
  title: string
  done: boolean
  created_at: string
}

export async function getTasks(): Promise<Task[]> {
  const supabase = await createClient()
  const { data, error } = await supabase
    .from('tasks')
    .select('id, title, done, created_at')
    .order('created_at', { ascending: false })
    .limit(50)

  if (error) throw error
  return data
}
```

## 3. 페이지 — `app/(main)/tasks/page.tsx`

```tsx
import type { Metadata } from 'next'
import { redirect } from 'next/navigation'
import { createClient } from '@/lib/supabase/server'
import { getTasks } from '@/lib/queries/tasks'
import { TaskList } from './_components/task-list'
import { NewTaskForm } from './_components/new-task-form'

export const metadata: Metadata = { title: 'Tasks' }

export default async function TasksPage() {
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/login')              // 미들웨어에 이은 2차 확인

  const tasks = await getTasks()             // RLS가 본인 행만 반환

  return (
    <main className="mx-auto max-w-2xl space-y-6 p-6">
      <h1 className="text-2xl font-semibold">Tasks</h1>
      <NewTaskForm />
      <TaskList tasks={tasks} />
    </main>
  )
}
```

## 4. 로딩·에러 — `loading.tsx` / `error.tsx`

```tsx
// app/(main)/tasks/loading.tsx
import { Skeleton } from '@/components/ui/skeleton'

export default function TasksLoading() {
  return (
    <div className="mx-auto max-w-2xl space-y-4 p-6">
      <Skeleton className="h-8 w-32" />
      <Skeleton className="h-10 w-full" />
      <Skeleton className="h-14 w-full" />
      <Skeleton className="h-14 w-full" />
    </div>
  )
}
```

```tsx
// app/(main)/tasks/error.tsx
'use client'

import { Button } from '@/components/ui/button'

export default function TasksError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <div className="mx-auto max-w-2xl p-8 text-center">
      <p className="text-sm text-destructive">목록을 불러오지 못했습니다.</p>
      <Button variant="outline" onClick={reset} className="mt-4">다시 시도</Button>
    </div>
  )
}
```

## 5. 목록 — `app/(main)/tasks/_components/task-list.tsx` (Server Component)

```tsx
import { EmptyState } from '@/components/common/empty-state'   // 정의: component-patterns.md §5
import { cn } from '@/lib/utils'
import type { Task } from '@/lib/queries/tasks'

interface TaskListProps {
  tasks: Task[]
}

export function TaskList({ tasks }: TaskListProps) {
  if (tasks.length === 0) {
    return (
      <EmptyState
        title="아직 등록된 할 일이 없습니다."
        description="위 폼에서 첫 항목을 추가해 보세요."
      />
    )
  }

  return (
    <ul className="space-y-2">
      {tasks.map((task) => (
        <li key={task.id} className="flex items-center gap-3 rounded-lg border bg-card p-4">
          <span className={cn('flex-1 text-sm', task.done && 'text-muted-foreground line-through')}>
            {task.title}
          </span>
          <time className="text-xs text-muted-foreground">
            {new Date(task.created_at).toLocaleDateString('ko-KR')}
          </time>
        </li>
      ))}
    </ul>
  )
}
```

## 6. 생성 액션 — `app/(main)/tasks/actions.ts`

```ts
'use server'

import { revalidatePath } from 'next/cache'
import { createClient } from '@/lib/supabase/server'

export interface ActionState {
  error: string | null                       // 폼 전체 에러 (backend-guide의 formError에 대응)
  fieldErrors?: Record<string, string[] | undefined>   // 필드별 에러 — backend-guide와 동일한 모양
  values?: { title: string }                 // 실패 시 입력 보존용
}

export async function createTask(_prev: ActionState, formData: FormData): Promise<ActionState> {
  const title = String(formData.get('title') ?? '').trim()
  if (!title) return { error: null, fieldErrors: { title: ['제목을 입력하세요.'] } }
  if (title.length > 200)
    return { error: null, fieldErrors: { title: ['200자 이하로 입력하세요.'] }, values: { title } }

  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) return { error: '로그인이 필요합니다.', values: { title } }

  const { error } = await supabase.from('tasks').insert({ title, user_id: user.id })
  if (error) return { error: '저장에 실패했습니다. 잠시 후 다시 시도하세요.', values: { title } }

  revalidatePath('/tasks')                   // 목록 서버 리렌더 트리거 (URL 기준 — 괄호 폴더는 URL에 없다)
  return { error: null }
}
```

버튼형 변이도 같은 계약을 쓴다 — 폼이 아니므로 `(id)` 하나만 받는다
(호출부는 resources/state-management.md의 `useTransition` 절).

```ts
export async function deleteTask(id: string): Promise<ActionState> {
  const supabase = await createClient()
  const { error } = await supabase.from('tasks').delete().eq('id', id)   // RLS가 소유자 검사
  if (error) return { error: '삭제에 실패했습니다.' }
  revalidatePath('/tasks')
  return { error: null }
}

export async function toggleTask(id: string): Promise<ActionState> { /* update({ done }) 후 동일 */ }
```

심화된 검증(스키마 검증 라이브러리)·에러 설계는 backend-guide를 따른다 — 여기서는 프론트가
의존하는 반환 계약만 보여준다. backend-guide 규약대로 Zod로 검증하면
`z.flattenError(parsed.error).fieldErrors`가 그대로 위 `fieldErrors` 자리에 들어오므로
아래 폼 렌더링 코드는 바꿀 필요가 없다.

## 7. 폼 — `app/(main)/tasks/_components/new-task-form.tsx` (Client Component)

```tsx
'use client'

import { useActionState } from 'react'
import { createTask, type ActionState } from '../actions'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

const initialState: ActionState = { error: null }

export function NewTaskForm() {
  const [state, formAction, isPending] = useActionState(createTask, initialState)

  const titleError = state.fieldErrors?.title?.[0]

  return (
    <form action={formAction} className="space-y-2">
      <div className="flex gap-2">
        <Input
          name="title"
          placeholder="할 일을 입력하세요"
          defaultValue={state.values?.title}
          aria-invalid={!!titleError}
          aria-describedby={titleError ? 'title-error' : undefined}
          required
          maxLength={200}
          disabled={isPending}
        />
        <Button type="submit" disabled={isPending}>
          {isPending ? '추가 중…' : '추가'}
        </Button>
      </div>
      {/* 필드 에러는 해당 입력 바로 아래에 */}
      {titleError && <p id="title-error" className="text-sm text-destructive">{titleError}</p>}
      {/* 폼 전체 에러(인증·저장 실패)는 폼 하단에 */}
      {state.error && <p className="text-sm text-destructive">{state.error}</p>}
    </form>
  )
}
```

React 19는 **액션이 완료되면 성공·실패와 무관하게** 비제어 폼을 리셋한다.
리셋은 각 입력을 `defaultValue`로 되돌리므로, 실패 시 액션이 돌려준 `values`를
`defaultValue`로 재주입하면 입력이 보존된다 — 성공 시에는 `values`가 없어
폼이 비워진다. 별도 리셋 코드는 필요 없다.

## 8. 흐름 요약

```
[조회] 요청 → middleware(세션 갱신·게이트) → page.tsx
       → getUser() 재확인 → getTasks() → TaskList 렌더
       (전환 중에는 loading.tsx, 쿼리 throw 시 error.tsx)

[생성] NewTaskForm 제출 → createTask 액션 (서버)
       → 검증 → getUser → insert → revalidatePath('/tasks')
       → 서버 리렌더 → 새 목록이 자동 반영, 폼은 비워짐
       (실패 시 { error | fieldErrors, values } 반환 →
        fieldErrors는 해당 입력 아래, error는 폼 하단에 인라인 표시,
        리셋된 입력은 defaultValue={state.values?.title}로 보존)
```

## 9. 체크포인트

- [ ] 조회는 `lib/queries/` 경유 — 컴포넌트 인라인 쿼리 없음
- [ ] 페이지에서 `getUser()` 재확인 (미들웨어만 신뢰하지 않음)
- [ ] 로딩(`loading.tsx`)·빈(TaskList 내부)·에러(`error.tsx`) 3상태 모두 존재
- [ ] 변이는 Server Action + `revalidatePath` — 클라이언트 재페칭 코드 없음
- [ ] 폼 에러는 인라인(필드 에러는 입력 아래, 폼 에러는 하단), 조회 에러는 경계 — 경로가 다르다
- [ ] 클라이언트 컴포넌트는 폼 하나뿐 — 나머지는 전부 Server Component
