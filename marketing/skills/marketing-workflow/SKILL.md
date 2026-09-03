---
name: marketing-workflow
description: 마케팅 콘텐츠 파이프라인을 오케스트레이션합니다 — AI 프롬프트 생성 → 스크롤 애니메이션 사이트 구축 → SEO 최적화를 순차 실행하고 dev/docs/marketing/에 통합합니다. "마케팅 캠페인", "제품 랜딩 페이지", "스크롤 스톱 콘텐츠", "마케팅 파이프라인"에 사용합니다. 개별 스테이지는 /scroll-stop-prompter · /scroll-stop-builder · /seo-strategy. 수동 호출 전용.
disable-model-invocation: true
---

# Marketing Workflow Orchestrator

마케팅 콘텐츠 파이프라인의 3개 스테이지를 순차 실행하고 진행 상태를 추적하는 오케스트레이터.

**파이프라인**: scroll-stop-prompter → scroll-stop-builder → seo-strategy

코드 워크플로우와 완전 독립. `dev/docs/marketing/`에 산출물 저장.

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

- 제품 마케팅 컨텍스트: `dev/docs/marketing/context-<제품>.md` — 제품명·타겟·핵심 가치·톤·금지 표현을 표 1개로
- 캠페인 요약: `dev/docs/marketing/campaign-<제품>.md` — 스테이지별 산출물 경로 + 다음 액션 목록
- 스테이지 스킬은 슬래시 명령으로 부른다 — `/scroll-stop-prompter` · `/scroll-stop-builder` · `/seo-strategy`
  (셋 다 이 플러그인의 형제 스킬이라 경로를 적을 필요가 없다)
