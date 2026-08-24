<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# 데이터 액세스 — 소유권은 키 조건에 있다

이 파일은 DynamoDB를 **부르는 코드**를 소유한다: 문서 클라이언트 싱글턴(`src/db/client.ts`)과
작업 모듈(`src/db/tasks.ts`) 전체 — 목록·단건·생성·수정·삭제·커서. 키 조합과 인덱스 설계는
`resources/data-modeling.md`가, 에러 판별기와 상태 코드표는 `resources/error-handling.md`가
소유한다. 이 모듈은 이벤트도 응답도 모른다 — `APIGatewayProxyEventV2`를 여기서 import하면
계층이 뒤집힌 것이다.

## 1. 판단 — 무엇으로 읽고 무엇으로 쓰는가

| 하려는 일 | 명령 | 조건 |
| --- | --- | --- |
| 키를 아는 한 건 | `GetCommand` | `keys.task(ownerId, id)` |
| 한 소유자의 목록 | `QueryCommand` | `pk` 등호 + `begins_with(sk, …)` |
| 상태로 좁힌 목록 | `QueryCommand` + `IndexName: 'gsi1'` | `gsi1pk` 등호 |
| 생성 | `PutCommand` | `attribute_not_exists(pk) AND attribute_not_exists(sk)` |
| 부분 수정 | `UpdateCommand` | `attribute_exists(pk)` |
| 삭제 | `DeleteCommand` | `attribute_exists(pk)` |
| 여러 파티션을 한 번에 | `TransactWriteCommand` | 항목마다 조건식 (6절) |

표에 없는 것이 하나 있다. **테이블 전체를 훑는 명령은 이 팩에 등장하지 않는다** —
그 명령을 쓰는 순간 소유권 조건이 키 조건이 아니라 사후 필터가 되기 때문이다.
근거 수치는 `resources/data-modeling.md` 5절에 있다.

세 가지가 항상 같이 간다: **소유자는 세션에서 오고, 키에 들어가고, 조건식이 그것을 강제한다.**
셋 중 하나라도 빠지면 나머지 둘은 방어가 아니다.

## 2. 클라이언트는 핸들러 밖에서 만든다 (`src/db/client.ts`)

Lambda에는 상주 커넥션이 없다. 대신 **실행 환경은 재사용된다** — 모듈 최상위에서 만든
클라이언트는 콜드 스타트 한 번의 비용으로 이후 호출 전부가 나눠 쓴다.

<!-- file: src/db/client.ts -->
```ts
// src/db/client.ts
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

// 모듈 최상위 — 콜드 스타트 밖이다. 핸들러 안에서 만들면 매 호출 새로 선다.
const base = new DynamoDBClient({});   // 리전·자격증명은 Lambda 실행 환경이 준다

export const ddb = DynamoDBDocumentClient.from(base, {
  // 중첩된 undefined는 기본 설정에서 던진다 — 부분 갱신 객체가 정확히 그 형태다
  marshallOptions: { removeUndefinedValues: true },
});
```

문서 클라이언트를 쓰면 `{ S: '...' }` 형태의 속성 값 표기를 다루지 않는다. 다만
`@aws-sdk/client-dynamodb`의 명령(`PutItemCommand` 등)을 여기 보내면 변환이 걸리지 않는다 —
**`@aws-sdk/lib-dynamodb`가 export하는 이름만** 쓴다.

## 3. 작업 모듈 (`src/db/tasks.ts`)

