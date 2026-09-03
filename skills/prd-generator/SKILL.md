---
name: prd-generator
description: 신규 기능 요청인데 dev/docs/prd/에 해당 PRD가 없을 때 PRD를 생성합니다. 서비스 규모에 따라 단일 PRD 또는 모듈형 PRD(prd-overload + Phase Sub PRD + Shared)를 선택합니다.
---

# PRD Generator

## 입력 처리

| 호출 상황 | 동작 |
|----------|------|
| epcc-planner에서 강화된 요구사항과 함께 호출 | 그것을 기반으로 PRD 생성 (Step 2 수집 생략) |
| 사용자가 `/prd-generator`로 직접 호출 | Step 2에서 사용자에게 직접 수집 |
| 기타 | 부족한 정보만 추가 수집 |

## 핵심 워크플로우

### Step 1: 기존 PRD 검색 및 판단

`dev/docs/prd/`에서 기능명·키워드로 탐색. 관련 PRD가 있으면 **새로 만들지 않고**
갱신 제안 → prd-reviewer로 연결한다.

### Step 2: 요구사항 수집

부족한 것만 묻는다 (진입 조건 4상태와 동일 원리 — 이미 아는 것을 다시 묻지 않는다):

| 항목 | 질문 예 |
| --- | --- |
| 문제 정의 | 누가 무엇이 불편한가 |
| 목표/비목표 | 이번에 하는 것과 명시적으로 안 하는 것 |
| 핵심 기능 | Must 3개 이내로 압축 가능한가 |
| 제약 | 기술·일정·비용 제약 |

### Step 3: PRD 모드 결정

| 조건 | 모드 | 생성물 |
|------|------|--------|
| Phase 2개 이상 / FR 20개 초과 / 크로스 도메인 | **모듈형** | prd-overload + Phase Sub PRDs + Shared |
| 위에 해당하지 않음 | **단일** | 단일 PRD 파일 |

### Step 4-S: 단일 PRD 생성

`assets/prd-template.md` 형식을 따른다. **모든 실행에서 같은 구조가 나와야 한다** —
템플릿에 없는 섹션 추가는 사용자 요청 시에만.

### Step 4-M: 모듈형 PRD 생성

- `prd-overload.md`: 전체 개요 + Phase 목록 + Phase 간 의존
- `phases/phase-N-<name>.md`: Phase별로 템플릿 §3~5 반복
- `shared/`: 공통 데이터 모델·용어. **한 곳이 원본, 나머지는 참조** (중복 서술 금지)

### Step 5: 파일 저장

- 단일: `dev/docs/prd/prd-<기능명>.md`
- 모듈형: `dev/docs/prd/<기능명>/` 아래 overload + phases/ + shared/

### Step 6: 사용자 확인

생성 요약(모드·FR 수·Must 수·열린 질문 수)을 제시하고 확정받는다.
확정 후 PRD 수정이 생기면 prd-reviewer의 "수정 후 검증"을 안내한다.

## 프로젝트 컨텍스트 활용

PRD 생성 시 CLAUDE.md, dev/docs/, .claude/rules/ 참조.
