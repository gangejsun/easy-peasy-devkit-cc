---
name: backend-guide
description: "[Preset: react-vite × aws-container] Hono + TypeScript container backend for React SPA clients: HTTP routes, Drizzle ORM with drizzle-kit migrations on RDS PostgreSQL, Zod validation, Cognito OIDC/JWKS verification, ownership checks, Vitest, ECS/Fargate portability. Use when creating or modifying Hono routes, Drizzle schemas or migrations, Zod schemas, JWT auth guards, REST endpoints, or backend tests. Use ONLY when the active preset matches."
---
<!-- epcc-guide-baseline: verified 2026-08-22 hono@4 @hono/node-server@1 typescript@5 drizzle-orm@0 drizzle-kit@0 pg@8 jose@5 zod@4 vitest@2 aws-cdk-lib@2 @aws-sdk/client-s3@3 @aws-sdk/s3-request-presigner@3 -->

React + Vite SPA를 클라이언트로 두는 컨테이너 백엔드 가이드다. 프론트엔드에 서버 런타임이
없으므로 **서버 로직 전부를 이 백엔드가 소유**하고, 브라우저가 이 REST API를 직접 호출한다.

## Quick Start

### 신규 엔드포인트 추가

- [ ] `src/schemas/<resource>.ts`에 Zod 요청/응답 스키마를 정의한다 — PATCH 스키마는
      **기본값 없는 base**에서 갈라 만든다 (`Create.partial()`은 미지정 필드를 덮어쓴다)
- [ ] 필요한 테이블이 `src/db/schema.ts`에 있는지 확인한다 — 없으면 아래 체크리스트를 먼저 수행
- [ ] `src/db/queries/<resource>.ts`에 쿼리를 추가한다 — **첫 인자는 항상 `ownerId`**
- [ ] `src/services/<resource>.ts`에 도메인 규칙과 소유권 판정을 넣는다
- [ ] `src/routes/<resource>.ts`에 라우트를 추가하고 `requireAuth`를 건다
- [ ] 핸들러 첫 줄에서 `jsonBody(c, Schema)` / `queryParams(c, Schema)`로 파싱한다
- [ ] 변이는 `.returning()` 결과가 비면 404를 던진다 — 0행을 200으로 응답하지 않는다
- [ ] `src/app.ts`에 서브 앱이 마운트됐는지 확인한다
- [ ] 핸들러 테스트 1개 + 실 DB 통합 테스트 1개를 추가한다 (`docker compose up -d --wait db`)

### 스키마 변경 / 마이그레이션

- [ ] `.claude/rules/data-modeling.md`를 열어 테이블 설계 규칙을 먼저 확인한다
- [ ] `src/db/schema.ts`를 수정한다 — 소유자 컬럼(`owner_id`)과 조회 인덱스를 함께 넣는다
- [ ] `npx drizzle-kit generate`로 SQL을 생성한다 — 손으로 SQL을 먼저 쓰지 않는다
- [ ] 생성된 `drizzle/*.sql`을 읽고 파괴적 구문(DROP, NOT NULL 추가)이 있는지 확인한다
- [ ] `docker compose up -d --wait db` 후 `npx drizzle-kit migrate`로 로컬에 적용한다
- [ ] 통합 테스트를 돌려 기존 쿼리가 깨지지 않는지 확인한다
- [ ] 파괴적 변경은 다단계로 나눈다 (컬럼 추가 → 백필 → NOT NULL 승격)
- [ ] 스키마 수정과 생성된 마이그레이션 파일을 **같은 커밋**에 넣는다

## Architecture Overview

```
브라우저 (React + Vite SPA)
   │  Authorization: Bearer <access token>   (CORS 교차 출처)
   ▼
ALB  ──►  ECS/Fargate : Hono 컨테이너 (표준 HTTP 서버)
                │
                ├─► RDS PostgreSQL (신뢰된 연결, Drizzle ORM)
                └─► JWKS 공개키 캐시 ◄── Cognito (OIDC 발급자)
```

- **SPA는 서버가 아니다**: 인증·권한·비즈니스 규칙·비밀 값은 전부 백엔드에만 존재한다.
  브라우저로 내려간 값은 모두 공개 값으로 취급한다
- **요청 흐름**: `routes/`(HTTP 계약) → `schemas/`(Zod 파싱) → `services/`(도메인 규칙·소유권)
  → `db/queries/`(SQL). 역방향 import 금지 — `db/queries/`는 Hono `Context`를 모른다
