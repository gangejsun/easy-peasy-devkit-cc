<!-- epcc-pack: backend/node-nest v3.16.0 -->
# 에러 처리 — 상태 코드는 한 표에서만 나온다

이 파일은 **도메인 실패를 HTTP 상태로 옮기는 규칙**을 소유한다. 봉투를 실제로 방출하는
예외 필터와 `AppError` 클래스는 **이음매의 몫이다** (`src/common/all-exceptions.filter.ts`
· `src/common/app-error.ts`) — 봉투 형태가 조합의 함수이기 때문이다.

## 1. 실패가 오는 세 갈래

| 출처 | 형태 | 여기서 하는 일 |
| --- | --- | --- |
| 우리 코드 | `AppError('NOT_FOUND')` | `ERROR_STATUS`로 상태를 찾는다 |
| 검증 파이프 | `BadRequestException({ code, details })` | 이미 HTTP 예외다 — 그대로 나간다 |
| 드라이버·라이브러리 | `QueryFailedError` 등 | `toAppError`가 정규화한다 |

세 갈래를 **한 곳에서 합류**시키는 것이 목적이다. 합류점이 여럿이면 같은 실패가 자리에
따라 다른 코드로 나가고, 그 차이는 클라이언트가 먼저 발견한다.

## 2. 매핑표와 판별자 (`src/common/error-status.ts`)

<!-- file: src/common/error-status.ts -->
```ts
import { ValidationError } from 'class-validator';
import { QueryFailedError } from 'typeorm';
import { AppError } from './app-error';

export const ERROR_STATUS: Record<string, number> = {
  VALIDATION_FAILED: 400,
  UNAUTHENTICATED: 401,
  FORBIDDEN: 403,
  NOT_FOUND: 404,
  CONFLICT: 409,
  INTERNAL: 500,
};

type PgError = { code?: string; constraint?: string };

export function isUniqueViolation(e: unknown): boolean {
  return e instanceof QueryFailedError && (e.driverError as PgError)?.code === '23505';
}

export function isForeignKeyViolation(e: unknown): boolean {
  return e instanceof QueryFailedError && (e.driverError as PgError)?.code === '23503';
}

export function fieldErrors(errors: ValidationError[]): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  const walk = (list: ValidationError[], prefix: string) => {
    for (const e of list) {
      const path = prefix ? `${prefix}.${e.property}` : e.property;
      const msgs = Object.values(e.constraints ?? {});
      if (msgs.length > 0) out[path] = msgs;
      if (e.children?.length) walk(e.children, path);
    }
  };
  walk(errors, '');
  return out;
}

export function toAppError(e: unknown): AppError {
  if (e instanceof AppError) return e;
  if (isUniqueViolation(e)) return new AppError('CONFLICT', '이미 존재하는 값이다');
  return new AppError('INTERNAL', '내부 오류');
}
```

## 3. 드라이버 코드로 판별한다 — 메시지 문자열이 아니라

<!-- verified: PostgreSQL 18.4 + typeorm@1.1.0 실행 — (ownerId, title) UNIQUE 를 위반하자 QueryFailedError.driverError.code === '23505' 이고 .constraint === 'UQ_tasks_owner_title' 이었다 -->

```ts
// src/common/error-status.ts
// ❌ 메시지를 문자열로 찾는다 — 드라이버 버전·로케일이 바뀌면 조용히 안 잡힌다
if ((e as Error).message.includes('duplicate key')) return new AppError('CONFLICT');
// ✅ SQLSTATE 코드로 판별한다
if (isUniqueViolation(e)) return new AppError('CONFLICT', '이미 존재하는 값이다');
```

| SQLSTATE | 뜻 | 이 팩의 처리 |
| --- | --- | --- |
| `23505` | 고유 제약 위반 | `CONFLICT` (409) |
| `23503` | 외래 키 위반 | 호출 문맥이 정한다 — 참조 대상 부재면 404, 자식이 남아 있으면 409 |
| `23514` | CHECK 위반 | 정상 경로라면 DTO가 먼저 잡았어야 한다. 500으로 두고 로그를 본다 |

`driverError`는 `QueryFailedError`의 필드이고 그 안에 드라이버(pg)의 원본 오류가 있다.
`constraint` 이름까지 보면 "어느 제약인가"로 분기할 수 있지만, **제약 이름은 마이그레이션이
정하는 값**이라 그 분기는 마이그레이션과 함께 움직인다는 점을 알고 쓴다.

