# 플랫폼 계약 — Claude Code가 보장하는 것

이 파일은 **하네스가 의존하는 플랫폼 동작의 정본**이다. 규칙·스킬·훅·스크립트가
"Claude Code는 이렇게 동작한다"를 전제할 때, 그 전제는 여기에 있어야 한다.

> **왜 이 파일이 있는가**
> v3에서 플랫폼 동작을 기억으로 단정해 결함이 반복됐다 — 치환되지 않는 자작 변수
> 표기 28곳, `.claude/rules/`가 네이티브 기능인 줄 몰라 작업 라우팅을 갱신 경로가 없는
> 곳에 배치, "규칙이 어떤 프로젝트에도 도달하지 못했다"는 사실이 아닌 전제.
> 셋 다 공식 문서 한 번이면 막혔다.

## 이 파일을 쓰는 법

1. **플랫폼 동작을 주장하기 전에 여기를 본다.**
2. 없으면 **공식 문서를 확인하고 출처 URL과 확인 날짜를 적어 추가한다.**
   전언·기억·"아마 그럴 것"은 넣지 않는다.
3. 항목이 틀린 것으로 드러나면 **고치고 날짜를 갱신한다.**
   `doctor --fast`가 확인 날짜 180일 초과를 경고한다 — 플랫폼은 움직인다.

---

## 1. 치환 변수

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/skills

| 변수 | 값 | 어디서 |
| --- | --- | --- |
| `${CLAUDE_SKILL_DIR}` | 스킬 자신의 디렉토리 | 개인·프로젝트·**플러그인** 스킬 전부 |
| `${CLAUDE_PLUGIN_ROOT}` | 플러그인 설치 디렉토리 | **플러그인 스킬에서만** |
| `${CLAUDE_PROJECT_DIR}` | 프로젝트 루트 | 스킬 · 훅 환경변수 |
| `${CLAUDE_PLUGIN_DATA}` | 플러그인 데이터 디렉토리 | 플러그인 스킬 |

**치환되는 곳은 두 곳뿐이다** — ⓐ 스킬의 마크다운 본문 ⓑ `allowed-tools` frontmatter의
Bash 규칙. 같은 변수를 양쪽에 쓰면 권한 프롬프트 없이 번들 스크립트를 실행할 수 있다.

> **자작 표기는 아무것도 치환하지 않는다.** `<skill-dir>` · `<Base directory>` 같은
> 표기는 이 저장소에서는 상대 경로가 우연히 맞아 통과하지만, 소비자에서 스킬은
> 플러그인 캐시(`~/.claude/plugins/cache/<마켓>/<플러그인>/<버전>/skills/<이름>/`)에
> 있으므로 호출이 실패한다. `doctor --fast`가 검출한다.

## 2. 플러그인 컴포넌트 자동 발견

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/plugins-reference

| 컴포넌트 | 기본 경로 | 매니페스트 키의 성질 |
| --- | --- | --- |
| 스킬 | `skills/` · `commands/` · 루트 `SKILL.md` | **기본에 추가** — `"skills": "./skills/"`는 같은 곳을 두 번 스캔(무해하나 불필요) |
| 에이전트 | `agents/` | **기본을 대체** |
| 커맨드 | `commands/` | **기본을 대체** |
| 훅 | `hooks/hooks.json` | 자동 발견. **매니페스트가 같은 파일을 또 가리키면 중복으로 판정되어 플러그인 로드가 거부된다** |

`rules`는 **플러그인 컴포넌트 타입이 아니다.** 플러그인의 `rules/`는 자동 배포되지
않으므로 `scripts/install-rules.sh`가 프로젝트 `.claude/rules/`로 설치한다.

## 3. `.claude/rules/` 로딩

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/memory

`.claude/rules/`는 **Claude Code 네이티브 기능**이다. 하네스가 만든 관습이 아니다.

| frontmatter | 로드 시점 |
| --- | --- |
| `paths:` **없음** | **매 세션 시작 시 무조건** — `.claude/CLAUDE.md`와 동일 우선순위 |
| `paths:` 있음 | Claude가 **매칭 파일을 읽을 때**. 매 도구 호출마다가 아니다 |

`paths`는 glob이며 중괄호 확장을 지원한다. 사용자 수준 `~/.claude/rules/`는 프로젝트
규칙보다 **먼저** 로드된다(= 프로젝트가 우선권을 갖는다).

> `paths:`를 붙이는 순간 조건부가 된다. **작업 시작 전에 필요한 규범**(무엇을 어떤
> 순서로 만드는가, 이전 작성물을 인용하기 직전의 점검)은 아직 아무 파일도 열지 않은
> 시점에 필요하므로 `paths`를 붙이면 안 된다.

## 4. CLAUDE.md 로딩

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/memory

- 작업 디렉토리와 **그 위 모든 디렉토리**의 `CLAUDE.md`·`CLAUDE.local.md`를 시작 시 로드
- **하위** 디렉토리의 것은 그 디렉토리 파일을 읽을 때 로드
- 블록 수준 HTML 주석은 **컨텍스트 주입 전에 제거된다** (유지자 메모용으로 안전)
- 권고 크기 200줄 미만. 4 MiB 초과 파일은 통째로 건너뛴다
- 시스템 프롬프트가 아니라 **사용자 메시지로** 전달된다 — 강제가 아니라 맥락이다.
  반드시 막아야 하는 것은 훅으로 만든다

## 5. 훅 이벤트별 출력 규격

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/hooks

**평문 stdout이 컨텍스트가 되는 이벤트는 셋뿐이다** —
`SessionStart` · `UserPromptSubmit` · `UserPromptExpansion`.

| 이벤트 | 차단 | 출력 |
| --- | --- | --- |
| `SessionStart` | 불가 | **평문 stdout이 컨텍스트가 된다** |
| `PreToolUse` | 가능 (exit 2) | `hookSpecificOutput.additionalContext` |
| `Stop` / `SubagentStop` | 가능 | **`decision`·`reason` 미지원.** `continue`·`systemMessage`·`additionalContext` 사용 |
| `PreCompact` | 가능 (exit 2) | **평문 stdout은 컨텍스트에 안 들어감** → JSON 필요 |
| `SessionEnd` | 불가 | 평문 stdout은 디버그 로그행 |
| `PostToolUse` | — | JSON |

미지원 필드는 **조용히 무시된다.** 그래서 "출력했다"가 "전달됐다"가 아니다.
`doctor --fast`가 이벤트별 규격 위반을 검출한다.

## 6. 서브에이전트

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/sub-agents

- `tools:` frontmatter는 **허용 목록**이다. 없는 도구는 쓸 수 없다 —
  `Skill`이 목록에 없으면 그 에이전트는 **스킬을 호출할 수 없다**
- 메인 대화의 auto memory는 서브에이전트에 상속되지 않는다
- 에이전트는 `.claude/rules/`를 상속받지 않는다 → 필요한 규범은 프롬프트에 직접 적는다
