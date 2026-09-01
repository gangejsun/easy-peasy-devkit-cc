# Phase 2 — 훅 11개 → 5개 재작성

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 1의 DoD를 통과한 뒤에.**

---

9단계 중 **2단계**다. Phase 1의 `doctor --fast`·`--self-test`가 뱉은 실패 목록이 이 단계의
입력이다. 훅 11개(1,518줄)를 **5개**로 재작성한다.

## 왜 줄이는가 — 개수가 아니라 도달의 문제다

출처 저장소에서 같은 구성의 훅 11개 중 8개가 4개월간 **죽은 채 아무 신호도 내지 않았다.**
살아 있던 3개도 두 개는 조용히 무시되는 형식으로 출력하고 있었다. 구체적으로:

- `stop-guard.sh` — **이 저장소의 실물을 열어 확인하라.** `stop-guard.sh:98`이
  `{"decision":"block","reason":…}`로 출력한다. **`Stop` 이벤트는 이 필드를 지원하지 않는다**
  (지원 필드는 `additionalContext`/`continue`/`systemMessage`). 파일 머리 주석은
  "하드 블록 — 세션 종료 물리적 차단"을 주장하고 `exit 1`을 쓰는데, **Stop 훅에서 차단은
  exit 2다**(`exit 1`은 비차단 오류). Phase 0의 `platform-contract.md` §5로 대조하라 —
  **주석이 주장하는 차단력과 실제 차단력이 다르면 그 게이트는 한 번도 막은 적이 없다.**
- `stop-guard.sh`의 입력이 `/tmp/modified-files-${SESSION_ID}.log`다 —
  `post-tool-use-tracker.sh`가 쓰는 파일이고, `/tmp`는 세션·재부팅을 넘어 보장되지 않는다.
  로그가 없으면 **"코드 변경 없음"으로 판정해 통과시킨다.** 즉 추적기가 죽으면 게이트도
  조용히 꺼진다. 대체품 `build-gate.sh`는 `/tmp` 상태에 의존하지 않고 **git 상태와
  transcript**를 본다
- `pre-compact-saver.sh` — `pre-compact-saver.sh:111`이 평문 `echo -e "$OUTPUT"`로 출력한다.
  **`PreCompact` stdout은 컨텍스트에 들어가지 않는다.** 평문이 컨텍스트가 되는 이벤트는
  `SessionStart`·`UserPromptSubmit`·`UserPromptExpansion` 셋뿐이다. 출처 저장소에서는 같은
  결함으로 4개월간 아무것도 보존되지 않았고, 사용자가 `SESSION-HANDOFF` 파일을 수동으로
  7개나 만들어야 했다.
  같은 파일 48~50행에 `|| echo "0"` 폴백이 있다 — **1줄 자리에 2줄이 들어가 정수 비교가
  깨지는** 바로 그 관용구다 (Phase 1의 `epcc_num`이 막는 것).
- `session-start-validator.sh:23` — `PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"`.
  **훅 파일 위치 기준의 상대 계산이다.** 지금은 우연히 맞지만 훅을 옮기거나 심볼릭 링크를
  거치면 저장소 밖을 가리킨다. 그리고 217행이 `/harness-evaluation (8번 + 10번 축)`을 권고하는데
  **그 축 체계는 Phase 8에서 7축으로 대체된다** — 살아남은 유일한 출력이 폐기될 권고다
- `post-tool-use-*` 3종 — 전부 `/tmp/<이름>-${SESSION_ID}.log`에 쓰고 **매 도구 호출마다
  `find /tmp -name '…' -mtime +7 -delete`를 돈다.** 상태가 저장소 밖에 있어 세션·재부팅을
  넘어 보장되지 않고, 정작 **필요한 측정(스킬 호출)은 하지 않는다.**
  대체품은 상태를 `$(epcc_state_dir)`(저장소 안)에 둔다
- `loop-keyword-detector.sh` + `persistent-loop.sh` — Claude Code가 `/loop`을 내장으로 제공한다.
  **빌트인과 경쟁하는 자산을 만들지 않는다.**

## 번역 표

| 출처(플러그인) | 여기 |
| --- | --- |
| `${CLAUDE_PLUGIN_ROOT}/scripts/lib/common.sh` | `${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel)}/.claude/scripts/lib/common.sh` |
| `hooks/hooks.json` | `.claude/settings.json`의 `hooks` 키 |
| 훅 파일 위치 `scripts/` | `.claude/hooks/` (스크립트는 `.claude/scripts/`, 훅은 `.claude/hooks/`로 분리해도 되고 합쳐도 된다 — **하나로 정하고 doctor가 그 규약을 검사하게 한다**) |

