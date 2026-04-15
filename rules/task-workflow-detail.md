---
paths:
  - "src/**"
  - "packages/**"
  - "dev/active/**"
  - "dev/docs/research/**"
  - "dev/docs/business/**"
  - "dev/docs/service/**"
  - "dev/docs/council/**"
---

# Task Workflow Detail - P4 구현 세부 규칙 + P0 가이드

> 이 파일은 P0(기획) 또는 P4(구현) 관련 작업 시 조건부 로딩됩니다. 라우팅 테이블은 `task-workflow.md` 참조.

## P4 구현 세부 규칙

### 공통 규칙 (모든 규모)

- `dev/active/<name>/` 폴더가 존재하면 참조. tasks.md 즉시 체크, context.md 업데이트
- `dev/active/` 폴더가 없는 경우(Small/Medium): 코드 컨벤션(`.claude/rules/code-conventions.md`)과 사용자 요구사항만으로 구현
- **구현 후 `/simplify`(Claude Code 번들 스킬, 코드 간소화)로 코드 정리 → 빌드 & 테스트 실행 필수**
- **계획과 괴리 시 즉시 멈추고 재계획**
- **규모 격상 감지**: P4 진행 중 수정 파일이 3개 이상이거나 2개 이상 도메인에 걸치면, 현재 규모(Small/Medium)를 재판단하고 필요 시 상위 규모의 워크플로우로 전환
- P4 완료 시 `dev/active/<name>/context.md`의 **IMPLEMENTATION NOTES** 섹션 업데이트 (변경 파일, 핵심 결정, 미해결 항목)

### Small / Medium 작업

- 메인 세션에서 직접 코딩 수행 (기존 방식 유지)
- **Small P1**: 생략. 요청이 불명확한 경우에만 `/prompt-enhancer` 선택적 호출
- **Medium P1**: 요청 불명확 또는 도메인 경계가 애매할 때 `/prompt-enhancer` 선택적 호출. 2개 이상 도메인에 걸치는 변경이 감지되면 Large로 격상하여 `planning-agent` 위임

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
4. 서브에이전트 보고의 `교훈` 필드가 "없음"이 아니면 → `docs/lessons.md`에 기록 (self-improvement.md 형식 준수)
5. 모든 태스크 완료 후 메인 세션에서 `/simplify` → 빌드 & 테스트 실행

**서브에이전트 프롬프트 템플릿:**

```
프로젝트: {project_root}
기술 스택: {tech_stack}
사전 준비: 작업 시작 전 아래 파일을 반드시 Read하세요:
- .claude/rules/code-conventions.md (코딩 컨벤션)
- .claude/rules/modification-guardrails.md §1~4 (도메인 경계 + 최소 수정 원칙)
- .claude/rules/security.md (보안 규칙)
언어 규칙: 내부 추론은 영어, 사용자 출력만 한국어
과잉 설계 금지: 요청된 것만 구현. 불필요한 추상화·의존성·범위 확장 금지.

태스크: {task_text}

참조 문서: {context.md 핵심 내용}

완료 시 아래 형식으로 보고하세요:

상태: [DONE / DONE_WITH_CONCERNS / NEEDS_CONTEXT / BLOCKED]
완료 항목: [구현한 내용 1-3줄 요약]
수정 파일: [변경한 파일 목록]
우려사항: [있으면 기술, 없으면 "없음"]
교훈: [작업 중 발견한 반복 가능한 교훈이 있으면 기술, 없으면 "없음"]
```

### P4 → P5 핸드오프

P4 완료 후 review-agent를 디스패치할 때 다음 형식으로 전달합니다:

```
작업 유형: [신규 기능 / 확장·수정 / 버그 수정 / 리팩토링]
작업 규모: [Medium / Large]
dev/active 경로: dev/active/<name>/
변경 요약: [1-3줄 요약]
변경 파일 수: [N]개
빌드/테스트 결과: [성공 / 실패 시 상세]
```

## 규모 판단 명확한 예시

| 작업                         | 규모   | 이유                          |
| ---------------------------- | ------ | ----------------------------- |
| 버튼 색상 변경 (className만) | Small  | 1파일, 3줄, 로직 없음         |
| 기존 함수에 매개변수 추가    | Medium | 1파일, 30줄, 호출처 수정 필요 |
| 새 페이지 + API 추가         | Large  | 5파일, 150줄                  |

