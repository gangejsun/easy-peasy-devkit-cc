<!-- epcc-pack: backend/node-api v3.13.0 -->
# 입력 검증 — Zod 4 스키마와 요청 파싱

이 파일이 소유하는 코드 파일은 셋이다: `src/env.ts` · `src/schemas/task.ts` · `src/http/parse.ts`.
에러 코드 → HTTP 상태 매핑과 `ZodError` 정규화는 `error-handling.md`가 소유한다.
파싱 헬퍼를 라우터 어디에 끼우는지는 이음매(`api-endpoints` 슬롯)의 몫이다.

## 1. 무엇을 어디서 검증하는가

**검증 지점은 실패 시점을 정하는 결정이다.** 늦게 검증할수록 실패가 사용자 요청 안으로
들어온다. 이 축에는 데이터 계층 정책 엔진이 없으므로 **애플리케이션이 유일한 경계다** —
여기서 통과시킨 값은 아무도 다시 보지 않는다.

| 입력 | 검증 지점 | 실패 시점 | 실패 형태 |
| --- | --- | --- | --- |
| 환경변수 | `src/env.ts` (`EnvSchema`) | 프로세스 부팅 | stderr + `exit(1)` |
| 요청 본문 | `parseBody(TaskCreateSchema, req)` | 요청 처리 | `AppError('VALIDATION_FAILED')` → 400 |
| 쿼리 문자열 | `parseQuery(TaskQuerySchema, req)` | 요청 처리 | 같음 |
| 경로 파라미터 | 라우터에서 `z.cuid()`/`z.uuid()` | 요청 처리 | 같음 |
| 값의 유일성 | DB 제약 (`@@unique`) | 쓰기 | Prisma `P2002` → 409 |
| **소유권** | 쿼리 조건 (`data-access.md`) | 쓰기/읽기 | 0행 → 404 |

마지막 행은 검증이 아니라 **인가**다. Zod로는 판정할 수 없다 — 스키마는 요청이 무엇을
말하는지만 알고 요청자가 누구인지는 모른다. `ownerId`를 요청 본문에서 읽으면 스키마가
통과시키는 순간 남의 행을 쓰게 된다. 주체는 검증된 세션(`req.user`)에서만 온다.

고를 때의 기준은 하나다: **이 값이 틀렸을 때 누가 먼저 알아야 하는가.** 배포자가 먼저
알아야 하면 부팅 시점(2절), 호출자가 알아야 하면 요청 시점(6절)이다.

## 2. 환경변수 스키마 (`src/env.ts`)

`process.env`를 읽는 파일은 저장소에 **이 하나뿐이다.** 다른 파일이 직접 읽으면 타입도
검증도 부팅 시점 실패도 전부 우회된다.

<!-- file: src/env.ts -->
```ts
import { z } from 'zod';

// 0이 정당한 값인 밀리초 설정. 코어스 전에 문자열을 검사해 빈 값이 0으로 새는 것을 막는다
const ms = (max: number) =>
  z.string().regex(/^\d+$/, '0 이상의 정수(ms)여야 합니다').transform(Number)
    .pipe(z.number().int().max(max));

export const EnvSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().min(1).max(65535).default(3000),
  DATABASE_URL: z.url({ protocol: /^postgres(ql)?$/ }),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug']).default('info'),
  SHUTDOWN_TIMEOUT_MS: ms(120_000).prefault('10000'),
  DRAIN_DELAY_MS: ms(60_000).prefault('800'),
});

export type Env = z.infer<typeof EnvSchema>;

const parsed = EnvSchema.safeParse(process.env);

if (!parsed.success) {
  process.stderr.write(`환경변수 검증 실패\n${z.prettifyError(parsed.error)}\n`);
  process.exit(1);
}

export const env: Env = parsed.data;
```

`process.stderr.write`를 쓰는 이유가 있다. 구조적 로거(`logger`, `operations.md`)는
`env.LOG_LEVEL`에 의존하므로 **이 시점에 아직 존재하지 않는다.** 여기서 로거를 부르면
순환 import가 되고, 그래서 환경 실패만이 이 저장소에서 로거 없이 보고되는 실패다.

`DATABASE_URL`에 `protocol` 옵션을 건 것도 의도다. `z.url()`만 쓰면
`https://evil.example/db`가 그대로 통과하고, 접속 실패는 부팅이 아니라 첫 쿼리에서 난다.
비밀이 담긴 URL이라 오류 메시지도 중요한데, Zod의 `invalid_format` 메시지는
`Invalid URL`뿐이라 값을 담지 않는다.
<!-- verified: zod 4.4.3 실행 — z.url({protocol:/^postgres(ql)?$/})에 postgres:// · postgresql:// · https:// · 비URL 4종을 넣어 통과·거부와 오류 메시지를 관측 -->

