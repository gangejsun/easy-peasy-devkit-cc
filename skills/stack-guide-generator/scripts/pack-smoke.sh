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

# ── 2. 스텁: 해소되지 않는 로컬 import를 채운다 ─────────────────────
# 원장의 requires는 이음매가 줄 것이므로 팩만 놓고 보면 항상 미해소다.
# 그것을 스텁으로 채워야 타입체크가 "이음매 미구현"이 아니라 팩 자신의 결함을 본다.
make_stubs() {
  local OUT="$1" made=0 spec names mod target
  [ -s "$OUT/.units.tsv" ] || { printf '0'; return 0; }

  grep -rhoE "import( type)? \{[^}]*\} from '@/[^']*'" "$OUT/units" 2>/dev/null \
    | sort -u > "$OUT/.imports.txt"

  while IFS= read -r spec; do
    [ -z "$spec" ] && continue
    mod=$(printf '%s' "$spec" | sed -E "s/.*from '@\///; s/'$//")
    names=$(printf '%s' "$spec" | sed -E "s/import( type)? \{//; s/\} from '.*//")
    target="src/$mod"
    case "$target" in *.ts|*.tsx) ;; *) target="$target.ts" ;; esac
    [ -f "$OUT/$target" ] && continue
    mkdir -p "$OUT/$(dirname "$target")" 2>/dev/null
    {
      printf '// pack-smoke 스텁 — 원장 requires(이음매 소유). 팩만으로는 해소되지 않는다.\n'
      printf '%s\n' "$names" | tr ',' '\n' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^type[[:space:]]+//; s/[[:space:]]+as[[:space:]]+.*//' \
        | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | sort -u | while read -r nm; do
            printf 'export type %s = any;\n' "$nm"
            printf 'export const %s: any = undefined as any;\n' "$nm"
          done
    } >> "$OUT/$target"
    made=$((made+1))
  done < "$OUT/.imports.txt"
  printf '%s' "$made"
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

  local st; st=$(make_stubs "$OUT_DIR")
  [ "$(num "$st")" -gt 0 ] && ok "미해소 로컬 import 스텁 ${st}개 생성 (원장 requires)" || ok "미해소 로컬 import 없음"

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

  sec "무해 픽스처 (통과해야 한다)"
  code=0; out=$(bash "$0" --pack "$fx/fixed" 2>&1) || code=$?
  if [ "$code" -eq 0 ]; then ok "수리 후 safeReturnTo → exit 0 (오탐 없음)"
  else bad "수리된 형태가 오탐됨 → exit $code" "$(printf '%s' "$out" | grep '✗' | head -2 | tr '\n' ';')"; fi
}

# ════════════════════════════════════════════════════════════════════
MODE=""; PACK=""; PROFILE="auto"; OUT_DIR=""; KEEP=0; NO_VECTORS=0

[ $# -eq 0 ] && { printf "인자 없음 (--help 참조)\n" >&2; exit 2; }
while [ $# -gt 0 ]; do
  case "$1" in
    --pack)        MODE="smoke"; PACK="${2:-}"; shift 2 || exit 2 ;;
    --profile)     PROFILE="${2:-}"; shift 2 || exit 2 ;;
    --out)         OUT_DIR="${2:-}"; shift 2 || exit 2 ;;
    --keep)        KEEP=1; shift ;;
    --no-vectors)  NO_VECTORS=1; shift ;;
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
