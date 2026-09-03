<!-- epcc-init 전용 자산. SKILL.md에서 절차 순서대로 호출된다.
     본문에 두면 인터뷰가 끝나기도 전에 486줄이 전부 컨텍스트에 들어간다. -->

# Step 5–6: epcc.config.json · CLAUDE.md 생성

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
