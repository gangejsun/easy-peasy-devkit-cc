<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 프로젝트 구조 — 모듈이 경계다

이 파일은 **모듈 그래프와 부팅 경로**를 소유한다. 컨트롤러의 경로·봉투는 이음매의 몫이고
(`seamSlots`의 `api-endpoints`), 쿼리는 `data-access.md`가, 검증 규칙은
`input-validation.md`가 소유한다.

## 1. 무엇을 어디에 두는가 — 결정 트리

| 새로 쓰는 것 | 어디에 | 왜 |
| --- | --- | --- |
| 도메인 로직·쿼리 | `src/<기능>/<기능>.service.ts` | HTTP를 모르는 계층. 테스트에 서버가 필요 없다 |
| 여러 기능이 쓰는 순수 함수 | `src/common/` | 모듈이 아니다 — provider로 만들지 않는다 |
| 여러 기능이 쓰는 **주입 대상** | 자기 모듈 + `exports` | provider는 모듈 밖으로 나가려면 export돼야 한다 |
| 운영 엔드포인트·수명 배선 | `src/ops/` | 도메인이 아니다. `operations.md`가 소유 |
| 요청 형태 정의 | `src/<기능>/dto/` | 클래스가 곧 스키마다 (`input-validation.md`) |
| 경로·상태 코드·봉투 | `src/<기능>/<기능>.controller.ts` | **이음매의 몫이다** |

**파일을 import했다고 쓸 수 있는 것이 아니다.** `TasksService`를 다른 모듈에서 주입받으려면
`TasksModule`이 `exports`해야 한다. 빠뜨리면 부팅이 `Nest can't resolve dependencies of
the X (?)` 로 죽는다 — 컴파일은 통과한다.

## 2. 루트 모듈 (`src/app.module.ts`)

루트는 **조립만** 한다. 컨트롤러도 provider도 직접 갖지 않는다 — 그래야 기능을 빼고
넣을 때 이 파일 한 곳만 본다.

<!-- file: src/app.module.ts -->
```ts
import { Module } from '@nestjs/common';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { TypeOrmModule } from '@nestjs/typeorm';
import { EnvVars, validateEnv } from './config/env';
import { buildDataSourceOptions } from './database/data-source';
import { OpsModule } from './ops/ops.module';
import { TasksModule } from './tasks/tasks.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, cache: true, validate: validateEnv }),
    TypeOrmModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService<EnvVars, true>) =>
        buildDataSourceOptions({
          DATABASE_URL: config.get('DATABASE_URL', { infer: true }),
          DB_SCHEMA: config.get('DB_SCHEMA', { infer: true }),
          DB_POOL_MAX: config.get('DB_POOL_MAX', { infer: true }),
          DB_SLOW_QUERY_MS: config.get('DB_SLOW_QUERY_MS', { infer: true }),
        }),
    }),
    OpsModule,
    TasksModule,
  ],
})
export class AppModule {}
```

`validate: validateEnv`가 **환경 검증을 부팅에 묶는 지점**이다. `ConfigModule`은 그
반환값을 설정으로 삼으므로, 이후 `config.get('PORT', { infer: true })`는 검증·변환을
마친 값을 준다. `isGlobal: true`가 없으면 모듈마다 `ConfigModule`을 import해야 한다.

`forRootAsync` + `inject: [ConfigService]`가 필요한 이유는 순서다 — DataSource 옵션을
만들려면 환경 값이 이미 검증돼 있어야 한다. `forRoot`에 값을 직접 쓰면 그 순서가 깨진다.

## 3. 기능 모듈 (`src/tasks/tasks.module.ts`)

<!-- file: src/tasks/tasks.module.ts -->
```ts
import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { Task } from './task.entity';
import { TasksController } from './tasks.controller';
import { TasksService } from './tasks.service';

@Module({
  imports: [TypeOrmModule.forFeature([Task])],
  controllers: [TasksController],
  providers: [TasksService],
  exports: [TasksService],
})
export class TasksModule {}
```

`TypeOrmModule.forFeature([Task])`가 `@InjectRepository(Task)`의 조달처다. 이것 없이
서비스에 `@InjectRepository(Task)`를 쓰면 `Nest can't resolve dependencies of the
TasksService (?, DataSource)` 로 부팅이 실패한다 — 물음표 자리가 빠진 의존이다.

`controllers` 배열은 **이음매가 채운다.** 팩만 조립한 상태에서는 이 모듈에 컨트롤러가
없는 것이 정상이다 (엔드포인트가 없을 뿐 서비스는 동작한다).

## 4. 부팅 (`src/main.ts`)

<!-- file: src/main.ts -->
```ts
import 'reflect-metadata';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { buildValidationPipe } from './common/validation';
import { EnvVars } from './config/env';
import { AppModule } from './app.module';
import { buildLogger } from './ops/logging';
import { installShutdown } from './ops/shutdown';

export async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const config: ConfigService<EnvVars, true> = app.get(ConfigService);

  app.useLogger(buildLogger({ LOG_LEVEL: config.get('LOG_LEVEL', { infer: true }) }));
  app.useGlobalPipes(buildValidationPipe());
  installShutdown(app, {
    DRAIN_DELAY_MS: config.get('DRAIN_DELAY_MS', { infer: true }),
    SHUTDOWN_TIMEOUT_MS: config.get('SHUTDOWN_TIMEOUT_MS', { infer: true }),
  });

  await app.listen(config.get('PORT', { infer: true }));
}

void bootstrap();
```

