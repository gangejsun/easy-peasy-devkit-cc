<!-- epcc-pack: backend/node-api v3.13.0 -->
# 테스트 — Vitest 2 · supertest 7 · 실 DB 격리

이 파일은 **테스트 하네스와 테스트 DB의 수명**을 소유한다: Vitest 설정, supertest로 앱을
태우는 형태, 워커별 DB 격리, 픽스처와 정리. 커넥션 풀 사이징·헬스체크·종료 절차는
`operations.md`가 소유한다 (같은 자원을 다루므로 두 파일을 함께 읽는다). 쿼리 함수의 형태는
`data-access.md`, 에러 코드표는 `error-handling.md`에 있다.

## 1. 판단 — 이 축에서 실 DB를 언제 쓰는가

**이 축에는 데이터 계층 정책 엔진이 없다.** 소유권 필터는 애플리케이션 쿼리에만 존재하므로,
그것을 검증하는 테스트가 실 DB를 거치지 않으면 **아무것도 증명하지 못한다** — Prisma를 모킹한
테스트는 "내가 쓴 mock이 내가 쓴 코드와 일치한다"만 확인한다.

| 확인하려는 것 | 층 | 도구 | 실 DB |
| --- | --- | --- | --- |
| Zod 스키마가 잘못된 본문을 거른다 | 단위 | Vitest | 아니오 |
| 서비스가 분기를 올바로 고른다 | 단위 | Vitest | 아니오 |
| 라우터가 400/404/409를 정확히 낸다 | 통합 | Vitest + supertest | 예 |
| **남의 행을 조회하면 404가 나온다** | 통합 | supertest + 실 DB | **예** |
| **0행 변이가 성공으로 나가지 않는다** | 통합 | supertest + 실 DB | **예** |
| `P2002`가 409로 매핑된다 | 통합 | 실 DB (유니크 제약이 있어야 발화한다) | **예** |
| Prisma·Express·Zod 자체 동작 | — | 테스트하지 않는다 | — |

기본값은 **실 DB 통합 테스트**다. 이 스택에서 모킹이 정당한 자리는 외부 HTTP 호출과 시각뿐이다.

## 2. Vitest 설정 (`vitest.config.ts`)

<!-- file: vitest.config.ts -->
```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';   // ✅ 'vite'가 아니라 'vitest/config'

export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
    setupFiles: ['src/test/db.ts'],   // 테스트 파일마다 다시 평가된다
    pool: 'forks',                    // 워커 = 별도 프로세스 = 별도 커넥션 풀
    poolOptions: {
      forks: { minForks: 1, maxForks: 4, isolate: false },   // ✅ 4절의 가드가 성립하는 조건
    },
    hookTimeout: 30_000,              // 마이그레이션이 이 안에서 돈다
    testTimeout: 15_000,
  },
});
```

`defineConfig`를 `'vite'`에서 가져오면 `test` 키가 타입에 없어 **TS2769로 실패한다**
(실행 확인: `Object literal may only specify known properties, and 'test' does not exist in
type 'UserConfigExport'`). 설정 파일이 `tsc`에 포함되지 않는 저장소에서는 이 실수가 조용히
남았다가 CI에서 터진다 — `tsconfig.json`의 `include`에 `vitest.config.ts`를 넣는다.

**워커 수는 `poolOptions.forks.maxForks`로 정한다** — forks 풀이 보는 값이 그것이다.
`test.maxWorkers`는 죽지는 않지만(실행 확인: `maxWorkers`와 `maxForks`를 어긋나게 줘도 통과)
forks 풀에서 무시되므로, 스키마 수와 맞춰야 하는 이 설계에서는 조용히 틀린 수를 준다.

**`isolate: false`가 이 설계의 전제다.** 기본값 `true`에서는 테스트 파일마다 새 프로세스가
떠서 4절의 워커 단위 가드가 무력해진다 — 근거는 4절에 실측으로 실었다.

## 3. supertest로 라우터를 실제로 태운다 (`*.test.ts`)

