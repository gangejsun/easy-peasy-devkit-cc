#!/bin/bash
# scripts/doctor.sh — epcc-devkit 자기검증
#
# CI가 없는 프로젝트를 전제로 설계했다. 따라서 이 스크립트는
# **사용자가 이미 치는 명령(pnpm build/test)에 기생**하거나 직접 호출된다.
#
#   doctor.sh --fast       구조 검사 (훅 규격, 룰 예산, dangling, 매니페스트)
#   doctor.sh --self-test  훅에 이벤트별 실제 stdin 픽스처 주입 → 효과 대조
#   doctor.sh --graph      workflow.graph.json 검증 (도달 불가 노드/엣지)
#   doctor.sh --usage      훅 하트비트 · 스킬 호출 · 엣지 traversal
#   doctor.sh --lessons    lessons.md 카테고리 집계 + 승격 후보 · 오탐 수축 후보(장치별)
#   doctor.sh --consumer   소비자 레이아웃 실증 (캐시 경로 + 빈/첫커밋전 프로젝트에서 훅 실행)
#   doctor.sh --inventory  영역별 자산 인벤토리 (판정 없음 — /harness-evaluation의 입력)
#   doctor.sh --all        위 전부 (fast · self-test · graph · consumer · usage · lessons · inventory)
#   doctor.sh              = --fast --graph
#
#   --root <dir>           검사 대상 플러그인 루트 교체 (자기시험 전용)
#
# 종료 코드: 0 = 통과, 1 = 실패 항목 존재

set -uo pipefail   # -e 없음: 모든 검사를 끝까지 돌려 전체 보고서를 낸다

# 루트가 둘이다 — 하나로 합치면 소비자 프로젝트에서 플러그인 구조 검사가 깨진다:
#   PLUGIN_ROOT: 플러그인 자산 검사(fast/graph/self-test) — 스크립트 위치가 곧 진실
#   PROJ:        프로젝트 상태 검사(usage/lessons) — 훅 로그·교훈은 소비자 쪽에 산다
# --root <dir> : 자기시험 전용. 합성 플러그인 트리를 대상으로 정적 검사를 돌린다.
# 이것이 없으면 정적 검사의 차단 능력을 재현 가능하게 증명할 수 없다 (손으로 심고
# 지운 증명은 다음 사람에게 남지 않는다).
DOCTOR_ROOT_OVERRIDE=""
_args=(); while [ $# -gt 0 ]; do
  case "$1" in
    --root) DOCTOR_ROOT_OVERRIDE="${2:-}"; shift 2 ;;
    *) _args+=("$1"); shift ;;
  esac
done
set -- ${_args+"${_args[@]}"}

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "$DOCTOR_ROOT_OVERRIDE" ] && PLUGIN_ROOT="$(cd "$DOCTOR_ROOT_OVERRIDE" 2>/dev/null && pwd)"
[ -n "$DOCTOR_ROOT_OVERRIDE" ] && [ -z "$PLUGIN_ROOT" ] && { printf '--root 경로 없음: %s\n' "$DOCTOR_ROOT_OVERRIDE" >&2; exit 2; }
PROJ="${CLAUDE_PROJECT_DIR:-$PWD}"
ROOT="$PLUGIN_ROOT"
cd "$ROOT" || exit 2

