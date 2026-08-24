<!-- epcc-pack: backend/firebase v3.14.0 -->
# Firestore Security Rules — 브라우저만 막는 경계

이 파일은 **`firestore.rules`의 문법 · 소유권 · 필드 검증 · 규칙 단위 테스트**를 소유한다.
필드 이름은 `resources/data-modeling.md`의 `TaskDoc`에서 오고, 규칙이 막지 **못하는** 경로
(Cloud Functions)의 검사는 `resources/data-access.md`가 소유한다. 어느 경로를 열지의
결정(`clientAccessPolicy`)은 이음매의 `auth-boundaries` 슬롯이 정한다.

## 1. 두 경계 — 규칙이 막는 것과 막지 못하는 것

**이 절이 이 팩 전체에서 가장 중요하다.** `firestore.rules` 전체가 `allow read: if false`인
상태에서 두 SDK로 같은 문서를 읽은 실측이다.

| 경로 | 읽기 | 쓰기 |
| --- | --- | --- |
| 클라이언트 SDK (`firebase@12`) | `permission-denied` — `false for 'get' @ L5` | `permission-denied` |
| `firebase-admin@14` (Cloud Functions) | **성공. 문서가 그대로 돌아온다** | **성공** |

`firebase-admin`은 관리자 자격으로 붙어 **규칙을 평가조차 하지 않는다.** 규칙이 아무리
촘촘해도 **함수 경로는 무방비다** — 함수가 `ownerId`를 확인하지 않으면 규칙이 없는 것과 같다.
거꾸로 함수만 쓸 계획이어도 **규칙은 잠가 둔다.** 「정책 엔진이 있으니 안전하다」는 이 축에서
**절반만 참이다**: 두 경계는 서로를 보완하지 않고 **다른 코드 경로**를 막는다.

## 2. 규칙 골격 (`firestore.rules`)

`read`를 `get`/`list`로, 쓰기를 `create`/`update`/`delete`로 **전부 나눈다.** 묶으면 생성과
수정의 불변식이 달라 둘 중 하나가 반드시 헐거워진다(§4에 실측). 이 파일은 리포지토리 루트에
있고 `firebase.json`과 `functions/test/emulator.ts`가 **디스크에서 읽는다** — 그래서 완전 파일로 배송한다.

<!-- file: firestore.rules -->
```
// firestore.rules
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function isSignedIn() { return request.auth != null; }
    function isOwner(res) { return isSignedIn() && res.data.ownerId == request.auth.uid; }

    function validTask(d) {
      return d.keys().hasOnly(['id', 'title', 'status', 'ownerId', 'createdAt', 'updatedAt'])
          && d.keys().hasAll(['id', 'title', 'status', 'ownerId', 'createdAt', 'updatedAt'])
          && d.title is string && d.title.size() > 0 && d.title.size() <= 200
          && d.status in ['open', 'done'];
    }

    match /tasks/{taskId} {
      allow get:  if isOwner(resource);
      allow list: if isSignedIn()
                  && request.query.limit <= 100
                  && resource.data.ownerId == request.auth.uid;

      allow create: if isOwner(request.resource)
                    && validTask(request.resource.data)
                    && request.resource.data.id == taskId
                    && request.resource.data.createdAt == request.time
                    && request.resource.data.updatedAt == request.time;

      allow update: if isOwner(resource)
                    && isOwner(request.resource)
                    && validTask(request.resource.data)
                    && request.resource.data.id == resource.data.id
                    && request.resource.data.createdAt == resource.data.createdAt
                    && request.resource.data.updatedAt == request.time;

      allow delete: if isOwner(resource);
    }

    match /{document=**} {
      allow read: if false;
      allow create, update, delete: if false;
    }
  }
}
```

`match` 블록의 허용은 **OR로 합쳐진다.** 맨 아래 포괄 거부는 다른 블록의 허용을 되돌리지
않는다 — 아직 규칙을 쓰지 않은 컬렉션을 막을 뿐이다. 그 블록에서도 쓰기는 셋으로 적는다.

## 3. `update`는 `resource`와 `request.resource`를 함께 본다

`resource`는 **기존 문서**, `request.resource`는 **쓰기 후의 문서**다. 실측:

| update 규칙 | 남이 `ownerId`를 자기 것으로 바꾸는 수정 | 소유자의 정상 수정 |
| --- | --- | --- |
| `request.resource`만 본다 | **통과한다** — 문서를 통째로 빼앗긴다 | 통과 |
| 둘 다 본다 | `permission-denied` | 통과 |

