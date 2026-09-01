<!-- epcc-pack-ledger: backend/node-nest v3.16.0 -->

# node-nest 팩 — 심볼 원장 (L0 선언본)

**저작 전에 메인 세션이 선언한 계약이다.** `provides`의 정의 파일 배정은 **소유 배정**이고,
클러스터를 갈라 병렬로 써도 중복 정의가 생기지 않게 하는 유일한 장치다. L1은 자기
클러스터에 배정된 심볼만 정의하고, 벗어나면 게이트의 `--pack`이 팬인에서 잡는다.

`requires`는 이 팩이 소비하지만 정의하지 않는다 — **이음매가 제공해야** 한다.
라이브러리 API는 원장 대상이 아니다.

**「형태」 열에 소스 경로를 적는다.** 원장은 「어느 **리소스 파일**이 소유하는가」를
배정하지만 그것은 문서의 소유이지 **코드의 경로**가 아니다. Nest에서는 이 구분이 특히
샌다 — 심볼 하나가 곧 파일 하나(`@Module` · `@Injectable` · `@Entity`)이고, 형제 파일이
그 경로로 `import`한다. fastapi 실측에서 소비처와 정의처의 경로가 갈려 조립본이 깨졌고
**게이트는 잡지 못했다**(원장 검사는 리소스 파일만 본다).

## provides — 이 팩이 정의한다