<!-- file: src/db/tasks.ts -->
```ts
// src/db/tasks.ts
import { GetCommand, QueryCommand, PutCommand, UpdateCommand, DeleteCommand } from '@aws-sdk/lib-dynamodb';
import { ddb } from './client';
import { TABLE, keys, type Task } from '../keys';
import type { TaskCreate, TaskUpdate, TaskStatus } from '../schemas/task';
import { isConditionalCheckFailed } from '../http/errors';
import { AppError } from '../http/app-error';

/** LastEvaluatedKey를 불투명 문자열로. 비밀이 아니라 서명 없는 인코딩이다. */
export function encodeCursor(key: Record<string, unknown>): string {
  return Buffer.from(JSON.stringify(key), 'utf8').toString('base64url');
}
export function decodeCursor(cursor: string): Record<string, unknown> {
  try {
    const k: unknown = JSON.parse(Buffer.from(cursor, 'base64url').toString('utf8'));
    if (!k || typeof k !== 'object' || Array.isArray(k)) throw new Error('shape');
    return k as Record<string, unknown>;
  } catch {
    throw new AppError('VALIDATION_FAILED', '커서를 해석할 수 없다');
  }
}

export async function listTasks(
  ownerId: string,
  q: { limit: number; cursor?: string; status?: TaskStatus },
): Promise<{ items: Task[]; cursor?: string }> {
  const { pk, skPrefix } = keys.taskList(ownerId);
  const start = q.cursor ? decodeCursor(q.cursor) : undefined;
  // 커서는 클라이언트가 보낸 값이다 — 소유자 파티션에 다시 고정한다
  if (start && start.pk !== pk) throw new AppError('VALIDATION_FAILED', '커서를 해석할 수 없다');
  const where = q.status !== undefined
    ? { IndexName: 'gsi1', KeyConditionExpression: 'gsi1pk = :g',
        ExpressionAttributeValues: { ':g': keys.statusList(ownerId, q.status).gsi1pk } }
    : { KeyConditionExpression: 'pk = :pk AND begins_with(sk, :sk)',
        ExpressionAttributeValues: { ':pk': pk, ':sk': skPrefix } };
  const res = await ddb.send(new QueryCommand({
    TableName: TABLE, ...where,
    Limit: q.limit, ExclusiveStartKey: start, ScanIndexForward: false,
  }));
  return {
    items: (res.Items ?? []) as Task[],
    cursor: res.LastEvaluatedKey ? encodeCursor(res.LastEvaluatedKey) : undefined,
  };
}

export async function getTask(ownerId: string, id: string): Promise<Task | null> {
  const res = await ddb.send(new GetCommand({ TableName: TABLE, Key: keys.task(ownerId, id) }));
  return (res.Item as Task | undefined) ?? null;   // 남의 것은 키가 달라 애초에 안 잡힌다
}

export async function putTask(ownerId: string, input: TaskCreate): Promise<Task> {
  const id = keys.newId();
  // 본문을 통째로 펼치지 않는다 — 필드를 하나씩 옮겨야 본문이 키·소유자를 덮을 길이 없다.
  // 다만 **옮길 것은 전부 옮긴다.** 세션에서 오는 것은 ownerId뿐이다
  const row: Task = {
    ...keys.task(ownerId, id), ...keys.taskGsi1(ownerId, input.status, id),
    id, title: input.title, status: input.status, // 본문의 값이다 — 하드코딩하면 GSI까지 굳는다
    ownerId,                                       // 세션에서 온다. 본문의 값은 쓰지 않는다
    createdAt: new Date().toISOString(),
  };
  try {
    await ddb.send(new PutCommand({
      TableName: TABLE, Item: row,
      ConditionExpression: 'attribute_not_exists(pk) AND attribute_not_exists(sk)',
    }));
  } catch (e) {
    if (isConditionalCheckFailed(e)) throw new AppError('CONFLICT', '이미 있는 작업이다');
    throw e;
  }
  return row;
}

export async function updateTask(ownerId: string, id: string, patch: TaskUpdate): Promise<Task> {
  const entries = Object.entries(patch).filter(([, v]) => v !== undefined);
  if (entries.length === 0) throw new AppError('VALIDATION_FAILED', '수정할 필드가 없다');
  const names: Record<string, string> = {};
  const values: Record<string, unknown> = {};
  const sets = entries.map(([k, v], i) => {
    names[`#n${i}`] = k;      // 이름은 자리표시자로. `status`는 DynamoDB 예약어다
    values[`:v${i}`] = v;
    return `#n${i} = :v${i}`;
  });
  const next = entries.find(([k]) => k === 'status')?.[1];
  if (typeof next === 'string') {
    names['#g'] = 'gsi1pk';   // 상태가 바뀌면 GSI1 파티션도 같은 UpdateItem에서 옮긴다
    values[':g'] = keys.taskGsi1(ownerId, next as TaskStatus, id).gsi1pk;
    sets.push('#g = :g');
  }
  try {
    const res = await ddb.send(new UpdateCommand({
      TableName: TABLE,
      Key: keys.task(ownerId, id),                 // 소유자가 키에 있다
      UpdateExpression: `SET ${sets.join(', ')}`,
      ExpressionAttributeNames: names,
      ExpressionAttributeValues: values,
      ConditionExpression: 'attribute_exists(pk)', // 없으면(=남의 것이면) 실패한다
      ReturnValues: 'ALL_NEW',
    }));
    return res.Attributes as Task;
  } catch (e) {
    if (isConditionalCheckFailed(e)) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
    throw e;
  }
}

