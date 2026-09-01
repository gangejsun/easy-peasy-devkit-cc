#!/bin/bash
# skills/stack-guide-generator/scripts/pack-smoke.sh — 축 팩 실행 검증 하네스
#
# 게이트(guide-gate.sh)는 읽어서 잡을 수 있는 것을 잡는다. 실측(2026-08-23)에서 게이트
# 전항을 통과한 뒤 남은 결함은 **거의 전부 실행으로** 잡혔다 — 감사자가 스크래치에 실제
# 프로젝트를 만들어 돌려서 찾았다. 그중 하나가 출하본 네 곳에 있던 오픈 리다이렉트다.
# 그 자발적 행위를 파이프라인의 단계로 올린 것이 이 스크립트다.
#
#   pack-smoke.sh --pack <팩디렉토리> [옵션]
#       --profile <이름>   툴체인 프로필 (기본 auto — pkgs로 추론)
#       --out <디렉토리>   작업 디렉토리 (기본 mktemp, 종료 시 삭제)
#       --keep             작업 디렉토리를 남긴다 (감사 A에 넘길 때)
#       --no-vectors       보안 벡터 시험을 건너뛴다
#       --online           pack.json의 pkgs를 작업 디렉토리에 **메이저 고정**으로 설치한다.
#                          이것이 없으면 tsc는 skip이고 감사 A가 그 설치를 대신 한다 —
#                          그 대기가 감사 임계 경로에 얹혔다. 네트워크 실패는 skip이지 FAIL이 아니다
#   pack-smoke.sh --self-test
#   pack-smoke.sh --help
#
# 표시가 두 가지다. 팩의 코드펜스는 대부분 발췌이고 전부 컴파일시키려 하면 위양성 늪이
# 된다 — 그래서 검사는 저자가 명시적으로 주장한 것에만 건다.
#   `// src/foo.ts`  (펜스 첫 줄)   = **라벨**. 이 조각이 어느 파일의 것인지 알린다.
#                                     복원은 하되 구문·타입 검사는 걸지 않는다
#   `<!-- file: src/foo.ts -->`     = **완전 파일 주장**. 구문·타입 검사 대상이다
# 보안 원시함수·설정 파일·테스트 하네스에는 후자를 단다 — 실측에서 실행으로 잡힌 결함이
# 전부 이 부류였다. 보안 벡터 시험은 두 표시 모두에서 함수를 찾는다.
#
# 층 소유: 추출·스텁·판정은 이 스크립트(툴체인 무관), 빌드·타입체크는 profiles/<이름>.sh.
# 프로필이 없는 툴체인은 **skip을 명시 보고**한다 (침묵 생략 금지).
#
# 종료 코드: 0 = 결함 없음, 1 = 결함, 2 = 사용법·자산 오류

set -uo pipefail   # -e 없음: 모든 검사를 끝까지 돌려 전체 보고서를 낸다

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 1. 추출: 경로 주석이 붙은 펜스를 **펜스 단위로** 복원 ───────────
# 이어 붙이지 않는다. 같은 경로를 여러 펜스가 주장하는 관용구는 "순차 발췌"가 아니라
# **대안·부분 조각**인 경우가 많고(vite.config.ts의 `resolve: {...}` 같은 객체 조각),
# 이어 붙이면 어느 쪽도 아닌 키메라가 만들어져 위양성을 낸다.
# 펜스마다 단위 파일 하나 + 매니페스트 1행을 남긴다.
#
# 안티패턴 펜스(펜스 앞 산문이 ❌ · 펜스 안 주석이 ❌)는 제외한다 — 나쁜 예를 복원해
# 검사에 넘기면 전부 위양성이 된다. 게이트의 codelines()와 같은 규약이다.
extract_files() {
  local P="$1" OUT="$2"
  mkdir -p "$OUT/units" || return 1
  awk -v out="$OUT" '
    function isbad(s) { return (index(s,"❌")>0 || (index(s,"✅")==0 && s ~ /(^|[^A-Za-z0-9_])(Bad|BAD)([^A-Za-z0-9_]|$)/)) }
    FNR==1 { inf=0; lastprose=""; pending="" }
    /^[[:space:]]*```/ {
      if (!inf) { inf=1; first=1; path=""; kind="label"; startln=FNR; skipf = isbad(lastprose)
                  if (pending != "") { path=pending; kind="file"; pending="" } }
      else { inf=0; path=""; kind="label" }
      next
    }
    !inf {
      if ($0 ~ /^[[:space:]]*<!--[[:space:]]*file:/) {
        pending=$0; sub(/^[[:space:]]*<!--[[:space:]]*file:[[:space:]]*/,"",pending); sub(/[[:space:]]*-->.*$/,"",pending)
      } else if ($0 ~ /[^[:space:]]/) { lastprose=$0 }
      next
    }
    {
      if (first) {
        first=0
        if (path == "" && $0 ~ /^[[:space:]]*(\/\/|#)[[:space:]]*[A-Za-z0-9_.@][A-Za-z0-9_.@\/-]*\.[A-Za-z]+/) {
          path=$0
          sub(/^[[:space:]]*(\/\/|#)[[:space:]]*/,"",path)
          sub(/[[:space:]].*$/,"",path)
        }
      }
      if (path == "" || skipf) next
      print path "\t" kind "\t" FILENAME "\t" startln "\t" $0
    }
  ' $(ls "$P/PACK.md" "$P"/resources/*.md 2>/dev/null) > "$OUT/.extract.tsv"

  local path kind src ln line key prev="" cur="" u=0 ext
  : > "$OUT/.units.tsv"
  while IFS=$'\t' read -r path kind src ln line; do
    [ -z "$path" ] && continue
    case "$path" in /*|*..*) continue ;;       # 절대 경로·상위 탈출은 받지 않는다
    esac
    key="$src:$ln"
    if [ "$key" != "$prev" ]; then
      u=$((u+1)); prev="$key"
      ext="${path##*.}"; case "$ext" in "$path") ext="txt";; esac
      cur=$(printf 'u%03d.%s' "$u" "$ext")
      printf '%s\t%s\t%s\t%s\t%s\n' "$cur" "$path" "$(basename "$src")" "$ln" "$kind" >> "$OUT/.units.tsv"
      : > "$OUT/units/$cur"
    fi
    printf '%s\n' "$line" >> "$OUT/units/$cur"
  done < "$OUT/.extract.tsv"
  printf '%s' "$u"
}


# ── 원장 requires 심볼 ─────────────────────────────────────────────
# **스텁은 「이음매가 줄 것」에만 쓴다.** 그 구분이 없으면 팩의 **경로 오기**까지 스텁이
# 덮어 파일 간 정합성 오류가 통째로 사라진다 — 두 번 재발했다(fastapi의
# `app/db/models.py`, firebase의 `./model.js`). 어느 쪽도 게이트가 잡지 못했고
# 감사가 실경로로 다시 조립해서야 드러났다.
_any_required() { # $1=출력디렉토리 $2=import한 이름 목록 → 하나라도 requires면 0
  local nm
  [ -s "$1/.requires.txt" ] || return 0     # 원장을 못 읽으면 예전대로 스텁한다
  while read -r nm; do
    [ -z "$nm" ] && continue
    grep -qxF "$nm" "$1/.requires.txt" && return 0
  done < <(printf '%s\n' "$2" | tr ',' '\n' \
      | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^type[[:space:]]+//; s/[[:space:]]+as[[:space:]]+.*//' \
      | grep -E '^[A-Za-z_][A-Za-z0-9_]*$')
  return 1
}

# ── 원장 provides 의 소스 경로 ─────────────────────────────────────
# **팩이 소유한 파일은 스텁으로 대체돼선 안 된다.** 대체되면 그 파일은 타입체크도
# 실행도 **한 번도 받지 않은 채** 통과로 보고된다 — gcp 실측에서 이 축의 보안 경계
# 전부(`src/firestore/tasks.ts`의 소유권 검사 6함수)가 정확히 그 상태였다.
# 원인은 코드펜스에 `<!-- file: -->` 표시가 없어 유닛으로 복원되지 않은 것이고,
# 게이트도 smoke도 그것을 **WARN조차 내지 않았다**.
provides_paths() { # $1=팩디렉토리 → 소스 경로 목록
  local led="$1/ledger.md"
  [ -f "$led" ] || return 0
  awk '/^## provides/{f=1;next} f&&/^## /{f=0} f' "$led" \
    | grep -oE '`[A-Za-z0-9_./-]+\.(ts|tsx|js|jsx|mts|py)`' \
    | tr -d '`' | sort -u
  return 0
}

