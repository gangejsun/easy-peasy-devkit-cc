---
name: nextjs-ui-ux-design
description: |
  [Preset: nextjs-supabase] UI/UX 디자인 인텔리전스. 67가지 UI 스타일, 96개 색상 팔레트, 57개 폰트 페어링,
  100개 산업별 추론 규칙, 25개 차트 유형을 기반으로 디자인 시스템을 생성합니다.
  사용자가 UI/UX 디자인, 화면 설계, 디자인 시스템 생성, 색상/타이포그래피/스타일 선택,
  랜딩 페이지 설계, 대시보드 레이아웃, 컴포넌트 스타일링을 요청할 때 사용합니다.
  새로운 페이지나 화면을 만들 때, 디자인 가이드가 필요할 때에도 사용됩니다.
  Use ONLY when the active preset matches.
---

# UI/UX Design Intelligence

BM25 기반 검색 엔진을 활용한 디자인 인텔리전스 스킬. 산업별 추론 규칙과 CSV 데이터베이스에서 최적 디자인 시스템을 생성한다.

**출처**: [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) v2.2.1

## 검색 도메인

| 도메인 | 데이터 | 용도 |
|--------|--------|------|
| `product` | products.csv (100+) | 제품 카테고리 기반 UI 패턴 |
| `style` | styles.csv (67) | 비주얼 스타일 추천 |
| `color` | colors.csv (96) | 색상 팔레트 |
| `typography` | typography.csv (57) | 폰트 페어링 |
| `landing` | landing.csv | 랜딩 페이지 패턴 |
| `chart` | charts.csv (25) | 데이터 시각화 |
| `ux` | ux-guidelines.csv (99) | UX 모범사례 |
| `react` | react-performance.csv | React 성능 최적화 |
| `web` | web-interface.csv | 웹 인터페이스 패턴 |
| `icons` | icons.csv | 아이콘 라이브러리 추천 |

## 워크플로우

### Step 1: 작업 유형 판별

사용자 요청에서 작업 유형을 판별하고 해당 Step으로 분기:

| 작업 유형 | 판별 조건 | 실행 Step |
|----------|----------|----------|
| 디자인 시스템 생성 | 새 프로젝트, 전체 스타일 가이드, 디자인 리뉴얼 | Step 2 → Step 3 → Step 4 → Step 5 |
| 페이지별 디자인 | 특정 페이지/화면 디자인 | Step 2(페이지 모드) → Step 3 → Step 5 |
| 도메인 검색 | 특정 영역(색상, 타이포, 스타일 등) 정보만 필요 | Step 3 |
| 스택 가이드라인 | 프레임워크별 구현 가이드 필요 | Step 4 |

요구사항에서 추출할 정보:
- **제품 유형**: e-commerce, SaaS 등 (기본: E-commerce)
- **스타일 키워드**: minimal, modern, glassmorphism 등
- **산업/도메인**: e-commerce, 커뮤니티, 서비스 등
- **스택**: nextjs, shadcn, react, html-tailwind (기본: nextjs + shadcn)

### Step 2: 디자인 시스템 생성

`-p` 옵션에 프로젝트명 전달 (EasyPeasyClaudeCodeDevkit: `-p "EasyPeasyClaudeCodeDevkit"`).

전체 디자인 시스템:

```bash
python3 .claude/skills/ui-ux-design/scripts/search.py "<제품유형> <산업> <키워드>" --design-system -p "<프로젝트명>" -f markdown
```

persist 모드 (지속적 참조용):

```bash
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --design-system --persist -p "<프로젝트명>" -o dev/docs/design
```

페이지별 오버라이드:

```bash
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --design-system --persist -p "<프로젝트명>" -o dev/docs/design --page "<페이지명>"
```

출력 구조:
```
dev/docs/design/<project-slug>/
├── MASTER.md          # 전체 디자인 시스템
└── pages/
    └── <page>.md      # 페이지별 오버라이드
```

### Step 3: 도메인별 보충 검색

특정 영역의 상세 정보가 필요할 때:

```bash
# 스타일 검색
python3 .claude/skills/ui-ux-design/scripts/search.py "modern e-commerce card" --domain style

# 색상 팔레트
python3 .claude/skills/ui-ux-design/scripts/search.py "trust marketplace" --domain color

# UX 가이드라인
python3 .claude/skills/ui-ux-design/scripts/search.py "group buying flow" --domain ux

# 차트 추천
python3 .claude/skills/ui-ux-design/scripts/search.py "progress tracker" --domain chart

# 폰트 페어링
python3 .claude/skills/ui-ux-design/scripts/search.py "modern clean korean" --domain typography
```

### Step 4: 스택 가이드라인 적용

```bash
# Next.js 특화 가이드라인
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --stack nextjs

# shadcn/ui 특화 가이드라인
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --stack shadcn

# Tailwind CSS 가이드라인
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --stack html-tailwind
```

### Step 5: 프론트엔드 가이드라인 연계

디자인 시스템을 코드로 구현할 때 `frontend-dev-guidelines` 스킬 규칙을 따른다:
- Server/Client Component 구분
- `function` 키워드 컴포넌트 선언
- `cn()` 유틸 + Tailwind CSS 스타일링
- shadcn/ui 컴포넌트 활용
- `@/` 경로 alias

## 품질 체크리스트 (Pre-Delivery)

구현 전 반드시 확인:
- [ ] 텍스트 대비율 4.5:1 이상
- [ ] 터치 타겟 최소 44x44px
- [ ] hover 상태가 레이아웃을 이동시키지 않을 것
- [ ] interactive 요소에 cursor-pointer
- [ ] SVG 아이콘 사용 (이모지 금지)
- [ ] 모바일 우선 반응형 (min 16px body text)
- [ ] 키보드 네비게이션 가능
- [ ] prefers-reduced-motion 체크

## 참조 문서

- 빠른 참조: [references/quick-reference.md](references/quick-reference.md)
- 프론트엔드 가이드라인: `.claude/skills/frontend-dev-guidelines/SKILL.md`
- 디자인 출력: `dev/docs/design/`

## 프로젝트 커스텀 리소스

> 아래 경로에 `.md` 파일이 존재하면 디자인 시스템 생성 시 자동으로 참조됩니다. 파일이 없으면 이 섹션은 무시됩니다.

| 카테고리 | 경로 | 이 스킬에서의 용도 |
|---------|------|-------------------|
| 디자인 원칙 | `.claude/resources/design-principles/` | UI/UX 디자인 결정 시 브랜드 가이드·디자인 원칙 적용 |
| 도메인 지식 | `.claude/resources/domain-knowledge/` | 도메인별 UX 패턴, 산업 특화 디자인 규칙 반영 |
