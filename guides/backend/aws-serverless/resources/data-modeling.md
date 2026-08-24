<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# 데이터 모델링 — 접근 패턴이 키를 정한다

이 파일은 **테이블 하나의 형태**를 소유한다: 접근 패턴 목록 · PK/SK 조합 · GSI 선택 ·
아이템 타입(`Task`) · 키 조립기(`keys`) · 테이블 이름(`TABLE`). 즉 `src/keys.ts` 전체다.
쿼리·쓰기 명령은 `resources/data-access.md`가, 테이블을 만드는 CDK 구성(`TaskTable`)과
GSI 프로비저닝은 `resources/deploy-and-iam.md`가 소유한다.

T1 데이터 모델링 카드는 이 축에서 **휴면한다** — 그 카드는 정규화·외래 키를 전제하고
`paths:`도 이 스택에 매칭되지 않는다. 단일 테이블 설계는 이 파일이 직접 쓴다.

## 1. 판단 — 접근 패턴 표를 먼저 채운다

관계형은 엔티티 → 정규화 → 쿼리 순으로 간다. DynamoDB는 **반대**다: 질의 목록을 먼저
적고, 그 목록이 키를 정하고, 키가 아이템 형태를 정한다. 순서를 뒤집으면 나중에
"이 질의는 Scan 말고는 방법이 없다"는 자리에 도착한다 — 그때는 마이그레이션이다.

**설계 전에 이 표를 채운다.** 빈 칸이 있으면 아직 키를 정하면 안 된다.

| # | 접근 패턴 | 질의 형태 | 인덱스 |
| --- | --- | --- | --- |
| AP1 | 소유자의 작업 한 건을 읽는다 | `GetItem(pk, sk)` | 기본 테이블 |
| AP2 | 소유자의 작업 전체를 최신순으로 | `pk = :pk AND begins_with(sk, 'TASK#')` | 기본 테이블 |
| AP3 | 소유자의 작업 중 상태별로 최신순 | `gsi1pk = :g` | GSI1 |
| AP4 | 작업을 만든다 (덮어쓰기 없이) | `PutItem` + `attribute_not_exists` | 기본 테이블 |
| AP5 | 작업을 고치거나 지운다 (내 것만) | `Update/DeleteItem(pk, sk)` + `attribute_exists` | 기본 테이블 |

세 판정 기준이 표를 채운다.

| 물음 | 답이 "예"라면 |
| --- | --- |
| 질의에 **등호로 고정되는 값**이 있는가 | 그 값이 파티션 키다 (여기서는 소유자) |
| 결과에 **순서**가 필요한가 | 정렬 키가 그 순서를 만들어야 한다 |
| 파티션 키가 **다른 값**이어야 하는 질의가 있는가 | GSI를 하나 더 만든다 |

## 2. 단일 테이블과 키 조립 (`src/keys.ts`)

테이블은 하나다. 아이템 종류는 `pk`/`sk` 접두사로 구분한다. **키 문자열을 만드는 자리는
이 파일 하나뿐이다** — 접두사가 두 곳에서 조립되면 한쪽만 고쳤을 때 조용히 갈라진다.

아이템 타입도 여기 산다. DynamoDB에는 스키마도 코드 생성도 없으므로 `pk`·`sk`·`gsi1pk`는
**아이템의 보통 속성**이고, 타입과 조립기가 같은 파일에 있어야 속성 이름이 한 곳에서만 정해진다.

<!-- file: src/keys.ts -->
```ts
// src/keys.ts
import { randomUUID } from 'node:crypto';
import { env } from './env';
import type { TaskStatus } from './schemas/task';

/** 단일 테이블 이름. 프로세스 환경은 `src/env.ts`만 읽는다. */
export const TABLE: string = env.TABLE_NAME;

/** 키 속성이 아이템 안에 산다 — 별도의 키 객체가 없다. */
export type Task = {
  pk: string; sk: string;
  id: string; title: string; status: TaskStatus;
  ownerId: string; createdAt: string;
  gsi1pk?: string; gsi1sk?: string;   // 희소 GSI — 없는 아이템은 색인되지 않는다
};

const owner = (ownerId: string) => `USER#${ownerId}`;
const item = (id: string) => `TASK#${id}`;