export async function deleteTask(ownerId: string, id: string): Promise<void> {
  try {
    await ddb.send(new DeleteCommand({
      TableName: TABLE, Key: keys.task(ownerId, id),
      ConditionExpression: 'attribute_exists(pk)', // 조건이 없으면 없는 키에도 성공한다
    }));
  } catch (e) {
    if (isConditionalCheckFailed(e)) throw new AppError('NOT_FOUND', '작업을 찾을 수 없다');
    throw e;
  }
}
```

`UpdateExpression`을 문자열 결합으로 만들지 않는 이유가 둘이다. 하나는 주입이고, 다른
하나는 **예약어**다 — `SET status = :s`는 `reserved keyword: status`로 거부된다.
<!-- verified: DynamoDB Local, @aws-sdk/lib-dynamodb@3.1116.0 — 실행 확인 -->
`#n0` 자리표시자를 기계적으로 붙이면 예약어 목록을 외울 필요가 없다. 빈 `patch`를 막는
첫 줄도 장식이 아니다: `SET ` 하나만 남은 식은 구문 오류로 500이 된다. <!-- verified: 실행 확인 -->

**하나씩 옮기는 형태의 대가는 「빠뜨림」이다.** `status`를 `'open'`으로 고정하면
`POST {"title":"x","status":"done"}`이 **201인데 저장된 값은 `open`**이고, `keys.taskGsi1`까지
`'open'` 파티션으로 굳어 `status=done` 목록에서 영영 사라진다(감사 A·C 실측).
스키마가 받아들인 필드는 **전부 소비한다** — 원장의 `putTask` 형태 열이 이것을 못박는다.

## 4. 소유권 — 조건식이 없으면 삭제는 항상 성공한다

`DeleteItem`은 **멱등**이다. 없는 키를 지워도 오류가 아니라 HTTP 200이다.
<!-- verified: DynamoDB Local — 조건식 없는 DeleteItem이 없는 키에 200. 실행 확인 -->
그래서 조건식 없이 삭제하면 **남의 작업을 지우라는 요청도 204로 응답한다** — 0행 변이를
성공으로 답하는 이 축의 대표 함정이다. `PutItem`도 같다: 조건식 있는 재삽입은
`ConditionalCheckFailedException`(HTTP 400), 없는 재삽입은 말없이 덮어썼다. <!-- verified: 실행 확인 -->

**남의 것은 404다.** 조건 실패를 `NOT_FOUND`로 매핑하면 부재와 권한 없음이 밖에서
구분되지 않는다 — 403으로 답하면 미인가 사용자가 id를 넣어 보며 리소스 존재를 열거한다.
`CONFLICT`는 생성에서만 나온다(그 자리에는 숨길 것이 없다).

