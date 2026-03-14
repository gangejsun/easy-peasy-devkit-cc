# Styling Guide

## Tailwind CSS v4 + shadcn/ui

### 기본 원칙

- Tailwind utility classes가 주 스타일링 방법
- `cn()` 유틸로 조건부 클래스 조합
- shadcn/ui 컴포넌트를 기본 UI 빌딩 블록으로 사용
- CSS 변수 기반 테마 (oklch 색상 모델)

---

## cn() 유틸리티

```typescript
// lib/utils.ts
import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
```

### 사용 패턴

```typescript
import { cn } from "@/lib/utils";

// 기본 사용
<div className={cn("px-4 py-2", className)} />

// 조건부 클래스
<button
  className={cn(
    "px-4 py-2 rounded-md font-medium transition-colors",
    isActive && "bg-primary text-primary-foreground",
    isDisabled && "opacity-50 cursor-not-allowed",
    className
  )}
/>

// variant 패턴
<div
  className={cn(
    "rounded-lg border p-4",
    variant === "default" && "bg-background",
    variant === "destructive" && "bg-destructive/10 border-destructive",
    variant === "success" && "bg-green-50 border-green-200"
  )}
/>
```

---

## shadcn/ui 컴포넌트

### 설치

```bash
pnpm dlx shadcn@latest add button card input
```

### 사용

```typescript
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
```

### 커스터마이징

shadcn/ui 컴포넌트는 `components/ui/`에 소스 코드로 존재하므로 직접 수정 가능:

```typescript
// components/ui/button.tsx 수정 가능
// 하지만 가능하면 className prop으로 오버라이드 우선
<Button className="w-full" variant="outline" size="lg">
  Submit
</Button>
```

---

## Responsive Design

```typescript
// 모바일 우선 (기본 → sm → md → lg → xl → 2xl)
<div className="px-4 sm:px-6 md:px-8 lg:px-12">
  <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
    {items.map((item) => (
      <ItemCard key={item.id} item={item} />
    ))}
  </div>
</div>

// 숨김/표시
<div className="hidden md:block">Desktop only</div>
<div className="md:hidden">Mobile only</div>

// 텍스트 크기
<h1 className="text-2xl sm:text-3xl lg:text-4xl font-bold">Title</h1>
```

---

## Theme Colors

CSS 변수 기반 테마 (globals.css에서 정의):

```typescript
// Tailwind에서 테마 색상 사용
<div className="bg-background text-foreground" />
<div className="bg-card text-card-foreground" />
<div className="bg-primary text-primary-foreground" />
<div className="bg-secondary text-secondary-foreground" />
<div className="bg-muted text-muted-foreground" />
<div className="bg-destructive text-destructive-foreground" />
<div className="border-border" />
<div className="ring-ring" />
```

### 다크 모드

```typescript
// globals.css에서 .dark 클래스로 테마 전환
// Tailwind의 dark: prefix 사용 가능
<div className="bg-white dark:bg-gray-900" />

// 하지만 CSS 변수 사용 시 자동 전환되므로 dark: 불필요
<div className="bg-background" /> // light/dark 자동 적용
```

---

## Common Patterns

### Flexbox

```typescript
// 수평 정렬
<div className="flex items-center gap-2">
<div className="flex items-center justify-between">
<div className="flex items-center justify-center">

// 수직 정렬
<div className="flex flex-col gap-4">

// 양쪽 정렬
<div className="flex items-center justify-between">
  <span>Left</span>
  <span>Right</span>
</div>
```

### Grid

```typescript
<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
<div className="grid grid-cols-12 gap-4">
  <div className="col-span-8">Main</div>
  <div className="col-span-4">Sidebar</div>
</div>
```

### Spacing

```typescript
// 간격 체계: 4px 단위 (p-1 = 4px, p-2 = 8px, p-4 = 16px, ...)
<div className="p-4">          {/* padding: 16px */}
<div className="px-4 py-2">   {/* x:16px, y:8px */}
<div className="space-y-4">   {/* 자식 간 간격 16px */}
<div className="gap-4">       {/* flex/grid 간격 16px */}
<div className="mt-8 mb-4">   {/* margin */}
```

### Typography

```typescript
<h1 className="text-3xl font-bold tracking-tight" />
<h2 className="text-2xl font-semibold" />
<p className="text-muted-foreground" />
<small className="text-sm text-muted-foreground" />
<span className="text-xs font-medium" />

// line-clamp (텍스트 줄 제한)
<p className="line-clamp-2">{longText}</p>
<p className="line-clamp-3">{longText}</p>
<p className="truncate">{longText}</p>  {/* 1줄 */}
```

### Borders & Shadows

```typescript
<div className="border rounded-lg" />
<div className="border-b border-border" />
<div className="shadow-sm" />
<div className="shadow-md hover:shadow-lg transition-shadow" />
<div className="ring-1 ring-border" />
```

### Animation

```typescript
<div className="transition-all duration-200" />
<div className="hover:scale-105 transition-transform" />
<div className="animate-pulse" />    {/* 스켈레톤 로딩 */}
<div className="animate-spin" />     {/* 스피너 */}
```

---

## Anti-Patterns

```typescript
// bad: 인라인 style
<div style={{ padding: "16px", marginTop: "8px" }} />
// good:
<div className="p-4 mt-2" />

// bad: CSS 모듈 (Tailwind 프로젝트에서)
import styles from "./Component.module.css";
// good: Tailwind utility classes 사용

// bad: 중복 클래스
<div className="p-4 p-4" />  // twMerge가 처리하지만 불필요
// good:
<div className="p-4" />

// bad: 하드코딩된 색상
<div className="bg-[#1a1a1a]" />
// good: 테마 변수 사용
<div className="bg-background" />
```
