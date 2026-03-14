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
| 6 | Animation | MEDIUM |
| 7 | Style Selection | MEDIUM |
| 8 | Charts & Data | LOW |

## 1. Accessibility (CRITICAL)

- `color-contrast` - 일반 텍스트 최소 4.5:1 비율
- `focus-states` - interactive 요소에 visible focus ring
- `alt-text` - 의미 있는 이미지에 descriptive alt text
- `aria-labels` - icon-only 버튼에 aria-label
- `keyboard-nav` - Tab 순서가 시각적 순서와 일치
- `form-labels` - label과 for 속성 사용

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

## 4. Layout & Responsive (HIGH)

- `viewport-meta` - width=device-width initial-scale=1
- `readable-font-size` - 모바일 body text 최소 16px
- `horizontal-scroll` - 콘텐츠가 viewport 너비에 맞도록
- `z-index-management` - z-index 스케일 정의 (10, 20, 30, 50)

## 5. Typography & Color (MEDIUM)

- `line-height` - body text에 1.5-1.75 사용
- `line-length` - 행당 65-75자 제한
- `font-pairing` - heading/body 폰트 성격 매칭

## 6. Animation (MEDIUM)

- `duration-timing` - micro-interaction에 150-300ms
- `transform-performance` - width/height 대신 transform/opacity 사용
- `loading-states` - Skeleton screen 또는 spinner

## 7. Style Selection (MEDIUM)

- `style-match` - 제품 유형에 맞는 스타일
- `consistency` - 모든 페이지에서 동일한 스타일
- `no-emoji-icons` - SVG 아이콘 사용, 이모지 금지

## 8. Charts & Data (LOW)

- `chart-type` - 데이터 유형에 맞는 차트
- `color-guidance` - 접근성 있는 색상 팔레트
- `data-table` - 접근성을 위한 테이블 대안 제공

## 검색 명령어 빠른 참조

```bash
SCRIPT=".claude/skills/ui-ux-design/scripts/search.py"

# 디자인 시스템 생성
python3 $SCRIPT "<쿼리>" --design-system -p "EasyPeasyClaudeCodeDevkit" -f markdown

# 도메인 검색
python3 $SCRIPT "<키워드>" --domain <style|color|ux|chart|typography|landing|product|icons|react|web>

# 스택 검색
python3 $SCRIPT "<키워드>" --stack <nextjs|shadcn|react|html-tailwind>

# persist (저장)
python3 $SCRIPT "<쿼리>" --design-system --persist -p "EasyPeasyClaudeCodeDevkit" -o dev/docs/design [--page "페이지명"]
```
