<!-- epcc-pack-ledger: backend/firebase v3.14.0 -->

# firebase 팩 — 심볼 원장 (L0 선언본)

저작 전에 메인 세션이 선언한 계약이다. 클러스터를 갈라 병렬로 써도 중복 정의와 **시그니처
추측**이 생기지 않게 하는 유일한 장치다.

## provides — 이 팩이 정의한다

**「형태」 열은 의무다.** 소유 파일만 배정하고 형태를 비우면 형제 클러스터가 시그니처를
추측한다 — 실측에서 `getTask(ownerId, id)`를 다른 클러스터가 `getTask(id, ownerId)`로 불렀고
두 인자가 모두 `string`이라 TypeScript도 게이트도 잡지 못해 모든 단건 조회가 404가 됐다.
인자 **순서** · 반환 · 실패 시 던지는 것 · **호출자가 배선해야 하는 것**을 함께 적는다.

**이 팩에서 특히 위험한 자리 둘**:
① `ownerId`와 `taskId`가 **둘 다 `string`**이다. 전 함수에서 **`ownerId` → `taskId`** 순서를
고정한다.
② **필드 소비 의무** — 시그니처가 맞아도 인자의 *내용*을 안 쓰면 같은 부류의 치명 결함이
된다(aws-serverless 실측: 생성 함수가 `status`를 버려 그 값으로 만든 문서가 목록에서
영영 사라졌다).

