---
name: marketing-workflow
description: |
  마케팅 콘텐츠 파이프라인을 오케스트레이션합니다. AI 이미지/비디오 프롬프트 생성(scroll-stop-prompter),
  스크롤 애니메이션 사이트 구축(scroll-stop-builder), SEO 최적화(seo-strategy)를
  순차 실행하고 결과를 dev/docs/marketing/에 통합합니다.
  사용자가 "마케팅 캠페인", "제품 랜딩 페이지 만들기", "스크롤 스톱 콘텐츠",
  "마케팅 워크플로우", "마케팅 파이프라인"을 요청할 때 사용합니다.
  개별 스테이지만 필요하면: AI 프롬프트 → /scroll-stop-prompter, 사이트 구축 → /scroll-stop-builder, SEO 분석 → /seo-strategy.
  수동 호출 전용 (/marketing-workflow). 자동 트리거되지 않습니다. (project)
---

# Marketing Workflow Orchestrator

마케팅 콘텐츠 파이프라인의 3개 스테이지를 순차 실행하고 진행 상태를 추적하는 오케스트레이터.

**파이프라인**: scroll-stop-prompter → scroll-stop-builder → seo-strategy

P0~P6 코드 워크플로우와 완전 독립. `dev/docs/marketing/`에 산출물 저장.

## 워크플로우

### Step 1: 파이프라인 모드 선택

| 요청 패턴                                   | 모드         | 실행 스테이지 |
| ------------------------------------------- | ------------ | ------------- |
| 전체 캠페인 / "마케팅 캠페인 만들기"        | full         | 1 → 2 → 3     |
| "AI 프롬프트만" / "프롬프트 생성"           | prompt-only  | 1             |
| "비디오로 사이트 만들기" / 비디오 파일 제공 | build-only   | 2             |
| "SEO 분석" / "사이트 감사"                  | seo-only     | 3             |
| "프롬프트 + 사이트"                         | prompt-build | 1 → 2         |
| "사이트 + SEO" / 비디오 + SEO 요청          | build-seo    | 2 → 3         |

### Step 2: 캠페인 초기화

1. 캠페인 이름을 사용자에게 확인
2. `dev/docs/marketing/<campaign-name>/` 디렉토리 생성
3. 제품 마케팅 컨텍스트 확보 (`context.md`)
4. `progress.md` 초기화

### Step 3: Stage 1 실행 — 프롬프트 생성

`/scroll-stop-prompter` 스킬 워크플로우 실행 (pipeline 모드). USER GATE로 Stage 2 전환 전 사용자 확인.

### Step 4: Stage 2 실행 — 사이트 구축

`/scroll-stop-builder` 스킬 워크플로우 실행. USER GATE로 Stage 3 전환 전 사용자 확인.

### Step 5: Stage 3 실행 — SEO 최적화

`/seo-strategy` 스킬 워크플로우 실행.

### Step 6: 캠페인 완료

모든 활성 스테이지가 완료되면 캠페인 요약 생성.

## 핸드오프 프로토콜

| Stage | 출력 파일    | 핵심 데이터                                |
| ----- | ------------ | ------------------------------------------ |
| 1 → 2 | `prompts.md` | 제품명, 설명, 스타일, AI 모델 추천         |
| 2 → 3 | `site.md`    | HTML 경로, 섹션 목록, 프레임 수, 제품 스펙 |

## 참조 문서

- 제품 마케팅 컨텍스트 템플릿: [assets/product-marketing-context-template.md](assets/product-marketing-context-template.md)
- 캠페인 요약 템플릿: [assets/campaign-summary-template.md](assets/campaign-summary-template.md)
- scroll-stop-prompter: `.claude/skills/scroll-stop-prompter/SKILL.md`
- scroll-stop-builder: `.claude/skills/scroll-stop-builder/SKILL.md`
- seo-strategy: `.claude/skills/seo-strategy/SKILL.md`
