---
name: epcc-init
description: EPCC Devkit 프로젝트 초기 설정. epcc.config.json과 CLAUDE.md를 생성합니다. 새 프로젝트에서 처음 EPCC Devkit을 설정할 때 사용합니다.
disable-model-invocation: true
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
git remote get-url origin 2>/dev/null           # vcsPlatform — github.com / gitlab.com
```

실측으로 정해지는 것: 프로젝트 이름 · 프레임워크 · 언어 · 패키지 매니저 · 빌드/테스트/린트
명령 · 소스 디렉토리 · importAlias · 레포 토폴로지 · (deps로 추정한) 백엔드 축 ·
코드 호스팅 플랫폼.

remote URL에 `github.com`이 있으면 `github`, `gitlab.com`이 있으면 `gitlab`으로 **확정한다**
— 묻지 않는다. 자체 호스팅이거나 remote가 없어 판정되지 않을 때만 3차 호출에서 묻는다.
**신규 빈 프로젝트면 실측할 것이 없으므로 프리셋 기본값이 그 자리를 대신한다.**

### Step 0.5: 환경 점검 — `jq`

이 하네스의 검증 훅(`build-gate`)과 `doctor --graph`는 `jq`가 있어야 온전히 작동한다.
없어도 플러그인 설치·실행 자체는 되지만, 두 안전장치가 **에러 하나 없이 조용히
저하된다**(macOS는 기본 미설치, Windows는 Git Bash에도 기본 포함되지 않는다).

```bash
command -v jq >/dev/null 2>&1 && jq --version || echo "MISSING"
```

- **있으면** 아무 말 없이 Step 1로 넘어간다.
- **없으면** 짧게 알리고 설치 여부를 묻는다 (일반 확인이면 충분 — `AskUserQuestion` 예산을
  쓰지 않는다):

  > "`jq`가 없어서 빌드 검증과 그래프 검증이 저하된 상태로 시작합니다. 지금 설치할까요?"

  패키지 매니저를 탐지해 명령을 고른다 (먼저 발견되는 것 사용):

  | 탐지 | 설치 명령 |
  | --- | --- |
  | `command -v brew` | `brew install jq` |
  | `command -v winget` | `winget install --id jqlang.jq -e --source winget` |
  | `command -v apt-get` | `sudo apt-get install -y jq` |
  | `command -v dnf` | `sudo dnf install -y jq` |
  | `command -v apk` | `apk add jq` |
  | 위 전부 없음 | 자동화 불가 — https://jqlang.org/download/ 안내 후 건너뜀 |

  `sudo`가 필요한 경로는 먼저 `sudo -n <명령>`으로 비밀번호 없이 시도한다. 실패하면
  (비밀번호 프롬프트는 도구를 멈추게 하므로) **실행을 포기하고** 사용자가 직접 터미널에서
  돌릴 명령만 안내한 뒤 다음 단계로 넘어간다.

  거절하거나 설치가 실패해도 **초기화를 막지 않는다** — "설치 없이 계속 진행합니다.
  나중에 `<명령>`으로 설치할 수 있습니다"라고 안내하고 Step 1로 진행한다.

  이 단계는 **`jq` 설치만** 다룬다. Windows에서 이 확인 자체가 이상하게 동작하면(명령을
  못 찾는 등) 원인은 Git Bash 부재일 수 있는데, 그건 이 단계가 고치는 대상이 아니다 —
  [`docs/windows-setup.md`](../../docs/windows-setup.md)로 안내한다.

### Step 1: 기존 설정 확인

프로젝트 루트에서 다음 파일 존재 여부를 확인합니다:
- `epcc.config.json` — 있으면 "이미 설정되어 있습니다. 재설정하시겠습니까?" 확인
- `CLAUDE.md` — 있으면 백업 후 덮어쓸지 확인

### 인터뷰 규약 — 답이 뒤 질문의 목록을 바꾸는 것만 앞으로 올린다

Step 2·4·4.5·4.7은 원래 필수 대기 3곳 + 조건부 5곳이었다. Step 0 실측이 대부분을
채우므로 **남은 것만 묶어서 묻는다.** 한 번에 하나씩 묻는 것이 사람의 시간을 가장 많이 쓴다.

묶는 규칙은 **횟수가 아니라 의존성**이다. `AskUserQuestion`은 한 호출의 답을 **동시에**
받으므로, 앞 답이 뒤 질문의 **선택지 목록을 바꾸는 경우 같은 호출에 넣을 수 없다.**
도구 한도는 **질문 4개 · 선택지 4개**다.

| 호출 | 묶는 질문 | 왜 이 순서인가 |
| --- | --- | --- |
| **1차 — 무엇을 만드는가** | ① 제품 형태 ② 백엔드 유형 ③ 응답 언어 ④ 경험 수준 | ①이 프론트 목록을, ②가 백엔드 세부 목록을 가른다 |
| **2차 — 무엇으로 만드는가** | ⑤ 프론트엔드(①로 필터) ⑥ 백엔드 세부(②로 필터) ⑦ 언어 TS/JS 또는 PWA 여부 ⑧ 레포 토폴로지 | 목록이 확정된 뒤라야 물을 수 있다 |
| **3차 — 무엇 위에 올리는가** (조건부) | ⑨ 배포 대상(자체 서버 프레임워크일 때) ⑩ 백엔드 미확정 차원 ⑪ 코드 호스팅(Step 0에서 판정 실패했을 때만 — `github` · `gitlab`) ⑫ 실측 실패분 | ⑨는 ⑥에 의존한다 |

- **실측값이 있으면 그것을 기본 선택지 첫 번째로 둔다** — 대부분 그대로 확인만 하고 지난다
- **3차는 채울 것이 없으면 호출하지 않는다.** 사전 제작 조합은 대부분 2회로 끝난다
- 답이 갈라지는 질문만 묻는다. "사전 제작본을 쓸까 생성할까" 같은 구현 세부는 묻지 않는다
- 첫 질문은 **제품 용어로 묻는다** — "프론트엔드를 고르세요"는 답하려면 이미 알아야 하지만
  "무엇을 만듭니까"는 누구나 답한다

### Step 2: 프리셋 선택 (대화형)

스택은 **프론트엔드 축과 백엔드 축**으로 이루어지고, 그 위에 축이 아닌 **차원**이 얹힌다
(제품 형태·언어·배포 대상). 축은 팩을 고르고, 차원은 그 팩의 **조건부 슬롯**을 켜고 끈다.

```
① 무엇을 만듭니까 — 이 선택이 뒤 질문의 목록을 정합니다:
  1. 웹            — 브라우저로 접속. 설치 없음
  2. 하이브리드 앱  — 하나의 웹 코드로 웹과 스토어 앱을 함께 낸다 (Capacitor 등)
  3. 네이티브 계열  — React Native · Flutter · Swift · Kotlin
  4. API 전용      — 사용자 화면 없음
