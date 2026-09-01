<!-- epcc-pack: frontend/vanilla v3.14.0 -->
# 타입과 테스트 — 주석이 주장하고, zod가 검증하고, tsc가 판정한다

소유: `jsconfig.json`의 검사기 설정 · `src/schemas/task.js`의 도메인 스키마와 타입 ·
`src/config.js`의 검증된 환경 값 · `vite.config.js`와 `test/`의 Vitest 하네스. 소유하지 않는 것 —
스토어의 제네릭은 `resources/state-management.md`, DOM 생성과 정리는
`resources/component-patterns.md`, 실제 API 호출은 이음매의 `data-fetching` 슬롯이다.

## 1. 결정 트리 — 주장인가 검증인가

**값이 어디서 왔는가**가 유일한 기준이다. 타입이 코드에 없고 주석에만 있으므로, 경계를
잘못 그으면 검사기가 통과시킨 코드가 런타임에 다른 모양을 받는다.

| 값의 출처 | 쓸 것 | 왜 |
| --- | --- | --- |
| 이 코드베이스가 만든 리터럴·계산 결과 | `@param` · `@returns` | tsc가 흐름을 따라간다. 런타임 비용 0 |
| 네트워크 응답 · `localStorage` · `URLSearchParams` · `postMessage` | `parseTask` 같은 zod 파서 | 주석은 런타임에 존재하지 않는다 |
| `import.meta.env` | `src/config.js`의 `config` | 빌드 시점에 문자열로 인라인된다 — 읽는 자리를 하나로 둔다 |
| `JSON.parse` 반환 | zod 파서 | 반환이 `any`라 **여기서 타입이 끊긴다** |

마지막 행이 이 축에서 가장 자주 새는 자리다. `any`는 오류를 내지 않고 조용히 퍼진다.

## 2. 검사기를 켠다 (`jsconfig.json`)

`checkJs`만 켜는 것으로는 부족하다. **`strict`가 없으면 주석을 빠뜨린 함수가 오류 없이
통과한다** — 「타입이 없다」가 아니라 「검사되지 않는다」다.

<!-- file: jsconfig.json -->
```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "allowJs": true,
    "checkJs": true,
    "noEmit": true,
    "strict": true,
    "types": ["vite/client", "vitest/globals"]
  },
  "include": ["src", "test", "*.js"]
}
```

`scripts.typecheck`는 `tsc --noEmit -p jsconfig.json`이다. tsc는 **검사기일 뿐 배송 언어가
아니다** — 산출물은 Vite가 만들고 `.js`가 그대로 나간다. 같은 파일을 `strict: false`로 돌리면
미주석 매개변수가 **한 건도 보고되지 않는다.**
<!-- verified: typescript@7.0.2 로 strict 켬=TS7006 / 끔=무오류 를 실행 대조 -->

## 3. JSDoc 타입 규약 (`src/schemas/task.js` 이외 전 파일 공통)

- **export하는 함수는 `@param`과 `@returns`를 모두 단다.** 하나라도 빠지면 그 자리에서
  `any`가 시작되고, 호출자 쪽에서는 오류가 사라진 것처럼 보인다
- 타입 이름은 **인라인 import**로 가져온다 — `.js` 확장자를 붙인다
- 단언은 `/** @type {T} */ (값)` — **괄호가 문법의 일부다.** 콜백은 인자 자리에서 바로 단다

```js
// 타입을 소비하는 쪽 — 인라인 import 로 가져온다
/** @typedef {import('../schemas/task.js').Task} Task */

/** @type {Task[]} */
const tasks = [];
const titles = tasks.map(/** @param {Task} t @returns {string} */ ((t) => t.title));
```

`titles`가 `string[]`로 좁혀지는 것을 tsc가 확인한다 — `titles[0].toFixed(2)`는 오류다.

## 4. 도메인 스키마 (`src/schemas/task.js`)

**스키마가 진실이고 타입은 거기서 도출한다.** 손으로 쓴 `@typedef`를 스키마 옆에 두면
두 벌이 되고, 두 벌은 반드시 갈라진다.

```js
// src/schemas/task.js
import { z } from 'zod';

export const TaskStatus = z.enum(['open', 'done']);

const taskInputFields = {
  title: z.string().min(1).max(200),
  status: TaskStatus,
};

export const TaskSchema = z.object({
  id: z.string().min(1),
  ownerId: z.string().min(1),
  ...taskInputFields,
  createdAt: z.iso.datetime(),
}).strict();

/** @typedef {import('zod').infer<typeof TaskSchema>} Task */

export const TaskCreateSchema = z.object({
  ...taskInputFields,
  status: TaskStatus.default('open'),
}).strict();

/** @typedef {import('zod').infer<typeof TaskCreateSchema>} TaskCreate */

export const TaskUpdateSchema = z.object(taskInputFields).partial().strict();
```

