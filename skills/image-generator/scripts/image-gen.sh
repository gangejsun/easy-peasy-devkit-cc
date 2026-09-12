#!/bin/bash
# skills/image-generator/scripts/image-gen.sh — OpenAI Images API(gpt-image-2) 직호출
#
# **왜 코덱스를 부르지 않는가.** 코덱스 CLI 의 내장 `image_gen` 도구는 데스크톱 앱 전용이다 —
# `codex exec` 와 `codex app-server`(플러그인 경로) 양쪽에서 도구 목록에 없음을 실측했다
# (codex 0.154.0 · features 의 image_generation 이 stable/true 인데도 없다).
# 코덱스가 배포하는 폴백 스크립트도 결국 OPENAI_API_KEY 를 요구한다. 그래서 코덱스 설치
# 여부와 내부 경로에 종속되느니 API 를 직접 부른다.
#
#   image-gen.sh --probe
#   image-gen.sh --estimate [--size WxH] [--quality Q] [-n N]
#   image-gen.sh --prompt <텍스트> --out <경로> [옵션]
#   image-gen.sh --prompt-file <파일> --out <경로> [옵션]
#   image-gen.sh --self-test
#
#   --size        auto 또는 WIDTHxHEIGHT (기본 1024x1024)
#                 16 의 배수 · 최대 변 3840 · 종횡비 3:1 이내 · 총 픽셀 655,360~8,294,400
#   --quality     low | medium | high | xhigh | max | auto   (기본 medium)
#   --format      png | jpeg | webp                          (기본 png)
#   --background  transparent | opaque | auto — transparent 는 png·webp 에서만
#   -n            1~10 (기본 1). 2 이상이면 파일명에 -1 · -2 … 접미사가 붙는다
#   --timeout     초 (기본 180)
#
# **과금은 ChatGPT 구독과 별개다.** 플랫폼 API 사용량으로 청구된다. 그래서 호출 전에
# 예상 단가를 찍고, 호출 후에는 응답의 usage 를 **추정이 아니라 실측으로** 보고한다.
#
# 키는 환경변수 OPENAI_API_KEY 만 읽는다. 인자로 받지 않고(프로세스 목록 노출) 파일에
# 저장하지도 않는다. python 에 환경변수 그대로 넘긴다.
#
# 종료 코드: 0 = 성공 · 1 = 실패(입력 오류·API 오류·파일 미생성) · 2 = 판정 불가
#            **판정 불가는 차단이 아니다.** 키가 없거나 의존 도구가 없는 상태이며, 스킬은
#            이때 인계 모드(프롬프트를 사람에게 넘김)로 빠진다. 없음을 실패로 접으면
#            오탐이 되고, 오탐은 사용자가 장치를 꺼버리게 만든다.
set -uo pipefail   # -e 없음: 검사를 끝까지 돌려 전체 보고를 낸다

FAIL=0; WARN=0; PASS=0
C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_D=$'\033[2m'; C_0=$'\033[0m'
ok()   { PASS=$((PASS+1)); printf "  ${C_G}✓${C_0} %s\n" "$1"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf "  ${C_R}✗${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
warn() { WARN=$((WARN+1)); printf "  ${C_Y}!${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; return 0; }
sec()  { printf "\n${C_D}── %s ─────────────────────────────${C_0}\n" "$1"; }
num()  { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }

usage() { sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; $d'; }

API_URL="${EPCC_IMAGE_API_URL:-https://api.openai.com/v1/images/generations}"
MODEL="${EPCC_IMAGE_MODEL:-gpt-image-2}"

# 공개 추정 단가(USD, 2026-09 기준). **계약이 아니라 안내다.**
# 표준 3종은 공표된 값을 그대로 쓴다 — 와이드·포트레이트는 정사각보다 싸므로 픽셀 수로
# 환산하면 오히려 비싸게 나온다(1536x1024 high 는 $0.165 인데 선형 환산은 $0.317 이었다).
# 표에 없는 치수만 정사각을 기준으로 픽셀 비례 환산하고, 모르는 quality 는 모른다고 말한다.
price_for() {   # $1 size · $2 quality → USD 또는 빈 문자열
  local s="$1" q="$2" base px
  case "$q" in xhigh|max) printf ''; return 0 ;; esac
  case "$s:$q" in
    1024x1024:low|1536x1024:low|1024x1536:low) printf '0.006'; return 0 ;;
    1024x1024:medium|1024x1024:auto)           printf '0.053'; return 0 ;;
    1024x1024:high)                            printf '0.211'; return 0 ;;
    1536x1024:medium|1024x1536:medium|1536x1024:auto|1024x1536:auto) printf '0.041'; return 0 ;;
    1536x1024:high|1024x1536:high)             printf '0.165'; return 0 ;;
    auto:*)                                    s="1024x1024" ;;
  esac
  case "$q" in low) base='0.006' ;; medium|auto) base='0.053' ;; high) base='0.211' ;; *) printf ''; return 0 ;; esac
  case "$s" in auto) px=$((1024 * 1024)) ;; *) px=$(( $(num "${s%%x*}") * $(num "${s##*x}") )) ;; esac
  [ "$px" -le 0 ] && px=$((1024 * 1024))
  awk -v b="$base" -v px="$px" 'BEGIN{ printf "%.4f", b * (px / 1048576.0) }'
  return 0
}

