<!-- epcc-pack-ledger: backend/gcp-serverless v3.14.0 -->

# gcp-serverless 팩 — 심볼 원장 (L0 선언본)

저작 전에 메인 세션이 선언한 계약이다. 클러스터를 갈라 병렬로 써도 중복 정의와 **시그니처
추측**이 생기지 않게 하는 유일한 장치다.

**「형태」 열은 의무다.** 소유 파일만 배정하고 형태를 비우면 형제 클러스터가 시그니처를
추측한다 — 실측(node-api)에서 `getTask(ownerId, id)`를 다른 클러스터가 `getTask(id, ownerId)`로
불렀고 두 인자가 모두 `string`이라 타입 검사도 게이트도 잡지 못해 모든 단건 조회가 404가
됐다. 인자 **순서** · 반환 · 실패 시 던지는 것 · **호출자가 배선해야 하는 것**을 함께 적는다.

**「정의 파일」은 문서의 소유이지 코드의 경로가 아니다.** 그래서 형태 열에 **소스 경로를
못박는다** — firebase 실측에서 한 클러스터는 `src/firestore/model.ts`(평평한 루트)를, 다른
둘은 `functions/src/…`를 가정해 조립본의 상대 import가 해소되지 않았다. **게이트는 심볼이
팩 어딘가에 정의만 되어 있으면 통과시킨다.**

**이 팩에서 특히 위험한 자리 셋:**

1. **`ownerId`와 `taskId`가 둘 다 `string`이다.** 순서를 바꿔도 TypeScript가 잡지 못한다.
   전 함수에서 **`ownerId` → `taskId`** 순서를 고정한다
2. **세션·트랜잭션 인자가 없다.** Firestore 클라이언트는 모듈 최상위의 프로세스 단일
   인스턴스이므로 리포지토리 함수는 그것을 **인자로 받지 않는다** — 트랜잭션이 필요한
   함수만 `Transaction`을 받고, 그 사실을 형태에 적는다
3. **필드 소비 의무.** 시그니처가 맞아도 인자의 *내용*을 안 쓰면 같은 부류의 치명 결함이
   된다(aws-serverless 실측: 생성 함수가 `status`를 버리고 하드코딩했다)

