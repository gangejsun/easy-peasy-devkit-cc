<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# 테스트와 배포 — 앱을 네트워크 없이 태우고, 차단을 증명하고, 컨테이너로 내보낸다

이 파일이 소유하는 것은 **테스트 하네스**(`test/helpers.ts` — `appFetch`·`withEmulator`) ·
**컨테이너 정의**(`Dockerfile`) · **런타임 서비스 계정 권한** 셋이다. 단위 테스트 파일은
**대상을 소유한 리소스가 소유한다** — `test/errors.test.ts`는 `error-handling.md`,
`test/schemas.test.ts`는 `input-validation.md`다. `startServer`·`shutdown`은 `project-structure.md`,
리포지토리는 `data-access.md`, 인덱스 선언은 `data-modeling.md`가 소유하고,
`currentUser`·`authFor`·`apiRouter`·`AppError`는 **이음매**가 정의한다 — 여기서는 부르고 대체할 뿐이다.

**이 축에는 백업이 없다.** `firestore.rules`는 전면 거부이고 서버는 서비스 계정으로 붙어 규칙을 통째로
우회한다. 소유권 경계를 관측하는 것은 이 테스트들뿐이고, **그 계정이 실제 권한 경계다.**

## 1. 무엇을 어느 층에서 태우는가

| 확인 대상 | 태우는 법 | 에뮬레이터 | 이 층을 피하면 무엇을 놓치나 |
| --- | --- | --- | --- |
| 스키마 거부 · 필드 오류 맵 | 함수 직접 호출 | 불필요 | — (`input-validation.md`가 소유한다) |
| gRPC 코드 판별 · 상태 매핑 | 함수 직접 호출 + 픽스처 | 불필요 | — (`error-handling.md`가 소유한다) |
| **소유권 차단 · 목록 필터 · 커서** | `appFetch(createApp(), …)` | **필수** | 리포지토리를 스텁으로 바꾸면 `where('ownerId', …)` 누락이 보이지 않는다 |
| **복합 인덱스 누락** | **어느 층에서도 걸리지 않는다** | — | 에뮬레이터는 인덱스를 요구하지 않는다 — 프로덕션 첫 요청이 gRPC 9로 죽는다 |
| 컨테이너 부팅 · 시그널 배수 | 이미지를 실제로 띄운다 | — | `PORT` 미준수와 배수 미동작은 배포 헬스체크에서만 드러난다 |

**세 번째 줄이 이 축의 전부다.** 소유권이 사는 곳은 자바스크립트가 아니라 **쿼리**다 — 리포지토리를
가짜로 바꾼 테스트는 초록이면서 아무것도 지키지 않는다. **네 번째 줄은 공백이고 메워지지 않는다**:
인덱스는 별개 산출물로 배포되고(6절) 에뮬레이터는 인덱스 없이도 복합 쿼리에 답한다.

## 2. `appFetch` — 서버를 세우지 않는다 (`test/helpers.ts`)

Hono 앱은 웹 표준 `Request`를 받아 `Response`를 돌려주는 함수다. `app.request()`는 그 함수를
직접 부른다 — 포트도, 소켓도, `serve()`도 없다.

<!-- verified: hono 4.13.4에서 net.Socket.connect · globalThis.fetch · net.Server.listen을 계측 — 두 요청 동안 셋 다 0회 -->
실측: `GET /healthz`와 `POST /echo`를 태우는 동안 소켓 연결·전역 `fetch`·`server.listen` 모두 **0회**였다.

<!-- verified: hono 4.13.4 dist/types/hono-base.d.ts:201 — 반환은 Response | Promise<Response>이고, 동기 핸들러에서 실제로 비-Promise Response가 나오는 것을 관측 -->
**`app.request()`의 반환 타입은 `Response | Promise<Response>`다.** 그래서 `appFetch`를 **`async`로
선언한다** — 그대로 `return`하면 원장의 `Promise<Response>`와 맞지 않아 strict 검사가 `TS2322`로 막는다.

