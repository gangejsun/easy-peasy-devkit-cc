<!-- epcc-pack: backend/firebase v3.14.0 -->
# 테스트와 배포 — 에뮬레이터가 유일한 증거

`firebase.json` · `functions/test/emulator.ts`(`emulatorEnv` · `withRulesTest` · `RULES`) ·
`functions/test/tasks.test.ts`(함수·리포지토리 회귀) · 인덱스 배포 순서를 소유한다.

**규칙 단위 테스트는 이 파일이 소유하지 않는다** — `functions/test/rules.test.ts`는
`resources/security-rules.md`의 몫이다(한 경로에 한 소유자). 스키마는
`resources/input-validation.md`, 리포지토리는 `resources/data-access.md`, `AppError`·`authFor`는
**이음매**(`functions/src/http/`)가 소유한다.

## 1. 결정 트리 — 무엇을 어느 하네스로 증명하는가

| 증명할 것 | 하네스 | 소유 |
| --- | --- | --- |
| `firestore.rules`의 소유권 불변식 | `withRulesTest` + `assertFails`/`assertSucceeds` 짝 | `security-rules.md` |
| 진입점의 소유권·검증·에러 봉투 | `onCall(...).run(req)` + Firestore 에뮬레이터 | 이 파일 |
| 스키마·구성 파라미터 해소 | `parseCallable` · `config()` 직접 호출 | 이 파일 |
| 와이어 계약(상태·본문) | `emulators:exec` + 실제 요청 | 이 파일 |
| 복합 인덱스 | **에뮬레이터로는 못 한다** | 실 프로젝트 배포뿐 |

**`firebase-functions-test`는 쓰지 않는다.** 3.5.0의 peer가 `firebase-admin@^8…^13`이라 admin 14와
ERESOLVE로 충돌해 툴체인 설치를 통째로 실패시킨다. 대체 경로는 `onCall`이 돌려주는 객체의
`.run(request)`이고, 타입 선언이 그것을 *"Used for unit testing"*이라 적는다.
<!-- verified: firebase-functions@7.3.2 v2/providers/https.d.ts:181-186 -->

## 2. 에뮬레이터 스위트 (`firebase.json`)

<!-- file: firebase.json -->
```json
{
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "functions": [{ "source": "functions", "codebase": "default", "runtime": "nodejs22" }],
  "emulators": {
    "auth": { "port": 9099 }, "firestore": { "port": 8080 }, "functions": { "port": 5001 },
    "singleProjectMode": true, "ui": { "enabled": false }
  }
}
```

`demo-` 접두사 프로젝트 ID(`demo-tasks`)면 CLI가 데모 모드로 붙어 실 서비스 접근을 전부
거부한다. CI는 `emulators:exec`가 정본이다 — **종료 코드를 그대로 전파한다**. `firebase-tools@15`는
**JDK 21 이상**을 요구한다(Temurin 17로는 기동 거부). <!-- verified: 파일럿(C1) 실측 · L0 확정 사실 -->

```bash
firebase emulators:exec --project demo-tasks --only firestore,auth,functions "cd functions && npm test"
```

**파라미터가 `.env`에서 해소되지 않으면 CLI가 선언 기본값으로 `functions/.env.local`을 만들어
둔다.** 다음 실행부터 `.env.local`이 `.env`를 이겨 `.env`를 고쳐도 값이 안 바뀐다. 두 파일과
`.secret.local`은 `.gitignore`에 넣는다.
<!-- verified: .env를 지운 뒤 emulators:exec 1회로 .env.local 자동 생성·우선 적용 계측 -->

## 3. 테스트 배선 (`functions/test/emulator.ts`)

<!-- file: functions/test/emulator.ts -->
```ts
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { initializeTestEnvironment, type RulesTestEnvironment } from '@firebase/rules-unit-testing';

const ROOT = resolve(__dirname, '../..');
const FUNCTIONS = resolve(__dirname, '..');
type Ports = { emulators: { firestore: { port: number }; auth: { port: number } } };
const CONFIG = JSON.parse(readFileSync(resolve(ROOT, 'firebase.json'), 'utf8')) as Ports;
export const PROJECT_ID = 'demo-tasks';
export const RULES = readFileSync(resolve(ROOT, 'firestore.rules'), 'utf8');

export function emulatorEnv(): void {
  const { firestore, auth } = CONFIG.emulators;
  process.env['GCLOUD_PROJECT'] = PROJECT_ID;
  process.env['FIRESTORE_EMULATOR_HOST'] = `127.0.0.1:${firestore.port}`;
  process.env['FIREBASE_AUTH_EMULATOR_HOST'] = `127.0.0.1:${auth.port}`;
  // 에뮬레이터 변수만으로는 admin SDK의 실 자격 증명 조회가 멈추지 않는다
  process.env['GCE_METADATA_HOST'] = '0';
  // vitest는 firebase-tools가 아니다 — 파라미터 파일을 스스로 읽어야 .value()가 채워진다
  for (const f of ['.env', '.env.local', '.secret.local']) {
    const p = resolve(FUNCTIONS, f);
    if (existsSync(p)) process.loadEnvFile(p);
  }
}

export async function withRulesTest(fn: (env: RulesTestEnvironment) => Promise<void>) {
  emulatorEnv();
  const env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { rules: RULES, host: '127.0.0.1', port: CONFIG.emulators.firestore.port },
  });
  try {
    await env.clearFirestore();
    await fn(env);
  } finally {
    await env.cleanup();
  }
}
```

