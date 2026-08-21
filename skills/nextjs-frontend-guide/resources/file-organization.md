# File Organization

디렉토리 구조 전체 지도, 파일 배치 결정 기준, 파일명 규칙, import 순서.

## 1. Directory Structure

```
app/                          # 라우팅 (폴더 구조 = URL)
├── layout.tsx                # 루트 레이아웃 (globals.css·폰트·Provider)
├── page.tsx                  # 홈
├── globals.css               # Tailwind v4 진입점
├── loading.tsx / error.tsx / not-found.tsx    # 전역 상태 UI
├── (auth)/                   # 라우트 그룹 — URL 미포함
│   ├── login/page.tsx
│   └── signup/page.tsx
├── (main)/
│   ├── layout.tsx            # 그룹 공유 레이아웃 (헤더·사이드바)
│   ├── posts/
│   │   ├── page.tsx          # 목록
│   │   ├── loading.tsx
│   │   ├── actions.ts        # 이 라우트의 Server Actions (콜로케이션)
│   │   ├── _components/      # 이 라우트 전용 컴포넌트 (라우팅 제외)
│   │   └── [id]/
│   │       ├── page.tsx      # 상세
│   │       └── not-found.tsx
│   └── search/page.tsx
└── api/                      # Route Handlers — backend-guide 관할
    └── webhooks/route.ts

components/
├── ui/                       # shadcn/ui 생성 컴포넌트 (CLI로만 추가)
├── layout/                   # 페이지 골격 공통 (page-header.tsx, app-sidebar.tsx)
├── common/                   # 도메인 무관 재사용 (empty-state.tsx, page-section.tsx)
├── post/                     # 도메인별 공유 컴포넌트 (여러 라우트에서 쓸 때)
│   ├── post-card.tsx
│   └── post-card-skeleton.tsx
├── user/
│   └── user-avatar.tsx
└── comment/
    └── comment-form.tsx

lib/
├── supabase/                 # client.ts · server.ts · middleware.ts
├── queries/                  # 데이터 조회 함수 (서버 전용, 유일한 조회 진입점)
│   ├── tasks.ts
│   └── profiles.ts
├── analytics/                # 외부 서비스 SDK 래퍼 (필요 시)
└── utils.ts                  # cn() 등 공통 유틸

hooks/                        # 커스텀 훅 (use-debounce.ts, use-media-query.ts)
stores/                       # Zustand (ui-store.ts, ui-store-provider.tsx)
types/                        # 공유 타입 (database.ts = Supabase 생성 타입)
constants/                    # 상수 (config.ts)
middleware.ts                 # 세션 갱신 + 보호 라우트
```

- `src/`를 쓰는 프로젝트면 같은 구조를 `src/` 아래에 둔다
- 프로젝트에 이미 확립된 구조가 있으면 그것을 우선한다

## 2. 배치 결정 기준

| 질문 | Yes → | No → |
| --- | --- | --- |
| Next.js 라우팅 파일(page/layout/loading/error/actions)? | `app/` | 다음 |
| 한 라우트에서만 쓰는 컴포넌트? | `app/<route>/_components/` | 다음 |
| 페이지 골격(헤더·컨테이너·액션바)? | `components/layout/` | 다음 |
| 도메인 무관 재사용 UI? | `components/common/` (원시 UI는 shadcn `components/ui/`) | 다음 |
| 특정 도메인의 공유 컴포넌트? | `components/<domain>/` | 다음 |
| 서버 데이터 조회 함수? | `lib/queries/` | 다음 |
| 클라이언트 전역 상태? | `stores/` | 다음 |
| React 훅? | `hooks/` | `types/` 또는 `constants/` |

새 공통 컴포넌트를 만들기 전에 `components/layout/`·`components/common/`을
grep으로 확인한다 — 이미 있으면 재사용 (resources/component-patterns.md).

## 3. 파일명 규칙

| 파일 유형 | 규칙 | 예시 |
| --- | --- | --- |
| 컴포넌트 | kebab-case.tsx (export는 PascalCase) | `post-card.tsx` → `PostCard` |
| 라우팅 파일 | Next.js 예약명 | `page.tsx`, `layout.tsx`, `actions.ts` |
| 커스텀 훅 | use-xxx.ts | `use-debounce.ts` |
| Zustand 스토어 | xxx-store.ts | `cart-store.ts`, `ui-store-provider.tsx` |
| 쿼리/유틸 | kebab-case.ts | `tasks.ts`, `format-date.ts` |
| 타입/상수 | kebab-case.ts | `database.ts`, `config.ts` |

## 4. Import 순서

```tsx
// 1. React / Next.js
import { Suspense } from 'react'
import Link from 'next/link'
import Image from 'next/image'

// 2. Third-party 라이브러리
import { z } from 'zod'

// 3. 프로젝트 내부 — UI 컴포넌트
import { Button } from '@/components/ui/button'
import { Card } from '@/components/ui/card'

// 4. 프로젝트 내부 — 레이아웃·도메인 컴포넌트
import { PageHeader } from '@/components/layout/page-header'
import { PostCard } from '@/components/post/post-card'

// 5. 프로젝트 내부 — 유틸·훅·스토어·쿼리
import { cn } from '@/lib/utils'
import { useDebounce } from '@/hooks/use-debounce'
import { useUiStore } from '@/stores/ui-store-provider'

// 6. 타입 (import type)
import type { Post } from '@/lib/queries/posts'
```

## 5. Props vs 공유 타입

```ts
// Good: Props는 컴포넌트 파일 상단에 정의
// components/post/post-card.tsx
interface PostCardProps {
  post: Post
  className?: string
}

export function PostCard({ post, className }: PostCardProps) {/* … */}

// Good: 서버 조회 데이터의 타입은 lib/queries/가 export — 컴포넌트가 재사용
// lib/queries/posts.ts
export interface Post {
  id: string
  title: string
  content: string
  created_at: string
}
```

`types/`는 도메인 공용 타입과 생성 타입(`database.ts`)에만 쓴다 —
쿼리 결과 타입을 `types/`와 `lib/queries/`에 이중 정의하지 않는다.

## 6. Anti-Patterns

```ts
// Bad: 상대경로 import
import { Button } from '../../components/ui/button'
// Good: @/ alias
import { Button } from '@/components/ui/button'

// Bad: 라우트 폴더에 컴포넌트를 맨몸으로 두기 (라우팅 파일과 뒤섞임)
// app/posts/post-card.tsx
// Good: 라우트 전용이면 app/posts/_components/post-card.tsx,
//       여러 라우트 공유면 components/post/post-card.tsx

// Bad: 하나의 거대한 컴포넌트 파일 (300줄+)
// → 독립적으로 테스트·재사용 가능한 단위로 분리

// Bad: index.ts barrel export (트리쉐이킹 저해, 순환 import 유발)
// components/post/index.ts ← 만들지 않는다. 각 파일에서 직접 import
```
