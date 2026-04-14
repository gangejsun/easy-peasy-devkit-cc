---
name: receiving-code-review
description: |
  코드 리뷰 피드백을 수신하여 기술적으로 검증하고 심각도별로 처리합니다.
  /requesting-code-review 결과, P6(gemini-claude-loop) 결과, 또는 사용자가 전달한 외부 리뷰 피드백을
  받았을 때 사용하세요. 피드백의 정확성을 검증하고, 부적절한 피드백에는 근거와 함께 반론합니다. (project)
---

# Receiving Code Review

코드 리뷰 피드백을 기술적으로 검증하고, 심각도별로 적절히 처리한다.

## 핵심 원칙

- **검증 우선**: 피드백을 맹목적으로 수용하지 않는다
- **기술적 엄밀성**: 사회적 동의보다 기술적 판단을 우선한다
- **근거 기반 반론**: 리뷰어가 틀렸을 때 구체적 근거와 함께 반박한다
- **YAGNI 검증**: "전문적으로 보이는" 제안이 실제로 필요한지 검증한다

## 워크플로우

### Step 1: 피드백 소스 확인 및 처리 범위 결정

### Step 2: 피드백 검증

각 이슈에 대해 사실 확인, 심각도 적절성, YAGNI 검증, 의도적 결정 확인, 기존 기능 영향을 확인한다.

### Step 3: 심각도별 처리

Critical → 즉시 사용자 보고. Important → 수정 진행. Suggestion → 기록만.

### Step 4: 처리 결과 요약

## 참조 문서

- 코딩 컨벤션: `.claude/rules/code-conventions.md`
- 도메인 경계: `.claude/rules/modification-guardrails.md`
- 보안 규칙: `.claude/rules/security.md`
