<!-- epcc-pack: frontend/vue v3.12.0 -->
# Styling (Tailwind CSS v3)

Tailwind 유틸리티가 이 프로젝트의 **유일한** 스타일 체계다. `<style scoped>`, CSS Modules,
인라인 `style` 객체를 섞지 않는다 — 섞이는 순간 "이 값이 어디서 오는지"를 두 곳에서 찾게 된다.

## 1. 설정

```js
// tailwind.config.js
export default {
  // .vue를 빼먹으면 클래스가 통째로 사라진다 — Vue 프로젝트의 1번 함정이다
  content: ['./index.html', './src/**/*.{vue,ts,tsx}'],
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
/* src/assets/main.css — 이 세 지시문이 v3의 진입점이다. main.ts가 이 파일을 import한다 */
@tailwind base;
@tailwind components;
@tailwind utilities;
```

Tailwind는 소스를 **문자열로** 훑는다. 스캔 범위 밖의 파일에서 쓴 클래스는 빌드 산출물에
존재하지 않는다. SFC의 `<template>`도 그 문자열 스캔의 대상이므로 규칙은 동일하다.

## 2. `cn()` 헬퍼

<!-- file: src/lib/cn.ts -->
```ts
// src/lib/cn.ts
import { clsx, type ClassValue } from 'clsx';
import { twMerge } from 'tailwind-merge';

export const cn = (...inputs: ClassValue[]) => twMerge(clsx(inputs));
```

`twMerge`는 충돌하는 유틸리티 중 **뒤에 온 것**을 남긴다 (`px-4 px-6` → `px-6`).
템플릿의 `:class` 배열·객체 문법은 병합을 하지 않고 이어 붙이기만 하므로, 충돌 가능한
클래스를 조합할 때는 `cn()`을 거친 `computed`를 쓴다.

```vue
<script setup lang="ts">
import { computed } from 'vue';
import { cn } from '@/lib/cn';

const props = defineProps<{ active: boolean; dense?: boolean }>();

// ✅ 충돌할 수 있는 조합은 cn()으로 — p-3와 p-6이 함께 남지 않는다
const rowClass = computed(() => cn('flex items-center p-6', props.dense && 'p-3',
  props.active && 'bg-brand-50 text-brand-700'));
</script>

<template>
  <!-- ✅ 충돌이 없는 상태 토글은 객체 문법으로 충분하다 -->
  <li :class="rowClass" />
  <li class="flex items-center" :class="{ 'font-semibold': active, 'opacity-50': !active }" />
</template>
```

## 3. 변형(variant) 정의는 SFC 밖에 둔다

`<script setup>`은 **값을** export할 수 없다. 여러 컴포넌트와 테스트가 같은 변형 표를
읽어야 하므로 표는 SFC 옆의 `.ts` 파일이 소유한다.

<!-- file: src/components/common/button-variants.ts -->
```ts
// src/components/common/button-variants.ts
import { cn } from '@/lib/cn';

export type ButtonVariant = 'primary' | 'secondary' | 'danger' | 'ghost';
export type ButtonSize = 'sm' | 'md' | 'lg';

const base = 'inline-flex items-center justify-center rounded-md font-medium transition-colors ' +
  'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-brand-500 ' +
  'disabled:pointer-events-none disabled:opacity-50';

const variants: Record<ButtonVariant, string> = {
  primary: 'bg-brand-600 text-white hover:bg-brand-700',
  secondary: 'border border-surface-border bg-white text-slate-700 hover:bg-surface-muted',
  danger: 'bg-danger-600 text-white hover:bg-danger-500',
  ghost: 'text-slate-600 hover:bg-surface-muted',
};

const sizes: Record<ButtonSize, string> = {
  sm: 'h-8 px-3 text-xs',
  md: 'h-10 px-4 text-sm',
  lg: 'h-12 px-6 text-base',
};

export function buttonClass(variant: ButtonVariant, size: ButtonSize): string {
  return cn(base, variants[variant], sizes[size]);
}
```

`Record<ButtonVariant, string>`이 변형을 추가할 때 표를 빠뜨리지 못하게 한다 — 키가
빠지면 타입 오류다. 클래스 문자열은 **완전한 형태**로 적는다 (§4).

## 4. 동적 클래스 문자열 금지

