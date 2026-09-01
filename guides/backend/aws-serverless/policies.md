<!-- epcc-pack-policies: backend/aws-serverless v3.13.0 -->

# aws-serverless 팩 — 파일 간 불변식 (L0 초안)

## 기계 검사 (게이트 `check_policies` · `check_pack_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간 아님.

**`증명 예` 열은 의무다** (없으면 FAIL). 게이트가 ① 예가 자기 정규식에 매치되는가
② `forbid`면 그 예가 대상 파일에 실재하지 않는가를 단언한다.
**`대상` 값에 마크다운 강조를 쓰지 않는다** — `**seam**`은 scope로 인식되지 않는다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 반례 | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | guide | `process\.env` | `input-validation.md, deploy-and-iam.md` | `const t = process.env.TABLE_NAME` | `process.env["TABLE_NAME"]` | 환경 값은 `env` 한 곳에서만 읽는다. 예외 둘: 스키마를 적용하는 자리와 CDK가 배포 시점 값을 넘기는 자리 |
| `boot-time-env-validation` | require | guide | `safeParse\([^)]*process\.env` | — | `EnvSchema.safeParse(process.env)` | `EnvSchema.parse(process.env)` | **콜드 스타트에 실패시킨다.** 핸들러 안에서 검증하면 잘못된 배포가 첫 요청까지 살아 있다 |
| `no-scan` | forbid | guide | `ScanCommand\|new Scan\(` | `data-modeling.md` | `new ScanCommand({ TableName: TABLE })` | `await ddb.send(new ScanCommand({}))` | Scan은 테이블 전체를 읽는다 — 비용과 지연이 데이터 양에 비례하고 **소유권 필터가 키 조건이 아니라 사후 필터가 된다.** 예외는 안티패턴을 설명하는 모델링 문서뿐 |
| `ownership-in-key` | require | guide | `(KeyConditionExpression\|ConditionExpression)` | — | `KeyConditionExpression: 'pk = :pk'` | `FilterExpression: 'ownerId = :o'` | **이 축의 최대 위험.** 정책 엔진이 없으므로 소유권은 **키 조건이나 조건식**에 들어가야 한다. 조회 후 비교는 경합에 뚫리고, 사후 필터는 이미 읽은 뒤다 |
| `no-table-wide-grant` | forbid | guide | `grantReadWriteData\|grantFullAccess` | — | `table.grantReadWriteData(fn)` | `table.grantFullAccess(fn)` | 함수별 최소 권한을 준다. 테이블 전체 권한은 한 함수가 뚫리면 전 도메인이 열린다 |
| `client-outside-handler` | require | guide | `DynamoDBDocumentClient\.from` | — | `const ddb = DynamoDBDocumentClient.from(base)` | `const ddb = new DynamoDBClient({})` | 클라이언트는 **모듈 최상위**에서 만든다. 핸들러 안에서 만들면 매 호출 연결이 새로 서고 콜드 스타트 이득이 사라진다 |
| `no-console` | forbid | guide | `console\.(log\|error\|warn)\(` | — | `console.log(user)` | `console.error(err)` | powertools 로거만 쓴다. CloudWatch에서 구조적 질의가 되어야 한다 |
| `error-status-single-table` | require | guide | `ERROR_STATUS\[[^]]*\][[:space:]]*\?\?` | — | `ERROR_STATUS[e.code] ?? 500` | `export const ERROR_STATUS = {` | 상태 코드를 파일마다 정하면 같은 실패가 자리에 따라 다른 코드로 나간다 |
| `no-relational-idiom` | forbid | guide | `\bJOIN\b\|foreign key\|외래 키` | `data-modeling.md` | `SELECT * FROM tasks JOIN users` | `외래 키를 만든다` | DynamoDB에는 조인이 없다. 관계형 습관을 그대로 옮기면 접근 패턴 설계가 통째로 어긋난다. 예외는 대조표를 싣는 모델링 문서뿐 |
| `vocab-task` | forbid | guide | `\bnotes?\b\|노트` | — | `const notes = []` | `노트를 만든다` | 도메인 어휘는 `Task`/`tasks`/`작업`으로 고정한다 (L0 발행). 실측에서 프론트가 `/tasks`, 백엔드가 `/notes`를 써서 완전 예제가 서로 실행 불가였다 |
| `auth-in-handler` | require | seam | `=[[:space:]]*requireAuth\(` | — | `const user = requireAuth(event)` | `export function requireAuth(event)` | **대상이 `seam`인 이유**: `requireAuth`는 이음매가 정의하므로 `guide`로 걸면 이음매가 배포되는 한 절대 실패하지 않는다 — 정작 검증해야 할 핸들러 배선이 검사되지 않는다 |
| `envelope-from-respond` | require | seam | `respond\.fail\(` | — | `return respond.fail(e)` | `return respond.ok(data)` | 봉투 방출은 한 곳에서만 한다. 핸들러가 직접 `{ statusCode, body }`를 만들면 봉투가 갈라진다. **정규식에 선택 그룹을 쓰지 않는 이유**: `respond(\.fail)?\(`로 쓰면 성공 경로의 `respond(...)`만으로 충족돼 **실패 경로를 전혀 측정하지 못한다** — 감사 A가 실측으로 찾았다. `ownership-in-query`가 파라미터 주석으로 충족되던 것과 같은 부류다 |

`대상`이 `guide`면 조립본 전체, `pack`이면 팩 파일만, `seam`이면 이음매 파일만,
`file:<이름>`이면 그 파일만 본다. 조립 전(`--pack`)에는 `seam` 대상이 판정 불가이므로
**건너뛴 것을 명시 보고**한다.

## 사람이 지킬 것 (기계로 판정 불가)

- **부재와 권한 없음을 구분해 응답하지 않는다.** 남의 아이템은 403이 아니라 404다
- **소유권을 `FilterExpression`으로 걸지 않는다.** 필터는 읽은 **뒤에** 적용되므로 과금도
  되고 페이지 크기도 어긋난다 — 소유자는 **파티션 키**에 들어가야 한다.
  `KeyConditionExpression`과 `FilterExpression`은 줄 단위로 구분되지만 **어느 쪽에
  소유자가 있는지**는 사람만 안다
- **부분 업데이트 스키마에 `.default()`를 겹치지 않는다.** 보내지 않은 필드가 기본값으로
  덮어써진다 — 문법은 완벽하고 실행만이 드러낸다
- **`UpdateExpression`을 문자열 결합으로 만들지 않는다.** 속성 이름은 `#n` 자리표시자로,
  값은 `:v`로 넘긴다
- **핸들러 하나가 여러 라우트를 처리하게 만들지 않는다.** 함수별 IAM 최소 권한이
  성립하지 않는다 — 라우트마다 함수를 나눈다
- **재시도 가능한 실패와 그렇지 않은 것을 구분한다.** 스로틀·타임아웃은 재시도 대상이고
  검증 실패는 아니다. API Gateway가 재시도하지 않는다는 것을 전제로 쓴다
