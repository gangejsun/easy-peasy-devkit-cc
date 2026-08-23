<!-- epcc-pack: backend/node-api v3.13.0 -->
# 운영 — 종료 · 헬스체크 · 커넥션 풀 · 구조적 로깅

이 파일은 **프로세스의 수명과 관측**을 소유한다: SIGTERM 처리, liveness/readiness 프로브,
커넥션 풀 사이징, pino 로거, 마이그레이션 배포 순서. 앱 조립과 미들웨어 순서는
`project-structure.md`, Prisma 싱글턴은 `data-access.md`, 테스트 DB 격리는 `testing.md`가
소유한다 (풀 사이징은 그 파일과 같은 자원을 다툰다).

이 파일이 읽는 환경 키는 `NODE_ENV` · `PORT` · `LOG_LEVEL` · `DRAIN_DELAY_MS` ·
`SHUTDOWN_TIMEOUT_MS`다.
`EnvSchema`에 없는 것은 거기에 추가한다 — 스키마 본문은 `src/env.ts`(`input-validation.md`가
소유)에 있고, 운영 코드는 환경 값을 직접 읽지 않고 `env`를 import한다.

## 1. 판단 — 네 가지 신호를 섞지 않는다

| 질문 | 답하는 곳 | 실패했을 때 오케스트레이터가 하는 일 |
| --- | --- | --- |
| 프로세스가 살아 있는가 | `healthz` (의존성을 보지 않는다) | **컨테이너를 죽인다** |
| 지금 트래픽을 받아도 되는가 | `readyz` (DB를 확인한다) | 로드밸런서에서 뺀다 (죽이지 않는다) |
| 종료해도 되는가 | `shutdown` (배수가 끝났는가) | — |
| 무슨 일이 있었는가 | `logger` (요청 상관관계) | — |

**둘을 같게 만들면 안 된다.** `healthz`가 DB를 확인하면, DB가 5초 잠깐 느릴 때
오케스트레이터가 멀쩡한 프로세스를 **재시작한다** — 그리고 재시작한 인스턴스가 다시 DB에
붙으면서 부하가 더 커진다. liveness는 "이 프로세스를 죽여야 재기하는가"에만 답한다.

반대로 `readyz`가 DB를 안 보면, 배포 직후 풀이 아직 안 찬 인스턴스로 트래픽이 들어간다.

## 2. 구조적 로깅 (`src/ops/logger.ts`)

<!-- file: src/ops/logger.ts -->
```ts
// src/ops/logger.ts
import { pino } from 'pino';
import { env } from '../env';

// `*`는 정확히 한 단계다. 깊이마다 손으로 적으면 반드시 빠뜨린다 — 만들어서 편다.
const SECRET_KEYS = ['password', 'token', 'accessToken', 'refreshToken',
  'apiKey', 'api_key', 'secret', 'clientSecret', 'DATABASE_URL'];
const atAnyDepth = (k: string) => [k, `*.${k}`, `*.*.${k}`, `*.*.*.${k}`];

export const logger = pino({
  level: env.LOG_LEVEL,
  redact: {
    paths: ['res.headers["set-cookie"]', ...SECRET_KEYS.flatMap(atAnyDepth)],
    censor: '[redacted]',
  },
  base: { service: 'tasks-api', env: env.NODE_ENV },
});
```

요청 상관관계는 `pino-http`가 붙인다. 앱 조립은 `project-structure.md`가 소유하므로 여기서는
배선만 보여 준다 — **가장 앞 미들웨어**여야 그 뒤에서 던져진 에러까지 같은 `reqId`로 묶인다.

```ts
// src/app.ts — makeApp() 안, 라우터보다 앞
import { randomUUID } from 'node:crypto';
import { pinoHttp } from 'pino-http';
import { logger } from './ops/logger';

// 자격 증명 헤더는 열거해서 막을 수 없다 — 허용 목록으로 고른다.
const SAFE_HEADERS = ['host', 'user-agent', 'content-type', 'content-length', 'x-request-id'];

app.use(pinoHttp({
  logger,
  genReqId: (req) => req.headers['x-request-id'] ?? randomUUID(),
  serializers: {
    req(req) {   // ✅ 기본 직렬화기는 헤더를 **전부** 싣는다 — 허용 목록으로 갈아 끼운다
      const headers: Record<string, unknown> = {};
      for (const h of SAFE_HEADERS) if (req.headers[h] !== undefined) headers[h] = req.headers[h];
      return { id: req.id, method: req.method, url: req.url, headers };
    },
  },
}));
```

