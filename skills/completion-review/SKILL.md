---
name: completion-review
description: |
  코드 구현이 끝나고 문서를 최신화해야 할 때 사용합니다.
  context.md 업데이트, tasks.md 체크 완료, 관련 아키텍처/API 문서 업데이트, 완료된 작업 아카이브를 처리합니다.
  CLAUDE.md 워크플로우의 Phase 5에 해당합니다. Small 작업의 P5 또는 review-agent가 호출합니다.
---

# Completion Review

개발 완료 후 문서 최신화 및 아카이브를 수행하는 스킬입니다.

## 워크플로우

### Step 1: 작업 유형 확인 및 업데이트 범위 결정

| 작업 유형                | Step 2 (개발 문서)             | Step 3 (프로젝트 문서)              | Step 4 (아카이브) |
| ------------------------ | ------------------------------ | ----------------------------------- | ----------------- |
| 신규 기능 개발           | context + tasks 전체 업데이트  | PRD, CLAUDE.md, dev/docs/ 전체 확인 | 수행              |
| 기존 기능 확장/수정/삭제 | context + tasks 업데이트       | 변경된 부분의 관련 dev/docs/        | 수행              |
| 버그 수정                | tasks만 (dev docs가 있는 경우) | 최소 업데이트 (필요한 경우만)       | 생략 가능         |
| 리팩토링                 | context + tasks 업데이트       | 아키텍처 문서 중점 업데이트         | 수행              |

### Step 2: 개발 문서 업데이트

`dev/active/<feature-name>/` 의 문서를 업데이트합니다.

### Step 3: 프로젝트 문서 업데이트

구현 중 발생한 변경사항을 분석하고, 해당하는 문서를 업데이트합니다.

## Pitfalls

- PRD와 다른 구현 발견 시 자동 수정하지 말 것 — 반드시 사용자에게 보고 후 선택
- 아카이브 전 tasks.md 미체크 항목이 의도적 제외인지 누락인지 확인
- context.md SESSION PROGRESS 업데이트 시 이전 세션 기록을 덮어쓰지 말 것 — append 방식

### Step 4: 아카이브

```bash
git mv dev/active/<feature-name> dev/archive/<feature-name>
```

### Step 4.5: 산출물 자체 검증

### Step 5: 사용자에게 완료 보고