- **신뢰 경계는 애플리케이션 층 하나뿐이다**: 이 스택에는 행 수준 정책 엔진이 없다.
  앱은 신뢰된 자격증명으로 DB에 붙으므로 **데이터 계층이 백업해 주지 않는다**.
  소유권 필터를 빠뜨린 쿼리 한 줄이 곧 데이터 유출이다
- **Cognito는 발급자일 뿐이다**: 검증은 표준 OIDC/JWKS로 하고 앱 코드는 벤더 SDK에
  의존하지 않는다 → `resources/portability-boundaries.md`
- **로컬 = 운영**: `docker compose`가 앱과 PostgreSQL 16을 함께 띄우므로 마이그레이션과
  통합 테스트를 실제로 실행해 검증한다

## Directory Structure

```
src/
├─ index.ts             # 부팅: serve(), SIGTERM 처리, Pool 종료
├─ app.ts               # Hono 앱 조립: 미들웨어 → 공개 라우트 → requireAuth → 보호 라우트
├─ config/env.ts        # 검증된 환경변수 단일 진입점 (부팅 시 1회 safeParse)
├─ http/
│  ├─ types.ts          # AppEnv — c.get/c.set 타입 (프로젝트 전역 1회 선언)
│  ├─ errors.ts         # AppError, 에러 코드표, onError 매핑
│  ├─ validate.ts       # jsonBody() / queryParams() / pathParam() 파싱 헬퍼
│  ├─ auth.ts           # makeRequireAuth(verify) 팩토리 + requireAuth (OIDC/JWKS)
│  ├─ return-path.ts    # safeReturnPath — 복귀 경로 검증 (오픈 리다이렉트 차단)
│  └─ logger.ts         # stdout 구조화 JSON 로거 + requestId
├─ routes/
│  ├─ auth.ts           # 로그인·로그아웃 URL + state 서명/검증 (공개 라우트)
│  └─ tasks.ts          # 리소스별 서브 앱 (HTTP 계약만)
├─ services/tasks.ts    # 도메인 규칙 + 소유권 판정
├─ db/
│  ├─ client.ts         # pg Pool + drizzle 인스턴스 (싱글턴)
│  ├─ schema.ts         # Drizzle 테이블 정의 (마이그레이션의 원본)
│  ├─ errors.ts         # SQLSTATE → 도메인 에러 변환 (23505 → 409)
│  └─ queries/tasks.ts  # 쿼리 전용 — 모든 함수가 ownerId를 받는다
├─ storage/
│  ├─ index.ts          # ObjectStorage 포트 (앱 코드가 보는 유일한 타입)
│  └─ s3.ts             # 유일하게 AWS SDK를 아는 파일 (S3_ENDPOINT로 MinIO 호환)
└─ schemas/tasks.ts     # Zod 요청/응답 DTO
drizzle/                # drizzle-kit 생성 SQL + meta/ (손으로 편집 금지)
tests/{unit,handler,integration}/ + tests/test-env.ts
docker-compose.yml      # app + postgres:16 (+ docker/init-test-db.sql)
drizzle.config.ts · Dockerfile
infra/                  # AWS CDK — src/ 에서 절대 import하지 않는다
```

## Core Principles (6 Key Rules)

### 1. 신뢰 경계에서 Zod로 파싱한다 — 검증이 아니라 파싱이다

요청 본문·쿼리·경로 파라미터는 전부 `unknown`이다. 파싱 결과 타입만 아래로 흘려보낸다.

```ts
// ✅ 파싱된 값만 서비스로 넘어간다
const body = await jsonBody(c, CreateTaskInput)   // 실패 시 422 봉투로 throw
const task = await createTask(user.sub, body)

// ❌ 캐스팅은 검증이 아니다 — 런타임에 아무것도 막지 못한다
const body = (await c.req.json()) as CreateTaskInput
await createTask(user.sub, body)   // title: 12MB 문자열도 그대로 통과
```

`z.infer<typeof CreateTaskInput>`을 서비스 시그니처에 쓰면 스키마가 곧 계약이 된다.
DB 제약(`notNull`, unique index, check)으로 한 번 더 건다 → `resources/input-validation.md`

### 2. 환경변수는 부팅 시 한 번 검증한다

`process.env`를 앱 코드에서 직접 읽지 않는다. 누락은 첫 요청이 아니라 **부팅에서** 죽어야 한다.

```ts
// ✅ src/config/env.ts — 단일 진입점, import 시점에 1회 검증
const parsed = EnvSchema.safeParse(process.env)
if (!parsed.success) { logInvalidEnvKeys(parsed.error); process.exit(1) }   // 배포가 롤백된다
export const env = parsed.data

// ❌ 사용처마다 직접 읽기 — 오타·누락이 배포 후 특정 경로에서만 터진다
const pool = new Pool({ connectionString: process.env.DATABSE_URL })   // undefined
```

