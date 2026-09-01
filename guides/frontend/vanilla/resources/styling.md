<!-- epcc-pack: frontend/vanilla v3.14.0 -->
# 스타일 — 레이어가 특정도 싸움을 대신하고, 컴포넌트가 자기 토큰을 소유한다

소유: `src/styles/tokens.css`(`@layer tokens`) · `src/styles/base.css`(`@layer base`) ·
`src/components/task-list.css`. 원장은 마지막 파일을 `taskListStyles`로 등재한다 — 코드에
그 식별자가 있다는 뜻이 아니라 **CSS 파일 하나가 심볼 단위**라는 뜻이다. 소유하지 않는 것 —
클래스를 실제로 붙이고 떼는 DOM 코드는 `resources/component-patterns.md`, 적재 중·빈·에러
화면의 구조는 `resources/loading-error-states.md`가 소유한다.

## 1. 결정 트리 — 이 값을 어디에 두는가

빌드 도구가 스코프를 만들어 주지 않는다. **파일과 이름 접두사가 유일한 스코프다.**

| 이 값은… | 두는 곳 | 왜 |
| --- | --- | --- |
| 두 컴포넌트 이상이 읽는 색·간격·타이포 | `src/styles/tokens.css` (`@layer tokens`) | 전역 토큰. 이름에 컴포넌트가 들어가면 안 된다 |
| 요소의 기본 모양 (`body` · `:focus-visible`) | `src/styles/base.css` (`@layer base`) | 레이어가 낮아 컴포넌트가 언제나 이긴다 |
| 한 컴포넌트의 높이·여백·타이포 | 그 컴포넌트의 CSS (`@layer components`) | `--task-row-height`처럼 접두사가 소유를 말한다 |
| 상태에 따라 달라지는 모양 | 수정자 클래스 (`.task-list__row--done`) | JS는 클래스만 토글하고 값은 CSS가 정한다 |
| 같은 컴포넌트의 다른 밀도 | 소유 파일 안의 수정자 (`.task-list--compact`) | 정의가 한 파일에 남는다 |
| JS가 **측정한** 값 | `style.setProperty('--task-row-height', …)` | 규칙이 아니라 값 하나만 넘긴다 |

## 2. 레이어 순서는 `index.html`이 못박는다

`@layer`의 순서는 **처음 등장한 순서**로 고정되고, 나중에 나온 순서 선언은 이미 자리를
잡은 레이어를 옮기지 못한다. 그래서 순서 선언을 CSS 파일 안에 두면 **모듈 import 순서에
매달린다.**

```html
<!-- index.html 의 <head> — 번들 스타일시트보다 먼저 파싱되는 유일한 자리다 -->
<style>@layer tokens, base, components;</style>
```

`main.js`가 `import './components/…'`을 스타일 import보다 먼저 쓰면 번들 CSS의 첫 줄이
`@layer components {`가 되고, 뒤늦게 나온 `@layer tokens, base, components;`는 무시된다 —
결과는 **`base`가 컴포넌트 규칙을 이기는** 정반대 순서다.
<!-- verified: vite@8.2.2 build 로 두 import 순서를 대조해 출력 CSS의 레이어 등장 순서가 뒤집히는 것을 관측 -->
`<head>`의 한 줄로 옮기면 import 순서와 무관해진다.
<!-- verified: 같은 실행에서 컴포넌트를 먼저 import해도 <style> 이 <link> 앞에 남는 것을 빌드 산출물로 확인 -->

## 3. 전역 토큰 (`src/styles/tokens.css`)

전역 토큰은 **두 컴포넌트 이상이 읽는 값만**이다. 하나만 읽는 값이 여기 올라오면 지울 때
누가 쓰는지 알 수 없어져 영원히 남는다.

```css
/* src/styles/tokens.css */
@layer tokens {
  :root {
    --color-surface: #ffffff;
    --color-text: #16181d;
    --color-muted: #6b7280;
    --color-accent: #2f6fed;
    --space-2: 0.5rem;
    --space-3: 1rem;
    --font-body: system-ui, sans-serif;
    --size-body: 1rem;
  }

  @media (prefers-color-scheme: dark) {
    :root {
      --color-surface: #14161a;
      --color-text: #e8eaed;
      --color-muted: #9aa1ab;
    }
  }
}
```