## 폐기·대체 매핑

| 기존 (11) | 처분 | 근거 |
| --- | --- | --- |
| `session-start-validator.sh` | → **`session-brief.sh`** 로 대체 | 루트 계산 결함 + 살아남은 출력이 금지된 권고뿐 |
| `pre-compact-saver.sh` | → **`handoff.sh`** 로 대체 (PreCompact + SessionEnd) | 평문 출력이 컨텍스트에 안 들어감 |
| `stop-guard.sh` | → **`build-gate.sh`** 로 대체 | 미지원 필드 + 단어 매칭 판정 |
| `security-check.sh` | **유지·개편** | 유일하게 제 일을 하던 훅. `lib/common.sh` 규율로 재작성 |
| `post-tool-use-tracker.sh`<br>`post-tool-use-read-tracker.sh`<br>`post-tool-use-build-tracker.sh` | → **`track-skill.sh`** 하나로 (PostToolUse `Skill` 매처) | 매 호출 `/tmp` 스캔 폐기. 측정 없이 컬링하지 않으려면 **스킬 호출**을 재야 한다 |
| `pre-tool-use-guard.sh` | **폐기** | 역할이 `security-check.sh`와 겹친다. 남길 검사가 있으면 그쪽으로 흡수 |
| `stop-trace-summary.sh` | **폐기** | 계측은 `epcc_heartbeat`/`epcc_edge`가 한다 (Phase 5가 소비) |
| `loop-keyword-detector.sh`<br>`persistent-loop.sh` | **폐기** | Claude Code 내장 `/loop` |

**폐기는 삭제가 아니라 이동이다.** `.claude/deprecated/`로 옮기고 만료일을 파일명에 새긴다
(기본 14일). 이 저장소에는 git이 있으므로 롤백은 보장되지만, `.claude/deprecated/`가
이미 존재하므로 그 규약을 따른다:

```
.claude/hooks/stop-guard.sh → .claude/deprecated/hooks_stop-guard.sh.shadow-expires-2026-09-08
```

## 남는 5개의 계약

모든 훅은 아래로 시작한다. **`lib/common.sh`를 source 하지 않는 훅을 만들지 않는다.**

```bash
INPUT=$(cat 2>/dev/null || printf '{}')
source "${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}/.claude/scripts/lib/common.sh"
epcc_begin "<훅이름>" "$INPUT"
```

그리고 **상태·로그 파일 경로는 `$(epcc_state_dir)`을 거친다.** `.claude/.epcc`를 문자열로
직접 조립하지 않는다 — 그러면 `--self-test`가 자기가 재는 로그에 쓰게 되고, 그 위에서
판정한 사용량 통계는 측정이 아니라 자기 주장이 된다 (Phase 1의 E-09).
`doctor --fast`가 이 규약을 검사한다.

### ① `session-brief.sh` — SessionStart

두 가지를 한다:

1. **T0 운영 규칙 출력** — `.claude/rules/operating-contract.md`(Phase 3에서 생성)의 본문을
   출력한다. HTML 주석 블록은 제거하고(`sed '/<!--/,/-->/d'`) 출력한다.
   > **왜 규칙 파일이 상시 로드되는데 훅이 또 출력하는가?** 이 저장소에서는 중복이 맞다.
   > Phase 3에서 판단한다 — 규칙 파일만으로 충분하다고 판정되면 이 절을 빼고,
   > 훅 쪽을 정본으로 삼으면 규칙 파일에 `paths`를 붙인다. **둘 중 하나만 정본이다.**
2. **세션 브리핑** — 브랜치·HEAD·미커밋 수·열린 `dev/active/` 워크스페이스·**훅 생존 현황**
   (`hookrun.log`에서 최근 실행 훅 목록). 컴포넌트는 자기를 보증하지 않는다 — 다른
   컴포넌트가 읽어서 죽은 훅을 보고한다.

**첫 커밋 전 저장소 가드 필수.** `git log`/`git rev-parse HEAD`는 커밋 0개인 저장소에서
exit 128을 내고, `pipefail` + ERR trap이 훅을 통째로 죽여 브리핑이 전부 사라진다.

