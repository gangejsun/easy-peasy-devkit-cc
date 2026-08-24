<!-- epcc-pack: backend/aws-serverless v3.13.0 -->
# 배포와 IAM — 함수가 권한의 단위다

이 파일은 **CDK 스택 구성 · 함수별 최소 권한 IAM · 번들링 · 배포 순서**를 소유한다.
테스트 하네스와 핸들러 테스트는 `resources/testing.md`가, 라우트↔함수 매핑
(`infra/routes.ts`)은 **이음매**가 소유한다. 키 설계는 `resources/data-modeling.md`,
쿼리는 `resources/data-access.md`, 핸들러 수명은 `resources/handler-patterns.md`다.

## 1. 판단 — 이 사실을 어디서 확인할 것인가

배포 파이프라인의 각 단계가 확인할 수 있는 것이 다르다. 한 단계에 다 몰면 느린 쪽이
전부를 지연시키고, 잘못 나누면 아무도 안 보는 자리가 생긴다.

| 확인하려는 것 | 어디서 | 도구 |
| --- | --- | --- |
| 키 조립 · 커서 인코딩 · Zod 스키마 | 단위 테스트 | Vitest — 순수 함수라 이벤트가 필요 없다 |
| 핸들러 배선(인증→검증→쿼리→봉투) | 핸들러 테스트 | `invokeHandler` + `authFor` |
| 소유권 차단(남의 것이 안 보이는가) | 핸들러 테스트 | 긍정·부정 **쌍**으로 (§6) |
| IAM이 실제로 좁은가 · 번들 내용 | 합성 | `cdk synth` 후 템플릿의 Action 목록과 `cdk.out/asset.*/index.js` (§3·§4) |
| 조건부 쓰기가 경합에서 이기는가 | 배포 후 | 실제 테이블. 로컬에서 재현할 수 없다 |
| 타임아웃·콜드 스타트 시간 | 배포 후 | CloudWatch. 로컬 시간은 참고값도 아니다 |

**합성은 배포가 아니지만 검사다.** `cdk synth`는 자격증명 없이 템플릿을 파일로 낸다 — 최소 권한 주장이 참인지 여기서 판정된다.

## 2. 테이블 스택 (`infra/table.ts`)

단일 테이블과 GSI1을 만드는 `Construct`와 함수별 권한 부여 함수가 한 파일에 산다.
**권한 부여가 테이블 정의 옆에 있어야** 액션 목록이 테이블 형태와 함께 갱신된다.

