#!/bin/bash
# .claude/hooks/security-check.sh
# @harness-type: portable (시크릿 패턴만 프로젝트별 교체)
# PreToolUse Hook: security.md Rule을 보완하는 최후 방어선
#
# 목적: Rule(사전 교육)을 통과한 명백한 보안 실수만 차단
# 전략: 정확한 시크릿 패턴 검사 + API Route Zod 검증 경고 (false positive 최소화)
#
# 실행 시점: Claude가 Edit/Write 도구 사용 직전
# 컨텍스트 포함: ❌ (Verbose 모드에만 표시)
# 토큰 사용: 0T

set -euo pipefail

# stdin에서 tool use 정보 읽기
INPUT=$(cat /dev/stdin 2>/dev/null)

# 도구 이름과 파일 경로, 콘텐츠 추출
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null || echo "")
OLD_STRING=$(echo "$INPUT" | jq -r '.tool_input.old_string // ""' 2>/dev/null || echo "")
NEW_STRING=$(echo "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null || echo "")

# Edit/Write 도구만 검증
if [[ ! "$TOOL_NAME" =~ ^(Edit|Write)$ ]]; then
  exit 0
fi

# Hook 자체 편집 시 자기 참조 회피 (시크릿 패턴 문자열이 매칭됨)
if [[ "$FILE_PATH" =~ security-check\.sh$ ]]; then
  exit 0
fi

# 검사 대상 텍스트 결합
SEARCH_TEXT="$CONTENT$NEW_STRING"

# ============================================================
# 규칙 1: 명백한 시크릿 패턴 차단 (정확한 패턴만)
# ============================================================

# AWS Access Key ID (정확한 형식: AKIA + 16자)
if echo "$SEARCH_TEXT" | grep -E -q 'AKIA[0-9A-Z]{16}'; then
  cat >&2 <<EOF
❌ ERROR: AWS Access Key ID 하드코딩 감지!

🔒 감지된 패턴: AKIA[0-9A-Z]{16}

✅ 올바른 방법:
  1. 환경 변수 사용:
     const accessKey = process.env.AWS_ACCESS_KEY_ID

  2. .env 파일에 저장 (.gitignore 필수):
     AWS_ACCESS_KEY_ID=AKIA...

  3. Vercel 환경 변수 설정

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi

# AWS Secret Access Key (40자 base64)
if echo "$SEARCH_TEXT" | grep -E -q '[A-Za-z0-9/+=]{40}' && \
   echo "$SEARCH_TEXT" | grep -i -q -E '(secret.*key|aws.*secret)'; then
  cat >&2 <<EOF
⚠️ WARNING: AWS Secret Access Key 의심 패턴 감지!

🔒 40자 base64 문자열 + "secret" 키워드 발견

✅ 확인 사항:
  - 실제 AWS Secret인가요? → 환경 변수로 이동
  - 테스트 데이터인가요? → 주석으로 명시

📖 상세: .claude/rules/security.md 참조
EOF
  # WARNING만, 차단하지 않음 (false positive 가능)
fi

# GitHub Personal Access Token (ghp_ + 36자)
if echo "$SEARCH_TEXT" | grep -E -q 'ghp_[a-zA-Z0-9]{36}'; then
  cat >&2 <<EOF
❌ ERROR: GitHub Personal Access Token 하드코딩 감지!

🔒 감지된 패턴: ghp_[a-zA-Z0-9]{36}

✅ 올바른 방법:
  1. GitHub Secrets 사용 (CI/CD):
     \${{ secrets.GITHUB_TOKEN }}

  2. 로컬 환경 변수:
     const token = process.env.GITHUB_TOKEN

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi

# Supabase Anon Key (JWT 형식)
# eyJ로 시작하는 JWT + "anon" 키워드
if echo "$SEARCH_TEXT" | grep -E -q 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9\.[a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'; then
  # anon key는 공개 가능하므로 WARNING만
  if echo "$SEARCH_TEXT" | grep -i -q 'anon'; then
    cat >&2 <<EOF
⚠️ WARNING: Supabase Anon Key 감지

ℹ️ Anon Key는 공개 가능하지만, 환경 변수 사용을 권장합니다:
  const supabase = createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  )

📖 상세: .claude/rules/security.md 참조
EOF
    # WARNING만, 차단하지 않음
  else
    # service_role key는 절대 공개 불가
    cat >&2 <<EOF
❌ ERROR: Supabase Service Role Key 의심!

🔒 JWT 형식의 Supabase Key 감지 (service_role일 가능성)

✅ 확인 사항:
  - Anon Key인가요? → NEXT_PUBLIC_SUPABASE_ANON_KEY 사용
  - Service Role Key인가요? → 절대 클라이언트에 노출 금지!
    → 서버 환경 변수(SUPABASE_SERVICE_ROLE_KEY)로 이동

📖 상세: .claude/rules/security.md 참조
EOF
    exit 2  # 차단
  fi
fi

# Stripe Secret Key (sk_live_ 또는 sk_test_)
if echo "$SEARCH_TEXT" | grep -E -q 'sk_(live|test)_[a-zA-Z0-9]{24,}'; then
  cat >&2 <<EOF
❌ ERROR: Stripe Secret Key 하드코딩 감지!

🔒 감지된 패턴: sk_live_ 또는 sk_test_

✅ 올바른 방법:
  1. 서버 환경 변수 (절대 클라이언트 노출 금지):
     const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!)

  2. .env.local에 저장:
     STRIPE_SECRET_KEY=sk_live_...

  3. Vercel 환경 변수 설정

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi

