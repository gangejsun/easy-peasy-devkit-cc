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

[[ "$TOOL_NAME" =~ ^(Edit|Write|MultiEdit)$ ]] || exit 0

# 이 훅 자신을 편집할 때는 자기 참조 회피 (패턴 문자열이 매칭됨)
[[ "$FILE_PATH" =~ security-check\.sh$ ]] && exit 0

TEXT="${CONTENT}${NEW_STRING}"
[ -z "$TEXT" ] && exit 0

block() {
  printf '❌ 차단: %s\n\n' "$1" >&2
  printf '%s\n\n' "$2" >&2
  printf '올바른 방법: 환경 변수로 이동 (.env.local — .gitignore 확인)\n' >&2
  exit 2
}
warn() { printf '⚠️  %s\n%s\n' "$1" "$2" >&2; }

# -e 필수: PEM 헤더처럼 '-'로 시작하는 패턴을 grep이 옵션으로 오해한다
has()  { printf '%s' "$TEXT" | grep -Eq  -e "$1"; }
hasi() { printf '%s' "$TEXT" | grep -Eqi -e "$1"; }

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

[ -n "$EPCC_ROOT" ] && epcc_edge "build" "security-check"

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