/** 키 조립은 여기 한 곳에서만. 소유자가 먼저다. */
export const keys = {
  task: (ownerId: string, id: string) => ({ pk: owner(ownerId), sk: item(id) }),
  taskList: (ownerId: string) => ({ pk: owner(ownerId), skPrefix: 'TASK#' }),
  taskGsi1: (ownerId: string, status: TaskStatus, id: string) => ({
    gsi1pk: `${owner(ownerId)}#STATUS#${status}`,
    gsi1sk: item(id),
  }),
  statusList: (ownerId: string, status: TaskStatus) => ({
    gsi1pk: `${owner(ownerId)}#STATUS#${status}`,
  }),
  /** 시간 순서를 갖는 id — 아래 3절. */
  newId: (): string =>
    Date.now().toString(16).padStart(12, '0') + randomUUID().replaceAll('-', '').slice(0, 16),
};
```

`taskList`가 `skPrefix`를 돌려주는 것이 핵심이다. 목록 질의는 **파티션 키 등호 + 정렬 키
접두사**로 성립하고, 둘 다 `KeyConditionExpression`에 들어간다 — 읽은 뒤에 거르는 필터가 아니다.

## 3. 정렬은 SK가 정한다 — id 생성이 모델링 결정이다

`keys.task(ownerId, id)`가 `id` 하나로 `sk`를 만들 수 있어야 `GetItem`이 성립한다.
그래서 `sk = TASK#<id>`이고, **목록의 순서는 곧 `id`의 사전순**이 된다.
여기에 무작위 UUID를 쓰면 목록은 UUID 순으로 나온다 — 사람이 읽을 수 없는 순서다.

`newId()`는 앞 12자리를 밀리초 타임스탬프(hex)로, 뒤 16자리를 난수로 만든다.
사전순 = 시간순이 되고, `ScanIndexForward: false` 하나로 최신순 목록이 나온다.

| 측정 | 결과 |
| --- | --- |
| 길이·문자 집합 | 28자, 소문자 hex만 — URL 경로에 그대로 쓴다 <!-- verified: node v24.7.0, 20만 회 생성 --> |
| 20만 개 생성 충돌 | 0건 (같은 밀리초 다수 포함) <!-- verified: 실행 확인 — 난수 64비트 --> |
| 사전순 정렬 = 시간 접두사 순 | 참 <!-- verified: 실행 확인 --> |
| 5ms 뒤 생성한 id가 사전순으로 더 큼 | 참 (`01a02e21054d` < `01a02e210554`) <!-- verified: 실행 확인 --> |

밀리초 타임스탬프는 12자리 hex로 서기 10000년대까지 자리가 남는다. `padStart(12, '0')`이
없으면 자릿수가 바뀌는 순간 사전순이 무너진다 — 그래서 패딩이 장식이 아니다.

## 4. GSI 선택 — 파티션 키가 달라야 할 때만 만든다

GSI는 **아이템 사본**이다. 쓰기가 두 번 일어나고 저장도 두 배다. 그러므로 판정은 하나다:
**기본 테이블의 파티션 키로는 그 질의를 등호로 고정할 수 없는가.**

여기서는 AP3("내 작업 중 `open`만 최신순")이 그렇다. 기본 테이블의 파티션은 소유자
하나뿐이라 상태를 등호로 잡을 수 없다. 그래서 GSI1을 **상태까지 파티션에 넣어** 만든다.

| | 파티션 키 | 정렬 키 |
| --- | --- | --- |
| 기본 테이블 | `USER#<ownerId>` | `TASK#<id>` |
| GSI1 | `USER#<ownerId>#STATUS#<status>` | `TASK#<id>` |

`gsi1sk`가 기본 테이블의 `sk`와 같은 값인 것이 의도다 — 두 인덱스의 정렬이 같아야
"최신순"의 뜻이 자리마다 달라지지 않는다.

**상태가 바뀌면 아이템은 GSI 파티션을 옮겨 간다.** 그 이동은 자동이 아니라 `gsi1pk`를
같이 갱신해야 일어난다 (`resources/data-access.md`의 `updateTask`). 갱신을 빠뜨리면
`done`으로 바꾼 작업이 `open` 목록에 계속 나온다.