```bash
if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
  HEAD_LINE=$(git log -1 --format='%h %s' | cut -c1-72)
else
  HEAD_LINE="없음 (첫 커밋 전)"
fi
```

### ② `security-check.sh` — PreToolUse (`Edit|Write|MultiEdit`)

하드코딩된 시크릿 **문자열**을 정규식으로 막는다. 위반 확인 시 exit 2 + 차단 사유.

**3상태를 지킨다.** 판정 불가(파일 읽기 실패·도구 부재)는 차단하지 않고 `epcc_emit_notice`로
알린다. 오탐은 사용자가 훅을 끄게 만들고, 꺼진 훅의 차단력은 0이다.

기존 330줄에서 살릴 것과 버릴 것을 가른다: **값이 아니라 배치의 문제**(서버 전용 키에
`NEXT_PUBLIC_` 접두사 등)는 정규식이 원리적으로 못 잡는다 → Phase 3의 `security.md` 규칙
카드로 넘긴다. 훅은 **문자열 패턴만** 본다. 훅과 카드의 분업을 훅 파일 주석에 표로 남긴다.

### ③ `build-gate.sh` — Stop

소스를 고쳤는데 빌드/테스트를 돌리지 않고 끝내려 하면 막는다.

```
1. stop_hook_active == true 면 즉시 exit 0 (무한 루프 방지)
2. 세션 기준선($(epcc_state_dir)/session-baseline.txt) 대비 변경된 소스 확장자 파일이 있는가
   → 없으면 exit 0
3. transcript JSONL을 **파싱해서** Bash 도구 호출의 command만 추출 → 빌드/테스트 명령이
   실제로 실행됐는가
4. 실행됐으면 exit 0, 아니면 epcc_emit_block "Stop" "<사유+구체적 명령>"
```

**3번이 3상태다.** `jq`는 macOS 기본 설치에 없다. `jq` 미설치 또는 transcript 읽기 실패는
**판정 불가**이지 미실행이 아니다:

```bash
UNDECIDABLE=""
if ! command -v jq >/dev/null 2>&1; then UNDECIDABLE="jq 미설치"
elif [ -z "$TRANSCRIPT" ] || [ ! -r "$TRANSCRIPT" ]; then UNDECIDABLE="transcript를 읽을 수 없음"; fi

if [ -n "$UNDECIDABLE" ]; then
  epcc_emit_notice "Stop" "소스 ${N}개가 변경되었으나 빌드/테스트 실행 여부를 **판정할 수 없습니다** (${UNDECIDABLE}). 차단하지 않습니다 — 직접 확인하세요."
  exit 0
fi
```

판정 명령은 이 저장소의 `pnpm build`/`pnpm test`/`pnpm lint`를 구체적으로 안내한다.
차단 메시지 끝에 **"(작성했다 ≠ 작동한다 — 검증까지가 한 동작입니다)"**를 붙인다.

### ④ `handoff.sh` — PreCompact + SessionEnd

컨텍스트 압축·세션 종료 시 작업 상태를 보존한다. **`epcc_emit_context`로 출력한다**
(평문 아님). 내용: 브랜치·HEAD·미커밋 목록(최대 12)·열린 `dev/active/` 워크스페이스의
task 진행률과 남은 작업.

`SessionEnd`면 `dev/handoff/<UTC타임스탬프>.md`로도 남기고 **최근 10개만 유지**한다.
파일에 append하는 코드를 쓰면 로테이션/상한을 같이 넣는다.

로테이션의 glob은 가드한다 — 매치 0건이면 리터럴이 파이프로 흐른다:

```bash
{ ls -1t "$HD"/*.md 2>/dev/null || true; } | tail -n +11 | while IFS= read -r old; do rm -f "$old"; done
```

첫 커밋 전 가드는 ①과 동일하게 필수다. 출처 저장소에서 이 가드가 없어 신규 프로젝트의
첫 세션에서 인계가 **전부** 소실됐다.

### ⑤ `track-skill.sh` — PostToolUse (매처 `Skill`)

스킬 호출을 `$(epcc_state_dir)/skilluse.log`에 기록한다. 이것이 없으면 "미사용 스킬 컬링"은
영원히 추측으로만 가능하다 — **측정 없이 컬링하지 않는다.**

매 도구 호출이 아니라 `Skill` 호출에만 반응한다. `/tmp` 스캔 없음. 5000행 초과 시 로테이션.

## `.claude/settings.json` 배선