## provides — 이 팩이 정의한다

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `settings` | input-validation.md | **`src/settings.ts`** — zod로 파싱한 환경 값. `GCP_PROJECT_ID` · `IDENTITY_PLATFORM_PROJECT_ID` · `PORT`(Cloud Run이 주입한다. 기본 8080) · `LOG_LEVEL` · `NODE_ENV` · `FIRESTORE_EMULATOR_HOST?`. **모듈 최상위에서 파싱한다** — 검증 실패가 부팅 실패여야 한다(요청 시점에 터지면 절반이 살아 있는 컨테이너가 된다). **환경을 읽는 유일한 파일이다** | 검증된 환경 값 |
| `TaskStatus` | input-validation.md | **`src/schemas/task.ts`** — `z.enum(['open', 'done'])`. **값은 소문자 `'open'`·`'done'`이다.** 와이어·Firestore 문서·테스트 단언에 쓰는 것은 **값**이지 멤버 이름이 아니다 — 이 칸을 비워 두었더니 형제 클러스터가 `=== 'DONE'`으로 단언해 차단 증명 테스트가 항상 빨갰다(fastapi 실측) | 상태 열거 |
| `Task` | input-validation.md | **`src/schemas/task.ts`** — `{ id: string; ownerId: string; title: string; status: TaskStatus; createdAt: Timestamp }`. `id`는 **문서 ID이지 문서 필드가 아니다** — converter가 스냅샷에서 채운다. `ownerId`는 **문서 필드로도 저장한다**(쿼리 필터가 그것을 읽는다) | 도메인 타입 |
| `TaskCreate` | input-validation.md | **`src/schemas/task.ts`** — `z.object({ title: z.string().min(1).max(200), status: TaskStatus.default('open') })`. `.strict()` — 미지 키를 **거부**한다 | 생성 본문 |
| `TaskUpdate` | input-validation.md | **`src/schemas/task.ts`** — `TaskCreate`의 부분형. **선택 필드에 기본값을 두지 않는다** — 두면 부분 수정이 보내지 않은 필드를 덮어쓴다. 빈 객체는 거부한다 | 수정 본문 |
| `TaskQuery` | input-validation.md | **`src/schemas/task.ts`** — `{ limit: number(1~100, 기본 20); cursor?: string; status?: TaskStatus }`. `.strict()` — **미지 쿼리 파라미터가 조용히 통과하면 필터가 무시된 목록을 정상 응답으로 준다** | 목록 쿼리 |
| `fieldErrors` | input-validation.md | **`src/schemas/errors.ts`** — `(err: z.ZodError) => Record<string, string[]>` — `path`를 점으로 이어 키로 쓴다. **배열 인덱스를 지우지 않는다** — 몇 번째 항목이 틀렸는지가 사라지면 폼이 오류를 못 붙인다 | 필드 오류 |
| `firestore` | data-access.md | **`src/firestore/client.ts`** **여기가 유일한 정의다** — `Firestore` 인스턴스. **모듈 최상위에서 한 번 만든다**(Cloud Run은 상주 프로세스다 — 요청마다 만들면 gRPC 채널이 쌓인다). `settings.FIRESTORE_EMULATOR_HOST`가 있으면 에뮬레이터로 붙는다 | 클라이언트 |
| `taskConverter` | data-access.md | **`src/firestore/converter.ts`** — `FirestoreDataConverter<Task>` — `toFirestore`는 `id`를 **문서 데이터에서 뺀다**(문서 ID와 중복 저장하면 둘이 갈린다), `fromFirestore`는 `snap.id`를 `id`에 채운다. **`fromFirestore`에서 스키마를 다시 파싱한다** — 문서는 코드 밖에서 바뀔 수 있으므로 신뢰 입력이 아니다 | 변환기 |
| `tasksRef` | data-access.md | **`src/firestore/tasks.ts`** — `CollectionReference<Task>` — `firestore.collection('tasks').withConverter(taskConverter)`. **`withConverter`를 빠뜨린 참조를 다른 파일이 만들지 않는다** — 만들면 그 경로만 원시 문서를 받아 타입이 거짓말을 한다 | 컬렉션 참조 |
| `listTasks` | data-access.md | **`src/firestore/tasks.ts`** — `(ownerId: string, q: TaskQuery) => Promise<{ items: Task[]; nextCursor: string \| null }>` — **`where('ownerId', '==', ownerId)`가 유일한 경계다.** 정렬은 `('createdAt', 'desc')` + `('__name__', 'desc')` 둘이다(동시각 문서가 페이지 경계에서 누락·중복된다) | 목록 |
| `getTask` | data-access.md | **`src/firestore/tasks.ts`** — `(ownerId: string, taskId: string) => Promise<Task \| null>` — **두 인자가 모두 `string`이니 순서가 생명이다.** 문서를 읽은 뒤 `doc.ownerId === ownerId`를 **반드시 확인한다** — 문서 ID만으로 읽으면 남의 작업을 준다. 없거나 남의 것이면 `null`(예외 아님) | 단건 |
| `createTask` | data-access.md | **`src/firestore/tasks.ts`** — `(ownerId: string, data: TaskCreate) => Promise<Task>` — **`data`의 `title`과 `status`를 모두 옮긴다.** `status`를 하드코딩하면 클라이언트가 보낸 값이 조용히 사라진다(aws-serverless 실측 치명). `ownerId`는 인자에서만 오고 **본문에서 오지 않는다** | 생성 |
| `updateTask` | data-access.md | **`src/firestore/tasks.ts`** — `(ownerId: string, taskId: string, patch: TaskUpdate) => Promise<Task>` — **트랜잭션 안에서 읽고 소유권을 확인한 뒤 쓴다.** 확인과 쓰기를 나누면 그 사이에 소유자가 바뀐 문서를 덮어쓴다. 없거나 남의 것이면 `AppError('NOT_FOUND', …)` — **`FORBIDDEN`이 아니다**(존재를 누설한다) | 수정 |
| `deleteTask` | data-access.md | **`src/firestore/tasks.ts`** — `(ownerId: string, taskId: string) => Promise<void>` — **`delete()`는 없는 문서에도 성공한다.** 트랜잭션 안에서 존재와 소유권을 확인한 뒤 지운다. 확인하지 않으면 남의 것을 지우라는 요청도 204가 된다 | 삭제 |
| `encodeCursor` | data-access.md | **`src/firestore/cursor.ts`** — `(createdAt: Timestamp, taskId: string) => string` — 불투명 문자열. 내부 정렬 키를 와이어 계약으로 만들지 않는다 | 커서 인코딩 |
| `decodeCursor` | data-access.md | **`src/firestore/cursor.ts`** — `(cursor: string) => { createdAt: Timestamp; taskId: string }` — 실패는 `AppError('VALIDATION_FAILED', …)`. **커서는 신뢰 입력이 아니다** | 커서 디코딩 |
| `isNotFound` | error-handling.md | **`src/firestore/errors.ts`**(HTTP를 모른다 — `http/` 아래에 두면 리포지토리가 HTTP 모듈을 끌어온다) — `(err: unknown) => boolean` — gRPC **코드 5**로 판정한다. 메시지 문자열 매칭은 SDK 버전에 따라 깨진다 | 부재 판별 |
| `isAlreadyExists` | error-handling.md | **`src/firestore/errors.ts`** — `(err: unknown) => boolean` — gRPC **코드 6** | 중복 판별 |
| `isFailedPrecondition` | error-handling.md | **`src/firestore/errors.ts`** — `(err: unknown) => boolean` — gRPC **코드 9**. **인덱스 없는 복합 쿼리가 이 코드로 죽는다** — 개발자 실수이지 사용자 입력 문제가 아니므로 4xx로 접으면 원인이 사라진다 | 전제 위반 판별 |
| `isAborted` | error-handling.md | **`src/firestore/errors.ts`** — `(err: unknown) => boolean` — gRPC **코드 10**(트랜잭션 경합). SDK가 이미 재시도한 뒤이므로 **여기까지 온 것은 재시도 소진이다** | 경합 판별 |
| `ERROR_STATUS` | error-handling.md | **`src/http/errors.ts`** — `Record<string, number>` — 도메인 코드 → HTTP 상태. **유일한 매핑표** | 상태 매핑 |
| `toAppError` | error-handling.md | **`src/http/errors.ts`** — `(err: unknown) => AppError` — 에러 핸들러가 **반드시 먼저 호출한다**. 모르는 것은 전부 `INTERNAL`로 접는다(원본 메시지에 프로젝트 ID·문서 경로가 들어 있다) | 정규화 |
| `verifyIdToken` | identity-tokens.md | **`src/identity/verify.ts`** — `(token: string) => Promise<IdTokenClaims>` — **비동기다.** `iss === 'https://securetoken.google.com/' + settings.IDENTITY_PLATFORM_PROJECT_ID` · `aud === settings.IDENTITY_PLATFORM_PROJECT_ID` · `exp`·`iat`를 검증하고, 서명은 JWKS로 확인한다. **모든 실패는 `AppError('UNAUTHENTICATED', …)` 하나로 접는다** — 만료·서명 불일치·발급자 불일치를 구분해 알리면 공격자에게 진단을 준다 | 토큰 검증 |
| `IdTokenClaims` | identity-tokens.md | **`src/identity/verify.ts`** — 최소 `{ sub: string; email?: string; email_verified?: boolean }`. **주체는 `sub`다** — `email`은 바뀔 수 있으므로 소유권 키로 쓰지 않는다 | 클레임 타입 |
| `jwks` | identity-tokens.md | **`src/identity/verify.ts`** **여기가 유일한 정의다** — `createRemoteJWKSet`의 반환. **모듈 최상위에서 한 번 만든다** — 요청마다 만들면 캐시가 없어져 매 요청이 Google에 왕복한다(Cloud Run은 상주 프로세스이므로 이 캐시가 실제로 산다) | JWKS 캐시 |
| `createApp` | project-structure.md | **`src/app.ts`** — `() => Hono` — **요청을 받지 않는다.** 라우터 마운트 + `installErrorHandlers(app)`(이음매) 호출 + `/healthz` 등록만 한다. `apiRouter`(이음매)를 `/api`에 붙인다 | 앱 조립 |
| `startServer` | project-structure.md | **`src/main.ts`** — `() => ServerType` — `@hono/node-server`의 `serve()`로 `settings.PORT`에 붙인다(환경을 직접 읽지 않는다). **`0.0.0.0`에 바인딩한다** — `localhost`에 바인딩하면 컨테이너 밖에서 도달하지 못해 배포가 헬스체크에서 죽는다 | 부팅 |
| `shutdown` | project-structure.md | **`src/main.ts`** — `(server: ServerType) => Promise<void>` — **배수를 수행하는 함수다.** 새 연결을 막고 진행 중 요청을 기다린 뒤 `firestore.terminate()`를 부른다. **호출자가 배선해야 할 것: `process.on('SIGTERM', …)` 핸들러 *안에서* 부른다.** 톱레벨에서 부르면 컨테이너가 부팅 직후 종료된다(node-api 실측 치명). Cloud Run은 SIGTERM 후 **10초**를 준다 | 종료 |
| `log` | project-structure.md | **`src/obs/log.ts`** — `(level: 'info' \| 'warn' \| 'error', message: string, fields?: Record<string, unknown>) => void` — **stdout에 JSON 한 줄**을 쓴다. Cloud Logging은 `severity` 키를 심각도로 읽으므로 `level`이 아니라 **`severity`로 내보낸다**. 비밀·토큰·문서 전문을 필드에 싣지 않는다 | 구조적 로깅 |
| `appFetch` | testing-and-deploy.md | **`test/helpers.ts`** — `(app: Hono, path: string, init?: RequestInit) => Promise<Response>` — `app.request()`로 **네트워크 없이** 앱을 직접 태운다 | 테스트 호출 |
| `withEmulator` | testing-and-deploy.md | **`test/helpers.ts`** — `(fn: () => Promise<void>) => Promise<void>` — 테스트마다 컬렉션을 비운다. **되돌리지 않으면 다음 테스트가 앞 테스트의 문서를 본다** | 테스트 격리 |

