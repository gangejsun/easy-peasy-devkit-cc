---
name: prd-generator
description: |
  사용자가 새로운 기능 개발을 요청했을 때, /dev/docs/prd 경로에 관련 PRD가 없으면 자동으로 PRD를 생성합니다.
  서비스 규모에 따라 단일 PRD 또는 모듈형 PRD(prd-overload + Phase Sub PRD + Shared) 체계를 선택합니다.
  수동 호출(/prd-generator) 또는 planning-agent P2에서 자동 호출됩니다. (project)
---

# PRD Generator

## 입력 처리

| 호출 상황 | 동작 |
|----------|------|
| planning-agent에서 강화된 요구사항과 함께 호출 | 그것을 기반으로 PRD 생성 (Step 2 수집 생략) |
| 사용자가 `/prd-generator`로 직접 호출 | Step 2에서 사용자에게 직접 수집 |
| 기타 | 부족한 정보만 추가 수집 |

## 핵심 워크플로우

### Step 1: 기존 PRD 검색 및 판단

### Step 2: 요구사항 수집

### Step 3: PRD 모드 결정

| 조건 | 모드 | 생성물 |
|------|------|--------|
| Phase 2개 이상 / FR 20개 초과 / 크로스 도메인 | **모듈형** | prd-overload + Phase Sub PRDs + Shared |
| 위에 해당하지 않음 | **단일** | 단일 PRD 파일 |

### Step 4-S: 단일 PRD 생성

### Step 4-M: 모듈형 PRD 생성

### Step 5: 파일 저장

### Step 6: 사용자 확인

## 프로젝트 컨텍스트 활용

PRD 생성 시 CLAUDE.md, dev/docs/, .claude/rules/ 참조.
