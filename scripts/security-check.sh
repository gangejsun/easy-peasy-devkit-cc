#!/bin/bash
# scripts/security-check.sh — PreToolUse (Edit|Write)
#
# 명백한 시크릿 하드코딩을 차단하는 최후 방어선.
#
# v2에서 11개 훅 중 **유일하게 작동한 훅**이다. 이유는 명확하다 —
# 경로를 몰라도 되기 때문에 잘못된 루트 계산의 영향을 받지 않았다.
# v3에서도 그 성질을 유지한다: 판정에 프로젝트 루트가 필요 없다.
#
# 정확한 패턴만 쓴다. false positive가 나면 사용자가 훅을 꺼버리고,
# 그러면 차단력은 0이 된다.

INPUT=$(cat 2>/dev/null || printf '{}')
# shellcheck source=lib/common.sh
source "${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}/scripts/lib/common.sh"

# 루트 해석 실패가 보안 검사를 막으면 안 된다 — 하트비트만 best-effort
EPCC_HOOK_NAME="security-check"
EPCC_ROOT="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || printf '')}"
[ -n "$EPCC_ROOT" ] && epcc_heartbeat 0

TOOL_NAME=$(epcc_field "$INPUT" '.tool_name')
FILE_PATH=$(epcc_field "$INPUT" '.tool_input.file_path')
CONTENT=$(epcc_field "$INPUT" '.tool_input.content')
NEW_STRING=$(epcc_field "$INPUT" '.tool_input.new_string')

# 이 훅 자신을 다룰 때는 자기 참조 회피 (패턴 문자열 자체가 매칭된다)
[[ "$FILE_PATH" =~ security-check\.sh$ ]] && exit 0

# ══════════════════════════════════════════════════════════════════════
# UI 방향 심사 소환 (차단하지 않는다)
# ══════════════════════════════════════════════════════════════════════
#
# 시크릿·파괴 게이트와 **축이 다르다.** 저 둘은 "지금 일어나면 안 되는 일"을 막고,
# 이것은 "지금이 아니면 못 하는 판단"을 소환한다.
#
# T1 카드 `.claude/rules/ui-design.md`는 Claude가 **매칭 파일을 읽을 때** 로드된다.
# 기존 UI를 고칠 때는 이웃을 읽으므로 뜬다. 그런데 읽을 것이 없는 그린필드 —
# 첫 화면을 새로 만드는 순간 — 에는 안 뜬다. 방향 결정이 가장 중요한 그 한 자리가
# 비어 있고, 이 브랜치가 그것만 메운다.
#
# **차단하지 않는다.** 심사를 실제로 했는지는 기계가 판정할 수 없고, 판정 불가는
# 차단하지 않는다 (harness-change 「차단 장치는 3상태다」).
#
# 조건을 셋으로 좁힌다. 매 편집마다 울면 사용자가 훅을 꺼버리고, 꺼진 훅의 도달력은 0이다:
#   ① Write만 — Edit·MultiEdit는 제외한다. 기존 파일 수정은 방향 결정이 아니다
#   ② UI 파일 확장자 — 디렉토리로 판정하면 `app/`이 FastAPI 백엔드까지 끌어온다
#   ③ 신규 생성만 — 덮어쓰기는 이미 방향이 있는 파일이다
# 테스트·스토리 파일은 뺀다: 확장자는 같지만 방향을 정하는 자리가 아니다.
#
# jq가 없으면 epcc_emit_context는 조용히 아무것도 내지 않는다. 알림이지 차단이
# 아니므로 그 저하는 받아들인다 — 없는 jq 때문에 보안 검사를 멈추지는 않는다.
if [ "$TOOL_NAME" = "Write" ] \
   && [[ "$FILE_PATH" =~ \.(tsx|jsx|vue|svelte|css|scss)$ ]] \
   && [[ ! "$FILE_PATH" =~ \.(test|spec|stories)\. ]] \
   && [ ! -f "$FILE_PATH" ]; then
  epcc_emit_context PreToolUse \
