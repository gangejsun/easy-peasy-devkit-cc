---
name: prompt-enhancer
description: Enhance user prompts by analyzing project context (code structure, dependencies, conventions, existing patterns). Use when users provide brief development requests where what to build is already settled but the project context is missing. If what to build is still undecided, use /brainstorming first — it hands its approved design to this skill.
---

# Prompt Enhancer

사용자의 간략한 개발 요청을 프로젝트 컨텍스트를 반영하여 **강화된 프롬프트**로 변환합니다. 진입 조건 4상태(의도·컨텍스트·영향 반경·검증 경로) 중 미충족 수에 따라 강화 수준이 달라집니다.

## Core Workflow

### Step 1: 프로젝트 컨텍스트 분석

**추측하지 않고 실측한다** — 프레임워크·패키지 매니저·테스트 러너를 관례로 단정하면
강화된 프롬프트가 거짓 전제를 다음 Phase로 실어 나른다.

```bash
cat epcc.config.json 2>/dev/null                     # 스택이 이미 선언돼 있으면 여기서 끝
ls package.json pyproject.toml go.mod Cargo.toml 2>/dev/null
git log --oneline -10 ; git diff --stat HEAD~5 2>/dev/null   # 최근 작업 지점
```

수집 상한: **파일 5개 · 명령 5회.** 요청과 무관한 디렉토리를 훑지 않는다 —
이 스킬의 산출물은 프롬프트 한 편이지 조사 보고서가 아니다.

요청 유형별로 무엇을 볼지는 `references/enhancement-patterns.md`가 정한다
(UI 컴포넌트 · API 엔드포인트 · 상태 관리 · 버그 수정 등). 해당 절만 읽는다.

### Step 2: 요청 의도 및 미충족 상태 파악

**강화 유형 판단:**

| 상황 | 강화 유형 | Step 3 동작 |
|------|----------|------------|
| 기획 파이프라인 경유 (service-plan 존재) | tech-spec | Step 3: 기술 명세 매핑 |
| 일반 요청 — 미충족 1개 이하 | 경량 | Step 3: 경량 강화 |
| 일반 요청 — 미충족 2개 이상 | 심층 | Step 3: 심층 강화 |

### Step 3: 수준별 강화 수행

#### 기술 명세 매핑 (tech-spec)

service-planner의 기능 요구사항(FR-xxx)을 프로젝트 코드 컨텍스트와 매핑합니다.

#### 경량 강화 (미충족 1개 이하)

프로젝트 맥락을 반영한 명확한 요청문으로 강화합니다.

#### 심층 강화 (미충족 2개 이상)

프로젝트 컨텍스트 + 구현 범위 + 상세 요구사항과 성공 기준까지 포함하여 강화합니다.

### Step 4: 사용자 확인

**Do NOT implement** until the user confirms. 목표는 다음 Phase에 전달할 명확한 요청을 만드는 것입니다.

## 참조 문서

| 파일 | 언제 읽는가 |
| --- | --- |
| `references/enhancement-patterns.md` | **Step 1에서만.** 요청 유형이 정해진 뒤 그 유형 절만 |
| `references/framework-guides.md` | Step 1에서 스택이 Next.js/React일 때만. **프로젝트에 `frontend-guide`·`backend-guide` 스킬이 있으면 그쪽이 이긴다** (스택 맞춤 생성본이라 더 정확하다) |

## Tips

- 기존 화면/컴포넌트가 있으면 "기존 X와 유사한 접근으로" 형태로 참조
- 미충족 수 판단이 애매하면 심층으로 강화