<!-- file: infra/table.ts -->
```ts
// infra/table.ts
import { RemovalPolicy } from 'aws-cdk-lib';
import {
  AttributeType, BillingMode, ProjectionType, Table, TableEncryption,
} from 'aws-cdk-lib/aws-dynamodb';
import { PolicyStatement } from 'aws-cdk-lib/aws-iam';
import type { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { Construct } from 'constructs';

const READ_ACTIONS = ['dynamodb:GetItem', 'dynamodb:Query'];
const WRITE_ACTIONS = ['dynamodb:PutItem', 'dynamodb:UpdateItem', 'dynamodb:DeleteItem'];
// 배치·트랜잭션은 별개 액션이다 — 위 다섯 개로는 BatchWrite도 TransactWrite도 못 부른다
const BATCH_ACTIONS = [
  'dynamodb:BatchGetItem', 'dynamodb:BatchWriteItem',
  'dynamodb:TransactWriteItems', 'dynamodb:ConditionCheckItem',
];

export class TaskTable extends Construct {
  readonly table: Table;

  constructor(scope: Construct, id: string) {
    super(scope, id);
    this.table = new Table(this, 'Table', {
      partitionKey: { name: 'pk', type: AttributeType.STRING },
      sortKey: { name: 'sk', type: AttributeType.STRING },
      billingMode: BillingMode.PAY_PER_REQUEST,
      encryption: TableEncryption.AWS_MANAGED,
      pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true },
      removalPolicy: RemovalPolicy.RETAIN,
    });
    this.table.addGlobalSecondaryIndex({
      indexName: 'gsi1',
      partitionKey: { name: 'gsi1pk', type: AttributeType.STRING },
      sortKey: { name: 'gsi1sk', type: AttributeType.STRING },
      projectionType: ProjectionType.ALL,
    });
  }
}

export function grantTaskAccess(
  fn: NodejsFunction, table: TaskTable, mode: 'read' | 'write' | 'batch',
): void {
  const arn = table.table.tableArn;
  fn.addToRolePolicy(new PolicyStatement({
    actions: READ_ACTIONS,
    resources: [arn, `${arn}/index/*`],
  }));
  if (mode === 'write' || mode === 'batch') {
    fn.addToRolePolicy(new PolicyStatement({ actions: WRITE_ACTIONS, resources: [arn] }));
  }
  if (mode === 'batch') {
    fn.addToRolePolicy(new PolicyStatement({ actions: BATCH_ACTIONS, resources: [arn] }));
  }
  fn.addEnvironment('TABLE_NAME', table.table.tableName);
}
```

`removalPolicy: RETAIN`이 `DeletionPolicy: Retain`과 **`UpdateReplacePolicy: Retain`**
두 줄로 방출되는 것을 합성으로 확인했다 — 뒤의 것이 §7에서 결정적이다.
<!-- verified: aws-cdk-lib 2.266.0 app.synth() 템플릿의 AWS::DynamoDB::Table 리소스 -->

## 3. 함수별 최소 권한 — 합성된 정책 문서가 증거다

「최소 권한」은 주장이 아니라 템플릿에서 세어지는 수다. 아래는
`grantTaskAccess(getFn, tasks, 'read')`와 `grantTaskAccess(putFn, tasks, 'write')`를
합성해 나온 **실제 `AWS::IAM::Policy` 문서**다.

```json
{
  "GetTaskFnServiceRoleDefaultPolicy": [
    { "Effect": "Allow", "Action": ["dynamodb:GetItem", "dynamodb:Query"],
      "Resource": ["<TableArn>", "<TableArn>/index/*"] }
  ],
  "PutTaskFnServiceRoleDefaultPolicy": [
    { "Effect": "Allow", "Action": ["dynamodb:GetItem", "dynamodb:Query"],
      "Resource": ["<TableArn>", "<TableArn>/index/*"] },
    { "Effect": "Allow",
      "Action": ["dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem"],
      "Resource": "<TableArn>" }
  ]
}
```

읽기 함수는 **액션 2개**, 쓰기 함수도 5개이고 쓰기 액션의 `Resource`에는 `/index/*`가
**없다** — 인덱스는 DynamoDB가 갱신하므로 함수가 인덱스에 쓸 이유가 없다.

**`'read'`·`'write'` 두 모드로는 배치·트랜잭션을 부를 수 없다.** `resources/data-access.md`
§6이 `TransactWriteCommand`·`BatchWriteCommand`·`BatchGetCommand`를 정상 패턴으로 가르치는데,
위 정책 문서에는 `dynamodb:TransactWriteItems`·`BatchWriteItem`·`BatchGetItem`·
`ConditionCheckItem`이 **하나도 없다** — 그대로 배포하면 코드는 통과하고 런타임에서
AccessDenied가 난다(§7 표의 첫 행이 말하는 실패다). 그래서 모드를 셋으로 나눈다:

| 모드 | 추가되는 액션 | 언제 |
| --- | --- | --- |
| `'read'` | `GetItem` · `Query` | 단건·목록 핸들러 |
| `'write'` | 위 + `PutItem` · `UpdateItem` · `DeleteItem` | 단일 아이템 변이 |
| `'batch'` | 위 + `BatchGetItem` · `BatchWriteItem` · `TransactWriteItems` · `ConditionCheckItem` | 배치·트랜잭션을 실제로 부르는 함수에만 |

`'batch'`를 기본값으로 두지 않는다 — 함수 하나가 배치 권한을 갖는 순간 그 함수가 뚫렸을 때
**한 번의 호출로 25건을 지울 수 있다.** 부르지 않는 함수에는 주지 않는 것이 이 절의 요지다.
<!-- verified: aws-cdk-lib 2.266.0 app.synth() — PolicyDocument.Statement를 그대로 옮겼다 -->
같은 스택에서 다른 도메인 테이블 `usersTable`에 테이블 전체 권한 헬퍼를 쓰면 **액션
12개**가 나오고 `Scan`·`BatchWriteItem`·`DescribeTable`·스트림 읽기까지 들어온다 —
❌ 이 형태를 쓰지 않는다:

```json
[
  { "Action": ["dynamodb:BatchGetItem", "dynamodb:Query", "dynamodb:GetItem",
      "dynamodb:Scan", "dynamodb:ConditionCheckItem", "dynamodb:BatchWriteItem",
      "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem",
      "dynamodb:DescribeTable"] },
  { "Action": ["dynamodb:GetRecords", "dynamodb:GetShardIterator"] }
]
```

2 대 12다. <!-- verified: aws-cdk-lib 2.266.0 — 같은 합성 실행에서 얻은 두 번째 정책 문서 -->
정책 `no-table-wide-grant`가 테이블 전체 권한 헬퍼를 금지하는 이유가 이 숫자다: 읽기
전용 목록 핸들러가 뚫리면 테이블 전체를 `Scan`하고 지울 수 있게 된다. **라우트마다
함수를 나누지 않으면 이 좁히기 자체가 불가능하다** — 한 함수가 목록과 삭제를 모두
처리하면 그 함수는 삭제 권한을 항상 갖는다.

## 4. 함수 정의와 번들링 (`infra/app.ts`)

```ts
// infra/app.ts
import { App, Duration, Stack } from 'aws-cdk-lib';
import { Architecture, Runtime } from 'aws-cdk-lib/aws-lambda';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import { LogGroup, RetentionDays } from 'aws-cdk-lib/aws-logs';
import { TaskTable, grantTaskAccess } from './task-table';
import { routes } from './routes';          // 이음매가 소유한다

const app = new App();
const stack = new Stack(app, 'TasksStack', {
  env: { account: process.env.CDK_DEFAULT_ACCOUNT, region: process.env.CDK_DEFAULT_REGION },
});
const tasks = new TaskTable(stack, 'Tasks');

const fn = (id: string, entry: string) => new NodejsFunction(stack, id, {
  entry, handler: 'handler',
  runtime: Runtime.NODEJS_22_X, architecture: Architecture.ARM_64,
  timeout: Duration.seconds(10), memorySize: 512,   // 통합 상한 29초보다 짧게
  logGroup: new LogGroup(stack, `${id}Logs`, { retention: RetentionDays.ONE_MONTH }),
});

const getFn = fn('GetTaskFn', 'src/handlers/tasks-get-one.ts');
grantTaskAccess(getFn, tasks, 'read');
routes(stack, { table: tasks });        // 라우트↔함수 매핑은 이음매가 소유한다
```

`entry`가 `.ts`여도 `Handler` 속성은 **`index.handler`**로 방출된다 — esbuild가 어떤
경로의 소스든 `index.js` 하나로 번들하므로, 소스 경로를 핸들러 문자열에 적으면 안 된다.
<!-- verified: aws-cdk-lib 2.266.0 합성 템플릿의 AWS::Lambda::Function Handler 값 -->

**external로 둘 것은 `@aws-sdk/*` 하나**다. `NodejsFunction`의 기본 `externalModules`가
SDK v3를 포함하는 Node 18 이상 런타임에서 `['@aws-sdk/*']`이고, `bundleAwsSDK: true`를
주지 않는 한 번들에서 빠진다. **번들할 것**은 powertools 로거·Zod처럼 런타임이 주지
않는 것 전부. 합성된 `index.js`를 실제로 재 본 값은 **무엇을 끌어오느냐로 8배 갈린다**:

| 핸들러가 import하는 것 | 번들 |
| --- | --- |
| powertools 로거 + SDK 호출만 | **74KB** |
| 위 + `parse.ts` → `errors.ts` → **Zod** | **603KB** |

**이 팩의 핸들러는 뒤쪽이다.** `parseBody`가 Zod를 부르고 `toAppError`가 `z.ZodError`를
보므로 검증을 쓰는 모든 핸들러가 Zod를 번들에 끌어온다. 74KB만 보고 콜드 스타트를
가늠하면 실제와 어긋난다 — 함수를 라우트마다 나누는 이유가 여기에도 있다(검증이 없는
핸들러는 603KB를 지불하지 않는다).
<!-- verified: aws-cdk-lib 2.266.0 합성 산출 index.js를 두 판본으로 계측 — 76,252바이트(74KB)와 618,074바이트(603KB). 두 판본 모두 require("@aws-sdk/client-dynamodb")가 남았다 -->

`timeout`·`memorySize`를 주지 않으면 템플릿에 두 속성이 **아예 방출되지 않는다** —
Lambda 기본값(3초·128MB)이 조용히 적용된다는 뜻이다. 명시한다.
<!-- verified: 두 속성을 뺀 합성에서 Timeout/MemorySize 키 부재 확인. 기본값은 aws-cdk-lib 2.266.0의 aws-lambda/lib/function.d.ts:162(@default Duration.seconds(3))·189(@default 128) 직접 대조 -->
## 5. 배포 순서와 되돌릴 수 없는 변경

**순서는 테이블 → 함수 → 라우트다.** CDK가 참조에서 의존성을 유도하므로 한 스택 안에서는
자동으로 지켜진다 — `grantTaskAccess`가 함수 역할을 테이블 ARN에 묶고
`addEnvironment('TABLE_NAME', …)`가 함수를 테이블 이름에 묶는다. 문제는 **참조로 표현되지
않는 순서**다.

| 변경 | 안전한 순서 | 어기면 |
| --- | --- | --- |
| 새 액션이 필요한 코드 배포 | 권한 **먼저** 넓히고 → 코드 배포 | 코드가 먼저 가면 런타임 AccessDenied. 배포는 성공한 채로 500이 난다 |
| 안 쓰게 된 액션 제거 | 코드 **먼저** 배포하고 → 권한 좁힘 | 순서를 바꾸면 아직 그 액션을 부르는 함수가 살아 있다 |
| 라우트 제거 | 클라이언트 이전 → 라우트 제거 → 함수 제거 | 함수를 먼저 지우면 라우트가 없는 대상을 가리킨다 |
| GSI 추가 | **한 배포에 하나씩** | DynamoDB는 UpdateTable 한 번에 인덱스 하나만 만든다 <!-- verified: DynamoDB Local 3.3.1에 GSI 2개 동시 생성을 요청해 LimitExceededException: Only 1 online index can be created or deleted simultaneously 수신. 실제 서비스 배포로는 미계측 --> |

**되돌릴 수 없는 것은 셋이다.** ① **`partitionKey`·`sortKey` 변경**은 테이블 **교체**다.
`UpdateReplacePolicy: Retain` 덕분에 기존 테이블이 지워지지는 않지만 스택이 가리키는 것은
**새 빈 테이블**이고 템플릿을 되돌려도 데이터는 따라오지 않는다 — 키 설계는 배포 전에
끝낸다. ② **GSI 삭제**는 인덱스 데이터를 버린다. 재생성은 전체 재구축이고 그동안 그
인덱스를 쓰는 쿼리는 실패한다. ③ **`Construct` id 변경**은 논리 ID를 바꾸므로
CloudFormation이 「삭제 후 생성」으로 읽는다 — 옛 테이블은 고아로 남고 새 것은 비어 있다.

**되돌릴 수 있는 것**은 함수 코드·타임아웃·메모리·환경변수·IAM 정책이고 스택 롤백이 그대로
복구한다. 그래서 위험한 변경은 **별도 배포로 분리**한다 — 키 변경과 코드 변경을 한 배포에
섞으면 롤백 가능한 절반이 롤백 불가능한 절반에 묶인다.

## 6. 오용 목록 ① — CDK 2 구 관용구 → 현재 형태

| 구 습관 | 현재 형태 |
| --- | --- |
| `pointInTimeRecovery: true` | `pointInTimeRecoverySpecification: { pointInTimeRecoveryEnabled: true }` — 앞은 deprecated <!-- verified: aws-cdk-lib 2.266.0 aws-dynamodb/lib/table.d.ts:220 @deprecated --> |
| `logRetention: RetentionDays.X` | `logGroup: new LogGroup(...)` — 앞은 deprecated이고 커스텀 리소스 Lambda를 하나 더 만든다 <!-- verified: aws-cdk-lib 2.266.0 aws-lambda/lib/function.d.ts:404 @deprecated --> |
| 테이블 전체 권한 헬퍼 1줄 | `grantTaskAccess(fn, table, 'read' \| 'write' \| 'batch')` — 액션 2~9개 |
| `lambda.Function` + 손수 `zip` · `Runtime.NODEJS_18_X` · x86_64 | `NodejsFunction`(esbuild 내장) · `Runtime.NODEJS_22_X` · `Architecture.ARM_64` |
| `billingMode` 미지정 후 용량 튜닝 | `BillingMode.PAY_PER_REQUEST` — 스로틀 판별은 `ThrottlingException`이 된다 |
| 핸들러 하나가 라우트 여럿 처리 | 라우트당 함수 하나 — 최소 권한의 단위 |

## 7. 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `cdk synth` vs `cdk deploy` | 앞은 자격증명 없이 도는 **검사**다. IAM 주장은 앞에서 판정하고, 뒤는 그 뒤에 한다 |
| `fn.addToRolePolicy` vs `table.grant*` | 앞은 액션을 우리가 고른다. 뒤는 헬퍼가 고른 목록을 받는다 — 12개짜리가 섞여 온다 |
| `RemovalPolicy.RETAIN` vs `DESTROY` | 앞은 삭제와 **교체** 양쪽에서 옛 테이블을 남긴다. 뒤는 키 변경 한 번에 데이터가 사라진다 |
| `externalModules` vs `nodeModules` | 앞은 번들에서 빼고 런타임이 주기를 기대한다. 뒤는 번들 대신 `node_modules`로 설치한다 |
| `Duration.seconds` (함수) vs 통합 타임아웃 | 함수 값이 통합 상한 29초보다 크면 클라이언트는 504를 받고 함수는 계속 돈다 |
