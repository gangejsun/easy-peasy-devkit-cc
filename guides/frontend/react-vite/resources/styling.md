<!-- epcc-pack: frontend/react-vite v3.12.0 -->
# Styling (Tailwind CSS v3)

Tailwind 유틸리티가 이 프로젝트의 **유일한** 스타일 체계다. CSS Modules, styled-components,
인라인 `style` 객체를 섞지 않는다 — 섞이는 순간 "이 값이 어디서 오는지"를 두 곳에서 찾게 된다.

## 1. 설정

```js
// tailwind.config.js
export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],   // 누락하면 클래스가 통째로 사라진다
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        // 색상은 의미 이름으로 — 화면에서 slate-700 같은 원시 값을 직접 고르지 않게 한다
        surface: { DEFAULT: '#ffffff', muted: '#f8fafc', border: '#e2e8f0' },
        brand: { 50: '#eef2ff', 500: '#6366f1', 600: '#4f46e5', 700: '#4338ca' },
        danger: { 50: '#fef2f2', 500: '#ef4444', 600: '#dc2626' },
      },
      borderRadius: { card: '0.625rem' },
    },
  },
  plugins: [],
};
```

```css
/* src/index.css — 이 세 지시문이 v3의 진입점이다 */
@tailwind base;
@tailwind components;
@tailwind utilities;
```

`content` 글롭이 실제 파일을 덮는지 확인한다. Tailwind는 소스를 **문자열로** 훑기 때문에,
스캔 범위 밖의 파일에서 쓴 클래스는 빌드 산출물에 존재하지 않는다.

## 2. `cn()` 헬퍼

<!-- file: src/lib/cn.ts -->
```ts
// src/lib/cn.ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
```

`twMerge`는 충돌하는 유틸리티 중 **뒤에 온 것**을 남긴다 (`px-4 px-6` → `px-6`).
이게 없으면 공통 컴포넌트의 기본 클래스를 호출부에서 덮을 수 없다.

## 3. 변형(variant) 정의

```tsx
const base = 'inline-flex items-center justify-center rounded-md font-medium ' +
  'transition-colors focus-visible:outline-none focus-visible:ring-2 ' +
  'focus-visible:ring-brand-500 disabled:pointer-events-none disabled:opacity-50';

const variants = {
  primary: 'bg-brand-600 text-white hover:bg-brand-700',
  secondary: 'border border-surface-border bg-white text-slate-700 hover:bg-surface-muted',
  danger: 'bg-danger-600 text-white hover:bg-danger-500',
  ghost: 'text-slate-600 hover:bg-surface-muted',
} as const;

const sizes = { sm: 'h-8 px-3 text-xs', md: 'h-10 px-4 text-sm', lg: 'h-12 px-6 text-base' } as const;

export type ButtonProps = ComponentPropsWithoutRef<'button'> & {
  variant?: keyof typeof variants;
  size?: keyof typeof sizes;
};
```

- `as const` + `keyof typeof`로 props 타입이 자동으로 따라온다 — 변형을 추가하면 타입도 늘어난다
- 클래스 문자열은 **완전한 형태**로 적는다 (아래 4항)

## 4. 동적 클래스 문자열 금지

```tsx
// ❌ 스캐너가 이 문자열을 못 본다 — 빌드된 CSS에 클래스가 없다
<span className={`text-${color}-500 bg-${tone}-50`} />

// ✅ 완전한 클래스를 맵으로 고른다
const toneClass = {
  info: 'text-sky-600 bg-sky-50',
  warn: 'text-amber-600 bg-amber-50',
  error: 'text-danger-600 bg-danger-50',
} as const;
<span className={toneClass[tone]} />
```

서버 응답에서 온 값으로 클래스를 만들어야 하는 정말 드문 경우에만 `safelist`를 쓴다.
`safelist`가 늘어나면 그건 데이터가 아니라 설계 문제다.

## 5. `@apply`는 예외적으로만

```css
/* ✅ 서드파티 마크업을 우리가 못 바꾸는 경우 */
.ProseMirror p { @apply my-2 leading-relaxed text-slate-700; }

/* ❌ 우리 컴포넌트를 클래스로 재발명 — 컴포넌트가 이미 그 일을 한다 */
.btn-primary { @apply inline-flex h-10 items-center rounded-md bg-brand-600 px-4 text-white; }
```

재사용 단위는 CSS 클래스가 아니라 **React 컴포넌트**다. `@apply`로 만든 클래스는
props도 타입도 없고, 어디서 쓰이는지 추적하기 어렵다.

