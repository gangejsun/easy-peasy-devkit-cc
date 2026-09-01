<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 데이터 액세스 — 소유권은 조회 조건이다

이 파일은 **쿼리와 그 안전성**을 소유한다. 테이블 정의와 연결 옵션은 `data-modeling.md`,
요청 형태는 `input-validation.md`, 실패의 상태 코드는 `error-handling.md`가 소유한다.

이 축에는 **행 수준 정책 엔진이 없다.** 애플리케이션이 신뢰된 연결로 DB에 붙으므로
소유권 필터를 빠뜨린 쿼리는 느려지는 것이 아니라 **남의 행을 돌려준다.**

## 1. 어떤 조회 API를 고르는가

| 필요 | 메서드 | 주의 |
| --- | --- | --- |
| 목록 | `find({ where, select, order, take })` | `where`가 배열이면 **OR**다 (§3) |
| 단건 | `findOne({ where, select })` | 없으면 `null`. `findOneOrFail`은 예외를 던진다 |
| 존재 확인 | `existsBy(where)` | 행을 가져오지 않는다 |
| 개수 | `countBy(where)` | 목록과 함께면 `findAndCount` |
| 생성 | `create(...)` → `save(...)` | `create`는 **메모리 인스턴스만** 만든다. `save`가 INSERT다 |
| 부분 수정 | `update(where, patch)` | 엔티티를 불러오지 않는다. `affected`를 본다 (§4) |
| 삭제 | `delete(where)` | 같다 |

`save(entity)`는 id가 있으면 UPDATE, 없으면 INSERT다 — **소유권 검사가 붙지 않는다.**
그래서 이 팩의 수정·삭제는 전부 `update`/`delete` + `where`이고, `save`는 생성에만 쓴다.

## 2. Repository는 DI로만 얻는다 (`src/tasks/tasks.service.ts`)

<!-- file: src/tasks/tasks.service.ts -->
```ts
import { Injectable } from '@nestjs/common';
import { InjectRepository } from '@nestjs/typeorm';
import { DataSource, FindOptionsWhere, In, LessThan, Repository } from 'typeorm';
import { AppError } from '../common/app-error';
import { decodeCursor } from './cursor';
import { CreateTaskDto } from './dto/create-task.dto';
import { ListTasksQueryDto } from './dto/list-tasks.query.dto';
import { UpdateTaskDto } from './dto/update-task.dto';
import { Task } from './task.entity';
import { TASK_VIEW, TaskView } from './task.view';

@Injectable()
export class TasksService {
  constructor(
    @InjectRepository(Task) private readonly tasks: Repository<Task>,
    private readonly dataSource: DataSource,
  ) {}

  async list(ownerId: string, q: ListTasksQueryDto): Promise<TaskView[]> {
    const base: FindOptionsWhere<Task> = { ownerId, ...(q.status ? { status: q.status } : {}) };
    let where: FindOptionsWhere<Task>[] = [base];
    if (q.cursor) {
      const c = decodeCursor(q.cursor);
      where = [
        { ...base, createdAt: LessThan(c.createdAt) },
        { ...base, createdAt: c.createdAt, id: LessThan(c.id) },
      ];
    }
    return this.tasks.find({
      where,
      select: TASK_VIEW,
      order: { createdAt: 'DESC', id: 'DESC' },
      take: q.limit,
    });
  }

  async get(ownerId: string, id: string): Promise<TaskView | null> {
    return this.tasks.findOne({ where: { id, ownerId }, select: TASK_VIEW });
  }

  async create(ownerId: string, dto: CreateTaskDto): Promise<TaskView> {
    const saved = await this.tasks.save(this.tasks.create({ ...dto, ownerId }));
    return { id: saved.id, title: saved.title, status: saved.status, createdAt: saved.createdAt };
  }

  async update(ownerId: string, id: string, patch: UpdateTaskDto): Promise<TaskView> {
    const res = await this.tasks.update({ id, ownerId }, patch);
    if (res.affected === 0) throw new AppError('NOT_FOUND', '작업을 찾지 못했다');
    const after = await this.get(ownerId, id);
    if (!after) throw new AppError('NOT_FOUND', '작업을 찾지 못했다');
    return after;
  }

  async remove(ownerId: string, id: string): Promise<void> {
    const res = await this.tasks.delete({ id, ownerId });
    if (res.affected === 0) throw new AppError('NOT_FOUND', '작업을 찾지 못했다');
  }

  async closeAll(ownerId: string, ids: string[]): Promise<number> {
    return this.dataSource.transaction(async (manager) => {
      const res = await manager.getRepository(Task).update({ id: In(ids), ownerId }, { status: 'done' });
      if (res.affected !== ids.length) throw new AppError('NOT_FOUND', '일부 작업을 찾지 못했다');
      return res.affected ?? 0;
    });
  }
}
```