ⓐ 포트를 `firebase.json`에서 읽는다 — 상수로 베끼면 스위트와 테스트가 다른 포트를 보고도 초록이
된다. ⓑ 규칙을 **출하 파일에서** 읽는다(`RULES`) — 인라인하면 배포되는 파일을 아무도 검사하지
않는다. ⓒ `cleanup()`을 `finally`에 둔다. ⓓ `vitest`는 `firebase-tools`가 아니라
`functions/.env`를 읽지 않는다 — 배선 전에 `config()`가 빈 값을 보고 죽었다.
<!-- verified: ⓓ는 배선 전 구성 검사가 "Too small: expected string to have >=16"으로 실패 -->

<!-- file: functions/test/setup.ts -->
```ts
import { emulatorEnv } from './emulator';
emulatorEnv(); // src/ 를 import하기 전에 돌아야 한다 — beforeAll로는 늦다
```

<!-- file: functions/vitest.config.mts -->
```ts
import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    setupFiles: ['./test/setup.ts'],
    fileParallelism: false,   // 같은 에뮬레이터 문서를 두 파일이 지운다
    testTimeout: 20_000,
    hookTimeout: 20_000,
  },
});
```

확장자가 `.mts`인 이유는 `functions/package.json`이 `"type": "commonjs"`이기 때문이고,
`setupFiles`가 필요한 이유는 `emulatorEnv()`가 **`src/` import보다 먼저** 돌아야 하기 때문이다 —
모듈 최상위에서 Firestore 클라이언트를 잡으므로 `beforeAll`로는 늦다.

## 4. 함수·스키마 회귀 (`functions/test/tasks.test.ts`)

<!-- file: functions/test/tasks.test.ts -->
```ts
import { describe, expect, it } from 'vitest';
import type { CallableRequest } from 'firebase-functions/v2/https';
import { tasksCreate, tasksGet } from '../src/index';
import { TaskUpdateSchema, parseCallable } from '../src/schemas/task';
import { config } from '../src/params';

// 지역 픽스처다 — `authFor`는 이음매(functions/src/http/auth.ts)가 소유하므로 이름을 피한다
const fakeAuth = (uid: string): NonNullable<CallableRequest['auth']> =>
  ({ uid, rawToken: '', token: { uid } as unknown as NonNullable<CallableRequest['auth']>['token'] });
const call = (uid: string | null, data: unknown) =>
  ({ ...(uid ? { auth: fakeAuth(uid) } : {}), data, rawRequest: {} }) as CallableRequest;

describe('함수 진입점 — .run()으로 직접 부른다', () => {
  it('소유자는 자기 작업을 읽고 남은 not-found를 받는다', async () => {
    const made = await tasksCreate.run(call('alice', { title: '작업 하나' }));
    expect(made.status).toBe('open');
    const done = await tasksCreate.run(call('alice', { title: '끝난 작업', status: 'done' }));
    expect(done.status).toBe('done'); // 보낸 값을 버리지 않는다
    expect((await tasksGet.run(call('alice', { taskId: made.id }))).title).toBe('작업 하나');
    await expect(tasksGet.run(call('mallory', { taskId: made.id })))
      .rejects.toMatchObject({ code: 'not-found' });
  });

  it('무토큰과 미지 필드는 각자의 코드로 접힌다', async () => {
    await expect(tasksCreate.run(call(null, { title: 'x' })))
      .rejects.toMatchObject({ code: 'unauthenticated' });
    await expect(tasksCreate.run(call('alice', { title: 'x', ownerId: 'mallory' })))
      .rejects.toMatchObject({ code: 'invalid-argument' });
  });

  it('부분 수정은 보낸 필드만 남고 빈 패치는 거부된다', () => {
    expect(parseCallable(TaskUpdateSchema, { title: '새 제목' })).toEqual({ title: '새 제목' });
    expect(() => parseCallable(TaskUpdateSchema, {})).toThrow();
  });

  it('구성은 인스턴스당 한 번만 검증된다', () => {
    expect(config().TASKS_WEBHOOK_KEY.length).toBeGreaterThanOrEqual(16);
    expect(config()).toBe(config());
  });
});
```