측정한 소유권 거동. **긍정과 부정을 짝으로 걸어야** 차단인지 전부 고장인지 갈린다.

| 행위 | 소유자 | 타인 |
| --- | --- | --- |
| `getTask` | 아이템 반환 | `null` <!-- verified: 실행 확인 --> |
| `updateTask` | `ALL_NEW` 반환, 값이 바뀜 | `AppError('NOT_FOUND')`, 원본 불변 <!-- verified: 실행 확인 --> |
| `deleteTask` | 이후 조회가 `null` | `AppError('NOT_FOUND')`, 원본 생존 <!-- verified: 실행 확인 --> |
| `listTasks` | 자기 25건 | 상대 아이템 유입 0건 <!-- verified: 실행 확인 --> |

**차단 증명은 `resources/testing.md` §3이 소유한다** — 세 장치를 실제로 지워 어느 단언이
빨개지는지 확인한 표가 거기 있다.

## 5. 커서 — 왕복·위조·평문

`LastEvaluatedKey`는 키 속성이 든 객체다. 그대로 응답에 실으면 내부 키 형식이 와이어
계약이 되므로 불투명 문자열로 감싼다. 실측: 소유자 25건을 `limit: 7`로 끝까지 넘겼을 때
**4장 · 25건 · 중복 0 · 누락 0**, 정렬은 내림차순 유지. <!-- verified: 실행 확인 -->

**커서는 신뢰 입력이 아니다.** base64url은 암호가 아니라 인코딩이라 평문이 그대로 보인다:
`{"sk":"TASK#01a0…","pk":"USER#ownerA"}`. 그래서 두 겹으로 막는다.

아래 표의 2·3행은 **앱 검사를 뺀 상태에서 DynamoDB만 남겨 잰 값**이다. §3의 `listTasks`는
`start.pk !== pk`를 GSI 경로에서도 무조건 돌리므로 팩 코드 그대로라면 세 시도가 **모두**
1행의 결과를 받는다.

| 시도 (앱 검사 기준) | 결과 |
| --- | --- |
| 커서의 `pk`를 남의 것으로 바꿔 `listTasks` 호출 | `AppError('VALIDATION_FAILED')` — 3절 코드의 재고정 검사 <!-- verified: 실행 확인 --> |
| **앱 검사를 빼고** 기본 테이블 질의로 DynamoDB에 직접 | `ValidationException: The provided starting key does not match the range key predicate` <!-- verified: 실행 확인 --> |
| **앱 검사를 빼고** GSI 커서에서 기본 테이블 `pk`만 위조 | **DynamoDB가 거부하지 않는다.** 결과는 여전히 `gsi1pk` 파티션 안이라 유출은 없지만, 거부가 없으므로 **앱 검사만이 유일한 방어**다 <!-- verified: 실행 확인 -->  |

세 번째 행이 앱 층 재고정을 지키는 이유다. DynamoDB의 거부는 기본 테이블 질의에서만
확인됐고, 그 거부는 `ValidationException`이라 에러 코드표에 없으면 500으로 나간다
(`resources/error-handling.md` §2가 400으로 접는다).

## 6. 배치와 트랜잭션 — 부분 실패가 기본값이다

배치는 원자적이지 않다. 트랜잭션은 원자적이지만 조건식이 하나라도 깨지면 전부 취소된다.

| | 상한 | 부분 실패 | 조건식 |
| --- | --- | --- | --- |
| `BatchWriteCommand` | 25건 (26건은 `ValidationException`) | `UnprocessedItems`로 되돌아온다 — **재시도는 호출자 몫** | 없다. 넣어도 오류 없이 무시됐다 <!-- verified: DynamoDB Local — 실행 확인. 실제 서비스 거동은 미검증 --> |
| `BatchGetCommand` | 100건 (101건은 `ValidationException`) | `UnprocessedKeys` <!-- verified: 실행 확인 --> | 해당 없음 |
| `TransactWriteCommand` | 100건 | 없다 — 전부 아니면 전무 | 항목마다 가능 |

