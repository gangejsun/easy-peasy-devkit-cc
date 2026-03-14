# File Organization

## Directory Structure

```
src/
├── app/                     # Next.js App Router (페이지 & 라우팅)
│   ├── (auth)/              # 인증 관련 (로그인, 회원가입)
│   │   ├── login/
│   │   │   └── page.tsx
│   │   └── signup/
│   │       └── page.tsx
│   ├── (main)/              # 메인 레이아웃
│   │   ├── layout.tsx       # 공유 레이아웃 (Header, Footer)
│   │   ├── deals/
│   │   │   ├── page.tsx     # 딜 목록
│   │   │   ├── loading.tsx  # 로딩 UI
│   │   │   └── [id]/
│   │   │       ├── page.tsx # 딜 상세
│   │   │       └── not-found.tsx
│   │   ├── my/
│   │   │   └── page.tsx     # 마이페이지
│   │   └── search/
│   │       └── page.tsx     # 검색
│   ├── api/                 # API Route Handlers
│   │   └── webhooks/
│   │       └── route.ts
│   ├── layout.tsx           # 루트 레이아웃
│   ├── page.tsx             # 홈페이지
│   ├── loading.tsx          # 전역 로딩
│   ├── error.tsx            # 전역 에러
│   └── not-found.tsx        # 전역 404
│
├── components/              # 재사용 가능한 컴포넌트
│   ├── ui/                  # shadcn/ui 컴포넌트 (자동 생성)
│   │   ├── button.tsx
│   │   ├── card.tsx
│   │   ├── input.tsx
│   │   └── ...
│   ├── deal/                # 딜 관련 컴포넌트
│   │   ├── DealCard.tsx
│   │   ├── DealList.tsx
│   │   └── DealCardSkeleton.tsx
│   ├── user/                # 유저 관련 컴포넌트
│   │   ├── UserAvatar.tsx
│   │   └── UserProfile.tsx
│   ├── payment/             # 결제 관련 컴포넌트
│   │   └── PaymentForm.tsx
│   └── layout/              # 레이아웃 컴포넌트
│       ├── Header.tsx
│       ├── Footer.tsx
│       └── Sidebar.tsx
│
├── lib/                     # 라이브러리 & 유틸리티
│   ├── supabase/
│   │   ├── client.ts        # 브라우저 Supabase 클라이언트
│   │   ├── server.ts        # 서버 Supabase 클라이언트
│   │   ├── admin.ts         # Service Role 클라이언트
│   │   └── middleware.ts    # 미들웨어용 클라이언트
│   ├── actions/             # Server Actions
│   │   ├── user.ts
│   │   └── post.ts
│   ├── toss/                # Toss Payments 연동
│   │   └── client.ts
│   └── utils.ts             # cn() 등 공통 유틸
│
├── hooks/                   # 커스텀 훅
│   ├── useDebounce.ts
│   └── useMediaQuery.ts
│
├── stores/                  # Zustand 스토어
│   ├── useAuthStore.ts
│   └── useCartStore.ts
│
├── types/                   # 공유 TypeScript 타입
│   ├── database.ts          # Supabase 생성 타입
│   ├── user.ts
│   └── post.ts
│
└── constants/               # 상수
    └── config.ts
```

---

## 파일 배치 규칙

### 어디에 넣을지 결정 기준

| 질문 | Yes → | No → |
|------|-------|------|
| Next.js 라우팅에 관련? | `app/` | 다음 질문 |
| 여러 도메인에서 재사용? | `components/ui/` 또는 `components/layout/` | 다음 질문 |
| 특정 도메인에 속함? | `components/{domain}/` | 다음 질문 |
| 서버에서 실행? | `lib/` 또는 `lib/actions/` | 다음 질문 |
| 클라이언트 상태? | `stores/` | 다음 질문 |
| React 훅? | `hooks/` | `types/` 또는 `constants/` |

### 파일명 규칙

| 파일 유형 | 규칙 | 예시 |
|----------|------|------|
| 컴포넌트 | PascalCase.tsx | `DealCard.tsx`, `Header.tsx` |
| 페이지 | page.tsx (Next.js 규칙) | `app/deals/page.tsx` |
| 레이아웃 | layout.tsx (Next.js 규칙) | `app/(main)/layout.tsx` |
| 훅 | camelCase.ts | `useDebounce.ts`, `useAuth.ts` |
| 스토어 | use~Store.ts | `useAuthStore.ts` |
| 유틸/서비스 | camelCase.ts | `formatPrice.ts` |
| 타입 | camelCase.ts | `user.ts`, `database.ts` |
| 상수 | camelCase.ts | `config.ts` |
| Server Action | camelCase.ts | `user.ts`, `post.ts` |

---

## Import Organization

권장 import 순서:

```typescript
// 1. React / Next.js
import { Suspense } from "react";
import Link from "next/link";
import Image from "next/image";

// 2. Third-party 라이브러리
import { z } from "zod";

// 3. 프로젝트 내부 - UI 컴포넌트
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

// 4. 프로젝트 내부 - 도메인 컴포넌트
import DealCard from "@/components/deal/DealCard";

// 5. 프로젝트 내부 - 유틸, 훅, 스토어
import { cn } from "@/lib/utils";
import { useDebounce } from "@/hooks/useDebounce";
import { useAuthStore } from "@/stores/useAuthStore";

// 6. 타입 (type 키워드 사용)
import type { Deal } from "@/types/deal";
```

---

## Props vs Types 파일

```typescript
// good: Props는 컴포넌트 파일에 정의
// components/deal/DealCard.tsx
interface DealCardProps {
  deal: Deal;
  className?: string;
}

function DealCard({ deal, className }: DealCardProps) { /* ... */ }

// good: 공유 타입은 types/ 디렉토리에
// types/deal.ts
export interface Deal {
  id: string;
  title: string;
  price: number;
  // ...
}
```

---

## Anti-Patterns

```typescript
// bad: 상대경로 import
import { Button } from "../../components/ui/button";
// good:
import { Button } from "@/components/ui/button";

// bad: 컴포넌트를 app/ 디렉토리에 직접 넣기
// app/deals/DealCard.tsx  ← 잘못된 위치
// good:
// components/deal/DealCard.tsx

// bad: 하나의 거대한 컴포넌트 파일 (300줄+)
// 분리 기준: UI가 독립적으로 테스트/재사용 가능한 단위로 분리

// bad: index.ts barrel export (Next.js에서 트리쉐이킹 문제)
// components/deal/index.ts ← 사용하지 않음
```
