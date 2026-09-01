<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 운영 — 종료·헬스체크·풀·관측

이 파일은 **프로세스와 연결의 수명**을 소유한다. 마이그레이션을 쓰는 법은
`data-modeling.md` §5가, 배포에서 **언제** 돌리는지는 여기 §7이 소유한다.

## 1. 종료가 왜 어려운가 — 세 가지 실측

| 관측 | 결과 |
| --- | --- |
| SIGTERM 직후 새 연결 | **즉시 거부**된다 (ECONNREFUSED). 배수 창이 없다 |
| `onModuleDestroy`·`beforeApplicationShutdown` 발화 | SIGTERM 후 **1ms**. 처리 중 요청이 아직 살아 있다 |
| keep-alive 연결이 남은 채 `app.close()` | **반환하지 않는다**. 5.8초 시한까지 매달렸다 |

<!-- verified: @nestjs/core@11.2.1 실행 — 위 세 줄을 각각 재현했다. 처리 중이던 요청은 1.2초 뒤 200으로 완료됐고 그 시점에도 DataSource.isInitialized 는 true 였다 -->

세 번째가 특히 위험하다. `closeAllConnections()`를 부르자 `app.close()`가 즉시 반환했고
`onApplicationShutdown`이 그때서야 발화했다 — 즉 **끊어 주지 않으면 종료가 끝나지 않는다.**

두 번째의 함의: **provider를 `onModuleDestroy`에서 닫지 않는다.** 그 시점에 DB 연결을
끊으면 처리 중이던 요청이 "Driver not Connected"로 실패한다.

## 2. 종료 배선 (`src/ops/shutdown.ts`)

<!-- file: src/ops/shutdown.ts -->
```ts
import { INestApplication, Logger } from '@nestjs/common';
import type { Server } from 'node:http';
import { EnvVars } from '../config/env';
import { ReadinessService } from './readiness.service';

type ShutdownEnv = Pick<EnvVars, 'DRAIN_DELAY_MS' | 'SHUTDOWN_TIMEOUT_MS'>;

export function installShutdown(app: INestApplication, env: ShutdownEnv): void {
  const log = new Logger('Shutdown');
  const readiness = app.get(ReadinessService);
  const server = app.getHttpServer() as Server;
  let started = false;

  const stop = async (signal: string): Promise<void> => {
    if (started) return;
    started = true;
    log.log({ event: 'shutdown.begin', signal });

    readiness.beginDrain();
    await new Promise((r) => setTimeout(r, env.DRAIN_DELAY_MS));

    const forced = setTimeout(() => {
      log.warn({ event: 'shutdown.force_close', afterMs: env.SHUTDOWN_TIMEOUT_MS });
      server.closeAllConnections();
    }, env.SHUTDOWN_TIMEOUT_MS);
    forced.unref();

    await app.close();
    clearTimeout(forced);
    log.log({ event: 'shutdown.done', signal });
  };

  for (const signal of ['SIGTERM', 'SIGINT'] as const) {
    process.once(signal, () => void stop(signal));
  }
}
```

순서에 각각 이유가 있다.

| 단계 | 왜 |
| --- | --- |
| `beginDrain()` | `/readyz`가 503을 내기 시작한다. 로드밸런서가 새 요청을 보내지 않는다 |
| `DRAIN_DELAY_MS` 대기 | 로드밸런서가 상태를 **알아차릴 시간**이다. 0이면 배수가 없는 것과 같다 |
| `SHUTDOWN_TIMEOUT_MS` 타이머 | 매달린 연결을 끊는 안전장치. `unref()`해서 이 타이머 자체가 종료를 막지 않게 한다 |
| `app.close()` | 리스너를 닫고 처리 중 요청을 기다린 뒤 Nest 훅을 돌린다 |
| `closeAllConnections()` | keep-alive를 끊는다. **이것이 없으면 위 줄이 반환하지 않는다** |

`process.once`를 쓰는 것과 `started` 플래그는 같은 목적이다 — 배포 도구가 SIGTERM을
두 번 보내는 일이 흔하고, 두 번째가 배수를 처음부터 다시 시작하면 안 된다.

**`app.enableShutdownHooks()`를 함께 켜지 않는다.** 켜면 Nest도 같은 시그널을 잡아
배수 전에 `app.close()`를 시작한다 — 이 함수가 만든 유예가 사라진다.

## 3. 헬스체크

<!-- file: src/ops/readiness.service.ts -->
```ts
import { Injectable } from '@nestjs/common';

@Injectable()
export class ReadinessService {
  private draining = false;

  isReady(): boolean {
    return !this.draining;
  }

  beginDrain(): void {
    this.draining = true;
  }
}
```

