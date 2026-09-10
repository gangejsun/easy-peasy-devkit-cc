#!/bin/bash
# scripts/lib/common.sh — epcc-devkit 훅 공유 기층
#
# 모든 훅이 이 파일을 source 한다. 목적은 편의가 아니라 **침묵 실패의 제거**다.
#
# v2에서 훅 8개가 4개월간 죽은 채 아무 신호도 내지 않았다. 원인 3가지:
#   1. 루트 경로를 BASH_SOURCE 상대로 계산 → 플러그인 배포 시 저장소 밖을 가리킴
#   2. `|| echo 0` 폴백이 1줄 자리에 2줄을 넣어 정수 비교를 붕괴시킴
#   3. 이벤트가 지원하지 않는 JSON 필드로 출력 → 조용히 무시됨
#
# 이 파일은 그 3가지를 각각 epcc_root / epcc_num / epcc_emit 으로 막는다.

# 이미 로드되었으면 재실행 안 함
[ -n "${EPCC_COMMON_LOADED:-}" ] && return 0
EPCC_COMMON_LOADED=1

set -Eeuo pipefail

# ── ERR trap: 실패를 조용히 넘기지 않는다 ────────────────────────────
# stderr로 내보내되 exit 코드는 훅별 정책을 따른다.
epcc_on_err() {
  local code=$? line=${1:-?}
  printf '[epcc:%s] ERROR line %s (exit %s)\n' "${EPCC_HOOK_NAME:-unknown}" "$line" "$code" >&2
  epcc_heartbeat "$code"
  exit "$code"
}
trap 'epcc_on_err $LINENO' ERR

# ── 프로젝트 루트 해석 ────────────────────────────────────────────────
# 우선순위: CLAUDE_PROJECT_DIR → stdin의 .cwd → git toplevel → 실패
# **추측하지 않는다.** 못 찾으면 exit 2로 차단한다 (안티골 1).
#
# 사용: EPCC_ROOT=$(epcc_root "$INPUT")
epcc_root() {
  local input="${1:-}" root=""

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR"; return 0
  fi

  if [ -n "$input" ] && command -v jq >/dev/null 2>&1; then
    root=$(printf '%s' "$input" | jq -r '.cwd // .workspace_dir // empty' 2>/dev/null || true)
    if [ -n "$root" ] && [ -d "$root" ]; then
      printf '%s' "$root"; return 0
    fi
  fi

  root=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$root" ] && [ -d "$root" ]; then
    printf '%s' "$root"; return 0
  fi

  printf '[epcc:%s] FATAL: 프로젝트 루트를 확정할 수 없습니다.\n' "${EPCC_HOOK_NAME:-unknown}" >&2
  printf '  시도: CLAUDE_PROJECT_DIR → stdin.cwd → git rev-parse --show-toplevel\n' >&2
  printf '  추측하지 않고 중단합니다. (안티골 1: 조용히 실패할 수 있는 가드 금지)\n' >&2
  exit 2
}

# ── 숫자 정규화 ──────────────────────────────────────────────────────
# macOS의 `wc -l`은 선행 공백을 붙이고, 파이프 실패 시 `|| echo 0`이
# 기존 출력에 덧붙어 "0\n0" 같은 다중 행을 만든다. 둘 다 정수 비교를 깬다.
# 항상 단일 정수를 보장한다. 비어있거나 파싱 불가면 0.
epcc_num() {
  local v="${1:-}"
  v=$(printf '%s' "$v" | tr -d '[:space:]' | head -c 18)
  case "$v" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "$v" ;;
  esac
}

# 파일 행 수를 안전하게 센다 (없으면 0)
epcc_count_lines() {
  [ -f "${1:-}" ] || { printf '0'; return 0; }
  epcc_num "$(wc -l < "$1" 2>/dev/null || printf '0')"
}

