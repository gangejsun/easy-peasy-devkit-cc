#!/bin/bash
# scripts/install-guide.sh — 축 팩 + 이음매를 조립해 프로젝트 가이드 스킬로 설치
#
# 사전 제작 단위가 "조합"에서 "축"으로 내려간 뒤의 배송 경로다. 조합에 진짜 의존하는
# 부분만 이음매로 남기고, 축 팩 × 2 + 이음매를 접어 스킬 두 개로 만든다:
#   .claude/skills/{frontend,backend}-guide/{SKILL.md, resources/*.md, assembly.json}
# **SKILL.md는 이음매가 있어야 생긴다** — 없으면 리소스만 깔린 정상 중간 상태다.
#
# **판정은 전부 여기서 한다.** 팩이 쓸 만한가 · 이음매가 있는가 · 무엇이 남았는가 ·
# 기준선이 신선한가는 이 스크립트가 읽는 데이터로 정해진다. 호출자가 산문으로 다시
# 판정하면 그 사본이 갈린다 — 실제로 갈려서 정상 조립본을 지우는 규칙이 됐었다.
#
# 사용:
#   install-guide.sh --frontend <팩|none> --backend <팩|none> [--seam <조합>]
#                    [--gate] [--notes <파일>] [--dry-run] [--force] [--no-freshness]
#
#   --frontend react-vite     guides/frontend/react-vite 를 쓴다
#   --backend  supabase       guides/backend/supabase 를 쓴다
#   --seam     nextjs+supabase  사전 제작 이음매를 함께 설치한다 (없으면 캐시 → 팩만)
#   --gate                      SKILL.md까지 만들어진 축만 guide-gate.sh에 넘긴다.
#                               리소스만 조립된 축은 넘기지 않는다 — 게이트는 SKILL.md
#                               부재를 FAIL로 판정하므로 정상 중간 상태를 실패로 오판한다
#   --notes <파일>              프리셋 notes(JSON)를 guide-job.json에 그대로 싣는다
#   --save-seam <조합>          방금 감사를 통과한 이음매를 캐시에 넣는다 (생성 직후 호출)
#   --no-cache                  캐시를 읽지도 쓰지도 않는다
#   --self-test                 합성 팩으로 「미완 팩을 조립하지 않는다」를 증명한다
#   --no-freshness              신선도 판정을 끈다. 기본은 켬 (scripts/guide-freshness.sh)
#                               — 최초 설치에서만 돌고, 네트워크가 없으면 미판정 보고다
#
# 남은 일은 `.epcc/guide-job.json`에 기록한다 — 축별로 무엇이 남았는지 아는 것은 여기뿐이다.
# 남은 것이 없으면 그 파일을 지운다. 작업을 닫는 것은 stack-guide-generator다.
#
# **팩이 없거나 미완이면 끊지 않는다.** 그 축을 생성 대상으로 기록하고 반대 축은 계속
# 조립한다 — 한 축이 없다고 다른 축의 조립을 버릴 이유가 없다.
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
# 종료 코드: 0 = 성공(생성 대기 포함), 1 = 설치 후 검증·게이트 실패, 2 = 사용법 오류

set -Eeuo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PROJECT_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
G="$PLUGIN_ROOT/guides"

FE=""; BE=""; SEAM=""; DRY=0; FORCE=0; SAVE_SEAM=""; NO_CACHE=0; CHECK_FRESH=1
GATE=0; NOTES=""; AXIS_STATE=""; FE_STATE=skip; BE_STATE=skip; SELFTEST=0
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
    --gate)       GATE=1; shift ;;
    --notes)      NOTES="${2:-}"; shift 2 ;;
    --no-freshness)    CHECK_FRESH=0; shift ;;
    --check-freshness) CHECK_FRESH=1; shift ;;   # 하위 호환 — 이제 기본값이다
    --self-test) SELFTEST=1; shift ;;
    --dry-run)  DRY=1; shift ;;
    --force)    FORCE=1; shift ;;
    # --help은 헤더 주석 전문이다. 범위를 숫자로 박으면 헤더가 자라는 순간 잘린다
    -h|--help)  awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; exit 0 ;;
    *) printf 'FATAL: 알 수 없는 인자: %s\n' "$1" >&2; exit 2 ;;
  esac
done