<!-- file: test/helpers.ts -->
```ts
// test/helpers.ts
import type { Hono } from 'hono';
import { settings } from '../src/settings.js';

/** 앱을 네트워크 없이 직접 태운다. async가 Response | Promise<Response>를 흡수한다. */
export async function appFetch(app: Hono, path: string, init?: RequestInit): Promise<Response> {
  return app.request(path, init);
}

/** 에뮬레이터 전용 경로다. 이 가드가 초기화를 실 데이터베이스로 겨누는 것을 막는 유일한 줄이다. */
function clearUrl(): string {
  const host = settings.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error('FIRESTORE_EMULATOR_HOST가 없다 — 실 데이터베이스에 붙을 뻔했다');
  return `http://${host}/emulator/v1/projects/${settings.GCP_PROJECT_ID}/databases/(default)/documents`;
}

async function clearAll(): Promise<void> {
  const res = await fetch(clearUrl(), { method: 'DELETE' });
  if (!res.ok) throw new Error(`에뮬레이터 초기화 실패: ${res.status}`);
}

export async function withEmulator(fn: () => Promise<void>): Promise<void> {
  await clearAll();
  try {
    await fn();
  } finally {
    await clearAll(); // 실패한 테스트가 다음 테스트를 오염시키지 않는다
  }
}
```

`settings`는 `src/settings.ts`가 소유한다 — **하네스도 환경을 직접 읽지 않는다.** 주입하는 자리(3절)만 예외다.

## 3. `withEmulator` — 되돌리지 않으면 다음 테스트가 앞 문서를 본다

**양성 대조군을 먼저 본다.** 격리 없이 두 테스트를 잇고, 뒤 테스트가 목록 길이를 세게 했다.

<!-- verified: firestore 에뮬레이터 v1.19.8 + vitest 4.1.11에서 세 테스트를 한 파일에 잇고 목록 길이를 출력 -->
| 테스트 | 무엇을 했나 | 목록 길이 |
| --- | --- | --- |
| A | `withEmulator` 없이 문서 1개 생성 | 1 |
| B | 아무것도 만들지 않고 목록만 조회 | **1 — 앞 테스트의 문서다** |
| C | 같은 조회를 `withEmulator` 안에서 | **0** |

B가 이 절의 근거다. 새는 것은 「가끔」이 아니라 **항상**이고, 방향이 하필 문서가 **늘어나는** 쪽이라
목록·페이지네이션 테스트가 조용히 다른 것을 재게 된다. **컬렉션을 하나씩 지우지 않는다**: 초기화
엔드포인트는 데이터베이스 전체를 한 번에 비우고, 손으로 적은 컬렉션 목록은 새 컬렉션이 생긴 날 낡는다.

**테스트 파일을 병렬로 돌리지 않는다.** 같은 에뮬레이터 데이터베이스 하나를 공유하므로 한 파일의
초기화가 다른 파일의 테스트 **한복판**에 떨어진다.

<!-- verified: 같은 세 파일을 fileParallelism만 바꿔 실행 — true에서 3개 전부 실패(본 문서 수 1·1·4), false에서 3개 전부 통과 -->
실측: 문서 5개를 만들고 세는 파일 셋을 `fileParallelism: true`로 돌리자 **셋 다 실패**했다(각각 1·1·4개를
봤다). 실패 문구가 「길이가 다르다」이므로 **원인이 격리라는 것이 드러나지 않는다.**

<!-- file: vitest.config.ts -->
```ts
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    env: { // settings는 모듈 최상위에서 파싱한다 — beforeAll에서 넣으면 늦다
      GCP_PROJECT_ID: 'demo-tasks',
      IDENTITY_PLATFORM_PROJECT_ID: 'demo-tasks',
      FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
    },
    fileParallelism: false, // 에뮬레이터 데이터베이스가 하나다
    testTimeout: 30_000,    // 워커의 첫 Firestore 왕복이 3초를 넘는다
  },
});
```

<!-- verified: 첫 Firestore 왕복이 포함된 테스트가 3.1~3.5초, 뒤이은 테스트는 20~350ms로 관측 -->
`testTimeout`은 실측에서 왔다 — 첫 왕복이 3.1~3.5초, 이후는 20~350ms였다. 기본 5초는 그 하나에만
걸려 **타임아웃으로 빨개진 것을 격리 결함으로 읽게** 만든다.

## 4. 의존성 오버라이드와 차단 증명 (`test/tasks.test.ts`)

`createApp()`은 **인자를 받지 않고**(원장) 라우터는 `currentUser`를 모듈에서 직접 import한다.
주입 지점이 없으므로 **모듈 대체가 유일한 자리**다. 대체는 편의가 아니다 — 유효한 Identity Platform
ID 토큰은 서명 키가 Google에 있어 테스트가 만들 수 없다(검증 로직은 `identity-tokens.md`가 확인한다).
`authFor(ownerId, roles?)`는 **동기다** — `await`하지 않는다.

**긍정 짝을 같은 `it` 안에 건다.** 소유자가 200을 받는다는 단언이 있어야 404가 「차단」인지 「전부 고장」인지 갈린다(5절).

<!-- file: test/tasks.test.ts -->
```ts
// test/tasks.test.ts
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Context, Next } from 'hono';
import { appFetch, withEmulator } from './helpers.js';
import { authFor, type AuthUser } from '../src/http/auth.js';
import { createApp } from '../src/app.js';
import { createTask } from '../src/firestore/tasks.js';

