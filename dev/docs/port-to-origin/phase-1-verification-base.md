# Phase 1 — 검증 기층: `lib/common.sh` + `doctor.sh`

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 0의 DoD를 통과한 뒤에.**

---

9단계 중 **1단계**다. 하네스를 고치기 전에 **고쳤는지 판정할 기계**를 먼저 만든다.

## 왜 이것이 먼저인가

출처 저장소(easy-peasy-devkit-cc)는 훅을 먼저 쓰고 검증기를 나중에 만들었다. 그 결과
훅 8개가 4개월간 죽은 채 아무 신호도 내지 않았고, 규칙 697줄이 어느 프로젝트에도
도달하지 못했으며, "차단한다"고 선언된 게이트가 한 번도 차단한 적이 없었다.
**살아있음 ≠ 작동함**이고, 둘을 가르는 것은 재실행뿐이다.

원칙: **Script가 할 수 있는 것은 Script에, LLM만 할 수 있는 것은 LLM에.**
검출된 결함의 다수는 안목이 아니라 grep으로 잡혔다.

## 번역 표 (이 저장소는 플러그인이 아니다)

| 출처(플러그인) | 여기 |
| --- | --- |
| `${CLAUDE_PLUGIN_ROOT}/scripts/` | `.claude/scripts/` |
| `hooks/hooks.json` | `.claude/settings.json`의 `hooks` 키 |
| `install-rules.sh`로 규칙 배포 | 불필요 — `.claude/rules/`가 곧 정본 |
| `doctor --consumer` | 불필요 — 이 저장소가 곧 소비자 |

## 할 일

### 1. `.claude/scripts/lib/common.sh` — 훅 공유 기층

목적은 편의가 아니라 **침묵 실패의 제거**다. Phase 0의 3번에서 찾은 죽은 훅들의 원인
3가지를 각각 함수로 막는다.

아래 함수를 구현한다. 파일 머리에 `[ -n "${EPCC_COMMON_LOADED:-}" ] && return 0` 재진입
가드를 두고, `set -Eeuo pipefail` + ERR trap을 건다 (ERR trap은 stderr로 보고하고
하트비트에 exit 코드를 남긴 뒤 종료한다).

| 함수 | 계약 |
| --- | --- |
| `epcc_root <input>` | 우선순위 `CLAUDE_PROJECT_DIR` → stdin의 `.cwd`/`.workspace_dir` → `git rev-parse --show-toplevel`. **못 찾으면 추측하지 않고 exit 2로 차단한다.** `BASH_SOURCE`·`dirname ../..` 금지 |
| `epcc_num <v>` | 공백 제거 후 순수 정수만 통과. 비었거나 파싱 불가면 `0`. macOS `wc -l`의 선행 공백과 `\|\| echo 0`이 만드는 다중 행을 둘 다 흡수한다 |
| `epcc_count_lines <file>` | 파일 없으면 0. 내부적으로 `epcc_num` 경유 |
| `epcc_emit_context <event> <text>` | **이벤트별 지원 필드로 갈라 출력한다.** `SessionStart`/`UserPromptSubmit`/`UserPromptExpansion` → stdout 평문. `PreCompact`/`SessionEnd`/`Stop`/`SubagentStop`/`PostToolUse` → `{"additionalContext":…}`. `PreToolUse` → `{"hookSpecificOutput":{"hookEventName":…,"additionalContext":…}}`. 알 수 없는 이벤트는 stderr 보고 후 return 1 |
| `epcc_emit_block <event> <reason>` | `Stop`/`SubagentStop`만. **`decision`/`reason`이 아니라** `{"continue":false,"systemMessage":…}`. 다른 이벤트는 거부 |
| `epcc_emit_notice <event> <msg>` | **비차단 알림.** `{"systemMessage":…}`. 판정 불가·참고 사항을 보이되 진행은 막지 않는다 |
| `epcc_json_escape <s>` | jq 미설치 폴백 |
| `epcc_state_dir` | 계측·상태 파일이 놓이는 디렉토리. `${EPCC_STATE_DIR:-${EPCC_ROOT}/.claude/.epcc}`. **경로를 문자열로 조립하는 곳이 여기 하나뿐이어야 한다** (이유는 아래 E-09) |
| `epcc_heartbeat <code>` | `$(epcc_state_dir)/hookrun.log`에 `이름\|UTC타임스탬프\|루트\|exit코드` append. **2000행 초과 시 최근 1000행만 유지** |
| `epcc_edge <from> <to>` | `$(epcc_state_dir)/graph.log`에 엣지 traversal 기록 (Phase 5가 소비) |
| `epcc_begin <name> <input>` | `EPCC_HOOK_NAME` 설정 → `epcc_root` → export → `epcc_heartbeat 0` |
| `epcc_field <input> <jq경로>` | jq 없으면 빈 문자열 (**차단하지 않는다**) |

