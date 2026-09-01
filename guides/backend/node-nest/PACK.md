<!-- epcc-pack: backend/node-nest v3.16.0 verified 2026-08-24 @nestjs/common@11 @nestjs/core@11 @nestjs/platform-express@11 @nestjs/config@4 @nestjs/typeorm@11 @nestjs/mapped-types@2 typeorm@1 pg@8 class-validator@0.15 class-transformer@0.5 reflect-metadata@0.2 rxjs@7 typescript@5 @nestjs/testing@11 jest@30 ts-jest@29 supertest@7 @types/jest@30 @types/supertest@6 @types/node@22 -->

# node-nest 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가 있는
조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

각 조각은 `<!-- pack-slot: 이름 -->` ~ `<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀
있어 프론트엔드 축이 무엇이든 그대로 성립한다. 조합의 함수인 것은 여기 없다 —
파일 끝의 표가 이음매의 몫을 명시한다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── main.ts                       # 부팅만 — 전역 파이프·로거·종료 배선 후 listen
├── app.module.ts                 # 루트 모듈: ConfigModule · TypeOrmModule · 기능 모듈
├── config/
│   └── env.ts                    # EnvVars(클래스가 곧 스키마) + validateEnv
├── common/
│   ├── validation.ts             # buildValidationPipe — 전역 파이프 조립
│   ├── error-status.ts           # ERROR_STATUS 표 · 드라이버 코드 판별 · 필드 오류
│   ├── app-error.ts              # AppError — **이음매가 소유한다**
│   └── all-exceptions.filter.ts  # 봉투 방출 — **이음매가 소유한다**
├── database/
│   ├── data-source.ts            # buildDataSourceOptions + CLI용 dataSource
│   └── migrations/               # migration:run으로 적용 (배포와 분리된 단계)
├── tasks/
│   ├── task.entity.ts            # @Entity — 테이블 매핑
│   ├── task.view.ts              # TaskView 타입 + TASK_VIEW select 상수 (같은 파일)
│   ├── cursor.ts                 # 커서 인코딩·디코딩
│   ├── dto/                      # class-validator DTO — 클래스가 곧 스키마다
│   ├── tasks.service.ts          # 쿼리 소유. HTTP를 모른다
│   ├── tasks.module.ts           # forFeature([Task]) + 서비스 export
│   └── tasks.controller.ts       # **이음매가 소유한다** (경로·봉투)
├── auth/                         # AuthGuard · CurrentUser — **이음매가 소유한다**
└── ops/
    ├── readiness.service.ts      # 배수 플래그의 유일한 소유자
    ├── health.controller.ts      # /healthz(liveness) · /readyz(readiness)
    ├── ops.module.ts             # 위 둘을 묶어 AppModule에 싣는다
    ├── shutdown.ts               # 배수 → 유예 → close → 강제 종료
    └── logging.ts                # buildLogger(JSON) + SlowQueryLogger

test/
└── db.ts                         # 워커별 스키마 격리 · 앱 부팅 · 시드 · 정리

jest.config.ts                    # ts-jest. e2e와 단위를 한 설정에서 돌린다
tsconfig.json                     # experimentalDecorators·emitDecoratorMetadata 필수
```

**의존은 한 방향으로만 흐른다**: `controller → service → repository`. 서비스가
`Request`·`Response`를 받으면 계층이 무너지고 쿼리 테스트에 HTTP 서버가 필요해진다.
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

**모듈이 경계다.** Nest에서 "무엇을 어디서 쓸 수 있는가"는 import 문이 아니라 **모듈
그래프**가 정한다. `TasksModule`이 `exports: [TasksService]`를 하지 않으면 다른 모듈은
그 서비스를 주입받지 못한다 — 파일을 import해도 `Nest can't resolve dependencies` 로
부팅이 실패한다. 그래서 이 팩은 **파일 배치가 아니라 모듈 경계로** 접근을 통제한다.

**Repository는 DI로만 얻는다.** `@InjectRepository(Task)`가 유일한 조달 경로다.
`dataSource.getRepository(Task)`를 서비스 필드에 직접 만들면 테스트에서 대역을 끼울
자리가 사라진다 (`getRepositoryToken(Task)`로 override할 대상이 없어진다).
예외는 **트랜잭션 안**이다 — 그때는 `manager.getRepository(Task)`가 그 트랜잭션에
묶인 인스턴스를 준다.

**`reflect-metadata`는 진입점 첫 줄에 온다.** 없으면 데코레이터 메타데이터를 읽는 첫
호출이 `Reflect.getMetadata is not a function`으로 죽는다 (실행 확인). `main.ts`와 CLI가
읽는 `database/data-source.ts` 둘 다 자기 첫 줄에 갖는다 — 진입점이 둘이기 때문이다.

