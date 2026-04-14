---
paths:
  - ".claude/agents/**"
  - "dev/active/**"
---

# Agent Governance

## 현재 아키텍처: 2 SubAgent 체제

| Agent          | 담당 Phase        | 정당화 근거                                                                                                                 |
| -------------- | ----------------- | --------------------------------------------------------------------------------------------------------------------------- |
| planning-agent | P0~P3 (P0-E 포함) | Context Pollution 방지 (수백 행 규모의 Skill 프롬프트 격리), Skill 간 오케스트레이션, P0-E Council Review (3관점 병렬 분석) |
| review-agent   | P5~P6             | 확인 편향 방지 (구현자 ≠ 검증자 분리), 검증 특화 워크플로우                                                                 |
| Main Session   | P4                | 사용자와의 지속적 상호작용 필요, 코드베이스 전체 탐색                                                                       |

## Agent 추가 판단 기준

새 SubAgent는 아래 3가지 중 **최소 1개**를 충족할 때만 도입합니다:

1. **Context Pollution**: 해당 작업의 프롬프트/결과가 Main Session 컨텍스트의 20%+ 차지
2. **Parallelization**: 독립적인 작업을 동시에 수행하여 속도 향상 가능
3. **Specialization**: 3개+ Skill을 조합하는 전문화된 워크플로우 존재

충족하지 않으면 Main Session에서 직접 수행하거나 기존 Agent에 통합합니다.

## Handoff 원칙

- Agent 간 handoff는 **파일 기반**으로만 수행 (컨텍스트 메모리 의존 금지)
- handoff 매체: `dev/active/` 파일, `dev/docs/prd/` 파일, `git diff`

### Handoff 검증

각 Agent는 입력 수신 시 **자체 검증**을 수행합니다 (구체적 검증 로직은 각 agent 파일에 정의):

- planning-agent: P3 완료 후 산출물 파일 존재 + 필수 섹션 확인
- review-agent: P5 시작 전 dev/active/ 또는 git diff 존재 확인

### Handoff 실패 시

재시도 상한: **3회**. 초과 시 사용자에게 보고.

실패 보고 형식:

```
[Handoff 실패] {source} → {target}
- 원인: {구체적 실패 원인}
- 누락: {파일/섹션 목록}
- 복구 옵션:
  (A) 자동 재시도
  (B) 수동 생성
  (C) 건너뛰기
```