## 3. 환경변수의 함정 — 빈 문자열과 `.default()`

`process.env`의 값은 전부 문자열이고, **설정되지 않은 것과 빈 문자열은 다르다.**
`.default()`는 `undefined`일 때만 발동하므로 `PORT=`(빈 값)는 기본값으로 가지 않는다.

```ts
// ❌ PORT= 이면 Number('') === 0 이 되어 0번 포트로 뜬다
PORT: z.coerce.number().default(3000),
```

```ts
// ✅ 범위를 걸면 0이 부팅 시점에 걸린다
PORT: z.coerce.number().int().min(1).max(65535).default(3000),
```

<!-- verified: zod 4.4.3 실행 — PORT 미설정/빈값/abc 3입력을 두 스키마 형태에 각각 통과시켜 대조 -->
| 입력 | `.default(3000)`만 | `.int().min(1)` 추가 |
| --- | --- | --- |
| `PORT` 미설정 | `3000` | `3000` |
| `PORT=` | **`0`** | `Too small: expected number to be >=1` → exit 1 |
| `PORT=abc` | `expected number, received NaN` | 같음 |

`.default()`는 **주입한 값을 다시 검증하지 않는다.** `z.string().trim().default('  x  ')`는
`'  x  '`를 그대로 돌려준다. 기본값에도 파이프라인을 태우려면 `.prefault()`를
쓴다 — 같은 입력이 `'x'`가 된다. <!-- verified: zod 4.4.3 실행 — z.string().trim()에 .default('  x  ')와 .prefault('  x  ')를 각각 걸어 undefined를 파싱: 전자는 '  x  ', 후자는 'x' -->

**0이 정당한 값이면 범위 검사로는 못 잡는다.** `PORT`는 `.min(1)`이 빈 값을 걸러줬지만
`DRAIN_DELAY_MS=0`(배수 지연 끄기)은 유효한 설정이라 같은 방어가 통하지 않는다 —
`DRAIN_DELAY_MS=`(오타로 빈 값)도 0이 되어 **기능이 조용히 꺼진다.** 이럴 때는 코어스에
맡기지 말고 **문자열을 먼저 검사한 뒤 변환**한다. 2절의 `ms()` 헬퍼가 그 형태다.

| 입력 | `z.coerce.number().int().min(0)` | `ms()` (문자열 검사 후 변환) |
| --- | --- | --- |
| 미설정 | 기본값 | 기본값 (`.prefault`가 파이프라인을 탄다) |
| `=0` (의도한 0) | `0` | `0` |
| `=` (오타) | **`0` — 구분되지 않는다** | `0 이상의 정수(ms)여야 합니다` → exit 1 |
| `=99999999` | 통과 | `Too big: expected number to be <=60000` |

## 4. 요청 스키마 (`src/schemas/task.ts`)

<!-- file: src/schemas/task.ts -->
```ts
import { z } from 'zod';

const title = z.string().trim().min(1, '제목은 비울 수 없습니다').max(200);
const status = z.enum(['open', 'done']);

export const TaskCreateSchema = z.strictObject({
  title,
  status: status.default('open'),
  dueAt: z.iso.datetime({ offset: true }).optional(),
});

export const TaskUpdateSchema = z
  .strictObject({
    title: title.optional(),
    status: status.optional(),
    dueAt: z.iso.datetime({ offset: true }).nullable().optional(),
  })
  .refine((v) => Object.keys(v).length > 0, {
    error: '수정할 필드가 최소 하나 필요합니다',
  });

export const TaskQuerySchema = z.object({
  status: status.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().min(1).optional(),
});

export type TaskCreate = z.infer<typeof TaskCreateSchema>;
export type TaskUpdate = z.infer<typeof TaskUpdateSchema>;
export type TaskQuery = z.infer<typeof TaskQuerySchema>;
```

`z.strictObject`를 본문에 쓰고 쿼리에는 쓰지 않는다. **기본 동작은 미지 키를 조용히
제거하는 것**이라 (`{ title:'a', evil:1 }` → `{ title:'a', status:'open' }`)
오타 난 필드가 무시된 채 200이 나간다. 쿼리 문자열은 추적 파라미터(`utm_*`)가 섞이므로
제거가 맞고, 본문은 클라이언트가 정확히 아는 계약이므로 거부가 맞다.

`limit`에 `.max(100)`이 있는 이유는 페이지 크기가 곧 DB 부하이기 때문이다. 상한 없는
`limit`은 한 요청으로 테이블을 전부 읽는 경로가 된다.

## 5. 부분 업데이트 — `.partial()`과 `.default()`를 겹치지 않는다

**이 축에서 가장 비싼 결함이다.** 문법은 완벽하고 타입도 통과하며, 실행만이 드러낸다.

