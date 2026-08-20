---
paths:
  - "supabase/**"
  - "**/migrations/**"
  - "db/**"
  - "prisma/**"
  - "drizzle/**"
  - "dev/docs/database/**"
---
<!-- epcc-rule-version: 3.4.2 -->

# 데이터 모델링 카드

> 김영한의 현대적 데이터 모델링 철학 기반. 새 테이블·마이그레이션·스키마 변경 설계 시 적용한다.
> 프로젝트에 정본 스키마 문서(`dev/docs/database/`)가 있으면 그것과 일관성을 유지한다.
>
> **적용 범위**: §1~4·6~9·11~13·15·17은 관계형 DB 공통. §5·10·14·16·18은
> PostgreSQL(Supabase 포함) 특화 — 다른 RDB에서는 원칙만 취하고 문법은 해당 DB로 치환한다.
> NoSQL 프로젝트에서는 이 카드의 paths가 거의 매칭되지 않아 휴면 상태가 된다.

**3대 원칙**: 대리키 우선 · 3NF 기본 · 비식별 관계 기본

---

## 1. 요구사항 분석 — 엔티티 추출

**추출 규칙**: 업무 기술서에서 **명사 → 엔티티 후보**, **동사 → 관계/행위 엔티티 후보**.

**엔티티 유효성 6기준** (모두 충족 시 엔티티): ①업무 필요 ②유일 식별자 존재 ③2+인스턴스 ④2+속성 ⑤업무 프로세스에서 이용 ⑥다른 엔티티와 관계 존재

**엔티티 분류**: 기본(독립 존재: 고객, 상품) → 중심(관계 파생: 주문, 계약) → 행위(이벤트 기록: 주문상세, 결제내역)

**설계 패턴**: 마스터-트랜잭션 분리(users vs transactions) · 코드 테이블 추출(TEXT+CHECK 또는 참조 테이블 → §9 상세) · 이력 관리(`_history` 테이블 분리 → §11 상세)

---

## 2. 개념적 모델링 — ERD 설계

**주식별자 선정**: ①업무에서 자주 사용 ②명칭(이름·내역) 배제 ③복합 최소화(단일 컬럼 선호) ④불변 ⑤NOT NULL ⑥유일

**카디널리티**: 1:1(통합 우선, 보안/선택적 관계 시만 분리) · 1:N(가장 흔함, FK는 N쪽) · N:M(**반드시 교차 테이블 분해**, 대리키 부여)

