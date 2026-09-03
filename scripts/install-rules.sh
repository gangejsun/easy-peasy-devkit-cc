#!/bin/bash
# scripts/install-rules.sh — T1 규칙 카드를 프로젝트에 설치
#
# §1.3의 실질 수정. v2에서는 플러그인의 rules/ 697줄이 프로젝트에 도달할 경로가
# 아예 없었다 (플러그인 매니페스트에 'rules' 컴포넌트 타입이 존재하지 않고,
# epcc-init에도 복사 단계가 없었다). CLAUDE.md는 있다고 선언했지만 없었다.
#
# 사용:
#   install-rules.sh [--dry-run] [--force] [--missing-only] [--quiet]
#
# 멱등하다. 이미 설치된 파일은 버전 스탬프를 비교해 결정한다:
#   - 동일 버전  → 건너뜀
#   - 구버전     → 갱신 (사용자 수정본은 .bak 백업)
#   - 사용자 수정 감지 + 버전 동일 → 건너뜀 (프로젝트 소유권 존중)
#
#   --missing-only  이미 있는 파일은 **버전을 보지 않고** 건드리지 않는다. 없는 것만 깐다.
#                   session-brief 훅이 자동 실행할 때 쓰는 모드다 — 자동 실행이 사용자
#                   수정본을 조용히 덮어쓰면 안 되므로, 갱신은 사람이 인자 없이 부를 때만 한다.
#   --quiet         변경이 없으면 아무것도 출력하지 않는다 (훅에서 매 세션 도는 용도)

set -Eeuo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SRC="$PLUGIN_ROOT/rules"
DST="$PROJECT_ROOT/.claude/rules"
# 카드가 링크로 가리키는 점진 로드용 참조. 카드 본문에서 `../references/<주제>/`로 참조하며,
# **`.claude/rules/` 안에 두면 안 된다** — 거기의 .md는 paths가 없으면 매 세션 상주하므로
# "필요할 때만 읽는다"가 성립하지 않는다.
REFSRC="$PLUGIN_ROOT/references"
REFDST="$PROJECT_ROOT/.claude/references"

DRY=0; FORCE=0; MISSING_ONLY=0; QUIET=0
for a in "$@"; do
  case "$a" in
    --dry-run)      DRY=1 ;;
    --force)        FORCE=1 ;;
    --missing-only) MISSING_ONLY=1 ;;
    --quiet)        QUIET=1 ;;
    -h|--help) sed -n '2,26p' "$0" | sed 's/^# \?//'; exit 0 ;;
  esac
done
say() { [ "$QUIET" -eq 1 ] || printf "$@"; }

[ -d "$SRC" ] || { printf 'FATAL: 플러그인 rules/ 없음: %s\n' "$SRC" >&2; exit 2; }

version_of() { grep -m1 -oE 'epcc-rule-version: [0-9]+\.[0-9]+\.[0-9]+' "$1" 2>/dev/null | awk '{print $2}'; }

say 'T1 규칙 설치\n  플러그인: %s\n  프로젝트: %s\n\n' "$SRC" "$DST"

[ "$DRY" -eq 0 ] && mkdir -p "$DST"

