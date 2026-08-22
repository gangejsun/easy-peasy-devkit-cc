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
#   doctor.sh --lessons    lessons.md 카테고리 집계 + 승격 후보
#   doctor.sh              = --fast --graph
#
# 종료 코드: 0 = 통과, 1 = 실패 항목 존재

set -uo pipefail   # -e 없음: 모든 검사를 끝까지 돌려 전체 보고서를 낸다

# 루트가 둘이다 — 하나로 합치면 소비자 프로젝트에서 플러그인 구조 검사가 깨진다:
#   PLUGIN_ROOT: 플러그인 자산 검사(fast/graph/self-test) — 스크립트 위치가 곧 진실
#   PROJ:        프로젝트 상태 검사(usage/lessons) — 훅 로그·교훈은 소비자 쪽에 산다
PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

# 코드 행만 남긴다 — 주석과 사용자 메시지 문자열은 검사 대상이 아니다.
# (린터가 자기 에러 메시지를 검출하는 것은 린터의 결함이다)
# BSD sed는 BRE에서 \| 교대를 지원하지 않는다 → -E(ERE) 필수
code_lines() {
  sed -E -e 's/^[[:space:]]*#.*$//' \
         -e '/^[[:space:]]*(bad|ok|warn|sec|printf|echo)[[:space:]]/d' "$1" 2>/dev/null
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

    # UserPromptSubmit은 hookSpecificOutput 미지원
    local ups_scripts
    ups_scripts=$(command -v jq >/dev/null 2>&1 && jq -r '.hooks.UserPromptSubmit[]?.hooks[]?.command // empty' "$hooks_json" 2>/dev/null | grep -oE '[a-z-]+\.sh' || true)
    for s in $ups_scripts; do
      [ -f "scripts/$s" ] || continue
      grep -q 'hookSpecificOutput' "scripts/$s" 2>/dev/null \
        && bad "UserPromptSubmit 훅 '$s'가 hookSpecificOutput 사용" "이 이벤트는 해당 필드 미지원"
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

  # T0 예산 — operating-contract.md 주석이 약속한 40줄 상한을 기계가 지킨다
  local t0="templates/operating-contract.md"
  if [ -f "$t0" ]; then
    local t0n; t0n=$(num "$(wc -l < "$t0")")
    if [ "$t0n" -le 40 ]; then
      ok "T0 운영 계약 ${t0n}/40줄"
    else
      bad "T0 운영 계약 ${t0n}줄 — 예산 40줄 초과" "매 세션 상시 주입 비용. 줄이거나 T1 카드로 내리세요"
    fi
  else
    bad "T0 운영 계약 파일 없음: $t0"
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
  local stot blk proj
  stot=$(num "$(ls -d skills/*/ 2>/dev/null | wc -l | tr -d ' ')")
  blk=$(num "$(grep -l '^description: |' skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')")
  proj=$(num "$(grep -l '(project)' skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')")
  [ "$blk" -gt 0 ] && warn "블록 스칼라 description ${blk}/${stot}" "단일 행 권장 (sprawl 유발)" || ok "블록 스칼라 없음"
  [ "$proj" -gt 0 ] && warn "'(project)' 접미사 ${proj}/${stot}" "라우팅에 무의미, 상시 상주 비용만 차지" || ok "'(project)' 접미사 없음"

  # 네이티브와 싸우는 문구
  if grep -rq 'skill-creator 플러그인보다 우선' skills/ 2>/dev/null; then
    bad "네이티브 스킬(skill-creator)을 밀어내는 문구 존재" "플랫폼 네이티브와 싸우지 않는다 (P6)"
  else
    ok "네이티브를 밀어내는 문구 없음"
  fi

  # ── 6.5 스킬 내부 참조 (B-6) ──
  # SKILL.md가 가리키는 references/·assets/·resources/ 상대 경로의 실재.
  # 기존 dangling 검사는 .claude/rules만 봐서 이 사각지대가 5건을 4개월간 숨겼다.
  sec "스킬 내부 참조"
  local sdang=0 schecked=0
  for sd in skills/*/; do
    [ -f "$sd/SKILL.md" ] || continue
    while IFS= read -r ref; do
      [ -z "$ref" ] && continue
      schecked=$((schecked+1))
      # 스킬 디렉토리 우선, 플러그인 루트 폴백 (${CLAUDE_PLUGIN_ROOT}/scripts/* 참조 허용)
      if [ ! -f "$sd$ref" ] && [ ! -f "$ref" ]; then
        bad "$(basename "$sd") → $ref 없음"; sdang=$((sdang+1))
      fi
    done < <(grep -ohE '(references|assets|resources|scripts)/[A-Za-z0-9._/-]+\.(md|json|csv|txt|py|sh|html|hbs)' "$sd/SKILL.md" 2>/dev/null | sort -u)
  done
  [ "$sdang" -eq 0 ] && ok "스킬 내부 참조 ${schecked}건 모두 실재"

  # .claude/skills/ 하드코딩 — 플러그인 스킬이 프로젝트 오버라이드 경로를 지시하면
  # 오버라이드가 없는 프로젝트(플러그인 전용 설치)에서 그 명령은 실패한다.
  # 스킬 로드 시 주어지는 Base directory(<skill-dir>) 기준이어야 한다.
  local hc=0
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    warn ".claude/skills/ 경로 하드코딩: $hit" "<skill-dir>(Base directory) 기준으로 변경"
    hc=$((hc+1))
  done < <(grep -rln 'python3 \.claude/skills/\|bash \.claude/skills/' skills/*/SKILL.md 2>/dev/null)
  [ "$hc" -eq 0 ] && ok "스크립트 호출의 .claude/skills/ 하드코딩 없음"

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
    done < <(grep -rl 'epcc-doctor: shared-copy' skills/*/references skills/*/resources 2>/dev/null | grep "/$base$" | sort)
  done < <(grep -rl 'epcc-doctor: shared-copy' skills/*/references skills/*/resources 2>/dev/null | xargs -I{} basename {} | sort | uniq -d)
  [ "$drift" -eq 0 ] && ok "공유 사본 드리프트 없음"

  # ── 7. 매니페스트 정합 ──
  sec "매니페스트"
  local pv cv
  pv=$(grep -m1 '"version"' package.json 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "?")
  cv=$(grep -m1 '"version"' .claude-plugin/plugin.json 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || echo "?")
  [ "$pv" = "$cv" ] && ok "버전 일치 ($pv)" || bad "버전 불일치: package.json=$pv, plugin.json=$cv"
  [ -f plugin.json ] && bad "루트 plugin.json 중복 존재" "Claude Code는 .claude-plugin/plugin.json만 읽음" \
                     || ok "매니페스트 단일"
  # hooks/hooks.json은 Claude Code가 자동 발견한다. 매니페스트가 같은 파일을 또 가리키면
  # "이미 로드된 파일 중복"으로 플러그인 전체 로드가 거부된다 — claude plugin validate는 이를 잡지 못한다
  if grep -qE '"hooks"[[:space:]]*:[[:space:]]*"(\./)?hooks/hooks\.json"' .claude-plugin/plugin.json 2>/dev/null; then
    bad "매니페스트 hooks가 기본 경로 hooks/hooks.json을 중복 참조" "자동 발견되는 파일이라 플러그인 로드 거부됨 — 해당 줄 삭제"
  else
    ok "매니페스트 hooks 기본 경로 중복 없음"
  fi

  # 스키마의 미구현 필드
  if grep -q 'disabledSkills\|activeSkills' schema/epcc.config.schema.json presets/*.json presets/*/*.json 2>/dev/null; then
    warn "미구현 필드(activeSkills/disabledSkills)가 스키마·프리셋에 존재" \
         "이를 읽어 스킬을 켜고 끄는 코드가 없음. 게이팅은 작동하지 않음"
  else
    ok "미구현 게이팅 필드 없음"
  fi
}

