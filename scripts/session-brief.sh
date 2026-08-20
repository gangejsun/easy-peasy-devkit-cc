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
  mkdir -p "$EPCC_ROOT/.claude/.epcc" 2>/dev/null || true
  git status --porcelain 2>/dev/null | awk '{print $NF}' | sort \
    > "$EPCC_ROOT/.claude/.epcc/session-baseline.txt" 2>/dev/null || true
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
HB="$EPCC_ROOT/.claude/.epcc/hookrun.log"
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
if [ -f "$HOOKS_JSON" ] && command -v jq >/dev/null 2>&1; then
  EXPECTED=$(epcc_num "$(jq -r '[.hooks|to_entries[].value[]?.hooks[]?]|length' "$HOOKS_JSON" 2>/dev/null)")
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
