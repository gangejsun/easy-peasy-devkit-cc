<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 입력 검증 — DTO 클래스가 곧 스키마다

이 파일은 **요청과 환경변수의 형태**를 소유한다. 검증 실패가 어떤 상태 코드로 나가는지는
`error-handling.md`가, 컨트롤러가 DTO를 어떻게 받는지는 이음매가 소유한다.

## 1. 무엇을 어디서 검증하는가

| 입력 | 검증 주체 | 실패 시점 |
| --- | --- | --- |
| 요청 본문·쿼리·파라미터 | DTO 클래스 + 전역 `ValidationPipe` | 요청 처리 전 (400) |
| 환경변수 | `EnvVars` + `validateEnv` | **부팅 시점** (프로세스 종료) |
| DB 제약 | 마이그레이션의 CHECK·UNIQUE | 쿼리 실행 시 (409 등) |

**세 층을 모두 건다.** DTO는 사용자에게 친절한 400을 주고, DB 제약은 DTO를 우회하는
경로(마이그레이션·수동 SQL·다른 서비스)를 막는다. 하나로 줄이려는 유혹이 있지만
막는 것이 서로 다르다.

## 2. 전역 파이프 (`src/common/validation.ts`)

<!-- file: src/common/validation.ts -->
```ts
import { BadRequestException, ValidationPipe } from '@nestjs/common';
import { fieldErrors } from './error-status';

export function buildValidationPipe(): ValidationPipe {
  return new ValidationPipe({
    whitelist: true,
    forbidNonWhitelisted: true,
    transform: true,
    transformOptions: { enableImplicitConversion: false },
    exceptionFactory: (errors) =>
      new BadRequestException({
        code: 'VALIDATION_FAILED',
        details: fieldErrors(errors),
      }),
  });
}
```

<!-- verified: @nestjs/common@11.2.1 + class-validator@0.15.1 실행 — 미지 키 admin 을 보내자 400 과 {"code":"VALIDATION_FAILED","details":{"admin":["property admin should not exist"]}} 가 나왔다 -->

| 옵션 | 켜는 이유 |
| --- | --- |
| `whitelist` | DTO에 선언되지 않은 키를 **제거**한다. 대량 할당(mass assignment)을 막는 1차 방어 |
| `forbidNonWhitelisted` | 제거 대신 **거부**한다. 없으면 오타 난 필드가 조용히 사라진 채 200이 나가 원인을 못 찾는다 |
| `transform` | 평범한 객체를 DTO **인스턴스**로 만든다. 이것이 없으면 `@Type`도 기본값도 적용되지 않는다 |
| `transformOptions.enableImplicitConversion: false` | 타입을 추측으로 바꾸지 않는다. 변환이 필요한 필드에만 `@Type`을 **명시**한다 (§4) |
| `exceptionFactory` | 기본 봉투는 `{ message: string[] }`로 **필드 정보가 평평해진다**. 필드별 맵으로 바꾸는 유일한 지점 |

기본 봉투와 `exceptionFactory` 봉투의 차이는 실제 응답으로 이렇다:

| 형태 | 응답 본문 |
| --- | --- |
| 기본 | `{"message":["title must be a string"],"error":"Bad Request","statusCode":400}` |
| 이 팩 | `{"code":"VALIDATION_FAILED","details":{"title":["title must be a string"]}}` |

**컨트롤러마다 `new ValidationPipe(...)`를 만들지 않는다.** 옵션이 갈리는 순간 어떤
엔드포인트는 미지 키를 거부하고 어떤 엔드포인트는 통과시킨다 — 그 차이는 코드를 전부
읽기 전에는 보이지 않는다.

## 3. 요청 DTO (`src/tasks/dto/`)

<!-- file: src/tasks/dto/create-task.dto.ts -->
```ts
import { IsIn, IsOptional, IsString, MaxLength, MinLength } from 'class-validator';

export class CreateTaskDto {
  @IsString() @MinLength(1) @MaxLength(200)
  title!: string;

  @IsOptional() @IsIn(['open', 'done'])
  status?: 'open' | 'done';
}
```

부분 업데이트는 `PartialType`으로 파생한다 — 필드를 두 벌 쓰면 갈린다.

