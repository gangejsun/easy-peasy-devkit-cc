<!-- epcc-pack: backend/node-api v3.13.0 -->
# 데이터 액세스 — Prisma 6 쿼리 계층 (`src/db/`)

이 파일이 소유하는 것: PrismaClient 싱글턴 · 쿼리 함수 · 페이지네이션 · 트랜잭션 경계 ·
마이그레이션 실행. 소유하지 않는 것: **테이블·컬럼·인덱스 설계는 T1 데이터 모델링 카드
(`.claude/rules/data-modeling.md`)가 정본이며 `prisma/**`·`db/**` 경로에서 자동 로드된다** —
여기 복사하지 않는다. 에러 코드 판별·상태 매핑은 `resources/error-handling.md`, 요청 스키마는
`resources/input-validation.md`, 앱 조립과 계층 규율은 `resources/project-structure.md`.

> **이 축에는 행 수준 정책 엔진이 없다.** 애플리케이션이 신뢰된 연결로 PostgreSQL에 붙으므로
> 이 파일의 `where`가 **유일한 권한 경계다.** 소유권 필터를 빠뜨리면 뒤에서 막아 줄 층이
> 없다 — 누락이 곧 데이터 유출이다. "데이터 계층이 백업하니 이중 방어" 서술은 이 축에서 거짓이다.

## 1. 판단 — 어느 호출을 고르는가

먼저 **소유자 판정 근거**를 정한다. `ownerId`는 검증된 세션에서만 온다(`requireAuth`가 실은
`req.user.id`). 요청 본문·쿼리 문자열·헤더에서 읽은 소유자 값은 쓰지 않는다 — 그건 공격자가
고르는 값이다.

| 하려는 일 | 형태 | 실패 신호 |
| --- | --- | --- |
| 소유자 범위 목록 | `findMany({ where: { ownerId } })` | 빈 배열 |
| 소유자 범위 단건 | `findFirst({ where: { id, ownerId } })` | `null` |
| 생성 | `create({ data: { ...input, ownerId } })` | throw (`P2002` 등) |
| 수정 | `updateMany` + 영향 행 수 확인 | `{ count: 0 }` — **예외가 없다** |
| 삭제 | `deleteMany` + 영향 행 수 확인 | `{ count: 0 }` — **예외가 없다** |
| 여러 쓰기를 원자적으로 | `$transaction(async (tx) => …)` | 예외 시 롤백 |
| ORM으로 못 쓰는 SQL | `$queryRaw` 태그드 템플릿 | throw |

쿼리 함수는 **평범한 인자만 받는다.** HTTP 객체를 받으면 쿼리 테스트에 서버가 필요해지고
계층이 무너진다 (`resources/project-structure.md` 1~2절).

## 2. 클라이언트 싱글턴 (`src/db/client.ts`)

이 저장소에서 `new PrismaClient(`가 등장하는 **유일한 자리다.** 인스턴스가 둘이면 커넥션 풀도
둘이 되어 풀 사이징 계산이 전부 틀어진다.

<!-- file: src/db/client.ts -->
```ts
// src/db/client.ts
import { PrismaClient } from '@prisma/client';
import { env } from '../env';

export const prisma = new PrismaClient({
  datasourceUrl: env.DATABASE_URL,
  log: env.NODE_ENV === 'development' ? ['warn', 'error'] : ['error'],
});
```

접속 문자열은 `env`에서만 온다 — 부팅 시점에 검증되지 않은 값으로 풀을 열면 실패가 첫 쿼리
시점으로 밀린다 (`resources/input-validation.md`). 풀 크기·타임아웃은 `resources/operations.md`가 정한다.

모듈 싱글턴으로 충분하다. **실행 확인**: 같은 모듈을 정적 `import`와 동적 `import()`로 두 번
불러도 `a === b`가 `true`였다. `globalThis` 가드는 프로세스를 유지한 채 모듈 그래프를 갈아끼우는
HMR 런타임의 관용구이며, 한 번 떠서 계속 사는 이 서버에는 불필요한 전역 오염이다.

## 3. 쿼리 함수 (`src/db/tasks.ts`)

소유권은 **전부 `where`에 들어간다.** 조회해 와서 나중에 소유자를 비교하는 형태는 그 사이의
변경에 뚫리고, 실수로 비교를 빠뜨려도 아무 신호가 없다.

