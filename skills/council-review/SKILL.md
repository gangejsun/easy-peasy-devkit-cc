---
name: council-review
description: |
  복잡한 기획 결정에서 기술/비즈니스/UX 3개 관점의 병렬 분석 후 통합 권고안을 도출합니다.
  사용자가 "다관점 분석", "council review", "3관점 검토"를 요청할 때,
  또는 planning-agent가 P0-E 단계로 호출할 때 사용합니다.
  Large 신규 기능 전용. 수동 호출 전용 (/council-review). 자동 트리거되지 않습니다. (project)
---

# Council Review

기획된 기능을 기술/비즈니스/UX 3개 관점에서 **병렬 분석**하고, 관점 간 **충돌을 감지·조정**하여 통합 권고안을 도출합니다. 순차 분석의 편향을 방지하고 사각지대 발견율을 높이는 것이 목적입니다.

<HARD-GATE>
3개 관점 분석 결과의 통합 권고안은 사용자 확인 없이 P1으로 전달되어서는 안 됩니다.
반드시 사용자 확인 후 전달합니다.
</HARD-GATE>

## 워크플로우

### Step 1: 입력 판별 및 전제 조건 확인

| 입력 상황                                            | 실행 Step                                                            |
| ---------------------------------------------------- | -------------------------------------------------------------------- |
| P0-D 서비스 기획서와 함께 호출 (planning-agent 경유) | Step 2 → Step 3 → Step 4 → Step 5 → Step 6                           |
| 사용자가 직접 호출 (서비스 기획 존재)                | Step 2 → Step 3 → Step 4 → Step 5 → Step 6                           |
| 서비스 기획서 없이 호출                              | 사용자에게 안내: "P0-D(서비스 기획) 완료 후 사용 가능합니다." → 종료 |

**전제 조건**: `dev/docs/service/service-plan-<name>.md` 존재 필수 (분석 대상이 되는 구체적 요구사항 필요).

### Step 2: 컨텍스트 조립

P0-A~D 산출물을 수집하여 통합 컨텍스트 브리프(~500단어)를 구성합니다.

**수집 대상:**

- `dev/docs/service/service-plan-<name>.md` (필수) — 기능 요구사항(FR-xxx), 비기능 요구사항(NFR-xxx), 핵심 화면, 데이터 모델
- `dev/docs/business/business-plan-<name>.md` (있으면) — 비즈니스 모델, KPI, 수익 구조
- `dev/docs/research/<topic>.md` (있으면) — 시장/경쟁사/기술 조사 결과

### Step 3: 3관점 Agent 병렬 디스패치

3개의 Task tool 서브에이전트를 **동시에** 호출합니다 (병렬 실행이 핵심).

각 서브에이전트에게 전달할 프롬프트는 `references/perspective-prompts.md`를 참조합니다.

**응답 수집 및 실패 처리:**

- 3개 모두 성공 → Step 4로 진행
- 1개 실패 → 2개 응답으로 진행 (실패 관점을 보고서에 "미분석" 표기)
- 2개+ 실패 → BLOCKED, 사용자에게 실패 보고
- NEEDS_CONTEXT 반환 시 → 추가 정보 포함하여 해당 Agent만 재디스패치 (최대 1회)

### Step 4: 충돌 감지

3개 관점의 응답을 6개 결정 차원에서 비교합니다.

**6개 결정 차원:**

| 차원                      | 비교 내용                              |
| ------------------------- | -------------------------------------- |
| 범위 (Scope)              | 포함/제외할 기능에 대한 각 관점의 입장 |
| 우선순위 (Priority)       | 무엇을 먼저 구현해야 하는지            |
| 아키텍처 (Architecture)   | 기술적 접근 방식                       |
| 일정 (Timeline)           | 공수/복잡도 평가                       |
| 리스크 (Risk)             | 각 관점에서 본 핵심 리스크             |
| 트레이드오프 (Trade-offs) | 품질 vs 속도, 비용 vs 기능 등          |

**판정 기준:**

- **ALIGNED**: 3관점 모두 같은 방향 → 합의 사항으로 기록
- **PARTIAL**: 2관점 동의 + 1관점 상이 → 다수 의견 채택, 소수 의견 기록
- **CONFLICTED**: 3관점 모두 상이 또는 2개 핵심 관점이 대립 → Step 5로

### Step 5: 재질의 (CONFLICTED 존재 시, 최대 1회)

CONFLICTED로 판정된 차원에 대해 상충하는 관점에 **재질문**합니다.

- Task tool로 해당 관점 Agent에게 재질문 (순차 실행)
- 조정 후 → PARTIAL로 변경
- 조정 불가 → "unresolved"로 표시 (사용자에게 tie-breaking 요청)
- **2차 재질의 없음** — 1회 재질의 후에도 미해결이면 그대로 보고

### Step 6: 통합 보고서 생성 및 사용자 확인

**저장 경로**: `dev/docs/council/council-review-<name>.md`

**사용자 확인:**

```
3관점 Council Review가 완료되었습니다.

## 분석 결과 요약
- 합의 (ALIGNED): [N]개 차원
- 절충 (PARTIAL): [N]개 차원
- 미해결 (UNRESOLVED): [N]개 차원

결과를 확정하면 P1(프롬프트 강화)으로 전달됩니다.
```

## 참조 문서

- 관점별 프롬프트 템플릿: `references/perspective-prompts.md`
- 통합 보고서 출력 형식: `assets/council-report-template.md`
- 서비스 기획서 저장소: `dev/docs/service/`
- Council Review 저장소: `dev/docs/council/`
