<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# 테스트 — 배선은 이벤트와 클레임에서 깨진다

이 파일은 **테스트 하네스와 핸들러 테스트**를 소유한다. 데이터 계층의 소유권·커서
회귀는 `resources/data-access.md` §4·§5가 실 DynamoDB에 걸고, 스키마 단위 테스트는
`resources/input-validation.md`가, 에러 정규화는 `resources/error-handling.md`가 맡는다.
CDK 합성·IAM 검사는 `resources/deploy-and-iam.md`다.

**층을 섞지 않는다.** 여기의 테스트는 **배선**(이벤트 → 주체 → 조회 → 봉투)을 증명하고,
소유권은 실 DynamoDB에 걸어야 증명된다 — 모의가 소유권까지 흉내 내면 차단을 증명하지
못하는 테스트가 된다.

## 1. 테스트 하네스 (`test/invoke.ts`)

핸들러를 **실제 함수로** 부른다. HTTP도 모의 서버도 없다 — 배선 결함은 이벤트 모양과 인증 클레임에서 나오므로 그 둘만 진짜면 된다.

<!-- file: test/invoke.ts -->
```ts
// test/invoke.ts
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2, Context } from 'aws-lambda';

const CONTEXT: Context = {
  callbackWaitsForEmptyEventLoop: false,
  functionName: 'tasks-test', functionVersion: '$LATEST', memoryLimitInMB: '512',
  invokedFunctionArn: 'arn:aws:lambda:ap-northeast-2:000000000000:function:tasks-test',
  awsRequestId: '00000000-0000-4000-8000-000000000000',
  logGroupName: '/aws/lambda/tasks-test', logStreamName: '2026/08/23/[$LATEST]0',
  getRemainingTimeInMillis: () => 3000,
  done: () => {}, fail: () => {}, succeed: () => {},
};

const BASE = {
  version: '2.0', routeKey: 'GET /api/tasks', rawPath: '/api/tasks', rawQueryString: '',
  headers: {}, isBase64Encoded: false,
  requestContext: { requestId: 'req-test', http: { method: 'GET', path: '/api/tasks' } },
} as unknown as APIGatewayProxyEventV2;

export async function invokeHandler(
  h: (e: APIGatewayProxyEventV2, c: Context) => Promise<APIGatewayProxyResultV2>,
  event: Partial<APIGatewayProxyEventV2>,
): Promise<APIGatewayProxyResultV2> {
  return h({ ...BASE, ...event }, { ...CONTEXT });
}
```

합치기는 **얕다**. `authFor(ownerId)`가 돌려주는 조각에 `requestContext`가 있으면 기본
`requestContext`를 통째로 덮으므로 이음매의 `authFor`는 `http`와 `requestId`까지 포함해
돌려줘야 한다 — 어기면 인증은 통과하는데 로깅 키가 사라진다.

## 2. 핸들러 테스트 — 긍정·부정을 같은 `it`에 건다

**arrange 없이는 이 테스트가 빨간 채로 출하된다.** 아래 `it`의 첫 줄은 `t1`이 `u1`의
것으로 **이미 존재할 때만** 200이다. 무엇으로 그 상태를 만드는지 적지 않으면 복사한
사람은 `expected 404 to be 200`을 받는다 — 「대역으로 대체」는 방법이 아니라 이름이다.

이 층에서 쓰는 대역은 **데이터 계층 모듈 모의**다. 증명 대상이 배선(이벤트 → 주체 →
조회 → 봉투)이기 때문이고, 소유권 자체는 실 DynamoDB에 걸어야 하므로 그 자리는
`resources/data-access.md` §4의 `test/tasks.ownership.test.ts`다. 두 층을 섞으면 모의가
소유권까지 흉내 내 **차단을 증명하지 못하는 테스트**가 된다.

```ts
// test/handlers/tasks-get-one.test.ts
import { describe, expect, it, vi } from 'vitest';
import { handler } from '../../src/handlers/tasks-get-one';
import { authFor } from '../../src/http/require-auth';
import { invokeHandler } from '../invoke';

// arrange — vi.mock은 import 위로 끌어올려진다. 팩토리는 vi 외의 바깥 값을 참조할 수 없다
vi.mock('../../src/db/tasks', () => ({
  getTask: vi.fn(async (ownerId: string, id: string) =>
    ownerId === 'u1' && id === 't1'
      ? { id, title: '내 것', status: 'open', ownerId, createdAt: '2026-08-23T00:00:00.000Z' }
      : null),
}));

const call = (owner: string, id: string) =>
  invokeHandler(handler, { ...authFor(owner), pathParameters: { id } }) as
    Promise<{ statusCode: number }>;

describe('GET /api/tasks/{id}', () => {
  it('소유자는 200, 남은 404 — 한 it 안에서 대조한다', async () => {
    expect((await call('u1', 't1')).statusCode).toBe(200);   // 긍정: 기능이 살아 있다
    expect((await call('u2', 't1')).statusCode).toBe(404);   // 부정: 차단된다
  });

  it('토큰 없는 요청은 401이다', async () => {
    const r = await invokeHandler(handler, { pathParameters: { id: 't1' } });
    expect((r as { statusCode: number }).statusCode).toBe(401);
  });
});
```

