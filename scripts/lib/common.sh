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

epcc_json_escape() {
  printf '%s' "${1:-}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | awk 'BEGIN{printf "\""} {printf "%s%s", sep, $0; sep="\\n"} END{printf "\""}'
}

# ── 하트비트 ─────────────────────────────────────────────────────────
# 매 훅이 첫 동작으로 자기 실행을 기록한다. 다른 컴포넌트(session-brief)가
# 이 로그를 읽어 죽은 훅을 보고한다. 컴포넌트는 자기를 보증하지 않는다 (P1).
epcc_heartbeat() {
  local code="${1:-0}" dir
  [ -z "${EPCC_ROOT:-}" ] && return 0
  dir="$EPCC_ROOT/.claude/.epcc"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s|%s|%s|%s\n' \
    "${EPCC_HOOK_NAME:-unknown}" \
    "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
    "${EPCC_ROOT}" \
    "$code" >> "$dir/hookrun.log" 2>/dev/null || true

  # 로테이션: 2000행 초과 시 최근 1000행만 유지 (무한 축적 방지)
  local n; n=$(epcc_count_lines "$dir/hookrun.log")
  if [ "$n" -gt 2000 ]; then
    tail -1000 "$dir/hookrun.log" > "$dir/hookrun.log.tmp" 2>/dev/null \
      && mv "$dir/hookrun.log.tmp" "$dir/hookrun.log" 2>/dev/null || true
  fi
}

# ── 그래프 엣지 계측 ─────────────────────────────────────────────────
# 어느 경로가 실제로 실행되는지 측정 가능하게 한다 (Graph Engineering G2).
epcc_edge() {
  local from="${1:-}" to="${2:-}" dir
  [ -z "${EPCC_ROOT:-}" ] && return 0
  dir="$EPCC_ROOT/.claude/.epcc"
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s|%s|%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$from" "$to" \
    >> "$dir/graph.log" 2>/dev/null || true
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
