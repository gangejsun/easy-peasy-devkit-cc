<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# 멱등성 설계

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

**안티패턴**: ①멱등성 키 없이 웹훅 처리 (중복 결제·중복 적립 위험) ②TTL 없는 멱등성 레코드 (테이블 무한 팽창) ③앱 레벨 중복 체크만 (DB UNIQUE 제약 필수 — 동시 요청 방어) ④멱등성 키를 PK로 사용 (대리키 원칙 위반 → 카드 §3)
