<!-- epcc-pack: backend/node-api v3.13.0 verified 2026-08-23 express@5 @prisma/client@6 prisma@6 zod@4 typescript@5 pino@9 pino-http@10 vitest@2 supertest@7 tsx@4 @types/express@5 @types/node@22 -->

# node-api 축 팩 — 허브 조각

조합 허브(`SKILL.md`)를 만들 때 **그대로 삽입할 축-지역 조각**이다. 사전 제작 이음매가 있는
조합은 이 파일을 쓰지 않는다 — 그 경우 이음매의 `HUB.md`가 허브 전문을 갖는다.

각 조각은 `<!-- pack-slot: 이름 -->` ~ `<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀
있어 프론트엔드 축이 무엇이든 그대로 성립한다. 조합의 함수인 것은 여기 없다 —
파일 끝의 표가 이음매의 몫을 명시한다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
src/
├── index.ts                 # 부팅만 — makeApp() + listen + shutdown 배선
├── app.ts                   # makeApp(): 라우터 마운트 + 미들웨어 순서 (요청을 받지 않는다)
├── env.ts                   # 프로세스 환경을 읽는 **유일한** 파일 (부팅 시점에 검증·실패)
├── db/
│   ├── client.ts            # PrismaClient 싱글턴 — 이 저장소에서 유일한 인스턴스
│   └── tasks.ts             # 쿼리 함수. HTTP를 모른다 (Request·Response를 받지 않는다)
├── schemas/
│   └── task.ts              # Zod 스키마 — 요청 본문·쿼리. DB 제약과 이중으로 건다
├── http/
│   ├── app-error.ts         # AppError — **이음매가 소유한다** (코드 문자열 + details)
│   ├── parse.ts             # parseBody/parseQuery — 검증 실패를 AppError로 정규화
│   ├── errors.ts            # ERROR_STATUS 표 · Prisma 에러 판별 · ZodError 정규화
│   ├── error-handler.ts     # errorHandler — **이음매가 소유한다** (봉투 방출)
│   ├── require-auth.ts      # requireAuth · AuthUser — **이음매가 소유한다** (토큰 검증)
│   └── routers/             # 라우터 — **이음매가 소유한다** (팩은 마운트 지점만 정한다)
├── services/                # 여러 쿼리를 묶는 도메인 로직 (트랜잭션 경계)
├── ops/
│   ├── health.ts            # healthz(liveness) · readyz(readiness)
│   ├── logger.ts            # pino 구조적 로거
│   └── shutdown.ts          # SIGTERM → 연결 배수 → 종료
└── test/
    └── db.ts                # 테스트 DB 연결·격리·정리 + 픽스처(seedTask)

prisma/
├── schema.prisma            # 모델 정의 — 테이블 설계는 T1 데이터 모델링 카드가 정본이다
└── migrations/              # migrate dev로 생성, migrate deploy로 적용 (배포와 분리)

vitest.config.ts             # 'vitest/config'의 defineConfig — 'vite'의 것에는 test 키가 없다
package.json                 # lint:layers 스크립트가 계층 역방향 import를 차단한다
```

**계층은 한 방향으로만 흐른다**: `routers → services → db`. 역방향 import는 계층을
무너뜨리고 쿼리 테스트에 서버를 요구하게 만든다. 예외는 하나뿐이다 (아래 참조).
<!-- /pack-slot -->

<!-- pack-slot: architecture-overview -->
## Architecture Overview

**모듈 해석은 `bundler`** — 상대 import에 확장자를 붙이지 않는다(`'./errors'`). `nodenext`면
확장자 없는 import가 TS2835로 전부 실패해 예제마다 `.js`를 붙여야 한다. 실행은 `tsx`가 맡는다.