<!-- file: src/ops/health.controller.ts -->
```ts
import { Controller, Get, HttpCode, ServiceUnavailableException } from '@nestjs/common';
import { InjectDataSource } from '@nestjs/typeorm';
import { DataSource } from 'typeorm';
import { ReadinessService } from './readiness.service';

@Controller()
export class HealthController {
  constructor(
    @InjectDataSource() private readonly dataSource: DataSource,
    private readonly readiness: ReadinessService,
  ) {}

  @Get('healthz')
  @HttpCode(200)
  live(): { status: string } {
    return { status: 'ok' };
  }

  @Get('readyz')
  async ready(): Promise<{ status: string }> {
    if (!this.readiness.isReady()) throw new ServiceUnavailableException({ status: 'draining' });
    try {
      await this.dataSource.query('SELECT 1');
    } catch {
      throw new ServiceUnavailableException({ status: 'database_unreachable' });
    }
    return { status: 'ok' };
  }
}
```

<!-- file: src/ops/ops.module.ts -->
```ts
import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';
import { ReadinessService } from './readiness.service';

@Module({
  controllers: [HealthController],
  providers: [ReadinessService],
  exports: [ReadinessService],
})
export class OpsModule {}
```

**둘을 가르는 것이 요점이다.**

| 엔드포인트 | 무엇을 답하는가 | 실패하면 |
| --- | --- | --- |
| `/healthz` | 프로세스가 살아 있는가 | 오케스트레이터가 **재시작**한다 |
| `/readyz` | 지금 요청을 받아도 되는가 | 로드밸런서가 **빼낸다** (재시작은 아니다) |

`/healthz`가 DB를 확인하면 안 되는 이유가 여기 있다 — DB가 잠깐 흔들릴 때 모든
인스턴스가 동시에 재시작되고, 재시작은 DB 부하를 더 올린다. liveness는 자기 자신만 본다.

`/readyz`는 배수 플래그를 **먼저** 본다. DB 확인보다 앞이어야 종료 중인 인스턴스가
DB 왕복 없이 즉시 503을 준다.

## 4. 커넥션 풀

<!-- verified: PostgreSQL 18.4 + pg@8.23.0 실행 — extra.max: 3 으로 동시 6요청을 걸자 풀의 totalCount 가 3에서 멈췄다 -->
`extra`는 드라이버(pg)에 그대로 넘어가는 옵션이다. `max`가 인스턴스당 상한이므로
**인스턴스 수 × `DB_POOL_MAX` ≤ PostgreSQL의 `max_connections`**여야 한다. 넘으면
스케일아웃이 곧 장애가 된다 — 새 인스턴스가 뜨는 순간 기존 인스턴스가 연결을 못 얻는다.

기본값 10은 작게 잡은 값이다. 늘리기 전에 **느린 쿼리부터 본다** — 풀 고갈은 대개
동시성 부족이 아니라 오래 잡고 있는 쿼리의 증상이다.

## 5. 로깅과 느린 쿼리 (`src/ops/logging.ts`)

<!-- file: src/ops/logging.ts -->
```ts
import { ConsoleLogger, Logger } from '@nestjs/common';
import { Logger as TypeOrmLogger } from 'typeorm';
import { EnvVars } from '../config/env';

const LEVELS = ['error', 'warn', 'log', 'debug', 'verbose'] as const;

type LogEnv = Pick<EnvVars, 'LOG_LEVEL'>;

export function buildLogger(env: LogEnv): ConsoleLogger {
  return new ConsoleLogger({
    json: true,
    colors: false,
    logLevels: LEVELS.slice(0, LEVELS.indexOf(env.LOG_LEVEL) + 1),
  });
}

export class SlowQueryLogger implements TypeOrmLogger {
  private readonly out = new Logger('Database');

  logQuerySlow(time: number, query: string): void {
    this.out.warn({ event: 'db.slow_query', durationMs: time, query: query.slice(0, 300) });
  }

  logQueryError(error: string | Error, query: string): void {
    this.out.error({ event: 'db.query_error', reason: String(error).slice(0, 300), query: query.slice(0, 300) });
  }

  logMigration(message: string): void {
    this.out.log({ event: 'db.migration', message });
  }

  logQuery(): void {}
  logSchemaBuild(): void {}
  log(): void {}
}
```

<!-- verified: @nestjs/common@11.2.1 실행 — ConsoleLogger({json:true}) 가 {"level":"log","pid":...,"timestamp":...,"message":...,"context":...} 를 냈고, 객체를 넘기면 message 자리에 그대로 실렸다 -->
Nest 11의 `ConsoleLogger`가 JSON을 내므로 **로깅 라이브러리를 더 들이지 않는다.**
문자열 대신 객체를 넘기면 그 객체가 `message`에 실려 검색 가능한 필드가 된다.

