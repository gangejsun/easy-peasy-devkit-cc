#!/bin/bash
# scripts/session-brief.sh — SessionStart
#
# 두 가지를 한다:
#   1. T0 운영 계약 출력 (플러그인 소유 → 자동 갱신, 프로젝트가 못 고침)
#   2. 세션 브리핑 — HEAD, 미커밋, 열린 워크스페이스, **훅 생존 현황**
#
# v2의 session-start-validator를 대체한다. 그 훅은 루트를 잘못 계산해
# 정수 비교가 깨진 채 exit 0으로 끝났고, 유일한 생존 출력이 사용자가
# 사용을 금지한 /harness-evaluation 권고였다.
#
# SessionStart는 stdout 평문이 그대로 컨텍스트가 되는 세 이벤트 중 하나다.

INPUT=$(cat 2>/dev/null || printf '{}')
# shellcheck source=lib/common.sh
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/lib/common.sh"
epcc_begin "session-brief" "$INPUT"

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# ── 1. T0 운영 계약 ──────────────────────────────────────────────────
CONTRACT="$PLUGIN_ROOT/templates/operating-contract.md"
if [ -f "$CONTRACT" ]; then
  # HTML 주석 블록 전체를 제거한다 ('^<!--'만 지우면 여러 줄 주석의 본문이 샌다)
  sed '/<!--/,/-->/d' "$CONTRACT" | sed '/./,$!d'
else
  printf '[epcc] 경고: 운영 계약 파일 없음 (%s)\n' "$CONTRACT"
fi

# ── 2. 세션 브리핑 ───────────────────────────────────────────────────
printf '\n## 세션 브리핑\n\n'

cd "$EPCC_ROOT" 2>/dev/null || true

if git rev-parse --git-dir >/dev/null 2>&1; then
  # 커밋 0개(초기화 직후) 리포: git log/rev-parse HEAD가 exit 128 → pipefail+ERR 트랩이
  # 훅 전체를 죽여 브리핑이 통째로 소실된다. HEAD 존재를 먼저 확인한다.
  if git rev-parse -q --verify HEAD >/dev/null 2>&1; then
    HEAD_LINE=$(git log -1 --format='%h %s' 2>/dev/null | cut -c1-72)
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  else
    HEAD_LINE="없음 (첫 커밋 전)"
    BRANCH=$(git branch --show-current 2>/dev/null)
  fi
  DIRTY=$(epcc_num "$(git status --porcelain 2>/dev/null | wc -l)")
  printf -- '- 브랜치 `%s` · HEAD `%s`\n' "${BRANCH:-?}" "${HEAD_LINE:-없음}"
  if [ "$DIRTY" -gt 0 ]; then
    printf -- '- 미커밋 %s개 파일\n' "$DIRTY"
  fi
  # 세션 시작 시점 스냅샷 — build-gate가 "이번 세션에 바뀐 것"을 판별하는 기준
  mkdir -p "$(epcc_state_dir)" 2>/dev/null || true
  git status --porcelain 2>/dev/null | awk '{print $NF}' | sort \
    > "$(epcc_state_dir)/session-baseline.txt" 2>/dev/null || true
fi

# 열린 워크스페이스
if [ -d "$EPCC_ROOT/dev/active" ]; then
  OPEN=$(find "$EPCC_ROOT/dev/active" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -5)
  if [ -n "$OPEN" ]; then
    printf -- '- 열린 작업: '
    printf '%s' "$OPEN" | while IFS= read -r d; do printf '`%s` ' "$(basename "$d")"; done
    printf '\n'
  fi
fi

