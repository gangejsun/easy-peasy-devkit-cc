#!/bin/bash
# scripts/guide-freshness.sh — 축 팩·설치 가이드의 부패(버전 낡음) 판정
#
# **날짜가 아니라 `pkgs` 메이저로 판정한다.** doctor의 「기준선 6개월 초과」는 대리
# 지표다 — 6개월이 지나도 메이저가 안 올랐으면 안 낡았고, 2개월 만에 프레임워크
# 메이저가 오르면 낡았다. 대조 대상(`pack.json`의 pkgs · 스탬프의 pkgs=)은 이미
# 있고 guide-gate가 그 존재를 강제한다. 그러니 대조만 한다.
#
#   guide-freshness.sh --pack <팩디렉토리>...     유지자: 팩의 pack.json pkgs
#   guide-freshness.sh --guide <가이드디렉토리>   소비자: SKILL.md/HUB.md 기준선·스탬프
#       --offline        조회하지 않고 **미판정을 명시 보고**한다 (부패 없음이 아니다)
#       --json           기계가 읽을 TSV를 함께 낸다
#       --timeout <초>   레지스트리 조회 상한 (기본 15)
#   guide-freshness.sh --self-test    차단 능력 증명 (네트워크 없이 돈다)
#
# **`fixesVariants`가 자동 최신화의 경계다.** 거기 걸린 패키지(프레임워크·ORM)의 메이저
# 상승은 팩 본문 전체의 전제가 바뀐 것이므로 소비자 세션에서 고치지 않는다 — 경고하고
# 플러그인 갱신으로 넘긴다. 그 외 패키지는 **영향받는 리소스 파일만** 재저작 대상이다.
#
# 조회 실패·오프라인은 **skip 명시 보고**다. "부패 없음"으로 세지 않는다 — 침묵 통과와
# 「검사했는데 깨끗함」이 구분되지 않으면 이 스크립트는 거짓말을 하게 된다.
#
# 종료 코드: 0 = 메이저 상승 없음, 1 = 메이저 상승 있음, 2 = 사용법·자산 오류

set -uo pipefail   # -e 없음: 모든 패키지를 끝까지 조회해 전체 보고서를 낸다

FAIL=0; WARN=0; PASS=0; SKIP=0
C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_C=$'\033[36m'; C_D=$'\033[2m'; C_0=$'\033[0m'
[ -t 1 ] || { C_R=""; C_G=""; C_Y=""; C_C=""; C_D=""; C_0=""; }

# doctor.sh의 규약을 복사한다 (source 아님 — lib/common.sh의 set -Eeuo pipefail과
# ERR trap은 "모든 검사를 끝까지 돌린다" 정책과 충돌한다). return 0을 명시한다.
ok()   { PASS=$((PASS+1)); printf "  ${C_G}✓${C_0} %s\n" "$1"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf "  ${C_R}✗${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
warn() { WARN=$((WARN+1)); printf "  ${C_Y}!${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
skip() { SKIP=$((SKIP+1)); printf "  ${C_C}–${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
sec()  { printf "\n${C_D}── %s ─────────────────────────────${C_0}\n" "$1"; return 0; }

num() { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }

TMP=$(mktemp -d 2>/dev/null) || { printf "임시 디렉토리 생성 실패\n" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

OFFLINE=0; JSON=0; NETTIMEOUT=15; MODE=""; TARGETS=()

# ── 이름과 메이저를 가른다 ──────────────────────────────────────────
# 스코프 패키지(@aws-sdk/client-dynamodb@3)가 있으므로 **마지막 @**에서 자른다.
split_spec() { # $1=spec → "name<TAB>선언버전(메이저 또는 메이저.마이너)"
  local spec="$1" name ver
  ver="${spec##*@}"
  name="${spec%@*}"
  case "$name" in '') printf '%s\t\n' "$spec"; return 0 ;; esac
  case "$ver" in ''|*[!0-9.]*) printf '%s\t\n' "$spec"; return 0 ;; esac
  printf '%s\t%s\n' "$name" "$ver"
  return 0
}

# **0.x는 마이너가 파괴적 변경 축이다** (semver: 0.y.z에서 y가 major 노릇을 한다).
# fastapi·uvicorn·ruff·httpx가 전부 0.x이므로 메이저만 보면 부패가 영영 안 보인다.
break_level() { # $1=버전문자열 → 비교 가능한 「파괴 수준」
  local v="$1" maj min
  maj="${v%%.*}"
  case "$maj" in ''|*[!0-9]*) printf '%s' "$v"; return 0 ;; esac
  if [ "$maj" != "0" ]; then printf '%s' "$maj"; return 0; fi
  case "$v" in
    *.*) min="${v#*.}"; min="${min%%.*}"; printf '0.%s' "$min" ;;
    *)   printf '0' ;;      # 마이너를 선언하지 않았다 — 비교 불가
  esac
  return 0
}

