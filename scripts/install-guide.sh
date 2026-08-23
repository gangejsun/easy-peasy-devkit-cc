#!/bin/bash
# scripts/install-guide.sh — 축 팩 + 이음매를 조립해 프로젝트 가이드 스킬로 설치
#
# 사전 제작 단위가 "조합"에서 "축"으로 내려간 뒤의 배송 경로다. 조합은 32가지이지만
# 축은 12가지(프론트 4 · 백엔드 8)이고, 조합에 진짜 의존하는 부분만 이음매로 남는다.
#
# 사용:
#   install-guide.sh --frontend <팩|none> --backend <팩|none> [--seam <조합>]
#                    [--dry-run] [--force]
#
#   --frontend react-vite     guides/frontend/react-vite 를 쓴다
#   --backend  supabase       guides/backend/supabase 를 쓴다
#   --seam     nextjs+supabase  사전 제작 이음매를 함께 설치한다 (없으면 팩만)
#
# 소유권이 나뉜다 (install-rules.sh의 T1 카드 ↔ 프로젝트 카드와 같은 구조):
#   팩 파일   → 플러그인 소유. epcc-pack 스탬프로 갱신을 판정한다
#   이음매    → 사전 제작이면 플러그인 소유, 생성물이면 프로젝트 소유(건드리지 않는다)
#
# 멱등하다. 스탬프 동일 → 건너뜀 / 구버전 → .bak 후 갱신 / 스탬프 동일 + 내용 상이
# → 사용자 수정본으로 보고 보존.
#
# 종료 코드: 0 = 성공, 1 = 설치 후 검증 실패, 2 = 사용법·자산 오류

set -Eeuo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
G="$PLUGIN_ROOT/guides"

FE=""; BE=""; SEAM=""; DRY=0; FORCE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --frontend) FE="${2:-}"; shift 2 ;;
    --backend)  BE="${2:-}"; shift 2 ;;
    --seam)     SEAM="${2:-}"; shift 2 ;;
    --dry-run)  DRY=1; shift ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  sed -n '2,25p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) printf 'FATAL: 알 수 없는 인자: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -d "$G" ] || { printf 'FATAL: guides/ 없음: %s\n' "$G" >&2; exit 2; }
[ -n "$FE" ] || [ -n "$BE" ] || { printf 'FATAL: --frontend 또는 --backend 중 하나는 필요합니다\n' >&2; exit 2; }

stamp_of() { grep -m1 -oE 'epcc-(pack|seam): [^ ]+ v[0-9]+\.[0-9]+\.[0-9]+' "$1" 2>/dev/null | awk '{print $3}' || true; }
TODAY=$(date +%Y-%m-%d)
installed=0; updated=0; skipped=0

# ── 파일 1개를 멱등 복사 ───────────────────────────────────────────
put() { # $1=원본 $2=대상
  local src="$1" dst="$2" base sv tv
  base=$(basename "$dst")
  sv=$(stamp_of "$src"); sv="${sv:-none}"
  if [ ! -f "$dst" ]; then
    printf '    + %-30s %s\n' "$base" "$sv"
    [ "$DRY" -eq 0 ] && cp "$src" "$dst"
    installed=$((installed+1)); return 0
  fi
  tv=$(stamp_of "$dst"); tv="${tv:-none}"
  if [ "$sv" = "$tv" ] && [ "$FORCE" -eq 0 ]; then
    if cmp -s "$src" "$dst"; then
      printf '    = %-30s 동일 — 건너뜀\n' "$base"
    else
      printf '    = %-30s 사용자 수정본 — 보존\n' "$base"
    fi
    skipped=$((skipped+1)); return 0
  fi
  printf '    ↑ %-30s %s → %s (백업)\n' "$base" "$tv" "$sv"
  if [ "$DRY" -eq 0 ]; then cp "$dst" "$dst.bak"; cp "$src" "$dst"; fi
  updated=$((updated+1)); return 0
}

# ── 허브 설치: [Preset:] 게이팅을 벗기고 name을 디렉토리에 맞춘다 ──
# 프로젝트에 설치되는 가이드는 그 프로젝트 전용이므로 프리셋 게이팅이 불필요하고,
# 남겨두면 "Use ONLY when the active preset matches"가 자기 프로젝트에서 오작동한다.
put_hub() { # $1=HUB.md $2=대상 SKILL.md $3=스킬명 $4=스탬프본문
  local src="$1" dst="$2" name="$3" info="$4"
  if [ -f "$dst" ] && [ "$FORCE" -eq 0 ] && grep -q 'epcc-guide: assembled' "$dst" 2>/dev/null; then
    printf '    = %-30s 기존 조립본 — 보존\n' "$(basename "$dst")"
    skipped=$((skipped+1)); return 0
  fi
  printf '    + %-30s (게이팅 제거 · name=%s)\n' "$(basename "$dst")" "$name"
  [ "$DRY" -eq 1 ] && { installed=$((installed+1)); return 0; }
  awk -v nm="$name" -v info="$info" '
    NR==1 && $0=="---" { print; inFm=1; next }
    inFm && /^name:/    { print "name: " nm; next }
    inFm && /^description:/ {
      line=$0
      gsub(/\[Preset:[^]]*\] */, "", line)
      gsub(/ *Use ONLY when the active preset matches\./, "", line)
      print line; next }
    inFm && $0=="---"   { print; inFm=0; print info; next }
    /^<!-- epcc-guide-baseline:/ { next }
    { print }
  ' "$src" > "$dst"
  installed=$((installed+1)); return 0
}