부팅 검증은 **`safeParse` + `process.exit(1)` 한 형태만** 쓴다 (`parse`의 예외는 어느 키가
빠졌는지를 로그에서 잃는다). 서버 비밀은 브라우저 번들에 인라인되는 접두사(`VITE_*`)에 절대
두지 않고, 공개 변수와 비밀은 스키마를 분리한다 → `resources/input-validation.md`

### 3. 소유권 필터는 쿼리 안에 있어야 한다

이 스택에는 데이터 계층 방어선이 없다. 조회·변이 **모든** 쿼리에 소유자 조건을 넣는다.

```ts
// ✅ 소유권이 WHERE 절에 있다 — 남의 행은 애초에 반환되지 않는다
export function findOwnedTask(ownerId: string, id: string) {
  return db.select().from(tasks)
    .where(and(eq(tasks.id, id), eq(tasks.ownerId, ownerId))).limit(1)
}

// ❌ 전체에서 꺼낸 뒤 코드로 거른다 — 거르기를 잊는 순간 유출이고, 로그·캐시에도 남는다
export function findTask(id: string) {
  return db.select().from(tasks).where(eq(tasks.id, id)).limit(1)
}
```

쿼리 함수 시그니처의 첫 인자를 `ownerId`로 고정하면 누락이 타입 에러로 드러난다.

### 4. 부재와 미인가는 동일한 응답이다 (존재 누설 금지)

403과 404를 구분해 응답하면 미인가 사용자가 리소스 존재를 열거할 수 있다.

```ts
// ✅ 소유 조건으로 조회하고, 없으면 404 하나로 응답한다
const task = await findOwnedTask(user.sub, id)
if (!task) throw new AppError(404, 'NOT_FOUND', 'Task not found')

// ❌ 존재 여부를 알려준다 — id를 훑으면 남의 리소스 목록이 만들어진다
const task = await findTask(id)
if (!task) throw new AppError(404, 'NOT_FOUND', 'Task not found')
if (task.ownerId !== user.sub) throw new AppError(403, 'FORBIDDEN', 'Not your task')
```

토큰 검증 실패도 사유를 구분하지 않는다 — 만료·서명 불일치·발급자 불일치 모두 동일한
401 `UNAUTHORIZED` 봉투다. 403은 **소유자가 아닌 축**(관리자 전용 등)에만 쓴다.

### 5. 변이는 영향 행 수를 확인한다

0행 변이를 성공으로 응답하면 "지웠다고 했는데 남아 있는" 버그가 조용히 생긴다.

```ts
// ✅ .returning() 결과가 비면 대상이 없거나 내 것이 아니다 → 404
const [updated] = await db.update(tasks).set({ title, updatedAt: new Date() })
  .where(and(eq(tasks.id, id), eq(tasks.ownerId, ownerId))).returning()
if (!updated) throw new AppError(404, 'NOT_FOUND', 'Task not found')

// ❌ 결과를 버린다 — 남의 id로 호출해도 204가 나간다
await db.delete(tasks).where(and(eq(tasks.id, id), eq(tasks.ownerId, ownerId)))
return c.body(null, 204)
```

### 6. 벤더 SDK는 인프라 층에 가둔다

회사는 이 백엔드를 온프레미스로 옮길 수 있다. `src/` 아래에 AWS 전용 API가 들어오면 이관이
코드 재작성이 된다.

```ts
// ✅ 표준 OIDC 검증 — issuer/JWKS URL 교체만으로 다른 IdP로 넘어간다
import { createRemoteJWKSet, jwtVerify } from 'jose'
const jwks = createRemoteJWKSet(new URL(env.OIDC_JWKS_URL))

// ❌ Cognito 전용 라이브러리·SDK를 앱 코드가 직접 안다
import { CognitoJwtVerifier } from 'aws-jwt-verify'   // 이관 시 전량 재작성
```

로그는 CloudWatch SDK가 아니라 **stdout 구조화 JSON**으로 쓴다. 판단 기준표는
`resources/portability-boundaries.md`.

## Common Imports

```ts
// HTTP 층
import { Hono } from 'hono'
import { cors } from 'hono/cors'
import { bodyLimit } from 'hono/body-limit'
import { createMiddleware } from 'hono/factory'
import { HTTPException } from 'hono/http-exception'
import { serve } from '@hono/node-server'

// 검증 / 인증 (표준 OIDC — 벤더 SDK 아님)
import { z } from 'zod'
import { createRemoteJWKSet, jwtVerify } from 'jose'

// 데이터 액세스
import { drizzle } from 'drizzle-orm/node-postgres'
import { Pool } from 'pg'
import { and, desc, eq, inArray, isNotNull, isNull, sql } from 'drizzle-orm'
import { index, pgTable, text, timestamp, uuid } from 'drizzle-orm/pg-core'

// 테스트
import { afterEach, beforeAll, describe, expect, it } from 'vitest'

// 프로젝트 내부 (tsconfig paths + vitest alias에 '@/' → 'src/' 등록)
import { env } from '@/config/env'
import { db } from '@/db/client'
import { AppError } from '@/http/errors'
```

