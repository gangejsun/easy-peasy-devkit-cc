<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 테스트 — 실 DB에 붙고, 워커마다 스키마로 가른다

이 파일은 **테스트 하네스**를 소유한다. 인증 헤더를 만드는 `authFor`는 이음매의 몫이고
(`auth-boundaries`가 헤더냐 쿠키냐를 정한다), 아래 예제는 그 자리를 헤더로 가정한 것이다.

## 1. 무엇을 어느 층에서 시험하는가

| 대상 | 방식 | 실 DB |
| --- | --- | --- |
| 순수 함수(커서 인코딩·에러 매핑) | 직접 호출 | 필요 없다 |
| 서비스 단독(분기·예외) | `Test.createTestingModule` + Repository 대역 | 필요 없다 |
| 쿼리의 정확성(소유권·`affected`) | 실 DB에 붙은 앱 | **필요하다** |
| 엔드포인트(상태 코드·봉투) | supertest + 전역 파이프·필터 | **필요하다** |

**소유권 검사는 반드시 실 DB에서 시험한다.** 대역은 우리가 짠 대로 답하므로 `where`에
`ownerId`가 빠져도 통과한다 — 그 결함은 정의상 대역이 볼 수 없다.

## 2. 서비스 단독 — Repository 대역

<!-- verified: @nestjs/testing@11.2.1 실행 — getRepositoryToken(Task) 가 문자열 'TaskRepository' 이고, affected: 0 을 돌려주는 대역으로 update 를 부르자 AppError('NOT_FOUND') 가 나왔다 -->

```ts
// test/tasks.service.spec.ts (발췌)
const moduleRef = await Test.createTestingModule({
  providers: [
    TasksService,
    { provide: getRepositoryToken(Task), useValue: { update: async () => ({ affected: 0 }) } },
    { provide: DataSource, useValue: { transaction: async (fn: unknown) => fn } },
  ],
}).compile();
await expect(moduleRef.get(TasksService).update('owner-a', 'id', {})).rejects.toMatchObject({ code: 'NOT_FOUND' });
```

`getRepositoryToken(Task)`가 주입 토큰이다. **서비스가 Repository를 스스로 만들면 이
자리가 사라진다** — `data-access.md` §2의 "DI로만"이 여기서 값을 낸다.

## 3. 워커별 스키마 격리 (`test/db.ts`)

<!-- file: test/db.ts -->
```ts
import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { DataSource } from 'typeorm';
import { AppModule } from '../src/app.module';
import { buildValidationPipe } from '../src/common/validation';
import { buildDataSourceOptions } from '../src/database/data-source';
import { validateEnv } from '../src/config/env';
import { Task } from '../src/tasks/task.entity';

export const testSchema = process.env.DB_SCHEMA ?? 'public';

export async function prepareSchema(schema: string): Promise<void> {
  const env = validateEnv({ ...process.env, DB_SCHEMA: 'public' });
  const admin = new DataSource(buildDataSourceOptions(env));
  await admin.initialize();
  const runner = admin.createQueryRunner();
  await runner.dropSchema(schema, true, true);
  await runner.createSchema(schema, true);
  await runner.release();
  await admin.destroy();
}

export async function createTestApp(
  configure?: (app: INestApplication) => void,
): Promise<INestApplication> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = moduleRef.createNestApplication({ logger: false });
  app.useGlobalPipes(buildValidationPipe());
  configure?.(app);
  await app.init();
  await app.get(DataSource).runMigrations();
  return app;
}

export async function resetDb(app: INestApplication): Promise<void> {
  await app.get(DataSource).getRepository(Task).deleteAll();
}

export async function seedTask(app: INestApplication, ownerId: string, patch: Partial<Task> = {}): Promise<Task> {
  const repo = app.get(DataSource).getRepository(Task);
  return repo.save(repo.create({ title: '작업', ownerId, ...patch }));
}
```

<!-- verified: PostgreSQL 18.4 + jest@30.4.2 실행 — pg_tables 조회로 tasks 테이블이 test_w1 스키마에 만들어진 것을 확인했다 -->
격리 단위가 **데이터베이스가 아니라 스키마**인 이유는 값이다: 데이터베이스를 워커마다
만들면 연결·템플릿 복제 비용이 크고, 트랜잭션 롤백으로 가르면 트랜잭션 자체를 시험할 수
없다. 스키마는 `DataSourceOptions.schema` 한 줄로 갈리고 마이그레이션이 그대로 돈다.

**원시 SQL을 쓰지 않는다.** 스키마 이름은 식별자라 파라미터화할 수 없어
`query('CREATE SCHEMA ' + name)`을 쓰고 싶어지지만, `QueryRunner`의 `createSchema`·
`dropSchema`가 그 일을 한다. 정리도 `repo.deleteAll()`이라 SQL이 없다.

## 4. 스키마는 AppModule을 import하기 **전에** 정한다