# ── 이벤트별 유효 JSON 출력 ──────────────────────────────────────────
# Claude Code는 이벤트마다 지원 필드가 다르다. 지원하지 않는 필드로 출력하면
# 조용히 무시된다 — v2의 stop-guard가 한 번도 차단하지 못한 이유.
#
#   SessionStart / UserPromptSubmit : stdout 평문이 그대로 컨텍스트가 됨
#   PreCompact / SessionEnd / Stop  : additionalContext (JSON) 필요
#   Stop                            : decision/reason 미지원. continue/systemMessage 사용
#   PreToolUse                      : hookSpecificOutput 지원
#
# 사용: epcc_emit_context <event> "<text>"
epcc_emit_context() {
  local event="${1:-}" text="${2:-}"
  [ -z "$text" ] && return 0

  case "$event" in
    SessionStart|UserPromptSubmit|UserPromptExpansion)
      # 이 세 이벤트만 stdout 평문이 컨텍스트로 들어간다
      printf '%s\n' "$text"
      ;;
    PreCompact|SessionEnd|Stop|SubagentStop|PostToolUse|PostToolBatch)
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg c "$text" '{additionalContext: $c}'
      else
        printf '{"additionalContext":%s}\n' "$(epcc_json_escape "$text")"
      fi
      ;;
    PreToolUse)
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg e "$event" --arg c "$text" \
          '{hookSpecificOutput:{hookEventName:$e, additionalContext:$c}}'
      fi
      ;;
    *)
      printf '[epcc] 알 수 없는 이벤트: %s\n' "$event" >&2
      return 1
      ;;
  esac
}

# Stop 계열 차단. decision/reason이 아니라 continue:false + systemMessage.
epcc_emit_block() {
  local event="${1:-}" reason="${2:-}"
  case "$event" in
    Stop|SubagentStop)
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg r "$reason" '{continue:false, systemMessage:$r}'
      else
        printf '{"continue":false,"systemMessage":%s}\n' "$(epcc_json_escape "$reason")"
      fi
      ;;
    *)
      printf '[epcc] %s 이벤트는 epcc_emit_block을 지원하지 않습니다\n' "$event" >&2
      return 1
      ;;
  esac
}

# Stop 계열 **비차단** 알림. 판정 불가·참고 사항을 사용자에게 보이되 진행은 막지 않는다.
# 차단(epcc_emit_block)과 분리한 이유: 판정 불가를 차단으로 접으면 오탐이 되고,
# 오탐은 훅을 끄게 만들어 차단력을 0으로 만든다.
epcc_emit_notice() {
  local event="${1:-}" msg="${2:-}"
  [ -z "$msg" ] && return 0
  case "$event" in
    Stop|SubagentStop|PostToolUse|PostToolBatch|PreCompact|SessionEnd)
      if command -v jq >/dev/null 2>&1; then
        jq -n --arg m "$msg" '{systemMessage:$m}'
      else
        printf '{"systemMessage":%s}\n' "$(epcc_json_escape "$msg")"
      fi
      ;;
    *)
      printf '[epcc] %s 이벤트는 epcc_emit_notice를 지원하지 않습니다\n' "$event" >&2
      return 1
      ;;
  esac
}

epcc_json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk 'BEGIN{printf "\""} {printf "%s%s", sep, $0; sep="\\n"} END{printf "\""}'
}

# ── 계측 기록 위치 ───────────────────────────────────────────────────
# 기본은 프로젝트의 `.claude/.epcc`다. `EPCC_STATE_DIR`로 돌릴 수 있는 이유는
# 하나뿐이다: **doctor --self-test가 자기가 재는 로그에 쓰면 안 된다.**
# 픽스처 주입은 훅이 진짜 프로젝트를 보게 하려고 CLAUDE_PROJECT_DIR을 저장소로
# 두는데(그것이 --consumer와 다른 점이다), 그 부수 효과로 하트비트·엣지 기록이
# 실사용 기록과 섞였다. 그러면 "어느 경로가 실제로 실행되는가"는 측정이 아니라
# 자기 주장이 된다 (평가 v3 · E-09).
epcc_state_dir() {
  printf '%s' "${EPCC_STATE_DIR:-${EPCC_ROOT:-.}/.claude/.epcc}"
}

