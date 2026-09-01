<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 데이터 모델링 — 엔티티·연결·마이그레이션

이 파일은 **테이블 매핑과 연결 조립**을 소유한다. 쿼리 작성은 `data-access.md`가,
운영 시점의 마이그레이션 배포 순서는 `operations.md` §7이 소유한다.

## 1. 열을 정할 때 무엇을 먼저 보는가

| 결정 | 기준 | 이 팩의 값 |
| --- | --- | --- |
| 기본 키 | 외부에 노출되는가 | `uuid` — 순번은 총량과 생성 속도를 누설한다 |
| 상태 열 | 값 집합이 닫혀 있는가 | `text` + CHECK 제약. PostgreSQL `enum` 타입은 값 추가에 DDL이 든다 |
| 시각 열 | 커서·정렬에 쓰는가 | `timestamptz` + **`precision: 3`** (§2) |
| 소유자 열 | 행이 사용자에게 묶이는가 | `ownerId uuid` + 복합 인덱스의 **첫 열** |
| 고유 제약 | 중복이 도메인 오류인가 | `(ownerId, title)` — 전역 고유는 남의 데이터를 누설한다 |

**고유 제약을 전역으로 걸지 않는다.** `UNIQUE(title)`이면 다른 사용자가 같은 제목을 쓸 때
409가 나가고, 그것으로 **남이 그 제목을 쓰고 있다는 사실**이 새어 나간다. 소유자와 묶는다.

## 2. 엔티티 (`src/tasks/task.entity.ts`)

<!-- file: src/tasks/task.entity.ts -->
```ts
import { Column, CreateDateColumn, Entity, Index, PrimaryGeneratedColumn, UpdateDateColumn } from 'typeorm';

export type TaskStatus = 'open' | 'done';

@Entity({ name: 'tasks' })
@Index('IDX_tasks_owner_created', ['ownerId', 'createdAt', 'id'])
export class Task {
  @PrimaryGeneratedColumn('uuid')
  id!: string;

  @Column({ type: 'text' })
  title!: string;

  @Column({ type: 'text', default: 'open' })
  status!: TaskStatus;

  @Column({ type: 'uuid' })
  ownerId!: string;

  @CreateDateColumn({ type: 'timestamptz', precision: 3 })
  createdAt!: Date;

  @UpdateDateColumn({ type: 'timestamptz', precision: 3 })
  updatedAt!: Date;
}
```

**`precision: 3`이 이 파일에서 가장 중요한 한 글자다.**
<!-- verified: PostgreSQL 18.4 + typeorm@1.1.0 실행 — precision 미지정(µs 저장) 상태에서 커서를 toISOString()으로 왕복시키자 5행 중 1행이 조회에서 누락됐고, precision: 3 으로 바꾼 뒤 같은 시나리오가 5행을 완주했다 -->
`timestamptz`는 마이크로초까지 저장하는데 JavaScript `Date`는 밀리초까지만 표현한다.
커서를 ISO 문자열로 실어 보내면 그 왕복에서 마이크로초가 잘리고, 잘린 값으로
`LessThan`을 걸면 **잘린 구간에 있는 행이 통째로 건너뛰어진다.** 컬럼 정밀도를 언어의
해상도에 맞추면 그 격차 자체가 사라진다.

필드에 `!`를 붙이는 것은 TypeScript의 확정 대입 단언이다 — 값을 채우는 주체가 ORM이라
컴파일러가 초기화를 볼 수 없다. `strictPropertyInitialization`을 끄는 것보다 좁은 처방이다.

`@Index`의 열 순서 `['ownerId', 'createdAt', 'id']`는 §5의 목록 쿼리와 **같은 순서**여야
한다. 소유자 필터가 앞에 오지 않으면 인덱스가 쓰이지 않는다.

## 3. 조회 형태 (`src/tasks/task.view.ts`)

<!-- file: src/tasks/task.view.ts -->
```ts
import { FindOptionsSelect } from 'typeorm';
import { Task } from './task.entity';

export type TaskView = Pick<Task, 'id' | 'title' | 'status' | 'createdAt'>;

export const TASK_VIEW: FindOptionsSelect<Task> = {
  id: true,
  title: true,
  status: true,
  createdAt: true,
};
```

