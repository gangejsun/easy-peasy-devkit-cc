---
name: ui-ux-design
description: "UI/UX 디자인 인텔리전스 — UI 스타일·색상 팔레트·폰트 페어링·산업별 추론·차트 유형을 기반으로 디자인 시스템을 생성합니다. UI/UX 디자인, 화면 설계, 디자인 시스템, 색상/타이포그래피/스타일 선택, 랜딩 페이지, 대시보드 레이아웃, 컴포넌트 스타일링, 새 페이지·화면 제작 시 사용합니다."
---

# UI/UX Design Intelligence

BM25 기반 검색 엔진을 활용한 디자인 인텔리전스 스킬. 산업별 추론 규칙과 CSV 데이터베이스에서 최적 디자인 시스템을 생성한다.

> 아래 명령의 `${CLAUDE_SKILL_DIR}`는 **Claude Code가 치환한다** — 손으로 경로를 채우지 않는다.
> (프로젝트 오버라이드 경로를 하드코딩하면 플러그인 전용 설치에서 실패한다)

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

`-p` 옵션에 프로젝트명을 전달한다 (예: `-p "MyProject"`).

전체 디자인 시스템:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "<제품유형> <산업> <키워드>" --design-system -p "<프로젝트명>" -f markdown
```

persist 모드 (지속적 참조용):

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "<쿼리>" --design-system --persist -p "<프로젝트명>" -o dev/docs/design
```

페이지별 오버라이드:

```bash
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "<쿼리>" --design-system --persist -p "<프로젝트명>" -o dev/docs/design --page "<페이지명>"
```

출력 구조:
```
dev/docs/design/<project-slug>/
├── MASTER.md          # 전체 디자인 시스템
└── pages/
    └── <page>.md      # 페이지별 오버라이드
```

### Step 2.5: 방향 심사 (코드 작성 전 게이트)

생성 결과를 그대로 코드로 옮기지 않는다. `.claude/rules/ui-design.md`의 심사를 통과시킨다:

- **기본값 3군집**(크림+세리프+테라코타 / 근검정+산성악센트 / 괘선 다단)에 안착했는가 —
  브리프가 지정하지 않았는데 안착했다면 그것은 선택이 아니라 기본값이다
- **시그니처 요소**가 지명됐는가 — 이 화면이 기억될 단 하나
- **비슷한 브리프에도 같은 답이 나오는가** — 그렇다면 고치고 무엇을 왜 바꿨는지 진술한다

검색 점수는 브리프 적합성이 아니라 키워드 일치도다. **1등이라는 사실은 근거가 아니다.**
`--persist`로 저장했다면 `MASTER.md`의 `## Signature`와 `## 방향 심사` 칸을 채운다.

심사를 통과하지 못한 방향으로는 코드를 쓰지 않는다.

### Step 3: 도메인별 보충 검색

특정 영역의 상세 정보가 필요할 때:

```bash
# 스타일 검색
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "modern e-commerce card" --domain style

# 색상 팔레트
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "trust marketplace" --domain color

# UX 가이드라인
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "group buying flow" --domain ux

# 차트 추천
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "progress tracker" --domain chart

# 폰트 페어링
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "modern clean korean" --domain typography
```

### Step 4: 스택 가이드라인 적용

> 스택 가이드라인은 `nextjs`·`shadcn`·`react`·`html-tailwind` **4종만** 지원한다.
> 그 밖의 스택(Vue·Svelte·vanilla 등)은 이 Step을 건너뛰고 Step 1~3만 쓴다 —
> 스타일·팔레트·타이포·UX 규칙은 스택 불변이라 그대로 유효하다.

```bash
# Next.js 특화 가이드라인
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "<쿼리>" --stack nextjs

# shadcn/ui 특화 가이드라인
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "<쿼리>" --stack shadcn

# Tailwind CSS 가이드라인
python3 ${CLAUDE_SKILL_DIR}/scripts/search.py "<쿼리>" --stack html-tailwind
```

### Step 5: 프론트엔드 가이드라인 연계