# handoff 산출물 위치. `epcc_state_dir`과 같은 이유로 돌릴 수 있다 —
# --self-test가 PreCompact/SessionEnd 픽스처를 주입하면 handoff가 **실물**
# dev/handoff/에 쓰고, 회전(최근 10개 유지)이 실사용 복원 자료를 밀어냈다.
# 상태 로그만 격리하고 이쪽을 빠뜨려 수리가 절반만 갔다 (평가 v5 · E-13).
epcc_handoff_dir() {
  printf '%s' "${EPCC_HANDOFF_DIR:-${EPCC_ROOT:-.}/dev/handoff}"
}

# ── 워킹트리 스냅샷 ──────────────────────────────────────────────────
# session-brief가 세션 시작 시 만들고 build-gate가 Stop에서 대조한다.
#
# **파일 이름만 담으면 안 된다.** 이름 집합은 「더러운가」를 담고 「바뀌었는가」를
# 담지 못한다. 그래서 세션 시작 시 이미 미커밋이던 소스 파일은 아무리 고쳐도
# `comm -13`에서 빠져 빌드 게이트가 통째로 침묵했다 — 작업을 이어서 하는
# 가장 흔한 경로에서 게이트의 차단력이 0이었다.
#
# 줄 형식: `<경로><TAB><mtime><TAB><크기>`. 내용 해시가 더 정확하지만 파일당
# 프로세스를 하나씩 띄운다 — mtime+크기는 `stat` 한 번으로 끝나고 "고쳤는데
# 못 잡는" 경우가 실질적으로 없다.
#
# **두 훅이 각자 계산하지 않는다.** 이 버그가 난 이유가 생성기와 대조기가 같은
# 파이프라인의 사본 둘이었기 때문이다. 사본이 하나면 어긋날 자리가 없다.
#
# 삭제된 파일은 stat이 실패한다 — 빈 값 대신 `-`를 넣어 **줄을 남긴다.**
# 건너뛰면 "지웠다가 되살린" 경우가 무변경으로 보인다.
epcc_worktree_snapshot() {
  local f st
  git status --porcelain 2>/dev/null | sed -E 's/^.{3}//; s/^.* -> //' | sort -u   | while IFS= read -r f; do
      [ -z "$f" ] && continue
      if [ -e "$f" ]; then
        st=$(stat -f '%m	%z' "$f" 2>/dev/null || stat -c '%Y	%s' "$f" 2>/dev/null || printf -- '-	-')
      else
        st=$(printf -- '-	-')
      fi
      printf '%s	%s
' "$f" "$st"
    done
}

# 스냅샷 줄에서 경로만 꺼낸다 (TAB 이전). 경로에 공백이 있어도 안전하다.
epcc_snapshot_paths() { cut -f1; }

