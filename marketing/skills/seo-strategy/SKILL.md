---
name: seo-strategy
description: SEO 3-Mode 분석 — 페이지 최적화(키워드·LSI·메타·구조화 데이터) · 사이트 전체 감사 · AI 검색 최적화. 결과는 인터랙티브 HTML 리포트. "SEO 분석", "SEO 최적화", "사이트 감사", "키워드 분석", "메타 태그", "AI SEO", "LLM 최적화"에 사용합니다. marketing-workflow Stage 3. 수동 호출 전용.
---

# SEO Strategy

3-Mode SEO 분석 및 최적화. 인터랙티브 HTML 리포트 생성.

## 워크플로우

### Step 1: 모드 선택

| 조건 | 모드 | 실행 Step |
|------|------|----------|
| 기사/블로그/단일 페이지 최적화 요청 | Mode 1 (Article) | 2A → 3A → 4 |
| 사이트 전체 감사 / URL 감사 요청 | Mode 2 (Audit) | 2B → 3B → 4 |
| "AI SEO", "AI 검색 최적화", "LLM 최적화" | Mode 3 (AI SEO) | 2C → 3C → 4 |
| marketing-workflow에서 호출 (site.md 존재) | Mode 2 (pipeline) | 2B(자동) → 3B → 4 |

### Step 2A-2C: 모드별 인테이크

각 모드에서 필요한 정보를 수집합니다. `dev/docs/marketing/`의 `context.md` 자동 로딩.

### Step 3A: Article SEO 분석 (Mode 1)

점수 산정은 `references/scoring-criteria.md` 기준. 키워드 분석, LSI 키워드, 온페이지 SEO, 콘텐츠 품질, 구조화 데이터, 메타 태그 생성, Buyer Stage 매핑.

### Step 3B: Site Audit 분석 (Mode 2)

점수 산정은 `references/scoring-criteria.md` + `references/technical-seo-checklist.md` 기준. 6개 카테고리 감사: Technical SEO(25%), On-Page(25%), Content(20%), Performance(15%), Mobile(10%), Accessibility(5%).

### Step 3C: AI SEO 분석 (Mode 3)

점수 산정은 `references/ai-seo-guide.md` 기준. 3 Pillar 평가: Structure(40%), Authority(35%), Presence(25%).

### Step 4: 리포트 전달 및 핸드오프

HTML 리포트를 로컬 서버로 오픈. 핵심 발견 사항 3-5개 요약 + 액션 아이템 목록.

## Next.js App Router SEO

프로젝트가 Next.js 기반일 때 추가 검사 및 추천. 상세: `references/nextjs-seo-guide.md`

## 참조 문서 — 해당 시점에만 읽는다

| 파일 | 언제 읽는가 |
| --- | --- |
| [references/scoring-criteria.md](references/scoring-criteria.md) | 점수를 산정하는 Step 4에서 |
| [references/technical-seo-checklist.md](references/technical-seo-checklist.md) | Mode 2 (사이트 감사)일 때만 |
| [references/nextjs-seo-guide.md](references/nextjs-seo-guide.md) | 대상이 Next.js 프로젝트일 때만 |
| [references/ai-seo-guide.md](references/ai-seo-guide.md) | Mode 3 (AI SEO)일 때만 |

파이프라인 연동: marketing-workflow 스킬 (Stage 3으로 호출됨)