[ -d "$G" ] || { printf 'FATAL: guides/ 없음: %s\n' "$G" >&2; exit 2; }
[ "$SELFTEST" -eq 1 ] || [ -n "$SAVE_SEAM" ] || [ -n "$FE" ] || [ -n "$BE" ] || { printf 'FATAL: --frontend 또는 --backend 중 하나는 필요합니다\n' >&2; exit 2; }

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

# ── 팩이 선언한 리소스를 다 갖고 있는가 ────────────────────────────
# 「디렉토리가 있다」는 「팩이 있다」가 아니다. L0 계약(pack.json·ledger·policies)만
# 동결하고 리소스를 아직 안 쓴 팩이 저장소에 실재한다. 존재로 판정하면 그 팩이 완성본과
# 구별되지 않아 ⓐ 0개면 조립 후 FATAL로 호출자를 중간에 죽이고 ⓑ 1/7이면 **"검증: 리소스
# 1개 ✓"로 통과**한다. 선언(resources[].file)과 실파일을 대조하는 것이 유일한 판정이다.
# 출력: 결손 파일명 목록(공백 구분). 비면 완비.
pack_missing() { # $1=팩디렉토리
  local packdir="$1" f miss=""
  [ -f "$packdir/pack.json" ] || { printf 'pack.json'; return 0; }
  # "file" 키는 resources[] 안에만 있다. "files"(클러스터)는 경계 때문에 걸리지 않는다
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -f "$packdir/resources/$f" ] || miss="$miss $f"
  done < <({ grep -oE '"file"[[:space:]]*:[[:space:]]*"[^"]+"' "$packdir/pack.json" 2>/dev/null || true; } \
           | sed -E 's/.*"([^"]+)"$/\1/')
  printf '%s' "${miss# }"
  return 0
}