**`epcc_emit_notice`가 `epcc_emit_block`과 분리된 이유를 파일 주석에 남긴다**:
판정 불가를 차단으로 접으면 오탐이 되고, 오탐은 사용자가 훅을 끄게 만들며, 꺼진 훅의
차단력은 0이다.

`epcc_heartbeat`·`epcc_edge`는 `EPCC_ROOT`가 비면 조용히 return 0 한다 — 계측이
훅 본체를 죽이면 안 된다.

### 2. `.claude/scripts/doctor.sh` — 자기검증

```
doctor.sh --fast       구조 검사
doctor.sh --self-test  훅에 이벤트별 실제 stdin 픽스처 주입 → 효과 대조
doctor.sh              = --fast
  --root <dir>         검사 대상 루트 교체 (자기시험 전용)
종료 코드: 0 = 통과, 1 = 실패 항목 존재, 2 = 사용법/자산 오류
```

**`set -uo pipefail` — `-e`는 넣지 않는다.** 모든 검사를 끝까지 돌려 전체 보고서를 내는 것이
정책이고, `-e`와 ERR trap은 그 정책과 충돌한다. 그래서 이 스크립트는 `lib/common.sh`를
**source 하지 않는다** (훅만 source 한다).

출력 헬퍼는 아래를 쓴다. `bad`/`warn`은 `$2`가 비면 반환값이 1이 되므로 **`return 0`을 명시한다** —
이것을 빠뜨리면 `[ 조건 ] && warn … || ok …` 관용구에서 둘 다 실행된다(출처 저장소의 실제 결함 E-10).

```bash
FAIL=0; WARN=0; PASS=0
ok()   { PASS=$((PASS+1)); printf "  ✓ %s\n" "$1"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf "  ✗ %s\n" "$1"; [ -n "${2:-}" ] && printf "      %s\n" "$2"; return 0; }
warn() { WARN=$((WARN+1)); printf "  ! %s\n" "$1"; [ -n "${2:-}" ] && printf "      %s\n" "$2"; return 0; }
sec()  { printf "\n── %s ────────────────\n" "$1"; return 0; }
num()  { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }
```

그리고 **`&& warn … || ok …` 형태를 쓰지 않는다. `if/else`로 쓴다.**

#### `--fast` 검사 항목

| # | 절 | 무엇을 잡는가 |
| --- | --- | --- |
| 1 | 금지 관용구 | `\|\| echo 0` · `BASH_SOURCE` 상대 루트 계산 · **무가드 glob 파이프**(`ls -1t dir/*.md \| …` — 매치 0건이면 리터럴이 흐른다) · **HEAD 미검증 git**(`git log`/`rev-parse HEAD`를 `rev-parse -q --verify HEAD` 없이 — 첫 커밋 전 저장소에서 exit 128) · **BSD 미지원 BRE 교대**(`sed 's/a\|b/…/'` — GNU에서만 동작하고 macOS에서는 **실패하지 않고 조용히 아무것도 안 잡는다**) |
| 2 | 훅 출력 규격 | 훅 스크립트가 `decision`/`reason`을 `Stop`에 쓰는가 · 평문 `echo`로 `PreCompact`/`SessionEnd`에 출력하는가 |
| 3 | 훅 배선 | `settings.json`이 가리키는 파일이 실재하는가 · 실재하는 훅이 배선돼 있는가 (양방향) |
| 4 | 규칙 도달성 | 각 `.claude/rules/*.md`의 `paths:` 유무와 의도 일치 · **상시 카드(paths 없음)에 `paths`가 생기면 FAIL** · `epcc-rule-version` 스탬프 존재 · T0 40줄 예산 · 규칙이 참조하는 파일의 dangling |
| 5 | 에이전트 계약 | frontmatter에 `tools` 명시 · 리뷰어에 `Write`/`Edit`가 없는가 |
| 6 | 스킬 description 위생 | 트리거 어휘 중복 · 길이 상위 목록 · 본문이 못 지키는 약속(placeholder) |
| 7 | 스킬 내부 참조 | `SKILL.md`가 참조하는 `assets/`·`scripts/`·`references/` 파일의 실재 · **자작 치환 표기 검출** (`<skill-dir>`·`<Base directory>` 등 — 공식 변수는 `${CLAUDE_SKILL_DIR}`) |
| 8 | 선언↔실물 | 문서가 주장하는 **수치**(규칙 N개·노드 M개)와 실제 개수 대조 · 아무도 읽지 않는 고아 자산 |
| 9 | 플랫폼 계약 신선도 | `.claude/docs/platform-contract.md`의 `확인:` 날짜 180일 초과 경고 |