<!-- file: src/tasks/dto/update-task.dto.ts -->
```ts
import { PartialType } from '@nestjs/mapped-types';
import { CreateTaskDto } from './create-task.dto';

export class UpdateTaskDto extends PartialType(CreateTaskDto) {}
```

<!-- verified: @nestjs/mapped-types@2.1.1 + @nestjs/common@11.2.1 실행 — 빈 본문 {} 이 통과했고, {status:'done'} 을 보내자 DTO의 키가 ['status'] 하나였다 -->
`PartialType`은 필드를 **선택으로 바꿀 뿐** 기본값을 만들지 않는다. 그래서 보내지 않은
필드는 DTO에 아예 없고, `update(where, patch)`가 그 열을 건드리지 않는다.

**부분 업데이트 DTO에 기본값을 겹치지 않는다.** `CreateTaskDto`의 `status`에
`= 'open'` 같은 초기값을 두면 `PartialType`이 그것까지 물려받아, 상태만 바꾸려는 요청이
제목을 덮어쓰거나 그 반대가 된다. 문법은 완벽하고 실행만이 드러낸다.

## 4. 쿼리 문자열은 언제나 문자열이다

<!-- file: src/tasks/dto/list-tasks.query.dto.ts -->
```ts
import { Type } from 'class-transformer';
import { IsIn, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';

export class ListTasksQueryDto {
  @IsOptional() @Type(() => Number) @IsInt() @Min(1) @Max(100)
  limit: number = 20;

  @IsOptional() @IsString()
  cursor?: string;

  @IsOptional() @IsIn(['open', 'done'])
  status?: 'open' | 'done';
}
```

<!-- verified: class-transformer@0.5.1 실행 — ?limit=5 가 number 5 로, 쿼리 없음이 기본값 20 으로 들어왔고 ?limit=999 는 400 이었다 -->
`@Type(() => Number)`가 없으면 `@IsInt()`가 `'5'`(문자열)를 거부해 **정상 요청이 400이
된다.** 전역에서 `enableImplicitConversion`을 켜면 이 데코레이터 없이도 변환되지만,
그러면 의도하지 않은 필드까지 추측 변환되어 `'true'`가 불린이 되는 식의 놀람이 생긴다.
변환이 필요한 자리에만 명시하는 쪽이 좁다.

기본값(`limit: number = 20`)은 `transform: true`가 켜져 있어야 적용된다 — DTO
**인스턴스**가 만들어져야 클래스 필드 초기값이 산다.

## 5. 환경변수 (`src/config/env.ts`)

<!-- file: src/config/env.ts -->
```ts
import { plainToInstance } from 'class-transformer';
import { IsIn, IsInt, IsString, Matches, Max, Min, validateSync } from 'class-validator';

export class EnvVars {
  @IsIn(['development', 'test', 'production'])
  NODE_ENV: 'development' | 'test' | 'production' = 'development';

  @IsInt() @Min(1) @Max(65535)
  PORT: number = 3000;

  @IsString()
  DATABASE_URL!: string;

  @Matches(/^[a-z_][a-z0-9_]*$/)
  DB_SCHEMA: string = 'public';

  @IsIn(['error', 'warn', 'log', 'debug', 'verbose'])
  LOG_LEVEL: 'error' | 'warn' | 'log' | 'debug' | 'verbose' = 'log';

  @IsInt() @Min(1) @Max(100)
  DB_POOL_MAX: number = 10;

  @IsInt() @Min(0)
  DB_SLOW_QUERY_MS: number = 300;

  @IsInt() @Min(0)
  DRAIN_DELAY_MS: number = 5000;

  @IsInt() @Min(1000)
  SHUTDOWN_TIMEOUT_MS: number = 10000;
}

export function validateEnv(raw: Record<string, unknown>): EnvVars {
  const parsed = plainToInstance(EnvVars, raw, {
    enableImplicitConversion: true,
    exposeDefaultValues: true,
  });
  const errors = validateSync(parsed, { whitelist: false, forbidUnknownValues: false });
  if (errors.length > 0) {
    const lines = errors.map((e) => `  ${e.property}: ${Object.values(e.constraints ?? {}).join(' · ')}`);
    throw new Error(`환경변수 검증 실패 — 부팅을 중단한다\n${lines.join('\n')}`);
  }
  return parsed;
}
```

