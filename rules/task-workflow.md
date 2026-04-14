# Task Workflow - 작업 워크플로우

## PDCA 원칙

모든 코드 작업은 **PDCA 사이클**을 따른다. Phase 라우팅과 규모별 경량화는 이 원칙의 구현이다.

| PDCA      | 하네스 구현                                                | 핵심 질문                          |
| --------- | ---------------------------------------------------------- | ---------------------------------- |
| **Plan**  | P0~P3 (규모별 차등)                                        | 무엇을 왜 만드는가?                |
| **Do**    | P4 구현 + Hook 실시간 보호                                 | 계획대로 실행하고 있는가?          |
| **Check** | P5 코드 리뷰 + P6 TDD + 빌드 게이트                        | 계획과 결과가 일치하는가?          |
| **Act**   | 교훈 기록(`docs/lessons.md`) → 3건+ 누적 시 규칙 승격 제안 | 반복 실수를 구조적으로 방지하는가? |

**Act 메커니즘**: ① 사용자 지적/반복 패턴 발견 시 `docs/lessons.md`에 기록 (self-improvement.md 참조) ② `session-start-validator.sh`가 세션 시작 시 3건+ 카테고리를 감지하여 승격 제안 ③ review-agent가 P5에서 반복 패턴을 독립 보고. 즉시 수정이 가능한 이슈는 Check 단계에서 바로 수정.

## 1. 작업 유형 분류

사용자 요청을 받으면 먼저 **"서비스 기능 코드"**(사용자가 쓰는 앱의 기능) 변경인지, **"개발 환경·도구·인프라"** 변경인지를 판단한 후 아래 유형에서 선택합니다.

## 2. 해당 Phase 실행

| 작업 유형                         | Phase 실행 순서   | 실행 방식                                                                             |
| --------------------------------- | ----------------- | ------------------------------------------------------------------------------------- |
| 신규 기능 (Small)                 | P4→P5             | 직접 P4 (요청 불명확 시 선택적 `/prompt-enhancer`) → `/completion-review`             |
| 신규 기능 (Medium)                | P1→P4→P5          | `/prompt-enhancer` → 직접 P4 → `review-agent`(P5: minimal)                            |
| 신규 기능 (Large)                 | P0→P1→P2→P3→P4→P5 | `planning-agent`(P0~P3, P0는 선택적) → 직접 P4 → `review-agent`(P5: full)             |
| 기존 기능 확장/수정/삭제 (Small)  | P4→P5             | 직접 P4 → `/completion-review`                                                        |
| 기존 기능 확장/수정/삭제 (Medium) | P4→P5             | 직접 P4 → `review-agent`(P5: minimal)                                                 |
| 기존 기능 확장/수정/삭제 (Large)  | P2→P3→P4→P5       | `planning-agent`(P2: 기존 PRD 수정/업데이트, P3) → 직접 P4 → `review-agent`(P5: full) |
| 버그 수정                         | P4→P5             | 직접 P4 → `review-agent`(P5: full)                                                    |
| 리팩토링                          | P3→P4→P5          | `/dev-docs-generator` 직접 호출 → 직접 P4 → `review-agent`(P5: full)                  |
| 문서 작업                         | 직접 수행         | 워크플로우 미적용. 단, **PRD 수정 후 `/prd-reviewer` 필수 실행** (아래 참조)          |
| 도구/환경 작업                    | 직접 수행         | 워크플로우 미적용                                                                     |
| 탐색/조사/분석/검토/기타          | 직접 수행         | 워크플로우 미적용                                                                     |

## 규모 판단 기준 (Small vs Medium vs Large)

### 기본 기준

- **Small**: 1파일, ≤10줄, 로직 없음
- **Medium**: 1~2파일, ~50줄, 로직 포함
- **Large**: 3+파일 또는 50줄+
- **Large 격상**: 파일 수·줄 수와 무관하게, 수정 대상이 **2개 이상 도메인**에 걸치면 Large
- **모호하면 Medium** (안전 우선)