```ts
// ❌ status만 고치면 GSI1 파티션은 옛 값에 남는다
UpdateExpression: 'SET #s = :s'
// ✅ 인덱스 속성을 같은 트랜잭션(같은 UpdateItem)에서 함께 옮긴다
UpdateExpression: 'SET #s = :s, #g = :g'
```

실측: 10건을 `done`으로 옮긴 뒤 `open` 목록에 남은 건수 **0건**, `done` 목록 10건.
<!-- verified: DynamoDB Local(-inMemory), @aws-sdk/lib-dynamodb@3.1116.0 — 실행 확인 -->

## 5. 소유자는 파티션 키에 들어간다 — 필터는 방어가 아니다

이 축에는 행 수준 정책 엔진이 없다. 애플리케이션 층이 **실질적 유일 경계**이고,
경계가 놓이는 물리적 자리는 `KeyConditionExpression`이다.

`FilterExpression`은 **읽은 뒤에** 적용된다. 아래는 같은 데이터(A 25건 · B 25건)에서
잰 값이다. 필터로 소유권을 거는 형태는 남의 파티션을 실제로 읽고, 그 읽기가 과금된다.

| 형태 | 반환 | ScannedCount | 소비 용량 |
| --- | --- | --- | --- |
| `Query`(pk = A) | 25 | 25 | 1.0 |
| `Scan` + `FilterExpression: ownerId = A` | 25 | 50 | 1.5 <!-- verified: 실행 확인 --> |
| `Scan` + `FilterExpression: ownerId = B` + `Limit: 10` | **0** | 10 | 0.5 <!-- verified: Limit이 필터보다 먼저 적용된다. 스캔 앞쪽 10건이 전부 A의 것이었다 — 실행 확인 --> |
| `Query`(pk = **B**) + `FilterExpression: ownerId = A` | 0 | **25** | **1.0** <!-- verified: 0건이지만 B의 파티션 25건을 전부 읽고 과금됐다 — 실행 확인 --> |

**표의 값은 DynamoDB Local(`-inMemory`) 측정이다.** 상대 비교(필터가 읽기를 줄이지
않는다)는 그대로 성립하지만, 절대값을 실서비스 RCU로 읽지 않는다 — 아이템 크기·일관성
설정·인덱스 사영이 전부 곱해진다.

세 번째 행이 페이지네이션을 망가뜨리는 자리다. `Limit`은 **필터 전에** 적용되므로
"10건 달라"는 요청이 0건을 돌려주면서 커서만 남긴다 — 빈 페이지가 무한히 이어진다.
**요청자의 파티션이 스캔 순서 뒤쪽에 있을 때** 나타나므로, 개발 데이터에서는 보이지 않다가
데이터가 쌓이면 나타난다. 같은 필터를 스캔 앞쪽에 있는 소유자로 걸면 10건이 그대로 왔다.

네 번째 행은 더 나쁘다. **0건을 돌려주면서 남의 파티션 25건을 전부 읽고 과금됐다** —
필터가 방어라면 이 읽기는 일어나지 않아야 했다.

```ts
// ❌ 이 축의 최대 위험. 소유권이 사후 필터에 있다
new ScanCommand({ TableName: TABLE, FilterExpression: 'ownerId = :o' })
// ✅ 소유자가 파티션 키에 있다 — 남의 파티션은 읽지도 않는다
KeyConditionExpression: 'pk = :pk AND begins_with(sk, :sk)'
```

`FilterExpression` 자체가 금지는 아니다. **이미 내 파티션 안**에서 부수적으로 거르는 것은
정상이다. 금지되는 것은 **소유권을 필터로 거는 것**이고, 그 구분은 기계가 못 한다 —
줄을 볼 때 "여기서 `:pk`에 들어가는 값이 세션에서 왔는가"를 사람이 확인한다.

## 6. 아이템 형태의 진화 — 스키마가 없다는 뜻

DynamoDB는 아이템마다 속성 집합이 다를 수 있다. 마이그레이션이 없는 대신 **읽는 쪽이
옛 아이템을 만난다.** 세 가지 규칙으로 감당한다.