`makeApp()`이 만든 앱 객체를 `request()`에 그대로 넘긴다 — `listen()`은 하지 않는다.
supertest가 요청마다 임시 포트를 열고 닫으므로 포트 충돌도 정리 코드도 없다.

```ts
// src/http/routers/tasks.test.ts
import { afterEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { makeApp } from '../../app';
import { resetDb, seedTask, testDb } from '../../test/db';

const app = makeApp();
afterEach(resetDb);

describe('POST /api/tasks', () => {
  it('제목이 없으면 400과 필드 오류를 돌려준다', async () => {
    // 인증 헤더를 빼면 400이 아니라 401이 나온다 — requireAuth가 먼저 걸린다
    const res = await request(app).post('/api/tasks').set(authFor('owner-1')).send({});
    expect(res.status).toBe(400);
    expect(res.body.error.code).toBe('VALIDATION_FAILED');
    expect(res.body.error.details.title).toBeDefined();
  });
});
```

**필드 오류 키는 `details`다** — 원장이 `AppError`를 `details?: Record<string, string[]>`로
못박았고, 그 값이 봉투에 그대로 실린다. 감싸는 봉투 모양(`error` 키의 위치)은 이음매의
`errorHandler`가 정하지만, **그 안의 필드 오류 키는 팩의 계약이다.**

Express 5는 **async 핸들러의 rejection을 에러 미들웨어로 넘긴다**
<!-- verified: express@5.2.1 + supertest@7.2.2로 실행. async 핸들러의 throw가 (err,req,res,next)에 도달함을 단언하는 테스트 통과 -->
— 그래서 `try/catch`로 감싼 핸들러를 테스트하지 말고 **던지게 두고 상태 코드를 본다**.

## 4. 테스트 DB 격리 — 무엇을 언제 고르는가

병렬 실행에서 테스트가 서로의 행을 지우는 것이 이 절의 유일한 문제다.

| 전략 | 격리 단위 | 언제 고르는가 | 대가 |
| --- | --- | --- | --- |
| **워커별 스키마** | 프로세스 | 기본값. 병렬을 유지하면서 완전히 격리된다 | 워커마다 마이그레이션 1회 |
| 트랜잭션 롤백 | 테스트 | 앱이 자체 트랜잭션을 열지 않을 때만 | 서비스의 `$transaction`과 중첩되면 깨진다 |
| truncate + 직렬 실행 | 파일 | 스키마를 만들 권한이 없을 때 | `fileParallelism: false` — 가장 느리다 |

**트랜잭션 롤백을 기본값으로 고르지 않는다.** 이 팩의 서비스 계층은 트랜잭션 경계를
자기가 잡으므로(`data-access.md`), 바깥에서 감싼 트랜잭션과 중첩되면 롤백 지점이 어긋난다.

<!-- file: src/test/db.ts -->
```ts
// src/test/db.ts
import { execFileSync } from 'node:child_process';
import type { Task } from '@prisma/client';

// process.env를 직접 쓰는 예외 자리다 (policies.md: env-single-entry).
// 워커마다 다른 스키마를 주입해야 하는데 src/env.ts는 부팅 시점에 값을 굳힌다.
// TEST_DATABASE_URL은 EnvSchema에 넣지 않는다 — 앱 부팅이 이 키를 알면 안 된다.
const base = process.env.TEST_DATABASE_URL;
if (!base) throw new Error('TEST_DATABASE_URL이 없다. 운영 DB로 테스트가 붙는 것을 막는다.');
const schema = `test_w${process.env.VITEST_POOL_ID ?? '0'}`;
const url = `${base}?schema=${schema}&connection_limit=2`;
process.env.DATABASE_URL = url;

// setupFiles는 테스트 파일마다 다시 평가된다. isolate: false에서만 globalThis가
// 프로세스에 남아, 마이그레이션이 파일 수가 아니라 워커 수만큼만 돈다.
const slot = globalThis as unknown as { __schemaReady?: Promise<void> };
slot.__schemaReady ??= (async () => {
  execFileSync('npx', ['prisma', 'migrate', 'deploy'], {
    env: { ...process.env, DATABASE_URL: url },
    stdio: 'inherit',
  });
})();
await slot.__schemaReady;

// 정적 import는 위 대입보다 먼저 실행된다 — 동적 import여야 새 URL을 읽는다.
const client = await import('../db/client');
export const testDb = client.prisma;   // 앱과 같은 싱글턴. 별도 인스턴스를 만들지 않는다

export async function resetDb(): Promise<void> {
  await testDb.task.deleteMany();
}

export async function seedTask(ownerId: string, over: Partial<Task> = {}): Promise<Task> {
  return testDb.task.create({
    data: { title: over.title ?? '보고서 쓰기', status: over.status ?? 'open', ownerId },
  });
}
```