<!-- verified: typeorm@1.1.0 + PostgreSQL 18.4 실행 — maxQueryExecutionTime: 100 에서 pg_sleep(0.15) 쿼리 6건이 모두 logQuerySlow(153ms) 로 왔다 -->
`SlowQueryLogger`는 TypeORM의 `Logger` 인터페이스 구현이고, `buildDataSourceOptions`가
`maxQueryExecutionTime`과 짝으로 건다 (`data-modeling.md` §4). 임계값을 넘긴 쿼리만
오므로 평상시 출력이 늘지 않는다.

**필드 이름이 `out`인 것은 우연이 아니다.** TypeORM의 `Logger` 인터페이스에 `log`
메서드가 있어서 `private readonly log = new Logger(...)`로 두면 `Property 'log' is
private in type 'SlowQueryLogger' but not in type 'Logger'`로 타입 검사가 막는다.

**알려진 공백**: 요청 상관관계 ID가 없다. 한 요청의 로그를 묶는 필드가 필요하면
`AsyncLocalStorage`로 실어야 하는데, 그 형태는 이 팩에서 검증하지 않았다 —
`pack.json`의 `knownGaps`가 정본이다.

## 6. 환경변수와 기본값

| 키 | 기본 | 운영에서 보는 값 |
| --- | --- | --- |
| `DB_POOL_MAX` | 10 | 인스턴스 수 × 이 값 ≤ `max_connections` |
| `DB_SLOW_QUERY_MS` | 300 | 임계값을 내리면 로그가 는다. 튜닝 중에만 낮춘다 |
| `DRAIN_DELAY_MS` | 5000 | 로드밸런서의 헬스체크 주기 × 2 이상 |
| `SHUTDOWN_TIMEOUT_MS` | 10000 | 오케스트레이터의 강제 종료(SIGKILL) 유예보다 **짧게** |

마지막 줄이 특히 중요하다. Kubernetes의 `terminationGracePeriodSeconds`(기본 30초)보다
길게 잡으면 우리 타이머가 도달하기 전에 프로세스가 죽어 배수가 무의미해진다.

## 7. 마이그레이션 배포 순서

`migrationsRun`은 꺼 둔다 (`data-modeling.md` §4). 부팅에서 돌리면 인스턴스가 동시에
뜰 때 같은 마이그레이션을 두 프로세스가 잡는다.

```
① 마이그레이션 실행 (배포 파이프라인의 독립 단계, 인스턴스 1개)
② 새 버전 배포 (롤링)
③ 옛 인스턴스 종료 — 배수 → close
```

그래서 **마이그레이션은 언제나 앞뒤 호환이어야 한다.** ①과 ②가 원자적이지 않으므로
옛 코드가 새 스키마 위에서 잠시 돈다 (`data-modeling.md` §6의 순서표가 그 처방이다).

## 오용 목록 ① — Express 운영 관용구 → NestJS 형태 대조표

| 구 습관 (Express) | 현재 형태 (NestJS 11) |
| --- | --- |
| `server.close(cb)`만으로 무중단 | keep-alive가 남으면 반환하지 않는다. `closeAllConnections()` 필요 |
| `app.enableShutdownHooks()`면 충분 | 배수 창을 만들지 않는다 — 새 연결이 즉시 거부된다 |
| `morgan`으로 요청 로그 | Nest `Logger` + `buildLogger`의 JSON 출력. 인터셉터로 요청 로그를 붙인다 |
| `pino`/`winston` 도입 | Nest 11의 `ConsoleLogger({ json: true })`로 충분하다 |
| `/health` 하나만 둔다 | liveness와 readiness는 **다른 질문**이다 (§3) |
| `process.on('SIGTERM', () => process.exit(0))` | 처리 중 요청을 버린다. 배수 → close → 강제 순서 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `onModuleDestroy` vs `onApplicationShutdown` | 앞은 요청이 아직 도는 시점(1ms), 뒤는 리스너가 닫힌 뒤. 자원 해제는 뒤 |
| `closeIdleConnections()` vs `closeAllConnections()` | 앞은 유휴만 끊는다 — 처리 중이던 연결은 남는다. 시한 초과 시에는 뒤 |
| liveness에 DB 확인 | 넣으면 DB 흔들림이 전 인스턴스 재시작이 된다 (§3) |
| `DRAIN_DELAY_MS = 0` | 배수가 없는 것과 같다. 로드밸런서는 즉시 알아차리지 못한다 |
| `extra.max`를 크게 | 인스턴스 수를 곱해서 본다. 풀 고갈의 원인은 대개 느린 쿼리다 |
| 로그에 원시 오류 그대로 | 쿼리·제약 이름은 300자로 자른다. 값이 로그로 새는 경로가 된다 |
