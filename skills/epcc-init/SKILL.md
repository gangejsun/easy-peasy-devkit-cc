---
name: epcc-init
description: EPCC Devkit 프로젝트 초기 설정. epcc.config.json과 CLAUDE.md를 생성합니다. 새 프로젝트에서 처음 EPCC Devkit을 설정할 때 사용합니다.
trigger: manual
---

# /epcc-init — EPCC 프로젝트 초기 설정

## 목적
현재 프로젝트에 EPCC Devkit의 프로젝트별 설정 파일(`epcc.config.json`, `CLAUDE.md`)을 생성하고 `dev/` 디렉토리 구조를 초기화합니다.

## 실행 절차

### Step 0: 레포 1회 실측 (질문 전에 — 물을 것을 줄이기 위해)

**묻기 전에 읽는다.** 알 수 있는 것을 묻는 것이 인터뷰 시간의 대부분이다. 아래를 한 번에
훑어 Step 2·4·4.5·4.7의 기본값을 미리 채운다:

```bash
ls -a                                   # 기존 코드 유무 · 툴체인 흔적
cat package.json 2>/dev/null            # framework · packageManager · scripts · deps
cat pyproject.toml requirements.txt 2>/dev/null
ls pnpm-lock.yaml yarn.lock package-lock.json bun.lockb uv.lock poetry.lock 2>/dev/null
ls src app packages services apps 2>/dev/null   # sourceDir · repoTopology
cat tsconfig.json 2>/dev/null | head -20        # importAlias · strict
```

실측으로 정해지는 것: 프로젝트 이름 · 프레임워크 · 언어 · 패키지 매니저 · 빌드/테스트/린트
명령 · 소스 디렉토리 · importAlias · 레포 토폴로지 · (deps로 추정한) 백엔드 축.
**신규 빈 프로젝트면 실측할 것이 없으므로 프리셋 기본값이 그 자리를 대신한다.**

### Step 1: 기존 설정 확인

프로젝트 루트에서 다음 파일 존재 여부를 확인합니다:
- `epcc.config.json` — 있으면 "이미 설정되어 있습니다. 재설정하시겠습니까?" 확인
- `CLAUDE.md` — 있으면 백업 후 덮어쓸지 확인

### 인터뷰 규약 — `AskUserQuestion` 2회로 끝낸다

Step 2·4·4.5·4.7은 원래 필수 대기 3곳 + 조건부 5곳이었다. Step 0 실측이 대부분을
채우므로 **남은 것만 두 묶음으로 모아 묻는다.** 한 번에 하나씩 묻는 것이 사람의
시간을 가장 많이 쓴다.

| 호출 | 묶는 질문 (최대 4개) |
| --- | --- |
| 1차 | ① 프론트엔드 축 ② 백엔드 축 ③ 응답 언어 ④ 경험 수준 |
| 2차 | ⑤ 실측·프리셋으로 채운 값 일괄 확인(프레임워크·언어·PM·명령·sourceDir) ⑥ 레포 토폴로지 ⑦ 백엔드 미확정 차원(있을 때만) ⑧ 프로젝트 이름(실측 실패 시만) |

- **실측값이 있으면 그것을 기본 선택지 첫 번째로 둔다** — 대부분 그대로 확인만 하고 지난다
- 2차에서 물을 것이 하나도 없으면 (프리셋 기본값이 전 차원을 채우는 조합) **호출하지 않는다**
- 답이 갈라지는 질문만 묻는다. "사전 제작본을 쓸까 생성할까" 같은 구현 세부는 묻지 않는다

### Step 2: 프리셋 선택 (대화형 — 2축)

스택은 **프론트엔드 축과 백엔드 축 두 개**로 이루어진다. 둘을 각각 고르게 하고,
**두 축이 모두 정해진 뒤에야 조합이 확정된다.**

```
① 프론트엔드를 고르세요:
  1. nextjs      — Next.js 15 App Router + React 19 + Tailwind v4 + shadcn/ui + Zustand
  2. react-vite  — React + Vite SPA (SSR 없음) + Tailwind + React Router + TanStack Query + Zustand
  3. vanilla     — 프레임워크 없음, 표준 DOM + ES 모듈 (랜딩·위젯·경량 사이트)
  4. none        — 프론트엔드 없음 (API 전용 프로젝트)

   └ 언어: TypeScript(기본) / JavaScript — 프리셋 선택 후 확인합니다

② 백엔드를 고르세요:
  1. supabase        — BaaS: PostgreSQL + RLS + Auth + Storage + Realtime
  2. firebase        — BaaS: Firestore + Auth + Storage + Cloud Functions
  3. aws-serverless  — AWS 조립: Lambda + API Gateway + DynamoDB + Cognito
  4. aws-container   — AWS 컨테이너: ECS/Fargate + RDS PostgreSQL + Drizzle + Cognito
                       (온프레미스 이식을 전제로 AWS 종속을 인프라 층에만 둔다)
  5. gcp-serverless  — GCP 조립: Cloud Run/Functions + Firestore + Identity Platform
  6. fastapi         — 자체 서버: FastAPI + SQLAlchemy 2.0 + Pydantic v2 + Alembic
  7. node-api        — 자체 서버: Express/NestJS + PostgreSQL + Prisma/Drizzle
  8. none            — 백엔드 없음 / 외부 REST API 소비
```