requires_syms() { # $1=팩디렉토리 → 심볼 이름 목록(줄바꿈 구분)
  local led="$1/ledger.md"
  [ -f "$led" ] || return 0
  awk '/^## requires/{f=1;next} f&&/^## /{f=0} f' "$led" \
    | grep -oE '^\|[[:space:]]*`[A-Za-z_][A-Za-z0-9_]*`' \
    | grep -oE '`[A-Za-z_][A-Za-z0-9_]*`' | tr -d '`' | sort -u
  return 0
}

# 상대 import를 유닛의 목표 경로 기준으로 접는다. 대상 파일이 아직 없으므로
# realpath를 쓸 수 없다 — 순수 문자열 정규화다.
normalize_rel() { # $1=기준 디렉토리 $2=상대 경로
  local combined seg out="" oldIFS="$IFS"
  combined="$1/$2"
  IFS=/
  # shellcheck disable=SC2086
  set -- $combined
  IFS="$oldIFS"
  for seg in "$@"; do
    case "$seg" in
      ''|'.') ;;
      '..') case "$out" in */*) out="${out%/*}";; *) out="";; esac ;;
      *) out="${out:+$out/}$seg" ;;
    esac
  done
  printf '%s' "$out"
}

# ── 2. 스텁: 해소되지 않는 로컬 import를 채운다 ─────────────────────
# 원장의 requires는 이음매가 줄 것이므로 팩만 놓고 보면 항상 미해소다.
# 그것을 스텁으로 채워야 타입체크가 "이음매 미구현"이 아니라 팩 자신의 결함을 본다.
make_stubs() {
  local OUT="$1" PACK="$2" made=0 orphan=0 spec names mod target
  : > "$OUT/.orphan.txt"
  : > "$OUT/.stubbed.txt"
  requires_syms "$PACK" > "$OUT/.requires.txt" 2>/dev/null || : > "$OUT/.requires.txt"
  provides_paths "$PACK" > "$OUT/.provides.txt" 2>/dev/null || : > "$OUT/.provides.txt"
  [ -s "$OUT/.units.tsv" ] || { printf '0'; return 0; }

  # 별칭(@/…)과 **상대 경로**를 모두 본다. 상대 경로만 쓰는 팩에서 스텁이 하나도 만들어지지
  # 않아 tsc가 이음매 미구현을 팩 결함으로 보고했다 (aws-serverless 실측 — 오탐).
  # 상대 경로는 **import한 파일의 위치** 기준이므로 유닛의 목표 경로와 함께 모은다.
  : > "$OUT/.imports.txt"
  local uid upath uspec
  while IFS=$'\t' read -r uid upath _rest; do
    [ -z "$uid" ] && continue
    [ -f "$OUT/units/$uid" ] || continue
    grep -ohE "import( type)? \{[^}]*\} from '@/[^']*'" "$OUT/units/$uid" 2>/dev/null \
      | while IFS= read -r uspec; do printf '.\t%s\n' "$uspec"; done >> "$OUT/.imports.txt"
    grep -ohE "import( type)? \{[^}]*\} from '\.[^']*'" "$OUT/units/$uid" 2>/dev/null \
      | while IFS= read -r uspec; do printf '%s\t%s\n' "$(dirname "$upath")" "$uspec"; done >> "$OUT/.imports.txt"
    # **JSDoc의 타입 import는 `import { }` 문이 아니다.** JS 팩은 타입을
    # `/** @typedef {import('../x.js').Task} Task */` 로 끌어온다 — 이 형태를 안 보면
    # 그 심볼이 스텁에 들어가지 않아 TS2694가 난다 (vanilla 실측: task-list.test.js).
    # `import { A } from '경로'` 꼴로 정규화해 아래 스텁 로직이 그대로 쓰게 한다.
    grep -ohE "import\('[^']+'\)\.[A-Za-z_][A-Za-z0-9_]*" "$OUT/units/$uid" 2>/dev/null \
      | sed -E "s#import\('([^']+)'\)\.([A-Za-z_][A-Za-z0-9_]*)#import { \2 } from '\1'#" \
      | while IFS= read -r uspec; do
          case "$uspec" in
            *"from '@/"*) printf '.\t%s\n' "$uspec" ;;
            *"from '."*)  printf '%s\t%s\n' "$(dirname "$upath")" "$uspec" ;;
          esac
        done >> "$OUT/.imports.txt"
  done < "$OUT/.units.tsv"
  sort -u -o "$OUT/.imports.txt" "$OUT/.imports.txt"

  # ── Python: `from app.http.handlers import install_error_handlers` ──
  # 원장 requires는 이음매가 줄 것이므로 팩만 놓고 보면 항상 미해소다. 이것을 채우지
  # 않으면 pyright가 이음매 미구현을 팩 결함으로 보고하고, **스키마 실행까지 막힌다**
  # (fastapi 팬인 실측). 지역 패키지 판정은 복원된 유닛 경로의 최상위 디렉토리로 한다 —
  # 라이브러리 import를 스텁하면 진짜 의존성을 가려 버린다.
  local roots; roots=$(cut -f2 "$OUT/.units.tsv" | grep '/' | cut -d/ -f1 | sort -u)
  local pyline pymod pynames pytarget root
  while IFS= read -r pyline; do
    [ -z "$pyline" ] && continue
    pymod=$(printf '%s' "$pyline" | sed -E 's/^[[:space:]]*from[[:space:]]+([A-Za-z_][A-Za-z0-9_.]*)[[:space:]]+import.*/\1/')
    case "$pymod" in ''|*' '*) continue ;; esac
    root="${pymod%%.*}"
    printf '%s\n' "$roots" | grep -qxF "$root" || continue     # 라이브러리다
    pytarget=$(printf '%s' "$pymod" | tr '.' '/').py
    [ -f "$OUT/$pytarget" ] && continue
    awk -F'\t' '$5=="file"{print $2}' "$OUT/.units.tsv" | grep -qxF "$pytarget" && continue
    # **패키지를 모듈로 가리지 않는다.** `from app.db import x`를 `app/db.py`로 스텁하면
    # 실재하는 `app/db/` 패키지를 가려 그 안의 모든 모듈이 미해소가 된다
    # (fastapi 최종 팬인 실측 — 정상 팩이 타입체크 실패로 보고됐다).
    [ -d "$OUT/${pytarget%.py}" ] && continue
    cut -f2 "$OUT/.units.tsv" | grep -q "^${pytarget%.py}/" && continue
    pynames=$(printf '%s' "$pyline" | sed -E 's/.*[[:space:]]import[[:space:]]+//; s/#.*//')
    if ! cut -f2 "$OUT/.units.tsv" | grep -qxF "$pytarget" && ! _any_required "$OUT" "$pynames"; then
      printf '%s\t%s\n' "$pytarget" "$(printf '%s' "$pynames" | tr -d '\n')" >> "$OUT/.orphan.txt"
      orphan=$((orphan+1)); continue
    fi
    mkdir -p "$OUT/$(dirname "$pytarget")" 2>/dev/null
    {
      printf '# pack-smoke 스텁 — 원장 requires(이음매 소유). 팩만으로는 해소되지 않는다.\n'
      printf 'from typing import Any\n'
      # **쓰임새로 형태를 가른다.** 파이썬 스텁에는 두 자리를 동시에 만족하는 형태가 없다:
      #   `NAME: Any = None` → 값 자리는 되지만 타입 표현식에서 `형식 식에는 변수를 사용할
      #                         수 없습니다`가 된다
      #   `class NAME: ...`   → 타입 자리는 되지만 값 자리에서 `type[NAME]`이 되어
      #                         구체 타입을 요구하는 인자에 못 넣는다
      # 둘 다 fastapi 팬인에서 **스텁 산물이 팩 결함으로 보고되는** 오탐을 냈다.
      # 그래서 유닛 본문에서 그 이름이 타입 표현식(`-> NAME` · `: NAME` · `[NAME]`)으로
      # 쓰이는지 보고 클래스와 값 중 하나를 고른다.
      printf '%s\n' "$pynames" | tr ',' '\n' \
        | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^.*[[:space:]]+as[[:space:]]+//' \
        | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u | while read -r nm; do
            if grep -rhqE "(->[[:space:]]*$nm\\b|:[[:space:]]*$nm\\b|\\[$nm\\]|except[[:space:]]+$nm\\b)" "$OUT/units" 2>/dev/null; then
              printf 'class %s(Exception):\n' "$nm"
              printf '    def __init__(self, *a: Any, **k: Any) -> None: ...\n'
              printf '    def __call__(self, *a: Any, **k: Any) -> Any: ...\n'
              printf '    def __getattr__(self, n: str) -> Any: ...\n'
            else
              printf '%s: Any = None\n' "$nm"
            fi
          done
    } >> "$OUT/$pytarget"
    printf '%s\n' "$pytarget" >> "$OUT/.stubbed.txt"
    # __init__.py가 없으면 pyright가 패키지로 보지 않는다
    local d="$OUT/$(dirname "$pytarget")"
    while [ "$d" != "$OUT" ] && [ -n "$d" ]; do
      [ -f "$d/__init__.py" ] || : > "$d/__init__.py"
      d=$(dirname "$d")
    done
    made=$((made+1))
  done < <(grep -rhE "^[[:space:]]*from[[:space:]]+[A-Za-z_][A-Za-z0-9_.]*[[:space:]]+import[[:space:]]" "$OUT/units" 2>/dev/null | sort -u)

  local base
  while IFS=$'\t' read -r base spec; do
    [ -z "$spec" ] && continue
    names=$(printf '%s' "$spec" | sed -E "s/import( type)? \{//; s/\} from '.*//")
    case "$spec" in
      *"from '@/"*)
        mod=$(printf '%s' "$spec" | sed -E "s/.*from '@\///; s/'$//")
        # `@/*`가 `src/`인지 루트인지는 팩의 배치가 정한다 — 유닛 경로로 판정한다
        # (nextjs는 app/·stores/를 루트에 둔다. src/로 못박으면 정상 import가 전부 미해소가 된다)
        if cut -f2 "$OUT/.units.tsv" | grep -q '^src/'; then target="src/$mod"; else target="$mod"; fi ;;
      *)
        mod=$(printf '%s' "$spec" | sed -E "s/.*from '//; s/'$//")
        target=$(normalize_rel "$base" "$mod") ;;
    esac
    [ -n "$target" ] || continue
    # **TS ESM은 `./model.js`로 쓰고 `model.ts`로 해소된다.** 확장자를 그대로 믿고 스텁하면
    # 실재하는 형제 모듈을 `any`로 덮어 **파일 간 정합성 오류를 통째로 가린다** —
    # firebase 감사 A 실측: tsc 통과가 정합성의 증거가 아니었고, 실경로로 다시 조립해서야
    # TS2307·TS2459가 드러났다. fastapi의 `app/db/models.py`와 같은 부류의 두 번째 재발이다.
    # **팩이 그 경로를 그대로 배송하면 확장자를 바꾸지 않는다.** 위 관용구는 TS 팩의 것이고,
    # JavaScript 팩에서는 `./resource.js`가 **문자 그대로** `resource.js`로 해소된다.
    # 무조건 바꾸면 유닛 경로(`src/state/resource.js`)와 어긋나 고아로 판정돼 스텁을 못 받고,
    # 완전 파일로 주장한 테스트 하네스가 **전부 TS2307**을 받는다 (vanilla 실측: 전 테스트 파일).
    if ! cut -f2 "$OUT/.units.tsv" | grep -qxF "$target"; then
      case "$target" in
        *.js)  target="${target%.js}.ts" ;;
        *.mjs) target="${target%.mjs}.mts" ;;
        *.ts|*.tsx|*.mts) ;;
        *) target="$target.ts" ;;
      esac
    fi
    # **우리가 만든 스텁이면 건너뛰지 않고 빠진 이름만 덧붙인다.** 존재만으로 건너뛰면
    # 첫 import 문의 이름만 들어가고 다른 파일이 쓰는 심볼은 영영 없다 — TS2305가 난다
    # (vanilla 실측: `store.test.js`의 `derive`). 우리 것이 아닌 실파일은 그대로 건너뛴다.
    if [ -f "$OUT/$target" ] && ! grep -qxF "$target" "$OUT/.stubbed.txt" 2>/dev/null; then continue; fi
    # **팩이 그 경로를 「완전 파일」로 주장했으면 스텁하지 않는다.** 유닛은 아직 units/
    # 아래에 있어 파일 존재 검사로는 걸리지 않는다 — 스텁을 얹으면 프로필이 실파일로
    # 옮길 때 같은 심볼이 두 번 선언돼 TS2451이 난다 (aws-serverless 실측 — 오탐).
    # **라벨 발췌는 제외 대상이 아니다** — 복원되지 않으므로 스텁이 없으면 미해소로
    # 남는다 (fastapi 실측: app/http/handlers.py가 라벨이라 스텁을 못 받았다)
    awk -F'\t' '$5=="file"{print $2}' "$OUT/.units.tsv" | grep -qxF "$target" && continue
    # **원장 requires에 없으면 스텁하지 않는다.** 그것은 이음매가 줄 것이 아니라
    # 팩이 스스로 조달했어야 하는 것이고, 스텁으로 덮으면 경로 오기가 사라진다.
    # 정확한 경로가 유닛에 있으면 **팩이 제공하는 것**이다(라벨 발췌이므로 복원만 안 됐다).
    # 고아가 아니므로 예전대로 스텁한다.
    if ! cut -f2 "$OUT/.units.tsv" | grep -qxF "$target" && ! _any_required "$OUT" "$names"; then
      printf '%s\t%s\n' "$target" "$(printf '%s' "$names" | tr -d '\n')" >> "$OUT/.orphan.txt"
      orphan=$((orphan+1)); continue
    fi
    mkdir -p "$OUT/$(dirname "$target")" 2>/dev/null
    if [ ! -f "$OUT/$target" ]; then
      printf '// pack-smoke 스텁 — 원장 requires(이음매 소유). 팩만으로는 해소되지 않는다.\n' > "$OUT/$target"
      printf '%s\n' "$target" >> "$OUT/.stubbed.txt"
      made=$((made+1))
    fi
    # **`.js` 대상에 TS 문법을 쓰지 않는다.** `export type X = any;`는 checkJs 를 켠
    # JavaScript 파일에서 구문 오류이고, 그 오류가 팩 결함으로 보고된다.
    local isjs=0; case "$target" in *.js|*.mjs|*.jsx) isjs=1 ;; esac
    printf '%s\n' "$names" | tr ',' '\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^type[[:space:]]+//; s/[[:space:]]+as[[:space:]]+.*//' \
      | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u | while read -r nm; do
          grep -qE "^export const $nm[ =:]" "$OUT/$target" && continue
          if [ "$isjs" -eq 1 ]; then
            printf '/** @typedef {any} %s */\n' "$nm"
            printf 'export const %s = /** @type {any} */ (undefined);\n' "$nm"
          else
            printf 'export type %s = any;\n' "$nm"
            printf 'export const %s: any = undefined as any;\n' "$nm"
          fi >> "$OUT/$target"
        done
  done < "$OUT/.imports.txt"
  printf '%s' "$made"
}


