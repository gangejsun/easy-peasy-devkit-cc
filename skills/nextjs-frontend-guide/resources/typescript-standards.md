# TypeScript Standards

strict 모드 전제의 타입 작성 표준: any 금지, 타입 가드, 유틸리티 타입, Supabase 생성 타입.

## 1. 핵심 규칙

- **strict 모드** 활성화 (`tsconfig.json`)
- **`any` 금지** → `unknown` + 타입 가드 또는 구체적 타입
- **`@/` alias** 필수 — 상대경로 import 금지
- **`function` 키워드**로 컴포넌트 선언 (`React.FC` 화살표 함수 금지)
- **Props 타입은 컴포넌트와 같은 파일**에 정의 (resources/component-patterns.md)

## 2. type vs interface

```ts
// interface: 컴포넌트 Props, 객체 형태
interface UserCardProps {
  user: User
  className?: string
  onSelect?: (id: string) => void
}

// type: 유니온, 유틸리티, 단순 별칭
type Status = 'active' | 'pending' | 'closed'
type Nullable<T> = T | null
```

## 3. any 금지 — unknown과 타입 가드

```ts
// Bad
function processData(data: any) {/* … */}

// Good: unknown + 좁히기
function processData(data: unknown) {
  if (typeof data === 'string') return data.toUpperCase()
  if (isUser(data)) return data.name
  throw new Error('Unexpected data type')
}

// 객체 타입 가드
function isUser(value: unknown): value is User {
  return typeof value === 'object' && value !== null && 'id' in value && 'email' in value
}
```

Discriminated union이면 가드 없이 좁혀진다:

```ts
type ActionResult<T> =
  | { success: true; data: T }
  | { success: false; error: string }

function handle<T>(result: ActionResult<T>) {
  if (result.success) return result.data     // 여기서 T로 좁혀짐
  console.error(result.error)
}
```

## 4. 타입 import는 `import type`

```ts
import type { Metadata } from 'next'
import type { Task } from '@/lib/queries/tasks'
import type { Database } from '@/types/database'

// 값과 타입 혼합 시
import { createClient } from '@/lib/supabase/server'
import type { SupabaseClient } from '@supabase/supabase-js'
```

## 5. 함수 반환 타입

공개 API(쿼리 함수·Server Action)는 반환 타입을 명시하고, 컴포넌트는 추론에 맡긴다.

```ts
// 쿼리 함수: 명시적 반환 타입 (lib/queries/ 규약)
export async function getProfileById(id: string): Promise<Profile | null> {
  const supabase = await createClient()
  const { data } = await supabase
    .from('profiles')
    .select('id, name, avatar_url')
    .eq('id', id)
    .single()
  return data
}

// Server Action: 반환 계약을 타입으로 고정 (전체 정의는 resources/complete-example.md §6)
import type { ActionState } from '@/app/(main)/tasks/actions'
export async function deleteTask(id: string): Promise<ActionState> {/* … */}

// 컴포넌트: 반환 타입 생략 (JSX 자동 추론)
export function TaskCard({ task }: TaskCardProps) {
  return <div>{task.title}</div>
}
```

## 6. 유틸리티 타입

```ts
type UpdateTaskInput = Partial<Task>                          // 모두 선택적
type TaskSummary = Pick<Task, 'id' | 'title'>                 // 일부만
type CreateTaskInput = Omit<Task, 'id' | 'created_at'>        // 일부 제외
type StatusColors = Record<Status, string>                    // 키-값 맵

const statusColors: StatusColors = {
  active: 'text-green-600',
  pending: 'text-yellow-600',
  closed: 'text-muted-foreground',
}
```

기존 타입에서 파생시킬 수 있는 타입을 손으로 다시 정의하지 않는다.

## 7. Supabase 생성 타입

```bash
npx supabase gen types typescript --project-id <id> > types/database.ts
```

```ts
import type { Database } from '@/types/database'

// 테이블 Row / Insert / Update 타입
type Task = Database['public']['Tables']['tasks']['Row']
type InsertTask = Database['public']['Tables']['tasks']['Insert']
type UpdateTask = Database['public']['Tables']['tasks']['Update']
```

- 클라이언트 팩토리에 제네릭을 지정하면 쿼리 결과가 자동으로 타입된다:
  `createServerClient<Database>(…)`, `createBrowserClient<Database>(…)`
- 스키마 변경 후에는 생성 명령을 다시 실행해 타입을 동기화한다
- 컴포넌트에 노출하는 타입은 `lib/queries/`가 가공해 export하는 것을 우선 사용

## 8. null/undefined 처리

```tsx
const name = user?.profile?.name              // optional chaining
const displayName = user?.name ?? 'Anonymous' // nullish coalescing (||와 다르다: 0·'' 유지)

// 조기 반환으로 좁히기 — non-null 단언(!)보다 우선
function renderUser(user: User | null) {
  if (!user) return <EmptyState title="사용자를 찾을 수 없습니다." />   // 정의: component-patterns.md §5
  return <UserCard user={user} />             // 여기서 user는 non-null
}
```

`!` 단언은 정말 확실한 경우(정적 요소 조회 등)에만 쓴다.

## 9. Naming Conventions

| 대상 | 규칙 | 예시 |
| --- | --- | --- |
| 컴포넌트/타입/인터페이스 | PascalCase | `UserCard`, `TaskListProps` |
| 함수/변수 | camelCase | `formatDate`, `userName` |
| 상수 | UPPER_SNAKE_CASE | `MAX_RETRIES`, `API_URL` |
| 타입 접미사 | 역할 반영 | `Props`, `State`, `Input`, `Response` |
| Zustand 스토어 훅 | use~Store | `useCartStore`, `useUiStore` |
| 커스텀 훅 | use~ | `useDebounce`, `useMediaQuery` |

파일명 규칙(kebab-case 등)은 resources/file-organization.md 참조.
