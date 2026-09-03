<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# SECURITY DEFINER 함수 작성 컨벤션

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

`_history` 테이블에 INSERT하는 트리거 함수는 [`change-history.md`](./change-history.md)의 트리거 절과 이 문서를 동시 적용:

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