이후 핸들러·서비스는 `req.log.info({ taskId }, '작업 갱신')`을 쓴다. `logger`를 직접 부르면
`reqId`가 빠져 운영에서 한 요청의 로그를 이어 붙일 수 없다.

## 3. `redact`가 가리는 것과 못 가리는 것 (실측)

`redact`는 **경로 기반**이고, 그래서 세 가지를 못 막는다. pino 9.14.0 · pino-http 10.5.0으로
실제 로깅해 출력을 확인했다.

| 모양 | 결과 |
| --- | --- |
| `{ token }` · `{ user: { password } }` · `{ items: [{ password }] }` | ✅ `[redacted]` |
| `{ a: { b: { c: { password } } } }` — `*.*.password`까지만 선언 | ❌ **그대로 출력됐다** |
| `{ refreshToken }` · `{ api_key }` · `{ secret }` — 목록에 없는 이름 | ❌ **그대로 출력됐다** |
| pino-http 기본 직렬화기의 `x-api-key` · `proxy-authorization` · `x-auth-token` | ❌ **평문으로 매 요청** |
| `{ err: new Error('connect failed: postgresql://u:PW@h/db') }` | ❌ **메시지·스택 전부 출력됐다** |

**① 이름을 열거하는 방식은 반드시 새어 나간다.** `accessToken`은 막고 `refreshToken`은
빠뜨리는 식이다 — 그리고 빠뜨린 쪽이 수명이 더 길다. 헤더는 열거가 더 나쁘다:
`authorization`·`cookie`만 막아도 `x-api-key`·`proxy-authorization`(RFC 7235 표준)·
`x-auth-token`이 **팩이 지시한 배선의 기본 경로에서 매 요청 새어 나갔다**. 그래서 2절은
헤더를 **허용 목록**으로 갈아 끼우고, 키 이름은 `SECRET_KEYS`로 모아 한곳에서 늘린다.

**② `*`는 정확히 한 단계다.** 깊이마다 따로 적어야 하고, **`**.password`는 예외를 던지지
않고 아무것도 가리지 않는다** — 조용히 무력한 설정이 된다. 2절의 `atAnyDepth`는 **깊이 4에서
끊긴다**(실행 확인: 깊이 4 ✅ · 깊이 5 ❌). 그보다 깊은 곳에 비밀을 담지 않는 것이 계약이다.

**③ 문자열 안에 박힌 비밀은 원리적으로 못 가린다.** 예외 객체를 통째로 싣지 말고 판별에
필요한 필드만 싣는다 — Prisma 연결 오류는 메시지에 커넥션 문자열을 담는다.

```ts
// src/ops/health.ts 안의 처리 — 예외를 통째로 싣지 않는다
logger.warn({ name: (err as Error).name }, 'readiness probe failed');   // ✅
```

## 4. 헬스체크 (`src/ops/health.ts`)

<!-- file: src/ops/health.ts -->
```ts
// src/ops/health.ts
import type { RequestHandler } from 'express';
import { prisma } from '../db/client';
import { logger } from './logger';

let draining = false;
export function beginDrain(): void { draining = true; }

export const healthz: RequestHandler = (_req, res) => {
  res.status(200).json({ status: 'ok' });   // 의존성을 보지 않는다
};

export const readyz: RequestHandler = async (_req, res) => {
  if (draining) { res.status(503).json({ status: 'draining' }); return; }
  try {
    await prisma.$queryRaw`SELECT 1`;       // 태그드 템플릿 — 파라미터화된다
    res.status(200).json({ status: 'ready' });
  } catch (err) {
    logger.warn({ name: (err as Error).name }, 'readiness probe failed');
    res.status(503).json({ status: 'degraded' });
  }
};
```

두 프로브는 **인증 앞**에 마운트한다 — 오케스트레이터는 토큰을 갖고 있지 않다. 대신 응답에
버전·호스트·스키마 같은 내부 정보를 싣지 않는다. 프로브 경로는 요청 로그에서 제외하거나
`trace` 레벨로 낮춘다 (초당 여러 번 들어와 로그 예산을 삼킨다).

`beginDrain`은 5절이 부르는 유일한 진입점이다. 이 플래그가 없으면 배수 중에도 `readyz`가
200을 돌려주고, 로드밸런서가 곧 죽을 인스턴스로 새 요청을 계속 보낸다.

