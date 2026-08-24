#!/bin/bash
# profiles/python.sh — pack-smoke.sh의 Python 프로필
#
# 프로필 계약은 함수 하나다: profile_check <작업디렉토리>.
# 그 안에서 이 툴체인이 할 수 있는 검사를 돌리고 ok/warn/bad/skip으로 보고한다
# (그 4함수와 num()은 pack-smoke.sh가 정의한다). 종료 코드를 만들지 않는다 —
# 판정 합산은 호출자가 한다.
#
# **의존성이 없으면 skip을 명시 보고한다.** 침묵 통과는 "검사했는데 깨끗함"과
# 구분되지 않고, 그것이 이 하네스가 대체하려는 실패 모드다.
#
# node-ts.sh와 같은 세 층이다: 구문(오프라인) → 타입(있으면) → 스키마 실행.
# 세 번째가 이 프로필의 존재 이유다 — 실측 최악의 결함은 문법이 완벽한 스키마였고
# **실행만이** 부분 업데이트가 필드를 덮어쓰는 것을 드러냈다.

profile_check() {
  local OUT="$1"
  [ -s "$OUT/.units.tsv" ] || { skip "복원 단위 없음 — 검사 대상 없음"; return 0; }
  local PY=""
  command -v python3 >/dev/null 2>&1 && PY="python3"
  [ -z "$PY" ] && command -v python >/dev/null 2>&1 && PY="python"
  [ -z "$PY" ] && { skip "python 없음 — 구문·타입 검사 생략"; return 0; }

  # ── 구문: 네트워크 없이 돈다 ──
  # 경로를 주장하는 펜스가 전부 완전한 파일인 것은 아니다. 들여쓰기된 메서드 본문이나
  # 설정 조각이 실재하는 관용구다. 조각을 구문 오류로 판정하면 위양성이 되고, 반대로
  # 전부 눈감으면 진짜 절단면을 놓친다. **표준 삽입 문맥에 넣어 컴파일되면 조각**,
  # 어디에도 안 들어가면 구문 오류로 가른다 (node-ts.sh와 같은 규율).
  cat > "$OUT/.classify.py" <<'CLS'
import sys, os, textwrap
d = sys.argv[1]
only = sys.argv[2:]

def compiles(src):
    try:
        compile(src, "<probe>", "exec")
        return True
    except SyntaxError:
        return False

files = only if only else sorted(os.listdir(d))
for f in files:
    p = os.path.join(d, f)
    if not os.path.isfile(p):
        continue
    src = open(p, encoding="utf-8").read()
    if f.endswith(".toml"):
        try:
            import tomllib
            tomllib.loads(src)
            print("FILE\t%s" % f)
        except ModuleNotFoundError:
            print("UNSUP\t%s\ttomllib 없음 (Python 3.11+ 필요)" % f)
        except Exception as e:
            print("FRAG\t%s\tTOML 조각: %s" % (f, str(e).split("\n")[0]))
        continue
    if not f.endswith(".py"):
        print("UNSUP\t%s\t.py도 .toml도 아니다" % f)
        continue
    if compiles(src):
        print("FILE\t%s" % f)
        continue
    body = textwrap.indent(src, "    ")
    if compiles("if True:\n" + body):
        print("FRAG\t%s\t문(statement) 조각" % f)
        continue
    if compiles("class __C:\n" + body):
        print("FRAG\t%s\t클래스 본문 조각" % f)
        continue
    try:
        compile(src, f, "exec")
        msg = ""
    except SyntaxError as e:
        msg = "%s (line %s)" % (e.msg, e.lineno)
    print("SYNTAX\t%s\t%s" % (f, msg))
CLS

  # 완전 파일을 주장한 단위만 검사한다. 라벨 단위는 조각인 것이 정상이므로
  # 구문 오류로 판정하면 전부 위양성이 된다.
  local claimed; claimed=$(awk -F'\t' '$5=="file" {print $1}' "$OUT/.units.tsv" | tr '\n' ' ')
  if [ -z "$(printf '%s' "$claimed" | tr -d ' ')" ]; then
    skip "완전 파일 주장 0개 — 구문·타입 검사 생략" "라벨(# 경로)만으로는 완전한 파일인지 알 수 없다. <!-- file: 경로 -->로 주장한 펜스만 검사한다"
    return 0
  fi
  # shellcheck disable=SC2086
  "$PY" "$OUT/.classify.py" "$OUT/units" $claimed 2>/dev/null > "$OUT/.classify.tsv"
  [ -s "$OUT/.classify.tsv" ] || { skip "구문 분류 실행 불가" "$PY가 분류기를 돌리지 못했다"; return 0; }

  local nfile nfrag nsyn nuns v u msg pth
  nfile=$(num "$(grep -c '^FILE' "$OUT/.classify.tsv" | tr -d ' ')")
  nfrag=$(num "$(grep -c '^FRAG' "$OUT/.classify.tsv" | tr -d ' ')")
  nsyn=$(num "$(grep -c '^SYNTAX' "$OUT/.classify.tsv" | tr -d ' ')")
  nuns=$(num "$(grep -c '^UNSUP' "$OUT/.classify.tsv" | tr -d ' ')")
  [ "$nuns" -gt 0 ] && skip "구문 미검사 ${nuns}개" "$(awk -F'\t' '$1=="UNSUP"{printf "%s(%s) ", $2, substr($3,1,40)}' "$OUT/.classify.tsv")— 이 프로필이 다루는 것은 .py와 .toml이다"
  [ "$nfrag" -gt 0 ] && warn "완전 파일이라 주장했으나 조각 ${nfrag}개" "$(awk -F'\t' '$1=="FRAG"{printf "%s(%s) ", $2, $3}' "$OUT/.classify.tsv")— <!-- file: --> 대신 라벨(# 경로)을 쓰거나, 펜스를 완전한 파일로 만든다"

  if [ "$nsyn" -gt 0 ]; then
    while IFS=$'\t' read -r v u msg; do
      [ "$v" = "SYNTAX" ] || continue
      pth=$(awk -F'\t' -v u="$u" '$1==u {print $2" ("$3":"$4")"}' "$OUT/.units.tsv")
      bad "구문 오류: $pth" "$msg"
    done < "$OUT/.classify.tsv"
  else
    ok "구문 검사 통과 — 주장한 완전 파일 ${nfile}개"
  fi

  # 완전 파일만 실제 트리로 옮긴다 (조각은 타입체크 대상이 아니다)
  local dst
  while IFS=$'\t' read -r v u msg; do
    [ "$v" = "FILE" ] || continue
    dst=$(awk -F'\t' -v u="$u" '$1==u {print $2}' "$OUT/.units.tsv")
    [ -n "$dst" ] || continue
    mkdir -p "$OUT/$(dirname "$dst")" 2>/dev/null
    cat "$OUT/units/$u" >> "$OUT/$dst"
  done < "$OUT/.classify.tsv"

  # ── 타입체크: 의존성이 필요하다 ──
  local tc=""
  [ -x "$OUT/.venv/bin/pyright" ] && tc="$OUT/.venv/bin/pyright"
  [ -z "$tc" ] && command -v pyright >/dev/null 2>&1 && tc="pyright"
  [ -z "$tc" ] && [ -x "$OUT/.venv/bin/mypy" ] && tc="$OUT/.venv/bin/mypy"
  [ -z "$tc" ] && command -v mypy >/dev/null 2>&1 && tc="mypy"
  if [ -z "$tc" ]; then
    skip "pyright·mypy 없음 — 타입체크 생략" "오프라인이면 정상이다. --online이 팩의 pkgs를 설치한다 — 이 항목은 **미검사**이지 통과가 아니다"
  else
    # **pyright에 인터프리터를 알려준다.** 안 주면 시스템 파이썬을 보고
    # `가져오기 "sqlalchemy"을(를) 확인할 수 없습니다`를 쏟는다 — 정상 팩이 전부
    # 타입체크 실패가 된다 (fastapi 팬인 실측 — 오탐).
    local tout tcode=0 pyargs=""
    [ -x "$OUT/.venv/bin/python" ] && case "$tc" in
      *pyright) pyargs="--pythonpath $OUT/.venv/bin/python" ;;
      *mypy)    pyargs="--python-executable $OUT/.venv/bin/python" ;;
    esac
    # shellcheck disable=SC2086
    tout=$(cd "$OUT" && "$tc" $pyargs app 2>&1) || tcode=$?
    if [ "$tcode" -eq 0 ]; then
      ok "타입체크 통과 ($tc)"
    else
      bad "타입체크 실패 ($tc)" "$(printf '%s' "$tout" | grep -E 'error' | head -3 | tr '\n' ';')"
    fi
  fi

  # ── 스키마 실행 ──
  # **실측 최악의 결함은 문법이 완벽한 스키마였다.** partial()과 default()가 겹쳐
  # 부분 업데이트가 보내지 않은 필드를 기본값으로 덮어썼고, 실행만이 그것을 드러냈다.
  # Pydantic v2에서 같은 부류는 `exclude_unset`을 안 쓴 `model_dump()`로 재발한다.
  _pyd_probe "$OUT" "$PY"
  return 0
}

