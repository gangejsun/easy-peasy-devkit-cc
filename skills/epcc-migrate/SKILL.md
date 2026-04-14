---
name: epcc-migrate
description: |
  EPCC Devkit Generator(plugin-generator) 기반 프로젝트를 Runtime Plugin으로 전환합니다.
  기존에 `npx epcc-devkit generate`로 설정한 프로젝트를 런타임 플러그인 방식으로 마이그레이션할 때 사용합니다.
trigger: manual
---

# /epcc-migrate — Generator → Runtime Plugin 마이그레이션

## 목적

기존 `plugin-generator/` (빌드타임 코드 제너레이터) 기반으로 설정된 프로젝트를 런타임 플러그인 방식으로 전환합니다. Core 파일은 플러그인이 제공하므로 프로젝트에서 제거하고, 프로젝트 고유 설정만 유지합니다.

## 전제 조건

- EPCC Devkit 런타임 플러그인이 설치되어 있어야 합니다
- 기존 `.claude/` 디렉토리가 Generator로 생성된 파일을 포함하고 있어야 합니다

## 실행 절차

### Step 1: 현재 상태 분석

프로젝트의 `.claude/` 디렉토리를 분석합니다:

**Core 파일 식별** (플러그인이 대체할 파일):

```
.claude/rules/
  - task-workflow.md          → 플러그인 Core Rule
  - agent-governance.md       → 플러그인 Core Rule
  - self-improvement.md       → 플러그인 Core Rule
  - execution-transparency.md → 플러그인 Core Rule
  - claude-md-authoring.md    → 플러그인 Core Rule

.claude/skills/
  - brainstorming/            → 플러그인 Core Skill
  - research/                 → 플러그인 Core Skill
  - business-planner/         → 플러그인 Core Skill
  - service-planner/          → 플러그인 Core Skill
  - prompt-enhancer/          → 플러그인 Core Skill
  - prd-generator/            → 플러그인 Core Skill
  - dev-docs-generator/       → 플러그인 Core Skill
  - completion-review/        → 플러그인 Core Skill
  - requesting-code-review/   → 플러그인 Core Skill
  - receiving-code-review/    → 플러그인 Core Skill
  - gemini-claude-loop/       → 플러그인 Core Skill
  - skill-generator/          → 플러그인 Core Skill
  - execution-dashboard/      → 플러그인 Core Skill
  - insight-saver/            → 플러그인 Core Skill
  - test-driven-development/  → 플러그인 Core Skill
  - security-review/          → 플러그인 Core Skill

.claude/hooks/
  - 모든 .sh/.mjs 파일       → 플러그인 hooks/hooks.json이 대체

.agent/
  - skills/                   → 불필요 (플러그인 스킬 자동 공유)
  - workflows/                → 불필요 (플러그인이 제공)
```

**프로젝트 고유 파일 식별** (유지해야 할 파일):

```
.claude/rules/
  - code-conventions.md       → 유지 (프로젝트 고유)
  - project-structure.md      → 유지 (프로젝트 고유)
  - modification-guardrails.md      → 제거 (SessionStart Hook이 대체)
  - security.md               → 제거 (Security Hook이 대체)

.claude/skills/
  - frontend-dev-guidelines/  → 유지 (프리셋 스킬 오버라이드)
  - backend-dev-guidelines/   → 유지 (프리셋 스킬 오버라이드)
  - ui-ux-design/             → 유지 (프리셋 스킬 오버라이드)

.claude/governance/
  - dynamic-rules/            → 유지 (프로젝트 고유)
```

### Step 2: epcc.config.json 생성 (미존재 시)

기존 CLAUDE.md에서 프로젝트 정보를 추출하여 `epcc.config.json`을 자동 생성합니다:

1. CLAUDE.md 파싱 → 프로젝트명, 언어, 기술 스택 추출
2. 적합한 프리셋 자동 추천
3. 사용자에게 확인 후 생성

### Step 3: 마이그레이션 보고서 생성

변경 사항을 요약한 보고서를 출력합니다:

```
## EPCC Migration Report

### 제거 대상 (플러그인이 대체)
- .claude/rules/task-workflow.md (Core Rule)
- .claude/rules/agent-governance.md (Core Rule)
- ... (Core 규칙 5개)
- .claude/skills/brainstorming/ (Core Skill)
- ... (Core/Configurable 스킬 16개)
- .claude/hooks/ (전체 — hooks.json이 대체)
- .agent/ (전체 — 플러그인 스킬 자동 공유)

### 유지 대상 (프로젝트 고유)
- .claude/rules/code-conventions.md
- .claude/rules/project-structure.md
- .claude/skills/frontend-dev-guidelines/ (프리셋 오버라이드)
- .claude/governance/dynamic-rules/

### 새로 생성
- epcc.config.json

### settings.json Hook 제거 대상
- hooks.PreToolUse (플러그인 hooks.json이 대체)
- hooks.PostToolUse (플러그인 hooks.json이 대체)
- ... (모든 EPCC Hook 항목)
```

### Step 4: 사용자 확인 후 실행

**반드시 사용자 확인 후 진행합니다:**

1. 보고서 검토 요청
2. "진행하시겠습니까?" 확인
3. 확인 시:
   - Core 파일 제거
   - `.claude/settings.json`에서 EPCC Hook 항목 제거
   - `.agent/` 디렉토리 제거
   - `epcc.config.json` 생성 (미존재 시)

### Step 5: 완료 보고

```
EPCC Migration 완료!

✅ Core 파일 제거: 5 rules, 16 skills, 8 hooks
✅ .agent/ 디렉토리 제거
✅ settings.json Hook 정리
✅ epcc.config.json 생성

유지된 프로젝트 파일:
  - .claude/rules/code-conventions.md
  - .claude/rules/project-structure.md
  - .claude/skills/frontend-dev-guidelines/ (프리셋 오버라이드)
  - .claude/governance/

다음 단계:
  1. Claude Code를 재시작하세요
  2. SessionStart Hook이 프로젝트 컨텍스트를 자동 주입합니다
  3. 오버라이드 스킬(.claude/skills/)은 플러그인 스킬보다 우선합니다
```

## 주의사항

- **비파괴적**: 프로젝트 고유 파일은 절대 삭제하지 않습니다
- **롤백 가능**: 삭제 전 파일 목록을 기록하여, 필요 시 Generator로 재생성 가능합니다
- `dev/` 디렉토리는 건드리지 않습니다 (작업 문서 보존)
- `.claude/governance/dynamic-rules/`는 유지합니다 (허용 목록 등)
