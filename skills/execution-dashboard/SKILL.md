---
name: execution-dashboard
description: 현재 세션의 실행 흐름(Skill/Rule/Hook/Agent/문서)을 타임라인과 카테고리별 요약으로 표시합니다. "실행추적", "실행흐름", "뭐 참고했어?", "어떤 스킬 썼어?" 등의 키워드 사용 시 트리거됩니다. 수동 호출 전용.
---

# Execution Dashboard

현재 세션에서 사용된 Skill/Rule/Hook/Agent/문서를 추적하여 타임라인과 카테고리별 요약 보고서를 생성합니다.

## 워크플로우

### Step 1: 세션 분석

대화 기록을 역순으로 분석하여 다음 정보 추출:

1. **Skill 호출**: System reminder의 "Following skills were invoked" 확인
2. **Rule 참조**: Read 도구로 읽은 `.claude/rules/*.md` 파일 목록
3. **Hook 실행**: System reminder의 "hook success/failure" 메시지
4. **Agent 호출**: Task 도구 호출 기록 (subagent_type 확인)
5. **문서 탐색**: Read/Glob/Grep으로 접근한 파일 목록

### Step 2: 타임라인 생성

시간순으로 정렬하여 실행 흐름 재구성:

```
[시간] [유형] [세부사항]
14:30 - Skill: /prd-generator (자동)
14:31 - Rule: security.md 읽기
14:32 - Agent: planning-agent 호출
14:33 - 문서: dev/docs/prd/auth-2026-03-07.md 생성
14:35 - Hook: PreToolUse security-check.sh ✅
```

### Step 3: 카테고리별 요약

각 카테고리별로 통계 생성:

**Skill (사용 횟수)**:
- `/prd-generator` (1회) — 자동 트리거
- `/dev-docs-generator` (1회) — planning-agent 호출

**Rule (참조 횟수)**:
- `.claude/rules/security.md` (2회)
- `.claude/rules/code-conventions.md` (1회)

**Hook (실행 횟수 + 성공/실패)**:
- `SessionStart` (1회) ✅
- `PreToolUse` (3회) ✅ 모두 통과

**Agent (호출 횟수 + 작업)**:
- `planning-agent` (1회) — P1→P2→P3 완료
- `Explore` (2회) — 코드베이스 탐색

**문서 (읽기/쓰기 구분)**:
- 읽기: `dev/docs/architecture/authentication.md`
- 쓰기: `dev/docs/prd/auth-2026-03-07.md`

### Step 4: 출력

다음 형식으로 Markdown 보고서 생성:

```markdown
# 🔍 실행 추적 대시보드

## 세션 요약
- 시작: {YYYY-MM-DD HH:MM}
- 지속 시간: {N}분
- Tool 호출: {N}회

## 🎯 Skill ({N}개)
1. `/{skill-name}` ({HH:MM}) — {자동/수동} — {설명}
...

## 📖 Rule ({N}개)
1. `.claude/rules/{name}.md` ({N}회 참조)
...

## 🔍 Hook ({N}회)
- `{HookType}` ({N}회) {✅/❌} {결과 요약}
...

## 🤖 Agent ({N}개)
- `{agent-type}` ({HH:MM}) — {작업 내용}
...

## 📚 문서 ({N}개)
- 📖 읽기: {file-path}
- ✍️ 쓰기: {file-path}
...
```

## 예시

**입력**:
```
실행흐름
```

**출력**:
```markdown
# 🔍 실행 추적 대시보드

## 세션 요약
- 시작: 2026-03-07 14:30
- 지속 시간: 15분
- Tool 호출: 12회

## 🎯 Skill (2개)
1. `/prd-generator` (14:30) — 자동 — PRD 검색/생성
2. `/dev-docs-generator` (14:35) — planning-agent — 개발 문서 생성

## 📖 Rule (2개)
1. `.claude/rules/security.md` (2회 참조)
2. `.claude/rules/code-conventions.md` (1회 참조)

## 🔍 Hook (4회)
- `SessionStart` (1회) ✅ Agent Governance 로드
- `PreToolUse` (3회) ✅ 모두 통과

## 🤖 Agent (1개)
- `planning-agent` (14:32) — P1→P2→P3 완료

## 📚 문서 (3개)
- 📖 읽기: `dev/docs/architecture/authentication.md`
- 📖 읽기: `dev/docs/security/rls-patterns.md`
- ✍️ 쓰기: `dev/docs/prd/auth-2026-03-07.md`
```

## 주의사항

- 대화 기록이 긴 경우 최근 50개 메시지만 분석 (성능 고려)
- System reminder에 없는 정보는 추론하지 말고 생략
- 타임스탬프는 대략적 순서만 표시 (정확한 시각은 불가)
- 사용자가 "간단히"를 요청하면 세션 요약과 카테고리별 개수만 표시