// vi.mock 팩토리는 맨 위로 끌어올려진다 — 주체 상자도 vi.hoisted로 함께 끌어올린다.
const ctx = vi.hoisted(() => ({ user: null as AuthUser | null }));
vi.mock('../src/http/auth.js', async (orig) => ({
  ...(await orig<typeof import('../src/http/auth.js')>()),
  currentUser: async (c: Context, next: Next) => { c.set('user', ctx.user); await next(); },
}));

const asUser = (id: string) => { ctx.user = authFor(id); };
const read = (taskId: string) => appFetch(createApp(), `/api/tasks/${taskId}`);
beforeEach(() => asUser('alice'));

describe('소유권 차단', () => {
  it('소유자는 200을 받고 남은 404를 받는다', async () => {
    await withEmulator(async () => {
      const mine = await createTask('alice', { title: '내 작업', status: 'open' });
      // ✅ 긍정 짝. 이 줄이 없으면 아래 404는 「차단」이 아니라 「전부 고장」일 수 있다
      expect((await read(mine.id)).status).toBe(200);
      asUser('bob');
      const res = await read(mine.id);
      expect(res.status).toBe(404);
      expect(res.status).not.toBe(403); // 403은 「그 문서는 있다」는 존재 증명이다
    });
  });
});
```

<!-- verified: 같은 테스트를 정적 import 판본과 동적 import 판본으로 각각 실행 — 둘 다 대체본이 적용돼 통과 -->
**정적 import로 충분하다** — `vi.mock`이 모듈 레지스트리를 먼저 갈아치우므로 `await import()`로 늦게
가져올 필요가 없다. 두 판본을 다 돌려 확인했다.

**대체는 `currentUser`에서 멈춘다.** 리포지토리나 `firestore`까지 대체하면 소유권이 사는 자리가
테스트에서 사라진다 — 자기 스텁이 자기 기대대로 답하는 것을 보는 것이다. 대체해도 되는 것은
**축이 소유하지 않는 것**, 즉 이음매의 자격 증명 배선뿐이다.

## 5. 돌연변이로 확인한다 — 짝을 뺀 판본과 나란히 돌린 결과

같은 테스트에서 긍정 짝 한 줄만 뺀 판본을 만들어 함께 돌렸다.
```ts
// ❌ 부정 단언만 — 이것은 차단 장치가 아니다
it('남의 것을 읽으면 404다', async () => {
  const mine = await createTask('alice', { title: '내 작업', status: 'open' });
  asUser('bob');
  expect((await read(mine.id)).status).toBe(404);
});
```

<!-- verified: firestore 에뮬레이터 v1.19.8에서 두 판본을 같은 실행에 넣고 돌연변이 3종을 하나씩 심어 계측 -->
| 심은 돌연변이 (**셋 다 타입 검사를 통과한다**) | 부정 단언만 | 짝 단언 |
| --- | --- | --- |
| `getTask` 본문을 통째로 `return null` | **초록** | 빨강 |
| `doc.ownerId !== ownerId` 검사 **한 줄** 삭제 | 빨강 | 빨강 |
| 호출부를 `getTask(taskId, ownerId)`로 뒤바꿈 | **초록** | 빨강 |

**첫 줄과 셋째 줄이 요점이다.** 구현을 통째로 무력화해도, 원장이 경고한 인자 순서를 뒤집어도,
부정 단언만 있는 테스트는 **초록으로 남는다** — 그 상태에서는 무엇을 읽어도 404이기 때문이다.
셋째 줄은 두 인자가 모두 `string`이라 타입 검사도 걸러 내지 못한다 — 남는 방벽은 **소유자가 200을
받는다는 한 줄**뿐이다. 둘째 줄은 부정 단언도 무언가는 잡음을 보이지만, 잡는 것은 **지운 그 한 줄뿐**이다.

**습관으로 만든다: 검사 한 줄을 지우고 다시 돌려라.** 빨개지지 않으면 그 테스트는 그 검사를
지키고 있지 않다. 살아남은 가드는 지울 대상이 아니라 **서술을 고칠 대상**이다 — 파일럿이
`src/firestore/errors.ts`의 `typeof code === 'number'` 가드가 살아남는 것을 보고 그 서술을
「유일한 방벽」에서 「이중 방어」로 정정했다(`error-handling.md` 2절).

## 6. 컨테이너와 배포 산출물 (`Dockerfile`)

계약은 셋이다 — **`PORT`를 환경에서 읽는다** · **node가 PID 1이다** · **인덱스는 따로 나간다.**

<!-- file: Dockerfile -->
```dockerfile
# Dockerfile
FROM node:22-slim AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npx tsc   # tsconfig의 outDir가 dist여야 한다. noEmit는 타입체크 전용 스크립트에 둔다