# ── 한 축을 조립 ───────────────────────────────────────────────────
assemble() { # $1=frontend|backend  $2=팩이름
  local axis="$1" pack="$2"
  local packdir="$G/$axis/$pack"
  local dst="$PROJECT_ROOT/.claude/skills/$axis-guide"
  local seamdir=""
  [ -n "$SEAM" ] && [ -d "$G/seams/$SEAM/$axis" ] && seamdir="$G/seams/$SEAM/$axis"

  [ -d "$packdir" ] || { printf 'FATAL: 팩 없음: %s\n' "$packdir" >&2; exit 2; }

  printf '  [%s-guide]  팩 %s%s\n' "$axis" "$pack" "${seamdir:+ + 사전 제작 이음매 $SEAM}"
  [ "$DRY" -eq 0 ] && mkdir -p "$dst/resources"

  local pv; pv=$(grep -m1 -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$packdir/PACK.md" 2>/dev/null || echo v0.0.0)
  local pkgs; pkgs=$(grep -m1 -oE 'pkgs=.*-->' "$packdir/PACK.md" 2>/dev/null | sed 's/ -->//' || true)
  [ -z "$pkgs" ] && pkgs=$(python3 -c "
import json,sys
try: print('pkgs=' + ' '.join(json.load(open('$packdir/pack.json'))['pkgs']))
except Exception: print('')" 2>/dev/null)

  local SEAMLABEL; if [ -n "$seamdir" ]; then SEAMLABEL="prebuilt/$SEAM"; else SEAMLABEL="generated"; fi
  local info="<!-- epcc-guide: assembled $TODAY combo=${FE:-none}+${BE:-none} packs=$axis/$pack@${pv#v} seam=$SEAMLABEL $pkgs -->"

  for f in "$packdir/resources"/*.md; do [ -f "$f" ] && put "$f" "$dst/resources/$(basename "$f")"; done
  if [ -n "$seamdir" ]; then
    for f in "$seamdir/resources"/*.md; do [ -f "$f" ] && put "$f" "$dst/resources/$(basename "$f")"; done
    put_hub "$seamdir/HUB.md" "$dst/SKILL.md" "$axis-guide" "$info"
  else
    printf '    ! SKILL.md 미생성 — 이음매가 없습니다. stack-guide-generator가 허브와 이음매를 만듭니다\n'
  fi

  # 조립 원장 — 무엇이 어디서 왔는지. 게이트가 팩 소유 파일을 식별하는 근거
  if [ "$DRY" -eq 0 ]; then
    { printf '{\n  "axis": "%s",\n  "pack": "%s/%s",\n  "packVersion": "%s",\n' "$axis" "$axis" "$pack" "${pv#v}"
      printf '  "seam": %s,\n  "assembledAt": "%s",\n' "$([ -n "$seamdir" ] && printf '"prebuilt/%s"' "$SEAM" || echo null)" "$TODAY"
      printf '  "packFiles": ['
      first=1; for f in "$packdir/resources"/*.md; do [ -f "$f" ] || continue
        [ $first -eq 0 ] && printf ', '; printf '"%s"' "$(basename "$f")"; first=0; done
      printf '],\n  "seamFiles": ['
      first=1; if [ -n "$seamdir" ]; then for f in "$seamdir/resources"/*.md; do [ -f "$f" ] || continue
        [ $first -eq 0 ] && printf ', '; printf '"%s"' "$(basename "$f")"; first=0; done; fi
      printf ']\n}\n'
    } > "$dst/assembly.json"
  fi

  # 설치 검증 — "복사했다"는 "존재한다"가 아니다 (install-rules.sh L79-85 관례)
  if [ "$DRY" -eq 0 ]; then
    local n; n=$(ls -1 "$dst/resources"/*.md 2>/dev/null | wc -l | tr -d ' ')
    if [ "${n:-0}" -eq 0 ]; then
      printf '\nFATAL: 설치 후에도 %s/resources 가 비어 있습니다.\n' "$dst" >&2; exit 1
    fi
    printf '    검증: 리소스 %s개 · assembly.json ✓\n' "$n"
  fi
}

printf '가이드 조립\n  플러그인: %s\n  프로젝트: %s\n\n' "$G" "$PROJECT_ROOT/.claude/skills"
[ -n "$FE" ] && [ "$FE" != none ] && assemble frontend "$FE"
[ -n "$BE" ] && [ "$BE" != none ] && assemble backend  "$BE"
printf '\n  신규 %d · 갱신 %d · 유지 %d\n' "$installed" "$updated" "$skipped"