스캐너는 소스를 문자열로 읽으므로 실행 시점에 조립되는 이름을 볼 수 없다.

❌ 아래는 빌드된 CSS에 클래스가 존재하지 않는다:

```vue
<template>
  <span :class="`text-${color}-500 bg-${tone}-50`" />
</template>
```

```vue
<script setup lang="ts">
// ✅ 완전한 클래스를 맵으로 고른다
const toneClass = {
  info: 'text-sky-600 bg-sky-50',
  warn: 'text-amber-600 bg-amber-50',
  error: 'text-danger-600 bg-danger-50',
} as const;
const props = defineProps<{ tone: keyof typeof toneClass }>();
</script>

<template>
  <span :class="toneClass[props.tone]" />
</template>
```

서버 응답에서 온 값으로 클래스를 만들어야 하는 드문 경우에만 `safelist`를 쓴다.
`safelist`가 늘어나면 그건 데이터가 아니라 설계 문제다.

## 5. scoped CSS와 인라인 style을 쓰지 않는다

아래 두 형태는 이 스택에 없다. 첫째는 스타일 소스를 둘로 쪼개고(같은 여백이 클래스에도
CSS에도 있게 된다), 둘째는 값이 번들 문자열이 아니라 런타임 객체가 되어 디자인 토큰
대조가 불가능해진다.

❌ 하지 않는다:

```vue
<template>
  <div class="card" :style="{ padding: dense ? '12px' : '24px' }">…</div>
</template>

<style scoped>
.card { border-radius: 10px; padding: 24px; }
</style>
```

허용되는 예외는 **계산해야만 나오는 수치**뿐이다: 드래그 좌표, 측정한 높이, 진행률 폭.
그 경우에도 CSS 변수 하나로 좁힌다.

```vue
<template>
  <div class="h-2 rounded-full bg-brand-600" :style="{ width: percent + '%' }" />
</template>
```

`@apply`는 서드파티 마크업을 우리가 못 바꿀 때만 쓴다. 우리 UI의 재사용 단위는 CSS
클래스가 아니라 **컴포넌트**다 — `@apply`로 만든 클래스는 props도 타입도 없다.

```css
/* ✅ 우리가 마크업을 소유하지 않는 영역 */
.ProseMirror p { @apply my-2 leading-relaxed text-slate-700; }
```

## 6. 레이아웃과 반응형

```vue
<template>
  <!-- 모바일 우선 — 접두사 없는 값이 작은 화면, 접두사가 큰 화면 -->
  <div class="grid grid-cols-1 gap-4 md:grid-cols-2 xl:grid-cols-3" />

  <!-- 간격은 gap으로. space-x/y는 자식 사이 마진이라 wrap·조건부 렌더에서 어긋난다 -->
  <div class="flex flex-wrap items-center gap-2" />
</template>
```

- 임의 값(`w-[137px]`)은 1회성 미세 조정에만. 두 번 이상 나오면 `theme.extend`로 올린다
- 절대 위치보다 flex/grid를 먼저 시도한다
- 텍스트 말줄임은 `truncate`(1줄) / `line-clamp-2`(여러 줄)
- `<Transition>`·`<TransitionGroup>`의 클래스는 Tailwind 유틸리티로 준다
  (`enter-active-class="transition duration-150"`) — 전환용 CSS 블록을 만들지 않는다

## 7. 접근성 기본선

```vue
<template>
  <!-- 포커스 링을 지우지 않는다. 마우스에서만 감추려면 focus-visible을 쓴다 -->
  <button class="focus-visible:ring-2 focus-visible:ring-brand-500 focus-visible:ring-offset-2" />

  <!-- 아이콘만 있는 버튼에는 접근 이름을 준다 -->
  <button aria-label="작업 삭제"><TrashIcon class="size-4" aria-hidden="true" /></button>

  <!-- 시각적으로만 숨김 (hidden은 스크린리더에서도 사라진다) -->
  <span class="sr-only">현재 페이지</span>
</template>
```

- 본문 대비는 `text-slate-700` 이상 (`text-slate-400`은 플레이스홀더 전용)
- 색만으로 상태를 표현하지 않는다 — 아이콘이나 텍스트를 함께 둔다
- 상호작용 대상의 최소 터치 크기는 `size-10`(40px) 이상
- 사용자 입력에서 온 문자열을 `v-html`로 그리지 않는다. Vue의 보간(`{{ }}`)은 자동
  이스케이프하지만 `v-html`은 그 방어를 통째로 끈다

