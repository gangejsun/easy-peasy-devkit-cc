<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# 데이터 변경이력 설계

> **핵심 원칙: "디스크 용량 < 개발 생산성 + 운영 안정성"**. 단순한 전체 행 스냅샷이 복잡한 컬럼 단위 로그를 이긴다.

### 11.1 변경 추적 컬럼 단계

모든 테이블에 적절한 단계의 추적 컬럼을 적용한다.

| 단계                    | 컬럼                                                   | 적용 대상                                  |
| ----------------------- | ------------------------------------------------------ | ------------------------------------------ |
| **Level 1** (기본)      | `created_at`, `created_by`, `updated_at`, `updated_by` | **거의 모든 테이블** (카드 §8 체크리스트)       |
| **Level 2** (변경 사유) | `change_type TEXT`, `change_reason TEXT`               | 비즈니스 중요 테이블 (가격·상태·등급 변경) |
| **Level 3** (감사)      | `source_system TEXT`, `client_ip INET`                 | 규제/보안 필수 · 다중 시스템 변경 테이블   |
| **Level 4** (분산 추적) | `request_id UUID`                                      | 마이크로서비스 환경 (전체 흐름 추적)       |

`change_type` 표준값 예시: `CREATE`, `PRICE_CHANGE`, `STATUS_CHANGE`, `STOCK_ADJUST`, `CORRECTION`. `source_system` 표준값 예시: `WEB_ADMIN`, `WEB_USER`, `API`, `BATCH`, `MOBILE_APP`.

### 11.2 이력 관리 전략 선택

| 방식                                      | 적용 시점                                                              | 미적용 시점                                      |
| ----------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------ |
| **전체 행 스냅샷 `_history` (기본 전략)** | 비즈니스 이력 필수 (상태·등급·가격 변경 등 대부분)                     | 고빈도 갱신 · 로그성 데이터                      |
| 이벤트 원장 (Event Sourcing)              | 금액·포인트 등 **원장성 데이터** (현재값 = SUM(delta), `point_events`) | 단순 CRUD, 이력 불필요                           |
| Generic Audit (공통 이력 테이블)          | 규정 준수 · 디버깅용 **보조** 전체 변경 추적                           | 단독 이력 전략으로 사용 (전용 `_history`와 병행) |
| SCD Type 1 (덮어쓰기)                     | 오류 수정 · 최신값만 필요                                              | 이전 값 추적 필요                                |

### 11.3 전체 행 스냅샷 `_history` 테이블 (권장 기본 전략)

**구조**: `{원본}_history` — `history_id` (PK BIGINT), 원본 전체 컬럼 복사, `history_created_at TIMESTAMPTZ DEFAULT now()`, `history_created_by UUID`, `change_type TEXT CHECK (change_type IN ('INSERT','UPDATE','DELETE'))`, `change_reason TEXT`.

**핵심 규칙**:

- **첫 INSERT부터 이력 저장 필수**: 최초 등록(INSERT) 시점에도 `_history`에 `change_type = 'INSERT'`로 저장. 이력 테이블만으로 완벽한 타임라인 보장. 변경 시점에만 저장하면 조회 시 UNION 지옥 발생
- **두 가지 시간 구분**: 원본의 `created_at` (데이터 생성일, 불변) + `history_created_at` (이력 기록일, 변경마다 갱신)
- 현재 데이터 조회 → 원본 테이블. 이력 조회 → `_history` 테이블. 테이블 분리로 현재 데이터 조회 성능 최적화

**유효기간 (선택적 적용)**:

| 데이터 유형                      | 유효기간 컬럼                                         | 이유                                                                 |
| -------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------- |
| 마스터 데이터 (상품·회원·조직)   | `valid_from`/`valid_to DEFAULT '9999-12-31'` **권장** | 시점 조회 최적화 (`WHERE :time >= valid_from AND :time < valid_to`)  |
| 트랜잭션 데이터 (주문·결제·로그) | **비권장**                                            | 발생 시점이 핵심, 데이터 양 많아 UPDATE 비용 큼                      |

유효기간 적용 시: 데이터 변경마다 이전 행의 `valid_to` UPDATE + 새 행 INSERT → **트랜잭션 필수**. `is_current BOOLEAN` + `valid_to` 중복은 의도적 반정규화 (직관성·인덱스 효율 → 카드 §7 원칙).

### 11.4 Generic Audit 패턴 (보조용)

`audit_logs` — `log_id` (PK), `table_name TEXT`, `row_id BIGINT`, `action TEXT`, `old_values JSONB`, `new_values JSONB`, `actor_id UUID`, `created_at TIMESTAMPTZ`. 트리거에서 `row_to_json(OLD)` / `row_to_json(NEW)` 활용.

**중요**: 공통 이력 테이블은 **주기적 아카이빙 필수** (월/분기 파티셔닝 + 보존 기간 후 cold storage 이동). 아카이빙 없이 운영 시 DB 용량 고갈 위험.

### 11.5 추적 제외 · 안티패턴 · 원칙

**추적 제외 대상**: 세션/토큰 테이블 · 캐시/임시 테이블 · 대량 로그 테이블 (별도 로그 파이프라인) · `audit_logs` 자기 자신

**비즈니스 이력 vs 시스템 로그**: DB에는 **비즈니스 이력만** 저장 (가격 변경, 상태 변경, 감사 기록 등). 시스템 로그 (HTTP 요청, 디버그 정보, 접속 기록)는 **파일 기반 로그 파이프라인**으로 관리. DB에 모든 로그를 쌓으면 비즈니스 트랜잭션 성능 저하 위험.

**안티패턴**: ①운영 테이블에 이력 컬럼 추가 (테이블 비대화) ②모든 테이블에 Generic Audit 적용 (성능 저하) ③이벤트 원장에서 레코드 UPDATE/DELETE (원장 불변 원칙 위반) ④`_history` 테이블에 INSERT 시점 이력 미저장 (타임라인 끊김·UNION 지옥) ⑤컬럼 단위 변경 로그(`column_name`, `old_value`, `new_value` TEXT)를 주 이력 전략으로 사용 (시점 복원 극도로 어려움 — 특정 필드 감사 표시용에만 허용)
