<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# 입력 검증 — 경계마다 스키마가 하나씩 있고, 환경도 그중 하나다

이 파일이 소유하는 것은 **환경을 읽는 유일한 자리**(`src/settings.ts`) · **도메인 스키마**
(`src/schemas/task.ts`) · **zod 오류를 필드 맵으로 접는 자리**(`src/schemas/errors.ts`)와 그 셋의
단위 테스트(`test/schemas.test.ts`)다. `ZodError`를 **어떤 상태 코드로 내보내는지**는
`error-handling.md`가, 스키마를 실제로 부르는 converter는 `data-access.md`가 소유한다.

## 1. 어디에 스키마를 두는가 — 경계 판단표

경계는 **신뢰가 바뀌는 자리**다. 값이 프로세스 밖에서 왔으면 스키마가 하나 필요하다.

| 경계 | 스키마 | 실패하면 | 왜 신뢰 입력이 아닌가 |
| --- | --- | --- | --- |
| 요청 본문 | `TaskCreate` · `TaskUpdate` | `VALIDATION_FAILED`(422) | 클라이언트가 쓴 값이다 |
| 쿼리 파라미터 | `TaskQuery` | `VALIDATION_FAILED`(422) | 위와 같다. **전부 문자열로 도착한다** |
| 프로세스 환경 | `settings`의 `Env` | **부팅이 실패한다** | 배포 설정은 사람이 손으로 쓴다 |
| Firestore 문서 | `Task` (converter가 부른다) | `VALIDATION_FAILED`(422) | 문서는 **코드 밖에서 바뀐다** |
| 커서 문자열 | `decodeCursor` (`data-access.md`) | `VALIDATION_FAILED`(422) | 클라이언트가 되돌려 보낸 값이다 |

세 번째 줄만 실패 방식이 다르다. **환경은 요청보다 먼저 도착하므로 실패도 먼저 해야 한다** —
요청 시점에 터지면 절반이 살아 있는 컨테이너가 트래픽을 받는다.

## 2. `settings` (`src/settings.ts`) — 검증 실패가 부팅 실패다

<!-- file: src/settings.ts -->
```ts
// src/settings.ts
import { z } from 'zod';
import { fieldErrors } from './schemas/errors.js';

// 환경 스키마에는 .strict()를 걸지 않는다 — process.env에는 PATH·HOME이 들어 있다.
const Env = z.object({
  GCP_PROJECT_ID: z.string().min(1),
  IDENTITY_PLATFORM_PROJECT_ID: z.string().min(1),
  PORT: z.coerce.number().int().min(1).max(65535).default(8080),
  LOG_LEVEL: z.enum(['info', 'warn', 'error']).default('info'),
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  FIRESTORE_EMULATOR_HOST: z.string().min(1).optional(),
});

const parsed = Env.safeParse(process.env);
if (!parsed.success) {
  process.stderr.write(
    JSON.stringify({ severity: 'CRITICAL', message: 'invalid environment', fields: fieldErrors(parsed.error) }) + '\n',
  );
  process.exit(1);
}

export const settings = parsed.data;
```

<!-- verified: 위 파일을 컴파일해 환경만 바꿔 5회 실행하고 stdout·stderr·종료 코드를 계측 -->
실측한 세 경우와 양성 대조군이다.

| 환경 | 관측 |
| --- | --- |
| 필수 값 둘 누락 | 종료 코드 **1**, stderr에 `{"severity":"CRITICAL",…,"fields":{"GCP_PROJECT_ID":["Invalid input: expected string, received undefined"],…}}` |
| `PORT=eighty` · `NODE_ENV=prod` | 종료 코드 **1** — `expected number, received NaN` · `Invalid option: expected one of "development"\|"test"\|"production"` |
| **정상 (양성 대조군)** | 종료 코드 **0**, `port: 8080` · `env: "development"` — 기본값이 실제로 채워진다 |

**`z.coerce.number()`인 이유**: 환경 값은 전부 문자열이다. `PORT=8080`이 `number` `8080`으로
들어오고, 키가 없으면 `.default(8080)`이 먼저 걸린다. **`process.exit(1)` 앞에
`process.stderr.write`를 쓰는 이유**: 파이프로 받아도 그 줄이 유실되지 않는 것을 실측했다 —
진단 없이 종료 코드만 남으면 배포 로그에서 「왜」가 사라진다.

<!-- verified: z.object({GCP_PROJECT_ID:z.string()}).strict() 로 process.env를 파싱해 unrecognized_keys의 keys 길이를 셈 -->
**환경 스키마에는 `.strict()`를 걸지 않는다.** 걸어 봤더니 `PATH`·`HOME` 등 **59개 키**가
한꺼번에 거부됐다. `.strict()`는 우리가 형태를 정한 입력에만 건다(5절).