# ── 2-B. 툴체인 설치 (--online) ─────────────────────────────────────
# **메이저를 고정한다.** 0.x는 마이너까지 읽는다 — semver의 0.y.z에서 y가 파괴적 변경
# 축이고, 마이너를 흘리면 `fastapi@0.141` 같은 항목이 통째로 설치 목록에서 빠진다
# (fastapi 팬인 실측: 12개 중 5개가 조용히 누락됐다).
# 팩이 typescript@5를 확정했는데 `npm i typescript`는 오늘 7.x를
# 받는다 — 다른 메이저의 판정은 이 팩에 대해 「낡음」이 아니라 「틀림」이다.
# 설치가 없으면 tsc는 모듈을 못 찾아 TS2307을 쏟는다. 그래서 typescript만 넣지 않고
# 팩이 선언한 pkgs 전부를 같은 메이저로 넣는다.
install_toolchain() {
  local P="$1" OUT="$2" specs sp
  specs=$(awk '/"pkgs"[[:space:]]*:/{f=1} f{print} f&&/\]/{exit}' "$P/pack.json" 2>/dev/null \
    | grep -oE '"[^"]+@[0-9]+(\.[0-9]+)?"' | tr -d '"' | sort -u | tr '\n' ' ')
  if [ -z "$(printf '%s' "$specs" | tr -d ' ')" ]; then
    skip "pack.json에 메이저가 붙은 pkgs가 없음 — 설치 생략" "타입체크는 프로필이 다시 판정한다"
    return 0
  fi
  # 생태계는 pack.json의 registry가 정한다 (없으면 npm).
  local reg; reg=$(grep -m1 -oE '"registry"[[:space:]]*:[[:space:]]*"[^"]+"' "$P/pack.json" 2>/dev/null | sed -E 's/.*"([^"]+)"$/\1/')
  reg="${reg:-npm}"
  local n; n=$(printf '%s' "$specs" | wc -w | tr -d ' ')

  if [ "$reg" = "pypi" ]; then
    # `name@N` → `name>=N,<N+1`. 메이저 고정의 뜻은 생태계가 달라도 같다.
    local pyspecs="" nm mj
    for sp in $specs; do
      nm="${sp%@*}"; mj="${sp##*@}"; mj="${mj%%.*}"
      case "$mj" in ''|*[!0-9]*) continue ;; esac
      pyspecs="$pyspecs $nm>=$mj,<$((mj+1))"
    done
    local venv="$OUT/.venv"
    if command -v uv >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      if (cd "$OUT" && uv venv "$venv" >/dev/null 2>&1 && uv pip install --python "$venv/bin/python" $pyspecs) >"$OUT/.pip.log" 2>&1; then
        ok "툴체인 설치 (uv) — 메이저 고정 ${n}개"
      else
        skip "툴체인 설치 실패 — 타입체크·스키마 실행은 미검사로 남는다" "$(tail -2 "$OUT/.pip.log" | tr '\n' ' ') — 오프라인이면 정상이다"
      fi
    elif command -v python3 >/dev/null 2>&1; then
      # shellcheck disable=SC2086
      if (cd "$OUT" && python3 -m venv "$venv" >/dev/null 2>&1 && "$venv/bin/pip" install -q $pyspecs) >"$OUT/.pip.log" 2>&1; then
        ok "툴체인 설치 (venv+pip) — 메이저 고정 ${n}개"
      else
        skip "툴체인 설치 실패 — 타입체크·스키마 실행은 미검사로 남는다" "$(tail -2 "$OUT/.pip.log" | tr '\n' ' ') — 오프라인이면 정상이다"
      fi
    else
      skip "uv·python3 없음 — 툴체인 설치 생략" "$specs"
    fi
    return 0
  fi

  command -v npm >/dev/null 2>&1 || { skip "npm 없음 — 툴체인 설치 생략" "$specs"; return 0; }
  printf '{ "name": "pack-smoke", "private": true, "type": "module" }\n' > "$OUT/package.json"
  # shellcheck disable=SC2086
  if (cd "$OUT" && npm i -D --silent --no-audit --no-fund $specs) >"$OUT/.npm.log" 2>&1; then
    ok "툴체인 설치 — 메이저 고정 ${n}개"
  else
    skip "툴체인 설치 실패 — 타입체크는 미검사로 남는다" "$(tail -2 "$OUT/.npm.log" | tr '\n' ' ') — 오프라인이면 정상이다"
  fi
  return 0
}