트랜잭션의 조건 실패는 이름이 다르게 온다. 실측에서 두 항목 중 둘째만 실패했을 때
`TransactionCanceledException` · `CancellationReasons = ["None", "ConditionalCheckFailed"]`가
나왔고 **첫 항목은 저장되지 않았다**. <!-- verified: 실행 확인 -->
그래서 `isConditionalCheckFailed`가 이름만 보지 않고 취소 사유까지 본다
(`resources/error-handling.md`). 이름만 보는 판별기는 트랜잭션 안의 조건 실패를 500으로 만든다.

스로틀은 성격이 다르다 — 재시도가 **맞는** 실패다. SDK 기본 재시도가 소진된 뒤에는
`isThroughputExceeded`로 판별해 `THROTTLED`로 내보낸다(API Gateway는 재시도하지 않는다).
검증 실패·조건 실패는 재시도 대상이 아니다.

## 오용 목록 ① — 관용구 대조표

| 구 습관 | 현재 형태 (SDK v3 · DocumentClient) |
| --- | --- |
| `new DynamoDB.DocumentClient()` (v2) | `DynamoDBDocumentClient.from(new DynamoDBClient({}))` <!-- verified: @aws-sdk/lib-dynamodb@3.1116.0 --> |
| `.promise()`를 붙여 await | `ddb.send(command)`가 이미 Promise다 |
| 핸들러 안에서 클라이언트 생성 | 모듈 최상위에서 한 번 |
| `{ S: value }` 속성 값 표기를 손으로 조립 | 문서 클라이언트가 변환한다 — 평범한 JS 값을 넣는다 |
| 조회 후 `if (item.ownerId !== user.id)` 비교 | 소유자를 키에 넣는다 — 조회 후 비교는 경합에 뚫린다 |
| `FilterExpression`으로 소유권 | `KeyConditionExpression`으로 소유권 |
| 페이지 번호(`offset`) | `ExclusiveStartKey` 커서 — DynamoDB에 offset은 없다 |
| `UpdateExpression`을 문자열 결합 | `#n`/`:v` 자리표시자를 기계적으로 생성 |
| 배치 결과를 성공으로 간주 | `UnprocessedItems`를 확인하고 재시도 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `PutCommand` vs `UpdateCommand` | `Put`은 아이템을 **통째로 교체**한다. 부분 수정에 쓰면 보내지 않은 속성이 사라진다 |
| `attribute_not_exists` vs `attribute_exists` | 생성은 앞(덮어쓰기 방지 → `CONFLICT`), 수정·삭제는 뒤(부재 감지 → `NOT_FOUND`) |
| `Limit` vs 반환 건수 | `Limit`은 읽을 아이템 수다. 필터가 붙으면 반환은 그보다 적을 수 있다 |
| `LastEvaluatedKey` 없음 vs 빈 페이지 | 키가 없어야 끝이다. 빈 `Items`는 끝이 아니다 — 커서가 있으면 계속 넘긴다 |
| `BatchWriteCommand` vs `TransactWriteCommand` | 원자성이 필요하면 트랜잭션. 배치는 부분 성공하고 조건식이 없다 |
| `ConditionalCheckFailedException` vs `TransactionCanceledException` | 트랜잭션 안의 조건 실패는 뒤 이름으로 온다. 앞만 보면 500이 된다 |
| `ReturnValues: 'ALL_NEW'` vs `'ALL_OLD'` | 응답에 실을 값은 `ALL_NEW`. `ALL_OLD`는 갱신 **전** 값이라 그대로 반환하면 옛 값을 보낸다 |
| 커서 인코딩 vs 커서 서명 | base64url은 감추지도 지키지도 않는다. 소유자 재고정이 방어이고, 서명이 필요하면 이음매가 정한다 |