- **`TaskUpdateSchema`를 `TaskCreateSchema.partial()`로 만들지 않는다.** `.partial()`은
  `.default('open')`을 벗기지 않아서, `status`를 보내지 않은 부분 수정이 `{ status: 'open' }`이
  된다 — 완료 처리한 작업이 조용히 되살아난다. 기본값 없는 필드 묶음에서 각각 만든다
  <!-- verified: zod@4.4.3 에서 Create.partial().parse({}) === {status:'open'} 을 노드로 관측 -->
- `createdAt`은 **ISO 문자열로 두고 `Date`로 바꾸지 않는다.** 직렬화 경계를 하나로 유지한다
- `.strict()`가 미지 키를 막는다 — 서버가 나중에 붙인 `isAdmin` 같은 필드가 그대로 흘러
  들어오지 않는다

`TaskStatus`의 값은 **소문자 `'open'`·`'done'`이다.** 와이어·`data-*` 속성·테스트 단언에
쓰는 것은 이 값이지 심볼 이름이 아니다.

## 5. 경계 파서 `parseTask` — `@type`이 끝나는 자리

```js
// src/schemas/task.js
/**
 * @param {unknown} raw
 * @returns {Task}
 */
export function parseTask(raw) {
  const result = TaskSchema.safeParse(raw);
  if (!result.success) {
    const where = result.error.issues.map((i) => i.path.join('.')).join(', ');
    throw new Error(`Task 형태가 아니다: ${where}`);
  }
  return result.data;
}
```

`safeParse`는 던지지 않고 `{ success, data | error }`를 준다. 여기서 **파서가 던지는 것이
계약이다** — 호출자가 실패를 무시하고 진행할 길을 남기지 않는다. `error.issues[].path`가
어긋난 필드를 짚어 준다.

```js
// ❌ 검사기는 통과하지만 런타임 보장이 0이다
const task = /** @type {Task} */ (await res.json());
// ✅ 경계에서 다시 파싱한다
const task = parseTask(await res.json());
```

`{ id: 't1', title: 'x' }`를 두 줄에 각각 넣으면 앞은 `task.status`가 `undefined`인 채로
흐르고, 뒤는 `ownerId, status, createdAt`을 짚어 던진다. <!-- verified: node 로 두 경로 실행 -->

## 6. 검증된 환경 값 (`src/config.js`)

**환경을 읽는 유일한 파일이다.** 모듈 최상위에서 파싱하므로 값이 어긋나면 부팅이 실패한다 —
첫 요청 시점에 터지면 사용자가 반쯤 살아 있는 화면을 본다.

```js
// src/config.js
import { z } from 'zod';

const EnvSchema = z.object({
  VITE_API_BASE: z.url(),
  VITE_ENV: z.enum(['development', 'staging', 'production']),
});

const parsed = EnvSchema.safeParse(import.meta.env);

if (!parsed.success) {
  const missing = parsed.error.issues.map((i) => i.path.join('.')).join(', ');
  throw new Error(`환경 값이 유효하지 않다: ${missing}`);
}

/** @typedef {import('zod').infer<typeof EnvSchema>} Config */

/** @type {Config} */
export const config = parsed.data;
```

**`VITE_` 접두사가 붙은 값은 번들에 문자열로 박힌다.** 비밀은 여기에 둘 수 없다 —
브라우저로 내려가는 코드에 그대로 남는다. 읽는 자리가 하나여야 그 검토도 한 곳에서 끝난다.

## 7. 테스트 하네스 (`vite.config.js` · `test/setup.js`)

<!-- file: vite.config.js -->
```js
// vite.config.js
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    environment: 'happy-dom',
    setupFiles: ['./test/setup.js'],
    include: ['test/**/*.test.js'],
  },
});
```

**`defineConfig`를 `vite`가 아니라 `vitest/config`에서 가져온다.** `vite`의 것으로 `test` 키를
쓰면 실행은 되지만 타입체크가 `TS2769`로 죽는다 — 검사기를 켜 놓은 이 팩에서는 CI가 막힌다.
<!-- verified: vite@8.2.2 + vitest@4.1.11 로 재현하고 import 교체로 해소 확인 -->

<!-- file: test/setup.js -->
```js
// test/setup.js
import { afterEach } from 'vitest';

afterEach(() => {
  document.body.replaceChildren();
  window.history.replaceState(null, '', '/tasks');
});
```

happy-dom은 파일 사이에서 DOM과 History를 초기화하지 않는다. 남은 노드와 남은 URL이 다음
파일의 단언을 통과시키는 것이 이 축에서 가장 흔한 위양성이다.