FROM node:22-slim
ENV NODE_ENV=production
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY --from=build /app/dist ./dist
USER node
# exec 형식이다. node가 PID 1이어야 SIGTERM이 배수 핸들러(src/main.ts)에 닿는다.
CMD ["node", "dist/main.js"]
```

**포트를 이미지에 적지 않는다.** Cloud Run이 `PORT`를 주입하고 `settings.PORT`가 읽는다 — 하드코딩한
8080은 주입값과 갈리는 순간 헬스체크를 실패시키는데 로그에는 아무 오류도 없다.

**위험한 것은 「셸 형식」이 아니라 node가 PID 1이 아닌 경우다.**

<!-- verified: darwin · node 24.7.0 · npm 11.5.1에서 각 기동 형태에 SIGTERM을 보내고 핸들러 도달 여부와 종료 코드를 계측. 리눅스 컨테이너의 PID 1 환경은 아니다 -->
| 기동 형태 | 배수 핸들러가 도는가 | 종료 코드 |
| --- | --- | --- |
| `["node", "dist/main.js"]` | **돈다** | 0 |
| `sh -c 'node dist/main.js'` | 돈다 — 셸이 자기를 `exec`로 대체한다 | 0 |
| `sh -c 'node dist/main.js; echo done'` | **안 돈다** — 뒤에 명령이 있어 `exec`가 일어나지 않는다 | 셸이 SIGTERM으로 죽는다 |
| `["npm", "start"]` | 돈다(npm이 전달한다) | **1 — 정상 배수가 실패로 기록된다** |

셋째 줄이 10초 배수를 통째로 없앤다. 넷째 줄은 배수는 되지만 로그에서 정상 종료와 크래시가 구분되지
않는다. **인덱스는 이미지에 들어 있지 않다** — `firestore.indexes.json`은 Firestore로 배포되는 **별개 산출물**이고, 순서도 정해져 있다: 인덱스가 먼저다.

<!-- unverified: 이 환경에 gcloud·firebase CLI와 도커 데몬이 없어 아래 두 명령을 실행하지 못했다 -->
```bash
firebase deploy --only firestore:indexes,firestore:rules   # 먼저. 규칙은 전면 거부다
gcloud run deploy tasks-api --source . --region=asia-northeast3 \
  --service-account=tasks-api-run@PROJECT.iam.gserviceaccount.com --no-allow-unauthenticated
