<!-- epcc-seam: vue+node-api v3.13.0 -->
# 완전 예제 — 마이그레이션에서 테스트까지 한 번 관통

`Task` 기능 하나를 처음부터 끝까지 잇는다. **여기서 새로 정의하는 것은 스키마와 서비스뿐이고**
나머지는 이미 있는 것을 소비한다 — 어느 단계가 어느 파일의 소유인지 보이는 것이 이 파일의
목적이다. 절마다 그 단계의 정본 파일을 지목한다.

## 1. 판단 — 여섯 단계와 그 소유자

새 기능을 만들 때 이 순서로 내려간다. 순서를 뒤집으면 — 라우터부터 쓰면 — 스키마가 없어
`any`가 번지고, 소유권 조건을 어디에 걸지 정하지 못한 채 핸들러가 완성된다.

| # | 단계 | 파일 | 정본 |
| --- | --- | --- | --- |
| 1 | 마이그레이션·모델 | `prisma/schema.prisma` | 이 파일 2절 (설계는 T1 데이터 모델링 카드) |
| 2 | 요청 스키마 | `src/schemas/task.ts` | `resources/input-validation.md` |
| 3 | 쿼리 | `src/db/tasks.ts` | `resources/data-access.md` |
| 4 | 서비스 (트랜잭션 경계) | `src/services/task-service.ts` | 이 파일 4절 |
| 5 | 라우터·마운트 | `src/http/routers/tasks.ts` · `src/app.ts` | `resources/api-endpoints.md` |
| 6 | 테스트 | `src/http/routers/tasks.test.ts` | 이 파일 6절 · `resources/testing.md` |

3단계까지 내려간 뒤 다시 올라오는 이유는 하나다 — **소유권을 걸 자리가 3단계이기 때문이다.**
이 축에는 데이터 계층 정책 엔진이 없어 쿼리의 `where`가 유일한 경계다.

## 2. 마이그레이션과 모델 (`prisma/schema.prisma`)

<!-- file: prisma/schema.prisma -->
```prisma
generator client {
  provider = "prisma-client-js"
}

datasource db {
  provider = "postgresql"
  url      = env("DATABASE_URL")
}

enum TaskStatus {
  open
  done
}

model Task {
  id        String     @id @default(cuid())
  title     String     @db.VarChar(200)
  status    TaskStatus @default(open)
  dueAt     DateTime?
  ownerId   String
  createdAt DateTime   @default(now())
  updatedAt DateTime   @updatedAt
  comments  Comment[]

  @@unique([ownerId, title])
  @@index([ownerId, createdAt, id])
}

model Comment {
  id      String @id @default(cuid())
  body    String
  taskId  String
  task    Task   @relation(fields: [taskId], references: [id], onDelete: Cascade)
  ownerId String
}

model AuditEntry {
  id      String   @id @default(cuid())
  ownerId String
  taskId  String
  action  String
  at      DateTime @default(now())
}

model RefreshToken {
  id        String    @id @default(cuid())
  tokenHash String    @unique
  ownerId   String
  expiresAt DateTime
  usedAt    DateTime?
  familyId  String

  @@index([ownerId])
}
```

<!-- verified: prisma@6.19.3 실행 — 이 파일 그대로 `prisma generate`가 통과해 @prisma/client에 Task·Comment·AuditEntry·RefreshToken과 TaskStatus를 만들었다. `migrate`는 PostgreSQL이 없어 돌리지 못했다 -->
네 모델이 다 필요한 이유가 있다. `Comment`는 `resources/data-access.md` 5절의 중첩 `select`
예제가 붙을 관계이고, `AuditEntry`는 4절의 트랜잭션이 쓰며, `RefreshToken`은
`resources/auth-boundaries.md` 5절의 회전이 쓴다. 하나라도 빠지면 그 절의 코드가 조립본에서 뜬다.

`@@unique([ownerId, title])`이 `P2002` → 409의 발화 지점이고, `@@index([ownerId, createdAt, id])`가
커서 페이지네이션의 정렬 키와 **같은 순서**다. 인덱스 순서가 다르면 커서가 동작은 하되 매 쪽이
정렬을 다시 한다. `@db.VarChar(200)`은 Zod의 `.max(200)`과 짝이다 — 한쪽만으로는 부족하다.

적용은 배포와 **분리된 단계**로 돈다: 개발은 `npx prisma migrate dev --name add-task`,
배포는 `npx prisma migrate deploy`. 애플리케이션 부팅에서 부르지 않는다 —
인스턴스가 동시에 뜨면 같은 마이그레이션을 경합해 적용한다.

## 3. 스키마와 쿼리는 팩이 준다 — 소비 형태만 맞춘다

2·3단계의 코드는 `resources/input-validation.md`와 `resources/data-access.md`에 있다. 여기서
확인할 것은 **호출 형태 두 가지**뿐이고, 둘 다 실측에서 실제로 틀렸던 자리다.

