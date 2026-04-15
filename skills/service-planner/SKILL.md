---
name: service-planner
description: |
  서비스 구조를 설계하고 구체적인 기능 요구사항을 도출합니다.
  사용자가 "서비스 기획", "기능 요구사항", "화면 설계", "사용자 플로우",
  "기능 목록", "요구사항 도출"을 요청할 때,
  또는 planning-agent가 P0-D 단계로 호출할 때 사용합니다.
  수동 호출 전용 (/service-planner). 자동 트리거되지 않습니다. (project)
---

# Service Planner

서비스를 설계하고 **구체적인 기능 요구사항(FR-xxx)**을 도출합니다.
"무엇을 어떻게 만들 것인가?"에 답하며, PRD가 이 산출물을 그대로 수용할 수 있는 수준의 구체성을 목표로 합니다.

<HARD-GATE>
기능 요구사항 테이블(Step 5)이 사용자 승인 없이 PRD로 전달되어서는 안 됩니다.
반드시 사용자 확인 후 저장합니다.
</HARD-GATE>

## 워크플로우

### Step 1: 입력 판별 및 범위 결정

| 입력 상황                    | 실행 Step                                  |
| ---------------------------- | ------------------------------------------ |
| P0-C 사업 기획서와 함께 호출 | Step 2 → Step 3 → Step 4 → Step 5 → Step 6 |
| 사용자가 직접 호출           | Step 3 → Step 4 → Step 5 → Step 6          |
| 기존 서비스 기획 수정 요청   | Step 3(기존 로드) → Step 5(수정) → Step 6  |

### Step 2: 사업 기획 통합

### Step 3: 사용자 여정 설계 (User Journey Mapping)

3-1. 핵심 페르소나 정의
3-2. 주요 사용자 시나리오 도출
3-3. User Story 작성

### Step 4: 정보 아키텍처 (IA) 설계

4-1. 화면 계층 구조 (Site Map)
4-2. 핵심 화면 목록
4-3. 화면 간 네비게이션 플로우
4-4. 데이터 모델 초안

### Step 5: 기능 요구사항 도출 — 핵심 산출물

5-1. User Story → Epic → Feature → Requirement 분해
5-2. 기능 요구사항 테이블 (FR-xxx) — MoSCoW 우선순위 + 수용 기준
5-3. 비기능 요구사항 테이블 (NFR-xxx)
5-4. 사용자 확인

## Pitfalls

- FR 도출 시 UI 화면 1:1 매핑 함정 회피
- NFR 숫자를 무의미하게 채우지 말 것
- 사업 기획의 수치를 그대로 FR 수용 기준에 복사하지 말 것

### Step 6: 서비스 기획서 저장 및 PRD 연결

저장 경로: `dev/docs/service/service-plan-<name>.md`

## 참조 문서

- 서비스 기획 프레임워크: `references/service-frameworks.md`
- 서비스 기획서 저장소: `dev/docs/service/`
- 사업 기획서 저장소: `dev/docs/business/`