# ── 한 축을 조립 ───────────────────────────────────────────────────
# AXIS_STATE를 남긴다: complete(SKILL.md까지) · resources(이음매 대기) · generate(팩 없음·미완)
#                      · pinned(스택 전제 고정으로 건드리지 않음)
assemble() { # $1=frontend|backend  $2=팩이름
  local axis="$1" pack="$2"
  local packdir="$G/$axis/$pack"
  local dst="$PROJECT_ROOT/.claude/skills/$axis-guide"
  local seamdir="" seamsrc=""
  AXIS_STATE=generate
  if [ -n "$SEAM" ] && [ -d "$G/seams/$SEAM/$axis" ]; then
    seamdir="$G/seams/$SEAM/$axis"; seamsrc="prebuilt/$SEAM"
  elif [ "$NO_CACHE" -eq 0 ] && [ -d "$CACHE_ROOT/${FE:-none}+${BE:-none}@$PLUGIN_VER/$axis" ]; then
    # 캐시 히트 — 이 조합을 이미 한 번 만들었고 감사를 통과했다
    seamdir="$CACHE_ROOT/${FE:-none}+${BE:-none}@$PLUGIN_VER/$axis"; seamsrc="cache/${FE:-none}+${BE:-none}@$PLUGIN_VER"
  fi

  # 팩 부재·미완은 실패가 아니라 **생성 경로**다. 여기서 끊으면 반대 축의 조립까지 버린다
  if [ ! -d "$packdir" ]; then
    printf '  [%s-guide]  팩 없음 (%s) — 전체 생성 대상으로 기록합니다\n' "$axis" "$pack"
    return 0
  fi
  local miss; miss=$(pack_missing "$packdir")
  if [ -n "$miss" ]; then
    printf '  [%s-guide]  팩 %s 미완 — 선언한 리소스가 없습니다: %s\n' "$axis" "$pack" "$miss"
    printf '             조립하지 않고 **전체 생성 대상**으로 기록합니다 (반쪽 팩은 없는 팩보다 나쁘다)\n'
    return 0
  fi

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
      PINNED=1; AXIS_STATE=pinned
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
      AXIS_STATE=complete
    else
      printf '    ! SKILL.md 미생성 — 이음매 리소스는 있으나 허브가 없습니다\n'
      AXIS_STATE=resources
    fi
  else
    printf '    ! SKILL.md 미생성 — 이음매가 없습니다. stack-guide-generator가 허브와 이음매를 만듭니다\n'
    AXIS_STATE=resources
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
    local n; n=$({ ls -1 "$dst/resources"/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')
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

# ── 게이트 ─────────────────────────────────────────────────────────
# **SKILL.md까지 만들어진 축만 넘긴다.** 게이트의 첫 검사가 SKILL.md 부재이므로,
# 이음매를 기다리는 정상 중간 상태를 넘기면 전량 FAIL이 나온다. 이 조건을 호출자의
# 산문에 두면 조합 25개에서 방금 조립한 리소스를 지우게 된다 — 실제로 그랬다.
GATE_SCRIPT="$PLUGIN_ROOT/skills/stack-guide-generator/scripts/guide-gate.sh"
run_gate() { # $1=axis  → 0 통과 / 1 FAIL(격리함)
  local axis="$1" code=0
  local dst="$PROJECT_ROOT/.claude/skills/$axis-guide"   # 같은 local 문에서 앞 변수를 참조하면 set -u가 잡는다
  if [ ! -f "$GATE_SCRIPT" ]; then
    printf '  ! 게이트 생략 — %s 없음 (**미검사**다)\n' "$GATE_SCRIPT"; return 0
  fi
  printf '\n  [%s-guide]  게이트\n' "$axis"
  bash "$GATE_SCRIPT" --guide "$dst" --assembly "$dst/assembly.json" || code=$?
  [ "$code" -eq 0 ] && return 0
  # 지우지 않고 스킬 밖으로 내린다. 지우면 진단할 것이 남지 않고, 자리에 두면
  # 반쪽 가이드가 로드된다 — .epcc/ 아래는 둘 다 아니다
  local quar="$PROJECT_ROOT/.epcc/failed-guides/$axis-guide"
  rm -rf "$quar"; mkdir -p "$(dirname "$quar")"; mv "$dst" "$quar"
  printf '\n  게이트 FAIL — %s-guide를 스킬에서 내렸습니다 (반쪽 가이드를 남기지 않는다)\n' "$axis"
  printf '    격리본: %s — 재생성 대상으로 기록합니다\n' "${quar#"$PROJECT_ROOT"/}"
  return 1
}

# ── 남은 일 기록 ───────────────────────────────────────────────────
# 축별로 무엇이 남았는지 아는 것은 이 스크립트뿐이다. 호출자가 손으로 채우면 틀린다.
# 닫는 것은 stack-guide-generator다 (완료 시 삭제 · 실패 시 status=failed).
write_job() {
  local job="$PROJECT_ROOT/.epcc/guide-job.json" need=""
  case "$FE_STATE" in
    generate)  need="$need \"frontend\"" ;;
    resources) need="$need \"seam:frontend\"" ;;
  esac
  case "$BE_STATE" in
    generate)  need="$need \"backend\"" ;;
    resources) need="$need \"seam:backend\"" ;;
  esac
  need="${need# }"; need="${need// /, }"
  if [ -z "$need" ]; then
    if [ -f "$job" ]; then
      [ "$DRY" -eq 0 ] && rm -f "$job"
      printf '\n  남은 일 없음 — 기존 guide-job.json을 지웠습니다\n'
    fi
    return 0
  fi
  printf '\n  남은 일: %s\n' "$need"
  [ "$DRY" -eq 1 ] && { printf '    (--dry-run — .epcc/guide-job.json을 쓰지 않습니다)\n'; return 0; }
  # 조립된 축만 팩 이름을 남긴다 — 생성 대상 축은 팩이 없다는 것이 정보다
  local fpack=null bpack=null
  case "$FE_STATE" in complete|resources|pinned) fpack="\"frontend/$FE\"" ;; esac
  case "$BE_STATE" in complete|resources|pinned) bpack="\"backend/$BE\"" ;; esac

  # notes는 프리셋을 읽는 호출자만 안다. 재호출에서 --notes가 없으면 기존 값을 이어받는다
  # — 파일을 열기 전에 읽어야 한다 (아래 리다이렉트가 먼저 비운다)
  local notes=null
  if [ -n "$NOTES" ] && [ -f "$NOTES" ]; then
    notes=$(cat "$NOTES")                     # $() 가 끝의 개행을 벗긴다
  elif [ -f "$job" ]; then
    notes=$(python3 -c "
import json
try: print(json.dumps(json.load(open('$job')).get('notes')))
except Exception: print('null')" 2>/dev/null || printf 'null')
  fi

  mkdir -p "$PROJECT_ROOT/.epcc"
  { printf '{\n  "status": "pending",\n  "combo": "%s+%s",\n' "${FE:-none}" "${BE:-none}"
    printf '  "need": [%s],\n' "$need"
    printf '  "state": { "frontend": "%s", "backend": "%s" },\n' "$FE_STATE" "$BE_STATE"
    printf '  "packs": { "frontend": %s, "backend": %s },\n' "$fpack" "$bpack"
    printf '  "notes": %s,\n' "$notes"
    printf '  "createdAt": "%s"\n}\n' "$TODAY"
  } > "$job"
  printf '    기록: %s — 다음 세션의 세션 브리핑이 알립니다\n' "${job#"$PROJECT_ROOT"/}"
  return 0
}