```

## 7. 서비스 계정 최소 권한 — 규칙을 우회하는 자격이다

이 계정은 `firestore.rules`를 통째로 우회한다. **그래서 여기가 실제 권한 경계이고**, 규칙을 조이는 것은
이 축에서 아무것도 바꾸지 않는다.

| 무엇에 | 역할 | 왜 그 선인가 |
| --- | --- | --- |
| 런타임(Cloud Run) | `roles/datastore.user` | 문서 CRUD까지다 |
| 런타임에 **주지 않는 것** | `roles/datastore.owner` | 데이터베이스 관리·삭제가 들어 있다 — 침해당한 컨테이너가 지울 수 있게 된다 <!-- unverified: 역할별 권한 목록을 대조하지 못했다 --> |
| 인덱스·규칙 배포 | `roles/datastore.indexAdmin` <!-- unverified: 역할 이름 미확인 --> | 배포 파이프라인 계정에 준다. 런타임과 **같은 계정을 쓰지 않는다** |
| ID 토큰 검증 | **역할이 필요 없다** | JWKS는 공개 엔드포인트다 — 이 축의 인증은 IAM을 전혀 쓰지 않는다 |
| 서비스 간 호출 | `roles/run.invoker` | 애플리케이션이 아니라 서비스 IAM이 판정한다(`identity-tokens.md` 1절) |

**`--service-account`를 반드시 명시한다.** 주지 않으면 프로젝트 기본 계정이 붙고 그 권한은 배포 명령 어디에도 적혀 있지 않아 **검토할 수 없다** <!-- unverified: 기본 계정의 현재 기본 역할을 확인하지 못했다 -->.

<!-- verified: 자격 증명 없이 존재하지 않는 프로젝트 ID로 에뮬레이터에 붙어 읽기·쓰기·트랜잭션이 전부 성공하는 것을 관측 -->
**테스트는 이 계정을 쓰지 않는다.** 실측에서 **자격 증명 없이, 존재하지 않는 프로젝트 ID로**
읽기·쓰기·트랜잭션이 전부 성공했다 — 통합 테스트가 초록인 것은 권한이 맞다는 뜻이 **전혀 아니고**,
권한 결함은 배포 후 첫 쓰기에서만 드러난다.

## 오용 목록 ① — 구 관용구 → 현재 형태 대조표

| 구 습관 | 현재 형태 (이 축) |
| --- | --- |
| supertest로 서버를 띄워 요청한다 | `appFetch(createApp(), path)` — 포트를 잡지 않는다 |
| `@firebase/rules-unit-testing`으로 규칙을 시험한다 | 이 축의 규칙은 전면 거부이고 서버가 우회한다 — 시험할 규칙이 없다 |
| jest의 `jest.mock` + `__mocks__` 디렉토리 | `vi.mock` + `vi.hoisted` — 팩토리가 최상위 `const`보다 먼저 실행된다 |
| `CMD npm start` | `CMD ["node", "dist/main.js"]` — 종료 코드 0이어야 정상 배수로 남는다 |
| `EXPOSE 8080` + 포트 하드코딩 | `settings.PORT`가 Cloud Run의 주입값을 읽는다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 부정 단언 vs 짝 단언 | 404 하나는 「전부 고장」과 구분되지 않는다. 200 짝이 있어야 차단이다 |
| `currentUser` 대체 vs 리포지토리 대체 | 앞은 이음매라 대체해도 된다. 뒤를 대체하면 지킬 것이 사라진다 |
| 에뮬레이터 통과 vs 인덱스 존재 | 에뮬레이터는 인덱스를 요구하지 않는다 — 통과는 인덱스를 증명하지 않는다 |
| 에뮬레이터 통과 vs IAM 권한 | 에뮬레이터는 자격 증명을 보지 않는다 — 통과는 권한을 증명하지 않는다 |
| 앞 초기화 vs `finally` 초기화 | 둘 다 건다. 앞은 앞선 실행의 잔재를, `finally`는 실패한 테스트의 잔재를 막는다 |