`@InjectRepository(Task)`가 유일한 조달 경로다. 서비스가 스스로
`dataSource.getRepository(Task)`를 필드에 만들면 **테스트에서 대역을 끼울 자리가
사라진다** — `getRepositoryToken(Task)`로 override할 대상이 없어지기 때문이다
(`testing.md` §2). 예외는 트랜잭션 안이고, 그 이유는 §7에 있다.

**서비스는 `Request`·`Response`를 받지 않는다.** 첫 인자가 언제나 `ownerId`인 것은
관례가 아니라 계약이다 — 호출자가 주체를 꺼내 넘기지 않으면 컴파일되지 않는다.

## 3. `where`가 배열이면 OR다 — 분기마다 소유권을 반복한다

<!-- verified: typeorm@1.1.0 + PostgreSQL 18.4 실행 — 아래 ❌ 형태로 조회하자 다른 소유자(B)의 행이 결과에 섞여 총 8행이 나왔다 -->
목록에서 소유자 A의 행이 5건, B의 행이 3건인 상태로 확인한 결과다.

```ts
// src/tasks/tasks.service.ts
// ❌ 두 번째 분기에 ownerId가 없다 — 그 분기가 남의 행을 통째로 통과시킨다
const leaked = await this.tasks.find({
  where: [{ ownerId, createdAt: LessThan(c.createdAt) }, { status: 'open' }],
});
// ✅ 분기마다 소유권을 반복한다 (base를 펼쳐 넣는 것이 그 장치다)
const rows = await this.tasks.find({
  where: [{ ...base, createdAt: LessThan(c.createdAt) }, { ...base, createdAt: c.createdAt, id: LessThan(c.id) }],
});
```

**정책 정규식은 이 결함을 잡지 못한다.** `ownership-in-query`는 「`where`에 `ownerId`가
한 번이라도 있는가」만 보므로 위 ❌도 통과한다. 그래서 `policies.md`가 이 항목을
「사람이 지킬 것」에 올려 두었다 — 기계가 못 보는 자리를 아는 것이 그 목록의 목적이다.

## 4. 변이는 영향 행 수를 확인한다

<!-- verified: typeorm@1.1.0 + PostgreSQL 18.4 실행 — 타인 소유 행에 update를 걸자 affected = 0 이 돌아왔고 예외 없이 성공했다 -->
소유권 필터가 걸린 `update`·`delete`는 **남의 행에 대해 조용히 성공한다.** 바뀐 행이
없을 뿐 오류가 아니다. 확인하지 않으면 200이 나가고 클라이언트는 수정됐다고 믿는다.

```ts
// src/tasks/tasks.service.ts
// ❌ 성공으로 읽는다 — 남의 행이면 아무것도 바뀌지 않았는데 200이 나간다
await this.tasks.update({ id, ownerId }, patch);
// ✅ 영향 행 수가 곧 존재·소유 판정이다
const res = await this.tasks.update({ id, ownerId }, patch);
if (res.affected === 0) throw new AppError('NOT_FOUND', '작업을 찾지 못했다');
```

`UpdateResult.affected`는 `number | undefined`, `DeleteResult.affected`는
`number | null | undefined`다 — `=== 0` 비교가 안전한 형태인 이유다. `> 0`으로 쓰면
`undefined`가 실패로 읽혀 정상 변이가 404가 된다.

**404이지 403이 아니다.** 남의 행을 가리키는 요청에 403을 주면 id를 훑어 리소스 존재를
열거할 수 있다 (`error-handling.md` §5).

## 5. 커서 페이지네이션

<!-- verified: PostgreSQL 18.4 실행 — 5행을 limit 2로 3회 넘겨 5행을 정확히 완주했고, 같은 시각을 가진 두 행이 id 역순으로 안정 정렬됐다 -->
오프셋 페이지네이션은 앞 페이지에 삽입·삭제가 일어나면 행을 건너뛰거나 중복해서 준다.
커서는 "마지막으로 본 행"을 기준으로 삼아 그 문제가 없다.

```ts
// src/tasks/cursor.ts — 정렬 키 전부를 커서에 싣는다
// (createdAt만 실으면 같은 시각의 행에서 순서가 무너진다)
const where = [
  { ...base, createdAt: LessThan(c.createdAt) },
  { ...base, createdAt: c.createdAt, id: LessThan(c.id) },
];
```

정렬은 `order: { createdAt: 'DESC', id: 'DESC' }`로 **커서의 두 열과 같은 순서**여야
한다. 하나라도 어긋나면 페이지 경계에서 행이 새거나 중복된다.

<!-- file: src/tasks/cursor.ts -->
```ts
import { AppError } from '../common/app-error';
import { TaskView } from './task.view';

export function encodeCursor(t: TaskView): string {
  return Buffer.from(`${t.createdAt.toISOString()}|${t.id}`, 'utf8').toString('base64url');
}

export function decodeCursor(raw: string): { createdAt: Date; id: string } {
  const [ts, id] = Buffer.from(raw, 'base64url').toString('utf8').split('|');
  const createdAt = new Date(ts ?? '');
  if (!id || Number.isNaN(createdAt.getTime())) {
    throw new AppError('VALIDATION_FAILED', '커서 형식이 올바르지 않다', { cursor: ['형식이 올바르지 않다'] });
  }
  return { createdAt, id };
}
```