FAIL=0; WARN=0; PASS=0
C_R=$'\033[31m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_D=$'\033[2m'; C_0=$'\033[0m'
[ -t 1 ] || { C_R=""; C_G=""; C_Y=""; C_D=""; C_0=""; }

ok()   { PASS=$((PASS+1)); printf "  ${C_G}✓${C_0} %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "  ${C_R}✗${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; }
warn() { WARN=$((WARN+1)); printf "  ${C_Y}!${C_0} %s\n" "$1"; [ -n "${2:-}" ] && printf "      ${C_D}%s${C_0}\n" "$2"; }
sec()  { printf "\n${C_D}── %s ─────────────────────────────${C_0}\n" "$1"; }

num() { local v; v=$(printf '%s' "${1:-}" | tr -d '[:space:]'); case "$v" in ''|*[!0-9]*) printf '0';; *) printf '%s' "$v";; esac; }

# T0 예산은 **여기 한 곳**이 정본이다. 검사가 42로 오른 뒤 카드 본문이 "40줄"을 인용한 채 남았다 —
# 문서가 인용하는 수는 「선언↔실물」이 이 상수와 대조한다 (평가 v6 · E-25).
T0_BUDGET=42

# 스킬 루트가 셋이다 — 소비자 하네스(skills/) · 마케팅 플러그인(marketing/skills/) ·
# 하네스 저작 플러그인(harness/skills/). 뒤의 둘은 소비자가 설치하지 않는다.
# **위생 검사는 셋 다** 본다: 분리가 검사 사각지대를 만들면 그 분리는 개선이 아니다.
# 반대로 description 예산 · 「선언↔실물」의 스킬 수는 **skills/만** 센다 —
# 소비자 세션에 상주하는 것이 그것뿐이기 때문이다. 그래프는 예외로 harness/skills를
# 포함한다: harness-evaluation은 되먹임 루프의 노드라 빠지면 그 루프가 끊긴다.
skill_roots() { local d; for d in skills marketing/skills harness/skills; do [ -d "$d" ] && printf '%s\n' "$d"; done; }
skill_dirs()  { local r; while IFS= read -r r; do find "$r" -mindepth 1 -maxdepth 1 -type d 2>/dev/null; done < <(skill_roots); }
skill_mds()   { local d; while IFS= read -r d; do [ -f "$d/SKILL.md" ] && printf '%s\n' "$d/SKILL.md"; done < <(skill_dirs); }
_shared_copies() { local d; while IFS= read -r d; do grep -rl 'epcc-doctor: shared-copy' "$d/references" "$d/resources" 2>/dev/null; done < <(skill_dirs); }

# 코드 행만 남긴다 — 주석과 사용자 메시지 문자열은 검사 대상이 아니다.
# (린터가 자기 에러 메시지를 검출하는 것은 린터의 결함이다)
# BSD sed는 BRE에서 \| 교대를 지원하지 않는다 → -E(ERE) 필수
code_lines() {
  sed -E -e 's/^[[:space:]]*#.*$//' \
         -e '/^[[:space:]]*(bad|ok|warn|sec|printf|echo)[[:space:]]/d' "$1" 2>/dev/null
}

# ════════════════════════════════════════════════════════════════════
# 정적 검사 픽스처 헬퍼 (--self-test 전용)
# ════════════════════════════════════════════════════════════════════

# 정적 검사가 통과하는 최소 합성 플러그인 트리. 다른 검사(매니페스트·훅 등)는
# 여기서 실패해도 무방하다 — 판정은 **특정 메시지의 유무**로만 한다.
_fx_static_tree() {
  local T="$1"
  mkdir -p "$T/rules" "$T/templates" "$T/skills/sample" "$T/skills/epcc-init" "$T/scripts" || return 1

  printf -- '<!-- epcc-rule-version: 0.0.1 -->\n# 라우팅\n\n| Phase | 조건 |\n| --- | --- |\n' \
    > "$T/rules/workflow-routing.md"
  printf -- '---\npaths:\n  - "src/**"\n---\n<!-- epcc-rule-version: 0.0.1 -->\n# 코드\n' \
    > "$T/rules/code-change.md"

  printf -- '# CLAUDE.md\n\n## 하네스\n\n라우팅은 `.claude/rules/workflow-routing.md`가 로드합니다.\n' \
    > "$T/templates/CLAUDE.md.hbs"

  printf -- '---\nname: sample\ndescription: x\n---\nbash ${CLAUDE_SKILL_DIR}/scripts/x.sh\n' \
    > "$T/skills/sample/SKILL.md"

  # 카드 표는 rules/ 실물 수(2)와 맞춘다. epcc-init은 그래프에서 manual이므로 frontmatter도
  # disable-model-invocation을 갖는다 (G8이 둘을 대조한다).
  printf -- '---\nname: epcc-init\ndescription: x\ndisable-model-invocation: true\n---\ninstall-rules\n\n| 파일 | 로드 조건 |\n| --- | --- |\n| `workflow-routing.md` | 상시 |\n| `code-change.md` | src |\n\n프리셋: alpha · beta · none\n' \
    > "$T/skills/epcc-init/SKILL.md"

  # 이름 목록 대조용 최소 자산. 프리셋 2축 + 사전 제작 이음매 1쌍이 문서에 다 실린 상태가
  # 기준선이다. seam.json은 두지 않는다 — 두면 "이음매의 팩 참조 실재" 검사가 없는 팩을
  # 가리켜 기준선이 빨개진다. _seams_in은 디렉토리명만 보므로 이것으로 충분하다.
  mkdir -p "$T/presets/frontend" "$T/presets/backend" "$T/guides/seams/alpha+beta" \
           "$T/docs" "$T/skills/stack-guide-generator/assets" || return 1
  printf -- '{"axis":"frontend","name":"alpha"}\n' > "$T/presets/frontend/alpha.json"
  printf -- '{"axis":"frontend","name":"none"}\n'  > "$T/presets/frontend/none.json"
  printf -- '{"axis":"backend","name":"beta"}\n'   > "$T/presets/backend/beta.json"
  printf -- '{"axis":"backend","name":"none"}\n'   > "$T/presets/backend/none.json"
  # README는 스킬 이름 전수 대조 대상이다 — 픽스처 스킬 3개를 다 적어 기준선을 맞춘다
  printf -- '# fx\n\n프리셋: alpha · beta · none\n\n사전 제작본: `alpha` × `beta`\n\n스킬: sample · epcc-init · stack-guide-generator\n' \
    > "$T/README.md"
  printf -- '# 프리셋\n\nalpha · beta · none\n' > "$T/docs/presets.md"
  printf -- '# Getting Started\n\nalpha / beta / none\n\nShips `alpha` × `beta`.\n' \
    > "$T/docs/getting-started.md"
  printf -- '# 규격서\n\n사전 제작본은 현재 1쌍이다(`alpha`×`beta`).\n' \
    > "$T/skills/stack-guide-generator/assets/guide-skeleton.md"

  # 선언↔실물 대조 대상 2곳. 이 트리의 **실물**과 맞는 수를 적어둔 것이 기준선이다
  # (훅 1 · 규칙 2 · 스킬 3 · 노드 3 · 엣지 0 · 프리셋 2+2 · 팩 0+0).
  # 훅 수의 실물은 hooks.json에서 나오므로 그 파일도 있어야 대조가 실제로 돈다 —
  # 없으면 '판정 불가'로 건너뛰고, 건너뛴 검사는 증명된 검사가 아니다.
  mkdir -p "$T/hooks" "$T/.claude-plugin" || return 1
  printf -- '{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"bash ${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"}]}]}}\n' \
    > "$T/hooks/hooks.json"
  printf -- '#!/bin/bash\nexit 0\n' > "$T/scripts/x.sh"
  printf -- '{"plugins":[{"name":"fx","description":"자기검증 훅 1종. 3개 스킬 + 축 가이드 팩(프론트 0 · 백엔드 0), 2축 프리셋(프론트 2 · 백엔드 2)."}]}\n' \
    > "$T/.claude-plugin/marketplace.json"
  printf -- '# 해부\n\n실물 대조 — 훅 1 · T1 규칙 카드 2 · 스킬 3 · 그래프 노드 3 · 엣지 1\n' \
    > "$T/docs/harness-anatomy.md"

  # 그래프: 스킬 2개 + 훅 1개를 노드로 선언. epcc-init은 manual(+frontmatter dmi), sample은
  # 인바운드 엣지로 도달한다 — sample을 manual로 두면 「수동 전용 선언 ↔ 상주 플래그」 픽스처가
  # dmi를 요구해 서로 부딪힌다. 훅 노드는 hooks.json이 등록한 x.sh에 대응한다 — 「미선언 훅」
  # 검사가 생긴 뒤로 등록만 하고 선언하지 않은 트리는 **결함 없는 기준선이 아니다**.
  cat > "$T/workflow.graph.json" <<'FXG'
{
  "version": "0.0.1",
  "nodes": [
    { "id": "sample", "kind": "skill", "path": "skills/sample/SKILL.md" },
    { "id": "epcc-init", "kind": "skill", "path": "skills/epcc-init/SKILL.md", "manual": true },
    { "id": "x", "kind": "hook", "path": "scripts/x.sh", "event": "SessionStart", "entry": true }
  ],
  "edges": [ { "from": "epcc-init", "to": "sample", "cond": "fx" } ]
}
FXG
  return 0
}

# 결함 하나를 심고 판정한다. **유효성 확인이 먼저다.**
#   $1 임시루트  $2 이름  $3 결함이 들어갈 파일(트리 상대)  $4 결함 표식(grep -E)
#   $5 기대 메시지  $6 심는 명령 ($T = 트리 경로)
_fx_static_case() {
  local sfx="$1" name="$2" file="$3" mark="$4" want="$5" plant="$6" mode="${7:---fast}"
  local T="$sfx/$name"
  rm -rf "$T"; cp -R "$sfx/base" "$T" 2>/dev/null || { bad "픽스처 복사 실패: $name"; return; }

  # 심기 실패를 감추지 않는다 — 감추면 "픽스처 무효"의 원인을 알 수 없다.
  local perr; perr=$(eval "$plant" 2>&1 >/dev/null)

  # ① 유효성 — 심으려던 것이 실제로 들어갔는가. 이 단계가 없어서 no-op 증명이 통과로 보였다.
  if ! grep -qE "$mark" "$T/$file" 2>/dev/null; then
    bad "픽스처 무효: $name" "결함 표식 '$mark'가 $file 에 없다 — 아래 판정은 무의미하다${perr:+ · 심기 오류: $perr}"
    return
  fi

  # ② 검출 — 그 상태에서 검사가 기대 메시지를 내는가
  local out; out=$(bash "$0" "$mode" --root "$T" 2>&1)
  # 사유 표시는 성공/실패 **양쪽**에서 낸다. 성공 분기에만 두면 정작 필요한 순간에
  # 침묵한다 — 미탐으로 실패했을 때야말로 "그럼 무엇이 대신 걸렸나"를 봐야 한다.
  # 경고(!)로 판정하는 픽스처도 사유가 보여야 한다: ✗만 보면 warn 기반 픽스처의
  # "의도한 이유로 걸렸는가"를 확인할 수 없다.
  local why=""
  [ -n "${EPCC_FX_WHY:-}" ] && why=$(printf '%s' "$out" | grep -E '✗|!' | head -2 | sed 's/^  *//' | tr '\n' ';')
  if printf '%s' "$out" | grep -q "$want"; then
    ok "$name → '$want' 검출"
  else
    bad "$name → '$want' 미검출" "결함을 심었는데 검사가 통과시켰다 — 미탐"
  fi
  [ -n "$why" ] && printf "      ${C_D}%s${C_0}\n" "$why"
  return 0
}

# ════════════════════════════════════════════════════════════════════
# --fast : 구조 검사
# ════════════════════════════════════════════════════════════════════
run_fast() {
  printf "\n${C_D}epcc doctor --fast${C_0}  (plugin: %s)\n" "$ROOT"

  # ── 1. 금지 관용구 lint (§1.1 검출) ──
  sec "금지 관용구 (침묵 실패 원인)"

  local n
  n=$(grep -rl 'BASH_SOURCE\[0\]}")/\.\./\.\.' scripts/ 2>/dev/null | grep -v '/lib/' | wc -l | tr -d ' ')
  n=$(num "$n")
  if [ "$n" -gt 0 ]; then
    bad "BASH_SOURCE 상대 루트 계산: ${n}개 파일" \
        "$(grep -rl 'BASH_SOURCE\[0\]}")/\.\./\.\.' scripts/ 2>/dev/null | grep -v '/lib/' | tr '\n' ' ')"
    printf "      ${C_D}→ 플러그인 배포 시 저장소 밖을 가리킴. epcc_root() 사용 필요${C_0}\n"
  else
    ok "BASH_SOURCE 상대 루트 계산 없음"
  fi

  local hits="" n=0
  for f in scripts/*.sh; do
    [ -f "$f" ] || continue
    case "$f" in */lib/*) continue;; esac
    if code_lines "$f" | grep -q '|| *echo *"\?0"\?'; then
      hits="$hits $(basename "$f")"; n=$((n+1))
    fi
  done
  if [ "$n" -gt 0 ]; then
    bad "'|| echo 0' 폴백: ${n}개 파일" "$hits — 1줄 자리에 2줄이 들어가 정수 비교를 붕괴시킴. epcc_num() 사용 필요"
  else
    ok "'|| echo 0' 폴백 없음"
  fi

  # 무가드 glob 파이프 — `ls dir/*.md | wc -l`은 무매칭 시 ls가 exit 1을 내고,
  # 훅의 pipefail+ERR 트랩이 스크립트를 통째로 죽인다. 하필 "0개일 때" 죽으므로
  # 0개를 알리려던 코드가 정확히 그 상황에서 침묵한다. `{ ... || true; }` 필요.
  # 대상은 **ERR trap이 걸린 스크립트만**이다: common.sh를 source하는 훅, 또는
  # 스스로 `set -e`/`-Eeuo`를 켠 설치기. 검사 스크립트(doctor 자신)는 `-e`가 없어
  # 파이프 실패가 죽이지 않으므로 제외한다 — 넣으면 오탐이고, 오탐은 lint를 무력화한다.
  local gl="" n=0
  for f in scripts/*.sh; do
    [ -f "$f" ] || continue
    case "$f" in */lib/*) continue;; esac
    # **언급이 아니라 실제 source를 본다.** 파일이 lib/common.sh를 문자열로 담기만 해도
    # 걸리던 필터라, doctor.sh가 회전 불변식 픽스처에서 그 경로를 부분 프로세스로 넘기자
    # 자기 자신을 ERR trap 보유자로 오인해 오탐을 냈다. 훅 5종과 설치기 2종은 그대로 걸린다.
    grep -qE '^set -[A-Za-z]*e|^[[:space:]]*(source|\.)[[:space:]]+[^|]*lib/common\.sh' "$f" 2>/dev/null || continue
    while IFS= read -r line; do
      case "$line" in *'|| true'*|*'||true'*) continue;; esac
      gl="$gl $(basename "$f")"; n=$((n+1)); break
    done < <(code_lines "$f" | grep -E 'ls[[:space:]][^|]*\*[^|]*\|')
  done
  if [ "$n" -gt 0 ]; then
    bad "무가드 glob 파이프: ${n}개 파일" "$gl — 무매칭 시 ls exit 1 → pipefail+ERR 트랩이 훅을 죽인다. { ... || true; } 필요"
  else
    ok "무가드 glob 파이프 없음"
  fi

  # HEAD 미검증 git 호출 — 커밋 0개(git init 직후) 저장소에서 exit 128.
  # 신규 프로젝트의 첫 세션이 정확히 그 상태다. rev-parse -q --verify HEAD 로 먼저 확인한다.
  local gh="" n=0
  for f in scripts/*.sh; do
    [ -f "$f" ] || continue
    case "$f" in */lib/*) continue;; esac
    code_lines "$f" | grep -qE 'git (log|describe)[[:space:]]|git rev-parse[[:space:]]+(--abbrev-ref[[:space:]]+)?HEAD' || continue
    grep -q 'rev-parse -q --verify HEAD' "$f" 2>/dev/null && continue
    gh="$gh $(basename "$f")"; n=$((n+1))
  done
  if [ "$n" -gt 0 ]; then
    bad "HEAD 미검증 git 호출: ${n}개 파일" "$gh — 커밋 0개 저장소에서 exit 128 → 훅 사망. git rev-parse -q --verify HEAD 로 먼저 확인"
  else
    ok "HEAD 미검증 git 호출 없음"
  fi

  # BSD BRE 교대 — macOS의 grep/sed는 BRE에서 \| 를 지원하지 않는다.
  # **실패하지 않고 조용히 무매칭**이 되므로 검사가 아무것도 안 잡는 채로 통과한다.
  # -E(ERE)를 쓰고 | 로 적어야 한다.
  local bre="" n=0
  for f in scripts/*.sh skills/*/scripts/*.sh marketing/skills/*/scripts/*.sh harness/skills/*/scripts/*.sh; do
    [ -f "$f" ] || continue
    code_lines "$f" 2>/dev/null | grep -qE "(grep|sed)([[:space:]]+-[a-df-zA-Z]+)*[[:space:]]+'[^']*\\\\\\|" || continue
    bre="$bre $(basename "$f")"; n=$((n+1))
  done
  if [ "$n" -gt 0 ]; then
    bad "BSD 미지원 BRE 교대(\\|): ${n}개 파일" "$bre — macOS에서 조용히 무매칭된다. grep -E / sed -E 와 | 를 쓸 것"
  else
    ok "BSD 미지원 BRE 교대 없음"
  fi

  # ── 2. 훅 출력 규격 (§1.2 검출) ──
  sec "훅 출력 규격 (이벤트별 지원 필드)"

  local hooks_json="hooks/hooks.json"
  if [ ! -f "$hooks_json" ]; then
    bad "hooks/hooks.json 없음"
  else
    # Stop 이벤트에 등록된 스크립트가 decision/reason을 쓰는지
    local stop_scripts
    stop_scripts=$(command -v jq >/dev/null 2>&1 && jq -r '.hooks.Stop[]?.hooks[]?.command // empty' "$hooks_json" 2>/dev/null | grep -oE '[a-z-]+\.sh' || true)
    local viol=0
    for s in $stop_scripts; do
      [ -f "scripts/$s" ] || continue
      if code_lines "scripts/$s" | grep -qE '"(decision|reason)"[[:space:]]*:'; then
        bad "Stop 훅 '$s'가 미지원 필드(decision/reason) 사용" \
            "Stop은 additionalContext/continue/systemMessage만 지원. 이 출력은 조용히 무시됨"
        viol=$((viol+1))
      fi
    done
    [ "$viol" -eq 0 ] && [ -n "$stop_scripts" ] && ok "Stop 훅 출력 규격 적합"

    # PreCompact은 stdout 평문이 컨텍스트가 되지 않는다
    local pc_scripts
    pc_scripts=$(command -v jq >/dev/null 2>&1 && jq -r '.hooks.PreCompact[]?.hooks[]?.command // empty' "$hooks_json" 2>/dev/null | grep -oE '[a-z-]+\.sh' || true)
    for s in $pc_scripts; do
      [ -f "scripts/$s" ] || continue
      if ! grep -q 'additionalContext' "scripts/$s" 2>/dev/null; then
        bad "PreCompact 훅 '$s'가 additionalContext 미사용" \
            "PreCompact stdout 평문은 컨텍스트에 들어가지 않음 (SessionStart/UserPromptSubmit만 해당)"
      else
        ok "PreCompact 훅 '$s' 출력 규격 적합"
      fi
    done

  fi

  # ── 3. 훅 등록 ↔ 파일 실재 ──
  sec "훅 배선"
  if [ -f "$hooks_json" ] && command -v jq >/dev/null 2>&1; then
    local missing=0 total=0
    while IFS= read -r cmd; do
      [ -z "$cmd" ] && continue
      total=$((total+1))
      local f; f=$(printf '%s' "$cmd" | grep -oE 'scripts/[a-z0-9./-]+\.sh' | head -1)
      [ -n "$f" ] && [ ! -f "$f" ] && { bad "등록된 훅 파일 없음: $f"; missing=$((missing+1)); }
    done < <(jq -r '.hooks | to_entries[] | .value[]?.hooks[]?.command // empty' "$hooks_json" 2>/dev/null)
    [ "$missing" -eq 0 ] && ok "등록된 훅 ${total}개 모두 실재"
  fi

  # ── 4. 규칙 도달성 (§1.3 검출) ──
  sec "규칙 도달성"

  local rules_lines=0
  [ -d rules ] && rules_lines=$(num "$(cat rules/*.md 2>/dev/null | wc -l | tr -d ' ')")

  if [ "$rules_lines" -gt 0 ]; then
    # 플러그인 매니페스트에 rules 컴포넌트가 있는가? (없다 — 지원 타입 아님)
    local has_rules_component=0
    [ -f .claude-plugin/plugin.json ] && grep -q '"rules"' .claude-plugin/plugin.json 2>/dev/null && has_rules_component=1

    # epcc-init이 rules를 설치하는가?
    local installs=0
    if [ -f skills/epcc-init/SKILL.md ]; then
      grep -qE 'CLAUDE_PLUGIN_ROOT.*/rules/|rules/.*→.*\.claude/rules|\.claude/rules/.*설치|install-rules' \
        skills/epcc-init/SKILL.md 2>/dev/null && installs=1
    fi

    if [ "$has_rules_component" -eq 0 ] && [ "$installs" -eq 0 ]; then
      bad "rules/ ${rules_lines}줄이 프로젝트에 도달할 경로 없음" \
          "플러그인 매니페스트에 'rules' 컴포넌트 타입이 없고, epcc-init에 설치 단계도 없음"
    else
      ok "rules/ ${rules_lines}줄 도달 경로 확보 (epcc-init 설치 단계)"
    fi
  fi

  # dangling .claude/rules 참조
  #
  # 마이그레이션 가이드처럼 "제거 대상"을 나열하는 문서는 존재하지 않는 경로를
  # 정당하게 언급한다. 파일명으로 몰래 제외하지 않고 명시적 마커를 요구한다:
  #   <!-- epcc-doctor: allow-stale-refs -->
  local scan_files=()
  while IFS= read -r sf; do
    grep -q 'epcc-doctor: allow-stale-refs' "$sf" 2>/dev/null || scan_files+=("$sf")
  done < <(find rules skills agents templates -name '*.md' -type f 2>/dev/null)

  local dang=0 checked=0 dlist=""
  for p in $( [ ${#scan_files[@]} -gt 0 ] && grep -hoE '\.claude/rules/[a-z0-9-]+\.md' "${scan_files[@]}" 2>/dev/null | sort -u); do
    checked=$((checked+1))
    local base; base=$(basename "$p")
    if [ ! -f "rules/$base" ] && [ ! -f ".claude/rules/$base" ]; then
      dang=$((dang+1)); dlist="$dlist $base"
    fi
  done
  if [ "$dang" -gt 0 ]; then
    bad "dangling .claude/rules 참조 ${dang}/${checked}" "존재하지 않음:$dlist"
  elif [ "$checked" -gt 0 ]; then
    ok "\.claude/rules 참조 ${checked}건 모두 실재"
  fi

  # 상시 로드 축 (§R1) — Claude Code는 `paths:` 없는 .claude/rules/*.md 를 매 세션
  # 무조건 로드한다. 작업 라우팅과 참조 신선도는 "아직 아무 파일도 열지 않은 시점"에
  # 필요하므로 조건부여서는 안 된다. paths가 붙는 순간 조용히 안 뜬다.
  local always=""
  for rc in rules/*.md; do
    [ -f "$rc" ] || continue
    grep -q '^paths:' "$rc" 2>/dev/null || always="$always $(basename "$rc")"
  done
  if [ -z "$always" ]; then
    bad "상시 로드 규칙 카드 없음" "rules/ 전부가 paths 조건부 — 작업 라우팅이 세션 시작 시 도달하지 못한다"
  elif [ ! -f rules/workflow-routing.md ] || grep -q '^paths:' rules/workflow-routing.md 2>/dev/null; then
    bad "workflow-routing.md가 상시가 아님" "paths를 지우세요 — 붙는 순간 세션 시작 시 안 뜹니다"
  else
    ok "상시 로드 카드:$always"
  fi

  # epcc-init Step 7의 카드 표가 rules/ 실물과 어긋나면, 사용자는 설치가 끝났는지
  # 판단할 근거를 잃는다. 표는 사본이므로 수가 갈라지는 순간 알린다.
  if [ -f skills/epcc-init/SKILL.md ]; then
    local nrules ntable
    nrules=$(num "$(ls -1 rules/*.md 2>/dev/null | wc -l | tr -d ' ')")
    ntable=$(num "$(grep -cE '^\| `[a-z-]+\.md` \|' skills/epcc-init/SKILL.md 2>/dev/null)")
    if [ "$nrules" -ne "$ntable" ]; then
      bad "epcc-init 카드 표 ${ntable}장 ≠ rules/ ${nrules}장" "설치 안내가 실물과 어긋난다"
    else
      ok "epcc-init 카드 표 ${ntable}장 = rules/ 실물"
    fi
  fi

  # 정본 이원화 방지 — Phase 표가 .hbs로 되돌아오면 카드와 갈라진다
  if [ -f templates/CLAUDE.md.hbs ] && grep -qE '^\| *P0|^\| *Phase *\|' templates/CLAUDE.md.hbs 2>/dev/null; then
    bad "CLAUDE.md.hbs에 Phase 표 재출현" "정본은 rules/workflow-routing.md — 사본은 드리프트 원천이다"
  else
    ok "Phase 표 정본 단일 (rules/workflow-routing.md)"
  fi

  # T0 예산 — operating-contract.md 주석이 약속한 42줄 상한을 기계가 지킨다.
  # 초과는 「삭제하라」가 아니라 분기점이다 — 선택지와 선택 간 실질 차이를 제시하고 사람이 고른다.
  local t0="templates/operating-contract.md"
  if [ -f "$t0" ]; then
    local t0n; t0n=$(num "$(wc -l < "$t0")")
    if [ "$t0n" -le "$T0_BUDGET" ]; then
      ok "T0 운영 규칙 ${t0n}/${T0_BUDGET}줄"
    else
      bad "T0 운영 규칙 ${t0n}줄 — 예산 ${T0_BUDGET}줄 초과" "$(printf '규범을 지우지 마세요. 아래 셋 중 하나를 고릅니다 — 잃는 것이 서로 다릅니다.\n      1) T1 카드로 내린다  — 도달은 유지, 상시성 상실 (그 경로를 만질 때만 뜬다)\n      2) 더 짧게 고쳐 쓴다  — 상시성 유지, 정보가 깎일 위험\n      3) 예산을 올린다      — 둘 다 유지, 매 세션 비용이 는다 (이 검사의 %s를 함께 올린다)' "$T0_BUDGET")"
    fi

    # T0에서 규범 절이 사라지면 조용히 전파된다 — 줄 수만 보는 검사는 삭제를 오히려 통과시킨다.
    # 이 절들을 「정본」이라 선언하고 인용하는 곳: epcc-planner · reversibility · harness-anatomy(2)
    local t0miss=""
    for _a in '되돌림 분류' '작업 진입' '최소 수정' '검증' '분기점' '언어'; do
      grep -qF -- "**${_a}**" "$t0" 2>/dev/null || t0miss="$t0miss ${_a}"
    done
    if [ -n "$t0miss" ]; then
      bad "T0에서 규범 절이 사라졌다:$t0miss" "이 절을 정본이라 선언하고 인용하는 곳이 있습니다 — 지우려면 인용처부터 함께 고치세요"
    else
      ok "T0 규범 절 6개 실재"
    fi

    # T0의 응답 언어 자리표시자 ↔ session-brief의 치환기.
    # **양쪽 다 있거나 다 없거나**다. 한쪽만이면 반대 방향으로 조용히 망가진다:
    #   자리표시자만 → `{{RESPONSE_LANGUAGE}}`가 매 세션 그대로 컨텍스트로 샌다
    #   치환기만     → T0가 언어를 고정하고 프로젝트 설정이 도달하지 못한다
    # 후자가 v3.25까지의 상태였다 — config에 language가 있어도 T0의 한국어가 이겼다.
    local t0ph=0 sbsub=0
    grep -qF '{{RESPONSE_LANGUAGE}}' "$t0" 2>/dev/null && t0ph=1
    grep -qF '{{RESPONSE_LANGUAGE}}' scripts/session-brief.sh 2>/dev/null && sbsub=1
    if [ "$t0ph" -eq 1 ] && [ "$sbsub" -eq 1 ]; then
      ok "응답 언어 자리표시자 ↔ 치환기 양립"
    elif [ "$t0ph" -eq 1 ]; then
      bad "T0 자리표시자를 치환할 곳이 없다" "session-brief.sh에 {{RESPONSE_LANGUAGE}} 치환이 없습니다 — 자리표시자가 매 세션 컨텍스트로 샙니다"
    elif [ "$sbsub" -eq 1 ]; then
      bad "치환기만 있고 T0에 자리표시자가 없다" "operating-contract.md의 **언어** 절이 언어를 고정하고 있습니다 — 프로젝트 설정이 도달하지 않습니다"
    else
      warn "응답 언어가 T0에 고정됨" "프로젝트가 언어를 고를 수 없습니다"
    fi

    # 언어 목록 드리프트 — init이 제시하는 코드는 hbs 분기와 스키마 예시에 모두 실려야 한다.
    # 하나라도 빠지면 그 언어를 고른 프로젝트만 CLAUDE.md에서 코드가 날것으로 보인다.
    local lmiss="" _l
    for _l in ko en id vi; do
      grep -qF "\"$_l\"" templates/CLAUDE.md.hbs 2>/dev/null || lmiss="$lmiss hbs:$_l"
      grep -qF "\"$_l\"" schema/epcc.config.schema.json 2>/dev/null || lmiss="$lmiss schema:$_l"
      grep -qF "\`$_l\`" skills/epcc-init/SKILL.md 2>/dev/null || lmiss="$lmiss init:$_l"
    done
    if [ -n "$lmiss" ]; then
      bad "언어 목록 불일치:$lmiss" "init 선택지 · CLAUDE.md.hbs 분기 · 스키마 examples 셋이 같아야 합니다"
    else
      ok "언어 목록 일치 (init ↔ hbs ↔ schema)"
    fi
  else
    bad "T0 운영 규칙 파일 없음: $t0"
  fi

  # 규칙 카드 버전 스탬프 — 없으면 install-rules가 0.0.0으로 읽어 갱신을 영영 건너뛴다
  local nostamp=""
  for rf in rules/*.md; do
    [ -f "$rf" ] || continue
    grep -q 'epcc-rule-version:' "$rf" 2>/dev/null || nostamp="$nostamp $(basename "$rf")"
  done
  if [ -n "$nostamp" ]; then
    bad "버전 스탬프 없는 규칙 카드:$nostamp" "install-rules.sh 갱신 판정 불가"
  else
    ok "규칙 카드 버전 스탬프 완비"
  fi

  # 카드 → 참조 링크 실재 (점진 로드의 도달 경로)
  # 큰 카드는 본문을 references/로 내리고 링크로 가리킨다. 링크가 끊기면
  # 모델은 "읽을 수 없는 파일"을 안내받고, 그 지식은 조용히 도달하지 않는다.
  local rdang=0 rchecked=0 rc rlnk
  for rc in "$ROOT"/rules/*.md; do
    [ -f "$rc" ] || continue
    while IFS= read -r rlnk; do
      [ -z "$rlnk" ] && continue
      rchecked=$((rchecked+1))
      [ -f "$ROOT/${rlnk#../}" ] || { bad "$(basename "$rc") → $rlnk 없음" "점진 로드가 끊긴다"; rdang=$((rdang+1)); }
    done < <(grep -ohE '\.\./references/[A-Za-z0-9._/-]+\.md' "$rc" 2>/dev/null | sort -u)
  done
  [ "$rdang" -eq 0 ] && ok "카드→참조 링크 ${rchecked}건 모두 실재"

  # §참조가 실재하는 절을 가리키는가 — 큰 카드를 쪼개면 옮겨간 절의 번호가 잔재로 남는다.
  # 「변경 후 역추적: 사라진 이름 쪽을 본다」의 기계 판정분. 범위 표기(§1~8)는 앞 숫자만 본다 —
  # 놓치는 쪽으로 기운 판정이지, 있는 것을 없다고 하지 않는다.
  local sdang=0 schk=0 card secs num
  for card in "$ROOT"/rules/*.md; do
    [ -f "$card" ] || continue
    secs=$(grep -oE '^## [0-9]+\.' "$card" 2>/dev/null | grep -oE '[0-9]+' | tr '\n' ' ')
    [ -z "$secs" ] && continue
    for num in $(grep -ohE '§[0-9]+' "$card" 2>/dev/null | grep -oE '[0-9]+' | sort -u); do
      schk=$((schk+1))
      case " $secs " in *" $num "*) ;; *)
        bad "$(basename "$card") §${num} — 그 절이 없다" "쪼개면서 옮겨간 절의 번호가 잔재로 남았다"; sdang=$((sdang+1)) ;;
      esac
    done
    # 이 카드의 참조 디렉토리도 같은 잣대로 본다 ("카드 §N")
    local rdir="$ROOT/references/$(basename "$card" .md)"
    [ -d "$rdir" ] || continue
    for num in $(grep -rohE '카드 §[0-9]+' "$rdir" 2>/dev/null | grep -oE '[0-9]+' | sort -u); do
      schk=$((schk+1))
      case " $secs " in *" $num "*) ;; *)
        bad "references/$(basename "$rdir") → 카드 §${num} 없음" "쪼개면서 옮겨간 절의 번호가 잔재로 남았다"; sdang=$((sdang+1)) ;;
      esac
    done
  done
  [ "$sdang" -eq 0 ] && ok "카드 §참조 ${schk}건 모두 실재하는 절"

  # ── 5. 에이전트 계약 ──
  sec "에이전트 계약"
  local aok=0 atot=0
  for f in agents/*.md; do
    [ -f "$f" ] || continue
    atot=$((atot+1))
    local fm miss=""
    fm=$(awk '/^---$/{c++;next} c==1' "$f" 2>/dev/null)
    for k in name description tools model; do
      printf '%s' "$fm" | grep -q "^${k}:" || miss="$miss $k"
    done
    if [ -n "$miss" ]; then
      bad "$(basename "$f"): frontmatter 누락 →$miss"
    else
      aok=$((aok+1))
    fi
  done
  [ "$atot" -gt 0 ] && [ "$aok" -eq "$atot" ] && ok "에이전트 ${atot}개 계약 완비"

  # ── 6. 스킬 위생 ──
  sec "스킬 description 위생"
  local stot=0 blk=0 proj=0 sm
  while IFS= read -r sm; do
    [ -z "$sm" ] && continue
    stot=$((stot+1))
    grep -q '^description: |' "$sm" 2>/dev/null && blk=$((blk+1))
    grep -q '(project)' "$sm" 2>/dev/null && proj=$((proj+1))
  done < <(skill_mds)
  [ "$blk" -gt 0 ] && warn "블록 스칼라 description ${blk}/${stot}" "단일 행 권장 (sprawl 유발)" || ok "블록 스칼라 없음"
  [ "$proj" -gt 0 ] && warn "'(project)' 접미사 ${proj}/${stot}" "라우팅에 무의미, 상시 상주 비용만 차지" || ok "'(project)' 접미사 없음"

  # 수동 전용 선언 ↔ disable-model-invocation 일치 (양방향)
  #   description은 스킬을 한 번도 부르지 않아도 상주한다(docs/platform-contract.md §2.4).
  #   "수동 호출 전용"이라 적고 플래그를 안 붙이면 **선언과 과금이 어긋난다** — 매 세션 헛돈.
  #   반대로 라우팅이 자동 발동으로 지목하는 스킬에 붙이면 모델이 영영 못 불러 라우팅이 끊긴다.
  local manual_unflagged="" flagged_routed="" legacy_key="" sname sdir
  while IFS= read -r sm; do
    [ -z "$sm" ] && continue
    sdir=$(dirname "$sm"); sname=$(basename "$sdir")
    local has_flag=0 says_manual=0 fm
    # 프론트매터 **블록 전체**를 본다. description: 첫 행만 보면 접힌 description의
    # 이어지는 행에 적힌 선언을 놓친다 — 그 틈으로 수동 전용 스킬이 상주했다.
    fm=$(awk '/^---$/{n++; if(n==2) exit} n==1' "$sm" 2>/dev/null)
    printf '%s\n' "$fm" | grep -q '^disable-model-invocation:[[:space:]]*true' && has_flag=1
    printf '%s\n' "$fm" | grep -q '수동 호출 전용' && says_manual=1
    # 플랫폼 계약에 없는 키는 조용히 무시된다 — 선언한 사람은 됐다고 믿는다.
    printf '%s\n' "$fm" | grep -q '^trigger:' && legacy_key="$legacy_key $sname"
    if [ "$says_manual" -eq 1 ] && [ "$has_flag" -eq 0 ]; then
      manual_unflagged="$manual_unflagged $sname"
    fi
    if [ "$has_flag" -eq 1 ]; then
      if grep -q "\`/${sname}\`" "$ROOT/rules/workflow-routing.md" 2>/dev/null; then
        flagged_routed="$flagged_routed $sname(라우팅)"
      elif grep -A3 "\"id\": \"${sname}\"" "$ROOT/workflow.graph.json" 2>/dev/null | grep -q '"phase"'; then
        flagged_routed="$flagged_routed $sname(그래프 phase)"
      # 다른 스킬이 **호출**하는가. 이름을 언급만 하는 「경계」 선언
      # ("…를 보는 것은 `/x`다")과 구분해야 한다 — 오탐은 검사를 꺼버리게 만든다.
      # 그래서 호출 동사가 같은 줄에 있을 때만 센다. 놓치는 쪽(미탐)으로 기운 판정이다.
      elif [ "$(grep -rh -- "\`/${sname}\`" "$ROOT"/skills/*/SKILL.md "$ROOT"/marketing/skills/*/SKILL.md "$ROOT"/harness/skills/*/SKILL.md 2>/dev/null \
               | grep -cE '실행|호출|부른다|순차')" -gt 0 ]; then
        flagged_routed="$flagged_routed $sname(다른 스킬이 호출)"
      fi
    fi
  done < <(skill_mds)
  if [ -n "$legacy_key" ]; then
    bad "플랫폼 계약에 없는 프론트매터 키 'trigger:':$legacy_key" \
        "아무 효과가 없다. 수동 전용은 'disable-model-invocation: true' (docs/platform-contract.md §2.4)"
  else
    ok "프론트매터 키 전부 계약 내"
  fi
  if [ -n "$manual_unflagged" ]; then
    bad "수동 전용인데 description이 상주:$manual_unflagged" \
        "프론트매터에 'disable-model-invocation: true'를 넣으면 매 세션 상주 비용이 0이 된다 (docs/platform-contract.md §2.4)"
  else
    ok "수동 전용 선언 ↔ 상주 플래그 일치"
  fi
  if [ -n "$flagged_routed" ]; then
    bad "자동 발동 대상에 모델 호출 차단:$flagged_routed" \
        "라우팅·그래프가 자동 발동으로 지목하는 스킬은 모델이 부를 수 있어야 한다 — 플래그를 빼거나 라우팅에서 내린다"
  else
    ok "모델 호출 차단이 라우팅을 끊지 않음"
  fi

  # 네이티브와 싸우는 문구
  local nfight=0 sr
  while IFS= read -r sr; do
    grep -rq 'skill-creator 플러그인보다 우선' "$sr" 2>/dev/null && nfight=1
  done < <(skill_roots)
  if [ "$nfight" -eq 1 ]; then
    bad "네이티브 스킬(skill-creator)을 밀어내는 문구 존재" "플랫폼 네이티브와 싸우지 않는다 (P6)"
  else
    ok "네이티브를 밀어내는 문구 없음"
  fi

  # ── 6.5 스킬 내부 참조 (B-6) ──
  # SKILL.md가 가리키는 references/·assets/·resources/ 상대 경로의 실재.
  # 기존 dangling 검사는 .claude/rules만 봐서 이 사각지대가 5건을 4개월간 숨겼다.
  sec "스킬 내부 참조"
  local sdang=0 schecked=0
  local sd
  while IFS= read -r sd; do
    [ -f "$sd/SKILL.md" ] || continue
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      schecked=$((schecked+1))
      # 스킬 디렉토리 우선, 플러그인 루트 폴백 (${CLAUDE_PLUGIN_ROOT}/scripts/* 참조 허용)
      if [ ! -f "$sd/$ref" ] && [ ! -f "$ref" ]; then
        bad "$(basename "$sd") → $ref 없음"; sdang=$((sdang+1))
      fi
    done < <(grep -ohE '(skills/[A-Za-z0-9._-]+/)?(references|assets|resources|scripts)/[A-Za-z0-9._/-]+\.(md|json|csv|txt|py|sh|html|hbs)' "$sd/SKILL.md" 2>/dev/null | sort -u)
  done < <(skill_dirs)
  [ "$sdang" -eq 0 ] && ok "스킬 내부 참조 ${schecked}건 모두 실재"

  # .claude/skills/ 하드코딩 — 플러그인 스킬이 프로젝트 오버라이드 경로를 지시하면
  # 오버라이드가 없는 프로젝트(플러그인 전용 설치)에서 그 명령은 실패한다.
  local hc=0
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    warn ".claude/skills/ 경로 하드코딩: $hit" "\${CLAUDE_SKILL_DIR} 기준으로 변경"
    hc=$((hc+1))
  done < <(skill_mds | while IFS= read -r sm; do grep -lE 'python3 \.claude/skills/|bash \.claude/skills/' "$sm" 2>/dev/null; done)
  [ "$hc" -eq 0 ] && ok "스크립트 호출의 .claude/skills/ 하드코딩 없음"

  # 번들 스크립트 경로 표기 — Claude Code가 치환하는 것은 \${CLAUDE_SKILL_DIR}와
  # \${CLAUDE_PLUGIN_ROOT} 둘뿐이다. <skill-dir> 같은 자작 표기는 **아무것도 치환하지
  # 않는다**. 이 저장소에서는 상대 경로가 우연히 맞아 드러나지 않지만, 소비자에서 스킬은
  # 플러그인 캐시에 있으므로 모델이 경로를 추측해야 하고 호출이 실패한다.
  local bogus=0
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    bad "치환되지 않는 스크립트 경로 표기: $hit" "\${CLAUDE_SKILL_DIR} 또는 \${CLAUDE_PLUGIN_ROOT}만 치환된다"
    bogus=$((bogus+1))
  # BSD grep은 BRE에서 \| 교대를 지원하지 않는다 → -E(ERE) 필수.
  # (이 파일 상단 code_lines()가 sed에 대해 같은 함정을 이미 적어두었다)
  done < <(skill_roots | while IFS= read -r sr; do grep -rnE '<skill[-_]dir>|\{skill[-_]dir\}|<Base directory>' "$sr" 2>/dev/null; done | cut -c1-120)
  [ "$bogus" -eq 0 ] && ok "번들 스크립트 경로 표기 정상 (\${CLAUDE_SKILL_DIR})"

  # 공유 사본 쌍의 내용 drift (사본 공유 구조의 알려진 실패 모드)
  # 동명 ≠ 사본 (complete-examples.md는 스킬마다 독립 내용). 파일명 추측 대신
  # 'epcc-doctor: shared-copy' 마커를 선언한 파일만 쌍으로 검사한다.
  local drift=0
  while IFS= read -r base; do
    [ -z "$base" ] && continue
    local first="" f2
    while IFS= read -r f2; do
      if [ -z "$first" ]; then first="$f2"
      elif ! diff -q "$first" "$f2" >/dev/null 2>&1; then
        warn "공유 사본 내용 상이: $first ↔ $f2" "사본 드리프트 — 한쪽을 원본으로 정하고 동기화"
        drift=$((drift+1))
      fi
    done < <(_shared_copies | grep "/$base$" | sort)
  done < <(_shared_copies | xargs -I{} basename {} | sort | uniq -d)
  [ "$drift" -eq 0 ] && ok "공유 사본 드리프트 없음"

  # 빈 절 제목 — 제목만 있고 본문 없이 같거나 얕은 레벨 제목이 뒤따르는 절.
  # description은 그 절이 있다고 약속하는데 본문은 비어 있으므로 **실행마다 구조가 달라진다**
  # (실측: enhancement-ab-v1의 E1에서 빈 Step 하나가 4섹션 계약을 0/4로 만들었다).
  # 이 결함은 스킬을 강화할 때만 사람이 봤고 기계는 아무도 보지 않아 살아남았다.
  # 코드 펜스 안의 '## '는 예시이지 절이 아니다 — 세지 않는다(오탐은 검사를 꺼버린다).
  local emptyh=0 eh
  while IFS= read -r eh; do
    [ -z "$eh" ] && continue
    warn "빈 절 제목: $eh" "제목이 약속한 본문이 없다 — 채우거나 제목을 지운다"
    emptyh=$((emptyh+1))
  done < <(skill_mds | while IFS= read -r sm; do
      awk -v F="$sm" '
        /^```/ { fence = !fence; prev=""; next }
        fence  { next }
        /^#+ / { lvl = index($0, " ") - 1
                 if (lvl >= 2 && prev != "" && lvl <= plvl) print F ": " prev
                 prev = (lvl >= 2 ? $0 : "")
                 plvl = lvl
                 next }
        NF     { prev = "" }
      ' "$sm"
    done)
  [ "$emptyh" -eq 0 ] && ok "빈 절 제목 없음"

  # 고아 리소스 — SKILL.md에서도, SKILL.md가 닿는 어떤 파일에서도, 저장소 어디에서도
  # 참조되지 않는 번들 파일. 위 「스킬 내부 참조」는 **선언→실물** 방향만 본다.
  # 반대 방향(실물→선언)이 사각이라 본문은 비어 있는데 참조만 떠 있는 배선 단절이 남았다.
  #
  # 판정은 **전이 폐포**다. ui-ux-design의 core.py는 SKILL.md가 아니라 search.py가
  # import한다 — 직접 참조만 세면 살아있는 파일을 죽었다고 부른다. 저장소 전역(스킬
  # 디렉토리 밖) 호출도 살아있음으로 친다: guide-gate.sh는 CLAUDE.md·npm test가 부른다.
  #
  # 대조는 **확장자를 뗀 이름**까지 본다. 참조는 파일명 그대로 오지 않는다 —
  # `from design_system import`(파이썬 import) · `--stack nextjs`(인자로 조립되는 경로) ·
  # `profiles/$lang.sh`(변수 치환). 확장자 있는 이름만 보면 이 셋이 전부 오탐이 된다.
  # 대가는 `core`·`python` 같은 짧은 이름이 산문에 우연히 걸려 진짜 고아를 놓치는 것이다 —
  # **미탐 쪽으로 기운 의도된 선택**이다. 오탐은 사람이 검사를 꺼버리게 만들지만
  # 미탐은 다음 검사 강화가 주워간다.
  local orphan=0 od
  while IFS= read -r od; do
    [ -f "$od/SKILL.md" ] || continue
    local cand; cand=$(find "$od" -type f ! -name SKILL.md ! -path '*/.*' 2>/dev/null | sort)
    [ -z "$cand" ] && continue
    local reach="$od/SKILL.md" round c stem rf hit newreach outside
    for round in 1 2 3; do
      newreach="$reach"
      while IFS= read -r c; do
        [ -z "$c" ] && continue
        case $'\n'"$newreach"$'\n' in *$'\n'"$c"$'\n'*) continue;; esac
        stem=$(basename "$c"); base=${stem%.*}; hit=0
        while IFS= read -r rf; do
          [ -z "$rf" ] && continue
          grep -qF "$stem" "$rf" 2>/dev/null && { hit=1; break; }
          grep -qF "$base" "$rf" 2>/dev/null && { hit=1; break; }
        done <<< "$reach"
        [ "$hit" -eq 1 ] && newreach="$newreach
$c"
      done <<< "$cand"
      [ "$newreach" = "$reach" ] && break
      reach="$newreach"
    done
    while IFS= read -r c; do
      [ -z "$c" ] && continue
      case $'\n'"$reach"$'\n' in *$'\n'"$c"$'\n'*) continue;; esac
      stem=$(basename "$c"); base=${stem%.*}
      outside=$(grep -rlF "$base" . --exclude-dir=.git --exclude-dir=node_modules \
                  --exclude-dir=.ua --exclude-dir=dev 2>/dev/null | grep -v "^\./${od}/" | head -1)
      [ -n "$outside" ] && continue
      warn "고아 리소스: $c" "SKILL.md에서 전이적으로도 저장소에서도 닿지 않는다 — 재연결하거나 뺀다"
      orphan=$((orphan+1))
    done <<< "$cand"
  done < <(skill_dirs)
  [ "$orphan" -eq 0 ] && ok "고아 리소스 없음"

  # 코드블록 안의 플러그인 상대 경로 — 산문의 `rules/x.md`는 정본 위치를 말하는 인용이지만
  # 코드블록의 `grep … rules/workflow-routing.md`는 **실행**된다. 소비자에서 그 경로는 없다
  # (`.claude/rules/…`거나 플러그인 캐시 안이다) — `${CLAUDE_PLUGIN_ROOT}`로 써야 치환된다 (평가 v6 · E-34).
  # 산문은 보지 않는다: 정본을 가리키는 인용을 전부 변수로 바꾸면 사람이 읽을 수 없다.
  local bp_bad=0 bp_list="" bpf bph
  while IFS= read -r bpf; do
    [ -f "$bpf" ] || continue
    grep -q 'epcc-doctor: allow-bare-paths' "$bpf" 2>/dev/null && continue
    bph=$(awk '/^```/{f=!f; next} f' "$bpf" 2>/dev/null \
      | grep -E '(^|[^A-Za-z0-9_/.$}-])(rules|scripts|skills|guides|templates|presets)/[A-Za-z0-9_.*/-]+' \
      | grep -vE 'CLAUDE_PLUGIN_ROOT|CLAUDE_SKILL_DIR|\.claude/|^[[:space:]]*#' | head -1)
    [ -z "$bph" ] && continue
    bp_bad=$((bp_bad+1)); bp_list="$bp_list
      · $bpf: $(printf '%s' "$bph" | cut -c1-80)"
  done < <({ skill_mds; find skills -type f \( -path '*/references/*.md' -o -path '*/assets/*.md' \) 2>/dev/null; } | sort -u)
  if [ "$bp_bad" -gt 0 ]; then
    bad "코드블록의 플러그인 상대 경로 ${bp_bad}파일:$bp_list" "소비자에서 실행되면 '없는 파일'이다 — \${CLAUDE_PLUGIN_ROOT}/…로 쓴다 (인용 산문은 그대로)"
  else
    ok "코드블록 경로 표기 정상 (플러그인 상대 경로 없음)"
  fi

  # ── 6.6 포트 잔재 ──
  #
  # 원본 저장소에서 옮겨 온 자산에는 **그때는 참이었으나 배포 맥락에서 거짓이 된 문장**이
  # 남는다. 틀리게 쓴 것이 아니라 맞게 쓴 것이 이사하면서 틀려졌으므로 문장 자체는
  # 자연스럽고 사람 눈에 안 띈다. 실측: 잔재 4건이 4.5개월·89커밋·doctor 강화 14회·
  # 하네스 평가 5회를 통과했다(2026-04-14 유입 → 2026-09-02 발견).
  #
  # 기존 검사가 못 잡는 이유는 셋이다. ① 「선언↔실물」은 **수치만** 대조하는데 개명은
  # 수치를 바꾸지 않는다 ② dangling 검사는 `.claude/rules/*.md` 한 패턴만 본다
  # ③ 위생 검사 대부분이 SKILL.md만 읽어 references/·resources/가 사각이다.
  # 그래서 여기서는 **재귀**로 본다.
  sec "포트 잔재"

  # 스캔 대상 — 소비자에게 배포되거나 소비자 문서를 생성하는 자산.
  # dev/는 넣지 않는다: 개발 기록이라 옛 이름을 서술하는 것이 정상이다.
  local _pr_targets=() _pt
  # harness/ 는 넣지 않는다: 이 절은 **소비자에게 배포되는** 자산의 잔재를 보는데,
  # harness/ 는 저작자 본인만 설치하는 플러그인이라 자기 이름·플러그인 경로가 정상 서술이다.
  for _pt in skills rules agents templates guides marketing; do
    [ -d "$_pt" ] && _pr_targets+=("$_pt")
  done

  # ① 소비자 경로에 나타난 스킬 이름 — 3분 판정.
  #    생성물(frontend-guide·backend-guide)은 소비자 .claude/skills/가 실제 위치이므로 정상.
  #    플러그인 스킬은 **플러그인 캐시에 살고 소비자 .claude/에 절대 놓이지 않는다** —
  #    거기 있다고 쓰면 모델이 없는 경로를 읽으러 간다.
  #    어느 쪽도 아니면 개명·폐기 후 따라가지 못한 죽은 참조다.
  local _pr_bad=0 _pr_chk=0
  if [ ${#_pr_targets[@]} -gt 0 ]; then
    local _sname
    while IFS= read -r _sname; do
      [ -z "$_sname" ] && continue
      _pr_chk=$((_pr_chk+1))
      case "$_sname" in
        frontend-guide|backend-guide) continue ;;   # 생성물 — 정상
      esac
      if [ -f "skills/$_sname/SKILL.md" ] || [ -f "marketing/skills/$_sname/SKILL.md" ] || [ -f "harness/skills/$_sname/SKILL.md" ]; then
        bad "소비자 경로에 플러그인 스킬: .claude/skills/$_sname" \
            "플러그인 스킬은 캐시에 산다. 소비자 .claude/skills/에는 생성물(frontend-guide·backend-guide)만 놓인다"
        _pr_bad=$((_pr_bad+1))
      else
        bad "죽은 스킬 참조: .claude/skills/$_sname" \
            "그런 스킬이 없다 — 개명·폐기 후 참조를 따라가지 않았다 (harness-change 「변경 후 역추적」)"
        _pr_bad=$((_pr_bad+1))
      fi
    # `deprecated`가 같은 줄에 있으면 폐기 경로 변환 예시다(harness-change 「Shadow 미러」).
    # 진짜 잔재는 폐기를 서술하지 않으므로 이 면제는 결함을 가리지 않는다.
    done < <(grep -rhE '\.claude/skills/[A-Za-z0-9._-]+' "${_pr_targets[@]}" 2>/dev/null \
             | grep -v 'deprecated' \
             | grep -oE '\.claude/skills/[A-Za-z0-9._-]+' | sed 's|.*/||' | sort -u)
  fi
  if [ "$_pr_bad" -eq 0 ]; then
    ok "소비자 경로의 스킬 이름 ${_pr_chk}종 정상"
  fi

  # ② 저장소 이름 누출 — 이름 집합을 매니페스트에서 도출한다(하드코딩 최소화).
  #    원본 저장소명만은 도출 불가라 명시한다. 이 이름들이 배포 자산에 예시·기본값으로
  #    박히면 소비자가 남의 프로젝트 이름을 받는다.
  #    URL이 있는 줄은 면제 — 이 저장소가 스키마의 실제 호스트다(epcc-init의 $schema).
  # jq에 의존하지 않는다 — 이 파일의 다른 매니페스트 판독과 같은 관례(grep -m1 + sed -E).
  _pr_name() {  # $1 파일
    [ -f "$1" ] || return 0
    grep -m1 '"name"' "$1" 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/'
  }
  # 디렉토리명은 쓰지 않는다 — 체크아웃 이름은 사용자가 바꿀 수 있고, `base`·`src`처럼
  # 짧고 흔한 값이면 온갖 산문에 걸려 검사를 못 쓰게 만든다(픽스처 트리에서 실측됐다).
  # 매니페스트의 선언만 쓰고, 6자 미만은 버린다.
  local _self_names="" _n
  for _n in "$(_pr_name .claude-plugin/plugin.json)" \
            "$(_pr_name package.json)" \
            "$(_pr_name .claude-plugin/marketplace.json)" \
            "EasyPeasyClaudeCodeDevkit"; do
    [ ${#_n} -ge 6 ] && _self_names="$_self_names $_n"
  done
  local _leak=0 _lhit
  if [ ${#_pr_targets[@]} -gt 0 ] && [ -n "$_self_names" ]; then
    for _n in $_self_names; do
      while IFS= read -r _lhit; do
        [ -z "$_lhit" ] && continue
        bad "저장소 이름 누출: $_lhit" \
            "소비자에게 배포되는 자산이다 — 플레이스홀더로 바꾼다 (URL은 면제)"
        _leak=$((_leak+1))
      done < <(grep -rnF -- "$_n" "${_pr_targets[@]}" 2>/dev/null \
               | grep -vE 'https?://' | cut -c1-110)
    done
  fi
  if [ "$_leak" -eq 0 ]; then
    ok "배포 자산 자기이름 검사 통과"   # 실패 메시지를 부분 포함하지 않게 — 기준선 grep이 성공을 오탐으로 읽는다
  fi

  # ③ 규칙 카드 본문의 **플러그인 맥락 경로** — ①②와 같은 사건의 세 번째 얼굴이다.
  #    ①②는 이사한 **이름**을 보고, 이것은 이사한 **경로**를 본다.
  #    T1 카드는 install-rules.sh가 소비자 `.claude/rules/`로 배송하므로 본문의 상대
  #    경로는 **소비자 루트**에서 해석된다. 플러그인 저장소에서 참인 경로를 그대로
  #    쓰면 모델이 없는 파일을 읽으러 간다 — 틀리게 쓴 것이 아니라 맞게 쓴 것이
  #    이사하면서 틀려졌으므로 사람 눈에 안 띈다(harness-change 「변경 후 역추적」).
  #    실측: harness-change.md 한 장에 6건(agents/·docs/×2·rules/·scripts/×2)이 있었고
  #    소비자 레이아웃에서 전부 없는 파일이었다. 표기 규약은 `<플러그인-루트>/…`이다.
  #
  #    판정식은 **플러그인에 실재하는가**다. 그것이 "저자가 플러그인 맥락에서 썼다"의
  #    유일한 기계 증거다. 존재하지 않는 경로는 이 검사의 대상이 아니다 —
  #    소비자가 만들 파일을 미리 가리키는 정상 서술과 구별할 수 없기 때문이다.
  local _pc_bad=0 _pc_n=0 _pcp _pcc
  # 프로젝트가 소유하고 하네스가 **필요할 때 만드는** 산출물. 신규 소비자에 없는 것이
  # 정상이라 면제한다. 이 목록을 늘리기 전에 "정말 프로젝트 소유인가"를 먼저 묻는다 —
  # 면제는 검사를 무디게 하는 유일한 방향이다.
  local _pc_owned=" docs/lessons.md docs/lessons-archive.md docs/decisions.md docs/decisions-archive.md dev/docs/ "
  if [ -d rules ]; then
    for _pcc in rules/*.md; do
      [ -f "$_pcc" ] || continue
      while IFS= read -r _pcp; do
        [ -z "$_pcp" ] && continue
        case "$_pc_owned" in *" $_pcp "*) continue ;; esac
        [ -e "$_pcp" ] || continue
        _pc_n=$((_pc_n+1))
        bad "규칙 카드의 플러그인 맥락 경로: $_pcc → $_pcp" \
            "소비자 .claude/rules/에서 이 상대 경로는 없는 파일입니다. \`<플러그인-루트>/$_pcp\`로 쓰세요"
        _pc_bad=$((_pc_bad+1))
      done < <(grep -ohE '`[a-z][a-zA-Z0-9._-]*/[a-zA-Z0-9./_-]+`' "$_pcc" 2>/dev/null | tr -d '`' | sort -u)
    done
  fi
  [ "$_pc_bad" -eq 0 ] && ok "규칙 카드 경로 표기 정상 (소비자 루트 기준)"

  # ── 7. 매니페스트 정합 ──
  #
  # 버전은 4곳에 흩어져 있다. 앞의 둘만 보던 검사를 README 배지와 marketplace.json까지
  # 넓힌다 — 뒤의 둘은 아무도 잡지 않아 어긋난 채 배포될 수 있었다.
  # ── 6.8 축 가이드 팩 (v3.12.0) ──
  # 사전 제작 단위가 조합에서 축으로 내려갔다. 팩은 스킬이 아니라 자산이므로
  # 스킬 검사가 닿지 않는다 — 여기서 계약 완비와 기준선 나이를 본다.
  if [ -d guides ]; then
    sec "축 가이드 팩"
    local pk pn pmiss=0 pold=0 pcount=0 pstale=""
    for pk in guides/frontend/*/ guides/backend/*/; do
      [ -d "$pk" ] || continue
      pcount=$((pcount+1)); pn=${pk%/}; pn=${pn#guides/}
      for req in PACK.md ledger.md policies.md pack.json; do
        [ -f "$pk$req" ] || { bad "팩 $pn: $req 없음" "팩 계약 4종이 다 있어야 게이트가 경계를 검사한다"; pmiss=$((pmiss+1)); }
      done
      # 리소스 전량에 배송 스탬프가 있어야 install-guide.sh가 멱등 갱신을 판정한다
      local nost; nost=$({ grep -L '^<!-- epcc-pack:' "$pk"resources/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')
      [ "$(num "$nost")" -gt 0 ] && { bad "팩 $pn: 스탬프 없는 리소스 ${nost}개" "스탬프가 없으면 사용자 수정본과 구버전을 구별할 수 없다"; pmiss=$((pmiss+1)); }
      # 기준선 나이 — 감사받지 않는 사전 제작본은 없는 가이드보다 나쁘다
      local vd; vd=$({ grep -m1 -oE 'verified [0-9]{4}-[0-9]{2}-[0-9]{2}' "$pk"PACK.md 2>/dev/null || true; } | awk '{print $2}')
      if [ -z "$vd" ]; then warn "팩 $pn: PACK.md에 verified 날짜 없음"; else
        local vts nts age
        vts=$(num "$(date -j -f %Y-%m-%d "$vd" +%s 2>/dev/null || date -d "$vd" +%s 2>/dev/null || true)")
        nts=$(num "$(date +%s)")
        if [ "$vts" -gt 0 ] && [ "$nts" -gt "$vts" ]; then
          age=$(( (nts - vts) / 86400 ))
          [ "$age" -ge 180 ] && { pstale="$pstale $pn(${age}일)"; pold=$((pold+1)); }
        fi
      fi
    done
    [ -n "$pstale" ] && warn "팩 기준선 6개월 초과:$pstale" "메이저 버전이 올랐는지 확인하고 감사 후 verified를 갱신한다"
    [ "$pmiss" -eq 0 ] && ok "축 팩 ${pcount}개 계약·스탬프 완비"
    # 이음매가 가리키는 팩이 실재하는가
    local sm smiss=0
    for sm in guides/seams/*/seam.json; do
      [ -f "$sm" ] || continue
      while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        [ -d "guides/$ref" ] || { bad "이음매 $(basename "$(dirname "$sm")"): 팩 $ref 없음"; smiss=$((smiss+1)); }
      done < <({ grep -oE '"(frontend|backend)Pack"[[:space:]]*:[[:space:]]*"[^"]+"' "$sm" 2>/dev/null || true; } | sed -E 's/.*"([^"]+)"$/\1/')
    done
    [ "$smiss" -eq 0 ] && ok "이음매의 팩 참조 실재"
  fi

  sec "매니페스트"
  local pv cv rv mism=""
  pv=$(grep -m1 '"version"' package.json 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  cv=$(grep -m1 '"version"' .claude-plugin/plugin.json 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  rv=$(grep -m1 -oE 'version-[0-9]+\.[0-9]+\.[0-9]+' README.md 2>/dev/null | sed 's/version-//')
  if [ -z "$pv" ]; then
    bad "package.json에서 버전을 읽지 못함"
  else
    [ "$cv" = "$pv" ] || mism="$mism plugin.json=${cv:-없음}"
    [ "$rv" = "$pv" ] || mism="$mism README배지=${rv:-없음}"
    # marketplace.json의 버전은 2곳이다 — 마켓플레이스 metadata + **이 플러그인의** 항목.
    # 이 저장소는 플러그인을 셋 호스팅하고(epcc-marketing·epcc-harness는 독립 버전이다) 파일의 모든
    # "version"을 긁으면 남의 버전까지 기준과 대조해 **오탐으로 실패한다.** 엔트리로 좁힌다.
    # jq 부재는 판정 불가다 — 차단하지 않고 건너뛰되 침묵하지 않는다 (3상태 규율).
    local mpname mtot=0 mbad=0 mv mskip=0
    mpname=$(grep -m1 '"name"' .claude-plugin/plugin.json 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    if command -v jq >/dev/null 2>&1; then
      while IFS= read -r mv; do
        [ -z "$mv" ] && continue
        mtot=$((mtot+1))
        [ "$mv" = "$pv" ] || mbad=$((mbad+1))
      done < <(jq -r --arg n "$mpname" \
                 '[.metadata.version?, (.plugins[]?|select(.name==$n)|.version)] | map(select(.!=null)) | .[]' \
                 .claude-plugin/marketplace.json 2>/dev/null)
      [ "$mtot" -eq 0 ] && mism="$mism marketplace.json=읽지못함"
      [ "$mbad" -gt 0 ] && mism="$mism marketplace.json(${mbad}/${mtot}곳 불일치)"
    else
      mskip=1
    fi
    if [ -n "$mism" ]; then
      bad "버전 불일치 (기준 package.json=$pv):$mism" \
          "4곳을 동시에 올린다 — plugin.json · package.json · README 배지 · marketplace.json"
    elif [ "$mskip" -eq 1 ]; then
      warn "marketplace.json 버전 대조 판정 불가 — jq 없음" \
           "plugin.json · package.json · README 배지 3곳은 일치 ($pv)"
    else
      ok "버전 4곳 일치 ($pv · marketplace ${mtot}곳 포함)"
    fi

    # 릴리스 도달 — 위의 4곳이 일치해도 **배포된 것은 아니다.** 대조 대상이 전부
    # 로컬 파일이라, 버전만 올리고 태그·푸시를 하지 않으면 소비자는 계속 옛 버전을
    # 받는다. 실제로 3.18.0을 17번 올리는 동안 배포된 것은 2.0.0이었다 (평가 v3 · E-08·E-12).
    # 원격을 조회하지 않는다 — 네트워크는 경계를 넘고(P7), 오프라인에서 못 돌면 검사가 아니다.
    # .git이 없으면 침묵한다: 소비자 캐시에는 .git이 없고, 거기서 경고하면 모든
    # 소비자에게 꺼지지 않는 경고가 된다.
    local pname rtag
    pname=$(grep -m1 '"name"' .claude-plugin/plugin.json 2>/dev/null | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    rtag="${pname:-plugin}--v${pv}"
    if [ -e .git ] && command -v git >/dev/null 2>&1; then
      if git rev-parse -q --verify "refs/tags/$rtag" >/dev/null 2>&1; then
        # 태그가 **있다**는 것과 **HEAD가 배포됐다**는 것은 다르다. 태그 뒤에 자산 커밋이
        # 쌓이면 이름은 통과하는데 소비자는 그 커밋을 하나도 받지 못한다 — 3.28.0 태그 뒤
        # 13커밋이 그 상태였다 (평가 v7 · E-52). 버전을 올리면 태그 이름이 바뀌어 위의
        # 「미배포」 경고로 넘어가므로, 이 경고는 "올려야 할 때"를 가리킨다.
        local after_tag
        after_tag=$(num "$(git rev-list --count "$rtag..HEAD" -- skills agents rules hooks scripts templates guides references presets schema workflow.graph.json 2>/dev/null)")
        if [ "$after_tag" -gt 0 ]; then
          warn "릴리스 태그 존재 ($rtag) — 그 뒤 자산 커밋 ${after_tag}건이 미배포" \
               "소비자는 태그 시점의 자산만 받는다. 버전 4곳 인상 → 커밋 → 'claude plugin tag --push'"
        else
          ok "릴리스 태그 존재 ($rtag) · 태그 이후 자산 커밋 0"
        fi
      else
        warn "버전 $pv 미배포 — 릴리스 태그 '$rtag' 없음" \
             "커밋 후 'claude plugin tag --push'. 태그 없이 버전만 올리면 소비자는 계속 옛 버전을 받는다"
      fi
    fi
  fi
  [ -f plugin.json ] && bad "루트 plugin.json 중복 존재" "Claude Code는 .claude-plugin/plugin.json만 읽음" \
                     || ok "매니페스트 단일"
  # hooks/hooks.json은 Claude Code가 자동 발견한다. 매니페스트가 같은 파일을 또 가리키면
  # "이미 로드된 파일 중복"으로 플러그인 전체 로드가 거부된다 — claude plugin validate는 이를 잡지 못한다
  if grep -qE '"hooks"[[:space:]]*:[[:space:]]*"(\./)?hooks/hooks\.json"' .claude-plugin/plugin.json 2>/dev/null; then
    bad "매니페스트 hooks가 기본 경로 hooks/hooks.json을 중복 참조" "자동 발견되는 파일이라 플러그인 로드 거부됨 — 해당 줄 삭제"
  else
    ok "매니페스트 hooks 기본 경로 중복 없음"
  fi

  # ── 7.5 선언↔실물 대조 (RC5) ──
  #
  # 문서에 손으로 적은 수는 반드시 낡는다. README가 "노드 24 · 엣지 41"이라고
  # 적어둔 사이 실물은 49/67이 되어 있었고, 스킬 수는 34·35·31 세 값이 공존했다.
  # 사람이 대조하기를 기대하지 않고 기계가 맞춘다.
  sec "선언↔실물"

  local claims=0 wrong=0
  _claim() {  # $1 라벨  $2 문서에서 뽑은 값  $3 실물  $4 파일
    [ -z "$2" ] && return 0
    claims=$((claims+1))
    [ "$2" = "$3" ] && return 0
    bad "$4: $1 주장 $2 ≠ 실물 $3"; wrong=$((wrong+1))
  }

  # 실물은 한 번만 센다. 대조하는 문서가 셋(README · marketplace.json · 해부 문서)으로
  # 늘었는데 각자 세면 **검사 자신이 사본을 셋 갖는 꼴**이 된다.
  # 판정 불가(jq 부재·파일 부재)는 빈 문자열로 두고 그 항목만 건너뛴다 — 3상태 규율.
  local real_sk real_ru real_fe real_be
  local real_nd="" real_ed="" real_hk=""
  real_sk=$(num "$(find skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')")
  real_ru=$(num "$({ ls -1 rules/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')")
  real_fe=$(num "$({ ls -1 presets/frontend/*.json 2>/dev/null || true; } | wc -l | tr -d ' ')")
  real_be=$(num "$({ ls -1 presets/backend/*.json 2>/dev/null || true; } | wc -l | tr -d ' ')")
  # 팩 수만은 **부재를 0으로 접지 않는다.** --consumer의 캐시 복사는 guides/를 제외하므로
  # 거기서 0으로 세면 정상 트리를 오탐한다 — 없는 것과 0개인 것은 다르다 (3상태 규율).
  local real_fp="" real_bp=""
  if [ -d guides/frontend ] && [ -d guides/backend ]; then
    real_fp=$(num "$(find guides/frontend -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')")
    real_bp=$(num "$(find guides/backend -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')")
  fi
  if command -v jq >/dev/null 2>&1 && [ -f workflow.graph.json ]; then
    real_nd=$(num "$(jq -r '.nodes|length' workflow.graph.json 2>/dev/null)")
    real_ed=$(num "$(jq -r '.edges|length' workflow.graph.json 2>/dev/null)")
  fi
  # 훅 수의 분모는 **고유 스크립트 수**다. 등록 엔트리 수를 쓰면 handoff.sh 하나가 두
  # 이벤트에 걸린 것 때문에 영원히 미달이 된다 — session-brief·--usage와 같은 식을 쓴다.
  if [ -f hooks/hooks.json ] && command -v jq >/dev/null 2>&1; then
    real_hk=$(num "$(jq -r '[.hooks|to_entries[].value[]?.hooks[]?.command
                    | capture("(?<f>[a-z0-9-]+)\\.sh").f] | unique | length' hooks/hooks.json 2>/dev/null)")
  fi

  # 줄 수 예산도 **손으로 적은 수**다 — 그런데 개수만 대조하고 여기는 비어 있었다.
  # 실제로 T0 예산이 40→42로 오른 뒤 문서 5곳이 40에 멈춰 있었고, 현재 파일(41줄)은
  # 모든 문서가 말하는 예산을 이미 넘긴 채 아무도 실패하지 않았다.
  # 스크립트 개별 줄 수는 넣지 않는다 — 설계 문서의 곁가지이지 예산이 아니다.
  local real_t0 real_rl
  real_t0=$(num "$(wc -l < templates/operating-contract.md 2>/dev/null)")
  real_rl=$(num "$({ cat rules/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')")

  if [ -f README.md ]; then
    if [ -n "$real_nd" ]; then
      _claim "그래프 노드" "$(grep -oE '노드 [0-9]+' README.md | head -1 | sed -E 's/[^0-9]*([0-9]+)/\1/')" "$real_nd" "README.md"
      _claim "그래프 엣지" "$(grep -oE '엣지 [0-9]+' README.md | head -1 | sed -E 's/[^0-9]*([0-9]+)/\1/')" "$real_ed" "README.md"
    fi
    _claim "스킬 수" "$(grep -oE '\| \*\*스킬\*\* \| [0-9]+' README.md | grep -oE '[0-9]+$')" "$real_sk" "README.md"
    _claim "T1 카드 수" "$(grep -oE 'T1 [0-9]+개' README.md | head -1 | sed -E 's/T1 ([0-9]+)개/\1/')" "$real_ru" "README.md"
    # 「T0 N줄 + T1 M개 L줄」 형식. 쉼표는 지우고 비교한다 (문서는 1,080으로 쓴다)
    # `grep -oE '[0-9]+'`로 훑으면 **라벨 안의 숫자**가 섞인다 — "T0"의 0이 값으로 잡혔다.
    # 「선언↔실물」이 자기 자신에게서 두 번째로 잡은 같은 실수다. 캡처 그룹으로 뽑는다.
    _claim "T0 줄 수" "$(grep -m1 -oE 'T0 [0-9]+줄' README.md | sed -E 's/T0 ([0-9]+)줄/\1/')" "$real_t0" "README.md"
    # 「T1 M개 L줄」과 「T1 L줄」 **전부**를 본다. `-m1`로 첫 매치만 보던 동안 v2 비교표의
    # 두 번째 값이 1,080에 멈춰 있었다 (평가 v6 · E-31).
    local _t1v
    for _t1v in $(grep -oE 'T1( [0-9]+개)? [0-9,]+줄' README.md | grep -oE '[0-9,]+줄' | tr -d ',줄' | sort -u); do
      _claim "T1 합계 줄 수" "$_t1v" "$real_rl" "README.md"
    done
    # v2→v3 비교표의 스킬 수 — `| 스킬 | 37개 | **30개** |`의 굵은 값. 위 「| **스킬** |」 패턴은 이 행을 못 본다.
    _claim "스킬 수(비교표)" "$(grep -oE '^\| 스킬 \| [0-9]+개 \| \*\*[0-9]+개' README.md | grep -oE '\*\*[0-9]+' | tr -d '*')" "$real_sk" "README.md"
    # 프리셋 축 개수. vue 축이 프리셋·팩·이음매·init 메뉴에 실재하는데 소비자 문서 3곳에
    # 한 번도 안 나왔고, README는 프론트를 4개라 주장했다. 검사가 같은 표의 옆 행에서
    # 멈춰 있었다 — 축을 늘리는 경로와 문서를 잇는 자리가 여기다 (평가 v5 · E-15).
    _claim "프론트 프리셋 수" "$(grep -oE '2축 [0-9]+\+[0-9]+' README.md | head -1 | sed -E 's/2축 ([0-9]+)\+([0-9]+)/\1/')" "$real_fe" "README.md"
    _claim "백엔드 프리셋 수" "$(grep -oE '2축 [0-9]+\+[0-9]+' README.md | head -1 | sed -E 's/2축 ([0-9]+)\+([0-9]+)/\2/')" "$real_be" "README.md"
  fi

  # marketplace.json은 **설치 전에** 소비자가 읽는 유일한 설명이다. 그런데 대조가
  # README에서 멈춰 있는 동안 여기는 "훅 4종 · 백엔드 팩 7 · 백엔드 프리셋 8"에 멈춰
  # 있었다(실물 5 · 8 · 9). 낡은 수가 가장 오래 사는 곳이 가장 늦게 검사받고 있었다.
  local MP=".claude-plugin/marketplace.json"
  if [ -f "$MP" ]; then
    local mp_pack mp_pre
    mp_pack=$(grep -oE '팩\(프론트 [0-9]+ · 백엔드 [0-9]+\)' "$MP" 2>/dev/null | head -1)
    mp_pre=$(grep -oE '프리셋\(프론트 [0-9]+ · 백엔드 [0-9]+\)' "$MP" 2>/dev/null | head -1)
    [ -n "$real_hk" ] && _claim "훅 수" \
      "$(grep -oE '훅 [0-9]+종' "$MP" 2>/dev/null | head -1 | grep -oE '[0-9]+')" "$real_hk" "$MP"
    _claim "스킬 수" "$(grep -oE '[0-9]+개 스킬' "$MP" 2>/dev/null | head -1 | grep -oE '[0-9]+')" "$real_sk" "$MP"
    if [ -n "$real_fp" ]; then
      _claim "프론트 팩 수" "$(printf '%s' "$mp_pack" | grep -oE '[0-9]+' | head -1)" "$real_fp" "$MP"
      _claim "백엔드 팩 수" "$(printf '%s' "$mp_pack" | grep -oE '[0-9]+' | tail -1)" "$real_bp" "$MP"
    fi
    _claim "프론트 프리셋 수" "$(printf '%s' "$mp_pre"  | grep -oE '[0-9]+' | head -1)" "$real_fe" "$MP"
    _claim "백엔드 프리셋 수" "$(printf '%s' "$mp_pre"  | grep -oE '[0-9]+' | tail -1)" "$real_be" "$MP"
  fi

  # 해부 문서는 하네스의 수를 본문에 적는다 — 즉 **이 저장소가 스스로 만든 사본**이다.
  # 사본을 만들었으면 대조 경로도 같이 만든다. 형식이 깨지면 침묵하지 않고 경고한다:
  # 조용히 건너뛰면 "검사받는 줄 알았는데 안 받던" 상태가 되고, 그게 이 검사의 원래 병이다.
  local AN="docs/harness-anatomy.md"
  if [ -f "$AN" ]; then
    local anl
    anl=$(grep -m1 -oE '훅 [0-9]+ · T1 규칙 카드 [0-9]+ · 스킬 [0-9]+ · 그래프 노드 [0-9]+ · 엣지 [0-9]+' "$AN" 2>/dev/null)
    if [ -z "$anl" ]; then
      warn "$AN에 실물 대조 줄 없음" "형식: '훅 N · T1 규칙 카드 N · 스킬 N · 그래프 노드 N · 엣지 N'"
    else
      # 캡처 그룹으로 뽑는다. `grep -oE '[0-9]+'`로 훑으면 **라벨 안의 숫자**가 섞인다 —
      # "T1"의 1이 값으로 들어와 다섯 자리가 한 칸씩 밀렸다 (이 검사가 자기 자신에게서 잡았다).
      local a_hk a_ru a_sk a_nd a_ed
      read -r a_hk a_ru a_sk a_nd a_ed <<< "$(printf '%s' "$anl" \
        | sed -E 's/^훅 ([0-9]+) · T1 규칙 카드 ([0-9]+) · 스킬 ([0-9]+) · 그래프 노드 ([0-9]+) · 엣지 ([0-9]+)$/\1 \2 \3 \4 \5/')"
      [ -n "$real_hk" ] && _claim "훅 수" "$a_hk" "$real_hk" "$AN"
      _claim "T1 카드 수" "$a_ru" "$real_ru" "$AN"
      _claim "스킬 수" "$a_sk" "$real_sk" "$AN"
      if [ -n "$real_nd" ]; then
        _claim "그래프 노드" "$a_nd" "$real_nd" "$AN"
        _claim "그래프 엣지" "$a_ed" "$real_ed" "$AN"
      fi
    fi
  fi

  # 스킬 수의 사본은 매뉴얼 두 곳에도 있다 — "N개를 외울 필요 없습니다"(user-manual) ·
  # "N개 합계 12,000바이트 예산"(operations-manual). 26→25 정리가 위 세 패턴만 고치고
  # 이 둘을 남겼다 (평가 v7 · E-50). 해부 문서의 「수동 전용 N개」도 손으로 적은 수다 —
  # skill-enhancer를 넣어 6이라 적었는데 dmi 실물은 5였다 (E-49).
  _claim "스킬 수" "$(grep -m1 -oE '[0-9]+개를 외울 필요' docs/user-manual.md 2>/dev/null | grep -oE '^[0-9]+')" "$real_sk" "docs/user-manual.md"
  _claim "스킬 수" "$(grep -m1 -oE '[0-9]+개 합계 12,000바이트' docs/operations-manual.md 2>/dev/null | grep -oE '^[0-9]+')" "$real_sk" "docs/operations-manual.md"
  if [ -f "$AN" ]; then
    local real_dmi
    real_dmi=$(num "$({ grep -l '^disable-model-invocation:[[:space:]]*true' skills/*/SKILL.md 2>/dev/null || true; } | wc -l | tr -d ' ')")
    _claim "수동 전용 수" "$(grep -m1 -oE '수동 호출 전용\*\* \(`disable-model-invocation`\) \|[^|]*— \*\*[0-9]+개\*\*' "$AN" 2>/dev/null | grep -oE '\*\*[0-9]+개\*\*$' | tr -d '*개')" "$real_dmi" "$AN"
  fi

  # 같은 문서가 「security-check가 막는 것 — N종」도 손으로 적는다. 실물은 훅의 차단 사유 제목
  # 수(위 「차단 사유 ↔ 픽스처」와 같은 식). 강제 푸시 게이트에 원격 삭제를 넣자 23이 24가 됐고,
  # 이 대조가 없었으면 그림 설명서 세 곳이 23에 멈췄다(평가 v9 · E-61).
  local real_blk mb
  real_blk=$(num "$({ grep -oE '(dblock|block) "[^"]+"' scripts/security-check.sh 2>/dev/null || true; } \
              | sed -E 's/^(dblock|block) "//; s/"$//; s/ \(\$[a-z_]+\)$//' | sort -u | wc -l | tr -d ' ')")
  if [ "$real_blk" -gt 0 ]; then
    for mb in $(grep -oE '[0-9]+종을 검사해|— [0-9]+종 전부' docs/manual/user.html 2>/dev/null | grep -oE '[0-9]+' | sort -u); do
      _claim "차단 사유 수" "$mb" "$real_blk" "docs/manual/user.html"
    done
    for mb in $(grep -oE '[Ss]creens [0-9]+ patterns|blocks — all [0-9]+<|[0-9]+ things that get blocked' docs/manual/en/user.html 2>/dev/null | grep -oE '[0-9]+' | sort -u); do
      _claim "차단 사유 수" "$mb" "$real_blk" "docs/manual/en/user.html"
    done
  fi

  # 위 검사는 `grep -m1`로 **한 형식의 첫 매치만** 본다. 같은 문서가 다른 표현으로 같은 수를
  # 또 적으면 안 보인다 — 실제로 해부 문서가 556줄 뒤에서 다른 수를 적고 있었고, 그 파일
  # 자신이 "문서에 손으로 적은 수는 반드시 낡는다"고 경고하는 중이었다.
  # 형식을 넓히되 **workflow.graph.json을 언급하는 줄**로 한정한다: 역사 서술
  # (README가 "노드 N · 엣지 N"이라고 적어둔 사이…)은 대조 대상이 아닌데, 그 줄에는
  # 파일명이 없어 자연히 빠진다.
  if [ -n "$real_nd" ]; then
    local gline gnode gedge gsrc
    while IFS=: read -r gsrc gline; do
      [ -z "$gline" ] && continue
      gnode=$(printf '%s' "$gline" | sed -E 's/.*노드 ([0-9]+) · 엣지 ([0-9]+).*/\1/')
      gedge=$(printf '%s' "$gline" | sed -E 's/.*노드 ([0-9]+) · 엣지 ([0-9]+).*/\2/')
      _claim "그래프 노드(본문)" "$gnode" "$real_nd" "$gsrc"
      _claim "그래프 엣지(본문)" "$gedge" "$real_ed" "$gsrc"
    done < <(grep -lF 'workflow.graph.json' README.md CLAUDE.md docs/*.md 2>/dev/null \
             | while IFS= read -r gf; do
                 grep -HF 'workflow.graph.json' "$gf" 2>/dev/null \
                   | grep -E '노드 [0-9]+ · 엣지 [0-9]+' | cut -d: -f1,2- \
                   | sed -E "s|^([^:]*):|\\1:|"
               done)
  fi
  # T0 예산 수치 — 문서가 인용하는 예산은 이 스크립트의 상수와 같아야 한다 (E-25).
  # `예산 N줄`은 CLAUDE.md 예산(60)에도 쓰이므로 T0·운영 규칙을 말하는 줄만 본다.
  local bf bv
  for bf in README.md rules/harness-change.md docs/harness-anatomy.md templates/operating-contract.md; do
    [ -f "$bf" ] || continue
    for bv in $(grep -E 'T0|운영 규칙|operating-contract' "$bf" 2>/dev/null | grep -oE '예산[ :]*[0-9]+줄|[0-9]+줄 예산' | grep -oE '[0-9]+' | sort -u); do
      _claim "T0 예산" "$bv" "$T0_BUDGET" "$bf"
    done
  done
  # T0 **주입** 줄 수(주석 제거 후) — 해부 문서가 "실제 주입 N줄"로 적는다
  local real_t0i
  real_t0i=$(num "$(sed '/<!--/,/-->/d' templates/operating-contract.md 2>/dev/null | sed '/./,$!d' | wc -l | tr -d ' ')")
  # `[0-9]+`로 훑으면 "T0"의 0이 값으로 잡힌다 — 이 파일이 세 번째로 자기에게서 잡은 같은 실수. 「N줄」만 뽑는다.
  for bv in $(grep -oE '주입 [0-9]+줄|운영 규칙 [0-9]+줄이' docs/harness-anatomy.md 2>/dev/null | grep -oE '[0-9]+줄' | tr -d '줄' | sort -u); do
    _claim "T0 주입 줄 수" "$bv" "$real_t0i" "docs/harness-anatomy.md"
  done

  # 그래프 kind 표 — 해부 문서 §04의 `| \`kind\` | N |` 행. tool이 1로 적힌 채 skill-creator가 들어왔다 (E-31).
  if [ -n "$real_nd" ] && [ -f docs/harness-anatomy.md ]; then
    local kk kn
    while IFS=$'\t' read -r kk kn; do
      [ -z "$kk" ] && continue
      _claim "그래프 kind($kk)" "$kn" "$(num "$(jq -r --arg k "$kk" '[.nodes[] | select(.kind==$k)] | length' workflow.graph.json 2>/dev/null)")" "docs/harness-anatomy.md"
    done < <(grep -oE '^\| `(skill|stage|hook|agent|store|tool|terminal)` \| [0-9]+ \|' docs/harness-anatomy.md \
             | sed -E 's/^\| `([a-z]+)` \| ([0-9]+) \|/\1\t\2/')
  fi

  # 에이전트 도구 목록 — README·해부 문서의 표가 frontmatter `tools:`와 같은 집합인가.
  # planner에 WebFetch가 들어간 뒤 두 문서가 넷만 적은 채 남았다 (E-31).
  local af an at dt dl
  for af in agents/*.md; do
    [ -f "$af" ] || continue
    an=$(basename "$af" .md)
    at=$(grep -m1 -E '^tools:' "$af" | sed 's/^tools:[[:space:]]*//' | tr ',·' '\n\n' | tr -d ' ' | grep -v '^$' | sort | tr '\n' ' ')
    [ -z "$at" ] && continue
    for dl in README.md docs/harness-anatomy.md; do
      [ -f "$dl" ] || continue
      # 괄호 안(`disallowedTools`: …)은 도구 목록이 아니라 주석이다 — 떼고 비교한다
      dt=$(grep -m1 -E "^\| \`$an\` \|" "$dl" | awk -F'|' '{print $3}' | sed -E 's/\([^)]*\)//g' | tr ',·' '\n\n' | tr -d ' ' | grep -v '^$' | sort | tr '\n' ' ')
      [ -z "$dt" ] && continue
      _claim "$an 도구 목록" "$dt" "$at" "$dl"
    done
  done
  [ "$wrong" -eq 0 ] && [ "$claims" -gt 0 ] && ok "문서 수치 주장 ${claims}건 실물과 일치"

  # ── 이름 목록 대조 ──
  # 위 _claim은 **수**만 본다. 수가 맞아도 이름이 안 실리는 부류는 못 잡는다.
  # 같은 실패가 두 번 관측됐다: ① vue 축이 프리셋·팩·init 메뉴에 실재하는데 소비자 문서
  # 3곳에 없었다(평가 v5 · E-15 — 그때 수 대조만 넣었다) ② 그 뒤 사전 제작 이음매
  # 3번째(vue+node-api)가 출하됐는데 또 같은 3곳에 안 실렸다.
  # 열거를 담는 파일을 하드코딩하는 것이 이 검사의 의미다 — 그 파일들이 곧 열거 지점이다.
  # 파일 부재는 차단하지 않는다 (harness-change 「차단 장치는 3상태다」 — 판정 불가).
  local nm_bad=0 nm_chk=0

  _names_in() {  # $1 문서  $2 라벨  $3 이름들(공백 구분)
    local doc="$1" label="$2" names="$3" n miss=""
    [ -f "$doc" ] || return 0
    [ -n "$names" ] || return 0
    for n in $names; do
      grep -qF -- "$n" "$doc" || miss="$miss $n"
    done
    nm_chk=$((nm_chk+1))
    [ -z "$miss" ] && return 0
    bad "$doc: $label 누락 —$miss" "축을 늘린 경로가 이 문서를 지나지 않았다"
    nm_bad=$((nm_bad+1)); return 0
  }

  # 이음매는 디렉토리명이 `vue+node-api`인데 문서에는 `vue` × `node-api`로 적힌다.
  # 완전일치를 요구하면 정상 문서를 FAIL시킨다. 그렇다고 `fe.*be`로 느슨하게 두면
  # **프리셋 나열 줄이 우연히 충족시킨다** — 한 줄에 프론트 목록과 백엔드 목록이 같이
  # 있어서 `vue.*node-api`가 걸린다(실측: README:43·getting-started:29에서 미탐).
  # 그래서 **두 이름이 구분자 하나로 인접**한 것만 인정한다.
  _seams_in() {  # $1 문서  $2 이음매 디렉토리명들(공백 구분)
    local doc="$1" seams="$2" s fe be miss=""
    [ -f "$doc" ] || return 0
    [ -n "$seams" ] || return 0
    for s in $seams; do
      fe=${s%%+*}; be=${s##*+}
      grep -qE -- "$fe\`?[[:space:]]*(×|\+)[[:space:]]*\`?$be" "$doc" || miss="$miss $s"
    done
    nm_chk=$((nm_chk+1))
    [ -z "$miss" ] && return 0
    bad "$doc: 사전 제작 이음매 누락 —$miss" "이 조합은 출하되는데 문서가 모른다"
    nm_bad=$((nm_bad+1)); return 0
  }

  local pnames snames doc
  pnames=$({ ls -1 presets/frontend/*.json presets/backend/*.json 2>/dev/null || true; } \
           | sed -E 's|.*/||; s|\.json$||' | sort -u | tr '\n' ' ')
  snames=$({ ls -1d guides/seams/*/ 2>/dev/null || true; } \
           | sed -E 's|.*/([^/]+)/$|\1|' | sort -u | tr '\n' ' ')

  for doc in README.md docs/presets.md docs/getting-started.md skills/epcc-init/SKILL.md; do
    _names_in "$doc" "프리셋 이름" "$pnames"
  done
  # 스킬 이름 — 소비자가 설치 전에 읽는 유일한 목록이 README다. 7개 스킬이 README·docs 어디에도
  # 없었고 그중 하나(test-driven-development)는 그래프 밖 인바운드가 0이었다 (평가 v6 · E-32).
  _names_in README.md "스킬 이름" "$(ls -1 skills 2>/dev/null | tr '\n' ' ')"
  # 그림 설명서(docs/manual/*.html)는 스킬을 `p-skill">/<name>` 필로 전수 나열한다 — 가장 큰
  # 소비자 표면(4파일 400KB)인데 어떤 대조도 닿지 않았고, 3.29.0의 하네스 분리 뒤 이름이 기계 밖에서
  # 낡은 자리가 정확히 여기와 README 표였다(평가 v8 · E-57). **수가 아니라 이름 집합**을 대조한다 —
  # "26 = devkit 25 + harness 1"처럼 수는 틀 잡기에 따라 정당하게 달라지지만 집합은 그렇지 않다.
  # 실물은 개발 하네스의 두 루트(skills/ · harness/skills/)다. marketing/은 독립 플러그인이라
  # 그림 설명서의 범위 밖이다. 필 형식이 없는 문서·파일 부재는 판정 불가 — 통과(3상태).
  _manual_skills_in() {  # $1 문서
    local doc="$1" real listed miss ghost
    [ -f "$doc" ] || return 0
    listed=$(grep -oE 'p-skill">/[a-z0-9-]+' "$doc" 2>/dev/null | sed 's|.*/||' | sort -u)
    [ -n "$listed" ] || return 0
    real=$(find skills harness/skills -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sed 's|.*/||' | sort -u)
    miss=$(comm -23 <(printf '%s\n' "$real") <(printf '%s\n' "$listed") | tr '\n' ' ')
    ghost=$(comm -13 <(printf '%s\n' "$real") <(printf '%s\n' "$listed") | tr '\n' ' ')
    nm_chk=$((nm_chk+1))
    [ -z "$miss$ghost" ] && return 0
    bad "$doc: 매뉴얼 스킬 목록 ≠ 실물${miss:+ — 누락 $miss}${ghost:+ — 유령 $ghost}" \
        "스킬을 넣고 뺀 경로가 그림 설명서를 지나지 않았다 — 필을 고치고 manual-variants.py로 파생본도 다시 낸다"
    nm_bad=$((nm_bad+1)); return 0
  }
  for doc in docs/manual/user.html docs/manual/en/user.html; do
    _manual_skills_in "$doc"
  done
  for doc in README.md docs/getting-started.md skills/stack-guide-generator/assets/guide-skeleton.md; do
    _seams_in "$doc" "$snames"
  done
  [ "$nm_bad" -eq 0 ] && [ "$nm_chk" -gt 0 ] && ok "문서 이름 목록 ${nm_chk}건 실물과 일치 (프리셋·이음매·매뉴얼 스킬)"

  # ── 카드 `paths:` ↔ 문서의 로드 조건 표 ──
  #
  # 수치도 이름도 아닌 세 번째 부류다. 카드의 `paths:`가 **비용과 도달을 동시에** 정하는데
  # (조건부 카드의 폭이 코딩 세션 상주량을 결정한다 — 평가 v6 E-35), 그것을 서술하는 표는
  # 손으로 유지됐다. `skills/epcc-init/SKILL.md`는 표 아래에 "이 표는 rules/의 실제
  # frontmatter를 반영해야 한다"고 **적어만** 두었고 대조하는 것이 없었다.
  # 실측: 그 상태에서 4건이 낡아 있었다 — harness-change의 `rules/**`·`agents/**`·`skills/**`
  # (실제로는 선언되지 않은 경로) · `dev/docs/**`(좁혀진 뒤에도 남음) · ui-design의
  # `**/*.{tsx,jsx,...}`(좁혀진 뒤에도 남음, 2곳).
  #
  # 판정은 **부분집합**이다: 표에 적힌 글롭은 전부 선언에 있어야 하지만, 선언 전부를
  # 표가 나열할 의무는 없다(문서는 요약할 권리가 있다). 그래서 "낡은 글롭"만 잡고
  # "생략"은 통과시킨다 — 그 반대로 두면 표를 읽기 어렵게 만드는 압력이 된다.
  local gl_bad=0 gl_chk=0

  # 중괄호 확장. `dev/docs/{prd,database}/**`와 선언 5줄을 같은 형태로 만든다.
  # eval을 쓰지만 **문자셋을 먼저 검증**한다 — 인용부호·$·백틱·;·공백이 없으므로
  # 확장 외의 해석이 일어날 수 없다. 검증에 걸리면 확장하지 않고 원문을 낸다.
  _glob_expand() {
    case "$1" in
      *'{'*)
        if printf '%s' "$1" | grep -qE '^[A-Za-z0-9_.,*/{}-]+$'; then
          eval "printf '%s\n' $1" 2>/dev/null && return 0
        fi
        printf '%s\n' "$1" ;;
      *) printf '%s\n' "$1" ;;
    esac
  }

  _paths_row() {  # $1 문서
    local doc="$1" card decl row cell g miss
    [ -f "$doc" ] || return 0
    for card in rules/*.md; do
      [ -f "$card" ] || continue
      # 선언 — frontmatter의 paths 글롭을 확장해 모은다
      decl=$({ awk '/^---$/{n++; next} n==1 && /^[[:space:]]*-[[:space:]]*"/{print}' "$card" 2>/dev/null \
              | sed -E 's/.*"([^"]*)".*/\1/' || true; })
      [ -n "$decl" ] || continue                     # 상시 카드는 대조할 표가 없다
      local dexp=""
      while IFS= read -r g; do
        [ -z "$g" ] && continue
        dexp="$dexp $(_glob_expand "$g" | tr '\n' ' ')"
      done < <(printf '%s\n' "$decl")

      # 문서의 표 행 — 첫 칸이 `<카드명>` 인 줄
      row=$({ grep -m1 -F "| \`$(basename "$card")\`" "$doc" 2>/dev/null || true; })
      [ -n "$row" ] || continue
      # 두 번째 칸에서 백틱 글롭만 뽑는다. 글롭이 없으면 산문 요약이므로 대조 대상이 아니다.
      cell=$(printf '%s' "$row" | awk -F'|' '{print $3}')
      miss=""
      while IFS= read -r g; do
        [ -z "$g" ] && continue
        local ge
        while IFS= read -r ge; do
          [ -z "$ge" ] && continue
          case " $dexp " in *" $ge "*) ;; *) miss="$miss $g" ;; esac
        done < <(_glob_expand "$g")
      done < <(printf '%s' "$cell" | grep -oE '`[^`]*\*[^`]*`' | tr -d '`' | sort -u)
      gl_chk=$((gl_chk+1))
      if [ -n "$miss" ]; then
        bad "$doc: $(basename "$card") 로드 조건 표가 선언에 없는 글롭을 주장 —$miss" \
            "카드의 paths:를 좁히거나 넓힌 경로가 이 표를 지나지 않았다"
        gl_bad=$((gl_bad+1))
      fi
    done
    return 0
  }
  _paths_row docs/harness-anatomy.md
  _paths_row skills/epcc-init/SKILL.md
  [ "$gl_bad" -eq 0 ] && [ "$gl_chk" -gt 0 ] && ok "카드 paths ↔ 문서 로드 조건 표 ${gl_chk}건 일치"

  # 고아 자산 — templates/ 중 아무도 참조하지 않는 파일.
  # CLAUDE.md.hbs가 그 상태였다 (epcc-init이 인라인 사본을 쓰고 있어 아무도 안 읽었다).
  local orph=0 ochk=0 ob
  while IFS= read -r tf; do
    [ -f "$tf" ] || continue
    ochk=$((ochk+1)); ob=$(basename "$tf")
    grep -rlF "$ob" --include='*.md' --include='*.sh' --include='*.json' \
      rules skills scripts agents templates docs CLAUDE.md README.md 2>/dev/null \
      | grep -vxF "$tf" | grep -q . && continue
    bad "고아 자산: $tf" "아무도 참조하지 않는다 — 죽은 자산이거나 배선 누락이다"; orph=$((orph+1))
  done < <(find templates -type f 2>/dev/null)
  [ "$orph" -eq 0 ] && [ "$ochk" -gt 0 ] && ok "templates/ ${ochk}건 모두 참조됨"

  # 플랫폼 계약 신선도 (RC1) — 플랫폼은 움직인다. 낡은 계약은 없는 계약보다 위험하다.
  local pc="docs/platform-contract.md"
  if [ ! -f "$pc" ]; then
    bad "$pc 없음" "플랫폼 동작의 정본이 없으면 기억으로 단정하게 된다"
  else
    local oldest="" d dd now age
    now=$(date +%s)
    while IFS= read -r d; do
      dd=$(date -j -f '%Y-%m-%d' "$d" +%s 2>/dev/null || date -d "$d" +%s 2>/dev/null || printf '')
      [ -z "$dd" ] && continue
      age=$(( (now - dd) / 86400 ))
      [ "$age" -gt 180 ] && oldest="$oldest $d(${age}일)"
    done < <(grep -oE '확인: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$pc" | awk '{print $2}')
    if [ -n "$oldest" ]; then
      warn "플랫폼 계약 항목이 180일 초과:$oldest" "공식 문서로 재확인하고 날짜를 갱신하세요"
    else
      ok "플랫폼 계약 확인 날짜 최신 (180일 이내)"
    fi
  fi

  # ── 8. 저장소 작업 규범 (§도달 경로 검증을 이 저장소 자신에게) ──
  #
  # 이 저장소는 자기 rules/를 로드하지 않는다 — 플러그인 컴포넌트 타입에 rules가 없고,
  # 여기엔 .claude/rules/도 없다. 하네스를 고칠 때의 규범이 도달하는 유일한 경로가
  # 루트 CLAUDE.md다. 그 도달을 기계가 지킨다 (v2에서 규칙 697줄이 4개월간 아무 데도
  # 도달하지 못한 사건의 재발 방지).
  sec "저장소 작업 규범"

  if [ ! -f CLAUDE.md ]; then
    bad "CLAUDE.md 없음" "하네스 변경 규범이 세션에 도달할 경로가 없다 (rules/는 소비자 배포용이라 여기서 로드되지 않음)"
  else
    local cn; cn=$(num "$(wc -l < CLAUDE.md 2>/dev/null | tr -d ' ')")
    if [ "$cn" -le 60 ]; then
      ok "CLAUDE.md ${cn}/60줄"
    else
      bad "CLAUDE.md ${cn}줄 — 예산 60줄 초과" "매 세션 상시 주입 비용. 상세는 docs/로 내리고 포인터만 남기세요"
    fi

    # 참조 경로 dangling. 슬래시가 있는 것만 본다 — 규범이 "만들지 마라"고 언급하는
    # 파일명(epcc.config.json 등)을 실재 요구로 오인하지 않기 위함이다.
    local cdang=0 cchk=0 p
    for p in $(grep -ohE '(\.?[A-Za-z0-9_-]+/)+[A-Za-z0-9_.-]+\.(md|sh|json)' CLAUDE.md 2>/dev/null | sort -u); do
      cchk=$((cchk+1))
      [ -e "$p" ] || { bad "CLAUDE.md → $p 없음" "규범이 가리키는 정본이 사라졌다 — 참조가 끊기면 규범도 끊긴다"; cdang=$((cdang+1)); }
    done
    [ "$cdang" -eq 0 ] && ok "CLAUDE.md 참조 ${cchk}건 모두 실재"
  fi

  # 스키마의 미구현 필드
  if grep -q 'disabledSkills\|activeSkills' schema/epcc.config.schema.json presets/*.json presets/*/*.json 2>/dev/null; then
    warn "미구현 필드(activeSkills/disabledSkills)가 스키마·프리셋에 존재" \
         "이를 읽어 스킬을 켜고 끄는 코드가 없음. 게이팅은 작동하지 않음"
  else
    ok "미구현 게이팅 필드 없음"
  fi

  # 설정 표면 ↔ 읽는 코드. 문서가 절(`### key`)로 약속한 최상위 필드를 아무 스크립트·스킬·카드도
  # 읽지 않으면 선언≠실물이다 — `workflow.p0/p6.enabled`·`customResources`가 그 상태였다
  # (평가 v6 · E-30). 답은 둘이다: 구현하거나 선언을 지우거나. 이 검사는 둘 중 하나가 일어나게만 한다.
  # 스키마·init 템플릿은 **쓰는 쪽**이라 읽는 증거로 세지 않는다.
  local cf="docs/configuration.md" ck cmiss="" cchk=0
  if [ -f "$cf" ]; then
    while IFS= read -r ck; do
      [ -z "$ck" ] && continue
      cchk=$((cchk+1))
      # 읽는 형태는 셋이다: jq 경로(`.domains.`) · 따옴표 키(`"domains"`) · 템플릿 변수(`{{#if domains.x}}`)
      grep -rqE "(^|[^A-Za-z0-9_-])${ck}[.\"'}[:space:]]" scripts rules templates agents skills/*/SKILL.md skills/*/scripts 2>/dev/null \
        || cmiss="$cmiss $ck"
    done < <(grep -oE '^### [a-zA-Z]+$' "$cf" 2>/dev/null | sed 's/^### //' | sort -u)
    if [ -n "$cmiss" ]; then
      bad "설정 필드 선언만 있고 읽는 코드 없음:$cmiss" "$cf 의 절이 약속한 필드를 아무 코드도 읽지 않는다 — 구현하거나 절을 지운다"
    elif [ "$cchk" -gt 0 ]; then
      ok "설정 필드 ${cchk}종 전부 읽는 코드 실재"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════════
# --self-test : 이벤트별 픽스처 주입
# ════════════════════════════════════════════════════════════════════
run_self_test() {
  printf "\n${C_D}epcc doctor --self-test${C_0}\n"
  sec "훅 픽스처 주입"

  # 픽스처 주입은 CLAUDE_PROJECT_DIR을 **이 저장소**로 둔다 (아래). 그것이 의도다 —
  # 훅이 진짜 프로젝트를 보게 하는 것이 self-test이고, 합성 프로젝트 검증은 --consumer가
  # 따로 한다. 그런데 그 부수 효과로 하트비트·엣지·베이스라인이 실사용 기록과 섞였고,
  # --usage의 "어느 경로가 실행되는가"가 측정이 아니라 자기 주장이 됐다 (평가 v3 · E-09).
  # 그래서 **보는 곳은 그대로 두고 쓰는 곳만** 임시 디렉토리로 돌린다.
  local stdir sfx=""
  stdir=$(mktemp -d 2>/dev/null) || stdir=""
  # RETURN 트랩은 하나뿐이다 — 아래 정적 픽스처의 $sfx도 여기서 함께 지운다.
  # (두 번 걸면 나중 것이 앞의 것을 덮어써서 임시 디렉토리가 남는다)
  trap 'rm -rf "${stdir:-/nonexistent}" "${sfx:-/nonexistent}"; unset EPCC_STATE_DIR EPCC_HANDOFF_DIR' RETURN
  if [ -n "$stdir" ]; then
    export EPCC_STATE_DIR="$stdir"
    # handoff도 같이 돌린다. 상태 로그만 격리하면 픽스처가 dev/handoff/에 실물을 쓰고
    # 회전이 실사용 복원 자료를 밀어낸다 (평가 v5 · E-13).
    export EPCC_HANDOFF_DIR="$stdir/handoff"
  else
    warn "임시 상태 디렉토리 생성 실패" "픽스처 기록이 실제 로그에 섞인다 — 계측 오염"
  fi

  local fx="scripts/fixtures"
  [ -d "$fx" ] || { bad "픽스처 디렉토리 없음: $fx"; return; }

  local hooks_json="hooks/hooks.json"
  command -v jq >/dev/null 2>&1 || { bad "jq 필요"; return; }

  # 계측 격리의 **증명**. 코드 모양(정규식 lint)이 아니라 행동을 본다 —
  # 픽스처 주입이 실사용 산출물을 건드리면 그 순간 실패한다. 상태 로그는 이미
  # EPCC_STATE_DIR로 돌렸으나 dev/handoff/를 빠뜨려 회전이 실물을 밀어냈다 (평가 v5 · E-13).
  local hd_before hd_after
  hd_before=$({ ls -1 dev/handoff 2>/dev/null || true; } | sort | tr '\n' ' ')

  local total=0 good=0
  # 소비된 픽스처를 **측정**한다. 어떤 픽스처가 쓰이는지 검사 쪽에서 재유도하면
  # (${event}.json 보간 + 리터럴 참조를 다시 구현하면) 사본이 하나 더 생기고,
  # 선택 로직이 바뀌는 순간 검사가 조용히 틀린다. 실제로 먹인 것만 누적한다.
  local used=""
  # 이벤트 → 스크립트 매핑을 hooks.json에서 읽어 각 이벤트 픽스처로 실행
  while IFS=$'\t' read -r event cmd; do
    [ -z "$cmd" ] && continue
    local f; f=$(printf '%s' "$cmd" | grep -oE 'scripts/[a-z0-9./-]+\.sh' | head -1)
    [ -n "$f" ] && [ -f "$f" ] || continue
    total=$((total+1))

    local fixture="$fx/${event}.json"
    [ -f "$fixture" ] || fixture="$fx/default.json"
    [ -f "$fixture" ] || { bad "$(basename "$f") [$event]: 픽스처 없음"; continue; }
    used="$used$(basename "$fixture")
"

    local out err code
    out=$(CLAUDE_PROJECT_DIR="$ROOT" bash "$f" < "$fixture" 2>/tmp/epcc_st_err); code=$?
    err=$(cat /tmp/epcc_st_err 2>/dev/null); rm -f /tmp/epcc_st_err

    if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
      bad "$(basename "$f") [$event]: exit $code" "${err:0:160}"
      continue
    fi
    if [ -n "$err" ]; then
      bad "$(basename "$f") [$event]: stderr 출력" "${err:0:160}"
      continue
    fi
    # 출력이 있으면 이벤트가 지원하는 형태인지 확인
    if [ -n "$out" ]; then
      case "$event" in
        Stop|SubagentStop|PreCompact|SessionEnd)
          if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
            if printf '%s' "$out" | jq -e 'has("decision") or has("reason")' >/dev/null 2>&1; then
              bad "$(basename "$f") [$event]: 미지원 필드 출력"; continue
            fi
          else
            bad "$(basename "$f") [$event]: 평문 출력 (이 이벤트는 JSON 필요)"; continue
          fi
          ;;
      esac
    fi
    good=$((good+1))
    ok "$(basename "$f") [$event] → exit $code"
  done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[]?.hooks[]? | "\($e)\t\(.command)"' "$hooks_json" 2>/dev/null)

  printf "\n  훅 자기검사: ${good}/${total}\n"

  hd_after=$({ ls -1 dev/handoff 2>/dev/null || true; } | sort | tr '\n' ' ')
  if [ "$hd_before" = "$hd_after" ]; then
    ok "픽스처가 실사용 산출물을 건드리지 않음 (dev/handoff 불변)"
  else
    bad "픽스처가 dev/handoff/를 변경했다" \
        "계측이 자기가 재는 데이터를 오염시킨다 — epcc_handoff_dir() 격리 확인 필요"
  fi

  # 폴백 증명 — 등록된 이벤트가 전부 named 픽스처를 가져 위 `default.json` 폴백은
  # **한 번도 실행된 적이 없다**. 실행된 적 없는 경로는 작동한다는 증거가 없다.
  # 새 훅 이벤트를 추가하는 순간 자기검사가 그것을 태우는지가 여기 달려 있다.
  local synth_fixture pcode=0
  synth_fixture="$fx/__epcc_unregistered_event__.json"
  [ -f "$synth_fixture" ] || synth_fixture="$fx/default.json"
  if [ ! -f "$synth_fixture" ]; then
    bad "default.json 없음" "미등록 이벤트의 폴백이 없다 — 새 훅이 자기검사 사각으로 들어간다"
  else
    CLAUDE_PROJECT_DIR="$ROOT" bash scripts/session-brief.sh < "$synth_fixture" >/dev/null 2>&1 || pcode=$?
    used="$used$(basename "$synth_fixture")
"
    if [ "$pcode" -eq 0 ] || [ "$pcode" -eq 2 ]; then
      ok "픽스처 폴백 작동 (미등록 이벤트 → default.json → exit $pcode)"
    else
      bad "픽스처 폴백이 깨졌다 (exit $pcode)" "새 훅 이벤트를 추가해도 자기검사가 그것을 태우지 못한다"
    fi
  fi

  # ── 양성 픽스처 (B-7): '살아있다'가 아니라 '막는다'를 증명 ──
  # 무해 픽스처는 exit 0만 확인한다. 차단돼야 할 입력이 실제로 exit 2로
  # 차단되는지는 별도 증명이 필요하다 (v2 교훈: 살아있음 ≠ 작동함).
  sec "양성 픽스처 (차단 검증)"
  # 도구 경로마다 따로 증명한다. 매처가 Edit|Write|MultiEdit뿐이던 동안 Bash 힙독으로
  # 쓰는 시크릿은 차단이 0이었고, Write 픽스처만 통과시켜 그 사실이 보이지 않았다
  # (평가 v5 · E-20). 커버리지의 구멍은 **경로별 픽스처가 없으면 보이지 않는다**.
  local bfx bcode blabel bwant brest bout
  # 파괴적 명령은 시크릿과 **다른 축**이다 (파일을 하나도 쓰지 않고 되돌릴 수 없게 만든다).
  # 축이 다르면 픽스처도 따로 있어야 한다 — 시크릿 픽스처가 통과해도 이쪽 커버리지는 0일 수 있다.
  #
  # 3번째 필드는 **기대 사유**다. exit 2만 보면 시크릿 픽스처가 파괴적 명령 분기에
  # 걸려도 통과한다 — 축별 커버리지를 증명하려고 픽스처를 나눠 놓고 정작 어느 축이
  # 잡았는지 안 보는 셈이었다. 사유는 `block`의 **1번 인자(제목)**만 쓴다:
  # 2번 인자(패턴 힌트)에는 리터럴 패턴이 들어 있어(security-check.sh의 "패턴: sk-proj-")
  # 여기 적으면 doctor.sh 자신이 그 훅에 막힌다.
  # 목록은 배열이다 — 아래 「차단 사유 ↔ 픽스처」 검사가 이 배열을 다시 읽는다.
  # 평가 v6: 차단 지점 22종 중 픽스처로 증명된 것이 4종뿐이었다(E-29). 우회 1종(E-21)은
  # 픽스처 없는 자리에서 4개월간 살았다 — 사유마다 픽스처가 있어야 그 사유의 차단이 증명이다.
  local POS_FX=(
    "PreToolUse-block.json:Write 시크릿 주입:AWS Access Key ID 하드코딩"
    "PreToolUse-bash-block.json:Bash 힙독 시크릿 주입:AWS Access Key ID 하드코딩"
    "PreToolUse-bash-destructive.json:Bash 파괴적 명령:TRUNCATE — 테이블 전체 비우기"
    "PreToolUse-bash-heredoc-sql.json:DB 클라이언트 힙독:DDL로 테이블/데이터베이스/스키마 삭제"
    "PreToolUse-bash-selfref-destructive.json:자기참조 우회 시도(파괴):DDL로 테이블/데이터베이스/스키마 삭제"
    "PreToolUse-bash-selfref-secret.json:자기참조 우회 시도(시크릿):AWS Access Key ID 하드코딩"
    "PreToolUse-bash-commit-then-drop.json:커밋 메시지 뒤의 실행 세그먼트:DDL로 테이블/데이터베이스/스키마 삭제"
    # 명령 치환 우회 — E-22 오탐 수리가 실행 경로까지 면제한 회귀를 고정한다.
    # 면제(_message_cmd)는 차단 지점과 **같은 강도로** 증명되어야 한다는 규율의 실례다.
    "PreToolUse-bash-commit-cmdsub.json:커밋 메시지 속 명령 치환:DDL로 테이블/데이터베이스/스키마 삭제"
    "PreToolUse-bash-gh-body-cmdsub.json:PR 본문 속 명령 치환:DDL로 테이블/데이터베이스/스키마 삭제"
    "PreToolUse-bash-stderr-null-write.json:stderr 폐기 + 파일 쓰기:AWS Access Key ID 하드코딩"
    "PreToolUse-bash-delete-nowhere.json:WHERE 없는 DELETE:WHERE 없는 DELETE FROM"
    "PreToolUse-bash-supabase-reset.json:supabase 초기화:supabase db reset — 로컬 DB 초기화"
    "PreToolUse-bash-prisma-reset.json:prisma 초기화:prisma 스키마 초기화"
    "PreToolUse-bash-alembic-base.json:마이그레이션 전량 되돌리기:마이그레이션 전량 되돌리기"
    "PreToolUse-bash-filter-branch.json:git 히스토리 재작성:git 히스토리 재작성/미러 푸시"
    "PreToolUse-bash-force-push-main.json:공유 브랜치 강제 푸시:공유 브랜치에 강제 푸시"
    "PreToolUse-bash-force-push-plus.json:+refspec 강제 푸시 (우회 시도):공유 브랜치에 강제 푸시"
    "PreToolUse-bash-push-delete-main.json:공유 브랜치 원격 삭제:공유 브랜치 원격 삭제"
    "PreToolUse-secret-github-pat.json:GitHub PAT:GitHub Personal Access Token 하드코딩"
    "PreToolUse-secret-github-oauth.json:GitHub OAuth 토큰:GitHub 토큰 하드코딩"
    "PreToolUse-secret-stripe.json:Stripe:Stripe Secret Key 하드코딩"
    "PreToolUse-secret-toss.json:토스페이먼츠:토스페이먼츠 Secret Key 하드코딩"
    "PreToolUse-secret-kakao.json:카카오페이:카카오페이 시크릿 하드코딩"
    "PreToolUse-secret-openai.json:OpenAI:OpenAI API Key 하드코딩"
    "PreToolUse-secret-anthropic.json:Anthropic:Anthropic API Key 하드코딩"
    "PreToolUse-secret-google.json:Google:Google API Key 하드코딩"
    "PreToolUse-secret-supabase-new.json:Supabase 신형 키:Supabase Secret Key 하드코딩"
    "PreToolUse-secret-supabase-service-role.json:Supabase service_role JWT:Supabase Service Role Key 하드코딩"
    "PreToolUse-secret-supabase-jwt.json:Supabase JWT(anon 표시 없음):Supabase JWT 키 하드코딩 의심"
    "PreToolUse-secret-pem.json:PEM 개인키:Private Key 하드코딩"
    "PreToolUse-secret-gcp-sa.json:GCP 서비스 계정 JSON:GCP Service Account JSON 하드코딩"
    "PreToolUse-secret-package-json.json:package.json 시크릿:package.json에 시크릿 포함"
  )
  # 픽스처의 `@@FILL<n>@@`를 실행 시점에 n자로 채운다. 스캐너가 잡는 자격증명 형태
  # (Stripe 등 체크섬 없이 패턴만 보는 검출기)를 **파일에 두지 않기 위해서다** — 저장소에
  # 남으면 GitHub push protection이 푸시를 막고, 그것을 허용 처리하면 패턴이 이력에 영구히
  # 남는다. 훅에 먹이는 것은 조립된 완전한 문자열이므로 차단 증명의 강도는 그대로다.
  _fx_fill() {   # $1 픽스처 경로 → stdout
    awk '{
      while (match($0, /@@FILL[0-9]+@@/)) {
        tok = substr($0, RSTART, RLENGTH)
        n = substr(tok, 7, length(tok) - 8) + 0
        s = ""; for (i = 0; i < n; i++) s = s "x"
        $0 = substr($0, 1, RSTART - 1) s substr($0, RSTART + RLENGTH)
      }
      print
    }' "$1"
  }

  for bfx in "${POS_FX[@]}"; do
    brest="${bfx#*:}"; bfx="$fx/${bfx%%:*}"
    blabel="${brest%%:*}"; bwant="${brest#*:}"
    if [ -f "$bfx" ] && [ -f scripts/security-check.sh ]; then
      bcode=0
      bout=$(_fx_fill "$bfx" | CLAUDE_PROJECT_DIR="$ROOT" bash scripts/security-check.sh 2>&1) || bcode=$?
      used="$used$(basename "$bfx")
"
      if [ "$bcode" -ne 2 ]; then
        bad "security-check: $blabel에 exit $bcode" "차단 훅이 잡아야 할 것을 잡지 못함 — 미탐"
      elif printf '%s' "$bout" | grep -qF "$bwant"; then
        ok "security-check: $blabel → exit 2 ('$bwant' — 의도한 사유)"
      else
        bad "security-check: $blabel이 다른 사유로 차단됨" \
            "기대 '$bwant' / 실제 '$(printf '%s' "$bout" | grep -m1 '차단:' | sed 's/^[^:]*: *//')' — 축별 커버리지가 증명되지 않는다"
      fi
    else
      warn "양성 픽스처 없음 ($bfx)" "그 도구 경로의 차단 능력이 증명되지 않은 상태"
    fi
  done

  # 오탐 방어 — 시크릿 **문자열이 들어 있으나 파일을 쓰지 않는** 조사 명령은 통과해야 한다.
  # 오탐은 사용자가 훅을 꺼버리게 만들고, 꺼진 훅의 차단력은 0이다.
  local okfx oklabel
  # 평가 v6에서 재현된 오탐 셋(E-22 커밋 메시지 · E-23 `2>/dev/null` · E-44 파일 힙독 안의
  # `; psql` 문자열)과 자기참조 단일 명령의 통과를 함께 증명한다.
  for okfx in "PreToolUse-bash-ok.json:시크릿 문자열 조사 명령" \
              "PreToolUse-bash-destructive-ok.json:파괴 구문 조사 명령" \
              "PreToolUse-bash-heredoc-authoring-ok.json:인터프리터 힙독 집필 명령" \
              "PreToolUse-bash-selfref-ok.json:doctor 실행 단일 명령" \
              "PreToolUse-bash-commit-msg-ok.json:DDL 어휘가 든 커밋 메시지" \
              "PreToolUse-bash-gh-title-ok.json:DDL 어휘가 든 PR 제목" \
              "PreToolUse-bash-stderr-null-ok.json:stderr 폐기만 있는 조사 명령" \
              "PreToolUse-bash-heredoc-file-dbstring-ok.json:파일 힙독 본문의 DB 클라이언트 문자열"; do
    oklabel="${okfx#*:}"; okfx="$fx/${okfx%%:*}"
    [ -f "$okfx" ] || { warn "오탐 픽스처 없음 ($okfx)" "그 경로의 오탐 방어가 증명되지 않은 상태"; continue; }
    used="$used$(basename "$okfx")
"
    bcode=0
    CLAUDE_PROJECT_DIR="$ROOT" bash scripts/security-check.sh < "$okfx" >/dev/null 2>&1 || bcode=$?
    if [ "$bcode" -eq 0 ]; then
      ok "security-check: $oklabel → exit 0 (오탐 없음)"
    else
      bad "security-check: 무해한 $oklabel에 exit $bcode" "오탐 — 훅이 꺼지는 원인"
    fi
  done

  # ── 강제 푸시 판정 불가 분기 (3상태) ──────────────────────────────
  # 정적 픽스처로는 못 증명한다 — 판정 불가는 **커밋 0개 저장소**라는 git 상태에서만 나온다.
  # 차단(exit 2)이 아니라 통과(exit 0) + 「판정 불가」 명시가 기대값이다. 접으면 오탐이다.
  local ud udcode udout
  ud=$(mktemp -d 2>/dev/null) || ud=""
  if [ -n "$ud" ] && git -C "$ud" init -q 2>/dev/null; then
    udcode=0
    udout=$(jq -nc '{tool_name:"Bash",tool_input:{command:"git push -f"}}' \
      | ( cd "$ud" && CLAUDE_PROJECT_DIR="$ud" bash "$ROOT/scripts/security-check.sh" 2>&1 >/dev/null )) || udcode=$?
    if [ "$udcode" -eq 0 ] && printf '%s' "$udout" | grep -q '판정 불가'; then
      ok "security-check: 강제 푸시 대상 판정 불가 → exit 0 + 명시 보고 (3상태)"
    else
      bad "security-check: 판정 불가 분기가 exit $udcode / 보고 $(printf '%s' "$udout" | grep -c '판정 불가')건" \
          "판정 불가를 차단으로 접었거나 침묵 통과했다"
    fi
  else
    warn "임시 git 저장소 생성 실패" "판정 불가 분기가 증명되지 않은 상태"
  fi
  rm -rf "${ud:-/nonexistent}"

  # ── 차단 사유 ↔ 픽스처 ────────────────────────────────────────────
  # 「고아 픽스처」는 픽스처→검사 방향만 본다. 반대 방향 — 훅의 **각 차단 사유**에 그것을
  # 증명하는 픽스처가 있는가 — 가 없어서 차단 지점 22종 중 4종만 증명된 채 4개월을 지났다.
  # 사유 제목(dblock/block의 1번 인자)을 훅에서 뽑아 위 POS_FX의 기대 사유와 대조한다.
  local reason rmiss="" rchk=0
  while IFS= read -r reason; do
    [ -z "$reason" ] && continue
    rchk=$((rchk+1))
    printf '%s\n' "${POS_FX[@]}" | grep -qF -- ":$reason" || rmiss="$rmiss
      · $reason"
  done < <(grep -oE '(dblock|block) "[^"]+"' scripts/security-check.sh 2>/dev/null \
           | sed -E 's/^(dblock|block) "//; s/"$//; s/ \(\$[a-z_]+\)$//' | sort -u)
  if [ -n "$rmiss" ]; then
    warn "차단 사유 ${rchk}종 중 픽스처 없는 사유:$rmiss" "그 사유의 차단은 증명되지 않았다 — 살아있음 ≠ 작동함"
  else
    ok "차단 사유 ${rchk}종 전부 픽스처로 증명됨"
  fi

  # ── .env 면제 (v3.26.0) ────────────────────────────────────────────
  # 시크릿의 **정당한 목적지**는 gitignore된 .env 파일인데 훅이 거기 쓰는 것까지
  # 막고 있었다 — 차단 메시지가 ".env.local로 옮기라"면서 그 파일을 막는 모순이었다.
  #
  # 이 면제는 **git 상태에 의존**하므로 정적 JSON 픽스처로는 증명할 수 없다.
  # 임시 저장소를 만들어 무시 여부를 통제한다. 증명해야 할 것은 셋이다:
  #   ① 무시되는 .env는 통과   ② 무시 안 되는 .env는 여전히 차단
  #   ③ 일반 소스는 회귀 없음  ④ 판정 불가(저장소 밖)면 면제하지 않는다
  local sc et ng
  sc="$(pwd)/scripts/security-check.sh"
  et=$(mktemp -d 2>/dev/null) || et=""
  ng=$(mktemp -d 2>/dev/null) || ng=""
  if [ -z "$et" ] || [ -z "$ng" ]; then
    warn "임시 디렉토리 생성 실패" ".env 면제가 증명되지 않은 상태"
  elif ! git -C "$et" init -q 2>/dev/null; then
    warn "git init 실패" ".env 면제가 증명되지 않은 상태 (git 부재?)"
  else
    printf '.env.local\n' > "$et/.gitignore"
    mkdir -p "$et/src"
    # 키는 **조각으로 조립**한다 — 이 스크립트 본문에 매치되는 리터럴을 두면
    # doctor.sh 자신을 편집할 때 훅이 자기 검사 스크립트를 차단한다.
    local kpre='sk-proj-' kbody='SELFTESTKEYAAAABBBBCCCCDDDD'
    local ekey="$kpre$kbody"
    local ecase epath ewant elabel erest ecode ewhere
    for ecase in "$et:.env.local:0:gitignore된 .env — 면제 작동" \
                 "$et:.env.production:2:gitignore 안 된 .env — 차단 유지" \
                 "$et:src/config.ts:2:일반 소스 — 회귀 없음" \
                 "$ng:.env.local:2:저장소 밖 — 판정 불가라 면제 없음"; do
      ewhere="${ecase%%:*}"; erest="${ecase#*:}"
      epath="${erest%%:*}"; erest="${erest#*:}"
      ewant="${erest%%:*}"; elabel="${erest#*:}"
      ecode=0
      jq -nc --arg p "$epath" --arg k "$ekey" \
        '{session_id:"epcc-doctor-test",cwd:".",tool_name:"Write",hook_event_name:"PreToolUse",tool_input:{file_path:$p,content:("OPENAI_API_KEY=" + $k + "\n")}}' \
        | ( cd "$ewhere" && CLAUDE_PROJECT_DIR="$ewhere" bash "$sc" >/dev/null 2>&1 ) || ecode=$?
      if [ "$ecode" -eq "$ewant" ]; then
        ok ".env 면제: $elabel → exit $ecode"
      else
        bad ".env 면제: $elabel → exit $ecode (기대 $ewant)" \
            "$( [ "$ewant" = 0 ] && printf '정당한 목적지에 쓰지 못한다 — 실사용이 막힌다' \
                                 || printf '면제가 과도하게 열렸다 — 시크릿이 커밋될 수 있다' )"
      fi
    done
  fi
  rm -rf "${et:-/nonexistent}" "${ng:-/nonexistent}"

  # ── 정적 검사 양성 픽스처 (RC4) ──────────────────────────────────
  # 정적 검사(상시 카드·치환자 표기·Phase 이원화·카드 표 수·그래프 미선언)는
  # 손으로 결함을 심어 증명했었다. 그 증명은 재현되지 않고, 실제로 한 번은
  # **픽스처가 심어지지도 않은 채 "통과"로 보였다** (없는 파일명을 노렸다).
  #
  # 그래서 두 단계로 나눈다:
  #   1) 픽스처 유효성 — 심으려던 문자열이 그 파일에 **실제로 있는가**
  #   2) 검출 — 그 상태에서 검사가 해당 메시지를 내는가 (+ 심기 전엔 안 내는가)
  # 1이 실패하면 2의 결과는 아무 의미가 없다.
  sec "정적 검사 양성 픽스처"

  sfx=$(mktemp -d 2>/dev/null) || { warn "임시 디렉토리 생성 실패" "정적 픽스처 생략"; sfx=""; }
  if [ -n "$sfx" ]; then
    # 정리는 함수 상단의 RETURN 트랩이 $stdir와 함께 담당한다
    _fx_static_tree "$sfx/base" || bad "정적 픽스처 트리 생성 실패"

    if [ -d "$sfx/base" ]; then
      # 기준선: 아래 메시지들이 **나오지 않아야** 한다 (오탐 방지)
      local base_out; base_out=$(bash "$0" --fast --root "$sfx/base" 2>&1; bash "$0" --graph --root "$sfx/base" 2>&1)
      local msg
      for msg in "상시 로드 규칙 카드 없음" "치환되지 않는 스크립트 경로 표기" \
                 "Phase 표 재출현" "카드 표 .* ≠" "그래프 미선언 스킬" \
                 "미선언" "읽는 노드 없는 저장소" "미배포" \
                 "프리셋 이름 누락" "사전 제작 이음매 누락" "계약에 없는 프론트매터 키" \
                 "소비자 경로에 플러그인 스킬" "죽은 스킬 참조" "저장소 이름 누출" \
                 "manual인데 disable-model-invocation 없음" "phase가 라우팅 카드에 없음" "같은 path를 가진 노드" \
                 "설정 필드 선언만 있고" "T0 예산 주장" "코드블록의 플러그인 상대 경로" "스킬 이름 누락" \
                 "규칙 카드의 플러그인 맥락 경로" "로드 조건 표가 선언에 없는 글롭" \
                 "수동 전용 수 주장" "그래프 manual 없음"; do
        printf '%s' "$base_out" | grep -q "$msg" \
          && bad "기준선 오탐: '$msg'" "결함이 없는데 검출됐다 — 검사가 못 쓰게 된다"
      done
      ok "기준선 픽스처 오탐 없음"

      _fx_static_case "$sfx" always-rule   'rules/workflow-routing.md' '^paths:' \
        "상시 로드 규칙 카드 없음" 'printf -- "---\npaths:\n  - \"src/**\"\n---\n" | cat - "$T/rules/workflow-routing.md" > "$T/r.tmp" && mv "$T/r.tmp" "$T/rules/workflow-routing.md"'

      # 카드가 링크한 참조가 사라졌을 때 — 점진 로드 도달 경로
      _fx_static_case "$sfx" ref-dangling 'rules/code-change.md' 'references/data-modeling/gone' \
        '점진 로드가 끊긴다' \
        "printf -- '패턴 상세는 [gone.md](../references/data-modeling/gone.md).\n' >> \"\$T/rules/code-change.md\""

      # 문서의 로드 조건 표가 카드의 paths:보다 넓게 주장할 때 (\140 = 백틱)
      _fx_static_case "$sfx" paths-table-drift 'docs/harness-anatomy.md' 'lib/\*\*' \
        '로드 조건 표가 선언에 없는 글롭을 주장' \
        'printf "| \140code-change.md\140 | \140lib/**\140 |\n" >> "$T/docs/harness-anatomy.md"'

      # 카드가 플러그인 저장소 맥락의 경로를 인용했을 때 — 배포되면 없는 파일이 된다
      _fx_static_case "$sfx" card-plugin-path 'rules/code-change.md' 'templates/CLAUDE.md.hbs' \
        '규칙 카드의 플러그인 맥락 경로' \
        "printf -- '템플릿은 \`templates/CLAUDE.md.hbs\`를 본다.\n' >> \"\$T/rules/code-change.md\""

      # 쪼개면서 옮겨간 절의 번호가 카드에 잔재로 남았을 때
      _fx_static_case "$sfx" section-stale 'rules/code-change.md' '§7' \
        '그 절이 없다' \
        "printf -- '## 1. 절\n\n상세는 §7 참조.\n' >> \"\$T/rules/code-change.md\""

      # 수동 전용 선언 ↔ 상주 플래그 (양방향)
      _fx_static_case "$sfx" manual-unflagged 'skills/sample/SKILL.md' '수동 호출 전용' \
        '수동 전용인데 description이 상주' \
        "perl -pi -e 's/^description: x\$/description: x 수동 호출 전용./' \"\$T/skills/sample/SKILL.md\""

      _fx_static_case "$sfx" flagged-routed 'skills/sample/SKILL.md' 'disable-model-invocation' \
        '자동 발동 대상에 모델 호출 차단' \
        "perl -pi -e 's/^description: x\$/description: x\\ndisable-model-invocation: true/' \"\$T/skills/sample/SKILL.md\"; printf -- '| P0 | 조건 | \`/sample\` |\n' >> \"\$T/rules/workflow-routing.md\""

      # 계약에 없는 키는 조용히 무시된다 — epcc-init이 'trigger: manual'로 넉 달간 상주했다
      _fx_static_case "$sfx" legacy-trigger 'skills/sample/SKILL.md' '^trigger:' \
        '플랫폼 계약에 없는 프론트매터 키' \
        "perl -pi -e 's/^description: x\$/description: x\\ntrigger: manual/' \"\$T/skills/sample/SKILL.md\""

      # 접힌 description의 **이어지는 행**에 적힌 선언. 첫 행만 보던 옛 검사는 이걸 놓쳤다.
      _fx_static_case "$sfx" manual-folded 'skills/sample/SKILL.md' '수동 호출 전용' \
        '수동 전용인데 description이 상주' \
        "perl -pi -e 's/^description: x\$/description: >-\\n  x\\n  수동 호출 전용./' \"\$T/skills/sample/SKILL.md\""

      _fx_static_case "$sfx" skill-dir     'skills/sample/SKILL.md' '<skill-dir>' \
        "치환되지 않는 스크립트 경로 표기" 'printf "bash <skill-dir>/scripts/x.sh\n" >> "$T/skills/sample/SKILL.md"'

      # 제목만 있고 본문이 없는 절. 강화할 때 사람이 볼 때만 잡히던 결함이라
      # 저장소에 16건이 남아 있었다 — 기계가 보기 시작한 뒤로는 남을 수 없다.
      _fx_static_case "$sfx" empty-heading 'skills/sample/SKILL.md' '^## 빈절' \
        '빈 절 제목' \
        'printf "\n## 빈절\n\n## 다음절\n\n본문\n" >> "$T/skills/sample/SKILL.md"'

      # SKILL.md에서도 저장소에서도 닿지 않는 번들 파일. 「스킬 내부 참조」의 역방향이다.
      _fx_static_case "$sfx" orphan-res 'skills/sample/references/dead.md' '고아' \
        '고아 리소스' \
        'mkdir -p "$T/skills/sample/references" && printf "# 고아\n" > "$T/skills/sample/references/dead.md"'

      _fx_static_case "$sfx" phase-dup     'templates/CLAUDE.md.hbs' '^| P0' \
        "Phase 표 재출현" 'printf "\n| Phase | 조건 |\n| --- | --- |\n| P0 | x |\n" >> "$T/templates/CLAUDE.md.hbs"'

      _fx_static_case "$sfx" graph-missing 'skills/orphan-skill/SKILL.md' 'orphan-skill' \
        "그래프 미선언 스킬" 'mkdir -p "$T/skills/orphan-skill" && printf -- "---\nname: orphan-skill\ndescription: x\n---\n" > "$T/skills/orphan-skill/SKILL.md"' --graph

      # 훅을 등록하고 그래프에 선언하지 않은 상태 (G5 대칭). 스킬 쪽만 검사하던 동안
      # 훅은 사각이었고, 요구는 rules/harness-change.md에 사람이 읽는 규범으로만 있었다.
      _fx_static_case "$sfx" hook-undeclared 'hooks/hooks.json' 'y\.sh' \
        "그래프 미선언 훅" 'jq ".hooks.Stop = [{\"hooks\":[{\"type\":\"command\",\"command\":\"bash scripts/y.sh\"}]}]" "$T/hooks/hooks.json" > "$T/h.tmp" && mv "$T/h.tmp" "$T/hooks/hooks.json" && printf -- "#!/bin/bash\nexit 0\n" > "$T/scripts/y.sh"' --graph

      # 라우팅 카드가 호출을 선언했는데 그래프 노드에 phase가 없는 상태 (G6).
      # \140 은 백틱 — eval에서 명령 치환으로 해석되지 않게 8진 이스케이프를 쓴다.
      _fx_static_case "$sfx" phase-unmapped 'rules/workflow-routing.md' '^\| P1' \
        'phase "P1" 미선언' 'printf -- "| P1 | x | \\140/sample\\140 |\n" >> "$T/rules/workflow-routing.md"' --graph

      # 쓰기만 있고 읽는 노드가 없는 저장소 (G7) — "문서가 있다"가 아니라 "소비된다".
      _fx_static_case "$sfx" store-orphan 'workflow.graph.json' '"store"' \
        "읽는 노드 없는 저장소" 'jq ".nodes += [{\"id\":\"memo\",\"kind\":\"store\",\"path\":\"rules/code-change.md\"}] | .edges += [{\"from\":\"sample\",\"to\":\"memo\"}]" "$T/workflow.graph.json" > "$T/g.tmp" && mv "$T/g.tmp" "$T/workflow.graph.json"' --graph

      # 그래프가 manual이라 하는데 frontmatter에 dmi가 없는 상태 (G8) — ui-ux-design이 실제로 그랬다.
      # 표식은 한 줄에 있어야 grep이 본다 — jq -c로 한 줄 JSON을 만든다 (pretty-print는 키마다 줄이 갈린다)
      _fx_static_case "$sfx" manual-no-dmi 'workflow.graph.json' '"id":"sample","kind":"skill","path":"skills/sample/SKILL.md","manual":true' \
        "manual인데 disable-model-invocation 없음" 'jq -c "(.nodes[] | select(.id==\"sample\")) += {\"manual\": true}" "$T/workflow.graph.json" > "$T/g.tmp" && mv "$T/g.tmp" "$T/workflow.graph.json"' --graph

      # frontmatter는 dmi인데 그래프 노드에 manual이 없는 상태 (G8' — G8의 역방향).
      # sample은 라우팅·phase·호출 어디에도 없으므로 「자동 발동 대상에 모델 호출 차단」과 부딪히지 않는다.
      _fx_static_case "$sfx" dmi-not-manual 'skills/sample/SKILL.md' '^disable-model-invocation' \
        "그래프 manual 없음" 'printf -- "---\nname: sample\ndescription: x\ndisable-model-invocation: true\n---\nbash \${CLAUDE_SKILL_DIR}/scripts/x.sh\n" > "$T/skills/sample/SKILL.md"' --graph

      # 그래프에 phase를 달았는데 라우팅 카드에 그 행이 없는 상태 (G9 — G6의 역방향).
      _fx_static_case "$sfx" phase-not-in-card 'workflow.graph.json' '"P9"' \
        "phase가 라우팅 카드에 없음" 'jq "(.nodes[] | select(.id==\"sample\")) += {\"phase\": [\"P9\"]}" "$T/workflow.graph.json" > "$T/g.tmp" && mv "$T/g.tmp" "$T/workflow.graph.json"' --graph

      # 두 노드가 한 파일을 가리키는데 note가 없는 상태 (G10).
      _fx_static_case "$sfx" dup-path 'workflow.graph.json' '"sample2"' \
        "같은 path를 가진 노드" 'jq ".nodes += [{\"id\":\"sample2\",\"kind\":\"skill\",\"path\":\"skills/sample/SKILL.md\",\"manual\":true}]" "$T/workflow.graph.json" > "$T/g.tmp" && mv "$T/g.tmp" "$T/workflow.graph.json"' --graph

      # 문서가 절로 약속한 설정 필드를 아무 코드도 읽지 않는 상태 (E-30).
      _fx_static_case "$sfx" config-ghost-field 'docs/configuration.md' '^### ghostField' \
        "설정 필드 선언만 있고 읽는 코드 없음" 'printf -- "# 설정\n\n### ghostField\n\n아무도 안 읽는다.\n" > "$T/docs/configuration.md"'

      # 카드 본문이 인용한 T0 예산 수치가 검사 상수와 다른 상태 (E-25).
      _fx_static_case "$sfx" t0-budget-drift 'rules/code-change.md' '예산 40줄' \
        "T0 예산 주장 40 ≠ 실물" 'printf -- "\nT0 운영 규칙이 예산 40줄을 넘으면 doctor가 막는다.\n" >> "$T/rules/code-change.md"; cp "$T/rules/code-change.md" "$T/rules/harness-change.md"'

      # 코드블록 안에 치환되지 않는 플러그인 상대 경로 (E-34).
      _fx_static_case "$sfx" bare-path-in-fence 'skills/sample/SKILL.md' 'grep -c x rules/workflow-routing.md' \
        "코드블록의 플러그인 상대 경로" 'printf -- "\n\`\`\`bash\ngrep -c x rules/workflow-routing.md\n\`\`\`\n" >> "$T/skills/sample/SKILL.md"'

      # 버전은 올렸는데 릴리스 태그가 없는 상태 (E-08·E-12). git 저장소일 때만 판정하므로
      # 픽스처도 git init을 해야 한다 — 하지 않으면 '검출됨'이 아니라 '검사가 안 돎'이다.
      # 프리셋을 늘리고 소비자 문서에 안 적은 상태 — vue 축이 실제로 그랬다.
      _fx_static_case "$sfx" preset-unlisted 'presets/backend/gamma.json' 'gamma' \
        "프리셋 이름 누락" 'printf -- "{\"axis\":\"backend\",\"name\":\"gamma\"}\n" > "$T/presets/backend/gamma.json"'

      # 이음매를 출하하고 문서에 안 적은 상태 — vue+node-api가 실제로 그랬다.
      _fx_static_case "$sfx" seam-unlisted 'guides/seams/alpha+gamma/contract.md' 'alpha' \
        "사전 제작 이음매 누락" 'mkdir -p "$T/guides/seams/alpha+gamma" && printf -- "# alpha x gamma\n" > "$T/guides/seams/alpha+gamma/contract.md"'

      # 문서가 실물과 다른 수를 주장하는 상태. 대조 대상을 README에서 둘 더 늘렸으므로
      # **늘린 경로 각각이** 실제로 잡는지 본다 — 한쪽 grep이 틀리면 주장이 빈 문자열이 되어
      # 조용히 건너뛰고, 그것은 통과와 구분되지 않는다.
      _fx_static_case "$sfx" anatomy-drift 'docs/harness-anatomy.md' '스킬 9' \
        "스킬 수 주장 9 ≠ 실물 3" 'sed "s/스킬 3/스킬 9/" "$T/docs/harness-anatomy.md" > "$T/a.tmp" && mv "$T/a.tmp" "$T/docs/harness-anatomy.md"'

      # 해부 문서의 「수동 전용 N개」 — 픽스처 트리의 dmi 실물은 epcc-init 1개다 (E-49).
      _fx_static_case "$sfx" manual-count-drift 'docs/harness-anatomy.md' '\*\*9개\*\*' \
        "수동 전용 수 주장 9 ≠ 실물 1" 'printf -- "\n| **수동 호출 전용** (\`disable-model-invocation\`) | \`epcc-init\` — **9개** | x |\n" >> "$T/docs/harness-anatomy.md"'

      # 그림 설명서의 스킬 필 목록이 실물과 어긋난 상태 — 픽스처 트리 실물은 3개인데 2개만 적는다 (E-57).
      _fx_static_case "$sfx" manual-skill-set-drift 'docs/manual/user.html' 'p-skill' \
        "매뉴얼 스킬 목록 ≠ 실물" 'mkdir -p "$T/docs/manual" && printf -- "<span class=\"pill p-skill\">/sample</span> <span class=\"pill p-skill\">/epcc-init</span>\n" > "$T/docs/manual/user.html"'

      # 그림 설명서의 차단 사유 수 — 합성 훅에 사유 2개를 두고 매뉴얼이 9라 주장하게 한다 (E-61).
      _fx_static_case "$sfx" manual-block-count-drift 'docs/manual/user.html' '9종을 검사해' \
        "차단 사유 수 주장 9 ≠ 실물 2" 'mkdir -p "$T/docs/manual" && printf "dblock \"A\"\ndblock \"B\"\n" > "$T/scripts/security-check.sh" && printf -- "<td>9종을 검사해 걸리면 exit 2</td>\n" > "$T/docs/manual/user.html"'

      _fx_static_case "$sfx" marketplace-drift '.claude-plugin/marketplace.json' '훅 9종' \
        "훅 수 주장 9 ≠ 실물 1" 'sed "s/훅 1종/훅 9종/" "$T/.claude-plugin/marketplace.json" > "$T/m.tmp" && mv "$T/m.tmp" "$T/.claude-plugin/marketplace.json"'

      _fx_static_case "$sfx" release-untagged 'package.json' '"version"' \
        "미배포" 'mkdir -p "$T/.claude-plugin" && printf "{\"version\":\"9.9.9\"}\n" > "$T/package.json" && printf "{\"name\":\"fx-plugin\",\"version\":\"9.9.9\"}\n" > "$T/.claude-plugin/plugin.json" && (cd "$T" && git init -q .)'

      # 포트 잔재 — 개명·이사가 남기는 부류. 「선언↔실물」은 수치만 보므로 원리적으로 못 잡는다.
      # sample은 픽스처 트리에 실재하는 스킬이라 「플러그인 스킬을 소비자 경로에 적었다」가 된다.
      _fx_static_case "$sfx" consumer-skill-path 'skills/sample/SKILL.md' '\.claude/skills/sample' \
        "소비자 경로에 플러그인 스킬" 'printf -- "- 참조: .claude/skills/sample/SKILL.md\n" >> "$T/skills/sample/SKILL.md"'
      # 없는 이름은 죽은 참조로 갈린다 — 한 검사의 두 갈래를 각각 증명한다.
      _fx_static_case "$sfx" dead-skill-ref 'skills/sample/SKILL.md' '\.claude/skills/gone-skill' \
        "죽은 스킬 참조" 'printf -- "- 참조: .claude/skills/gone-skill/SKILL.md\n" >> "$T/skills/sample/SKILL.md"'
      # 자기 이름 누출 — 이름 집합은 매니페스트에서 도출되므로 픽스처의 plugin.json 이름을 쓴다.
      _fx_static_case "$sfx" self-name-leak 'skills/sample/SKILL.md' 'EasyPeasyClaudeCodeDevkit' \
        "저장소 이름 누출" 'printf -- "예시 프로젝트: EasyPeasyClaudeCodeDevkit\n" >> "$T/skills/sample/SKILL.md"'
    fi
  fi

  # ── 고아 픽스처 ────────────────────────────────────────────────────
  # 위에서 **실제로 먹인** 것과 디렉토리를 대조한다. 어떤 픽스처가 쓰이는지 재유도하지
  # 않으므로(${event}.json 보간 + 리터럴 참조를 다시 구현하지 않으므로) 선택 로직이 바뀌어도
  # 영원히 일치한다. templates/에는 이 검사가 있었는데(고아 자산) 정작 **자기검증 도구인
  # 픽스처**에는 없어서 죽은 픽스처가 조용히 살았다 — 원칙이 자기 자신에게만 면제됐다.
  sec "픽스처 소비"
  local ofx ob orphf=0 ocnt=0
  while IFS= read -r ofx; do
    [ -f "$ofx" ] || continue
    ocnt=$((ocnt+1)); ob=$(basename "$ofx")
    printf '%s' "$used" | grep -qxF "$ob" && continue
    bad "고아 픽스처: $ofx" "아무 검사도 이 픽스처를 먹이지 않는다 — 죽은 자산이거나 배선 누락이다"
    orphf=$((orphf+1))
  done < <(find "$fx" -maxdepth 1 -name '*.json' 2>/dev/null | sort)
  [ "$orphf" -eq 0 ] && [ "$ocnt" -gt 0 ] && ok "픽스처 ${ocnt}건 모두 소비됨"

  # ── 하트비트 회전 불변식 ──────────────────────────────────────────
  # **회전은 어떤 컴포넌트의 마지막 증거도 지우지 않는다.**
  # 이것이 깨지면 생존 지표가 살아있는 훅을 "실행된 적 없음"으로 보고한다 — 실측으로
  # 그랬다: security-check가 Edit/Write/Bash 전부에 걸려 로그의 97%를 차지하고
  # track-skill의 이력을 창 밖으로 밀어냈다. 구현이 tail -1000으로 되돌아가도 잡을
  # 검사가 없던 자리다. 코드 모양이 아니라 **행동**을 본다.
  sec "하트비트 회전 불변식"
  local rt rn
  rt=$(mktemp -d 2>/dev/null) || rt=""
  if [ -z "$rt" ]; then
    warn "임시 디렉토리 생성 실패" "회전 불변식이 증명되지 않은 상태"
  else
    { printf 'ghost-hook|2026-01-01T00:00:00Z|x|0\n'
      awk 'BEGIN{ for (i = 0; i < 2100; i++) print "noisy-hook|2026-01-02T00:00:00Z|x|0" }'
    } > "$rt/hookrun.log"
    EPCC_STATE_DIR="$rt" EPCC_ROOT="$rt" EPCC_HOOK_NAME="noisy-hook" \
      bash -c '. "$1/scripts/lib/common.sh"; epcc_heartbeat 0' _ "$ROOT" >/dev/null 2>&1
    rn=$(num "$(wc -l < "$rt/hookrun.log" 2>/dev/null | tr -d ' ')")
    if awk -F'|' '{print $1}' "$rt/hookrun.log" 2>/dev/null | grep -qx 'ghost-hook'; then
      ok "밀려난 훅의 마지막 증거가 회전 후에도 남는다 (${rn}행)"
    else
      bad "회전이 밀려난 훅의 증거를 지웠다 (${rn}행)" \
          "생존 지표가 살아있는 훅을 '실행된 적 없음'으로 보고하게 된다"
    fi
    if [ "$rn" -gt 0 ] && [ "$rn" -le 1100 ]; then
      ok "회전 후 크기 유계 (${rn}행 ≤ 1100)"
    else
      bad "회전 후 크기 ${rn}행" "0이면 로그가 통째로 날아간 것이고, 상한을 넘으면 무한 증식한다"
    fi
    # graph.log — 세 로그 중 이것만 회전이 없었다 (평가 v6 · E-28). 같은 방식으로 행동을 본다.
    awk 'BEGIN{ for (i = 0; i < 5100; i++) print "2026-01-01T00:00:00Z|build|security-check" }' > "$rt/graph.log"
    EPCC_STATE_DIR="$rt" EPCC_ROOT="$rt" \
      bash -c '. "$1/scripts/lib/common.sh"; epcc_edge build handoff' _ "$ROOT" >/dev/null 2>&1
    rn=$(num "$(wc -l < "$rt/graph.log" 2>/dev/null | tr -d ' ')")
    if [ "$rn" -gt 0 ] && [ "$rn" -le 2600 ] && tail -1 "$rt/graph.log" | grep -q '|build|handoff$'; then
      ok "graph.log 회전 후 크기 유계 (${rn}행 ≤ 2600) · 마지막 엣지 보존"
    else
      bad "graph.log 회전 실패 (${rn}행)" "무한 축적이거나 방금 쓴 엣지가 사라졌다"
    fi
    rm -rf "$rt"
  fi

  # 루트 해석 확인
  sec "루트 해석"
  local resolved
  resolved=$(cd "$(dirname scripts/doctor.sh)/.." 2>/dev/null && pwd)
  [ "$resolved" = "$ROOT" ] && ok "해석된 루트 = $ROOT" || bad "루트 불일치: $resolved ≠ $ROOT"
}

# ════════════════════════════════════════════════════════════════════
# --graph : 그래프 검증
# ════════════════════════════════════════════════════════════════════
run_graph() {
  printf "\n${C_D}epcc doctor --graph${C_0}\n"
  sec "워크플로우 그래프"

  local g="workflow.graph.json"
  [ -f "$g" ] || { bad "$g 없음" "그래프가 산문으로만 선언되어 검증 불가 (G1)"; return; }
  command -v jq >/dev/null 2>&1 || { warn "jq 없음 — 그래프 검증 생략"; return; }

  jq -e . "$g" >/dev/null 2>&1 || { bad "$g JSON 파싱 실패"; return; }

  # 노드 실재 확인
  local missing=0 ntot=0
  while IFS=$'\t' read -r id kind path; do
    [ -z "$id" ] && continue
    ntot=$((ntot+1))
    [ -z "$path" ] || [ "$path" = "null" ] && continue
    if [ ! -e "$path" ]; then
      bad "노드 '$id' ($kind)의 경로 없음: $path"; missing=$((missing+1))
    fi
  done < <(jq -r '.nodes[]? | "\(.id)\t\(.kind)\t\(.path // "")"' "$g" 2>/dev/null)
  [ "$missing" -eq 0 ] && ok "노드 ${ntot}개 모두 실재"

  # 엣지 타깃 실재
  local ids dang=0 etot=0
  ids=$(jq -r '.nodes[]?.id' "$g" 2>/dev/null)
  while IFS=$'\t' read -r from to; do
    [ -z "$from" ] && continue
    etot=$((etot+1))
    printf '%s\n' "$ids" | grep -qx "$from" || { bad "엣지 소스 미정의: $from"; dang=$((dang+1)); }
    printf '%s\n' "$ids" | grep -qx "$to"   || { bad "엣지 타깃 미정의: $to";  dang=$((dang+1)); }
  done < <(jq -r '.edges[]? | "\(.from)\t\(.to)"' "$g" 2>/dev/null)
  [ "$dang" -eq 0 ] && ok "엣지 ${etot}개 모두 유효한 노드 참조"

  # 인바운드 없는 노드 (도달 불가 자산) — entry 표시 노드는 제외
  local unreach=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    jq -e --arg n "$id" '.nodes[] | select(.id==$n) | (.entry == true) or (.manual == true)' "$g" >/dev/null 2>&1 && continue
    jq -e --arg n "$id" '[.edges[]? | select(.to==$n)] | length > 0' "$g" >/dev/null 2>&1 \
      || { bad "인바운드 엣지 없는 노드: $id" "도달 불가 자산 (§1.3과 같은 병). 수동 전용이 의도면 노드에 \"manual\": true"; unreach=$((unreach+1)); }
  done < <(printf '%s\n' "$ids")
  [ "$unreach" -eq 0 ] && ok "도달 불가 노드 없음"

  # 미선언 스킬 (G5) — 기존 검사는 *선언된* 노드만 봐서, 노드로 선언조차 되지 않은
  # 자산은 사각지대였다. v3에서 기획 스킬 8개가 호출자 없이 떠 있던 것을 아무도 못 잡은
  # 이유가 이것이다. 자산 목록(skills/)과 선언(graph)을 대조한다.
  local undecl=0 ulist="" sname
  for sname in skills/*/; do
    [ -d "$sname" ] || continue
    sname=$(basename "$sname")
    [ -f "skills/$sname/SKILL.md" ] || continue
    printf '%s\n' "$ids" | grep -qx "$sname" && continue
    undecl=$((undecl+1)); ulist="$ulist $sname"
  done
  if [ "$undecl" -gt 0 ]; then
    bad "그래프 미선언 스킬 ${undecl}개" "선언이 없으면 호출 근거도 없다 —$ulist"
  else
    ok "스킬 전부 그래프에 선언됨"
  fi

  # 미선언 훅 (G5 대칭) — 위 검사는 skills/만 돈다. 훅에는 대응물이 없어서 여섯 번째 훅을
  # 등록하고 그래프 노드를 안 넣어도 아무도 모른다. 요구사항은 rules/harness-change.md에
  # **사람이 읽는 규범으로만** 있었고, 지금 성립하는 것은 규율이지 기계가 아니다.
  # id가 아니라 **path로 대조한다** — session-brief.sh의 노드 id는 'session-start'라
  # basename 비교는 즉시 오탐이 난다.
  local hundecl=0 hlist="" hpath
  while IFS= read -r hpath; do
    [ -z "$hpath" ] && continue
    jq -e --arg p "$hpath" '[.nodes[]? | select(.kind=="hook" and .path==$p)] | length > 0' \
      "$g" >/dev/null 2>&1 && continue
    hundecl=$((hundecl+1)); hlist="$hlist $hpath"
  done < <(jq -r '.hooks | to_entries[] | .value[]?.hooks[]?.command' hooks/hooks.json 2>/dev/null \
           | grep -oE 'scripts/[a-z0-9./-]+\.sh' | sort -u)
  if [ "$hundecl" -gt 0 ]; then
    bad "그래프 미선언 훅 ${hundecl}개" "hooks.json에 등록됐는데 그래프에 노드가 없다 — 계측 사각 —$hlist"
  else
    ok "훅 전부 그래프에 선언됨"
  fi

  # 에러 엣지 선언 여부 (G4)
  local noerr=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    jq -e --arg n "$id" '.nodes[] | select(.id==$n) | (.on_error // empty) | length > 0' "$g" >/dev/null 2>&1 \
      || noerr=$((noerr+1))
  done < <(jq -r '.nodes[]? | select(.kind=="agent" or .kind=="stage") | .id' "$g" 2>/dev/null)
  [ "$noerr" -gt 0 ] && warn "에러 엣지 미선언 노드 ${noerr}개" "실패 경로가 그래프에 없으면 실패는 조용히 사라진다 (G4)" \
                     || ok "모든 실행 노드가 에러 엣지 선언"

  # 라우팅 카드 Phase ↔ 그래프 phase 대조 (G6)
  # 라우팅 카드는 P0-A~P6 어휘로, 그래프는 stage/skill id로 같은 워크플로우를 주장해 왔다.
  # 두 어휘가 이어져 있지 않으면 "Phase가 실제로 호출되는가"를 기계가 답할 수 없다.
  local rc="rules/workflow-routing.md" pmiss=0 ptot=0
  if [ -f "$rc" ]; then
    while IFS=$'\t' read -r ph target; do
      [ -z "$ph" ] && continue
      ptot=$((ptot+1))
      if ! printf '%s\n' "$ids" | grep -qx "$target"; then
        bad "라우팅 카드 $ph의 호출 대상이 그래프에 없음: $target" "선언 없는 호출은 검사도 계측도 불가"
        pmiss=$((pmiss+1)); continue
      fi
      jq -e --arg n "$target" --arg p "$ph" \
        '.nodes[] | select(.id==$n) | (.phase // []) | index($p)' "$g" >/dev/null 2>&1 \
        || { bad "$target 노드에 phase \"$ph\" 미선언" "라우팅 카드와 그래프가 다른 어휘로 같은 것을 주장한다"; pmiss=$((pmiss+1)); }
    done < <(awk -F'|' '/^\| P[0-9]/ {
                ph=$2; gsub(/^[ \t]+|[ \t]+$/,"",ph);
                n=split($4, part, "`");
                for (i=2; i<=n; i+=2) { t=part[i]; sub(/^\//,"",t);
                  if (t ~ /^[a-z][a-z0-9-]+$/) printf "%s\t%s\n", ph, t }
              }' "$rc")
    [ "$pmiss" -eq 0 ] && ok "라우팅 카드 Phase 호출 ${ptot}건 전부 그래프 phase와 일치"
  else
    warn "$rc 없음 — Phase 대조 생략"
  fi

  # 저장소 소비 경로 (G7)
  # store는 쓰기(인바운드)와 읽기(아웃바운드)를 모두 가져야 한다. 읽는 노드가 없는
  # 저장소는 비용만 있고 드리프트의 원천이다 — "문서가 있다"가 아니라 "문서가 소비된다".
  # 경고가 꺼지는 조건이 둘 다 손에 있다: 소비 엣지를 잇거나 저장소를 폐지하거나.
  local orphan=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    jq -e --arg n "$id" '[.edges[]? | select(.from==$n)] | length > 0' "$g" >/dev/null 2>&1 \
      || { warn "읽는 노드 없는 저장소: $id" "소비 엣지를 잇거나 저장소를 폐지한다"; orphan=$((orphan+1)); }
  done < <(jq -r '.nodes[]? | select(.kind=="store") | .id' "$g" 2>/dev/null)
  [ "$orphan" -eq 0 ] && ok "모든 저장소에 소비 경로 존재"

  # produces 선언은 연결까지가 한 동작이다 — 선언만 하고 저장소를 잇지 않으면
  # 그 산출물은 그래프의 사각지대로 남는다 (stage의 produces는 파일이 아니므로 제외).
  local unlinked=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    jq -e --arg n "$id" '[.edges[]? | select(.from==$n)] | length > 0' "$g" >/dev/null 2>&1 \
      || { bad "produces를 선언했으나 산출 엣지 없음: $id" "산출물이 그래프에서 추적 불가"; unlinked=$((unlinked+1)); }
  done < <(jq -r '.nodes[]? | select(.produces != null and .kind != "stage") | .id' "$g" 2>/dev/null)
  [ "$unlinked" -eq 0 ] && ok "produces 선언 노드 전부 산출 엣지 보유"

  # manual 선언 ↔ frontmatter (G8) — 그래프가 "수동 전용"이라 한 스킬이 description으로
  # 자동 발동하면 그래프가 거짓이다. ui-ux-design이 그 상태였고 doctor는 frontmatter만 봤다 (평가 v6 · E-26).
  local gm=0 gmlist="" mid mpath
  while IFS=$'\t' read -r mid mpath; do
    [ -z "$mid" ] && continue
    [ -f "$mpath" ] || continue
    grep -q '^disable-model-invocation:[[:space:]]*true' "$mpath" 2>/dev/null && continue
    gm=$((gm+1)); gmlist="$gmlist $mid"
  done < <(jq -r '.nodes[]? | select(.kind=="skill" and .manual==true) | "\(.id)\t\(.path // "")"' "$g" 2>/dev/null)
  if [ "$gm" -gt 0 ]; then
    bad "그래프 manual인데 disable-model-invocation 없음:$gmlist" "그래프는 수동이라 하고 description은 자동 발동한다 — 한쪽이 거짓이다"
  else
    ok "manual 노드 전부 frontmatter와 일치"
  fi

  # 역방향 (G8') — frontmatter가 dmi인데 그래프 노드에 manual이 없으면 그래프가 그 스킬을
  # 자동 발동 가능으로 그리는 셈이다. G8만 있던 동안 epcc-init·harness-evaluation이 그 상태였다
  # (평가 v7 · E-51). 그래프에 노드가 없는 스킬은 「그래프 미선언 스킬」이 따로 잡는다.
  local g8r=0 g8rlist="" dpath did
  while IFS= read -r dpath; do
    [ -z "$dpath" ] && continue
    did=$(jq -r --arg p "$dpath" '.nodes[]? | select(.kind=="skill" and .path==$p) | .id' "$g" 2>/dev/null | head -1)
    [ -z "$did" ] && continue
    jq -e --arg n "$did" '.nodes[]? | select(.id==$n and .manual==true)' "$g" >/dev/null 2>&1 && continue
    g8r=$((g8r+1)); g8rlist="$g8rlist $did"
  done < <(grep -l '^disable-model-invocation:[[:space:]]*true' $(skill_mds) 2>/dev/null)
  if [ "$g8r" -gt 0 ]; then
    bad "disable-model-invocation인데 그래프 manual 없음:$g8rlist" "frontmatter는 수동이라 하고 그래프는 자동 발동으로 그린다 — 노드에 \"manual\": true"
  else
    ok "dmi 스킬 전부 그래프 manual과 일치"
  fi

  # 그래프 → 카드 역방향 (G9) — G6은 카드가 말한 호출이 그래프에 있는지만 봤다. 그래프가
  # 스킬에 phase를 달았는데 카드에 그 행이 없으면 호출 조건 없는 선언이다 (stage는 어휘 앵커라 제외).
  local g9=0 g9list="" gph gid
  if [ -f "$rc" ]; then
    while IFS=$'\t' read -r gid gph; do
      [ -z "$gid" ] && continue
      grep -qE "^\| *${gph} *\|" "$rc" 2>/dev/null || { g9=$((g9+1)); g9list="$g9list $gid:$gph"; }
    done < <(jq -r '.nodes[]? | select(.kind=="skill" and .phase != null) | .id as $i | .phase[] | "\($i)\t\(.)"' "$g" 2>/dev/null)
    if [ "$g9" -gt 0 ]; then
      bad "그래프 phase가 라우팅 카드에 없음:$g9list" "카드 행이 없는 phase는 호출 조건이 없는 선언이다"
    else
      ok "그래프 phase 전부 라우팅 카드에 행 존재"
    fi
  fi

  # 중복 path (G10) — 두 노드가 한 파일을 가리키면 하나는 별칭이다. 의도면 note로 말한다.
  local dup
  dup=$(jq -r '[.nodes[]? | select(.path != null and (.note // "") == "")] | group_by(.path) | map(select(length>1)) | .[] | map(.id) | join("+")' "$g" 2>/dev/null)
  if [ -n "$dup" ]; then
    warn "같은 path를 가진 노드 (note 없음): $(printf '%s' "$dup" | tr '\n' ' ')" "별칭이면 note에 이유를 적고, 아니면 한쪽을 지운다"
  else
    ok "노드 path 중복 없음 (note 없는 노드 기준)"
  fi
}

# ════════════════════════════════════════════════════════════════════
# --consumer : 소비자 레이아웃 실증 (RC2)
#
# 이 저장소에는 소비자가 없다. 그래서 개발 머신 조건이 검증 조건이 되어 있었고,
# 그 결과 (ⓐ) handoff가 커밋 0개 저장소에서 죽고 (ⓑ) build-gate가 jq 없으면
# 오탐 차단하고 (ⓒ) 스킬 스크립트 경로가 여기서만 우연히 맞는 것을 넉 달간 못 봤다.
#
# 플러그인을 캐시 유사 경로로 복사하고, **가장 취약한 프로젝트 상태**에서 훅을 돌린다.
# ════════════════════════════════════════════════════════════════════
run_consumer() {
  printf "\n${C_D}epcc doctor --consumer${C_0}  (소비자 레이아웃 실증)\n"

  local tmp; tmp=$(mktemp -d 2>/dev/null) || { bad "임시 디렉토리 생성 실패"; return; }
  trap 'rm -rf "$tmp"' RETURN
  local cache="$tmp/cache/epcc-devkit/x"
  mkdir -p "$cache" || { bad "캐시 경로 생성 실패"; return; }

  sec "플러그인 캐시 복사"
  # guides/ 는 크고 이 검증과 무관하다 (install-guide는 별도 자기시험이 있다)
  if ! (cd "$ROOT" && tar cf - --exclude=.git --exclude=guides --exclude=dev . ) | (cd "$cache" && tar xf -) 2>/dev/null; then
    bad "캐시 복사 실패"; return
  fi
  [ -f "$cache/scripts/session-brief.sh" ] && ok "캐시 경로에 플러그인 자산 복사됨" \
    || { bad "캐시 복사 검증 실패"; return; }

  # 프로젝트 3종 — ⓐ가 handoff exit 128을 잡는 조건이다
  local ok_all=1
  _consumer_project() {   # $1 라벨  $2 경로  $3 커밋할까  $4 config 만들까
    mkdir -p "$2" && (cd "$2" && git init -q .) || return 1
    printf 'export const a = 1\n' > "$2/src_a.ts"
    [ "$3" = "commit" ] && (cd "$2" && git add -A && git -c user.email=t@t -c user.name=t commit -q -m init)
    [ "$4" = "config" ] && printf '{"techStack":{"commands":{"build":"echo build"}}}\n' > "$2/epcc.config.json"
    return 0
  }

  local label path fixture hook code err out
  for label in "첫-커밋-전:none:none" "커밋-있음:commit:none" "설정-있음:commit:config"; do
    local nm; nm=${label%%:*}
    local rest=${label#*:}; local docommit=${rest%%:*}; local docfg=${rest#*:}
    path="$tmp/proj-$nm"
    _consumer_project "$nm" "$path" "$docommit" "$docfg" || { bad "$nm: 프로젝트 생성 실패"; continue; }

    sec "훅 실행 — $nm"
    local fails=0
    while IFS=$'\t' read -r event cmd; do
      [ -z "$cmd" ] && continue
      hook=$(printf '%s' "$cmd" | grep -oE 'scripts/[a-z0-9./-]+\.sh' | head -1)
      [ -n "$hook" ] && [ -f "$cache/$hook" ] || continue
      fixture="$ROOT/scripts/fixtures/${event}.json"
      [ -f "$fixture" ] || fixture="$ROOT/scripts/fixtures/default.json"
      [ -f "$fixture" ] || continue
      code=0
      out=$(CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$path" \
            bash "$cache/$hook" < "$fixture" 2>"$tmp/err") || code=$?
      err=$(cat "$tmp/err" 2>/dev/null)
      if [ "$code" -ne 0 ] && [ "$code" -ne 2 ]; then
        bad "$nm · $(basename "$hook") [$event]: exit $code" "${err:0:140}"; fails=$((fails+1)); ok_all=0
      elif [ -n "$err" ]; then
        bad "$nm · $(basename "$hook") [$event]: stderr 출력" "${err:0:140}"; fails=$((fails+1)); ok_all=0
      fi
    done < <(command -v jq >/dev/null 2>&1 && jq -r '.hooks | to_entries[] | .key as $e | .value[]?.hooks[]? | "\($e)\t\(.command)"' "$ROOT/hooks/hooks.json" 2>/dev/null)
    [ "$fails" -eq 0 ] && ok "$nm: 훅 전부 정상 (exit 0/2 · stderr 없음)"
  done

  # 설정 있는 프로젝트에 규칙이 자동 설치되었는가
  sec "T1 규칙 자동 설치"
  local rp="$tmp/proj-설정-있음/.claude/rules"
  local rn; rn=$(num "$({ ls -1 "$rp"/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')")
  local pn; pn=$(num "$({ ls -1 "$ROOT"/rules/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')")
  if [ "$rn" -eq "$pn" ] && [ "$rn" -gt 0 ]; then
    ok "규칙 ${rn}/${pn}장 자동 설치"
  else
    bad "규칙 자동 설치 ${rn}/${pn}장" "session-brief의 누락분 자동 설치가 동작하지 않았다"
  fi
  local always; always=$({ grep -L '^paths:' "$rp"/*.md 2>/dev/null || true; } | head -1)
  [ -n "$always" ] && ok "상시 로드 카드 설치됨: $(basename "$always")" \
                   || bad "상시 로드 카드 없음" "작업 라우팅이 세션에 도달하지 않는다"

  # 점진 로드 — 카드가 링크한 참조가 소비자 레이아웃에 실제로 도달했는가.
  # 링크만 배달되고 파일이 안 오면 "필요할 때 읽는다"가 "읽을 수 없다"가 된다.
  local cdang=0 cn=0 crc clnk
  for crc in "$rp"/*.md; do
    [ -f "$crc" ] || continue
    while IFS= read -r clnk; do
      [ -z "$clnk" ] && continue
      cn=$((cn+1))
      [ -f "$rp/$clnk" ] || cdang=$((cdang+1))
    done < <(grep -ohE '\.\./references/[A-Za-z0-9._/-]+\.md' "$crc" 2>/dev/null | sort -u)
  done
  if [ "$cn" -eq 0 ]; then
    ok "카드→참조 링크 없음 (해당 없음)"
  elif [ "$cdang" -eq 0 ]; then
    ok "점진 로드 참조 ${cn}건 소비자에 도달"
  else
    bad "참조 ${cdang}/${cn}건 미도달" "install-rules.sh가 references/를 함께 설치하지 않았다"
  fi

  # 설정 없는 프로젝트에는 쓰지 않았는가 (동의 관문)
  [ -d "$tmp/proj-첫-커밋-전/.claude/rules" ] \
    && bad "미설정 프로젝트에 규칙을 썼다" "epcc.config.json 관문이 새고 있다" \
    || ok "미설정 프로젝트에 쓰지 않음 (동의 관문 유효)"

  # build-gate 판정 불가 분기 — 차단하면 안 된다
  sec "판정 불가 분기"
  local bp="$tmp/proj-설정-있음"
  code=0
  out=$(printf '{"stop_hook_active":false}' | CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$bp" \
        bash "$cache/scripts/build-gate.sh" 2>/dev/null) || code=$?
  if [ "$code" -ne 0 ]; then
    bad "build-gate: transcript 없음에 exit $code" "판정 불가를 차단으로 접었다 — 오탐은 훅을 꺼지게 만든다"
  elif printf '%s' "$out" | grep -q '"continue"[[:space:]]*:[[:space:]]*false'; then
    bad "build-gate: 판정 불가인데 continue:false" "차단하면 안 된다"
  else
    ok "build-gate: 판정 불가 → 차단 없음"
  fi

  # UI 렌더 알림 — **알림이지 차단이 아니다.** 둘 다 증명한다.
  # 빌드는 돌았는데 렌더 확인 흔적이 없는 세션을 합성해서 넣는다.
  sec "UI 렌더 알림 (비차단)"
  local up="$tmp/proj-커밋-있음"
  mkdir -p "$up/src"
  printf 'export const A = () => <div/>;\n' > "$up/src/Card.tsx"
  (cd "$up" && git add -A >/dev/null 2>&1 && git commit -qm ui >/dev/null 2>&1)
  printf 'export const A = () => <div>changed</div>;\n' > "$up/src/Card.tsx"
  mkdir -p "$up/.claude/.epcc"; : > "$up/.claude/.epcc/session-baseline.txt"
  rm -f "$up/.claude/.epcc/ui-notice.stamp"
  printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"npm run build"}}]}}' \
    > "$tmp/ui-transcript.jsonl"
  code=0
  out=$(printf '{"stop_hook_active":false,"transcript_path":"%s"}' "$tmp/ui-transcript.jsonl" \
        | CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$up" \
          bash "$cache/scripts/build-gate.sh" 2>/dev/null) || code=$?
  if ! command -v jq >/dev/null 2>&1; then
    warn "UI 알림 미검증 — jq 없음" "판정 불가를 통과로 접지 않는다"
  elif [ "$code" -ne 0 ]; then
    bad "build-gate: UI 알림 경로에서 exit $code" "알림은 종료 코드를 바꾸면 안 된다"
  elif printf '%s' "$out" | grep -q '"continue"[[:space:]]*:[[:space:]]*false'; then
    bad "build-gate: UI 알림이 차단으로 나갔다" "오탐 차단은 사용자가 훅을 끄게 만든다"
  elif printf '%s' "$out" | grep -q '렌더를 확인한 흔적이 없습니다'; then
    ok "build-gate: UI 변경 + 빌드만 → 알림 발생, 차단 없음"
  else
    bad "build-gate: UI 알림이 나오지 않았다" "타입체크 통과가 렌더 증거로 취급되고 있다"
  fi
  # 두 번째 호출은 침묵해야 한다 — 꺼지지 않는 경고는 무시를 학습시킨다.
  out=$(printf '{"stop_hook_active":false,"transcript_path":"%s"}' "$tmp/ui-transcript.jsonl" \
        | CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$up" \
          bash "$cache/scripts/build-gate.sh" 2>/dev/null)
  printf '%s' "$out" | grep -q '렌더를 확인한 흔적이 없습니다' \
    && bad "UI 알림이 매 Stop 마다 반복된다" "세션당 1회 마커가 동작하지 않는다" \
    || ok "UI 알림 세션당 1회 (반복 경고 없음)"

  # ── 검증 명령 인식 — 양쪽을 증명한다 (평가 v9 · E-60) ─────────────
  # ⓐ fastapi 프리셋이 처방하는 맨 `pytest`를 알아봐야 한다 — 못 알아보면 자기 처방을 돌린
  #    세션을 막는 오탐이고, 오탐은 훅을 끄게 만든다.
  # ⓑ `echo npm run build`는 실행이 아니다 — 문자열 포함으로 통과시키면 v2 stop-guard다.
  sec "검증 명령 인식 (build-gate)"
  local vt="$tmp/verify-transcript.jsonl" vcase vcmd vwant
  for vcase in "pytest -q|pass" "python -m pytest|pass" "npx tsc --noEmit|pass" "echo npm run build|block" "grep -rn 'pnpm build' README.md|block"; do
    vcmd="${vcase%|*}"; vwant="${vcase##*|}"
    printf '%s\n' "$(jq -nc --arg c "$vcmd" '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}')" > "$vt"
    printf 'export const A = () => <div>%s</div>;\n' "$RANDOM" > "$up/src/Card.tsx"
    code=0
    out=$(printf '{"stop_hook_active":false,"transcript_path":"%s"}' "$vt" \
          | CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$up" \
            bash "$cache/scripts/build-gate.sh" 2>/dev/null) || code=$?
    if ! command -v jq >/dev/null 2>&1; then
      warn "검증 명령 인식 미검증 — jq 없음" "판정 불가를 통과로 접지 않는다"; break
    elif printf '%s' "$out" | grep -q '"continue"[[:space:]]*:[[:space:]]*false'; then
      [ "$vwant" = "block" ] && ok "build-gate: '$vcmd' → 실행 아님 → 차단" \
        || bad "build-gate: '$vcmd'를 실행으로 못 알아봄 → 차단" "처방한 검증 명령을 돌린 세션을 막는 오탐 — 훅을 끄게 만든다"
    else
      [ "$vwant" = "pass" ] && ok "build-gate: '$vcmd' → 실행으로 인식" \
        || bad "build-gate: '$vcmd'를 실행으로 셌다" "문자열 포함이 통과 근거가 됐다 — v2 stop-guard의 실패"
    fi
  done

  # ── 응답 언어 도달 ────────────────────────────────────────────────
  # 언어 선택은 config에 적히는 것으로 끝나지 않는다. T0는 파일이 아니라 훅 **출력**이라
  # 치환이 실제로 일어나야 도달한다. 살아있음 ≠ 작동함.
  sec "응답 언어 도달"
  local lp="$tmp/proj-lang" lout=""
  mkdir -p "$lp"
  printf '{"project":{"name":"t","language":"id","languageLabel":"Bahasa Indonesia"},"techStack":{"language":"TypeScript"}}\n' \
    > "$lp/epcc.config.json"
  lout=$(printf '{}' | CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$lp" \
         EPCC_STATE_DIR="$lp/.epcc" bash "$cache/scripts/session-brief.sh" 2>/dev/null || true)
  if printf '%s' "$lout" | grep -q '{{'; then
    bad "T0에 자리표시자가 남았다" "치환이 동작하지 않습니다 — 매 세션 {{RESPONSE_LANGUAGE}}가 컨텍스트로 샙니다"
  elif printf '%s' "$lout" | grep -q 'Bahasa Indonesia'; then
    ok "설정 언어가 T0에 도달 (id → Bahasa Indonesia)"
  else
    bad "설정 언어가 T0에 도달하지 않았다" "epcc.config.json의 project.language가 무시되고 있습니다"
  fi

  # 이 파일에는 "language" 키가 넷 있다 (project·techStack·frontend·backend).
  # 범위를 좁히지 않으면 스택 언어(TypeScript)를 응답 언어로 읽는다.
  printf '%s' "$lout" | grep -q 'TypeScript로' \
    && bad "techStack.language를 응답 언어로 읽었다" "project 블록으로 범위를 좁히지 않았습니다" \
    || ok "스택 언어를 응답 언어로 오인하지 않음"

  # 미설정 프로젝트 폴백 — 여기서 라벨이 비면 자리표시자가 그대로 샌다
  lout=$(printf '{}' | CLAUDE_PLUGIN_ROOT="$cache" CLAUDE_PROJECT_DIR="$tmp/proj-첫-커밋-전" \
         EPCC_STATE_DIR="$tmp/proj-첫-커밋-전/.epcc" bash "$cache/scripts/session-brief.sh" 2>/dev/null || true)
  printf '%s' "$lout" | grep -q '{{' \
    && bad "미설정 프로젝트의 T0에 자리표시자가 남았다" "폴백 라벨이 비어 있습니다" \
    || ok "미설정 프로젝트 폴백 (자리표시자 누출 없음)"

  # 차단 증명 — 치환기를 들어낸 픽스처가 실제로 --fast에 막히는가, **의도한 사유로** 막히는가
  local bcache="$tmp/cache-broken" bout=""
  if cp -R "$cache" "$bcache" 2>/dev/null; then
    perl -pi -e 's/\{\{RESPONSE_LANGUAGE\}\}//g' "$bcache/scripts/session-brief.sh" 2>/dev/null || true
    bout=$(bash "$bcache/scripts/doctor.sh" --fast --root "$bcache" 2>&1 || true)
    printf '%s' "$bout" | grep -q '치환할 곳이 없다' \
      && ok "치환기 제거 → --fast 차단 (의도한 사유)" \
      || bad "치환기를 들어냈는데 --fast가 통과시켰다" "자리표시자 누출이 검출되지 않습니다"
  fi

  # 플러그인 밖에서 doctor 자신이 도는가
  sec "플러그인 밖 실행"
  (cd "$tmp/proj-커밋-있음" && bash "$cache/scripts/doctor.sh" --fast >/dev/null 2>&1) \
    && ok "캐시 경로의 doctor --fast → exit 0" \
    || bad "캐시 경로의 doctor --fast 실패" "소비자가 자기검증을 못 한다"
}

# ════════════════════════════════════════════════════════════════════
# --usage : 계측
# ════════════════════════════════════════════════════════════════════
run_usage() {
  printf "\n${C_D}epcc doctor --usage${C_0}  (project: %s)\n" "$PROJ"
  local d="$PROJ/.claude/.epcc"

  sec "훅 하트비트"
  if [ -f "$d/hookrun.log" ]; then
    # 분모는 **고유 스크립트 수**다. 선언 엔트리 수를 쓰면 안 된다 —
    # handoff.sh 하나가 PreCompact·SessionEnd 두 이벤트에 걸려 있어서,
    # 분자(로그의 스크립트 이름 distinct)가 분모에 도달하는 것이 구조적으로 불가능해진다.
    # 영원히 5/6을 표시하는 지표는 꺼지지 않는 경고이고, 무시를 학습시킨다 (평가 v3 · E-11).
    local expected; expected=$(command -v jq >/dev/null 2>&1 \
      && jq -r '[.hooks|to_entries[].value[]?.hooks[]?.command
                 | capture("(?<f>[a-z0-9-]+)\\.sh").f] | unique | length' hooks/hooks.json 2>/dev/null \
      || echo "?")
    printf "  최근 세션 훅 실행:\n"
    awk -F'|' '{c[$1]++; last[$1]=$2} END{for(k in c) printf "    %-24s %4d회  최근 %s\n", k, c[k], last[k]}' "$d/hookrun.log" | sort
    local distinct; distinct=$(awk -F'|' '{print $1}' "$d/hookrun.log" | sort -u | wc -l | tr -d ' ')
    printf "  살아있는 훅: %s/%s\n" "$(num "$distinct")" "$(num "$expected")"
    # if/else로 쓴다. `[ ... ] && warn "..." || ok "..."`는 warn의 반환값이 1이라
    # (상세 인자 $2가 없을 때) 두 갈래가 **함께** 실행된다 — 실패를 보고한 직후
    # 같은 화면에서 "없음"으로 취소하고 PASS 카운터까지 올린다 (평가 v3 · E-10).
    local fails; fails=$(num "$(awk -F'|' '$4!="0"' "$d/hookrun.log" 2>/dev/null | wc -l | tr -d ' ')")
    if [ "$fails" -gt 0 ]; then
      warn "비정상 종료 ${fails}건" "$(awk -F'|' '$4!="0" {printf "%s(exit %s) ", $1, $4}' "$d/hookrun.log" 2>/dev/null | head -c 160)"
    else
      ok "비정상 종료 없음"
    fi
  else
    warn "하트비트 로그 없음" "훅이 아직 한 번도 실행되지 않았거나 계측이 배선되지 않음"
  fi

  sec "그래프 엣지 traversal"
  if [ -f "$d/graph.log" ]; then
    awk -F'|' '{printf "    %s → %s\n", $2, $3}' "$d/graph.log" | sort | uniq -c | sort -rn | head -20
    # 죽은 엣지: 그래프에 선언됐지만 한 번도 안 밟힌 것
    # 죽은 엣지는 **코드가 방출할 수 있는 엣지**에 한해 판정한다.
    # stage 간 전이는 모델 행동이라 훅이 방출할 수 없다. 그것까지 '죽었다'고
    # 보고하면 영원히 꺼지지 않는 경고가 되고, 꺼지지 않는 경고는 무시당한다.
    if [ -f workflow.graph.json ] && command -v jq >/dev/null 2>&1; then
      local dead=0
      while IFS=$'\t' read -r from to; do
        [ -z "$from" ] && continue
        grep -q "|${from}|${to}$" "$d/graph.log" 2>/dev/null \
          || { printf "    ${C_Y}미실행 엣지${C_0}: %s → %s\n" "$from" "$to"; dead=$((dead+1)); }
      done < <(jq -r '.edges[]? | select(.instrumented == true and (has("conditionalEmit") | not)) | "\(.from)\t\(.to)"' workflow.graph.json 2>/dev/null)
      [ "$dead" -gt 0 ] && warn "계측 엣지 중 미실행 ${dead}개" "주장이 아니라 측정이다"

      # 조건부 방출 엣지는 **분류하되 경고하지 않는다.** 차단이 일어나야(build-gate→build),
      # 또는 주기가 돌아와야(session-start→harness-evaluation) 방출되므로, 정상 상태에서
      # 미방출인 것이 정상이다. 이것을 죽은 엣지로 세면 영원히 꺼지지 않는 경고가 되고,
      # 꺼지지 않는 경고는 무시를 학습시킨다 (평가 v3 · E-04).
      while IFS=$'\t' read -r from to why; do
        [ -z "$from" ] && continue
        grep -q "|${from}|${to}$" "$d/graph.log" 2>/dev/null \
          || printf "    ${C_D}미실행(조건부)${C_0}: %s → %s — %s\n" "$from" "$to" "$why"
      done < <(jq -r '.edges[]? | select(.instrumented == true and has("conditionalEmit")) | "\(.from)\t\(.to)\t\(.conditionalEmit)"' workflow.graph.json 2>/dev/null)
    fi
  else
    warn "엣지 traversal 로그 없음"
  fi

  sec "스킬 호출"
  if [ -f "$d/skilluse.log" ]; then
    # 로그의 $2는 플랫폼이 주는 정규화 이름(`epcc-devkit:foo`)이고, 아래 미호출 판정의
    # 대조군은 `skills/` 디렉토리명(`foo`)이다. 접두사를 벗기지 않으면 둘은 영원히 어긋나고,
    # 방금 호출한 스킬이 같은 화면에서 '호출 기록 없음'으로 찍힌다 (평가 v5 · E-19).
    awk -F'|' '{n=$2; sub(/^[^:]*:/,"",n); c[n]++} END{for(k in c) printf "    %-32s %d\n", k, c[k]}' "$d/skilluse.log" | sort -k2 -rn | head -20

    # 계측 기간 내 호출 기록 없는 플러그인 스킬 — 판정이 아니라 관찰 대상 목록.
    # 장기(수개월) 무호출이 지속되는 자산만 폐기 후보로 사용자에게 제안한다.
    local unseen="" un=0 sname
    while IFS= read -r sname; do
      [ -z "$sname" ] && continue
      awk -F'|' '{n=$2; sub(/^[^:]*:/,"",n); print n}' "$d/skilluse.log" 2>/dev/null | grep -qx "$sname" \
        || { un=$((un+1)); unseen="$unseen $sname"; }
    done < <(ls -1 "$PLUGIN_ROOT/skills" 2>/dev/null)
    if [ "$un" -gt 0 ]; then
      printf "    ${C_D}호출 기록 없음 %d개:%s${C_0}\n" "$un" "$unseen"
      printf "    ${C_D}(계측 기간이 짧으면 정상 — 장기 무호출만 폐기 후보)${C_0}\n"
    fi
  else
    warn "스킬 호출 로그 없음" "미사용 스킬 판정은 계측 후에만 (안티골 8)"
  fi

  sec "상주 컨텍스트 비용"
  # 호출 여부와 무관하게 **매 세션 무조건** 들어가는 비용. T0만 예산(42줄)이 있었고
  # 나머지는 아무도 세지 않았다 — 특히 스킬 description은 스킬을 한 번도 안 써도
  # 전량이 상주한다. 그래서 평가 축 P5가 계속 '미계측'이었다.
  # 단위는 **바이트**다(wc -c). 한국어는 문자당 약 3바이트라 문자 수보다 크다 —
  # 아래 래칫의 역사값이 전부 바이트로 측정됐으므로 값이 아니라 라벨을 맞춘다.
  # **토큰 환산은 하지 않는다** — 환산 계수는 모델별로 다르고 여기서 검증할 수 없다.
  # 검증 불가한 숫자를 만드는 것이 안티골 8이다.
  local c_t0 c_route c_desc c_agent c_sum sfile
  # T0만 주석을 제거한다 — session-brief.sh가 출력 직전에 실제로 지우기 때문이다.
  # workflow-routing.md는 Claude Code가 **파일 그대로** 로드하므로 주석도 컨텍스트다.
  # (여기서 sed로 지우면 계측이 실물보다 작게 거짓말한다 — 실측 414바이트 차이.)
  c_t0=$(num "$(sed '/<!--/,/-->/d' "$PLUGIN_ROOT/templates/operating-contract.md" 2>/dev/null | wc -c | tr -d ' ')")
  c_route=$(num "$(wc -c < "$PLUGIN_ROOT/rules/workflow-routing.md" 2>/dev/null | tr -d ' ')")
  c_desc=0
  # 리셋은 `[A-Za-z_-]+:` — 프론트매터 키에는 하이픈·대문자가 섞인다(`disable-model-invocation`).
  # `[a-z_]+:`로는 그 줄이 리셋되지 않아 description 뒤에 딸려 들어갔다. 상주분(c_desc)은
  # 두 정규식이 같은 값을 내므로 래칫에는 영향이 없었고, **비상주 값만 186바이트 부풀어 있었다** —
  # 절감 폭을 실제보다 크게 보고하던 자리다.
  local dtop="" dn dv c_hidden=0 n_hidden=0
  for sfile in "$PLUGIN_ROOT"/skills/*/SKILL.md; do
    [ -f "$sfile" ] || continue
    dv=$(num "$(awk '/^---$/{n++; next} n==1 && /^(name|description):/{p=1} n==1 && /^[A-Za-z_-]+:/ && !/^(name|description):/{p=0} n==1 && p{print} n>=2{exit}' "$sfile" | wc -c | tr -d ' ')")
    dn=$(basename "$(dirname "$sfile")")
    # disable-model-invocation: true 인 스킬의 description은 상주하지 않는다
    # (docs/platform-contract.md §2.4). 합산하면 측정이 실제보다 크게 거짓말한다.
    if grep -q '^disable-model-invocation:[[:space:]]*true' "$sfile" 2>/dev/null; then
      c_hidden=$((c_hidden + dv)); n_hidden=$((n_hidden + 1)); continue
    fi
    c_desc=$((c_desc + dv))
    dtop="${dtop}${dv} ${dn}
"
  done
  # 에이전트 description — 스킬과 **같은 성질인데 자산 타입이 달라서** 빠져 있었다.
  # 부르지 않아도 상주하고(docs/platform-contract.md §6), 심지어 스킬의
  # disable-model-invocation에 해당하는 비상주 스위치가 **없어서 끌 수도 없다**.
  # `tools:`까지 세는 이유는 에이전트 목록의 렌더가 `(Tools: …)`를 실제로 포함하기 때문이다
  # (스킬 목록에는 그 줄이 없어 위 루프는 name/description만 센다).
  # 리셋 정규식이 위 스킬 루프와 다르다 — 에이전트 프론트매터에는 `disallowedTools:`처럼
  # 대문자가 섞인 키가 있고, `[a-z_-]+:`로는 리셋되지 않아 그 줄까지 딸려 들어간다(실측 +86바이트).
  c_agent=0
  local afile
  for afile in "$PLUGIN_ROOT"/agents/*.md; do
    [ -f "$afile" ] || continue
    c_agent=$((c_agent + $(num "$(awk '/^---$/{n++; next} n==1 && /^(name|description|tools):/{p=1} n==1 && /^[A-Za-z_-]+:/ && !/^(name|description|tools):/{p=0} n==1 && p{print} n>=2{exit}' "$afile" | wc -c | tr -d ' ')")))
  done
  local n_agent; n_agent=$(num "$({ ls -1 "$PLUGIN_ROOT"/agents/*.md 2>/dev/null || true; } | wc -l | tr -d ' ')")

  c_sum=$((c_t0 + c_route + c_desc + c_agent))

  # 조건부 카드 — **무조건 소계에서 빠져 있던 부분이다.** paths가 있으니 "조건부"이지만
  # `src/**`·`app/**`류를 가진 카드는 소스 파일 하나만 읽으면 들어오므로, 코딩 세션에서는
  # 사실상 확정 로드다. 그것을 계측에서 통째로 빼두면 P5가 실물의 1/3만 보고 판정한다
  # (실측: 보고 17,063바이트 ↔ 코딩 세션 48,450바이트).
  # 글롭을 해석하지는 않는다 — 검증 불가한 정교함 대신 **두 묶음**으로 정직하게 나눈다.
  local c_src=0 c_oth=0 n_src=0 n_oth=0 rcard
  for rcard in "$PLUGIN_ROOT"/rules/*.md; do
    [ -f "$rcard" ] || continue
    grep -q '^paths:' "$rcard" 2>/dev/null || continue    # 상시 카드는 위에서 셌다
    if grep -qE '^\s+- "(src|app|packages|lib)/\*\*"' "$rcard" 2>/dev/null; then
      c_src=$((c_src + $(num "$(wc -c < "$rcard" | tr -d ' ')"))); n_src=$((n_src+1))
    else
      c_oth=$((c_oth + $(num "$(wc -c < "$rcard" | tr -d ' ')"))); n_oth=$((n_oth+1))
    fi
  done

  printf "    %-32s %8s바이트\n" "T0 운영 규칙" "$c_t0"
  printf "    %-32s %8s바이트\n" "workflow-routing (상시 로드)" "$c_route"
  printf "    %-32s %8s바이트\n" "스킬 description (상주분)" "$c_desc"
  printf "    %-32s %8s바이트  ${C_D}끌 수 없음${C_0}\n" "에이전트 description ${n_agent}개" "$c_agent"
  printf "    %-32s %8s바이트\n" "── 무조건 소계" "$c_sum"
  printf "    %-32s %8s바이트  ${C_D}소스 1개만 읽으면${C_0}\n" "조건부 카드 ${n_src}장 (src/app/lib)" "$c_src"
  printf "    %-32s %8s바이트  ${C_D}해당 경로 편집 시${C_0}\n" "조건부 카드 ${n_oth}장 (그 외)" "$c_oth"
  printf "    %-32s %8s바이트\n" "── 코딩 세션 실측" "$((c_sum + c_src))"
  # 총합만으로는 무엇을 압축할지 모른다 — 상위 3개를 함께 보인다.
  printf "    ${C_D}상위: %s${C_0}\n" "$(printf '%s' "$dtop" | sort -rn | head -3 | awk '{printf "%s %s · ", $2, $1}' | sed 's/ · $//')"
  [ "$n_hidden" -gt 0 ] && printf "    ${C_D}비상주 %d개 %s바이트 (disable-model-invocation)${C_0}\n" "$n_hidden" "$c_hidden"
  # 정직 보고 — 무엇을 못 세는지 밝힌다. T0는 session-brief 출력의 대부분이고 위에서 셌다.
  # 남은 것은 브리핑 가변부(HEAD·미커밋 수·훅 생존 = 약 400~600바이트)뿐이다.
  printf "    ${C_D}브리핑 가변부(HEAD·미커밋·훅 생존)는 세션마다 달라 미포함${C_0}\n"
  # 생성 가이드 description — 이전 판은 "소비자 쪽이라 미포함"으로 끝냈지만, 허브는
  # 플러그인이 배송하는 guides/seams/*/이므로 **여기서 셀 수 있다.** 셀 수 있는데 빼는 것이
  # 직전 교훈(2026-09-10)이 지목한 낙관적 거짓이다. 다만 소계에는 넣지 않는다 —
  # epcc-init을 돌린 소비자에게만 생기고 어느 이음매냐에 따라 값이 달라지므로,
  # 하나를 골라 소계에 더하면 그것이야말로 검증 불가한 수가 된다. 범위로 보고한다.
  local g_min="" g_max="" gdir gpair gh
  for gdir in "$PLUGIN_ROOT"/guides/seams/*/; do
    [ -d "$gdir" ] || continue
    gpair=0
    for gh in "$gdir"frontend/HUB.md "$gdir"backend/HUB.md; do
      [ -f "$gh" ] || continue
      gpair=$((gpair + $(num "$(awk '/^---$/{n++; next} n==1 && /^(name|description):/{p=1} n==1 && /^[A-Za-z_-]+:/ && !/^(name|description):/{p=0} n==1 && p{print} n>=2{exit}' "$gh" | wc -c | tr -d ' ')")))
    done
    [ "$gpair" -eq 0 ] && continue
    # if로 쓴다 — `[ ] || [ ] && x`는 우선순위가 눈에 보이는 것과 다르고,
    # 이 파일이 이미 같은 형태로 두 갈래를 함께 실행한 전례가 있다(평가 v3 · E-10).
    if [ -z "$g_min" ] || [ "$gpair" -lt "$g_min" ]; then g_min="$gpair"; fi
    if [ -z "$g_max" ] || [ "$gpair" -gt "$g_max" ]; then g_max="$gpair"; fi
  done
  if [ -n "$g_min" ]; then
    printf "    ${C_D}참고: 생성 가이드 description %s~%s바이트 — epcc-init 후 소비자에 상주, 이음매마다 달라 소계 제외${C_0}\n" "$g_min" "$g_max"
  fi
  printf "    ${C_D}프로젝트가 저술하는 CLAUDE.md는 내용을 플러그인이 알 수 없어 미포함${C_0}\n"
  # 예산은 **반복 증거가 쌓인 뒤에** 둔다는 규율을 지켰다 — 평가 v3(14,219바이트) · v4(11,662) ·
  # v5(11,662)에서 3회 연속 "예산 있는 T0의 4.8배인데 상한이 없다"로 관측됐다(E-07).
  # 그래서 지금 값을 상한으로 **고정(래칫)**한다: 압축된 상태를 되돌리지 못하게만 한다.
  # 차단이 아니라 경고다 — 이 숫자는 정확성 게이트가 아니라 절제의 눈금이고,
  # 무관한 작업을 막으면 그것이 훅을 꺼버리게 만드는 오탐이 된다.
  local desc_budget=12000
  if [ "$c_desc" -gt "$desc_budget" ]; then
    warn "스킬 description ${c_desc}바이트 — 예산 ${desc_budget}바이트 초과" \
         "스킬을 한 번도 호출하지 않아도 전량이 매 세션 상주한다. 압축하거나 본문으로 내리세요"
  else
    ok "스킬 description ${c_desc}/${desc_budget}바이트"
  fi
  ok "상주 비용 실측 — 무조건 ${c_sum}(에이전트 ${c_agent} 포함) · 코딩 세션 $((c_sum + c_src))바이트 (판정은 P5)"
}

# ════════════════════════════════════════════════════════════════════
# --lessons : Act 루프
# ════════════════════════════════════════════════════════════════════
run_lessons() {
  printf "\n${C_D}epcc doctor --lessons${C_0}\n"
  sec "교훈 집계"

  local lf="$PROJ/docs/lessons.md"
  [ -f "$lf" ] || { warn "docs/lessons.md 없음"; return; }

  local threshold=3 found=0
  printf "  %-24s %5s  %s\n" "카테고리" "건수" "상태"
  while read -r cnt cat; do
    [ -z "$cat" ] && continue
    local status="—"
    # 오탐은 승격 대상이 아니다 — 규칙(rules/lessons.md)은 이 카테고리를 **수축**으로 처리하라 한다.
    # 카테고리 합계로 "승격 후보"를 내면 규칙과 반대 방향의 경고가 매 실행 뜬다 (평가 v6 · E-27).
    if [ "$cat" = "false-positive" ]; then
      status="${C_D}수축 대상 — 아래 「오탐 수축 후보」 장치별 집계 참조${C_0}"
    elif [ "$(num "$cnt")" -ge "$threshold" ]; then
      # 대응 룰 카드가 실재하는가?
      #   ① 파일명이 카테고리와 일치        → 확실한 대응 자산
      #   ② 본문에 언급                      → 단 lessons.md 는 제외.
      #      그 파일은 카테고리 *예시 목록*을 담고 있어서, 카탈로그를 규칙으로
      #      오인하면 승격되지 않은 것이 승격된 것으로 보고된다.
      local card=""
      for d in "$PLUGIN_ROOT/rules" "$PROJ/.claude/rules"; do
        [ -f "$d/$cat.md" ] && card="$d/$cat.md" && break
      done
      if [ -z "$card" ]; then
        card=$(grep -rli --include='*.md' --exclude='lessons.md' -- "$cat" "$PLUGIN_ROOT/rules" "$PROJ/.claude/rules" 2>/dev/null | head -1)
      fi
      if [ -n "$card" ]; then
        status="${C_G}승격됨 → ${card}${C_0}"
      else
        status="${C_Y}승격 후보 — 대응 룰 카드 없음${C_0}"; found=$((found+1))
      fi
    fi
    printf "  %-24s %5s  %b\n" "$cat" "$cnt" "$status"
  done < <(grep -oE '\[category: [^]]+\]' "$lf" 2>/dev/null | sed 's/\[category: //;s/\]//' | sort | uniq -c | sort -rn)

  local total; total=$(num "$(grep -c '^## \[category:' "$lf" 2>/dev/null)")
  printf "\n  총 %s건" "$total"
  [ -f "$PROJ/docs/lessons-archive.md" ] \
    && printf " · 아카이브 %s건\n" "$(num "$(grep -c '^## \[category:' "$PROJ/docs/lessons-archive.md" 2>/dev/null)")" \
    || printf " · ${C_Y}아카이브 파일 없음${C_0}\n"

  [ "$found" -gt 0 ] && warn "승격 후보 ${found}건" "승격 시 lessons-archive.md로 물리 이동 (선언이 아니라 파일 이동으로 증명)"

  # ── 오탐 수축 후보 — 장치별 ──
  # 서로 다른 장치의 오탐을 카테고리 하나로 합치면 "무엇을 좁힐 것인가"가 사라진다. 장치는
  # 항목의 `- 장치:` 줄이 정본이고, 없으면 본문 첫 스크립트/스킬 이름으로 추정한다(추정은 표시한다).
  # 같은 장치 2건 이상이면 규칙대로 **조건을 좁히거나 경고로 내린다** — 규칙을 추가하지 않는다.
  sec "오탐 수축 후보 (장치별)"
  local fp_total fp_hot=0
  fp_total=$(num "$(grep -c '^## \[category: false-positive\]' "$lf" 2>/dev/null)")
  if [ "$fp_total" -eq 0 ]; then
    printf "  (기록 없음)\n"
  else
    while read -r cnt dev; do
      [ -z "$dev" ] && continue
      printf "  %-44s %s건\n" "$dev" "$cnt"
      [ "$(num "$cnt")" -ge 2 ] && fp_hot=$((fp_hot+1))
    done < <(awk '
      /^## \[category: /{ if (fp && dev=="") print "(장치 미표기)"; fp=($0 ~ /false-positive\]/); dev=""; next }
      fp && /^- 장치:/ { d=$0; sub(/^- 장치:[ \t]*/,"",d); if (dev=="") { dev=d; print d }; next }
      fp && dev=="" {
        if (match($0, /[a-z-]+\.sh/))               { dev=substr($0,RSTART,RLENGTH) "(추정)"; print dev }
        else if (match($0, /skills\/[a-z-]+/))     { dev=substr($0,RSTART,RLENGTH) "(추정)"; print dev }
        else if ($0 ~ /하네스 평가|harness-evaluation/) { dev="harness-evaluation(추정)"; print dev } }
      END { if (fp && dev=="") print "(장치 미표기)" }' "$lf" | sort | uniq -c | sort -rn)
    if [ "$fp_hot" -gt 0 ]; then
      warn "같은 장치 오탐 2건 이상 — ${fp_hot}개 장치" "규칙을 추가하지 않는다 — 그 장치의 조건을 좁히거나 경고로 내린다 (rules/lessons.md)"
    else
      ok "오탐 ${fp_total}건 — 장치별 2건 미만"
    fi
  fi

  # 반복 요청 [request: X] — 3건+이면 자동화(스킬 승격) 후보
  sec "반복 요청 집계"
  local rfound=0 rshown=0
  while read -r cnt req; do
    [ -z "$req" ] && continue
    rshown=1
    local rstatus="—"
    if [ "$(num "$cnt")" -ge "$threshold" ]; then
      if [ -d "$PLUGIN_ROOT/skills/$req" ] || [ -d "$PROJ/.claude/skills/$req" ]; then
        rstatus="${C_G}자동화됨 → 대응 스킬 실재${C_0}"
      else
        rstatus="${C_Y}자동화 후보 — 대응 스킬 없음${C_0}"; rfound=$((rfound+1))
      fi
    fi
    printf "  %-24s %5s  %b\n" "$req" "$cnt" "$rstatus"
  done < <(grep -oE '\[request: [^]]+\]' "$lf" 2>/dev/null | sed 's/\[request: //;s/\]//' | sort | uniq -c | sort -rn)
  [ "$rshown" -eq 0 ] && printf "  (기록 없음)\n"
  [ "$rfound" -gt 0 ] && warn "자동화 후보 ${rfound}건" "동일 요청 3회+ — 스킬 승격 검토 (사용자 승인 필수)"

  # Shadow 폐기 미러 — 만료분은 삭제 확정 또는 롤백 결정이 필요하다
  local sh_dir="$PROJ/.claude/deprecated"
  if [ -d "$sh_dir" ]; then
    sec "Shadow 폐기 미러"
    local today expired=0 sh_active=0 exp_list=""
    today=$(date +%Y-%m-%d)
    while IFS= read -r sf; do
      [ -z "$sf" ] && continue
      local exp="${sf##*.shadow-expires-}"
      case "$exp" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
          if [ "$exp" \< "$today" ]; then expired=$((expired+1)); exp_list="$exp_list $(basename "$sf")"
          else sh_active=$((sh_active+1)); fi ;;
        *) expired=$((expired+1)); exp_list="$exp_list $(basename "$sf")(만료일 형식 오류)" ;;
      esac
    done < <(find "$sh_dir" -name '*.shadow-expires-*' -type f 2>/dev/null)
    if [ "$expired" -gt 0 ]; then
      warn "만료된 shadow ${expired}건" "폐기 확정(삭제) 또는 롤백(원위치 복구) 결정 필요:$exp_list"
    else
      ok "shadow ${sh_active}건 관찰 중 · 만료 없음"
    fi
  fi
}

# ════════════════════════════════════════════════════════════════════
# --inventory : 영역별 자산 인벤토리 (판정 없음)
#
# /harness-evaluation의 요청 관점 ①「영역별 검토」와 ⑨「토큰 비용」의 **입력**이다. 평가 스킬은
# 다시 세지 않는다 — 여기서 센 것을 판단한다. 판정(ok/bad)을 내지 않는 이유: 이 수들은
# 예산이 아니라 관측이고, 관측에 임계를 박는 것은 반복 증거가 쌓인 뒤의 일이다(E-07의 규율).
# ════════════════════════════════════════════════════════════════════
run_inventory() {
  printf "\n${C_D}epcc doctor --inventory${C_0}  (plugin: %s)\n" "$PLUGIN_ROOT"
  local g="workflow.graph.json" hasjq=0
  command -v jq >/dev/null 2>&1 && [ -f "$g" ] && hasjq=1

  sec "스킬 (${C_D}줄=SKILL.md · desc=상주 바이트 · 호출시=디렉토리 .md 합계 · in/out=그래프 엣지 · 문서=README+docs 언급 파일 수${C_0})"
  printf "  %-26s %5s %6s %-3s %8s %5s %4s  %s\n" "스킬" "줄" "descB" "상주" "호출시B" "in/out" "문서" "phase"
  local sd sn sl dv dmi ib eio dm ph
  for sd in skills/*/; do
    [ -f "$sd/SKILL.md" ] || continue
    sn=$(basename "$sd")
    sl=$(num "$(wc -l < "$sd/SKILL.md")")
    dv=$(num "$(awk '/^---$/{n++; next} n==1 && /^(name|description):/{p=1} n==1 && /^[a-z_-]+:/ && !/^(name|description):/{p=0} n==1 && p{print} n>=2{exit}' "$sd/SKILL.md" | wc -c | tr -d ' ')")
    dmi="○"; grep -q '^disable-model-invocation:[[:space:]]*true' "$sd/SKILL.md" 2>/dev/null && dmi="—"
    ib=$(num "$(find "$sd" -name '*.md' -print0 2>/dev/null | xargs -0 cat 2>/dev/null | wc -c | tr -d ' ')")
    eio="?"; ph=""
    if [ "$hasjq" -eq 1 ]; then
      eio=$(jq -r --arg n "$sn" '"\([.edges[]|select(.to==$n)]|length)/\([.edges[]|select(.from==$n)]|length)"' "$g" 2>/dev/null)
      ph=$(jq -r --arg n "$sn" '[.nodes[]|select(.id==$n)|.phase[]?]|join(",")' "$g" 2>/dev/null)
    fi
    dm=$(num "$(grep -lF -- "$sn" README.md docs/*.md 2>/dev/null | wc -l | tr -d ' ')")
    printf "  %-26s %5s %6s %-3s %8s %5s %4s  %s\n" "$sn" "$sl" "$dv" "$dmi" "$ib" "$eio" "$dm" "$ph"
  done

  sec "규칙 카드 (${C_D}paths=조건 글롭 수, 0=상시 · 링크=../references 참조 수${C_0})"
  printf "  %-24s %5s %-8s %5s %5s\n" "카드" "줄" "스탬프" "paths" "링크"
  local rc rl rs rp rk
  for rc in rules/*.md; do
    [ -f "$rc" ] || continue
    rl=$(num "$(wc -l < "$rc")")
    rs=$(grep -m1 -oE 'epcc-rule-version: [0-9.]+' "$rc" | awk '{print $2}')
    rp=$(num "$(awk '/^---$/{n++; next} n==1 && /^[[:space:]]*- /{c++} END{print c+0}' "$rc")")
    rk=$(num "$(grep -oE '\.\./references/[A-Za-z0-9_./-]+\.md' "$rc" | sort -u | wc -l | tr -d ' ')")
    printf "  %-24s %5s %-8s %5s %5s\n" "$(basename "$rc")" "$rl" "${rs:-없음}" "$rp" "$rk"
  done
  printf "  %-24s %5s\n" "합계" "$(num "$(cat rules/*.md 2>/dev/null | wc -l | tr -d ' ')")"

  sec "훅 (${C_D}차단=dblock/block 호출 지점 · 픽스처=이 스크립트를 먹이는 fixtures/*.json${C_0})"
  printf "  %-22s %5s %-24s %5s %6s\n" "스크립트" "줄" "이벤트" "차단" "픽스처"
  if [ -f hooks/hooks.json ] && command -v jq >/dev/null 2>&1; then
    local hs hev hl hb hf
    while IFS=$'\t' read -r hs hev; do
      [ -f "$hs" ] || continue
      hl=$(num "$(wc -l < "$hs")")
      hb=$(num "$(grep -cE '^[[:space:]]*(&& |\|\| )?(dblock|block) "' "$hs")")
      hf=$(num "$(ls -1 scripts/fixtures/${hev%%|*}*.json 2>/dev/null | wc -l | tr -d ' ')")
      printf "  %-22s %5s %-24s %5s %6s\n" "$(basename "$hs")" "$hl" "$hev" "$hb" "$hf"
    done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[]?.hooks[]?.command
                    | capture("(?<f>scripts/[a-z0-9./-]+\\.sh)").f + "\t" + $e' hooks/hooks.json 2>/dev/null \
             | awk -F'\t' '{ if ($1 in ev) ev[$1]=ev[$1]"|"$2; else ev[$1]=$2 } END { for (k in ev) print k "\t" ev[k] }' | sort)
  fi
  printf "  %-22s %5s\n" "lib/common.sh" "$(num "$(wc -l < scripts/lib/common.sh 2>/dev/null)")"

  sec "에이전트 (${C_D}descB=상주 바이트 · 스킬 표와 달리 비상주 스위치가 없다${C_0})"
  local af adv
  for af in agents/*.md; do
    [ -f "$af" ] || continue
    # 스킬 표의 descB는 name+description만 센다. 여기도 **같은 식**을 쓴다 — 두 표를 나란히
    # 읽는 것이 --inventory의 용도이므로 비교 가능성이 우선이다. `tools:`까지 더한 값은
    # --usage의 「상주 컨텍스트 비용」이 낸다(그쪽은 실제 렌더를 재는 것이 목적이라 포함한다).
    adv=$(num "$(awk '/^---$/{n++; next} n==1 && /^(name|description):/{p=1} n==1 && /^[A-Za-z_-]+:/ && !/^(name|description):/{p=0} n==1 && p{print} n>=2{exit}' "$af" | wc -c | tr -d ' ')")
    printf "  %-16s %4s줄 %6s descB  model=%-7s tools=%s\n" "$(basename "$af" .md)" "$(num "$(wc -l < "$af")")" \
      "$adv" \
      "$(grep -m1 -E '^model:' "$af" | sed 's/^model:[[:space:]]*//')" \
      "$(grep -m1 -E '^tools:' "$af" | sed 's/^tools:[[:space:]]*//')"
  done

  sec "축 가이드 팩 (${C_D}verified=팩 검증일 · pkgs=신선도 기준 패키지 수${C_0})"
  local pk pj
  for pk in guides/frontend/*/ guides/backend/*/; do
    [ -f "$pk/pack.json" ] || continue
    pj="$pk/pack.json"
    printf "  %-28s %3s파일 %6s줄  v%-7s verified=%s pkgs=%s\n" "${pk#guides/}" \
      "$(num "$(find "$pk" -type f | wc -l | tr -d ' ')")" \
      "$(num "$(find "$pk" -name '*.md' -print0 | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')")" \
      "$(jq -r '.packVersion // "?"' "$pj" 2>/dev/null)" "$(jq -r '.verified // "?"' "$pj" 2>/dev/null)" \
      "$(jq -r '(.pkgs // []) | length' "$pj" 2>/dev/null)"
  done
  printf "  이음매: %s\n" "$({ ls -1d guides/seams/*/ 2>/dev/null || true; } | sed -E 's|.*/([^/]+)/$|\1|' | tr '\n' ' ')"

  sec "기타 자산"
  printf "  %-14s %3s파일 %6s줄\n" "references/" "$(num "$(find references -name '*.md' 2>/dev/null | wc -l | tr -d ' ')")" "$(num "$(find references -name '*.md' -print0 2>/dev/null | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')")"
  printf "  %-14s %3s파일 %6s줄\n" "templates/" "$(num "$(find templates -type f 2>/dev/null | wc -l | tr -d ' ')")" "$(num "$(find templates -type f -print0 2>/dev/null | xargs -0 cat 2>/dev/null | wc -l | tr -d ' ')")"
  printf "  %-14s %3s파일\n" "presets/" "$(num "$(find presets -name '*.json' 2>/dev/null | wc -l | tr -d ' ')")"
  printf "  %-14s %3s파일\n" "fixtures/" "$(num "$(ls -1 scripts/fixtures/*.json 2>/dev/null | wc -l | tr -d ' ')")"
  printf "  %-14s %3s파일 %6s줄\n" "docs/" "$(num "$(ls -1 docs/*.md 2>/dev/null | wc -l | tr -d ' ')")" "$(num "$(cat docs/*.md 2>/dev/null | wc -l | tr -d ' ')")"
  printf "  %-14s %3s파일 %6s줄  (검사 스크립트 — 판정 장치의 유지비)\n" "scripts/*.sh" "$(num "$(ls -1 scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')")" "$(num "$(cat scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')")"
  printf "  ${C_D}상주 비용의 실측은 --usage, 호출 흔적은 --usage의 스킬 호출 절이 낸다 — 여기서는 세지 않는다${C_0}\n"
}

# ════════════════════════════════════════════════════════════════════
MODE="${1:---default}"
case "$MODE" in
  --fast)      run_fast ;;
  --self-test) run_self_test ;;
  --graph)     run_graph ;;
  --usage)     run_usage ;;
  --lessons)   run_lessons ;;
  --consumer)  run_consumer ;;
  --inventory) run_inventory ;;
  --all)       run_fast; run_self_test; run_graph; run_consumer; run_usage; run_lessons; run_inventory ;;
  --default)   run_fast; run_graph ;;
  -h|--help)
    # 헤더 주석 전체를 낸다. 줄 번호를 박으면 헤더가 자라는 순간 잘리거나 구현이 샌다 —
    # `sed -n '2,24p'`가 실제로 `set -uo pipefail`까지 6줄을 출력하고 있었다 (평가 v6 · E-36).
    awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
    exit 0 ;;
  *) printf "알 수 없는 옵션: %s (--help 참조)\n" "$MODE" >&2; exit 2 ;;
esac

printf "\n${C_D}────────────────────────────────────────────${C_0}\n"
printf "  통과 %s · ${C_Y}경고 %s${C_0} · ${C_R}실패 %s${C_0}\n\n" "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