## 오용 목록 ① — v4 관용구를 v3에 쓰지 않는다

이 프로젝트의 기준선은 **tailwindcss@3.4**다. 문서·블로그에서 본 v4 문법을 들여오면
빌드가 조용히 깨지거나 스타일이 통째로 사라진다.

| v4 관용구 (여기서는 오류) | v3 형태 |
| --- | --- |
| `@import "tailwindcss";` | `@tailwind base; @tailwind components; @tailwind utilities;` |
| CSS 안의 `@theme { --color-brand-500: … }` | `tailwind.config.js`의 `theme.extend.colors` |
| PostCSS 플러그인 `@tailwindcss/postcss` | `tailwindcss` (+ `autoprefixer`) |
| Vite 플러그인 `@tailwindcss/vite` | PostCSS 경유 — `postcss.config.js`에 등록 |
| 설정 없이 자동 소스 탐지 | `content: [...]` 글롭을 반드시 적는다 (`.vue` 포함) |
| `bg-linear-to-r` · `shadow-xs` · `outline-hidden` | `bg-gradient-to-r` · `shadow-sm` · `outline-none` |
| 기본 `border` 색이 `currentColor` | v3 기본은 `gray-200` — v4 기준 코드를 옮기면 테두리 색이 달라진다 |

`size-4`는 v4 전용이 **아니다.** v3.4에서 추가된 유틸리티이므로 이 기준선에서 그대로 쓴다.
v4 문법인지 판단이 서지 않으면 추측하지 말고 설치된 버전의 문서에서 확인한다.

## 오용 목록 ② — 혼동 쌍

| 혼동하는 짝 | 정확한 적용 조건 |
| --- | --- |
| `class` vs `:class` | 고정 문자열은 `class`. 둘을 같은 요소에 함께 써도 되고 Vue가 합친다 — 고정분을 `:class` 안으로 끌어들이지 않는다 |
| `:class` 객체·배열 vs `cn()` | 충돌하지 않는 토글은 객체 문법. **충돌 가능한 유틸리티**(여백·크기·색)를 조건부로 고를 때만 `cn()` — 객체 문법에는 tailwind-merge가 없다 |
| 호출부 `class` 폴스루 vs prop | 폴스루된 `class`는 루트 클래스에 **이어 붙기만** 한다. 컴포넌트가 소유한 토큰을 바꾸려는 의도라면 `variant`/`size` prop을 늘린다 |
| `:style` vs 유틸리티 클래스 | 값이 디자인 토큰이면 클래스. **런타임에 계산되는 수치**(진행률 폭, 측정 높이)만 `:style` |
| `<style scoped>` vs 유틸리티 | scoped는 쓰지 않는다. 서드파티 마크업이라 클래스를 못 붙이는 경우에만 전역 CSS + `@apply` |
| `gap` vs `space-x-*` | flex/grid 컨테이너는 `gap`. `space-*`는 자식 마진이라 줄바꿈·조건부 렌더에서 어긋난다 |
| `w-full` vs `flex-1` | 부모 너비 전체는 `w-full`. 남는 공간을 형제와 나누면 `flex-1 min-w-0` |
| `hidden` vs `sr-only` | 완전히 없애려면 `hidden`. 보이지 않지만 읽혀야 하면 `sr-only` |
| `v-show` vs `hidden` 클래스 | 토글은 `v-show`가 낫다 — `display` 제어가 한 곳에 남는다 |
| `focus:` vs `focus-visible:` | 키보드에만 링을 보이려면 `focus-visible`. `outline-none`만 주는 것은 접근성 위반 |
| 임의 값 `[#4f46e5]` vs 테마 토큰 | 색은 언제나 토큰. 임의 값은 크기·위치의 1회성 보정에만 |
| `overflow-hidden` vs `min-w-0` | flex 자식의 텍스트 넘침은 `min-w-0`가 없으면 `truncate`가 동작하지 않는다 |
| `dark:` vs 별도 테마 CSS | `darkMode: 'class'`이므로 루트 `<html>`의 클래스 토글 하나로 제어한다 |
