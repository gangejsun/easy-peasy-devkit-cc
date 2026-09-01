<!-- epcc-pack: frontend/nextjs v3.12.0 -->
# Performance

이미지·코드 스플리팅·메모이제이션·리소스 정리 등 프론트엔드 성능 최적화.

## 1. 최우선 최적화 — Server Component 유지

Server Component는 그 자체가 성능 최적화다: 클라이언트 번들 0, 서버 렌더링.
**`'use client'` 경계를 최소로 유지하는 것이 가장 효과적인 최적화**이며,
아래 기법들은 그 다음이다 — 측정 없이 선제 적용하지 않는다.

## 2. Next.js Image

```tsx
import Image from 'next/image'

// 고정 크기 — LCP(첫 화면 최대 요소) 이미지에는 priority
<Image src="/hero.jpg" alt="Hero" width={800} height={400} priority />

// 반응형 (fill) — 부모에 relative + 비율 지정, sizes로 다운로드 크기 축소
<div className="relative aspect-video">
  <Image
    src={imageUrl}
    alt={title}
    fill
    className="rounded-lg object-cover"
    sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
  />
</div>
```

```ts
// next.config.ts — 외부 이미지 호스트 허용 (오브젝트 스토리지 등)
const config = {
  images: {
    remotePatterns: [{ hostname: 'assets.example.com' }],   // 백엔드 축의 스토리지 호스트로 치환
  },
}
```

- `<img>` 태그 직접 사용 금지 — 항상 `next/image`
- `fill` 이미지에는 `sizes`를 반드시 지정한다 (기본값 100vw는 과다 다운로드)

## 3. Dynamic Import (Code Splitting)

무거운 클라이언트 UI(에디터·차트·지도)는 필요할 때만 로드한다.

```tsx
// 주의: `ssr: false`는 'use client' 파일 안에서만 허용된다.
// Server Component에서 쓰면 Next.js 15는 런타임 에러를 던진다.
'use client'

import { useState } from 'react'
import dynamic from 'next/dynamic'

const HeavyEditor = dynamic(() => import('@/components/common/rich-editor'), {
  loading: () => <div className="h-64 animate-pulse rounded-lg bg-muted" />,
  ssr: false,               // 브라우저 전용 라이브러리일 때만
})

export function EditToggle({ content }: { content: string }) {
  const [editing, setEditing] = useState(false)
  return editing
    ? <HeavyEditor content={content} />
    : <button onClick={() => setEditing(true)}>{content}</button>
}
```

- Server Component에서 지연 로드가 필요하면 `ssr: false` **없이**
  `dynamic(() => import(…))`만 쓴다 — SSR은 유지되고 클라이언트 청크만 분리된다
- 첫 화면에 보이지 않는 조건부 UI(모달 내부, 탭 뒤 콘텐츠)가 분리 후보다

## 4. useMemo · useCallback — 필요한 곳에만

```tsx
// app/(main)/tasks/_components/task-stats.tsx
'use client'

import { memo, useCallback, useMemo, useState } from 'react'
import { cn } from '@/lib/utils'
import type { Task } from '@/lib/queries/tasks'

export function TaskStats({ tasks }: { tasks: Task[] }) {
  const [selectedId, setSelectedId] = useState<string | null>(null)

  // Good: 비싼 계산에만 useMemo
  const stats = useMemo(
    () => ({ total: tasks.length, doneCount: tasks.filter((t) => t.done).length }),
    [tasks]
  )

  // Good: memo된 자식에 전달하는 핸들러에만 useCallback
  //       (핸들러 참조가 매 렌더 바뀌면 자식의 memo가 무력화된다)
  const handleSelect = useCallback((id: string) => setSelectedId(id), [])

  return (
    <div className="space-y-1">
      <p className="text-sm text-muted-foreground">{stats.doneCount} / {stats.total} 완료</p>
      {tasks.map((task) => (
        <TaskRow key={task.id} task={task} selected={task.id === selectedId} onSelect={handleSelect} />
      ))}
    </div>
  )
}

interface TaskRowProps {
  task: Task
  selected: boolean
  onSelect: (id: string) => void
}

const TaskRow = memo(function TaskRow({ task, selected, onSelect }: TaskRowProps) {
  return (
    <button onClick={() => onSelect(task.id)} className={cn('block w-full text-left text-sm', selected && 'font-semibold')}>
      {task.title}
    </button>
  )
})
```

```tsx
// Bad: 단순한 계산에 useMemo
const fullName = useMemo(() => `${firstName} ${lastName}`, [firstName, lastName])
// Good: 직접 계산
const fullName = `${firstName} ${lastName}`

// Bad: 자식에 전달하지 않는 핸들러에 useCallback
const handleClick = useCallback(() => setOpen(true), [])
// Good: 직접 정의
const handleClick = () => setOpen(true)
```