installed=0; skipped=0; updated=0
for f in "$SRC"/*.md; do
  [ -f "$f" ] || continue
  base=$(basename "$f")
  target="$DST/$base"
  sv=$(version_of "$f"); sv="${sv:-0.0.0}"

  if [ ! -f "$target" ]; then
    say '  + %-24s (v%s) 신규\n' "$base" "$sv"
    [ "$DRY" -eq 0 ] && cp "$f" "$target"
    installed=$((installed+1))
    continue
  fi

  # --missing-only: 이미 있으면 버전을 보지 않는다. 자동 실행이 덮어쓰지 않게 하는 경계다.
  if [ "$MISSING_ONLY" -eq 1 ]; then
    skipped=$((skipped+1)); continue
  fi

  tv=$(version_of "$target"); tv="${tv:-0.0.0}"
  if [ "$sv" = "$tv" ] && [ "$FORCE" -eq 0 ]; then
    say '  = %-24s (v%s) 동일 — 건너뜀\n' "$base" "$tv"
    skipped=$((skipped+1))
    continue
  fi

  # 사용자가 수정했는지 확인 (내용 차이 + 버전 동일 → 프로젝트 소유)
  if [ "$sv" = "$tv" ] && ! cmp -s "$f" "$target"; then
    say '  = %-24s 사용자 수정본 — 보존\n' "$base"
    skipped=$((skipped+1))
    continue
  fi

  say '  ↑ %-24s v%s → v%s (백업: %s.bak)\n' "$base" "$tv" "$sv" "$base"
  if [ "$DRY" -eq 0 ]; then
    cp "$target" "$target.bak"
    cp "$f" "$target"
  fi
  updated=$((updated+1))
done

# --quiet 이어도 실제로 무언가 설치·갱신했으면 알린다 — 조용한 변경은 없다
if [ "$QUIET" -eq 1 ] && [ $((installed+updated)) -gt 0 ]; then
  printf 'T1 규칙 카드 %d장 자동 설치 (%s)\n' "$((installed+updated))" "${DST#$PROJECT_ROOT/}"
fi
say '\n  신규 %d · 갱신 %d · 유지 %d\n' "$installed" "$updated" "$skipped"

# 카드가 링크한 참조 자산 — 카드와 같은 판정 규칙(버전 스탬프)을 쓴다
refn=0
if [ -d "$REFSRC" ]; then
  while IFS= read -r rf; do
    rel="${rf#$REFSRC/}"
    rt="$REFDST/$rel"
    if [ ! -f "$rt" ]; then
      [ "$DRY" -eq 0 ] && { mkdir -p "$(dirname "$rt")"; cp "$rf" "$rt"; }
      refn=$((refn+1)); continue
    fi
    [ "$MISSING_ONLY" -eq 1 ] && continue
    rsv=$(version_of "$rf"); rsv="${rsv:-0.0.0}"
    rtv=$(version_of "$rt"); rtv="${rtv:-0.0.0}"
    if [ "$rsv" != "$rtv" ] || [ "$FORCE" -eq 1 ]; then
      if [ "$DRY" -eq 0 ]; then
        cmp -s "$rf" "$rt" || cp "$rt" "$rt.bak"
        cp "$rf" "$rt"
      fi
      refn=$((refn+1))
    fi
  done < <(find "$REFSRC" -name '*.md' -type f 2>/dev/null)
  [ "$refn" -gt 0 ] && say '  + 참조 자산 %d개 (%s)\n' "$refn" "${REFDST#$PROJECT_ROOT/}"
fi

# 설치 검증 — "복사했다"는 "존재한다"가 아니다
if [ "$DRY" -eq 0 ]; then
  # 무매칭 시 ls exit 1 → pipefail+ERR 트랩이 여기서 죽어 아래 FATAL을 못 낸다.
  # 즉 "0장"을 알리려던 코드가 하필 0장일 때 침묵한다.
  n=$({ ls -1 "$DST"/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')
  if [ "${n:-0}" -eq 0 ]; then
    printf '\nFATAL: 설치 후에도 %s에 규칙이 없습니다.\n' "$DST" >&2
    exit 1
  fi
  say '  검증: %s에 %s개 규칙 존재 ✓\n' "${DST#$PROJECT_ROOT/}" "$n"

  # 카드가 가리키는 참조가 실제로 도달했는가. 링크만 있고 파일이 없으면
  # 모델은 "읽을 수 없는 파일"을 안내받고 점진 로드가 조용히 끊긴다.
  dang=0
  for c in "$DST"/*.md; do
    [ -f "$c" ] || continue
    while IFS= read -r lnk; do
      [ -z "$lnk" ] && continue
      [ -f "$DST/$lnk" ] || { printf 'WARN: %s → %s 미설치\n' "$(basename "$c")" "$lnk" >&2; dang=$((dang+1)); }
    done < <(grep -ohE '\.\./references/[A-Za-z0-9._/-]+\.md' "$c" 2>/dev/null | sort -u)
  done
  [ "$dang" -eq 0 ] && say '  검증: 카드→참조 링크 전부 도달 ✓\n'
fi