`export` 선언문이 있는 심볼만 싣는다.

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `AppModule` | project-structure.md | `src/app.module.ts`. `@Module` 루트 — `ConfigModule.forRoot({ validate: validateEnv })` · `TypeOrmModule.forRootAsync` · 기능 모듈을 import한다. **컨트롤러를 직접 갖지 않는다** | 루트 모듈 (조립 지점) |
| `bootstrap` | project-structure.md | `src/main.ts`. `() => Promise<void>` — `reflect-metadata`를 **파일 첫 줄에** import한 뒤 `NestFactory.create` → 전역 파이프 → `installShutdown` → `listen` 순 | 부팅 함수 (프로세스 진입점) |
| `TasksModule` | project-structure.md | `src/tasks/tasks.module.ts`. `@Module` — `TypeOrmModule.forFeature([Task])`를 import하고 `TasksService`를 `exports`한다. 컨트롤러 배열은 **이음매가 채운다** | 기능 모듈 |
| `Task` | data-modeling.md | `src/tasks/task.entity.ts`. `@Entity({ name: 'tasks' })` 클래스 — `id` · `title` · `status: TaskStatus` · `ownerId` · `createdAt` · `updatedAt`. 시각 컬럼은 `{ type: 'timestamptz', precision: 3 }` | 엔티티 (테이블 매핑) |
| `TaskStatus` | data-modeling.md | `src/tasks/task.entity.ts`. `'open' \| 'done'` | 상태 유니온 |
| `TaskView` | data-modeling.md | `src/tasks/task.view.ts`. `Pick<Task, 'id' \| 'title' \| 'status' \| 'createdAt'>` — `ownerId`를 담지 않는다 | 조회 5개의 반환 타입. **이음매의 컨트롤러가 핸들러를 타이핑하려면 이름이 있어야 한다** |
| `TASK_VIEW` | data-modeling.md | `src/tasks/task.view.ts`. `FindOptionsSelect<Task>` — `TaskView`와 같은 열을 고르는 `select` 값. **둘을 한 파일에 두는 이유**: 타입과 `select`가 갈리면 컴파일은 통과하고 런타임 값만 빈다 | `select` 상수 |
| `TasksService` | data-access.md | `src/tasks/tasks.service.ts`. `@Injectable`. 메서드 5개 — `list(ownerId, q)` · `get(ownerId, id)` · `create(ownerId, dto)` · `update(ownerId, id, patch)` · `remove(ownerId, id)`. **소유자가 언제나 첫 인자다.** `update`·`remove`는 영향 행 수가 0이면 `AppError('NOT_FOUND')`를 던진다 | 도메인 서비스 (쿼리 소유) |
| `buildDataSourceOptions` | data-modeling.md | `src/database/data-source.ts`. `buildDataSourceOptions(env)` — 인자는 `Pick<EnvVars, 'DATABASE_URL' \| 'DB_SCHEMA' \| 'DB_POOL_MAX' \| 'DB_SLOW_QUERY_MS'>`, 반환 `DataSourceOptions`. `synchronize: false`·`migrationsRun: false` 고정 | DataSource 옵션 조립 (앱·CLI가 공유한다) |
| `dataSource` | data-modeling.md | `src/database/data-source.ts`. `DataSource` — **TypeORM CLI 전용 기본 내보내기 대상**이다. 앱은 이것을 쓰지 않고 `TypeOrmModule`이 만든 것을 주입받는다 | CLI용 DataSource |
| `encodeCursor` | data-access.md | `src/tasks/cursor.ts`. `(t: TaskView) => string` — `createdAt` + `id`를 base64url로 싣는다 | 커서 인코딩 |
| `decodeCursor` | data-access.md | `src/tasks/cursor.ts`. `(raw: string) => { createdAt: Date; id: string }` — 형식 오류는 `AppError('VALIDATION_FAILED')` | 커서 디코딩 |
| `EnvVars` | input-validation.md | `src/config/env.ts`. class-validator 데코레이터가 붙은 클래스. `NODE_ENV` · `PORT` · `DATABASE_URL` · `DB_SCHEMA` · `LOG_LEVEL` · `DB_POOL_MAX` · `DB_SLOW_QUERY_MS` · `DRAIN_DELAY_MS` · `SHUTDOWN_TIMEOUT_MS`. **선언하지 않은 키는 `ConfigService`가 알지 못한다** | 환경변수 스키마 (클래스가 곧 스키마) |
| `validateEnv` | input-validation.md | `src/config/env.ts`. `(raw: Record<string, unknown>) => EnvVars` — `ConfigModule.forRoot({ validate })`에 넘긴다. 실패는 **부팅 시점에** throw | 환경변수 검증 진입점 |
| `CreateTaskDto` | input-validation.md | `src/tasks/dto/create-task.dto.ts`. `title` 필수 · `status` 선택 | 생성 요청 본문 |
| `UpdateTaskDto` | input-validation.md | `src/tasks/dto/update-task.dto.ts`. `PartialType(CreateTaskDto)` — **기본값을 겹치지 않는다** | 수정 요청 본문 (부분 업데이트) |
| `ListTasksQueryDto` | input-validation.md | `src/tasks/dto/list-tasks.query.dto.ts`. `limit`(기본 20) · `cursor?` · `status?`. 숫자 필드에 `@Type(() => Number)`가 **필수**다 | 목록 쿼리 문자열 |
| `buildValidationPipe` | input-validation.md | `src/common/validation.ts`. `buildValidationPipe() => ValidationPipe` — `whitelist` · `forbidNonWhitelisted` · `transform` · `exceptionFactory`를 못박는다. `bootstrap`이 `useGlobalPipes`로 건다 | 전역 검증 파이프 조립 |
| `ERROR_STATUS` | error-handling.md | `src/common/error-status.ts`. `Record<string, number>` — 도메인 코드 → HTTP 상태. **유일한 매핑표** | 도메인 에러 코드 → HTTP 상태 표 |
| `toAppError` | error-handling.md | `src/common/error-status.ts`. `(e: unknown) => AppError` — 이음매의 예외 필터가 **반드시 먼저 호출한다** | 알 수 없는 throw → `AppError` 정규화 |
| `isUniqueViolation` | error-handling.md | `src/common/error-status.ts`. `(e: unknown) => boolean` — `QueryFailedError.driverError.code === '23505'` | 고유 제약 위반 판별 |
| `isForeignKeyViolation` | error-handling.md | `src/common/error-status.ts`. `(e: unknown) => boolean` — 같은 자리의 `'23503'` | 외래 키 위반 판별 |
| `fieldErrors` | error-handling.md | `src/common/error-status.ts`. `(errors: ValidationError[]) => Record<string, string[]>` — 중첩 DTO는 `a.b` 경로로 편다 | `ValidationError[]` → 필드 오류 맵 |
| `testSchema` | testing.md | `test/db.ts`. `string` — `test_w${JEST_WORKER_ID}`. 워커마다 다르다. `createTestApp`이 이 값을 `DB_SCHEMA`로 주입한다 | 워커별 스키마 이름 |
| `prepareSchema` | testing.md | `test/db.ts`. `prepareSchema(schema: string) => Promise<void>` — `QueryRunner.dropSchema`/`createSchema`. **원시 SQL을 쓰지 않는다.** 인자를 받는 이유: `globalSetup`은 워커 **밖**에서 돌아 `JEST_WORKER_ID`가 없으므로 자기 스키마만 만들면 2번 워커가 빈 스키마를 만난다 | 스키마 생성 (globalSetup에서 1회) |
| `createTestApp` | testing.md | `test/db.ts`. `createTestApp(configure?)` — `configure`는 `(app: INestApplication) => void`, 반환 `Promise<INestApplication>`. 전역 파이프를 실앱과 같게 걸고 **`init()` 전에** `configure`를 부른다. 이음매의 예외 필터가 그 자리다 — 없으면 `AppError`가 전부 500으로 나가 테스트가 상태 코드를 못 본다 (실측). 호출자가 `app.close()` 책임 | 테스트 앱 부팅 |
| `resetDb` | testing.md | `test/db.ts`. `(app: INestApplication) => Promise<void>` — `repo.deleteAll()`. 테스트 **간** 정리 | 테스트 간 정리 |
| `seedTask` | testing.md | `test/db.ts`. `(app: INestApplication, ownerId: string, patch?: Partial<Task>) => Promise<Task>` | 픽스처 생성 |
| `ReadinessService` | operations.md | `src/ops/readiness.service.ts`. `@Injectable` — `isReady(): boolean` · `beginDrain(): void`. **배수 플래그의 유일한 소유자** | 준비 상태 (배수 플래그) |
| `HealthController` | operations.md | `src/ops/health.controller.ts`. `@Controller()` — `GET /healthz`(liveness, 의존성을 보지 않는다) · `GET /readyz`(readiness, 배수 중이면 503) | 헬스 엔드포인트 |
| `OpsModule` | operations.md | `src/ops/ops.module.ts`. `@Module` — `ReadinessService`를 `exports`하고 `HealthController`를 싣는다. `AppModule`이 import한다 | 운영 모듈 |
| `installShutdown` | operations.md | `src/ops/shutdown.ts`. `installShutdown(app, env)` — `env`는 `Pick<EnvVars, 'DRAIN_DELAY_MS' \| 'SHUTDOWN_TIMEOUT_MS'>`, 반환 `void` — SIGTERM/SIGINT를 배선한다. 배수 → 유예 → `app.close()` → 시한 초과 시 `closeAllConnections()`. **`bootstrap`이 `listen` 전에 부른다** | 종료 배선 |
| `buildLogger` | operations.md | `src/ops/logging.ts`. `buildLogger(env)` — 인자는 `Pick<EnvVars, 'LOG_LEVEL'>`, 반환 `ConsoleLogger`(`json: true`). **`NestFactory.create`의 옵션이 아니라 `bufferLogs: true` + `app.useLogger(...)`로 건다** — 그래야 `main.ts`가 `process.env`를 읽지 않는다 | 구조적 로거 조립 |
| `SlowQueryLogger` | operations.md | `src/ops/logging.ts`. TypeORM `Logger` 구현 — `logQuerySlow`·`logQueryError`만 실질 동작한다. `buildDataSourceOptions`가 `maxQueryExecutionTime`과 짝으로 건다 | 느린 쿼리·쿼리 오류 관측 |