# ── 레지스트리 조회 ─────────────────────────────────────────────────
# 생태계는 pack.json의 registry로 정한다 (없으면 npm). PyPI는 curl 하나로 끝난다.
resolve_latest() { # $1=이름 $2=레지스트리 → 최신 버전 문자열 또는 빈 문자열
  local name="$1" reg="${2:-npm}"
  # 자기검사는 네트워크에 의존하면 안 된다 — 차단 능력을 증명하는 것이지
  # 레지스트리의 오늘 상태를 재는 것이 아니다.
  if [ -n "${EPCC_FRESHNESS_FAKE:-}" ] && [ -f "$EPCC_FRESHNESS_FAKE" ]; then
    awk -F'\t' -v n="$name" '$1==n {print $2; found=1} END{ if(!found) print "" }' "$EPCC_FRESHNESS_FAKE"
    return 0
  fi
  case "$reg" in
    npm)
      command -v npm >/dev/null 2>&1 || return 0
      npm view "$name" version --fetch-timeout "$((NETTIMEOUT*1000))" --no-audit --no-fund 2>/dev/null | tail -1
      ;;
    pypi)
      command -v curl >/dev/null 2>&1 || return 0
      curl -fsS --max-time "$NETTIMEOUT" "https://pypi.org/pypi/$name/json" 2>/dev/null \
        | tr ',' '\n' | grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' \
        | sed -E 's/.*"([^"]+)"$/\1/'
      ;;
    *) return 0 ;;
  esac
  return 0
}

# ── 팩·가이드에서 pkgs 목록을 얻는다 ────────────────────────────────
specs_of_pack() { # $1=팩디렉토리
  awk '/"pkgs"[[:space:]]*:/{f=1} f{print} f&&/\]/{exit}' "$1/pack.json" 2>/dev/null \
    | grep -oE '"[^"]+@[0-9]+(\.[0-9]+)?"' | tr -d '"' | sort -u
  return 0
}

specs_of_guide() { # $1=가이드디렉토리 — 기준선 우선, 없으면 생성 스탬프
  local f line
  for f in "$1/SKILL.md" "$1/HUB.md"; do
    [ -f "$f" ] || continue
    line=$(grep -m1 -oE '<!-- epcc-guide-baseline:[^>]*-->' "$f" 2>/dev/null)
    [ -z "$line" ] && line=$(grep -m1 -oE 'pkgs=[^ ]*( [^ ]+@[0-9.]+)*' "$f" 2>/dev/null)
    [ -n "$line" ] && { printf '%s' "$line" | grep -oE '[@A-Za-z0-9_./-]+@[0-9]+(\.[0-9]+)?' | sort -u; return 0; }
  done
  return 0
}

# ── fixesVariants 경계 ──────────────────────────────────────────────
# 값(express·prisma·hono·drizzle …)이 패키지 이름에 들어 있으면 「팩 전제」로 본다.
is_fixed_variant() { # $1=패키지이름 $2=팩디렉토리
  local name="$1" P="$2" v
  [ -f "$P/pack.json" ] || return 1
  while IFS= read -r v; do
    [ -z "$v" ] && continue
    case "$name" in *"$v"*) return 0 ;; esac
  done < <(awk '/"fixesVariants"[[:space:]]*:/{f=1} f{print} f&&/\}/{exit}' "$P/pack.json" 2>/dev/null \
            | grep -oE ':[[:space:]]*"[^"]+"' | sed -E 's/.*"([^"]+)"$/\1/')
  return 1
}