_pyd_probe() {
  local OUT="$1" PY="$2" pybin="$PY"
  [ -x "$OUT/.venv/bin/python" ] && pybin="$OUT/.venv/bin/python"
  "$pybin" -c 'import pydantic' >/dev/null 2>&1 || {
    skip "pydantic 없음 — 스키마 실행 생략" "가이드가 검증 라이브러리를 고정했다면 이 검사가 **읽기로는 안 잡히는 부류**를 잡는다"
    return 0
  }
  # 팩이 정의한 스키마 파일을 찾는다. 없으면 검사 대상이 없는 것이지 통과가 아니다.
  local sf; sf=$({ grep -rl 'BaseModel' "$OUT/app" 2>/dev/null || true; } | head -3 | tr '\n' ' ')
  if [ -z "$(printf '%s' "$sf" | tr -d ' ')" ]; then
    skip "BaseModel을 정의한 파일 없음 — 스키마 실행 생략" "완전 파일로 주장한 펜스에만 걸린다"
    return 0
  fi
  cat > "$OUT/.pydprobe.py" <<'PRB'
import sys, os, importlib.util, inspect
sys.path.insert(0, os.getcwd())
from pydantic import BaseModel, ValidationError


def probe(name, obj, fields):
    # ① 빈 객체 — 필수 필드가 실제로 거부되는가
    required = [k for k, f in fields.items() if f.is_required()]
    try:
        obj()
        empty = "통과"
    except ValidationError:
        empty = "거부"
    print("EMPTY\t%s\t%s\t필수 %d개" % (name, empty, len(required)))

    # ② 필드 1개만 담은 부분 업데이트 — **보내지 않은 필드가 채워져 나오는가**
    #    exclude_unset 없이 dump하는 것이 흔한 저장 경로다. 그때 기본값이 실려
    #    나오면 부분 수정이 나머지 필드를 덮어쓴다 (실측 최악의 결함이 이 부류).
    one = None
    for k in fields:
        for cand in ("x", 1, True):
            try:
                one = (k, obj(**{k: cand}))
                break
            except ValidationError:
                continue
        if one:
            break
    if one:
        k, inst = one
        dumped = inst.model_dump()
        filled = [x for x, v in dumped.items() if x != k and v is not None]
        print("PARTIAL\t%s\t%s\t%s" % (name, k, ",".join(filled) or "-"))
    else:
        print("PARTIAL\t%s\t-\tERR 단일 필드로 만들 수 없다" % name)

    # ③ 미지 키 — 통과·제거·거부 중 무엇인가
    try:
        obj.model_validate({"__zzz__": 1}, strict=False)
        unknown = "통과"
    except ValidationError as e:
        unknown = "거부" if "extra" in str(e).lower() else "필수누락(미지키는 무시)"
    except Exception:
        unknown = "확인불가"
    print("UNKNOWN\t%s\t%s" % (name, unknown))


found = 0
for path in sys.argv[1:]:
    mod_name = path.replace("/", ".").removesuffix(".py")
    spec = importlib.util.spec_from_file_location(mod_name, path)
    if spec is None or spec.loader is None:
        continue
    m = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(m)
    except Exception as e:
        print("LOAD\t%s\t%s" % (path, str(e).split("\n")[0]))
        continue
    for name, obj in vars(m).items():
        if not (inspect.isclass(obj) and issubclass(obj, BaseModel) and obj is not BaseModel):
            continue
        fields = getattr(obj, "model_fields", {})
        if not fields:
            continue
        found += 1
        try:
            probe(name, obj, fields)
        except Exception as e:
            # **한 모델의 실패가 나머지를 삼키면 안 된다** — 스키마 실행이 통째로
            # skip이 되어 이 프로필의 존재 이유가 사라진다 (fastapi 팬인 실측).
            print("CLSERR\t%s\t%s" % (name, str(e).split("\n")[0]))
print("FOUND\t%d" % found)
PRB
  local out
  # shellcheck disable=SC2086
  out=$(cd "$OUT" && "$pybin" .pydprobe.py $sf 2>&1)
  local nfound; nfound=$(num "$(printf '%s' "$out" | awk -F'\t' '$1=="FOUND"{print $2}' | tail -1)")
  if [ "$nfound" -eq 0 ]; then
    skip "스키마 클래스를 적재하지 못했다" "$(printf '%s' "$out" | grep '^LOAD' | head -2 | tr '\n' ';') — 이음매 스텁이 필요한 import가 있으면 정상이다"
    return 0
  fi
  # **부분 수정 스키마에서만 결함이다.** 생성 스키마의 기본값은 정상이므로 이름으로 가른다
  # (Update·Patch). 가르지 않으면 정상 팩이 전부 FAIL한다 — 오탐이 검사를 죽인다.
  local leak other
  leak=$(printf '%s' "$out" | awk -F'\t' 'tolower($2) ~ /update|patch/ && $1=="PARTIAL" && $4!="-" && $4 !~ /^ERR/ {printf "%s(%s만 보냈는데 %s가 채워짐) ", $2, $3, $4}')
  other=$(printf '%s' "$out" | awk -F'\t' 'tolower($2) !~ /update|patch/ && $1=="PARTIAL" && $4!="-" && $4 !~ /^ERR/ {printf "%s(%s) ", $2, $4}')
  if [ -n "$leak" ]; then
    bad "부분 수정이 보내지 않은 필드를 채운다: $leak" "exclude_unset 없이 dump하면 이 기본값이 저장을 덮어쓴다 — 실측 최악의 결함이 이 부류였다. 부분 수정 스키마의 선택 필드에는 기본값을 두지 않는다(None만)"
  else
    ok "스키마 실행 ${nfound}개 — 부분 수정 스키마가 필드를 채우지 않는다"
    [ -n "$other" ] && printf "      ${C_D}생성 스키마의 기본값(정상): %s${C_0}\n" "$other"
  fi
  printf "      ${C_D}%s${C_0}\n" "$(printf '%s' "$out" | awk -F'\t' '$1=="EMPTY"{printf "%s:빈객체=%s(%s) ", $2, $3, $4} $1=="UNKNOWN"{printf "미지키=%s ", $3}')"
  return 0
}
