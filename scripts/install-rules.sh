#!/bin/bash
# scripts/install-rules.sh — T1 규칙 카드를 프로젝트에 설치
#
# §1.3의 실질 수정. v2에서는 플러그인의 rules/ 697줄이 프로젝트에 도달할 경로가
# 아예 없었다 (플러그인 매니페스트에 'rules' 컴포넌트 타입이 존재하지 않고,
# epcc-init에도 복사 단계가 없었다). CLAUDE.md는 있다고 선언했지만 없었다.
#
# 사용:
#   install-rules.sh [--dry-run] [--force]
#
# 멱등하다. 이미 설치된 파일은 버전 스탬프를 비교해 결정한다:
#   - 동일 버전  → 건너뜀
#   - 구버전     → 갱신 (사용자 수정본은 .bak 백업)
#   - 사용자 수정 감지 + 버전 동일 → 건너뜀 (프로젝트 소유권 존중)

set -Eeuo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SRC="$PLUGIN_ROOT/rules"
DST="$PROJECT_ROOT/.claude/rules"

DRY=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --dry-run) DRY=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) sed -n '2,20p' "$0" | sed 's/^# \?//'; exit 0 ;;
  esac
done

[ -d "$SRC" ] || { printf 'FATAL: 플러그인 rules/ 없음: %s\n' "$SRC" >&2; exit 2; }

version_of() { grep -m1 -oE 'epcc-rule-version: [0-9]+\.[0-9]+\.[0-9]+' "$1" 2>/dev/null | awk '{print $2}'; }

printf 'T1 규칙 설치\n  플러그인: %s\n  프로젝트: %s\n\n' "$SRC" "$DST"

[ "$DRY" -eq 0 ] && mkdir -p "$DST"

installed=0; skipped=0; updated=0
for f in "$SRC"/*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  target="$DST/$base"
  sv=$(version_of "$f"); sv="${sv:-0.0.0}"

  if [ ! -f "$target" ]; then
    printf '  + %-24s (v%s) 신규\n' "$base" "$sv"
    [ "$DRY" -eq 0 ] && cp "$f" "$target"
    installed=$((installed+1))
    continue
  fi

  tv=$(version_of "$target"); tv="${tv:-0.0.0}"
  if [ "$sv" = "$tv" ] && [ "$FORCE" -eq 0 ]; then
    printf '  = %-24s (v%s) 동일 — 건너뜀\n' "$base" "$tv"
    skipped=$((skipped+1))
    continue
  fi

  # 사용자가 수정했는지 확인 (내용 차이 + 버전 동일 → 프로젝트 소유)
  if [ "$sv" = "$tv" ] && ! cmp -s "$f" "$target"; then
    printf '  = %-24s 사용자 수정본 — 보존\n' "$base"
    skipped=$((skipped+1))
    continue
  fi

  printf '  ↑ %-24s v%s → v%s (백업: %s.bak)\n' "$base" "$tv" "$sv" "$base"
  if [ "$DRY" -eq 0 ]; then
    cp "$target" "$target.bak"
    cp "$f" "$target"
  fi
  updated=$((updated+1))
done

printf '\n  신규 %d · 갱신 %d · 유지 %d\n' "$installed" "$updated" "$skipped"

# 설치 검증 — "복사했다"는 "존재한다"가 아니다
if [ "$DRY" -eq 0 ]; then
  n=$(ls -1 "$DST"/*.md 2>/dev/null | wc -l | tr -d ' ')
  if [ "${n:-0}" -eq 0 ]; then
    printf '\nFATAL: 설치 후에도 %s에 규칙이 없습니다.\n' "$DST" >&2
    exit 1
  fi
  printf '  검증: %s에 %s개 규칙 존재 ✓\n' "${DST#$PROJECT_ROOT/}" "$n"
fi
