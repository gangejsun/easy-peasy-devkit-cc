#!/bin/bash
# scripts/track-skill.sh — PostToolUse (Skill)
#
# 스킬 호출을 기록한다. 이것이 없으면 "미사용 스킬 컬링"은 영원히 추측으로만
# 가능하다 — v2 감사가 "출력 디렉토리가 비었다"를 사용 증거로 삼아야 했던 이유다.
#
# 안티골 8: 측정 없이 컬링하지 않는다.
#
# v2의 PostToolUse 추적기 3종과 다른 점:
#   - 매 도구 호출이 아니라 Skill 호출에만 반응
#   - /tmp 전체 스캔 없음 (그 훅들이 매 호출마다 하던 짓)
#   - 소비자가 실재한다 (doctor --usage)

INPUT=$(cat 2>/dev/null || printf '{}')
# shellcheck source=lib/common.sh
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/lib/common.sh"

EPCC_HOOK_NAME="track-skill"
EPCC_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || printf '')}"
[ -z "$EPCC_ROOT" ] && exit 0

SKILL=$(epcc_field "$INPUT" '.tool_input.skill')
[ -z "$SKILL" ] && exit 0

DIR="$(epcc_state_dir)"
mkdir -p "$DIR" 2>/dev/null || exit 0
printf '%s|%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$SKILL" >> "$DIR/skilluse.log" 2>/dev/null || true
epcc_edge "build" "track-skill"   # 그래프가 instrumented:true로 선언한 엣지 — 방출 없으면 '미실행' 경고가 영구 잔존

# 로테이션 (무한 축적 방지)
N=$(epcc_count_lines "$DIR/skilluse.log")
if [ "$N" -gt 5000 ]; then
  tail -2500 "$DIR/skilluse.log" > "$DIR/skilluse.log.tmp" 2>/dev/null \
    && mv "$DIR/skilluse.log.tmp" "$DIR/skilluse.log" 2>/dev/null || true
fi

epcc_heartbeat 0
exit 0