백엔드 축은 **형태가 세 가지**다. 이름만 다른 동급 항목이 아니므로 선택 시 구분해 안내한다:

| 형태 | 해당 | 특징 |
| --- | --- | --- |
| BaaS | supabase · firebase | 벤더가 DB·인증·스토리지를 함께 제공. 데이터 계층에 정책 엔진이 있다 |
| 서버리스 조립 | aws-serverless · gcp-serverless | 관리형 서비스를 직접 조합. **행 수준 정책 엔진이 없을 수 있어** 애플리케이션 층 검사 비중이 커진다 |
| 자체 서버 | aws-container · fastapi · node-api | 상주 서버를 운영. 애플리케이션 층이 유일한 경계 |

**언어(TypeScript/JavaScript)는 프리셋이 아니라 차원이다.** 프리셋 기본값을 표시하고
Step 4에서 확인받는다 — 이 값에 따라 가이드의 타입 표준 슬롯이 살아나거나 JSDoc 규약으로
대체된다.

> **왜 2축인가**: 가이드 내용은 한 축의 함수가 아니라 **조합의 함수**다. 같은 Supabase라도
> Next.js와 짝지으면 Route Handlers·Server Actions 중심이고, React+Vite SPA와 짝지으면
> Edge Functions·브라우저 직접 호출 중심으로 **완전히 다른 가이드**가 된다. 두 축을 먼저
> 확정해야 서로를 고려한 가이드를 만들 수 있다.

`frontend: none` + `backend: none` 조합은 이전의 `blank` 프리셋에 해당한다.

### Step 3: 프리셋 기본값 로드 (병합)

세 파일을 읽어 이 순서로 병합한다 (뒤가 앞을 덮어씀):

1. `${CLAUDE_PLUGIN_ROOT}/presets/base.json` — 공통 domains·보안 패턴
2. `${CLAUDE_PLUGIN_ROOT}/presets/frontend/<선택>.json`
3. `${CLAUDE_PLUGIN_ROOT}/presets/backend/<선택>.json`

병합 규칙:

- `security.secretPatterns`는 **덮어쓰지 않고 누적**한다 (base + 축별 패턴)
- `additionalStack`도 누적한다
- `domains.sourceDir`은 프론트엔드 축의 값을 우선한다. 프론트엔드가 `none`이면
  백엔드 축의 `sourceDir`을 쓴다. 두 축이 모두 있고 값이 다르면 사용자에게 확인받는다
- 각 프리셋의 `notes`는 config에 기록하지 않는다 — Step 9.5에서 가이드 생성 에이전트에
  **조합 맥락으로 전달**한다 (서로를 고려한 가이드를 만드는 근거)

### Step 4: 프로젝트 정보 수집 (대화형)

사용자에게 다음 정보를 질문합니다 (프리셋 기본값이 있으면 표시):

1. **프로젝트 이름** (필수)
2. **응답 언어** — ko / en / ja / zh (기본: en)
3. **경험 수준** — senior / mid / junior (기본: senior)
4. **축별 프레임워크·언어·패키지 매니저** (병합된 프리셋 기본값 확인)
5. **빌드/테스트/린트 명령어** (프리셋 기본값 확인)
6. **소스 디렉토리** (Step 3 병합 규칙의 결과를 확인)
7. **공유 패키지 경로** (선택)

**툴체인이 둘인 조합** (예: react-vite + fastapi — TypeScript/npm과 Python/uv)은 축마다
명령이 다르다. 이때는 축별 명령을 각각 받고, **프로젝트 대표 명령**(`techStack.commands`)을
따로 확인한다 — build-gate와 health-check가 읽는 값이라 반드시 채워져야 한다.
모노레포면 대표 명령이 두 축을 함께 도는 루트 스크립트인 경우가 많다.

### Step 4.5: 백엔드 미확정 차원 채우기

백엔드 **유형**은 Step 2에서 이미 정해졌다 — 여기서 다시 묻지 않는다. 선택한 백엔드
프리셋이 비워둔 차원만 채운다:

