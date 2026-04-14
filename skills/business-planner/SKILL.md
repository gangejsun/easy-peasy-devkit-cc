---
name: business-planner
description: |
  아이디어나 기능을 사업적 관점에서 검증하고 사업 기획서를 생성합니다.
  사용자가 "사업 기획", "비즈니스 모델", "수익화", "시장 진입", "사업성 분석"을 요청할 때,
  또는 planning-agent가 P0-C 단계로 호출할 때 사용합니다.
  수동 호출 전용 (/business-planner). 자동 트리거되지 않습니다. (project)
---

# Business Planner

아이디어나 기능을 사업적 관점에서 검증하고, 구조화된 사업 기획서를 생성합니다.
"이걸 왜 만들어야 하는가?"에 대한 사업적 근거를 마련합니다.

## 워크플로우

### Step 1: 입력 판별 및 분석 범위 결정

| 입력 상황 | 실행 Step |
|----------|----------|
| P0-B 리서치 결과와 함께 호출 (planning-agent 경유) | Step 2 → Step 3 → Step 4 → Step 5 |
| 사용자가 직접 호출 (리서치 없음) | Step 3 → Step 4 → Step 5 |
| 기존 사업 기획서 수정 요청 | Step 3(기존 문서 로드) → Step 4 → Step 5 |

### Step 2: 리서치 통합

`dev/docs/research/` 문서를 읽고 사업 기획에 활용할 데이터를 추출합니다.

### Step 3: 사업 환경 분석

`references/business-frameworks.md`의 5C Analysis 가이드를 참조하여 분석합니다.

각 항목에 대해 사용자에게 **1개씩 질문** (brainstorming 패턴):
3-1. Company (자사 역량)
3-2. Customer (고객)
3-3. Competitor (경쟁)
3-4. Collaborator (협력)
3-5. Climate (환경)

### Step 4: 사업 모델 설계

5C 분석 결과를 바탕으로 사업 모델을 설계합니다.

4-1. 가치 제안 (Value Proposition)
4-2. 수익 모델
4-3. 비용 구조
4-4. Go-to-Market 전략
4-5. 핵심 지표 (KPI)
4-6. 리스크 매트릭스

### Step 5: 사업 기획서 저장 및 확인

**저장 경로**: `dev/docs/business/business-plan-<name>.md`

## 참조 문서

- 사업 기획 프레임워크: `references/business-frameworks.md`
- 사업 기획서 저장소: `dev/docs/business/`
- 리서치 저장소: `dev/docs/research/`