# ── 하트비트 ─────────────────────────────────────────────────────────
# 매 훅이 첫 동작으로 자기 실행을 기록한다. 다른 컴포넌트(session-brief)가
# 이 로그를 읽어 죽은 훅을 보고한다. 컴포넌트는 자기를 보증하지 않는다 (P1).
epcc_heartbeat() {
  local code="${1:-0}" dir
  [ -z "${EPCC_ROOT:-}" ] && return 0
  dir="$(epcc_state_dir)"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s|%s|%s|%s\n' \
    "${EPCC_HOOK_NAME:-unknown}" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${EPCC_ROOT}" \
    "$code" >> "$dir/hookrun.log" 2>/dev/null || true

  # 로테이션: 2000행 초과 시 최근 1000행 유지 (무한 축적 방지).
  #
  # **불변식: 회전은 어떤 컴포넌트의 마지막 증거도 지우지 않는다.**
  # 단순 tail은 이 로그를 거짓말하게 만든다 — security-check는 Edit/Write/MultiEdit/Bash
  # 전부에 걸려 행의 97%를 차지하고, 다른 훅의 이력을 창 밖으로 밀어낸다. 그러면
  # session-brief가 **실제로 돈 훅을 "실행된 적 없음"으로 보고한다** (track-skill 실측:
  # skilluse.log에 7행이 남아 있는데 hookrun.log에서는 증발했다). 지표가 재던 것은
  # "돈 적 있는가"가 아니라 "회전에서 살아남을 만큼 최근에 돌았는가"였다.
  #
  # 창 밖으로 밀리는 이름만 골라 그 마지막 행 하나를 함께 남긴다. 전역 dedup을 쓰지 않는
  # 이유는 같은 훅이 같은 초에 두 번 도는 것이 정상이고, 그것을 지우면 행 수가 왜곡되기
  # 때문이다. 비용은 회전 시점(2000행마다 한 번)에만 들고 훅 호출마다 드는 비용은 0이다.
  local n; n=$(epcc_count_lines "$dir/hookrun.log")
  if [ "$n" -gt 2000 ]; then
    awk -F'|' -v keep=1000 '
      # NF>=4 이고 이름이 비지 않은 행만 carry 후보로 본다 — 부분 쓰기로 생긴 오염 행이
      # 매 회전마다 마지막 증거로 영구 carry 되는 것을 막는다 (정상 writer는 4필드를 쓴다).
      # 주의: 이 awk 프로그램은 셸 작은따옴표 안이다. 주석에도 작은따옴표를 쓰지 않는다.
      { rows[NR] = $0; if (NF >= 4 && $1 != "") last[$1] = NR }
      END {
        start = NR - keep + 1; if (start < 1) start = 1
        for (k in last) if (last[k] < start) print rows[last[k]]
        for (i = start; i <= NR; i++) print rows[i]
      }
    ' "$dir/hookrun.log" > "$dir/hookrun.log.tmp" 2>/dev/null \
      && mv "$dir/hookrun.log.tmp" "$dir/hookrun.log" 2>/dev/null || true
  fi
}

# ── 그래프 엣지 계측 ─────────────────────────────────────────────────
# 어느 경로가 실제로 실행되는지 측정 가능하게 한다 (Graph Engineering G2).
epcc_edge() {
  local from="${1:-}" to="${2:-}" dir
  [ -z "${EPCC_ROOT:-}" ] && return 0
  dir="$(epcc_state_dir)"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s|%s|%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$from" "$to" \
    >> "$dir/graph.log" 2>/dev/null || true
  # 회전 — 이 로그만 상한이 없었다(평가 v6 · E-28). 가장 많이 쓰는 기록자(security-check가 도구
  # 호출마다 방출)인데 형제 로그 둘은 회전하고 이것만 무한 축적했다. append에는 상한이 따른다
  # (code-change 「append하는 코드를 쓰면 로테이션/상한을 같이 넣는다」 — 하네스도 예외가 아니다).
  local n; n=$(epcc_num "$(wc -l < "$dir/graph.log" 2>/dev/null)")
  if [ "$n" -gt 5000 ]; then
    tail -2500 "$dir/graph.log" > "$dir/graph.log.tmp" 2>/dev/null \
      && mv "$dir/graph.log.tmp" "$dir/graph.log" 2>/dev/null || rm -f "$dir/graph.log.tmp"
  fi
}

# ── 훅 초기화 ────────────────────────────────────────────────────────
# 사용:
#   INPUT=$(cat 2>/dev/null || echo '{}')
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#   epcc_begin "session-brief" "$INPUT"
epcc_begin() {
  EPCC_HOOK_NAME="${1:-unknown}"
  local input="${2:-}"
  EPCC_ROOT=$(epcc_root "$input")
  export EPCC_HOOK_NAME EPCC_ROOT
  epcc_heartbeat 0
}

# stdin JSON에서 필드 추출 (jq 없으면 빈 문자열)
epcc_field() {
  local input="${1:-}" path="${2:-}"
  command -v jq >/dev/null 2>&1 || { printf ''; return 0; }
  printf '%s' "$input" | jq -r "$path // empty" 2>/dev/null || printf ''
}
