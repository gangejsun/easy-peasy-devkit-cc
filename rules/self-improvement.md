---
paths:
  - "src/**"
  - "packages/**"
  - "app/**"
  - "lib/**"
---

# Self-Improvement Rule

## 교훈 기록
- 사용자가 코드나 접근 방식을 **수정/지적**하면 → `docs/lessons.md`에 기록
- 기록 형식: `## [category: <카테고리명>] <교훈 제목>` + 날짜, 상황, 실수, 교훈
- 카테고리 예시: `validation`, `tdd`, `architecture`, `security`, `naming`, `scope`, `communication`

## 규칙 승격 (로그 기반 자동 감지)
- `session-start-validator.sh`가 세션 시작 시 `docs/lessons.md`를 파싱
- 동일 카테고리 항목이 **3건 이상**이면 → 승격 후보로 사용자에게 제안
- 사용자 확인 후 → 이 파일 "승격된 규칙" 섹션에 추가 + lessons.md 해당 항목에 "승격됨" 표기
- review-agent도 코드 리뷰 중 반복 패턴을 독립적으로 보고 (정성적 보완)

## 승격된 규칙
(아직 없음)
