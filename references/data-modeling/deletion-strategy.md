<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# 데이터 삭제 전략 — Status vs Soft Delete vs Hard Delete

> **"삭제는 기술이 아니라 정책이다."** 핵심 도메인(주문·결제·정산)은 보통 삭제가 아니라 **상태(Status)**로 관리한다.

| 전략                             | 적용 시점                                     | 예시                                                      |
| -------------------------------- | --------------------------------------------- | --------------------------------------------------------- |
| **Status 기반** (삭제 개념 없음) | 비즈니스 생명주기 복잡 · 다단계 상태 전이     | 상품(판매중/품절/판매중지), 주문(결제대기/완료/취소/환불) |
| **Soft Delete** (`deleted_at`)   | 단순 존재 유무 · 복구 가능성 · FK 참조 유지   | 댓글, 게시글, 좋아요, 회원 탈퇴                           |
| **Hard Delete**                  | 보관 가치 없음 · GDPR 삭제 의무 · 임시 데이터 | 장바구니, 로그, 세션, 테스트 데이터                       |

**Soft Delete 기본**: `deleted_at TIMESTAMPTZ` (NULL = 활성). `is_deleted BOOLEAN` 금지 (삭제 시점 유실).

**필수 구현** (Soft Delete 채택 시):

- 부분 인덱스: `CREATE INDEX idx_{테이블}_active ON {테이블}(...) WHERE deleted_at IS NULL`
- UNIQUE 제약: `CREATE UNIQUE INDEX uq_{테이블}_{컬럼} ON {테이블}({컬럼}) WHERE deleted_at IS NULL` (활성 행에만 유니크)
- RLS 정책: 모든 SELECT/UPDATE 정책의 `USING` 절에 `AND deleted_at IS NULL` 추가 (행 수준 보안을 쓰는 스택에 한함 — 상세는 해당 스택 backend-guide의 인증/권한 경계 리소스)
- 조회 계층: soft delete 필터(`deleted_at IS NULL`)를 쿼리마다 반복하지 말고 DB View 또는 공용 쿼리 헬퍼로 강제한다

**이력 테이블과의 관계** (→ [`change-history.md`](./change-history.md)): Soft Delete와 `_history` 테이블은 **대체재가 아니라 보완재**. FK 참조 있는 핵심 테이블 → Soft Delete + `_history` 병행 (참조 무결성 유지 + 변경 이력 보존). FK 참조 없는 테이블 → Hard Delete + `_history`로 충분 (메인 테이블 경량화).

**안티패턴**: ①`is_deleted BOOLEAN` 사용 (삭제 시점 유실, 포렌식 불가) ②부분 인덱스 없이 전체 테이블 스캔 ③RLS 정책에 soft delete 미반영 (삭제 데이터 노출) ④soft delete + hard delete 혼용 (일관성 상실) ⑤핵심 도메인(주문·상품)에 `deleted_at` 적용 — Status 기반 관리를 먼저 검토하라