### 자동 Medium 이상 경로

다음 경로는 **줄 수/로직 무관**하게 자동으로 Medium 이상:

- `**/api/**` (API Route Handler)
- `**/actions.ts` (Server Actions)
- `**/middleware.ts` (미들웨어)
- `**/*.test.ts` `**/*.test.py` `**/*.spec.*` (테스트 코드)
- `**/migrations/**` `**/schema.*` (DB 관련)
- `**/types/**` (타입 정의)

## 워크플로우 미적용 유형 판단 가이드

- **도구/환경 작업**: 스킬 생성/설치, MCP 서버 설정, CI/CD 파이프라인, 패키지 의존성, 린트/포맷 설정, 개발 도구 구성 등 서비스 기능이 아닌 개발 인프라 변경
- **탐색/조사/분석**: 코드 동작 설명, 성능 분석, 코드 리뷰, 아키텍처 조사, 기술 비교 등 코드 변경 없이 정보를 제공하는 작업

### PRD 수정 후 검증 규칙

IMPORTANT: `dev/docs/prd/` 내 문서를 수정한 경우, 수정 완료 후 **`/prd-reviewer`를 반드시 실행**한다.

- **단일 PRD**: 축 A~D + F 검증
- **모듈형 PRD**: 축 A~F 검증 (E: 크로스 문서 정합성, F: 설계 원칙 정합성)
- 이슈 발견 시 재수정 후 역검증까지 완료해야 "문서 작업 완료"로 간주

## Phase 정의

> **Phase 계층**: P0~P6는 최상위 Phase. 각 Phase 내부 세부 실행 단계는 Step(A/B/C)으로 표기 (예: P5 Step A).

상세 Phase 규칙(P4 구현 세부, P0 가이드, 참조 경로)은 `.claude/rules/task-workflow-detail.md` 참조.

| Phase | 이름                | 수행 방법                                                                                                                                                                                     |
| ----- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| P0-A  | 아이디에이션        | `planning-agent` 위임. 단독: `/brainstorming`.                                                                                                                                                |
| P0-B  | 리서치              | `planning-agent` 위임. 단독: `/research`.                                                                                                                                                     |
| P0-C  | 사업 기획           | `planning-agent` 위임. 단독: `/business-planner`.                                                                                                                                             |
| P0-D  | 서비스 기획         | `planning-agent` 위임. 단독: `/service-planner`.                                                                                                                                              |
| P0-E  | Council Review      | `planning-agent` 위임. 3관점 병렬 분석 (기술/비즈니스/UX) + 충돌 조정. Large 신규 기능 전용. 단독: `/council-review`.                                                                         |
| P1    | 프롬프트 강화       | `planning-agent` 위임 (Large 신규 기능). Small: 생략. Medium: 요청 불명확 시 선택적 호출. 단독: `/prompt-enhancer`.                                                                           |
| P2    | PRD 검색/생성       | `planning-agent` 위임. 단독: `/prd-generator`.                                                                                                                                                |
| P3    | 개발 문서 생성      | `planning-agent` 위임. 단독: `/dev-docs-generator`.                                                                                                                                           |
| P4    | 구현                | 상세 → `task-workflow-detail.md` P4 섹션                                                                                                                                                      |
| P5    | 완료 및 문서 최신화 | Small → `/completion-review` (문서 최신화만). Medium/Large/버그 → `review-agent` 위임 (코드 리뷰 + 문서 최신화). 상세 → review-agent.md                                                       |
| P6    | 외부 AI 교차 검증   | `review-agent`가 P5 후 조건 판단 → **사용자 확인** 시 수행. P5(동일 모델 리뷰)의 공통 맹점을 다른 AI 모델(Gemini/Codex)로 보완. 조건: 3+파일·새 API·DB 스키마 중 2개+. 상세 → review-agent.md |