```

**이 질문이 정하는 것**은 프론트 목록만이 아니다. `deliveryModel`과 그 파생값
`clientKind`(웹이면 `browser`, 나머지 셋은 `app`)가 **백엔드·인프라 가이드의 슬롯**까지
가른다 — 토큰을 쿠키에 둘지 보안 저장소에 둘지, 멱등 배치 수집·푸시·API 버전 협상 절이
살아날지. **묻지 않으면 도달할 수 없는 정보다.**

```
② 프론트엔드를 고르세요:      ← ①이 목록을 가른다

  ▸ ①이 「웹」 또는 「하이브리드 앱」이면:
    1. nextjs      — Next.js 15 App Router + React 19 + Tailwind v4 + shadcn/ui + Zustand
    2. react-vite  — React + Vite SPA (SSR 없음) + Tailwind + React Router + TanStack Query + Zustand
    3. vue         — Vue 3 Composition API + Vite SPA (SSR 없음) + Tailwind + Vue Router + Pinia
    4. vanilla     — 프레임워크 없음, 표준 DOM + ES 모듈 (랜딩·위젯·경량 사이트)

  ▸ ①이 「네이티브 계열」이면 — **대응 축 팩이 없다.** 실제 기술만 받아
    `techStack.nativeStack`에 기록하고 프론트 축은 **생성 경로**를 탄다:
    1. React Native   2. Flutter   3. Swift / Kotlin   4. 기타(직접 입력)

  ▸ ①이 「API 전용」이면 — 묻지 않는다. 프론트 축은 `none`이다

   └ 언어: TypeScript(기본) / JavaScript — 프리셋 선택 후 확인합니다
   └ ①이 「웹」이면 PWA 여부도 함께 확인합니다 (서비스워커·오프라인 캐시·설치 프롬프트)

