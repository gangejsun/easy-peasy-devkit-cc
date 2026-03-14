---
name: skill-generator
description: .claude/skills/ 폴더의 커스텀 스킬(SKILL.md)을 새로 만들거나 기존 스킬을 수정·개선할 때 **우선적으로** 사용하세요 — frontmatter 규칙, body 컨벤션, 검증 체크리스트, 트리거 최적화 방법이 담겨 있어 이 스킬을 먼저 읽고 작업하는 것이 중요합니다. 다음 세 가지 상황에 적용됩니다: ① "스킬 만들어줘/추가해줘", 커스텀 슬래시 명령어(/xxx) 신규 생성, "커스텀 명령어 만들 수 있어?", "/deploy-check 스킬로 만들기" 등 **모든 스킬 생성 요청**, ② 기존 .claude/skills/ 스킬의 워크플로우·description·트리거 조건·버그 수정, ③ 외부/마켓플레이스 스킬을 현재 프로젝트에 맞게 가져와 적용.
---

# Skill Generator

Claude Code용 커스텀 스킬(`.claude/skills/`)을 생성하거나 개선하는 메타 스킬.

## 핵심 원칙

### 간결함 우선

컨텍스트 윈도우는 공공재. Claude가 이미 아는 것은 설명하지 말 것. 모든 내용에 "이 문단이 토큰 비용을 정당화하는가?"를 질문할 것. 장황한 설명보다 간결한 예시를 선호.

### 자유도 설정

스킬의 성격에 따라 지침의 구체성을 조절:

| 자유도 | 사용 시점 | 형태 |
|--------|----------|------|
| **높음** | 여러 접근법이 유효, 컨텍스트에 따라 결정 | 텍스트 가이드라인 |
| **중간** | 선호 패턴 존재, 일부 변형 허용 | 파라미터 있는 pseudocode |
| **낮음** | 작업이 깨지기 쉬움, 일관성 필수 | 구체적 스크립트 |

### 작성 스타일

지침의 "왜"를 설명할 것. MUST/NEVER 대문자는 보안·안전 이슈에만 한정.
일반 지침은 이유를 함께 전달하면 Claude가 더 정확하게 따름.

- Bad: "파일명은 반드시 kebab-case로 작성하세요."
- Good: "파일명은 kebab-case로 작성 (자동 생성 시 일관성 유지 및 URL 호환)."

### Progressive Disclosure

스킬은 3단계로 로딩됨:

1. **Metadata** (name + description) — 항상 컨텍스트에 로드 (~100 words)
2. **SKILL.md body** — 스킬 트리거 시 로드 (<5k words)
3. **Bundled resources** — 필요 시 로드 (무제한)

**핵심**: SKILL.md body는 500행 이하 유지. 상세 내용은 references/로 분리.

## 스킬 파일 구조

```
skill-name/
├── SKILL.md            # 메인 스킬 파일 (필수)
├── scripts/            # 실행 가능 코드 (선택)
├── references/         # 참조 문서 - 필요 시 로드 (선택)
└── assets/             # 출력에 사용되는 파일 (선택)
```

**절대 포함하지 말 것**: README.md, CHANGELOG.md, INSTALLATION_GUIDE.md 등 보조 문서

### Frontmatter 규칙

- `name` (필수): kebab-case, 폴더명과 일치
- `description` (필수): **동작 + 트리거 조건**을 포함. description만으로 스킬 매칭이 결정되므로, "언제 사용하는가" 정보는 body가 아닌 여기에 집중
- `(project)` 태그: 프로젝트 종속 스킬에만 추가

**description 예시:**

```
# Good — 동작 + 트리거가 명확
"사용자가 새로운 기능 개발을 요청했을 때, /dev/docs/prd 경로에 관련 PRD가 없으면 자동으로 PRD를 생성합니다. (project)"

# Good — 영문도 동일 패턴
"Create distinctive, production-grade frontend interfaces. Use when the user asks to build web components, pages, or applications."

# Bad — 트리거 누락
"PRD를 생성하는 스킬입니다."
```

### Body 작성 규칙

- 명령형/부정형(imperative) 문체 사용
- body에 스킬의 호출 판단에 관한 내용을 넣지 말 것 (body는 트리거 이후에만 로딩되므로 호출 판단에 영향을 줄 수 없음). 표현과 무관하게 적용 — "호출 방식", "사용 조건", "실행 조건", "트리거 조건", "언제 사용하는가" 등 모두 해당
- 수동 호출 전용 스킬이면 description에 명시 (예: "수동 호출 전용 (/skill-name). 자동 트리거되지 않습니다.")
- `## 워크플로우` 섹션 필수. Step 1에서 작업 유형별 동작 분기를 정의하고, 이후 Step에서 실제 실행 액션을 기술할 것
- 참조 파일이 큰 경우 (>10k words), SKILL.md에 grep 검색 패턴 포함

## 스킬 생성 워크플로우

### Step 1: 구체적 사용 예시 수집

추상적 요구사항이 아닌 실제 사용 시나리오를 확보:
- "어떤 기능을 지원해야 하는가?"
- "사용자가 어떻게 말할 때 이 스킬이 트리거되어야 하는가?"
- "입력과 출력의 구체적 예시는?"

한 번에 너무 많은 질문을 하지 말 것. 핵심 질문부터 시작하고 필요 시 후속 질문.