각 검사는 **실패했을 때 무엇을 하라는지**를 `bad`의 두 번째 인자로 준다. 조치 문구 없는
실패 보고는 무시를 학습시킨다.

#### `--self-test` 검사 항목

이것이 이 단계의 핵심이다. **훅에 실제 stdin을 주입하고 효과를 대조한다.**

`.claude/scripts/fixtures/`에 이벤트별 JSON을 둔다:
`SessionStart.json` · `Stop.json` · `PreCompact.json` · `SessionEnd.json` ·
`PreToolUse.json` · `PreToolUse-block.json` · `PostToolUse.json` ·
`UserPromptSubmit.json` · `default.json`

| # | 절 | 판정 |
| --- | --- | --- |
| 1 | 훅 픽스처 주입 | 훅마다 배선된 이벤트의 픽스처를 stdin으로 넣는다. **exit 0 또는 2가 아니면 FAIL. stderr 출력이 있으면 FAIL.** 출력이 있으면 그 이벤트가 지원하는 형태인지 대조 |
| 2 | 양성 픽스처 (차단 검증) | 결함을 심은 입력(`PreToolUse-block.json`에 하드코딩 시크릿)을 넣고 **exit 2와 차단 사유**를 받는지 확인 |
| 3 | **픽스처 유효성 확인** | ↓ 아래 별도 설명 |
| 4 | 정적 검사 양성 픽스처 | `--root`로 합성 트리를 만들어 `--fast`의 각 검사에 결함을 하나씩 심고 **특정 메시지가 나오는지**로 판정 |
| 5 | 루트 해석 | `CLAUDE_PROJECT_DIR` 없음 + stdin `.cwd` 없음 + git 아님 → **exit 2**인지 |

**3번(픽스처 유효성)을 반드시 넣는다.** 출처 저장소에서 차단 증명이 no-op이었던 적이 있다 —
존재하지 않는 파일명을 노려 결함 심기가 실패했는데 결과는 "통과"로 보였다. 작동하지 않는
검사를 작동한다고 보고할 뻔했다. 그래서 결함 주입 헬퍼는 **심은 뒤 그 결함이 실제로
파일에 있는지 grep으로 먼저 확인**하고, 없으면 `✗ 픽스처 무효`로 실패시킨다:

```bash
# $1 임시루트  $2 이름  $3 결함이 들어갈 파일(트리 상대)  $4 결함 표식(grep -E)  $5 기대 메시지  $6 심는 명령
inject_and_check() {
  local T="$1" name="$2" file="$3" marker="$4" expect="$5" cmd="$6"
  eval "$cmd"
  if ! grep -qE "$marker" "$T/$file" 2>/dev/null; then
    bad "$name: 픽스처 무효" "결함이 $file 에 심기지 않았다 — 이 검사는 아무것도 증명하지 않는다"
    return 0
  fi
  if bash "$0" --fast --root "$T" 2>&1 | grep -q "$expect"; then ok "$name: 검출"
  else bad "$name: 미검출" "기대 메시지: $expect"; fi
}
```

또한 `EPCC_FX_WHY=1` 환경변수를 주면 **어떤 사유로 검출됐는지**를 함께 출력한다.
결함이 의도한 이유가 아니라 우연히 다른 검사에 걸려도 "통과"로 보이기 때문이다.

#### 여기서 고쳐서 만드는 것 (출처의 결함 E-09)

출처의 `--self-test`는 픽스처를 주입할 때 `CLAUDE_PROJECT_DIR`을 저장소 자신으로 둔다.
그것 자체는 의도다 — **훅이 진짜 프로젝트를 보게 해야** 판정이 의미가 있다. 문제는
부수 효과였다: 하트비트·엣지 기록이 `.claude/.epcc/`에 쌓여 **실사용 기록과 섞였다.**
그 위에서 판정한 사용량 통계가 전부 doctor 자신의 픽스처 흔적이었다.
**계측기가 자기가 재는 데이터를 쓴 것이다.**

고치는 자리는 doctor가 아니라 `lib/common.sh`다. **기록 위치를 함수로 빼고 환경변수로
돌릴 수 있게 한다.** 그 변수가 존재하는 이유는 하나뿐이고, 그 이유를 주석에 적는다.

```bash
# ── 계측 기록 위치 ───────────────────────────────────────────────────
# 기본은 프로젝트의 `.claude/.epcc`다. `EPCC_STATE_DIR`로 돌릴 수 있는 이유는
# 하나뿐이다: **doctor --self-test가 자기가 재는 로그에 쓰면 안 된다.**
epcc_state_dir() {
  printf '%s' "${EPCC_STATE_DIR:-${EPCC_ROOT:-.}/.claude/.epcc}"
}
```

