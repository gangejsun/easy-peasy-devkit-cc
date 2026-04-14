# UI/UX Design Quick Reference

디자인 작업 시 우선순위별 참조 가이드.

## 규칙 우선순위

| 순위 | 카테고리 | 영향도 |
|------|----------|--------|
| 1 | Accessibility | CRITICAL |
| 2 | Touch & Interaction | CRITICAL |
| 3 | Performance | HIGH |
| 4 | Layout & Responsive | HIGH |
| 5 | Typography & Color | MEDIUM |
| 6 | Animation & Interaction | MEDIUM |
| 7 | Style Selection | MEDIUM |
| 8 | Anti-Patterns | MEDIUM |
| 9 | Charts & Data | LOW |

## 1. Accessibility (CRITICAL)

- `color-contrast` - 일반 텍스트 최소 4.5:1 비율
- `focus-states` - interactive 요소에 visible focus ring
- `alt-text` - 의미 있는 이미지에 descriptive alt text
- `aria-labels` - icon-only 버튼에 aria-label
- `keyboard-nav` - Tab 순서가 시각적 순서와 일치
- `form-labels` - label과 for 속성 사용
- `color-only` - 색상만으로 정보 전달 금지 (아이콘+텍스트 병행)
- `skip-nav` - 첫 focusable 요소로 skip-to-main-content 링크

## 2. Touch & Interaction (CRITICAL)

- `touch-target-size` - 최소 44x44px 터치 타겟
- `hover-vs-tap` - primary interaction은 click/tap 사용
- `loading-buttons` - async 작업 중 버튼 disable
- `error-feedback` - 문제 지점 근처에 명확한 에러 메시지
- `cursor-pointer` - 클릭 가능 요소에 cursor-pointer

## 3. Performance (HIGH)

- `image-optimization` - WebP, srcset, lazy loading 사용
- `reduced-motion` - prefers-reduced-motion 확인
- `content-jumping` - async 콘텐츠에 공간 예약
- `gpu-animation` - transform/opacity만 애니메이션 (GPU 가속)

## 4. Layout & Responsive (HIGH)

- `viewport-meta` - width=device-width initial-scale=1
- `readable-font-size` - 모바일 body text 최소 16px
- `horizontal-scroll` - 콘텐츠가 viewport 너비에 맞도록
- `z-index-management` - z-index 스케일 정의 (10, 20, 30, 50)

## 5. Typography & Color (MEDIUM)

- `line-height` - body text에 1.5-1.75 사용
- `line-length` - 행당 65-75자 제한
- `font-pairing` - heading/body 폰트 성격 매칭
- `color-60-30-10` - 60% background, 30% primary, 10% accent
- `semantic-tokens` - raw hex 대신 CSS 변수 사용
- `max-3-colors` - primary + secondary + accent. 나머지 파생

## 6. Animation & Interaction (MEDIUM)

### Micro-Interactions (150-300ms)
- `button-hover` - scale(1.02) + translateY(-1px) + shadow lift
- `input-focus` - ring + border-color shift + label float
- `card-hover` - shadow elevation + subtle translateY
- `toggle-switch` - spring easing 전환
- `ripple-effect` - 클릭 지점에서 확산

### Scroll Animations (400-800ms)
- `staggered-entrance` - 자식 요소 순차 fade-up (100ms 딜레이)
- `parallax` - 배경/전경 속도 차이 (배경 0.5x)
- `reveal-on-scroll` - IntersectionObserver로 viewport 진입 시 트리거
- `progress-indicator` - 스크롤 진행률 표시

### Performance Rules
- `gpu-only` - transform/opacity만 사용. width/height/top/left 금지
- `max-concurrent` - 동시 애니메이션 최대 2개
- `reduced-motion` - `@media (prefers-reduced-motion: no-preference)` 래핑 필수
- `easing-guide` - 진입: ease-out, 퇴장: ease-in, 전환: ease-in-out

## 7. Style Selection (MEDIUM)

- `style-match` - 제품 유형에 맞는 스타일
- `consistency` - 모든 페이지에서 동일한 스타일
- `no-emoji-icons` - SVG 아이콘 사용, 이모지 금지

## 8. Anti-Patterns (MEDIUM)

### Design Anti-Patterns
- `flash-over-function` - 시각 효과보다 기능 우선
- `low-contrast` - 텍스트 대비율 4.5:1 미만 금지
- `over-clutter` - 한 화면에 최대 3개 초점
- `font-soup` - 최대 2개 폰트 패밀리
- `tiny-targets` - 44x44px 미만 터치 타겟 금지

### UX Anti-Patterns
- `form-frustration` - 5개 초과 필드 노출 금지 (점진적 공개)
- `content-wall` - 가치 보여주기 전 로그인 요구 금지
- `dark-patterns` - 사용자 기만 UI 금지
- `dead-end-error` - 해결 방법 없는 에러 메시지 금지

## 검색 명령어 빠른 참조

```bash
SCRIPT=".claude/skills/ui-ux-design/scripts/search.py"

# 디자인 시스템 생성
python3 $SCRIPT "<쿼리>" --design-system -p "EasyPeasyClaudeCodeDevkit" -f markdown

# 도메인 검색
python3 $SCRIPT "<키워드>" --domain <style|color|ux|chart|typography|landing|product|icons|react|web|animation|anti-pattern>

# 스택 검색
python3 $SCRIPT "<키워드>" --stack <nextjs|shadcn|react|html-tailwind>

# persist (저장)
python3 $SCRIPT "<쿼리>" --design-system --persist -p "EasyPeasyClaudeCodeDevkit" -o dev/docs/design [--page "페이지명"]
```