**진입점 이름은 리포지토리 심볼과 다르다** — `tasksGet`/`tasksCreate`를 import한다.
`getTask`/`createTask`로 쓰면 `TS2459`이고, 실측에서 그 이름 충돌로 스위트가 적재조차 되지
않았다. **`tasksGet`은 `null`을 돌려주지 않는다**: 없거나 남의 것이면 `AppError('NOT_FOUND')`를
던지고 `withErrors`가 `HttpsError('not-found')`로 옮긴다 — `null` 반환은 리포지토리 `getTask`의
계약이지 콜러블의 계약이 아니다. `AuthData`는 재노출되지 않아
`NonNullable<CallableRequest['auth']>`로 참조하고 `rawToken`은 필수다(빼면 TS2741).
`.run()`은 HTTP 계층을 건너뛰어 **규칙을 우회하는 admin 경로**를 돌린다 — 소유권 부정 단언이
제일 비싼 이유다.

## 5. 차단 증명 — 지워서 빨개지는지 확인한 표

살아있는 테스트와 작동하는 테스트는 다르다. 아래는 **이 파일이 출하하는 `tasks.test.ts`(4건
초록)에 결함을 하나씩 심고 `emulators:exec`로 돌린 결과다.**

| 심은 결함 | 결과 |
| --- | --- |
| `TaskCreateSchema`를 `z.object`로 | 1건 FAIL — `promise resolved "{ id: … }" instead of rejecting` |
| `TaskUpdateSchema`를 `TaskCreateSchema.partial()`로 유도 | 1건 FAIL — `{title,status:'open'}` ≠ `{title}` |
| `TaskUpdateSchema`의 `.refine` 제거 | 1건 FAIL — `expected [Function] to throw an error` |
| `getTask`의 소유 확인 제거 | 1건 FAIL — 남의 문서가 돌아온다 |
| `getTask`를 통째로 `return null` | 1건 FAIL — **긍정 짝이 잡았다** |
| `createTask`가 `status`를 하드코딩 | 1건 FAIL — `expected 'open' to be 'done'` |
| `requireUid`를 `req.auth?.uid ?? 'anonymous'`로 | 1건 FAIL — 무토큰이 통과 |
| `tasksGet`이 `NOT_FOUND` 대신 `null`을 반환 | 1건 FAIL — `promise resolved "null" instead of rejecting` |
| `.secret.local`을 16자 미만으로 | **2건** FAIL — 구성 검증이 두 경로를 막았다 |

<!-- verified: 9개 결함을 각각 심고 emulators:exec로 돌려 종료 코드와 실패 메시지를 계측 -->

**규칙 계열 결함은 여기서 재지 않는다** — `functions/test/rules.test.ts`가 `security-rules.md`
소유이므로 그 차단 증명표도 그 파일이 갖는다. 같은 결함을 두 파일이 각자 계측하면 두 표의
결론이 갈리고, 실측에서 실제로 갈렸다.

## 6. 인덱스 · 배포 순서 · 되돌릴 수 없는 변경

**에뮬레이터는 복합 인덱스를 강제하지 않는다.** `"indexes": []`에서
`where('ownerId','==') + orderBy('createdAt','desc')`가 통과했고, `firestore.indexes.json`이
**JSON 구문 오류(`{ "indexes": [ broken ] }`)여도 기동해 질의를 전부 돌렸다.** 침묵이 계측 실패가
아님은 같은 장치의 **양성 대조군 둘**이 보증한다: `in`에 값 31개면
`INVALID_ARGUMENT: 'IN' supports up to 30 comparison values.`로 거부됐고, `firestore.rules`를
깨면 `Error compiling rules: L2:1 mismatched input '<EOF>'`로 보고했다. **인덱스만 조용했다.**
<!-- verified: indexes.json을 빈 배열/구문 오류로 두고 admin SDK 질의 4종을 계측 · 대조군 2건 포함 -->

`firebase deploy`의 타겟 순서는 `--only`에 적은 순서가 아니라 CLI가 가진 고정 순서다:
database → storage → **firestore → functions** → hosting. firestore 안에서는 **규칙 → 인덱스**
순이고, 인덱스 생성은 POST 한 번이라 **완성을 기다리지 않는다.**
<!-- verified: firebase-tools@15.28.1 deploy/index.js:30-42 · filterTargets.js:6-16 · deploy/firestore/deploy.js · firestore/api.js:356-366 -->