## P0 Phase 가이드

P0는 **신규 기능 Large** 작업에서 선택적으로 적용됩니다.

### P0 선택 규칙

신규 기능 Large 판정 시, 요구사항 명확성과 무관하게 **항상 P0 진행 여부를 사용자에게 질문**합니다.

**planning-agent 질문 형식:**

- P0 Phase 옵션(P0-A ~ P0-E)을 제시하고 사용자가 선택
- 사용자가 "P0 불필요" / "바로 진행"을 선택하면 P1부터 시작
- 요구사항이 막연할 때는 해당 P0 Phase를 **추천**으로 표시

**P0 Phase 선택 가이드 (사용자 참고용):**

- 아이디어 구체화가 필요할 때 → P0-A (아이디에이션)
- 시장/경쟁 데이터가 필요할 때 → P0-B (리서치)
- 사업성 검증이 필요할 때 → P0-C (사업 기획)
- 기능 요구사항 정리가 필요할 때 → P0-D (서비스 기획)
- 다관점 분석이 필요할 때 → P0-E (Council Review)

### P0 산출물 경로

| Phase | 산출물 경로                                 |
| ----- | ------------------------------------------- |
| P0-B  | `dev/docs/research/<topic>.md`              |
| P0-C  | `dev/docs/business/business-plan-<name>.md` |
| P0-D  | `dev/docs/service/service-plan-<name>.md`   |
| P0-E  | `dev/docs/council/council-review-<name>.md` |

## Dev Docs 3-File 패턴

> `dev/active/<name>/`는 **plan / context / tasks** 3개 파일로 구성되며, Phase·Agent 간 핸드오프 매체 역할을 합니다. 구조·섹션 규약은 `dev/templates/feature-{plan,context,tasks}-template.md`가 권위자이며, 생성 절차는 `/dev-docs-generator` 스킬이 수행합니다.

### 운영 원칙

- `context.md`의 **SESSION PROGRESS** 섹션은 **마일스톤마다 갱신**한다 (완료 시점이 아닌, 완료할 때마다). ✅ COMPLETED / 🟡 IN PROGRESS / ⚠️ BLOCKERS / 📝 NEXT STEPS를 현재 상태로 유지
- `tasks.md`의 체크박스는 **완료 즉시** `[x]`로 표시 (배치 처리 금지)
- `plan.md`는 스코프나 Phase가 **실제로 변경될 때만** 수정. 진행 상황 추적에 쓰지 않는다
- 작업 항목은 **actionable**해야 한다: 파일명·수용 기준·의존성을 포함. "인증 고치기"가 아니라 "`AuthMiddleware.ts`에 JWT 검증 추가 (수용: 유효 토큰 통과, 오류는 에러 트래커로 전송)"

### 재개 절차 (컨텍스트 리셋 후)

`dev/active/<name>/`가 존재하는 작업에 복귀할 때:

1. `context.md` 먼저 읽기 — SESSION PROGRESS에 현재 상태가 집약되어 있음
2. `tasks.md`로 완료/미완료 항목 확인
3. `plan.md`로 전체 전략 재확인
4. 즉시 작업 재개, 사용자에게 현재 상태 요약 보고 후 다음 단계 제안

### Handoff 매체

Agent 간 핸드오프는 파일 기반으로만 수행하며 구두(컨텍스트 메모리) 의존 금지 (`agent-governance.md` §Handoff 원칙).

| Handoff                             | 매체                                           |
| ----------------------------------- | ---------------------------------------------- |
| planning-agent → Main Session(P4)   | `dev/active/<name>/` 3개 파일                  |
| Main Session(P4) → review-agent(P5) | `context.md` IMPLEMENTATION NOTES + `git diff` |

## P4 구현 시 참조 경로

> 아래 경로는 기능 개발 과정에서 생성됩니다. 해당 문서가 없으면 참조를 건너뜁니다.

| 개발 영역    | 참조 경로                   |
| ------------ | --------------------------- |
| 아키텍처     | `dev/docs/architecture/`    |
| API 설계     | `dev/docs/api/`             |
| 데이터베이스 | `dev/docs/database/`        |
| 보안         | `dev/docs/security/`        |
| 테스트       | `dev/docs/testing/`         |
| 배포         | `dev/docs/deployment/`      |
| 문제 해결    | `dev/docs/troubleshooting/` |
| 디자인       | `dev/docs/design/`          |