## HTTP Status Codes & Anti-Patterns

| 상황 | 코드 | 봉투 `error.code` |
| --- | --- | --- |
| 조회 성공 / 생성 성공 / 삭제 성공 | 200 / 201 / 204 | — |
| JSON 파싱 불가, 잘못된 쿼리 형식 | 400 | `BAD_REQUEST` |
| 토큰 없음·만료·서명 불일치 (사유 구분 없음) | 401 | `UNAUTHORIZED` |
| 인증됐으나 역할·스코프 부족 (소유권 아님) | 403 | `FORBIDDEN` |
| 리소스 부재 **또는** 미인가 접근 | 404 | `NOT_FOUND` |
| unique 제약 위반, 상태 충돌 | 409 | `CONFLICT` |
| 스키마 검증 실패 (형식은 맞으나 규칙 위반) | 422 | `VALIDATION_FAILED` |
| 예상 못 한 예외 (내부 메시지 노출 금지) | 500 | `INTERNAL` |

**Anti-Patterns**

- 200으로 응답하고 본문에 `{ ok: false }`를 담는다 → 클라이언트가 에러를 놓친다
- `catch (e) { console.error(e) }` 후 계속 진행 → 실패가 성공으로 보고된다
- `app.use('*', requireAuth)`를 `/healthz` **앞에** 등록 → ALB 헬스체크가 401로 죽는다.
  Hono는 등록 순서대로 실행하므로 공개 경로(`/healthz`, `/api/auth`)를 **먼저** 등록한다
- 서버 부팅 시 마이그레이션 실행 → 여러 Fargate 태스크가 동시에 부팅하며 경합한다.
  마이그레이션은 배포 파이프라인의 **별도 일회성 태스크**로 돌린다
- 에러 메시지에 DB 제약명·SQL·스택을 담아 클라이언트로 반환 → 스키마가 새어 나간다
- 목록 응답에 `limit` 없이 전체 반환 → 행이 늘면 조용히 타임아웃한다
- SPA가 보낸 `ownerId`/`role`을 신뢰 → 소유자는 **검증된 토큰의 `sub`**에서만 온다

## Navigation Guide

| 하려는 일 | 읽을 파일 |
| --- | --- |
| 라우트·핸들러 추가, 요청/응답 봉투, 페이지네이션 계약, CORS | `resources/api-endpoints.md` |
| 상태 코드 매핑, 에러 코드표, `onError` 전역 처리, PostgreSQL 에러 변환 | `resources/api-endpoints.md` |
| Drizzle 쿼리·트랜잭션, 소유권 필터, 영향 행 확인, 마이그레이션 실행 | `resources/data-access.md` |
| **테이블·컬럼·인덱스 설계 규칙** (정규화, 키, 제약) | `.claude/rules/data-modeling.md` |
| Zod 스키마 작성, 요청 파싱 헬퍼, DB 제약 이중화 | `resources/input-validation.md` |
| 환경변수 스키마, 비밀/공개 값 분리, 부팅 시 실패 | `resources/input-validation.md` |
| 토큰 검증, `requireAuth` 배선, 역할·스코프, 로그인/로그아웃 흐름, 복귀 경로 검증 | `resources/auth-and-permissions.md` |
| Vitest 설정, 핸들러 테스트, 실 DB 통합 테스트, 테스트용 토큰 서명 | `resources/testing.md` |
| `docker compose` 로컬 패리티, 통합 테스트 DB 초기화·격리 | `resources/testing.md` |
| AWS 종속을 인프라 층에 가두기, 온프레미스 이관 체크리스트, 로깅·저장소·비밀 | `resources/portability-boundaries.md` |
| Dockerfile, 배포 순서(마이그레이션 별도 태스크), 헬스체크·셧다운, 풀 사이징, 느린 쿼리·N+1 관측 | `resources/deployment-and-operations.md` |
| `docker-compose.yml` 전문, 로컬 스모크 체크, 온프레미스에서 달라지는 지점 | `resources/deployment-and-operations.md` |
| 마이그레이션 → 스키마 → 핸들러 → 테스트 전 구간 예제 | `resources/complete-example.md` |