순서는 지켜지지만 완성은 보장되지 않는다 — 새 쿼리를 쓰는 함수는 인덱스를 먼저 배포하고
콘솔에서 `Enabled`를 본 다음 올린다. <!-- unverified: 실 프로젝트 배포가 필요해 계측하지 못했다 -->
파일에 없는 기존 인덱스는 **기본적으로 지우지 않는다**: 대화형이면 확인을 묻고(기본 아니오),
`--non-interactive`는 로그만 남기며 `--force`에서만 지운다 — CI에서 `--force`를 습관으로
붙이면 그때부터 인덱스 파일이 삭제 권한을 갖는다.
<!-- verified: firebase-tools@15.28.1 firestore/api.js:85-121 -->

`firebase deploy`는 인증을 먼저 하므로 **오프라인에서는 인덱스 파일 검증에 도달조차 못 한다** —
JSON 구문 오류도 `Failed to authenticate`가 먼저다. 유일한 로컬 검증은 CLI 내부의
`validateSpec`을 직접 부르는 것이고, 그것을 배포 전 스크립트로 고정한다.

<!-- file: scripts/check-indexes.mjs -->
```js
import { readFileSync } from 'node:fs';
import { FirestoreApi } from 'firebase-tools/lib/firestore/api.js';
const api = new FirestoreApi();
try {
  api.validateSpec(api.upgradeOldSpec(JSON.parse(readFileSync('firestore.indexes.json', 'utf8'))));
} catch (e) {
  console.error(`firestore.indexes.json 부적합: ${e.message}`);
  process.exit(1);
}
```

`order: "ASC"`(정답은 `ASCENDING`)를 잡아 exit 1을 준다. **`queryScope` 누락은 놓친다** — 서버
검증의 대체물이 아니라 값 오타 필터다. <!-- verified: 두 결함을 각각 넣어 종료 코드 1/0을 계측 -->
배포는 `check-indexes` → `emulators:exec` 테스트 → `--only firestore:rules,firestore:indexes` →
(콘솔에서 `Enabled` 확인) → `--only functions` 순으로 고정한다.

되돌릴 수 없는 것 넷. ① **인덱스 삭제**는 다시 만들 때 컬렉션 전체를 백필한다. ② **export 이름
변경**은 매니페스트의 엔드포인트 키가 곧 export 이름이라 함수 삭제 + 신규 생성이 되고 URL·최소
인스턴스가 초기화된다. ③ **규칙 배포는 전체 교체라** 빠뜨린 블록은 사라진다. ④ **하위 컬렉션은
부모를 지워도 고아로 남는다.** <!-- verified: ②는 매니페스트의 endpoints.tasksCreate.entryPoint · ④는 파일럿(C1) 실측(L0) -->

## 오용 목록 ① — `firebase-functions-test` → 에뮬레이터 관용구 대조표

| 구 습관 | 현재 형태 |
| --- | --- |
| `firebase-functions-test`로 감싼다 · `test.wrap(fn)` | `onCall(...).run(request)`를 직접 부른다 |
| `firebase.initializeTestApp({ auth })` · `firebase.loadFirestoreRules({ rules })` | `env.authenticatedContext(uid)` · `initializeTestEnvironment({ firestore: { rules } })` |
| `firebase.clearFirestoreData()` · `firebase.apps().map((a) => a.delete())` | `env.clearFirestore()` · `env.cleanup()` |
| 테스트 안에 규칙 문자열을 인라인 | `readFileSync('firestore.rules')` — 출하 파일을 검사한다 |
| `vitest --reporter=basic` | `vitest@4`가 제거했다. 기본 리포터를 쓴다 <!-- verified: 파일럿(C1) 로더 오류로 확인 · L0 확정 사실 --> |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `emulators:start` vs `emulators:exec` | 개발 중에는 앞, CI는 뒤. `exec`만 종료 코드를 전파한다 |
| `getTask`(리포지토리) vs `tasksGet`(진입점) | 앞은 `null` 반환, 뒤는 `not-found` 예외. 테스트가 import하는 것은 뒤다 |
| `authFor` vs `fakeAuth` | 앞은 이음매 소유다. 팩의 테스트가 주체를 만들면 다른 이름을 쓴다 |
| `assertSucceeds` vs `await` · `clearFirestore()` vs `cleanup()` | 앞 쌍은 같다(no-op) · 뒤는 데이터만 vs 환경 자체 |
| 에뮬레이터 초록 = 인덱스 정상 | 아니다. 강제하지도 검사하지도 않는다 |
| `vitest.config.ts` vs `.mts` | `"type": "commonjs"` 패키지에서는 `.mts` |
| `.env` vs `.env.local` | CLI가 자동 생성하면 그쪽이 이긴다. 둘 다 `.gitignore` |