새것만 검사하면 공격자가 `ownerId`를 **자기 uid로** 바꾼 순간 소유자가 맞아 통과한다.
`isOwner(resource) && isOwner(request.resource)`는 "바꾸기 전에도 내 것이고 바꾼 뒤에도 내
것"을 요구하므로 이전 자체가 불가능해진다.

실측 둘: **`update`의 `request.resource.data`는 병합된 전체 문서다** — `{ title }`만 보내도
규칙은 `ownerId`를 본다. 뒤집으면 `updatedAt == request.time`을 요구하는 규칙은 **`updatedAt`을
보내지 않은 수정을 거부한다.** `delete`에서는 `request.resource`가 **null**이다.

## 4. `write`로 묶으면 무엇이 헐거워지는가

하나로 묶은 쓰기 규칙(`request.resource` 기준)과 넷으로 나눈 규칙을 같은 데이터에 걸고 잰
결과: **묶은 규칙은 남의 문서에서 `ownerId`를 자기 것으로 바꾸는 수정을 통과시키고, 동시에
소유자 본인의 삭제를 거부한다.** 삭제에는 `request.resource`가 없어서(§3) 묶은 조건이 평가
오류(`Null value error.`)를 내기 때문이다. 즉 묶기는 헐거워지기만 하는 게 아니라 **동시에
고장난다** — 소유자가 자기 작업을 지울 수 없는 채로 배포되고, 같은 규칙이 소유자 이전은
통과시킨다. 하나의 조건식으로 네 동사의 불변식을 동시에 만족시킬 수 없다.

## 5. 필드 검증 — 규칙이 스키마 노릇을 하는 범위

`validTask`는 **키 집합 · 타입 · 리터럴 집합**을 규칙 층에서 강제한다. 무엇이 실제로
거부되는지는 §7의 `create` 테스트가 벡터로 들고 있다 — 미지 필드 `isAdmin` · 리터럴 밖
`status` · 빈 `title` · 남의 `ownerId` · 클라이언트 시각 `createdAt` · 문서 ID 불일치.
`createdAt == request.time`이 규칙이 서버 시각을 강제하는 유일한 방법이다.

**`hasAll`은 이 규칙 파일에서 단독으로 막는 문서가 없다.** 여섯 필드를 하나씩 빼며 쟀더니
`hasAll` 유무와 무관하게 **여섯 경우 전부 거부**됐다 — 나머지 조건이 각 필드를 따로 제약한다.
그래도 남긴다: 저 조건 중 **하나가 빠지면 그 순간 `hasAll`이 유일한 방어**가 된다.

## 6. 규칙과 쿼리의 결합 — `list`는 결과가 아니라 **쿼리**를 평가한다

`allow list`에 `resource.data.ownerId == request.auth.uid`가 있을 때 실측:

| 쿼리 | 결과 |
| --- | --- |
| `where` 없이 목록 | **`permission-denied`** — 0건이 아니다 |
| `where('ownerId', '==', 'alice')` (본인) | 통과, 1건 |
| `where('ownerId', '==', 'bob')` (남) | **`permission-denied`** — 빈 결과가 아니다 |

Firestore는 문서를 읽어 보고 거르지 않는다. **쿼리가 규칙을 만족함을 증명하지 못하면 쿼리
자체를 거부한다.** 그래서 규칙과 쿼리는 항상 같은 커밋에서 바뀐다.

`request.query.limit`에는 함정이 더 있다. `where` + `limit(50)`은 통과하고 `limit(500)`은
거부되지만 **`limit()`을 안 붙인 쿼리도 거부된다** — `null <= 100`이 `Unsupported operation
error.`를 낸다. 이 조건은 **모든 쿼리에 `limit()`을 의무화한다는 뜻**이다.

## 7. 규칙 단위 테스트 (`functions/test/rules.test.ts`)

**에뮬레이터 없이 규칙을 읽어서 검증하지 않는다** — `resource`/`request.resource` 구분과 평가
순서는 읽기로 틀리는 대표 자리다. 이 파일이 **규칙 테스트의 유일한 소유자**이고, `withRulesTest`와
`RULES`는 `resources/testing-and-deploy.md`(`functions/test/emulator.ts`)가 소유한다.