- **속성을 추가할 때는 선택(`?`)으로 시작한다.** 기존 아이템에는 그 속성이 없다.
  필수로 만들려면 백필이 먼저다
- **속성을 지우지 말고 쓰기를 멈춘다.** 지우는 쓰기는 전체 스캔이고, 읽는 쪽이 무시하면 값은 없는 것과 같다
- **아이템에 `schemaVersion`을 두는 것은 종류가 늘어난 뒤에 한다.** 처음부터 두면
  분기만 늘고 쓰는 곳이 없다

`gsi1pk`/`gsi1sk`를 선택 속성으로 둔 것도 같은 이유다. **GSI는 두 키 속성이 모두 있는
아이템만 색인한다**(희소 인덱스) — 나중에 같은 테이블에 다른 종류의 아이템이 들어와도
GSI1은 작업만 담는다.

`undefined`를 그대로 넘기는 것은 조심한다. 실측에서 **최상위** 속성의 `undefined`는
기본 설정으로도 통과했지만(속성이 빠진 채 저장된다), **중첩된** `undefined`는
`Pass options.removeUndefinedValues=true ...`로 던졌다.
<!-- verified: @aws-sdk/lib-dynamodb@3.1116.0 — 실행 확인 -->
그래서 클라이언트를 만들 때 `removeUndefinedValues: true`를 켠다
(`resources/data-access.md` 2절).

## 오용 목록 ① — 관계형 습관 → 단일 테이블 대조표

| 구 습관 (관계형) | 현재 형태 (DynamoDB 단일 테이블) |
| --- | --- |
| 엔티티마다 테이블 하나 | 테이블 하나 + `pk`/`sk` 접두사로 종류 구분 |
| `JOIN`으로 연관을 따라간다 | 같은 파티션에 나란히 두고 한 번의 `Query`로 읽는다 |
| 외래 키 제약이 무결성을 지킨다 | 제약이 없다 — `ConditionExpression`이 그 자리다 |
| 정규화 후 필요한 쿼리를 쓴다 | 접근 패턴을 먼저 적고 키를 거기서 도출한다 |
| `ORDER BY created_at DESC` | 정렬은 SK가 정한다 — 시간 순서를 **id에** 넣는다 |
| `WHERE owner_id = ?` (인덱스가 알아서) | 소유자를 **파티션 키에** 넣는다. `WHERE`에 해당하는 `FilterExpression`은 읽은 뒤다 |
| `SELECT *` 후 앱에서 거른다 | 거르는 만큼 과금된다 — 키 조건으로 좁힌다 |
| 인덱스는 나중에 추가하면 된다 | 파티션 키는 바꿀 수 없다 — 새 GSI이거나 마이그레이션이다 |
| `AUTO_INCREMENT` | 단조 증가 키는 한 파티션에 쓰기를 몰아 hot partition을 만든다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `KeyConditionExpression` vs `FilterExpression` | 앞은 읽을 범위를 정하고 뒤는 읽은 뒤 거른다. **소유권은 항상 앞** |
| GSI vs LSI | 파티션 키가 달라야 하면 GSI. LSI는 파티션 키가 같고 정렬만 다를 때이며 테이블 생성 후 추가할 수 없다 |
| `begins_with(sk, ...)` vs `contains(...)` | `begins_with`만 키 조건이 된다. `contains`는 필터라 사후 적용이다 |
| 무작위 UUID vs 시간 순서 id | SK에 쓰는 id는 정렬을 결정한다. 최신순이 필요하면 시간 접두사를 넣는다 |
| `attribute_not_exists(pk)` vs `attribute_exists(pk)` | 앞은 생성(덮어쓰기 방지), 뒤는 수정·삭제(부재 감지). 뒤바꾸면 모든 갱신이 실패한다 |
| 희소 GSI vs 전체 GSI | 키 속성을 선택으로 두면 그 속성이 있는 아이템만 색인된다 — 종류가 섞인 테이블에서 이것이 기본 선택 |
| `Limit` vs 페이지 크기 | `Limit`은 **읽을 아이템 수**다. 필터가 있으면 반환 건수와 다르다 |
