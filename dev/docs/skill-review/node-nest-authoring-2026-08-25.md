# node-nest 축 팩 저작 실측 (2026-08-25)

백엔드 8번째 축(`backend/node-nest` — NestJS 11 + TypeORM 1 + class-validator + Jest)을
`pack-authoring.md`의 L0→L1→L3 경로로 만들었다. **첫 데코레이터 축**이고, 그 사실이
하네스 결함 세 건을 실물로 끌어냈다 — fastapi(첫 Python 축)·vanilla(첫 JavaScript 축)에서
난 것과 같은 부류다. 「새 툴체인을 들이면 하네스가 한 언어만 안다고 가정한다」는 규범이
세 번째로 값을 냈다.

## 이 세션의 방식 — 병렬을 쓰지 않았다

`pack-authoring.md`가 규정한 L1 팬아웃(클러스터 병렬)을 **쓰지 않고 직렬로** 저작했다.
세션 설정이 서브에이전트 사용을 막았기 때문이고, 품질 기준은 한 항목도 바꾸지 않았다
(`--pack` FAIL 0 · `pack-smoke --online` FAIL 0). 그러므로 이 기록은 병렬 대 직렬의
비교값이 아니다 — **되돌림 기준 표의 입력으로 쓰지 않는다.**

대신 직렬이라서 가능했던 것 하나를 기록한다: **저작 전에 참조 구현을 세워 실행으로
먼저 확인했다.** 스크래치에 NestJS 11 프로젝트를 만들고 실 PostgreSQL 18.4(임베디드)에
붙여 21개 파일을 돌린 뒤, 그 파일들을 그대로 펜스에 옮겼다. 팩의 모든 `<!-- file: -->`
펜스는 **실행된 코드**이지 기억에서 쓴 코드가 아니다.

## 산출

| 항목 | 값 |
| --- | --- |
| 리소스 | 7개 (project-structure · data-modeling · data-access · input-validation · error-handling · testing · operations) |
| 완전 파일 주장 | 26개 (원장이 선언한 소스 경로 20건 전부 포함) |
| 게이트 `--pack` | 통과 28 · WARN 4 · REVIEW 2 · **FAIL 0** |
| `pack-smoke --online` | 통과 8 · WARN 1 · SKIP 2 · **FAIL 0** — **타입체크 통과** |
| 정책 | 17건 (기계 검사 15 + 이음매 대상 2), 전부 증명 예·반례 통과 |
| 도달 검증 | `install-guide.sh --backend node-nest` 로 소비자 프로젝트에 리소스 7개 조립 확인 |

`pack-smoke --online`의 타입체크가 **실제로 통과한 첫 팩**이다. node-api는 같은 자리에서
`prisma generate` 부재로 FAIL 1이 남아 있고 그것이 knownGap으로 기록돼 있다.

## 하네스 결함 — 데코레이터 축이 드러낸 것

| # | 결함 | 증상 | 픽스처 |
| --- | --- | --- | --- |
| 1 | `fixesVariants` 대조가 **패키지 이름을 부분 문자열로** 찾는다 | `@nestjs/platform-express`(Nest의 기본 HTTP 어댑터)가 「경쟁 제품 express」로 잡혀 정상 팩이 FAIL. `check_leak`의 `nextCursor ↔ next`와 같은 부류 | `fvscope`(오탐) + `fvscopebad`(미탐) 양방향 |
| 2 | `check_env`가 **클래스 필드로 선언한 스키마**를 보지 못한다 | class-validator 축은 스키마가 객체가 아니라 클래스이고 값 자리에 **타입**이 온다. 선언 0건으로 보고 `env.LOG_LEVEL` 사용을 「스키마에 없는 키」로 FAIL | `envclass` + `envclassbad` 양방향 |
| 3 | 프로필이 **`experimentalDecorators` 없이** tsconfig를 만든다 | TypeScript 5는 그때 데코레이터를 ES 표준으로 읽는다 — 그 문법에 **파라미터 데코레이터가 없어** 정상 Nest 코드가 TS1240으로 전부 실패 | `deco` (+ 데코레이터 없는 팩은 꺼지는지도 단언) |
| 4 | strip-only 모드가 거부한 단위를 **타입체크 트리에 넣지 않는다** | 그 UNSUP은 「정상 TypeScript일 수 있다」고 스스로 보고하면서 tsc가 있어도 영영 판정하지 않았다. NestJS는 생성자 주입이 곧 파라미터 프로퍼티라 **서비스·컨트롤러가 통째로 검사 밖**이었다 (미탐) | `deco` — 실트리에 파일이 놓이는지 단언 |
| 5 | `types`를 `["node"]`로 못박아 **팩이 선언한 나머지 @types가 시야 밖** | 팩이 배송한 테스트 파일이 `Cannot find name 'describe'`로 실패 (오탐) | 설치된 `@types/*` 전량을 싣도록 변경 |
| 6 | 원장 형태의 **인자 개수 대조가 앞머리 고정** | 규범이 「형태 열에 소스 경로를 적는다」로 바뀌자 형태가 `` `src/boot.ts`. `boot(raw) => Env` ``로 시작해 **대조가 통째로 건너뛰어졌다**. 픽스처가 인자 개수를 틀리게 해도 통과 (미탐) | 기존 `badarity`가 다시 살아났다 |