**타입과 `select` 값을 한 파일에 두는 이유**: 둘이 갈리면 컴파일은 통과하고 런타임 값만
빈다. `TaskView`에 `updatedAt`을 추가하고 `TASK_VIEW`를 잊으면, 그 필드는 타입상 존재하고
값은 `undefined`인 채 응답 봉투에 실린다. 같은 화면에 두면 한쪽만 고치기 어렵다.

`ownerId`를 담지 않는 것도 계약이다 — 응답에 소유자 id가 실리면 그 자체가 내부 식별자
누출이고, 클라이언트가 그것으로 접근 제어를 흉내 내기 시작한다.

## 4. 연결 조립 (`src/database/data-source.ts`)

<!-- file: src/database/data-source.ts -->
```ts
import 'reflect-metadata';
import { DataSource, DataSourceOptions } from 'typeorm';
import { EnvVars, validateEnv } from '../config/env';
import { SlowQueryLogger } from '../ops/logging';
import { Task } from '../tasks/task.entity';

type DbEnv = Pick<EnvVars, 'DATABASE_URL' | 'DB_SCHEMA' | 'DB_POOL_MAX' | 'DB_SLOW_QUERY_MS'>;

export function buildDataSourceOptions(env: DbEnv): DataSourceOptions {
  return {
    type: 'postgres',
    url: env.DATABASE_URL,
    schema: env.DB_SCHEMA,
    entities: [Task],
    migrations: [`${__dirname}/migrations/*.{ts,js}`],
    synchronize: false,
    migrationsRun: false,
    extra: { max: env.DB_POOL_MAX },
    maxQueryExecutionTime: env.DB_SLOW_QUERY_MS,
    logger: new SlowQueryLogger(),
  };
}

export const dataSource = new DataSource(buildDataSourceOptions(validateEnv(process.env)));
```

**한 함수가 앱과 CLI 양쪽에 쓰인다.** 앱은 `AppModule`이 `ConfigService`에서 값을 꺼내
이 함수를 부르고, TypeORM CLI는 파일 끝의 `dataSource`를 직접 읽는다. 옵션이 갈리면
"마이그레이션은 통과했는데 앱이 다른 스키마를 본다" 같은 어긋남이 난다.

| 옵션 | 값 | 왜 |
| --- | --- | --- |
| `synchronize` | `false` | 켜면 배포마다 예고 없는 DDL이 돈다. 열 삭제가 곧 데이터 삭제다 |
| `migrationsRun` | `false` | 부팅과 마이그레이션을 분리한다 (`operations.md` §7) |
| `schema` | `env.DB_SCHEMA` | 테스트가 워커별 스키마로 격리하는 지점 (`testing.md` §3) |
| `extra.max` | `env.DB_POOL_MAX` | pg 풀 상한. 인스턴스 수 × 이 값이 서버 상한을 넘으면 안 된다 |
| `maxQueryExecutionTime` | `env.DB_SLOW_QUERY_MS` | 이 값을 넘긴 쿼리가 `SlowQueryLogger.logQuerySlow`로 온다 |

`reflect-metadata`가 이 파일 첫 줄에도 있는 것은 **진입점이 둘이기 때문이다** — CLI는
`main.ts`를 거치지 않고 이 파일을 직접 로드한다.

## 5. 마이그레이션 (`src/database/migrations/`)

<!-- file: src/database/migrations/1756000000000-CreateTasks.ts -->
```ts
import { MigrationInterface, QueryRunner, Table, TableIndex } from 'typeorm';

export class CreateTasks1756000000000 implements MigrationInterface {
  async up(q: QueryRunner): Promise<void> {
    await q.createTable(
      new Table({
        name: 'tasks',
        columns: [
          { name: 'id', type: 'uuid', isPrimary: true, default: 'gen_random_uuid()' },
          { name: 'title', type: 'text' },
          { name: 'status', type: 'text', default: "'open'" },
          { name: 'ownerId', type: 'uuid' },
          { name: 'createdAt', type: 'timestamptz', precision: 3, default: 'now()' },
          { name: 'updatedAt', type: 'timestamptz', precision: 3, default: 'now()' },
        ],
        checks: [{ name: 'CHK_tasks_status', expression: `"status" IN ('open','done')` }],
        uniques: [{ name: 'UQ_tasks_owner_title', columnNames: ['ownerId', 'title'] }],
      }),
      true,
    );
    await q.createIndex(
      'tasks',
      new TableIndex({ name: 'IDX_tasks_owner_created', columnNames: ['ownerId', 'createdAt', 'id'] }),
    );
  }

  async down(q: QueryRunner): Promise<void> {
    await q.dropTable('tasks', true);
  }
}
```

<!-- verified: PostgreSQL 18.4 실행 — migration:run 이 테이블·CHECK·UNIQUE·인덱스를 만들었고, 테스트 하네스가 격리 스키마에 같은 마이그레이션을 다시 돌려 통과했다 -->
**`QueryRunner`의 DDL API를 쓰고 원시 SQL을 쓰지 않는다.** `q.query('CREATE TABLE ...')`은
문자열이라 스키마를 인식하지 못한다 — 격리된 스키마로 붙은 연결에서도 `search_path`가
가리키는 곳(대개 `public`)에 테이블을 만든다. `createTable`은 DataSource의 `schema`
설정을 그대로 따르므로 **같은 마이그레이션이 운영 스키마와 테스트 스키마 양쪽에서 성립한다.**

실행은 두 명령이다. 앞이 적용, 뒤가 되돌림이다.

```bash
npx typeorm-ts-node-commonjs migration:run -d src/database/data-source.ts
npx typeorm-ts-node-commonjs migration:revert -d src/database/data-source.ts
```

`down`을 비워 두지 않는다. 되돌릴 수 없는 마이그레이션은 배포 중 문제가 났을 때
**앞으로 가는 것 말고 선택지가 없게** 만든다.

## 6. 스키마를 바꿀 때의 순서

파괴적 변경은 한 번에 하지 않는다. 배포와 마이그레이션이 원자적이지 않아 새 코드와 옛
코드가 잠시 함께 돌기 때문이다.

| 하려는 것 | 안전한 순서 |
| --- | --- |
| 열 추가 | NULL 허용으로 추가 → 코드 배포 → 백필 → NOT NULL |
| 열 삭제 | 코드에서 사용 제거 → 배포 → 다음 릴리스에서 DROP |
| 열 이름 변경 | 새 열 추가 → 양쪽 쓰기 → 백필 → 읽기 전환 → 옛 열 삭제 |
| 제약 추가 | 위반 행 정리 → `NOT VALID`로 추가 → `VALIDATE` |

## 오용 목록 ① — TypeORM 0.2/0.3 관용구 → 1.x 형태 대조표

<!-- verified: typeorm@1.1.0 런타임 export 목록 확인 — Connection·createConnection·getRepository·getManager 가 없다 -->

| 구 습관 (0.2~0.3) | 현재 형태 (TypeORM 1.x) |
| --- | --- |
| `createConnection()` · `getConnection()` | `new DataSource(options)` + `initialize()`. Nest에서는 `TypeOrmModule`이 대신한다 |
| 전역 `getRepository(Task)` | `@InjectRepository(Task)` 또는 `dataSource.getRepository(Task)` |
| `getManager().transaction(...)` | `dataSource.transaction(...)` |
| `ormconfig.json` | 코드로 조립한 `DataSourceOptions` — 타입 검사를 받는다 |
| `repo.update({}, patch)`로 전체 갱신 | `repo.updateAll(patch)` — **이름이 경고다.** 이 축에는 쓸 자리가 없다 |
| `@Column({ type: 'timestamp' })` | `timestamptz` + `precision: 3`. 타임존 없는 시각은 배포 지역이 바뀌면 의미가 바뀐다 |
| `synchronize: true`로 개발 | 처음부터 마이그레이션. 개발 스키마와 운영 스키마가 갈리는 것을 막는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `@CreateDateColumn` vs `@Column({ default: 'now()' })` | 전자는 ORM이 값을 넣고 후자는 DB가 넣는다. ORM을 거치지 않는 경로(마이그레이션·수동 SQL)가 있으면 후자만 신뢰할 수 있다 |
| `@PrimaryGeneratedColumn('uuid')` vs `@PrimaryColumn` | 전자는 DB가 생성한다. 애플리케이션이 id를 만들어야 하면(멱등 생성) 후자 |
| CHECK 제약 vs DTO 검증 | 둘 다 건다. DTO는 400을 주고 CHECK는 우회 경로를 막는다 |
| `nullable: true` vs 기본값 | "값이 없다"와 "아직 정하지 않았다"가 다른 의미면 NULL, 아니면 기본값 |
| 인덱스 `['ownerId','createdAt']` vs `['createdAt','ownerId']` | 필터가 앞, 정렬이 뒤. 순서를 바꾸면 소유자 필터에 인덱스가 쓰이지 않는다 |
