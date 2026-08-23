<!-- epcc-pack: backend/aws-container v3.12.0 -->
# 입력 검증 (Zod 4) — 요청 본문·쿼리·환경변수

브라우저에서 오는 값은 전부 적대적 입력이다. SPA에도 같은 스키마로 검증이 있더라도
**클라이언트 검증은 UX이고 신뢰 경계는 서버뿐**이다.

## 스키마는 `src/schemas/`에 둔다

아래 `src/schemas/tasks.ts`가 **요청 스키마의 정본**이다. 다른 리소스 파일에 나오는
`CreateTaskInput` / `UpdateTaskInput` / `ListTasksQuery` 인용은 전부 이 정의를 가리킨다.

```ts
// src/schemas/tasks.ts
import { z } from 'zod'

export const TaskIdParam = z.object({ id: z.uuid() })

// 기본값이 없는 필드 정의가 원본이다 — 생성 스키마에만 default를 얹는다
const TaskFields = z.strictObject({
  title: z.string().trim().min(1).max(120),
  body: z.string().max(20_000),
})

export const CreateTaskInput = TaskFields.extend({ body: TaskFields.shape.body.default('') })

export const UpdateTaskInput = TaskFields.partial().refine(
  (v) => Object.keys(v).length > 0,
  { error: '변경할 필드가 최소 하나 필요합니다' },
)

export const ListTasksQuery = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
  cursor: z.string().max(200).optional(),       // base64url("<iso>|<uuid>")
  archived: z.stringbool().optional(),          // "true"/"false" 쿼리 문자열 → boolean
})

export type CreateTaskInput = z.infer<typeof CreateTaskInput>
export type UpdateTaskInput = z.infer<typeof UpdateTaskInput>
export type ListTasksQuery = z.infer<typeof ListTasksQuery>
```

- **PATCH 스키마를 생성 스키마에서 `.partial()`로 뽑지 않는다.** `.partial()`은 `.default()`를
  지우지 못한다 — `CreateTaskInput.partial().parse({})`는 `{ body: '' }`를 내놓는다. 그러면
  ① "필드 하나 이상" `refine`이 영구 통과해 빈 PATCH가 거절되지 않고 ② `set({ ...patch })`가
  **건드리지도 않은 본문을 빈 문자열로 덮어쓴다.** 기본값 없는 `TaskFields`가 원본이어야 한다
- **`strictObject`를 기본으로 쓴다**: 모르는 키가 조용히 통과하면 `{ ownerId: "..." }`
  같은 값이 그대로 `insert`에 실려 갈 수 있다 (`.extend()`·`.partial()`은 strict를 유지한다)
- 모든 문자열에 `max()`를 건다. 상한 없는 문자열은 메모리·저장소 공격면이다
- 쿼리 파라미터는 항상 문자열이다 → 숫자는 `z.coerce.number()`, 불리언은 `z.stringbool()`
- 선언한 쿼리 파라미터는 **반드시 쿼리 함수까지 배선한다**. `archived`는
  `listOwnedTasks(ownerId, limit, cursor, archived)`가 소비한다 (`resources/data-access.md`) —
  파싱만 되고 아무도 읽지 않는 파라미터는 클라이언트에게 없는 기능을 약속한다

## 파싱 헬퍼 (`src/http/validate.ts`)

핸들러가 매번 `safeParse` 분기를 쓰지 않도록 세 개만 만든다.

```ts
import type { Context } from 'hono'
import { z, type ZodType } from 'zod'
import { AppError } from '@/http/errors'

function fail(err: z.ZodError): never {
  throw new AppError(422, 'VALIDATION_FAILED', '요청 값이 올바르지 않습니다',
    z.flattenError(err).fieldErrors)
}

export async function jsonBody<T extends ZodType>(c: Context, schema: T): Promise<z.infer<T>> {
  let raw: unknown
  try {
    raw = await c.req.json()
  } catch {
    throw new AppError(400, 'BAD_REQUEST', 'JSON 본문을 읽을 수 없습니다')
  }
  const r = schema.safeParse(raw)
  return r.success ? r.data : fail(r.error)
}

export function queryParams<T extends ZodType>(c: Context, schema: T): z.infer<T> {
  const r = schema.safeParse(c.req.query())
  return r.success ? r.data : fail(r.error)
}

export function pathParam<T extends ZodType>(c: Context, schema: T): z.infer<T> {
  const r = schema.safeParse(c.req.param())
  return r.success ? r.data : fail(r.error)
}
```

