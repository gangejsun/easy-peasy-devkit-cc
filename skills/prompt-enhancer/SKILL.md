---
name: prompt-enhancer
description: Enhance user prompts by analyzing project context (code structure, dependencies, conventions, existing patterns). Use when users provide brief development requests that would benefit from project-specific context to generate more accurate, contextually-aware prompts.
---

# Prompt Enhancer

사용자의 간략한 개발 요청을 프로젝트 컨텍스트를 반영하여 **강화된 프롬프트**로 변환합니다. 요청 규모에 따라 강화 수준이 달라집니다.

## Core Workflow

### Step 1: 프로젝트 컨텍스트 분석

### Step 2: 요청 의도 및 규모 파악

**강화 유형 판단:**

| 상황                                   | 강화 유형 | Step 3 동작               |
| -------------------------------------- | --------- | ------------------------- |
| P0 파이프라인 경유 (service-plan 존재) | P0-Tech   | Step 3: P0 기술 명세 매핑 |
| 일반 요청 — Medium 규모                | Medium    | Step 3: Medium 강화       |
| 일반 요청 — Large 규모                 | Large     | Step 3: Large 강화        |

### Step 3: 규모별 강화 수행

#### P0 기술 명세 매핑 (P0-Tech)

service-planner의 기능 요구사항(FR-xxx)을 프로젝트 코드 컨텍스트와 매핑합니다.

#### Medium 요청

프로젝트 맥락을 반영한 명확한 요청문으로 강화합니다.

#### Large 요청

프로젝트 컨텍스트 + 구현 범위 + 상세 요구사항과 성공 기준까지 포함하여 강화합니다.

### Step 4: 사용자 확인

**Do NOT implement** until the user confirms. 목표는 다음 Phase에 전달할 명확한 요청을 만드는 것입니다.

## Tips

- 기존 화면/컴포넌트가 있으면 "기존 X와 유사한 접근으로" 형태로 참조
- 규모 판단이 애매하면 Large로 강화