# ── 입력 검증 ────────────────────────────────────────────────────────────────
validate_size() {   # $1 size → 0 통과 · 1 위반(사유는 stdout)
  local s="$1" w h
  [ "$s" = "auto" ] && return 0
  case "$s" in
    [1-9]*x[1-9]*) ;;
    *) printf 'size 는 auto 또는 WIDTHxHEIGHT 형식이다 (예: 1024x1024)'; return 1 ;;
  esac
  w=$(num "${s%%x*}"); h=$(num "${s##*x}")
  [ "$w" -eq 0 ] || [ "$h" -eq 0 ] && { printf 'size 의 가로·세로는 양의 정수여야 한다'; return 1; }
  [ $((w % 16)) -ne 0 ] || [ $((h % 16)) -ne 0 ] && { printf 'size 의 가로·세로는 16 의 배수여야 한다 (받은 값: %sx%s)' "$w" "$h"; return 1; }
  [ "$w" -gt 3840 ] || [ "$h" -gt 3840 ] && { printf 'size 의 최대 변은 3840px 이다'; return 1; }
  local lo=$w hi=$h; [ "$w" -gt "$h" ] && { lo=$h; hi=$w; }
  [ $((hi)) -gt $((lo * 3)) ] && { printf 'size 의 종횡비는 3:1 을 넘을 수 없다'; return 1; }
  local px=$((w * h))
  [ "$px" -lt 655360 ]  && { printf 'size 의 총 픽셀은 655,360 이상이어야 한다 (받은 값: %s)' "$px"; return 1; }
  [ "$px" -gt 8294400 ] && { printf 'size 의 총 픽셀은 8,294,400 이하여야 한다 (받은 값: %s)' "$px"; return 1; }
  return 0
}
validate_quality() {
  case "$1" in low|medium|high|xhigh|max|auto) return 0 ;;
    *) printf 'quality 는 low·medium·high·xhigh·max·auto 중 하나다'; return 1 ;; esac
}
validate_format() {
  case "$1" in png|jpeg|webp) return 0 ;;
    *) printf 'format 은 png·jpeg·webp 중 하나다'; return 1 ;; esac
}
validate_background() {   # $1 background · $2 format
  case "$1" in
    ''|auto|opaque) return 0 ;;
    transparent) case "$2" in png|webp) return 0 ;;
                   *) printf 'background=transparent 는 png·webp 에서만 쓸 수 있다'; return 1 ;; esac ;;
    *) printf 'background 는 transparent·opaque·auto 중 하나다'; return 1 ;;
  esac
}

# ── 준비 판정 (3상태) ────────────────────────────────────────────────────────
probe() {   # stdout 한 줄: ready · no-key · unavailable
  if ! command -v python3 >/dev/null 2>&1; then
    printf 'unavailable\n'; printf '%s\n' "python3 가 없어 요청을 만들 수 없습니다." >&2; return 2
  fi
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    printf 'no-key\n'
    printf '%s\n' "OPENAI_API_KEY 가 없습니다 — 자동 생성 대신 인계 모드로 진행하세요." >&2
    return 2
  fi
  printf 'ready\n'; return 0
}