# ── 3. 훅 생존 현황 (P1: 컴포넌트는 자기를 보증하지 않는다) ──────────
HB="$(epcc_state_dir)/hookrun.log"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ] && command -v jq >/dev/null 2>&1; then
  # 분모는 **고유 스크립트 수**다. 선언 엔트리 수를 쓰면 안 된다 — handoff.sh 하나가
  # PreCompact·SessionEnd 두 이벤트에 걸려 있어 분자(로그의 스크립트명 distinct)가 분모에
  # 도달하는 것이 구조적으로 불가능해진다. 그러면 매 세션 미달을 표시하는 꺼지지 않는
  # 경고가 되고, 무시를 학습시킨다. doctor.sh의 --usage와 같은 식을 쓴다 (평가 v5 · E-14).
  EXPECTED=$(epcc_num "$(jq -r '[.hooks|to_entries[].value[]?.hooks[]?.command
                  | capture("(?<f>[a-z0-9-]+)\\.sh").f] | unique | length' "$HOOKS_JSON" 2>/dev/null)")
  if [ -f "$HB" ]; then
    # 최근 7일 내 실행된 고유 훅 수
    SEEN=$(epcc_num "$(awk -F'|' '{print $1}' "$HB" 2>/dev/null | sort -u | wc -l)")
    FAILED=$(awk -F'|' '$4!="0" {print $1}' "$HB" 2>/dev/null | sort -u | tr '\n' ' ')
    if [ "$SEEN" -lt "$EXPECTED" ]; then
      printf -- '- ⚠️ 훅 생존 %s/%s — 일부 훅이 실행된 적 없음. `bash "%s/scripts/doctor.sh" --self-test` 확인\n' "$SEEN" "$EXPECTED" "$PLUGIN_ROOT"
      epcc_edge "session-start" "doctor"
    else
      printf -- '- 훅 %s/%s 정상\n' "$SEEN" "$EXPECTED"
    fi
    [ -n "$FAILED" ] && printf -- '- ⚠️ 비정상 종료 훅: %s\n' "$FAILED"
  else
    printf -- '- 훅 하트비트 없음 (첫 세션)\n'
  fi
fi

# jq 부재 — 조용히 기능이 준다. 빌드 게이트는 판정 불가로 떨어지고(차단하지 않음)
# doctor --graph는 검증을 생략한다. 사용자가 그 사실을 알아야 설치 여부를 결정할 수 있다.
if ! command -v jq >/dev/null 2>&1; then
  printf -- '- ⚠️ `jq` 미설치 — 빌드 게이트가 판정 불가 상태이고 `doctor --graph`가 생략됩니다 (`brew install jq`)\n'
fi

# ── 3.3 플러그인 갱신 도달 — 단, 스택 전제는 프로젝트가 고정한다 ────
# 프로젝트는 시작 시점의 스택 전제 위에 코드를 쌓는다. 플러그인 팩이 next@16 패턴으로
# 옮겼는데 이 프로젝트가 15라면 갱신본은 낡은 것이 아니라 **이 프로젝트에 대해 틀린**
# 지침이다. 버전 상승은 의존성을 올릴 때 함께 하는 프로젝트의 결정이다.
#
# 그래서 고정하는 것은 "스택 전제"이지 "지침의 정확성"이 아니다:
#   pkgs 메이저 동일 + 팩 버전 상승 → 같은 전제 안의 수정(결함·보안) → 알린다
#   pkgs 메이저 상이                → 전제가 이동했다 → 침묵. 프로젝트가 결정한다
# 근거: 사전 제작 가이드에 권한 상승 취약점이 몇 달간 있었다. 그건 버전 문제가 아니라
# 결함이었고, 같은 스택을 쓰는 프로젝트에 도달하지 않으면 안 된다.
PLUG_VER=$({ grep -m1 -oE '"version"[[:space:]]*:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' \
  "$PLUGIN_ROOT/.claude-plugin/plugin.json" 2>/dev/null || true; } | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)

epcc_majors() {  # stdin: "pkgs=a@1 b@2 ..." → 정렬된 "a@1 b@2"
  grep -oE '[@A-Za-z0-9._/-]+@[0-9]+' 2>/dev/null | sort -u | tr '\n' ' '
}