## 5. graceful shutdown (`src/ops/shutdown.ts`)

**순서가 틀리면 배포마다 5xx가 난다.** ① 준비 해제 → ② 로드밸런서가 알아챌 시간 → ③ 새 연결
거부 + 처리 중 요청 배수 → ④ DB 연결 해제 → ⑤ 종료. ②를 빼면 `close()` 직후에도 아직
라우팅 중이던 요청이 연결 거부를 맞는다.

<!-- file: src/ops/shutdown.ts -->
```ts
// src/ops/shutdown.ts
import type { Server } from 'node:http';
import { prisma } from '../db/client';
import { env } from '../env';
import { beginDrain } from './health';
import { logger } from './logger';

let running: Promise<void> | null = null;

export function shutdown(server: Server): Promise<void> {
  running ??= drainAndExit(server);   // 신호가 두 번 와도 한 번만 돈다
  return running;
}

async function drainAndExit(server: Server): Promise<void> {
  beginDrain();                                              // ① readyz가 503을 낸다
  logger.info({ drainDelayMs: env.DRAIN_DELAY_MS }, 'shutdown: draining');
  const kill = setTimeout(() => {
    logger.error('shutdown: timed out, forcing exit');
    process.exit(1);                                         // 마지막 안전망
  }, env.SHUTDOWN_TIMEOUT_MS);
  kill.unref();
  await new Promise((r) => setTimeout(r, env.DRAIN_DELAY_MS)); // ② LB가 알아챌 시간
  const closed = new Promise<void>((resolve, reject) =>
    server.close((err) => (err ? reject(err) : resolve())),    // ③ 배수
  );
  server.closeIdleConnections();
  await closed;
  await prisma.$disconnect();                                  // ④
  clearTimeout(kill);
  logger.info('shutdown: complete');                           // ⑤ 이벤트 루프가 비면 종료된다
}
```

```ts
// src/index.ts — 부팅에서 신호를 건다
const server = makeApp().listen(env.PORT, () => logger.info({ port: env.PORT }, 'listening'));
process.on('SIGTERM', () => { void shutdown(server); });
process.on('SIGINT', () => { void shutdown(server); });
```

실행으로 확인한 것 (Node 24.7.0 · Express 5.2.1, `DRAIN_DELAY_MS=800`):

- SIGTERM 전 `readyz`는 200, **SIGTERM 300ms 뒤 같은 프로세스가 503**을 돌려줬다 —
  배수 중에도 서버는 여전히 연결을 받는다. 그것이 ②의 목적이다
- 배수 시작 전에 들어간 1.5초짜리 요청이 **200으로 완결**됐다. `close()`가 기다렸다
- 프로세스는 SIGTERM 후 **1.22초에 종료**했고 `$disconnect()`가 호출됐다.
  종료 후 새 연결은 거부됐다
- `server.closeIdleConnections()`는 Node 24.7.0에서 **유휴 keep-alive 연결에 대해 잉여다**
  — `close()`만으로 2ms에 닫혔다 <!-- verified: net 소켓으로 keep-alive 연결을 유지한 채 close()를 재어 확인 -->.
  더 중요한 것은 **헤더가 완결되지 않은 요청은 `closeIdleConnections()`로도 안 닫힌다**는 것이다
  (3초 대기 후에도 BLOCKED). 그래서 강제 종료 타이머가 진짜 안전망이다

`SHUTDOWN_TIMEOUT_MS`는 오케스트레이터의 유예 시간보다 **짧게** 잡는다 — 길면 우리 타이머가
아니라 SIGKILL이 먼저 오고, 배수가 아무 의미가 없어진다.

## 6. 커넥션 풀 사이징

Prisma는 인스턴스마다 자체 풀을 만든다. PostgreSQL의 `max_connections`는 **클러스터 전체**의
한도다. 둘을 곱셈으로 이어야 한다.

```
인스턴스 수 × connection_limit
  + 마이그레이션 잡  + 운영 도구(psql·대시보드)  + 테스트 워커
  ≤ max_connections − superuser_reserved_connections
```

`connection_limit`은 연결 문자열에 붙인다: `postgresql://…/app?connection_limit=10`.
지정하지 않으면 Prisma가 호스트 CPU 수에서 유도하므로, **큰 머신에 인스턴스를 여러 개 띄우면
합계가 조용히 한도를 넘는다** <!-- unverified -->.