'새 UI 파일이다. 방향을 정하는 중이라면 `.claude/rules/ui-design.md`의 심사를 먼저 통과시킨다 — 기본값 3군집 회피 · 시그니처 요소 하나 · 2패스 심사. 이미 정해진 방향을 따르는 중이면 그대로 진행한다.'
fi

# ══════════════════════════════════════════════════════════════════════
# 파괴적 명령 게이트
# ══════════════════════════════════════════════════════════════════════
#
# 시크릿 검사와 **축이 다르다.** 시크릿은 "값이 잘못된 쪽에 있다"를 보고,
# 이 게이트는 "되돌릴 수 없는 일이 지금 일어나려 한다"를 본다.
# 되돌림 분류(T0)는 **편집 경로**로 판정하므로 `DROP TABLE`처럼 파일을 하나도
# 건드리지 않는 파괴는 원리적으로 잡지 못한다 — 그 사각지대가 여기다.
#
# 차단(exit 2)은 **되돌림이 사실상 불가능한 것만**이다. `rm -rf`·`reset --hard`·
# `clean -fdx`는 경고에 둔다: 오탐은 사용자가 훅을 꺼버리게 만들고, 꺼진 훅의
# 차단력은 0이다. 같은 항목에서 오탐이 2건 이상 나오면 규칙을 넓히지 말고
# **조건을 좁히거나 그 항목을 경고로 내린다** (rules/lessons.md의 false-positive 규율).
#
# **3상태다.** 강제 푸시의 대상 브랜치를 판정할 수 없으면(저장소 밖·detached·커밋 0개)
# 차단하지 않고 「판정 불가」를 명시 보고한 뒤 통과시킨다.
#
# 알려진 한계 — `cat x.sql | psql`처럼 파괴 구문이 **파일 안에** 있으면 명령 문자열에
# 나타나지 않아 잡히지 않는다. 훅은 흔한 경로를 막을 뿐이고, 나머지는 되돌림 분류와
# 사용자 확인이 담당한다. 이 한계를 넓히려 정규식을 키우면 오탐이 먼저 커진다.

dblock() {   # $1 무엇  $2 영향  $3 안전한 대안
  printf '❌ 차단: %s\n\n' "$1" >&2
  printf '영향: %s\n' "$2" >&2
  printf '안전한 대안: %s\n\n' "$3" >&2
  printf '이 명령이 정말 필요하면 영향과 롤백 절차를 사용자에게 먼저 제시하고 확인을 받으세요.\n' >&2
  exit 2
}
dwarn() { printf '⚠️  %s\n     %s\n' "$1" "$2" >&2; }

# 명령의 첫 토큰 (선행 환경변수 대입은 건너뛴다)
_first_tok() {
  printf '%s' "$1" | sed -E 's/^[[:space:]]*//; s/^([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*//' | awk '{print $1; exit}'
}

# 조사·검색 명령인가. `grep 'DROP TABLE' supabase/migrations/`를 막으면 그것이 바로 오탐이다.
#
# 판정 순서가 중요하다. "명령 어딘가에 psql/supabase가 있으면 읽기가 아니다"로 먼저
# 걸러면 **경로에 들어있는 이름**(`supabase/migrations/`)이 클라이언트로 오인된다.
# 그래서 첫 토큰으로 먼저 읽기를 확정하고, **파이프 뒤 명령 위치**에 클라이언트가
# 올 때만(`cat x.sql | psql`) 읽기 판정을 뒤집는다.
_readonly_cmd() {
  case "$(_first_tok "$1")" in
    grep|egrep|fgrep|rg|ag|cat|head|tail|less|more|ls|find|wc|awk|diff|jq|file|stat|which|echo|printf) ;;
    git) printf '%s' "$1" | grep -Eq '^[[:space:]]*git[[:space:]]+(log|diff|show|grep|blame|status|branch|remote|config|rev-parse|describe|ls-files)([^a-zA-Z-]|$)' || return 1 ;;
    *) return 1 ;;
  esac
  # 읽기 명령이 파괴적 실행기로 흘러들어가는가 — 그때는 읽기가 아니다
  printf '%s' "$1" | grep -Eqi '[|;&][[:space:]]*(sudo[[:space:]]+)?(npx[[:space:]]+)?(psql|mysql|mariadb|sqlite3|mongosh?|supabase|prisma|drizzle-kit|alembic|sqlcmd)([[:space:]]|$)' && return 1
  return 0
}