실행으로 확인한 것 (Vitest 2.1.9 · Node 24.7.0 · 테스트 파일 6개 · `maxForks: 2`):

- `VITEST_POOL_ID`는 **풀 슬롯 번호**다. `1`…`maxForks` 범위로 묶이고 프로세스보다 오래
  산다 — 파일이 워커보다 많으면 여러 프로세스가 같은 값을 이어받는다(POOL_ID `1`을 pid 3개가
  나눠 썼다). **스키마 이름에는 이 성질이 필요하다**: 스키마 수가 `maxForks`로 묶인다
- `setupFiles`는 **테스트 파일마다 다시 평가된다** — 모듈 스코프 가드로는 중복을 못 막는다
- **`isolate`가 기본값(`true`)이면 가드가 무력하다**: 파일마다 새 프로세스가 떠서
  `globalThis`가 새로 생기고, 가드 본문이 워커 수(2)가 아니라 **파일 수(6)만큼 돌았다**.
  `isolate: false`를 주면 pid 2개 · 가드 본문 2회로 떨어진다. `migrate deploy`가 파일 수만큼
  도는 것이 `hookTimeout`을 태우는 간헐 실패의 원인이다
- 위 파일이 만든 URL이 `migrate deploy`에 그대로 전달된다
  (`...?schema=test_w1&connection_limit=2`)

**`testDb`는 `src/db/client.ts`의 싱글턴 그 자체다.** 테스트가 별도 클라이언트를 만들면
커넥션 풀이 둘이 되고, 앱이 쓴 행을 테스트가 다른 연결로 못 볼 수 있다.

## 5. 소유권 회귀 테스트 — 이 축에서 가장 비싼 테스트

정책 엔진이 없으므로 이 세 가지는 **매 라우터마다** 있어야 한다. 나머지를 다 지우더라도
이건 남긴다.

**부정 단언만 걸면 차단을 증명하지 못한다.** `getTask`를 통째로 `return null`로 바꾸거나
`where`의 두 열을 뒤바꿔도 "남의 것 → 404"는 그대로 통과한다 — 모든 것이 404이기 때문이다.
**긍정 경로를 짝으로 붙여야** 그 테스트가 차단 장치가 된다.

```ts
// src/http/routers/tasks.test.ts
it('소유자는 200, 남은 404 — 짝으로 건다', async () => {
  const mine = await seedTask('owner-1');
  const other = await seedTask('owner-2');
  const ok = await request(app).get(`/api/tasks/${mine.id}`).set(authFor('owner-1'));
  expect(ok.status).toBe(200);           // ✅ 없으면 전부 404인 구현도 통과한다
  const denied = await request(app).get(`/api/tasks/${other.id}`).set(authFor('owner-1'));
  expect(denied.status).toBe(404);       // ✅ 존재를 누설하지 않는다 (403이 아니다)
});

it('0행 변경이 200으로 나가지 않는다 — 짝으로 건다', async () => {
  const mine = await seedTask('owner-1');
  const other = await seedTask('owner-2');
  const ok = await request(app)
    .patch(`/api/tasks/${mine.id}`).set(authFor('owner-1')).send({ status: 'done' });
  expect(ok.status).toBe(200);           // ✅ 긍정 경로
  const denied = await request(app)
    .patch(`/api/tasks/${other.id}`).set(authFor('owner-1')).send({ status: 'done' });
  expect(denied.status).toBe(404);
  const after = await testDb.task.findFirst({ where: { id: other.id } });
  expect(after?.status).toBe('open');    // 행이 실제로 안 바뀌었는지 DB에서 다시 읽는다
});
```

