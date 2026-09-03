---
paths:
  - "supabase/**"
  - "**/migrations/**"
  - "db/**"
  - "prisma/**"
  - "drizzle/**"
  - "dev/docs/database/**"
---
<!-- epcc-rule-version: 3.25.0 -->

# 데이터 모델링 카드

> 김영한의 현대적 데이터 모델링 철학 기반. 새 테이블·마이그레이션·스키마 변경 설계 시 적용한다.
> 프로젝트에 정본 스키마 문서(`dev/docs/database/`)가 있으면 그것과 일관성을 유지한다.
>
> **적용 범위**: §1~4·6~8은 관계형 DB 공통, §5는 PostgreSQL(Supabase 포함) 특화 —
> 다른 RDB에서는 원칙만 취하고 문법은 해당 DB로 치환한다. 아래 「패턴 참조」의 각 파일도
> 머리에 적용 범위를 밝힌다. NoSQL 프로젝트에서는 이 카드의 paths가 거의 매칭되지 않아 휴면 상태가 된다.

**3대 원칙**: 대리키 우선 · 3NF 기본 · 비식별 관계 기본

---

## 1. 요구사항 분석 — 엔티티 추출

**추출 규칙**: 업무 기술서에서 **명사 → 엔티티 후보**, **동사 → 관계/행위 엔티티 후보**.

**엔티티 유효성 6기준** (모두 충족 시 엔티티): ①업무 필요 ②유일 식별자 존재 ③2+인스턴스 ④2+속성 ⑤업무 프로세스에서 이용 ⑥다른 엔티티와 관계 존재

**엔티티 분류**: 기본(독립 존재: 고객, 상품) → 중심(관계 파생: 주문, 계약) → 행위(이벤트 기록: 주문상세, 결제내역)

**설계 패턴**: 마스터-트랜잭션 분리(users vs transactions) · 코드 테이블 추출(TEXT+CHECK 또는 참조 테이블 → `common-code.md` 상세) · 이력 관리(`_history` 테이블 분리 → `change-history.md` 상세)

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

**흔한 실수**: JSONB로 1NF 우회 (구조적 데이터를 JSON에 때려넣기), EAV 패턴 남용 (→ `eav-vs-jsonb.md` 상세), 과도한 정규화 (코드 테이블 10단계 분리).

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
| 요약 테이블       | 대량 집계 매번 스캔 | Materialized View 또는 주기적 갱신 (→ `statistics.md`) |

**필수**: 역정규화 시 사유·동기화 메커니즘·정합성 위험을 테이블 정의서에 기록.

---

## 8. 마이그레이션 & RLS 체크리스트

새 테이블 생성 시 필수 점검:

- [ ] `CREATE TABLE` + 인라인 제약조건 (PK, FK, CHECK, NOT NULL, DEFAULT)
- [ ] `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` + 최소 1개 정책 (행 수준 보안을 쓰는 스택에 한함 — 정책 상세는 해당 스택 backend-guide의 인증/권한 경계 리소스. RLS가 없는 스택은 애플리케이션 층 소유권 검사가 유일한 경계다)
- [ ] FK 컬럼에 인덱스 생성 (`idx_{테이블}_{FK컬럼}`)
- [ ] 빈번한 WHERE/ORDER BY 컬럼에 인덱스 추가
- [ ] JSONB 컬럼에 GIN 인덱스 (내부 검색 필요 시)
- [ ] TypeScript 타입 정의 → 프로젝트 타입 디렉토리 (모노레포면 공유 패키지 `types/`) + barrel export 업데이트
- [ ] 테이블 정의서 → `dev/docs/database/` (선택, 중규모+ 시)
- [ ] `created_at TIMESTAMPTZ DEFAULT now()` + `updated_at TIMESTAMPTZ DEFAULT now()` 공통 컬럼
- [ ] `created_by UUID` + `updated_by UUID` 공통 컬럼 (거의 모든 테이블에 기본 적용 → `change-history.md` Level 1)
- [ ] 비즈니스 이력 필수 테이블 → `_{테이블}_history` 이력 테이블 동시 생성 (→ `change-history.md`)
- [ ] Soft Delete 적용 시: `deleted_at` 컬럼 + 부분 인덱스 + RLS 조건 반영 (→ `deletion-strategy.md`)
- [ ] 멱등성 필요 시: `idempotency_key` UNIQUE 컬럼 + TTL 정리 (→ `idempotency.md`)

---

---

## 패턴 참조 — 필요한 것만 읽는다

이 카드는 **스키마를 만들 때 항상 필요한 것**만 담는다(§1~8). 아래 열 가지 패턴은
그 패턴을 **실제로 설계할 때만** 필요하므로 `.claude/references/data-modeling/`으로 내렸다.
해당하는 줄의 파일 **하나만** 읽는다 — 전부 읽으면 이 분리가 무의미해진다.

| 지금 설계하는 것 | 읽을 파일 |
| --- | --- |
| 상태·구분·유형처럼 **값 집합이 정해진 컬럼**을 만든다 | [`common-code.md`](../references/data-modeling/common-code.md) — 공통코드 테이블 설계 |
| 카테고리·조직도처럼 **자기 자신을 참조하는 계층**을 만든다 | [`hierarchy.md`](../references/data-modeling/hierarchy.md) — 계층구조 설계 |
| 누가 언제 무엇을 바꿨는지 **이력을 남겨야** 한다 | [`change-history.md`](../references/data-modeling/change-history.md) — 데이터 변경이력 설계 |
| 직전 값 하나만 컬럼에 들고 있으면 되는 경우 | [`scd-type3.md`](../references/data-modeling/scd-type3.md) — 컬럼에 이전 값 보관 — SCD Type 3 |
| 삭제를 어떻게 할지 정한다 (상태값 · Soft · Hard) | [`deletion-strategy.md`](../references/data-modeling/deletion-strategy.md) — 데이터 삭제 전략 — Status vs Soft Delete vs Hard Delete |
| 집계·대시보드용 **통계 테이블**을 만든다 | [`statistics.md`](../references/data-modeling/statistics.md) — 통계테이블 설계 |
| 결제·웹훅처럼 **같은 요청이 두 번 와도** 안전해야 한다 | [`idempotency.md`](../references/data-modeling/idempotency.md) — 멱등성 설계 |
| 속성이 가변적이라 컬럼을 고정할 수 없다 | [`eav-vs-jsonb.md`](../references/data-modeling/eav-vs-jsonb.md) — EAV vs JSONB 설계 |
| 공통 속성 + 타입별 속성으로 **상속 관계**를 만든다 | [`supertype-subtype.md`](../references/data-modeling/supertype-subtype.md) — 슈퍼타입/서브타입 (상속 관계) 설계 |
| 권한을 넘겨 실행하는 **DB 함수**를 작성한다 | [`security-definer.md`](../references/data-modeling/security-definer.md) — SECURITY DEFINER 함수 작성 컨벤션 |
