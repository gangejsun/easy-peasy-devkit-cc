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
#   guide-gate.sh --pack <팩디렉토리>
#       축 팩을 조립 전에 검사한다. 축 안에서 닫히는 검사만 돌리고, 조합의 함수인
#       것(requires 충족·--pair)은 건너뛴 것을 명시 보고한다.
#   guide-gate.sh --pair --contract <계약파일> --frontend <디렉토리> --backend <디렉토리>
#   guide-gate.sh --self-test   합성 픽스처만 (빠르다 — 하네스를 고칠 때마다 돌린다)
#   guide-gate.sh --regress     + 출하 팩 6개와 사전 제작 이음매 전부를 실제로 검사한다.
#       합성 픽스처는 **미탐**을 잡고 실물은 **오탐**을 잡는다. 느리므로 출하 전에 돌린다.
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
# 출력: <파일>\t<줄번호>\t<본문>\t<펜스ID>
# 4번째 열은 펜스 단위 검사(보안 형태·중복 펜스)를 위한 것이다. 앞 3열은 그대로이므로
# 기존 `cut -f3` 소비처는 영향을 받지 않는다.
codelines() {
  awk '
    # 표식은 ❌/✅ 가 영어 단어보다 우선한다. 단어 판정의 경계에서 _ 와 숫자를 빼야
    # 계약 식별자(BAD_SHAPE·BAD_REQUEST)가 안티패턴 표식으로 오인되지 않는다 —
    # 오인되면 그 지점부터 코드 추출이 꺼져 이후 검사가 조용히 건너뛴다(미탐).
    function isbad(s)  { return (index(s,"❌")>0 || (index(s,"✅")==0 && s ~ /(^|[^A-Za-z0-9_])(Bad|BAD)([^A-Za-z0-9_]|$)/)) }
    function isgood(s) { return (index(s,"✅")>0 || (index(s,"❌")==0 && s ~ /(^|[^A-Za-z0-9_])(Good|GOOD)([^A-Za-z0-9_]|$)/)) }
    function iscomment(s) { return (s ~ /^[[:space:]]*(\/\/|#|\*|\/\*|--)/) }
    FNR==1 { inf=0; pol=1; lastprose=""; fn=0 }
    /^[[:space:]]*```/ { if (!inf) { inf=1; fn++; pol = isbad(lastprose) ? 0 : 1 } else { inf=0 }; next }
    !inf { if ($0 ~ /[^[:space:]]/) lastprose=$0; next }
    iscomment($0) { if (isbad($0)) pol=0; else if (isgood($0)) pol=1; next }
    pol { print FILENAME "\t" FNR "\t" $0 "\t" FILENAME "#" fn }
  ' "$@"
}

# 가이드(SKILL.md)와 축 팩(PACK.md)을 모두 받는다 — --pack 모드가 같은 검사를 재사용한다.
guide_files() { ls "$1/SKILL.md" "$1/PACK.md" "$1"/resources/*.md 2>/dev/null; }

# 프레임워크가 이름을 정하는 export — 서로 다른 라우트에서 시그니처가 갈리는 것이 정상이다
FRAMEWORK_EXPORTS='^(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|default|middleware|config|metadata|generateMetadata|generateStaticParams|loader|action|handler|Component|ErrorBoundary)$'

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
  check_pack_iface "$G"
  check_policies "$G"
  check_security_shapes "$G"
  check_claims "$G"
  check_duplicate_fences "$G"
  check_blocking_proof "$G"
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
    # 배송 스탬프(epcc-pack/epcc-seam)는 내용이 아니라 기계 메타데이터다 — 예산에서 뺀다.
    # 세지 않으면 정확히 300줄인 원본이 팩으로 옮겨지는 것만으로 초과가 된다.
    n=$(num "$(grep -vcE '^<!-- epcc-(pack|seam):' "$f" | tr -d ' ')")
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

  # 값이 `z.string()...` 형태만이 아니라 `ms(60_000)...` 같은 **헬퍼 호출**일 수 있다.
  # 점만 인정하면 헬퍼로 선언한 키가 미선언으로 잡혀 정상 코드가 FAIL한다 (node-api 실측).
  grep -oE '^[[:space:]]*[A-Z][A-Z0-9_]{2,}:[[:space:]]*[A-Za-z_$][A-Za-z0-9_$]*[.(]' "$TMP/code.txt" \
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


# ── 12. 팩 인터페이스: 팩의 requires를 조립본이 충족하는가 ──
# 축 팩과 이음매를 갈라 배송하면 "팩이 쓰는데 이음매가 안 주는 심볼"이 새 결함
# 부류가 된다. 원장의 requires 표가 그 계약이고 이 검사가 그 강제다.
# 종류를 구분한다: 프로젝트=export 필요 · 라이브러리=import에 이름 등장 · 교차축=상대 가이드 소유(건너뜀)
check_pack_iface() {
  local G="$1"
  [ -n "$ASSEMBLY" ] || return 0
  sec "팩 인터페이스 (requires 충족)"
  [ -f "$ASSEMBLY" ] || { bad "assembly.json 없음: $ASSEMBLY"; return; }

  local pack; pack=$(grep -oE '"pack"[[:space:]]*:[[:space:]]*"[^"]+"' "$ASSEMBLY" | sed -E 's/.*"([^"]+)"$/\1/')
  [ -n "$pack" ] || { warn "assembly.json에 pack 항목 없음"; return; }
  local pdir="$PLUGIN_GUIDES/$pack"
  [ -d "$pdir" ] || { bad "팩 디렉토리 없음: $pdir" "--plugin-guides로 경로를 주거나 CLAUDE_PLUGIN_ROOT를 설정한다"; return; }
  local led="$pdir/$PACK_LEDGER_NAME"
  [ -f "$led" ] || { warn "팩 원장 없음: $led"; return; }

  # requires 절의 표만 읽는다 (provides 절과 섞이면 반대로 판정한다)
  awk '/^## requires/{f=1;next} /^## /{f=0} f' "$led" \
    | grep -E '^\|[[:space:]]*`' \
    | awk -F'|' 'NF>=4 { gsub(/`|[[:space:]]/,"",$2); gsub(/[[:space:]]/,"",$3); if ($2!="") print $2"\t"$3 }' \
    > "$TMP/req.tsv"

  local n; n=$(num "$(grep -c . "$TMP/req.tsv" | tr -d ' ')")
  [ "$n" -eq 0 ] && { warn "팩 원장에서 requires 항목을 읽지 못함" "형식: | \`심볼\` | 종류 | 형태 | 이유 |"; return; }

  local sym kind miss=0 skipped=0
  while IFS=$'\t' read -r sym kind; do
    [ -z "$sym" ] && continue
    case "$kind" in
      교차축|cross-axis|생성물|generated)
        skipped=$((skipped+1)); continue ;;
      라이브러리|library)
        if grep -qhE "import[^\n]*\b$sym\b|from '[^']+'" $(guide_files "$G") 2>/dev/null \
           && grep -qhw "$sym" $(guide_files "$G") 2>/dev/null; then :; else
          bad "팩 requires '$sym'(라이브러리) 바인딩이 조립본에 없음"; miss=$((miss+1)); fi ;;
      *)
        if ! grep -hqE "^export[[:space:]]+(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+$sym\b" $(guide_files "$G") 2>/dev/null; then
          bad "팩 requires '$sym'을 이음매가 정의하지 않음" "팩 예제가 실행 불가가 된다 — 이음매가 export하거나 원장에서 종류를 고친다"
          miss=$((miss+1)); fi ;;
    esac
  done < "$TMP/req.tsv"

  [ "$miss" -eq 0 ] && ok "팩 requires ${n}건 충족 (교차축 ${skipped}건 제외)"
}

# ── 13. 정책 원장: 팩이 선언한 파일 간 불변식을 조립본이 지키는가 ──
# 실측(2026-08-22) 감사 57건 중 26건이 "정책을 선언한 곳과 강제하는 곳이 다르고
# 둘을 맞춰볼 의무가 없다"였다. 심볼에는 원장이 있었으나 정책에는 없었다.
# 검사는 codelines() 출력에만 건다 — 산문·주석·안티패턴 예시를 세면 전부 위양성이다.
check_policies() {
  local G="$1"
  [ -n "$ASSEMBLY" ] || return 0
  sec "정책 원장 (팩 불변식)"

  local pack; pack=$(grep -oE '"pack"[[:space:]]*:[[:space:]]*"[^"]+"' "$ASSEMBLY" | sed -E 's/.*"([^"]+)"$/\1/')
  local pol="$PLUGIN_GUIDES/$pack/$PACK_POLICIES_NAME"
  [ -f "$pol" ] || { warn "팩 정책 파일 없음: $pol"; return; }

  # 파싱은 _parse_policies가 단일 소유한다 (두 파서가 갈리면 검사와 증명이 어긋난다).
  _parse_policies "$pol" "$TMP/pol.tsv"

  local n; n=$(num "$(grep -c . "$TMP/pol.tsv" | tr -d ' ')")
  [ "$n" -eq 0 ] && { warn "팩 정책에서 항목을 읽지 못함: $pol"; return; }

  # 팩 소유 파일 목록 (대상=seam 판정에 쓴다)
  local packfiles; packfiles=$(grep -oE '"packFiles"[^]]*\]' "$ASSEMBLY" | grep -oE '"[a-z0-9.-]+\.md"' | tr -d '"' | tr '\n' ' ')

  local id verdict scope rx except ex has viol=0 pass=0 targets f base hits
  while IFS=$'\t' read -r id verdict scope rx except ex has; do
    [ -z "$id" ] && continue
    # 대상 범위를 파일 목록으로 환원한다
    targets=""
    for f in $(guide_files "$G"); do
      base=$(basename "$f")
      case "$scope" in
        seam)  case " $packfiles " in *" $base "*) continue;; esac ;;
        pack)  case " $packfiles " in *" $base "*) ;; *) continue;; esac ;;
        file:*) [ "$base" = "${scope#file:}" ] || continue ;;
      esac
      case "$except" in ""|"—"|"-") ;; *)
        case ",$(printf '%s' "$except" | tr -d ' '),"  in *",$base,"*) continue;; esac ;;
      esac
      targets="$targets $f"
    done
    [ -z "$targets" ] && { rev "정책 '$id' 대상 파일 0개" "scope=$scope 예외=$except — 범위를 확인한다"; continue; }

    # shellcheck disable=SC2086
    hits=$(codelines $targets | cut -f3 | grep -cE "$rx" 2>/dev/null || true)
    hits=$(num "$hits")
    if [ "$verdict" = "forbid" ]; then
      if [ "$hits" -gt 0 ]; then
        # shellcheck disable=SC2086
        bad "정책 위반 '$id' — 금지 패턴 ${hits}건" "$(codelines $targets | grep -E "$rx" | head -2 | awk -F'\t' '{printf "%s:%s ", substr($1,match($1,/[^\/]*$/)), $2}')"
        viol=$((viol+1))
      else pass=$((pass+1)); fi
    else
      if [ "$hits" -eq 0 ]; then
        bad "정책 위반 '$id' — 필수 패턴이 조립본에 없음" "정규식: $rx"
        viol=$((viol+1))
      else pass=$((pass+1)); fi
    fi
  done < "$TMP/pol.tsv"

  [ "$viol" -eq 0 ] && ok "팩 정책 ${pass}건 통과"

  check_policy_proof "$G" "$pol" "$packfiles"
}

# ── 공용: 정책 표 파싱 ──────────────────────────────────────────────
# | id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
# 출력: id \t 판정 \t 대상 \t 정규식 \t 예외 \t 증명예 \t 증명예열있음(0/1)
# 정규식 안의 \| 는 마크다운 표의 이스케이프다 — 열 구분보다 먼저 보호한다.
_parse_policies() {
  awk '/^## 기계 검사/{f=1;next} /^## /{f=0} f' "$1" \
    | grep -E '^\|[[:space:]]*`' \
    | sed 's/\\|/\x01/g' \
    | awk -F'|' 'NF>=7 {
        for(i=2;i<=7;i++){ gsub(/^[[:space:]]+|[[:space:]]+$/,"",$i); gsub(/`/,"",$i); gsub(/\x01/,"|",$i) }
        # 대상(scope) 열만 마크다운 강조를 벗긴다. 정규식·증명 예의 * 는 의미가 있으므로 건드리지 않는다.
        # 실측: vue 팩이 대상을 **seam**으로 적어 게이트가 scope를 인식하지 못했고,
        # 감사가 지시한 "이음매를 겨눈다"는 수리가 조용히 무효였다.
        gsub(/[*_]/,"",$4)
        ex = (NF>=9) ? $7 : ""; has = (NF>=9) ? 1 : 0
        if ($2!="") print $2"\t"$3"\t"$4"\t"$5"\t"$6"\t"ex"\t"has }' > "$2"
}

# 정책 1건의 대상 파일 목록. packfiles가 비면 scope=seam은 대상 0개가 된다.
_policy_targets() {
  local G="$1" scope="$2" except="$3" packfiles="$4" f base out=""
  for f in $(guide_files "$G"); do
    base=$(basename "$f")
    case "$scope" in
      seam)  case " $packfiles " in *" $base "*) continue;; esac ;;
      pack)  case " $packfiles " in *" $base "*) ;; *) continue;; esac ;;
      file:*) [ "$base" = "${scope#file:}" ] || continue ;;
    esac
    case "$except" in ""|"—"|"-") ;; *)
      case ",$(printf '%s' "$except" | tr -d ' ')," in *",$base,"*) continue;; esac ;;
    esac
    out="$out $f"
  done
  printf '%s' "$out"
}

# ── 14. 정책 차단 증명 (증명 예 열) ─────────────────────────────────
# 실측(2026-08-23) vue 팩 저작의 벽시계를 지배한 것이 "정책마다 결함 픽스처를 만들어
# 실제로 잡히는지 돌리기"였다. 그 왕복을 표의 한 열 + 여기의 단언으로 바꾼다.
#   ① 증명 예가 자기 정규식에 매치되는가 (아니면 죽은 정규식이다)
#   ② forbid면 그 예가 대상 파일에 실재하지 않는가 (실재하면 자기 정책을 어긴 것)
# 판정이 저자의 기억에서 게이트의 상시 단언으로 올라간다.
check_policy_proof() {
  local G="$1" pol="$2" packfiles="${3:-}"
  sec "정책 차단 증명 (증명 예)"
  [ -f "$pol" ] || { warn "정책 파일 없음: $pol"; return 0; }
  _parse_policies "$pol" "$TMP/polproof.tsv"
  local n; n=$(num "$(grep -c . "$TMP/polproof.tsv" | tr -d ' ')")
  [ "$n" -eq 0 ] && { warn "정책에서 항목을 읽지 못함: $pol" "형식: | id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |"; return 0; }

  local id verdict scope rx except ex has viol=0 pass=0 skip=0 targets
  while IFS=$'\t' read -r id verdict scope rx except ex has; do
    [ -z "$id" ] && continue
    if [ "$has" != "1" ] || [ -z "$ex" ] || [ "$ex" = "—" ] || [ "$ex" = "-" ]; then
      bad "정책 '$id' — 증명 예 없음" "차단 증명이 저자의 기억에만 남는다. 표에 '증명 예' 열을 채운다"
      viol=$((viol+1)); continue
    fi
    if ! printf '%s\n' "$ex" | grep -qE "$rx" 2>/dev/null; then
      bad "정책 '$id' — 증명 예가 자기 정규식에 안 잡힌다" "예: $ex  ·  정규식: $rx — 죽은 정규식이거나 예가 틀렸다"
      viol=$((viol+1)); continue
    fi
    if [ "$verdict" = "forbid" ]; then
      targets=$(_policy_targets "$G" "$scope" "$except" "$packfiles")
      if [ -z "$targets" ]; then skip=$((skip+1)); pass=$((pass+1)); continue; fi
      # shellcheck disable=SC2086
      if codelines $targets | cut -f3 | grep -qF -- "$ex" 2>/dev/null; then
        bad "정책 '$id' — 증명 예가 본문에 실재한다" "금지 패턴의 예가 코드 행에 있다 = 자기 정책을 어겼다"
        viol=$((viol+1)); continue
      fi
    fi
    pass=$((pass+1))
  done < "$TMP/polproof.tsv"
  [ "$viol" -eq 0 ] && ok "정책 ${pass}건 차단 증명 통과 (대상 0개로 건너뛴 실재 검사 ${skip}건)"
  return 0
}

# ── 15. 보안 형태: 재발 형태 차단 ───────────────────────────────────
# 팩별 정책이 아니라 축 무관 형태다 — 그래서 policies.md가 아니라 게이트가 소유한다.
# 실측(2026-08-23): safeReturnTo의 origin 검사가 `/..//evil.example`에 뚫렸다.
# new URL()이 origin을 통과시킨 뒤 점 세그먼트를 정규화해 `/..`가 선행 `/`를 삼킨다.
# 출하본 네 곳 전부 4/4 벡터가 통과했다. 발명하지 않는다 — 실측이 찾은 두 형태만 본다.
check_security_shapes() {
  local G="$1"
  sec "보안 형태 (재발 차단)"
  local files; files=$(guide_files "$G")
  [ -n "$files" ] || return 0

  cat > "$TMP/sec.awk" <<'AWKSEC'
BEGIN { FS = "\t" }
{ t[$4] = t[$4] "\n" $3; if (!($4 in loc)) loc[$4] = $1 ":" $2 }
END {
  for (k in t) {
    s = t[k]
    hasURL   = (index(s, "new URL(") > 0)
    hasOrig  = (s ~ /\.origin[[:space:]]*[!=]==/ || s ~ /[!=]==[[:space:]]*[A-Za-z0-9_.]*\.origin/)
    hasPath  = (index(s, "pathname") > 0)
    hasSlash = (index(s, "'//'") > 0 || index(s, "\"//\"") > 0)
    if (hasURL && hasOrig && !(hasPath && hasSlash))
      print "origin-only-redirect\t" loc[k]
    hasSW    = (s ~ /startsWith\('\/'\)/ || s ~ /startsWith\("\/"\)/)
    hasRedir = (s ~ /returnTo|redirectTo|returnPath|callbackUrl|safeReturn|safeInternal/)
    if (hasSW && hasRedir && !hasSlash)
      print "prefix-only-redirect\t" loc[k]
  }
}
AWKSEC

  # shellcheck disable=SC2086
  codelines $files | awk -f "$TMP/sec.awk" | sort -u > "$TMP/secshape.txt"

  # ③ 요청에서 온 값으로 리다이렉트하라는 **지시**. 이 형태는 산문·표에 실리므로
  # 펜스만 보면 놓친다 (node-api 실측: 오용 대조표의 '현재 형태' 칸이 검증 없이
  # `req.get('Referer')`를 읽으라고 했고, 실행에서 javascript:·절대 URL이 전부 통과했다).
  # 이 저장소에서 오픈 리다이렉트는 이번이 세 번째다 — 좁게 걸되 기계로 건다.
  # `searchParams.set('redirect', …)`처럼 값을 **싣는** 방향은 `redirect(`가 없어 걸리지 않는다.
  # shellcheck disable=SC2086
  grep -nE 'redirect\(' $files 2>/dev/null \
    | grep -E 'Referer|req\.get\(|req\.query|req\.body|req\.headers|searchParams\.get\(|location\.search' \
    | grep -vE 'safe[A-Za-z]*\(|allowlist|허용목록|\.origin' \
    | sed -E 's/^([^:]*):([0-9]+):.*/request-derived-redirect\t\1:\2/' | sort -u >> "$TMP/secshape.txt"

  local shape where n=0
  while IFS=$'\t' read -r shape where; do
    [ -z "$shape" ] && continue
    n=$((n+1))
    case "$shape" in
      origin-only-redirect)
        bad "복귀 경로를 origin 비교만으로 판정 ($(basename "$where"))" \
            "new URL()이 origin을 통과시킨 뒤 점 세그먼트를 정규화한다 — '/..//host'가 '//host'가 된다. 출력 pathname을 검증하라" ;;
      prefix-only-redirect)
        bad "복귀 경로를 startsWith('/')만으로 판정 ($(basename "$where"))" \
            "'//host'·'/\\host'는 브라우저에서 외부 URL로 파싱된다 — 문자열 prefix 검사로는 막히지 않는다" ;;
      request-derived-redirect)
        bad "요청에서 온 값으로 리다이렉트 ($(basename "$where"))" \
            "Referer·쿼리·본문은 공격자가 정한다 — 절대 URL·javascript:·프로토콜 상대가 그대로 통과한다. 검증 함수를 통과시키거나 허용목록을 쓴다" ;;
    esac
  done < "$TMP/secshape.txt"
  [ "$n" -eq 0 ] && ok "알려진 취약 형태 없음"
  return 0
}

# ── 16. 버전 주장 인벤토리 ──────────────────────────────────────────
# 감사자에게 넘기는 "버전 주장 목록"을 지금은 손으로 만든다. 게이트가 산문에서 전수
# 수집한다. 실측(2026-08-23)에서 이 부류 5건이 거짓이었고, 잘못 확신한 지식은 생성
# 규율로 막을 수 없다 — 감사의 고유 영역이므로 목록을 정확히 넘기는 것이 일이다.
# FAIL이 아니라 WARN인 이유: 산문 정규식은 위양성을 낸다. 목록 자동화가 목적이다.
check_claims() {
  local G="$1"
  sec "버전 주장 인벤토리"
  local files; files=$(guide_files "$G")
  [ -n "$files" ] || return 0

  cat > "$TMP/claims.awk" <<'AWKCLAIM'
BEGIN { FS = "\n" }
FNR == 1 { inf = 0; prev = "" }
/^[[:space:]]*```/ { inf = !inf; prev = ""; next }
inf { next }
{
  line = $0
  if (line !~ /[^[:space:]]/) { prev = ""; next }
  claim = 0
  if (line ~ /[Vv][0-9]+(\.[0-9]+)*[[:space:]]*(에서|부터|이후|이상|미만)/) claim = 1
  if (line ~ /이제는|이제 더|더 이상|더는|이전 버전|구버전|폐기(됐|되|된)/) claim = 1
  if (line ~ /deprecated|Deprecated|no longer|was added in|since v[0-9]|removed in/) claim = 1
  if (line ~ /버전(부터|에서)|메이저(부터|에서)/) claim = 1
  # 한국어 실행 단정 마커. 저자가 태그 대신 산문으로 "실행 확인"이라 쓰면 태그 스캔이
  # 놓치는데, **거짓 주장이 정확히 그 사각지대에 몰려 있었다** (node-api 감사 B: 거짓
  # 4건 중 3건이 미태그 "(실행 확인)" 블록). 태그 규율이 도달하지 못한 곳만 살아남았다.
  if (line ~ /실행 확인|실행으로 확인|차단 확인|타입 확인|계측했|재현했/) claim = 1
  # 저자가 단 태그 자체가 주장 선언이다 — 문구 스캔이 놓친 것을 이것이 건진다.
  # 태그만 보고 인벤토리에서 빼면 전부 태그된 팩에서 감사 B가 빈손이 된다.
  tagged = 0
  if (line ~ /<!--[[:space:]]*(un)?verified/) { tagged = 1; claim = 1 }
  # 앞 줄 귀속은 **그 줄이 태그만 있는 독립 주석일 때만** 인정한다. 내용이 함께 있는
  # 줄(표 행 안의 인라인 태그 등)에서 귀속을 허용하면 태그 하나가 뒤따르는 표 행 전부를
  # '태그됨'으로 덮어 미태그 주장이 검사를 통과하면서 검사를 피한다 (감사 B 지적).
  else if (prev ~ /^[[:space:]]*<!--[^>]*(un)?verified[^>]*-->[[:space:]]*$/) { tagged = 1; claim = 1 }
  if (!claim) { prev = line; next }
  print (tagged ? "T" : "U") "\t" FILENAME ":" FNR "\t" substr(line, 1, 120)
  prev = line
}
AWKCLAIM

  # shellcheck disable=SC2086
  awk -f "$TMP/claims.awk" $files > "$TMP/claims.tsv" 2>/dev/null

  local tot unt
  tot=$(num "$(grep -c . "$TMP/claims.tsv" | tr -d ' ')")
  unt=$(num "$(grep -c '^U' "$TMP/claims.tsv" | tr -d ' ')")
  if [ "$tot" -eq 0 ]; then ok "버전 주장 없음"; return 0; fi

  if [ "$unt" -gt 0 ]; then
    warn "태그 없는 버전 주장 ${unt}건 (전체 ${tot}건)" "<!-- verified: 근거 --> 또는 <!-- unverified -->로 표시하면 통과한다"
  else
    ok "버전 주장 ${tot}건 전부 태그됨"
  fi

  # 인벤토리는 태그 여부와 무관하게 **전수 출력**한다 — 감사 B의 입력이 이것이고,
  # 태그된 항목이야말로 판정 대상이다(태그는 "주장했다"는 선언이지 "참"이라는 증명이 아니다).
  # 태그 없는 것만 찍으면 전부 태그된 팩에서 감사 B가 빈손이 된다 (node-api 실측).
  printf "      ${C_D}── 버전 주장 인벤토리 %s건 (감사 B 입력) ──${C_0}\n" "$tot"
  local st loc txt shown=0
  while IFS=$'\t' read -r st loc txt; do
    [ -z "$loc" ] && continue
    shown=$((shown+1))
    [ "$shown" -le 40 ] && printf "      ${C_D}[%s] %s${C_0}  %s\n" "$st" "$loc" "$txt"
  done < "$TMP/claims.tsv"
  [ "$shown" -gt 40 ] && printf "      ${C_D}… 그 외 %s건은 %s 에서 읽는다 (생략 아님)${C_0}\n" "$((shown-40))" "$TMP/claims.tsv"
  return 0
}

# ── 17. 중복 펜스: 병렬 저작이 만드는 중복 서술 ─────────────────────
# 원장은 심볼만 추적하고 서술은 보지 않는다. 클러스터를 갈라 저작하면 같은 코드 예시를
# 각자 쓰게 되고, 300줄 예산을 갉아먹은 뒤 둘이 갈라지면 자기모순이 된다.
# FAIL이 아니라 REVIEW인 이유: 정당한 반복이 있다(공통 import 블록, 안티패턴과 수리형).
check_duplicate_fences() {
  local G="$1"
  sec "중복 펜스 (파일 간 같은 코드)"
  local files; files=$(guide_files "$G")
  [ -n "$files" ] || return 0

  # shellcheck disable=SC2086
  codelines $files | awk -F'\t' '
    { line=$3
      gsub(/^[[:space:]]+|[[:space:]]+$/,"",line); gsub(/[[:space:]]+/," ",line)
      if (line=="") next
      t[$4]=t[$4] line "\002"; c[$4]++; f[$4]=$1; if (!($4 in l)) l[$4]=$2 }
    END { for (k in t) if (c[k]>=3) print f[k] ":" l[k] "\t" t[k] }' \
    | sort -t"$(printf '\t')" -k2 > "$TMP/fences.tsv"

  awk -F'\t' '$2==p && $1!=pf { print pf " ↔ " $1 } { p=$2; pf=$1 }' "$TMP/fences.tsv" \
    | sed -E 's#[^ ]*/([^/ ]+)#\1#g' | sort -u > "$TMP/dupfence.txt"

  local n; n=$(num "$(grep -c . "$TMP/dupfence.txt" | tr -d ' ')")
  if [ "$n" -gt 0 ]; then
    rev "파일 간 동일 코드펜스 ${n}쌍" "$(head -4 "$TMP/dupfence.txt" | tr '\n' ';') — 정당한 반복(공통 import·안티패턴 쌍)이면 통과, 아니면 한 곳으로 모은다"
  else
    ok "파일 간 중복 코드펜스 없음"
  fi
  return 0
}

# ── 17-B. 차단 증명 없는 테스트 ─────────────────────────────────────
# 실측(2026-08-23): 팩이 「이 축에서 가장 비싼 테스트」로 제시한 소유권 회귀 테스트가
# 부정 단언(404)만 걸어, 쿼리 함수를 통째로 `return null`로 바꿔도 초록이었다.
# **차단 장치가 차단을 증명하지 못한다** — 이 저장소가 자기 게이트에 적용하는 규범을
# 팩의 테스트가 어긴 것이다. 기계가 의미를 판정할 수 없으므로 REVIEW다.
check_blocking_proof() {
  local G="$1"
  sec "테스트의 차단 증명"
  local files; files=$(guide_files "$G")
  [ -n "$files" ] || return 0

  # 테스트 코드가 있는 파일만 본다
  # shellcheck disable=SC2086
  codelines $files | awk -F'\t' '$3 ~ /(^|[^A-Za-z])(it|test)\(/ {print $1}' | sort -u > "$TMP/testfiles.txt"
  local n; n=$(num "$(grep -c . "$TMP/testfiles.txt" | tr -d ' ')")
  [ "$n" -eq 0 ] && { ok "테스트 코드 없음 — 해당 없음"; return 0; }

  local f neg pos base hit=0
  while read -r f; do
    [ -z "$f" ] && continue
    base=$(basename "$f")
    neg=$(num "$(codelines "$f" | cut -f3 | grep -cE 'toBe\((40[0-9]|41[0-9]|42[0-9]|50[0-9])\)|status\).toBe\(4' 2>/dev/null || true)")
    pos=$(num "$(codelines "$f" | cut -f3 | grep -cE 'toBe\(20[0-9]\)' 2>/dev/null || true)")
    if [ "$neg" -gt 0 ] && [ "$pos" -eq 0 ]; then
      rev "$base — 실패 단언 ${neg}건, 성공 단언 0건" \
          "구현을 통째로 실패시켜도 통과하는 테스트다. 긍정 경로를 짝으로 걸어야 차단이 증명된다"
      hit=$((hit+1))
    fi
  done < "$TMP/testfiles.txt"
  [ "$hit" -eq 0 ] && ok "테스트 ${n}파일 — 긍정·부정 짝 확인"
  return 0
}

# ── 18. 팩 메타: pack.json ↔ 실파일 ↔ fixesVariants ─────────────────
# 축 팩은 프레임워크·ORM 같은 변형을 못박는데, 지금까지 그것을 선언하지 않았고 조립
# 시점에 대조하지도 않았다. NestJS를 고른 프로젝트가 Express 팩을 받으면 없는 것을
# 받는 게 아니라 **틀린 것**을 받는다. fixesVariants가 그 선언이고 여기가 그 정합 검사다.
check_pack_meta() {
  local P="$1" j="$1/pack.json"
  sec "팩 메타 (pack.json)"
  [ -f "$j" ] || { bad "pack.json 없음: $j"; return 0; }

  local nm ax
  nm=$(grep -m1 -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+"' "$j" | sed -E 's/.*"([^"]+)"$/\1/')
  ax=$(grep -m1 -oE '"axis"[[:space:]]*:[[:space:]]*"[^"]+"' "$j" | sed -E 's/.*"([^"]+)"$/\1/')
  [ "$nm" = "$(basename "$P")" ] && ok "name = 디렉토리명 ($nm)" || bad "pack.json name '$nm' ≠ 디렉토리 '$(basename "$P")'"
  case "$ax" in frontend|backend) ok "axis = $ax";; *) bad "axis가 frontend/backend가 아님: '$ax'";; esac

  # resources[] ↔ 실파일 차집합
  grep -oE '"file"[[:space:]]*:[[:space:]]*"[^"]+"' "$j" | sed -E 's/.*"([^"]+)"$/\1/' | sort -u > "$TMP/pjres.txt"
  ls "$P"/resources/*.md 2>/dev/null | while read -r f; do basename "$f"; done | sort -u > "$TMP/realres.txt"
  local miss ghost
  miss=$(comm -13 "$TMP/pjres.txt" "$TMP/realres.txt" | tr '\n' ' ')
  ghost=$(comm -23 "$TMP/pjres.txt" "$TMP/realres.txt" | tr '\n' ' ')
  [ -n "$(printf '%s' "$miss" | tr -d ' ')" ] && bad "pack.json resources[]에 없는 실파일: $miss" "Navigation Guide 행이 생기지 않아 조립본에서 도달 불가가 된다"
  [ -n "$(printf '%s' "$ghost" | tr -d ' ')" ] && bad "pack.json resources[]가 없는 파일을 가리킴: $ghost"
  [ -z "$(printf '%s%s' "$miss" "$ghost" | tr -d ' ')" ] && ok "resources[] $(num "$(wc -l < "$TMP/pjres.txt")")개 ↔ 실파일 일치"

  # exampleDomain — 도메인 어휘 고정 (병렬 저작의 어휘 분기를 막는 계약)
  grep -q '"exampleDomain"' "$j" && ok "exampleDomain 선언됨" || bad "exampleDomain 없음" "도메인 어휘가 고정되지 않으면 파일마다 다른 리소스 이름을 쓴다 (실측: /tasks ↔ /notes)"

  # fixesVariants — 못박은 변형 선언 (없으면 {}를 명시한다)
  if ! grep -q '"fixesVariants"' "$j"; then
    bad "fixesVariants 선언 없음" "팩이 못박은 프레임워크·ORM을 선언하지 않으면 조립 시점에 대조할 수 없다. 못박은 게 없으면 {}를 명시한다"
    return 0
  fi
  local pkgs; pkgs=$(tr -d '\n' < "$j" | grep -oE '"pkgs"[[:space:]]*:[[:space:]]*\[[^]]*\]' | tr 'A-Z' 'a-z')
  local fv; fv=$(tr -d '\n' < "$j" | grep -oE '"fixesVariants"[[:space:]]*:[[:space:]]*\{[^}]*\}')
  local pairs; pairs=$(printf '%s' "$fv" | grep -oE '"[A-Za-z]+"[[:space:]]*:[[:space:]]*"[^"]+"' | sed -E 's/"([A-Za-z]+)"[[:space:]]*:[[:space:]]*"([^"]+)"/\1\t\2/')
  if [ -z "$pairs" ]; then ok "fixesVariants 비어 있음 (못박은 변형 없음을 명시)"; return 0; fi

  # 상호 배타 제품군 — 선언한 값의 경쟁 제품이 pkgs에 있으면 선언이 거짓이다
  cat > "$TMP/variants.tsv" <<'VARTBL'
framework	express	express
framework	hono	hono
framework	fastify	fastify
framework	koa	koa
framework	nestjs	@nestjs/
orm	prisma	prisma
orm	drizzle	drizzle-orm,drizzle-kit
orm	sequelize	sequelize
orm	typeorm	typeorm
orm	knex	knex
store	pinia	pinia
store	vuex	vuex
store	zustand	zustand
store	redux	@reduxjs/
store	jotai	jotai
query	vue-query	@tanstack/vue-query
query	react-query	@tanstack/react-query
query	swr	swr
query	apollo	@apollo/
VARTBL

  local dim val grp prod toks t mine="" hit=0 n=0
  while IFS=$'\t' read -r dim val; do
    [ -z "$val" ] && continue
    n=$((n+1))
    local lval; lval=$(printf '%s' "$val" | tr 'A-Z' 'a-z')
    # 선언 값이 어느 제품인가
    mine=""; grp=""
    while IFS=$'\t' read -r g prod toks; do
      for t in $(printf '%s' "$toks" | tr ',' ' '); do
        case "$lval" in *"$t"*) mine="$prod"; grp="$g";; esac
        [ "$lval" = "$prod" ] && { mine="$prod"; grp="$g"; }
      done
    done < "$TMP/variants.tsv"
    if [ -z "$mine" ]; then
      printf '%s' "$pkgs" | grep -qF "$lval" && ok "fixesVariants.$dim = $val (pkgs에 등장)" \
        || warn "fixesVariants.$dim = '$val' — pkgs에서 확인 불가" "알려진 제품군이 아니고 패키지 목록에도 없다. 오타이거나 선언이 낡았다"
      continue
    fi
    # 같은 군의 다른 제품이 pkgs에 있으면 모순
    while IFS=$'\t' read -r g prod toks; do
      [ "$g" = "$grp" ] || continue
      [ "$prod" = "$mine" ] && continue
      for t in $(printf '%s' "$toks" | tr ',' ' '); do
        if printf '%s' "$pkgs" | grep -qF "$t"; then
          bad "fixesVariants.$dim = '$val'인데 pkgs에 경쟁 제품 '$t'" "선언과 실물이 모순이다 — 조립 시점 대조가 거짓 통과한다"
          hit=$((hit+1))
        fi
      done
    done < "$TMP/variants.tsv"
  done <<EOF
$pairs
EOF
  [ "$hit" -eq 0 ] && ok "fixesVariants ${n}건 ↔ pkgs 모순 없음"
  return 0
}

# ── 19. 팩 원장: provides 정의 대조 ─────────────────────────────────
# 조립 전에는 requires를 검사할 수 없다(이음매가 아직 없다). provides는 축 안에서
# 닫히므로 지금 검사할 수 있고, 병렬 저작의 팬인 지점이 바로 여기다 —
# L0가 배정한 정의 파일에 실제로 정의가 들어갔는지 확인한다.
check_pack_ledger() {
  local P="$1" led="$1/ledger.md"
  sec "팩 원장 (provides 배정 대조)"
  [ -f "$led" ] || { bad "팩 원장 없음: $led"; return 0; }

  # provides 표는 4열이다: | 심볼 | 정의 파일 | 형태 | 성격 |
  # 「형태」가 없으면 형제 클러스터가 시그니처를 **추측한다** — 실측(2026-08-23)에서
  # getTask(ownerId, id)를 다른 클러스터가 getTask(id, ownerId)로 불렀고 두 인자가 모두
  # string이라 TypeScript도 이 게이트도 잡지 못했다. 치명 결함 2건의 단일 원인이다.
  # 형태 셀에는 유니온·제네릭 때문에 이스케이프한 `\|`가 흔하다. 열 구분보다 먼저
  # 보호하지 않으면 형태가 잘리고 인자 개수 대조가 엉뚱한 값을 본다 (정책 표와 같은 함정).
  awk '/^## provides/{f=1;next} /^## /{f=0} f' "$led" \
    | grep -E '^\|[[:space:]]*`' \
    | sed 's/\\|/\x01/g' \
    | awk -F'|' 'NF>=4 { gsub(/[[:space:]]/,"",$3); shape=(NF>=6)?$4:""
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",shape); gsub(/\x01/,"|",shape)
        print $2"\t"$3"\t"shape }' > "$TMP/prov.raw"

  # 한 행에 여러 심볼(`a` · `b`)이 오는 관용구가 실재한다 — 분해한다
  : > "$TMP/prov.tsv"
  local syms deff shape s noshape=0
  while IFS=$'\t' read -r syms deff shape; do
    [ -z "$syms" ] && continue
    case "$shape" in ""|"—"|"-") noshape=$((noshape+1)); shape="";; esac
    for s in $(printf '%s' "$syms" | tr -d ' ' | tr '`' ' ' | tr '·' ' '); do
      [ -z "$s" ] && continue
      printf '%s\t%s\t%s\n' "$s" "$deff" "$shape" >> "$TMP/prov.tsv"
    done
  done < "$TMP/prov.raw"

  if [ "$noshape" -gt 0 ]; then
    bad "provides 「형태」 열이 빈 행 ${noshape}건" \
        "소유 파일만 배정하고 형태를 비우면 형제 클러스터가 시그니처를 추측한다. 인자 순서·반환·실패 시 던지는 것·호출자가 배선할 것을 적는다"
  else
    ok "provides 전 행에 형태 선언됨"
  fi

  local rows; rows=$(num "$(grep -c . "$TMP/prov.tsv" | tr -d ' ')")
  if [ "$rows" -eq 0 ]; then
    warn "팩 원장 provides가 비었음" "패턴 지식형 팩(export 0개)이면 정상이다 — pack.json의 symbolSurface로 선언한다"
    return 0
  fi

  local n_def=0 rf declared actual
  while IFS=$'\t' read -r s deff shape; do
    [ -z "$s" ] && continue
    rf=$(_resolve "$P" "$deff")
    if [ -z "$rf" ]; then bad "팩 원장 '$s'의 정의 파일이 실재하지 않음: $deff"; n_def=$((n_def+1)); continue; fi
    codelines "$rf" | cut -f3 | grep -qE "(export[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+$s\b" \
      || { bad "팩 원장 '$s'의 정의가 $(basename "$rf")에 없음" "L0가 배정한 소유 파일에 정의가 들어가지 않았다 — 넣거나 원장을 고친다"; n_def=$((n_def+1)); continue; }

    # 형태가 호출 시그니처를 선언했으면 실제 정의의 인자 개수와 대조한다.
    # 이름 순서까지는 기계가 못 보지만 **개수 불일치는 잡는다** — 형태를 적어 놓고
    # 정의를 다르게 쓰면 소비자가 원장을 믿고 틀린 호출을 쓴다.
    local bare; bare=$(printf '%s' "$shape" | tr -d '`')
    declared=$(printf '%s' "$bare" | sed -nE "s/^$s\(([^)]*)\).*/\1/p" | head -1)
    if printf '%s' "$bare" | grep -qE "^$s\("; then
      local dn=0
      [ -n "$(printf '%s' "$declared" | tr -d ' ')" ] && dn=$(printf '%s' "$declared" | awk -F',' '{print NF}')
      actual=$(awk -F'\t' -v n="$s" '$1==n {print $2; exit}' "$TMP/defs.tsv")
      if [ -n "$actual" ] && [ "$dn" -ne "$(num "$actual")" ]; then
        bad "원장 '$s'의 형태는 인자 ${dn}개인데 정의는 $(num "$actual")개" \
            "$(basename "$rf") — 소비자는 원장을 믿는다. 둘 중 하나가 틀렸다"
        n_def=$((n_def+1))
      fi
    fi
  done < "$TMP/prov.tsv"

  cut -f1 "$TMP/prov.tsv" | sort -u > "$TMP/provsym.txt"

  # requires로 선언한 심볼을 팩이 스스로 export하면 자기모순이다 — 이음매가 소유한다고
  # 해놓고 자기가 정의한 것이므로, 조립 후 같은 이름이 두 곳에서 정의된다.
  # (실측: react-vite 팩이 useTasksQuery를 requires에 두고 PACK.md에서 export했다)
  awk '/^## requires/{f=1;next} /^## /{f=0} f' "$led" \
    | grep -E '^\|[[:space:]]*`' \
    | awk -F'|' 'NF>=4 { gsub(/`|[[:space:]]/,"",$2); if ($2!="") print $2 }' | sort -u > "$TMP/reqsym.txt"
  # requires 심볼을 **팩이 호출하면서** 형태에 시그니처를 적지 않으면, 이음매는 인자
  # 순서를 추측한다. 실측(2026-08-23): react-vite가 `ApiError(500, 'BAD_SHAPE', msg)`로
  # 부르는데 형태에는 필드 목록만 있었다 — 뒤 두 인자가 모두 string이라 뒤바꿔도
  # TypeScript가 잡지 못한다. provides의 「형태」 열과 같은 구멍이 requires에 남아 있었다.
  awk '/^## requires/{f=1;next} /^## /{f=0} f' "$led" \
    | grep -E '^\|[[:space:]]*`' | sed 's/\\|/\x01/g' \
    | awk -F'|' 'NF>=4 { gsub(/`|[[:space:]]/,"",$2); sh=$4
        gsub(/^[[:space:]]+|[[:space:]]+$/,"",sh); gsub(/\x01/,"|",sh)
        if ($2!="") print $2"\t"sh }' > "$TMP/reqshape.tsv"

  local rsym rshape nosig=0
  while IFS=$'\t' read -r rsym rshape; do
    [ -z "$rsym" ] && continue
    # 팩이 이 심볼을 호출하는가. 산문은 codelines()가 이미 제외했고, **꼬리 주석**도
    # 뗀다 — `// ✅ 라우터 → notFound → errorHandler(4인자)`가 호출로 잡히던 오탐이다.
    sed 's/[[:space:]]\/\/.*$//' "$TMP/code.txt" > "$TMP/code.nocomment.txt"
    grep -qE "(^|[^A-Za-z0-9_.\$])(new[[:space:]]+)?$rsym\(" "$TMP/code.nocomment.txt" 2>/dev/null || continue
    printf '%s' "$rshape" | grep -qF "$rsym(" && continue
    bad "requires '$rsym'을 호출하면서 형태에 시그니처가 없음" \
        "이음매가 인자 순서를 추측한다. 같은 타입 인자가 둘 이상이면 뒤바꿔도 타입이 통과한다 — 형태에 \`$rsym(...)\`를 적는다"
    nosig=$((nosig+1))
  done < "$TMP/reqshape.tsv"
  [ "$nosig" -eq 0 ] && ok "호출하는 requires 심볼 전부 시그니처 선언됨"

  local both; both=$(comm -12 "$TMP/exports.txt" "$TMP/reqsym.txt" | tr '\n' ' ')
  if [ -n "$(printf '%s' "$both" | tr -d ' ')" ]; then
    bad "requires로 선언한 심볼을 팩이 스스로 export함:$both" \
        "이음매가 소유한다고 해놓고 자기가 정의했다 — 조립 후 정의가 둘이 된다. 예시라면 requires에서 빼거나 예시임을 원장에 명시한다"
  else
    ok "requires ↔ export 충돌 없음"
  fi

  # 예제 전용 심볼은 원장의 '예제' 절에 선언한다 (vue 팩의 관용구).
  # 예시 컴포넌트인지 실제 모듈인지는 기계가 판정할 수 없으므로 REVIEW다 —
  # FAIL로 만들면 저자가 예시를 provides에 밀어 넣게 되고 그것이 더 나쁘다.
  awk '/^## .*예제/{f=1;next} /^## /{f=0} f' "$led" \
    | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`' | sort -u > "$TMP/exsym.txt"
  cat "$TMP/provsym.txt" "$TMP/exsym.txt" | sort -u > "$TMP/declared.txt"
  local unreg; unreg=$(comm -23 "$TMP/exports.txt" "$TMP/declared.txt" | tr '\n' ' ')
  if [ -n "$(printf '%s' "$unreg" | tr -d ' ')" ]; then
    rev "원장에 없는 export 심볼:$unreg" "배정 밖 심볼이다 — provides에 올리거나, 예시면 원장의 '예제' 절에 적는다"
  else
    ok "export 심볼 전부 원장에 선언됨"
  fi
  [ "$n_def" -eq 0 ] && ok "팩 원장 ${rows}행 정의 대조 통과"
  return 0
}

# ── 19-B. 완전 파일 펜스의 import 완결성 ───────────────────────────
# `<!-- file: 경로 -->`는 저자가 "이 펜스만으로 그 파일이다"라고 주장하는 표시다.
# 그 주장이 참이면 **원장 심볼을 쓰면서 정의도 import도 하지 않는 일이 있을 수 없다.**
# 실측(2026-08-23): vue 팩의 clearClientState가 STORAGE_KEY를 import 없이 써서 그대로
# 복사하면 ReferenceError였다. 게이트의 기존 로컬 import 검사는 `@/`로 시작하는 경로만
# 봐서 상대 경로(`./ui`) 파일을 놓쳤고, 그 방향(import된 것이 정의되었나)만 봤다 —
# 이 검사는 반대 방향(쓰인 것이 조달되었나)이다.
# 라벨 펜스(`// 경로`)는 발췌가 정상이므로 검사하지 않는다.
check_fence_imports() {
  local P="$1"
  [ -s "$TMP/provsym.txt" ] || return 0
  sec "완전 파일 펜스의 import 완결성"
  local files; files=$(guide_files "$P")
  [ -n "$files" ] || return 0

  # `<!-- file: -->` 직후 펜스만 뽑는다: <파일>\t<시작줄>\t<본문>
  # shellcheck disable=SC2086
  awk '
    FNR==1 { inf=0; claim=0 }
    /^[[:space:]]*<!--[[:space:]]*file:/ { claim=1; next }
    /^[[:space:]]*```/ {
      if (!inf) { inf=1; use=claim; start=FNR; claim=0 } else { inf=0; use=0 }
      next
    }
    !inf { if ($0 ~ /[^[:space:]]/) claim=0; next }
    # 주석 행은 제외한다 — 심볼이 설명에만 등장하는 것을 "사용"으로 세면 오탐이다
    # (개발 중 실측: `// ① readyz가 503을 낸다`가 미조달로 잡혔다).
    # codelines()와 같은 주석 판정을 쓴다.
    use && $0 !~ /^[[:space:]]*(\/\/|#|\*|\/\*|--)/ {
      line=$0
      sub(/[[:space:]]\/\/.*$/, "", line)   # 꼬리 주석도 뗀다 — `beginDrain(); // readyz가 503을 낸다`
      print FILENAME "\t" start "\t" line
    }
  ' $files > "$TMP/fileunits.tsv"

  local nu; nu=$(cut -f1,2 "$TMP/fileunits.tsv" 2>/dev/null | sort -u | grep -c . | tr -d ' ')
  nu=$(num "$nu")
  [ "$nu" -eq 0 ] && { warn "완전 파일 주장 펜스 0개 — 검사 대상 없음" "보안 원시함수·설정·테스트 하네스 펜스 앞에 <!-- file: 경로 -->를 단다"; return 0; }

  local key bad_n=0 sym body
  while IFS= read -r key; do
    [ -z "$key" ] && continue
    body=$(awk -F'\t' -v k="$key" '$1"\t"$2==k {print $3}' "$TMP/fileunits.tsv")
    while read -r sym; do
      [ -z "$sym" ] && continue
      # 점 뒤의 이름은 속성 접근이지 모듈 바인딩 사용이 아니다
      # (`process.env`가 원장 심볼 `env`로 잡히던 오탐 — 개발 중 실측).
      # 점 뒤(속성 접근)와 콜론 앞(객체 키·타입 주석)은 모듈 바인딩 사용이 아니다.
      # `process.env` · `env: { ... }` 가 원장 심볼 `env`로 잡히던 오탐 (개발 중 실측).
      printf '%s\n' "$body" | grep -qE "(^|[^.[:alnum:]_$])$sym([^A-Za-z0-9_:]|$)" || continue
      # 이 펜스 안에서 정의되었거나 import되었는가
      printf '%s\n' "$body" | grep -qE "(export[[:space:]]+)?(async[[:space:]]+)?(function|const|let|class|type|interface|enum)[[:space:]]+$sym\b" && continue
      printf '%s\n' "$body" | grep -qE "^[[:space:]]*import[^;]*\b$sym\b" && continue
      bad "완전 파일이 '$sym'을 조달 없이 사용 (${key%%$'\t'*} 기준)" \
          "$(basename "${key%%$'\t'*}"):${key##*$'\t'} — 그대로 복사하면 ReferenceError다. import를 넣거나 라벨(// 경로)로 낮춘다"
      bad_n=$((bad_n+1))
    done < "$TMP/provsym.txt"
  done < <(cut -f1,2 "$TMP/fileunits.tsv" | sort -u)

  [ "$bad_n" -eq 0 ] && ok "완전 파일 ${nu}개 — 원장 심볼 조달 완결"
  return 0
}

# ── 20. 팩 정책 집행 (조립 전) ──────────────────────────────────────
# check_policies는 assembly.json(=조립본)을 전제한다. 팩 저작 직후에는 이음매가 없으므로
# 축 안에서 판정 가능한 것만 돌린다: forbid는 확정 판정(FAIL), require는 이음매가 채울 수
# 있으므로 부재를 REVIEW로 둔다. 대상이 seam인 정책은 판정 자체가 불가능하다 — 명시 보고한다.
check_pack_policies() {
  local P="$1" pol="$1/$PACK_POLICIES_NAME"
  sec "팩 정책 집행 (조립 전 판정 가능분)"
  [ -f "$pol" ] || { warn "팩 정책 파일 없음: $pol"; return 0; }
  _parse_policies "$pol" "$TMP/packpol.tsv"
  local n; n=$(num "$(grep -c . "$TMP/packpol.tsv" | tr -d ' ')")
  [ "$n" -eq 0 ] && { warn "팩 정책에서 항목을 읽지 못함: $pol"; return 0; }

  local packfiles; packfiles=$(_pack_basenames "$P")
  local id verdict scope rx except ex has targets hits viol=0 pass=0 defer=0
  while IFS=$'\t' read -r id verdict scope rx except ex has; do
    [ -z "$id" ] && continue
    targets=$(_policy_targets "$P" "$scope" "$except" "$packfiles")
    if [ -z "$targets" ]; then defer=$((defer+1)); continue; fi
    # shellcheck disable=SC2086
    hits=$(num "$(codelines $targets | cut -f3 | grep -cE "$rx" 2>/dev/null || true)")
    if [ "$verdict" = "forbid" ]; then
      if [ "$hits" -gt 0 ]; then
        # shellcheck disable=SC2086
        bad "팩이 자기 정책 '$id'을 어김 — 금지 패턴 ${hits}건" \
            "$(codelines $targets | grep -E "$rx" | head -2 | awk -F'\t' '{printf "%s:%s ", substr($1,match($1,/[^\/]*$/)), $2}')"
        viol=$((viol+1))
      else pass=$((pass+1)); fi
    else
      if [ "$hits" -eq 0 ]; then
        rev "필수 패턴 '$id'이 팩에 없음" "정규식: $rx — 이음매가 채울 자리면 정상이다. 대상을 seam으로 옮길지 판단한다"
      else pass=$((pass+1)); fi
    fi
  done < "$TMP/packpol.tsv"
  [ "$viol" -eq 0 ] && ok "팩 정책 ${pass}건 통과 (대상=seam이라 조립 후로 미룬 ${defer}건 제외)"
  return 0
}

# 팩 파일 basename 목록 — _policy_targets의 scope 판정에 쓴다.
# 팩 모드에서 이 목록을 주면 scope=seam은 대상 0개가 되어 자동으로 조립 후로 미뤄진다.
_pack_basenames() {
  local f out=""
  for f in $(guide_files "$1"); do out="$out $(basename "$f")"; done
  printf '%s' "$out"
}

# ════════════════════════════════════════════════════════════════════
# --pack : 축 팩 1개 검사 (조립 전)
# ════════════════════════════════════════════════════════════════════
# 팩은 지금까지 단독으로 검증할 수 없었다 — run_guide가 SKILL.md를 전제하고 팩은
# PACK.md를 갖기 때문이다. 그래서 이음매가 없는 신규 팩은 저작 직후에 검사할 방법이
# 없었고 vue 팩 저작이 임기응변이 된 원인이기도 하다.
# 축 안에서 닫히는 검사만 돌린다. 조합의 함수인 것(requires 충족·--pair)은 조립 후다.
run_pack() {
  local P="$1"
  printf "\n${C_D}guide-gate --pack${C_0}  %s\n" "$P"

  [ -d "$P" ] || { printf "팩 디렉토리 없음: %s\n" "$P" >&2; exit 2; }
  [ -f "$P/PACK.md" ] || { bad "PACK.md 없음"; return; }

  local FILES; FILES=$(guide_files "$P")
  [ -n "$FILES" ] || { bad "resources/*.md 없음"; return; }
  # shellcheck disable=SC2086
  codelines $FILES > "$TMP/code.tsv"
  cut -f3 "$TMP/code.tsv" > "$TMP/code.txt"

  check_pack_meta "$P"
  check_budget "$P"
  check_fences "$P"
  check_symbols "$P"
  check_pack_ledger "$P"
  check_env "$P"
  check_leak "$P"
  check_pm "$P"
  check_pack_policies "$P"
  check_policy_proof "$P" "$P/$PACK_POLICIES_NAME" "$(_pack_basenames "$P")"
  check_security_shapes "$P"
  check_claims "$P"
  check_duplicate_fences "$P"
  check_blocking_proof "$P"
  check_fence_imports "$P"

  sec "조립 후로 미루는 검사 (명시)"
  warn "팩 requires 충족 검사는 건너뜀" "이음매가 아직 없다 — install-guide.sh 조립 후 --guide --assembly 로 돌린다"
  warn "와이어 계약 대조(--pair)는 건너뜀" "상대 축 가이드가 있어야 한다 — 조립 후 --pair --contract 로 돌린다"
  warn "대상=seam 정책은 판정 불가" "이음매를 겨눈 정책이다 — 조립 후 --guide --assembly 가 판정한다"
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
# 계약에서 대조 대상 행만 남긴다: 목록 항목과 표 행. 산문·인용문(>)의 백틱은
# 설명이지 계약 값이 아니다 — 세면 "실측에서 백엔드가 `/notes`를 썼다" 같은 문장이
# 계약 요구사항으로 둔갑한다 (개발 중 14건 오인 확인).
# 절 머리의 '> surface: frontend|backend' 선언을 읽어 해당 절 행에 태그를 붙인다.
# 선언이 없으면 both — 기존 계약은 그대로 동작한다.
contract_rows_tagged() {
  awk '
    /^## /            { sfc="both" }
    /^>[[:space:]]*surface:[[:space:]]*(frontend|backend|both)[[:space:]]*$/ {
                        sub(/^>[[:space:]]*surface:[[:space:]]*/,""); gsub(/[[:space:]]/,"");
                        sfc=$0; next }
    # 불릿은 **뒤에 공백**이 있어야 한다 — `**굵은 글씨**` 산문이 목록으로 읽히면
    # 한쪽 전용 값이 양쪽 요구로 둔갑한다. contract_rows()와 같은 규칙을 쓴다.
    /^[[:space:]]*([-*][[:space:]]|\|)/ {
                        if ($0 ~ /^[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|/) next
                        print sfc "\t" $0 }
  ' "$1"
}

# 목록 항목은 불릿 **뒤에 공백**이 있어야 한다. `**굵은 글씨**`로 시작하는 산문이
# `*` 불릿으로 읽히면 한쪽 전용 값이 양쪽 요구로 둔갑한다 (개발 중 실측: 계약 §6의
# "**서버 전용**: … 이름은 `rt`" 산문이 프론트 미충족 FAIL을 냈다).
contract_rows() { grep -E '^[[:space:]]*([-*][[:space:]]|\|)' "$1" | grep -vE '^[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|'; }

run_pair() {
  printf "\n${C_D}guide-gate --pair${C_0}  계약: %s\n" "$CONTRACT"
  [ -f "$CONTRACT" ] || { printf "계약 파일 없음: %s\n" "$CONTRACT" >&2; exit 2; }
  [ -d "$FE" ] && [ -d "$BE" ] || { printf "가이드 디렉토리 없음 (--frontend/--backend)\n" >&2; exit 2; }

  # 도메인 어휘: 계약 §0이 비어 있으면 두 가이드가 서로 다른 리소스를 설명하게 된다.
  # 실측에서 사전 제작 두 쌍 모두 프론트 /tasks ↔ 백엔드 /notes 였다.
  sec "도메인 어휘"
  if grep -q '^## 0\. 도메인 어휘' "$CONTRACT"; then
    local vocab; vocab=$(awk '/^## 0\. 도메인 어휘/{f=1;next} /^## /{f=0} f' "$CONTRACT" \
      | grep -E '^[[:space:]]*[-*]' \
      | grep -oE '`[A-Za-z_/][A-Za-z0-9_/-]*`' | tr -d '`' | sort -u)
    if [ -z "$vocab" ]; then
      bad "계약 §0 도메인 어휘가 비어 있음" "엔티티·컬렉션·경로를 각각 백틱으로 채운다"
    else
      local vmiss=""
      for v in $vocab; do
        grep -rqw -- "$v" "$FE" 2>/dev/null || vmiss="$vmiss FE:$v"
        grep -rqw -- "$v" "$BE" 2>/dev/null || vmiss="$vmiss BE:$v"
      done
      if [ -n "$vmiss" ]; then bad "도메인 어휘 불일치:$vmiss" "한쪽만 아는 리소스 이름 — 완전 예제가 서로 실행 불가가 된다"
      else ok "도메인 어휘 $(printf '%s' "$vocab" | wc -w | tr -d ' ')개 양쪽 일치"; fi
    fi
  else
    warn "계약에 §0 도메인 어휘 절이 없음" "구 양식이다 — wire-contract.template.md의 §0를 채운다"
  fi

  sec "계약 토큰 차집합"
  # 백틱 안의 식별자 + 3자리 상태 코드가 대조 토큰이다. 백틱 스팬 '전체'가 아니라
  # 스팬 '안'에서 뽑는다 — 봉투를 통째로 감싼 계약(`{ data, nextCursor }`)에서
  # 토큰이 0개가 되면 이 검사는 조용히 통과한다.
  local NOISE='^([A-Z]|string|number|boolean|object|null|true|false|undefined|unknown|never|any|void|json|JSON|Date|Promise|Record|Array|GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS)$'
  # 표면(surface)별로 나눠 뽑는다. 절에 '> surface: backend' 선언이 있으면 그 절의
  # 토큰은 백엔드에만 요구한다 — 액션 경계로 이야기하는 조합에서 HTTP 절이 그렇다.
  _tok() { # $1 = both|frontend|backend 중 포함할 표면들(정규식)
    { contract_rows_tagged "$CONTRACT" | awk -F'\t' -v re="$1" '$1 ~ re {print $2}' \
        | grep -oE '`[^`]+`' | tr -d '`' | grep -oE '[A-Za-z_][A-Za-z0-9_]*'
      contract_rows_tagged "$CONTRACT" | awk -F'\t' -v re="$1" '$1 ~ re {print $2}' \
        | grep -oE '(^|[^0-9A-Za-z_])[1-5][0-9][0-9]([^0-9A-Za-z_]|$)' | grep -oE '[0-9]{3}'
    } | grep -vE "$NOISE" | sort -u
  }
  _tok '^(both|frontend|backend)$' > "$TMP/tokens.txt"
  _tok '^(both|frontend)$' > "$TMP/tok_fe.txt"
  _tok '^(both|backend)$'  > "$TMP/tok_be.txt"

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
  done < "$TMP/tok_fe.txt"
  while read -r t; do
    [ -z "$t" ] && continue
    grep -rqw "$t" $(guide_files "$BE") 2>/dev/null || { mb="$mb $t"; nb=$((nb+1)); }
  done < "$TMP/tok_be.txt"

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
  _fx_assert "$fx/envhelper/sample-backend-guide" 0 "헬퍼로 선언한 env 키가 오탐되지 않음" --generated
  _fx_assert "$fx/dupexport/sample-backend-guide" 1 "중복 export 상이 정의" --generated
  _fx_assert "$fx/budget/sample-backend-guide"    1 "리소스 300줄 초과"     --generated
  _fx_assert "$fx/fence/sample-backend-guide"     1 "닫히지 않은 코드펜스"  --generated
  _fx_assert "$fx/section/sample-backend-guide"   1 "필수 섹션 누락"        --generated
  _fx_assert "$fx/nostamp/sample-backend-guide"   1 "생성 스탬프 없음"      --generated
  _fx_assert "$fx/leak/sample-backend-guide"      1 "교차 누출 키워드"      --generated --forbid prisma
  _fx_assert "$fx/clean/sample-backend-guide"     1 "패키지 매니저 불일치"  --generated --pm pnpm
  _fx_assert "$fx/clean/sample-backend-guide"     1 "원장 불일치(소비처 부재)" --generated --ledger "$fx/clean/ledger-bad.md"
  _fx_assert "$fx/clean/sample-backend-guide"     1 "원장 미등재 심볼"      --generated --ledger "$fx/clean/ledger-short.md"

  # 팩/이음매 경계 (v3.12.0) — 팩 자산은 --plugin-guides로 주입한다
  local PG="$fx/pg" A="$fx/clean/asm.json"
  cp "$fx/pg/backend/fxpack/policies.md" "$fx/pg/backend/fxpack/.keep-policies" 2>/dev/null || true
  _fx_assert "$fx/clean/sample-backend-guide" 0 "팩 requires 충족 + 생성물 제외" --generated --assembly "$A" --plugin-guides "$PG" --pack-ledger-name ledger-ok.md
  _fx_assert "$fx/clean/sample-backend-guide" 1 "팩 requires 미충족"        --generated --assembly "$A" --plugin-guides "$PG" --pack-ledger-name ledger.md
  _fx_assert "$fx/clean/sample-backend-guide" 1 "팩 정책 위반 (forbid)"     --generated --assembly "$A" --plugin-guides "$PG" --pack-ledger-name ledger-ok.md --pack-policies-name policies-forbid.md
  _fx_assert "$fx/clean/sample-backend-guide" 1 "팩 정책 위반 (require 부재)" --generated --assembly "$A" --plugin-guides "$PG" --pack-ledger-name ledger-ok.md --pack-policies-name policies-require-missing.md
  _fx_assert "$fx/clean/sample-backend-guide" 0 "정책 예외 열이 실제로 먹음"  --generated --assembly "$A" --plugin-guides "$PG" --pack-ledger-name ledger-ok.md --pack-policies-name policies-excepted.md

  # ── 축 팩 단독 검사 (v3.13.0) ──
  # 팩은 이음매 없이 검증할 수 없었다. --pack이 그 자리이고, 병렬 저작의 팬인 지점이다.
  _fx_build_pack "$fx" || { bad "팩 픽스처 생성 실패"; return; }

  sec "무해 팩 픽스처 (통과해야 한다)"
  _fx_assert_pack "$fx/pk/clean/fxpack2"     0 "결함 없는 축 팩"
  _fx_assert_pack "$fx/pk/secok/fxpack2"     0 "수리된 복귀 경로 검증이 오탐되지 않음"
  _fx_assert_pack "$fx/pk/dupfence/fxpack2"  0 "파일 간 동일 펜스는 REVIEW이지 FAIL 아님"

  sec "양성 팩 픽스처 (차단해야 한다)"
  _fx_assert_pack "$fx/pk/polnoex/fxpack2"   1 "정책 증명 예 열 없음"
  _fx_assert_pack "$fx/pk/polbadex/fxpack2"  1 "증명 예가 자기 정규식에 미매치"
  _fx_assert_pack "$fx/pk/polrealex/fxpack2" 1 "forbid 증명 예가 본문에 실재"
  _fx_assert_pack "$fx/pk/secorigin/fxpack2" 1 "복귀 경로를 origin 비교만으로 판정"
  _fx_assert_pack "$fx/pk/secprefix/fxpack2" 1 "복귀 경로를 startsWith('/')만으로 판정"
  _fx_assert_pack "$fx/pk/secrefer/fxpack2"  1 "요청에서 온 값으로 리다이렉트 (산문 지시)"
  _fx_assert_pack "$fx/pk/ledgerbad/fxpack2" 1 "원장 배정 파일에 정의 없음"
  _fx_assert_pack "$fx/pk/reqexport/fxpack2" 1 "requires 심볼을 팩이 스스로 export"
  _fx_assert_pack "$fx/pk/fvbad/fxpack2"     1 "fixesVariants ↔ pkgs 모순"
  _fx_assert_pack "$fx/pk/vocab/fxpack2"     1 "어휘 정책 위반 (L0 발행 forbid)"
  _fx_assert_pack "$fx/pk/noshape/fxpack2"   1 "provides 형태 열이 빔"
  _fx_assert_pack "$fx/pk/badarity/fxpack2"  1 "형태의 인자 개수 ≠ 실제 정의"
  _fx_assert_pack "$fx/pk/noimport/fxpack2"  1 "완전 파일이 원장 심볼을 조달 없이 사용"
  _fx_assert_pack "$fx/pk/reqnosig/fxpack2"  1 "requires 심볼을 호출하나 시그니처 미선언"

  [ "$REGRESS" -eq 0 ] && { sec "회귀 코퍼스"; skip_note; }

  sec "REVIEW 픽스처 (판정이 사람에게 넘어가야 한다)"
  _fx_review_assert "$fx/pk/noproof/fxpack2" "차단 증명 없는 테스트" "실패 단언"
  _fx_review_assert "$fx/pk/clean/fxpack2"   "" "실패 단언"

  [ "$REGRESS" -eq 1 ] && run_shipped_corpus
  return 0
}

# ── 출하 팩 회귀 코퍼스 ─────────────────────────────────────────────
# 합성 픽스처만으로는 **오탐**을 못 잡는다. 이 게이트의 결함 4건이 전부 실사용에서만
# 드러났다 (node-api 실측): check_env가 헬퍼 선언을 미선언으로 오판, check_claims가
# 태그된 주장을 인벤토리에서 제외, 앞줄 태그 귀속 과대, 보안 형태가 산문을 못 봄.
# 그래서 **출하 중인 팩 전체를 자기검사에 넣는다** — 새 검사가 실물에 오탐하면
# --self-test가 즉시 빨개진다. 미탐만큼 오탐도 게이트를 못 쓰게 만든다.
run_shipped_corpus() {
  sec "출하 팩 회귀 코퍼스 (오탐 차단)"
  if [ ! -d "$PLUGIN_GUIDES" ]; then
    warn "출하 팩 디렉토리 없음: $PLUGIN_GUIDES" "--plugin-guides로 경로를 주면 회귀가 켜진다 — 지금은 **미검사**다"
    return 0
  fi
  local d n=0 code
  for d in "$PLUGIN_GUIDES"/frontend/*/ "$PLUGIN_GUIDES"/backend/*/; do
    [ -f "$d/PACK.md" ] || continue
    n=$((n+1))
    code=0; bash "$0" --pack "${d%/}" >/dev/null 2>&1 || code=$?
    if [ "$code" -eq 0 ]; then
      ok "출하 팩 $(basename "$(dirname "${d%/}")")/$(basename "${d%/}") → FAIL 0"
    else
      bad "출하 팩 $(basename "$(dirname "${d%/}")")/$(basename "${d%/}") → exit $code" \
          "$(bash "$0" --pack "${d%/}" 2>&1 | grep '✗' | head -2 | sed 's/^  *//' | tr '\n' ';')"
    fi
  done
  [ "$n" -eq 0 ] && warn "출하 팩 0개 — 회귀 코퍼스가 비었다"

  run_shipped_seams
  return 0
}

# ── 사전 제작 이음매 회귀 ───────────────────────────────────────────
# 사전 제작 이음매는 조합 단위 출하 자산이라 **팩을 고칠 때마다 함께 검사해야 한다** —
# 팩의 requires가 늘거나 정책이 바뀌면 이음매가 조용히 어긋난다. 그 검사가 사람의
# 성실함에 달려 있으면 놓친다. 조립해서 조립본 게이트와 --pair를 돌린다.
# (조합당 3검사 × 이음매 수. --pack만으로는 requires 충족·대상=seam 정책이 켜지지 않는다)
run_shipped_seams() {
  local root; root=$(cd "$PLUGIN_GUIDES/.." 2>/dev/null && pwd) || return 0
  local inst="$root/scripts/install-guide.sh"
  [ -f "$inst" ] || { warn "install-guide.sh 없음 — 이음매 회귀 생략" "$inst"; return 0; }
  sec "사전 제작 이음매 회귀 (조합 단위)"

  local sj combo fe be proj n=0 code
  for sj in "$PLUGIN_GUIDES"/seams/*/seam.json; do
    [ -f "$sj" ] || continue
    combo=$(basename "$(dirname "$sj")")
    fe=$(grep -oE '"frontendPack"[^"]*"[^"]+"' "$sj" | sed -E 's|.*/||; s|"$||')
    be=$(grep -oE '"backendPack"[^"]*"[^"]+"'  "$sj" | sed -E 's|.*/||; s|"$||')
    [ -n "$fe" ] && [ -n "$be" ] || { warn "이음매 $combo — 팩 참조를 읽지 못함"; continue; }
    n=$((n+1))
    proj="$TMP/seam-$combo"; mkdir -p "$proj"
    if ! CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PROJECT_DIR="$proj" \
         bash "$inst" --frontend "$fe" --backend "$be" --seam "$combo" --no-cache >/dev/null 2>&1; then
      bad "이음매 $combo — 조립 실패"; continue
    fi
    local g ok_all=1
    for g in frontend backend; do
      code=0
      bash "$0" --guide "$proj/.claude/skills/$g-guide" \
                --assembly "$proj/.claude/skills/$g-guide/assembly.json" \
                --plugin-guides "$PLUGIN_GUIDES" >/dev/null 2>&1 || code=$?
      [ "$code" -eq 0 ] || { bad "이음매 $combo/$g → exit $code" \
        "$(bash "$0" --guide "$proj/.claude/skills/$g-guide" --assembly "$proj/.claude/skills/$g-guide/assembly.json" --plugin-guides "$PLUGIN_GUIDES" 2>&1 | grep '✗' | head -2 | sed 's/^  *//' | tr '\n' ';')"; ok_all=0; }
    done
    code=0
    bash "$0" --pair --contract "$PLUGIN_GUIDES/seams/$combo/contract.md" \
              --frontend "$proj/.claude/skills/frontend-guide" \
              --backend "$proj/.claude/skills/backend-guide" >/dev/null 2>&1 || code=$?
    [ "$code" -eq 0 ] || { bad "이음매 $combo --pair → exit $code" "와이어 계약이 양쪽에서 갈렸다"; ok_all=0; }
    [ "$ok_all" -eq 1 ] && ok "이음매 $combo → 조립본 2개 + --pair FAIL 0"
  done
  [ "$n" -eq 0 ] && warn "사전 제작 이음매 0개"
  return 0
}


# REVIEW는 exit 코드를 바꾸지 않으므로 출력으로 판정한다.
# want가 비면 "그 REVIEW가 **없어야** 한다"는 뜻이다 (오탐 차단).
# 코퍼스를 건너뛰었으면 그렇게 말한다 — "픽스처 통과"와 "실물 검사함"은 다르다.
skip_note() {
  printf "  ${C_C}–${C_0} 출하 팩·이음매 회귀 생략 (--regress로 켠다)\n"
  printf "      ${C_D}합성 픽스처는 미탐을 잡고 실물은 오탐을 잡는다 — 출하 전에 --regress를 돌린다${C_0}\n"
  return 0
}

_fx_review_assert() {
  local dir="$1" label="$2" needle="$3"
  local out; out=$(bash "$0" --pack "$dir" 2>&1)
  if [ -n "$label" ]; then
    if printf '%s' "$out" | grep -q "$needle"; then ok "$label → REVIEW 발생"
    else bad "$label → REVIEW가 나오지 않음" "차단 증명 없는 테스트를 통과시켰다"; fi
  else
    if printf '%s' "$out" | grep -q "$needle"; then bad "무해 팩에 '$needle' REVIEW 오탐"
    else ok "무해 팩에 차단 증명 REVIEW 없음"; fi
  fi
  return 0
}

_fx_assert_pack() {
  local dir="$1" want="$2" label="$3"; shift 3
  local out code=0
  out=$(bash "$0" --pack "$dir" "$@" 2>&1) || code=$?
  if [ "$code" -eq "$want" ]; then
    ok "$label → exit $code"
    # 차단은 됐는데 **다른 이유로** 차단된 픽스처는 픽스처가 아니다.
    # EPCC_FX_WHY=1 로 실제 FAIL 사유를 보고 의도와 대조한다.
    [ -n "${EPCC_FX_WHY:-}" ] && [ "$want" -eq 1 ] && \
      printf "      ${C_D}%s${C_0}\n" "$(printf '%s' "$out" | grep '✗' | head -2 | sed 's/^  *//' | tr '\n' ';')"
  else
    bad "$label → exit $code (기대 $want)" "$(printf '%s' "$out" | grep -E '✗|통과 ' | head -3 | tr '\n' ';')"
  fi
}

# 축 팩 픽스처 — v3.13.0에서 생긴 표면(--pack · 증명 예 · 보안 형태 · 변형 선언)을 고정한다.
_fx_build_pack() {
  local fx="$1" b="$1/pk/clean/fxpack2" m
  mkdir -p "$b/resources" || return 1

  cat > "$b/PACK.md" <<'FXPM'
<!-- epcc-pack: backend/fxpack2 v0.0.0 verified 2026-01-01 zod@4 -->

# fxpack2 축 팩 — 허브 조각

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── env.ts
└── boot.ts
```
<!-- /pack-slot -->
FXPM

  cat > "$b/resources/a.md" <<'FXPA'
# 스키마와 환경변수

```ts
import { z } from 'zod'

export const EnvSchema = z.object({
  PORT: z.string(),
})
```

`EnvSchema`는 b.md의 부팅 경로가 쓴다.
FXPA

  cat > "$b/resources/b.md" <<'FXPB'
# 부팅

```ts
import { EnvSchema } from '@/env'

export function boot(raw) {
  return EnvSchema.parse(raw)
}
```

`boot`는 진입점이 한 번만 호출한다.
FXPB

  cat > "$b/ledger.md" <<'FXPL'
## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `EnvSchema` | a.md | `ZodObject` — `safeParse(process.env)`로 적용 | env 스키마 |
| `boot` | b.md | `boot(raw: unknown) => Env` — 실패는 throw | 부팅 |

## requires — 이음매가 제공해야 한다

| 심볼 | 종류 | 형태 | 이유 |
| --- | --- | --- | --- |
| `logger` | 프로젝트 | 구조적 로거 | 이음매 소유 |
FXPL

  cat > "$b/policies.md" <<'FXPP'
## 기계 검사

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `zod-present` | require | guide | `from 'zod'` | — | `import { z } from 'zod'` | 스키마 라이브러리 고정 |
| `no-console` | forbid | guide | `console\.log\(` | — | `console.log(user)` | 구조적 로거만 쓴다 |
FXPP

  cat > "$b/pack.json" <<'FXPJ'
{
  "axis": "backend",
  "name": "fxpack2",
  "exampleDomain": { "entity": "Task", "collection": "tasks" },
  "fixesVariants": { "orm": "prisma" },
  "pkgs": ["zod@4", "prisma@6"],
  "resources": [
    { "file": "a.md", "nav": "스키마" },
    { "file": "b.md", "nav": "부팅" }
  ]
}
FXPJ

  for m in polnoex polbadex polrealex secorigin secprefix secok secrefer ledgerbad reqexport fvbad vocab dupfence noproof noshape badarity noimport reqnosig; do
    mkdir -p "$fx/pk/$m" && cp -R "$b" "$fx/pk/$m/" || return 1
  done
  # c.md를 더하는 픽스처는 pack.json에도 실어야 의도한 검사에서 차단된다.
  # 싣지 않으면 'resources[] 불일치'로 먼저 걸려 픽스처가 다른 것을 증명하게 된다.
  local v
  for v in secorigin secprefix secok; do
    sed -i.bak 's#{ "file": "b.md", "nav": "부팅" }#{ "file": "b.md", "nav": "부팅" },\
    { "file": "c.md", "nav": "복귀 경로" }#' "$fx/pk/$v/fxpack2/pack.json" && rm -f "$fx/pk/$v/fxpack2/pack.json.bak"
  done

  # ① 증명 예 열 자체가 없다 (구 6열 형식)
  cat > "$fx/pk/polnoex/fxpack2/policies.md" <<'FXP1'
## 기계 검사

| id | 판정 | 대상 | 정규식 | 예외 파일 | 설명 |
| --- | --- | --- | --- | --- | --- |
| `no-console` | forbid | guide | `console\.log\(` | — | 구조적 로거만 쓴다 |
FXP1

  # ② 증명 예가 자기 정규식에 안 잡힌다 — 죽은 정규식을 드러낸다
  cat > "$fx/pk/polbadex/fxpack2/policies.md" <<'FXP2'
## 기계 검사

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `no-console` | forbid | guide | `console\.error\(` | — | `console.log(user)` | 예와 정규식이 어긋난다 |
FXP2

  # ③ forbid의 증명 예가 팩 본문에 실재한다 — 자기 정책을 어긴 것이다
  cat > "$fx/pk/polrealex/fxpack2/policies.md" <<'FXP3'
## 기계 검사

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `no-zod` | forbid | guide | `from 'zod'` | — | `import { z } from 'zod'` | 본문에 그대로 있다 |
FXP3

  # ④·⑤ 보안 형태 — 실측(2026-08-23)이 출하본 네 곳에서 찾은 두 형태
  cat > "$fx/pk/secorigin/fxpack2/resources/c.md" <<'FXP4'
# 복귀 경로

```ts
export function safeReturnTo(raw: string, fallback = '/') {
  const url = new URL(raw, window.location.origin);
  if (url.origin !== window.location.origin) return fallback;
  return url.pathname + url.search;
}
```
FXP4
  cat > "$fx/pk/secprefix/fxpack2/resources/c.md" <<'FXP5'
# 복귀 경로

```ts
export function safeReturnTo(raw: string, fallback = '/') {
  if (!raw.startsWith('/')) return fallback;
  return raw;
}
```
FXP5
  # 차단을 증명하지 못하는 테스트 — 실패 단언만 있고 성공 단언이 없다.
  # 구현을 통째로 실패시켜도 통과하므로 "차단 장치"가 아니다 (node-api 실측).
  cat > "$fx/pk/noproof/fxpack2/resources/b.md" <<'FXP12'
# 부팅

```ts
import { EnvSchema } from '@/env'

export function boot(raw) {
  return EnvSchema.parse(raw)
}
```

`boot`는 진입점이 한 번만 호출한다.

```ts
it('남의 것을 읽으면 404다', async () => {
  const res = await request(app).get('/x')
  expect(res.status).toBe(404)
})
```
FXP12

  # 요청 유래 리다이렉트는 **산문·표에도 실린다** — 펜스만 보면 놓친다.
  # node-api 실측에서 오용 대조표의 칸이 검증 없이 Referer를 읽으라고 지시했다.
  cat > "$fx/pk/secrefer/fxpack2/resources/c.md" <<'FXP7'
# 오용 목록

| 구 습관 | 현재 형태 |
| --- | --- |
| `res.redirect('back')` | 특수 처리가 없어졌다. `req.get('Referer')`를 직접 읽는다 |
FXP7

  # 무해 대조군: 수리된 형태는 통과해야 한다 (오탐은 미탐만큼 게이트를 못 쓰게 만든다)
  cat > "$fx/pk/secok/fxpack2/resources/c.md" <<'FXP6'
# 복귀 경로

```ts
export function safeReturnTo(raw: string, fallback = '/') {
  const url = new URL(raw, window.location.origin);
  if (url.origin !== window.location.origin) return fallback;
  const p = url.pathname;
  if (!p.startsWith('/') || p.startsWith('//')) return fallback;
  return p + url.search;
}
```
FXP6

  # ⑪ 형태 열이 비었다 — 형제 클러스터가 시그니처를 추측하게 된다
  sed -i.bak 's#| `boot` | b.md | `boot(raw: unknown) => Env` — 실패는 throw |#| `boot` | b.md | — |#' \
    "$fx/pk/noshape/fxpack2/ledger.md" && rm -f "$fx/pk/noshape/fxpack2/ledger.md.bak"

  # ⑫ 형태가 선언한 인자 개수와 실제 정의가 다르다
  sed -i.bak 's#`boot(raw: unknown) => Env` — 실패는 throw#`boot(raw: unknown, opts: Opts) => Env` — 실패는 throw#' \
    "$fx/pk/badarity/fxpack2/ledger.md" && rm -f "$fx/pk/badarity/fxpack2/ledger.md.bak"

  # ⑭ requires 심볼을 호출하면서 형태에 시그니처가 없다 — 이음매가 인자 순서를 추측한다
  printf '\n```ts\nlogger(env, "boot")\n```\n' >> "$fx/pk/reqnosig/fxpack2/resources/b.md"

  # ⑬ 완전 파일이 원장 심볼을 조달 없이 쓴다 — 그대로 복사하면 ReferenceError
  cat > "$fx/pk/noimport/fxpack2/resources/b.md" <<'FXP13'
# 부팅

<!-- file: src/boot.ts -->
```ts
// src/boot.ts
export function boot(raw) {
  return EnvSchema.parse(raw)
}
```

`boot`는 진입점이 한 번만 호출한다.
FXP13

  # ⑥ 원장이 배정한 파일에 정의가 없다 — 병렬 저작의 팬인 결함
  sed -i.bak 's#| `boot` | b.md |#| `boot` | a.md |#' "$fx/pk/ledgerbad/fxpack2/ledger.md" && rm -f "$fx/pk/ledgerbad/fxpack2/ledger.md.bak"

  # ⑦ requires로 선언한 심볼을 팩이 스스로 export한다 (실측: react-vite의 useTasksQuery)
  sed -i.bak 's#| `logger` | 프로젝트 |#| `boot` | 프로젝트 |#' "$fx/pk/reqexport/fxpack2/ledger.md" && rm -f "$fx/pk/reqexport/fxpack2/ledger.md.bak"

  # ⑧ 선언한 변형과 pkgs가 모순 — 조립 시점 대조가 거짓 통과한다
  sed -i.bak 's#"prisma@6"#"drizzle-orm@0"#' "$fx/pk/fvbad/fxpack2/pack.json" && rm -f "$fx/pk/fvbad/fxpack2/pack.json.bak"

  # ⑨ 어휘 정책 — L0가 발행하는 forbid 행이 병렬 저작의 어휘 분기를 잡는가
  cat > "$fx/pk/vocab/fxpack2/policies.md" <<'FXP9'
## 기계 검사

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `vocab-task` | forbid | guide | `\bnote(s)?\b` | — | `const notes = []` | 도메인 어휘는 Task로 고정 (L0 발행) |
FXP9
  printf '\n```ts\nexport const notes = []\n```\n' >> "$fx/pk/vocab/fxpack2/resources/b.md"
  sed -i.bak 's#| `boot` | b.md | 부팅 |#| `boot` | b.md | 부팅 |\n| `notes` | b.md | 어휘 위반 |#' "$fx/pk/vocab/fxpack2/ledger.md" && rm -f "$fx/pk/vocab/fxpack2/ledger.md.bak"

  # ⑩ 무해: 파일 간 같은 코드펜스는 REVIEW이지 FAIL이 아니다 (공통 import 블록이 실재한다)
  cat >> "$fx/pk/dupfence/fxpack2/resources/a.md" <<'FXP10'

```ts
import { z } from 'zod'
import { boot } from '@/boot'
import { EnvSchema } from '@/env'
```
FXP10
  cat >> "$fx/pk/dupfence/fxpack2/resources/b.md" <<'FXP11'

```ts
import { z } from 'zod'
import { boot } from '@/boot'
import { EnvSchema } from '@/env'
```
FXP11
  return 0
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

  for m in dangling envkey envhelper dupexport budget fence section nostamp leak; do
    mkdir -p "$fx/$m" && cp -R "$b" "$fx/$m/" || return 1
  done

  printf '| 없는 파일 | `resources/missing.md` |\n' >> "$fx/dangling/sample-backend-guide/SKILL.md"
  printf '\n```ts\nconst timeout = env.REQUEST_TIMEOUT_MS\n```\n' >> "$fx/envkey/sample-backend-guide/resources/b.md"
  # 헬퍼 호출로 선언한 키를 그대로 소비한다 — 정상 코드이므로 통과해야 한다
  printf '\n```ts\nexport const ms = (max) => max\nexport const Extra = {\n  DRAIN_DELAY_MS: ms(60000),\n}\n```\n' >> "$fx/envhelper/sample-backend-guide/resources/a.md"
  printf '\n```ts\nconst drain = env.DRAIN_DELAY_MS\n```\n' >> "$fx/envhelper/sample-backend-guide/resources/b.md"
  printf '\n```ts\nexport function connect(url, options) {\n  return url\n}\n```\n' >> "$fx/dupexport/sample-backend-guide/resources/c.md"
  awk 'BEGIN{ for (i=0; i<310; i++) print "패딩 행 — 예산 초과를 만든다" }' >> "$fx/budget/sample-backend-guide/resources/d.md"
  printf '\n```ts\nconst unclosed = 1\n' >> "$fx/fence/sample-backend-guide/resources/e.md"
  sed -i.bak 's/^## Common Imports$/기본 import 묶음:/' "$fx/section/sample-backend-guide/SKILL.md" && rm -f "$fx/section/sample-backend-guide/SKILL.md.bak"
  sed -i.bak '/epcc-guide: generated/d' "$fx/nostamp/sample-backend-guide/SKILL.md" && rm -f "$fx/nostamp/sample-backend-guide/SKILL.md.bak"
  printf '\n마이그레이션은 prisma migrate로 돌린다.\n' >> "$fx/leak/sample-backend-guide/resources/f.md"

  # ── 팩/이음매 픽스처 (v3.12.0에서 생긴 새 표면) ──
  # 축 팩과 이음매를 갈라 배송하면 두 결함 부류가 새로 생긴다:
  #   ① 팩이 소비하는데 이음매가 정의하지 않는 심볼 (팩 예제가 실행 불가가 된다)
  #   ② 팩이 선언한 파일 간 불변식을 이음매가 어김 (실측 감사 57건 중 26건이 이 부류)
  # 둘 다 차단을 증명한다. 예외 열이 실제로 먹는지도 함께 증명한다 —
  # 예외가 무시되면 정당한 코드가 영구 위반으로 찍혀 게이트를 못 쓰게 된다.
  local pk="$fx/pg/backend/fxpack"
  mkdir -p "$pk" || return 1

  cat > "$pk/ledger.md" <<'FXLED'
## requires
| 심볼 | 종류 | 형태 | 이유 |
| --- | --- | --- | --- |
| `connect` | 프로젝트 | 부팅 경로 | 이음매 소유 |
| `neverProvided` | 프로젝트 | 이음매가 주지 않는 심볼 | 차단 증명용 |
FXLED

  cat > "$pk/ledger-ok.md" <<'FXLEDOK'
## requires
| 심볼 | 종류 | 형태 | 이유 |
| --- | --- | --- | --- |
| `connect` | 프로젝트 | 부팅 경로 | 이음매 소유 |
| `SomeGeneratedType` | 생성물 | 도구 산출물 | 검사 제외 증명용 |
FXLEDOK

  cat > "$pk/policies.md" <<'FXPOL'
## 기계 검사
| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `zod-present` | require | guide | `from 'zod'` | — | `import { z } from 'zod'` | 스키마 라이브러리 고정 |
FXPOL

  cat > "$pk/policies-forbid.md" <<'FXPOLV'
## 기계 검사
| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `no-zod` | forbid | guide | `from 'zod'` | — | `import { z } from 'zod'` | 차단 증명용 |
FXPOLV

  cat > "$pk/policies-require-missing.md" <<'FXPOLR'
## 기계 검사
| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `must-have-graphql` | require | guide | `from 'graphql'` | — | `import { gql } from 'graphql'` | 차단 증명용 |
FXPOLR

  cat > "$pk/policies-excepted.md" <<'FXPOLE'
## 기계 검사
| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `no-zod` | forbid | guide | `from 'zod'` | `a.md` | `import { z } from 'zod'` | 유일 등장 파일을 예외로 두면 통과해야 한다 |
FXPOLE

  printf '{ "axis": "backend", "pack": "backend/fxpack", "packFiles": ["a.md"], "seamFiles": ["b.md","c.md","d.md","e.md","f.md"] }\n' > "$fx/clean/asm.json"
  return 0
}

# ════════════════════════════════════════════════════════════════════
MODE=""; GUIDE=""; LEDGER=""; FORBID=""; PM=""; GENERATED=0
CONTRACT=""; FE=""; BE=""; ASSEMBLY=""; PACK_LEDGER_NAME="ledger.md"; PACK_POLICIES_NAME="policies.md"
REGRESS=0
PLUGIN_GUIDES="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}/guides"

[ $# -eq 0 ] && { printf "인자 없음 (--help 참조)\n" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --guide)     MODE="guide"; GUIDE="${2:-}"; shift 2 || exit 2 ;;
    --pack)      MODE="pack";  GUIDE="${2:-}"; shift 2 || exit 2 ;;
    --pair)      MODE="pair"; shift ;;
    --self-test) MODE="selftest"; shift ;;
    --regress)   MODE="selftest"; REGRESS=1; shift ;;
    --contract)  CONTRACT="${2:-}"; shift 2 || exit 2 ;;
    --frontend)  FE="${2:-}"; shift 2 || exit 2 ;;
    --backend)   BE="${2:-}"; shift 2 || exit 2 ;;
    --ledger)    LEDGER="${2:-}"; shift 2 || exit 2 ;;
    --forbid)    FORBID="${2:-}"; shift 2 || exit 2 ;;
    --pm)        PM="${2:-}"; shift 2 || exit 2 ;;
    --assembly)  ASSEMBLY="${2:-}"; shift 2 || exit 2 ;;
    --plugin-guides) PLUGIN_GUIDES="${2:-}"; shift 2 || exit 2 ;;
    --pack-ledger-name)   PACK_LEDGER_NAME="${2:-}"; shift 2 || exit 2 ;;   # --self-test 전용
    --pack-policies-name) PACK_POLICIES_NAME="${2:-}"; shift 2 || exit 2 ;; # --self-test 전용
    --generated) GENERATED=1; shift ;;
    -h|--help)   sed -n '2,28p' "$0" | sed -E 's/^#[[:space:]]?//'; exit 0 ;;
    *)           printf "알 수 없는 옵션: %s (--help 참조)\n" "$1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  guide) [ -n "$GUIDE" ] || { printf -- "--guide <디렉토리> 필요\n" >&2; exit 2; }; run_guide "$GUIDE" ;;
  pack)  [ -n "$GUIDE" ] || { printf -- "--pack <디렉토리> 필요\n" >&2; exit 2; };  run_pack "$GUIDE" ;;
  pair)  run_pair ;;
  selftest) run_self_test ;;
  *)     printf "모드 없음: --guide · --pack · --pair (--help 참조)\n" >&2; exit 2 ;;
esac

printf "\n${C_D}────────────────────────────────────────────${C_0}\n"
printf "  통과 %s · ${C_Y}WARN %s${C_0} · ${C_C}REVIEW %s${C_0} · ${C_R}FAIL %s${C_0}\n\n" "$PASS" "$WARN" "$REVIEW" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