관측 지점 세 개를 먼저 보고 숫자를 정한다 — 여기서 단정할 수 있는 값은 없다.

| 무엇 | 어떻게 본다 |
| --- | --- |
| 실제 사용 중인 연결 | `SELECT count(*), state FROM pg_stat_activity WHERE datname = current_database() GROUP BY state` |
| 서버 한도 | `SHOW max_connections` · `SHOW superuser_reserved_connections` |
| 풀 고갈 | 풀 타임아웃 에러(`P2024`)의 발생률 <!-- unverified --> |

`state = 'idle in transaction'`이 쌓이면 풀을 키우기 전에 **트랜잭션 안의 외부 호출**을 먼저
찾는다. 풀 확대는 그 증상을 잠깐 가리고 DB 쪽에서 다시 터진다.

`testing.md`가 워커별 URL에 `connection_limit=2`를 붙이는 이유도 이 식이다 — 워커 4개가
기본 풀을 각각 열면 로컬 개발 DB의 한도를 혼자 다 쓴다.

## 7. 마이그레이션은 배포와 분리된 단계다

부팅에서 `migrate deploy`를 하면 안 되는 이유는 `data-access.md`에 있다. 여기서는 **그래서
배포 순서를 어떻게 짜는가**만 다룬다.

```bash
# 배포 파이프라인 — 앱을 굴리기 전에 한 번, 한 프로세스만
npx prisma migrate deploy      # ① 스키마 전진 (되돌리기 없음 — 앞으로만 간다)
# ② 새 이미지 롤아웃 (readyz가 초록이 될 때까지 기다린다)
```

순서 때문에 **한 배포 동안 옛 코드와 새 스키마가 공존한다.** 그래서 파괴적 변경은 두 배포로
가른다: 먼저 열을 추가하고 양쪽 쓰기, 다음 배포에서 옛 열을 지운다. 한 번에 `NOT NULL` 열을
추가하거나 열 이름을 바꾸면 롤아웃 중인 옛 인스턴스가 전부 5xx를 낸다.

`migrate dev`는 개발 기기 전용이다 — 스키마를 초기화할 수 있으므로 CI·운영에서 부르지 않는다.

## 오용 목록 ① — 단일 프로세스 습관 → 오케스트레이션 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `console.*`로 로그 | `logger`/`req.log` — 레벨·상관관계·JSON 직렬화가 붙는다 |
| `/health` 하나로 모든 것 | `healthz`(liveness)와 `readyz`(readiness)를 가른다 |
| `process.exit(0)`으로 즉시 종료 | `shutdown()`으로 배수 후 이벤트 루프가 비어 자연 종료 |
| 부팅에서 `migrate deploy` | 배포 파이프라인의 분리된 단계 |
| `SIGKILL`만 상정 | `SIGTERM` 처리 + 그보다 짧은 강제 종료 타이머 |
| 풀 크기를 앱마다 기본값으로 | `connection_limit`을 인스턴스 수와 곱해 한도와 맞춘다 |
| 에러를 통째로 로깅 | 판별 필드만 — `redact`는 문자열 안을 못 본다 |
| 요청 헤더를 기본값대로 로깅 | `serializers.req`로 허용 목록만 남긴다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `healthz`에 DB 확인 vs `readyz`에 DB 확인 | `readyz`에만. `healthz`가 DB를 보면 DB 지연이 재시작 폭풍이 된다 |
| `*.token` vs `*.*.token` | `*`는 정확히 한 단계다. 깊이마다 따로 적고(`**`는 무력하다) 깊이 4에서 끊긴다 |
| 헤더 차단 목록 vs 허용 목록 | **허용 목록**. `x-api-key`·`proxy-authorization` 같은 이름은 끝없이 늘어난다 |
| `server.close()` vs `closeIdleConnections()` | 배수는 `close()`가 한다. 후자는 유휴 소켓용이고 미완결 요청은 못 닫는다 |
| 강제 종료 타이머 vs 배수 지연 | 지연은 LB가 알아챌 시간(②), 타이머는 배수가 안 끝날 때의 안전망(⑤) |
| `logger` vs `req.log` | 요청 맥락이 있으면 `req.log` — 없으면 `reqId`가 빠진다 |
| `migrate dev` vs `migrate deploy` | `dev`는 개발 기기 전용(초기화 가능), 배포는 `deploy` |
| `max_connections` vs `connection_limit` | 앞은 서버 전체 한도, 뒤는 **인스턴스 하나**의 풀 크기 |