# ── 3. 보안 벡터: security-vectors.md의 A절을 실제로 돌린다 ─────────
# 실측 최대 발견(오픈 리다이렉트)이 이 부류였고 읽기로는 세 번의 감사가 놓쳤다.
run_vectors() {
  local OUT="$1"
  sec "보안 벡터 (복귀 경로 검증)"
  command -v node >/dev/null 2>&1 || { skip "node 없음 — 벡터 시험 생략" "설치 후 다시 돌린다. 돌리지 않은 것을 돌렸다고 보고하지 않는다"; return 0; }

  local u pth fn found=""
  while IFS=$'\t' read -r u pth _ _; do
    [ -z "$u" ] && continue
    fn=$(grep -oE "export (async )?(function|const) (safe|validate|sanitize)[A-Za-z0-9_]*" "$OUT/units/$u" 2>/dev/null \
         | awk '{print $NF}' | grep -iE '(return|redirect|internal|path|url)' | head -1)
    [ -n "$fn" ] && { found="units/$u|$fn"; break; }
  done < "$OUT/.units.tsv"
  if [ -z "$found" ]; then
    skip "복귀 경로 검증 함수를 찾지 못함" "이 팩이 정의하지 않으면 정상이다 — 정의한다면 첫 줄에 경로 주석을 달아야 복원된다"
    return 0
  fi

  local vf="${found%%|*}" vn="${found##*|}"
  cat > "$OUT/.vectors.mjs" <<'VEC'
const [, , modPath, fnName] = process.argv;
globalThis.window = { location: { origin: 'https://app.example', href: 'https://app.example/' } };
const FB = '/__fallback__';
const ATTACK = [
  ['A1  //host',            '//evil.example'],
  ['A2  /\\host',           '/\\evil.example'],
  ['A3  absolute',          'https://evil.example'],
  ['A4  javascript:',       'javascript:alert(1)'],
  ['A5  /..//host',         '/..//evil.example'],
  ['A6  /../..//host',      '/../..//evil.example'],
  ['A7  encoded //',        '%2f%2fevil.example'],
  ['A8  CRLF',              '/tasks\n\rSet-Cookie: x=1'],
  ['A9  leading tab',       '\tjavascript:alert(1)'],
  ['A10 empty',             ''],
];
const NORMAL = [
  ['A11 query+hash',        '/tasks?filter=open#top'],
  ['A12 nested',            '/tasks/123'],
];
const unsafe = (v) => typeof v !== 'string'
  || !v.startsWith('/') || v.startsWith('//') || v.startsWith('/\\')
  || /^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(v) || /[\x00-\x1f]/.test(v);

const mod = await import(modPath);
const fn = mod[fnName];
if (typeof fn !== 'function') { console.log(`ERR\t함수 ${fnName}를 import할 수 없음`); process.exit(0); }
for (const [label, input] of ATTACK) {
  let out; try { out = fn(input, FB); } catch (e) { out = `THREW ${e.message}`; }
  console.log(`${unsafe(out) ? 'FAIL' : 'PASS'}\t${label}\t${JSON.stringify(input)}\t${JSON.stringify(out)}`);
}
for (const [label, input] of NORMAL) {
  let out; try { out = fn(input, FB); } catch (e) { out = `THREW ${e.message}`; }
  const broken = (out === FB) || unsafe(out);
  console.log(`${broken ? 'FAIL' : 'PASS'}\t${label}\t${JSON.stringify(input)}\t${JSON.stringify(out)}`);
}
VEC

  local res
  res=$(cd "$OUT" && node --experimental-strip-types .vectors.mjs "./$vf" "$vn" 2>&1)
  if ! printf '%s' "$res" | grep -qE '^(PASS|FAIL|ERR)'; then
    skip "벡터 실행 불가 ($vn)" "$(printf '%s' "$res" | tail -2 | tr '\n' ' ')"
    return 0
  fi
  printf '%s\n' "$res" > "$OUT/vector-report.tsv"

  local nf; nf=$(num "$(grep -c '^FAIL' "$OUT/vector-report.tsv" | tr -d ' ')")
  local np; np=$(num "$(grep -c '^PASS' "$OUT/vector-report.tsv" | tr -d ' ')")
  if [ "$nf" -gt 0 ]; then
    bad "$vn — ${nf}/$((nf+np)) 벡터 차단 실패" "$vf"
    grep '^FAIL' "$OUT/vector-report.tsv" | while IFS=$'\t' read -r _ label inp outp; do
      printf "      ${C_R}%-18s${C_0} %s → %s\n" "$label" "$inp" "$outp"
    done
  else
    ok "$vn — 벡터 ${np}건 전부 기대대로 (차단 10 · 정상 통과 2)"
  fi
  return 0
}

