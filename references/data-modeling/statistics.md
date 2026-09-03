<!-- epcc-rule-version: 3.25.0 · 이 파일이 정본. 상위 카드: .claude/rules/data-modeling.md -->

# 통계테이블 설계

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

**안티패턴**: ①UNIQUE 인덱스 없이 `CONCURRENTLY` refresh 시도 (에러) ②갱신 주기 미문서화 (stale 데이터 인지 불가) ③MV로 충분한데 Summary Table 도입 (→ 카드 §7 역정규화 전제 위반) ④**`count = count + :delta` 누적 증분 갱신 — 배치 재실행 시 데이터 뻥튀기** (반드시 전체값 덮어쓰기 또는 DELETE & INSERT 사용)
