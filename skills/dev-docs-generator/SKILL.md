---
name: dev-docs-generator
description: 구현 전 개발 문서(plan, context, tasks)가 필요할 때, PRD가 완성된 직후에 사용합니다. dev/active/ 폴더에 plan, context, tasks 문서를 생성합니다. 신규 기능 개발, 기존 기능 확장, 리팩토링 시. CLAUDE.md 워크플로우의 Phase 3에 해당합니다.
---

# Dev Docs Generator

개발 문서(plan, context, tasks)를 `dev/active/` 폴더에 생성하는 스킬입니다.

## 입력 처리

| 호출 상황                                                | 입력                      | 동작                              |
| -------------------------------------------------------- | ------------------------- | --------------------------------- |
| epcc-planner에서 PRD 경로와 함께 호출                  | PRD 파일 경로 + 요구사항  | PRD를 참조하여 개발 문서 생성     |
| 사용자가 `/dev-docs-generator`로 직접 호출 (리팩토링 등) | 사용자 요구사항만         | PRD 없이 프로젝트 분석만으로 생성 |
| PRD가 이미 존재하는 경우                                 | `dev/docs/prd/` 경로 안내 | 기존 PRD를 자동 탐색하여 참조     |

## 워크플로우

### Step 1: 작업 유형 확인 및 문서 범위 결정

**먼저 필요성을 판정한다**: 작업이 한 세션에 끝나면 워크스페이스를 만들지 않는다
(reversibility.md — "세션을 넘어갈 때만"). 세션을 넘어갈 때만 아래로 진행:

| 작업 유형 | 생성 문서 |
| --- | --- |
| 신규 기능 (PRD 있음) | plan + context + tasks |
| 리팩토링/확장 | plan + tasks (context는 결정 기록 생기면) |
| 버그 수정 (다세션) | tasks만 |

### Step 2: 기존 문서 확인

`dev/active/`에 동일 slug가 있으면 새로 만들지 않고 기존 문서를 갱신한다.
`dev/archive/`에 유사 작업이 있으면 참조로 안내한다.

### Step 3: 폴더 및 문서 생성

**양쪽을 건드리면 계약이 슬라이스보다 먼저다.** 이 작업이 프론트·백엔드를 모두 새로 만들면
`workflow-routing.md` 「기능 하나의 안쪽 순서」 1·2를 여기서 앞당긴다 — 화면×필드 표
(서비스 기획서 Step 4-4, 없으면 PRD의 화면 절에서 뽑는다)를 읽고 `dev/docs/api/wire-contract.md`를 쓴다.

- 양식은 `${CLAUDE_PLUGIN_ROOT}/skills/stack-guide-generator/assets/wire-contract.template.md`의
  **§0~§5 절 제목과 「계약 값은 목록·표 행에만」 규약**을 그대로 쓴다. 그 파일의 머리말(가이드
  격리 생성·게이트 대조)과 `exampleDomain` 지시는 가이드 생성용이라 옮기지 않는다. §6 인증
  표면은 자체 인증 백엔드일 때만 채운다.
- **이미 있으면 재작성하지 않는다** — 이번 기능의 엔티티·엔드포인트·에러 코드만 §0·§4에 추가한다.
- 도메인 모델은 계약 §0 + 화면×필드 표로 논리 수준까지 충당한다. 물리 스키마는 안쪽 순서
  4번에서 `data-modeling` 카드가 담당한다 — 여기서 별도 문서를 만들지 않는다.

`dev/active/<slug>/`에 `assets/doc-templates.md`의 3종 형식으로 생성한다.
tasks.md의 **수정 범위 (Scope)** 섹션은 필수다 — epcc-reviewer가 Scope 준수를 대조한다.

체크리스트는 **수직 슬라이스**로 묶는다 — 각 슬라이스는 전 층을 얇게 관통해 혼자 시연 가능하고,
새 컨텍스트 하나에 들어가며, `막는 것`으로 선행 슬라이스를 선언한다. 광역 리팩토링은
이 규칙의 예외라 확장→이주→수축으로 배열한다. 형식과 판정 기준은 템플릿 파일에 있다.

### Step 4: 사용자 확인

생성 문서 목록 + plan의 접근 요약을 제시하고 확정받는다.

## 산출물 검증

- 3종 문서가 템플릿의 필수 섹션을 갖는가
- tasks.md에 Scope 섹션이 있는가
- 각 슬라이스에 `막는 것`이 적혀 있고, 슬라이스 하나가 새 컨텍스트 하나에 들어가는가
- 프론트·백엔드 양쪽 작업이면 `dev/docs/api/wire-contract.md`가 있고 이번 기능의 엔드포인트가 §4에 있는가
- plan의 검증 경로가 실행 가능한 명령인가

## 참조 문서

- 문서 템플릿: [assets/doc-templates.md](assets/doc-templates.md)
- 계약 양식: `${CLAUDE_PLUGIN_ROOT}/skills/stack-guide-generator/assets/wire-contract.template.md` — 사본을 두지 않는다
- 기존 활성 작업: `dev/active/` · 아카이브: `dev/archive/`
