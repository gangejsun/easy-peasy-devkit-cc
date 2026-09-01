<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# 프로젝트 구조 — 한 방향 계층과 컨테이너 하나의 수명

이 파일이 소유하는 것은 **앱을 조립하는 자리**(`src/app.ts`) · **프로세스를 세우고 내리는
자리**(`src/main.ts`) · **무엇이 일어났는지 남기는 자리**(`src/obs/log.ts`) 셋이다.
`installErrorHandlers` · `apiRouter` · `AppError`는 **이음매가 소유한다**(`src/http/handlers.ts` ·
`src/http/routes.ts` · `src/errors.ts`) — 여기서는 부르기만 한다. 환경 값을 읽는 `settings`는
`input-validation.md`(`src/settings.ts`)가 소유하고, **이 파일은 환경을 직접 읽지 않는다.**

## 1. 새 코드를 어디에 두는가 — 계층 판단표

**계층은 한 방향이다**: `routes → services → firestore`. 아래 칸이 위 칸을 import하면 그 계층은
이미 무너진 것이고, 증상은 「데이터 계층 테스트가 HTTP를 세워야만 돈다」로 나타난다.

| 그 코드가 하는 일 | 두는 곳 | 그 계층이 알아도 되는 것 |
| --- | --- | --- |
| 요청·응답을 만진다 (`Context` · 상태 · 헤더) | `src/http/` — **이음매 소유** | Hono · `AppError`의 코드 |
| 「누가 무엇을 할 수 있는가」를 판정한다 | `src/services/tasks.ts` | 스키마 타입 · 리포지토리 · `AppError` |
| 문서를 읽고 쓴다 | `src/firestore/` | Firestore SDK · 스키마 타입 — **HTTP를 모른다** |
| 입력 형태를 판정한다 | `src/schemas/` (`input-validation.md`) | zod와 도메인 타입뿐 |
| 프로세스를 세우고 내린다 | `src/main.ts` · `src/app.ts` | 전부 |
| 무엇이 일어났는지 남긴다 | `src/obs/log.ts` | `settings`뿐 |

**판단이 갈릴 때의 규칙 하나**: 그 코드가 HTTP 상태 코드나 `Context`를 알아야 한다면 아래로
내리지 말고 **위로 올린다.** 리포지토리에 상태를 한 번 들이면 그 뒤로는 서비스가 그것을
그대로 통과시키게 되고, 되돌리려면 전 계층을 다시 만져야 한다.

## 2. `createApp` (`src/app.ts`) — 요청을 받지 않는다

`createApp()`은 **인자를 받지 않고 조립만 한다.** 요청을 받는 순간 테스트가 앱을 새로 세울 수
없게 되고, 앱 인스턴스가 프로세스 전역으로 굳는다.

<!-- file: src/app.ts -->
```ts
// src/app.ts
import { Hono } from 'hono';
import { installErrorHandlers } from './http/handlers.js';
import { apiRouter } from './http/routes.js';

/** 요청을 받지 않는다 — 조립만 한다. 그래서 테스트가 매번 새 앱을 세울 수 있다. */
export function createApp(): Hono {
  const app = new Hono();
  // 헬스체크는 인증도 Firestore도 거치지 않는다.
  app.get('/healthz', (c) => c.body(null, 204));
  app.route('/api', apiRouter);
  installErrorHandlers(app);
  return app;
}
```

<!-- verified: hono 4.13.4에서 onError를 route 앞·뒤로 각각 등록해 /api/boom을 태워 관측 — 둘 다 500으로 잡혔다 -->
`installErrorHandlers(app)`의 **호출 위치는 등록 순서와 무관하다.** `app.onError`·`app.notFound`는
미들웨어 체인이 아니라 앱의 속성이라, `app.route()` 앞에 걸든 뒤에 걸든 하위 라우터가 던진 것을
잡는다. 실측에서 두 순서 모두 `/api/boom`을 500으로 접었다.

<!-- verified: hono 4.13.4에서 서브 라우터에 자기 onError를 걸고 부모에도 걸어 관측 — 서브 쪽이 이겼다(599) -->
**그런데 하위 라우터가 자기 `onError`를 가지면 부모의 것이 돌지 않는다.** 실측에서 `apiRouter`에
`onError`를 걸자 `createApp`의 핸들러는 한 번도 실행되지 않았다 — `/api` 아래 전부, 즉 API 전체가
다른 봉투로 나간다. **`onError`를 거는 자리는 이 파일 하나다.**