# ════════════════════════════════════════════════════════════════════
# --self-test : 이벤트별 픽스처 주입
# ════════════════════════════════════════════════════════════════════
run_self_test() {
  printf "\n${C_D}epcc doctor --self-test${C_0}\n"
  sec "훅 픽스처 주입"

  local fx="scripts/fixtures"
  [ -d "$fx" ] || { bad "픽스처 디렉토리 없음: $fx"; return; }

  local hooks_json="hooks/hooks.json"
  command -v jq >/dev/null 2>&1 || { bad "jq 필요"; return; }

  local total=0 good=0
  # 이벤트 → 스크립트 매핑을 hooks.json에서 읽어 각 이벤트 픽스처로 실행
  while IFS=$'\t' read -r event cmd; do
    [ -z "$cmd" ] && continue
    local f; f=$(printf '%s' "$cmd" | grep -oE 'scripts/[a-z0-9./-]+\.sh' | head -1)
    [ -n "$f" ] && [ -f "$f" ] || continue
    total=$((total+1))

    local fixture="$fx/${event}.json"
    [ -f "$fixture" ] || fixture="$fx/default.json"
    [ -f "$fixture" ] || { bad "$(basename "$f") [$event]: 픽스처 없음"; continue; }

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

  # ── 양성 픽스처 (B-7): '살아있다'가 아니라 '막는다'를 증명 ──
  # 무해 픽스처는 exit 0만 확인한다. 차단돼야 할 입력이 실제로 exit 2로
  # 차단되는지는 별도 증명이 필요하다 (v2 교훈: 살아있음 ≠ 작동함).
  sec "양성 픽스처 (차단 검증)"
  local blockfx="$fx/PreToolUse-block.json"
  if [ -f "$blockfx" ] && [ -f scripts/security-check.sh ]; then
    local bcode=0
    CLAUDE_PROJECT_DIR="$ROOT" bash scripts/security-check.sh < "$blockfx" >/dev/null 2>&1 || bcode=$?
    if [ "$bcode" -eq 2 ]; then
      ok "security-check: 시크릿 주입 → exit 2 (차단 확인)"
    else
      bad "security-check: 시크릿 주입에 exit $bcode" "차단 훅이 잡아야 할 것을 잡지 못함 — 미탐"
    fi
  else
    warn "양성 픽스처 없음 ($blockfx)" "차단 능력이 증명되지 않은 상태"
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
    jq -e --arg n "$id" '.nodes[] | select(.id==$n) | .entry == true' "$g" >/dev/null 2>&1 && continue
    jq -e --arg n "$id" '[.edges[]? | select(.to==$n)] | length > 0' "$g" >/dev/null 2>&1 \
      || { bad "인바운드 엣지 없는 노드: $id" "도달 불가 자산 (§1.3과 같은 병)"; unreach=$((unreach+1)); }
  done < <(printf '%s\n' "$ids")
  [ "$unreach" -eq 0 ] && ok "도달 불가 노드 없음"

  # 에러 엣지 선언 여부 (G4)
  local noerr=0
  while IFS= read -r id; do
    [ -z "$id" ] && continue
    jq -e --arg n "$id" '.nodes[] | select(.id==$n) | (.on_error // empty) | length > 0' "$g" >/dev/null 2>&1 \
      || noerr=$((noerr+1))
  done < <(jq -r '.nodes[]? | select(.kind=="agent" or .kind=="stage") | .id' "$g" 2>/dev/null)
  [ "$noerr" -gt 0 ] && warn "에러 엣지 미선언 노드 ${noerr}개" "실패 경로가 그래프에 없으면 실패는 조용히 사라진다 (G4)" \
                     || ok "모든 실행 노드가 에러 엣지 선언"
}