**계층 규율의 예외는 정확히 하나다**: `http/app-error.ts`. 도메인 실패를 표현할 공통 타입을
`db/`에 두면 HTTP 계층이 데이터 계층을 타입 의존하게 되어 방향이 뒤집힌다. `AppError`는
HTTP를 모르는 순수 에러 클래스이므로(상태는 `ERROR_STATUS`가 따로 매핑한다) 이름이 `http/`에
있을 뿐 의존은 단방향으로 남는다. **계층 검사 스크립트는 이 예외만 뚫는다.**

**이음매가 소유하는 파일 셋**: `http/app-error.ts` · `http/error-handler.ts` ·
`http/require-auth.ts` · `http/routers/`. import DAG가 `app-error → errors → parse`,
`errors → error-handler`로 순환 없이 닫히는 유일한 배치다 — 경로를 못박지 않으면 팩의
`import { AppError } from './app-error'`가 조립 후 dangling이 된다.
<!-- /pack-slot -->

<!-- pack-slot: core-principles-axis -->
## Core Principles (7 Key Rules)

이 축에는 **행 수준 정책 엔진이 없다.** 애플리케이션이 신뢰된 연결로 PostgreSQL에 붙으므로
규칙 1~3이 유일한 경계다 — "데이터 계층이 백업하니 이중 방어"는 여기서 성립하지 않는다.
`user`는 `requireAuth`가 `req.user`에 실은 `AuthUser`다.

### 1. 소유권은 조회 조건에 있다 — 조회 뒤 비교가 아니다

소유권 필터가 빠진 쿼리는 느려지는 게 아니라 **남의 행을 돌려준다.** 조회 후 비교는 잊기
쉽고 경합에도 뚫린다. 조건에 넣으면 잊는 것 자체가 불가능해진다.
<!-- verified: @prisma/client@6.19.3 generate 후 tsc --strict 로컬 실행 (2026-08-23) -->
Prisma 6의 where-unique 입력은 유니크 필드와 **함께** 비유니크 필터를 받는다 (`ownerId` 단독은 TS2322).
그래도 이 팩은 단건 조회를 **`findFirst`로 통일한다** — `getTask`가 그 형태다.

```ts
// src/services/tasks.ts
// ❌ 조회한 뒤 소유자를 비교한다 — 비교를 빠뜨려도 잡아 줄 계층이 없다
const found = await prisma.task.findUnique({ where: { id } })
if (found && found.ownerId !== user.id) throw new AppError('FORBIDDEN', '권한이 없습니다')
// ✅ 소유권은 조회 조건이다
const task = await prisma.task.findFirst({ where: { id, ownerId: user.id } })
```

### 2. 변이는 영향 행 수로 판정한다

소유권 필터가 걸린 수정·삭제는 남의 행에 대해 **0행 변경으로 조용히 성공한다.** 영향 행 수를
보지 않으면 200이 나가고, 클라이언트는 자기가 남의 데이터를 고쳤다고 믿는다.

```ts
// src/services/tasks.ts
// ❌ 0행 변경을 성공으로 응답한다 — 남의 id를 넣어도 200이 나간다
await prisma.task.updateMany({ where: { id, ownerId: user.id }, data })
return { ok: true }
// ✅ 영향 행 수가 곧 판정이다 — updateMany/deleteMany는 { count }를 돌려준다
const changed = await prisma.task.updateMany({ where: { id, ownerId: user.id }, data })
if (changed.count === 0) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다')
```

### 3. 부재와 미소유는 외부에 같은 응답이다

403이 돌아온다는 사실 자체가 "그 id는 존재한다"는 답이다. 미인가 사용자가 id를 훑어 소유
관계를 그려낼 수 있으므로, 둘을 가르는 정보는 응답이 아니라 로그에만 남긴다.

