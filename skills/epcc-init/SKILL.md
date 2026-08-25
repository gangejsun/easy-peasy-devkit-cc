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
  3. vue         — Vue 3 Composition API + Vite SPA (SSR 없음) + Tailwind + Vue Router + Pinia
  4. vanilla     — 프레임워크 없음, 표준 DOM + ES 모듈 (랜딩·위젯·경량 사이트)
  5. none        — 프론트엔드 없음 (API 전용 프로젝트)

   └ 언어: TypeScript(기본) / JavaScript — 프리셋 선택 후 확인합니다

② 백엔드를 고르세요:
  1. supabase        — BaaS: PostgreSQL + RLS + Auth + Storage + Realtime
  2. firebase        — BaaS: Firestore + Auth + Storage + Cloud Functions
  3. aws-serverless  — AWS 조립: Lambda + API Gateway + DynamoDB + Cognito
  4. aws-container   — AWS 컨테이너: ECS/Fargate + RDS PostgreSQL + Drizzle + Cognito
                       (온프레미스 이식을 전제로 AWS 종속을 인프라 층에만 둔다)
  5. gcp-serverless  — GCP 조립: Cloud Run/Functions + Firestore + Identity Platform
  6. fastapi         — 자체 서버: FastAPI + SQLAlchemy 2.0 + Pydantic v2 + Alembic
  7. node-api        — 자체 서버: Express 5 + PostgreSQL + Prisma
  8. node-nest       — 자체 서버: NestJS 11 + PostgreSQL + TypeORM 1 + class-validator
                       (모듈·DI·데코레이터가 구조를 정한다 — Express의 변형이 아니다)
  9. none            — 백엔드 없음 / 외부 REST API 소비
