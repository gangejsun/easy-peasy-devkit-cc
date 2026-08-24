<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# Lambda 핸들러 형태 — 요청 하나가 함수 하나를 깨우는 세계

이 파일은 **핸들러의 수명과 배선**을 소유한다: 무엇을 모듈 최상위에 두는가, 래퍼가
무엇을 하는가, 로그에 무엇을 싣고 무엇을 싣지 않는가. 입력 검증은
`resources/input-validation.md`, 상태 코드 매핑은 `resources/error-handling.md`,
쿼리는 `resources/data-access.md`가 소유한다. `requireAuth`·`respond`·`AppError`는
**이음매**가 정의한다(`src/http/require-auth.ts` · `src/http/respond.ts` ·
`src/http/app-error.ts`) — 여기서는 부르기만 한다.

## 1. 판단 — 이 값을 모듈 최상위에 둘 것인가 핸들러 안에 둘 것인가

실행 환경은 요청 사이에 **얼어붙었다 풀린다**. 모듈 최상위 코드는 콜드 스타트에 한 번
돌고 그 결과를 **같은 환경이 처리하는 모든 후속 요청이 공유**한다. 그래서 판단 기준은
하나다 — **다음 요청이 이 값을 읽어도 안전한가.**

| 값 | 두는 곳 | 왜 |
| --- | --- | --- |
| `ddb` (DocumentClient) | 모듈 최상위 | 자격증명 해석과 커넥션 준비를 콜드 스타트에 끝낸다. 정책 `client-outside-handler`가 요구한다 |
| `logger` | 모듈 최상위 | 인스턴스를 재사용한다. 요청 스코프 값은 `appendKeys`로 붙였다 뗀다 |
| `env` (검증된 환경 값) | 모듈 최상위 | 잘못된 배포를 첫 요청이 아니라 **초기화에서** 죽인다 |
| Zod 스키마 객체 | 모듈 최상위 | 스키마 조립 비용이 요청당이 아니라 환경당이 된다 |
| 인증 주체 · 요청 본문 · 요청 ID | **핸들러 안** | 최상위에 두면 다음 요청이 앞 사용자의 값을 읽는다 — 이 축의 조용한 데이터 유출 경로다 |
| 조회 결과 캐시 | 핸들러 안 (또는 TTL을 명시한 최상위) | 환경은 수십 분~수 시간 산다. 무효화 없는 캐시는 오래된 데이터를 계속 낸다 |

**최상위 초기화는 게으르지 않다.** 모듈이 로드되면 조건 없이 돈다. 그래서 최상위에는
`await`가 필요 없는 것만 둔다 — 최상위 `await`는 콜드 스타트 시간을 늘리고, 실패하면
핸들러가 호출되기도 전에 함수가 죽는다. <!-- unverified: Lambda 런타임의 초기화 실패 동작. 로컬에서 재현하지 않았다 -->

## 2. 표준 핸들러 (`src/handlers/tasks-get-one.ts`)

라우트 하나에 파일 하나다. 순서가 고정돼 있다: **인증 → 입력 → 데이터 → 응답**, 그리고
바깥을 `try/catch`가 감싸 실패를 봉투로 바꾼다.

```ts
// src/handlers/tasks-get-one.ts
import type { APIGatewayProxyEventV2 } from 'aws-lambda';
import { withContext, logger } from '../obs/logger';
import { requireAuth } from '../http/require-auth';
import { respond } from '../http/respond';
import { AppError } from '../http/app-error';
import { getTask } from '../db/tasks';
import { pathParam } from '../http/parse';

export const handler = withContext(async (event: APIGatewayProxyEventV2) => {
  try {
    const user = requireAuth(event);              // 미들웨어가 아니다 — 첫 줄의 함수 호출
    const id = pathParam(event, 'id');
    const task = await getTask(user.id, id);      // 소유자가 먼저다
    if (!task) throw new AppError('NOT_FOUND', 'task not found');
    logger.info('task read', { ownerId: user.id, taskId: id });
    return respond(task);
  } catch (e) {
    return respond.fail(e);                       // 봉투 방출은 한 곳에서만
  }
});
```

`event`는 `APIGatewayProxyEventV2`다. `body` · `pathParameters` · `queryStringParameters`는
**선택 필드**이지 `| null`이 아니므로 `?.` · `?? {}`로 꺼낸다. 상태 코드는 핸들러가 정하지
않는다 — `respond.fail`이 `toAppError`로 정규화한 뒤 `ERROR_STATUS`에서 읽는다.

**부재와 권한 없음을 구분하지 않는다.** 남의 작업을 요청해도 404다. `getTask(user.id, id)`가
소유자를 키 조건에 넣으므로 남의 아이템은 애초에 조회되지 않고, 결과적으로 두 경우가
같은 응답이 된다 — 403을 따로 내면 미인가 사용자가 존재를 열거할 수 있다.