```ts
// src/services/tasks.ts — 요청 로거를 req로 받는다 (reqId가 붙어야 요청을 이어 붙일 수 있다)
// ❌ 부재는 404, 남의 것은 403 — 응답이 존재를 알려준다
if (!row) throw new AppError('NOT_FOUND', '없습니다')
if (row.ownerId !== user.id) throw new AppError('FORBIDDEN', '권한이 없습니다')
// ✅ 소유권 조건으로 조회했으므로 두 경우가 같은 결과다. 구분은 로그에만 남는다
if (!task) {
  req.log.warn({ taskId: id }, 'task missing or not owned')
  throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다')
}
```

인증 실패도 같다 — 자격 증명이 틀렸는지 계정이 없는지 구분해 알리면 계정 존재가 새어 나간다.

### 4. 입력은 스키마 하나를 지난다 — 환경변수도 입력이다

요청 본문·쿼리는 `TaskCreateSchema`·`TaskUpdateSchema`·`TaskQuerySchema`를 `parseBody`/
`parseQuery`가 적용하고, 실패를 `AppError('VALIDATION_FAILED')`로 정규화한다. 환경변수는
`EnvSchema`를 통과한 `env` 하나만 읽는다 — 누락·형식 오류가 첫 요청이 아니라 **부팅 시점에** 터진다.

```ts
// ❌ 모듈마다 환경변수를 직접 읽는다 — 오타·누락이 배포 몇 시간 뒤 특정 요청에서 터진다
const conn = process.env.DATABASE_URL ?? 'postgresql://localhost:5432/app'
// ✅ 앱 코드에서 프로세스 환경을 읽는 유일한 모듈은 src/env.ts다
import { env } from './env'
const conn = env.DATABASE_URL
```

예외는 테스트 설정 `src/test/db.ts` 하나뿐이다 — 격리 DB URL을 주입한다.

Zod 스키마는 DB 제약(`@unique` · `NOT NULL`)을 **대체하지 않는다** — 두 겹으로 건다.

### 5. 데이터 계층은 HTTP를 모른다

`src/db/*`의 시그니처에 `Request` · `Response` · `NextFunction`이 등장하면 계층이 뒤집힌다 —
쿼리 하나를 시험하는 데 서버가 필요해지고 `routers → services → db` 방향이 무너진다.

```ts
// src/db/tasks.ts
// ❌ 쿼리 함수가 Express 타입을 받는다
import type { Request, Response } from 'express'
// ✅ 파싱된 값만 인자로 받는다. HTTP 해석은 라우터, 봉투 방출은 errorHandler의 몫이다
import type { TaskQuery } from '../schemas/task'
import { prisma } from './client'
```

### 6. 미들웨어 순서가 곧 동작이다 — 에러 미들웨어는 정확히 4인자다

<!-- verified: express@5.2.1 로컬 실행 — 3인자 함수는 건너뛰어지고 4인자만 에러를 받았다 (2026-08-23) -->
3인자로 선언한 에러 핸들러는 Express가 **일반 미들웨어로 취급해** 에러가 그냥 지나간다.
`notFound`는 라우터 **뒤**, `errorHandler`는 **맨 마지막**이다.

```ts
// src/app.ts — makeApp() 내부
// ❌ notFound가 라우터보다 앞이면 모든 요청이 404다. 3인자는 에러 핸들러가 아니다
app.use(notFound)
app.use('/api/tasks', tasksRouter)
app.use((err, req, res) => { res.status(500).json({ error: 'internal' }) })
// ✅ 라우터 → notFound → errorHandler(4인자)
app.use('/api/tasks', tasksRouter)
app.use(notFound)
app.use(errorHandler)
```

### 7. 상태 코드는 도메인 코드에서만 파생된다

라우터가 자기 상태 코드를 고르면 같은 실패가 자리마다 다른 코드로 나간다. 던지는 것은 도메인
코드뿐이고, 상태는 `ERROR_STATUS` 한 표가, 봉투는 `errorHandler` 한 곳이 정한다.