디자인 시스템을 코드로 구현할 때 프로젝트의 `frontend-guide` 스킬 규칙을 따른다 —
스택 관행(컴포넌트 경계·클래스 병합·파일 배치)의 정본은 그쪽이다. 예(Next.js 조합):
- Server/Client Component 구분
- `function` 키워드 컴포넌트 선언
- `cn()` 유틸 + Tailwind CSS 스타일링
- shadcn/ui 컴포넌트 활용
- `@/` 경로 alias

### Step 6: 렌더 증명 (코드를 쓴 뒤)

Step 2.5가 **쓰기 전** 게이트라면 이것은 **쓴 뒤** 게이트다. 타입체크 통과는 화면이
나온다는 증거가 아니다 — 판정 규범의 정본은 `.claude/rules/ui-design.md` §6이다.

**사전 설치 (최초 1회, 이 프로젝트에 아직 없으면)** — 플러그인은 Playwright를 자동
설치하지 않는다(모든 소비자 프로젝트에 크로미움 다운로드를 강제하지 않기 위해서다).
프로젝트 루트에서 아래를 그대로 실행한다:

```bash
npm i -D playwright && npx playwright install chromium
```

pnpm/yarn을 쓰면:

```bash
pnpm add -D playwright && pnpm exec playwright install chromium
# 또는
yarn add -D playwright && yarn playwright install chromium
```

서버는 내장 `/run`으로 띄운다(이 스킬은 서버를 관리하지 않는다). 그 URL에 프로브를 건다:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/ui-probe.sh --url http://localhost:3000 --ready "main"
```

`--ready`에 렌더 완료를 뜻하는 선택자를 준다 — **가시성 기반 대기가 가장 신뢰할 수 있다.**
선택자를 찾아야 하면 `--recon`으로 인벤토리를 넓힌다(기본은 종류당 8개, 컨텍스트 절약).
콘솔 error·미포착 예외·실패 요청이 있으면 exit 1이다. 품질 실측은 WARN이라 종료 코드를
올리지 않는다. 브라우저가 없으면 exit 2 — **판정 불가이지 통과가 아니다.**

## 품질 체크리스트 (Pre-Delivery)

Step 6의 `ui-probe`가 실측하는 항목에는 *(실측)* 을 붙였다 — 나머지는 사람이 본다.
**실측 가능한 것을 눈으로 확인했다고 적지 않는다.**

- [ ] 텍스트 대비율 4.5:1 이상 *(실측)*
- [ ] 터치 타겟 최소 44x44px *(실측 · 모바일 뷰포트)*
- [ ] hover 상태가 레이아웃을 이동시키지 않을 것
- [ ] interactive 요소에 cursor-pointer *(실측)*
- [ ] SVG 아이콘 사용 (이모지 금지)
- [ ] 모바일 우선 반응형 (min 16px body text) *(실측 · 본문 중앙값)*
- [ ] 키보드 네비게이션 가능
- [ ] prefers-reduced-motion 체크 *(실측)*

## 참조 문서

- 빠른 참조: [references/quick-reference.md](references/quick-reference.md)
- 프론트엔드 가이드라인: `.claude/skills/frontend-guide/SKILL.md` (스택별로 생성된다)
- 디자인 판단 규범: `.claude/rules/ui-design.md` (UI 파일 편집 시 자동 로드) — §6이 렌더 증명의 정본
- 렌더 프로브: [scripts/ui-probe.sh](scripts/ui-probe.sh) (`--help` 로 사용법)
- 디자인 출력: `dev/docs/design/`

## 프로젝트 커스텀 리소스

> 아래 경로에 `.md` 파일이 존재하면 디자인 시스템 생성 시 자동으로 참조됩니다. 파일이 없으면 이 섹션은 무시됩니다.

| 카테고리 | 경로 | 이 스킬에서의 용도 |
|---------|------|-------------------|
| 디자인 원칙 | `.claude/resources/design-principles/` | UI/UX 디자인 결정 시 브랜드 가이드·디자인 원칙 적용 |
| 도메인 지식 | `.claude/resources/domain-knowledge/` | 도메인별 UX 패턴, 산업 특화 디자인 규칙 반영 |
