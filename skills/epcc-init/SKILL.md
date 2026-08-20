---
name: epcc-init
description: EPCC Devkit 프로젝트 초기 설정. epcc.config.json과 CLAUDE.md를 생성합니다. 새 프로젝트에서 처음 EPCC Devkit을 설정할 때 사용합니다.
trigger: manual
---

# /epcc-init — EPCC 프로젝트 초기 설정

## 목적
현재 프로젝트에 EPCC Devkit의 프로젝트별 설정 파일(`epcc.config.json`, `CLAUDE.md`)을 생성하고 `dev/` 디렉토리 구조를 초기화합니다.

## 실행 절차

### Step 1: 기존 설정 확인

프로젝트 루트에서 다음 파일 존재 여부를 확인합니다:
- `epcc.config.json` — 있으면 "이미 설정되어 있습니다. 재설정하시겠습니까?" 확인
- `CLAUDE.md` — 있으면 백업 후 덮어쓸지 확인

### Step 2: 프리셋 선택 (대화형)

사용자에게 프리셋을 선택하도록 안내합니다:

```
사용 가능한 프리셋:

1. nextjs-supabase  — Full-Stack JS/TS: Next.js 15 + Supabase + Tailwind + shadcn/ui
2. react-vite       — SPA Frontend: React + Vite + Tailwind + REST API
3. python-fastapi   — Python Backend: FastAPI + SQLAlchemy + Pydantic
4. blank            — 최소 설정, 직접 구성

어떤 프리셋을 사용하시겠습니까?
```

### Step 3: 프리셋 기본값 로드

선택된 프리셋 파일을 읽습니다:
- **플러그인 경로**: `${CLAUDE_PLUGIN_ROOT}/presets/<preset-name>.json`
- 이 파일의 `techStack`, `domains`, `security` 값을 `epcc.config.json`의 기본값으로 사용

### Step 4: 프로젝트 정보 수집 (대화형)

사용자에게 다음 정보를 질문합니다 (프리셋 기본값이 있으면 표시):

1. **프로젝트 이름** (필수)
2. **응답 언어** — ko / en / ja / zh (기본: en)
3. **경험 수준** — senior / mid / junior (기본: senior)
4. **프레임워크** (프리셋 기본값 확인)
5. **언어** (프리셋 기본값 확인)
6. **패키지 매니저** (프리셋 기본값 확인)
7. **빌드/테스트/린트 명령어** (프리셋 기본값 확인)
8. **소스 디렉토리** (기본: src)
9. **공유 패키지 경로** (선택)

### Step 4.5: 백엔드 차원 확인 (대화형 — Supabase 고정 아님)

프리셋의 백엔드는 **기본값이지 고정이 아니다.** 기본값을 표시하고 반드시 확인한다:

```
백엔드 구성을 확인합니다 (프리셋 기본값: Supabase BaaS + PostgreSQL):

1. 백엔드 유형 — BaaS(Supabase/Firebase) / 클라우드 자체 구축(AWS·GCP·Azure) / 프레임워크 내장
2. (자체 구축 시) 클라우드/호스팅 — AWS / GCP / Azure / 자체
3. DB — PostgreSQL / MySQL / MongoDB / DynamoDB / 기타
4. 데이터 액세스 — Prisma / Drizzle / SQLAlchemy / SDK 직접
5. 인증 — Supabase Auth / NextAuth / Cognito / 자체 구현

기본값 그대로 진행할까요, 바꾸시겠습니까?
```

BaaS 선택 시 DB·인증은 자동 추론 후 확인만 받는다. 자체 구축 선택 시 2~5를 필수로 묻는다.

### Step 4.7: 레포 구조 확인 (대화형)

기존 코드가 있으면 먼저 실측(`ls` + 주요 디렉토리 확인)으로 추정한 값을 기본값으로 표시하고 확인만 받는다:

```
레포 구조를 확인합니다:

1. single   — 싱글레포: 앱 하나 (기본값)
2. monorepo — 모노레포: 루트 앱 + 공유 패키지 (packages/ 등)
3. msa      — 서비스 여러 개 (services/·apps/ 분리, 서비스 간 API/이벤트 계약)
```

- **monorepo** 선택 시에만 Step 4의 "공유 패키지 경로"를 필수로 확정한다
- 선택 결과는 Step 5의 `domains.repoTopology`와 Step 7.5의 구조 카드 생성에 쓰인다