**헬스체크가 의존성을 만지지 않는 이유**: Firestore를 한 번 찔러 보는 `/healthz`는 그럴듯하지만,
그 순간 데이터 계층 장애가 곧 **배포 실패**가 된다. 살아 있는 컨테이너까지 함께 교체된다.

## 3. `startServer` (`src/main.ts`) — `0.0.0.0`에 바인딩한다

포트는 **`settings.PORT`에서 온다.** 이 파일이 환경을 직접 읽으면 검증도 기본값도 부팅 시점
실패도 전부 우회되고, 그 사실은 배포된 다음에야 드러난다.

<!-- verified: 같은 서버를 hostname만 바꿔 두 번 띄우고 루프백과 인터페이스 주소로 각각 curl -->
`localhost`(=`127.0.0.1`)에 붙이면 **컨테이너 밖에서 도달하지 못한다.** 실측에서 listen 소켓이
`127.0.0.1:8801`로 잡혔고 루프백은 200, 같은 호스트의 인터페이스 주소(`192.168.0.142:8801`)는
연결 자체가 실패했다. `0.0.0.0`으로 붙이면 소켓이 `*:8801`이 되고 양쪽 모두 200이었다.
<!-- unverified: 실 Cloud Run 배포가 없어 「헬스체크가 죽어 배포가 롤백된다」까지는 관측하지 못했다 — 관측한 것은 인터페이스 수준의 도달 불가까지다 -->
Cloud Run의 헬스체크는 컨테이너 밖에서 온다.

## 4. `shutdown` (`src/main.ts`) — 시그널 핸들러 **안에서** 부른다

`shutdown(server)`는 **배수를 수행하는 함수다.** 이름이 아니라 호출 자리가 계약이다.

<!-- file: src/main.ts -->
```ts
// src/main.ts
import { serve, type ServerType } from '@hono/node-server';
import { createApp } from './app.js';
import { firestore } from './firestore/client.js';
import { log } from './obs/log.js';
import { settings } from './settings.js';

/** Cloud Run이 SIGTERM 뒤에 주는 시간은 10초다. 그 안에서 끝낸다. */
const DRAIN_DEADLINE_MS = 8_000;

export function startServer(): ServerType {
  return serve(
    // 0.0.0.0이다. localhost는 컨테이너 안의 루프백이라 밖에서 도달하지 못한다.
    { fetch: createApp().fetch, port: settings.PORT, hostname: '0.0.0.0' },
    (info) => log('info', 'listening', { port: info.port, address: info.address }),
  );
}

export async function shutdown(server: ServerType): Promise<void> {
  log('info', 'drain start');
  const drained = new Promise<void>((resolve) => {
    server.close(() => resolve());
    if ('closeIdleConnections' in server) server.closeIdleConnections();
  });
  let timer: ReturnType<typeof setTimeout> | undefined;
  const deadline = new Promise<void>((resolve) => { timer = setTimeout(resolve, DRAIN_DEADLINE_MS); });
  await Promise.race([drained, deadline]);
  clearTimeout(timer);
  await firestore.terminate();
  log('info', 'drain done');
}

const server = startServer();
// shutdown은 여기서만 부른다. 톱레벨에서 부르면 컨테이너가 부팅 직후 종료된다.
process.on('SIGTERM', () => { void shutdown(server); });
```

```ts
// ❌ 톱레벨 호출 — 서버가 뜨자마자 자기를 닫는다. 컨테이너가 부팅에 실패한다
const booted = startServer();
await shutdown(booted);
```

<!-- verified: 두 형태를 각각 프로세스로 띄워 stdout과 포트 도달을 계측 -->
실측으로 양쪽을 띄워 비교했다.

| 부르는 자리 | 관측 |
| --- | --- |
| 톱레벨 | `drain start`가 **2ms**에 찍히고 `listening`은 **한 번도 찍히지 않았다.** 3초 뒤 프로세스는 없었고 포트는 연결 거부였다 |
| `SIGTERM` 핸들러 안 | 1.5초짜리 요청이 진행 중일 때 시그널을 보냈더니 그 요청이 **200 · 완전한 본문**으로 끝났고, 배수는 그 1.1초 뒤에 완료됐다. 프로세스는 스스로 종료됐다 |