| 백엔드 축 | 확정된 것 | 여기서 물을 것 |
| --- | --- | --- |
| `supabase` | backendType·database·dataAccess·auth 전부 | 없음 — 표시하고 확인만 |
| `fastapi` | backendType·database·dataAccess | **인증 방식**(JWT 자체 발급·OAuth 제공자·세션) · 호스팅(선택) |
| `node-api` | backendType·database | **프레임워크**(Express/NestJS) · **ORM**(Prisma/Drizzle) · **인증 방식** |
| `aws-container` | 전 차원 기본값 | 없음 — 표시하고 확인만. 기본값(RDS PostgreSQL·Drizzle·Cognito)을 바꾸면 사전 제작본 대상에서 이탈해 생성 경로를 탄다 |
| `aws-serverless` · `gcp-serverless` | 전 차원 기본값 | 기본값과 다른 서비스를 쓰면 그 차원(예: DynamoDB→RDS) |
| `firebase` | 전 차원 | 없음 — 표시하고 확인만 |
| `none` | — | 외부 API를 쓴다면 그 인증 방식(토큰 보관 위치가 보안 지점) |

프리셋 밖 조합(MongoDB·Prisma·Cognito 등)으로 바꾸고 싶다는 요청이 나오면 그 자리에서
차원을 받아 `techStack.backend`에 기록한다 — 프리셋은 출발점이지 상한이 아니다.
이 경우 조합이 사전 제작 대상에서 벗어나므로 Step 9.5는 생성 경로를 탄다.

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
    "presets": { "frontend": "<Step 2 선택>", "backend": "<Step 2 선택>" },
    "preset": "<frontend>+<backend>",           // 하위 호환 표기 — presets가 정본

    // 프로젝트 대표값 — build-gate·health-check가 읽는다. 반드시 채운다
    "framework": "<대표 프레임워크>",
    "language": "<대표 언어>",
    "packageManager": "<대표 패키지 매니저>",
    "commands": { "build": "<입력값>", "test": "<입력값>", "lint": "<입력값>" },

    "frontend": {                                // 프론트엔드 축 (none이면 빈 값)
      "framework": "<입력값 또는 프리셋 기본값>",
      "language": "<입력값 또는 프리셋 기본값>",
      "packageManager": "<입력값 또는 프리셋 기본값>",
      "commands": { "build": "", "test": "", "lint": "" },
      "sourceDir": "<프리셋 기본값>",
      "additionalStack": []
    },
    "backend": {                                 // 백엔드 축
      "backendType": "<baas | serverless | cloud-server | framework-builtin | 빈 값>",
      "cloudProvider": "<입력값 또는 null>",
      "database": "<프리셋 기본값 또는 입력값>",
      "dataAccess": "<프리셋 기본값 또는 입력값>",
      "auth": "<Step 4.5 입력값>",
      "framework": "<자체 서버일 때만>",
      "language": "<자체 서버일 때만>",
      "packageManager": "<자체 서버일 때만>",
      "commands": { "build": "", "test": "", "lint": "" },
      "sourceDir": "<자체 서버일 때만>"
    },
    "additionalStack": []                        // base + 두 축 누적
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

### Step 9.5: 스택 가이드 확보 (질문 없음 · init을 붙잡지 않는다)

**init은 가이드를 기다리지 않는다.** 조립으로 끝나는 조합만 여기서 완결하고, 생성이
필요하면 작업만 등록하고 Step 10으로 넘어간다.

> 근거: 생성 1회의 실측이 **수리 전 54분**이었고(`dev/docs/skill-review/contract-first-e2e-2026-08-22.md`)
> 그 끝에서도 감사자 둘 다 설치 불가 판정을 냈다. 설치 첫인상을 그 시간에 묶을 이유가 없다 —
> 가이드는 첫 컴포넌트·첫 핸들러를 쓸 때 필요하지 `init`이 끝나는 순간 필요한 것이 아니다.

#### 분기 — 축 팩 보유 여부로 정한다

사전 제작 단위는 **조합이 아니라 축**이다. `${CLAUDE_PLUGIN_ROOT}/guides/`를 조회한다:

```bash
ls "${CLAUDE_PLUGIN_ROOT}/guides/frontend/"   # 보유한 프론트 축 팩
ls "${CLAUDE_PLUGIN_ROOT}/guides/backend/"    # 보유한 백엔드 축 팩
ls "${CLAUDE_PLUGIN_ROOT}/guides/seams/"      # 보유한 사전 제작 이음매
```

| 상태 | 동작 | 소요 |
| --- | --- | --- |
| 두 축 팩 + 사전 제작 이음매 있음 | `install-guide.sh` 조립 — **init 안에서 완결** | 초 단위 |
| 두 축 팩 있음 · 이음매 없음 | 팩만 조립하고 **이음매 생성 작업 등록** | init 즉시 종료 |
| 한 축만 팩 있음 | 그 축은 조립, 반대 축은 **전체 생성 작업 등록** | init 즉시 종료 |
| 팩 없음 | **전체 생성 작업 등록** | init 즉시 종료 |
| `none` × `none` | 가이드 없음 | — |

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-guide.sh" \
  --frontend <프론트 팩|none> --backend <백엔드 팩|none> [--seam <조합>]
