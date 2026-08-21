# Styling

Tailwind CSS v4 + shadcn/ui 스타일 체계와 금지 패턴.

## 1. Tailwind v4 — CSS-first 구성

v4는 JS 설정 파일 없이 CSS에서 구성한다. 진입점은 `app/globals.css` 하나뿐이다.

```css
/* app/globals.css — shadcn/ui init이 생성하는 구조 */
@import "tailwindcss";
@import "tw-animate-css";

@custom-variant dark (&:is(.dark *));

:root {
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
  --radius: 0.625rem;
  /* …shadcn init이 생성하는 나머지 토큰 */
}

.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  /* …다크 값 오버라이드 */
}

@theme inline {
  --color-background: var(--background);
  --color-foreground: var(--foreground);
  --color-primary: var(--primary);
  --color-primary-foreground: var(--primary-foreground);
  --color-muted-foreground: var(--muted-foreground);
  --color-destructive: var(--destructive);
  --color-border: var(--border);
  --radius-lg: var(--radius);
  /* …@theme 매핑으로 bg-background 등 유틸리티가 생성된다 */
}
```

- `tailwind.config.js`를 새로 만들지 않는다 — 토큰 추가는 `@theme`에서
- 커스텀 토큰 추가 예: `@theme inline { --color-brand: var(--brand); }`
  → `bg-brand`, `text-brand` 유틸리티가 자동 생성

## 2. 시맨틱 토큰 우선

raw 색상 대신 의미 기반 토큰을 쓴다 — 다크 모드가 공짜로 따라온다.

```tsx
// Good: 시맨틱 토큰 — .dark에서 자동 반전
<div className="bg-background text-foreground border-border" />
<p className="text-muted-foreground">보조 설명</p>
<p className="text-destructive">에러 메시지</p>

// Bad: raw 색상 — 다크 모드에서 깨진다
<div className="bg-white text-black border-gray-200" />
```

## 3. shadcn/ui 워크플로

```bash
npx shadcn@latest init            # 최초 1회 — globals.css·lib/utils.ts 구성
npx shadcn@latest add button input dialog skeleton
```

- 컴포넌트는 **코드로 복사**되어 `components/ui/`에 들어온다 — 우리 소유이므로
  직접 수정해도 된다. 단, 수정은 프로젝트 전역 요구일 때만 (개별 화면 요구는 `className`으로)
- 스타일 확장은 사용처에서 `className` → 내부 `cn()`이 Tailwind 충돌을 병합한다
- 새 원시 UI가 필요하면 직접 만들기 전에 shadcn/ui 카탈로그를 먼저 확인한다

```ts
// lib/utils.ts — 모든 조건부 클래스 조합의 표준
import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}
```

## 4. 변형(variant)은 CVA로

boolean props 증식 대신 `variant`/`size` 축으로 통제한다 — shadcn/ui와 같은 방식.

```tsx
import { cva, type VariantProps } from 'class-variance-authority'
import { cn } from '@/lib/utils'

const badgeVariants = cva(
  'inline-flex items-center rounded-md px-2 py-0.5 text-xs font-medium',
  {
    variants: {
      variant: {
        default: 'bg-primary text-primary-foreground',
        outline: 'border border-border text-foreground',
        destructive: 'bg-destructive text-white',
      },
    },
    defaultVariants: { variant: 'default' },
  }
)

interface BadgeProps
  extends React.HTMLAttributes<HTMLSpanElement>,
    VariantProps<typeof badgeVariants> {}

export function Badge({ className, variant, ...props }: BadgeProps) {
  return <span className={cn(badgeVariants({ variant }), className)} {...props} />
}
```

## 5. 반응형·다크 모드

```tsx
// 모바일 퍼스트: 기본값이 모바일, 브레이크포인트로 확장
<div className="grid grid-cols-1 gap-4 md:grid-cols-2 lg:grid-cols-3" />

// 다크 모드: .dark 클래스 토글 (@custom-variant 설정 기준)
// 시맨틱 토큰을 쓰면 dark: 접두사가 거의 필요 없다.
// 토큰 밖의 예외적 경우에만 dark: 사용
<div className="shadow-sm dark:shadow-none" />
```

다크 모드 토글은 `<html>`에 `.dark` 클래스를 넣고 빼는 클라이언트 컴포넌트로 구현하고,
첫 페인트 깜빡임(FOUC)을 막으려면 루트 layout의 inline script로 클래스를 선적용한다.

## 6. 클래스 작성 컨벤션

- 순서: 레이아웃(flex/grid) → 크기/간격 → 타이포 → 색 → 테두리/그림자 → 상태(hover 등)
  — `prettier-plugin-tailwindcss`를 쓰면 자동 정렬된다
- 조건부 클래스는 항상 `cn()` — 문자열 템플릿 조합 금지 (충돌 병합이 안 된다)
- 반복되는 클래스 묶음은 CSS로 추상화하지 말고 **컴포넌트로 추출**한다
  (resources/component-patterns.md의 2회 검토 · 3회 필수 규칙)

## 7. 금지 패턴

- **인라인 `style` 속성** — 예외는 런타임 계산값뿐 (진행률 `width`, 동적 좌표)
- **런타임 CSS-in-JS 라이브러리 추가** — Server Component와 충돌, 이 스택에 없음
- **컴포넌트별 개별 CSS 파일 추가** — 전역 스타일 파일은 `app/globals.css` 하나만
- **시맨틱 토큰이 있는데 raw 색상 사용** — `bg-white` 대신 `bg-background`
- **임의 값 남용** (`w-[137px]`) — 스케일 값으로 표현 불가한지 먼저 검토
- **`@apply` 남용** — 반복은 컴포넌트 추출로 해결, `@apply`는 전역 base 스타일 정도만
- **`tailwind.config.js` 신규 생성** — v4는 `@theme`으로 구성 (JS config는 레거시 호환용)
