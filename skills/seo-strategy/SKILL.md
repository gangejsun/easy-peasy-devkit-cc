---
name: seo-strategy
description: >
  3-Mode SEO 분석 스킬. Mode 1: 기사/페이지 SEO 최적화 (키워드 분석, LSI, 메타 태그, 구조화 데이터 생성),
  Mode 2: 사이트 전체 감사 (기술 SEO, 콘텐츠, 성능, 모바일, 접근성 종합 점수),
  Mode 3: AI SEO 최적화 (AI 검색 엔진 인용/추출 최적화, 3 Pillar 평가).
  분석 결과를 인터랙티브 HTML 리포트로 생성합니다.
  사용자가 "SEO 분석", "SEO 최적화", "사이트 감사", "키워드 분석", "메타 태그 생성",
  "검색 엔진 최적화", "AI SEO", "AI 검색 최적화", "LLM 최적화"를 요청할 때 사용합니다.
  marketing-workflow Stage 3으로도 호출됩니다.
  AI SEO/LLM 최적화도 이 스킬에서 Mode 3으로 처리합니다. 전체 마케팅 캠페인은 /marketing-workflow.
  수동 호출 전용 (/seo-strategy). 자동 트리거되지 않습니다. (project)
---

# SEO Strategy

3-Mode SEO 분석 및 최적화. 인터랙티브 HTML 리포트 생성.

## 워크플로우

### Step 1: 모드 선택

| 조건                                       | 모드              | 실행 Step         |
| ------------------------------------------ | ----------------- | ----------------- |
| 기사/블로그/단일 페이지 최적화 요청        | Mode 1 (Article)  | 2A → 3A → 4       |
| 사이트 전체 감사 / URL 감사 요청           | Mode 2 (Audit)    | 2B → 3B → 4       |
| "AI SEO", "AI 검색 최적화", "LLM 최적화"   | Mode 3 (AI SEO)   | 2C → 3C → 4       |
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

## 참조 문서

- 점수 산정 기준: [references/scoring-criteria.md](references/scoring-criteria.md)
- 기술 SEO 체크리스트: [references/technical-seo-checklist.md](references/technical-seo-checklist.md)
- Next.js SEO 가이드: [references/nextjs-seo-guide.md](references/nextjs-seo-guide.md)
- AI SEO 최적화 가이드: [references/ai-seo-guide.md](references/ai-seo-guide.md)
- 파이프라인 연동: `.claude/skills/marketing-workflow/SKILL.md`