## 6. 레이아웃과 반응형

```tsx
// 모바일 우선 — 접두사 없는 값이 작은 화면, 접두사가 큰 화면
<div className="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3">

// 간격은 gap으로. space-x/y는 자식 사이 마진이라 wrap·순서 변경에서 어긋난다
<div className="flex flex-wrap items-center gap-2">
```

- 임의 값(`w-[137px]`)은 1회성 미세 조정에만. 두 번 이상 나오면 `theme.extend`로 올린다
- 절대 위치보다 flex/grid를 먼저 시도한다
- 텍스트 말줄임은 `truncate`(1줄) / `line-clamp-2`(여러 줄)

## 7. 접근성 기본선

```tsx
// 포커스 링을 지우지 않는다. 마우스에서만 감추려면 focus-visible을 쓴다
className="focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2"

// 아이콘만 있는 버튼에는 접근 이름을 준다
<button aria-label="작업 삭제"><TrashIcon className="h-4 w-4" aria-hidden /></button>

// 시각적으로만 숨김 (display:none은 스크린리더에서도 사라진다)
<span className="sr-only">현재 페이지</span>
```

- 본문 대비는 `text-slate-700` 이상 (`text-slate-400`은 플레이스홀더 전용)
- 색만으로 상태를 표현하지 않는다 — 아이콘이나 텍스트를 함께 둔다
- 상호작용 대상의 최소 터치 크기는 `h-10 w-10`(40px) 이상

## 오용 목록 ① — v4 관용구를 v3에 쓰지 않는다

이 프로젝트의 기준선은 **tailwindcss@3**이다. 문서·블로그에서 본 v4 문법을 들여오면
빌드가 조용히 깨지거나 스타일이 통째로 사라진다.

| v4 관용구 (여기서는 오류) | v3 형태 |
| --- | --- |
| `@import "tailwindcss";` | `@tailwind base; @tailwind components; @tailwind utilities;` |
| CSS 안의 `@theme { --color-brand-500: … }` | `tailwind.config.js`의 `theme.extend.colors` |
| PostCSS 플러그인 `@tailwindcss/postcss` | `tailwindcss` (+ `autoprefixer`) |
| Vite 플러그인 `@tailwindcss/vite` | PostCSS 경유 — `postcss.config.js`에 등록 |
| 설정 없이 자동 소스 탐지 | `content: [...]` 글롭을 반드시 적는다 |
| `bg-linear-to-r` · `shadow-xs` · `outline-hidden` | `bg-gradient-to-r` · `shadow-sm` · `outline-none` — v4에서 이름이 바뀐 유틸리티들 |
| 기본 `border` 색이 `currentColor` | v3 기본은 `gray-200` — v4 기준 코드를 옮기면 테두리 색이 달라진다 |

`size-4`는 v4 전용이 **아니다.** v3.4에서 추가된 유틸리티이므로 이 기준선(`tailwindcss@3.4`)에서
그대로 쓴다 — `h-4 w-4`로 되돌릴 이유가 없다. v4 문법인지 판단이 서지 않으면 추측하지 말고
설치된 버전의 문서에서 확인한다.

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `gap` vs `space-x-*` | flex/grid 컨테이너는 `gap`. `space-*`는 자식 마진이라 줄바꿈·순서 변경·조건부 렌더에서 어긋난다 |
| `w-full` vs `flex-1` | 부모 너비 전체를 채우려면 `w-full`. 남는 공간을 형제와 나누려면 `flex-1 min-w-0` |
| `hidden` vs `sr-only` | 완전히 없애려면 `hidden`. 보이지 않지만 스크린리더에는 읽혀야 하면 `sr-only` |
| `focus:` vs `focus-visible:` | 키보드 사용자에게만 링을 보이려면 `focus-visible`. 무조건 `outline-none`만 주는 것은 접근성 위반 |
| 임의 값 `[#4f46e5]` vs 테마 토큰 | 색은 언제나 토큰. 임의 값은 크기·위치의 1회성 보정에만 |
| `overflow-hidden` vs `min-w-0` | flex 자식의 텍스트 넘침은 `min-w-0`가 없으면 `truncate`가 동작하지 않는다 |
| `dark:` vs 별도 테마 CSS | `darkMode: 'class'`이므로 루트 `<html>`의 클래스 토글 하나로 제어한다. 색을 두 벌 정의하지 않는다 |