**시각 정밀도가 여기서 문제가 된다.** `toISOString()`은 밀리초까지만 쓰므로 컬럼이
마이크로초를 저장하면 왕복에서 값이 잘리고 그 구간의 행이 건너뛰어진다. 처방은 커서
쪽이 아니라 컬럼 쪽이다 — `data-modeling.md` §2의 `precision: 3`이 그것이다.

## 6. `select`는 값만 좁힌다 — 타입은 그대로다

<!-- verified: typeorm@1.1.0 실행 — select: TASK_VIEW 로 가져온 객체에 ownerId 키는 존재했고 값은 undefined 였다 -->

```ts
// src/tasks/tasks.service.ts
// ❌ 컴파일된다. 런타임 값은 undefined다 — 봉투에 실리면 조용히 틀린 응답이 된다
const t = await this.tasks.findOne({ where: { id, ownerId }, select: TASK_VIEW });
return { owner: t!.ownerId };
// ✅ 반환 타입을 TaskView로 명시한다 — 선택하지 않은 열에 손대면 컴파일이 막는다
async get(ownerId: string, id: string): Promise<TaskView | null> { /* ... */ }
```

TypeORM은 `select`로 좁힌 결과에도 엔티티 타입을 그대로 준다. **타입 시스템이 이
좁힘을 모른다**는 것이 이 축에서 가장 조용한 함정이고, 유일한 방어는 서비스 메서드의
반환 타입을 `TaskView`로 못박는 것이다.

## 7. 트랜잭션 경계

```ts
// src/tasks/tasks.service.ts
// ✅ 트랜잭션 안에서는 manager가 주는 Repository를 쓴다 — 주입받은 것은 그 트랜잭션 밖이다
return this.dataSource.transaction(async (manager) => {
  const res = await manager.getRepository(Task).update({ id: In(ids), ownerId }, { status: 'done' });
  if (res.affected !== ids.length) throw new AppError('NOT_FOUND', '일부 작업을 찾지 못했다');
  return res.affected ?? 0;
});
```

**주입받은 Repository를 트랜잭션 안에서 쓰면 그 쿼리는 트랜잭션 밖에서 돈다** — 롤백돼도
남는다. 이것이 §2의 "Repository는 DI로만"에 예외가 있는 유일한 자리다.

트랜잭션 안에서 **외부 호출(HTTP·큐·메일)을 하지 않는다.** 롤백되지 않고, 락만 길어진다.
바깥에서 커밋을 확인한 뒤에 부른다.

## 오용 목록 ① — Prisma/ActiveRecord 관용구 → TypeORM 1.x 형태 대조표

이 축에 오는 사람의 절반은 다른 ORM에서 온다. 이름이 비슷하고 의미가 다른 것만 싣는다.

| 구 습관 | 현재 형태 (TypeORM 1.x) |
| --- | --- |
| `prisma.task.findUnique({ where: { id } })` | `findOne({ where: { id, ownerId } })` — 유니크 여부와 무관하게 조건을 더 걸 수 있다 |
| `findMany({ where: { OR: [...] } })` | `find({ where: [ ... ] })` — **배열 자체가 OR**다 |
| `update({ where, data })`가 없으면 예외 | `update(where, patch)`는 예외를 던지지 않는다. `affected`를 본다 |
| `select: { id: true }`가 타입을 좁힌다 | 좁히지 않는다. 반환 타입을 손으로 명시한다 (§6) |
| `take`/`skip`으로 페이지 | `skip`은 오프셋이다. 이 팩은 커서를 쓴다 (§5) |
| `$transaction([...])` 배열 | `dataSource.transaction(async (manager) => ...)` — 콜백 안에서 `manager` 사용 |
| `task.save()` (ActiveRecord) | `repo.save(task)`. 엔티티에 메서드를 달지 않는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `create()` vs `save()` | `create`는 인스턴스만 만든다(쿼리 없음). DB에 넣는 것은 `save` |
| `save()` vs `update()` | 수정에 `save`를 쓰면 소유권 조건을 걸 자리가 없다. 부분 수정은 언제나 `update(where, patch)` |
| `findOne` vs `findOneOrFail` | 후자는 `EntityNotFoundError`를 던진다 — 그 예외를 그대로 두면 500이 나간다. 이 팩은 `findOne` + `null` 판정으로 통일한다 |
| `where: { a, b }` vs `where: [{ a }, { b }]` | 앞은 AND, 뒤는 OR. 실수하면 소유권이 통째로 무력해진다 |
| `In([])` (빈 배열) | 빈 배열이면 아무 행도 매치되지 않는다. 호출 전에 길이를 확인한다 |
| `delete()` vs `softDelete()` | 후자는 `@DeleteDateColumn`이 있어야 한다. 없으면 열이 없어 쿼리가 실패한다 |