```ts
// ❌ TaskCreateSchema.partial() — status의 .default('open')가 살아남는다
const TaskUpdateSchema = TaskCreateSchema.partial();
```

`.partial()`은 각 필드를 `.optional()`로 감쌀 뿐 **안쪽의 `.default()`를 벗기지 않는다.**
`PATCH /api/tasks/1` 에 `{ "title": "수정됨" }`만 보내면 파싱 결과가
`{ title: '수정됨', status: 'open' }`이 되고, 완료 처리된 작업이 조용히 되살아난다.
`.default()`가 붙은 필드가 없으면 문제도 없어서 **`.default()`를 나중에 추가하는 순간**
멀쩡하던 PATCH가 망가진다. 4절처럼 필드마다 `.optional()`을 직접 붙이면 겹칠 자리가 없다.

<!-- verified: express 5.2.1 + zod 4.4.3 통합 실행 — 두 스키마 형태를 같은 라우터에 물려 세 입력을 실제 HTTP 요청으로 대조 -->
두 형태를 같은 라우터에 물려 실제 요청으로 시험한 세 입력이다. 오른쪽 열은 **봉투가 아니라**
상태 코드와 `details`(또는 파싱된 값)만 떼어 보인 것이다 — 봉투는 이음매가 정한다:

| # | 입력 | 상태 · `details` 또는 파싱 결과 |
| --- | --- | --- |
| ① | `{}` | 400 · `{"_":["수정할 필드가 최소 하나 필요합니다"]}` |
| ② | `{"title":"수정됨"}` | 200 · `{"title":"수정됨"}` — **`status`가 채워지지 않는다** |
| ③ | `{"title":"a","evil":1}` | 400 · `{"_":["Unrecognized key: \"evil\""]}` |

②가 `.partial()` 형태에서는 `{"title":"수정됨","status":"open"}`이 된다. ①은 더하다 —
빈 본문이 400이 아니라 `{"status":"open"}`으로 **통과한다.** 두 형태를 갈라 돌리기 전까지
이 차이는 어떤 읽기로도 보이지 않는다.

①의 `.refine()`도 의무다. 빈 객체가 통과하면 필드 0개짜리 `UPDATE`가 나가고, `updatedAt`만
바뀐 행이 200으로 응답된다.

## 6. 파싱 헬퍼 (`src/http/parse.ts`)

<!-- file: src/http/parse.ts -->
```ts
import type { Request } from 'express';
import type { z } from 'zod';
import { AppError } from './app-error';
import { fieldErrors } from './errors';

function run<S extends z.ZodType>(schema: S, raw: unknown, where: string): z.output<S> {
  const r = schema.safeParse(raw);
  if (r.success) return r.data;
  throw new AppError('VALIDATION_FAILED', `${where} 검증에 실패했습니다`, fieldErrors(r.error));
}

export function parseBody<S extends z.ZodType>(schema: S, req: Request): z.output<S> {
  return run(schema, req.body, '요청 본문');
}

export function parseQuery<S extends z.ZodType>(schema: S, req: Request): z.output<S> {
  return run(schema, req.query, '쿼리 문자열');
}
```

`AppError`는 이 팩이 정의하지 않는다 — 이음매가 `src/http/app-error.ts`에 소유한다.
`fieldErrors`는 `error-handling.md`가 소유한다.

반환값을 쓰고 `req.query`에 다시 대입하지 않는 데는 이유가 있다. **Express 5의 `req.query`는
setter가 없는 getter라 대입이 어느 쪽으로든 실패한다** — 그런데 실패하는 *방식*이 모듈
종류에 따라 갈린다.
<!-- verified: express 5.2.1 실행 — 같은 핸들러를 CJS와 ESM으로 각각 돌려 대입 후 req.query를 관측 -->

ESM·strict에서는 `TypeError: Cannot set property query…`가 나지만, **CJS sloppy 모드에서는
던지지 않고 조용히 무시된다.** 어느 쪽이든 대입 후 `req.query`는 원래 값 그대로다.

**조용한 실패 쪽이 더 위험하다.** CJS에서는 검증했다고 믿는 코드가 원본 문자열을 계속
읽으면서 아무 신호도 내지 않는다. 어느 쪽이든 대입은 결코 반영되지 않으므로, 검증된 값은
지역 변수로 받아 그대로 쓴다.

`z.output<S>`를 쓰는 것도 의도다. `z.infer`와 값은 같지만, `.transform()`이나 `.default()`가
붙은 스키마에서 **입력 타입과 출력 타입이 갈리는 자리**를 이름이 드러낸다.

호출자는 `try/catch`를 쓰지 않는다. Express 5는 핸들러가 던진 예외를 — 동기든 거부된
프로미스든 — 에러 미들웨어로 자동 전달한다. 미들웨어 순서는
`project-structure.md`가 소유한다.