③ 백엔드 유형을 고르세요 — **이름만 다른 동급 항목이 아니라 형태가 셋이다**:
  1. BaaS          — 벤더가 DB·인증·스토리지를 함께 제공. 데이터 계층에 정책 엔진이 있다
  2. 서버리스 조립  — 관리형 서비스를 직접 조합. **행 수준 정책 엔진이 없을 수 있어**
                     애플리케이션 층 검사 비중이 커진다
  3. 자체 서버      — 상주 서버를 운영. 애플리케이션 층이 유일한 경계
  4. 없음           — 백엔드 없음 / 외부 REST API 소비

  ↳ 1. BaaS — 어느 벤더입니까:
      1. supabase        — PostgreSQL + RLS + Auth + Storage + Realtime
      2. firebase        — Firestore + Auth + Storage + Cloud Functions

  ↳ 2. 서버리스 조립 — 클라우드가 곧 런타임 모델이다:
      1. aws-serverless  — Lambda + API Gateway + DynamoDB + Cognito
      2. gcp-serverless  — Cloud Run/Functions + Firestore + Identity Platform

  ↳ 3. 자체 서버 — 먼저 프레임워크를 고른다:
      1. aws-container   — Hono + Drizzle · ECS/Fargate + RDS PostgreSQL + Cognito
                           (AWS 인프라까지 포함된 완제품. 온프레미스 이식을 전제로
                            AWS 종속을 인프라 층에만 둔다)
      2. fastapi         — **Python**: FastAPI + SQLAlchemy 2.0 + Pydantic v2 + Alembic
      3. node-api        — Express 5 + PostgreSQL + Prisma
      4. node-nest       — NestJS 11 + PostgreSQL + TypeORM 1 + class-validator
                           (모듈·DI·데코레이터가 구조를 정한다 — Express의 변형이 아니다)

      **`fastapi`만 Python이고 나머지 셋은 TypeScript다** — 툴체인이 갈리므로 프론트 축과
      명령이 달라진다.

      ↳ `fastapi`·`node-api`·`node-nest`를 골랐다면 **배포 대상(서버 구성)**도 고른다:
          1. 미정 / 클라우드 비종속 (기본값) — 어디에 배포하든 같은 가이드
          2. AWS                          — ECS/Fargate · EC2 등
          3. 그 외 (직접 입력)             — GCP · Azure · Vercel · 온프레미스
        `aws-container`는 AWS가 이미 확정이므로 이 질문을 하지 않는다.