```ts
// src/services/task-service.ts — 팩 쿼리 소비 형태
// ❌ 인자 순서를 뒤집었다. 둘 다 string이라 tsc가 잡지 못하고 모든 조회가 404가 된다
const task = await getTask(id, ownerId);
// ✅ 소유자가 먼저다
const task = await getTask(ownerId, id);
```

`listTasks(ownerId, q)`의 `q`는 `TaskQuery` 그대로다. 쿼리 함수가 `take: q.limit + 1`로 한 행
더 받아 오므로 **소비 측이 잘라내고 커서를 만든다** — 그 조립은 라우터가 한다
(`resources/api-endpoints.md` 6절).

## 4. 서비스 — 트랜잭션 경계 (`src/services/task-service.ts`)

쿼리 하나로 끝나면 서비스가 필요 없다. **여러 쓰기가 원자적이어야 할 때** 생긴다.
보관 처리는 상태 변경과 감사 기록이 함께 성공하거나 함께 실패해야 한다.

```ts
// src/services/task-service.ts
import type { Prisma } from '@prisma/client';
import { AppError } from '../http/app-error';
import { prisma } from '../db/client';

export function archiveTask(ownerId: string, id: string) {
  return prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    const changed = await tx.task.updateMany({ where: { id, ownerId }, data: { status: 'done' } });
    if (changed.count === 0) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다');
    await tx.auditEntry.create({ data: { ownerId, taskId: id, action: 'archive' } });
  });
}
```

세 줄이 다 필요하다. **소유권은 `where`에** 들어가고(조회 후 비교는 경합에 뚫린다),
**영향 행 수가 판정**이며(`updateMany`는 남의 행에 대해 예외 없이 `count: 0`이다),
**감사 기록은 같은 트랜잭션 안**이다(밖에 두면 상태만 바뀌고 기록이 사라지는 조합이 생긴다).

트랜잭션 안에서 HTTP 호출이나 큐 발행을 하지 않는다 — 롤백돼도 그 부수효과는 되돌아오지
않고, 외부 응답을 기다리는 동안 락만 길어진다. 커밋 뒤에 한다.

## 5. 라우터와 마운트 (`src/http/routers/tasks.ts` · `src/app.ts`)

`tasksRouter`의 전문은 `resources/api-endpoints.md` 5절에 있다. 여기서는 4절의 서비스를
붙이는 줄만 본다 — 서비스가 던지고 라우터는 성공 봉투만 만든다.

```ts
// src/http/routers/tasks.ts — 보관 처리 라우트 (requireAuth는 라우터 전체에 걸려 있다)
tasksRouter.post('/:id/archive', async (req, res) => {
  const task = await archiveTask(actor(req).id, req.params.id);
  res.json({ data: task });
});
```

```ts
// src/app.ts — makeApp() 안의 마운트 순서 (발췌)
app.use(cors);                       // 프리플라이트는 본문 파서보다 앞
app.use(express.json({ limit: '1mb' }));
app.use('/api/auth', authRouter);
app.use('/api/tasks', tasksRouter);
app.use(notFound);                   // 라우터 뒤
app.use(errorHandler);               // 반드시 마지막
```

<!-- verified: express@5.2.1 + supertest@7.2.2 실행 — 이 배선으로 소유자의 보관 요청이 200 `{"data":{…"status":"done"}}`, 타인의 같은 요청이 404 NOT_FOUND, 타인 행의 status는 open 그대로였다. 트랜잭션 자체(prisma.$transaction·auditEntry)는 PostgreSQL이 없어 메모리 스텁으로 대체했고 실물 미검증이다 -->
`makeApp`과 `notFound`는 팩이 소유한다(`resources/project-structure.md`) — 여기서 다시 정의하지
않고 마운트 줄만 늘린다.

## 6. 테스트 관통 (`src/http/routers/tasks.test.ts`)