### Step 5: epcc.config.json 생성

수집된 정보로 `epcc.config.json` 생성:

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/gyeong/epcc-devkit/main/plugin/schema/epcc.config.schema.json",

  "project": {
    "name": "<입력값>",
    "language": "<입력값>",
    "experienceLevel": "<입력값>"
  },

  "techStack": {
    "preset": "<선택된 프리셋>",
    "framework": "<입력값 또는 프리셋 기본값>",
    "language": "<입력값 또는 프리셋 기본값>",
    "packageManager": "<입력값 또는 프리셋 기본값>",
    "commands": {
      "build": "<입력값>",
      "test": "<입력값>",
      "lint": "<입력값>"
    },
    "backend": {
      "backendType": "<baas | cloud-server | framework-builtin>",
      "cloudProvider": "<Step 4.5 입력값 또는 null>",
      "database": "<Step 4.5 입력값>",
      "dataAccess": "<Step 4.5 입력값>",
      "auth": "<Step 4.5 입력값>"
    },
    "additionalStack": []
  },

  "domains": {
    "sourceDir": "<입력값>",
    "sharedPackage": "<입력값>",
    "importAlias": "<입력값>",
    "repoTopology": "<monorepo | single | msa — Step 4.7 선택값>"
  },

  "security": {
    "secretPatterns": []  // 프리셋 기본값 사용
  },

  "customResources": {}
}
```

### Step 6: CLAUDE.md 생성

다음 템플릿을 기반으로 `CLAUDE.md`를 렌더링합니다:

```markdown
# CLAUDE.md

## Project Overview
### <프로젝트 이름>

## User Profile

- Response Language: <언어>
- Experience Level: <경험 수준>
<Senior인 경우 추가>
- 코드 변경 시 **변경 이유와 영향 범위** 설명, 여러 접근 시 **장단점 비교** 후 추천안 제시
- 버그 수정 시 **자율적으로 분석·수정** 후 결과만 보고 (질문으로 시간 낭비 금지)

## 기술 스택

- **프레임워크**: <프레임워크> + <언어>
- <추가 스택 목록>
- **패키지 매니저**: <패키지 매니저>
<공유 패키지가 있는 경우>
- **프로젝트 구조**: 모노레포 (루트 앱 + `<공유 패키지>`)

## 개발 명령어

- 빌드: `<빌드 명령>` | 테스트: `<테스트 명령>` | 린트: `<린트 명령>`

## 코딩 컨벤션

<프로젝트 고유 컨벤션만 1행씩. 없으면 섹션 삭제>

---

## 하네스

운영 계약은 세션 시작 시 자동 주입됩니다. 작업 규칙은 `.claude/rules/`에서 조건부 로드됩니다.

- `bash <플러그인-루트>/scripts/doctor.sh` — 하네스 자기검증 (절대 경로는 세션 브리핑에 표시)
- `bash <플러그인-루트>/scripts/doctor.sh --usage` — 훅 생존·계측
```

> **CLAUDE.md는 100행 내외로 유지하세요.** 프로젝트 구조 트리, 기술 특화 규칙,
> 코드 스타일 상세는 넣지 않습니다 — 실시간 탐색이 가능하거나 `.claude/rules/`가 담당합니다.
> 매 행마다 "이 행을 지우면 Claude가 실수하는가"를 물어 아니면 지웁니다.

### Step 7: T1 규칙 카드 설치 (필수 — 건너뛰지 마세요)

플러그인의 규칙 카드를 프로젝트 `.claude/rules/`로 설치합니다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-rules.sh"
```

설치되는 카드 (경로 매칭 시 조건부 로드):

| 파일 | 로드 조건 |
| --- | --- |
| `code-change.md` | `src/**` `app/**` `packages/**` 편집 시 |
| `reversibility.md` | 소스·마이그레이션·워크스페이스 편집 시 |
| `harness-change.md` | `.claude/**` `scripts/**` 편집 시 |
| `lessons.md` | `docs/lessons.md` 편집 시 |
| `doc-dependency.md` | `dev/docs/{prd,database,design,architecture,api}/**` 편집 시 |
| `data-modeling.md` | `supabase/**` `**/migrations/**` `db/**` `prisma/**` 등 DB 경로 편집 시 |

**설치 후 반드시 확인**하세요:

```bash
ls .claude/rules/
```

파일이 0개면 설치가 실패한 것입니다. 사용자에게 보고하고 중단하세요.