# ── 4. 프로필 위임 ──────────────────────────────────────────────────
# 복원된 단위의 확장자로 판정한다 — pack.json의 pkgs 문자열보다 정확하다
# (supabase 팩은 pkgs에 typescript가 없지만 코드는 전부 TS다).
detect_profile() {
  local OUT="$1" exts
  exts=$(cut -f2 "$OUT/.units.tsv" 2>/dev/null | sed -E 's/.*\.//' | sort -u | tr '\n' ' ')
  case " $exts " in
    *" ts "*|*" tsx "*|*" mts "*|*" js "*|*" mjs "*|*" vue "*) printf 'node-ts'; return ;;
  esac
  case " $exts " in *" py "*) printf 'python'; return ;; esac
  printf 'none'
}

run_profile() {
  local P="$1" OUT="$2" prof="$3"
  sec "툴체인 프로필 ($prof)"
  local ps="$SCRIPT_DIR/profiles/$prof.sh"
  if [ ! -f "$ps" ]; then
    skip "프로필 '$prof' 없음 — 빌드·타입체크 생략" "확장점은 profiles/<이름>.sh의 4함수다. 이 팩의 툴체인은 아직 채워지지 않았다"
    return 0
  fi
  # shellcheck disable=SC1090
  . "$ps"
  profile_check "$OUT"
  return 0
}

run_smoke() {
  local P="$1"
  printf "\n${C_D}pack-smoke${C_0}  %s  ${C_D}(작업 %s)${C_0}\n" "$P" "$OUT_DIR"
  [ -d "$P" ] || { printf "팩 디렉토리 없음: %s\n" "$P" >&2; exit 2; }
  [ -f "$P/PACK.md" ] || { printf "PACK.md 없음: %s\n" "$P" >&2; exit 2; }

  sec "코드펜스 복원 (경로 주석이 있는 것만)"
  local n; n=$(extract_files "$P" "$OUT_DIR")
  if [ "$(num "$n")" -eq 0 ]; then
    warn "복원된 펜스 0개" "경로 표시가 붙은 펜스가 없다 — 실행 검증의 대상이 생기지 않는다"
  else
    local nfile nlabel
    nfile=$(num "$(awk -F'\t' '$5=="file"' "$OUT_DIR/.units.tsv" | grep -c .)")
    nlabel=$(num "$(awk -F'\t' '$5=="label"' "$OUT_DIR/.units.tsv" | grep -c .)")
    ok "펜스 ${n}개 복원 — 완전 파일 주장 ${nfile}개 · 라벨 ${nlabel}개"
    [ "$nfile" -eq 0 ] && warn "완전 파일을 주장한 펜스가 0개" "구문·타입 검사의 대상이 없다. 보안 원시함수·설정·테스트 하네스 펜스 앞에 <!-- file: 경로 -->를 단다"
  fi

  local st; st=$(make_stubs "$OUT_DIR" "$P")
  if [ "$(num "$st")" -gt 0 ]; then
    ok "미해소 로컬 import 스텁 ${st}개 생성 (원장 requires)" \
       "$(cut -f1 "$OUT_DIR/.stubbed.txt" 2>/dev/null | tr '\n' ' ')"
  else
    ok "미해소 로컬 import 없음"
  fi

  # **팩이 소유한 파일이 스텁으로 대체됐으면 그것은 통과가 아니라 미검사다.**
  # 원장 provides가 배정한 소스 경로는 팩이 배송하는 것이므로 스텁이 덮어선 안 된다.
  # 덮이면 그 파일의 코드는 타입체크도 실행도 **한 번도 받지 않고** 초록으로 보고된다 —
  # gcp 실측에서 이 축의 보안 경계 전부(`src/firestore/tasks.ts`의 소유권 검사 6함수)가
  # 그 상태였고, 원인은 코드펜스에 `<!-- file: -->` 표시가 없어 유닛으로 복원되지
  # 않은 것이었다. 게이트도 smoke도 WARN조차 내지 않았다.
  local ownstub=0 pp
  if [ -s "$OUT_DIR/.provides.txt" ] && [ -s "$OUT_DIR/.stubbed.txt" ]; then
    while IFS= read -r pp; do
      [ -z "$pp" ] && continue
      case "$pp" in *.d.ts) continue ;; esac        # 라이브러리 타입 선언은 팩 소유가 아니다
      if grep -qxF "$pp" "$OUT_DIR/.stubbed.txt"; then
        bad "팩이 소유한 파일이 스텁으로 대체됨: $pp" \
            "원장 provides가 배정한 경로다. 그 코드펜스에 <!-- file: $pp --> 를 달아 유닛으로 복원시켜라 — 지금 이 파일은 타입체크도 실행도 받지 않았다"
        ownstub=$((ownstub+1))
      fi
    done < "$OUT_DIR/.provides.txt"
  fi
  [ "$ownstub" -eq 0 ] && [ -s "$OUT_DIR/.provides.txt" ] && ok "팩 소유 파일이 스텁으로 대체되지 않음"
  # **원장 requires에 없는데 해소되지 않는 로컬 import는 팩의 결함이다.**
  # 스텁으로 덮으면 경로 오기가 사라진다 — 두 번 재발한 부류다(fastapi `app/db/models.py`,
  # firebase `./model.js`). 둘 다 타입체크를 「통과」시켰고 감사가 실경로로 다시
  # 조립해서야 드러났다.
  # **두 경우를 가른다.** 같은 파일 이름을 팩이 **다른 경로에** 배송했으면 경로 오기이고
  # 그것은 결함이다(FAIL). 그런 이름이 아예 없으면 프로젝트가 만드는 예제 앱 심볼이라
  # 정상이다(WARN — 목록만 남긴다). 가르지 않고 전부 FAIL로 두면 출하 팩 6개가 깨지고,
  # **오탐이 검사를 죽인다.**
  local orph mism=0 illus=0 t nm base
  orph=$(num "$(grep -c . "$OUT_DIR/.orphan.txt" 2>/dev/null | tr -d ' ')")
  if [ "$orph" -gt 0 ]; then
    : > "$OUT_DIR/.mismatch.txt"; : > "$OUT_DIR/.illus.txt"
    while IFS=$'\t' read -r t nm; do
      [ -z "$t" ] && continue
      base=$(basename "$t")
      if cut -f2 "$OUT_DIR/.units.tsv" | grep -qE "(^|/)$base$"; then
        printf '%s\t%s\n' "$t" "$nm" >> "$OUT_DIR/.mismatch.txt"; mism=$((mism+1))
      else
        printf '%s\t%s\n' "$t" "$nm" >> "$OUT_DIR/.illus.txt"; illus=$((illus+1))
      fi
    done < "$OUT_DIR/.orphan.txt"
    if [ "$mism" -gt 0 ]; then
      bad "경로 불일치 ${mism}건 — 같은 파일을 팩이 **다른 경로에** 배송한다" \
          "$(awk -F'\t' '{printf "%s ", $1}' "$OUT_DIR/.mismatch.txt")— import 경로와 배송 경로가 갈렸다. 조립하면 모듈을 찾지 못한다(감사가 실경로로 재조립해야 드러나던 부류다)"
    fi
    [ "$illus" -gt 0 ] && warn "팩이 배송하지 않는 로컬 import ${illus}건" \
        "$(awk -F'\t' '{printf "%s ", $1}' "$OUT_DIR/.illus.txt")— 프로젝트가 만드는 예제 앱 심볼이면 정상이다. 원장의 「예제에 등장하는 앱 심볼」 표에 있는지 확인한다"
  fi

  [ "$ONLINE" -eq 1 ] && { sec "툴체인 설치 (--online)"; install_toolchain "$P" "$OUT_DIR"; }
  [ "$PROFILE" = "auto" ] && PROFILE=$(detect_profile "$OUT_DIR")
  run_profile "$P" "$OUT_DIR" "$PROFILE"
  [ "$NO_VECTORS" -eq 0 ] && run_vectors "$OUT_DIR" || skip "보안 벡터 생략 (--no-vectors)" ""
}