if [ -n "${PLUG_VER:-}" ]; then
  FIXES=""; PINNED=""
  for AJ in "$EPCC_ROOT"/.claude/skills/*/assembly.json; do
    [ -f "$AJ" ] || continue
    GD=$(dirname "$AJ"); GN=$(basename "$GD")
    PKV=$({ grep -m1 -oE '"packVersion"[[:space:]]*:[[:space:]]*"[0-9.]+"' "$AJ" 2>/dev/null || true; } | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true)
    [ -n "${PKV:-}" ] && [ "$PKV" = "$PLUG_VER" ] && continue     # 최신 — 조용
    PACK=$({ grep -m1 -oE '"pack"[[:space:]]*:[[:space:]]*"[^"]+"' "$AJ" 2>/dev/null || true; } | sed -E 's/.*"([^"]+)"$/\1/')
    PJ="$PLUGIN_ROOT/guides/$PACK/pack.json"
    [ -f "$PJ" ] || continue
    HAVE=$({ grep -m1 -oE 'pkgs=[^>]*' "$GD/SKILL.md" 2>/dev/null || true; } | epcc_majors)
    WANT=$({ grep -oE '"[@A-Za-z0-9._/-]+@[0-9.]+"' "$PJ" 2>/dev/null | tr -d '"' || true; } | epcc_majors)
    if [ -n "$HAVE" ] && [ -n "$WANT" ] && [ "$HAVE" != "$WANT" ]; then
      PINNED="$PINNED $GN"          # 전제 이동 — 프로젝트가 결정한다
    else
      FIXES="$FIXES $GN(v$PKV)"     # 같은 전제 안의 수정 — 도달해야 한다
    fi
  done
  [ -n "$FIXES" ] && printf -- '- 같은 스택 전제의 가이드 수정본이 있습니다 (플러그인 v%s ↔ 설치본%s) — `bash "%s/scripts/install-guide.sh" --frontend <팩> --backend <팩>`\n' \
    "$PLUG_VER" "$FIXES" "$PLUGIN_ROOT"
  [ -n "$PINNED" ] && printf -- '- %s: 플러그인 팩이 다른 스택 메이저로 이동했습니다 — **갱신하지 않습니다**. 의존성을 올릴 때 `/stack-guide-generator`로 함께 옮기세요\n' \
    "$(printf '%s' "$PINNED" | sed 's/^ //')"

  # T1 규칙 카드는 스택 전제가 없다 (코드 변경 규율·되돌림·교훈) — 항상 최신이 옳다
  #
  # **미설치를 먼저 본다.** 아래 드리프트 루프는 .claude/rules/ 를 순회하므로 디렉토리가
  # 비어 있으면 본문이 한 번도 돌지 않고, 그러면 "한 번도 설치되지 않았다"가 조용히
  # 통과한다. install-rules 실행은 epcc-init 스킬의 지시일 뿐 훅이 아니다 — 모델이
  # Step 7을 건너뛰면 규칙은 영영 도달하지 않는다. 그 사실을 아는 것은 여기뿐이다.
  # glob 무매칭 시 ls는 exit 1 — pipefail+ERR 트랩이 훅을 통째로 죽인다.
  # 하필 "규칙이 0장"일 때 죽으므로, 알리려던 바로 그 상황에서 침묵한다. || true 가드 필수.
  RCOUNT=$(epcc_num "$({ ls -1 "$EPCC_ROOT"/.claude/rules/*.md 2>/dev/null || true; } | wc -l)")
  PCOUNT=$(epcc_num "$({ ls -1 "$PLUGIN_ROOT"/rules/*.md 2>/dev/null || true; } | wc -l)")

  # 누락분 자동 설치 — 두 경계를 지킨다:
  #   ⓐ epcc.config.json이 있을 때만. 플러그인은 전역 설치라 이 관문이 없으면 사용자가 여는
  #     모든 저장소에 .claude/rules/ 를 쓰게 된다. config 존재 = 이 프로젝트가 epcc를 쓴다는 표시
  #   ⓑ --missing-only. 있는 파일은 버전도 보지 않는다 — 자동 실행이 사용자 수정본을
  #     조용히 덮어쓰면 안 된다. 갱신은 아래에서 **보고**만 하고 사람이 실행한다
  # 설치를 스킬 지시로만 두면 모델이 Step 7을 건너뛸 때 규범이 영영 도달하지 않는다.
  if [ -f "$EPCC_ROOT/epcc.config.json" ] && [ "$RCOUNT" -lt "$PCOUNT" ]; then
    CLAUDE_PROJECT_DIR="$EPCC_ROOT" bash "$PLUGIN_ROOT/scripts/install-rules.sh" --missing-only --quiet 2>/dev/null || true
    RCOUNT=$(epcc_num "$({ ls -1 "$EPCC_ROOT"/.claude/rules/*.md 2>/dev/null || true; } | wc -l)")
  fi

  # 미설치 경고도 config 관문을 쓴다. 미설정 프로젝트는 §3.5의 /epcc-init 넛지가 이미
  # 담당하므로, 여기서 또 말하면 epcc를 안 쓰는 저장소에 경고가 두 줄 뜬다.
  if [ "$RCOUNT" -eq 0 ] && [ "$PCOUNT" -gt 0 ] && [ -f "$EPCC_ROOT/epcc.config.json" ]; then
    printf -- '- ⚠️ T1 규칙 카드 미설치 (자동 설치도 실패) — `bash "%s/scripts/install-rules.sh"` 직접 실행하세요. 작업 라우팅·되돌림·보안 규범이 세션에 도달하지 않는 상태입니다\n' "$PLUGIN_ROOT"
  else
    RDRIFT=0
    for RC in "$EPCC_ROOT"/.claude/rules/*.md; do
      [ -f "$RC" ] || continue
      SRC="$PLUGIN_ROOT/rules/$(basename "$RC")"; [ -f "$SRC" ] || continue
      SV=$({ grep -m1 -oE 'epcc-rule-version: [0-9.]+' "$SRC" 2>/dev/null || true; } | awk '{print $2}')
      TV=$({ grep -m1 -oE 'epcc-rule-version: [0-9.]+' "$RC"  2>/dev/null || true; } | awk '{print $2}')
      [ -n "${SV:-}" ] && [ -n "${TV:-}" ] && [ "$SV" != "$TV" ] && RDRIFT=$((RDRIFT+1))
    done
    [ "$RDRIFT" -gt 0 ] && printf -- '- T1 규칙 카드 %s개가 구버전 — `bash "%s/scripts/install-rules.sh"` 재실행\n' "$RDRIFT" "$PLUGIN_ROOT"
    # 플러그인에 새 카드가 생겼는데 프로젝트에 없는 경우 (드리프트 루프는 못 잡는다).
    # config 관문 필수 — 없으면 epcc를 쓰지 않는 저장소에 "0/8장" 경고가 뜬다.
    [ "$RCOUNT" -lt "$PCOUNT" ] && [ -f "$EPCC_ROOT/epcc.config.json" ] \
      && printf -- '- T1 규칙 카드 %s/%s장만 설치됨 — `bash "%s/scripts/install-rules.sh"` 재실행\n' "$RCOUNT" "$PCOUNT" "$PLUGIN_ROOT"
  fi
fi

# ── 3.4 미완 가이드 작업 (세션이 죽어도 20분이 사라지지 않게) ────────
# 가이드 생성은 init의 임계 경로 밖에서 돈다. 세션이 끊기면 그 사실을 아는 것이
# 이 훅뿐이므로, 여기서 알리지 않으면 작업은 조용히 유실된다.
GJ="$EPCC_ROOT/.epcc/guide-job.json"
if [ -f "$GJ" ]; then
  GJ_STATUS=$({ grep -oE '"status"[[:space:]]*:[[:space:]]*"[a-z]+"' "$GJ" 2>/dev/null || true; } | sed -E 's/.*"([a-z]+)"$/\1/')
  GJ_COMBO=$({ grep -oE '"combo"[[:space:]]*:[[:space:]]*"[^"]*"' "$GJ" 2>/dev/null || true; } | sed -E 's/.*"([^"]*)"$/\1/')
  case "${GJ_STATUS:-}" in
    pending|running|interrupted)
      printf -- '- 가이드 생성 미완 (`%s`, 상태 %s) — `/stack-guide-generator`로 이어서 만듭니다\n' \
        "${GJ_COMBO:-?}" "$GJ_STATUS"
      epcc_edge "session-start" "stack-guide-generator" ;;
    failed)
      printf -- '- ⚠️ 가이드 생성 실패 (`%s`) — `.epcc/guide-job.json`의 사유 확인 후 `/stack-guide-generator` 재시도\n' \
        "${GJ_COMBO:-?}" ;;
  esac
fi

# ── 3.5 미설정 프로젝트 넛지 (설치 후 가장 이른 대화형 접점) ─────────
if [ ! -f "$EPCC_ROOT/epcc.config.json" ]; then
  printf -- '- 미설정 프로젝트 — `/epcc-init`로 기술 스택(백엔드·DB 포함)을 선택하면 스택 맞춤 가이드가 생성됩니다\n'
fi

# ── 3.6 자기검증 진입점 (소비자 프로젝트에는 scripts/가 없다 — 절대 경로가 유일한 진실) ──
printf -- '- 자기검증: `bash "%s/scripts/doctor.sh"`\n' "$PLUGIN_ROOT"

# ── 4. 교훈 승격 후보 (임계 도달 시에만) ─────────────────────────────
LF="$EPCC_ROOT/docs/lessons.md"
if [ -f "$LF" ]; then
  # grep은 무매칭 시 exit 1 — pipefail+ERR 트랩이 훅을 죽이지 않도록 || true 가드
  CAND=$({ grep -oE '\[category: [^]]+\]' "$LF" 2>/dev/null || true; } \
    | sed 's/\[category: //;s/\]//' | sort | uniq -c | sort -rn \
    | awk '$1>=3 {printf "%s(%s) ", $2, $1}')
  [ -n "$CAND" ] && printf -- '- 교훈 승격 후보: %s→ `bash "%s/scripts/doctor.sh" --lessons`\n' "$CAND" "$PLUGIN_ROOT"
  RCAND=$({ grep -oE '\[request: [^]]+\]' "$LF" 2>/dev/null || true; } \
    | sed 's/\[request: //;s/\]//' | sort | uniq -c | sort -rn \
    | awk '$1>=3 {printf "%s(%s) ", $2, $1}')
  [ -n "$RCAND" ] && printf -- '- 반복 요청 자동화 후보: %s→ 스킬 승격 검토 (`--lessons`)\n' "$RCAND"
fi

# ── 5. 외부 변화 점검 경과 (자가-진화 루프의 탐색 단계) ──────────────
# 스탬프 파일을 따로 두지 않는다 — harness-evaluation 리포트 파일명이 원장이고,
# 최신 리포트의 mtime이 곧 마지막 점검 시점이다.
LATEST_HE=$({ ls -t "$EPCC_ROOT"/dev/docs/harness-evaluation/*.md 2>/dev/null || true; } | head -1)
if [ -n "$LATEST_HE" ]; then
  HE_MTIME=$(epcc_num "$(stat -f %m "$LATEST_HE" 2>/dev/null || stat -c %Y "$LATEST_HE" 2>/dev/null || true)")
  NOW_TS=$(epcc_num "$(date +%s)")
  if [ "$HE_MTIME" -gt 0 ] && [ "$NOW_TS" -gt "$HE_MTIME" ]; then
    HE_AGE=$(( (NOW_TS - HE_MTIME) / 86400 ))
    if [ "$HE_AGE" -ge 30 ]; then
      printf -- '- 마지막 하네스 평가 후 %s일 경과 — 외부 변화(네이티브 기능·모델) 점검용 `/harness-evaluation` 권장\n' "$HE_AGE"
      epcc_edge "session-start" "harness-evaluation"
    fi
  fi
fi

exit 0