# ── 자기 시험 ──────────────────────────────────────────────────────
# **차단 장치를 만들었으면 차단을 증명한다.** 합성 팩 두 개(완비·미완)를 만들어
# 「선언 대비 결손이면 조립하지 않는다」가 살아있는지 본다. 살아있음 ≠ 작동함이다.
run_self_test() {
  local t proj out code=0 pass=0 fail=0
  t=$(mktemp -d) || { printf '임시 디렉토리 생성 실패\n' >&2; exit 2; }
  trap 'rm -rf "$t"' EXIT
  proj="$t/proj"

  local p
  for p in full half; do
    mkdir -p "$t/guides/frontend/$p/resources"
    printf '<!-- epcc-pack: frontend/%s v1.0.0 verified 2026-01-01 zod@4 -->\n\n# %s 축 팩 — 허브 조각\n' "$p" "$p" \
      > "$t/guides/frontend/$p/PACK.md"
    printf '{\n  "axis": "frontend",\n  "name": "%s",\n  "packVersion": "1.0.0",\n  "pkgs": ["zod@4"],\n  "resources": [\n    { "file": "a.md", "nav": "가" },\n    { "file": "b.md", "nav": "나" }\n  ]\n}\n' "$p" \
      > "$t/guides/frontend/$p/pack.json"
    printf '<!-- epcc-pack: frontend/%s v1.0.0 -->\n\n# 가\n' "$p" > "$t/guides/frontend/$p/resources/a.md"
  done
  # full만 선언대로 b.md를 싣는다. half는 선언만 하고 싣지 않는다 (= L0만 동결한 미완 팩)
  printf '<!-- epcc-pack: frontend/full v1.0.0 -->\n\n# 나\n' > "$t/guides/frontend/full/resources/b.md"

  _st() { # $1=팩 $2=기대상태 $3=라벨 [나머지=추가 인자]
    local pk="$1" want="$2" label="$3" got; shift 3
    rm -rf "$proj"; mkdir -p "$proj"
    out=$(CLAUDE_PLUGIN_ROOT="$t" CLAUDE_PROJECT_DIR="$proj" \
          bash "$0" --frontend "$pk" --no-freshness --no-cache "$@" 2>&1) || true
    got=$(printf '%s' "$out" | sed -nE 's/.*상태: frontend=([a-z]+).*/\1/p' | head -1)
    if [ "$got" = "$want" ]; then
      printf '  ✓ %s → %s\n' "$label" "$got"; pass=$((pass+1))
    else
      printf '  ✗ %s → %s (기대 %s)\n' "$label" "${got:-없음}" "$want"; fail=$((fail+1))
    fi
  }

  printf '\ninstall-guide --self-test\n\n'
  _st full "resources" "완비 팩은 조립된다 (이음매 없어 resources)"
  _st half "generate"  "미완 팩은 조립하지 않는다 (선언 대비 결손)"

  # 미완 팩은 **아무것도 설치하지 않아야** 한다 — 반쪽이 남으면 차단이 아니다
  if [ -d "$proj/.claude/skills/frontend-guide" ]; then
    printf '  ✗ 미완 팩인데 스킬 디렉토리가 생겼다\n'; fail=$((fail+1))
  else
    printf '  ✓ 미완 팩은 스킬 디렉토리를 만들지 않는다\n'; pass=$((pass+1))
  fi
  # 그리고 남은 일로 기록돼야 한다 — 조용히 없어지면 사용자가 영영 모른다
  # need 배열을 직접 본다 — "frontend"만 찾으면 state 키에도 걸려 돌연변이를 놓친다
  if grep -q '"need": \["frontend"\]' "$proj/.epcc/guide-job.json" 2>/dev/null; then
    printf '  ✓ 미완 팩을 생성 대상으로 기록한다\n'; pass=$((pass+1))
  else
    printf '  ✗ guide-job.json에 생성 대상이 없다\n'; fail=$((fail+1))
  fi

  # ── 게이트 FAIL → 격리 ────────────────────────────────────────────
  # **이 분기는 사용자의 설치본을 옮긴다.** 옮기는 코드에 픽스처가 없으면
  # 「살아있다」와 「작동한다」를 구분할 수 없다. 게이트를 실패시킬 이음매를 만들어
  # ⓐ 스킬 자리에서 내려갔는가 ⓑ 격리본이 남았는가 ⓒ 생성 대상으로 기록됐는가를 본다.
  if [ -f "$PLUGIN_ROOT/skills/stack-guide-generator/scripts/guide-gate.sh" ]; then
    mkdir -p "$t/skills/stack-guide-generator/scripts" "$t/guides/seams/full+none/frontend/resources"
    cp "$PLUGIN_ROOT/skills/stack-guide-generator/scripts/guide-gate.sh" \
       "$t/skills/stack-guide-generator/scripts/guide-gate.sh"
    # 필수 섹션도 frontmatter도 없는 허브 — 게이트의 첫 검사가 이것을 잡는다
    printf '<!-- epcc-seam: full+none v1.0.0 -->\n\n# 반쪽 허브\n' \
      > "$t/guides/seams/full+none/frontend/HUB.md"
    printf '<!-- epcc-seam: full+none v1.0.0 -->\n\n# 이음매 리소스\n' \
      > "$t/guides/seams/full+none/frontend/resources/seam.md"

    _st full "generate" "게이트 FAIL이면 생성 대상으로 되돌린다" --seam full+none --gate
    if [ -d "$proj/.epcc/failed-guides/frontend-guide" ]; then
      printf '  ✓ 격리본이 .epcc/failed-guides/ 에 남는다 (지우면 진단할 것이 없다)\n'; pass=$((pass+1))
    else
      printf '  ✗ 격리본이 없다 — 게이트 FAIL 후 무엇이 남았는지 알 수 없다\n'; fail=$((fail+1))
    fi
    if [ -d "$proj/.claude/skills/frontend-guide" ]; then
      printf '  ✗ 게이트 FAIL인데 스킬 자리에 그대로 있다 (반쪽 가이드가 로드된다)\n'; fail=$((fail+1))
    else
      printf '  ✓ 게이트 FAIL이면 스킬 자리에서 내려간다\n'; pass=$((pass+1))
    fi
  else
    printf '  – 게이트 격리 픽스처 생략 — guide-gate.sh 없음 (**미검사**다)\n'
  fi

  printf '\n  통과 %d · 실패 %d\n\n' "$pass" "$fail"
  [ "$fail" -eq 0 ] || exit 1
  exit 0
}