| 심볼 | 정의 파일 | 형태 | 성격 |
| --- | --- | --- | --- |
| `TaskDoc` | data-modeling.md | **`functions/src/firestore/model.ts`** — `{ id: string; title: string; status: TaskStatus; ownerId: string; createdAt: Timestamp; updatedAt: Timestamp }` — **`id`는 문서 ID의 사본이다**(쿼리 결과를 그대로 직렬화할 수 있게). `createdAt`은 `FieldValue.serverTimestamp()`로 쓰고 **클라이언트 시각을 믿지 않는다** | 문서 형태 |
| `TaskStatus` | data-modeling.md | **`functions/src/firestore/model.ts`** — `'open' \| 'done'` — 규칙·스키마·쿼리가 **같은 리터럴 집합**을 쓴다. 규칙에도 이 목록이 문자열로 박히므로 늘릴 때 두 곳을 함께 고친다 | 상태 열거 |
| `COLLECTION` | data-modeling.md | **`functions/src/firestore/model.ts`** — `const COLLECTION = 'tasks'` — 컬렉션 이름을 조립하는 **유일한 자리**. 규칙 경로와 이 상수가 갈라지면 규칙이 다른 컬렉션을 지킨다 | 컬렉션 이름 |
| `taskConverter` | data-modeling.md | **`functions/src/firestore/model.ts`** — `FirestoreDataConverter<TaskDoc>` — `toFirestore`/`fromFirestore`. **`fromFirestore`가 `id`를 스냅숏에서 채운다.** 컨버터 없이 `snap.data()`를 쓰면 `id`가 없는 객체가 돌아다닌다 | 타입 컨버터 |
| `rulesForTasks` | security-rules.md | **`firestore.rules`** — `firestore.rules`의 `match /tasks/{taskId}` 블록 — `read`·`create`·`update`·`delete`를 **따로** 쓴다. `write` 하나로 묶으면 생성과 수정의 불변식이 달라 둘 중 하나가 반드시 헐거워진다 | 보안 규칙 |
| `isOwner` | security-rules.md | **`firestore.rules`** — 규칙 함수 `isOwner(res)` — `request.auth != null && res.data.ownerId == request.auth.uid`. **`update`에서는 `resource`(기존)와 `request.resource`(새것) 양쪽을 본다** — 새것만 보면 소유자를 남에게 넘기는 수정이 통과한다 | 규칙 함수 |
| `db` | data-access.md | **`functions/src/firestore/client.ts`** — `Firestore` — `getFirestore()`의 결과를 **모듈 최상위**에서 잡는다(콜드 스타트 밖). `initializeApp()`은 한 번만 부른다 — **다만 같은 옵션으로 다시 부르면 예외 없이 조용히 첫 app이 돌아온다**(옵션이 다를 때만 `app/duplicate-app`). 즉 중복 호출은 런타임이 아니라 규율이 막는다 (C2 실측) | admin 클라이언트 |
| `listTasks` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(ownerId: string, q: TaskQuery) => Promise<{ items: TaskDoc[]; cursor?: string }>` — `where('ownerId','==',ownerId)`가 **유일한 경계**다. `orderBy('createdAt','desc')` + `startAfter`로 넘긴다 | 목록 |
| `getTask` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(ownerId: string, taskId: string) => Promise<TaskDoc \| null>` — **두 `string`의 순서가 생명이다.** 문서를 읽은 뒤 `ownerId` 일치를 확인하고 다르면 `null`(예외 아님) — 문서 ID만으로는 남의 것도 읽힌다 | 단건 |
| `createTask` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(ownerId: string, input: TaskCreate) => Promise<TaskDoc>` — **`input`의 `title`과 `status`를 모두 옮긴다.** `status`를 하드코딩하면 클라이언트가 보낸 값이 조용히 사라진다. `ownerId`는 인증 컨텍스트에서만 온다 | 생성 |
| `updateTask` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(ownerId: string, taskId: string, patch: TaskUpdate) => Promise<TaskDoc>` — **존재+소유를 트랜잭션 안에서 확인한 뒤** 쓴다. 확인과 쓰기를 나누면 그 사이에 소유자가 바뀔 수 있다. 없거나 남의 것이면 `AppError('NOT_FOUND')` | 수정 |
| `deleteTask` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(ownerId: string, taskId: string) => Promise<void>` — **`delete()`는 없는 문서에도 성공한다.** 트랜잭션 안에서 존재+소유를 확인하고 아니면 `AppError('NOT_FOUND')`. 확인하지 않으면 남의 것을 지우라는 요청도 성공으로 답한다 | 삭제 |
| `encodeCursor` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(createdAt: Timestamp, taskId: string) => string` — 불투명 문자열. 내부 정렬 키를 와이어 계약으로 만들지 않는다 | 커서 인코딩 |
| `decodeCursor` | data-access.md | **`functions/src/firestore/tasks.ts`** — `(cursor: string) => { createdAt: Timestamp; taskId: string }` — 실패는 `AppError('VALIDATION_FAILED')`. **커서는 신뢰 입력이 아니다** | 커서 디코딩 |
| `TaskCreateSchema` | input-validation.md | **`functions/src/schemas/task.ts`** — `z.strictObject` — 미지 키를 **거부**한다. `status`는 기본값 `'open'` | 생성 본문 |
| `TaskUpdateSchema` | input-validation.md | **`functions/src/schemas/task.ts`** — 부분 수정. **선택 필드에 `.default()`를 겹치지 않는다** — 겹치면 보내지 않은 필드가 기본값으로 저장을 덮어쓴다 | 수정 본문 |
| `TaskQuerySchema` | input-validation.md | **`functions/src/schemas/task.ts`** — `z.object` — `limit`(1~100, 기본 20) · `cursor?` · `status?` | 목록 쿼리 |
| `TaskCreate` · `TaskUpdate` · `TaskQuery` | input-validation.md | 각 스키마의 `z.output` | 파생 타입 |
| `REGION` | input-validation.md | **`functions/src/params.ts`** — `defineString('TASKS_REGION', …)`. **모듈 최상위에서 선언하고 `.value()`는 핸들러 안에서 부른다** — 최상위 호출은 배포 분석 단계에서 터진다 | 함수 파라미터 |
| `PAGE_MAX` | input-validation.md | **`functions/src/params.ts`** — `defineInt('TASKS_PAGE_MAX', …)` | 함수 파라미터 |
| `WEBHOOK_KEY` | input-validation.md | **`functions/src/params.ts`** — `defineSecret('TASKS_WEBHOOK_KEY')` | 비밀 파라미터 |
| `Config` | input-validation.md | **`functions/src/params.ts`** — `z.output<typeof ConfigSchema>` | 구성 타입 |
| `config` | input-validation.md | **`functions/src/params.ts`** — `config() => Config` — 파라미터 값을 Zod로 검증해 캐시한다. **핸들러 안에서 부른다**. **키는 환경변수 이름 그대로다**(`TASKS_PAGE_MAX` · `TASKS_WEBHOOK_KEY`) — camelCase로 바꾸지 않는다. 선언한 파라미터와 이름이 같아야 빠진 것이 눈에 보인다(실측: 형제 클러스터가 `{ pageMax }`로 구조분해해 `undefined`가 됐다) | 구성 접근자 |
| `parseCallable` | input-validation.md | **`functions/src/schemas/task.ts`** — `<S extends z.ZodType>(schema: S, data: unknown) => z.output<S>` — `onCall`의 `request.data`를 검증한다. 실패는 `AppError('VALIDATION_FAILED')` | 호출 본문 파싱 |
| `logger` | functions-patterns.md | **`functions/src/obs/logger.ts`** — `firebase-functions/logger` 재노출. **`console.log`를 쓰지 않는다** — 구조적 필드가 사라져 Cloud Logging에서 질의할 수 없다 | 구조적 로거 |
| `withErrors` | functions-patterns.md | **`functions/src/obs/logger.ts`** — `<T>(h: (req: CallableRequest) => Promise<T>) => (req: CallableRequest) => Promise<T>` — `AppError`를 `HttpsError`로 옮기고 미처리 예외를 로깅한 뒤 **일반 문구로 접는다**. **핸들러를 감싸 export한다** | 핸들러 래퍼 |
| `requireUid` | functions-patterns.md | **`functions/src/obs/logger.ts`** — `(req: CallableRequest) => string` — 동기. `req.auth?.uid`가 없으면 `AppError('UNAUTHENTICATED')`. **`onCall`은 토큰을 자동 검증하지만 없는 것을 막지는 않는다** | 주체 추출 |
| `emulatorEnv` | testing-and-deploy.md | **`functions/test/emulator.ts`** — `() => void` — 테스트 전에 `FIRESTORE_EMULATOR_HOST` 등을 세운다. **실 프로젝트로 테스트가 새는 것을 막는 유일한 장치다** | 에뮬레이터 배선 |
| `withRulesTest` | testing-and-deploy.md | **`functions/test/emulator.ts`** — `(fn: (env: RulesTestEnvironment) => Promise<void>) => Promise<void>` — `@firebase/rules-unit-testing`의 환경을 열고 반드시 닫는다. 닫지 않으면 다음 테스트가 앞 규칙으로 돈다 | 규칙 테스트 하네스 |