`epcc_heartbeat`·`epcc_edge`와 상태 파일을 쓰는 모든 훅(`build-gate`의 `session-baseline.txt`,
`track-skill`의 `skilluse.log`)이 **직접 경로를 조립하지 않고 이 함수를 거친다.**
그리고 self-test는 픽스처 주입 시 이 변수만 돌린다:

```bash
ISO=$(mktemp -d)
out=$(EPCC_STATE_DIR="$ISO" bash "$f" < "$fixture" 2>"$ISO/err"); code=$?
rm -rf "$ISO"
```

**`CLAUDE_PROJECT_DIR`은 그대로 둔다** — 훅은 여전히 진짜 프로젝트를 본다. 새는 것은
로그뿐이었으므로 로그만 격리한다.

doctor에 이 규약의 검사도 넣는다: 훅 스크립트가 `.claude/.epcc`를 **문자열로 직접
조립**하면 FAIL (`grep -n '\.claude/\.epcc' .claude/hooks/*.sh` → 0건이어야 한다).
검사가 없으면 다음에 추가되는 훅이 다시 직접 경로를 쓴다.

### 3. `.claude/scripts/` 배치 규약을 `CLAUDE.md`에 1줄 추가

> 훅은 `.claude/scripts/lib/common.sh`를 source한다. **검사 스크립트(doctor 계열)는 하지 않는다** —
> `set -Eeuo pipefail`과 ERR trap이 "모든 검사를 끝까지 돌린다"는 정책과 충돌한다.
> 대신 doctor의 `ok/bad/warn/sec` + `num()` + 종료 코드 규약을 **복사**하고 `return 0`을 명시한다.

## 하지 말 것

- **훅·규칙을 아직 고치지 않는다.** 이 단계는 자를 만드는 단계다. `--fast`가 기존 훅 11개에서
  실패를 잔뜩 뱉는 것이 **정상이고 그것이 산출물**이다. 그 목록을 Phase 2가 소비한다.
- 검사 항목을 늘려서 통과율을 올리지 않는다. 통과하지 못하는 항목은 그대로 두고 기록한다.
- `-e`를 doctor에 넣지 않는다. 첫 실패에서 멈추면 전체 보고서가 안 나온다.
- 검사 스크립트에서 `lib/common.sh`를 source 하지 않는다.

## 검증

```bash
bash .claude/scripts/doctor.sh --fast; echo "exit=$?"
bash .claude/scripts/doctor.sh --self-test; echo "exit=$?"
EPCC_FX_WHY=1 bash .claude/scripts/doctor.sh --self-test | grep -i '픽스처'
```

**차단을 증명한다** — 아래를 각각 실행해서 doctor가 실제로 잡는지 본다:

```bash
# ① 금지 관용구: 임시 훅에 || echo 0 을 심는다 → --fast가 검출해야 한다
# ② 훅 출력 규격: Stop 훅에 decision:block 을 심는다 → 검출
# ③ 규칙 도달성: 상시 카드에 paths: 를 붙인다 → FAIL
# ④ 루트 해석: env -i bash .claude/hooks/<훅>.sh </dev/null → exit 2
```

## 완료 기준 (DoD)

1. `.claude/scripts/lib/common.sh`의 12개 함수가 전부 구현돼 있고, `epcc_root`가 루트를
   못 찾으면 **exit 2로 차단**한다 (추측하지 않는다)
2. `doctor.sh --fast`가 9개 절을 돌고 exit 코드가 0 또는 1이다 (2가 아니다)
3. `doctor.sh --self-test`가 훅 전량에 픽스처를 주입하고, **`EPCC_STATE_DIR`로 로그를
   격리**한다 — 실행 전후로 `.claude/.epcc/hookrun.log`의 행 수가 변하지 않는다:
   ```bash
   before=$(wc -l < .claude/.epcc/hookrun.log 2>/dev/null || echo 0)
   bash .claude/scripts/doctor.sh --self-test >/dev/null
   after=$(wc -l < .claude/.epcc/hookrun.log 2>/dev/null || echo 0)
   [ "$before" = "$after" ] && echo "격리 OK" || echo "오염 — E-09 재현됨"
   ```
4. 결함 주입 4종이 각각 **의도한 메시지로** 검출된다. 픽스처를 무효화하면 `✗ 픽스처 무효`가 뜬다
5. 훅 스크립트가 `.claude/.epcc`를 문자열로 직접 조립하지 않는다:
   `grep -n '\.claude/\.epcc' .claude/hooks/*.sh` → **0건**
6. `doctor.sh` 안에 `&& warn … || ok …` 형태가 **0건**이다: `grep -n '&& warn.*|| ok' .claude/scripts/doctor.sh`
7. Phase 0에서 찾은 "조용히 무시되는 중"인 훅 목록이 `--fast` 출력으로도 재현된다

---

**다음**: `phase-2-hooks.md`