- **파싱 실패는 400이 아니라 422**다. 400은 "JSON조차 아님", 422는 "JSON이지만 규칙 위반"
- `z.flattenError(err).fieldErrors`는 `{ title: ["..."] }` 형태라 SPA 폼에 그대로 매핑된다
- 에러 `details`에 원본 입력을 되돌려 담지 않는다 — 비밀 값이 응답과 로그에 복제된다

## DB 제약으로 한 번 더 건다

Zod는 **이번 요청**만 본다. 동시 요청·다른 진입점·수동 SQL은 Zod를 통과하지 않는다.
그래서 같은 규칙을 스키마 제약으로도 표현한다.

| 규칙 | Zod (요청 경계) | DB (최종 방어) |
| --- | --- | --- |
| 필수 값 | `z.string().min(1)` | `.notNull()` |
| 사용자별 제목 중복 금지 | 사전 조회는 경합에 진다 | `uniqueIndex('tasks_owner_title_key')` |
| 길이 상한 | `.max(120)` | `varchar(120)` 또는 check 제약 |
| 열거값 | `z.enum([...])` | check 제약 또는 참조 테이블 |

중복 확인을 `select` → 없으면 `insert`로 구현하면 동시 요청 두 개가 모두 통과한다.
**그냥 넣고 `23505`를 409로 변환한다** (`resources/api-endpoints.md`의 `isUniqueViolation`).

## 환경변수도 입력이다 (`src/config/env.ts`)

앱 코드가 `process.env`를 직접 읽으면 오타·누락이 **배포 후 특정 경로에서만** 터진다.
검증된 단일 모듈을 두어 부팅 시점에 실패시킨다.

```ts
import { z } from 'zod'

const PublicEnv = z.object({                       // 로그에 찍어도 되는 값
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().default(8080),
  LOG_LEVEL: z.enum(['debug', 'info', 'warn', 'error']).default('info'),
  CORS_ORIGINS: z.string().transform((s) => s.split(',').map((v) => v.trim())),
  DB_POOL_MAX: z.coerce.number().int().min(1).max(50).default(10),
  DB_SSL: z.stringbool().default(true),
  DB_CA_PATH: z.string().min(1).optional(),        // 서버 인증서 검증용 CA 번들 경로
  OIDC_ISSUER: z.url(),                            // 예: https://cognito-idp.<region>...
  OIDC_JWKS_URL: z.url(),
  OIDC_AUDIENCE: z.string().min(1),                // 앱 클라이언트 id (= client_id 클레임)
  OIDC_GROUPS_CLAIM: z.string().min(1).default('cognito:groups'),
  OIDC_AUTHORIZE_BASE: z.url(),                    // Hosted UI 도메인 (authorize·logout의 origin)
  SPA_CALLBACK_URL: z.url(),                       // 앱 클라이언트에 등록된 콜백 URL
  SPA_LOGOUT_URL: z.url(),                         // 등록된 sign-out URL (logout_uri에 그대로)
  S3_BUCKET: z.string().min(1),
  S3_ENDPOINT: z.url().optional(),                 // 온프레미스 MinIO일 때만 설정
  AWS_REGION: z.string().min(1).optional(),        // S3 어댑터 설정값 — 온프레미스에선 비운다
})

const SecretEnv = z.object({                       // 절대 로그·응답에 넣지 않는 값
  DATABASE_URL: z.string().startsWith('postgres'),
  AUTH_STATE_SECRET: z.string().min(32),           // OAuth state 서명 키 (HMAC)
})

const EnvSchema = z.object({ ...PublicEnv.shape, ...SecretEnv.shape })
const parsed = EnvSchema.safeParse(process.env)
if (!parsed.success) {
  console.error(JSON.stringify({
    level: 'error', msg: 'invalid environment',
    issues: z.flattenError(parsed.error).fieldErrors,   // 키 이름만, 값은 찍지 않는다
  }))
  process.exit(1)                                   // 부팅 실패 = 배포 실패 (헬스체크가 잡는다)
}

export const env = parsed.data
export const publicEnvKeys = Object.keys(PublicEnv.shape)   // 로그 마스킹 기준
```

규칙:

- `env`는 `src/` 어디서나 import한다. **`process.env`는 이 파일에서만 등장한다**
  (CI에서 `grep -rn "process\.env" src/ --include=*.ts | grep -v config/env.ts`가 비어야 한다)