check_target() { # $1=라벨 $2=자산 디렉토리 $3=pack|guide
  local label="$1" DIR="$2" kind="$3" reg="npm"
  sec "$label"

  local specs
  if [ "$kind" = "pack" ]; then
    specs=$(specs_of_pack "$DIR")
    reg=$(grep -m1 -oE '"registry"[[:space:]]*:[[:space:]]*"[^"]+"' "$DIR/pack.json" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/')
    reg="${reg:-npm}"
  else
    specs=$(specs_of_guide "$DIR")
  fi

  local n; n=$(num "$(printf '%s' "$specs" | grep -c . | tr -d ' ')")
  if [ "$n" -eq 0 ]; then
    warn "대조할 pkgs가 없다" "메이저가 붙은 항목이 없으면 부패는 **영영 보이지 않는다** — pack.json의 pkgs 또는 epcc-guide-baseline을 채운다"
    return 0
  fi

  if [ "$OFFLINE" -eq 1 ]; then
    skip "오프라인 — ${n}개 미판정" "이것은 **부패 없음이 아니다.** 네트워크가 있을 때 다시 돌린다"
    return 0
  fi

  # 조회는 병렬로. 레지스트리 왕복이 유일한 비용이다.
  local spec name major
  : > "$TMP/jobs.txt"
  while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    IFS=$'\t' read -r name major < <(split_spec "$spec")
    [ -n "$major" ] || continue
    printf '%s\t%s\n' "$name" "$major" >> "$TMP/jobs.txt"
  done <<< "$specs"

  : > "$TMP/res.tsv"
  while IFS=$'\t' read -r name major; do
    [ -z "$name" ] && continue
    { printf '%s\t%s\t%s\n' "$name" "$major" "$(resolve_latest "$name" "$reg")" >> "$TMP/res.tsv"; } &
  done < "$TMP/jobs.txt"
  wait

  local latest lmaj same=0 minor=0 majorup=0 unknown=0 files fixed
  : > "$TMP/report.tsv"
  while IFS=$'\t' read -r name major latest; do
    [ -z "$name" ] && continue
    if [ -z "$latest" ]; then
      unknown=$((unknown+1))
      printf '%s\t%s\t?\t미판정\t\n' "$name" "$major" >> "$TMP/report.tsv"
      continue
    fi
    # 0.x는 마이너까지, 1.0 이상은 메이저만 본다
    lmaj=$(break_level "$latest")
    local dmaj; dmaj=$(break_level "$major")
    if [ "$dmaj" = "0" ] && [ "${latest%%.*}" = "0" ]; then
      # 선언이 `name@0`뿐이다 — 0.x에서는 마이너가 파괴 축이라 대조 대상이 없다
      minor=$((minor+1)); printf '%s\t%s\t%s\t0x_마이너_미선언\t\n' "$name" "$major" "$latest" >> "$TMP/report.tsv"
      continue
    fi
    if [ "$lmaj" = "$dmaj" ]; then
      same=$((same+1)); printf '%s\t%s\t%s\t동일\t\n' "$name" "$major" "$latest" >> "$TMP/report.tsv"
    elif [ "$(num "${lmaj%%.*}")" -lt "$(num "${dmaj%%.*}")" ] || { [ "${lmaj%%.*}" = "${dmaj%%.*}" ] && [ "$(num "${lmaj#*.}")" -lt "$(num "${dmaj#*.}")" ]; }; then
      # 선언이 최신보다 높다 — 오타이거나 npm 패키지가 아닌 것을 목록에 넣은 것이다
      minor=$((minor+1)); printf '%s\t%s\t%s\t선언이_더_높음\t\n' "$name" "$major" "$latest" >> "$TMP/report.tsv"
    else
      majorup=$((majorup+1))
      files=""
      [ -d "$DIR/resources" ] && files=$({ grep -rlF "$name" "$DIR/resources" 2>/dev/null || true; } | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')
      # **전제 변경은 메이저 상승일 때만이다.** fixesVariants가 선언하는 것은 「어느
      # 프레임워크·ORM인가」이고, 0.x의 마이너 상승은 그 선택을 바꾸지 않는다.
      # 0.x 마이너까지 전제 변경으로 올리면 FastAPI가 릴리스할 때마다 「플러그인을
      # 갱신하라」가 울려 신호가 죽는다.
      fixed="no"
      if is_fixed_variant "$name" "$DIR" && [ "${dmaj%%.*}" != "${lmaj%%.*}" ]; then fixed="yes"; fi
      printf '%s\t%s\t%s\t메이저상승\t%s\t%s\n' "$name" "$dmaj→$lmaj" "$latest" "$fixed" "$files" >> "$TMP/report.tsv"
    fi
  done < "$TMP/res.tsv"

  [ "$same" -gt 0 ] && ok "메이저 동일 ${same}개"
  [ "$unknown" -gt 0 ] && skip "조회 실패 ${unknown}개 — 미판정" "$(awk -F'\t' '$4=="미판정"{printf "%s ", $1}' "$TMP/report.tsv")— 부패 없음이 아니다"
  local nhigh n0x
  nhigh=$(num "$(awk -F'\t' '$4=="선언이_더_높음"' "$TMP/report.tsv" | grep -c . | tr -d ' ')")
  n0x=$(num "$(awk -F'\t' '$4=="0x_마이너_미선언"' "$TMP/report.tsv" | grep -c . | tr -d ' ')")
  [ "$nhigh" -gt 0 ] && warn "선언 버전이 최신보다 높은 항목 ${nhigh}개" "$(awk -F'\t' '$4=="선언이_더_높음"{printf "%s(선언 %s ↔ 최신 %s) ", $1, $2, $3}' "$TMP/report.tsv")— 오타이거나 **레지스트리 패키지가 아닌 것**(런타임 버전 등)을 목록에 넣은 것이다"
  [ "$n0x" -gt 0 ] && warn "0.x인데 마이너를 선언하지 않은 항목 ${n0x}개" "$(awk -F'\t' '$4=="0x_마이너_미선언"{printf "%s(선언 %s ↔ 최신 %s) ", $1, $2, $3}' "$TMP/report.tsv")— **0.y.z에서는 y가 파괴적 변경 축이다.** \`name@0\`으로는 부패가 영영 보이지 않는다 — \`name@0.141\`처럼 마이너까지 적는다"

  if [ "$majorup" -eq 0 ]; then
    ok "메이저 상승 없음 — 신선하다"
  else
    local nm om lt fx fl
    while IFS=$'\t' read -r nm om lt st fx fl; do
      [ "$st" = "메이저상승" ] || continue
      if [ "$fx" = "yes" ]; then
        bad "팩 전제가 바뀌었다: $nm $om (최신 $lt)" "fixesVariants에 걸린 패키지다 — **소비자 세션에서 고치지 않는다.** 플러그인 갱신(새 축 팩)의 사안이고, 지금은 선언된 메이저 그대로 설치하는 것이 옳다"
      else
        if [ -n "$fl" ]; then
          warn "부분 부패: $nm $om (최신 $lt)" "영향 리소스: $fl — 이 파일들만 재저작하고 감사 B를 집중한다"
        else
          warn "부분 부패(툴체인): $nm $om (최신 $lt)" "리소스가 이름으로 언급하지 않는다 — 설정·명령·타입 환경에만 등장한다. 재저작 대상은 없지만 **pack-smoke의 --online 설치가 이 메이저로 바뀐다**"
        fi
      fi
    done < "$TMP/report.tsv"
  fi

  [ "$JSON" -eq 1 ] && { printf "\n${C_D}── TSV (이름·선언메이저·최신·판정·fixesVariants·영향파일) ──${C_0}\n"; cat "$TMP/report.tsv"; }
  return 0
}


# ── 자기검사: 차단 능력을 증명한다 ─────────────────────────────────
# **살아있음 ≠ 작동함.** 결함을 심은 픽스처가 실제로 exit 1을 받는지, 그리고
# **의도한 이유로** 받는지 본다 (EPCC_FX_WHY=1로 사유를 찍는다).
_fx_pack() { # $1=디렉토리 $2=fixesVariants JSON 조각 $3=pkgs 조각
  mkdir -p "$1/resources" || return 1
  cat > "$1/pack.json" <<EOF
{
  "axis": "backend", "name": "fx", "packVersion": "0.0.0",
  "fixesVariants": $2,
  "pkgs": [$3]
}
EOF
  printf '# fx\n\n`express` 를 쓴다. `pino` 도 쓴다.\n' > "$1/resources/a.md"
  return 0
}

_fx_run() { # $1=라벨 $2=기대exit $3=팩디렉토리 $4=기대사유(grep)
  local out code
  out=$(EPCC_FRESHNESS_FAKE="$TMP/fake.tsv" bash "$0" --pack "$3" 2>&1); code=$?
  if [ "$code" -ne "$2" ]; then
    bad "$1 → exit $code (기대 $2)" "$(printf '%s' "$out" | grep -E '✗|!|통과 ' | head -3 | tr '\n' ';')"
    return 0
  fi
  if [ -n "${4:-}" ] && ! printf '%s' "$out" | grep -q "$4"; then
    bad "$1 → exit $code 이지만 **다른 이유로** 그렇다" "기대 사유: $4 / 실제: $(printf '%s' "$out" | grep -E '✗|!' | head -2 | tr '\n' ';')"
    return 0
  fi
  ok "$1 → exit $code"
  [ -n "${EPCC_FX_WHY:-}" ] && printf "      ${C_D}%s${C_0}\n" "$(printf '%s' "$out" | grep -E '✗|!' | head -2 | sed 's/^  *//' | tr '\n' ';')"
  return 0
}

run_self_test() {
  printf "\n${C_D}guide-freshness --self-test${C_0}  (차단 능력 증명 · 네트워크 없음)\n"
  printf 'express\t5.2.1\nprisma\t7.9.1\npino\t9.9.9\nzod\t4.4.3\n' > "$TMP/fake.tsv"

  sec "무해 픽스처 (통과해야 한다)"
  _fx_pack "$TMP/clean" '{ "framework": "express" }' '"express@5", "pino@9", "zod@4"'
  _fx_run "메이저가 전부 일치 → 신선" 0 "$TMP/clean" ""

  sec "양성 픽스처 (차단해야 한다)"
  _fx_pack "$TMP/variant" '{ "orm": "prisma" }' '"express@5", "prisma@6"'
  _fx_run "fixesVariants 패키지의 메이저 상승 → 팩 전제 변경" 1 "$TMP/variant" "팩 전제가 바뀌었다"

  _fx_pack "$TMP/partial" '{ "framework": "express" }' '"express@5", "pino@8"'
  _fx_run "그 외 패키지의 메이저 상승 → 부분 부패" 1 "$TMP/partial" "부분 부패"

  _fx_pack "$TMP/nopkgs" '{}' ''
  _fx_run "pkgs가 비면 부패가 영영 보이지 않는다 → WARN" 1 "$TMP/nopkgs" "대조할 pkgs가 없다"

  sec "0.x — 마이너가 파괴적 변경 축이다"
  printf 'fastapi\t0.141.1\nuvicorn\t0.52.4\nexpress\t5.2.1\n' > "$TMP/fake.tsv"
  _fx_pack "$TMP/zerominor" '{}' '"fastapi@0.115"'
  _fx_run "0.115 → 0.141 은 파괴적 상승이다" 1 "$TMP/zerominor" "부분 부패"

  _fx_pack "$TMP/zeronominor" '{}' '"fastapi@0"'
  _fx_run "마이너 없는 0.x 선언은 대조 대상이 없다 → WARN" 1 "$TMP/zeronominor" "마이너를 선언하지 않은"

  _fx_pack "$TMP/zerosame" '{}' '"fastapi@0.141", "uvicorn@0.52"'
  _fx_run "0.x 마이너가 일치하면 신선" 0 "$TMP/zerosame" ""

  printf 'express\t5.2.1\nprisma\t7.9.1\npino\t9.9.9\nzod\t4.4.3\n' > "$TMP/fake.tsv"

  sec "fixesVariants — 전제 변경은 메이저에서만"
  printf 'fastapi\t0.141.1\n' > "$TMP/fake.tsv"
  _fx_pack "$TMP/fvminor" '{ "framework": "fastapi" }' '"fastapi@0.115"'
  _fx_run "fixesVariants의 0.x 마이너 상승 → 부분 부패 (전제 변경 아님)" 1 "$TMP/fvminor" "부분 부패"

  printf 'fastapi\t1.2.0\n' > "$TMP/fake.tsv"
  _fx_pack "$TMP/fvmajor" '{ "framework": "fastapi" }' '"fastapi@0.141"'
  _fx_run "fixesVariants의 메이저 상승 → 전제 변경" 1 "$TMP/fvmajor" "팩 전제가 바뀌었다"

  printf 'express\t5.2.1\nprisma\t7.9.1\npino\t9.9.9\nzod\t4.4.3\n' > "$TMP/fake.tsv"

  sec "미판정을 통과로 세지 않는다"
  printf '' > "$TMP/fake.tsv"
  _fx_pack "$TMP/unknown" '{}' '"express@5"'
  _fx_run "조회 실패는 skip이지 '부패 없음'이 아니다" 0 "$TMP/unknown" "미판정"
  return 0
}

while [ $# -gt 0 ]; do
  case "$1" in
    --pack)    MODE="pack";  shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do TARGETS+=("$1"); shift; done ;;
    --guide)   MODE="guide"; shift; while [ $# -gt 0 ] && [ "${1#--}" = "$1" ]; do TARGETS+=("$1"); shift; done ;;
    --self-test) MODE="selftest"; shift ;;
    --offline) OFFLINE=1; shift ;;
    --json)    JSON=1; shift ;;
    --timeout) NETTIMEOUT="$(num "${2:-15}")"; shift 2 || exit 2 ;;
    -h|--help) sed -n '2,22p' "$0" | sed -E 's/^#[[:space:]]?//'; exit 0 ;;
    *) printf "알 수 없는 옵션: %s (--help 참조)\n" "$1" >&2; exit 2 ;;
  esac