estimate() {   # $1 size · $2 quality · $3 n
  local s="$1" q="$2" n per
  n=$(num "$3"); [ "$n" -lt 1 ] && n=1
  per=$(price_for "$s" "$q")
  if [ -z "$per" ]; then
    printf '예상 단가: 미상 (quality=%s 는 공개 추정치가 없습니다) — ChatGPT 구독과 별개로 청구됩니다\n' "$q"
    return 0
  fi
  awk -v p="$per" -v n="$n" -v q="$q" -v z="$s" 'BEGIN{
    printf "예상 단가: 약 $%.3f (%s장 · %s · quality=%s) — ChatGPT 구독과 별개로 청구됩니다\n", p*n, n, z, q
  }'
  return 0
}

# ── 생성 ─────────────────────────────────────────────────────────────────────
generate() {
  local prompt="$1" out="$2" size="$3" quality="$4" fmt="$5" bg="$6" n="$7" timeout="$8" msg
  if ! command -v python3 >/dev/null 2>&1; then
    bad "python3 없음 — 판정 불가" "요청을 만들 수 없습니다. 인계 모드로 진행하세요."; return 2
  fi
  if [ -z "${OPENAI_API_KEY:-}" ]; then
    bad "OPENAI_API_KEY 없음 — 판정 불가(차단 아님)" \
        "자동 생성을 건너뛰고 인계 모드로 진행하세요 — 프롬프트를 사람에게 넘깁니다."; return 2
  fi
  [ -z "$prompt" ] && { bad "프롬프트가 비어 있습니다"; return 1; }
  [ -z "$out" ]    && { bad "--out 이 필요합니다"; return 1; }
  if msg=$(validate_size "$size");            [ -n "$msg" ]; then bad "$msg"; return 1; fi
  if msg=$(validate_quality "$quality");      [ -n "$msg" ]; then bad "$msg"; return 1; fi
  if msg=$(validate_format "$fmt");           [ -n "$msg" ]; then bad "$msg"; return 1; fi
  if msg=$(validate_background "$bg" "$fmt"); [ -n "$msg" ]; then bad "$msg"; return 1; fi
  n=$(num "$n"); { [ "$n" -lt 1 ] || [ "$n" -gt 10 ]; } && { bad "-n 은 1~10 이다"; return 1; }

  local dir; dir=$(dirname "$out")
  mkdir -p "$dir" 2>/dev/null || { bad "출력 디렉토리를 만들 수 없습니다: $dir"; return 1; }

  estimate "$size" "$quality" "$n"

  EPCC_IG_PROMPT="$prompt" python3 - "$API_URL" "$MODEL" "$out" "$size" "$quality" "$fmt" "$bg" "$n" "$timeout" <<'PY'
import base64, json, os, sys, urllib.error, urllib.request

url, model, out, size, quality, fmt, bg, n, timeout = sys.argv[1:10]
body = {"model": model, "prompt": os.environ["EPCC_IG_PROMPT"], "n": int(n), "output_format": fmt}
if size != "auto":
    body["size"] = size
if quality != "auto":
    body["quality"] = quality
if bg:
    body["background"] = bg

req = urllib.request.Request(
    url, data=json.dumps(body).encode(), method="POST",
    headers={"Authorization": "Bearer " + os.environ["OPENAI_API_KEY"],
             "Content-Type": "application/json"})
try:
    with urllib.request.urlopen(req, timeout=float(timeout)) as r:
        payload = json.load(r)
except urllib.error.HTTPError as e:
    detail = e.read().decode("utf-8", "replace")[:500]
    print("  \033[31m✗\033[0m API 오류 HTTP %s" % e.code)
    print("      \033[2m%s\033[0m" % detail)
    sys.exit(1)
except Exception as e:                      # 네트워크 단절·타임아웃은 실패이지 판정 불가가 아니다
    print("  \033[31m✗\033[0m API 호출 실패: %s" % e)
    sys.exit(1)

data = payload.get("data") or []
if not data:
    print("  \033[31m✗\033[0m 응답에 이미지가 없습니다")
    sys.exit(1)

root, ext = os.path.splitext(out)
if not ext:
    ext = "." + ("jpg" if fmt == "jpeg" else fmt)
written = []
for i, item in enumerate(data):
    b64 = item.get("b64_json")
    if not b64:                              # gpt-image 계열은 url 을 주지 않는다
        print("  \033[31m✗\033[0m 응답에 b64_json 이 없습니다 (항목 %d)" % i)
        sys.exit(1)
    path = out if len(data) == 1 else "%s-%d%s" % (root, i + 1, ext)
    with open(path, "wb") as f:
        f.write(base64.b64decode(b64))
    if os.path.getsize(path) == 0:
        print("  \033[31m✗\033[0m 0 바이트 파일: %s" % path)
        sys.exit(1)
    written.append(path)

MAGIC = {"png": b"\x89PNG\r\n\x1a\n", "jpeg": b"\xff\xd8\xff", "webp": b"RIFF"}
for path in written:
    with open(path, "rb") as f:
        head = f.read(8)
    if not head.startswith(MAGIC[fmt]):
        print("  \033[31m✗\033[0m %s 시그니처가 아닙니다: %s" % (fmt, path))
        sys.exit(1)
    print("  \033[32m✓\033[0m %s (%d bytes)" % (path, os.path.getsize(path)))

u = payload.get("usage") or {}
if u:                                        # 추정이 아니라 실측 — 청구의 근거다
    print("  \033[2m실측 usage: %s\033[0m" % json.dumps(u, ensure_ascii=False))
PY
  local rc=$?
  [ "$rc" -eq 0 ] && ok "생성 완료" || bad "생성 실패 (exit $rc)"
  return "$rc"
}