if [ "$SELFTEST" -eq 1 ]; then run_self_test; fi
if [ -n "$SAVE_SEAM" ]; then save_seam "$SAVE_SEAM"; exit 0; fi

printf '가이드 조립\n  플러그인: %s\n  프로젝트: %s\n\n' "$G" "$PROJECT_ROOT/.claude/skills"
if [ -n "$FE" ] && [ "$FE" != none ]; then assemble frontend "$FE"; FE_STATE="$AXIS_STATE"; fi
if [ -n "$BE" ] && [ "$BE" != none ]; then assemble backend  "$BE"; BE_STATE="$AXIS_STATE"; fi
printf '\n  신규 %d · 갱신 %d · 유지 %d\n' "$installed" "$updated" "$skipped"

gate_failed=0
if [ "$GATE" -eq 1 ] && [ "$DRY" -eq 1 ]; then
  printf '  (--dry-run — 게이트를 돌리지 않습니다)\n'
elif [ "$GATE" -eq 1 ]; then
  if [ "$FE_STATE" = complete ]; then
    if ! run_gate frontend; then FE_STATE=generate; gate_failed=1; fi
  fi
  if [ "$BE_STATE" = complete ]; then
    if ! run_gate backend;  then BE_STATE=generate; gate_failed=1; fi
  fi
fi

printf '\n  상태: frontend=%s · backend=%s\n' "$FE_STATE" "$BE_STATE"
printf '    complete=스킬 완성 · resources=이음매 대기 · generate=생성 필요 · pinned=전제 고정 · skip=해당 없음\n'
write_job
if [ "$gate_failed" -eq 1 ]; then exit 1; fi
exit 0