## 5. React.memo — 리렌더가 실측으로 비싼 컴포넌트에만

```tsx
import { memo } from 'react'

const ExpensiveChart = memo(function ExpensiveChart({ data }: { data: ChartPoint[] }) {
  // 복잡한 렌더링 로직
  return <canvas /* … */ />
})
```

기본값은 memo 없음 — 프로파일링으로 리렌더 비용이 확인된 경우에만 감싼다.

## 6. Debounce — 빈번한 입력 이벤트

<!-- file: hooks/use-debounce.ts -->
```ts
// hooks/use-debounce.ts
import { useEffect, useState } from 'react'

export function useDebounce<T>(value: T, delay = 300): T {
  const [debouncedValue, setDebouncedValue] = useState(value)

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedValue(value), delay)
    return () => clearTimeout(timer)
  }, [value, delay])

  return debouncedValue
}
```

```tsx
// app/(main)/tasks/_components/search-bar.tsx
'use client'

import { useEffect, useState } from 'react'
import { useDebounce } from '@/hooks/use-debounce'
import { useQueryParams } from '@/hooks/use-query-params'   // 정의: resources/state-management.md §7
import { Input } from '@/components/ui/input'

export function SearchBar() {
  const { searchParams, setQueryParam } = useQueryParams()
  const initial = searchParams.get('q') ?? ''
  const [query, setQuery] = useState(initial)
  const debouncedQuery = useDebounce(query, 300)            // 300ms 정지 후에만 URL 갱신

  useEffect(() => {
    if (debouncedQuery !== initial) setQueryParam('q', debouncedQuery)  // searchParams 갱신 → 서버 재조회
  }, [debouncedQuery, initial, setQueryParam])

  return <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="검색" />
}
```

URL이 바뀌면 Server Component가 새 `searchParams`로 다시 실행된다 — 클라이언트 재페칭 코드는
필요 없다. 서버 쪽 검색 쿼리 작성은 resources/data-fetching.md의 검색·페이지네이션 절 참조.

## 7. 리소스 정리 — Memory Leak 방지

`useEffect`에서 만든 구독·타이머·리스너는 반드시 cleanup으로 해제한다.

<!-- file: components/common/live-status.tsx -->
```tsx
// components/common/live-status.tsx
'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'

export function LiveStatus({ statusUrl }: { statusUrl: string }) {
  const router = useRouter()
  const [narrow, setNarrow] = useState(false)

  useEffect(() => {
    const interval = setInterval(() => router.refresh(), 5000)   // 인터벌
    return () => clearInterval(interval)
  }, [router])

  // 아래 fetch는 "cleanup 기법 시연"이다 — 이 스택의 데이터 조회는 Server Component가 한다.
  // 클라이언트 fetch는 데이터 계층 밖의 외부 API(상태 배지·서드파티 위젯)에만 쓴다.
  useEffect(() => {
    const controller = new AbortController()                     // 요청 취소
    fetch(statusUrl, { signal: controller.signal }).catch(() => {})
    return () => controller.abort()
  }, [statusUrl])

  useEffect(() => {
    const handler = () => setNarrow(window.innerWidth < 768)     // 이벤트 리스너
    window.addEventListener('resize', handler)
    return () => window.removeEventListener('resize', handler)
  }, [])

  return <span className="text-xs text-muted-foreground">{narrow ? '모바일' : '데스크톱'}</span>
}
```

실시간 구독 채널도 동일하다 — 백엔드 축이 제공하는 해제 API로 정리한다 (`resources/data-fetching.md`).

## 8. 리스트 key

```tsx
// Good: 안정적인 고유 key
{tasks.map((task) => <TaskCard key={task.id} task={task} />)}

// Bad: 인덱스 key — 항목 추가/삭제/정렬 시 상태가 어긋난다
{tasks.map((task, index) => <TaskCard key={index} task={task} />)}
```

## 9. 성능 체크리스트

- [ ] Server Component가 기본이고 `'use client'` 경계가 최소인가?
- [ ] 이미지는 `next/image` + 적절한 `sizes`·`priority`인가?
- [ ] 무거운 클라이언트 UI를 `dynamic()`으로 분리했는가? (`ssr: false`는 클라이언트 파일에서만)
- [ ] `useEffect`마다 cleanup이 있는가?
- [ ] 검색/필터 입력에 debounce를 적용했는가?
- [ ] 불필요한 `useMemo`/`useCallback`/`memo`를 넣지 않았는가?