```

**제품 형태는 `techStack.deliveryModel`에 기록한다** (`web`·`hybrid`·`native`·`api-only`).
「웹」이면 `techStack.pwa`를, 「네이티브 계열」이면 `techStack.nativeStack`을 함께 채운다.
그리고 **파생값을 config에 함께 쓴다**:

> `clientKind = (deliveryModel === 'web') ? 'browser' : 'app'`

각 팩이 제각기 재유도하면 서술이 갈리므로 **한 곳에서 정하고 팩은 이 값만 본다.**
하이브리드·네이티브 계열은 백엔드 입장에서 전부 같다 — "브라우저가 서버와 대화"가 아니라
**"앱이 API와 대화"**다.

| 슬롯 | `browser` | `app` |
| --- | --- | --- |
| 클라이언트 인증 전달 | 쿠키 세션 · CORS · CSRF 방어 | **Bearer + 보안 저장소**(쿠키 아님) |
| 멱등 수집 | 빈다 | **살아난다** — 오프라인 배치 동기화가 전제 |
| 푸시 발송 | 빈다 | 살아난다 (FCM/APNs) |
| API 버전 협상 | 빈다 | 살아난다 — 구버전 앱이 계속 돈다 |

**슬롯이 비는 것은 정상 경로다.** 웹 프로젝트의 백엔드 가이드에 푸시 절이 없는 것은 결함이
아니라 차원이 제대로 작동한 결과다.

> **충돌 경고 — 「하이브리드 앱」 × `nextjs`**: Capacitor 셸은 정적 자산을 싣기 때문에
> `output: 'export'`가 강제되고 **Server Actions·Route Handlers를 쓸 수 없다.** 이 조합이
> 나오면 사용자에게 알리고 ⓐ `react-vite`로 바꾸거나 ⓑ Next.js를 정적 내보내기로 쓰되
> 서버 기능을 백엔드 축에 두는 선택지를 제시한다. **제품 형태를 묻지 않으면 이 충돌을
> 검출할 방법이 없다.**

**배포 대상은 `techStack.backend.cloudProvider`에 기록한다** — 신규 필드가 아니라 스키마에
이미 있는 차원이다("미정"이면 `null`). 이 값이 비어 있으면 클라우드 비종속 가이드가 나가고,
채워져 있으면 Step 4.5와 Step 9.5가 그 클라우드의 인프라 지침을 요구 사항으로 취급한다.

> **왜 유형을 먼저 묻는가** — "AWS"는 백엔드 프레임워크가 아니라 배포 대상이다. 그런데
> 클라우드를 프론트·백엔드와 나란한 **자유 조합 축**으로 풀면 두 가지가 깨진다.
> ⓐ `aws-container`(Hono 컨테이너)와 `aws-serverless`(Lambda 핸들러)는 클라우드만 같고
> **프레임워크 자체가 다르다** — "같은 프레임워크에 클라우드만 바꾼다"가 성립하지 않는다.
> ⓑ 사전 제작 단위를 조합이 아니라 축으로 둔다는 결정(`docs/presets.md`)과 충돌해 조합이
> 폭발한다. 그래서 **인프라는 상주 서버 부류에서만 독립 차원으로 다룬다** — 서버리스와
> BaaS는 클라우드가 곧 아키텍처라 분리 대상이 아니다.

**언어(TypeScript/JavaScript)도, 제품 형태도 프리셋이 아니라 차원이다.** 축은 어느 팩을
쓸지 고르고, 차원은 그 팩의 **조건부 슬롯을 켜고 끈다** — 언어는 타입 표준 슬롯을,
제품 형태는 오프라인·셸·인증 전달·푸시 슬롯을 가른다. 그래서 **팩 자체는 어떤 차원 조합에도
성립해야 하고, 특화는 생성 시점에 일어난다.** 차원별 내용을 팩에 산문으로 박으면 그 팩은
한 형태에 기울어 나머지 조합에서 틀린 지침이 된다.

> **왜 2축인가**: 가이드 내용은 한 축의 함수가 아니라 **조합의 함수**다. 같은 Supabase라도
> Next.js와 짝지으면 Route Handlers·Server Actions 중심이고, React+Vite SPA와 짝지으면
> Edge Functions·브라우저 직접 호출 중심으로 **완전히 다른 가이드**가 된다. 두 축을 먼저
> 확정해야 서로를 고려한 가이드를 만들 수 있다.

`frontend: none`은 ①에서 「API 전용」을 고른 결과다 — 프론트엔드 축의 선택지가 아니라
제품 형태의 귀결이므로 ②에서 묻지 않는다. `frontend: none` + `backend: none` 조합은
이전의 `blank` 프리셋에 해당한다.

### Step 3: 프리셋 기본값 로드 (병합)

세 파일을 읽어 이 순서로 병합한다 (뒤가 앞을 덮어씀):

1. `${CLAUDE_PLUGIN_ROOT}/presets/base.json` — 공통 domains·보안 패턴
2. `${CLAUDE_PLUGIN_ROOT}/presets/frontend/<선택>.json`
3. `${CLAUDE_PLUGIN_ROOT}/presets/backend/<선택>.json`

병합 규칙:

- `additionalStack`은 덮어쓰지 않고 **누적**한다
- `domains.sourceDir`은 프론트엔드 축의 값을 우선한다. 프론트엔드가 `none`이면
  백엔드 축의 `sourceDir`을 쓴다. 두 축이 모두 있고 값이 다르면 사용자에게 확인받는다
- 각 프리셋의 `notes`는 config에 기록하지 않는다 — Step 9.5에서 가이드 생성 에이전트에
  **조합 맥락으로 전달**한다 (서로를 고려한 가이드를 만드는 근거)

### Step 4: 프로젝트 정보 수집 (대화형)

사용자에게 다음 정보를 질문합니다 (프리셋 기본값이 있으면 표시):

1. **프로젝트 이름** (필수)
2. **응답 언어** — 선택지 4개 + 「기타」(`AskUserQuestion`이 자동 제공하는 자유 입력)

   | 표시 | `language` | `languageLabel` |
   | --- | --- | --- |
   | 한국어 | `ko` | `한국어` |
   | English | `en` | `English` |
   | Bahasa Indonesia | `id` | `Bahasa Indonesia` |
   | Tiếng Việt | `vi` | `Tiếng Việt` |
   | 기타(직접 입력) | 입력값의 BCP-47 태그 | 그 언어의 **엔도님**(자기 언어 표기) |

   기타로 들어온 값은 모델이 정규화한다 — "태국어"·"Thai"·"ภาษาไทย" → `th` / `ภาษาไทย`.
   태그를 확정할 수 없으면 `language`는 비우고 `languageLabel`만 채운다.
   **두 값 모두 config에 쓴다.** `session-brief.sh`가 이걸 읽어 T0 운영 규칙의
   `{{RESPONSE_LANGUAGE}}`를 치환한다 — 여기서 쓰지 않으면 언어 선택이 도달하지 않는다.

   이 선택이 정하는 것은 **최종 출력 언어**뿐이다. 분석·추론은 항상 영어이고,
   업계에서 영어로 통용되는 전문용어(`Bottom Sheet` · `GNB` · `middleware`)는
   어떤 언어를 골라도 영어 원어로 남는다 — 이 규범의 정본은 T0다.
3. **경험 수준** — senior / mid / junior (기본: senior)
4. **축별 프레임워크·언어·패키지 매니저** (병합된 프리셋 기본값 확인)
5. **빌드/테스트/린트 명령어** (프리셋 기본값 확인)
6. **소스 디렉토리** (Step 3 병합 규칙의 결과를 확인)
7. **공유 패키지 경로** (`monorepo`·`msa`면 필수 — Step 4.7 참조. `single`이면 생략)

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

1. monorepo — 루트 앱 + 공유 패키지 (packages/)                    (기본값)
   ↳ 두 곳 이상이 쓰는 코드가 있을 때. 웹+관리자, 앱+랜딩, 공유 UI·타입·유틸
   ↳ packages/는 Costly로 분류되어 수정 시 리뷰가 한 단계 더 붙습니다

2. single   — 앱 하나
   ↳ 아직 공유할 대상이 없을 때. 프로토타입·단일 서비스
   ↳ 나중에 packages/가 생기면 그때 monorepo로 올리면 됩니다 (되돌리기 쉬움)

3. msa      — 서비스 여러 개 (services/·apps/)
   ↳ 배포 단위가 여러 개일 때. 서비스 간 API·이벤트 계약을 따로 관리합니다

고르기 어려우면 — 지금 두 곳 이상이 쓰는 코드가 있습니까?
  있다 → 1   ·   없다 → 2   ·   따로 배포한다 → 3
```