**5·6은 node-nest가 원인이 아니라 계기다.** 6은 「소스 경로를 형태에 적는다」는 규범 자체가
만든 사각지대이므로 **모든 팩에 소급 적용된다** — 형태 열에 경로를 적은 팩은 그동안 인자
개수를 검사받지 않았다.

## 자기검사가 빨간 채였다 (선행 상태)

작업 시작 시점에 `guide-gate --self-test`가 **FAIL 9~10**이었다. 원인은 팩 결함이 아니라
**픽스처가 규격을 따라오지 못한 것**이다: 정책 표에 `반례` 열이 신설됐고 `provides` 형태에
소스 경로가 의무가 됐는데 합성 픽스처는 구 형식 그대로였다. 픽스처 5종을 규격에 맞춘 뒤
**FAIL 0(통과 53)**이 됐다.

> **차단 장치의 자기검사가 빨간 채로 오래 있으면 새 빨강과 옛 빨강을 구분할 수 없다.**
> 이번에 새 픽스처를 얹기 전에 먼저 초록으로 만들어야 했던 이유가 그것이다.

## 팩이 실행으로만 알아낸 것 (24건 중 골라 기록)

| 관측 | 결과 | 팩의 처방 |
| --- | --- | --- |
| `timestamptz`(µs) ↔ JS `Date`(ms) | 커서를 ISO로 왕복시키면 **5행 중 1행이 조회에서 누락** | 컬럼에 `precision: 3` — 같은 시나리오가 5행 완주 |
| `where`가 배열이면 OR | 한 분기의 `ownerId`를 빼자 다른 소유자의 행이 섞였다(8행) | 분기마다 `...base` 전개. **정규식은 이 결함을 못 본다** → 「사람이 지킬 것」 |
| `app.close()` + keep-alive | 5.8초 시한까지 **반환하지 않았다**. `closeAllConnections()`에 즉시 완료 | 배수 → 유예 → close → 시한 강제 |
| `onModuleDestroy` 발화 시점 | SIGTERM 후 **1ms**, 처리 중 요청은 1.2초 뒤 완료 | provider를 여기서 닫지 않는다 |
| `ConfigModule.forRoot()` 평가 시점 | **모듈 파일 로드 시점**에 validate가 돈다 | 테스트 스키마는 `setupFiles`에서 정한다 |
| 위 항목의 발견 경로 | 테스트는 **4/4 초록이었다**. `pg_tables`를 직접 조회해서 알았다 | 격리가 실제로 걸렸는지는 DB에 물어본다 |
| `select`의 좁힘 | 런타임 값만 좁고 **타입은 `Task` 그대로** | 반환 타입을 `TaskView`로 명시 |
| `AppError`(비 HttpException) | 예외 필터가 없으면 **전부 500** | 이음매의 필터가 봉투를 방출한다 |

마지막에서 두 번째 줄이 이 세션에서 가장 비싼 교훈이다 — **초록인 테스트가 격리되지 않은
채로 돌고 있었다.** 실패가 아니라 관측이 그것을 잡았다.

## 남긴 공백 (`pack.json`의 `knownGaps`가 정본)

1. 요청 상관관계 ID — `ConsoleLogger({ json: true })`의 출력 형태만 확인했고 `AsyncLocalStorage` 배선은 미검증
2. `migration:generate`의 산출 — 손으로 쓴 마이그레이션만 실행 확인
3. 다중 인스턴스 마이그레이션 경합 — 지침의 근거가 관측이 아니라 원리
4. TypeScript 7 — `moduleResolution: "node"`가 TS5108로 제거됐다. TS5와 TS7을 **하나의 tsconfig로 만족시킬 수 없어** 검증한 쪽(TS5)을 싣고 기록만 남겼다
