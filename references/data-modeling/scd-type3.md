<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# 컬럼에 이전 값 보관 — SCD Type 3

**제한적 사용**: 직전 값 1개만 필요한 **선형 상태 머신**에서만 허용. 그 외 → [`change-history.md`](./change-history.md) `_history` 테이블.

| 적용 조건                             | 미적용 조건                     |
| ------------------------------------- | ------------------------------- |
| 상태가 선형 전이 (A→B→C, 되돌림 없음) | 감사/규정 요구 (전체 이력 필요) |
| 직전 값 1개만 비즈니스에 필요         | 다단계 undo/redo 기능           |
| 조인 없이 즉시 비교 필요 (성능 우선)  | 3개+ 이전 값 추적 가능성        |
| 변경 빈도 낮음 (일 1~2회)             | 고빈도 갱신 (prev\_ 컬럼 낭비)  |

**네이밍**: `prev_{column_name}` 접미사. 예: `status` + `prev_status`, `tier` + `prev_tier`. 변경 시점 추적 필요 시 `{column}_changed_at TIMESTAMPTZ` 동반 컬럼 선택 추가.

**갱신 로직**: `UPDATE SET prev_status = status, status = :new_status` — 단일 문으로 원자적 교체. 앱 레벨에서 old value를 읽어 SET하지 않는다 (동시성 경쟁 위험).

**안티패턴**: ①`prev_prev_` 컬럼 등장 시 즉시 `_history` 테이블로 전환 ②앱에서 SELECT → 변수 저장 → UPDATE (race condition) ③prev\_ 컬럼에 트리거 없이 수동 관리 (누락 위험)