- **실측이 기본값을 이긴다.** 기존 저장소에 `packages/`·`services/`가 없으면 `single`을
  기본값으로 제시한다. `monorepo` 기본값은 **신규 프로젝트와 실측 판정 불가일 때만** 적용된다
- 공유 패키지 경로(Step 4 항목 7)는 **`single`을 고를 때만 건너뛴다** — `monorepo`·`msa`는 필수다.
  그 경로가 없으면 Step 7.5가 구조 카드의 `paths:`를 채우지 못하고, `paths:`가 비면
  그 카드는 공유 코드 위에서 영영 로드되지 않는다
- 선택 결과는 Step 5의 `domains.repoTopology`와 Step 7.5의 구조 카드 생성에 쓰인다

> **선택지에 부연을 붙이는 이유** — 기본값만 있고 판단 근거가 없으면 사용자는 그냥
> 기본값을 누르고, 앱 하나짜리 프로젝트가 빈 `packages/`를 안고 시작한다.
> 판정 질문은 규모가 아니라 **"지금 두 곳 이상이 쓰는 코드가 있는가"** 하나다 —
> 규모로 물으면 "앞으로 커질 것 같다"는 답이 나오고, 그것은 근거가 아니다.
>
> 그리고 구조가 막아주는 것은 **리뷰 요구까지**다. "A를 고치다 B가 깨졌다"를 실제로
> 알려주는 것은 B의 테스트이고, 구조는 그 테스트를 독립적으로 돌릴 수 있게 할 뿐이다.

