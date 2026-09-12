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

## 2.4 스킬 프론트매터 — 상주 비용을 정하는 스위치

확인: 2026-09-02 · 출처: https://code.claude.com/docs/en/skills

**description은 스킬을 한 번도 부르지 않아도 상주한다.** 그 상주 여부를 정하는 필드가 둘이다.

| 프론트매터 | 사용자가 부를 수 있나 | 모델이 부를 수 있나 | description 상주 |
| --- | --- | --- | --- |
| (기본) | 예 | 예 | **상주** |
| `disable-model-invocation: true` | 예 | **아니오** | **상주하지 않음** |
| `user-invocable: false` | 아니오 | 예 | 상주 |

즉 **수동 호출 전용 스킬에 `disable-model-invocation: true`를 붙이면 매 세션 비용이 0이 된다.**
붙이지 않으면 "수동 전용"이라고 본문에 적어도 description 값은 그대로 상주한다 —
**선언과 과금이 어긋나는 자리**이고, 이 저장소가 실제로 그랬다(v3.24.0 기준 5개).

> **주의 — `claude plugin details`의 추정기는 이 플래그를 반영하지 않는다.**
> 실측(2026-09-03 · v3.25.0): 플래그를 붙인 5개 스킬이 여전히 always-on 70~140토큰으로
> 계상됐고, 그 값은 description 길이에 비례했다. 훅은 `no model context cost`로 따로
> 표시하므로 0 비용을 모델링할 줄은 안다 — 이 플래그만 빠진 것으로 보인다.
> 위 표가 공식 문서의 선언이고 추정기는 투영이라 **선언을 따르되**, 절감 폭을
> `details` 숫자로 검증하려 하지 않는다. 두 값이 갈린다는 사실 자체를 여기 남긴다.

반대 방향의 함정: 라우팅 표(`rules/workflow-routing.md`)나 `workflow.graph.json`의 `phase`가
자동 발동으로 지목하는 스킬에 이 플래그를 붙이면 **모델이 영영 부를 수 없게 되어 라우팅이 끊긴다.**
붙이기 전에 두 곳을 모두 확인한다 (`doctor --fast`의 「수동 전용 일치」가 대신 본다).

그 밖에 비용·동작에 영향이 있는 필드:

| 필드 | 효과 |
| --- | --- |
| `description` + `when_to_use` | 합쳐 **1,536자**에서 잘린다(`skillListingMaxDescChars`로 조절). 넘기면 뒤가 사라진다 |
| `paths` | 스킬도 규칙 카드처럼 경로 조건부로 만들 수 있다 |
| `context: fork` (+ `agent`, `background`) | 스킬을 **격리된 서브에이전트에서** 실행 — 본문과 중간 산출물이 메인 창에 들어오지 않는다 |
| `model` · `effort` | 그 스킬 턴에만 적용되는 모델·노력 수준 |
| `allowed-tools` · `disallowed-tools` | 그 스킬 턴 동안의 도구 허용/차단 |

**본문은 부를 때만 로드되고, 참조 파일은 읽을 때만 로드된다** — SKILL.md는 500줄 이하로 두고
상세는 옆 파일로 내리는 것이 공식 권고다.

## 2.5 마켓플레이스 — 한 저장소, 여러 플러그인

확인: 2026-09-01 · 출처: https://code.claude.com/docs/en/plugin-marketplaces

하나의 `marketplace.json`이 **같은 저장소의 서브디렉토리에 있는 여러 플러그인**을
호스팅할 수 있다.

| 사실 | 내용 |
| --- | --- |
| `source` | `"./"`로 시작하는 **상대 경로**. **마켓플레이스 루트**(=`.claude-plugin/`을 담은 디렉토리) 기준으로 해석된다 |
| `../` | **쓰지 않는다** — 마켓플레이스 루트 밖은 참조 불가 |
| 서브 플러그인 매니페스트 | 각 플러그인 디렉토리에 **자기 `.claude-plugin/plugin.json`이 있어야 한다** |
| 버전 | 플러그인마다 **독립**이다. 마켓플레이스 `metadata.version`과 같을 필요가 없다 |

