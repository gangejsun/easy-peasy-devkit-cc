<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# 계층구조 설계

**기본: Adjacency List + CTE** (`parent_id` FK + `WITH RECURSIVE`). 90%+ 요구사항 충족. Closure Table은 EXPLAIN ANALYZE로 성능 문제 입증 시에만 도입 (카드 §7 역정규화 전제와 동일).

| 방식                      | 적용 시점                      | 미적용 시점                          | PostgreSQL 구현                                                                    |
| ------------------------- | ------------------------------ | ------------------------------------ | ---------------------------------------------------------------------------------- |
| Adjacency List            | 깊이 ≤5, 쓰기 빈번, 단순 트리  | 깊은 트리에서 조상/자손 쿼리 빈번    | `parent_id BIGINT REFERENCES self` + `WITH RECURSIVE` CTE                          |
| Materialized Path (ltree) | 깊이 10+, 조상/자손 검색 빈번  | 노드 이동 빈번 (경로 전체 갱신 비용) | `CREATE EXTENSION ltree` + GiST 인덱스 + `@>` 연산자                               |
| Closure Table             | 임의 깊이, 읽기/쓰기 균형 필요 | 단순 트리 (과도 설계)                | 교차 테이블 `(ancestor_id, descendant_id, depth)` + 자기참조 행 `(id, id, 0)` 필수 |
| Nested Sets               | 읽기 전용 또는 변경 극히 드묾  | 삽입/삭제 빈번 (전체 lft/rgt 재번호) | `lft`/`rgt` INTEGER 컬럼                                                           |

**선택 기준**: ①읽기/쓰기 비율 (읽기 위주 → ltree/Nested Sets, 쓰기 위주 → Adjacency List) ②트리 깊이 (≤5 → Adjacency List, 10+ → ltree) ③변경 빈도 (잦은 이동 → Adjacency List 또는 Closure Table)

**CTE 활용 패턴**: ①깊이 제한: 재귀 케이스에 `WHERE depth < {max_depth}` (부모 기준 검사 — `<=` 아님 주의) ②경로 문자열: `CONCAT(parent.path, ' > ', child.name)` 패턴 (Breadcrumb) ③계층 집계: 재귀 CTE로 자손 ID 수집 후 `WHERE id IN (...)` 집계

**안티패턴**: ①필요 전 Closure Table 도입 (YAGNI) ②self-FK 없이 `parent_id`만 (무결성 없음) ③깊이 제한 없는 재귀 CTE (무한 루프 위험 — 깊이 상한 조건 필수) ④루트 노드 식별 컬럼 누락 (`parent_id IS NULL` 또는 `depth = 0`)