## requires — 이음매가 제공해야 한다

`프로젝트`는 이음매가 정의해야 하고, `라이브러리`는 import 문에 이름이 등장하는지로
판정한다. **팩이 호출하는 심볼에는 호출 시그니처를 적는다** — 적지 않으면 이음매가
인자 순서를 추측한다(게이트가 FAIL로 막는다).

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `AppError` | 프로젝트 | `new AppError(code: string, message: string, details?: Record<string, string[]>)` — **앞 두 인자가 모두 `string`이니 순서가 생명이다(코드가 먼저).** 코드표에 반드시 포함: `VALIDATION_FAILED` · **`UNAUTHENTICATED`**(`verifyIdToken`이 던진다 — 빠지면 401이 500으로 나간다) · `FORBIDDEN` · `NOT_FOUND` · `CONFLICT` · `INTERNAL`. **`src/errors.ts`에 둔다** — `src/http/` 아래가 **아니다**: 리포지토리와 커서가 그것을 던지므로 거기 두면 데이터 계층이 HTTP 모듈을 끌어온다 | 에러 코드표와 봉투 형태가 와이어 계약의 함수 |
| `installErrorHandlers` | 프로젝트 | `(app: Hono) => void` — `app.onError`와 `app.notFound`를 건다. **`toAppError`로 먼저 정규화하고 `ERROR_STATUS`로 상태를 정한다.** `createApp`이 부른다 | 응답 봉투가 와이어 계약의 함수 |
| `currentUser` | 프로젝트 | Hono 미들웨어 — `MiddlewareHandler`. 자격 증명을 꺼내 **`verifyIdToken`(팩 제공)에 넘기고** 결과를 `c.set('user', …)`로 심는다. 실패는 `AppError('UNAUTHENTICATED', …)`. **`src/http/auth.ts`에 둔다.** 라우터는 이 미들웨어로만 주체를 얻는다 — 토큰을 직접 파싱하는 라우터가 하나라도 있으면 경계가 둘이 된다 | 토큰이 **어떻게 도착하는지**(베어러 헤더 vs 세션 쿠키)가 조합의 함수 |
| `AuthUser` | 프로젝트 | 최소 `{ id: string; roles: string[] }` — **`id`는 ID 토큰의 `sub`이고 그것이 `ownerId`가 된다** | 위와 같다 |
| `authFor` | 프로젝트 | `(ownerId: string, roles?: string[]) => AuthUser` — 테스트가 `currentUser`를 대체할 때 넘길 주체를 만든다. **동기** | 클레임 형태가 인증 방식의 함수 |
| `apiRouter` | 프로젝트 | `Hono` — 도메인 라우터를 모아 `createApp`이 `app.route('/api', apiRouter)`로 붙인다 | 라우트 구성이 조합의 함수 |

## 알려진 공백

없다. 축-지역 필수 슬롯이 모두 채워지고, 비어 보이는 것(API 엔드포인트 · 인증 경계 ·
완전 예제)은 `pack.json`의 `seamSlots`가 선언한 이음매의 몫이다.

## 예제에 등장하는 앱 심볼 (프로젝트가 만든다)

`provides`도 `requires`도 아니다. 예제에서 이름만 등장하므로 조립 후에도 정의가 없는 것이 정상이다.

| 이름 | 등장 | 성격 |
| --- | --- | --- |
| `TaskService` | project-structure.md (계층 예시) | 서비스 계층 예시 |
