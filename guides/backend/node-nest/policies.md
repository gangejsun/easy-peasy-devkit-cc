<!-- epcc-pack-policies: backend/node-nest v3.16.0 -->

# node-nest 팩 — 파일 간 불변식

이 팩이 **선언한 정책을 팩 자신과 이음매가 지키는지** 게이트가 대조한다. 정책을 선언한 곳과
강제하는 곳이 다르고 둘을 맞춰볼 의무가 없으면 정책은 문서로만 남는다 — 이 파일이 그 의무다.

## 기계 검사 (게이트 `check_policies` · `check_pack_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간 아님.
산문과 안티패턴 예시를 세면 전부 위양성이 된다.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 게이트가 ① 예가 자기 정규식에 매치되는가
② `forbid`면 그 예가 대상 파일에 실재하지 않는가를 단언한다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 scope로 인식되지 않아 정책이
조용히 전 파일을 겨눈다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 반례 | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | guide | `process\.env` | `data-modeling.md, testing.md` | `const url = process.env.DATABASE_URL` | `process.env['DATABASE_URL']` | 환경 값은 `validateEnv`를 거친 뒤 `ConfigService`로만 읽는다. 직접 읽으면 타입도 검증도 부팅 시점 실패도 우회된다. 예외 둘: DI 밖에서 도는 **CLI DataSource**와, 워커 ID로 스키마를 가르는 테스트 하네스. **`main.ts`는 예외가 아닌 것이 의도다** — `bufferLogs: true` + `useLogger`가 있어서 로거를 만들려고 env를 먼저 읽을 이유가 없다 |
| `env-validated-at-boot` | require | file:input-validation.md | `validateSync\(` | — | `const errors = validateSync(parsed, { forbidUnknownValues: false })` | `const errors = await validate(parsed)` | 누락·형식 오류가 첫 사용 시점이 아니라 **부팅 시점에** 실패해야 한다. 첫 사용 시점 실패는 배포 몇 시간 뒤 특정 요청에서 터진다 |
| `env-wired-to-config-module` | require | file:project-structure.md | `validate:[[:space:]]*validateEnv` | — | `ConfigModule.forRoot({ isGlobal: true, validate: validateEnv })` | `ConfigModule.forRoot({ isGlobal: true })` | 검증 함수를 **쓰는 곳**이 없으면 스키마는 죽은 코드다. `input-validation.md`가 정의하고 루트 모듈이 배선한다 — 두 파일에 걸친 계약이라 양쪽을 각각 겨눈다 |
| `ownership-in-query` | require | file:data-access.md | `where:[[:space:]]*\{[^}]*ownerId` | — | `where: { id, ownerId }` | `async get(ownerId: string, id: string)` | **이 축의 최대 위험.** 데이터 계층 정책 엔진이 없으므로 소유권은 쿼리 조건에 걸어야 한다. 조회 후 비교는 경합에 뚫리고, 누락은 곧 데이터 유출이다. **정규식이 `where` 객체 안을 요구하는 이유**: 맨 `ownerId:`는 TypeScript 파라미터 주석(`ownerId: string`) 한 줄로 충족돼 `where`에 실렸는지를 전혀 보지 못한다 |
| `mutation-affected-rows` | require | file:data-access.md | `\.affected[[:space:]]*(!==\|===)` | — | `if (res.affected === 0) throw new AppError('NOT_FOUND')` | `return res.affected ?? 0` | 소유권 필터가 걸린 변이는 남의 행에 대해 **0행 변경**으로 조용히 성공한다. `UpdateResult.affected`를 보지 않으면 200을 돌려준다 (실측: 타인 수정 시 `affected = 0`) |
| `no-blanket-mutation` | forbid | guide | `\.(updateAll\|deleteAll)\(` | `testing.md` | `await this.tasks.updateAll({ status: 'done' })` | `await repo.deleteAll()` | TypeORM 1.x가 신설한 `updateAll`·`deleteAll`은 **WHERE 없이** 테이블 전체를 친다. 소유권 필터를 걸 자리가 아예 없으므로 이 축에서는 도메인 코드에 등장할 이유가 없다. 예외는 격리된 스키마를 비우는 테스트 정리뿐이다 |
| `no-sql-string-interpolation` | forbid | guide | `\.query\([^)]*\$\{` | — | `await ds.query(` + 백틱 + `SELECT * FROM ${table}` | `await manager.query(sql${suffix})` | 식별자는 파라미터화할 수 없어 문자열로 끼워 넣게 되고, 그 습관이 값에도 옮는다. 값은 `query(sql, params)`나 태그드 템플릿 `repo.sql`로, 스키마·테이블 이름은 `QueryRunner`의 DDL API(`createSchema`·`createTable`)로 다룬다 — 이 팩은 원시 DDL을 한 줄도 쓰지 않는다 |
| `no-typeorm-globals` | forbid | guide | `createConnection\(\|getConnection\(\|getManager\(` | — | `const conn = await createConnection()` | `const em = getManager()` | TypeORM 1.x에 **그 이름들이 없다** (런타임 export 확인). 0.2 시절 전역 연결 관용구를 그대로 쓰면 `TypeError: not a function`으로 부팅이 죽는다. 연결은 `DataSource`이고 앱 코드는 DI로 받는다 |
| `no-synchronize` | forbid | guide | `synchronize:[[:space:]]*[^f[:space:]]` | — | `synchronize: true` | `synchronize: process.env.NODE_ENV !== 'production'` | 스키마를 엔티티에서 자동 반영하면 배포마다 예고 없는 DDL이 돈다 — 열 삭제가 데이터 삭제가 된다. 테스트도 예외가 아니다: 이 팩의 테스트는 **마이그레이션을 실제로 돌려** 그 마이그레이션까지 검증한다 |
| `timestamp-precision-pinned` | require | file:data-modeling.md | `precision:[[:space:]]*3` | — | `@CreateDateColumn({ type: 'timestamptz', precision: 3 })` | `@Column({ type: 'timestamptz' })` | `timestamptz`는 마이크로초, JS `Date`는 밀리초다. 커서를 ISO 문자열로 왕복시키면 그 사이 정밀도가 잘려 **행을 건너뛴다** (실측: 5행 중 1행 누락). 컬럼 정밀도를 3으로 못박아 DB와 언어의 해상도를 맞춘다 |
| `validation-pipe-strict` | require | file:input-validation.md | `forbidNonWhitelisted:[[:space:]]*true` | — | `forbidNonWhitelisted: true` | `whitelist: true` | `whitelist`만 켜면 미지 키가 **조용히 삭제**된다 — 오타 난 필드가 무시된 채 200이 나가 클라이언트가 원인을 못 찾는다. 거부해야 오타가 즉시 드러난다 |
| `no-console` | forbid | guide | `console\.(log\|error\|warn)\(` | — | `console.log(user)` | `console.error(e)` | 구조적 로거만 쓴다. `console`은 레벨·문맥·직렬화가 없어 운영에서 검색되지 않는다. Nest의 `Logger`(주입 또는 `new Logger('Context')`)를 쓰고 출력 형태는 `buildLogger`가 정한다 |
| `graceful-shutdown` | require | file:operations.md | `SIGTERM` | — | `process.once('SIGTERM', () => void stop('SIGTERM'))` | `process.once('SIGINT', handler)` | 컨테이너 종료 시 처리 중인 요청을 배수하지 않으면 배포마다 5xx가 난다. **Nest의 `enableShutdownHooks()`만으로는 부족하다** — 그것은 배수 창을 만들지 않는다 (실측) |
| `error-status-single-table` | require | file:error-handling.md | `ERROR_STATUS` | — | `ERROR_STATUS[err.code] ?? 500` | `const status = 404` | 상태 코드를 파일마다 정하면 같은 실패가 자리에 따라 다른 코드로 나간다 |
| `vocab-task` | forbid | guide | `\bnotes?\b\|노트` | — | `const notes = []` | `const note = {}` | 도메인 어휘는 `Task`/`tasks`/`작업`으로 고정한다 (L0 발행). 실측에서 프론트가 `/tasks`, 백엔드가 `/notes`를 써서 완전 예제가 서로 실행 불가였다 |
| `guard-on-controller` | require | seam | `AuthGuard` | — | `@UseGuards(AuthGuard)` | `@UseGuards(RolesGuard)` | **대상이 `seam`인 이유**: `AuthGuard`는 이음매가 정의하므로 `guide`로 걸면 이음매가 배포되는 한 절대 실패하지 않는다 — 정작 검증해야 할 컨트롤러 배선이 검사되지 않는다 |
| `envelope-from-filter` | require | seam | `AllExceptionsFilter` | — | `app.useGlobalFilters(new AllExceptionsFilter())` | `app.useGlobalFilters(new HttpExceptionFilter())` | 봉투 방출은 한 곳에서만 한다. 컨트롤러가 직접 `res.status(...).json(...)`을 하면 봉투가 갈라진다. 위와 같은 이유로 이음매를 겨눈다 |