## 3. 환경을 읽는 파일은 하나다

`settings` 밖에서 환경을 읽으면 **타입도 기본값도 부팅 시점 실패도 전부 우회하고**, 그 사실은
배포된 뒤 그 코드 경로가 처음 실행될 때 드러난다.

```ts
// ❌ 검증을 우회한다. 타입은 string | undefined이고, 오타는 런타임까지 산다
const port = Number(process.env.PORT ?? 8080);
// ❌ 「여기서만 잠깐」이 두 번째 진입점이다 — 이제 기본값이 두 곳에 있다
const projectId = process.env.GCP_PROJECT_ID!;
// ✅ 검증된 값만 쓴다. 타입은 number이고, 틀렸으면 이 코드는 아예 실행되지 않았다
import { settings } from './settings.js';
serve({ fetch: createApp().fetch, port: settings.PORT, hostname: '0.0.0.0' });
```

예외는 **둘뿐이다**: 스키마를 정의하는 이 파일 자신과 테스트가 `FIRESTORE_EMULATOR_HOST`를
주입하는 자리. 정책 `env-single-entry`가 나머지를 FAIL로 막는다.

## 4. 도메인 스키마 (`src/schemas/task.ts`)

<!-- file: src/schemas/task.ts -->
```ts
// src/schemas/task.ts
import { Timestamp } from '@google-cloud/firestore';
import { z } from 'zod';

export const TaskStatus = z.enum(['open', 'done']);
export type TaskStatus = z.infer<typeof TaskStatus>;

// z.date()는 Timestamp를 거부한다 — 실측 메시지: "expected date, received Timestamp".
const timestamp = z.instanceof(Timestamp);

export const Task = z.object({
  id: z.string().min(1),
  ownerId: z.string().min(1),
  title: z.string().min(1).max(200),
  status: TaskStatus,
  createdAt: timestamp,
});
export type Task = z.infer<typeof Task>;

export const TaskCreate = z.object({
  title: z.string().min(1).max(200),
  status: TaskStatus.default('open'),
}).strict();
export type TaskCreate = z.infer<typeof TaskCreate>;

export const TaskUpdate = z.object({
  title: z.string().min(1).max(200).optional(),
  status: TaskStatus.optional(),
}).strict()
  .refine((patch) => Object.keys(patch).length > 0, { message: '수정할 필드가 하나도 없다' });
export type TaskUpdate = z.infer<typeof TaskUpdate>;

export const TaskQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().min(1).optional(),
  status: TaskStatus.optional(),
}).strict();
export type TaskQuery = z.infer<typeof TaskQuery>;
```

**`TaskStatus`의 값은 소문자 `'open'`·`'done'`이다.** 와이어·Firestore 문서·테스트 단언에 쓰는
것은 **값**이지 멤버 이름이 아니다 — 실측에서 `status=DONE`은
`Invalid option: expected one of "open"|"done"`으로 거부됐다. **`id`는 문서 ID이지 문서 필드가
아니다**(converter가 `snap.id`로 채운다). 반면 `ownerId`는 문서 필드로도 저장한다 — 쿼리
필터가 그것을 읽는다(`data-access.md`).

## 5. 부분 수정과 미지 키 — 조용히 틀리는 두 자리

두 결함 다 **오류가 아니라 잘못된 성공**으로 나타난다. 200이 나가고 로그에 아무것도 남지 않는다.

<!-- verified: zod 4.4.3에서 TaskCreate.partial().parse({}) 의 반환과, .strict() 유무 두 스키마의 같은 입력 파싱 결과를 출력 -->
```ts
// ❌ partial()은 ZodOptional로 감싸지만 안쪽 default는 살아 있다
TaskCreate.partial().parse({});      // ❌ 실측: { status: 'open' } — 보내지 않은 status가 생겼다
// ✅ 선택 필드를 직접 쓴다. 기본값이 없으므로 없는 키는 없는 채로 남는다
TaskUpdate.parse({ title: '장보기' }); // ✅ 실측: { title: '장보기' }
// ❌ .strict()가 없으면 통과한다 — 실측: { status: undefined } 로 파싱돼 필터가 사라진다
z.object({ status: TaskStatus.optional() }).parse({ stat: 'done' });
// ✅ 같은 입력이 거부된다 — unrecognized_keys
TaskQuery.safeParse({ stat: 'done' });
```

`PATCH`에 `{"title":"장보기"}`만 보낸 사용자가 **완료 표시를 잃고**, `?stat=done`으로 오타 낸
클라이언트는 **필터가 무시된 전체 목록**을 정상 응답으로 받는다. **빈 객체도 거부한다** —
`.refine()`이 그 자리다. `.strict()` **뒤에** 붙여도 미지 키 거부는 유지된다(실측).