<!-- file: src/http/routers/tasks.test.ts -->
```ts
import { afterEach, describe, expect, it } from 'vitest';
import request from 'supertest';
import { makeApp } from '../../app';
import { resetDb, seedTask, testDb } from '../../test/db';
import { authFor } from '../../test/auth';

const app = makeApp();
afterEach(resetDb);

describe('GET/PATCH /api/tasks/:id — 소유권', () => {
  it('소유자는 200, 남은 404 — 짝으로 건다', async () => {
    const mine = await seedTask('owner-1');
    const other = await seedTask('owner-2', { title: '남의 작업' });
    const ok = await request(app).get(`/api/tasks/${mine.id}`).set(authFor('owner-1'));
    expect(ok.status).toBe(200);
    expect(ok.body).toMatchObject({ data: { id: mine.id, title: '보고서 쓰기' } });
    const denied = await request(app).get(`/api/tasks/${other.id}`).set(authFor('owner-1'));
    expect(denied.status).toBe(404);
    expect(denied.body.error.code).toBe('NOT_FOUND');
  });

  it('0행 변경이 200으로 나가지 않는다 — 짝으로 건다', async () => {
    const mine = await seedTask('owner-1');
    const other = await seedTask('owner-2', { title: '남의 작업' });
    const ok = await request(app)
      .patch(`/api/tasks/${mine.id}`).set(authFor('owner-1')).send({ status: 'done' });
    expect(ok.status).toBe(200);
    expect(ok.body.data.title).toBe('보고서 쓰기');   // .default() 겹침 회귀
    const denied = await request(app)
      .patch(`/api/tasks/${other.id}`).set(authFor('owner-1')).send({ status: 'done' });
    expect(denied.status).toBe(404);
    const after = await testDb.task.findFirst({ where: { id: other.id } });
    expect(after?.status).toBe('open');              // DB에서 다시 읽는다
  });

  it('인증이 없으면 401, 있으면 200 — 짝으로 건다', async () => {
    const mine = await seedTask('owner-1');
    const anon = await request(app).get(`/api/tasks/${mine.id}`);
    expect(anon.status).toBe(401);
    expect(anon.body.error.code).toBe('UNAUTHENTICATED');
    const ok = await request(app).get(`/api/tasks/${mine.id}`).set(authFor('owner-1'));
    expect(ok.status).toBe(200);
  });
});
```

**긍정 단언이 이 테스트의 절반이다.** 실패 단언만 걸면 구현을 통째로 망가뜨려도 초록이다 —
모든 것이 404이기 때문이다. 두 변이를 실제로 심어 확인했다:

<!-- verified: vitest@2.1.9 + supertest@7.2.2 실행 — 아래 두 변이를 각각 적용해 돌리고 되돌렸다 -->
| 심은 결함 | 무엇이 깨지는가 | 결과 |
| --- | --- | --- |
| `getTask`를 `return null`로 | 긍정 단언 (`toBe(200)`) | 4건 중 3건 실패 |
| `where`에서 `ownerId` 제거 | 부정 단언 (`expected 200 to be 404`) | 4건 중 2건 실패 |

한쪽만 있으면 다른 쪽 결함이 통과한다. 짝으로 걸어야 이 테스트가 차단 장치가 된다.
`seedTask`·`resetDb`·`testDb`는 팩이(`resources/testing.md`), `authFor`는 이음매가
(`resources/auth-boundaries.md` 6절) 준다. `requireAuth`는 **모킹하지 않는다** — 모킹하면
정작 검증해야 할 인가 배선이 테스트에서 빠진다.

## 오용 목록 ① — 관통 예제에서 실제로 깨지는 자리

| 구 습관 | 이 조합의 형태 |
| --- | --- |
| 부팅에서 `migrate deploy`를 부른다 | 배포와 분리된 단계. 인스턴스가 동시에 뜨면 경합한다 |
| `db push`로 스키마를 맞춘다 | 마이그레이션 파일이 남지 않아 되돌릴 기록이 없다 |
| 라우터에서 `prisma`를 직접 부른다 | 쿼리는 `src/db/`, 트랜잭션 경계는 `src/services/` |
| 서비스가 `Request`를 인자로 받는다 | 평범한 인자만. HTTP 해석은 라우터의 몫이다 |
| 감사 기록을 트랜잭션 밖에서 쓴다 | 같은 `tx` 안. 밖이면 상태만 바뀌고 기록이 사라진다 |
| `createdAt` 하나로 커서를 만든다 | `(createdAt, id)` 전순서. 같은 밀리초에 만들어진 행이 실재한다 |
| 실패 단언만 있는 소유권 테스트 | 긍정 경로를 같은 `it` 안에 짝으로 건다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `getTask(ownerId, id)` vs `getTask(id, ownerId)` | 소유자가 먼저다. 둘 다 `string`이라 컴파일러가 잡지 못한다 |
| `src/db/` vs `src/services/` | 쿼리 하나면 `db/`. 여러 쓰기가 원자적이어야 하면 `services/` |
| `updateMany` vs `update` | 소유권 필터가 있으면 둘 다 안전하다. 차이는 실패 신호(`count: 0` vs `P2025`) |
| `migrate dev` vs `migrate deploy` | 앞은 개발에서 SQL을 만들고, 뒤는 만들어진 것을 적용만 한다 |
| `@@unique` vs Zod `.refine()` | 유일성은 DB만 원자적으로 판정한다. 검사 후 삽입은 경합에 뚫린다 |
| `toMatchObject` vs `toBe` (봉투) | 필요한 키만 본다. 봉투 전체 고정은 이음매가 바뀔 때마다 깨진다 |
| `afterEach(resetDb)` vs `beforeEach` | `afterEach` — 실패한 테스트의 잔여 행을 그 자리에서 지운다 |
