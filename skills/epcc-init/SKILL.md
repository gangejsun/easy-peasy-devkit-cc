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
    "additionalStack": []
  },

  "domains": {
    "sourceDir": "<입력값>",
    "sharedPackage": "<입력값>",
    "importAlias": "<입력값>"
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

- `bash scripts/doctor.sh` — 하네스 자기검증
- `bash scripts/doctor.sh --usage` — 훅 생존·계측
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

**설치 후 반드시 확인**하세요:

```bash
ls .claude/rules/
```

파일이 0개면 설치가 실패한 것입니다. 사용자에게 보고하고 중단하세요.

> 상시 규범(T0)은 파일이 아니라 `session-brief` 훅이 매 세션 출력합니다.
> 플러그인 소유이므로 자동 갱신되며 프로젝트가 수정할 수 없습니다.

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

### Step 10: 완료 보고

```
EPCC Devkit 초기 설정 완료!

생성된 파일:
  ✅ epcc.config.json
  ✅ CLAUDE.md
  ✅ .claude/rules/ (규칙 카드 N개)
  ✅ dev/ 디렉토리 구조

검증:
  bash scripts/doctor.sh

다음 단계:
  1. CLAUDE.md를 검토하고 프로젝트 고유 정보를 채우세요
  2. Claude Code를 재시작하면 하네스가 활성화됩니다
```

## 주의사항

- 이 스킬은 프로젝트 루트에 파일을 생성합니다
- 기존 `CLAUDE.md`가 있으면 반드시 백업 여부를 확인하세요
- `epcc.config.json`의 `security.secretPatterns`는 프리셋 기본값이 자동 적용됩니다
