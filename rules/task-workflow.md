---
paths:
  - "src/**"
  - "packages/**"
  - "app/**"
  - "lib/**"
---

# Task Workflow - 작업 워크플로우

## Step 1: 작업 유형 분류

사용자 요청을 받으면 먼저 **"서비스 기능 코드"**(사용자가 쓰는 앱의 기능) 변경인지, **"개발 환경·도구·인프라"** 변경인지를 판단한 후 아래 유형에서 선택합니다.

## Step 2: 해당 Phase 실행

| 작업 유형 | Phase 실행 순서 | 실행 방식 |
|----------|---------------|----------|
| 신규 기능 (Small) | P1→P4→P5 | `/prompt-enhancer` → 직접 P4 → `/completion-review` |
| 신규 기능 (Medium) | P1→P4→P5 | `/prompt-enhancer` → 직접 P4 → `review-agent`(P5: minimal) |
| 신규 기능 (Large) | P0→P1→P2→P3→P4→P5 | `planning-agent`(P0~P3, P0는 선택적) → 직접 P4 → `review-agent`(P5: full) |
| 기존 기능 확장/수정/삭제 (Small) | P4→P5 | 직접 P4 → `/completion-review` |
| 기존 기능 확장/수정/삭제 (Medium) | P4→P5 | 직접 P4 → `review-agent`(P5: minimal) |
| 기존 기능 확장/수정/삭제 (Large) | P2→P3→P4→P5 | `planning-agent`(P2: 기존 PRD 수정/업데이트, P3) → 직접 P4 → `review-agent`(P5: full) |
| 버그 수정 | P4→P5 | 직접 P4 → `review-agent`(P5: full) |
| 리팩토링 | P3→P4→P5 | `/dev-docs-generator` 직접 호출 → 직접 P4 → `review-agent`(P5: full) |
| 문서 작업 | 직접 수행 | 워크플로우 미적용 |
| 도구/환경 작업 | 직접 수행 | 워크플로우 미적용 |
| 탐색/조사/분석/검토/기타 | 직접 수행 | 워크플로우 미적용 |

## 규모 판단 기준 (Small vs Medium vs Large)

### 기본 기준
- **Small**: 1파일, ≤10줄, 로직 없음
- **Medium**: 1~2파일, ~50줄, 로직 포함
- **Large**: 3+파일 또는 50줄+
- **모호하면 Medium** (안전 우선)

### 명확한 예시
| 작업 | 규모 | 이유 |
|------|------|------|
| 버튼 색상 변경 (className만) | Small | 1파일, 3줄, 로직 없음 |
| 기존 함수에 매개변수 추가 | Medium | 1파일, 30줄, 호출처 수정 필요 |
| 새 페이지 + API 추가 | Large | 5파일, 150줄 |

### 자동 Medium 이상 경로
다음 경로는 **줄 수/로직 무관**하게 자동으로 Medium 이상:
- API 라우트 핸들러 경로
- Server Actions / 서버 액션 파일
- 미들웨어 파일
- 테스트 코드 파일
- DB 관련 파일 (마이그레이션, 스키마 등)
- 타입 정의 파일

## 워크플로우 미적용 유형 판단 가이드

- **도구/환경 작업**: 스킬 생성/설치, MCP 서버 설정, CI/CD 파이프라인, 패키지 의존성, 린트/포맷 설정, 개발 도구 구성 등 서비스 기능이 아닌 개발 인프라 변경
- **탐색/조사/분석**: 코드 동작 설명, 성능 분석, 코드 리뷰, 아키텍처 조사, 기술 비교 등 코드 변경 없이 정보를 제공하는 작업

## Phase 정의

| Phase | 이름 | 수행 방법 |
|-------|------|----------|
| P0-A | 아이디에이션 | `planning-agent` 위임. 단독: `/brainstorming`. |
| P0-B | 리서치 | `planning-agent` 위임. 단독: `/research`. |
| P0-C | 사업 기획 | `planning-agent` 위임. 단독: `/business-planner`. |
| P0-D | 서비스 기획 | `planning-agent` 위임. 단독: `/service-planner`. |
| P1 | 프롬프트 강화 | `planning-agent` 위임 (신규 기능 시). 단독: `/prompt-enhancer`. |
| P2 | PRD 검색/생성 | `planning-agent` 위임. 단독: `/prd-generator`. |
| P3 | 개발 문서 생성 | `planning-agent` 위임. 단독: `/dev-docs-generator`. |
| P4 | 구현 | 아래 'P4 구현 세부 규칙' 참조 |
| P5 | 완료 및 문서 최신화 | `review-agent` 위임. 독립적 관점에서 검증. |
| P6 | TDD 검증 | `review-agent`가 P5 중 조건 판단 후 **사용자 확인을 받고** 수행. |

