---
name: ui-ux-design
description: |
  UI/UX 디자인 인텔리전스. 67가지 UI 스타일, 96개 색상 팔레트, 57개 폰트 페어링,
  55개 애니메이션 효과, 38개 안티패턴, 100개 산업별 추론 규칙, 25개 차트 유형을 기반으로
  5-Dimension 디자인 시스템을 생성합니다.
  사용자가 UI/UX 디자인, 화면 설계, 디자인 시스템 생성, 색상/타이포그래피/스타일 선택,
  랜딩 페이지 설계, 대시보드 레이아웃, 컴포넌트 스타일링, 애니메이션/인터랙션을 요청할 때 사용합니다.
  새로운 페이지나 화면을 만들 때, 디자인 가이드가 필요할 때에도 사용됩니다. (project)
---

# UI/UX Design Intelligence

BM25 기반 검색 엔진을 활용한 디자인 인텔리전스 스킬. 산업별 추론 규칙과 CSV 데이터베이스에서 5-Dimension 프레임워크로 최적 디자인 시스템을 생성한다.

**출처**: [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) v2.2.1

## 5-Dimension Framework

디자인 시스템 생성 시 5개 차원을 Progressive Disclosure로 제공:

| 차원                  | 내용                                        | 검색 도메인          |
| --------------------- | ------------------------------------------- | -------------------- |
| D1: Pattern & Layout  | 제품별 페이지 구조, CTA 배치, 섹션 순서     | `product`, `landing` |
| D2: Style & Aesthetic | 비주얼 스타일, Use When/Avoid, 키워드       | `style`              |
| D3: Color & Theme     | 색상 팔레트, 60-30-10, 시맨틱 토큰          | `color`              |
| D4: Typography        | 폰트 페어링, 무드 매칭, CSS Import          | `typography`         |
| D5: Animations        | 마이크로인터랙션, 스크롤, 로딩, 페이지 전환 | `animation`          |

## 워크플로우

### Step 1: 작업 유형 판별

| 작업 유형          | 판별 조건                                                  | 실행 Step                             |
| ------------------ | ---------------------------------------------------------- | ------------------------------------- |
| 디자인 시스템 생성 | 새 프로젝트, 전체 스타일 가이드, 디자인 리뉴얼             | Step 2 → Step 3 → Step 4 → Step 5     |
| 페이지별 디자인    | 특정 페이지/화면 디자인                                    | Step 2(페이지 모드) → Step 3 → Step 5 |
| 도메인 검색        | 특정 영역(색상, 타이포, 스타일, 애니메이션 등) 정보만 필요 | Step 3                                |
| 스택 가이드라인    | 프레임워크별 구현 가이드 필요                              | Step 4                                |

### Step 2: 디자인 시스템 생성

```bash
python3 .claude/skills/ui-ux-design/scripts/search.py "<제품유형> <산업> <키워드>" --design-system -p "<프로젝트명>" -f markdown
```

persist 모드 (지속적 참조용):

```bash
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --design-system --persist -p "<프로젝트명>" -o dev/docs/design
```

### Step 3: 도메인별 보충 검색

```bash
# 스타일 검색
python3 .claude/skills/ui-ux-design/scripts/search.py "modern e-commerce card" --domain style

# 색상 팔레트
python3 .claude/skills/ui-ux-design/scripts/search.py "trust marketplace" --domain color

# 안티패턴 검증
python3 .claude/skills/ui-ux-design/scripts/search.py "low contrast navigation" --domain anti-pattern
```

### Step 4: 스택 가이드라인 적용

```bash
python3 .claude/skills/ui-ux-design/scripts/search.py "<쿼리>" --stack nextjs
```

### Step 5: 프론트엔드 가이드라인 연계

디자인 시스템을 코드로 구현할 때 `frontend-dev-guidelines` 스킬 규칙을 따른다.

## 품질 체크리스트 (Pre-Delivery)

- [ ] 텍스트 대비율 4.5:1 이상
- [ ] 터치 타겟 최소 44x44px
- [ ] hover 상태가 레이아웃을 이동시키지 않을 것
- [ ] interactive 요소에 cursor-pointer
- [ ] SVG 아이콘 사용 (이모지 금지)
- [ ] 모바일 우선 반응형 (min 16px body text)
- [ ] 키보드 네비게이션 가능
- [ ] prefers-reduced-motion 체크
- [ ] transform/opacity만 사용한 애니메이션 (GPU 가속)
- [ ] 마이크로인터랙션 150-300ms, 페이지 전환 300-500ms
- [ ] 동시 애니메이션 최대 2개

## 참조 문서

- 빠른 참조: [references/quick-reference.md](references/quick-reference.md)
- 프론트엔드 가이드라인: `.claude/skills/frontend-dev-guidelines/SKILL.md`
- 디자인 출력: `dev/docs/design/`
