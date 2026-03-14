# Governance System - 하이브리드 전략

## 개요

EPCC Devkit는 **하이브리드 거버넌스 시스템**을 운영합니다:
- **Rule 파일** (`.claude/rules/*.md`): 정적 규칙, 세션 시작 시 로드
- **Hook 스크립트** (`.claude/hooks/*.sh|.mjs`): 동적 검증, 이벤트 기반 실행

---

## 아키텍처

```
.claude/
├── rules/                          # 정적 규칙 (paths 지정 → 조건부 로드)
│   ├── task-workflow.md             # Phase 라우팅 (Core)
│   ├── agent-governance.md          # Agent 아키텍처 (Core)
│   ├── code-conventions.md          # 코딩 스타일 (Preset/Template)
│   ├── project-structure.md         # 파일 구조 (Preset/Template)
│   └── security.md                  # 보안 체크리스트 (Configurable)
│
├── hooks/                          # 동적 거버넌스
│   ├── security-check.mjs           # 보안 패턴 검사 (Configurable)
│   ├── pre-tool-use-guard.mjs       # 도메인 경계 차단 (Configurable)
│   ├── post-tool-use-tracker.sh     # 파일 변경 추적 (Core)
│   └── session-start-validator.sh   # Agent 규칙 조건부 출력 (Template)
│
└── governance/                     # 하이브리드 설정
    └── README.md                   # 이 파일
```

---

## 의사결정 가이드

### 새 규칙 추가 시

```
[Q1] 항상 적용되어야 하는가?
  YES → Rule 파일 (.claude/rules/*.md)
  NO  ↓

[Q2] 물리적 차단이 필요한가?
  YES → PreToolUse Hook
  NO  ↓

[Q3] 실시간 추적/로깅인가?
  YES → PostToolUse Hook
  NO  ↓

[Q4] 세션 시작 시에만 필요한가?
  YES → SessionStart Hook (조건부)
  NO  → Rule 파일 (기본)
```