<!-- file: functions/test/rules.test.ts -->
```ts
// functions/test/rules.test.ts
import { describe, expect, it } from 'vitest';
import {
  assertFails,
  assertSucceeds,
  type RulesTestEnvironment,
} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, limit, query,
  serverTimestamp, setDoc, Timestamp, updateDoc, where,
} from 'firebase/firestore';
import { RULES, withRulesTest } from './emulator';
import { COLLECTION } from '../src/firestore/model';

// 출하하는 firestore.rules 원문이다 — emulator.ts가 디스크에서 읽어 RULES로 내놓는다.
// 규칙을 테스트에 문자열로 박으면 출하본을 검사하지 않게 된다.
const rulesForTasks = RULES;
const LUMPED = /allow\s+[a-z,\s]*\bwrite\b\s*:/;

const seed = (env: RulesTestEnvironment, id: string, ownerId: string) =>
  env.withSecurityRulesDisabled((ctx) =>
    setDoc(doc(ctx.firestore(), COLLECTION, id), {
      id, title: '보고서 작성', status: 'open', ownerId,
      createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
    }),
  );

describe('firestore.rules — tasks', () => {
  it('출하 규칙이 검사 대상이고, 쓰기를 묶지 않는다', () => {
    // ❌ 양성 대조군 — 「묶은 쓰기」의 두 형태. 정규식이 둘 다 잡아야 차단 장치다
    expect('  allow write: if isOwner(resource);').toMatch(LUMPED);
    expect('  allow read, write: if false;').toMatch(LUMPED);
    // ✅ 출하본은 그 형태가 아니다
    expect(rulesForTasks).toMatch(/match \/tasks\/\{taskId\}/);
    expect(rulesForTasks).toMatch(/allow\s+create\s*:/);
    expect(rulesForTasks).not.toMatch(LUMPED);
  });

  it('소유자는 읽고 남은 못 읽는다', async () => {
    await withRulesTest(async (env: RulesTestEnvironment) => {
      await seed(env, 't1', 'alice');
      const alice = env.authenticatedContext('alice').firestore();
      const mallory = env.authenticatedContext('mallory').firestore();
      await assertSucceeds(getDoc(doc(alice, COLLECTION, 't1')));
      await assertFails(getDoc(doc(mallory, COLLECTION, 't1')));
    });
  });

  it('소유자 이전 update는 막히고 제목 수정은 통과한다', async () => {
    await withRulesTest(async (env: RulesTestEnvironment) => {
      await seed(env, 't2', 'alice');
      const alice = env.authenticatedContext('alice').firestore();
      const mallory = env.authenticatedContext('mallory').firestore();
      await assertFails(updateDoc(doc(mallory, COLLECTION, 't2'), {
        ownerId: 'mallory', updatedAt: serverTimestamp(),
      }));
      await assertSucceeds(updateDoc(doc(alice, COLLECTION, 't2'), {
        title: '보고서 v2', updatedAt: serverTimestamp(),
      }));
    });
  });

  it('목록은 where가 있어야 통과한다', async () => {
    await withRulesTest(async (env: RulesTestEnvironment) => {
      await seed(env, 't3', 'alice');
      const alice = env.authenticatedContext('alice').firestore();
      const tasks = collection(alice, COLLECTION);
      await assertFails(getDocs(query(tasks, limit(20))));
      const mine = query(tasks, where('ownerId', '==', 'alice'), limit(20));
      const ok = await assertSucceeds(getDocs(mine));
      expect(ok.docs.map((d) => (d.data() as { ownerId: string }).ownerId)).toEqual(['alice']);
    });
  });

  it('create는 규격을 강제한다 — 정상은 통과, 위반은 전부 거부', async () => {
    await withRulesTest(async (env: RulesTestEnvironment) => {
      const alice = env.authenticatedContext('alice').firestore();
      const good = (id: string) => ({
        id, title: '보고서 작성', status: 'open', ownerId: 'alice',
        createdAt: serverTimestamp(), updatedAt: serverTimestamp(),
      });
      await assertSucceeds(setDoc(doc(alice, COLLECTION, 'n1'), good('n1')));
      const rejected: Record<string, Record<string, unknown>> = {
        n2: { isAdmin: true },                      // hasOnly — 미지 필드
        n3: { status: 'archived' },                 // 리터럴 집합 밖
        n4: { title: '' },                          // 빈 제목
        n5: { ownerId: 'mallory' },                 // 남의 소유로 생성
        n6: { createdAt: Timestamp.fromMillis(0) }, // 클라이언트 시각
      };
      for (const [id, patch] of Object.entries(rejected)) {
        await assertFails(setDoc(doc(alice, COLLECTION, id), { ...good(id), ...patch }));
      }
      await assertFails(setDoc(doc(alice, COLLECTION, 'zz'), good('n7'))); // ID != id 필드
    });
  });

  it('삭제는 소유자만 — 남의 작업은 지워지지 않는다', async () => {
    await withRulesTest(async (env: RulesTestEnvironment) => {
      await seed(env, 'd1', 'alice');
      await seed(env, 'd2', 'alice');
      const alice = env.authenticatedContext('alice').firestore();
      const mallory = env.authenticatedContext('mallory').firestore();
      await assertFails(deleteDoc(doc(mallory, COLLECTION, 'd1')));
      await assertSucceeds(deleteDoc(doc(alice, COLLECTION, 'd2')));
    });
  });
});
```