done

[ -n "$MODE" ] || { printf -- "--pack 또는 --guide 중 하나가 필요합니다\n" >&2; exit 2; }
if [ "$MODE" = "selftest" ]; then
  run_self_test
  printf "\n────────────────────────────────────────────\n"
  printf "  통과 %s · WARN %s · SKIP %s · FAIL %s\n" "$PASS" "$WARN" "$SKIP" "$FAIL"
  [ "$FAIL" -gt 0 ] && exit 1
  exit 0
fi
[ "${#TARGETS[@]}" -gt 0 ] || { printf -- "--%s <디렉토리> 가 필요합니다\n" "$MODE" >&2; exit 2; }
[ "$(num "$NETTIMEOUT")" -gt 0 ] || NETTIMEOUT=15

printf "\n${C_D}guide-freshness${C_0}  %s개 대상  ${C_D}(%s · 조회 상한 %s초)${C_0}\n" \
  "${#TARGETS[@]}" "$MODE" "$NETTIMEOUT"

for t in "${TARGETS[@]}"; do
  if [ ! -d "$t" ]; then bad "대상 없음: $t"; continue; fi
  check_target "$(basename "$(dirname "$t")")/$(basename "$t")" "${t%/}" "$MODE"
done

printf "\n────────────────────────────────────────────\n"
printf "  통과 %s · WARN %s · SKIP %s · 전제변경 %s\n" "$PASS" "$WARN" "$SKIP" "$FAIL"
# 종료 코드 1은 「메이저 상승이 있다」이지 실패가 아니다 — 호출자가 분기한다.
[ "$FAIL" -gt 0 ] && exit 1
[ "$WARN" -gt 0 ] && exit 1
exit 0