<!-- verified: @nestjs/config@4.0.4 실행 — createTestApp 안에서 process.env.DB_SCHEMA 를 바꾸자 DataSource.options.schema 가 여전히 'public' 이었고, 테이블이 격리 스키마가 아니라 public 에 만들어졌다. 그런데도 테스트는 4/4 통과했다 -->
**이 함정이 이 파일에서 가장 비싸다.** `ConfigModule.forRoot()`는 모듈 파일이 로드되는
순간 `validate`를 돌린다 — 클래스 데코레이터의 인자로 평가되기 때문이다. `AppModule`을
import한 뒤에 `process.env`를 바꾸면 **설정에는 반영되지 않는다.**

증상이 고약한 이유는 그때도 테스트가 초록이라는 데 있다. 워커 둘이 같은 `public`
스키마를 쓰면서 서로의 행을 지우는데, 각 테스트가 `beforeEach`에서 정리하므로 대개
그냥 통과한다. 발견은 실패가 아니라 **`pg_tables`를 직접 조회해서** 했다.

<!-- file: test/setup.ts -->
```ts
import 'reflect-metadata';

// **AppModule 을 import 하기 전에** 스키마를 정한다.
// ConfigModule.forRoot() 는 모듈 파일이 로드되는 순간 validate 를 돌리므로,
// 그 뒤에 process.env 를 바꿔도 설정에는 반영되지 않는다 (실측).
process.env.DB_SCHEMA = `test_w${process.env.JEST_WORKER_ID ?? '1'}`;
```

`setupFiles`는 테스트 파일과 그 import보다 먼저 돈다 — 그래서 이 자리가 유일하게
안전하다. `setupFilesAfterEnv`는 늦다.

<!-- file: test/global-setup.ts -->
```ts
import 'reflect-metadata';
import type { Config } from '@jest/types';
import { prepareSchema } from './db';

export default async function globalSetup(config: Config.GlobalConfig): Promise<void> {
  for (let worker = 1; worker <= config.maxWorkers; worker++) {
    await prepareSchema(`test_w${worker}`);
  }
}
```

`globalSetup`은 **워커 밖에서 한 번** 돈다 — 그래서 `JEST_WORKER_ID`가 없다. 자기
스키마만 만들면 2번 워커가 빈 스키마를 만나 실패한다. `maxWorkers`를 받아 전부 만든다.

<!-- file: jest.config.js -->
```js
/** @type {import('jest').Config} */
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  rootDir: '.',
  testRegex: '.*\\.spec\\.ts$',
  setupFiles: ['<rootDir>/test/setup.ts'],
  globalSetup: '<rootDir>/test/global-setup.ts',
  maxWorkers: 2,
  testTimeout: 20000,
};
```

설정을 `jest.config.ts`로 두면 jest 30이 ESM으로 읽으려다 실패하고 경고를 낸다
(동작은 한다). `.js` + JSDoc 타입 주석이 경고 없이 같은 타입 검사를 받는다.
<!-- verified: jest@30.4.2 실행 — jest.config.ts 에서 "Failed to load the ES module" 경고가 났고 .js 로 바꾸자 사라졌다 -->

## 5. 엔드포인트 테스트 — 차단을 증명한다

<!-- file: test/tasks.spec.ts -->
```ts
import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { AllExceptionsFilter } from '../src/common/all-exceptions.filter';
import { createTestApp, resetDb, seedTask } from './db';

const A = '11111111-1111-1111-1111-111111111111';
const B = '22222222-2222-2222-2222-222222222222';
const authFor = (ownerId: string) => ({ 'x-owner-id': ownerId });

describe('작업 API', () => {
  let app: INestApplication;

  beforeAll(async () => {
    app = await createTestApp((a) => a.useGlobalFilters(new AllExceptionsFilter()));
  });
  afterAll(async () => { await app.close(); });
  beforeEach(async () => { await resetDb(app); });

  it('소유자는 자기 작업을 읽고, 남은 읽지 못한다', async () => {
    const mine = await seedTask(app, A, { title: '내 작업' });
    const ok = await request(app.getHttpServer()).get(`/api/tasks/${mine.id}`).set(authFor(A));
    expect(ok.status).toBe(200);
    expect(ok.body.data.title).toBe('내 작업');

    const denied = await request(app.getHttpServer()).get(`/api/tasks/${mine.id}`).set(authFor(B));
    expect(denied.status).toBe(404);
  });

  it('소유자는 수정하고, 남의 수정은 404이며 값이 그대로다', async () => {
    const mine = await seedTask(app, A, { title: '원래 제목' });
    const ok = await request(app.getHttpServer()).patch(`/api/tasks/${mine.id}`).set(authFor(A)).send({ title: '바꾼 제목' });
    expect(ok.status).toBe(200);
    expect(ok.body.data.title).toBe('바꾼 제목');

    const denied = await request(app.getHttpServer()).patch(`/api/tasks/${mine.id}`).set(authFor(B)).send({ title: '탈취' });
    expect(denied.status).toBe(404);
    const after = await request(app.getHttpServer()).get(`/api/tasks/${mine.id}`).set(authFor(A));
    expect(after.body.data.title).toBe('바꾼 제목');
  });

  it('목록은 소유자의 행만 담는다', async () => {
    await seedTask(app, A, { title: 'A-1' });
    await seedTask(app, A, { title: 'A-2' });
    await seedTask(app, B, { title: 'B-1' });
    const res = await request(app.getHttpServer()).get('/api/tasks?limit=10').set(authFor(A));
    expect(res.status).toBe(200);
    expect(res.body.data).toHaveLength(2);
    expect(res.body.data.map((t: { title: string }) => t.title).sort()).toEqual(['A-1', 'A-2']);
  });

  it('DTO에 없는 키는 거부하고, 올바른 본문은 통과한다', async () => {
    const ok = await request(app.getHttpServer()).post('/api/tasks').set(authFor(A)).send({ title: '정상' });
    expect(ok.status).toBe(201);

    const bad = await request(app.getHttpServer()).post('/api/tasks').set(authFor(A)).send({ title: '오타', admin: true });
    expect(bad.status).toBe(400);
    expect(bad.body.error.details).toHaveProperty('admin');
  });
});
```