<!-- verified: class-validator@0.15.1 + class-transformer@0.5.1 실행 — DATABASE_URL 미설정·PORT='abc' 상태에서 부팅이 두 필드의 제약 메시지를 담아 즉시 실패했다 -->
**`AppModule`이 이 함수를 `ConfigModule.forRoot({ validate: validateEnv })`에 넘긴다**
(`project-structure.md` §2). 그 배선이 없으면 이 파일은 죽은 코드다.

| 선택 | 이유 |
| --- | --- |
| `enableImplicitConversion: true` | 환경변수는 **전부 문자열**이다. 여기서만은 추측 변환이 맞다 |
| `exposeDefaultValues: true` | 없으면 클래스 필드의 기본값이 무시돼 `PORT`가 `undefined`가 된다 |
| `forbidUnknownValues: false` | 프로세스 환경에는 우리가 모르는 키가 잔뜩 있다. 그것을 오류로 만들면 어디서도 부팅하지 못한다 |
| `throw` (반환이 아니라) | 부팅을 **중단**시키는 것이 목적이다. 잘못된 설정으로 뜬 프로세스는 몇 시간 뒤 특정 요청에서 터진다 |

**`process.env`를 읽는 곳은 이 파일이 아니다.** `ConfigModule`이 프로세스 환경을 이
함수에 넘기고, 애플리케이션 코드는 `ConfigService`로만 값을 얻는다. 직접 읽는 곳은
DI 밖에서 도는 CLI DataSource와 테스트 하네스 둘뿐이고, 그것이 `policies.md`의
`env-single-entry` 예외 목록 전부다.

`DB_SCHEMA`에 `@Matches(/^[a-z_][a-z0-9_]*$/)`가 붙은 이유는 그 값이 **식별자로 쓰이기
때문**이다 — 식별자는 파라미터화할 수 없으므로 형태를 미리 좁혀 둔다.

## 오용 목록 ① — Zod/Joi 관용구 → class-validator 형태 대조표

| 구 습관 (스키마 객체) | 현재 형태 (DTO 클래스) |
| --- | --- |
| `z.object({...})`를 따로 선언 | 클래스 자체가 스키마다. 타입과 검증이 한 선언에 있다 |
| `schema.parse(body)`를 핸들러에서 호출 | 전역 `ValidationPipe`가 컨트롤러 진입 전에 한다 |
| `.strict()`로 미지 키 거부 | `whitelist` + `forbidNonWhitelisted` (파이프 옵션) |
| `z.coerce.number()` | `@Type(() => Number)` — 필드마다 명시 |
| `.partial()` | `PartialType(Dto)` (`@nestjs/mapped-types`) |
| `z.infer<typeof Schema>` | 클래스 이름이 곧 타입이다 |
| `.optional()` | `@IsOptional()` — **없으면 `undefined`도 검증 대상**이 되어 실패한다 |
| `safeParse` 결과를 분기 | `exceptionFactory`가 그 자리다. 핸들러는 성공 경로만 본다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `@IsOptional()` vs `?:` | 앞은 검증 건너뛰기, 뒤는 타입 표기. **둘 다** 필요하다 |
| `whitelist`만 vs `forbidNonWhitelisted`까지 | 전자는 조용히 지운다. 클라이언트 오타를 드러내려면 후자 |
| `@Type(() => Number)` vs `enableImplicitConversion` | 전자는 필드 지정, 후자는 전역 추측. 요청 DTO에는 전자, 환경변수에는 후자 |
| `@IsIn([...])` vs TypeScript 유니온 | 유니온은 런타임에 사라진다. 값 집합은 반드시 `@IsIn` |
| `@ValidateNested()` 누락 | 중첩 객체가 **검사되지 않은 채** 통과한다. `@Type`과 짝으로 쓴다 |
| DTO에 메서드·기본 로직 추가 | DTO는 형태 선언이다. 변환 로직은 서비스로 — 그래야 대역을 끼울 수 있다 |