## 8. 차단을 증명하는 테스트 (`test/schemas.test.js`)

**부정 단언만 있는 테스트는 차단 장치가 아니다.** 스키마를 통째로 `z.any()`로 바꿔도
`expect(...).success).toBe(false)`만 있는 테스트는 초록일 수 있다. 긍정 경로를 **같은 `it`
안에** 짝으로 건다.

<!-- file: test/schemas.test.js -->
```js
// test/schemas.test.js
import { describe, it, expect } from 'vitest';
import { TaskSchema, TaskCreateSchema, TaskUpdateSchema, parseTask } from '../src/schemas/task.js';

const valid = {
  id: 't1', ownerId: 'u1', title: '보고서 초안',
  status: 'open', createdAt: '2026-08-24T03:00:00Z',
};

describe('TaskSchema', () => {
  it('정상 Task 는 통과하고 미지 키는 막힌다', () => {
    expect(TaskSchema.safeParse(valid).success).toBe(true);
    expect(TaskSchema.safeParse({ ...valid, isAdmin: true }).success).toBe(false);
  });

  it('status 는 소문자만 받는다', () => {
    expect(TaskSchema.safeParse({ ...valid, status: 'done' }).success).toBe(true);
    expect(TaskSchema.safeParse({ ...valid, status: 'OPEN' }).success).toBe(false);
  });
});

describe('부분 수정', () => {
  it('생성은 status 를 채우고, 수정은 보내지 않은 필드를 만들지 않는다', () => {
    expect(TaskCreateSchema.parse({ title: 'a' })).toEqual({ title: 'a', status: 'open' });
    expect(TaskUpdateSchema.parse({ title: 'b' })).toEqual({ title: 'b' });
  });
});

describe('parseTask', () => {
  it('경계에서 통과시키고 형태가 다르면 던진다', () => {
    expect(parseTask(valid).id).toBe('t1');
    expect(() => parseTask({ ...valid, createdAt: '2026-08-24' })).toThrow(/createdAt/);
  });
});
```

세 번째 `describe`가 이 파일에서 가장 비싼 단언이다. `TaskUpdateSchema`를
`TaskCreateSchema.partial()`로 되돌리면 `toEqual({ title: 'b' })`가 즉시 빨개진다 —
그것이 「차단이 살아 있다」의 증명이다. <!-- verified: 두 형태로 각각 vitest run 을 돌려 대조 -->

## 9. 무엇을 테스트하지 않는가

| 쓰지 않는다 | 대신 |
| --- | --- |
| `z.string().min(1)`이 빈 문자열을 막는지 | zod의 테스트다. **우리 스키마의 조합**만 단언한다 |
| JSDoc 타입이 맞는지 확인하는 런타임 단언 | `tsc --noEmit`이 판정한다. CI에 그 명령을 넣는다 |
| CSS 계산값·실제 렌더 결과 | happy-dom은 **대리**다. 이 축은 실 브라우저 왕복을 검증하지 못한다 |
| 이음매의 `fetchTasks` 응답 형태 | 조립 후에 생긴다. 팩은 `parseTask`가 그것을 막는다는 것만 단언한다 |

## 오용 목록 ① — TypeScript · zod 3 습관 → JSDoc + zod 4 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `interface Task { … }` | `/** @typedef {import('zod').infer<typeof TaskSchema>} Task */` |
| `function f(x: string): Task {}` | `/** @param {string} x */` + `/** @returns {Task} */` |
| `value as Task` | `/** @type {Task} */ (value)` — 괄호가 필수다 |
| `z.string().url()` · `z.string().datetime()` | `z.url()` · `z.iso.datetime()` <!-- verified: zod@4.4.3 로 두 형태 실행 대조 --> |
| `.partial()`로 수정 스키마 파생 | 기본값 없는 필드 묶음에서 각각 만든다 (§4) |
| `defineConfig` from `vite` + `test` 키 | `vitest/config`의 `defineConfig` (§7) |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `@type` vs `parseTask` | 내가 만든 값은 앞, 프로세스 밖에서 온 값은 뒤 |
| `.parse()` vs `.safeParse()` | 실패가 곧 중단이면 앞(부팅·테스트), 흐름을 이어야 하면 뒤 |
| `TaskCreateSchema` vs `TaskUpdateSchema` | 생성은 기본값을 채운다. 수정은 **채우지 않는다** |
| `checkJs` vs `strict` | 앞은 검사를 켜고, 뒤가 미주석을 오류로 만든다 |
| `environment: 'happy-dom'` vs `'node'` | DOM·History를 만지면 앞, 순수 스키마 테스트면 뒤로 충분하다 |
| `import.meta.env` 직접 읽기 vs `config` | **언제나 뒤.** 직접 읽기는 `src/config.js`에서만 허용된다 |