**마감을 거는 이유**: 배수를 무한정 기다리면 Cloud Run이 10초 뒤에 프로세스를 강제로 죽이고,
그 순간 `firestore.terminate()`가 실행되지 않는다. 8초는 그보다 먼저 포기하는 값이다.

<!-- verified: 유휴 keep-alive 소켓 1개(응답 헤더 `connection: keep-alive`, 열린 소켓 1)를 남기고 close() 콜백 지연을 계측 — 유무 모두 0ms. 단 측정 런타임은 Node 24.7.0이고 이 축의 대상은 Node 22다 -->
`closeIdleConnections()`는 측정한 런타임에서 **이중 방어였다** — 지우고 재보아도 `close()`
콜백은 즉시 왔다(Node가 스스로 유휴 keep-alive 연결을 닫아 준다). 그래도 남긴다: 그 거동은
Node 내부의 성질이고 우리 계약이 아니며, **대상 런타임(22)에서 직접 재보지는 못했다.**

## 5. 컨테이너 하나의 수명 — 콜드 스타트 · 동시성

**Cloud Run은 상주 프로세스다.** 이 팩의 결정 넷(Firestore 클라이언트 재사용 · JWKS 캐시 ·
SIGTERM 배수 · 모듈 최상위 `settings`)이 전부 그 전제 위에 있다.

| 시점 | 무엇이 도는가 | 그래서 |
| --- | --- | --- |
| 콜드 스타트 | 모듈 최상위가 **인스턴스당 한 번** 돈다 | `settings` 파싱 실패는 곧 **부팅 실패**다 — 절반 살아 있는 컨테이너가 생기지 않는다 |
| 요청 처리 | 같은 모듈 인스턴스를 여러 요청이 **동시에** 쓴다 <!-- unverified: 실 Cloud Run 없음 — 기본 동시성 값은 관측하지 못했다 --> | 모듈 최상위에 **요청별 가변 상태**를 두지 않는다. 클라이언트·캐시처럼 읽기 전용으로 공유되는 것만 둔다 |
| 응답 후 | 요청 밖에서는 CPU가 보장되지 않는다 <!-- unverified: 실 Cloud Run 없음 --> | 응답을 보낸 뒤 돌리는 「나중에 정리」 프로미스는 다음 요청까지 얼어 있을 수 있다 |
| SIGTERM | 배수 시간 **10초** (L0 동결) | 4절의 마감이 그보다 먼저 끝난다 |

요청 안에서 `new Firestore()`나 `createRemoteJWKSet()`을 만들면 이 표의 첫 줄이 무의미해진다 —
캐시가 요청마다 버려져 gRPC 채널이 쌓이고 매 요청이 Google에 왕복한다.

## 6. `log` (`src/obs/log.ts`) — 키는 `level`이 아니라 `severity`다

<!-- unverified: 실 GCP 프로젝트가 없어 Cloud Logging이 이 키를 실제로 심각도로 읽는지는 관측하지 못했다. 값 집합은 문서 기준이다 -->
Cloud Logging이 심각도로 읽는 키는 **`severity`**이고 값도 정해진 집합이다 — `warn`이 아니라
`WARNING`이다. `level: 'warn'`으로 내보내면 전 로그가 하나의 심각도로 뭉쳐 필터가 무력해진다.

<!-- file: src/obs/log.ts -->
```ts
// src/obs/log.ts
import { settings } from '../settings.js';

type Level = 'info' | 'warn' | 'error';

// Cloud Logging이 심각도로 읽는 키는 `level`이 아니라 `severity`이고, 값도 이 집합이다.
const SEVERITY: Record<Level, string> = { info: 'INFO', warn: 'WARNING', error: 'ERROR' };
const RANK: Record<Level, number> = { info: 10, warn: 20, error: 30 };

export function log(level: Level, message: string, fields?: Record<string, unknown>): void {
  if (RANK[level] < RANK[settings.LOG_LEVEL]) return;
  let line: string;
  try {
    line = JSON.stringify({ severity: SEVERITY[level], message, ...fields });
  } catch {
    // 순환 참조·BigInt는 stringify를 던진다. 로깅 실패가 요청을 죽이면 안 된다.
    line = JSON.stringify({ severity: SEVERITY[level], message, logError: 'unserializable fields' });
  }
  process.stdout.write(line + '\n');
}
```

<!-- verified: 위 파일을 그대로 실행해 stdout을 캡처 -->
실측 출력과 두 함정이다.

