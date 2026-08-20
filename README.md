# EasyPeasy Claude Code Devkit

AI Native Dev Harness for Claude Code — 되돌림 가능성 축 워크플로우, 자기검증 훅, 그래프 계측.

![version](https://img.shields.io/badge/version-3.2.1-blue)
![license](https://img.shields.io/badge/license-MIT-green)

## 무엇인가

Claude Code 플러그인입니다. 코드 작업을 **되돌림 가능성**으로 분류해 필요한 만큼만 절차를
적용하고, 하네스 자신이 살아 있는지 스스로 검증합니다.

설계 원칙은 하나입니다 — **컴포넌트는 자기 존재를 증명하거나 죽는다.**
v2에서 훅 11개 중 10개가 경로 계산 오류와 출력 규격 불일치로 4개월간 조용히 죽어 있었고,
아무도 그것을 알아채지 못했습니다. v3는 그 실패가 구조적으로 불가능하도록 다시 만들었습니다.

## Quick Start

### 1. Install the Plugin

```bash
claude plugin install epcc-devkit
```

### 2. Initialize Your Project

프로젝트 디렉토리에서 Claude Code를 실행한 뒤:

```
/epcc-init
```

대화형으로 진행됩니다:
- 프리셋 선택 (nextjs-supabase, react-vite, python-fastapi, blank)
- 프로젝트 정보 수집
- `epcc.config.json` + `CLAUDE.md` 생성
- **`.claude/rules/`에 규칙 카드 설치** ← v3 신규
- `dev/` 디렉토리 구조 생성

### 3. Verify

```bash
bash scripts/doctor.sh
```

`통과 N · 경고 N · 실패 0`이면 정상입니다. 실패가 있으면 무엇이 왜 깨졌는지 함께 출력됩니다.

## 작업 분류 — 되돌림 가능성

규모(줄 수·파일 수)로 분류하지 않습니다. 규모는 사람 판단을 요구해 드리프트하고,
**틀린 변수를 봅니다** — 5줄 마이그레이션이 400줄 리팩토링보다 위험합니다.

| 클래스 | 판정 (경로 기반) | 요구 |
|--------|------------------|------|
| **Irreversible** | `**/migrations/**` · auth/RLS · 결제·정산 · 운영 데이터 | 리뷰 + 다관점 교차검증 + 사용자 확인 + 롤백 절차 |
| **Costly** | 공유 패키지 · public API · 타입 계약 · `**/api/**` | 리뷰 필수 + 영향 범위 제시 |
| **Reversible** | 그 외 전부 (기본값) | 바로 진행. 리뷰 선택 |

**진입 조건 4상태** — 의도 명확 · 컨텍스트 최신 · 영향 반경 파악 · 검증 경로 존재.
넷 다 충족이면 준비 작업 없이 곧바로 구현합니다. 충족된 항목을 위한 문서를 만들지 않습니다.

**단계**: `understand` / `plan` / `build` / `verify` / `cross-check` — 각각 독립 호출.
번호를 붙이지 않습니다. 번호는 의무를 만들고, 의무는 서류를 만듭니다.

## 구성 요소

| 계층 | 수 | 내용 |
|------|-----|------|
| **훅** | 5 스크립트 / 6 등록 | SessionStart · PreToolUse · Stop · PreCompact · SessionEnd · PostToolUse |
| **규칙** | T0 26줄 + T1 4개 242줄 | T0는 훅이 상시 주입(플러그인 소유), T1은 경로 매칭 시 조건부 로드 |
| **에이전트** | 2 | `epcc-planner`(쓰기 없음) · `epcc-reviewer`(읽기 전용) |
| **스킬** | 32 | 기획·구현·검증·보안·마케팅 워크플로우 + 스택 가이드 생성기 |
| **프리셋** | 4 | nextjs-supabase · react-vite · python-fastapi · blank |

### 훅

| 훅 | 이벤트 | 역할 |
|----|--------|------|
| `session-brief` | SessionStart | 운영 계약 주입 + HEAD·미커밋·열린 작업 + **훅 생존 현황** |
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
| **T1** 조건부 | `.claude/rules/*.md` (`paths:` 매칭) | 프로젝트 | 버전 스탬프로 드리프트 감지 |
| **T2** 참조 | 플러그인 스킬 | 플러그인 | ✅ |

T0을 훅 출력으로 둔 것이 핵심입니다 — 플러그인 소유라 자동 갱신되면서 상시 로드되므로,
규칙이 프로젝트에서 독립적으로 자라나는 드리프트가 구조적으로 불가능합니다.

### 에이전트

| 에이전트 | 도구 | 구조적으로 불가능해지는 것 |
|----------|------|---------------------------|
| `epcc-planner` | Read, Grep, Glob, WebSearch | 불필요한 문서 양산 (Write 없음) |
| `epcc-reviewer` | Read, Grep, Glob, Bash | 파일 무단 이동·수정 (읽기 전용) |

권한이 없으면 위반이 불가능합니다. 지시보다 권한 제거를 우선합니다.

## 자기검증 — `doctor`

CI가 없는 프로젝트를 전제로 설계했습니다. 사용자가 직접 칠 수 있는 단일 명령입니다.

```bash
bash scripts/doctor.sh              # 구조 검사 + 그래프 검증
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
기계 판독 가능한 형태로 선언합니다. 현재 노드 23 · 엣지 39.

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
생성합니다 (`stack-guide-generator`). 정확히 Next.js+Supabase 조합만 플러그인 원본을
그대로 사용합니다. 스택이 바뀌면 `/stack-guide-generator`로 재생성합니다.

## Available Presets

| Preset | Stack | Skills |
|--------|-------|--------|
| `nextjs-supabase` | Next.js 15 + Supabase + Tailwind + shadcn/ui | 플러그인 가이드 원본 사용 |
| `react-vite` | React + Vite + Tailwind | 가이드 **생성** (조합 확인 후) |
| `python-fastapi` | FastAPI + SQLAlchemy + Pydantic | 가이드 **생성** (조합 확인 후) |
| `blank` | Custom | 전체 차원 인터뷰 → 가이드 생성 |

## Project Override

플러그인 스킬을 커스터마이즈하려면 프로젝트의 `.claude/skills/`로 복사합니다:

```bash
mkdir -p .claude/skills/brainstorming
# 커스텀 SKILL.md 작성
```

프로젝트 파일이 항상 플러그인 파일보다 우선합니다.

## v2에서 업그레이드

```
/epcc-migrate
```

죽은 훅 제거, 규칙 3계층 재배치, 에이전트 개명을 수행합니다.
각 단계 후 `doctor --fast`로 확인하며 진행하고, 프로젝트 고유 자산은 보존합니다.

### v2 → v3 주요 변경

| 항목 | v2 | v3 |
|------|-----|-----|
| 훅 | 11개 (10개가 침묵 실패) | **5개, 전부 자기검증** |
| 규칙 | 697줄, 프로젝트 도달 경로 없음 | **T0 26줄 + T1 242줄, 설치 실증** |
| 작업 분류 | P0~P6 번호 + S/M/L 규모 | **되돌림 가능성 축 (경로 판정)** |
| 에이전트 | frontmatter 없음, 전체 도구 접근 | **계약 완비 + 최소 권한** |
| 스킬 | 37개 | **34개** (네이티브가 더 나은 것만 제거) |
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

> **판단 기준**: "네이티브가 존재한다"는 중복의 증거이지 열등의 증거가 아닙니다.
> 폐기를 제안하려면 양쪽 본문을 열어 커버 영역을 비교해야 하고, 비교 대상은
> 훼손되지 않은 최선 버전이어야 합니다.

## Next Steps

- [Configuration Reference](docs/configuration.md) — `epcc.config.json` 전체 옵션
- [Presets Guide](docs/presets.md) — 프리셋 상세

## License

MIT
