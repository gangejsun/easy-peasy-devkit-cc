---
name: dev-docs-generator
description: |
  기능 개발을 위한 plan, context, tasks 문서를 dev/active/ 폴더에 생성합니다.
  신규 기능 개발, 기존 기능 확장, 리팩토링 시 개발 문서가 필요할 때 사용됩니다.
  CLAUDE.md 워크플로우의 Phase 3에 해당합니다.
---

# Dev Docs Generator

개발 문서(plan, context, tasks)를 `dev/active/` 폴더에 생성하는 스킬입니다.

## 입력 처리

이 스킬은 다양한 방식으로 호출될 수 있습니다:

| 호출 상황 | 입력 | 동작 |
|----------|------|------|
| planning-agent에서 PRD 경로와 함께 호출 | PRD 파일 경로 + 요구사항 | PRD를 참조하여 개발 문서 생성 |
| 사용자가 `/dev-docs-generator`로 직접 호출 (리팩토링 등) | 사용자 요구사항만 | PRD 없이 프로젝트 분석만으로 생성 |
| PRD가 이미 존재하는 경우 | `dev/docs/prd/` 경로 안내 | 기존 PRD를 자동 탐색하여 참조 |

## 워크플로우

### Step 1: 작업 유형 확인 및 문서 범위 결정

현재 작업 유형에 따라 생성할 문서의 범위와 깊이를 결정합니다.

| 작업 유형 | 생성 문서 | plan 중점 | context 중점 | tasks 중점 |
|----------|----------|----------|-------------|-----------|
| 신규 기능 개발 | plan + context + tasks 전체 | 전체 구현 전략, 아키텍처 결정, 기술 선택 근거 | PRD 핵심 요약, 관련 서비스, 데이터 모델 | 전체 구현 체크리스트 (UI, API, DB, 테스트) |
| 기존 기능 확장/수정/삭제 | plan + context + tasks 전체 | 변경 범위, 영향도 분석, 하위 호환성 | 기존 코드 참조, 변경 이유, 리스크 | 변경 항목 중심 체크리스트 |
| 리팩토링 | plan + context + tasks 전체 | 리팩토링 목표, before/after 구조 | 현재 문제점, 목표 아키텍처 | 단계별 체크리스트, 테스트 보존 확인 |
| 버그 수정 (복잡) | context + tasks만 (plan 생략 가능) | - | 버그 원인, 영향 범위, 재현 조건 | 수정 항목 + 검증 체크리스트 |

### Step 2: 기존 문서 확인

```bash
ls dev/active/
```

동일 기능에 대한 기존 문서가 있는지 확인합니다.
- 기존 문서 존재: 해당 문서를 업데이트할지 새로 만들지 사용자에게 확인
- 기존 문서 부재: Step 3 진행

### Step 3: 폴더 및 문서 생성

```bash
mkdir -p dev/active/<feature-name>
```

feature-name은 kebab-case로 작성합니다.

**명명 규칙:**

| 작업 유형 | 폴더명 패턴 | 예시 |
|----------|-----------|------|
| 신규 기능 | `<feature>` | `deal`, `notification` |
| 기능 확장/수정 | `<feature>-<변경요약>` | `deal-category-filter`, `notification-push` |
| 리팩토링 | `<feature>-refactor` | `deal-refactor` |

- `-v2`, `-extend` 같은 모호한 접미사 금지. 구체적 변경 내용을 접미사로 사용

`dev/templates/`의 템플릿 구조를 **참고**하되, **단순 복사가 아닌 해당 기능에 맞는 내용으로 직접 작성**합니다.

| 생성 파일 | 참조 템플릿 | 작성 내용 |
|----------|------------|----------|
| `<name>-plan.md` | `feature-plan-template.md` | 구현 전략, 단계별 계획, 수용 기준 |
| `<name>-context.md` | `feature-context-template.md` | 핵심 결정사항, 주요 파일, 기술적 제약 |
| `<name>-tasks.md` | `feature-tasks-template.md` | 구체적인 작업 체크리스트 |

IMPORTANT: 템플릿의 섹션 구조는 유지하되, 플레이스홀더(`[feature-name]`, `[설명]` 등)를 실제 기능 내용으로 채워서 작성해야 합니다.

IMPORTANT: tasks.md에 반드시 **수정 범위 (Scope)** 섹션을 포함해야 합니다. 이 섹션은 P4 구현 시 도메인 경계 준수를 위한 가이드입니다. `.claude/rules/domain-boundaries.md` 참조.

### Step 4: 사용자 확인

생성된 문서를 요약하여 사용자에게 보여주고, 수정이 필요한지 확인합니다.

```
개발 문서가 생성되었습니다.

📁 dev/active/<feature-name>/
├── <name>-plan.md     - 구현 전략 및 계획
├── <name>-context.md  - 핵심 결정사항 및 컨텍스트
└── <name>-tasks.md    - 작업 체크리스트

검토 후 수정이 필요하면 말씀해주세요. 이대로 구현을 진행할까요?
```

## 산출물 검증

Step 4 (사용자 확인) 전, 생성된 문서를 자체 검증:

| 검증 항목 | 기준 | 실패 시 |
|----------|------|--------|
| 3개 파일 존재 | plan, context, tasks 모두 생성됨 | 누락 파일 재생성 |
| tasks.md Scope 섹션 | `## 수정 범위` 또는 `## Scope` 존재 | 섹션 추가 |
| plan.md 구현 전략 | `## Proposed Solution` 또는 실질적 구현 계획 존재 | 섹션 보완 |
| context.md SESSION | `## SESSION PROGRESS` 존재 | 섹션 추가 |

## 참조 문서

- 템플릿: `dev/templates/`
- 문서화 패턴: `docs/dev-docs-pattern.md`
- 기존 활성 작업: `dev/active/`
- 아카이브된 작업: `dev/archive/`

## 프로젝트 커스텀 리소스

> 아래 경로에 `.md` 파일이 존재하면 개발 문서 생성 시 자동으로 참조됩니다. 파일이 없으면 이 섹션은 무시됩니다.

| 카테고리 | 경로 | 이 스킬에서의 용도 |
|---------|------|-------------------|
| 코딩 표준 | `.claude/resources/coding-standards/` | tasks.md 생성 시 구현 가이드라인으로 활용 |
| 도메인 지식 | `.claude/resources/domain-knowledge/` | context.md 작성 시 비즈니스 규칙·도메인 제약 반영 |
