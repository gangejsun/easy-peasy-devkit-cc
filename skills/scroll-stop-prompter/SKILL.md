---
name: scroll-stop-prompter
description: >
  제품 사진/영상을 스크롤 스톱 콘텐츠로 변환하기 위한 AI 이미지/비디오 프롬프트를 생성합니다.
  조립뷰(Assembled), 분해뷰(Deconstructed), 비디오 전환(Video Transition) 3종 프롬프트를
  타겟 AI 모델별로 최적화하여 생성하고, 복사 가능한 HTML 프리뷰 페이지를 제공합니다.
  사용자가 "AI 프롬프트 생성", "제품 프롬프트", "스크롤 스톱 프롬프트", "이미지/비디오 프롬프트"를
  요청할 때 사용합니다. marketing-workflow Stage 1으로도 호출됩니다.
  전체 마케팅 파이프라인은 /marketing-workflow. 사이트 구축은 /scroll-stop-builder.
  수동 호출 전용 (/scroll-stop-prompter). 자동 트리거되지 않습니다. (project)
---

# Scroll-Stop Prompter

제품의 "스크롤 스톱" 콘텐츠 제작을 위한 AI 이미지/비디오 프롬프트 3종을 생성하고 HTML 프리뷰 페이지로 전달.

## 워크플로우

### Step 1: 작업 유형 판별

| 조건                                                 | 모드       | 실행 Step         |
| ---------------------------------------------------- | ---------- | ----------------- |
| marketing-workflow에서 호출 (campaign 디렉토리 존재) | pipeline   | 2 → 3 → 4 → 5     |
| 단독 호출                                            | standalone | 2 → 3 → 4         |
| 특정 프롬프트 유형만 요청 ("조립뷰만", "비디오만")   | single     | 2 → 3(해당만) → 4 |

### Step 2: 사용자 인테이크

AskUserQuestion으로 수집: 제품명, 제품 설명, 비주얼 스타일, 타겟 AI 모델.

### Step 3: 프롬프트 생성

3종 프롬프트를 생성: Prompt A (Assembled Shot), Prompt B (Deconstructed Shot), Prompt C (Video Transition).

각 프롬프트의 상세 포함 요소 및 AI 모델별 최적화 매핑: `references/prompt-guide.md` 참조.

### Step 4: HTML 프리뷰 페이지 생성

`assets/prompt-page-template.html` 템플릿 기반으로 HTML 생성.

### Step 5: 파이프라인 핸드오프 (pipeline 모드 전용)

`prompts.md`를 캠페인 디렉토리에 저장.

## 프롬프트 작성 원칙

- **구체적 시각 묘사**: "sleek" 대신 "brushed aluminum with subtle anodized finish"
- **조명 묘사 필수**: 모든 프롬프트에 조명 셋업 명시
- **배경 일관성**: 3개 프롬프트의 배경 톤 통일
- **모델 전용 문법**: 각 AI 모델의 파라미터 형식 준수

## 참조 문서

- 프롬프트 상세 가이드: [references/prompt-guide.md](references/prompt-guide.md)
- HTML 프리뷰 템플릿: [assets/prompt-page-template.html](assets/prompt-page-template.html)
- 파이프라인 연동: `.claude/skills/marketing-workflow/SKILL.md`