## 테스트 파일의 소유자 — **한 경로에 한 소유자**

같은 논리 파일을 두 클러스터가 각자 배송하면 **경로가 달라 게이트의 중복 펜스 검사에도
걸리지 않는다** — 실측에서 `rules.test.ts`가 서로 다른 경로·서로 다른 내용으로 이중
출하됐고 두 파일의 「차단 증명」 결론이 정면으로 모순됐다.

| 파일 | 소유 리소스 | 내용 |
| --- | --- | --- |
| `functions/test/emulator.ts` | testing-and-deploy.md | `emulatorEnv` · `withRulesTest` · `RULES` |
| `functions/test/rules.test.ts` | **security-rules.md** | 규칙 단위 테스트 전량. 다른 리소스는 **참조만** 한다 |
| `functions/test/tasks.test.ts` | testing-and-deploy.md | 함수(`onCall`) 회귀 |
| `functions/test/repo.test.ts` | data-access.md | 리포지토리 직접 호출 회귀 — 콜러블을 거치지 않는다 |

**모든 테스트는 `functions/test/` 아래에 둔다** — 루트 `test/`를 쓰지 않는다.

## 팩이 export하는 함수 진입점 — **이름을 여기서 고정한다**

`functions/src/index.ts`가 export하는 이름이다. **소유는 이음매**(`api-endpoints`가 어떤
엔드포인트가 존재하는지 정한다)이지만 **이름은 축이 고정한다** — 고정하지 않으면 클러스터마다
다르게 부르고, 실측에서 실제로 그랬다(`tasksCreate` ↔ `createTask`로 갈려 테스트 파일이
적재조차 되지 않았다). 리포지토리 심볼(`createTask` 등)과 **이름이 겹치지 않게** 접두형을 쓴다.

| export | 리포지토리 대응 |
| --- | --- |
| `tasksList` | `listTasks` |
| `tasksGet` | `getTask` |
| `tasksCreate` | `createTask` |
| `tasksUpdate` | `updateTask` |
| `tasksDelete` | `deleteTask` |

**`tasksGet`은 없는 문서에 `null`을 돌려주지 않는다** — `AppError('NOT_FOUND')`를 던지고
`withErrors`가 `HttpsError('not-found')`로 옮긴다. `null` 반환은 리포지토리 `getTask`의
계약이지 콜러블의 계약이 아니다.

