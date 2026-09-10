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

```bash
tail -200 .claude/.epcc/skilluse.log .claude/.epcc/hookrun.log .claude/.epcc/graph.log 2>/dev/null
```

### Step 1: 세션 분석 (시맨틱 데이터)

대화 기록을 역순으로 분석하여 Skill 호출, Rule 참조, Hook 실행, Agent 호출, 문서 탐색 정보를 추출합니다.

**출처를 항목마다 표시한다** — 로그에서 온 것(`계측`)과 대화에서 추론한 것(`추론`)을
섞으면 이 보고서를 근거로 쓸 수 없다. 둘이 어긋나면 계측이 이긴다.

### Step 2: 타임라인 생성

시간순으로 한 줄씩. 로그가 있는 항목이 먼저 자리를 잡고, 추론 항목은 그 사이에 끼운다.

```
| 시각 | 종류 | 이름 | 결과 | 출처 |
| --- | --- | --- | --- | --- |
| 14:02 | Hook | session-brief | exit 0 | 계측 |
| 14:03 | Skill | codebase-survey | 완료 | 계측 |
| 14:11 | Rule | code-change.md | 참조 | 추론 |
```

시각을 알 수 없으면 `--`로 두고 순서만 유지한다 — **시각을 지어내지 않는다.**

### Step 3: 카테고리별 요약

Skill · Rule · Hook · Agent · 문서 다섯 갈래로 접는다.

```
| 카테고리 | 호출 수 | 항목 (호출 순) |
| --- | --- | --- |
| Skill | 2 | codebase-survey · completion-review |
| Hook | 5 | session-brief ×1 · build-gate ×3 · track-skill ×1 |
| Rule | 3 | workflow-routing · code-change · reversibility |
| Agent | 0 | — |
| 문서 | 4 | CLAUDE.md · docs/harness-anatomy.md … |
```

호출 수 0인 카테고리도 지우지 않고 `0 | —`로 남긴다 — **없었다는 것이 관측 결과다.**

### Step 4: 출력

위 두 표를 이 순서로 낸다: **요약 표 먼저, 타임라인 나중.** 그 뒤 한 문단으로
눈에 띄는 것만 적는다 (예: "훅 5회 중 3회가 build-gate — 소스 변경이 잦았다").

계측 로그가 없어 전부 추론이면 **보고서 첫 줄에 그 사실을 적는다.**

## 주의사항

- 대화 기록이 긴 경우 최근 50개 메시지만 분석
- System reminder에 없는 정보는 추론하지 말고 생략
- `.claude/.epcc/` 로그가 없으면 Step 0을 건너뛰고 대화 기록 분석만 수행 (추측 데이터임을 보고서에 명시)