**전역 배선의 순서**: `bufferLogs: true`로 생성 → `useLogger` → `useGlobalPipes` →
(이음매의 `useGlobalFilters`) → `installShutdown` → `listen`. 로거를 나중에 거는 것이
의도다 — `NestFactory.create`의 `logger` 옵션을 쓰려면 앱보다 먼저 환경 값을 읽어야
하고, 그러면 `main.ts`가 `process.env`를 직접 읽게 된다.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
## Core Principles (7 Key Rules)

이 축에는 **행 수준 정책 엔진이 없다.** 애플리케이션이 신뢰된 연결로 PostgreSQL에 붙으므로
규칙 1~3이 유일한 경계다 — "데이터 계층이 백업하니 이중 방어"는 여기서 성립하지 않는다.
`user`는 이음매의 `AuthGuard`가 실은 `AuthUser`다.

### 1. 소유권은 `where`에 있다 — 조회 뒤 비교가 아니다

```ts
// src/tasks/tasks.service.ts
// ❌ 조회한 뒤 소유자를 비교한다 — 비교를 빠뜨려도 잡아 줄 계층이 없다
const found = await this.tasks.findOne({ where: { id } });
if (found && found.ownerId !== user.id) throw new AppError('FORBIDDEN');
// ✅ 소유권은 조회 조건이다
const task = await this.tasks.findOne({ where: { id, ownerId }, select: TASK_VIEW });
```

### 2. `where`가 배열이면 OR다 — 분기마다 소유권을 반복한다

<!-- verified: typeorm@1.1.0 + PostgreSQL 18.4 실행 — 한 분기의 ownerId를 뺐더니 다른 소유자의 행이 결과에 섞였다 (총 8행) -->
분기 하나에서 `ownerId`를 빠뜨리면 그 분기가 남의 행을 통째로 통과시킨다. 정책 정규식은
「`where`에 `ownerId`가 있는가」만 보므로 **이 결함을 기계가 잡지 못한다.**

### 3. 변이는 영향 행 수를 확인한다

<!-- verified: typeorm@1.1.0 + PostgreSQL 18.4 실행 — 타인 소유 행에 update를 걸면 affected = 0 이 돌아왔다 -->
소유권 필터가 걸린 `update`·`delete`는 남의 행에 대해 **0행 변경으로 조용히 성공**한다.
`res.affected === 0`을 보지 않으면 200이 나간다.

### 4. `select`는 값만 좁힌다 — 타입은 그대로다

<!-- verified: typeorm@1.1.0 실행 — select 후 객체에 ownerId 키는 있고 값은 undefined였다 -->
반환 타입을 `TaskView`로 **명시**하지 않으면 `task.ownerId`가 컴파일되고 런타임에
`undefined`가 된다. 그 값이 봉투에 실리면 소리 없이 잘못된 응답이 나간다.

### 5. 스키마 변경은 마이그레이션으로만 — `synchronize`는 켜지 않는다

테스트도 예외가 아니다. 이 팩의 테스트 하네스는 격리된 스키마에 **마이그레이션을 실제로
돌려** 그 마이그레이션까지 검증한다.

### 6. 검증은 DTO 클래스가 하고, 전역 파이프가 강제한다

`whitelist` + `forbidNonWhitelisted` + `transform`을 한 곳(`buildValidationPipe`)에서
못박는다. 컨트롤러마다 `new ValidationPipe(...)`를 새로 만들면 옵션이 갈린다.

### 7. 종료는 배수부터 — 그리고 keep-alive를 끊어 준다

<!-- verified: @nestjs/core@11.2.1 실행 — keep-alive 연결이 남은 채 app.close()가 5.8초 시한까지 반환하지 않았고, closeAllConnections() 호출 시 즉시 완료했다 -->
`app.close()`는 **열린 keep-alive 연결이 하나라도 있으면 영원히 반환하지 않는다.**
시한을 걸고 `server.closeAllConnections()`로 끊는 것이 종료를 끝내는 유일한 장치다.
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

```ts
// 프레임워크
import { Injectable, Module, Logger, ValidationPipe } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { InjectRepository, InjectDataSource, TypeOrmModule } from '@nestjs/typeorm';
import { DataSource, Repository, LessThan, In, QueryFailedError } from 'typeorm';
import { IsIn, IsInt, IsOptional, IsString, validateSync } from 'class-validator';
import { plainToInstance, Type } from 'class-transformer';

// 팩이 소유하는 모듈 — 경로는 src/<계층>/ 기준 (배정은 ledger.md가 정본이다)
import { EnvVars, validateEnv } from './config/env';
import { buildValidationPipe } from './common/validation';
import { ERROR_STATUS, toAppError, isUniqueViolation, fieldErrors } from './common/error-status';
import { buildDataSourceOptions } from './database/data-source';
import { Task, TaskStatus } from './tasks/task.entity';
import { TASK_VIEW, TaskView } from './tasks/task.view';
import { encodeCursor, decodeCursor } from './tasks/cursor';
import { TasksService } from './tasks/tasks.service';
import { ReadinessService } from './ops/readiness.service';
import { installShutdown } from './ops/shutdown';
import { buildLogger, SlowQueryLogger } from './ops/logging';

// 이음매 소유 — 경로는 축이 고정한다
import { AppError } from './common/app-error';
import { AllExceptionsFilter } from './common/all-exceptions.filter';
import { AuthGuard, AuthUser } from './auth/auth.guard';
import { CurrentUser } from './auth/current-user.decorator';
```