<!-- file: src/db/tasks.ts -->
```ts
// src/db/tasks.ts
import type { Prisma, Task, TaskStatus } from '@prisma/client';
import { AppError } from '../http/app-error';
import { prisma } from './client';

const fields = { id: true, title: true, status: true, createdAt: true } satisfies Prisma.TaskSelect;
export type TaskView = Prisma.TaskGetPayload<{ select: typeof fields }>;
type Patch = Partial<Pick<Task, 'title' | 'status'>>;

export function listTasks(
  ownerId: string,
  q: { limit: number; cursor?: string; status?: TaskStatus },
): Promise<TaskView[]> {
  return prisma.task.findMany({
    where: { ownerId, ...(q.status ? { status: q.status } : {}) },
    select: fields,
    orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
    take: q.limit + 1,
    ...(q.cursor ? { cursor: { id: q.cursor }, skip: 1 } : {}),
  });
}

export function getTask(ownerId: string, id: string): Promise<TaskView | null> {
  return prisma.task.findFirst({ where: { id, ownerId }, select: fields });
}

export function insertTask(ownerId: string, input: Patch & { title: string }): Promise<TaskView> {
  return prisma.task.create({ data: { ...input, ownerId }, select: fields });
}

export async function updateTask(ownerId: string, id: string, patch: Patch): Promise<TaskView> {
  const changed = await prisma.task.updateMany({ where: { id, ownerId }, data: patch });
  if (changed.count === 0) throw new AppError('NOT_FOUND', 'Task not found');
  const view = await getTask(ownerId, id);
  if (!view) throw new AppError('NOT_FOUND', 'Task not found');
  return view;
}

export async function deleteTask(ownerId: string, id: string): Promise<void> {
  const removed = await prisma.task.deleteMany({ where: { id, ownerId } });
  if (removed.count === 0) throw new AppError('NOT_FOUND', 'Task not found');
}
```

`listTasks`의 `q`는 `TaskQuery`(`resources/input-validation.md`)를 그대로 받는 형태다 —
스키마가 파싱하는 필드(`limit`·`cursor`·`status`)를 **인자 타입과 `where` 양쪽에** 반영한다.
구조적 타이핑이라 필드를 빠뜨린 인자 타입에도 `TaskQuery`가 그대로 들어가고 컴파일된다:
누락된 필터는 타입 오류가 아니라 **조용히 무시되는 조건**이 된다. 실행 확인: `status: 'done'`을
넘기면 완료 1건, `'open'`이면 미완 1건, 생략하면 2건이 왔다.

`insertTask`에서 **`ownerId`가 전개 뒤에 온다.** 순서를 바꾸면 요청 본문이 실어 보낸
`ownerId`가 세션 값을 덮어쓴다. 실측(실 DB): `{ ...body, ownerId }`는 `alice`로,
`{ ownerId, ...body }`는 `attacker`로 저장됐다. 문법은 양쪽 다 통과한다.

## 4. 변이는 영향 행 수를 확인한다

소유권 필터가 걸린 변이는 남의 행에 대해 **예외 없이 0행 변경으로 끝난다.** 확인하지 않으면
라우터가 200을 돌려주고, 호출자는 수정이 된 줄 안다.

PostgreSQL 실측 — `bob`의 행을 `alice`로 건드렸을 때:

| 호출 | Prisma가 보낸 SQL | 결과 |
| --- | --- | --- |
| `updateMany({ where: { id, ownerId } })` | `UPDATE … WHERE "id" = $1 AND "ownerId" = $2` | `{ count: 0 }`, 예외 없음, 피해 행 그대로 |
| `update({ where: { id, ownerId } })` | 같은 WHERE + `RETURNING` | `P2025` throw |
| `deleteMany({ where: { id, ownerId } })` | `DELETE … WHERE "id" = $1 AND "ownerId" = $2` | `{ count: 0 }`, 예외 없음 |

둘 다 DB 수준에서는 안전하다 — 차이는 **실패 신호**뿐이다. `updateMany`/`deleteMany`가 조용한
쪽이므로 `count`를 반드시 본다. `update`/`delete`를 쓸 거면 `P2025`를 `isRecordNotFound`로
받아 `NOT_FOUND`로 정규화한다 (`resources/error-handling.md`).

**남의 행에 대한 응답은 404다.** 403을 돌려주면 "그 id는 존재한다"를 알려주는 것이고,
미인가 사용자가 id를 훑어 리소스 존재를 열거할 수 있다. 위 함수들이 부재와 권한 없음에
같은 `NOT_FOUND`를 던지는 이유다.