**긍정과 부정을 같은 `it` 안에 짝으로, 행위자는 둘로 건다.** 거부 단언만 걸면 규칙을 통째로
`if false`로 바꿔도 초록이고, 소유자 한 명만 쓰면 규칙의 절반이 측정되지 않는다. 첫 `it`의
`LUMPED`처럼 **「X가 나오지 않는다」에는 양성 대조군을 먼저 건다** — 무엇을 잡는지 보이지
않으면 아무것도 못 잡는 정규식과 구분되지 않는다. 실측: 좁은 `/allow\s+write\s*:/`는 이 팩
자신이 쓰던 `allow read, write: if false`를 **놓쳤다.**

규칙에 결함을 심어 확인했다. **11건 중 10건이 빨개졌다** — `create`의 `validTask` ·
`isOwner(request.resource)` · `id == taskId` · `createdAt == request.time` 제거 · `allow delete`
행 삭제 · `delete` 완화 · `update`의 `isOwner(resource)` 제거 · `list`와 `get`의 소유권 제거 ·
넷을 `allow write`로 묶기(4건 빨강) · 포괄 거부를 `allow read, write:`로 되돌리기. **생존자는
`hasAll` 제거 하나**이고 그것은 §5가 잰 중복이다.

**두 번은 초록인데 이유가 틀렸다.** ① 탈취 시도가 `updatedAt`을 안 보내 *다른* 조건에 걸렸다.
② 필드 누락 벡터가 `hasAll`이 아니라 `updatedAt == request.time`에 걸렸다 — 그 벡터는 빼고
§5의 측정으로 대체했다. 부정 단언은 **의도한 조건 때문에** 거부되는지 확인해야 증거가 된다.

## 오용 목록 ① — Realtime Database 규칙 → Firestore 규칙 관용구 대조표

RTDB 습관이 그대로 오면 조용히 틀린다. 오른쪽은 실측, 왼쪽은 스택 지식이다. <!-- unverified: RTDB 쪽 관용구는 재현하지 않았다 -->

| 구 습관 (RTDB 규칙) | 현재 형태 (Firestore 규칙) |
| --- | --- |
| `.read` / `.write` 두 동사 | `get`·`list`·`create`·`update`·`delete` 다섯으로 나눈다 |
| 부모의 허용이 자식에 **상속된다** | 상속되지 않는다. 경로마다 `match`를 쓰거나 `{document=**}`로 명시 |
| `auth.uid` · `now` | `request.auth.uid` · `request.time` |
| `data` / `newData` | `resource.data` / `request.resource.data` |
| 쿼리에 규칙 개념이 없다 | `list`가 **쿼리 자체**를 평가한다. `where`가 없으면 거부다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| `resource` vs `request.resource` | 기존 vs 쓰기 후. `update`는 **둘 다**, `delete`는 `resource`만(다른 쪽은 null) |
| `get` vs `list` | 단건과 쿼리는 별개 동사다. `list`만 느슨하면 목록으로 남의 문서가 통째로 샌다 |
| `create` vs `update` | 생성은 `request.resource`만, 수정은 불변 필드(`id`·`createdAt`) 보존까지 |
| `hasOnly` vs `hasAll` | 앞은 미지 필드를 **혼자서** 막는다. 뒤는 각 필드를 따로 제약하는 조건이 있으면 중복이다(§5 실측) |
| 규칙 vs `firebase-admin` | 규칙은 클라이언트 SDK만 막는다. 함수 경로의 경계는 `where('ownerId', '==', ownerId)` |
| 인라인 규칙 문자열 vs 출하 파일 | 테스트에 규칙을 문자열로 박으면 **출하하는 파일을 검사하지 않는다.** `RULES`를 쓴다 |
| 규칙이 통과함 vs 쿼리가 돎 | 규칙을 통과해도 복합 인덱스가 없으면 실서비스에서 그 쿼리만 실패한다 |
