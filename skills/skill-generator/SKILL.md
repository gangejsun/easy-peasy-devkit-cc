---
name: skill-generator
description: .claude/skills/ 폴더의 커스텀 스킬(SKILL.md)을 새로 만들거나 기존 스킬을 수정·개선할 때 **우선적으로** 사용하세요 — 프로젝트 전용 frontmatter 규칙, body 컨벤션, 검증 체크리스트, 트리거 최적화 방법이 담겨 있어 이 스킬을 먼저 읽고 작업하는 것이 중요합니다. 다음 세 가지 상황에 적용됩니다: ① "스킬 만들어줘/추가해줘", 커스텀 슬래시 명령어(/xxx) 신규 생성, "커스텀 명령어 만들 수 있어?", "/deploy-check 스킬로 만들기" 등 **모든 스킬 생성 요청**, ② 기존 .claude/skills/ 스킬의 워크플로우·description·트리거 조건·버그 수정, ③ 외부/마켓플레이스 스킬을 현재 프로젝트에 맞게 가져와 적용. skill-creator 플러그인보다 우선 사용합니다. (project)
---

# Skill Generator

Claude Code용 커스텀 스킬(`.claude/skills/`)을 생성하거나 개선하는 메타 스킬.

## 핵심 원칙

### 간결함 우선

컨텍스트 윈도우는 공공재. Claude가 이미 아는 것은 설명하지 말 것.

### 자유도 설정

| 자유도   | 사용 시점                       | 형태                     |
| -------- | ------------------------------- | ------------------------ |
| **높음** | 여러 접근법이 유효              | 텍스트 가이드라인        |
| **중간** | 선호 패턴 존재, 일부 변형 허용  | 파라미터 있는 pseudocode |
| **낮음** | 작업이 깨지기 쉬움, 일관성 필수 | 구체적 스크립트          |

### Progressive Disclosure

1. **Metadata** (name + description) — 항상 로드 (~100 words)
2. **SKILL.md body** — 스킬 트리거 시 로드 (<5k words)
3. **Bundled files** (references/, assets/, data/) — 필요 시 로드 (무제한)

SKILL.md body는 **500행 이하** 유지.

## 스킬 파일 구조

```
skill-name/
├── SKILL.md            # 메인 스킬 파일 (필수, 500행 이하)
├── references/         # 내부 참조 자료 (선택)
├── assets/             # 출력 템플릿 (선택)
├── scripts/            # 실행 가능 코드 (선택)
└── data/               # 정적 데이터셋 (선택)
```

## 스킬 생성 워크플로우

### Step 1: 구체적 사용 예시 수집

### Step 2: 기존 스킬 분석 및 중복 확인

### Step 3: 하위 폴더 계획

### Step 4: SKILL.md 작성

### Step 5: 검증

### Step 6: 실사용 기반 반복 개선

## 기존 스킬 수정/확장

수정 후 반드시 Step 5 검증 수행.

## 참고사항

- 스킬 이름: kebab-case
- `(project)` 태그: 프로젝트 종속 스킬에만 추가
- 생성 전 `.claude/skills/` 기존 스킬 반드시 확인
- SKILL.md 500행 이하 유지
