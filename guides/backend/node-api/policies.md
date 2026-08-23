<!-- epcc-pack-policies: backend/node-api v3.13.0 -->

# node-api 팩 — 파일 간 불변식 (L0 초안)

이 팩이 **선언한 정책을 팩 자신과 이음매가 지키는지** 게이트가 대조한다. 정책을 선언한 곳과
강제하는 곳이 다르고 둘을 맞춰볼 의무가 없으면 정책은 문서로만 남는다 — 이 파일이 그 의무다.

## 기계 검사 (게이트 `check_policies` · `check_pack_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간 아님.
산문과 안티패턴 예시를 세면 전부 위양성이 된다.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 게이트가 ① 예가 자기 정규식에 매치되는가
② `forbid`면 그 예가 대상 파일에 실재하지 않는가를 단언한다. 실측(2026-08-23)에서 정책마다
결함 픽스처를 만들어 돌리는 일이 vue 저작의 벽시계를 지배했고, 이 열이 그 왕복을 대체한다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 scope로 인식되지 않아 정책이
조용히 전 파일을 겨눈다 — vue 팩에서 실제로 그랬다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | guide | `process\.env` | `input-validation.md, testing.md` | `const url = process.env.DATABASE_URL` | 환경 값은 `env` 한 곳에서만 읽는다. 다른 파일이 직접 읽으면 타입도 검증도 부팅 시점 실패도 우회된다. 예외 둘: 스키마를 적용하는 자리와, 테스트가 격리 DB를 주입하는 자리 |
| `boot-time-env-validation` | require | guide | `safeParse\([^)]*process\.env` | — | `EnvSchema.safeParse({ ...process.env })` | 누락·형식 오류가 첫 사용 시점이 아니라 **부팅 시점에** 실패해야 한다. 첫 사용 시점 실패는 배포 몇 시간 뒤 특정 요청에서 터진다 |
| `prisma-single-client` | forbid | guide | `new PrismaClient\(` | `data-access.md` | `const db = new PrismaClient()` | 클라이언트가 둘이면 커넥션 풀이 둘이 된다. 싱글턴을 정의하는 자리만 예외다. **테스트도 예외가 아닌 것은 의도다** — 격리는 새 클라이언트가 아니라 URL 주입으로 한다 (C3 확인) |
| `no-raw-sql-interpolation` | forbid | guide | `\$(queryRawUnsafe\|executeRawUnsafe)` | — | `prisma.$queryRawUnsafe(sql)` | `Unsafe` 변형은 문자열을 그대로 보낸다. 태그드 템플릿(`$queryRaw`)은 파라미터화되므로 허용이다. **테이블 이름은 파라미터화할 수 없어 이 축에서 `TRUNCATE` 기반 테스트 정리는 봉쇄된다 — 의도한 것이다**: `deleteMany()`가 느리지만 FK 순서를 타입으로 강제받는다 (C3 지적) |
| `ownership-in-query` | require | guide | `where:[[:space:]]*\{[^}]*ownerId` | — | `where: { id, ownerId }` | **이 축의 최대 위험.** 데이터 계층 정책 엔진이 없으므로 소유권은 쿼리 조건에 걸어야 한다. 조회 후 비교는 경합에 뚫리고, 누락은 곧 데이터 유출이다. **정규식이 `where` 객체 안을 요구하는 이유**: 맨 `ownerId:`는 TypeScript 파라미터 주석(`ownerId: string`) 한 줄로 충족돼 `where`에 실렸는지를 전혀 보지 못한다 — C2가 실측으로 찾았다 |
| `mutation-affected-rows` | require | guide | `\.count[[:space:]]*===[[:space:]]*0` | — | `if (res.count === 0) throw new AppError('NOT_FOUND')` | 소유권 필터가 걸린 변이는 남의 행에 대해 **0행 변경**으로 조용히 성공한다. 영향 행 수를 보지 않으면 200을 돌려준다 |
| `db-layer-knows-no-http` | forbid | file:data-access.md | `\b(Request\|Response\|NextFunction)\b\|\bres\.(status\|json\|send\|sendStatus\|set\|cookie\|redirect\|end)\b` | — | `export function listTasks(req: Request) {` | 데이터 계층이 HTTP를 알면 테스트에 서버가 필요해지고 계층이 무너진다. 쿼리 함수는 평범한 인자만 받는다. **맨 `res.`를 금지하지 않는 이유**: 변이 결과의 관용적 이름이 정확히 `res`라 `mutation-affected-rows`의 `res.count === 0`과 충돌한다 — 응답 객체의 메서드만 겨눈다 (C2 실측) |
| `no-console` | forbid | guide | `console\.(log\|error\|warn)\(` | — | `console.log(user)` | 구조적 로거만 쓴다. `console`은 요청 상관관계·레벨·직렬화가 없어 운영에서 검색되지 않는다 |
| `graceful-shutdown` | require | guide | `SIGTERM` | — | `process.on('SIGTERM', shutdown)` | 컨테이너 종료 시 처리 중인 요청을 배수하지 않으면 배포마다 5xx가 난다 |
| `error-status-single-table` | require | guide | `ERROR_STATUS` | — | `ERROR_STATUS[err.code] ?? 500` | 상태 코드를 파일마다 정하면 같은 실패가 자리에 따라 다른 코드로 나간다 |
| `vocab-task` | forbid | guide | `\bnotes?\b\|노트` | — | `const notes = []` | 도메인 어휘는 `Task`/`tasks`/`작업`으로 고정한다 (L0 발행). 실측에서 프론트가 `/tasks`, 백엔드가 `/notes`를 써서 완전 예제가 서로 실행 불가였다 — 클러스터를 갈라 저작하면 그 표면이 늘어난다 |
| `requireauth-on-router` | require | seam | `requireAuth` | — | `router.post('/', requireAuth, createTask)` | **대상이 `seam`인 이유**: `requireAuth`는 이음매가 정의하므로 `guide`로 걸면 이음매가 배포되는 한 절대 실패하지 않는다 — 정작 검증해야 할 라우터 배선이 검사되지 않는다 (vue 팩의 실측 지적) |
| `envelope-from-error-handler` | require | seam | `errorHandler` | — | `app.use(errorHandler)` | 봉투 방출은 한 곳에서만 한다. 라우터가 직접 `res.status(400).json(...)`을 하면 봉투가 갈라진다. 위와 같은 이유로 이음매를 겨눈다 |