## 3. 관측 배선 (`src/obs/logger.ts`)

로거·래퍼·콜드 스타트 플래그가 한 파일에 산다. 셋 다 **모듈 최상위 상태**에 의존하므로
나누면 플래그가 두 벌이 된다.

<!-- file: src/obs/logger.ts -->
```ts
// src/obs/logger.ts
import { Logger } from '@aws-lambda-powertools/logger';
import type { APIGatewayProxyEventV2, APIGatewayProxyResultV2, Context } from 'aws-lambda';
import { env } from '../env';

type ApiHandler = (e: APIGatewayProxyEventV2, c: Context) => Promise<APIGatewayProxyResultV2>;

export const logger = new Logger({ serviceName: 'tasks', logLevel: env.LOG_LEVEL });

let cold = true;

export function isColdStart(): boolean {
  return cold;
}

export function withContext(h: ApiHandler): ApiHandler {
  return async (event, context) => {
    logger.addContext(context);
    logger.appendKeys({ coldStart: cold, routeKey: event.routeKey });
    try {
      return await h(event, context);
    } catch (e) {
      logger.error('unhandled handler error', e as Error);
      throw e;
    } finally {
      cold = false;
      logger.removeKeys(['coldStart', 'routeKey']);
    }
  };
}
```

`removeKeys`를 `finally`에 두는 것이 핵심이다. `appendKeys`는 **인스턴스에 남는다** —
떼지 않으면 다음 요청의 로그가 앞 요청의 `routeKey`를 달고 나간다. 같은 이유로 요청
스코프 값(사용자 ID·본문)은 `appendKeys`가 아니라 개별 로그 호출의 인자로 넘긴다.

`withContext`의 타입이 `Handler`가 아니라 좁힌 `ApiHandler`인 이유가 있다.
`@types/aws-lambda@8.10.162`의 `Handler`는 콜백 스타일을 함께 지원하느라 반환이
`void | Promise<TResult>`라, `await h(...)`의 결과가 `void`를 포함해 래퍼가 그대로는
`Handler`로 타입이 맞지 않는다. 좁힌 형태는 `Handler`에 **대입 가능**하므로 Lambda 쪽
계약은 그대로다. <!-- verified: tsc 5.9.3 strict — 좁히기 전 TS2322 재현, 좁힌 뒤 `const asLambda: Handler = handler` 통과 -->

## 4. 미들웨어 체인이 없다 — 래퍼는 하나로 끝낸다

`withContext`가 **유일한 래퍼**다. 그 이상 쌓지 않는 이유는 취향이 아니다.

- **래퍼는 타입을 지운다.** 인증을 래퍼로 올리면 `AuthUser`를 핸들러에 넘길 통로가
  `event`에 몰래 붙이는 필드뿐이고, 그 필드는 타입 시스템 밖에 있다. 함수 호출은
  `const user = requireAuth(event)`로 값이 **반환**되므로 타입이 살아 있다
- **래퍼는 순서를 숨긴다.** 체인이 셋을 넘으면 어느 것이 먼저 도는지 호출부에서 안 보인다.
  핸들러 첫 세 줄에 세 함수 호출이 있으면 순서가 곧 코드다
- **래퍼는 조기 반환을 어렵게 한다.** 미들웨어가 401을 내려면 봉투를 알아야 하고, 그러면
  `respond`가 두 곳에서 불린다 — 정책 `envelope-from-respond`가 막는 형태다

`withContext`가 하는 일은 **관측뿐**이다: 컨텍스트 부착, 콜드 스타트 표시, 그리고 마지막
그물. 미처리 예외를 **로깅하고 다시 던진다** — 삼키면 반환값이 `undefined`가 되어
API Gateway가 원인 없는 502/500을 내고 CloudWatch에는 아무것도 남지 않는다. 로컬 실행에서
`throw new Error('kaboom')`이 `{"level":"ERROR","message":"unhandled handler error",
"error":{"name":"Error","message":"kaboom","stack":...}}`로 찍힌 뒤 호출자에게 그대로
재던져지는 것을 확인했다. <!-- verified: tsx 실행 — 로그 방출 후 catch 블록에서 'kaboom' 수신 -->

## 5. 콜드 스타트 플래그 — powertools의 `cold_start`를 그대로 믿지 않는다

우리 `isColdStart()`는 모듈 최상위 `cold` 플래그를 읽고, `withContext`가 `finally`에서
`false`로 내린다. 그래서 **첫 호출이 도는 동안에는 `true`**이고 그 뒤로는 `false`다
(로컬 실행: 호출 전 `true` → 호출 1 내부 `true` → 호출 1 이후 `false` → 호출 2 `false`).
<!-- verified: tsx 실행 — invokeHandler 2회 호출 전후로 isColdStart() 값 계측 -->