## 5. 열을 좁히고, 관계는 한 번에 가져온다

`select`를 생략하면 모든 열이 온다. 비밀·해시·내부 플래그가 있는 모델에서는 그것이 그대로
로그와 응답으로 나가는 경로가 된다. 위 `fields` 상수가 `ownerId`를 빼는 이유도 같다 —
응답 봉투에 소유자 식별자를 실을 이유가 없다.

관계를 루프에서 조회하면 쿼리가 행 수만큼 늘어난다. **실측(행 10개)**: 목록 1회 + 루프
10회 = **11 쿼리**, 중첩 `select` = **2 쿼리**, 개수만 필요할 때 `_count` = **1 쿼리**.

```ts
// src/db/tasks.ts — 관계 로딩 (필요할 때만 fields를 확장한다)
// ✅ 중첩 select — 관계 단계마다 1회, 열도 좁힌다
const withComments = await prisma.task.findMany({
  where: { ownerId },
  select: { id: true, title: true, comments: { select: { id: true, body: true } } },
});

// ✅ 개수만 필요하면 관계 행을 가져오지 않는다
const withCounts = await prisma.task.findMany({
  where: { ownerId },
  select: { id: true, title: true, _count: { select: { comments: true } } },
});
```

중첩 `select`가 1회가 아니라 2회인 것은 Prisma가 기본적으로 JOIN이 아니라 관계 단계별 쿼리로
읽기 때문이다. 행 수에 비례하지 않는다는 것이 요점이다.

## 6. 커서 페이지네이션

`skip`(오프셋)은 건너뛴 행을 DB가 실제로 읽고 버리므로 뒤 페이지가 선형으로 느려지고, 그
사이 삽입·삭제가 일어나면 행이 중복되거나 빠진다. 커서는 **정렬 키 위치**에서 이어 읽는다.

`take: limit + 1`로 한 행 더 받아 다음 페이지 유무를 알아낸다 — 별도 `count` 쿼리가 없어진다.

```ts
// src/services/task-service.ts — listTasks 소비 측
const rows = await listTasks(user.id, { limit, cursor });
const hasMore = rows.length > limit;
const items = hasMore ? rows.slice(0, limit) : rows;
const nextCursor = hasMore ? items[items.length - 1].id : null;
```

정렬 키는 **전순서**여야 한다. `createdAt` 하나만으로는 부족하다 — 실측에서 연속 생성한 6행이
같은 밀리초 값을 가졌고, 동률 구간의 행 순서는 실행 계획에 달린다. 유일 열(`id`)을 2차 키로
넣어 전순서로 만들고, 인덱스도 같은 순서로 건다(`@@index([ownerId, createdAt, id])` — 설계
자체는 T1 데이터 모델링 카드가 정본이다).

## 7. 트랜잭션 경계 (`src/services/`)

트랜잭션은 쿼리 함수가 아니라 **서비스가 연다.** 쿼리 함수가 저마다 트랜잭션을 열면 두 함수를
묶어 쓸 때 중첩되고, 경계가 호출 순서에 따라 달라진다.

```ts
// src/services/task-service.ts
import type { Prisma } from '@prisma/client';
import { AppError } from '../http/app-error';
import { prisma } from '../db/client';

export function archiveTask(ownerId: string, id: string) {
  return prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    const changed = await tx.task.updateMany({ where: { id, ownerId }, data: { status: 'done' } });
    if (changed.count === 0) throw new AppError('NOT_FOUND', 'Task not found');
    await tx.auditEntry.create({ data: { ownerId, taskId: id, action: 'archive' } });
  });
}
```

**실행 확인**: 콜백이 던지면 그 안의 `create`가 롤백됐다(행 수 5 → 5). 헬퍼에 트랜잭션을
넘길 때 인자 타입은 `Prisma.TransactionClient`다 — `PrismaClient`로 타이핑하면 컴파일은 되지만
헬퍼가 트랜잭션 밖 연결을 쓰게 되는 실수를 타입이 막지 못한다.

트랜잭션 안에서 HTTP 호출·큐 발행을 하지 않는다. 롤백돼도 그 부수효과는 되돌아오지 않고,
외부 응답을 기다리는 동안 락만 길어진다. 커밋 뒤에 한다.