`AppError`는 **어느 계층이든 던진다** — HTTP를 모르는 순수 에러 클래스이고 상태 매핑은
`ERROR_STATUS`가 따로 한다. `AuthGuard`·`CurrentUser`·`TasksController`는 이음매가
정의하므로 팩 코드에는 등장하지 않는다.
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
## HTTP Status Codes & Anti-Patterns

**상태 코드의 정본은 `error-handling.md`가 소유한 `ERROR_STATUS`다.** 아래는 그 표의 요약이고,
어긋나면 `ERROR_STATUS`가 이긴다.

| 코드 | 도메인 코드 | 언제 나가는가 |
| --- | --- | --- |
| 200 | — | 조회·수정 성공 (본문 있음) |
| 201 | — | 생성 성공 — Nest가 `@Post`에 기본으로 준다 |
| 204 | — | 삭제 성공 — `@HttpCode(204)`를 명시해야 한다 |
| 400 | `VALIDATION_FAILED` | DTO 검증 실패. 필드 오류는 `details`에 |
| 401 | `UNAUTHENTICATED` | 자격 증명이 없거나 만료 — 이음매의 `AuthGuard`가 던진다 |
| 403 | `FORBIDDEN` | **존재를 이미 아는** 리소스에 대한 행위 거부(역할 부족)에만 쓴다 |
| 404 | `NOT_FOUND` | 부재 **와** 남의 소유. 둘을 가르면 id를 훑어 존재를 알아낼 수 있다 |
| 409 | `CONFLICT` | 고유 제약 충돌 — 드라이버 코드 `23505` |
| 503 | — | 배수 중이거나 DB 미도달 — `/readyz`만 낸다 |
| 500 | `INTERNAL` | 그 외 전부. 원인은 응답이 아니라 로그에만 남긴다 |

### 안티패턴 — NestJS 11 + TypeORM 1에서 실제로 관찰되는 것

| ❌ 형태 | 왜 틀렸나 / 대신 |
| --- | --- |
| `createConnection()` · `getManager()` | TypeORM 1.x에 **그 export가 없다**. `DataSource`를 DI로 받는다 <!-- verified: typeorm@1.1.0 런타임 export 목록에 Connection·createConnection·getRepository·getManager 없음 --> |
| `repo.update({}, patch)` · `updateAll` | WHERE 없는 변이는 남의 행까지 친다. 1.x가 그것을 `updateAll`로 분리한 것은 **경고이지 권장이 아니다** |
| `@Column() createdAt: Date` (정밀도 없음) | `timestamptz`(µs)와 JS `Date`(ms)의 해상도 차가 커서 페이지네이션에서 행을 건너뛴다 <!-- verified: PostgreSQL 18.4 실행 — precision 미지정 시 5행 중 1행 누락, precision: 3에서 5행 완주 --> |
| 서비스가 `@Res() res`를 받는다 | 컨트롤러 밖으로 HTTP가 새고 Nest의 인터셉터·직렬화가 통째로 우회된다 |
| `new ValidationPipe()`를 컨트롤러마다 | 옵션이 갈린다. 전역 하나(`buildValidationPipe`)만 둔다 |
| `enableShutdownHooks()`만으로 무중단 배포 | 그 훅은 **새 연결을 즉시 거부**하고 배수 창을 만들지 않는다 <!-- verified: @nestjs/core@11.2.1 실행 — SIGTERM 직후 새 연결이 ECONNREFUSED, 처리 중 요청만 완료됐다 --> |
| `onModuleDestroy`에서 자원 닫기 | 처리 중 요청이 남아 있는 시점에 발화한다 <!-- verified: @nestjs/core@11.2.1 실행 — SIGTERM 후 1ms에 발화, 요청은 1.2초 뒤 완료 --> |
| `console.log`로 요청 로그 | 레벨·문맥·직렬화가 없다. `Logger` + `buildLogger`의 JSON 출력 |
<!-- /pack-slot -->

## 이음매가 채울 것

| 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| `api-endpoints` | 컨트롤러의 경로·데코레이터와 응답 봉투. 봉투는 와이어 계약이 정한다 |
| `auth-boundaries` | 토큰 검증 방식이 프론트 축에 서버 런타임이 있는지에 달렸다 |
| `complete-example` | 마이그레이션 → 엔티티 → DTO → 서비스 → 컨트롤러 → e2e 관통 |