```

조립이 끝나면 게이트로 확인한다 — 조립도 검증 대상이다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/stack-guide-generator/scripts/guide-gate.sh" \
  --guide .claude/skills/<축>-guide --assembly .claude/skills/<축>-guide/assembly.json
```

**FAIL이 남으면 그 축의 가이드를 지우고 보고한다.** 반쪽 가이드를 남기지 않는다.

#### 기준선 점검 (조립한 축에 한해, 묻지 않고 점검한다)

팩 스탬프(`<!-- epcc-pack: ... verified YYYY-MM-DD pkg@major ... -->`)와 프로젝트의 실제
의존성(`package.json` 등)을 **메이저 버전 기준으로** 대조한다.

- 일치하면 아무 말도 하지 않는다 (질문도 경고도 없음)
- 어긋나면 **구체적으로 보고만** 한다 — 재생성 여부를 묻지 않는다:

```
가이드 기준선과 프로젝트 의존성이 다릅니다:
  zod: 가이드 v4 기준 ↔ 프로젝트 v3
이 항목의 지침은 이 프로젝트에서 맞지 않을 수 있습니다.
조정하려면 /stack-guide-generator 를 실행하세요.
```

> "재생성할까요?"라고 묻지 않는 이유: 사용자는 가이드가 낡았는지 알 방법이 없어 감으로
> 답하게 되고, 그러면 그 질문은 매 세션의 소음이 된다. 시스템이 대조해 **어긋날 때만**
> 구체적으로 말하는 것이 답할 수 있는 정보다.

#### 생성이 필요하면 — 작업만 등록하고 init을 끝낸다

`.epcc/guide-job.json`을 쓴다. **미완성 가이드는 설치하지 않는다** — 완성·감사·수리를
마친 뒤에만 `.claude/skills/`에 들어간다.

```jsonc
{
  "status": "pending",              // pending | running | interrupted | done | failed
  "combo": "<frontend>+<backend>",
  "need": ["frontend", "backend"],  // 팩으로 이미 조립된 축은 빼고, 이음매만 필요하면 "seam:frontend"
  "packs": { "frontend": "<팩|null>", "backend": "<팩|null>" },
  "notes": { "serverCode": "...", "securityBoundary": "...", "policyEngine": true },
  "createdAt": "<날짜>"
}
```

그리고 사용자에게 알린다 (승인을 묻지 않는다 — 무엇을 할지는 시스템이 안다):

```
확정된 조합: <프론트> × <백엔드>
축 팩으로 조립한 것: <있으면 나열>
생성이 필요한 것: <나열> — 지금 이어서 만들까요, 다음 세션에 만들까요?
(init 자체는 완료됐습니다. 가이드 없이도 T1 규칙 카드는 이미 작동합니다)
```

이어서 만든다고 하면 `stack-guide-generator`를 호출하고, 아니면 여기서 끝낸다.
`session-brief` 훅이 다음 세션에 미완 작업을 알린다.

> 이 한 가지만 묻는 이유: **지금 20분을 쓸지는 사용자의 시간에 대한 결정**이라 시스템이
> 대신 답할 수 없다. 반면 "사전 제작본을 쓸지 생성할지"는 구현 세부라 묻지 않는다.

- 호출 시 **두 축의 프리셋 `notes`를 함께 전달한다.** 가이드는 한 축의 함수가 아니라
  조합의 함수이기 때문이다 — 서버 코드가 어디 사는지(프론트 축의 `serverCode`),
  보안 경계가 어디인지(백엔드 축의 `securityBoundary`), 데이터 계층에 정책 엔진이 있는지가
  두 가이드의 내용을 함께 결정한다
- 한 축이 팩으로 이미 조립됐다면 그 팩의 `ledger.md`·`policies.md`를 생성 에이전트에
  전달한다 — 이음매가 팩의 `requires`를 채우고 `policies`를 어기지 않아야 한다

#### 사전 제작본을 늘리는 기준

조합은 32가지지만 **축은 12가지**(프론트 4 · 백엔드 8)다. 조합 단위로 사전 제작하면
가이드 45개(약 9만 줄)가 되어 유지 불가능하고, 감사받지 않는 사전 제작본은 부패해서
**없는 가이드보다 나쁘다**(틀린 지침을 신뢰하게 만든다). 축 단위는 12개라 감사 가능하다.

> **정기 감사 대상으로 등록할 수 있을 때만 사전 제작한다.** 축 팩은 이 기준을 충족한다 —
> 팩 하나를 감사하면 조합 4개(프론트) 또는 8개(백엔드)가 함께 좋아진다.

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