### Step 5–6: epcc.config.json · CLAUDE.md 생성

**`assets/config-and-claude-md.md`를 읽고 그대로 따른다.**

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
| `harness-change.md` | `.claude/**` `scripts/**` `hooks/**` `dev/docs/harness-evaluation/**` 편집 시 |
| `lessons.md` | 소스·`.claude/**`·`scripts/**`·`dev/docs/**` 편집 시 |
| `doc-dependency.md` | `dev/docs/{prd,database,design,architecture,api}/**` 편집 시 |
| `data-modeling.md` | `supabase/**` `**/migrations/**` `db/**` `prisma/**` 등 DB 경로 편집 시. §1~8만 담고 열 가지 패턴은 `.claude/references/data-modeling/`으로 내려 **필요한 것만** 읽는다 |
| `ui-design.md` | `**/components/**` `**/*.{css,scss}` `**/app/**/page.{tsx,jsx}` `**/app/**/layout.{tsx,jsx}` 편집 시 |

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
2.5. **「의존 방향」 절을 채운다** — 기존 코드가 있으면 import가 실제로 흐르는 방향을
   실측하고, 신규면 프리셋 토폴로지의 방향을 적는다. 레이어가 없으면
   「단층 — 해당 없음」이라고 적는다. **억지로 세우지 않는다** — 없는 레이어를
   카드에 적으면 `epcc-reviewer`가 존재하지 않는 위반을 보고한다
3. 플레이스홀더와 안내 주석을 전부 치환·제거하고 `.claude/rules/` 아래
   `project-structure.md`로 저장한다
4. `${CLAUDE_PLUGIN_ROOT}/templates/rules/code-conventions.template.md`도 같은 방식 —
   프리셋에 맞는 **스택 블록 하나만** 남기고, 공통 블록(네이밍·코드 스타일·커밋 규약)은
   유지한다. 기존 린트 설정·CLAUDE.md에 프로젝트 고유 규약이 있으면 사용자 확인 후 반영해
   `code-conventions.md`로 저장한다
5. 두 카드의 `paths:` frontmatter가 **실제 소스 디렉토리**(Step 4 입력값)를 가리키는지
   확인한다 — paths가 틀리면 카드는 영영 로드되지 않는다.
   **토폴로지가 요구하는 경로도 함께 확인한다** — `monorepo`면 공유 패키지 경로가,
   `msa`면 서비스 루트들이 `paths:`에 실재해야 한다. **없으면 카드를 저장하지 않고**
   Step 4.7·Step 4로 돌아가 경로를 확정한 뒤 다시 생성한다.
   소스 디렉토리만 덮는 카드는 공유 코드 위에서 한 번도 뜨지 않는다 —
   그런 카드는 없는 카드보다 나쁘다(있다고 믿게 만든다)

> 이 두 카드에는 `epcc-rule-version` 스탬프를 넣지 않는다 — 프로젝트 소유임을 표시한다.
>
> **보호 기제는 스탬프가 아니라 이름 비충돌이다.** `install-rules.sh`는 플러그인
> `rules/*.md`만 순회하므로(`for f in "$SRC"/*.md`), `rules/`에 같은 이름이 없는 한
> 후보에 오지 않는다. 따라서 **플러그인 `rules/`에 `project-structure.md` ·
> `code-conventions.md`를 만들지 않는다** — 만드는 순간 무스탬프 타겟이 `0.0.0`으로
> 읽혀 프로젝트 사본이 덮어써진다(`.bak`은 남지만 조용한 손실이다).

### Step 8–9.5: dev/ · .gitignore · 스택 가이드 확보

**`assets/scaffold-and-guide.md`를 읽고 그대로 따른다.**

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
- 시크릿 차단은 `security-check.sh` 훅에 **내장**되어 있습니다 — 프로젝트 설정 항목이 아닙니다
