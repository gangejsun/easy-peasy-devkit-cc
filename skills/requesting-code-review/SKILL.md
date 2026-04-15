---
name: requesting-code-review
description: |
  P5(완료 및 문서 최신화) 단계에서 구현 코드의 구조화된 리뷰를 수행합니다.
  review-agent가 P5 Step A로 호출하거나, 사용자가 코드 리뷰를 명시적으로 요청할 때 사용하세요.
  git diff 기반으로 6개 영역(계획 정합성, 코드 품질, 아키텍처, 문서/표준, 이슈 식별, 커뮤니케이션)을
  검증하고 구조화된 리뷰 보고서를 생성합니다. (project)
---

# Requesting Code Review

git diff 기반으로 구현 코드를 6개 영역에서 체계적으로 리뷰하고 구조화된 보고서를 생성한다.

## 워크플로우

### Step 0: 리뷰 모드 자동 선택

| 작업 규모 | 리뷰 모드    | 검증 범위   |
| --------- | ------------ | ----------- |
| Medium    | skip/minimal | Critical만  |
| Large     | full         | 6-area 전체 |

### Step 1: 리뷰 컨텍스트 수집 및 분기 결정

### Step 2: 계획 정합성 검증

### Step 2-1: PRD 요구사항 대조 (dev/docs/prd/ 존재 시)

### Step 3: 코드 품질 및 아키텍처 리뷰 (Full 모드)

### Step 3-minimal: 최소 검증 (Medium 작업 전용)

타입 안전성, 도메인 경계, 보안, 에러 처리, 구조적 건전성 중 Critical만 검증.

### Step 4: 이슈 분류

### Step 5: 리뷰 보고서 생성

## 참조 문서

- 리뷰 프롬프트 템플릿: [references/code-review-prompt.md](references/code-review-prompt.md)
- 코딩 컨벤션: `.claude/rules/code-conventions.md`
- 도메인 경계: `.claude/rules/modification-guardrails.md`
- 보안 규칙: `.claude/rules/security.md`