## requires — 이음매가 제공해야 한다

**종류를 구분한다.** `프로젝트`는 이음매가 `export`해야 하고, `라이브러리`는 이음매가 고른
패키지에서 오므로 import 문에 이름이 등장하는지로 판정한다.

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `AppError` | 프로젝트 | `src/common/app-error.ts`에 둔다. `new AppError(code, message?, details?)` · 필드 `code: string` · `details?: Record<string, string[]>`. **코드표에 반드시 포함할 것**: `VALIDATION_FAILED`(`buildValidationPipe`가 던진다) · `NOT_FOUND`(`TasksService`) · `CONFLICT` · `UNAUTHENTICATED` · `FORBIDDEN` · `INTERNAL`. 빠지면 `ERROR_STATUS`가 조용히 500으로 떨어진다 | 에러 코드표와 필드 오류 형태가 와이어 계약의 함수 |
| `AllExceptionsFilter` | 프로젝트 | `src/common/all-exceptions.filter.ts`에 둔다. `new AllExceptionsFilter()` — 인자 없다. `@Catch()` — `toAppError`로 정규화하고 `ERROR_STATUS`로 상태를 정한 뒤 **봉투를 방출한다**. `bootstrap`이 `useGlobalFilters`로 건다 | 응답 봉투 형태가 와이어 계약의 함수 |
| `AuthGuard` | 프로젝트 | `src/auth/auth.guard.ts`에 둔다. `CanActivate` — 검증된 주체를 `request.user`에 싣는다. 실패는 `AppError('UNAUTHENTICATED')` | **토큰 검증 방식이 조합의 함수다** — 프론트 축에 서버 런타임이 있으면 세션 쿠키, SPA면 베어러 토큰이 된다 |
| `CurrentUser` | 프로젝트 | `src/auth/current-user.decorator.ts`에 둔다. `createParamDecorator`로 만든 파라미터 데코레이터 — 컨트롤러가 `@CurrentUser() user: AuthUser`로 받는다 | 위와 같다. 주입 형태가 가드의 함수다 |
| `AuthUser` | 프로젝트 | 최소 `{ id: string }`. Express `Request['user']`에 선언 병합으로 붙인다 | 위와 같다 |
| `TasksController` | 프로젝트 | `src/tasks/tasks.controller.ts`에 둔다. `@Controller('api/tasks')` — 이 팩의 `TasksService`와 DTO를 소비해 엔드포인트와 봉투를 만든다. `TasksModule`의 `controllers`에 실린다 | 핸들러 형태와 봉투가 조합의 함수 (`seamSlots`의 `api-endpoints`) |
| `authFor` | 프로젝트 | `authFor(ownerId: string) => Record<string, string>` — supertest `.set()`에 넘길 인증 헤더 객체를 만든다. **테스트 전용**이고 앱 코드가 부르지 않는다 | 헤더냐 쿠키냐가 `auth-boundaries`의 함수다. 산문으로만 있으면 조립 후 게이트가 잡지 못한다 |

## 알려진 공백

없다. 축-지역 필수 슬롯 6개가 모두 채워지고, 비어 보이는 것(API 엔드포인트 · 인증 경계 ·
완전 예제)은 공백이 아니라 `pack.json`의 `seamSlots`가 선언한 **이음매의 몫**이다.
내용상의 미검증 항목은 `pack.json`의 `knownGaps`가 정본이다.

## 예제에 등장하는 앱 심볼 (프로젝트가 만든다)

`provides`도 `requires`도 아니다 — 팩이 정의하지 않고 이음매가 줄 것도 아니며, 소비자
프로젝트가 자기 도메인으로 작성한다. 예제에서 이름만 등장하므로 조립 후에도 정의가 없는
것이 정상이다.

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `UsersModule` | project-structure.md (모듈 조립 예시) | 다른 기능 모듈 |
| `CreateTasks1756000000000` | data-modeling.md §5 (마이그레이션 예시) | 마이그레이션 클래스. 이름에 타임스탬프가 붙으므로 프로젝트마다 다르다 |