이 저장소가 그 형태다 — `epcc-devkit`(`source: "./"`) · `epcc-marketing`
(`source: "./marketing/"`) · `epcc-harness`(`source: "./harness/"`)가 공존한다.
**분리 이유는 같지 않다 — 둘이고, 무엇을 아끼는지가 다르다.**

| 분리 | 아끼는 것 | 근거 |
| --- | --- | --- |
| `epcc-marketing` | **컨텍스트 예산** | 5종 중 3종이 모델 발동 가능이라 description이 상주한다. 개발과 무관한 스킬이 개발 세션의 예산을 먹는다 |
| `epcc-harness` | **커맨드 목록** | `harness-evaluation`은 `dmi: true`라 상주 비용이 **0**이다(§2.4). 그런데도 분리한 것은 `skills/`에 두면 소비자가 **쓸 수 없는 `/harness-evaluation`을 보고 누르기** 때문이다 — 소스 저장소 밖에서는 「평가 대상 없음」으로 exit 2 한다 |

§2.4의 표가 말하듯 `dmi: true`는 **상주 비용만** 끈다. 커맨드 목록의 한 줄은 그대로 남으므로,
`dmi`를 붙였다고 소비자가 쓸 수 없는 스킬을 `skills/`에 둬도 되는 것이 아니다.

**따라오는 함정 하나** — `doctor`의 버전 대조가 `marketplace.json`의 **모든** `"version"`을
긁으면 남의 플러그인 버전까지 기준과 맞춰야 하는 것으로 읽혀 **오탐으로 실패한다.**
대조는 `plugin.json`의 이름과 같은 엔트리로 좁힌다 (`doctor.sh` 「매니페스트」).

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

### 5.1 발화 빈도 — 규격이 아니라 **언제 오는가**

확인: 2026-08-26 · 출처: https://code.claude.com/docs/en/hooks

| 이벤트 | 언제 | 한 세션당 |
| --- | --- | --- |
| `Stop` | **Claude가 응답을 마칠 때** — 사용자 프롬프트 1건이 완결되는 시점 | 프롬프트 수만큼 |
| `PreToolUse` / `PostToolUse` | 도구 호출마다 | 도구 호출 수만큼 |
| `SessionStart` | 시작·재개(`startup`/`resume`) | 1~2 |

> **`Stop`은 도구 호출마다 오지 않는다.** 한 턴 안에서 도구를 20번 부르고 마지막에 답해도
> `Stop`은 **1회**다. 이 사실이 계약에 없어서 평가 v5가 오탐을 냈다 — 턴 진행 중에
> `hookrun.log`를 읽고 `build-gate` 기록이 없는 것을 보고 "Stop 훅이 실사용에서
> 한 번도 실행되지 않았다"고 단정했다. 실제로는 그 턴이 아직 안 끝난 것뿐이었고,
> 턴이 끝나자 같은 초에 기록됐다.
>
> **계측의 공백은 훅의 죽음과 같은 모양을 한다.** 가르는 것은 "그 이벤트가 발생할
> 기회가 있었는가"이고, 그것은 로그가 아니라 **발화 조건**을 봐야 안다.

### 5.3 timeout — 기본값과 초과 시 운명

확인: 2026-09-12 · 출처: https://code.claude.com/docs/en/hooks

`command` 훅의 기본 timeout은 **600초**다(`prompt` 30 · `agent` 60. `UserPromptSubmit`류는 30,
`MessageDisplay`는 10으로 낮아진다). 훅별로 `"timeout": <초>` 필드로 줄인다.

> Claude Code cancels a `command`, `http`, or `mcp_tool` hook that reaches its `timeout`,
> discarding the hook's output, so on most events a timed-out hook renders no decision.
>
> A timed-out `command` hook doesn't block the tool call. The call continues through the
> normal permission flow, so don't count on a stalled hook to act as a gate.