`대상`이 `guide`면 조립된 가이드 전체(팩 + 이음매), `pack`이면 팩 파일만, `seam`이면 이음매
파일만, `file:<이름>`이면 그 파일만 본다. `require`는 최소 1회 등장이면 충족이다.
조립 전(`--pack`)에는 `seam` 대상 정책이 판정 불가이므로 **건너뛴 것을 명시 보고**한다.

## 사람이 지킬 것 (기계로 판정 불가)

- **`where`가 배열이면 OR다 — 모든 분기에 소유권을 건다.** 커서 페이지네이션처럼 분기가
  둘인 쿼리에서 한쪽의 `ownerId`를 빠뜨리면 그 분기가 남의 행을 통째로 통과시킨다.
  정규식은 「`where`에 `ownerId`가 한 번이라도 있는가」만 보므로 **분기별 누락을 보지
  못한다** (실측으로 누출을 재현했다)
- **부재와 권한 없음을 구분해 응답하지 않는다.** 남의 행을 조회하면 403이 아니라 404다 —
  구분하면 미인가 사용자가 리소스 존재를 열거할 수 있다
- **`select`는 런타임 값만 좁히고 타입은 좁히지 않는다.** `select: TASK_VIEW`로 가져온
  객체의 타입은 여전히 `Task`라서 `task.ownerId`가 컴파일되지만 값은 `undefined`다
  (실측). 반환 타입을 `TaskView`로 **명시**하는 것이 유일한 방어다
- **`@Type(() => Number)` 없이 쿼리 문자열이 숫자가 된다고 가정하지 않는다.** 전역
  `transform: true`만으로는 `@IsInt()`가 `'20'`을 거부한다
- **부분 업데이트 DTO에 기본값을 겹치지 않는다.** `PartialType`은 필드를 선택으로 만들
  뿐이고, 기본값을 그대로 두면 보내지 않은 필드가 덮어써진다
- **트랜잭션 안에서 외부 호출(HTTP·큐)을 하지 않는다.** 롤백되지 않고 락만 길어진다
- **마이그레이션은 배포와 분리된 단계로 돌린다.** 부팅에서 `migrationsRun`을 켜면
  인스턴스가 동시에 뜰 때 경합한다
- **provider를 `onModuleDestroy`에서 닫지 않는다.** 그 훅은 처리 중인 요청이 남아 있는
  시점에 발화한다 (실측: SIGTERM 후 1ms, 요청은 1.2초 뒤 완료)