# ── 자기검증 ─────────────────────────────────────────────────────────────────
self_test() {
  sec "image-gen.sh 자기검증 (네트워크 없음)"
  local t; t=$(mktemp -d) || { bad "임시 디렉토리 생성 실패"; return 1; }
  trap 'rm -rf "$t"' RETURN

  _case() {   # $1 설명 · $2 기대 exit · shift 2 → 실행할 명령
    local desc="$1" want="$2"; shift 2
    "$@" >/dev/null 2>&1; local got=$?
    [ "$got" -eq "$want" ] && ok "$desc (exit $got)" || bad "$desc — exit $got, 기대 $want"
  }

  # size 검증 — 위반은 전부 1
  _case "size 1024x1024 통과"          0 validate_size 1024x1024
  _case "size auto 통과"               0 validate_size auto
  _case "size 1000x1000 거부(16 배수)" 1 validate_size 1000x1000
  _case "size 4096x1024 거부(최대 변)" 1 validate_size 4096x1024
  _case "size 3072x512 거부(종횡비)"   1 validate_size 3072x512
  _case "size 512x512 거부(총 픽셀)"   1 validate_size 512x512
  _case "size 형식 오류 거부"          1 validate_size 1024X1024
  _case "quality medium 통과"          0 validate_quality medium
  _case "quality ultra 거부"           1 validate_quality ultra
  _case "format png 통과"              0 validate_format png
  _case "format gif 거부"              1 validate_format gif
  _case "투명 배경 + png 통과"          0 validate_background transparent png
  _case "투명 배경 + jpeg 거부"         1 validate_background transparent jpeg

  # 3상태 — 키 없음은 **판정 불가(2)** 이지 실패(1)가 아니다
  local out
  out=$(OPENAI_API_KEY= probe 2>/dev/null); local rc=$?
  [ "$rc" -eq 2 ] && [ "$out" = "no-key" ] && ok "키 없음 → no-key · exit 2 (차단 아님)" \
    || bad "키 없음 판정이 틀렸다 — '$out' · exit $rc" "판정 불가를 실패로 접으면 오탐이 된다"
  out=$(OPENAI_API_KEY=sk-test-not-real probe 2>/dev/null); rc=$?
  [ "$rc" -eq 0 ] && [ "$out" = "ready" ] && ok "키 있음 → ready · exit 0" \
    || bad "키 있음 판정이 틀렸다 — '$out' · exit $rc"

  # 키 없이 생성 시도 → 2 (네트워크에 나가지 않는다)
  ( OPENAI_API_KEY= generate "x" "$t/a.png" 1024x1024 medium png "" 1 5 ) >/dev/null 2>&1
  [ $? -eq 2 ] && ok "키 없이 생성 시도 → exit 2 (인계 모드로 넘긴다)" \
    || bad "키 없이 생성 시도가 2 가 아니다"

  # 키가 있어도 입력이 틀리면 네트워크 전에 1 로 끊는다
  ( OPENAI_API_KEY=sk-test-not-real generate "x" "$t/b.png" 1000x1000 medium png "" 1 5 ) >/dev/null 2>&1
  [ $? -eq 1 ] && ok "잘못된 size → 호출 전에 exit 1" || bad "잘못된 size 가 호출 전에 걸리지 않았다"
  ( OPENAI_API_KEY=sk-test-not-real generate "" "$t/c.png" 1024x1024 medium png "" 1 5 ) >/dev/null 2>&1
  [ $? -eq 1 ] && ok "빈 프롬프트 → exit 1" || bad "빈 프롬프트가 걸리지 않았다"

  # 단가 안내 — medium 은 숫자가, xhigh 는 '미상' 이 나와야 한다
  estimate 1024x1024 medium 1 | grep -q '약 \$0\.053' \
    && ok "단가: 정사각 medium = 공표값 \$0.053" || bad "단가 추정이 어긋난다"
  estimate 1536x1024 high 1 | grep -q '약 \$0\.165' \
    && ok "단가: 와이드 high = 공표값 \$0.165 (정사각보다 싸다)" \
    || bad "와이드를 픽셀 비례로 환산해 비싸게 낸다" "1536x1024 high 는 \$0.211 이 아니라 \$0.165 다"
  estimate 1024x1024 medium 2 | grep -q '약 \$0\.106' \
    && ok "장수 배수 반영 (2장)" || bad "n 이 단가에 반영되지 않는다"
  estimate 1024x1024 xhigh 1 | grep -q '미상' \
    && ok "공개 추정치 없는 quality 는 '미상' 으로 말한다" || bad "모르는 단가를 아는 척한다"
  estimate 1024x1024 medium 1 | grep -q '구독과 별개' \
    && ok "과금 고지가 단가 줄에 붙어 있다" || bad "과금 고지가 없다"

  printf "\n  통과 %s · 경고 %s · 실패 %s\n" "$PASS" "$WARN" "$FAIL"
  [ "$FAIL" -gt 0 ] && return 1
  return 0
}