# 파일에 텍스트를 **쓰는** 명령은 파괴의 실행이 아니다.
# `cat > 0003_drop_legacy.sql <<'EOF' ... EOF`는 마이그레이션을 **작성**하는 것이지
# 실행하는 것이 아니고, 픽스처·문서·테스트를 쓸 때도 같은 문자열이 나온다.
# (시크릿 검사는 반대 방향이다 — 시크릿은 쓰는 행위 자체가 노출이므로 그 경로는 계속 본다.
#  실제로 이 게이트를 만들 때 자기 픽스처 작성 명령이 막혔다. 그게 이 함수가 생긴 이유다.)
# 힙독만으로 판정하지 않는다: `psql <<'SQL'`은 힙독이지만 실행이다.
_authoring_cmd() {
  case "$(_first_tok "$1")" in
    cat|tee|printf|echo) printf '%s' "$1" | grep -Eq '(>|<<)' && return 0 ;;
  esac
  return 1
}

destructive_gate() {
  local DCMD="$1" target=""
  dhas() { printf '%s' "$DCMD" | grep -Eqi -e "$1"; }

  # ── 데이터 파괴 (SQL·마이그레이션 도구) ────────────────────────────
  # 조사 명령도 작성 명령도 아닌 것 = 실행하려는 것
  if ! _readonly_cmd "$DCMD" && ! _authoring_cmd "$DCMD"; then

    dhas '(^|[^a-z_])drop[[:space:]]+(table|database|schema)([^a-z_]|$)' \
      && dblock "DDL로 테이블/데이터베이스/스키마 삭제" \
                "해당 객체와 그 안의 모든 행이 사라집니다. 백업 없이는 복구 불가입니다" \
                "먼저 백업(pg_dump 등)을 뜨고, 트랜잭션 안에서 실행해 결과를 확인한 뒤 커밋하세요"

    # coreutils `truncate -s 0 file`은 대시가 있어 걸리지 않는다
    dhas '(^|[^a-z_])truncate[[:space:]]+(table[[:space:]]+)?["a-z_]' \
      && dblock "TRUNCATE — 테이블 전체 비우기" \
                "모든 행이 삭제되고 대개 롤백·복구가 불가능합니다 (트리거도 건너뜁니다)" \
                "DELETE ... WHERE 로 범위를 좁히거나, 백업 후 실행하세요"

    # WHERE 없는 DELETE — 테이블명 뒤가 바로 `;` 또는 끝일 때만 (WHERE가 있으면 매칭 안 됨)
    dhas '(^|[^a-z_])delete[[:space:]]+from[[:space:]]+["a-z_][a-z0-9_."]*[[:space:]]*(;|$)' \
      && dblock "WHERE 없는 DELETE FROM" \
                "대상 테이블의 모든 행이 삭제됩니다" \
                "WHERE 절로 범위를 좁히고, 먼저 같은 조건의 SELECT COUNT(*)로 영향 행 수를 확인하세요"

    dhas 'supabase[[:space:]]+db[[:space:]]+reset' \
      && dblock "supabase db reset — 로컬 DB 초기화" \
                "스키마와 데이터가 전부 삭제되고 마이그레이션이 처음부터 재적용됩니다. 시드 밖의 데이터는 사라집니다" \
                "특정 마이그레이션만 되돌리려면 되돌림 마이그레이션을 새로 작성하세요"

    dhas 'prisma[[:space:]]+migrate[[:space:]]+reset|prisma[[:space:]]+db[[:space:]]+push[^|;&]*--force-reset' \
      && dblock "prisma 스키마 초기화" \
                "데이터베이스를 드롭하고 다시 만듭니다. 기존 데이터는 전부 사라집니다" \
                "prisma migrate dev 로 증분 마이그레이션을 만드세요"

    dhas 'alembic[[:space:]]+downgrade[[:space:]]+base|drizzle-kit[[:space:]]+drop' \
      && dblock "마이그레이션 전량 되돌리기" \
                "모든 마이그레이션이 역적용되어 스키마와 데이터가 사라집니다" \
                "되돌릴 리비전을 하나만 지정하세요 (alembic downgrade -1)"

    # WHERE 없는 UPDATE는 되돌릴 수는 있으나 조용히 전 행을 바꾼다 — 경고
    dhas '(^|[^a-z_])update[[:space:]]+["a-z_][a-z0-9_."]*[[:space:]]+set[^;]*(;|$)' \
      && ! dhas '(^|[^a-z_])where([^a-z_]|$)' \
      && dwarn "WHERE 없는 UPDATE — 테이블 전 행이 바뀝니다" "WHERE 절로 범위를 좁혔는지 확인하세요"
  fi

  # ── git 히스토리 파괴 ──────────────────────────────────────────────
  dhas 'git[[:space:]]+filter-branch|git[[:space:]]+filter-repo|git[[:space:]]+push[^|;&]*--mirror' \
    && dblock "git 히스토리 재작성/미러 푸시" \
              "모든 커밋 해시가 바뀌어 다른 사람의 클론이 전부 어긋납니다. 원격 히스토리는 되돌릴 수 없습니다" \
              "재작성이 정말 필요하면 팀에 먼저 공지하고, 백업 브랜치와 태그를 남긴 뒤 진행하세요"

  # ── 강제 푸시 — 대상 브랜치로 판정한다 (3상태) ─────────────────────
  if dhas 'git[[:space:]]+push' && dhas '(--force([^-]|$)|[[:space:]]-f([[:space:]]|$))' && ! dhas '--force-with-lease'; then
    # 명시 refspec의 마지막 비플래그 토큰을 대상으로 본다
    target=$(printf '%s' "$DCMD" | tr ';|&' '\n' | grep -E 'git[[:space:]]+push' | head -1 \
             | awk '{n=0; for(i=1;i<=NF;i++) if($i !~ /^-/) t[++n]=$i; if(n>=4) print t[n]}')
    target="${target##*:}"
    # refspec이 없으면 현재 브랜치다. 커밋 0개 저장소에서 rev-parse가 exit 128로
    # 죽지 않게 HEAD 존재를 먼저 확인한다 — 없으면 판정 불가로 남긴다.
    if [ -z "$target" ] && git rev-parse -q --verify HEAD >/dev/null 2>&1; then
      target=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf '')
    fi
    case "$target" in
      main|master|develop|development|release|release/*|prod|production|stage|staging)
        dblock "공유 브랜치에 강제 푸시 ($target)" \
               "원격 히스토리를 덮어써 다른 사람이 푸시한 커밋이 사라질 수 있습니다. 복구하려면 그 사람의 로컬 사본이 필요합니다" \
               "git push --force-with-lease — 남의 커밋이 있으면 거부됩니다. 이미 공개된 커밋은 revert로 되돌리세요" ;;
      ""|HEAD)
        printf '⚠️  판정 불가: 강제 푸시의 대상 브랜치를 확인할 수 없습니다\n' >&2
        printf '     (저장소 밖 · detached HEAD · 커밋 0개). 차단하지 않고 통과시킵니다 —\n' >&2
        printf '     대상이 공유 브랜치인지 직접 확인하고, --force-with-lease를 쓰세요.\n' >&2 ;;
      *)
        dwarn "기능 브랜치 강제 푸시 ($target)" "공유 중인 브랜치면 --force-with-lease를 쓰세요" ;;
    esac
  fi

  # ── 되돌릴 수 있으나 조용히 잃는 것들 — 경고만 ─────────────────────
  if dhas '(^|[^a-z_])rm[[:space:]]+(-[a-zA-Z]*[rR][a-zA-Z]*[[:space:]]+)*-?[a-zA-Z]*[fF]' \
     && ! dhas '(node_modules|/dist|/build|\.next|\.turbo|\.cache|/tmp/|coverage)'; then
    dwarn "rm -rf — 삭제된 파일은 휴지통을 거치지 않습니다" "대상 경로를 다시 확인하세요. 추적 중인 파일이면 git으로 되돌릴 수 있는지 먼저 보세요"
  fi
  dhas 'git[[:space:]]+reset[^|;&]*--hard' \
    && dwarn "git reset --hard — 미커밋 변경이 사라집니다" "먼저 git stash 또는 git diff > patch 로 남기세요"
  dhas 'git[[:space:]]+clean[^|;&]*-[a-z]*[fd]' \
    && dwarn "git clean — 추적되지 않는 파일이 삭제됩니다" "git clean -n 으로 대상을 먼저 확인하세요"

  return 0
}

# 모델이 파일을 쓰는 경로는 Edit/Write만이 아니다. Bash 힙독·리다이렉션으로 쓰면
# 매처가 Edit|Write|MultiEdit뿐일 때 시크릿 차단이 **0**이 된다 — 게이트의 실효
# 커버리지가 도구 선택에 좌우된다 (평가 v5 · E-20).
# 엣지는 **판정 전에** 남긴다. 아래 block()들 뒤에 두었더니 차단이 발생한 순간
# 그 줄에 도달하지 못해, --usage의 traversal이 성공 경로만 셌다 —
# 훅이 존재하는 이유인 사건이 계측에서 가장 안 보였다 (하트비트와 같은 규율).
[ -n "$EPCC_ROOT" ] && epcc_edge "build" "security-check"

case "$TOOL_NAME" in
  Edit|Write|MultiEdit)
    TEXT="${CONTENT}${NEW_STRING}"
    ;;
  Bash)
    CMD=$(epcc_field "$INPUT" '.tool_input.command')
    # 자기 참조 회피 — 이 훅과 doctor는 패턴 문자열 자체를 본문에 갖고 있다
    case "$CMD" in *security-check.sh*|*doctor.sh*) exit 0 ;; esac

    # 파괴적 명령은 **파일을 쓰지 않아도** 되돌릴 수 없다. 아래 쓰기 필터보다 먼저 본다.
    destructive_gate "$CMD"
    # **파일을 쓰는 명령만** 본다. 읽기 명령까지 스캔하면 조사·검사 명령
    # (`grep 'AKIA[0-9A-Z]{16}' ...`)이 오탐으로 막히고, 오탐은 사용자가 훅을
    # 꺼버리게 만들며 꺼진 훅의 차단력은 0이다.
    printf '%s' "$CMD" | grep -Eq '(^|[^0-9A-Za-z_])(tee|dd)([^0-9A-Za-z_]|$)|>' || exit 0
    TEXT="$CMD"
    ;;
  *) exit 0 ;;
esac
[ -z "$TEXT" ] && exit 0

block() {
  printf '❌ 차단: %s\n\n' "$1" >&2
  printf '%s\n\n' "$2" >&2
  # 안내는 **실제로 가능한 경로**를 가리켜야 한다. 예전 문구는 ".env.local로 옮기라"고
  # 했는데 정작 그 파일 쓰기도 막혀 있어서, 유일하게 불가능한 곳을 가리키고 있었다.
  if [ "${ENV_NOT_IGNORED:-0}" = "1" ]; then
    printf '이 파일은 .gitignore에 없습니다 — 먼저 추가하세요. 그러면 여기에 쓸 수 있습니다.\n' >&2
  else
    printf '올바른 방법: .gitignore된 .env 파일로 옮기세요 (거기에는 쓸 수 있습니다).\n' >&2
  fi
  exit 2
}
warn() { printf '⚠️  %s\n%s\n' "$1" "$2" >&2; }

# -e 필수: PEM 헤더처럼 '-'로 시작하는 패턴을 grep이 옵션으로 오해한다
has()  { printf '%s' "$TEXT" | grep -Eq  -e "$1"; }
hasi() { printf '%s' "$TEXT" | grep -Eqi -e "$1"; }

# ── .env 면제 — 증명된 경우에만 ──────────────────────────────────────
#
# 시크릿의 **정당한 목적지**는 gitignore된 .env 파일이다. 그런데 이 훅에는 경로
# 조건이 package.json 하나뿐이라 거기에 쓰는 것까지 막고 있었다 — 차단 메시지가
# ".env.local로 옮기라"고 안내하면서 정작 그 파일 쓰기를 막는 모순이었고,
# "키를 환경 변수에 등록해줘"라는 **가장 흔한 정상 작업**이 불가능했다.
#
# **면제는 증명된 경우에만 준다.** 판정 불가(git 없음 · 저장소 밖 · 미추적)면
# 면제하지 않고 아래 검사로 내려가므로 오늘의 동작이 그대로 유지된다 —
# 이 완화는 어떤 경우에도 오늘보다 나빠지지 않고, 증명될 때만 열린다.
# 그래서 「판정 불가를 차단으로 접지 않는다」와 충돌하지 않는다: 새로 차단하는 것이
# 아니라 **새 예외를 주지 않는** 것이고, 기존 차단은 그대로다.
#
# `.gitignore`를 텍스트로 훑지 않는다 — 중첩 .gitignore · 부정 패턴(`!`) · 전역
# exclude를 놓친다. `git check-ignore`가 권위 있는 답을 갖고 있다.
# 파일이 있는 디렉토리로 이동해 basename을 묻는다: file_path가 절대·상대 어느
# 쪽이어도 같은 결과가 나오고, git이 상위 .gitignore 계층을 스스로 해석한다.
#
# **Bash 힙독(`cat > .env.local <<EOF`)은 면제하지 않는다.** 그 경로는 file_path가
# 비어 있고, 셸 명령 문자열에서 대상 경로를 신뢰성 있게 파싱할 수 없다.
# (같은 한계를 destructive_gate도 갖는다 — 위 「파일 안의 파괴 구문」 주석 참조.)
case "$TOOL_NAME" in
  Edit|Write|MultiEdit)
    if [[ "$(basename -- "$FILE_PATH")" =~ ^\.env(\..+)?$ ]]; then
      if ( cd "$(dirname -- "$FILE_PATH")" 2>/dev/null \
           && git check-ignore -q -- "$(basename -- "$FILE_PATH")" 2>/dev/null ); then
        printf '🔐 시크릿을 %s 에 기록합니다 — .gitignore로 무시되는 파일이라 커밋되지 않습니다.\n' "$FILE_PATH" >&2
        exit 0
      fi
      # 무시되지 않거나 판정 불가. 면제 없이 아래 검사로 내려가되, block()의 안내가
      # ".gitignore에 추가하라"로 갈라지도록 표시만 남긴다.
      ENV_NOT_IGNORED=1
    fi
    ;;
esac

# ── 차단 대상: 명백한 시크릿 ─────────────────────────────────────────

has 'AKIA[0-9A-Z]{16}' \
  && block "AWS Access Key ID 하드코딩" "패턴: AKIA + 16자 대문자/숫자"

has 'ghp_[a-zA-Z0-9]{36}' \
  && block "GitHub Personal Access Token 하드코딩" "패턴: ghp_ + 36자"

has 'gh[pousr]_[A-Za-z0-9]{36,}' \
  && block "GitHub 토큰 하드코딩" "패턴: gho_/ghu_/ghs_/ghr_"

has 'sk_(live|test)_[a-zA-Z0-9]{24,}' \
  && block "Stripe Secret Key 하드코딩" "패턴: sk_live_ 또는 sk_test_"

has '(test|live)_sk_[a-zA-Z0-9]{20,}' \
  && block "토스페이먼츠 Secret Key 하드코딩" "패턴: test_sk_ 또는 live_sk_"

# 카카오페이 — 룰에 명시된 시크릿인데 v2 검사에 누락되어 있었다
hasi 'kakao.{0,20}(secret_?key|admin_?key)[[:space:]]*[:=][[:space:]]*['"'"'"][^'"'"'"]{16,}' \
  && block "카카오페이 시크릿 하드코딩" "secretKey/adminKey는 서버 환경 변수로만"

has 'sk-proj-[a-zA-Z0-9_-]{20,}' \
  && block "OpenAI API Key 하드코딩" "패턴: sk-proj-"

has 'sk-ant-[a-zA-Z0-9_-]{20,}' \
  && block "Anthropic API Key 하드코딩" "패턴: sk-ant-"

has 'AIza[0-9A-Za-z_-]{35}' \
  && block "Google API Key 하드코딩" "패턴: AIza + 35자"

# Supabase 신형 키 체계 (sb_secret_ / sb_publishable_)
has 'sb_secret_[a-zA-Z0-9_-]{20,}' \
  && block "Supabase Secret Key 하드코딩" "sb_secret_ 키는 서버 전용. 절대 클라이언트 노출 금지"

# Supabase 레거시 JWT 키
if has 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[a-zA-Z0-9_-]{40,}\.[a-zA-Z0-9_-]+'; then
  if hasi 'service_?role'; then
    block "Supabase Service Role Key 하드코딩" "service_role은 RLS를 우회합니다. 절대 클라이언트 노출 금지"
  elif ! hasi 'anon|publishable'; then
    block "Supabase JWT 키 하드코딩 의심" "service_role일 가능성. anon이면 NEXT_PUBLIC_ 환경변수 사용"
  else
    warn "Supabase Anon Key 감지" "공개 가능하지만 환경 변수 사용을 권장합니다"
  fi
fi

# has()가 이미 grep -e 를 쓰므로 호출부에 '--'를 붙이면 안 된다.
# 붙이면 '--'가 패턴 인자가 되어 '--'를 포함한 모든 코드(i--, count--)가 오차단된다.
has '-----BEGIN[[:space:]]+(RSA|EC|DSA|OPENSSH|PGP)?[[:space:]]*PRIVATE KEY-----' \
  && block "Private Key 하드코딩" "PEM 형식 개인키"

if has '"type"[[:space:]]*:[[:space:]]*"service_account"' && has '"private_key"[[:space:]]*:'; then
  block "GCP Service Account JSON 하드코딩" "GOOGLE_APPLICATION_CREDENTIALS 경로 지정 사용"
fi

# package.json에 시크릿
if [[ "$FILE_PATH" =~ package\.json$ ]] && has '(AKIA|ghp_|sk_live_|sk_test_|sb_secret_)'; then
  block "package.json에 시크릿 포함" "npm run 시 노출됩니다"
fi

# ── 경고 대상 (차단하지 않음) ────────────────────────────────────────

# API Route / Server Action의 입력 검증 누락
if [ "$TOOL_NAME" = "Write" ] \
   && [[ "$FILE_PATH" =~ (api/.+\.(ts|js)|/actions\.(ts|js))$ ]] \
   && ! has "(from ['\"]zod['\"]|z\.(object|string|number|array|enum|union))" \
   && ! has "(valibot|yup|joi|superstruct|arktype|typia)"; then
  warn "API Route/Server Action에 스키마 검증 미감지: $FILE_PATH" \
       "모든 외부 입력은 스키마로 검증하세요 (zod 등)"
fi

# XSS — dangerouslySetInnerHTML은 sanitize 동반 없이는 경고 (차단하지 않음:
# 같은 파일의 기존 sanitize import는 이 diff에 안 보일 수 있다)
if has 'dangerouslySetInnerHTML' && ! hasi 'dompurify|sanitize'; then
  warn "dangerouslySetInnerHTML 감지: $FILE_PATH" \
       "DOMPurify 등으로 sanitize하거나 텍스트 렌더링으로 대체하세요"
fi

# .env 직접 편집
if [[ "$FILE_PATH" =~ \.env$ ]] || [[ "$FILE_PATH" =~ \.env\.(local|production)$ ]]; then
  warn ".env 파일 수정: $FILE_PATH" ".gitignore 포함 여부를 확인하세요 (.env.example은 OK)"
fi

exit 0