**순서에 이유가 있다.**

| 단계 | 왜 이 자리인가 |
| --- | --- |
| `bufferLogs: true` | 부팅 중 로그를 버퍼에 담아 둔다. 커스텀 로거가 붙은 뒤 한 번에 흘러나온다 |
| `app.get(ConfigService)` | 이미 검증된 값이다. **여기서 `process.env`를 읽지 않는다** |
| `useLogger` | `NestFactory.create`의 `logger` 옵션을 쓰면 앱보다 먼저 환경을 읽어야 한다 |
| `useGlobalPipes` | 컨트롤러가 요청을 받기 전에 걸려야 한다 |
| `installShutdown` | `listen` **전**이다. 리스너가 열린 뒤 SIGTERM이 오면 배선이 없다 |
| `listen` | 마지막. 이 줄 이후로 요청이 들어온다 |

이음매는 `useGlobalPipes` 다음에 `app.useGlobalFilters(new AllExceptionsFilter())`를
끼운다 — 봉투를 방출하는 곳이 그 하나여야 하기 때문이다.

## 5. 데코레이터가 도는 전제 (`tsconfig.json`)

Nest는 데코레이터 메타데이터로 주입 대상을 찾는다. 아래 두 옵션이 없으면 **컴파일은
되는데 부팅이 죽는다** — `Nest can't resolve dependencies` 의 흔한 원인이다.

<!-- file: tsconfig.json -->
```json
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2023",
    "moduleResolution": "node",
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "strict": true,
    "strictPropertyInitialization": false,
    "esModuleInterop": true,
    "outDir": "dist",
    "skipLibCheck": true
  },
  "include": ["src/**/*", "test/**/*"]
}
```

`strictPropertyInitialization`을 끄는 대신 **엔티티·DTO 필드에 `!`를 붙이는 쪽**을
권한다 (이 팩의 코드가 그렇게 돼 있다). 끄면 엔티티 밖의 평범한 클래스에서도 초기화
누락이 조용히 통과한다. 위 설정에 남긴 것은 기존 프로젝트를 옮겨 올 때의 완충이다.

## 6. 순환 의존과 배럴

**배럴 파일(`index.ts`)을 두지 않는다.** `import { X } from '../tasks'` 형태는 모듈
그래프와 파일 그래프를 어긋나게 만들고, Nest에서 순환 의존이 나면 원인이 배럴에
숨는다. 이 팩의 모든 import는 파일을 직접 가리킨다.

순환이 정말로 필요하면 `forwardRef(() => OtherModule)`가 있지만, 그전에 **의존을 한
방향으로 펴는 것**을 먼저 시도한다 — 대개 공통 부분을 `common/`의 순수 함수로 내리면
풀린다. `forwardRef`는 부팅 순서를 사람이 추론해야 하는 코드로 만든다.

## 오용 목록 ① — Express 관용구 → NestJS 형태 대조표

같은 Node 위에 있지만 **다른 시스템이다.** Express 습관을 그대로 옮기면 Nest의
가드·파이프·필터가 통째로 우회된다.

| 구 습관 (Express) | 현재 형태 (NestJS 11) |
| --- | --- |
| `app.use(express.json())` | 기본으로 켜져 있다. 한도만 `NestFactory.create(App, { bodyParser: true })` 계열로 조정 |
| `app.use(authMiddleware)` | `AuthGuard`(`CanActivate`) — 실행 문맥과 메타데이터를 본다 |
| `app.use(errorHandler)` (4인자) | `@Catch()` 예외 필터 + `useGlobalFilters` |
| `req`/`res`를 핸들러에서 직접 | `@Body()`·`@Query()`·`@Param()` 파라미터 데코레이터 |
| 라우터 파일에서 `router.get('/x')` | `@Controller('x')` + `@Get()` — **클래스가 곧 라우팅 선언** |
| `next(err)` | 그냥 `throw` — 파이프라인이 필터로 보낸다 |
| 미들웨어 순서로 실행 순서 제어 | 가드 → 인터셉터 → 파이프 → 핸들러 순서가 **고정**이다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `providers` vs `exports` | `providers`는 이 모듈 안에서 쓰는 것, `exports`는 이 모듈을 import한 쪽이 쓸 수 있는 것. 둘 다 필요하면 둘 다 적는다 |
| `imports` vs 파일 import | 모듈을 쓰려면 `imports` 배열. 타입만 쓰려면 파일 import로 충분하다 |
| `forRoot` vs `forFeature` | 연결·전역 설정은 `forRoot`(루트에서 1회), 엔티티별 Repository는 `forFeature`(기능 모듈마다) |
| `useGlobalPipes` vs `APP_PIPE` provider | 전자는 DI 밖에서 만든다. 파이프가 provider를 주입받아야 하면 `APP_PIPE`를 쓴다 — 이 팩의 파이프는 주입이 필요 없어 전자다 |
| `@Injectable()` 누락 | 주입받는 것이 없으면 동작하는 것처럼 보이다가, 의존을 하나 추가하는 순간 `Cannot read properties of undefined` 로 죽는다. provider에는 언제나 붙인다 |
