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
    src={post.imageUrl}
    alt={post.title}
    fill
    className="rounded-lg object-cover"
    sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
  />
</div>
```

```ts
// next.config.ts — 외부 이미지 호스트 허용 (Supabase Storage 등)
const config = {
  images: {
    remotePatterns: [{ hostname: '*.supabase.co' }],
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
'use client'

import { useMemo, useCallback } from 'react'

// Good: 비싼 계산에만 useMemo
const stats = useMemo(
  () => ({
    total: items.length,
    doneCount: items.filter((i) => i.done).length,
  }),
  [items]
)

// Good: memo된 자식에 전달하는 핸들러에만 useCallback
const handleDelete = useCallback((id: string) => deleteItem(id), [])
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
'use client'

// 검색 입력 → 300ms 정지 후에만 URL 갱신(서버 재조회)
const [query, setQuery] = useState('')
const debouncedQuery = useDebounce(query, 300)

useEffect(() => {
  if (debouncedQuery) setQueryParam('q', debouncedQuery)   // searchParams 갱신
}, [debouncedQuery])
```

## 7. 리소스 정리 — Memory Leak 방지

`useEffect`에서 만든 구독·타이머·리스너는 반드시 cleanup으로 해제한다.

```tsx
'use client'

useEffect(() => {
  const interval = setInterval(poll, 5000)             // 인터벌
  return () => clearInterval(interval)
}, [])

useEffect(() => {
  const controller = new AbortController()             // fetch 취소
  fetch(url, { signal: controller.signal }).then(/* … */).catch(() => {})
  return () => controller.abort()
}, [url])

useEffect(() => {
  const handler = () => {/* … */}                      // 이벤트 리스너
  window.addEventListener('resize', handler)
  return () => window.removeEventListener('resize', handler)
}, [])
```

Supabase realtime 채널도 동일하다 — `removeChannel`로 해제 (resources/data-fetching.md).

## 8. 리스트 key

```tsx
// Good: 안정적인 고유 key
{tasks.map((task) => <TaskItem key={task.id} task={task} />)}

// Bad: 인덱스 key — 항목 추가/삭제/정렬 시 상태가 어긋난다
{tasks.map((task, index) => <TaskItem key={index} task={task} />)}
```

## 9. 성능 체크리스트

- [ ] Server Component가 기본이고 `'use client'` 경계가 최소인가?
- [ ] 이미지는 `next/image` + 적절한 `sizes`·`priority`인가?
- [ ] 무거운 클라이언트 UI를 `dynamic()`으로 분리했는가? (`ssr: false`는 클라이언트 파일에서만)
- [ ] `useEffect`마다 cleanup이 있는가?
- [ ] 검색/필터 입력에 debounce를 적용했는가?
- [ ] 불필요한 `useMemo`/`useCallback`/`memo`를 넣지 않았는가?