> 상시 규범(T0)은 파일이 아니라 `session-brief` 훅이 매 세션 출력합니다.
> 플러그인 소유이므로 자동 갱신되며 프로젝트가 수정할 수 없습니다.

### Step 7.5: 프로젝트 전용 규칙 카드 생성 (프로젝트 소유)

Step 7의 카드가 **플러그인 소유**(버전 스탬프로 자동 갱신)라면, 이 단계의 두 카드는
**프로젝트 소유**다 — 이 프로젝트의 실제 구조·컨벤션을 담고, 이후 프로젝트가 직접 관리한다.

1. `${CLAUDE_PLUGIN_ROOT}/templates/rules/project-structure.template.md`를 읽는다
2. **기존 코드가 있으면 실제 트리를 실측한다** (`ls` + 주요 디렉토리 2~3 depth) —
   추측으로 채우지 않는다. 신규 프로젝트면 프리셋 + Step 4.7 토폴로지의 목표 구조로 채운다
3. 플레이스홀더와 안내 주석을 전부 치환·제거하고 `.claude/rules/` 아래
   `project-structure.md`로 저장한다
4. `${CLAUDE_PLUGIN_ROOT}/templates/rules/code-conventions.template.md`도 같은 방식 —
   프리셋에 맞는 **스택 블록 하나만** 남기고, 공통 블록(네이밍·코드 스타일·커밋 규약)은
   유지한다. 기존 린트 설정·CLAUDE.md에 프로젝트 고유 규약이 있으면 사용자 확인 후 반영해
   `code-conventions.md`로 저장한다
5. 두 카드의 `paths:` frontmatter가 **실제 소스 디렉토리**(Step 4 입력값)를 가리키는지
   확인한다 — paths가 틀리면 카드는 영영 로드되지 않는다

> 이 두 카드에는 `epcc-rule-version` 스탬프를 넣지 않는다. 스탬프가 없어야
> `install-rules.sh`가 플러그인 갱신 시 이 파일들을 건드리지 않는다.

### Step 8: dev/ 디렉토리 생성

```
dev/
├── active/     # 진행 중 작업
├── archive/    # 완료된 작업
├── docs/       # 프로젝트 문서
│   ├── prd/
│   ├── architecture/
│   ├── api/
│   ├── database/
│   ├── research/
│   ├── business/
│   ├── service/
│   ├── insights/
│   └── design/
└── templates/
    ├── feature-plan-template.md
    ├── feature-context-template.md
    └── feature-tasks-template.md
```

### Step 9: .gitignore 업데이트

`.gitignore`에 다음 항목을 추가합니다 (이미 있으면 건너뜀):
```
.epcc/
```

### Step 9.5: 스택 가이드 생성

확정된 조합을 요약하고 가이드 생성 여부를 확인한다:

```
확정된 스택: <프론트엔드> + <백엔드 유형> + <DB> + <데이터 액세스>
이 조합에 맞는 frontend-guide / backend-guide 스킬을 .claude/skills/에 생성할까요?
```

- 승인 시 **stack-guide-generator 스킬을 호출**한다 (Step 1 인터뷰는 config가 채워졌으므로 생략됨)
- 정확히 Next.js+Supabase 조합이면 생성 없이 플러그인 원본 사용을 안내한다
- 거절 시 나중에 `/stack-guide-generator`로 생성 가능함을 안내한다

### Step 10: 완료 보고

```
EPCC Devkit 초기 설정 완료!

생성된 파일:
  ✅ epcc.config.json
  ✅ CLAUDE.md
  ✅ .claude/rules/ (플러그인 규칙 카드 N개 + 프로젝트 전용 project-structure · code-conventions)
  ✅ .claude/skills/frontend-guide · backend-guide (생성한 경우)
  ✅ dev/ 디렉토리 구조

검증:
  bash "${CLAUDE_PLUGIN_ROOT}/scripts/doctor.sh"

다음 단계:
  1. CLAUDE.md를 검토하고 프로젝트 고유 정보를 채우세요
  2. Claude Code를 재시작하면 하네스가 활성화됩니다
```

## 주의사항

- 이 스킬은 프로젝트 루트에 파일을 생성합니다
- 기존 `CLAUDE.md`가 있으면 반드시 백업 여부를 확인하세요
- `epcc.config.json`의 `security.secretPatterns`는 프리셋 기본값이 자동 적용됩니다