# Toss Payments Secret Key (토스 페이먼츠)
if echo "$SEARCH_TEXT" | grep -E -q 'test_sk_|live_sk_'; then
  cat >&2 <<EOF
❌ ERROR: Toss Payments Secret Key 하드코딩 감지!

🔒 감지된 패턴: test_sk_ 또는 live_sk_

✅ 올바른 방법:
  1. 서버 환경 변수:
     const secretKey = process.env.TOSS_SECRET_KEY

  2. .env.local에 저장:
     TOSS_SECRET_KEY=test_sk_...

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi


# PEM Private Key (RSA, EC, DSA 등)
if echo "$SEARCH_TEXT" | grep -E -q '\-\-\-\-\-BEGIN[[:space:]]+(RSA|EC|DSA|OPENSSH|PGP)?[[:space:]]*PRIVATE KEY\-\-\-\-\-'; then
  cat >&2 <<EOF
❌ ERROR: Private Key 하드코딩 감지!

🔒 감지된 패턴: -----BEGIN ... PRIVATE KEY-----

✅ 올바른 방법:
  1. 환경 변수로 이동:
     const key = process.env.PRIVATE_KEY

  2. 파일 시스템에서 읽기:
     const key = fs.readFileSync('/path/to/key.pem')

  3. .env.local에 저장 (줄바꿈은 \\n으로 이스케이프):
     PRIVATE_KEY="-----BEGIN RSA PRIVATE KEY-----\\n..."

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi

# OpenAI API Key (sk-proj- + 20자 이상)
if echo "$SEARCH_TEXT" | grep -E -q 'sk-proj-[a-zA-Z0-9]{20,}'; then
  cat >&2 <<EOF
❌ ERROR: OpenAI API Key 하드코딩 감지!

🔒 감지된 패턴: sk-proj-...

✅ 올바른 방법:
  const openai = new OpenAI({ apiKey: process.env.OPENAI_API_KEY })

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi

# Google/GCP Service Account JSON Key
if echo "$SEARCH_TEXT" | grep -E -q '"type"[[:space:]]*:[[:space:]]*"service_account"' && \
   echo "$SEARCH_TEXT" | grep -E -q '"private_key"[[:space:]]*:'; then
  cat >&2 <<EOF
❌ ERROR: GCP Service Account Key JSON 하드코딩 감지!