## 4. `AppError`는 HTTP를 모른다

`AppError`에 상태 코드를 넣지 않는 것이 이 설계의 요지다 — 서비스 계층이 HTTP를 알기
시작하면 같은 실패를 CLI·큐 소비자·배치에서 재사용할 수 없다. 상태는 `ERROR_STATUS`가
경계에서 한 번 붙인다.

**`AppError`는 `HttpException`이 아니다.** 그래서 이음매의 예외 필터가 없으면
<!-- verified: @nestjs/core@11.2.1 실행 — 필터를 걸지 않은 앱에서 AppError('NOT_FOUND') 가 500 {"statusCode":500,"message":"Internal server error"} 로 나갔다 -->
Nest의 기본 필터가 **전부 500으로** 내보낸다. 팩만 조립한 상태에서 상태 코드가 이상하면
가장 먼저 볼 곳이 여기다.

컨트롤러가 `NotFoundException`을 직접 던지는 것도 동작은 하지만, 그러면 도메인 코드가
Nest에 묶이고 봉투가 두 갈래(`AppError` 경유와 직접)로 갈린다. 이 팩은 `AppError`로
통일한다.

## 5. 부재와 권한 없음을 구분하지 않는다

<!-- verified: PostgreSQL 18.4 실행 — 타인 소유 행에 대한 조회·수정·삭제가 모두 404 {"error":{"code":"NOT_FOUND"}} 였다 -->

```ts
// src/tasks/tasks.service.ts
// ❌ 존재를 알려 준다 — id를 훑으면 남의 리소스 존재를 열거할 수 있다
if (!task) throw new AppError('NOT_FOUND');
if (task.ownerId !== ownerId) throw new AppError('FORBIDDEN');
// ✅ 소유권을 조회 조건에 넣으면 두 경우가 같은 결과가 된다
const task = await this.tasks.findOne({ where: { id, ownerId }, select: TASK_VIEW });
if (!task) throw new AppError('NOT_FOUND', '작업을 찾지 못했다');
```

`FORBIDDEN`(403)은 **존재를 이미 아는** 리소스에 대한 행위 거부에만 쓴다 — 역할이
모자란 경우가 그것이다. 소유권 판정에는 쓰지 않는다.

## 6. 내부 원인은 응답이 아니라 로그로

`toAppError`가 알 수 없는 예외를 `INTERNAL`로 접는 것은 정보 차단이 목적이다. 스택·SQL·
제약 이름이 응답에 실리면 스키마와 내부 구조가 그대로 새어 나간다. 원인은
`SlowQueryLogger.logQueryError`와 예외 필터의 로그가 남긴다 (`operations.md` §5).

## 오용 목록 ① — Express 에러 관용구 → NestJS 형태 대조표

| 구 습관 (Express) | 현재 형태 (NestJS 11) |
| --- | --- |
| `next(err)`로 넘긴다 | 그냥 `throw`. 파이프라인이 필터로 보낸다 |
| 4인자 미들웨어 `(err, req, res, next)` | `@Catch()` + `implements ExceptionFilter` |
| 라우터마다 try/catch로 상태 결정 | 서비스는 `AppError`만 던지고 상태는 경계에서 한 번 |
| `res.status(409).json(...)` | 던지고 필터가 봉투를 만든다. 컨트롤러가 봉투를 만들면 갈린다 |
| `process.on('unhandledRejection')`에 의존 | async 핸들러의 거부는 Nest가 필터로 보낸다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `AppError` vs `HttpException` | 도메인 실패는 앞, 이미 HTTP 의미가 확정된 것(파이프의 400)은 뒤 |
| `@Catch()` vs `@Catch(HttpException)` | 인자 없는 쪽이 **모든** 예외를 받는다. 좁히면 `AppError`가 기본 필터로 새어 500이 된다 |
| 404 vs 403 | 소유권은 404, 역할 부족은 403 (§5) |
| 409 vs 422 | 고유 제약 충돌은 409. 422는 이 축에 도달 경로가 없다 |
| `instanceof QueryFailedError` vs 메시지 검사 | 앞만 쓴다. 메시지는 드라이버 버전에 따라 바뀐다 |
| 예외 필터에서 다시 throw | 응답이 두 번 나가거나 아무 응답도 안 나간다. 필터는 반드시 응답을 끝낸다 |