<!-- verified: zod 4.4.3에서 미지 키 둘을 한꺼번에 보내 issues 배열을 출력 -->
zod 4의 `unrecognized_keys` issue는 **키마다 하나씩 나오지 않는다** — 미지 키 둘에
`{ code: 'unrecognized_keys', keys: ['nope','other'], path: [] }` **한 개**가 나왔고, 같은 요청의
필드 오류는 함께 오지 않았다(거기서 끊긴다). 본문에도 건다: `TaskCreate`가 받은 `ownerId`는
무시되는 것이 아니라 **거부돼야 한다** — 소유자는 검증된 토큰의 `sub`에서만 온다.

## 6. converter 경계 — 문서는 신뢰 입력이 아니다

Firestore 문서는 콘솔·다른 서비스·이전 버전의 코드가 쓸 수 있다. `fromFirestore`에서 `Task`로
**다시 파싱한다**(그 파일은 `data-access.md`가 소유한다). 여기서 정하는 것은 스키마 쪽이다.

<!-- verified: @google-cloud/firestore 9.0.0의 Timestamp.now()를 zod 4.4.3에 태워 관측 -->
| 쓴 것 | 관측 |
| --- | --- |
| `z.date().safeParse(Timestamp.now())` | **거부** — `Invalid input: expected date, received Timestamp` |
| `z.instanceof(Timestamp).safeParse(Timestamp.now())` | 통과. `new Date()`는 거부 |
| `JSON.stringify({ createdAt: Timestamp.now() })` | `{"createdAt":{"_seconds":…,"_nanoseconds":…}}` |

첫 줄이 함정이다 — `createdAt: z.date()`는 컴파일되고 픽스처가 `Date`면 테스트도 통과하지만 실제
문서를 읽는 순간 전부 실패한다. **문서에서 오는 값은 문서가 준 타입으로 검증한다.** 셋째 줄은
봉투의 문제다: 그대로 직렬화하면 SDK 내부 필드 이름이 와이어 계약이 된다.

## 7. `fieldErrors` (`src/schemas/errors.ts`) — `path`가 비는 자리가 있다

<!-- file: src/schemas/errors.ts -->
```ts
// src/schemas/errors.ts
import type { z } from 'zod';

/** path가 빈 issue(= 객체 전체 문제)가 접히는 고정 키다. */
export const ROOT_FIELD = '_root';

export function fieldErrors(err: z.ZodError): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const issue of err.issues) {
    // path는 PropertyKey[]다 — 배열 인덱스는 number이므로 문자열로 바꿔 잇는다.
    const key = issue.path.length === 0 ? ROOT_FIELD : issue.path.map(String).join('.');
    (out[key] ??= []).push(issue.message);
  }
  return out;
}
```

<!-- verified: zod 4.4.3이 만든 ZodError의 issue.path를 그대로 출력해 대조 -->
| 무엇이 틀렸나 | 관측된 `issue.path` | 키 |
| --- | --- | --- |
| `title`이 빈 문자열 | `['title']` | `title` |
| 배열 항목 안의 필드 | `['items', 1, 'title']` | `items.1.title` — **인덱스를 지우지 않는다** |
| `.strict()` 위반 | **`[]`** | `_root` |
| `.refine()` 실패 (빈 수정 본문) | **`[]`** | `_root` |

중첩 객체는 `['meta','tag']` → `meta.tag`로 이어진다. 빈 배열을 그대로 이으면 키가 `''`가 된다 —
폼은 그 오류를 어디에도 붙이지 못하고 사용자는 「저장이 안 되는데 빨간 글씨가 없는」 상태에
빠진다. `_root`는 **클라이언트가 객체 수준 메시지를 찾을 자리**다.

<!-- verified: zod 4.4.3에서 'errors' in err === false 를 관측 -->
`ZodError`는 **`.issues`만 갖는다.** zod 3의 `.errors`는 없다. 그리고 `path`의 타입은
`PropertyKey[]`이므로 `String()`을 거치지 않고 `join`하면 타입 검사가 막는다.

## 8. 차단을 증명한다 (`test/schemas.test.ts`)

**부정 단언만 있는 테스트는 차단 장치가 아니다** — 스키마를 통째로 `z.never()`로 바꿔도
「미지 키가 거부된다」는 초록이다. 정상 입력이 통과한다는 단언을 **같은 `it` 안에** 짝으로 건다.