**부정 단언만 있으면 차단 장치가 아니다.** `getTask`를 통째로 `return null`로 바꿔
돌려 봤다: 부정 단언만 있는 판본은 초록으로 통과했고 긍정 줄이 있는 판본은
`expected 404 to be 200`으로 실패했다 — 차단을 증명하는 것은 404가 아니라 **200과
404의 대조**다. <!-- verified: vitest 2.1.9 — getTask를 return null로 치환한 뮤턴트 실행 결과 -->
`authFor`·`requireAuth`·`respond`는 이음매가 정의하므로, 조립 후 실제 인증 방식으로
같은 테스트가 다시 돈다.

**로컬 호출 세 층**: ① `npx vitest run` — 핸들러를 프로세스 안에서 태운다(자격증명
불필요, DynamoDB 호출은 대역으로 대체) ② `npx cdk synth` — 템플릿·IAM·번들 검사
③ 배포 후 `aws lambda invoke --payload file://event.json out.json` — 실제 IAM과 실제
테이블이 처음 개입하는 지점이다.

## 3. 데이터 계층 회귀 — 실 DynamoDB에 건다

소유권과 커서는 **모의로 증명되지 않는다.** 모의는 정답을 알고 있어서 조건식을 지워도
초록이다. 아래 둘은 DynamoDB Local에 실제로 건다(거동표는 `resources/data-access.md` §4·§5).

```ts
// test/tasks.ownership.test.ts
it('남의 작업은 수정되지 않고, 내 작업은 수정된다', async () => {
  const mine = await putTask('A', { title: '내 것', status: 'open' });
  expect((await updateTask('A', mine.id, { title: '고침' })).title).toBe('고침');   // ✅ 긍정
  await expect(updateTask('B', mine.id, { title: '탈취' })).rejects.toThrow();      // ✅ 부정
  expect((await getTask('A', mine.id))?.title).toBe('고침');                        // 원본 불변
});

it('남의 것은 지워지지 않고, 본문의 status는 GSI까지 간다', async () => {
  const done = await putTask('A', { title: '끝난 것', status: 'done' });
  expect((await listTasks('A', { limit: 10, status: 'done' })).items.map((t) => t.id))
    .toContain(done.id);                                                           // ✅ 긍정
  await expect(deleteTask('B', done.id)).rejects.toThrow();                        // ✅ 부정
  expect(await getTask('A', done.id)).not.toBeNull();                              // 원본 생존
  await deleteTask('A', done.id);
  expect(await getTask('A', done.id)).toBeNull();                                  // ✅ 긍정
});
```

부정 단언만 걸면 `updateTask`를 통째로 `throw`로 바꿔도 초록이다. 긍정 단언이
"차단"과 "전부 고장"을 가른다.

```ts
// test/tasks.cursor.test.ts — 재고정 검사를 지우면 두 번째 단언이 빨개진다
it('위조 커서는 GSI 경로에서도 거부된다', async () => {
  const page = await listTasks('A', { limit: 1, status: 'open' });
  expect(page.cursor).toBeDefined();                                          // ✅ 긍정
  const forged = encodeCursor({ ...decodeCursor(page.cursor!), pk: 'USER#B' });
  await expect(listTasks('A', { limit: 1, status: 'open', cursor: forged }))
    .rejects.toThrow();                                                       // ✅ 부정
});
```

| 지운 것 | 빨개지는 단언 |
| --- | --- |
| `deleteTask`의 `ConditionExpression` | `rejects.toThrow()` — `DeleteItem`은 없는 키에도 200이라 예외가 사라진다 |
| `putTask`의 `input.status` → `'open'` 하드코딩 | `toContain(done.id)` — `done` 목록이 비고 `open` 목록에 잘못 뜬다 |
| `listTasks`의 커서 재고정 검사 | 위조 커서 시험(GSI 경로) — DynamoDB가 거부하지 않는 경로다 |

**차단 장치는 「있다」가 아니라 「없애면 빨개진다」로만 증명된다.** 위 셋을 실제로 지워
확인한 결과다.

## 4. 오용 목록 — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 단위 테스트 vs 핸들러 테스트 | 키 조립·커서는 앞, 인증·봉투·상태 코드는 뒤 — 뒤를 앞으로 흉내 내면 배선이 검사되지 않는다 |
| 부정 단언만 vs 긍정·부정 쌍 | 404만 걸면 구현을 통째로 망가뜨려도 초록이다. 200을 같은 `it`에 건다 |
| 데이터 계층 모의 vs 실 DynamoDB | 앞은 배선을, 뒤는 소유권을 증명한다. 앞으로 소유권을 증명하려 들면 모의가 정답을 알고 있다 |
