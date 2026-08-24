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
#   --seam     nextjs+supabase  사전 제작 이음매를 함께 설치한다 (없으면 캐시 → 팩만)
#   --save-seam <조합>          방금 감사를 통과한 이음매를 캐시에 넣는다 (생성 직후 호출)
#   --no-cache                  캐시를 읽지도 쓰지도 않는다
#   --check-freshness           조립 직전에 팩의 pkgs 메이저가 오늘도 맞는지 대조한다
#                               (scripts/guide-freshness.sh). 네트워크가 없으면 미판정 보고
#
# 이음매 캐시 — 조합당 한 번만 만든다:
#   ~/.claude/epcc/seam-cache/<조합>@<플러그인버전>/{frontend,backend}/
#   사전 제작 이음매가 없어도 같은 조합의 두 번째 프로젝트부터는 생성 없이 조립된다.
#   이음매는 양쪽 축 메이저 버전에 모두 부패하므로 플러그인 버전으로 캐시를 가른다.
#
# 소유권이 나뉜다 (install-rules.sh의 T1 카드 ↔ 프로젝트 카드와 같은 구조):
#   팩 파일   → 플러그인 소유. epcc-pack 스탬프로 갱신을 판정한다
#   이음매    → 사전 제작이면 플러그인 소유, 생성물이면 프로젝트 소유(건드리지 않는다)
#
# 멱등하다. 스탬프 동일 → 건너뜀 / 구버전 → .bak 후 갱신 / 스탬프 동일 + 내용 상이
# → 사용자 수정본으로 보고 보존.
#
# **스택 전제는 프로젝트가 고정한다.** 이미 설치된 가이드의 pkgs 메이저가 플러그인 팩과
# 다르면 갱신하지 않는다 — 프로젝트는 시작 시점의 스택 위에 코드를 쌓았고, 다른 메이저의
# 패턴으로 바꾸면 낡은 것이 아니라 이 프로젝트에 대해 틀린 지침이 된다. 버전 상승은
# 의존성을 올릴 때 함께 하는 프로젝트의 결정이다. 같은 메이저 안의 수정(결함·보안)은
# 갱신한다. 의도적으로 넘기려면 --force.
#
# 종료 코드: 0 = 성공, 1 = 설치 후 검증 실패, 2 = 사용법·자산 오류

set -Eeuo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
G="$PLUGIN_ROOT/guides"

FE=""; BE=""; SEAM=""; DRY=0; FORCE=0; SAVE_SEAM=""; NO_CACHE=0; CHECK_FRESH=0
PLUGIN_VER=$(grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[0-9.]+"' "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
PLUGIN_VER="${PLUGIN_VER:-0.0.0}"
CACHE_ROOT="${EPCC_SEAM_CACHE:-$HOME/.claude/epcc/seam-cache}"
while [ $# -gt 0 ]; do
  case "$1" in
    --frontend) FE="${2:-}"; shift 2 ;;
    --backend)  BE="${2:-}"; shift 2 ;;
    --seam)       SEAM="${2:-}"; shift 2 ;;
    --save-seam)  SAVE_SEAM="${2:-}"; shift 2 ;;
    --no-cache)   NO_CACHE=1; shift ;;
    --check-freshness) CHECK_FRESH=1; shift ;;
    --dry-run)  DRY=1; shift ;;
    --force)    FORCE=1; shift ;;
    -h|--help)  sed -n '2,25p' "$0" | sed -E 's/^# ?//'; exit 0 ;;
    *) printf 'FATAL: 알 수 없는 인자: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -d "$G" ] || { printf 'FATAL: guides/ 없음: %s\n' "$G" >&2; exit 2; }