- **다크 모드는 토큰 값만 바꾼다.** 컴포넌트 규칙을 다시 쓰기 시작하면 두 벌이 되고
  한쪽만 고치는 날이 온다
- **이름에 컴포넌트를 넣지 않는다.** `--task-row-height`가 여기 있으면 전역인지 컴포넌트
  소유인지 이름으로 구분할 수 없다
- 커스텀 프로퍼티는 **상속된다.** `:root`에 두면 모든 컴포넌트가 읽고, 컴포넌트 블록에
  두면 그 서브트리만 읽는다 — §5가 이 성질을 그대로 쓴다

## 4. 요소 기본값 (`src/styles/base.css`)

리셋과 요소 기본값은 `@layer base`에 둔다. 레이어가 `components`보다 **낮으므로**
컴포넌트 규칙이 특정도와 무관하게 이긴다 — `!important`도, 선택자 중첩도 필요 없다.

```css
/* src/styles/base.css */
@layer base {
  *, *::before, *::after { box-sizing: border-box; }

  body {
    margin: 0;
    font-family: var(--font-body);
    font-size: var(--size-body);
    color: var(--color-text);
    background: var(--color-surface);
  }

  :focus-visible { outline: 2px solid var(--color-accent); outline-offset: 2px; }
}
```

`:focus-visible`을 여기서 한 번 정의하고 컴포넌트에서 지우지 않는다. 프레임워크가 없어
포커스 링을 되돌려 주는 층이 따로 없다 — 지우면 키보드 사용자가 위치를 잃는다.

## 5. 컴포넌트가 소유하는 토큰 (`src/components/task-list.css`)

**컴포넌트 토큰은 컴포넌트 블록 안에서 정의한다.** `:root`가 아니다 — 서브트리에만
상속되므로 이름 충돌 걱정 없이 짧게 쓸 수 있고, 파일을 지우면 토큰도 함께 사라진다.
이 파일은 `src/components/task-list.js`가 첫 줄에서 `import './task-list.css';`로 끌어온다 —
컴포넌트를 지우면 스타일도 번들에서 빠진다. 그 import가 §2의 순서 함정을 만드는 자리다.

```css
/* src/components/task-list.css */
@layer components {
  .task-list {
    --task-row-height: 2.75rem;
    --task-row-gap: var(--space-2);
    --task-row-title-size: var(--size-body);

    margin: 0;
    padding: 0;
    list-style: none;
  }

  .task-list--compact { --task-row-height: 2rem; }

  .task-list__row {
    display: flex;
    align-items: center;
    gap: var(--task-row-gap);
    block-size: var(--task-row-height);
    padding-inline: var(--space-3);
  }

  .task-list__title {
    font-size: var(--task-row-title-size);
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }

  .task-list__row--done .task-list__title {
    color: var(--color-muted);
    text-decoration: line-through;
  }
}
```

높이·간격·글자 크기가 **이 파일에서만 정의된다.** 다른 밀도가 필요하면 규칙을 다시
쓰지 않고 값만 재대입한다.

```css
/* ❌ 사용처가 규칙을 다시 쓴다 — 행 높이의 진실이 두 곳이 된다 */
.task-list__row { block-size: 2rem; }
/* ✅ 소유 파일 안의 수정자로 값만 바꾼다. 호출자는 클래스 하나를 더 붙일 뿐이다 */
.task-list--compact { --task-row-height: 2rem; }
```

컴포넌트 토큰은 전역 토큰을 **기본값으로 참조한다**(`var(--space-2)`). 그래야 전역
간격 척도를 바꿨을 때 컴포넌트가 따라오고, 그럼에도 이 컴포넌트만 예외로 두고 싶으면
한 줄만 고치면 된다.

## 6. 클래스 이름 규약

**접두사가 유일한 스코프다.** 스코프드 스타일도, CSS Modules의 해시도 없다.

| 형태 | 뜻 | 예 |
| --- | --- | --- |
| `.<컴포넌트 파일 이름>` | 블록. 루트 요소 하나 | `.task-list` |
| `.<블록>__<요소>` | 그 블록 안의 부품 | `.task-list__row` · `.task-list__title` |
| `.<블록>--<수정자>` · `.<블록>__<요소>--<수정자>` | 변형·상태 | `.task-list--compact` · `.task-list__row--done` |

