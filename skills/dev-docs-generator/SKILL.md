---
name: dev-docs-generator
description: |
  구현 전 개발 문서(plan, context, tasks)가 필요할 때, PRD가 완성된 직후에 사용합니다.
  dev/active/ 폴더에 plan, context, tasks 문서를 생성합니다.
  신규 기능 개발, 기존 기능 확장, 리팩토링 시. CLAUDE.md 워크플로우의 Phase 3에 해당합니다.
---

# Dev Docs Generator

개발 문서(plan, context, tasks)를 `dev/active/` 폴더에 생성하는 스킬입니다.

## 입력 처리

| 호출 상황                                                | 입력                      | 동작                              |
| -------------------------------------------------------- | ------------------------- | --------------------------------- |
| planning-agent에서 PRD 경로와 함께 호출                  | PRD 파일 경로 + 요구사항  | PRD를 참조하여 개발 문서 생성     |
| 사용자가 `/dev-docs-generator`로 직접 호출 (리팩토링 등) | 사용자 요구사항만         | PRD 없이 프로젝트 분석만으로 생성 |
| PRD가 이미 존재하는 경우                                 | `dev/docs/prd/` 경로 안내 | 기존 PRD를 자동 탐색하여 참조     |

## 워크플로우

### Step 1: 작업 유형 확인 및 문서 범위 결정

### Step 2: 기존 문서 확인

### Step 3: 폴더 및 문서 생성

IMPORTANT: tasks.md에 반드시 **수정 범위 (Scope)** 섹션을 포함해야 합니다.

### Step 4: 사용자 확인

## 산출물 검증

## 참조 문서

- 템플릿: `dev/templates/`
- 문서화 패턴: `docs/dev-docs-pattern.md`
- 기존 활성 작업: `dev/active/`
- 아카이브된 작업: `dev/archive/`