<!-- file: test/schemas.test.ts -->
```ts
// test/schemas.test.ts
import { describe, expect, it } from 'vitest';
import { z } from 'zod';
import { fieldErrors } from '../src/schemas/errors.js';
import { TaskCreate, TaskQuery, TaskUpdate } from '../src/schemas/task.js';

describe('스키마', () => {
  it('미지 키는 본문·쿼리 양쪽에서 거부되고, 정상 입력은 통과한다', () => {
    expect(TaskCreate.safeParse({ title: '장보기', ownerId: 'mallory' }).success).toBe(false);
    expect(TaskQuery.safeParse({ stat: 'done' }).success).toBe(false);
    expect(TaskQuery.safeParse({ status: 'DONE' }).success).toBe(false);   // 값은 소문자다
    // ✅ 긍정 짝이 없으면 스키마를 z.never()로 바꿔도 초록이다
    expect(TaskCreate.parse({ title: '장보기' })).toEqual({ title: '장보기', status: 'open' });
    expect(TaskQuery.parse({ limit: '5', status: 'open' })).toEqual({ limit: 5, status: 'open' });
    // ✅ 양성 대조군: .strict()가 없으면 같은 입력이 통과하고 status는 undefined다
    const loose = z.object({ status: z.enum(['open', 'done']).optional() });
    expect(loose.parse({ stat: 'done' }).status).toBeUndefined();
  });

  it('부분 수정은 보내지 않은 필드를 만들지 않고, 빈 본문은 거부한다', () => {
    expect(TaskUpdate.parse({ title: '장보기' })).toEqual({ title: '장보기' });
    expect(TaskUpdate.safeParse({}).success).toBe(false);
    // ✅ 대조군 둘: 생성 스키마는 같은 본문에 기본값을 채우고, 필드 하나짜리 수정은 통과한다
    expect(TaskCreate.parse({ title: '장보기' }).status).toBe('open');
    expect(TaskUpdate.safeParse({ status: 'done' }).success).toBe(true);
  });

  it('fieldErrors — 빈 path는 _root로 접고 배열 인덱스는 남긴다', () => {
    const strictErr = TaskCreate.safeParse({ title: 'x', nope: 1 }).error as z.ZodError;
    expect(Object.keys(fieldErrors(strictErr))).toEqual(['_root']);
    const nested = z.object({ items: z.array(z.object({ title: z.string().min(1) })) });
    const arrErr = nested.safeParse({ items: [{ title: 'ok' }, { title: '' }] }).error as z.ZodError;
    expect(Object.keys(fieldErrors(arrErr))).toEqual(['items.1.title']);
    // ✅ 긍정 짝: 정상 입력에는 오류가 없다 — 전부 _root로 접는 구현을 배제한다
    expect(TaskCreate.safeParse({ title: 'x' }).success).toBe(true);
  });
});
```

<!-- verified: 돌연변이 8종을 심어 vitest로 실행 — 전부 빨개졌고 실패 이유도 의도한 것이었다 -->
실측: 돌연변이 8종이 **전부 잡혔다** — `.strict()` 제거(`TaskCreate`·`TaskQuery`) ·
`TaskUpdate = TaskCreate.partial()` · `.refine()` 제거 · 열거 값을 대문자로 · `z.coerce` 제거 ·
`fieldErrors`의 빈 `path` 처리 삭제(키가 `''`) · 배열 인덱스 제거(`items.title`).

## 오용 목록 ① — zod 3 → zod 4 관용구 대조표

| 구 습관 (zod 3) | 현재 형태 (zod 4) |
| --- | --- |
| `err.errors` | `err.issues` — `.errors`는 없다 <!-- verified: zod 4.4.3에서 'errors' in err === false --> |
| `err.flatten().fieldErrors` | `fieldErrors(err)` — 빈 `path`를 `_root`로 접는다 |
| `issue.path.join('.')` | `issue.path.map(String).join('.')` — 타입이 `PropertyKey[]`다 |
| `schema.parse()`를 try/catch로 감싸 응답을 만든다 | 그냥 던진다. `toAppError`가 접는다(`error-handling.md`) |
| `z.record(z.string())`로 환경을 훑는다 | 필요한 키만 선언한다. 안 쓰는 키는 스키마에 없다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `.strict()`를 요청 입력에 vs 환경에 | 요청에만. 환경에 걸면 `PATH`까지 거부된다(실측 59개) |
| `TaskCreate.partial()` vs 직접 쓴 `TaskUpdate` | 앞은 안쪽 `default`를 살려 부분 수정을 덮어쓴다 |
| `z.date()` vs `z.instanceof(Timestamp)` | 문서에서 오는 값은 뒤. 앞은 `Timestamp`를 거부한다 |
| `TaskStatus`의 **값** vs 멤버 이름 | 와이어·문서·단언에 쓰는 것은 소문자 값이다 |
| `settings` vs 직접 읽기 | 예외는 `src/settings.ts`와 에뮬레이터 주입 테스트뿐이다 |
| 미지 키 무시 vs 거부 | 무시는 **잘못된 성공**을 만든다 — 필터 없는 목록이 200으로 나간다 |