## requires — 이음매가 제공해야 한다

| 심볼 | 종류 | 팩이 가정하는 형태 | 왜 이음매인가 |
| --- | --- | --- | --- |
| `AppError` | 프로젝트 | `new AppError(code: string, message: string, details?: Record<string, string[]>)` — **뒤 두 인자가 모두 `string`이니 순서가 생명이다.** 코드표에 반드시 포함: `VALIDATION_FAILED` · **`UNAUTHENTICATED`**(`requireUid`가 던진다) · `NOT_FOUND` · `CONFLICT` · `FORBIDDEN` · `INTERNAL` | 에러 코드표가 와이어 계약의 함수 |
| `toHttpsError` | 프로젝트 | `toHttpsError(e: unknown) => HttpsError` — `AppError`를 Firebase의 `HttpsError` 코드로 옮긴다. **`withErrors`가 부른다** | 봉투가 와이어 계약의 함수 |
| `AuthUser` | 프로젝트 | 최소 `{ uid: string; roles: string[] }` — 커스텀 클레임에서 뽑는다 | 클레임 형태가 인증 방식의 함수 |
| `authFor` | 프로젝트 | `authFor(uid: string, roles?: string[]) => Partial<CallableRequest>` — 테스트가 함수에 넘길 인증 컨텍스트 조각을 만든다. **동기**. **팩은 이 이름을 지역 정의하지 않는다** — 정의하면 조립 후 정의가 둘이 된다(실측: react-vite 팩이 같은 실수를 했다). 팩의 테스트가 임시 주체가 필요하면 `fakeAuth` 같은 다른 이름을 쓴다 | 위와 같다 |
| `clientAccessPolicy` | 프로젝트 | `'rules-only' \| 'functions-only' \| 'both'` — **프론트가 SDK로 Firestore를 직접 읽는가**를 선언한다. 이 값이 규칙과 함수 중 어느 쪽이 주 경계인지를 바꾸므로 조합이 정한다 | 접근 경로가 조합의 함수 |

## 게이트 REVIEW의 정당화 (침묵 통과 금지)

| REVIEW | 판정 |
| --- | --- |
| 원장에 없는 export: `tasksList`·`tasksGet`·`tasksCreate`·`tasksUpdate`·`tasksDelete` | **정상 — 이음매가 소유를 결정한다.** 이 축에서는 함수가 곧 엔드포인트이므로 「어떤 엔드포인트가 존재하는가」는 `api-endpoints` 이음매 슬롯의 몫이다(프론트가 SDK로 직접 읽는 조합이면 개수가 줄거나 0이 된다). 팩은 **형태를 보이는 예제**로 다섯을 export하고, 이음매는 그것을 그대로 쓰거나 골라 쓰거나 다시 쓴다. 원장 `provides`에 넣으면 「팩이 계약으로 고정했다」는 뜻이 되어 이음매의 결정권을 뺏는다 |
| 유령 정의: `tasksCreate`·`tasksUpdate`·`tasksDelete` | **위와 같은 이유로 정상.** 세 변이 함수는 `functions/src/index.ts`가 export하는 진입점이고 **소비처는 클라이언트 SDK와 배포 파이프라인**이지 가이드 본문이 아니다. `tasksList`·`tasksGet`은 테스트가 부르므로 이 목록에 없다 |
| 원장에 없는 export: `TaskStatusSchema` | **정상.** `TaskStatus` 리터럴 유니온의 Zod 대응물이고 `TaskCreateSchema`·`TaskUpdateSchema`·`TaskQuerySchema`가 재사용한다. 원장이 `TaskStatus`를 이미 고정했으므로 그 파생을 다시 고정할 필요가 없다 |
| 원장에 없는 export: `PROJECT_ID`·`RULES` | **정상.** 규칙 단위 테스트 하네스의 지역 상수다(`withRulesTest`가 쓴다). 이음매도 다른 파일도 참조하지 않는다 |

## 알려진 공백

없다. 축-지역 필수 슬롯이 모두 채워지고, 비어 보이는 것(API 엔드포인트 · 인증 경계 ·
완전 예제)은 `pack.json`의 `seamSlots`가 선언한 이음매의 몫이다.