# ── 인자 ─────────────────────────────────────────────────────────────────────
MODE=""; PROMPT=""; OUT=""; SIZE="1024x1024"; QUALITY="medium"; FMT="png"; BG=""; N=1; TIMEOUT=180
while [ $# -gt 0 ]; do
  case "$1" in
    --probe)       MODE="probe" ;;
    --estimate)    MODE="estimate" ;;
    --self-test)   MODE="self-test" ;;
    --prompt)      MODE="generate"; PROMPT="${2:-}"; shift ;;
    --prompt-file) MODE="generate"; PROMPT=$(cat "${2:-}" 2>/dev/null); shift ;;
    --out)         OUT="${2:-}"; shift ;;
    --size)        SIZE="${2:-}"; shift ;;
    --quality)     QUALITY="${2:-}"; shift ;;
    --format)      FMT="${2:-}"; shift ;;
    --background)  BG="${2:-}"; shift ;;
    -n)            N="${2:-}"; shift ;;
    --timeout)     TIMEOUT="${2:-}"; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             printf ' 알 수 없는 옵션: %s\n' "$1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

case "$MODE" in
  probe)     probe; exit $? ;;
  estimate)  estimate "$SIZE" "$QUALITY" "$N"; exit 0 ;;
  self-test) self_test; exit $? ;;
  generate)  generate "$PROMPT" "$OUT" "$SIZE" "$QUALITY" "$FMT" "$BG" "$N" "$TIMEOUT"; exit $? ;;
  *)         usage; exit 1 ;;
esac