## 8. 마이그레이션 실행 (`prisma/migrations/`)

| 상황 | 명령 | 비고 |
| --- | --- | --- |
| 개발 중 스키마 변경 | `npx prisma migrate dev --name <변경>` | SQL 파일 생성 + 적용 + `generate`까지 한다 |
| 배포 | `npx prisma migrate deploy` | **애플리케이션 부팅과 분리된 단계로** 돌린다 |
| 클라이언트 타입만 재생성 | `npx prisma generate` | 스키마를 바꾼 뒤 타입이 안 맞으면 이것부터 |

**실행 확인**: `migrate dev --name init`이 `prisma/migrations/<타임스탬프>_init/migration.sql`을
만들고 적용한 뒤 클라이언트를 재생성했다.

부팅에서 `migrate deploy`를 부르지 않는다. 인스턴스가 여러 개 동시에 뜨면 같은 마이그레이션을
경합해서 적용하고, 실패한 마이그레이션이 앱을 부팅 불가 상태로 만든다. `db push`는 마이그레이션
파일을 남기지 않으므로 공유 환경에서 쓰지 않는다 — 되돌릴 기록이 없다.

## 오용 목록 ① — 구 Prisma 관용구 → Prisma 6 대조표

| 구 습관 | 현재 형태 (Prisma 6) |
| --- | --- |
| `prisma.$use(middleware)`로 쿼리 가로채기 <!-- verified: Prisma 6.19.3 실행 — typeof prisma.$use === 'undefined' --> | `$use`가 없다. `prisma.$extends({ query: … })`를 쓴다 |
| `findFirst({ …, rejectOnNotFound: true })` <!-- verified: Prisma 6.19.3 실행 — PrismaClientValidationError --> | 옵션이 제거됐다. `findFirstOrThrow` / `findUniqueOrThrow` |
| `datasources: { db: { url } }` <!-- verified: Prisma 6.19.3 실행 — 구 형태로도 쿼리가 돌았다 --> | `datasourceUrl: url` 한 줄로 쓴다 (구 형태도 아직 동작한다) |
| 문자열을 만들어 `$queryRawUnsafe`에 넘기기 | 태그드 템플릿 `$queryRaw` — 값이 파라미터로 바인딩된다. 실측: `ownerId`에 `alice' OR '1'='1`을 넣어도 0행 |
| `findUnique({ where: { id } })` 후 `if (row.ownerId !== me)` | 소유권을 `where`에 넣는다. <!-- verified: Prisma 6.19.3 실행 — SQL에 ownerId 조건이 실렸고 결과가 null --> 확장 whereUnique로 `findUnique({ where: { id, ownerId } })`도 되지만, 이 팩은 `findFirst`로 통일한다 |
| `skip: (page - 1) * size`로 페이지 이동 | 커서 페이지네이션 (`cursor` + `skip: 1`) |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `updateMany` vs `update` | 소유권 필터가 있으면 둘 다 안전하다. 차이는 실패 신호 — `updateMany`는 `{ count: 0 }`로 조용하고 `update`는 `P2025`를 던진다. `count`를 안 볼 거면 `updateMany`를 쓰지 않는다 |
| `findFirst` vs `findUnique` | 비유일 조건(`ownerId`)만으로 찾을 땐 `findFirst`. `findUnique`의 `where`는 유일 키를 **반드시** 포함해야 한다 (타입 확인: `{ id: string } & TaskWhereInput`) |
| `select` vs `include` | 열을 좁히려면 `select`. `include`는 본체 전 열 + 관계라서 비밀 열이 딸려 온다 |
| `$transaction([...])` vs `$transaction(async tx => …)` | 앞은 서로 의존 없는 쿼리 묶음(순차 실행·한 트랜잭션). 중간 결과로 다음 쿼리를 정해야 하면 뒤 |
| `count` vs `_count` | 행 수만 세면 `prisma.task.count()`. 부모 행마다 관계 개수를 붙이려면 `select: { _count: … }` |
| `upsert` vs `create` 후 `P2002` 처리 | 유일 제약이 있고 "있으면 갱신"이 의도면 `upsert`. 중복을 **오류로 알려야** 하면 `create` + `isUniqueViolation` |
| `deleteMany({})` vs 개별 삭제 | 빈 `where`는 테이블 전체를 지운다. 테스트 정리(`resetDb`) 외에는 쓰지 않는다 |
