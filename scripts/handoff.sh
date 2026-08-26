#!/bin/bash
# scripts/handoff.sh — PreCompact + SessionEnd
#
# 컨텍스트가 압축되거나 세션이 끝날 때 작업 상태를 보존한다.
#
# v2의 pre-compact-saver는 평문 echo로 출력했는데, PreCompact stdout은
# 컨텍스트에 들어가지 않는다 (SessionStart / UserPromptSubmit /
# UserPromptExpansion 세 이벤트만 평문이 컨텍스트가 된다).
# 즉 4개월간 아무것도 보존하지 않았고, 그래서 사용자가 수동으로
# SESSION-HANDOFF 파일을 7개나 만들어야 했다.
#
# v3는 additionalContext JSON으로 출력하고, SessionEnd에서는 파일로도 남긴다.

INPUT=$(cat 2>/dev/null || printf '{}')
# shellcheck source=lib/common.sh
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/lib/common.sh"
epcc_begin "handoff" "$INPUT"

cd "$EPCC_ROOT" 2>/dev/null || exit 0

EVENT=$(epcc_field "$INPUT" '.hook_event_name'); EVENT="${EVENT:-PreCompact}"

OUT=""
add() { OUT="${OUT}$1"$'\n'; }

# ── git 상태 ─────────────────────────────────────────────────────────
if git rev-parse --git-dir >/dev/null 2>&1; then
  # 커밋 0개(git init 직후) 저장소: git log·rev-parse HEAD가 exit 128 →
  # pipefail+ERR 트랩이 훅을 통째로 죽여 인계가 **전부** 사라진다.
  # 신규 프로젝트의 첫 세션이 정확히 이 상태다 (session-brief가 이미 같은 함정을 막아두었다).
  if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    HEADL=$(git log -1 --format='%h %s' 2>/dev/null | cut -c1-64)
  else
    BRANCH=$(git branch --show-current 2>/dev/null)
    HEADL="없음 (첫 커밋 전)"
  fi
  add "## 작업 상태 보존"
  add ""
  add "- 브랜치 \`${BRANCH:-?}\` · HEAD \`${HEADL:-없음}\`"

  MODIFIED=$(git status --porcelain 2>/dev/null | head -12)
  if [ -n "$MODIFIED" ]; then
    N=$(epcc_num "$(git status --porcelain 2>/dev/null | wc -l)")
    add "- 미커밋 ${N}개:"
    while IFS= read -r l; do [ -n "$l" ] && add "  - \`${l}\`"; done <<< "$MODIFIED"
  fi
fi

# ── 열린 워크스페이스 ────────────────────────────────────────────────
if [ -d "$EPCC_ROOT/dev/active" ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    NAME=$(basename "$d")
    add ""
    add "### 진행 중: ${NAME}"
    TF=$(find "$d" -name '*task*' -type f 2>/dev/null | head -1)
    if [ -n "$TF" ] && [ -f "$TF" ]; then
      DONE=$(epcc_num "$(grep -c '^\s*- \[x\]' "$TF" 2>/dev/null)")
      TODO=$(epcc_num "$(grep -c '^\s*- \[ \]' "$TF" 2>/dev/null)")
      add "- 진행률 ${DONE}/$((DONE+TODO))"
      if [ "$TODO" -gt 0 ]; then
        add "- 남은 작업:"
        grep '^\s*- \[ \]' "$TF" 2>/dev/null | head -5 | sed 's/^\s*- \[ \]/  -/' | while IFS= read -r t; do
          printf '%s\n' "$t"
        done | while IFS= read -r t; do add "$t"; done
      fi
      add "- 파일: \`${TF#$EPCC_ROOT/}\`"
    fi
  done < <(find "$EPCC_ROOT/dev/active" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -3)
fi

[ -z "$OUT" ] && exit 0
add ""
add "> 위 파일들을 참조하여 작업을 이어서 진행하세요."

# ── SessionEnd면 파일로도 남긴다 ─────────────────────────────────────
if [ "$EVENT" = "SessionEnd" ]; then
  HD="$(epcc_handoff_dir)"
  if mkdir -p "$HD" 2>/dev/null; then
    TS=$(date -u '+%Y%m%d-%H%M%S')
    printf '%s\n' "$OUT" > "$HD/${TS}.md" 2>/dev/null || true
    # 최근 10개만 유지 (무한 축적 방지)
    { ls -1t "$HD"/*.md 2>/dev/null || true; } | tail -n +11 | while IFS= read -r old; do rm -f "$old"; done
  fi
fi

epcc_edge "build" "handoff"
epcc_emit_context "$EVENT" "$OUT"
exit 0