powertools가 로그에 붙이는 `cold_start` 키는 **다른 것**이고 두 가지 함정이 있다.

| 함정 | 실제 동작 |
| --- | --- |
| Lambda 밖에서는 항상 `false` | `Utility` 생성자가 `AWS_LAMBDA_INITIALIZATION_TYPE`이 `on-demand`가 아니면 `coldStart`를 즉시 `false`로 내린다. 테스트·로컬에서 `cold_start:false`만 보이는 이유다 <!-- verified: @aws-lambda-powertools/commons 2.35.0 Utility.js getColdStart + 환경변수 유무로 출력 대조 --> |
| 읽으면 소진된다 | `getColdStart()`는 `true`를 반환하면서 내부 플래그를 `false`로 바꾼다. 핸들러에서 한 번 부르면 `addContext`가 붙이는 값이 `false`가 된다 <!-- verified: 위와 같은 소스, `if (this.coldStart) { this.coldStart = false; return true }` --> |

프로비저닝된 동시성에서도 `on-demand`가 아니므로 powertools의 `cold_start`는 계속
`false`다. **분기·측정·테스트에는 `isColdStart()`를 쓴다.** 로그의 `coldStart` 키는
`withContext`가 우리 플래그로 직접 붙이므로 두 값이 갈리지 않는다.

## 6. 타임아웃과 재시도 — 29초가 실제 상한이다

Lambda 자체 상한은 15분이지만 API Gateway HTTP API 뒤에서는 도달하지 못한다.
`HttpLambdaIntegration`의 통합 타임아웃은 **50ms ~ 29초**이고 기본값이 29초다.
<!-- verified: aws-cdk-lib 2.266.0 aws-apigatewayv2-integrations/lib/http/lambda.d.ts:22-27 -->
통합이 먼저 끊기면 클라이언트는 504를 받고 **Lambda는 계속 돈다** — 쓰기 작업이라면
클라이언트가 실패로 본 요청이 성공해 있을 수 있다.

| 실패 | 재시도 대상인가 | 근거 |
| --- | --- | --- |
| DynamoDB 스로틀 (`isThroughputExceeded`) | **예** — SDK가 이미 재시도한다. 소진되면 429로 내린다 | 일시적이고 같은 요청이 다음에 성공한다 |
| 통합 타임아웃(504) | 조건부 — **쓰기는 위험하다** | 서버 쪽 결과를 모른다. 조건부 쓰기가 재실행을 안전하게 만든다 |
| `AppError('VALIDATION_FAILED')` | 아니오 | 같은 입력은 항상 같은 실패다 |
| `AppError('CONFLICT')` | 아니오 | 재시도가 충돌을 풀지 않는다 |

**API Gateway는 프록시 통합을 재시도하지 않는다** — 재시도는 클라이언트의 몫이다.
따라서 생성 요청에는 멱등 키를 조건부 쓰기로 걸어야 클라이언트 재시도가 중복을 만들지
않는다(`resources/data-access.md`). <!-- unverified: AWS 문서 기반. 실제 API Gateway 배포로 계측하지 않았다 -->

함수 타임아웃은 통합보다 **짧게** 잡는다. 통합이 29초에 끊는데 함수가 60초면, 끊긴 뒤
31초 동안 과금되면서 아무도 읽지 않을 응답을 만든다.

## 7. 로그에 비밀이 새지 않게 — powertools는 아무것도 가리지 않는다

powertools logger 2.35.0에는 **자동 마스킹이 없다.** 로컬 실행으로 6가지 깊이를 넣어
출력을 확인했고 **전부 평문으로 찍혔다**: 최상위 `token`, `user.accessToken`(깊이 2),
`a.b.password`·`a.b.connectionString`(깊이 3), `headers.authorization`의 `Bearer …`,
배열 원소 안의 `apiKey`, 그리고 **`Error`의 `message`와 `stack` 안에 문자열로 박힌
커넥션 문자열까지**. <!-- verified: @aws-lambda-powertools/logger 2.35.0 — tsx 실행, 6개 프로브 출력 전량 평문 확인 -->

마지막 것이 가장 위험하다. `logger.error('failed', e)`는 `error.stack`을 통째로 싣는데,
비밀이 예외 메시지에 들어간 경우 **로그 키를 아무리 고르게 골라도 새어 나간다.**

```ts
// src/handlers/tasks-get-one.ts
// ❌ 이벤트·헤더를 통째로 싣는다 — 가려주는 것이 아무것도 없다
logger.info('incoming', { event });
logger.debug('auth', { headers: event.headers });
// ✅ 식별자와 모양만 싣는다. 값이 아니라 존재 여부를 로깅한다
logger.info('list tasks', {
  ownerId: user.id,
  limit: q.limit,
  hasCursor: Boolean(q.cursor),
});
```