| 사실 | 이 하네스에 대한 함의 |
| --- | --- |
| 초과 시 출력 **폐기**, 오류 표시 없음 | 침묵 실패의 한 형태 — 훅이 느려지면 브리핑·차단이 조용히 사라진다 |
| `PreToolUse` 초과는 **차단하지 않는다**(fail-open) | `security-check`가 15초를 넘기면 그 호출은 검사 없이 통과한다. 게이트의 강도는 timeout 안에서 끝나는 속도에 의존한다 |
| 기본 600초 | 선언하지 않으면 멈춘 훅이 세션을 10분 붙잡는다 — `hooks/hooks.json`은 훅별로 10~30초를 선언한다 |

## 5.2 Windows에서 훅 실행 셸

확인: 2026-09-05 · 출처: https://code.claude.com/docs/en/hooks · https://code.claude.com/docs/en/setup

`hooks/hooks.json`의 모든 `command`는 리터럴 문자열이다(예: `"bash ${CLAUDE_PLUGIN_ROOT}/scripts/session-brief.sh"`).
이 문자열을 **무엇으로 해석해 실행할지**는 `shell` 필드가 정하고, 기본값은 OS에 따라 갈린다:

> Defaults to `"bash"`, or to `"powershell"` on Windows when Git Bash isn't installed.

| 실행 환경 | 훅을 해석하는 셸 | `"bash script.sh"` 문자열의 운명 |
| --- | --- | --- |
| macOS · Linux · WSL | bash | 그대로 실행 |
| 네이티브 Windows + Git for Windows 설치됨 | Git Bash | 그대로 실행 |
| 네이티브 Windows + Git for Windows **없음** | PowerShell | PowerShell이 `bash`를 실행 파일로 찾으려 하고, PATH에 없으면 **훅이 실행되지 않는다** |

설치 가이드도 같은 결론을 명시한다:

> [Git for Windows] enables the Bash tool by providing Git Bash. Without Git for Windows,
> Claude Code runs shell commands via the PowerShell tool.

**이 하네스에 대한 함의** — 훅 5개(`session-brief`·`security-check`·`build-gate`·`handoff`·
`track-skill`) 전부가 `"bash ..."` 패턴이다. Git for Windows 없는 네이티브 Windows에서는
`jq` 부재처럼 **일부 검증이 판정 불가로 저하**되는 정도가 아니라, **훅 5개가 통째로 한 번도
실행되지 않을 수 있다** — 이 저장소가 경계하는 "조용한 무력화" 중 가장 심한 형태다.
(참고로 Git for Windows가 제공하는 Git Bash는 `grep`·`awk`·`sed`는 포함하지만 `jq`는
포함하지 않는다 — 별도 설치가 필요하다.)

소비자 대상 설치 안내는 `docs/windows-setup.md`와 README의 「Windows 사용자라면」
콜아웃이 맡는다.

## 6. 서브에이전트

확인: 2026-08-24 · 출처: https://code.claude.com/docs/en/sub-agents

- `tools:` frontmatter는 **허용 목록**이다. 없는 도구는 쓸 수 없다 —
  `Skill`이 목록에 없으면 그 에이전트는 **스킬을 호출할 수 없다**
- **단, 허용 목록만으로 쓰기를 막지는 못한다.** 실측(2026-09-07 · v3.26.0):
  `tools: Read, Grep, Glob, WebSearch, WebFetch`만 선언한 `epcc-planner`가 실행 시점에
  **Write·Edit를 함께 갖고 있었다.** 같은 세션에서 `disallowedTools: Write, Edit, NotebookEdit`를
  가진 `epcc-reviewer`는 선언대로였다. 원인은 확인하지 못했다 — 추정하지 않고 사실만 남긴다.
  **쓰기를 확실히 막으려면 `disallowedTools`를 함께 쓴다.** 허용 목록 하나로
  「권한이 없으니 위반이 불가능하다」를 주장하면 그 주장이 조용히 거짓이 된다
- 메인 대화의 auto memory는 서브에이전트에 상속되지 않는다
- 에이전트는 `.claude/rules/`를 상속받지 않는다 → 필요한 규범은 프롬프트에 직접 적는다