`대상`이 `guide`면 조립된 가이드 전체(팩 + 이음매), `pack`이면 팩 파일만, `seam`이면 이음매
파일만, `file:<이름>`이면 그 파일만 본다. `require`는 최소 1회 등장이면 충족이다.
조립 전(`--pack`)에는 `seam` 대상 정책이 판정 불가이므로 **건너뛴 것을 명시 보고**한다.

## 사람이 지킬 것 (기계로 판정 불가)

- **부재와 권한 없음을 구분해 응답하지 않는다.** 남의 행을 조회하면 403이 아니라 404다 —
  구분하면 미인가 사용자가 리소스 존재를 열거할 수 있다. 정규식으로는 응답 분기의 의미를
  볼 수 없다
- **`findUnique({ where: { id } })`로 조회한 뒤 소유자를 비교하지 않는다.** 소유권은 조회
  조건에 넣는다. 두 형태는 줄 단위로 구분되지 않는다 — `ownerId:`가 있는지만 기계가 본다
- **부분 업데이트 스키마에 `.default()`를 겹치지 않는다.** 보내지 않은 필드가 기본값으로
  덮어써진다. 문법은 완벽하고 실행만이 드러낸다 (실측 최악의 결함)
- **트랜잭션 안에서 외부 호출(HTTP·큐)을 하지 않는다.** 롤백되지 않고 락만 길어진다
- **`select`로 필요한 열만 가져온다.** 특히 비밀·해시 열이 있는 모델에서 전체 선택은
  로그·응답으로 새는 경로가 된다
- **마이그레이션은 배포와 분리된 단계로 돌린다.** 애플리케이션 부팅에서 `migrate deploy`를
  하면 인스턴스가 동시에 뜰 때 경합한다