```ts
// src/http/routers/tasks.ts (이음매 소유)
// ❌ 라우터가 상태 코드와 봉투를 직접 만든다
if (!task) return res.status(403).json({ error: 'not yours' })
// ✅ 도메인 코드만 던진다 — 상태 매핑은 ERROR_STATUS가 소유한다
if (!task) throw new AppError('NOT_FOUND', '작업을 찾을 수 없습니다')
```
<!-- /pack-slot -->

<!-- pack-slot: common-imports-axis -->
## Common Imports

경로는 위 Directory Structure 그대로다. 모듈 해석이 `bundler`이므로 **상대 import에 확장자를
붙이지 않는다.** 파일마다 필요한 줄만 고르고, **각 줄이 어느 계층에서 정당한지는 주석이 정한다** —
계층을 건너뛴 import가 규칙 5를 깨는 자리다. 같은 디렉토리 안에서는 경로를 `./`로 줄인다.

```ts
// 라이브러리 — 계층 무관
import { Router } from 'express'                    // 라우터(이음매)에서만
import type { RequestHandler } from 'express'       // 라우터·미들웨어(이음매)에서만
import { z } from 'zod'                             // src/schemas/*
import { Prisma, type Task } from '@prisma/client'

// 팩이 소유하는 모듈 — 경로는 src/<계층>/ 한 단계 아래 기준 (배정은 ledger.md가 정본이다)
import { env } from '../env'                        // 어느 계층이든
import { prisma } from '../db/client'               // src/db/* 에서만
import { listTasks, getTask, insertTask, updateTask, deleteTask } from '../db/tasks'  // 서비스·라우터
import { TaskCreateSchema, TaskUpdateSchema, TaskQuerySchema } from '../schemas/task' // 라우터(이음매)
import type { TaskCreate, TaskUpdate, TaskQuery } from '../schemas/task'              // 서비스·라우터
import { parseBody, parseQuery } from '../http/parse'   // 라우터(이음매)에서만 — Request를 받는다
import { ERROR_STATUS, isUniqueViolation, isRecordNotFound, fieldErrors } from '../http/errors'  // errorHandler(이음매)에서만
import { logger } from '../ops/logger'              // 부팅 경로에서만 — 요청 안에서는 req.log
import { AppError } from '../http/app-error'        // 어느 계층이든 던진다
import { requireAuth } from '../http/require-auth'  // 라우터(이음매)에서만
```

`AppError` · `errorHandler`(`src/http/error-handler.ts`) · `requireAuth`는 **이음매 소유이지만 경로는
축이 고정한다.** `AuthUser`·`tasksRouter`는 이음매가 정의만 하므로 여기 없다.
<!-- /pack-slot -->

<!-- pack-slot: http-status-and-antipatterns -->
## HTTP Status Codes & Anti-Patterns

**상태 코드의 정본은 `error-handling.md`가 소유한 `ERROR_STATUS`다.** 아래는 그 표의 요약이고,
어긋나면 `ERROR_STATUS`가 이긴다 — 이 표를 고치기 전에 `ERROR_STATUS`를 먼저 본다.

| 코드 | 도메인 코드 | 언제 나가는가 |
| --- | --- | --- |
| 200 | — | 조회·수정 성공 (본문 있음) |
| 201 | — | 생성 성공 — `Location: /api/tasks/{id}` |
| 204 | — | 삭제 성공 (본문 없음) |
| 400 | `VALIDATION_FAILED` | 본문·쿼리가 Zod 스키마를 통과하지 못했다. 필드 오류는 `details`에 |
| 401 | `UNAUTHENTICATED` | 자격 증명이 없거나 만료 — `requireAuth`가 던진다 |
| 403 | `FORBIDDEN` | **존재를 이미 아는** 리소스에 대한 행위 거부(역할 부족)에만 쓴다 |
| 404 | `NOT_FOUND` | 부재 **와** 남의 소유. 둘을 가르면 id를 훑어 존재를 알아낼 수 있다 |
| 409 | `CONFLICT` | 고유 제약 충돌 — Prisma `P2002` |
| 413 | `PAYLOAD_TOO_LARGE` | 본문이 파서 한도를 넘었다 — `express.json({ limit })`가 던진다 |
| 500 | `INTERNAL` | 그 외 전부. 원인은 응답이 아니라 로그에만 남긴다 |