## 7. DB 제약과 이중으로 건다

Zod는 요청을 막고 DB 제약은 경합을 막는다. **둘 중 하나만으로는 부족하다.**

| Zod (`schemas/task.ts`) | Prisma (`prisma/schema.prisma`) | 한쪽만 있으면 |
| --- | --- | --- |
| `title.max(200)` | `@db.VarChar(200)` | Zod만: 다른 경로(시드·배치)가 우회한다 |
| `z.enum(['open','done'])` | `enum TaskStatus { open done }` | DB만: 400이어야 할 것이 500이 된다 |
| — (판정 불가) | `@@unique([ownerId, title])` | 검사 후 삽입은 경합에 뚫린다 |

세 번째 행이 핵심이다. "먼저 조회해 없으면 삽입"은 두 요청이 동시에 오면 둘 다 통과한다.
유일성은 **DB만 원자적으로 판정할 수 있고**, 애플리케이션은 그 실패(`P2002`)를 409로
번역하는 일만 한다 — `error-handling.md`의 `isUniqueViolation`이 그 자리다.

## 오용 목록 ① — Zod 3 → Zod 4 관용구 대조표

설치본(zod 4.4.3)의 `.d.ts`를 행 단위로 대조해 만들었다. 왼쪽 형태는 아직 동작하고 컴파일
오류도 나지 않는다 — 그래서 조용히 남는다. **각주가 붙은 일곱 행은 `@deprecated` 주석을
행 번호까지 확인한 것이고, 붙지 않은 두 행(`.strict()` · `.default()`)은 라이브러리가 회수한
API가 아니라 이 스택에서 관찰되는 오용이다.** 근거가 다르므로 섞어 읽지 않는다.

| 구 습관 (Zod 3) | 현재 형태 (Zod 4) |
| --- | --- |
| `z.string().email()` | `z.email()` <!-- verified: zod 4.4.3 classic/schemas.d.cts:110 @deprecated --> |
| `z.string().url()` | `z.url()` <!-- verified: 같은 파일 112행 @deprecated --> |
| `z.string().uuid()` / `.cuid2()` / `.ulid()` | `z.uuid()` / `z.cuid2()` / `z.ulid()` <!-- verified: 같은 파일 120·138·140행 @deprecated --> |
| `z.string().datetime()` | `z.iso.datetime()` <!-- verified: 같은 파일 160행 @deprecated --> |
| `z.object({}).passthrough()` | `z.looseObject({})` 또는 `.loose()` <!-- verified: 같은 파일 460행 @deprecated --> |
| `err.flatten()` · `err.format()` | `z.flattenError(err)` · `z.treeifyError(err)` <!-- verified: zod 4.4.3 classic/errors.d.cts:7·10 @deprecated --> |
| `{ message: '...' }` (검사 옵션) | `{ error: '...' }` <!-- verified: zod 4.4.3 core/api.d.cts:9 @deprecated — 다만 message는 아직 우선 적용된다(실행 확인) --> |
| `z.object({}).strict()` | `z.strictObject({})` — 폐기는 아니다. 타입 주석이 `Consider`로만 권한다 |
| `.default()`로 변환까지 기대 | `.prefault()` — `.default()`는 주입값을 재검증하지 않는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `.partial()` vs 필드별 `.optional()` | `.default()`가 하나라도 있으면 `.partial()`은 쓰지 않는다 (5절) |
| `.parse()` vs `.safeParse()` | 헬퍼 안에서는 `safeParse` — `parse`의 `ZodError`는 `message`가 issue 배열 JSON 통째라 그대로 응답에 실으면 내부 구조가 샌다 |
| `z.object` vs `z.strictObject` | 본문은 `strictObject`(오타를 거부), 쿼리는 `z.object`(추적 파라미터를 제거) |
| `.optional()` vs `.nullable()` | "보내지 않음"은 `.optional()`, "값을 비움"은 `.nullable()`. PATCH에서 필드를 지우려면 **둘 다** 필요하다 |
| `.default()` vs `.catch()` | `.default()`는 `undefined`만, `.catch()`는 **모든 실패**를 삼킨다 — 요청 검증에 `.catch()`를 쓰면 잘못된 입력이 조용히 기본값이 된다 |
| `z.infer` vs `z.input` | 스키마를 통과한 뒤의 값은 `z.infer`(=`z.output`). 클라이언트가 보내는 형태는 `z.input` |
| `z.coerce.number()` vs `z.number()` | 쿼리·환경변수는 항상 문자열이므로 `coerce`. JSON 본문의 숫자에 쓰면 `"5"`도 통과해 계약이 흐려진다 |
| `env.PORT` vs `process.env.PORT` | 앱 코드는 언제나 `env` — `process.env`를 읽어도 되는 파일은 `src/env.ts`와 테스트 설정뿐이다 |
