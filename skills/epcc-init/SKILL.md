---
name: epcc-init
description: |
  EPCC Devkit 프로젝트 초기 설정. epcc.config.json과 CLAUDE.md를 생성합니다.
  새 프로젝트에서 처음 EPCC Devkit을 설정할 때 사용합니다.
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

  "workflow": {
    "p0": { "enabled": true },
    "p6": { "enabled": true }
  },

  "customResources": {},
  "disabledSkills": []
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
- **프로젝트 구조**: 모노레포 (루트 앱 + `<공유 패키지>`). 상세 → `.claude/rules/project-structure.md`

## 개발 명령어

- 빌드: `<빌드 명령>` | 테스트: `<테스트 명령>` | 린트: `<린트 명령>`

## 코딩 컨벤션

- 상세 규칙 → `.claude/rules/code-conventions.md`

---

## 작업 워크플로우

**코드 작업** (신규 기능, 기존 기능 수정, 버그 수정, 리팩토링 등):
→ `.claude/rules/task-workflow.md` 자동 적용

**비코드 작업** (위 코드 작업 외 모든 작업):
→ 워크플로우 미적용 / 직접 수행
```

### Step 7: dev/ 디렉토리 생성

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

### Step 8: .gitignore 업데이트

`.gitignore`에 다음 항목을 추가합니다 (이미 있으면 건너뜀):
```
.epcc/
```

### Step 9: 완료 보고

```
EPCC Devkit 초기 설정 완료!

생성된 파일:
  ✅ epcc.config.json
  ✅ CLAUDE.md
  ✅ dev/ 디렉토리 구조

다음 단계:
  1. CLAUDE.md를 검토하고 필요시 수정하세요
  2. 프로젝트에 code-conventions.md나 project-structure.md가 필요하면
     .claude/rules/ 에 직접 생성하세요
  3. Claude Code를 재시작하면 EPCC 워크플로우가 활성화됩니다
```

## 주의사항

- 이 스킬은 프로젝트 루트에 파일을 생성합니다
- 기존 `CLAUDE.md`가 있으면 반드시 백업 여부를 확인하세요
- `epcc.config.json`의 `security.secretPatterns`는 프리셋 기본값이 자동 적용됩니다