## P4 구현 세부 규칙

### 공통 규칙 (모든 규모)
- `dev/active/<name>/` 폴더가 존재하면 참조. tasks.md 즉시 체크, context.md 업데이트
- `dev/active/` 폴더가 없는 경우(Small/Medium): 코드 컨벤션과 사용자 요구사항만으로 구현
- **구현 후 빌드 및 테스트 실행 필수** (CLAUDE.md의 commands 참조)
- **계획과 괴리 시 즉시 멈추고 재계획**

### Small / Medium 작업
- 메인 세션에서 직접 코딩 수행
- **Medium 신규 기능 보충**: P1(prompt-enhancer)에서 수정 대상 파일과 범위를 명확히 확인. 2개 이상 도메인에 걸치는 변경이 감지되면 Large로 격상 고려

### Large 작업: 서브에이전트 디스패치
Large 작업(3+파일 또는 50줄+)의 P4는 **태스크별 서브에이전트 격리** 방식으로 실행합니다.

**실행 흐름:**
1. `dev/active/<name>/tasks.md`에서 전체 태스크 목록을 읽는다
2. 각 태스크를 **개별 Task tool 서브에이전트**로 디스패치한다:
   - 서브에이전트에게 **태스크 텍스트를 인라인으로 전달** (파일 경로 참조가 아님)
   - 프롬프트에 프로젝트 루트 경로, 기술 스택, 코딩 컨벤션 핵심 사항을 포함
   - 서브에이전트는 `subagent_type: "general-purpose"` 사용
3. 서브에이전트 완료 후 **상태 코드**를 확인한다:
   - `DONE` → tasks.md 해당 항목 `[x]` 체크 → 다음 태스크 디스패치
   - `DONE_WITH_CONCERNS` → 우려사항 기록 후 다음 태스크 진행
   - `NEEDS_CONTEXT` → 추가 정보를 포함하여 재디스패치
   - `BLOCKED` → 사용자에게 보고 후 판단 대기
4. 모든 태스크 완료 후 메인 세션에서 빌드 및 테스트 실행

## P0 Phase 가이드

P0는 **신규 기능 Large** 작업에서 선택적으로 적용됩니다.

### P0 선택 규칙
신규 기능 Large 판정 시, 요구사항 명확성과 무관하게 **항상 P0 진행 여부를 사용자에게 질문**합니다.

**P0 Phase 선택 가이드 (사용자 참고용):**
- 아이디어 구체화가 필요할 때 → P0-A (아이디에이션)
- 시장/경쟁 데이터가 필요할 때 → P0-B (리서치)
- 사업성 검증이 필요할 때 → P0-C (사업 기획)
- 기능 요구사항 정리가 필요할 때 → P0-D (서비스 기획)

### P0 진행 규칙
- 각 Phase는 독립적 — 중간 Phase를 건너뛸 수 있음
- 각 Phase 완료 후 다음 Phase 진행 여부를 사용자가 결정

### P0 산출물 경로
| Phase | 산출물 경로 |
|-------|-----------|
| P0-B | `dev/docs/research/<topic>.md` |
| P0-C | `dev/docs/business/business-plan-<name>.md` |
| P0-D | `dev/docs/service/service-plan-<name>.md` |

## P4 구현 시 참조 경로

> 아래 경로는 기능 개발 과정에서 생성됩니다. 해당 문서가 없으면 참조를 건너뜁니다.

| 개발 영역 | 참조 경로 |
|----------|----------|
| 아키텍처 | `dev/docs/architecture/` |
| API 설계 | `dev/docs/api/` |
| 데이터베이스 | `dev/docs/database/` |
| 보안 | `dev/docs/security/` |
| 테스트 | `dev/docs/testing/` |
| 배포 | `dev/docs/deployment/` |
| 문제 해결 | `dev/docs/troubleshooting/` |
| 디자인 | `dev/docs/design/` |
