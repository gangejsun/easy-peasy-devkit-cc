#!/bin/bash
# skills/stack-guide-generator/scripts/guide-gate.sh — 생성 가이드 기계 게이트
#
# 프롬프트에 흩어져 있던 체크리스트를 스크립트로 옮긴 것이다. 판정은 3단이다.
#   FAIL   설치 차단 — 하나라도 남으면 설치하지 않는다 (exit 1)
#   WARN   보고 의무 — 설치는 하되 사용자 보고에 실어야 한다
#   REVIEW 한 항목씩 사람이 정당화한다 — 자동 실패로 만들면 위양성에 묻혀 못 쓴다
#
#   guide-gate.sh --guide <가이드디렉토리> [옵션]
#       --ledger <파일>    심볼 원장(마크다운 표) ↔ 실제 정의·소비 대조
#       --forbid <kw,kw>   교차 누출 금지 키워드 (확정 조합에 없는 스택 이름)
#       --pm <이름>        프리셋의 packageManager — 다른 매니저 명령을 잡는다
#       --generated        생성물로 취급 (생성 스탬프 필수)
#   guide-gate.sh --pair --contract <계약파일> --frontend <디렉토리> --backend <디렉토리>
#   guide-gate.sh --help
#
# 코드 판정은 코드펜스 안만 본다. 주석 행과 ❌/Bad 표식 이후 구간은 제외한다 —
# 가이드는 안티패턴 예시를 일부러 싣기 때문에 블라인드 스캔은 위양성투성이가 된다.
#
# 종료 코드: 0 = FAIL 0, 1 = FAIL 존재, 2 = 사용법 오류

set -uo pipefail   # -e 없음: 모든 검사를 끝까지 돌려 전체 보고서를 낸다

FAIL=0; WARN=0; PASS=0; REVIEW=0
C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_C=$'\033[36m'; C_D=$'\033[2m'; C_0=$'\033[0m'
[ -t 1 ] || { C_R=""; C_G=""; C_Y=""; C_C=""; C_D=""; C_0=""; }