🔒 감지된 패턴: {"type": "service_account", "private_key": ...}

✅ 올바른 방법:
  1. 환경 변수로 JSON 경로 지정:
     GOOGLE_APPLICATION_CREDENTIALS=/path/to/service-account.json

  2. 시크릿 매니저 사용 (프로덕션)

📖 상세: .claude/rules/security.md 참조
EOF
  exit 2  # 차단
fi

# ============================================================
# 규칙 2: API Route / Server Action — Zod 입력 검증 경고
# ============================================================

# Write 도구로 새 파일 작성 시에만 검사 (Edit은 부분 수정이므로 제외)
if [[ "$TOOL_NAME" == "Write" ]]; then
  # API Route Handler 또는 Server Action 파일인지 확인
  IS_API_ROUTE=false
  if [[ "$FILE_PATH" =~ src/app/api/.+\.ts$ ]]; then
    IS_API_ROUTE=true
  elif [[ "$FILE_PATH" =~ /actions\.ts$ ]]; then
    IS_API_ROUTE=true
  fi

  if [ "$IS_API_ROUTE" = true ]; then
    # Zod import 또는 z. 사용 여부 확인
    HAS_ZOD=false
    if echo "$SEARCH_TEXT" | grep -q -E "(from ['\"]zod['\"]|from ['\"]@/|z\.(object|string|number|array|enum|union|literal|boolean|optional|nullable))"; then
      HAS_ZOD=true
    fi

    if [ "$HAS_ZOD" = false ]; then
      cat >&2 <<EOF
⚠️ WARNING: API Route/Server Action에 Zod 입력 검증 미감지!

📋 파일: $FILE_PATH

🔒 보안 원칙: 모든 외부 입력은 Zod 스키마로 검증해야 합니다.

✅ 올바른 패턴:
  import { z } from "zod"

  const schema = z.object({
    name: z.string().min(1),
    email: z.string().email(),
  })

  const body = schema.parse(await request.json())

📖 상세: .claude/rules/security.md §2 참조
EOF
      # WARNING만, 차단하지 않음 (작성 진행 중일 수 있음)
    fi
  fi
fi

# ============================================================
# 규칙 3: .env 파일 차단 (실수로 커밋 방지)
# ============================================================

if [[ "$FILE_PATH" =~ \.env$ ]] && [[ ! "$FILE_PATH" =~ \.env\.(example|template)$ ]]; then
  cat >&2 <<EOF
⚠️ WARNING: .env 파일 수정 감지!

📋 파일: $FILE_PATH

✅ 확인 사항:
  1. .gitignore에 .env 포함 여부 확인
  2. .env.example은 OK, .env는 Git 커밋 금지
  3. 민감 정보가 포함되어 있나요?

💡 대안:
  - .env.example 파일로 템플릿 제공
  - 실제 값은 각자 로컬 .env에 설정

📖 상세: .claude/rules/security.md 참조
EOF
  # WARNING만, 차단하지 않음 (개발 중 필요할 수 있음)
fi

# ============================================================
# 규칙 3: package.json에 시크릿 포함 차단
# ============================================================

if [[ "$FILE_PATH" =~ package\.json$ ]]; then
  # scripts에 시크릿이 포함되면 위험 (npm run 시 노출)
  if echo "$SEARCH_TEXT" | grep -E -q '(AKIA|ghp_|sk_live_|sk_test_)'; then
    cat >&2 <<EOF
❌ ERROR: package.json에 시크릿 포함!

🔒 package.json의 scripts나 config에 시크릿이 포함되어 있습니다.

✅ 올바른 방법:
  1. package.json에서 시크릿 제거
  2. 환경 변수 사용:
     "scripts": {
       "deploy": "vercel --token \$VERCEL_TOKEN"
     }

📖 상세: .claude/rules/security.md 참조
EOF
    exit 2  # 차단
  fi
fi

# ============================================================
# 통과
# ============================================================

exit 0