**참여도**: 필수(NOT NULL FK) vs 선택(NULLABLE FK). ERD 표기: **IE(Crow's Foot)** 기본.

**용어사전**: 새 도메인 설계 시 `dev/docs/database/`에 정의 — 표준용어명, 영문 물리명, 정의, 도메인(타입), 허용값

---

## 3. 논리적 모델링 — 키와 관계

### 키 전략

**기본: 대리키(BIGINT)**. 자연키는 UNIQUE 제약으로만 관리. "비즈니스와 무관한 대리키를 사용하라" — 김영한 (사례: 주민번호 PK → 개인정보보호법 변경으로 수집 불가)

| 상황         | 타입                                  | 비고                          |
| ------------ | ------------------------------------- | ----------------------------- |
| 일반 PK      | `BIGINT GENERATED ALWAYS AS IDENTITY` | 8B, 순차삽입, 조인 최적       |
| URL/API 노출 | `UUID DEFAULT gen_random_uuid()`      | 열거 공격 방지. 16B, 랜덤삽입 |
| 분산 시스템  | UUID v7 / ULID                        | 시간순 정렬, 거의 순차삽입    |

### 관계 규칙

- **FK 위치**: 항상 **Many(N) 쪽**에 배치. 1:1은 주 테이블(더 자주 조회하는 쪽)에 배치
- **N:M**: 교차 테이블 + 대리키 PK. 직접 N:M 매핑 금지 (추가 속성 확장 불가)
- **복합키**: 3컬럼+ → 대리키 전환
- **식별 vs 비식별**: **비식별 기본**. 식별은 순수 교차 테이블 또는 생명주기 완전 종속 시만

---

## 4. 정규화

**3NF 기본, BCNF 선별 적용**.

| 정규형 | 핵심 규칙                                  | 위반 시 문제             |
| ------ | ------------------------------------------ | ------------------------ |
| 1NF    | 모든 컬럼 원자값 (반복 그룹·다중값 제거)   | 검색/갱신 불가           |
| 2NF    | 부분 함수 종속 제거 (복합PK 일부에만 종속) | 갱신 이상                |
| 3NF    | 이행 함수 종속 제거 (A→B→C에서 A→C)        | 삽입/삭제 이상           |
| BCNF   | **모든 결정자가 후보키**여야 함            | 갱신 이상 (3NF보다 엄격) |

**BCNF 판별**: 모든 FD의 좌변(결정자)이 후보키인지 확인. 아니면 분해.

**정규화 하지 않는 경우**:

- 이력/스냅샷 테이블: 시점 고정 데이터 (당시 상품명, 당시 가격)
- 로그/이벤트 테이블: 쓰기 최적화 우선 (예: `events.data` JSONB)
- 읽기 위주 집계: OLAP, 대시보드용 요약 테이블

**흔한 실수**: JSONB로 1NF 우회 (구조적 데이터를 JSON에 때려넣기), EAV 패턴 남용 (→ §16 상세), 과도한 정규화 (코드 테이블 10단계 분리).

---

## 5. 물리적 모델링 — 데이터 타입

PostgreSQL/Supabase 기준:

| 범주           | 규칙                | 타입                                            |
| -------------- | ------------------- | ----------------------------------------------- |
| PK             | 대리키              | `BIGINT GENERATED ALWAYS AS IDENTITY`           |
| 공개 ID        | UUID                | `UUID DEFAULT gen_random_uuid()`                |
| 금액           | **절대 FLOAT 금지** | `NUMERIC(12,0)` (원화) / `NUMERIC(15,2)` (외화) |
| 문자열(제한)   | 비즈니스 규칙 길이  | `VARCHAR(n)` (이메일 320, 닉네임 30 등)         |
| 문자열(무제한) | 길이 미정           | `TEXT`                                          |
| 시간           | **항상 타임존**     | `TIMESTAMPTZ DEFAULT now()`                     |
| 날짜만         | 시간 불필요         | `DATE` (생년월일, 만료일)                       |
| 상태/유형      | 열거값              | `TEXT` + `CHECK` 제약                           |
| 유동적 스키마  | JSONB               | `JSONB` + CHECK 제약 또는 앱 Zod 검증           |
| 불리언         | 확실히 이진일 때만  | `BOOLEAN` (3+상태 가능성 → TEXT 열거형)         |
| 수량/카운트    | 정수                | `INTEGER` (대규모: `BIGINT`)                    |

---

## 6. 네이밍 컨벤션

기존 스키마와 일관성 유지:

| 대상                | 규칙                                    | 예시                                              |
| ------------------- | --------------------------------------- | ------------------------------------------------- |
| 테이블              | snake_case, **복수형**                  | `orders`, `point_events`                          |
| 컬럼                | snake_case                              | `product_name`, `unit_price`                      |
| PK                  | `{테이블_단수}_id`                      | `user_id`, `order_id`                             |
| FK                  | `{참조테이블_단수}_id`                  | `host_id`, `order_id`                             |
| Boolean             | `is_` / `has_`                          | `is_public`, `has_receipt`                        |
| Timestamp           | `_at` 접미사                            | `created_at`, `cancelled_at`                      |
| 인덱스/유니크/CHECK | `idx_`/`uq_`/`chk_` + `{테이블}_{컬럼}` | `idx_orders_status`, `chk_orders_total_positive`  |

---

## 7. 역정규화

**전제**: 정규화된 설계 완성 후, **EXPLAIN ANALYZE로 성능 문제 입증** 시에만 적용.

| 패턴              | 적용 시점           | 필수 조건                                  |
| ----------------- | ------------------- | ------------------------------------------ |
| 테이블 병합 (1:1) | 항상 함께 조회      | 별도 권한 관리 불필요                      |
| 컬럼 중복         | 조인 제거 필요      | 동기화 전략 문서화 (트리거/앱 로직)        |
| 파생 컬럼         | 집계 쿼리 빈번      | DB 트리거로 자동 갱신                      |
| 요약 테이블       | 대량 집계 매번 스캔 | Materialized View 또는 주기적 갱신 (→ §14) |

**필수**: 역정규화 시 사유·동기화 메커니즘·정합성 위험을 테이블 정의서에 기록.

---

## 8. 마이그레이션 & RLS 체크리스트

새 테이블 생성 시 필수 점검:

- [ ] `CREATE TABLE` + 인라인 제약조건 (PK, FK, CHECK, NOT NULL, DEFAULT)
- [ ] `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` + 최소 1개 정책 (Supabase — RLS 상세는 backend-guide 스킬의 supabase-patterns 리소스)
- [ ] FK 컬럼에 인덱스 생성 (`idx_{테이블}_{FK컬럼}`)
- [ ] 빈번한 WHERE/ORDER BY 컬럼에 인덱스 추가
- [ ] JSONB 컬럼에 GIN 인덱스 (내부 검색 필요 시)
- [ ] TypeScript 타입 정의 → 프로젝트 타입 디렉토리 (모노레포면 공유 패키지 `types/`) + barrel export 업데이트
- [ ] 테이블 정의서 → `dev/docs/database/` (선택, 중규모+ 시)
- [ ] `created_at TIMESTAMPTZ DEFAULT now()` + `updated_at TIMESTAMPTZ DEFAULT now()` 공통 컬럼
- [ ] `created_by UUID` + `updated_by UUID` 공통 컬럼 (거의 모든 테이블에 기본 적용 → §11 Level 1)
- [ ] 비즈니스 이력 필수 테이블 → `_{테이블}_history` 이력 테이블 동시 생성 (→ §11 상세)
- [ ] Soft Delete 적용 시: `deleted_at` 컬럼 + 부분 인덱스 + RLS 조건 반영 (→ §13)
- [ ] 멱등성 필요 시: `idempotency_key` UNIQUE 컬럼 + TTL 정리 (→ §15)

---

## 9. 공통코드 테이블 설계

**기본: `TEXT` + `CHECK`** (§5). 운영 중 동적 추가가 필요한 코드만 별도 참조 테이블로 분리.

| 방식             | 적용 시점                                     | 미적용 시점                         |
| ---------------- | --------------------------------------------- | ----------------------------------- |
| `TEXT` + `CHECK` | 값 변경 거의 없음 (status, type 등 열거형)    | 운영 중 코드 값 추가/삭제 빈번      |
| 개별 참조 테이블 | FK 무결성 필요 · 동적 추가 · 정렬/표시명 관리 | 코드 3개 이하 고정값 (CHECK로 충분) |
| 앱 상수 + Zod    | DB 독립적 타입 안전성 · 프론트 공유           | 다중 서비스 간 DB 레벨 정합성 필요  |

**참조 테이블 구조** (개별 도메인별 분리): `{도메인}_codes` — `code_id` (PK BIGINT), `code_value` (UNIQUE, FK 참조 대상), `display_name`, `sort_order INTEGER`, `is_active BOOLEAN DEFAULT true`. 부분 인덱스: `WHERE is_active = true`. 참조 시 `code_value`를 FK로 사용 (조인 없이 읽기 가능).

**OTLT(One True Lookup Table) 금지**: 모든 코드를 단일 범용 테이블(`group_code` + `code`)에 넣으면 — ①FK 무결성 상실 (어떤 그룹의 코드든 참조 가능) ②컬럼별 CHECK 제약 불가 ③타입 안전성 상실 ④ERD 가독성 저하.

**안티패턴**: ①OTLT 설계 ②비즈니스 의미 없는 코드값 (`1`, `2`, `3` 대신 `pending`, `active`, `completed`) ③정적 코드(변경 불가)와 동적 코드(운영 추가) 혼합 ④참조 테이블 없이 매직 스트링 직접 사용

**공통코드 vs 앱 ENUM 판단 기준**:

| 상황                                   | 선택                                                                                   | 이유                                                |
| -------------------------------------- | -------------------------------------------------------------------------------------- | --------------------------------------------------- |
| 화면 표시(드롭다운) 전용, 로직 미관여  | DB 참조 테이블 (또는 `TEXT`+`CHECK`)                                                   | 운영 유연성 우선 — 재배포 없이 DB만 수정            |
| 비즈니스 로직(`if`/`switch`) 분기 필요 | 앱 ENUM (TypeScript `as const` 등)                                                     | 타입 안전성·컴파일 검증·IDE 자동완성                |
| 로직 분기 + 표시명/속성 변경 빈번      | **하이브리드**: 앱 ENUM(코드값·타입 안전성) + DB 참조 테이블(표시명·속성·운영 유연성)  | 양쪽 장점 결합. **ENUM-DB 동기화 검증 테스트 필수** |

**조회 전략**: 공통코드 표시명은 SQL 조인이 아닌 **앱 레벨 로컬 메모리 캐시(TTL 60초)** 로 조회. 조인 지옥(Join Hell) 방지.

**자연키 예외**: 공통코드 참조 테이블은 §3 대리키 원칙의 예외 — `code_value`(문자열)를 FK 대상으로 직접 사용. 이유: ①데이터 가독성 (조인 없이 의미 파악) ②앱 ENUM 이름과 1:1 매핑 용이. FK 제약은 선택 (앱 레벨 검증 충분 시 생략 가능).

---

## 10. 계층구조 설계

**기본: Adjacency List + CTE** (`parent_id` FK + `WITH RECURSIVE`). 90%+ 요구사항 충족. Closure Table은 EXPLAIN ANALYZE로 성능 문제 입증 시에만 도입 (§7 역정규화 전제와 동일).

| 방식                      | 적용 시점                      | 미적용 시점                          | PostgreSQL 구현                                                                    |
| ------------------------- | ------------------------------ | ------------------------------------ | ---------------------------------------------------------------------------------- |
| Adjacency List            | 깊이 ≤5, 쓰기 빈번, 단순 트리  | 깊은 트리에서 조상/자손 쿼리 빈번    | `parent_id BIGINT REFERENCES self` + `WITH RECURSIVE` CTE                          |
| Materialized Path (ltree) | 깊이 10+, 조상/자손 검색 빈번  | 노드 이동 빈번 (경로 전체 갱신 비용) | `CREATE EXTENSION ltree` + GiST 인덱스 + `@>` 연산자                               |
| Closure Table             | 임의 깊이, 읽기/쓰기 균형 필요 | 단순 트리 (과도 설계)                | 교차 테이블 `(ancestor_id, descendant_id, depth)` + 자기참조 행 `(id, id, 0)` 필수 |
| Nested Sets               | 읽기 전용 또는 변경 극히 드묾  | 삽입/삭제 빈번 (전체 lft/rgt 재번호) | `lft`/`rgt` INTEGER 컬럼                                                           |

**선택 기준**: ①읽기/쓰기 비율 (읽기 위주 → ltree/Nested Sets, 쓰기 위주 → Adjacency List) ②트리 깊이 (≤5 → Adjacency List, 10+ → ltree) ③변경 빈도 (잦은 이동 → Adjacency List 또는 Closure Table)

**CTE 활용 패턴**: ①깊이 제한: 재귀 케이스에 `WHERE depth < {max_depth}` (부모 기준 검사 — `<=` 아님 주의) ②경로 문자열: `CONCAT(parent.path, ' > ', child.name)` 패턴 (Breadcrumb) ③계층 집계: 재귀 CTE로 자손 ID 수집 후 `WHERE id IN (...)` 집계

**안티패턴**: ①필요 전 Closure Table 도입 (YAGNI) ②self-FK 없이 `parent_id`만 (무결성 없음) ③깊이 제한 없는 재귀 CTE (무한 루프 위험 — 깊이 상한 조건 필수) ④루트 노드 식별 컬럼 누락 (`parent_id IS NULL` 또는 `depth = 0`)

---

## 11. 데이터 변경이력 설계

> **핵심 원칙: "디스크 용량 < 개발 생산성 + 운영 안정성"**. 단순한 전체 행 스냅샷이 복잡한 컬럼 단위 로그를 이긴다.

### 11.1 변경 추적 컬럼 단계

모든 테이블에 적절한 단계의 추적 컬럼을 적용한다.

| 단계                    | 컬럼                                                   | 적용 대상                                  |
| ----------------------- | ------------------------------------------------------ | ------------------------------------------ |
| **Level 1** (기본)      | `created_at`, `created_by`, `updated_at`, `updated_by` | **거의 모든 테이블** (§8 체크리스트)       |
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

유효기간 적용 시: 데이터 변경마다 이전 행의 `valid_to` UPDATE + 새 행 INSERT → **트랜잭션 필수**. `is_current BOOLEAN` + `valid_to` 중복은 의도적 반정규화 (직관성·인덱스 효율 → §7 원칙).

### 11.4 Generic Audit 패턴 (보조용)

`audit_logs` — `log_id` (PK), `table_name TEXT`, `row_id BIGINT`, `action TEXT`, `old_values JSONB`, `new_values JSONB`, `actor_id UUID`, `created_at TIMESTAMPTZ`. 트리거에서 `row_to_json(OLD)` / `row_to_json(NEW)` 활용.

**중요**: 공통 이력 테이블은 **주기적 아카이빙 필수** (월/분기 파티셔닝 + 보존 기간 후 cold storage 이동). 아카이빙 없이 운영 시 DB 용량 고갈 위험.

### 11.5 추적 제외 · 안티패턴 · 원칙

**추적 제외 대상**: 세션/토큰 테이블 · 캐시/임시 테이블 · 대량 로그 테이블 (별도 로그 파이프라인) · `audit_logs` 자기 자신

**비즈니스 이력 vs 시스템 로그**: DB에는 **비즈니스 이력만** 저장 (가격 변경, 상태 변경, 감사 기록 등). 시스템 로그 (HTTP 요청, 디버그 정보, 접속 기록)는 **파일 기반 로그 파이프라인**으로 관리. DB에 모든 로그를 쌓으면 비즈니스 트랜잭션 성능 저하 위험.

**안티패턴**: ①운영 테이블에 이력 컬럼 추가 (테이블 비대화) ②모든 테이블에 Generic Audit 적용 (성능 저하) ③이벤트 원장에서 레코드 UPDATE/DELETE (원장 불변 원칙 위반) ④`_history` 테이블에 INSERT 시점 이력 미저장 (타임라인 끊김·UNION 지옥) ⑤컬럼 단위 변경 로그(`column_name`, `old_value`, `new_value` TEXT)를 주 이력 전략으로 사용 (시점 복원 극도로 어려움 — 특정 필드 감사 표시용에만 허용)

---

## 12. 컬럼에 이전 값 보관 — SCD Type 3

**제한적 사용**: 직전 값 1개만 필요한 **선형 상태 머신**에서만 허용. 그 외 → §11 `_history` 테이블.

| 적용 조건                             | 미적용 조건                     |
| ------------------------------------- | ------------------------------- |
| 상태가 선형 전이 (A→B→C, 되돌림 없음) | 감사/규정 요구 (전체 이력 필요) |
| 직전 값 1개만 비즈니스에 필요         | 다단계 undo/redo 기능           |
| 조인 없이 즉시 비교 필요 (성능 우선)  | 3개+ 이전 값 추적 가능성        |
| 변경 빈도 낮음 (일 1~2회)             | 고빈도 갱신 (prev\_ 컬럼 낭비)  |

**네이밍**: `prev_{column_name}` 접미사. 예: `status` + `prev_status`, `tier` + `prev_tier`. 변경 시점 추적 필요 시 `{column}_changed_at TIMESTAMPTZ` 동반 컬럼 선택 추가.

**갱신 로직**: `UPDATE SET prev_status = status, status = :new_status` — 단일 문으로 원자적 교체. 앱 레벨에서 old value를 읽어 SET하지 않는다 (동시성 경쟁 위험).

**안티패턴**: ①`prev_prev_` 컬럼 등장 시 즉시 `_history` 테이블로 전환 ②앱에서 SELECT → 변수 저장 → UPDATE (race condition) ③prev\_ 컬럼에 트리거 없이 수동 관리 (누락 위험)

---

## 13. 데이터 삭제 전략 — Status vs Soft Delete vs Hard Delete

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
- RLS 정책: 모든 SELECT/UPDATE 정책의 `USING` 절에 `AND deleted_at IS NULL` 추가 (Supabase — 상세는 backend-guide 스킬의 supabase-patterns 리소스)
- Supabase 클라이언트: `.is("deleted_at", null)` 필터 또는 DB View로 자동 필터링

**이력 테이블과의 관계** (→ §11): Soft Delete와 `_history` 테이블은 **대체재가 아니라 보완재**. FK 참조 있는 핵심 테이블 → Soft Delete + `_history` 병행 (참조 무결성 유지 + 변경 이력 보존). FK 참조 없는 테이블 → Hard Delete + `_history`로 충분 (메인 테이블 경량화).

**안티패턴**: ①`is_deleted BOOLEAN` 사용 (삭제 시점 유실, 포렌식 불가) ②부분 인덱스 없이 전체 테이블 스캔 ③RLS 정책에 soft delete 미반영 (삭제 데이터 노출) ④soft delete + hard delete 혼용 (일관성 상실) ⑤핵심 도메인(주문·상품)에 `deleted_at` 적용 — Status 기반 관리를 먼저 검토하라

---

## 14. 통계테이블 설계

**기본: Materialized View** + `pg_cron` 주기적 갱신. 실시간 불필요 시 항상 MV 우선.

| 방식                   | 적용 시점                                                            | 미적용 시점                                       |
| ---------------------- | -------------------------------------------------------------------- | ------------------------------------------------- |
| Materialized View (MV) | 집계 쿼리 반복 · stale 허용 · 단순~중간 집계                         | 초 단위 실시간 필요 · MV refresh 비용 > 직접 쿼리 |
| Summary Table          | 증분 갱신 필요 · 커스텀 집계 로직 · MV refresh 전체 재계산 비용 과다 | 단순 COUNT/SUM (MV 충분)                          |
| 실시간 쿼리            | 데이터 소량 · 인덱스로 충분 · 항상 최신 필요                         | 대량 테이블 반복 집계 (응답 시간 초과)            |

**하이브리드 조회 전략** (실시간 통계가 필요하나 원본 전체 집계가 부담인 경우): 과거 데이터(통계/MV 테이블) `UNION ALL` 오늘 데이터(원본 테이블, 날짜 인덱스 필수). 오늘 하루치 데이터만 실시간 집계하므로 DB 부하 최소. 원본 테이블의 날짜 컬럼에 **반드시 인덱스**가 있어야 유효.

**시간 단위 집계 원칙**: 일별 통계 테이블(daily) 하나면 충분. 주간/월간/연간 통계는 일별 통계를 `GROUP BY`로 재집계 (10년치 = 3,650행, DB에게 일도 아님). 별도 월간/연간 테이블 생성은 관리 포인트만 증가 — 글로벌급 규모가 아니면 불필요.

**MV 네이밍**: `mv_{주제}_{단위}` (예: `mv_order_daily_stats`, `mv_user_monthly_summary`)

**MV 필수 사항**: ①`CREATE UNIQUE INDEX` 필수 — `REFRESH MATERIALIZED VIEW CONCURRENTLY` 전제조건 ②갱신: `pg_cron` 또는 Supabase Edge Function 스케줄 ③테이블 정의서에 갱신 주기 · 소스 쿼리 · stale 허용 시간 명시

**Summary Table**: `stat_{주제}_{단위}` 네이밍. `period_start TIMESTAMPTZ` + `period_end TIMESTAMPTZ` + 집계 컬럼 + `updated_at TIMESTAMPTZ`. BRIN 인덱스 (시계열 순차 삽입 최적).

**배치 갱신 전략** (멱등성 필수):

| 배치 유형                    | 전략                                                                                       | 이유                                                           |
| ---------------------------- | ------------------------------------------------------------------------------------------ | -------------------------------------------------------------- |
| 야간 배치 (1일 1회)          | **DELETE & INSERT** — 해당 기간 삭제 후 원본 재집계                                        | 멱등성 명확 · 환불 등 소급 변경 자동 반영 · 디버깅 용이        |
| 마이크로 배치 (분~시간 단위) | **UPSERT 전체값 덮어쓰기** — `INSERT ... ON CONFLICT DO UPDATE SET count = EXCLUDED.count` | DELETE & INSERT의 Undo/Redo Log 비용 회피 · 인덱스 파편화 방지 |

**안티패턴**: ①UNIQUE 인덱스 없이 `CONCURRENTLY` refresh 시도 (에러) ②갱신 주기 미문서화 (stale 데이터 인지 불가) ③MV로 충분한데 Summary Table 도입 (→ §7 역정규화 전제 위반) ④**`count = count + :delta` 누적 증분 갱신 — 배치 재실행 시 데이터 뻥튀기** (반드시 전체값 덮어쓰기 또는 DELETE & INSERT 사용)

---

## 15. 멱등성 설계

**결제 · 외부 API · 상태 전이**: 반드시 멱등성 보장. 순수 읽기 · 단일 트랜잭션 내부 연산은 불필요.

| 적용 필수                                 | 미적용                                   |
| ----------------------------------------- | ---------------------------------------- |
| 결제 처리 (외부 결제 webhook 재시도)      | 순수 읽기 (SELECT)                       |
| 상태 전이 (request→paid→completed)        | 단일 트랜잭션 내부 연산                  |
| 외부 API 호출 (푸시 알림 / OCR / 결제 등) | 생성 시점에 자연 UNIQUE 존재 (email 등)  |
| 분산 시스템 간 메시지 처리                | 삭제 연산 (이미 없으면 무시 = 자연 멱등) |

**패턴**: `idempotency_key VARCHAR(64) UNIQUE` 컬럼 추가. `INSERT ... ON CONFLICT (idempotency_key) DO UPDATE SET updated_at = now() RETURNING *` — 중복 요청 시 기존 결과 반환.

**키 생성 전략**: 클라이언트 생성 `{user_id}:{action}:{target_id}:{timestamp_bucket}` 또는 서버 생성 `{webhook_event_id}` (PG 웹훅 ID 활용).

**TTL**: `created_at + INTERVAL '24h'` 이후 `pg_cron` 배치로 정리 (무한 축적 방지). 인덱스: `idx_{테이블}_idempotency_key`.

**안티패턴**: ①멱등성 키 없이 웹훅 처리 (중복 결제·중복 적립 위험) ②TTL 없는 멱등성 레코드 (테이블 무한 팽창) ③앱 레벨 중복 체크만 (DB UNIQUE 제약 필수 — 동시 요청 방어) ④멱등성 키를 PK로 사용 (대리키 원칙 위반 → §3)

---

## 16. EAV vs JSONB 설계

**PostgreSQL에서 EAV 금지**. JSONB + GIN 인덱스가 모든 면에서 우월 (성능 수만 배, 저장 1/3).

| JSONB 적용 시점                                   | JSONB 미적용 시점 (정규 컬럼 사용)         |
| ------------------------------------------------- | ------------------------------------------ |
| 동적/확장 스키마 (사용자 정의 필드, 설정)         | 구조 확정 · 쿼리 빈번 · 인덱스 최적화 필요 |
| 희소 데이터 (대부분 행에서 NULL인 선택 속성)      | FK 참조 대상 (관계형 JOIN 필요)            |
| 메타데이터 · 외부 API 응답 캐시 · 이벤트 페이로드 | 집계/정렬 대상 (정규 컬럼 + B-tree 선호)   |
| 스키마 진화 빈번 (ALTER TABLE 없이 확장)          | 값의 NOT NULL · CHECK 제약이 필요한 경우   |

**GIN 인덱스 선택** (§5 확장):

| 연산자 클래스    | 용도                            | 크기          | 적용 시점                       |
| ---------------- | ------------------------------- | ------------- | ------------------------------- |
| `jsonb_path_ops` | `@>` containment 검색 전용      | 작음 (20~30%) | 대부분의 JSONB 검색 (기본 선택) |
| `jsonb_ops`      | `?`/`?|`/`?&`/`@>` 키 존재·부분 매칭 | 큼 (60~80%)   | 키 존재 여부 검색 필요 시만     |

**검증**: DB `CHECK` 제약 (구조 고정 시) 또는 앱 Zod 스키마 (구조 유동 시). §5 기존 규칙과 동일.

**안티패턴**: ①EAV 테이블 (`entity_id`, `attribute`, `value` TEXT) — 타입 안전성·쿼리 성능·저장 효율 모두 상실 ②정규화 회피용 JSONB (구조적 데이터를 JSONB에 때려넣기 — §4 1NF 위반) ③GIN 인덱스 없는 JSONB 검색 (sequential scan) ④`jsonb_ops` 남용 (containment만 필요 시 `jsonb_path_ops`로 60%+ 인덱스 절약)

---

## 17. 슈퍼타입/서브타입 (상속 관계) 설계

> **경계**: 상속 설계는 **안정적이고 예측 가능한 타입 계층**에 사용. 속성이 동적이고 예측 불가하면 §16 JSONB를 사용.

**기본: 조인 전략** (부모+자식 테이블, PK 공유 1:1). 서브타입 적고 고유 속성 적으면 단일 테이블도 허용.

| 전략                     | 구조                                                        | 장점                                               | 단점                                                 | 적용 시점                                                |
| ------------------------ | ----------------------------------------------------------- | -------------------------------------------------- | ---------------------------------------------------- | -------------------------------------------------------- |
| **조인 전략** (Joined)   | 부모 테이블(공통 속성) + 자식 테이블(고유 속성), PK 공유 FK | 정규화 · NOT NULL 가능 · FK 가능 · 확장 용이       | 상세 조회 시 JOIN 필요 · INSERT 2회                  | 서브타입 많거나 확장 예정 · 고유 속성 많음 · 무결성 중요 |
| **단일 테이블** (Single) | 하나의 테이블 + `type` 구분자 컬럼, 고유 속성은 NULL 허용   | 조회 성능 최상 (JOIN 불필요) · 쿼리 단순 · FK 가능 | NULL 다수 · NOT NULL 불가(고유 속성) · 테이블 비대화 | 서브타입 적고 고정적 · 고유 속성 적음 · 성능 우선        |

**조인 전략 핵심**: 자식 테이블의 PK = 부모 테이블의 PK를 참조하는 FK (1:1 관계). `FOREIGN KEY (product_id) REFERENCES product(product_id)`. 전체 조회는 부모 테이블만, 상세 조회는 `LEFT JOIN`.

**Table-per-Concrete-Class 금지**: 자식마다 공통 속성을 중복 보유하는 방식. ①전체 조회 시 `UNION ALL` 필요 ②FK 설정 불가 ③공통 속성 변경 시 모든 테이블 수정 — 실무에서 사용하지 않는다.

**선택 기준**: ①유형 간 차이 크고 고유 속성 많으면 → 조인 전략 ②유형 간 차이 적고 고유 속성 적으면 → 단일 테이블 ③속성이 동적으로 변하거나 카테고리가 계속 늘어나면 → §16 JSONB (상속 설계 대상이 아님)

---

## 18. SECURITY DEFINER 함수 작성 컨벤션

> `_history` 트리거 + 민감 RPC + Vault 함수 등 PostgreSQL SECURITY DEFINER 함수 공통 작성 표준.
> 실전 운영에서 반복 검증된 결함 패턴(search_path 누락, ambiguous 인자명, 권한 우회)에서 승격된 규칙이다.

### 18.1 5단계 체크리스트 (모든 SECURITY DEFINER 함수에 적용)

| #   | 단계                            | 패턴                                                                                                                                          | 누락 시 위험                                                                                                |
| --- | ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| 1   | `SET search_path` 명시          | `LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions` (vault 사용 시 `vault, public, extensions`)                          | 세션 search_path 의존 → 동명 객체 공격 / Supabase Security Advisor 경고                                     |
| 2   | 인자명 `p_` 접두사              | `CREATE FUNCTION fn(p_user_id BIGINT, p_key_id TEXT)`                                                                                         | 외부 뷰/테이블 컬럼명과 ambiguous error (42702) — 함수 진입 자체 차단                                       |
| 3   | 외부 객체 조회 시 명시 prefix   | `WHERE vault.decrypted_secrets.name = p_key_id`                                                                                               | 인자 접두사 누락 시 ambiguous error 재발                                                                    |
| 4   | `REVOKE EXECUTE` + `GRANT` 명시 | `REVOKE EXECUTE ON FUNCTION public.fn(args) FROM PUBLIC, anon, authenticated; GRANT EXECUTE ON FUNCTION public.fn(args) TO service_role;`     | Supabase default GRANT 정책상 anon/authenticated가 EXECUTE 권한 보유 → 클라이언트 직접 RPC 호출로 권한 우회 |
| 5   | 사후 검증 DO 블록 + e2e         | 마이그레이션 본문에서 `pg_proc.proconfig` + `has_function_privilege` 검증 + `RAISE EXCEPTION` / anon 클라이언트로 RPC 호출 시 42501 차단 확인 | 적용 통과 ≠ 작동 통과. runtime ambiguous, 권한 누설 등 잠재 결함이 배포까지 누출                            |

### 18.2 `_history` 트리거 함수 추가 의무 + DO 검증 블록 배치 컨벤션

`_history` 테이블에 INSERT하는 트리거 함수는 §11.3과 본 §18을 동시 적용:

- 위 1~5단계 + **`_history` 테이블에 INSERT 정책 명시 의무** (RLS deny-by-default에 걸려 이력 기록이 조용히 실패하는 사고 방지)
- **운영 테이블 NOT NULL/CHECK 변경 시 `_history` 동기 동반** (원본만 고치면 이력 INSERT가 제약 위반으로 실패)

**DO 검증 블록 배치 컨벤션**:

- DO 블록은 항상 마이그레이션 **본문 말미**(`REVOKE` / `GRANT` 직후)에 배치
- `COMMIT` 이전 위치 — Postgres는 마이그레이션을 단일 트랜잭션으로 실행하므로 DO 블록이 RAISE EXCEPTION으로 실패하면 전체 마이그레이션 롤백 (의도된 동작)
- 검증 항목은 **결정론적**으로 잡는다: `pg_proc.proconfig` 존재 / `has_function_privilege` 부정 확인 / `pg_cron.job` 존재 / 카탈로그 행 COUNT — `RAISE NOTICE`로 합격 메시지를 1회 출력, 의도된 차단만 `RAISE EXCEPTION`
- 안티패턴: 비결정론적 데이터 (예: 운영 시드 행 COUNT >= N) 또는 향후 도입될 데이터에 의존하는 검증 — 자기 마이그레이션이 자기 자신을 abort시킬 위험. 시드는 별도 ON CONFLICT INSERT로 분리하고 검증은 **방금 작성한 객체의 정의**에만 의존

### 18.3 안티패턴

- ① `REVOKE FROM PUBLIC`만 명시하고 anon/authenticated 누락 — Supabase는 anon에 별도 default GRANT 부여하므로 PUBLIC 회수만으로는 차단 불가
- ② 인자명 `name`, `key_id`, `type` 등 흔한 컬럼명 사용 — vault/storage/pg_catalog 등 시스템 뷰와 충돌 위험
- ③ 마이그레이션 적용 후 anon RPC 호출 검증 생략 — DO 블록 사후 검증으로 부분 보강 가능하나 e2e가 결정적
- ④ lessons에 표준 패턴을 기록하고도 직후 마이그레이션에서 동일 결함 재발 — lessons 작성 시 잔존 동일 패턴 전수 grep + 정정 마이그레이션 동시 진행
- ⑤ **DO 검증 블록에서 외부 의존(FK·RLS·트리거) INSERT/UPDATE 시도 후 EXCEPTION catch 금지** — 의도와 다른 다층 exception(FK 위반·CHECK 위반·RLS 거부)이 catch에 잡혀 잘못된 판단으로 흐름. `pg_constraint` + `pg_get_constraintdef` LIKE / `information_schema.columns` / `pg_proc.proconfig` / `has_function_privilege` 카탈로그 정적 검증만 사용

### 18.4 동적 e2e 동반 의무 (정적 검증의 한계)

SECURITY DEFINER RPC + RLS 정책은 모듈 단위 정적 검증(DO 블록·grep·typecheck·db:types)만으로 결함 침묵 통과한다. 정적 검증은 "구조"를 보장하고 "동적 결합"은 보장하지 못한다:

- ① 신규 RPC가 의존하는 컬럼이 마이그레이션에 누락(`42703 column does not exist`) — DO 카탈로그 검증은 함수 본문 컬럼 참조까지 grep하지 않음
- ② RLS UPDATE 정책 `USING`만 명시 `WITH CHECK` 누락 — viewer 권한 UPDATE 시점에 `42501` 차단 (`pg_policy` 카탈로그 검증은 정책 존재만 확인)
- ③ 인자명 + 외부 뷰 컬럼 ambiguous (`42702`) — syntax 통과 + 적용 통과 + runtime fail

**의무 패턴**: 신규 SECURITY DEFINER RPC 또는 RLS 정책 추가 시 모듈 단위 DO 블록과 함께 **본문 실제 호출 e2e 1건 동반 작성**. 정적 검증과 동적 검증을 같은 작업 단위에 묶어 결함 발견 → 정정 마이그 → push의 사이클을 1회로 종결한다.

**검증 스크립트 작성 시 추가 3축 self-check** (e2e SQL/MCP/CLI 모두 공통):

- ① 실행 환경 권한 (service_role / anon) — MCP execute_sql 등은 권한 확인 의무
- ② 결과 수신 능력 (`RAISE NOTICE` 수신 여부, RETURNS TABLE vs row count) — 환경별로 다름
- ③ 시간/타입 변환식의 의도-표현 1:1 매칭 (sample 값 1건 mental run)

위 3축 미통과 시 e2e는 통과처럼 보이나 의도된 시나리오를 수행하지 않음.