```json
{
  "hooks": {
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash .claude/hooks/session-brief.sh" }] }],
    "PreToolUse":  [{ "matcher": "Edit|Write|MultiEdit", "hooks": [{ "type": "command", "command": "bash .claude/hooks/security-check.sh" }] }],
    "Stop":        [{ "hooks": [{ "type": "command", "command": "bash .claude/hooks/build-gate.sh" }] }],
    "PreCompact":  [{ "hooks": [{ "type": "command", "command": "bash .claude/hooks/handoff.sh" }] }],
    "SessionEnd":  [{ "hooks": [{ "type": "command", "command": "bash .claude/hooks/handoff.sh" }] }],
    "PostToolUse": [{ "matcher": "Skill", "hooks": [{ "type": "command", "command": "bash .claude/hooks/track-skill.sh" }] }]
  }
}
```

`permissions`·`env`·`outputStyle`·`enabledPlugins` 블록은 **그대로 둔다.** 단
`env.CLAUDE_EXECUTION_TRACE`는 폐기된 `stop-trace-summary.sh`가 쓰던 값이면 함께 제거한다.

## 하지 말 것

- 훅을 늘리지 않는다. 5개보다 많아지면 **Phase 1의 3-질문**(기존과 겹치는가 · 모델 향상으로
  불필요해졌는가 · 잘 되는 것을 굳이 바꾸는가)을 통과했는지 근거를 적는다.
- 개별 사례의 정답을 하드코딩하지 않는다. 다음 작업에도 재사용되는 개입만 남긴다.
- 판정 불가를 차단으로 접지 않는다.
- 폐기 훅을 `rm`하지 않는다 — `.claude/deprecated/`로 만료일과 함께 이동한다.

## 검증

```bash
bash .claude/scripts/doctor.sh --fast       # 훅 배선·출력 규격 절이 통과해야 한다
bash .claude/scripts/doctor.sh --self-test  # 5개 전부 픽스처 주입 → exit 0/2 + 규격 출력
```

**차단을 증명한다** — 살아있음 ≠ 작동함:

```bash
# ① security-check: 시크릿을 심은 PreToolUse 픽스처 → exit 2 + 차단 사유
echo '{"hook_event_name":"PreToolUse","cwd":"'$PWD'","tool_name":"Write","tool_input":{"file_path":"/tmp/x.ts","content":"const k=\"sk-ant-api03-REDACTED-EXAMPLE\""}}' \
  | bash .claude/hooks/security-check.sh; echo "exit=$?"   # 2 를 기대

# ② build-gate 3상태: jq를 PATH에서 가린 채 실행 → 차단이 아니라 systemMessage
PATH=/usr/bin:/bin bash -c 'echo "{\"hook_event_name\":\"Stop\",\"cwd\":\"'$PWD'\"}" | bash .claude/hooks/build-gate.sh'

# ③ handoff 첫 커밋 전 가드: 빈 저장소에서 죽지 않는지
T=$(mktemp -d); (cd "$T" && git init -q); \
  echo '{"hook_event_name":"PreCompact","cwd":"'$T'"}' | CLAUDE_PROJECT_DIR="$T" bash .claude/hooks/handoff.sh; echo "exit=$?"; rm -rf "$T"

# ④ 가드 제거 → 실패하는지 (검사가 실제로 무언가를 잡는지)
```

## 완료 기준 (DoD)

1. `.claude/hooks/`에 훅이 **5개**이고, 폐기 6개가 `.claude/deprecated/`에 만료일과 함께 있다
2. 5개 전부 `lib/common.sh`를 source하고 `epcc_begin`으로 시작한다
3. `doctor --self-test`가 5개 전부에 픽스처를 주입하고 실패 0이다
4. **차단 증명 ①~④가 전부 기대대로 동작한다.** 특히 ②가 `continue:false`가 아니라
   `systemMessage`를 내야 한다 — 판정 불가는 차단이 아니다
5. `.claude/settings.json`의 `hooks` 블록이 위 6개 엔트리와 일치하고, 가리키는 파일이 전부 실재한다
6. `grep -rn 'decision"\s*:\s*"block' .claude/hooks/` 가 **0건**이다
7. `.claude/.epcc/hookrun.log`에 5개 훅 이름이 전부 나타난다 (실제 세션을 한 번 돌린 뒤)
8. `grep -n '\.claude/\.epcc' .claude/hooks/*.sh` 가 **0건**이다 — 상태 경로는 `epcc_state_dir` 경유

---

**다음**: `phase-3-rules.md`
