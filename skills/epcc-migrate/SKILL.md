---
name: epcc-migrate
description: EPCC Devkit v2 하네스가 설치된 프로젝트를 v3로 전환합니다. 죽은 훅 제거, 규칙 3계층 재배치, 에이전트 개명을 수행합니다. 사용자가 "하네스 마이그레이션", "v3 전환", "epcc 업그레이드"를 요청할 때 사용하며 수동 호출 전용입니다.
---

<!-- epcc-doctor: allow-stale-refs
     이 문서는 v2에서 제거할 파일들을 이름으로 나열한다.
     그 경로들이 실재하지 않는 것이 정상이므로 dangling 검사에서 제외한다. -->

# /epcc-migrate — v2 → v3 마이그레이션

## 목적

v2 하네스가 설치된 프로젝트를 v3 구조로 전환합니다.

**왜 필요한가**: v2는 프로젝트의 `.claude/`에 규칙을 직접 배치하는 구조였고, 훅 11개 중
10개가 경로 계산 오류와 출력 규격 불일치로 조용히 죽어 있었습니다. v3는 그 자산들을
플러그인 소유로 옮겨 자동 갱신되게 하고, 죽은 훅을 제거합니다.

## Step 1: 현재 상태 진단

먼저 무엇이 있는지 **측정**합니다. 추측으로 지우지 않습니다.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" --fast
```

그리고 프로젝트 측 자산을 확인합니다:

```bash
ls -1 .claude/rules/ 2>/dev/null
ls -1 .claude/hooks/ 2>/dev/null
ls -1 .claude/agents/ 2>/dev/null
grep -c 'hooks' .claude/settings.json 2>/dev/null
```

## Step 2: 제거 대상 (v3가 대체하거나 폐기)

### 죽은 훅 — `.claude/hooks/`

아래는 v2에서 **경로 계산 오류로 작동하지 않았거나** 출력 규격이 무효였던 훅입니다.
v3의 4개 훅이 플러그인에서 자동 제공되므로 프로젝트 사본은 제거합니다.

| 파일 | 제거 사유 |
| --- | --- |
| `session-start-validator.sh` | 루트 오계산 → 정수 비교 붕괴. `session-brief`가 대체 |
| `stop-guard.sh` | Stop이 지원하지 않는 `decision`/`reason` 출력 → 한 번도 차단 못 함. `build-gate`가 대체 |
| `pre-compact-saver.sh` | PreCompact 평문 stdout은 컨텍스트에 안 들어감 → 무효. `handoff`가 대체 |
| `post-tool-use-*.sh` (3종) | 매 도구 호출마다 `/tmp` 전체 스캔. 소비자도 함께 제거되어 무의미 |
| `pre-tool-use-guard.sh` | 절대/상대 경로 정규식 불일치로 미작동 |
| `stop-trace-summary.sh` | 기본 비활성 + 소비 로그 제거됨 |
| `persistent-loop.sh` · `loop-keyword-detector.sh` | 네이티브 `/loop` 및 `ralph-loop` 플러그인과 중복 |

**`.claude/settings.json`의 해당 훅 등록도 함께 제거**합니다. 플러그인이 `hooks/hooks.json`으로 관리합니다.

> `security-check.sh`는 v2에서 유일하게 정상 작동한 훅입니다. 프로젝트 사본이 있으면
> 제거해도 되지만(플러그인이 제공), **프로젝트 고유 시크릿 패턴이 추가되어 있으면
> 그 패턴을 먼저 사용자에게 보여주고 확인**받으세요.

### 폐기된 규칙 — `.claude/rules/`

| 파일 | 처리 |
| --- | --- |
| `task-workflow.md` · `task-workflow-detail.md` | → `reversibility.md`로 대체 (P0~P6 번호 폐기) |
| `modification-guardrails.md` | → `code-change.md` + `harness-change.md`로 분할 |
| `self-improvement.md` | → `lessons.md` (Act 루프는 `doctor --lessons`가 수행) |
| `agent-governance.md` | → 삭제. 규범이 에이전트 프롬프트로 이관됨 |
| `decision-autopilot.md` · `-detail.md` | → 삭제. 핵심만 T0 운영 계약으로 축약 |
| `claude-md-authoring.md` | → 삭제 |
| `execution-transparency.md` | → 삭제 |

**제거 전 반드시**: 각 파일에 프로젝트가 직접 추가한 내용이 있는지 확인하고,
있으면 사용자에게 보여준 뒤 어디로 옮길지 확인받습니다. 승격된 규칙이 여기 쌓여 있을 수 있습니다.

### 구 에이전트 — `.claude/agents/`

`planning-agent.md` · `review-agent.md` → 플러그인의 `epcc-planner` · `epcc-reviewer`로 대체.
프로젝트 사본이 있으면 제거합니다.

## Step 3: v3 규칙 설치

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-rules.sh"
```

설치 후 확인:

```bash
ls -1 .claude/rules/
```

## Step 4: 유지 대상 (건드리지 않음)

- `.claude/rules/code-conventions.md` · `project-structure.md` — 프로젝트 고유
- `.claude/rules/` 중 프로젝트가 직접 만든 도메인 규칙
- `.claude/skills/` 프로젝트 오버라이드
- `dev/` 전체 (작업 문서·PRD·아카이브)
- `docs/lessons.md`
- `CLAUDE.md` — 단 아래 Step 5 참조

## Step 5: CLAUDE.md 정리

v2 CLAUDE.md는 삭제된 파일을 참조하고 있을 가능성이 높습니다.

1. `.claude/rules/task-workflow.md` 참조 → 제거 (운영 계약이 세션 시작 시 자동 주입됨)
2. P0~P6 Phase 테이블 → 제거 (되돌림 축으로 대체됨)
3. 존재하지 않는 파일을 가리키는 링크 전부 제거

## Step 6: 검증 (필수)

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" --fast
bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh" --self-test
```

**실패 0이 아니면 마이그레이션이 끝나지 않은 것입니다.** 남은 실패를 사용자에게 보고하세요.

## Step 7: 보고

```
v3 마이그레이션 완료

제거: 훅 N개 · 규칙 N개 · 에이전트 N개
설치: .claude/rules/ 규칙 카드 N개
보존: [프로젝트 고유 자산 목록]

doctor --fast: 통과 N · 경고 N · 실패 N

확인 필요:
- [사용자 결정이 필요했던 항목]
```

## 주의사항

- **파일을 지우기 전에 반드시 내용을 읽고**, 프로젝트가 추가한 내용이 있으면 사용자에게 확인받습니다
- 한 번에 전부 지우지 말고 카테고리별로 진행하며 각 단계 후 `doctor --fast`로 확인합니다
- `git status`가 깨끗한 상태에서 시작하면 되돌리기 쉽습니다

## 마이그레이션 후: 스택 가이드

v2 프로젝트에는 스택 맞춤 가이드가 없다. 마이그레이션 완료 후 안내한다:

- `epcc.config.json`에 `techStack.backend` 차원이 없으면 `/stack-guide-generator` 실행을 권한다
  (백엔드 유형·DB·데이터 액세스를 확인하고 frontend/backend-guide를 생성)
- 정확히 Next.js+Supabase 조합이면 플러그인 원본이 담당하므로 생성 불필요