**각 `it`이 긍정과 부정을 짝으로 건다.** 부정만 걸면 구현을 통째로 망가뜨려도 초록이다 —
모든 요청이 404가 되기 때문이다. 위 두 번째 테스트가 수정 후 값까지 다시 읽는 것도
같은 이유다: 404를 받았다는 것만으로는 "막혔다"와 "원래 값이 날아갔다"가 구분되지 않는다.

<!-- verified: jest@30.4.2 + PostgreSQL 18.4 실행 — get()의 where 에서 ownerId 를 빼자 첫 테스트가 즉시 실패했고(1 failed), 되돌리자 4/4 통과했다 -->
차단 증명은 실제로 해 본다: 소유권 필터를 지우고 테스트가 **빨개지는지** 확인한 뒤
되돌린다. 빨개지지 않으면 그 테스트는 차단 장치가 아니라 장식이다.

`createTestApp`의 `configure` 콜백이 이음매의 예외 필터를 끼우는 자리다. 걸지 않으면
`AppError`가 전부 500으로 나가 **상태 코드 단언이 전부 의미를 잃는다**
(`error-handling.md` §4).

## 6. 무엇을 정리하고 무엇을 두는가

| 시점 | 하는 일 | 왜 |
| --- | --- | --- |
| `globalSetup` | 워커 수만큼 스키마 생성 | 한 번이면 된다. 매번 만들면 느리다 |
| `beforeAll` | 앱 부팅 + 마이그레이션 | 앱 하나를 파일 전체가 공유한다 |
| `beforeEach` | `resetDb` | 테스트 간 순서 의존을 끊는다 |
| `afterAll` | `app.close()` | 빠뜨리면 jest가 "open handles"로 매달린다 |

`afterEach`에 정리를 두지 않는 이유는 실패한 테스트의 DB 상태를 남겨 두기 위해서다 —
`beforeEach` 정리는 다음 테스트가 알아서 한다.

## 오용 목록 ① — Express/Vitest 관용구 → Nest + Jest 형태 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `supertest(app)` (Express 앱 직접) | `supertest(app.getHttpServer())` |
| `jest.mock('../src/db')` 모듈 모킹 | `overrideProvider(token).useValue(...)` — DI가 이미 이음매다 |
| `beforeAll`에서 `new Service(new Repo())` | `Test.createTestingModule` — 실제 주입 그래프를 그대로 쓴다 |
| `process.env.X = ...`를 테스트 안에서 | `setupFiles`에서 (§4). 모듈 로드 뒤에는 늦다 |
| `vi.fn()` / `vitest` 설정 | `jest.fn()` / `jest.config.js`. Nest CLI 기본이 Jest다 |
| 트랜잭션 롤백으로 격리 | 스키마로 격리. 트랜잭션 자체를 시험해야 하기 때문 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `setupFiles` vs `setupFilesAfterEnv` | 앞은 테스트 프레임워크 **전**(환경 설정), 뒤는 후(matcher 등록). 스키마 지정은 반드시 앞 |
| `globalSetup` vs `beforeAll` | 앞은 프로세스 밖에서 1회(워커 ID 없음), 뒤는 워커 안에서 파일마다 |
| `app.init()` vs `app.listen()` | 테스트는 `init()`으로 충분하다. `listen`은 포트를 잡아 병렬 실행에서 충돌한다 |
| `deleteAll()` vs `TRUNCATE` | 전자는 API라 스키마·FK 순서를 ORM이 안다. 후자는 원시 SQL이 된다 |
| `expect(res.status).toBe(404)` 단독 | 긍정 경로와 짝으로 걸지 않으면 차단 증명이 아니다 (§5) |
| 실 DB 없이 소유권 시험 | 대역은 우리가 짠 대로 답한다 — 그 결함을 구조적으로 볼 수 없다 |