- **접두사 = 파일 이름 = 마운트 함수 이름.** `src/components/task-list.js`의
  `mountTaskList`가 `.task-list*`를 소유한다. 셋이 갈리면 CSS를 지울 때 무엇이 죽는지 모른다
- **요소 선택자와 자손 깊이로 쓰지 않는다.** `.task-list li span`은 `<template>` 마크업을
  한 번 바꾸면 조용히 죽고, 죽어도 아무 도구가 알려 주지 않는다
- **클래스 문자열은 JS와 CSS 두 곳에 산다.** 어느 쪽도 상대를 검사하지 않으므로
  `rg "task-list__" src/`가 대조 수단이다. 이름을 바꾸면 두 곳을 같은 커밋에서 바꾼다
- **상태는 클래스로, 값은 CSS로.** JS는 `classList.toggle('task-list__row--done', …)`까지만
  하고 그 상태가 무엇으로 보이는지는 이 파일이 정한다

## 7. 인라인 스타일 금지 경계

인라인 `style` 속성은 **모든 레이어 바깥**이라 `@layer`로 이길 수 없다. 한 번 쓰기
시작하면 다음 사람은 `!important`로 대응하고, 그 시점에 레이어 설계가 무의미해진다.

```js
// ❌ 규칙을 문자열로 만들어 싣는다 — 레이어 밖이고, 값이 사용자 입력이면 표면이 하나 는다
row.setAttribute('style', `block-size:${h}px;color:red`);
// ✅ 값 하나만 커스텀 프로퍼티로 넘기고 규칙은 CSS 에 남긴다
list.style.setProperty('--task-row-height', `${h}px`);
```

허용되는 자리는 **JS만 알 수 있는 측정값 하나를 넘길 때**다 — 컨테이너 실측 높이,
가상 스크롤 오프셋처럼 CSS가 알 수 없는 값. 그때도 넘기는 것은 **값**이지 규칙이 아니다.
`el`의 `props`에 `style`을 싣지 않는다는 규칙도 같은 이유이고, 사용자 입력이 섞이면
`style` 속성은 배경 이미지 URL 같은 표면을 하나 더 연다.

## 오용 목록 ① — Tailwind · CSS-in-JS 습관 → 플레인 CSS + `@layer` 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `className="flex items-center h-11"` | 클래스 하나(`.task-list__row`) + 소유 파일의 규칙 |
| `styled.li` 템플릿 리터럴 · `css={{ … }}` prop | `src/components/task-list.css` — 파일이 스코프다 |
| CSS Modules의 `styles.row` | 접두사 규약이 그 자리다. 해시가 없으므로 이름이 계약이다 |
| `!important`로 특정도 싸움 | `@layer` 순서로 이긴다. 필요하면 레이어를 옮긴다 |
| 다크모드에서 컴포넌트 규칙을 재선언 | `prefers-color-scheme` 안에서 **토큰 값만** 바꾼다 |
| 인라인 `style`로 동적 값 | `style.setProperty('--task-row-height', …)` |
| `:root`에 컴포넌트 토큰 | 컴포넌트 블록(`.task-list`)에 둔다 — 지울 때 함께 사라진다 |
| 유틸리티 클래스를 직접 만든다 | 전역 토큰 + 컴포넌트 규칙. 유틸리티는 소유자가 없다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 전역 토큰 vs 컴포넌트 토큰 | 두 컴포넌트 이상이 읽으면 앞, 한 컴포넌트가 소유하면 뒤 |
| `@layer base` vs `@layer components` | 요소 기본값은 앞, 클래스 규칙은 뒤 |
| 수정자 클래스 vs 새 컴포넌트 | 값만 다르면 앞, 구조가 다르면 뒤 |
| `block-size` 재선언 vs 커스텀 프로퍼티 재대입 | **언제나 뒤.** 규칙은 소유 파일에만 있다 |
| `style.setProperty(…)` vs `setAttribute('style', …)` | 값 하나면 앞. 뒤는 규칙을 문자열로 만드는 것이다 |
| `:root` vs 컴포넌트 블록에 토큰 선언 | 전 화면이 읽으면 앞, 서브트리만 읽으면 뒤 |
| `.task-list__row--done` vs `.done` | **언제나 앞.** 접두사 없는 이름은 소유자가 없다 |
