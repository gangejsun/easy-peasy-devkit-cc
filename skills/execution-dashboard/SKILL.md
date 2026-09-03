---
name: execution-dashboard
description: 이번 세션에서 어떤 스킬/규칙/Hook이 참조되었는지 실행흐름을 파악하고 싶을 때 사용합니다. 타임라인과 카테고리별 요약으로 표시합니다. "실행추적", "실행흐름", "뭐 참고했어?", "어떤 스킬 썼어?" 등의 키워드 사용 시 트리거됩니다. 수동 호출 전용.
disable-model-invocation: true
---

# Execution Dashboard

현재 세션에서 사용된 Skill/Rule/Hook/Agent/문서를 추적하여 타임라인과 카테고리별 요약 보고서를 생성합니다.

## 워크플로우

### Step 0: 계측 로그 통합 (결정론적 데이터)

v3 훅이 기록한 `.claude/.epcc/` 로그를 읽어 정확한 실행 데이터를 확보합니다:

| 로그 | 기록 주체 | 내용 |
| --- | --- | --- |
| `.claude/.epcc/skilluse.log` | track-skill (PostToolUse) | 스킬 호출 |
| `.claude/.epcc/hookrun.log` | 모든 훅 (common.sh) | 훅 실행·exit code |
| `.claude/.epcc/graph.log` | 훅 (epcc_edge) | 그래프 엣지 traversal |

### Step 1: 세션 분석 (시맨틱 데이터)

대화 기록을 역순으로 분석하여 Skill 호출, Rule 참조, Hook 실행, Agent 호출, 문서 탐색 정보를 추출합니다.

### Step 2: 타임라인 생성

### Step 3: 카테고리별 요약

### Step 4: 출력

## 주의사항

- 대화 기록이 긴 경우 최근 50개 메시지만 분석
- System reminder에 없는 정보는 추론하지 말고 생략
- `.claude/.epcc/` 로그가 없으면 Step 0을 건너뛰고 대화 기록 분석만 수행 (추측 데이터임을 보고서에 명시)