규칙 셋: ① `event` · `event.headers` · `requestContext.authorizer`를 통째로 넘기지
않는다 ② 토큰·비밀은 **길이나 존재 여부**로만 남긴다 ③ 비밀을 예외 메시지에 넣지 않는다 —
`AppError`의 `message`는 클라이언트에도 로그에도 간다.

**`message`와 `stack`만 보는 것으로는 부족하다.** 에러 객체는 그 둘 말고도 실린다:

| 함께 실리는 것 | 왜 문제인가 |
| --- | --- |
| `Error`에 붙은 **커스텀 열거 속성** | AWS SDK 예외는 `$metadata`·`$fault`를, 트랜잭션 실패는 `CancellationReasons`를 **항상** 달고 온다. 요청 조각과 내부 식별자가 그 안에 있다 |
| `Error.cause` | 원인 체인을 타고 **하위 계층의 예외가 통째로** 따라 올라온다. 커넥션 문자열이 거기 있으면 상위 메시지를 아무리 다듬어도 새어 나간다 |
| **이 팩 자신의 `respond.fail`** | `resources/error-handling.md` §6의 어댑터가 500일 때 `{ code, err: e }`로 **에러를 통째로 싣는다.** 위 두 줄이 그대로 CloudWatch에 들어간다 |

마지막 행이 규칙의 예외가 아니라 **규칙이 적용될 자리**다. 500은 원인을 남겨야 하는
자리이므로 `err: e`를 지우는 것이 답이 아니다 — 실을 것을 고른다(`err: { name: e?.name,
message: e?.message }`처럼) 아니면 로그 그룹의 접근을 좁힌다. 어느 쪽이든 **결정을 하고
넘어간다.** 이음매가 `respond`를 소유하므로 그 결정도 이음매의 몫이다.

## 8. 오용 목록 ① — Express/Fastify 관용구 → Lambda 형태 대조표

| 구 습관 (Express/Fastify) | 현재 형태 (Lambda + API Gateway HTTP API v2) |
| --- | --- |
| `app.use(authMiddleware)` | 핸들러 첫 줄 `const user = requireAuth(event)` — 체인이 없다 |
| `req.body` (파서 미들웨어가 채운다) | `parseBody(TaskCreateSchema, event)` — `event.body`는 문자열이거나 아예 없다 |
| `res.status(404).json(...)` | `return respond.fail(new AppError('NOT_FOUND', '...'))` |
| `next(err)`로 에러 전파 | `try/catch` + `respond.fail(e)` — 전파받을 상위가 없다 |
| 한 프로세스가 전 라우트를 처리 | 라우트당 함수 하나 — IAM 최소 권한의 단위가 함수다 |
| 부팅 시 커넥션 풀 생성 | 모듈 최상위에서 클라이언트 1개. 풀도 상주 커넥션도 없다 |
| `process.on('uncaughtException')` | `withContext`의 `catch` — 로깅하고 다시 던진다 |
| `console.log`로 디버깅 | powertools `logger` — CloudWatch에서 구조적 질의가 되어야 한다 |
| `app.listen` 앞의 헬스체크 초기화 | 최상위 초기화. 실패는 함수 초기화 실패로 나타난다 |

## 9. 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `logger.getColdStart()` vs `isColdStart()` | 앞은 **읽으면 소진**되고 `on-demand` 초기화가 아니면 항상 `false`다. 분기·테스트에는 뒤를 쓴다 |
| `appendKeys` vs `appendPersistentKeys` | 요청 스코프는 앞(반드시 `removeKeys`로 뗀다), 환경 전역은 뒤. 앞을 떼지 않으면 다음 요청 로그가 오염된다 |
| `logger.addContext` vs `logger.appendKeys` | 앞은 Lambda `Context` 전용(함수명·요청 ID·메모리), 뒤는 임의 키. `addContext`에 이벤트를 넘기지 않는다 |
| `event.requestContext.requestId` vs `context.awsRequestId` | 앞은 API Gateway 요청 ID, 뒤는 Lambda 호출 ID. 상관 추적은 앞, 실행 추적은 뒤 |
| `throw` vs `return respond.fail(e)` | 클라이언트에게 보일 실패는 뒤. `throw`는 `withContext`가 로깅 후 재던져 게이트웨이 5xx가 된다 |
| `event.body` 직접 `JSON.parse` vs `parseBody` | `isBase64Encoded`가 `true`면 앞은 깨진다. 파싱은 `src/http/parse.ts` 한 곳에서 |
| `withContext` vs 래퍼 추가 | 두 번째 관심사는 래퍼가 아니라 핸들러 첫 줄의 **함수 호출**로 넣는다 |
| 최상위 상수 vs 최상위 캐시 | 앞은 안전(불변), 뒤는 요청 간 공유 — 사용자별 값을 담으면 교차 노출이다 |