`authFor()`는 **이음매가 제공한다** — 헤더냐 쿠키냐는 조합이 정하는 것이고
(`seamSlots`의 `auth-boundaries`), 팩이 그 모양을 못박으면 조합마다 어긋난다. 테스트는
이음매의 `requireAuth`를 **모킹하지 않고 그대로 태운다**: 모킹하면 정작 검증해야 할
인가 배선이 테스트에서 빠진다.

부분 업데이트 회귀도 같은 자리에 둔다 — `{ status: 'done' }`만 보냈을 때 `title`이 그대로인지
단언한다. 스키마에 `.default()`가 겹치면 문법은 완벽한 채로 다른 필드가 덮어써진다.

## 6. 테스트하지 않는 것

- **라이브러리 자체**: Zod가 문자열을 거르는지, Express가 경로를 매칭하는지, Prisma가
  SQL을 만드는지. 이건 우리 코드의 성질이 아니다
- **모킹한 Prisma 위의 소유권 로직**: mock은 실제 `WHERE` 절을 실행하지 않는다.
  통과해도 유출을 못 막는다
- **커버리지 숫자**: 위 5절의 세 테스트가 없는 90%는 없는 것보다 위험하다 —
  안전하다는 신호를 준다
- **스키마 존재 여부**: `migrate deploy`가 성공했다는 사실이 그 증명이다
- **로그 출력 문자열**: 형태가 바뀌면 깨지고 무엇도 지키지 않는다.
  대신 `operations.md`의 `redact` 시험처럼 **비밀이 나가지 않는지**를 본다

## 오용 목록 ① — Jest → Vitest 2 관용구 대조표

| 구 습관 (Jest) | 현재 형태 (Vitest 2) |
| --- | --- |
| `jest.config.js`에 별도 설정 | `vitest.config.ts`의 `test` 키 (`vitest/config`의 `defineConfig`) |
| 전역 `describe`/`it`이 기본 제공 | 기본은 명시 import. 전역이 필요하면 `test.globals: true` |
| `jest.mock('module')` | `vi.mock('module')` — 단, 이 축에서는 Prisma를 모킹하지 않는다 |
| `testEnvironment: 'node'` | `test.environment: 'node'` |
| `maxWorkers` | `poolOptions.forks.maxForks` — forks 풀은 `maxWorkers`를 보지 않는다 |
| `globalSetup`에서 DB 준비 | setupFile + `globalThis` 가드 + **`isolate: false`** (워커별 스키마가 필요하므로) |
| `--runInBand` | `test.fileParallelism: false` |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `'vite'`의 `defineConfig` vs `'vitest/config'`의 것 | `test` 키를 쓰면 반드시 후자. 전자는 TS2769 |
| `setupFiles` vs `globalSetup` | 워커별(격리 DB)은 `setupFiles`, 프로세스 밖 1회(도커 기동)는 `globalSetup` |
| `VITEST_POOL_ID` vs `VITEST_WORKER_ID` | 스키마 이름은 **`POOL_ID`만**. `WORKER_ID`는 파일마다 증가해(실측 1…6) 스키마가 무한히 늘어난다 |
| `request(app)` vs `request(server)` | 앱 객체를 넘긴다. `listen()`한 서버를 넘기면 정리 책임이 생긴다 |
| `afterEach(resetDb)` vs `beforeEach(resetDb)` | `afterEach` — 실패한 테스트의 잔여 행을 다음 테스트가 아니라 그 자리에서 지운다 |
| 소유권 위반 응답 404 vs 403 | **404**. 403은 리소스 존재를 열거하게 해준다 |
| `toBe` vs `toMatchObject` (응답 본문) | 봉투 전체를 `toBe`로 고정하면 이음매가 바뀔 때마다 깨진다. 필요한 키만 본다 |