```

백엔드 축은 **형태가 세 가지**다. 이름만 다른 동급 항목이 아니므로 선택 시 구분해 안내한다:

| 형태 | 해당 | 특징 |
| --- | --- | --- |
| BaaS | supabase · firebase | 벤더가 DB·인증·스토리지를 함께 제공. 데이터 계층에 정책 엔진이 있다 |
| 서버리스 조립 | aws-serverless · gcp-serverless | 관리형 서비스를 직접 조합. **행 수준 정책 엔진이 없을 수 있어** 애플리케이션 층 검사 비중이 커진다 |
| 자체 서버 | aws-container · fastapi · node-api · node-nest | 상주 서버를 운영. 애플리케이션 층이 유일한 경계 |

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
| `node-api` | backendType·database·프레임워크(Express 5)·ORM(Prisma) | **인증 방식**. 프레임워크·ORM은 팩이 못박았다 — 다르면 `node-nest`이거나 생성 경로다 |
| `node-nest` | backendType·database·프레임워크(NestJS 11)·ORM(TypeORM 1)·검증(class-validator) | **인증 방식**. 가드가 세션 쿠키를 볼지 베어러 토큰을 볼지는 프론트 축의 함수다 |
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
  "$schema": "https://raw.githubusercontent.com/gangejsun/easy-peasy-devkit-cc/main/schema/epcc.config.schema.json",

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

**정본은 `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.hbs`다.** 이 스킬에 템플릿 본문을
옮겨 적지 않는다 — 사본은 드리프트 원천이고, 실제로 v3에서 이 스킬의 인라인 사본이
정본과 갈라져 「작업 라우팅」 섹션이 프로젝트에 도달하지 못했다.

1. `${CLAUDE_PLUGIN_ROOT}/templates/CLAUDE.md.hbs`를 Read한다
2. Handlebars 표현을 `epcc.config.json`의 값으로 치환한다:
   - `{{project.name}}` · `{{techStack.framework}}` 등 → 해당 값
   - `{{#if ...}}...{{/if}}` → 조건이 참이면 본문만 남기고, 거짓이면 블록 전체 삭제
   - `{{#each techStack.additionalStack}}` → 항목마다 한 줄씩 전개
   - `{{#if (eq project.language "ko")}}` 류 → 실제 설정값에 맞는 분기 하나만 남김
3. `<플러그인-루트>` 자리표시자는 **그대로 둔다** — 절대 경로는 매 세션 브리핑의
   '자기검증' 줄에 표시되므로, 여기에 박아 넣으면 플러그인 경로 변경 시 끊긴다
4. 프로젝트 루트에 `CLAUDE.md`로 쓴다 (기존 파일이 있으면 Step 0의 백업 확인을 따른다)

**「하네스」 섹션의 `.claude/rules/workflow-routing.md` 포인터를 지우지 않는다.**
P0~P6 Phase 표 본문은 그 카드에 있고 Step 7이 설치한다 — CLAUDE.md에 표를 다시
써넣지 않는다 (사본이 갈리면 `doctor --fast`가 실패시킨다).

> **CLAUDE.md는 100행 내외로 유지하세요.** 프로젝트 구조 트리, 기술 특화 규칙,
> 코드 스타일 상세는 넣지 않습니다 — 실시간 탐색이 가능하거나 `.claude/rules/`가 담당합니다.
> 매 행마다 "이 행을 지우면 Claude가 실수하는가"를 물어 아니면 지웁니다.

### Step 7: T1 규칙 카드 설치 (필수 — 건너뛰지 마세요)

플러그인의 규칙 카드를 프로젝트 `.claude/rules/`로 설치합니다:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-rules.sh"
```

설치되는 카드:

| 파일 | 로드 조건 |
| --- | --- |
| `workflow-routing.md` | **매 세션 무조건** (`paths` 없음) — 작업 라우팅 P0~P6 + 참조 신선도 |
| `code-change.md` | `src/**` `app/**` `packages/**` `lib/**` 편집 시 |
| `security.md` | `src/**` `app/**` `packages/**` `lib/**` 편집 시 |
| `reversibility.md` | 소스·마이그레이션·워크스페이스 편집 시 |
| `harness-change.md` | `.claude/**` `scripts/**` 편집 시 |
| `lessons.md` | 소스·`.claude/**`·`scripts/**`·`dev/docs/**` 편집 시 |
| `doc-dependency.md` | `dev/docs/{prd,database,design,architecture,api}/**` 편집 시 |
| `data-modeling.md` | `supabase/**` `**/migrations/**` `db/**` `prisma/**` 등 DB 경로 편집 시 |

> 이 표는 `rules/`의 실제 frontmatter를 반영해야 한다. 카드를 추가·수정하면 여기도 고친다
> — `doctor --fast`가 카드 수 불일치를 검출한다.

**설치 후 반드시 확인**하세요:

```bash
ls .claude/rules/
```

파일이 0개면 설치가 실패한 것입니다. 사용자에게 보고하고 중단하세요.

> **이 단계를 건너뛰어도 다음 세션에 복구됩니다** — `session-brief` 훅이 `epcc.config.json`이
> 있고 카드가 모자라면 `install-rules.sh --missing-only`를 자동 실행합니다. 그래도 여기서
> 직접 실행하세요: 이번 세션에서 규칙이 필요한 작업이 바로 이어질 수 있고, 훅은 **누락분만**
> 깔지 구버전은 갱신하지 않습니다.
>
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

> 이 두 카드에는 `epcc-rule-version` 스탬프를 넣지 않는다 — 프로젝트 소유임을 표시한다.
>
> **보호 기제는 스탬프가 아니라 이름 비충돌이다.** `install-rules.sh`는 플러그인
> `rules/*.md`만 순회하므로(`for f in "$SRC"/*.md`), `rules/`에 같은 이름이 없는 한
> 후보에 오지 않는다. 따라서 **플러그인 `rules/`에 `project-structure.md` ·
> `code-conventions.md`를 만들지 않는다** — 만드는 순간 무스탬프 타겟이 `0.0.0`으로
> 읽혀 프로젝트 사본이 덮어써진다(`.bak`은 남지만 조용한 손실이다).

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
```

> 문서 템플릿은 프로젝트에 복사하지 않는다 — `/dev-docs-generator`가
> `skills/dev-docs-generator/assets/doc-templates.md`를 정본으로 쓴다. 사본을 두면 갈린다.
>
> `council/` · `harness-evaluation/` 등 나머지 산출물 디렉토리는 해당 스킬이
> 처음 쓸 때 만든다. 빈 디렉토리는 git이 추적하지도 않으므로 미리 만들지 않는다.

### Step 9: .gitignore 업데이트

`.gitignore`에 다음 항목을 추가합니다 (이미 있으면 건너뜀):
```
.epcc/
```

### Step 9.5: 스택 가이드 확보 (질문 없음 · init을 붙잡지 않는다)

**init은 가이드를 기다리지 않는다.** 조립으로 끝나는 조합은 여기서 완결되고, 생성이
필요하면 스크립트가 작업을 등록한다.

> 근거: 생성 1회의 실측이 **수리 전 54분**이었고(`dev/docs/skill-review/contract-first-e2e-2026-08-22.md`)
> 그 끝에서도 감사자 둘 다 설치 불가 판정을 냈다. 설치 첫인상을 그 시간에 묶을 이유가 없다 —
> 가이드는 첫 컴포넌트·첫 핸들러를 쓸 때 필요하지 `init`이 끝나는 순간 필요한 것이 아니다.

#### 호출 1회로 끝난다 — 여기서 판정하지 않는다

팩이 쓸 만한가 · 이음매가 있는가 · 게이트를 돌릴 축이 어디인가 · 무엇이 남았는가는
**전부 `install-guide.sh`가 자기가 읽는 데이터로 정한다.** 그것을 이 자리에서 산문으로
다시 판정하면 사본이 갈린다 — 실제로 갈려서, 사전 제작 이음매가 없는 조합 25개에서
**방금 조립한 리소스를 지우는 규칙**이 됐던 것이 이 절의 이전 판이다.

```bash
# 두 축의 프리셋 notes를 넘긴다 — 가이드는 한 축의 함수가 아니라 조합의 함수다.
# 서버 코드가 어디 사는지(프론트 축) · 보안 경계가 어디인지 · 데이터 계층에 정책 엔진이
# 있는지(백엔드 축)가 두 가이드의 내용을 함께 결정한다
mkdir -p .epcc && cat > .epcc/preset-notes.json <<'JSON'
{ "serverCode": "<프론트 프리셋 notes>", "securityBoundary": "<백엔드 프리셋 notes>",
  "policyEngine": <true|false>, "language": "<TypeScript|JavaScript>" }
JSON

SEAM=""
[ -d "${CLAUDE_PLUGIN_ROOT}/guides/seams/<프론트>+<백엔드>" ] && SEAM="--seam <프론트>+<백엔드>"

bash "${CLAUDE_PLUGIN_ROOT}/scripts/install-guide.sh" \
  --frontend <프론트 프리셋|none> --backend <백엔드 프리셋|none> $SEAM \
  --gate --notes .epcc/preset-notes.json
```

출력 마지막의 `상태:` 한 줄이 결과 전부다:

| 상태 | 뜻 | 이 자리에서 할 일 |
| --- | --- | --- |
| `complete` | 스킬로 완성됐고 게이트를 통과했다 | 없음 |
| `resources` | 리소스만 조립됨 — 이음매 대기 (**정상 중간 상태**) | 없음 |
| `generate` | 팩이 없거나 미완이라 전체 생성이 필요하다 | 없음 |
| `pinned` | 이미 설치된 가이드의 스택 전제를 지켰다 | 없음 |
| `skip` | 그 축이 `none`이다 | 없음 |

- **`.epcc/guide-job.json`을 손으로 쓰지 않는다.** 남은 일이 있으면 스크립트가 쓰고,
  없으면 지운다. 축별로 무엇이 남았는지 아는 것은 그쪽이다
- **종료 코드 1**(게이트 FAIL)이면 그 축은 `.epcc/failed-guides/`로 내려가 있다.
  보고만 하고 **init은 계속한다** — 가이드가 없어도 T1 규칙 카드는 이미 작동한다
- **기준선 대조도 스크립트가 한다**(기본 켬). 출력에 메이저 상승이 보이면 손으로 판단하지
  말고 **그대로 옮겨 보고**한다. 재생성 여부는 묻지 않는다 — 사용자는 가이드가 낡았는지
  알 방법이 없어 감으로 답하게 되고, 그러면 그 질문은 매 세션의 소음이 된다

#### 남은 일이 있으면 — 하나만 묻고 끝낸다

```
확정된 조합: <프론트> × <백엔드>
가이드 상태: frontend=<상태> · backend=<상태>
남은 일: <guide-job.json의 need 그대로> — 지금 이어서 만들까요, 다음 세션에 만들까요?
(init 자체는 완료됐습니다. 가이드 없이도 T1 규칙 카드는 이미 작동합니다)
```

이어서 만든다고 하면 `stack-guide-generator`를 호출한다 — **인자를 정리해 넘길 필요가 없다.**
그 스킬이 `.epcc/guide-job.json`을 읽어 시작하고, 끝나면 그 파일을 닫는다.
아니면 여기서 끝낸다. `session-brief` 훅이 다음 세션에 미완 작업을 알린다.

> 이 한 가지만 묻는 이유: **지금 20분을 쓸지는 사용자의 시간에 대한 결정**이라 시스템이
> 대신 답할 수 없다. 반면 "사전 제작본을 쓸지 생성할지"는 구현 세부라 묻지 않는다.

#### 사전 제작본을 늘리는 기준

사전 제작 단위는 **조합이 아니라 축**이다. 조합 단위로 사전 제작하면 유지 불가능하고,
감사받지 않는 사전 제작본은 부패해서 **없는 가이드보다 나쁘다**(틀린 지침을 신뢰하게 만든다).

> **정기 감사 대상으로 등록할 수 있을 때만 사전 제작한다.** 축 팩은 이 기준을 충족한다 —
> 팩 하나를 감사하면 그 축을 쓰는 조합 전부가 함께 좋아진다.

### Step 10: 완료 보고

```
EPCC Devkit 초기 설정 완료!

생성된 파일:
  ✅ epcc.config.json
  ✅ CLAUDE.md
  ✅ .claude/rules/ (플러그인 규칙 카드 N개 + 프로젝트 전용 project-structure · code-conventions)
  ✅ dev/ 디렉토리 구조

가이드 (Step 9.5의 `상태:` 줄을 그대로 옮긴다 — 반쪽을 완성본으로 보고하지 않는다):
  ✅ .claude/skills/<축>-guide       — 스킬 완성 (complete)
  ⏳ .claude/skills/<축>-guide/      — 리소스만 · 이음매 대기 (resources)
  ⏳ <축>                            — 생성 필요 (generate)

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