422 · 405 · 410은 이 축에 도달 경로가 없다. 새 코드가 필요하면 도메인 코드를 먼저 `ERROR_STATUS`에
넣고 이 표를 갱신한다 — 표를 먼저 늘리면 두 정본이 갈라진다.

### 안티패턴 — Express 5 + Prisma 6에서 실제로 관찰되는 것

<!-- verified: express@5.2.1 · path-to-regexp@8.4.2 · @prisma/client@6.19.3 로컬 실행 (2026-08-23) -->

| ❌ 형태 | 왜 틀렸나 / 대신 |
| --- | --- |
| `asyncHandler(...)` · `express-async-handler` 래핑 | Express 5는 async 핸들러의 거부를 스스로 에러 미들웨어로 보낸다(실행 확인). 래퍼는 순수한 배관 부채다 <!-- verified: express@5.2.1 로컬 실행 — async 핸들러의 throw가 4인자 미들웨어에 도달했다 --> |
| `app.use((err, req, res) => ...)` | 3인자는 **일반 미들웨어**다 — 에러가 그냥 지나가 기본 핸들러로 떨어진다(실행 확인). 에러 미들웨어는 정확히 4인자 <!-- verified: express@5.2.1 로컬 실행 — 3인자 use는 건너뛰어지고 4인자가 err를 받았다 --> |
| `app.use('*', ...)` · `app.get('/*', ...)` | path-to-regexp 8이 `Missing parameter name`으로 **부팅을 실패시킨다**(실행 확인). 경로 없는 `app.use(notFound)` 또는 `'/{*splat}'` <!-- verified: path-to-regexp@8.4.2 — Missing parameter name at index 1 로 부팅 실패 --> |
| `router.get('/:id?', ...)` | 선택 파라미터 `?` 문법이 없다 — `Unexpected ?`로 부팅 실패(실행 확인). `'/{:id}'`를 쓴다 <!-- verified: path-to-regexp@8.4.2 — Unexpected ? at index 4 로 부팅 실패 --> |
| `?filter[status]=open`이 중첩 객체로 온다고 가정 | 기본 쿼리 파서가 `simple`이라 `"filter[status]"`가 통째로 키가 된다(실행 확인). 평평한 키 + `TaskQuerySchema`의 `z.coerce` <!-- verified: express@5.2.1 로컬 실행 — ?a[b]=1 이 {"a[b]":"1"} 로 파싱됐다 --> |
| 라우터에서 `res.status(409).json(...)` | 봉투가 갈라진다. 도메인 코드를 `AppError`로 던지고 `errorHandler` 한 곳에서만 방출한다 |
| `prisma.$queryRawUnsafe`로 정렬 컬럼 넘기기 | 태그드 `$queryRaw`조차 **식별자는 파라미터화하지 못한다** — 정렬 컬럼은 허용 목록으로 좁힌다 |
| `console.log`로 요청 로그 | 레벨·요청 상관관계·직렬화가 없어 운영에서 검색되지 않는다. `logger`(pino) + `pino-http` |
<!-- /pack-slot -->

## 이음매가 채울 것

| 슬롯 | 왜 조합의 함수인가 |
| --- | --- |
| `api-endpoints` | 라우터 형태 + 요청/응답 봉투. 봉투는 와이어 계약이 정한다 |
| `auth-boundaries` | 토큰 검증 방식이 프론트 축에 서버 런타임이 있는지에 달렸다 |
| `complete-example` | 마이그레이션 → 스키마 → 쿼리 → 서비스 → 라우터 → 테스트 관통 |