# doctor.sh의 규약을 복사한다 (source 아님 — lib/common.sh의 set -Eeuo pipefail과
# ERR trap은 "모든 검사를 끝까지 돌린다" 정책과 충돌한다).
# doctor.sh 원본은 $2가 비면 반환값이 1이다. 여기서는 return 0을 명시한다.
ok()   { PASS=$((PASS+1));     printf "  ${C_G}✓${C_0} %s\n" "$1"; return 0; }
bad()  { FAIL=$((FAIL+1));     printf "  ${C_R}✗${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
warn() { WARN=$((WARN+1));     printf "  ${C_Y}!${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
rev()  { REVIEW=$((REVIEW+1)); printf "  ${C_C}?${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
sec()  { printf "\n${C_D}── %s ─────────────────────────────${C_0}\n" "$1"; return 0; }

num() { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }

TMP=$(mktemp -d 2>/dev/null) || { printf "임시 디렉토리 생성 실패\n" >&2; exit 2; }
trap 'rm -rf "$TMP"' EXIT

# ── 코드 행 추출 ────────────────────────────────────────────────────
# 코드펜스 안 + 주석이 아닌 + 안티패턴(❌/Bad) 구간이 아닌 행만 남긴다.
# 표식은 두 관용구를 모두 인정한다: `// ❌` / `// ✅`, `// Bad` / `// Good`.
# 펜스 직전 산문 행이 ❌/Bad면 펜스 전체가 안티패턴으로 시작한다.
# 출력: <파일>\t<줄번호>\t<본문>
codelines() {
  awk '
    # 표식은 ❌/✅ 가 영어 단어보다 우선한다. 단어 판정의 경계에서 _ 와 숫자를 빼야
    # 계약 식별자(BAD_SHAPE·BAD_REQUEST)가 안티패턴 표식으로 오인되지 않는다 —
    # 오인되면 그 지점부터 코드 추출이 꺼져 이후 검사가 조용히 건너뛴다(미탐).
    function isbad(s)  { return (index(s,"❌")>0 || (index(s,"✅")==0 && s ~ /(^|[^A-Za-z0-9_])(Bad|BAD)([^A-Za-z0-9_]|$)/)) }
    function isgood(s) { return (index(s,"✅")>0 || (index(s,"❌")==0 && s ~ /(^|[^A-Za-z0-9_])(Good|GOOD)([^A-Za-z0-9_]|$)/)) }
    function iscomment(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*|--)/) }
    FNR==1 { inf=0; pol=1; lastprose="" }
    /^[[:space:]]*```/ { if (!inf) { inf=1; pol = isbad(lastprose) ? 0 : 1 } else { inf=0 }; next }
    !inf { if ($0 ~ /[^[:space:]]/) lastprose=$0; next }
    iscomment($0) { if (isbad($0)) pol=0; else if (isgood($0)) pol=1; next }
    pol { print FILENAME "\t" FNR "\t" $0 }
  ' "$@"
}

guide_files() { ls "$1/SKILL.md" "$1"/resources/*.md 2>/dev/null; }

# 프레임워크가 이름을 정하는 export — 서로 다른 라우트에서 시그니처가 갈리는 것이 정상이다
FRAMEWORK_EXPORTS='^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|default|middleware|config|metadata|generateMetadata|generateStaticParams|loader|action|handler)$'

# ════════════════════════════════════════════════════════════════════
# --guide : 가이드 1개 검사
# ════════════════════════════════════════════════════════════════════
run_guide() {
  local G="$1"
  printf "\n${C_D}guide-gate${C_0}  %s\n" "$G"

  [ -d "$G" ] || { printf "가이드 디렉토리 없음: %s\n" "$G" >&2; exit 2; }
  [ -f "$G/SKILL.md" ] || { bad "SKILL.md 없음"; return; }

  local FILES; FILES=$(guide_files "$G")
  [ -n "$FILES" ] || { bad "resources/*.md 없음"; return; }
  # shellcheck disable=SC2086
  codelines $FILES > "$TMP/code.tsv"
  cut -f3 "$TMP/code.tsv" > "$TMP/code.txt"

  check_structure "$G"
  check_refs "$G"
  check_budget "$G"
  check_fences "$G"
  check_section_budget "$G"
  check_symbols "$G"
  check_env "$G"
  check_leak "$G"
  check_pm "$G"
  check_stamp "$G"
  check_ledger "$G"
}

# ── 1. 구조: frontmatter + 필수 섹션 8개 순서 ──
check_structure() {
  local G="$1" f="$1/SKILL.md"
  sec "구조 (필수 섹션 8개)"

  head -1 "$f" | grep -q '^---$' && ok "frontmatter 구분자" || bad "1행이 '---'이 아님 — frontmatter 없음"

  local nm dn
  nm=$(awk '/^name:/{sub(/^name:[[:space:]]*/,"");gsub(/^"|"$/,"");print;exit}' "$f")
  dn=$(basename "$G")
  [ "$nm" = "$dn" ] && ok "name = 디렉토리명 ($nm)" || bad "name 불일치: '$nm' ≠ 디렉토리 '$dn'" "스킬이 로드되지 않거나 다른 이름으로 노출된다"

  local dl
  dl=$(num "$(awk '/^description:/{sub(/^description:[[:space:]]*/,"");gsub(/^"|"$/,"");print length($0);exit}' "$f")")
  if [ "$dl" -eq 0 ]; then bad "description 없음 (또는 블록 스칼라)"
  elif [ "$dl" -le 450 ]; then ok "description ${dl}/450자"
  else bad "description ${dl}자 — 규격 상한 450자 초과"; fi

  local heads n h
  heads=$(grep '^## ' "$f" | sed 's/^## //')
  n=$(num "$(printf '%s\n' "$heads" | grep -c . | tr -d ' ')")
  if [ "$n" -ne 7 ]; then
    bad "'## ' 섹션 ${n}개 — 규격은 7개(frontmatter 포함 8)" "$(printf '%s' "$heads" | tr '\n' '/')"
  else
    local i=1 okorder=1
    for want in "Quick Start" "Architecture Overview" "Directory Structure" "Core Principles" "Common Imports" "*" "Navigation Guide"; do
      h=$(printf '%s\n' "$heads" | sed -n "${i}p")
      if [ "$want" != "*" ]; then
        case "$h" in "$want"*) ;; *) bad "섹션 ${i} 불일치: '$h' — 규격은 '$want'"; okorder=0;; esac
      fi
      i=$((i+1))
    done
    [ "$okorder" -eq 1 ] && ok "필수 섹션 7개 순서 적합"
  fi
}

# ── 2. 참조: dangling + Navigation 커버리지 차집합 ──
check_refs() {
  local G="$1"
  sec "참조 (dangling · Navigation 커버리지)"

  local d=0 c=0 r
  for r in $(grep -rhoE 'resources/[A-Za-z0-9._-]+\.md' "$G"/SKILL.md "$G"/resources/*.md 2>/dev/null | sort -u); do
    c=$((c+1))
    [ -f "$G/$r" ] || { bad "dangling 참조: $r"; d=$((d+1)); }
  done
  [ "$d" -eq 0 ] && ok "리소스 참조 ${c}건 모두 실재"

  awk '/^## Navigation Guide/{s=1;next} /^## /{s=0} s' "$G/SKILL.md" \
    | grep -oE 'resources/[A-Za-z0-9._-]+\.md' | sort -u > "$TMP/nav.txt"
  ls "$G"/resources/*.md 2>/dev/null | while read -r p; do printf 'resources/%s\n' "$(basename "$p")"; done | sort -u > "$TMP/real.txt"

  local uncovered ghostref
  uncovered=$(comm -13 "$TMP/nav.txt" "$TMP/real.txt" | tr '\n' ' ')
  ghostref=$(comm -23 "$TMP/nav.txt" "$TMP/real.txt" | tr '\n' ' ')
  [ -n "$(printf '%s' "$uncovered" | tr -d ' ')" ] \
    && bad "Navigation Guide 미커버 리소스: $uncovered" "규격: resources/ 전 파일이 정확히 1회 이상 등장" \
    || ok "Navigation 커버리지 완전 ($(num "$(wc -l < "$TMP/real.txt")")개)"
  [ -n "$(printf '%s' "$ghostref" | tr -d ' ')" ] \
    && bad "Navigation Guide가 없는 파일을 가리킴: $ghostref"

  local rc; rc=$(num "$(wc -l < "$TMP/real.txt")")
  if [ "$rc" -ge 6 ] && [ "$rc" -le 10 ]; then ok "리소스 파일 ${rc}개 (규격 6~10)"
  else warn "리소스 파일 ${rc}개 — 규격 6~10 밖" "필수 7슬롯 + 선택 0~3에서 도출된 범위"; fi
}

# ── 3. 예산 ──
check_budget() {
  local G="$1" over=0 near=0 f n
  sec "예산 (파일당 300줄)"
  for f in $(guide_files "$G"); do
    n=$(num "$(wc -l < "$f" | tr -d ' ')")
    if   [ "$n" -gt 300 ]; then bad "$(basename "$f") ${n}줄 — 300줄 초과"; over=$((over+1))
    elif [ "$n" -gt 290 ]; then warn "$(basename "$f") ${n}줄 — 290줄 초과(보고 의무)" "상한에 붙은 파일은 다음 변경 때 저자가 아니라 예산이 삭제 대상을 고른다"; near=$((near+1)); fi
  done
  [ "$over" -eq 0 ] && [ "$near" -eq 0 ] && ok "전 파일 290줄 이하"
}

# ── 4. 코드펜스 짝 ──
check_fences() {
  local G="$1" odd=0 f n
  sec "코드펜스 짝"
  for f in $(guide_files "$G"); do
    n=$(num "$(grep -c '^[[:space:]]*```' "$f" | tr -d ' ')")
    [ $((n % 2)) -ne 0 ] && { bad "$(basename "$f"): 펜스 ${n}개 — 홀수" "닫히지 않은 코드 블록. 이후 본문 전체가 코드로 렌더된다"; odd=$((odd+1)); }
  done
  [ "$odd" -eq 0 ] && ok "전 파일 코드펜스 짝 일치"
}

# ── 5. 섹션별 예산 (규격서의 예산 열) ──
check_section_budget() {
  local G="$1" f="$1/SKILL.md"
  sec "섹션별 예산"

  local hit=0 name lim n
  while IFS=$'\t' read -r name lim; do
    [ -z "$name" ] && continue
    n=$(num "$(awk -v s="## $name" '$0==s||index($0,s)==1{f=1;next} /^## /{f=0} f' "$f" | grep -c . | tr -d ' ')")
    [ "$n" -eq 0 ] && continue
    [ "$n" -gt "$lim" ] && { warn "## $name ${n}줄 — 규격 ${lim}줄"; hit=$((hit+1)); }
  done <<'LIMITS'
Architecture Overview	30
Directory Structure	30
Common Imports	30
LIMITS

  # 보조 섹션(6번째)은 ≤40줄
  local aux
  aux=$(grep '^## ' "$f" | sed 's/^## //' | sed -n '6p')
  if [ -n "$aux" ]; then
    n=$(num "$(awk -v s="## $aux" 'index($0,s)==1{f=1;next} /^## /{f=0} f' "$f" | grep -c . | tr -d ' ')")
    [ "$n" -gt 40 ] && { warn "보조 섹션 '## $aux' ${n}줄 — 규격 40줄"; hit=$((hit+1)); }
  fi

  # Quick Start: 체크리스트 2개, 각 6~9항목
  local qs cl
  # 체크리스트 제목은 '### 제목' 또는 '**제목:**' 둘 다 인정한다 (두 관용구가 실재한다)
  qs=$(awk '/^## Quick Start/{f=1;next} /^## /{f=0} f' "$f")
  cl=$(num "$(printf '%s\n' "$qs" | grep -cE '^(### |\*\*.*\*\*[[:space:]]*$)' | tr -d ' ')")
  if [ "$cl" -ne 2 ]; then warn "Quick Start 체크리스트 ${cl}개 — 규격 2개"; hit=$((hit+1)); fi
  printf '%s\n' "$qs" | awk '
    /^### /                      { if (h!="") print h "\t" c; h=substr($0,5); c=0; next }
    /^\*\*.*\*\*[[:space:]]*$/  { if (h!="") print h "\t" c; h=$0; gsub(/\*/,"",h); c=0; next }
    /^[[:space:]]*(-|[0-9]+\.)[[:space:]]/{ if (h!="") c++ }
    END{ if (h!="") print h "\t" c }' > "$TMP/qs.tsv"
  while IFS=$'\t' read -r name n; do
    [ -z "$name" ] && continue
    n=$(num "$n")
    { [ "$n" -lt 6 ] || [ "$n" -gt 9 ]; } && { warn "Quick Start '$name' ${n}항목 — 규격 6~9"; hit=$((hit+1)); }
  done < "$TMP/qs.tsv"

  # Core Principles: 규칙 5~8개, 각 ≤20줄
  local cp rules
  cp=$(awk '/^## Core Principles/{f=1;next} /^## /{f=0} f' "$f")
  rules=$(num "$(printf '%s\n' "$cp" | grep -c '^### ' | tr -d ' ')")
  { [ "$rules" -lt 5 ] || [ "$rules" -gt 8 ]; } && { warn "Core Principles 규칙 ${rules}개 — 규격 5~8"; hit=$((hit+1)); }
  printf '%s\n' "$cp" | awk '
    /^### /{ if (h!="") print h "\t" c; h=substr($0,5); c=0; next }
    { if (h!="") c++ }
    END{ if (h!="") print h "\t" c }' > "$TMP/cp.tsv"
  while IFS=$'\t' read -r name n; do
    [ -z "$name" ] && continue
    [ "$(num "$n")" -gt 20 ] && { warn "규칙 '$(printf '%.44s' "$name")' $(num "$n")줄 — 규격 20줄"; hit=$((hit+1)); }
  done < "$TMP/cp.tsv"

  [ "$hit" -eq 0 ] && ok "섹션별 예산 전항 적합"
}

# ── 6. 심볼: 중복 export 상이 정의(FAIL) · 유령 정의/미정의 호출/시그니처 혼재(REVIEW) ──
check_symbols() {
  local G="$1"
  sec "심볼 (중복 정의 · 유령 정의 · 미정의 호출)"

  # 정의 사이트 → "이름<TAB>인자개수".
  # 인자 개수는 괄호 깊이를 세어 최상위 쉼표만 센다 — 구조 분해(`{ a, b }`)와
  # 제네릭(`Record<string, string>`)의 쉼표를 인자로 세면 정상 코드가 불일치로 잡힌다.
  # 같은 줄에서 괄호가 닫히지 않으면(여러 줄 시그니처) 판정을 포기한다.
  awk '
    function arity(s,   i,d,c,ch,pv,seen) {
      d=0; c=0; seen=0; pv=""
      for (i=1; i<=length(s); i++) {
        ch=substr(s,i,1)
        if (ch=="(" || ch=="{" || ch=="[") d++
        else if (ch=="<") { if (pv ~ /[A-Za-z0-9_]/) d++ }
        else if (ch==">") { if (pv != "=" && d>0) d-- }
        else if (ch=="}" || ch=="]") { if (d>0) d-- }
        else if (ch==")") { if (d==0) return seen ? c+1 : 0; d-- }
        else if (ch=="," && d==0) c++
        if (d==0 && ch ~ /[A-Za-z0-9_$]/) seen=1
        pv=ch
      }
      return -1
    }
    {
      line=$0
      while (match(line, /export[[:space:]]+(async[[:space:]]+)?function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/) \
          || match(line, /export[[:space:]]+const[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*(async[[:space:]]+)?\(/)) {
        hit=substr(line, RSTART, RLENGTH)
        rest=substr(line, RSTART+RLENGTH)
        nm=hit; sub(/[[:space:]]*(=[[:space:]]*(async[[:space:]]+)?)?\($/, "", nm); sub(/.*[[:space:]]/, "", nm)
        a=arity(rest)
        if (a >= 0) print nm "\t" a
        line=rest
      }
    }' "$TMP/code.txt" | sort -u > "$TMP/defs.tsv"

  local dup
  dup=$(awk -F'\t' -v skip="$FRAMEWORK_EXPORTS" '$1 !~ skip {c[$1]++} END{for(k in c) if (c[k]>1) print k}' "$TMP/defs.tsv" | sort | tr '\n' ' ')
  if [ -n "$(printf '%s' "$dup" | tr -d ' ')" ]; then
    bad "중복 export — 같은 이름이 서로 다른 시그니처로 정의됨: $dup" \
        "소비처가 어느 정의를 믿어야 하는지 알 수 없다. 하나로 통일하거나 이름을 나눈다"
  else
    ok "중복 export 상이 정의 없음"
  fi

  # 전체 export 이름 (프레임워크 예약 이름 제외)
  grep -oE 'export (async )?(function|const|class|type|interface) [A-Za-z_][A-Za-z0-9_]*' "$TMP/code.txt" \
    | awk '{print $NF}' | sort -u | grep -vE "$FRAMEWORK_EXPORTS" > "$TMP/exports.txt"

  # 유령 정의 — 가이드 전체에서 정의 1회뿐
  : > "$TMP/ghost_fn.txt"; : > "$TMP/ghost_comp.txt"
  local s cnt
  while read -r s; do
    [ -z "$s" ] && continue
    cnt=$(num "$(grep -rhow "$s" $(guide_files "$G") 2>/dev/null | grep -c . | tr -d ' ')")
    [ "$cnt" -gt 1 ] && continue
    case "$s" in [A-Z]*) printf '%s\n' "$s" >> "$TMP/ghost_comp.txt";; *) printf '%s\n' "$s" >> "$TMP/ghost_fn.txt";; esac
  done < "$TMP/exports.txt"

  local gf gc
  gf=$(num "$(grep -c . "$TMP/ghost_fn.txt" | tr -d ' ')")
  gc=$(num "$(grep -c . "$TMP/ghost_comp.txt" | tr -d ' ')")
  [ "$gf" -gt 0 ] && rev "유령 정의(함수·스키마) ${gf}건" "$(tr '\n' ' ' < "$TMP/ghost_fn.txt")— 정의만 있고 가이드 어디서도 다시 쓰이지 않는다. 소비처를 만들거나 삭제"
  [ "$gc" -gt 0 ] && rev "단회 등장 컴포넌트 ${gc}건" "$(tr '\n' ' ' < "$TMP/ghost_comp.txt")— 독립 예시 컴포넌트면 정상"
  [ "$gf" -eq 0 ] && [ "$gc" -eq 0 ] && ok "유령 정의 없음"

  # 미정의 프로젝트 로컬 호출 — '@/'에서 import했는데 가이드에 정의가 없는 이름
  grep -oE "import (type )?\{[^}]*\} from '@/[^']*'" "$TMP/code.txt" \
    | sed -E "s/import (type )?\{//; s/\} from '.*//" | tr ',' '\n' \
    | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^type[[:space:]]+//; s/[[:space:]]+as[[:space:]]+.*//' \
    | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u > "$TMP/localimports.txt"
  : > "$TMP/undef.txt"
  while read -r s; do
    [ -z "$s" ] && continue
    grep -qE "(export[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+$s\b" "$TMP/code.txt" \
      || printf '%s\n' "$s" >> "$TMP/undef.txt"
  done < "$TMP/localimports.txt"
  local ud; ud=$(num "$(grep -c . "$TMP/undef.txt" | tr -d ' ')")
  [ "$ud" -gt 0 ] \
    && rev "정의 없이 import되는 로컬 심볼 ${ud}건" "$(tr '\n' ' ' < "$TMP/undef.txt")— 스캐폴딩(UI 키트)이면 정상, 가이드가 소개한 이름이면 절단면" \
    || ok "로컬 import 심볼 전부 정의됨"

  # 시그니처 혼재 — 정의는 하나인데 호출 형태가 유·무인자로 갈린다
  local mixed=""
  while read -r s; do
    [ -z "$s" ] && continue
    local forms
    forms=$(grep -ohE "\b$s\([^)]*" "$TMP/code.txt" | sed -E "s/^$s\(//" | sed -E 's/^([A-Za-z0-9_{[]).*/유/; s/^$/무/' | sort -u | tr -d '\n')
    case "$forms" in *유*무*|*무*유*) mixed="$mixed $s";; esac
  done < "$TMP/exports.txt"
  [ -n "$mixed" ] \
    && rev "호출 형태 혼재:$mixed" "가변인자 유틸(cn 등)·선택 인자면 정상, 그 외는 자기모순" \
    || ok "호출 형태 혼재 없음"
}

# ── 7. env 키 커버리지 ──
check_env() {
  local G="$1"
  sec "env 키 커버리지"

  grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]{2,}:[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*\.' "$TMP/code.txt" \
    | sed -E 's/^[[:space:]]*//; s/:.*//' | sort -u > "$TMP/envdecl.txt"
  local nd; nd=$(num "$(grep -c . "$TMP/envdecl.txt" | tr -d ' ')")
  if [ "$nd" -eq 0 ]; then
    warn "검증된 env 스키마가 없음 — 커버리지 검사 생략" "규격서: 환경변수도 입력이다. 검증된 단일 모듈에서 부팅 시점에 실패시킨다"
    return
  fi

  grep -oE '(^|[^A-Za-z0-9_.])env\.[A-Z][A-Z0-9_]+' "$TMP/code.txt" | sed -E 's/.*env\.//' | sort -u > "$TMP/envuse.txt"
  local miss; miss=$(comm -23 "$TMP/envuse.txt" "$TMP/envdecl.txt" | tr '\n' ' ')
  if [ -n "$(printf '%s' "$miss" | tr -d ' ')" ]; then
    bad "env 스키마에 없는 키 사용: $miss" "부팅 검증을 통과한 뒤 사용처에서 undefined가 된다 — 스키마에 추가하라"
  else
    ok "env 사용 키 $(num "$(wc -l < "$TMP/envuse.txt")")개 전부 스키마(${nd}개)에 선언됨"
  fi
}

# ── 8. 교차 누출 ──
check_leak() {
  local G="$1"
  [ -n "$FORBID" ] || return 0
  sec "교차 누출"
  # 단어 경계(-w)로 본다. 부분 문자열로 보면 계약이 지정한 필드명이 금지어에 걸린다
  # (`--forbid next` ↔ `nextCursor`) — 같은 게이트의 --pair 는 그 필드를 요구하므로
  # 두 검사가 서로 반대를 요구하게 된다. 라이브러리 누출은 import 경로나 점 호출로
  # 나타나고 그 둘은 -w 로도 잡힌다(`@prisma/client`·`prisma.user`).
  local kw hits n=0
  for kw in $(printf '%s' "$FORBID" | tr ',' ' '); do
    [ -z "$kw" ] && continue
    hits=$(grep -rniwF "$kw" $(guide_files "$G") 2>/dev/null | head -3 | cut -c1-110 | tr '\n' ';')
    if [ -n "$hits" ]; then bad "확정 조합에 없는 스택 키워드 '$kw' 등장" "$hits"; n=$((n+1)); fi
  done
  [ "$n" -eq 0 ] && ok "금지 키워드 누출 없음"
}

# ── 9. 패키지 매니저 정합 ──
check_pm() {
  local G="$1"
  [ -n "$PM" ] || return 0
  sec "패키지 매니저"
  local other n=0 hits
  for other in npm pnpm yarn bun uv poetry pip; do
    [ "$other" = "$PM" ] && continue
    hits=$(grep -rhoE "\b$other (run|install|add|exec|dlx|create|i|sync|ci)\b" $(guide_files "$G") 2>/dev/null | sort -u | tr '\n' ' ')
    if [ -n "$(printf '%s' "$hits" | tr -d ' ')" ]; then
      bad "패키지 매니저 불일치: 확정은 '$PM'인데 '$other' 명령 사용" "$hits"; n=$((n+1))
    fi
  done
  [ "$n" -eq 0 ] && ok "패키지 매니저 '$PM' 일관"
}

# ── 10. 스탬프와 패키지 커버리지 ──
check_stamp() {
  local G="$1" f="$1/SKILL.md"
  sec "스탬프"

  local stamp base
  stamp=$(grep -m1 -oE '<!-- epcc-guide:[^>]*-->' "$f" 2>/dev/null)
  base=$(grep -m1 -oE '<!-- epcc-guide-baseline:[^>]*-->' "$f" 2>/dev/null)

  if [ "$GENERATED" -eq 1 ]; then
    [ -n "$stamp" ] && ok "생성 스탬프 존재" || bad "생성 스탬프 없음" "재생성 시 수동 편집을 감지할 근거가 사라진다"
    [ -n "$stamp" ] && { case "$stamp" in *pkgs=*) ok "스탬프에 pkgs= 있음";; *) warn "스탬프에 pkgs= 없음" "버전 드리프트 검사의 대조 대상이 생기지 않는다";; esac; }
  else
    [ -n "$base" ] && ok "검증 기준선 존재" || warn "검증 기준선(epcc-guide-baseline) 없음" "사전 제작 가이드는 기준선이 낡음 판정의 유일한 근거다"
  fi

  local decl; decl="$stamp$base"
  [ -n "$decl" ] || return 0

  grep -oE "from '[^'.][^']*'" "$TMP/code.txt" | sed -E "s/from '//; s/'$//" \
    | grep -v '^@/' | grep -vE '^(node:|bun:)' \
    | sed -E 's#^(@[^/]+/[^/]+).*#\1#; s#^([^@][^/]*)/.*#\1#' \
    | grep -vE '^(fs|path|crypto|http|https|url|util|os|events|stream|buffer|child_process|assert|zlib|net|tls|worker_threads|perf_hooks|timers|process)$' \
    | sort -u > "$TMP/pkgs.txt"

  local p missing=""
  while read -r p; do
    [ -z "$p" ] && continue
    printf '%s' "$decl" | grep -qF "$p@" || missing="$missing $p"
  done < "$TMP/pkgs.txt"
  [ -n "$missing" ] \
    && warn "스탬프에 없는 import 패키지:$missing" "버전 드리프트 검사가 이 패키지들을 보지 못한다 — 스탬프에 <pkg>@<major>를 추가하라" \
    || ok "import 패키지 $(num "$(wc -l < "$TMP/pkgs.txt")")개 전부 스탬프에 선언됨"
}

# ── 11. 심볼 원장 대조 ──
check_ledger() {
  local G="$1"
  [ -n "$LEDGER" ] || return 0
  sec "심볼 원장 대조"
  [ -f "$LEDGER" ] || { bad "원장 파일 없음: $LEDGER"; return; }

  # | `심볼` | 정의파일 | 소비처1, 소비처2 |
  sed -E 's/^[[:space:]]*\|//; s/\|[[:space:]]*$//' "$LEDGER" \
    | grep '|' | grep -v '^[[:space:]]*[-: ]*|[-: |]*$' \
    | awk -F'|' 'NF>=3 { gsub(/`|[[:space:]]/,"",$1); if ($1=="" || $1=="심볼" || $1=="symbol") next; print $1"\t"$2"\t"$3 }' \
    > "$TMP/ledger.tsv"

  local rows; rows=$(num "$(grep -c . "$TMP/ledger.tsv" | tr -d ' ')")
  [ "$rows" -eq 0 ] && { bad "원장에서 항목을 읽지 못함: $LEDGER" "형식: | \`심볼\` | 정의파일 | 소비처, 소비처 |"; return; }

  local sym deff cons n_def=0 n_con=0 rf cf c
  while IFS=$'\t' read -r sym deff cons; do
    [ -z "$sym" ] && continue
    rf=$(_resolve "$G" "$deff")
    if [ -z "$rf" ]; then bad "원장 '$sym'의 정의 파일이 실재하지 않음: $(printf '%s' "$deff" | tr -d ' `')"; n_def=$((n_def+1)); continue; fi
    if ! codelines "$rf" | cut -f3 | grep -qE "(export[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+$sym\b"; then
      bad "원장 '$sym'의 정의가 $(basename "$rf")에 없음" "원장은 계약이다 — 정의를 넣거나 원장에서 지운다"; n_def=$((n_def+1))
    fi
    for c in $(printf '%s' "$cons" | tr ',' ' '); do
      c=$(printf '%s' "$c" | tr -d ' `')
      [ -z "$c" ] || [ "$c" = "—" ] || [ "$c" = "-" ] && continue
      cf=$(_resolve "$G" "$c")
      if [ -z "$cf" ]; then bad "원장 '$sym'의 소비처 파일이 실재하지 않음: $c"; n_con=$((n_con+1)); continue; fi
      grep -qw "$sym" "$cf" || { bad "원장 '$sym'이 소비처 $(basename "$cf")에 등장하지 않음" "유령 정의 — 소비하거나 원장에서 지운다"; n_con=$((n_con+1)); }
    done
  done < "$TMP/ledger.tsv"

  cut -f1 "$TMP/ledger.tsv" | sort -u > "$TMP/ledgersym.txt"
  local unreg; unreg=$(comm -23 "$TMP/exports.txt" "$TMP/ledgersym.txt" | tr '\n' ' ')
  if [ -n "$(printf '%s' "$unreg" | tr -d ' ')" ]; then
    bad "원장에 없는 export 심볼:$unreg" "층 2 규율: 새 프로젝트 로컬 심볼은 도입 즉시 원장에 등재한다"
  else
    ok "export 심볼 전부 원장에 등재됨"
  fi
  [ "$n_def" -eq 0 ] && [ "$n_con" -eq 0 ] && ok "원장 ${rows}행 정의·소비 대조 통과"
}

_resolve() {
  local G="$1" name; name=$(printf '%s' "$2" | tr -d ' `')
  [ -z "$name" ] && return 0
  if   [ -f "$G/$name" ];           then printf '%s' "$G/$name"
  elif [ -f "$G/resources/$name" ]; then printf '%s' "$G/resources/$name"
  fi
}

# ════════════════════════════════════════════════════════════════════
# --pair : 와이어 계약 ↔ 두 가이드 차집합
# ════════════════════════════════════════════════════════════════════
run_pair() {
  printf "\n${C_D}guide-gate --pair${C_0}  계약: %s\n" "$CONTRACT"
  [ -f "$CONTRACT" ] || { printf "계약 파일 없음: %s\n" "$CONTRACT" >&2; exit 2; }
  [ -d "$FE" ] && [ -d "$BE" ] || { printf "가이드 디렉토리 없음 (--frontend/--backend)\n" >&2; exit 2; }

  sec "계약 토큰 차집합"
  # 백틱 안의 식별자 + 3자리 상태 코드가 대조 토큰이다. 백틱 스팬 '전체'가 아니라
  # 스팬 '안'에서 뽑는다 — 봉투를 통째로 감싼 계약(`{ data, nextCursor }`)에서
  # 토큰이 0개가 되면 이 검사는 조용히 통과한다.
  { grep -oE '`[^`]+`' "$CONTRACT" | tr -d '`' | grep -oE '[A-Za-z_][A-Za-z0-9_]*'
    grep -oE '(^|[^0-9])[1-5][0-9][0-9]([^0-9]|$)' "$CONTRACT" | grep -oE '[0-9]{3}'
  } | grep -vE '^([A-Z]|string|number|boolean|object|null|true|false|undefined|unknown|never|any|void|json|JSON|Date|Promise|Record|Array|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$' \
    | sort -u > "$TMP/tokens.txt"

  local ntok; ntok=$(num "$(wc -l < "$TMP/tokens.txt")")
  if [ "$ntok" -lt 5 ]; then
    bad "계약에서 대조 토큰 ${ntok}개만 추출됨" "필드·에러 코드 이름을 각각 백틱으로 감싸야 대조된다 (양식: assets/wire-contract.template.md)"
    return
  fi
  ok "계약 토큰 ${ntok}개 추출"

  local t nf=0 nb=0 mf="" mb=""
  while read -r t; do
    [ -z "$t" ] && continue
    grep -rqw "$t" $(guide_files "$FE") 2>/dev/null || { mf="$mf $t"; nf=$((nf+1)); }
    grep -rqw "$t" $(guide_files "$BE") 2>/dev/null || { mb="$mb $t"; nb=$((nb+1)); }
  done < "$TMP/tokens.txt"

  [ "$nf" -gt 0 ] && bad "계약 토큰 ${nf}건이 frontend에 없음:$mf" "프론트가 계약의 이 부분을 다루지 않는다" || ok "frontend 계약 토큰 전량 등장"
  [ "$nb" -gt 0 ] && bad "계약 토큰 ${nb}건이 backend에 없음:$mb"  "백엔드가 계약의 이 부분을 내보내지 않는다" || ok "backend 계약 토큰 전량 등장"

  sec "페이지네이션 모델 배타성"
  local model
  model=$(grep -iE '모델|model' "$CONTRACT" | grep -oiE 'cursor|offset' | head -1 | tr 'A-Z' 'a-z')
  if [ -z "$model" ]; then
    warn "계약에 페이지네이션 모델(cursor|offset) 선언이 없음"
  else
    local rival hits
    # 'ring-offset-2' 같은 CSS 클래스에 걸리지 않도록 하이픈 뒤 offset은 제외한다
    [ "$model" = "cursor" ] && rival='page=|[^-]offset[^-]|\btotalPages\b' || rival='\bnextCursor\b'
    hits=$(grep -rhoE "$rival" $(guide_files "$FE") $(guide_files "$BE") 2>/dev/null | sort -u | tr '\n' ' ')
    [ -n "$(printf '%s' "$hits" | tr -d ' ')" ] \
      && rev "모델은 '$model'인데 상대 모델의 어휘가 등장: $hits" "설명 목적이면 정상, 예시 코드가 쓰면 계약 위반" \
      || ok "페이지네이션 모델 '$model' 배타 유지"
  fi

  sec "엔드포인트 차집합"
  # UI 라우트와 API 경로는 문자열만으로 구별되지 않는다 — HTTP 호출 어휘가 같은 줄에
  # 있는 것만 API 경로로 본다. 판단이 필요하므로 REVIEW다.
  codelines $(guide_files "$FE") 2>/dev/null | cut -f3 \
    | grep -iE 'api|fetch|http|request|axios|client|url' \
    | grep -oE "'/[a-zA-Z0-9][a-zA-Z0-9/:{}._$-]*'" | tr -d "'" | sort -u > "$TMP/fe_paths.txt"
  local p miss=0 tot=0 stem missing=""
  while read -r p; do
    [ -z "$p" ] && continue
    tot=$((tot+1))
    stem=$(printf '%s' "$p" | sed -E 's#^/api##; s#/:[A-Za-z0-9_]+##g; s#/\{[^}]*\}##g; s#/$##')
    [ -z "$stem" ] || [ "$stem" = "/" ] && continue
    grep -rqF -- "$stem" $(guide_files "$BE") 2>/dev/null || { missing="$missing $p"; miss=$((miss+1)); }
  done < "$TMP/fe_paths.txt"
  [ "$miss" -eq 0 ] \
    && ok "프론트가 호출하는 경로 ${tot}건 모두 백엔드에서 발견" \
    || rev "백엔드에서 찾지 못한 프론트 호출 경로 ${miss}건:$missing" "예시용 가상 경로면 정상, 실제 계약이면 한쪽이 빠진 것"
}

# ════════════════════════════════════════════════════════════════════
# --self-test : 차단 능력 증명 (doctor.sh의 양성 픽스처 패턴)
# ════════════════════════════════════════════════════════════════════
# "살아있다"는 "막는다"가 아니다. 정규식 하나가 어긋나면 모든 검사가 조용히
# 통과하고, 그 상태는 겉보기에 정상과 구별되지 않는다. 결함을 심은 픽스처가
# 실제로 exit 1을 받는지 확인해야만 게이트를 신뢰할 수 있다.
run_self_test() {
  printf "\n${C_D}guide-gate --self-test${C_0}  (차단 능력 증명)\n"
  local fx="$TMP/fx"
  _fx_build "$fx" || { bad "픽스처 생성 실패"; return; }

  sec "무해 픽스처 (통과해야 한다)"
  _fx_assert "$fx/clean/sample-backend-guide" 0 "결함 없는 가이드" --generated
  _fx_assert "$fx/clean/sample-backend-guide" 0 "올바른 원장" --generated --ledger "$fx/clean/ledger-ok.md"
  # 두 음성 검사 — 미탐은 오탐보다 위험하다. 각각 실제로 게이트를 통과처럼 보이게 했던 결함이다
  _fx_assert "$fx/clean/sample-backend-guide" 0 "계약 식별자(BAD_SHAPE)가 표식으로 오인되지 않음" --generated --ledger "$fx/clean/ledger-ok.md"
  _fx_assert "$fx/clean/sample-backend-guide" 0 "계약 필드명(nextCursor)이 금지어 부분 문자열에 안 걸림" --generated --forbid next

  sec "양성 픽스처 (차단해야 한다)"
  _fx_assert "$fx/dangling/sample-backend-guide"  1 "dangling 리소스 참조"  --generated
  _fx_assert "$fx/envkey/sample-backend-guide"    1 "env 스키마 미선언 키"  --generated
  _fx_assert "$fx/dupexport/sample-backend-guide" 1 "중복 export 상이 정의" --generated
  _fx_assert "$fx/budget/sample-backend-guide"    1 "리소스 300줄 초과"     --generated
  _fx_assert "$fx/fence/sample-backend-guide"     1 "닫히지 않은 코드펜스"  --generated
  _fx_assert "$fx/section/sample-backend-guide"   1 "필수 섹션 누락"        --generated
  _fx_assert "$fx/nostamp/sample-backend-guide"   1 "생성 스탬프 없음"      --generated
  _fx_assert "$fx/leak/sample-backend-guide"      1 "교차 누출 키워드"      --generated --forbid prisma
  _fx_assert "$fx/clean/sample-backend-guide"     1 "패키지 매니저 불일치"  --generated --pm pnpm
  _fx_assert "$fx/clean/sample-backend-guide"     1 "원장 불일치(소비처 부재)" --generated --ledger "$fx/clean/ledger-bad.md"
  _fx_assert "$fx/clean/sample-backend-guide"     1 "원장 미등재 심볼"      --generated --ledger "$fx/clean/ledger-short.md"
}

_fx_assert() {
  local dir="$1" want="$2" label="$3"; shift 3
  local out code=0
  out=$(bash "$0" --guide "$dir" "$@" 2>&1) || code=$?
  if [ "$code" -eq "$want" ]; then
    ok "$label → exit $code"
  else
    bad "$label → exit $code (기대 $want)" "$(printf '%s' "$out" | grep -E '✗|통과 ' | head -3 | tr '\n' ';')"
  fi
}

_fx_build() {
  local fx="$1" b="$1/clean/sample-backend-guide" m
  mkdir -p "$b/resources" || return 1

  cat > "$b/SKILL.md" <<'FXSKILL'
---
name: sample-backend-guide
description: "Self-test fixture backend guide. Use when creating or modifying endpoints, schemas, or tests."
---
<!-- epcc-guide: generated 2026-01-01 stack=none+none+none+none pkgs=zod@4 -->

## Quick Start

### New Endpoint

- [ ] 스키마 확정
- [ ] 핸들러 작성
- [ ] 인증 확인
- [ ] 소유권 필터
- [ ] 에러 매핑
- [ ] 테스트 추가

### New Schema

- [ ] 필드 확정
- [ ] 제약 이중화
- [ ] 마이그레이션
- [ ] 쿼리 갱신
- [ ] 타입 확인
- [ ] 테스트 추가

## Architecture Overview

요청은 핸들러 → 서비스 → 저장소 순으로 흐른다.

## Directory Structure

src/ 아래에 routes/ services/ db/ 를 둔다.

## Core Principles (5 Key Rules)

### 1. 입력은 스키마로 검증한다
핸들러 첫 줄에서 파싱한다.

### 2. 환경변수는 검증된 모듈로만 읽는다
부팅 시점에 실패시킨다.

### 3. 소유권은 쿼리 조건으로 건다
호출자 신뢰 금지.

### 4. 부재와 권한 없음을 구분하지 않는다
존재 누설 금지.

### 5. 에러는 코드표로 매핑한다
상태 코드는 한 곳에서 정한다.

## Common Imports

기본 import 묶음은 resources/a.md 참고.

## HTTP Status Codes & Anti-Patterns

400 · 401 · 404 · 409 · 500 다섯 가지만 쓴다.

## Navigation Guide

| 하려는 일 | 읽을 파일 |
| --- | --- |
| 스키마·환경변수 | `resources/a.md` |
| 부팅과 배선 | `resources/b.md` |
| 핸들러 | `resources/c.md` |
| 에러 처리 | `resources/d.md` |
| 테스트 | `resources/e.md` |
| 운영 | `resources/f.md` |
FXSKILL

  cat > "$b/resources/a.md" <<'FXA'
# 스키마와 환경변수

```ts
import { z } from 'zod'

export const EnvSchema = z.object({
  PORT: z.string(),
  DATABASE_URL: z.string(),
})
```

```ts
export function connect(url) {
  return url
}
```

```ts
// ✅ 계약 밖 응답은 BAD_SHAPE로 만든다 — 표식은 ✅이고 BAD_SHAPE는 계약 식별자다
export function parseShape(v) {
  return v
}
```

`connect`는 b.md의 부팅 경로가 쓴다.
FXA

  cat > "$b/resources/b.md" <<'FXB'
# 부팅

```ts
import { EnvSchema, connect } from '@/a'

export function boot(env) {
  return connect(env.DATABASE_URL)
}
```

`EnvSchema`로 검증한 뒤 `env.PORT`로 listen한다. `boot`는 c.md가 호출한다.
FXB

  printf '# 핸들러\n\n`boot`가 만든 배선을 그대로 쓴다. 응답은 `parseShape`로 검증하고 목록은 `nextCursor`를 담는다.\n' > "$b/resources/c.md"
  printf '# 에러 처리\n\n코드표는 허브에 있다.\n'          > "$b/resources/d.md"
  printf '# 테스트\n\n행복 경로와 검증 실패를 함께 쓴다. 실행은 `npm run test`.\n' > "$b/resources/e.md"
  printf '# 운영\n\n헬스체크는 의존성 확인 뒤에 준비 완료를 알린다.\n' > "$b/resources/f.md"

  cat > "$fx/clean/ledger-ok.md" <<'FXL1'
| 심볼 | 정의 파일 | 소비처 |
| --- | --- | --- |
| `EnvSchema` | a.md | b.md |
| `connect` | a.md | b.md |
| `boot` | b.md | c.md |
| `parseShape` | a.md | c.md |
FXL1
  cat > "$fx/clean/ledger-bad.md" <<'FXL2'
| 심볼 | 정의 파일 | 소비처 |
| --- | --- | --- |
| `EnvSchema` | a.md | b.md |
| `connect` | a.md | b.md |
| `boot` | b.md | d.md |
| `parseShape` | a.md | c.md |
FXL2
  cat > "$fx/clean/ledger-short.md" <<'FXL3'
| 심볼 | 정의 파일 | 소비처 |
| --- | --- | --- |
| `EnvSchema` | a.md | b.md |
| `connect` | a.md | b.md |
FXL3

  for m in dangling envkey dupexport budget fence section nostamp leak; do
    mkdir -p "$fx/$m" && cp -R "$b" "$fx/$m/" || return 1
  done

  printf '| 없는 파일 | `resources/missing.md` |\n' >> "$fx/dangling/sample-backend-guide/SKILL.md"
  printf '\n```ts\nconst timeout = env.REQUEST_TIMEOUT_MS\n```\n' >> "$fx/envkey/sample-backend-guide/resources/b.md"
  printf '\n```ts\nexport function connect(url, options) {\n  return url\n}\n```\n' >> "$fx/dupexport/sample-backend-guide/resources/c.md"
  awk 'BEGIN{ for (i=0; i<310; i++) print "패딩 행 — 예산 초과를 만든다" }' >> "$fx/budget/sample-backend-guide/resources/d.md"
  printf '\n```ts\nconst unclosed = 1\n' >> "$fx/fence/sample-backend-guide/resources/e.md"
  sed -i.bak 's/^## Common Imports$/기본 import 묶음:/' "$fx/section/sample-backend-guide/SKILL.md" && rm -f "$fx/section/sample-backend-guide/SKILL.md.bak"
  sed -i.bak '/epcc-guide: generated/d' "$fx/nostamp/sample-backend-guide/SKILL.md" && rm -f "$fx/nostamp/sample-backend-guide/SKILL.md.bak"
  printf '\n마이그레이션은 prisma migrate로 돌린다.\n' >> "$fx/leak/sample-backend-guide/resources/f.md"
  return 0
}

# ════════════════════════════════════════════════════════════════════
MODE=""; GUIDE=""; LEDGER=""; FORBID=""; PM=""; GENERATED=0
CONTRACT=""; FE=""; BE=""

[ $# -eq 0 ] && { printf "인자 없음 (--help 참조)\n" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --guide)     MODE="guide"; GUIDE="${2:-}"; shift 2 || exit 2 ;;
    --pair)      MODE="pair"; shift ;;
    --self-test) MODE="selftest"; shift ;;
    --contract)  CONTRACT="${2:-}"; shift 2 || exit 2 ;;
    --frontend)  FE="${2:-}"; shift 2 || exit 2 ;;
    --backend)   BE="${2:-}"; shift 2 || exit 2 ;;
    --ledger)    LEDGER="${2:-}"; shift 2 || exit 2 ;;
    --forbid)    FORBID="${2:-}"; shift 2 || exit 2 ;;
    --pm)        PM="${2:-}"; shift 2 || exit 2 ;;
    --generated) GENERATED=1; shift ;;
    -h|--help)   sed -n '2,20p' "$0" | sed -E 's/^#[[:space:]]?//'; exit 0 ;;
    *)           printf "알 수 없는 옵션: %s (--help 참조)\n" "$1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  guide) [ -n "$GUIDE" ] || { printf -- "--guide <디렉토리> 필요\n" >&2; exit 2; }; run_guide "$GUIDE" ;;
  pair)  run_pair ;;
  selftest) run_self_test ;;
  *)     printf "모드 없음: --guide 또는 --pair (--help 참조)\n" >&2; exit 2 ;;
esac

printf "\n${C_D}────────────────────────────────────────────${C_0}\n"
printf "  통과 %s · ${C_Y}WARN %s${C_0} · ${C_C}REVIEW %s${C_0} · ${C_R}FAIL %s${C_0}\n\n" "$PASS" "$WARN" "$REVIEW" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