[ -n "$SAVE_SEAM" ] || [ -n "$FE" ] || [ -n "$BE" ] || { printf 'FATAL: --frontend 또는 --backend 중 하나는 필요합니다\n' >&2; exit 2; }

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
  local seamdir="" seamsrc=""
  if [ -n "$SEAM" ] && [ -d "$G/seams/$SEAM/$axis" ]; then
    seamdir="$G/seams/$SEAM/$axis"; seamsrc="prebuilt/$SEAM"
  elif [ "$NO_CACHE" -eq 0 ] && [ -d "$CACHE_ROOT/${FE:-none}+${BE:-none}@$PLUGIN_VER/$axis" ]; then
    # 캐시 히트 — 이 조합을 이미 한 번 만들었고 감사를 통과했다
    seamdir="$CACHE_ROOT/${FE:-none}+${BE:-none}@$PLUGIN_VER/$axis"; seamsrc="cache/${FE:-none}+${BE:-none}@$PLUGIN_VER"
  fi

  [ -d "$packdir" ] || { printf 'FATAL: 팩 없음: %s\n' "$packdir" >&2; exit 2; }

  # 신선도 판정 — **최초 설치일 때만 돈다.**
  # 기존 프로젝트는 이미 스택을 고정했고(아래 PINNED 블록), 그 고정을 흔드는 정보는
  # 결정이 아니라 소음이다. 최초 설치는 반대다 — 프로젝트가 아직 아무것도 고정하지
  # 않았으므로 팩이 전제한 메이저가 오늘도 맞는지가 실제 판단 재료다.
  # 「최초」의 판정 기준은 assembly.json이다 — SKILL.md는 이음매가 없으면 아예 안 생겨
  # (node-api 실측) 매번 최초로 오판한다.
  if [ "$CHECK_FRESH" -eq 1 ] && [ ! -f "$dst/assembly.json" ]; then
    local fscript="$PLUGIN_ROOT/scripts/guide-freshness.sh" fcode=0
    if [ -f "$fscript" ]; then
      printf '  [%s-guide]  신선도 판정 (%s)\n' "$axis" "$pack"
      bash "$fscript" --pack "$packdir" || fcode=$?
      if [ "$fcode" -ne 0 ]; then
        printf '    ↑ 메이저 상승이 있습니다. **설치는 계속합니다** — 선언된 메이저가 이 팩이\n'
        printf '      실제로 검증한 것이고, 다른 메이저의 패턴은 낡은 것이 아니라 틀린 것입니다.\n'
        printf '      「팩 전제가 바뀌었다」는 플러그인 갱신 사안이고, 「부분 부패」는 해당\n'
        printf '      리소스만 재저작할 대상입니다 (stack-guide-generator Step 4-1).\n'
      fi
    else
      printf '    ! 신선도 판정 생략 — %s 없음\n' "$fscript"
    fi
  fi

  # 스택 전제 고정 — 설치본과 팩의 pkgs 메이저가 다르면 팩을 건드리지 않는다.
  # 정책을 메시지로만 두면 강제되지 않는다 (선언 위치 ≠ 강제 위치).
  local PINNED=0
  if [ -f "$dst/SKILL.md" ] && [ "$FORCE" -eq 0 ]; then
    local have want
    have=$({ grep -m1 -oE 'pkgs=[^>]*' "$dst/SKILL.md" 2>/dev/null || true; } \
           | grep -oE '[@A-Za-z0-9._/-]+@[0-9]+' | sort -u | tr '\n' ' ')
    want=$({ grep -oE '"[@A-Za-z0-9._/-]+@[0-9.]+"' "$packdir/pack.json" 2>/dev/null | tr -d '"' || true; } \
           | grep -oE '[@A-Za-z0-9._/-]+@[0-9]+' | sort -u | tr '\n' ' ')
    if [ -n "$have" ] && [ -n "$want" ] && [ "$have" != "$want" ]; then
      PINNED=1
      printf '  [%s-guide]  스택 전제 고정 — 팩을 갱신하지 않습니다\n' "$axis"
      printf '    설치본: %s\n    플러그인: %s\n' "$have" "$want"
      printf '    의존성을 올릴 때 /stack-guide-generator로 함께 옮기거나, 알고 넘기려면 --force\n'
      return 0
    fi
  fi

  printf '  [%s-guide]  팩 %s%s\n' "$axis" "$pack" "${seamsrc:+ + 이음매 $seamsrc}"
  [ "$DRY" -eq 0 ] && mkdir -p "$dst/resources"

  local pv; pv=$(grep -m1 -oE 'v[0-9]+\.[0-9]+\.[0-9]+' "$packdir/PACK.md" 2>/dev/null || echo v0.0.0)
  local pkgs; pkgs=$(grep -m1 -oE 'pkgs=.*-->' "$packdir/PACK.md" 2>/dev/null | sed 's/ -->//' || true)
  [ -z "$pkgs" ] && pkgs=$(python3 -c "
import json,sys
try: print('pkgs=' + ' '.join(json.load(open('$packdir/pack.json'))['pkgs']))
except Exception: print('')" 2>/dev/null)

  local SEAMLABEL="${seamsrc:-generated}"
  local info="<!-- epcc-guide: assembled $TODAY combo=${FE:-none}+${BE:-none} packs=$axis/$pack@${pv#v} seam=$SEAMLABEL $pkgs -->"

  for f in "$packdir/resources"/*.md; do [ -f "$f" ] && put "$f" "$dst/resources/$(basename "$f")"; done
  if [ -n "$seamdir" ]; then
    for f in "$seamdir/resources"/*.md; do [ -f "$f" ] && put "$f" "$dst/resources/$(basename "$f")"; done
    # 캐시 항목은 허브 없이 리소스만 있을 수 있다 (허브가 생기기 전에 적재된 경우).
    # 없는 허브를 전제하면 조립이 조용히 중단된다 — 명시적으로 갈라 처리한다.
    if [ -f "$seamdir/HUB.md" ]; then
      put_hub "$seamdir/HUB.md" "$dst/SKILL.md" "$axis-guide" "$info"
    else
      printf '    ! SKILL.md 미생성 — 이음매 리소스는 있으나 허브가 없습니다\n'
    fi
  else
    printf '    ! SKILL.md 미생성 — 이음매가 없습니다. stack-guide-generator가 허브와 이음매를 만듭니다\n'
  fi

  # 조립 원장 — 무엇이 어디서 왔는지. 게이트가 팩 소유 파일을 식별하는 근거
  if [ "$DRY" -eq 0 ]; then
    { printf '{\n  "axis": "%s",\n  "pack": "%s/%s",\n  "packVersion": "%s",\n' "$axis" "$axis" "$pack" "${pv#v}"
      printf '  "seam": %s,\n  "assembledAt": "%s",\n' "$([ -n "$seamsrc" ] && printf '"%s"' "$seamsrc" || echo null)" "$TODAY"
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

# ── 캐시 적재 ──────────────────────────────────────────────────────
# 생성 + 게이트 + 감사 + 수리를 마친 이음매만 넣는다. 미검증 산출물을 캐시에 넣으면
# 그 조합의 모든 후속 프로젝트가 같은 결함을 물려받는다 — 캐시가 결함의 증폭기가 된다.
save_seam() {
  local combo="$1" axis src n=0
  local dir="$CACHE_ROOT/$combo@$PLUGIN_VER"   # 같은 local 문에서 앞 변수를 참조하면 set -u가 잡는다
  [ "$NO_CACHE" -eq 0 ] || { printf '  --no-cache 지정 — 캐시에 넣지 않습니다\n'; return 0; }
  for axis in frontend backend; do
    src="$PROJECT_ROOT/.claude/skills/$axis-guide"
    [ -d "$src/resources" ] || continue
    # 팩 소유 파일은 캐시에 넣지 않는다 — 플러그인이 이미 갖고 있고,
    # 넣으면 팩 갱신이 캐시에 가려 영영 도달하지 않는다
    local packfiles=""
    [ -f "$src/assembly.json" ] && packfiles=$(grep -oE '"packFiles"[^]]*\]' "$src/assembly.json" | grep -oE '"[^"]+\.md"' | tr -d '"' | tr '\n' ' ')
    [ "$DRY" -eq 0 ] && mkdir -p "$dir/$axis/resources"
    local f base
    for f in "$src/resources"/*.md; do
      [ -f "$f" ] || continue
      base=$(basename "$f")
      case " $packfiles " in *" $base "*) continue;; esac
      [ "$DRY" -eq 0 ] && cp "$f" "$dir/$axis/resources/$base"
      n=$((n+1))
    done
    [ -f "$src/SKILL.md" ] && [ "$DRY" -eq 0 ] && cp "$src/SKILL.md" "$dir/$axis/HUB.md"
  done
  if [ "$n" -eq 0 ]; then
    printf 'FATAL: 캐시에 넣을 이음매 파일이 없습니다 (%s)\n' "$combo" >&2; exit 1
  fi
  printf '이음매 캐시 적재: %s (%s개 파일)\n  %s\n' "$combo@$PLUGIN_VER" "$n" "$dir"
  return 0
}

if [ -n "$SAVE_SEAM" ]; then save_seam "$SAVE_SEAM"; exit 0; fi

printf '가이드 조립\n  플러그인: %s\n  프로젝트: %s\n\n' "$G" "$PROJECT_ROOT/.claude/skills"
[ -n "$FE" ] && [ "$FE" != none ] && assemble frontend "$FE"
[ -n "$BE" ] && [ "$BE" != none ] && assemble backend  "$BE"
printf '\n  신규 %d · 갱신 %d · 유지 %d\n' "$installed" "$updated" "$skipped"