run_self_test() {
  printf "\n${C_D}pack-smoke --self-test${C_0}  (차단 능력 증명)\n"
  local fx="$OUT_DIR/fx"
  mkdir -p "$fx/broken/resources" "$fx/fixed/resources" || { bad "픽스처 생성 실패"; return; }

  local m
  for m in broken fixed; do
    printf '<!-- epcc-pack: frontend/fx v0 -->\n# fx 팩\n' > "$fx/$m/PACK.md"
    printf '{ "axis": "frontend", "name": "fx", "pkgs": ["typescript@5"] }\n' > "$fx/$m/pack.json"
  done

  # 수리 전 형태 — origin만 검사한다. 실측에서 출하본 네 곳이 이 형태였다.
  cat > "$fx/broken/resources/routing.md" <<'FXB'
# 복귀 경로

<!-- file: src/lib/safeReturnTo.ts -->
```ts
// src/lib/safeReturnTo.ts
export function safeReturnTo(raw: unknown, fallback = '/'): string {
  if (typeof raw !== 'string' || raw === '') return fallback;
  try {
    const url = new URL(raw, window.location.origin);
    if (url.origin !== window.location.origin) return fallback;
    return url.pathname + url.search + url.hash;
  } catch { return fallback; }
}
```
FXB

  # 수리 후 형태 — 출력 pathname을 검증한다
  cat > "$fx/fixed/resources/routing.md" <<'FXF'
# 복귀 경로

<!-- file: src/lib/safeReturnTo.ts -->
```ts
// src/lib/safeReturnTo.ts
export function safeReturnTo(raw: unknown, fallback = '/'): string {
  if (typeof raw !== 'string' || raw === '') return fallback;
  try {
    const url = new URL(raw, window.location.origin);
    if (url.origin !== window.location.origin) return fallback;
    const p = url.pathname;
    if (!p.startsWith('/') || p.startsWith('//') || p.startsWith('/\\')) return fallback;
    return p + url.search + url.hash;
  } catch { return fallback; }
}
```
FXF

  # ── 경로 불일치 픽스처 ──────────────────────────────────────────
  # **스텁이 팩의 경로 오기를 덮던 부류.** 두 번 재발했다(fastapi `app/db/models.py`,
  # firebase `./model.js`) — 둘 다 타입체크를 「통과」시켰고 감사가 실경로로 다시
  # 조립해서야 드러났다. 스텁은 원장 requires에만 쓴다.
  mkdir -p "$fx/pathbad/resources" || { bad "경로 픽스처 생성 실패"; return; }
  printf '<!-- epcc-pack: backend/fx v0 -->\n# fx 팩\n' > "$fx/pathbad/PACK.md"
  printf '{ "axis": "backend", "name": "fx", "pkgs": ["typescript@5"] }\n' > "$fx/pathbad/pack.json"
  cat > "$fx/pathbad/ledger.md" <<'FXPL2'
## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `keys` | a.md | `keys.task(o, i) => string` | 키 조립 |

## requires — 이음매가 제공해야 한다

| 심볼 | 종류 | 형태 | 이유 |
| --- | --- | --- | --- |
| `logger` | 프로젝트 | 구조적 로거 | 이음매 소유 |
FXPL2
  cat > "$fx/pathbad/resources/a.md" <<'FXPA2'
# 키

<!-- file: src/db/keys.ts -->
```ts
export const keys = { task: (o: string, i: string) => `${o}#${i}` }
```

<!-- file: src/db/tasks.ts -->
```ts
import { keys } from '../model/keys'
export const pk = keys.task('a', 'b')
```
FXPA2

  # ── Python 프로필 픽스처 ────────────────────────────────────────
  # 실측 최악의 결함은 **문법이 완벽한 스키마**였다 — partial()과 default()가 겹쳐
  # 부분 수정이 보내지 않은 필드를 덮어썼고 실행만이 그것을 드러냈다.
  # Pydantic v2에서 같은 부류는 「선택 필드에 None 아닌 기본값」으로 재발한다.
  mkdir -p "$fx/py-ok/resources" "$fx/py-bad/resources" || { bad "python 픽스처 생성 실패"; return; }
  for m in py-ok py-bad; do
    printf '<!-- epcc-pack: backend/fx v0 -->\n# fx 팩\n' > "$fx/$m/PACK.md"
    printf '{ "axis": "backend", "name": "fx", "registry": "pypi", "pkgs": ["pydantic@2"] }\n' > "$fx/$m/pack.json"
  done
  cat > "$fx/py-ok/resources/schemas.md" <<'FXPOK'
# 스키마

<!-- file: app/schemas.py -->
```python
# app/schemas.py
from pydantic import BaseModel, ConfigDict


class TaskUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str | None = None
    status: str | None = None
```
FXPOK
  cat > "$fx/py-bad/resources/schemas.md" <<'FXPBAD'
# 스키마

<!-- file: app/schemas.py -->
```python
# app/schemas.py
from pydantic import BaseModel, ConfigDict


class TaskUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    title: str | None = None
    status: str = "open"
    priority: int = 0
```
FXPBAD

  # ── 마크업·스타일 시트를 구문 오류로 판정하지 않는다 (오탐) ──
  # 프론트엔드 축 팩은 `index.html`·`styles.css`를 완전 파일로 주장한다. Node의 타입
  # 스트리핑은 그것들을 파싱하지 못하는데 분류기가 **구문 오류**로 셌다 — 실측에서
  # 정상 팩이 FAIL 2를 받았다. 오탐 하나가 검사를 죽인다.
  mkdir -p "$fx/js-markup/resources" || { bad "마크업 픽스처 생성 실패"; return; }
  printf '<!-- epcc-pack: frontend/fx v0 -->\n# fx 팩\n' > "$fx/js-markup/PACK.md"
  printf '{ "axis": "frontend", "name": "fx", "pkgs": ["typescript@7"] }\n' > "$fx/js-markup/pack.json"
  cat > "$fx/js-markup/resources/entry.md" <<'FXJSM'
# 진입점

<!-- file: index.html -->
```html
<!doctype html>
<html lang="ko"><body><div id="app"></div></body></html>
```

<!-- file: src/styles.css -->
```css
:root { --gap: 8px; }
```

<!-- file: src/main.js -->
```js
/**
 * @param {string} id
 * @returns {number}
 */
export function mount(id) { return id }
```

<!-- file: entry.js -->
```js
/** @type {number} */
export const answer = 'not a number'
```
FXJSM

  # ── JS 팩 스텁 픽스처 — 라벨 소스 + 완전 파일 테스트 ──────────────
  # vanilla(첫 JavaScript 축)에서 pack-smoke의 JS 결함 4종이 실물로만 드러났다:
  # ⓐ `./x.js`를 무조건 `x.ts`로 바꿔 유닛 경로와 어긋나 스텁을 못 받았고(TS2307)
  # ⓑ `.js` 스텁에 TS 문법을 써서 checkJs가 구문 오류를 냈고
  # ⓒ 파일 존재만으로 건너뛰어 두 번째 import 문의 이름이 빠졌고(TS2305)
  # ⓓ JSDoc `import('...').Type`을 import로 보지 않아 타입이 빠졌다(TS2694).
  # 넷 다 **tsc 없이** 산출물(스텁 파일)로 판정할 수 있다 — 오프라인에서도 도는 픽스처다.
  mkdir -p "$fx/js-stub/resources" || { bad "JS 스텁 픽스처 생성 실패"; return; }
  printf '<!-- epcc-pack: frontend/fxjs v0 -->\n# fxjs 팩\n' > "$fx/js-stub/PACK.md"
  printf '{ "axis": "frontend", "name": "fxjs", "pkgs": ["typescript@7"] }\n' > "$fx/js-stub/pack.json"
  # 원장이 소스 경로를 선언하면 그 경로가 스텁으로 덮이는 것은 **미검사**다 — FAIL 이어야 한다.
  # gcp 의 소유권 검사 6함수와 vanilla 의 6모듈이 정확히 이 상태로 초록이었다.
  cat > "$fx/js-stub/ledger.md" <<'FXJSL'
## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `createStore` | store.md | **`src/store/create.js`** — `(initial) => store` | 스토어 |

## requires — 이음매가 제공해야 한다

| 심볼 | 종류 | 형태 | 이유 |
| --- | --- | --- | --- |
| `Task` | 프로젝트 | 도메인 타입 | 이음매 소유 |
FXJSL
  cat > "$fx/js-stub/resources/store.md" <<'FXJSS'
# 스토어

```js
// src/store/create.js
export function createStore(initial) { return initial }
export function derive(store, fn) { return fn(store) }
```

```js
// src/schemas/task.js
/** @typedef {{ id: string }} Task */
export const TASK_KEY = 'task'
```

<!-- file: test/a.test.js -->
```js
import { createStore } from '../src/store/create.js'
/** @typedef {import('../src/schemas/task.js').Task} Task */
export const a = createStore(1)
```

<!-- file: test/b.test.js -->
```js
import { derive } from '../src/store/create.js'
export const b = derive(1, (x) => x)
```
FXJSS

  local out code
  sec "양성 픽스처 (차단해야 한다)"
  out=$(bash "$0" --pack "$fx/broken" --no-vectors 2>&1); code=$?
  [ "$code" -eq 0 ] && ok "추출·스텁 단계는 결함 없는 팩을 통과시킨다 → exit 0" || bad "추출 단계가 이유 없이 실패 → exit $code"

  code=0; out=$(bash "$0" --pack "$fx/broken" 2>&1) || code=$?
  if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q '차단 실패'; then
    ok "수리 전 safeReturnTo → exit 1 ($(printf '%s' "$out" | grep -oE '[0-9]+/[0-9]+ 벡터 차단 실패'))"
    printf '%s\n' "$out" | grep -E '^      .*A[0-9]' | head -3
  else
    bad "수리 전 safeReturnTo가 차단되지 않음 → exit $code" "$(printf '%s' "$out" | grep -E '✓|✗|–' | tail -2 | tr '\n' ';')"
  fi

  code=0; out=$(bash "$0" --pack "$fx/pathbad" --no-vectors 2>&1) || code=$?
  if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q '경로 불일치'; then
    ok "같은 파일을 다른 경로에서 import → exit 1 (의도한 이유로)"
    [ -n "${EPCC_FX_WHY:-}" ] && printf "      ${C_D}%s${C_0}\n" "$(printf '%s' "$out" | grep '✗' | head -1 | sed 's/^  *//')"
  else
    bad "경로 불일치를 잡지 못한다 → exit $code" "$(printf '%s' "$out" | grep -E '✗|!' | head -2 | tr '\n' ';')"
  fi

  code=0; out=$(bash "$0" --pack "$fx/py-bad" --no-vectors 2>&1) || code=$?
  if [ "$code" -eq 1 ] && printf '%s' "$out" | grep -q '부분 수정이 보내지 않은 필드를 채운다'; then
    ok "부분 수정 스키마의 기본값 → exit 1 (의도한 이유로)"
    [ -n "${EPCC_FX_WHY:-}" ] && printf "      ${C_D}%s${C_0}\n" "$(printf '%s' "$out" | grep '✗' | head -1 | sed 's/^  *//')"
  elif [ "$code" -ne 1 ]; then
    bad "부분 수정 스키마의 기본값 → exit $code (기대 1)" "python 프로필이 이 부류를 잡지 못한다"
  else
    bad "exit 1이지만 **다른 이유**다" "$(printf '%s' "$out" | grep '✗' | head -2 | tr '\n' ';')"
  fi

  sec "무해 픽스처 (통과해야 한다)"
  code=0; out=$(bash "$0" --pack "$fx/py-ok" --no-vectors 2>&1) || code=$?
  [ "$code" -eq 0 ] && ok "선택 필드가 전부 None 기본값 → exit 0 (오탐 없음)" \
    || bad "정상 Pydantic 스키마를 FAIL시킨다 → exit $code" "$(printf '%s' "$out" | grep '✗' | head -2 | tr '\n' ';')"

  code=0; out=$(bash "$0" --pack "$fx/js-markup" --no-vectors --keep --out "$fx/out-js" 2>&1) || code=$?
  if printf '%s' "$out" | grep -q '파싱하지 않는'; then
    ok "html·css 완전 파일 주장 → 구문 오류가 아니라 미검사로 보고"
  else
    bad "마크업·스타일 시트를 구문 오류로 판정한다" "$(printf '%s' "$out" | grep '✗' | head -2 | tr '\n' ';')"
  fi

  # **검사가 도는 것과 검사가 대상을 보는 것은 다르다.** tsc 는 오프라인에서 없을 수 있으므로
  # 판정 자체가 아니라 **판정의 전제**(생성된 tsconfig)를 단언한다 — 이 둘이 틀리면 JSDoc
  # 타입 오류를 심어도 「타입체크 통과」가 난다(실측 — 미탐).
  if [ -f "$fx/out-js/tsconfig.json" ]; then
    if grep -q '"checkJs": true' "$fx/out-js/tsconfig.json"; then
      ok "JS 팩 → checkJs 켜짐 (allowJs 만으로는 JSDoc 타입이 하나도 검사되지 않는다)"
    else
      bad "JS 팩인데 checkJs 가 꺼져 있다" "$(grep -o 'checkJs[^,]*' "$fx/out-js/tsconfig.json")"
    fi
    if grep -q '"\*\.js"' "$fx/out-js/tsconfig.json"; then
      ok "루트 JS 가 include 에 있다 (\"*.ts\"만 두면 main.js 가 tsc 시야 밖이다)"
    else
      bad "루트 JS 가 include 에 없다" "$(grep -o '"include".*' "$fx/out-js/tsconfig.json")"
    fi
  else
    bad "tsconfig 가 생성되지 않았다" "$fx/out-js/tsconfig.json 없음 — 판정의 전제를 확인할 수 없다"
  fi

  code=0; out=$(bash "$0" --pack "$fx/fixed" --no-vectors --keep --out "$fx/out-ts" 2>&1) || code=$?
  if [ -f "$fx/out-ts/tsconfig.json" ] && grep -q '"checkJs": false' "$fx/out-ts/tsconfig.json"; then
    ok "TS 팩 → checkJs 꺼짐 (전역으로 켜면 TS 팩이 배송하는 설정 조각이 오탐된다)"
  else
    bad "TS 팩에서 checkJs 가 켜졌다" "설정 조각(vite.config.js 류)이 새로 검사 대상이 되어 오탐이 난다"
  fi

  # ── 데코레이터 팩 (node-nest 실측) ─────────────────────────────────
  # 두 가지를 단언한다. 판정 자체가 아니라 **판정의 전제**다 — tsc 는 오프라인에서 없다.
  #   ⓐ experimentalDecorators 가 켜지는가. 꺼져 있으면 TypeScript 가 데코레이터를
  #     ES 표준으로 읽어 **파라미터 데코레이터가 전부 오류**가 된다 (TS1240 — 오탐)
  #   ⓑ strip-only 모드가 거부한 단위가 실트리에 놓이는가. 놓이지 않으면 tsc 가 있어도
  #     그 파일은 **영영 검사되지 않는다** — NestJS 는 생성자 주입이 곧 파라미터
  #     프로퍼티라 서비스·컨트롤러가 통째로 빠졌다 (미탐)
  mkdir -p "$fx/deco/resources" || { bad "데코레이터 픽스처 생성 실패"; return; }
  printf '<!-- epcc-pack: backend/fx v0 -->\n# fx 팩\n' > "$fx/deco/PACK.md"
  printf '{ "axis": "backend", "name": "fx", "pkgs": ["typescript@5"] }\n' > "$fx/deco/pack.json"
  cat > "$fx/deco/resources/a.md" <<'FXDECO'
# 서비스

<!-- file: src/tasks.service.ts -->
```ts
import { Injectable } from '@nestjs/common';
import { Repo } from './repo';

@Injectable()
export class TasksService {
  constructor(private readonly repo: Repo) {}

  find(id: string): string {
    return this.repo.get(id);
  }
}
```
FXDECO

  code=0; out=$(bash "$0" --pack "$fx/deco" --no-vectors --keep --out "$fx/out-deco" 2>&1) || code=$?
  if [ -f "$fx/out-deco/tsconfig.json" ] && grep -q '"experimentalDecorators": true' "$fx/out-deco/tsconfig.json"; then
    ok "데코레이터 팩 → experimentalDecorators 켜짐 (꺼지면 정상 Nest 코드가 TS1240으로 전부 실패한다)"
  else
    bad "데코레이터 팩인데 experimentalDecorators 가 꺼져 있다" "$(grep -o 'experimentalDecorators[^,]*' "$fx/out-deco/tsconfig.json" 2>/dev/null)"
  fi
  if [ -f "$fx/out-deco/src/tasks.service.ts" ]; then
    ok "strip-only 가 거부한 단위도 실트리에 놓인다 (파라미터 프로퍼티가 타입체크 밖으로 새지 않는다)"
  else
    bad "파라미터 프로퍼티 파일이 실트리에 없다" "복원은 됐는데 타입체크 대상 트리에 놓이지 않았다 — tsc 가 있어도 영영 검사되지 않는다"
  fi
  if [ -f "$fx/out-ts/tsconfig.json" ] && grep -q '"experimentalDecorators": false' "$fx/out-ts/tsconfig.json"; then
    ok "데코레이터 없는 TS 팩 → experimentalDecorators 꺼짐 (감지가 항상-켬이 아니다)"
  else
    bad "데코레이터가 없는데 experimentalDecorators 가 켜졌다" "감지가 무조건 참이면 그 검사는 아무것도 가르지 않는다"
  fi


  code=0; out=$(bash "$0" --pack "$fx/js-stub" --no-vectors --keep --out "$fx/out-jsstub" 2>&1) || code=$?
  local stub="$fx/out-jsstub/src/store/create.js"
  if [ -f "$stub" ]; then
    ok "JS 팩의 라벨 소스가 .js 로 스텁된다 (.ts 로 바꾸면 유닛과 어긋나 TS2307)"
    grep -q '@typedef' "$stub" && ok "스텁이 JSDoc 문법이다 (.js 에 export type 을 쓰면 checkJs 가 구문 오류를 낸다)" \
      || bad "JS 스텁에 TS 문법을 썼다" "$(head -3 "$stub" | tr '\n' ';')"
    if grep -q 'createStore' "$stub" && grep -q 'derive' "$stub"; then
      ok "스텁이 여러 import 문의 이름을 합친다 (첫 문만 넣으면 TS2305)"
    else
      bad "스텁이 두 번째 import 문의 이름을 빠뜨렸다" "$(grep -c 'export const' "$stub") 개만 선언됨"
    fi
  else
    bad "JS 팩의 라벨 소스에 스텁이 생기지 않았다" "$stub 없음 — 완전 파일 테스트가 전부 TS2307을 받는다"
  fi
  # 팩 소유 파일이 스텁으로 대체되면 FAIL 이어야 한다 (양성) — 위 --pack 실행의 exit 를 본다
  if printf '%s' "$out" | grep -q '팩이 소유한 파일이 스텁으로 대체됨'; then
    ok "팩 소유 파일이 스텁으로 덮이면 잡는다 (미검사가 초록으로 보고되던 자리)"
  else
    bad "팩 소유 파일이 스텁으로 덮였는데 통과시킨다" "원장 provides 가 배정한 경로다 — 그 코드는 타입체크도 실행도 받지 않는다"
  fi

  if [ -f "$fx/out-jsstub/src/schemas/task.js" ] && grep -q 'Task' "$fx/out-jsstub/src/schemas/task.js"; then
    ok "JSDoc import('...').Type 도 스텁 대상이다 (안 보면 TS2694)"
  else
    bad "JSDoc 타입 import 가 스텁에 반영되지 않았다" "JS 팩은 타입을 import { } 로 끌어오지 않는다"
  fi

  code=0; out=$(bash "$0" --pack "$fx/fixed" 2>&1) || code=$?
  if [ "$code" -eq 0 ]; then ok "수리 후 safeReturnTo → exit 0 (오탐 없음)"
  else bad "수리된 형태가 오탐됨 → exit $code" "$(printf '%s' "$out" | grep '✗' | head -2 | tr '\n' ';')"; fi
}

# ════════════════════════════════════════════════════════════════════
MODE=""; PACK=""; PROFILE="auto"; OUT_DIR=""; KEEP=0; NO_VECTORS=0; ONLINE=0

[ $# -eq 0 ] && { printf "인자 없음 (--help 참조)\n" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pack)        MODE="smoke"; PACK="${2:-}"; shift 2 || exit 2 ;;
    --profile)     PROFILE="${2:-}"; shift 2 || exit 2 ;;
    --out)         OUT_DIR="${2:-}"; shift 2 || exit 2 ;;
    --keep)        KEEP=1; shift ;;
    --no-vectors)  NO_VECTORS=1; shift ;;
    --online)      ONLINE=1; shift ;;
    --self-test)   MODE="selftest"; shift ;;
    -h|--help)     sed -n '2,25p' "$0" | sed -E 's/^#[[:space:]]?//'; exit 0 ;;
    *)             printf "알 수 없는 옵션: %s (--help 참조)\n" "$1" >&2; exit 2 ;;
  esac
done

if [ -z "$OUT_DIR" ]; then
  OUT_DIR=$(mktemp -d 2>/dev/null) || { printf "작업 디렉토리 생성 실패\n" >&2; exit 2; }
  [ "$KEEP" -eq 0 ] && trap 'rm -rf "$OUT_DIR"' EXIT
else
  mkdir -p "$OUT_DIR" || exit 2
fi

case "$MODE" in
  smoke)    [ -n "$PACK" ] || { printf -- "--pack <디렉토리> 필요\n" >&2; exit 2; }; run_smoke "$PACK" ;;
  selftest) run_self_test ;;
  *)        printf "모드 없음: --pack 또는 --self-test (--help 참조)\n" >&2; exit 2 ;;
esac

printf "\n${C_D}────────────────────────────────────────────${C_0}\n"
printf "  통과 %s · ${C_Y}WARN %s${C_0} · ${C_C}SKIP %s${C_0} · ${C_R}FAIL %s${C_0}\n" "$PASS" "$WARN" "$SKIP" "$FAIL"
[ "$KEEP" -eq 1 ] && printf "  ${C_D}작업 디렉토리: %s${C_0}\n" "$OUT_DIR"
printf "\n"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
