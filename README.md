# EasyPeasy Claude Code Devkit

AI Native Dev Harness for Claude Code — 되돌림 가능성 축 워크플로우, 자기검증 훅, 그래프 계측.

![version](https://img.shields.io/badge/version-3.25.0-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## 무엇인가

Claude Code 플러그인입니다. 코드 작업을 **되돌림 가능성**으로 분류해 필요한 만큼만 절차를
적용하고, 하네스 자신이 살아 있는지 스스로 검증합니다.

설계 원칙은 하나입니다 — **컴포넌트는 자기 존재를 증명하거나 죽는다.**
v2에서 훅 11개 중 10개가 경로 계산 오류와 출력 규격 불일치로 4개월간 조용히 죽어 있었고,
아무도 그것을 알아채지 못했습니다. v3는 그 실패가 구조적으로 불가능하도록 다시 만들었습니다.

> **각 장치가 왜 그 자리에 그 형태로 있는지**는 [하네스 해부](docs/harness-anatomy.md)에
> 정리되어 있습니다 — 훅 5종·규칙 3계층·루프 5종·그래프 엔지니어링을 각각이 막는 실패에서
> 출발해 설명하고, 작업 1건을 끝까지 추적하는 워크스루로 넷을 한 번에 보여줍니다.

## Quick Start

### 1. Install the Plugin

```bash
claude plugin install epcc-devkit
```

> **설치 전 확인** — 마켓플레이스가 읽는 것은 **`origin/main`**입니다. 릴리스 태그
> (`epcc-devkit--v{version}`)와 main 병합이 끝난 버전만 소비자에게 도달합니다.
> 아직 병합되지 않은 브랜치를 쓰려면 저장소를 직접 등록하세요:
>
> ```bash
> claude plugin marketplace add <이 저장소 경로>
> claude plugin install epcc-devkit@easy-peasy-devkit
> ```

**마케팅 스킬은 별도 플러그인입니다.** 같은 마켓플레이스에 `epcc-marketing`(스킬 5종 —
AI 프롬프트 · 스크롤 드리븐 사이트 · SEO 3-Mode · 웹 에셋)이 함께 있고, **독립 버전**으로
나갑니다. 개발 하네스에서 분리한 이유는 컨텍스트 예산입니다 — 스킬 description은 그 스킬을
한 번도 쓰지 않아도 매 세션 상주하므로, 개발과 무관한 스킬이 개발 세션의 예산을 먹습니다.
필요할 때만 설치하세요:

```bash
claude plugin install epcc-marketing@easy-peasy-devkit
```

### 2. Initialize Your Project

프로젝트 디렉토리에서 Claude Code를 실행한 뒤:

```
/epcc-init
```

대화형으로 진행됩니다:
- 프리셋 선택 — 프론트엔드 축(nextjs·react-vite·vue·vanilla·none) + 백엔드 축(supabase·firebase·aws-serverless·aws-container·gcp-serverless·fastapi·node-api·node-nest·none)
- 프로젝트 정보 수집
- `epcc.config.json` + `CLAUDE.md` 생성
- **`.claude/rules/`에 규칙 카드 설치** ← v3 신규
- `dev/` 디렉토리 구조 생성

### 3. Verify

새 세션의 브리핑에 표시되는 **'자기검증'** 줄의 명령을 그대로 실행합니다
(플러그인 설치 경로 기준 절대 경로가 표시됩니다):

```bash
bash "<플러그인-루트>/scripts/doctor.sh"
```

`통과 N · 경고 N · 실패 0`이면 정상입니다. 실패가 있으면 무엇이 왜 깨졌는지 함께 출력됩니다.

## 작업 분류 — 되돌림 가능성

규모(줄 수·파일 수)로 분류하지 않습니다. 규모는 사람 판단을 요구해 드리프트하고,
**틀린 변수를 봅니다** — 5줄 마이그레이션이 400줄 리팩토링보다 위험합니다.

> 아래는 `templates/operating-contract.md`의 **인용**입니다. 정본은 그 파일이며,
> 값이 갈리면 그쪽이 옳습니다.

| 클래스 | 판정 (경로 기반) | 요구 — 누가 하는가 |
|--------|------------------|------|
| **Irreversible** | `**/migrations/**` · auth/RLS · 결제·정산 · 운영 데이터 | `epcc-reviewer` 다관점 팬아웃 + 사용자 확인 + 롤백 절차 |
| **Costly** | 공유 패키지 · public API · 타입 계약 · `**/api/**` · `**/actions.ts` · `**/middleware.ts` · 생성 파일 | `epcc-reviewer` 필수 (자기 리뷰 불가) |
| **Reversible** | 그 외 전부, 테스트 코드 포함 (기본값) | 바로 진행. 마무리는 `/completion-review` |

**진입 조건 4상태** — 의도 명확 · 컨텍스트 최신 · 영향 반경 파악 · 검증 경로 존재.
넷 다 충족이면 준비 작업 없이 곧바로 구현합니다. 충족된 항목을 위한 문서를 만들지 않습니다.

**두 축은 직교합니다.** 되돌림 클래스가 *얼마나 검증할지*를 정하고,
`.claude/rules/workflow-routing.md`의 **작업 라우팅 표(P0~P6)** 가 *무엇을 어떤 순서로
만들지*를 정합니다. 이 카드는 `paths:`가 없어 **매 세션 무조건 로드**됩니다.
Phase 번호는 순서 표시일 뿐 의무가 아닙니다 — 진입 조건 4상태가 충족되면 P0~P3을 건너뜁니다.

## 구성 요소

| 계층 | 수 | 내용 |
|------|-----|------|
| **훅** | 5 스크립트 / 6 등록 | SessionStart · PreToolUse · Stop · PreCompact · SessionEnd · PostToolUse |
| **규칙** | T0 40줄 + T1 9개 1,265줄 | T0는 훅이 상시 주입(플러그인 소유). T1은 `workflow-routing`이 **매 세션 상시**, 나머지는 경로 매칭 시 조건부 로드 |
| **에이전트** | 2 | `epcc-planner`(쓰기 없음) · `epcc-reviewer`(읽기 전용) |
| **스킬** | 27 | 측량·기획·구현·검증·보안·PR 워크플로우 + 스택 가이드 생성기 + 스킬 강화기 (마케팅 5종은 `epcc-marketing` 플러그인으로 분리) |
| **프리셋** | 2축 5+9 | 프론트엔드: nextjs·react-vite·vue·vanilla·none / 백엔드: supabase·firebase·aws-serverless·aws-container·gcp-serverless·fastapi·node-api·node-nest·none |

### 훅

| 훅 | 이벤트 | 역할 |
|----|--------|------|
| `session-brief` | SessionStart | 운영 규칙 주입 + **T1 카드 누락분 자동 설치** + HEAD·미커밋·열린 작업 + **훅 생존 현황** |
| `security-check` | PreToolUse | 시크릿 하드코딩 차단 (exit 2) |
| `build-gate` | Stop | 소스 수정 후 빌드/테스트 미실행 시 차단 |
| `handoff` | PreCompact · SessionEnd | 컴팩트·종료 시 작업 상태 보존 |
| `track-skill` | PostToolUse | 스킬 호출 계측 — 측정 없이 컬링하지 않기 위해 |

모든 훅은 `scripts/lib/common.sh`를 공유합니다. 프로젝트 루트를 확정할 수 없으면
**추측하지 않고 exit 2로 차단**하며, 매 실행을 `.claude/.epcc/hookrun.log`에 기록해
다음 세션 브리핑이 죽은 훅을 보고합니다.

### 규칙 3계층

| 계층 | 매체 | 소유 | 자동 갱신 |
|------|------|------|-----------|
| **T0** 상시 | `session-brief` 훅이 출력 | 플러그인 | ✅ |
| **T1** 상시 | `.claude/rules/workflow-routing.md` (`paths:` 없음 → 매 세션 로드) | 프로젝트 | 버전 스탬프로 드리프트 감지 |
| **T1** 조건부 | `.claude/rules/*.md` (`paths:` 매칭) | 프로젝트 | 버전 스탬프로 드리프트 감지 |
| **T2** 참조 | 플러그인 스킬 | 플러그인 | ✅ |

T0을 훅 출력으로 둔 것이 핵심입니다 — 플러그인 소유라 자동 갱신되면서 상시 로드되므로,
규칙이 프로젝트에서 독립적으로 자라나는 드리프트가 구조적으로 불가능합니다.

여기에 더해 `/epcc-init`이 **프로젝트 소유 카드 2장**(project-structure ·
code-conventions)을 생성합니다 — 레포 토폴로지(싱글/모노레포/MSA)와 실측 트리,
프리셋에 맞는 컨벤션으로 채워지며, 버전 스탬프가 없어 플러그인 갱신의 영향을 받지 않습니다.

### 에이전트

| 에이전트 | 도구 | 구조적으로 불가능해지는 것 |
|----------|------|---------------------------|
| `epcc-planner` | Read, Grep, Glob, WebSearch | 불필요한 문서 양산 (Write 없음) |
| `epcc-reviewer` | Read, Grep, Glob, Bash | 파일 무단 이동·수정 (읽기 전용) |

권한이 없으면 위반이 불가능합니다. 지시보다 권한 제거를 우선합니다.

## 자기검증 — `doctor`

CI가 없는 프로젝트를 전제로 설계했습니다. 사용자가 직접 칠 수 있는 단일 명령입니다.
소비자 프로젝트에서는 `<플러그인-루트>/scripts/doctor.sh`를 사용하세요 (세션 브리핑에 절대 경로 표시).
플러그인 자산 검사(--fast·--graph·--self-test)는 플러그인 루트를, 프로젝트 상태
검사(--usage·--lessons)는 현재 프로젝트를 자동으로 봅니다.

```bash
bash scripts/doctor.sh              # 구조 검사 + 그래프 검증 (devkit 저장소 개발 시)
bash scripts/doctor.sh --self-test  # 훅에 이벤트별 픽스처 주입 → 효과 대조
bash scripts/doctor.sh --graph      # 도달 불가 노드 · dangling 엣지 · 에러 엣지 누락
bash scripts/doctor.sh --usage      # 훅 생존 · 스킬 호출 · 엣지 traversal
bash scripts/doctor.sh --lessons    # 교훈 집계 + 승격 후보
bash scripts/doctor.sh --all        # 전체
```

검사 항목:
- **금지 관용구** — `BASH_SOURCE` 상대 루트 계산, `|| echo 0` 폴백
- **훅 출력 규격** — 이벤트가 지원하지 않는 JSON 필드 사용 (Stop의 `decision`/`reason` 등)
- **규칙 도달성** — 선언됐지만 프로젝트에 도달할 경로가 없는 자산
- **dangling 참조** — 존재하지 않는 파일을 가리키는 링크
- **에이전트 계약** — `name`·`description`·`tools`·`model` 완비 여부
- **매니페스트 정합** — 버전 단일 소스, 미구현 설정 필드

## 그래프 선언

`workflow.graph.json`이 노드(에이전트·스킬·훅)와 엣지(전이 조건), **에러 엣지**를
기계 판독 가능한 형태로 선언합니다. 현재 노드 46 · 엣지 78.

`doctor --graph`가 검증합니다:
- 모든 엣지의 타깃이 실재하는가
- 인바운드 엣지가 없는 노드가 있는가 (= 도달 불가 자산)
- 모든 실행 노드가 에러 엣지를 선언했는가 (실패 경로가 그래프에 없으면 실패는 조용히 사라진다)

`doctor --usage`는 실제 실행된 엣지를 집계합니다. "이 스킬은 안 쓰인다"가 **주장이 아니라 측정**이 됩니다.

## Zero-Config Mode

`epcc.config.json` 없이도 동작합니다. 훅 5종과 되돌림 축 워크플로우는 항상 활성입니다.
설정을 추가하면 다음이 활성화됩니다:
- 프로젝트별 시크릿 패턴
- 빌드/테스트 명령 인식 (`build-gate`가 구체적 명령을 안내)

## 스택 가이드 — 프리셋은 기본값, 조합은 선택

프리셋은 백엔드를 고정하지 않습니다. `/epcc-init`이 백엔드 유형(BaaS·클라우드 자체
구축·프레임워크 내장)·클라우드·DB(PostgreSQL·MongoDB 등)·데이터 액세스·인증을 확인하고,
확정된 조합에 맞는 `frontend-guide`·`backend-guide` 스킬을 프로젝트 `.claude/skills/`에
생성합니다 (`stack-guide-generator`). 사전 제작본이 있는 세 조합(`nextjs`×`supabase`,
`react-vite`×`aws-container`, `vue`×`node-api`)만 플러그인 원본을 그대로 씁니다. 사전 제작본을 쓸지
생성할지는 **시스템이 조합을 보고 정하며 묻지 않습니다.** 스택이 바뀌면
`/stack-guide-generator`로 재생성합니다.

## Available Presets

| Preset | Stack | Skills |
|--------|-------|--------|
| `nextjs` × `supabase` | Next.js 15 + Supabase + Tailwind + shadcn/ui | 사전 제작본 사용 |
| `react-vite` × `aws-container` | React+Vite SPA + ECS/Fargate + RDS PostgreSQL + Drizzle | 사전 제작본 사용 |
| `vue` × `node-api` | Vue 3 SPA + Express 5 + PostgreSQL + Prisma | 사전 제작본 사용 |
| `none` × `none` | Custom | 가이드 없음 (Core만) |
| 그 외 모든 조합 | 두 축의 조합 | 가이드 **생성** (검증 루프 포함) |

## Project Override — 사용자 자산의 우선권

**규범부터** — 파일 메커니즘 이전에, 모델이 따르는 우선순위가 명시되어 있습니다
(`.claude/rules/workflow-routing.md` 「지시 우선순위」, 매 세션 상시 로드). 두 층은 방향이
반대입니다:

- **안전 바닥** (되돌림 분류 · 검증 의무 · 시크릿 경계 · 분기점) — 프로젝트는 **올릴 수만**
  있습니다. 내리려면 사용자의 명시 요청이 필요합니다.
- **절차·양식** (가이드 팩의 스택 관행 · 스킬 워크플로 · 네이밍 · 문서 형식) —
  **프로젝트가 이깁니다.** 순서는 사용자 요청 → 프로젝트 `CLAUDE.md`·`AGENTS.md` →
  프로젝트 `.claude/rules/`·`docs/` → **저장소의 기존 코드 패턴** → 플러그인 가이드·스킬.

핵심은 마지막 화살표입니다 — **기존 코드 패턴이 플러그인 가이드를 이깁니다.** 가이드가
권하는 형태와 저장소가 실제로 쓰는 형태가 다르면 저장소를 따릅니다. 그리고 소비자가 원래
갖고 있던 `AGENTS.md`·`CODEX.md`·`.github/`·`docs/`·기존 `CLAUDE.md`는 **명시 요청 없이
고치지 않습니다**(비침습).

아래는 그 규범을 파일 수준에서 뒷받침하는 메커니즘입니다.

| 자산 | 우선 메커니즘 |
|------|--------------|
| 규칙 (`.claude/rules/`) | **프로젝트 소유** — install-rules가 사용자 수정본을 감지하면 보존 (버전 스탬프) |
| 훅 (`settings.json`) | 프로젝트 훅과 플러그인 훅이 **모두** 실행됨 (병존, 충돌 없음) |
| 스킬 | 플러그인 스킬은 `epcc-devkit:이름`으로, 프로젝트 스킬은 `이름`으로 **병존**합니다. 강한 우선권이 필요하면 **다른 이름 + description에 경계 선언**이 확실합니다 — 이 플러그인이 스택 가이드를 프로젝트의 `frontend-guide`로만 두고 플러그인 쪽에는 스킬이 아닌 **축 팩**(`guides/`)으로 둔 이유가 그것입니다 — 이름이 겹치지 않으면 우선권 다툼 자체가 없습니다 |

커스터마이즈 예:

```bash
mkdir -p .claude/skills/my-brainstorming
# 커스텀 SKILL.md 작성 — description에 "브레인스토밍은 이 스킬을 우선 사용" 명시
```

플러그인 파일 자체는 수정하지 마세요 — 업데이트 시 덮어써집니다. 모든 커스터마이즈는
프로젝트 쪽(`.claude/`)에서 하며, 플러그인은 이를 존중하도록 설계되어 있습니다.

## v2에서 업그레이드

```
/epcc-migrate
```

죽은 훅 제거, 규칙 3계층 재배치, 에이전트 개명을 수행합니다.
각 단계 후 `doctor --fast`로 확인하며 진행하고, 프로젝트 고유 자산은 보존합니다.

### v2 → v3 주요 변경

| 항목 | v2 | v3 |
|------|-----|-----|
| 훅 | 11개 (Stop의 `decision`/`reason` 등 출력 규격 위반으로 다수가 무효) | **5개, 전부 자기검증** |
| 규칙 | generator가 `.claude/rules/`에 복사 (무조건 로드 3장 + 조건부 11장) | **T0 40줄 + T1 1,097줄, `install-rules.sh`로 설치 실증. 상시/조건부 구분 유지** |
| 검증 강도 | S/M/L 규모 판단 | **되돌림 가능성 축 (경로 판정)** |
| Phase | P0~P6 (`.claude/rules/task-workflow.md` 상시 로드) | **P0~P6 유지** — `workflow-routing.md`로 이관, 상시 로드 성질 보존 |
| 에이전트 | frontmatter 없음, 전체 도구 접근 | **계약 완비 + 최소 권한** |
| 스킬 | 37개 | **30개** (네이티브가 더 나은 것만 제거, 가이드 생성기·강화기·축약 원장 추가) |
| 검증 | 없음 | **`doctor` 5개 모드** |
| 그래프 | 산문으로 흩어짐 | **`workflow.graph.json` + 계측** |

**제거된 것**: `persistent-loop`·`loop-keyword-detector`(→ 네이티브 `/loop`) ·
`skill-generator`(→ `skill-creator` — 방법론은 대등하나 네이티브만 A/B 실측 평가를 제공) ·
`requesting-code-review`(→ 네이티브 `/code-review`. 단 계획·PRD 대조는 `epcc-reviewer`로 이관) ·
PostToolUse 추적기 3종

**제거하지 않은 것**: 네이티브가 존재해도 **커버 영역이 다르면 유지**합니다.

| 스킬 | 네이티브가 다루지 않는 영역 |
| --- | --- |
| `/security-review` | 내장은 브랜치 diff 전용이고 시크릿을 명시적으로 제외합니다. 이 스킬은 코드베이스 전수 감사·의존성 CVE·결제 보안을 담당 |
| `/receiving-code-review` | 내장은 지적을 *생성*합니다. 받은 지적을 *비판적으로 검증*하는 대응물은 없습니다 |
| `/harness-evaluation` | `doctor`는 측정(훅 생존·dangling·예산), 이 스킬은 판단(설계가 좋은가·지금 모델에 과잉인가) |
| `/shortcut-ledger` | 내장 `/simplify`는 **이미 쓴** 코드를 줄입니다. 의도적으로 남긴 축약의 천장이 만료됐는지 추적하는 대응물은 없습니다 (쓰기 전 규범 자체는 `code-change.md` 「구현 사다리」) |
| `/codebase-survey` | 내장 `/init`은 `CLAUDE.md`를 **한 번** 만듭니다. `epcc-init`도 최초 1회만 실측하고, 그렇게 만든 프로젝트 소유 카드 두 장(`project-structure`·`code-conventions`)에는 **갱신 경로도 드리프트 감지 장치도 없습니다.** 이 스킬이 그 갱신 경로이며, 구조를 처방하지 않고 측정·서술만 합니다 |
| `/pr-prep` | 내장 `/code-review`는 diff의 **결함**을, `epcc-reviewer`는 **계약**을, `/completion-review`는 **문서**를 다룹니다. **PR 본문을 만드는 대응물은 없습니다** — 되돌림 클래스가 의무 섹션(롤백 절차·호출처·개입 근거)을 정하는 형태는 이 하네스 고유입니다 |

> **판단 기준**: "네이티브가 존재한다"는 중복의 증거이지 열등의 증거가 아닙니다.
> 폐기를 제안하려면 양쪽 본문을 열어 커버 영역을 비교해야 하고, 비교 대상은
> 훼손되지 않은 최선 버전이어야 합니다.

## Next Steps

- [하네스 해부](docs/harness-anatomy.md) — 훅·규칙 3계층·루프·그래프가 **왜 그렇게 구현됐는가**
- [Configuration Reference](docs/configuration.md) — `epcc.config.json` 전체 옵션
- [Presets Guide](docs/presets.md) — 프리셋 상세

## License

MIT