- **`env`에 없는 키를 코드가 읽으면 컴파일이 깨져야 한다.** 새 설정을 쓰기 전에 이 스키마에
  먼저 추가한다 — 스키마에 없는 키를 `env.X`로 읽으면 타입 에러이므로 누락이 부팅 전에 잡힌다
- **서버 비밀을 `VITE_*` 접두사에 두지 않는다.** Vite는 그 접두사를 브라우저 번들에
  인라인한다 — 리포지토리를 공유하는 SPA 쪽 `.env`와 백엔드 `.env`를 섞지 않는다
- 비밀 분류 기준은 "유출되면 사고인가"다. `DB_POOL_MAX`·`DB_SSL`은 튜닝 값이라 공개다 —
  비밀 목록을 부풀리면 로그·부팅 진단에 쓸 수 있는 값이 사라진다
- `publicEnvKeys`는 로거가 **부팅 설정을 찍을 때 화이트리스트**로 쓴다. 목록에 없는 키는
  구조적으로 로그에 오를 수 없다 → `resources/portability-boundaries.md`의 `logBootConfig`
- 부팅 실패는 `throw`가 아니라 `process.exit(1)` — 컨테이너가 즉시 죽고 배포가 롤백된다.
  **이 파일의 `safeParse` + `exit(1)`이 부팅 검증의 유일한 형태다** (`parse`를 쓰지 않는다)
- 로컬은 `docker compose`의 `environment:`가 진입점이다. `.env`는 커밋하지 않고
  `.env.example`에 **키 이름만** 유지한다

## 파일 업로드 입력

SPA가 파일을 직접 올린다면 presigned URL로 넘기더라도 **메타데이터는 서버가 검증**한다:
`contentType`을 허용 목록으로 제한하고, `contentLength` 상한을 서명 조건에 넣는다.
클라이언트가 보낸 파일명은 저장 키로 쓰지 않는다 — 서버가 키를 생성한다.

## 오용 목록 (Zod 3 → Zod 4 관용구 대조표)

| 구 습관 (Zod 3) | Zod 4 형태 |
| --- | --- |
| `z.string().email()` | `z.email()` |
| `z.string().uuid()` | `z.uuid()` |
| `z.string().url()` | `z.url()` |
| `z.object({...}).strict()` | `z.strictObject({...})` |
| `z.object({...}).passthrough()` | `z.looseObject({...})` |
| `{ message: '...' }` | `{ error: '...' }` |
| `{ required_error, invalid_type_error }` | 단일 `error` 콜백/문자열 |
| `err.format()` | `z.treeifyError(err)` |
| `err.flatten()` | `z.flattenError(err)` |
| `z.preprocess((v) => v === 'true', z.boolean())` | `z.stringbool()` |
| `z.record(z.string())` (단일 인자) | `z.record(z.string(), z.string())` (키·값 모두 명시) |

## 오용 목록 (혼동 쌍)

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `parse()` vs `safeParse()` | **둘 다 `safeParse`다.** 경계 파싱은 422 봉투로, 부팅 설정은 키 이름만 찍고 `process.exit(1)`로 — `parse`의 예외는 스택만 남기고 어느 키가 빠졌는지를 로그에서 잃는다 |
| `Create.partial()`로 PATCH 스키마 만들기 | `.default()`가 남아 빈 PATCH가 통과하고 미지정 필드를 덮어쓴다 → 기본값 없는 base를 원본으로 두고 Create에만 `.default()`를 얹는다 |
| `z.object()` vs `z.strictObject()` | 요청 본문은 `strictObject` — 미지 키를 거절한다. 외부 웹훅 페이로드는 `object`가 낫다 |
| `.optional()` vs `.nullish()` vs `.default()` | 키 없음은 `optional`, `null` 허용까지면 `nullish`, 값이 항상 있어야 하면 `default` |
| `z.coerce.number()` vs `z.number()` | 쿼리 파라미터는 문자열이므로 `coerce`. JSON 본문의 숫자는 `z.number()` |
| `z.infer` vs `z.input` | 서비스 시그니처는 변환 **후** 타입인 `z.infer`. `z.input`은 파싱 전 형태다 |
| 응답도 스키마로 파싱 | 응답은 우리가 만든 값이다 — 파싱 대신 반환 타입으로 계약한다. 파싱은 신뢰 경계에서만 |
| SPA와 스키마 파일 공유 | 공유해도 되지만 **서버 검증을 생략하는 근거는 아니다**. 클라이언트는 어떤 요청이든 보낼 수 있다 |