### Step 2: 기존 스킬 분석 및 중복 확인

`.claude/skills/` 폴더를 탐색하여 확인:

| 상황 | 액션 |
|------|------|
| 동일 기능 스킬 존재 | 기존 스킬 개선으로 전환 |
| 유사 기능 스킬 존재 | 차이점 설명, 신규 vs 확장 선택 제안 |
| 트리거 조건 충돌 | 트리거를 더 구체화하여 분리 |
| 해당 없음 | Step 3로 진행 |

### Step 3: 재사용 가능한 리소스 계획

각 사용 예시를 분석하여 어떤 리소스가 필요한지 판단:
- **scripts/**: 매번 동일 코드를 재작성하게 되는 경우 → 스크립트로 저장
- **references/**: 매번 재탐색하는 스키마/문서가 있는 경우 → 참조 문서로 저장
- **assets/**: 출력에 사용하는 템플릿/이미지가 있는 경우 → 에셋으로 저장

### Step 4: SKILL.md 작성

작성 원칙:
1. description에 동작 + 트리거 조건 반드시 명시
2. 단계적 수행 지침(워크플로우) 섹션을 아래 구조로 작성:
   - **Step 1**: 작업 유형(또는 입력 조건)에 따라 이후 Step의 동작 범위/분기를 결정하는 테이블
   - **Step 2~N**: Claude가 즉시 수행 가능한 구체적 액션
   - 각 Step에 명확한 입력/출력 정의
   - Step 1 분기 테이블은 **조건에 따라 이후 Step 실행이 달라져야** 함:
     - Good: "디자인 시스템 생성 → Step 2→3→4→5 / 도메인 검색 → Step 3만"
     - Bad: 모든 조건에서 같은 Step을 실행하는 단순 정보 추출 테이블
3. 입력/출력 예시 포함
4. 참조 파일 경로 명시
5. CLAUDE.md의 Phase 정의를 확인하여, 새 스킬이 워크플로우의 어느 Phase에 해당하는지 파악하고 description에 명시

#### Description Pushy 수준

Claude는 스킬을 "undertrigger"하는 경향이 있음 — 유용한 상황에서도 호출하지 않는 경우가 많음. 이를 방지하기 위해 description을 약간 "pushy"하게 작성:

**적정 (지향)**:
- 구체적 트리거 조건 열거: "신규 기능 개발, 기존 기능 확장, 리팩토링 시"
- 명확한 상황 서술: "사용자가 ~을 요청했을 때", "~가 없으면"
- Edge case 포함: "명시적으로 요청하지 않더라도 ~한 상황이면 사용"

**과도 (회피)**:
- "모든", "항상" 등 무조건적 수식어
- 주관적 판단 위임: "도움이 될 것 같으면", "필요하다고 생각되면"

**부족 (회피)**:
- 트리거 조건 누락: "~를 수행합니다." (언제?)
- "Use when" 없음

Pushy 수준별 예시와 should-trigger/should-not-trigger 작성법: [references/templates.md](references/templates.md) 참조

**워크플로우 작성 참고 예시**: dev-docs-generator, completion-review 스킬 참조
**템플릿과 타입별 예시**: [references/templates.md](references/templates.md) 참조

### Step 5: 검증

**Frontmatter 검증:**
- [ ] name/description 존재, kebab-case, 폴더명 일치
- [ ] description에 동작 + 트리거 조건 포함
- [ ] 프로젝트 종속 스킬이면 `(project)` 태그 존재, 아니면 부재
- [ ] 수동 호출 전용이면 description에 명시

**Body 검증:**
- [ ] 호출 판단 관련 섹션 없음 (호출 방식, 사용 조건, 트리거 조건 등)
- [ ] Step 1이 작업 유형별 분기 테이블 (조건에 따라 이후 실행 Step이 다름)
- [ ] 워크플로우 명확, 출력 형식 정의, 참조 경로 실재

**충돌 검증:**
- [ ] 기존 스킬과 트리거 비충돌, 기존 워크플로우 미방해

**Description 트리거 검증:**
- should-trigger 예시 3개 + should-not-trigger 예시 3개를 작성
- 각 예시에 대해 "이 description으로 Claude가 스킬을 호출할 것인가?" 판단
- 2개 이상 불일치 시 description 수정 후 재판단

### Step 6: 실사용 기반 반복 개선

생성된 스킬을 실제로 사용하고:
1. 어려움이나 비효율 발견
2. SKILL.md 또는 리소스 업데이트 식별
3. 변경 적용 후 재테스트

## 기존 스킬 수정/확장

| 변경 유형 | 접근 방식 |
|----------|----------|
| description 수정 | frontmatter만 수정 |
| 워크플로우 추가/수정 | 해당 섹션만 수정 |
| 전면 개편 | 기존 내용 백업 후 재작성 |
| 스킬 분리 | 기존 축소 + 새 스킬 생성 |

수정 후 반드시 Step 5 검증 수행. CLAUDE.md의 Phase 정의와 충돌하지 않는지 확인.

## 참고사항

- 스킬 이름: kebab-case
- `(project)` 태그: 프로젝트 종속 스킬에만 추가
- 생성 전 `.claude/skills/` 기존 스킬 반드시 확인
- SKILL.md 500행 이하 유지, 초과 시 references/로 분리
- 명령형 문체 사용 (imperative form)