# ════════════════════════════════════════════════════════════════════
# --usage : 계측
# ════════════════════════════════════════════════════════════════════
run_usage() {
  printf "\n${C_D}epcc doctor --usage${C_0}  (project: %s)\n" "$PROJ"
  local d="$PROJ/.claude/.epcc"

  sec "훅 하트비트"
  if [ -f "$d/hookrun.log" ]; then
    local expected; expected=$(command -v jq >/dev/null 2>&1 && jq -r '[.hooks|to_entries[].value[]?.hooks[]?]|length' hooks/hooks.json 2>/dev/null || echo "?")
    printf "  최근 세션 훅 실행:\n"
    awk -F'|' '{c[$1]++; last[$1]=$2} END{for(k in c) printf "    %-24s %4d회  최근 %s\n", k, c[k], last[k]}' "$d/hookrun.log" | sort
    local distinct; distinct=$(awk -F'|' '{print $1}' "$d/hookrun.log" | sort -u | wc -l | tr -d ' ')
    printf "  살아있는 훅: %s/%s\n" "$(num "$distinct")" "$expected"
    local fails; fails=$(awk -F'|' '$4!="0"' "$d/hookrun.log" 2>/dev/null | wc -l | tr -d ' ')
    [ "$(num "$fails")" -gt 0 ] && warn "비정상 종료 ${fails}건" || ok "비정상 종료 없음"
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
      done < <(jq -r '.edges[]? | select(.instrumented == true) | "\(.from)\t\(.to)"' workflow.graph.json 2>/dev/null)
      [ "$dead" -gt 0 ] && warn "계측 엣지 중 미실행 ${dead}개" "주장이 아니라 측정이다"
    fi
  else
    warn "엣지 traversal 로그 없음"
  fi

  sec "스킬 호출"
  if [ -f "$d/skilluse.log" ]; then
    awk -F'|' '{c[$2]++} END{for(k in c) printf "    %-32s %d\n", k, c[k]}' "$d/skilluse.log" | sort -k2 -rn | head -20

    # 계측 기간 내 호출 기록 없는 플러그인 스킬 — 판정이 아니라 관찰 대상 목록.
    # 장기(수개월) 무호출이 지속되는 자산만 폐기 후보로 사용자에게 제안한다.
    local unseen="" un=0 sname
    while IFS= read -r sname; do
      [ -z "$sname" ] && continue
      awk -F'|' '{print $2}' "$d/skilluse.log" 2>/dev/null | grep -qx "$sname" \
        || { un=$((un+1)); unseen="$unseen $sname"; }
    done < <(ls -1 "$PLUGIN_ROOT/skills" 2>/dev/null)
    if [ "$un" -gt 0 ]; then
      printf "    ${C_D}호출 기록 없음 %d개:%s${C_0}\n" "$un" "$unseen"
      printf "    ${C_D}(계측 기간이 짧으면 정상 — 장기 무호출만 폐기 후보)${C_0}\n"
    fi
  else
    warn "스킬 호출 로그 없음" "미사용 스킬 판정은 계측 후에만 (안티골 8)"
  fi
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
    if [ "$(num "$cnt")" -ge "$threshold" ]; then
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
MODE="${1:---default}"
case "$MODE" in
  --fast)      run_fast ;;
  --self-test) run_self_test ;;
  --graph)     run_graph ;;
  --usage)     run_usage ;;
  --lessons)   run_lessons ;;
  --all)       run_fast; run_self_test; run_graph; run_usage; run_lessons ;;
  --default)   run_fast; run_graph ;;
  -h|--help)
    sed -n '2,20p' "$0" | sed 's/^# \?//'
    exit 0 ;;
  *) printf "알 수 없는 옵션: %s (--help 참조)\n" "$MODE" >&2; exit 2 ;;
esac

printf "\n${C_D}────────────────────────────────────────────${C_0}\n"
printf "  통과 %s · ${C_Y}경고 %s${C_0} · ${C_R}실패 %s${C_0}\n\n" "$PASS" "$WARN" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