| 부른 것 | 나온 줄 |
| --- | --- |
| `log('warn', 'id token rejected', { reason: 'ERR_JWT_EXPIRED' })` | `{"severity":"WARNING","message":"id token rejected","reason":"ERR_JWT_EXPIRED"}` |
| `log('error', 'unhandled', { err: new Error('boom') })` | `{"severity":"ERROR","message":"unhandled","err":{}}` — **`Error`는 `{}`가 된다** |
| 순환 참조를 필드로 | `logError: "unserializable fields"` — 던지지 않는다 |

**`Error`를 필드에 그대로 싣지 않는다.** `JSON.stringify`는 `name`·`message`·`stack`을 모두
버린다 — 「원인을 남겼다」고 믿는 자리에 `{}`만 남는다. 필요한 것을 문자열로 꺼내 싣는다.
그리고 **토큰·문서 전문·이메일은 싣지 않는다.** 로그도 유출 경로다.

## 7. 리포지토리는 HTTP를 모른다

계층이 무너지는 자리는 거의 항상 **편의**다 — 리포지토리에서 바로 404를 주고 싶어진다.
아래는 `src/services/tasks.ts`가 리포지토리를 부르는 형태다.

```ts
// ❌ 리포지토리가 Context를 받는다 — 이 함수의 테스트는 이제 HTTP 앱을 세워야 한다
export async function findTask(c: Context, taskId: string) { /* … */ }
// ❌ 리포지토리가 상태를 안다 — 같은 판정이 라우터에도 생겨 둘이 갈린다
if (!doc.exists) return { status: 404 };
// ✅ 데이터 계층은 값만 준다. 없거나 남의 것이면 null이다
const task = await getTask(ownerId, taskId);
// ✅ 상태로 바꾸는 판정은 서비스가 한다 — 부재와 남의 것을 구분하지 않는다
if (task === null) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
```

`TaskService`처럼 클래스를 세울지 함수를 export할지는 자유다. **고정된 것은 방향 하나다** —
`src/firestore/` 아래의 어떤 파일도 `hono`·`src/http/`를 import하지 않는다. gRPC 코드를 판별하는
`isNotFound`류가 `src/http/errors.ts`가 아니라 `src/firestore/errors.ts`에 사는 이유도 같다.

## 오용 목록 ① — 상주 서버·서버리스 관용구 → 이 축의 형태

| 구 습관 | 현재 형태 (Cloud Run + Hono) |
| --- | --- |
| `app.listen(3000)`처럼 포트를 코드에 박는다 | `settings.PORT` — Cloud Run이 주입한다 |
| `hostname: 'localhost'` · `serve({ fetch })`처럼 호스트 생략 | `hostname: '0.0.0.0'`을 **명시한다** |
| `process.on('SIGTERM', () => process.exit(0))` | `shutdown(server)` — 진행 중 요청을 잃지 않는다 |
| 함수형 서버리스의 「핸들러마다 클라이언트 생성」 | 모듈 최상위 단일 인스턴스. 상주 프로세스에서만 캐시가 산다 |
| `console.log('user %s logged in', id)` | `log('info', 'login', { userId: id })` — 한 줄 JSON |
| `winston`·`pino` 트랜스포트 설정 | stdout 한 줄이면 끝이다. 수집은 플랫폼이 한다 |
| 라우터마다 `try/catch`로 응답을 만든다 | 던지고 `installErrorHandlers` 하나가 받는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `createApp()` vs 모듈 전역 `app` | 조립은 함수여야 테스트가 매번 새로 세운다 |
| `shutdown` **정의** vs **호출 자리** | 정의는 `src/main.ts`, 호출은 `SIGTERM` 핸들러 안 |
| `server.close()` vs `process.exit()` | 앞은 진행 중 요청을 기다린다. 뒤는 그것을 끊는다 |
| `app.onError` — 부모 vs 하위 라우터 | 하위 것이 이긴다. 이 축은 부모 하나만 건다 |
| `/healthz`에 의존성 점검을 넣기 vs 넣지 않기 | 넣으면 데이터 계층 장애가 배포 실패가 된다 |
| `severity` vs `level` | Cloud Logging이 읽는 키는 앞이고, 값은 `WARNING`이다 |
| 모듈 최상위 상태 — 공유 캐시 vs 요청별 값 | 앞은 맞고 뒤는 동시 요청끼리 섞인다 |
