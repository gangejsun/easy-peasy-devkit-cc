<!-- epcc-pack: backend/gcp-serverless v3.14.0 -->
# 문서 설계 — 소유권은 필드에 있고, 쿼리 형태는 인덱스가 정한다

이 파일이 소유하는 것은 **문서에 무엇을 담고 어디에 두는가**와, 그 결정이 강제하는 **선언물
둘**이다 — `firestore.indexes.json` · `firestore.rules`. 읽고 쓰는 코드는 `data-access.md`가
소유하고(`src/firestore/`), 스키마 타입(`Task`·`TaskCreate`)은 `input-validation.md`가
소유한다(`src/schemas/task.ts`). **이 파일은 새 export를 만들지 않는다** — 설계 규율이다.

**이 축에는 정책 엔진이 없다.** 아래 3절이 그것을 실행으로 보인다: 같은 문서를 같은 규칙
아래에서 두 경로로 읽었을 때 하나는 거부됐고 **서버 자격 증명 경로는 통과했다.** 소유권을
지키는 것은 문서 설계와 애플리케이션 코드뿐이다.

## 1. 배치 결정 — 루트 컬렉션인가 서브컬렉션인가

방법보다 이 선택이 먼저다. **바꾸려면 데이터를 옮겨야 하므로 되돌릴 수 없다.**

| 문서가 … | 배치 | 왜 |
| --- | --- | --- |
| 한 사용자에게 속하고 **관리·집계·이관이 언젠가 필요하다** | **루트 `tasks/{taskId}` + `ownerId` 필드** ← 이 팩이 고른 것 | 소유권이 쿼리에 드러나 기계가 검사할 수 있다(정책 `ownership-in-query`). 경로에 숨으면 검사할 문자열이 없다 |
| 한 사용자에게 속하고 **사용자 경계를 넘어 묶어 볼 일이 영원히 없다** | 서브컬렉션 `users/{uid}/tasks/{taskId}` | 경로가 곧 소유자다. 단, 넘어 보는 순간 `collectionGroup` 쿼리가 필요하고 **그 쿼리에는 소유자 경계가 없다** |
| 여러 주체가 공유한다 | 루트 + `memberIds: string[]` (`array-contains`로 필터) | 소유자 하나로 표현되지 않는다 |
| 부모 없이 존재할 수 없다 | 서브컬렉션 | 단 **부모 문서를 지워도 서브컬렉션은 남는다** — 삭제는 자동이 아니다 |

마지막 줄이 서브컬렉션의 함정이다. `users/{uid}` 문서를 지워도 그 아래 `tasks/*`는 그대로
살아 있고 `users/{uid}`는 **없는 부모**가 된다. 지우려면 하위를 열거해 지워야 한다.

**서브컬렉션이 소유권을 지켜 주는 것처럼 보이는 것이 이 축에서 가장 비싼 착각이다.** 경로에
`uid`가 박혀 있어도 그 `uid`를 넣는 것은 애플리케이션 코드이고, 잘못된 값을 넣으면 경로가
그대로 남의 자리를 가리킨다. 규칙이 그것을 막아 주지 않는다(3절).

## 2. 문서 형태 — 무엇을 저장하고 무엇을 저장하지 않는가

`tasks/8kQ2vN…` 문서 하나는 이렇게 생겼다. 문서 ID가 곧 `Task.id`이므로 **`id`는 데이터에
없다.**

```json
{
  "ownerId": "PLd3aX8mQ2bK7…",
  "title": "청구서 보내기",
  "status": "open",
  "createdAt": "<Timestamp 1700000000.000000000>"
}
```

| 필드 | 저장 타입 | 저장하는가 | 왜 |
| --- | --- | --- | --- |
| `id` | — | **하지 않는다** | 문서 ID다. 필드로도 두면 두 값이 갈리고, 갈린 뒤에는 어느 쪽이 진짜인지 알 수 없다 |
| `ownerId` | `string` | **한다** | 쿼리 필터가 읽는 **유일한 자리**다. 문서 ID에 인코딩하면(`{uid}_{rand}`) 쿼리가 그것을 읽지 못한다 |
| `title` | `string` | 한다 | 길이 상한은 스키마가 건다(`input-validation.md`) — 6절 참조 |
| `status` | `string` | 한다 | 저장되는 것은 **소문자 값** `'open'`·`'done'`이다 |
| `createdAt` | `Timestamp` | 한다 | 정렬·범위 필터의 키다. ISO 문자열로 두면 비교가 문자열 비교가 되고 시간대가 섞이는 순간 정렬이 무너진다 |

위 예시의 `createdAt` 자리는 **문자열이 아니라 `Timestamp` 값**이다 — 콘솔 표시를 흉내 낸 것이다.

<!-- unverified: 에뮬레이터는 샤딩을 흉내 내지 않아 핫스팟 자체는 관측하지 못했다. 자동 ID 권고는 Firestore 문서의 설계 지침이다 -->
**문서 ID는 자동 생성 ID를 쓴다**(`tasksRef.doc()`). 사람이 읽는 순차 ID(`task-1`·`task-2`)나
타임스탬프 접두 ID는 키 공간의 한 구간에 쓰기를 몰아 넣는다 — Firestore는 키 범위로 샤딩하므로
**단조 증가하는 ID는 항상 같은 샤드를 때린다.**

`ownerId`에 넣는 값은 검증된 ID 토큰의 `sub`다(`identity-tokens.md`). 요청 본문의 사용자
식별자는 자격 증명이 아니라 입력이다.

## 3. `firestore.rules`는 전면 거부다 — 그리고 그것이 정직한 상태다

<!-- file: firestore.rules -->
```
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {
    // 이 축에서 Firestore에 붙는 것은 Cloud Run이 서비스 계정(ADC)으로 하는 서버 접근뿐이고,
    // 서버 접근은 규칙을 통째로 우회한다. 클라이언트 SDK가 직접 붙는 경로는 존재하지 않는다.
    // 규칙에 조건을 쓰면 「규칙이 지켜 준다」는 거짓 전제만 생긴다.
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

이 파일을 **배포 산출물에 포함한다.** 없으면 새 데이터베이스의 기본값이 적용되고, 그 기본값이
무엇인지는 프로젝트 생성 시점에 고른 모드에 달려 있다 — 통제 밖의 값을 경계로 두게 된다.

**규칙이 살아 있고, 서버는 그것을 통과한다.** 위 규칙을 로드한 Firestore 에뮬레이터에서
같은 문서를 두 경로로 읽었다.

<!-- verified: firestore-emulator 1.19.8에 **위 파일 그대로**를 로드하고 tasks/ix1을 두 경로로 조회 — 응답 코드와 본문을 직접 계측 -->

| 경로 | 응답 |
| --- | --- |
| 규칙을 거치는 클라이언트 경로 (자격 증명 없음) | **403** `PERMISSION_DENIED` — `false for 'get' @ L9` |
| 서버 자격 증명 경로 (이 팩이 쓰는 경로) | **200** — 같은 문서를 그대로 받았다 |

<!-- verified: 같은 에뮬레이터 세션에서 @google-cloud/firestore 9.0.0으로 수행한 이 팩의 모든 쓰기·읽기·트랜잭션이 성공 -->
그리고 같은 규칙 아래에서 `@google-cloud/firestore` 9의 생성·수정·삭제·트랜잭션이 **전부
성공했다.** 403은 규칙이 죽어 있어서가 아니라는 양성 대조군이고, 200은 그 규칙이 이 팩의
코드에 아무 영향도 주지 않는다는 관측이다.

**그래서 「이중 방어」라고 쓸 자리가 없다.** 소유권 검사를 빠뜨린 쿼리는 뒤에서 막히지 않고
그대로 남의 문서를 준다.

## 4. 복합 인덱스 선언 (`firestore.indexes.json`)

**쿼리 형태가 인덱스를 정한다.** `data-access.md`의 `listTasks`가 만드는 형태는 둘이고, 그
둘이 그대로 이 파일의 두 항목이다.

| 쿼리 | 필요한 인덱스 |
| --- | --- |
| `where ownerId` + `orderBy createdAt desc` + `orderBy __name__ desc` | `ownerId` ASC → `createdAt` DESC → `__name__` DESC |
| 위 + `where status` | `ownerId` ASC → `status` ASC → `createdAt` DESC → `__name__` DESC |

**등호 필터가 먼저, 정렬 키가 나중이다.** 순서를 바꾸면 그 인덱스는 이 쿼리를 만족시키지 않는다.

<!-- file: firestore.indexes.json -->
```json
{
  "indexes": [
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" },
        { "fieldPath": "__name__", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "tasks",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "createdAt", "order": "DESCENDING" },
        { "fieldPath": "__name__", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

<!-- verified: firebase-tools 14의 FirestoreApi.validateSpec에 위 파일을 태워 VALID. 양성 대조군으로 order를 "SIDEWAYS"로 바꾼 파일은 「Field "order" must be one of ASCENDING, DESCENDING」으로 거부됐다 -->
이 파일은 firebase-tools의 인덱스 스펙 검증기를 통과한다 — 검증기가 아무거나 받는 것이
아님은 잘못된 파일이 거부되는 것으로 확인했다.

**`__name__` 행을 빠뜨리지 않는다.** 마지막 정렬 키가 `desc`이므로 문서 ID 정렬도 `DESCENDING`
이어야 한다. 생략하면 기본값 `ASCENDING`이 되고, 그 인덱스는 `orderBy('__name__', 'desc')`를
만족시키지 않는다 — 즉 커서 페이지네이션이 쓰는 바로 그 형태가 인덱스를 못 찾는다.

## 5. 인덱스 누락은 에뮬레이터를 통과한다 — 그래서 배포에서 처음 죽는다

<!-- verified: firestore-emulator 1.19.8에 firestore.indexes.json을 비운 채 4절 둘째 형태의 쿼리를 태워 정상 응답을 받았다 -->
실측: `indexes` 배열을 **비운 상태로** `where ownerId` + `where status` + `orderBy createdAt` +
`orderBy __name__` 쿼리를 태웠고, 에뮬레이터는 그대로 결과를 돌려줬다. **테스트가 초록인 것이
인덱스가 있다는 뜻이 아니다.**

<!-- unverified: 실 GCP 프로젝트가 없어 프로덕션이 이 쿼리를 실제로 거부하는 것은 관측하지 못했다. gRPC 9의 도메인 처리는 error-handling.md가 소유한다 -->
프로덕션에서 인덱스 없는 복합 쿼리는 **gRPC 9 `FAILED_PRECONDITION`**으로 실패한다. 이 팩은
그것을 **500으로 접는다** — 사용자 입력 문제가 아니라 배포 누락이고, 4xx로 접으면 원인이
로그에서 사라지기 때문이다(`error-handling.md`).

**새 필터·정렬 조합을 만들면 같은 커밋에서 이 파일을 고친다.** 나중으로 미룬 인덱스는
「테스트는 통과했는데 배포하면 죽는」 유일한 부류이고, 그 사이 창을 잡아 주는 장치가 없다.

## 6. 문서 크기와 쓰기 경합

문서 하나는 **1 MiB보다 작아야 하고**, 실제 상한은 그보다 조금 낮다.

<!-- verified: firestore-emulator 1.19.8에 1000 KiB 필드는 성공, 1100 KiB 필드는 gRPC 3 INVALID_ARGUMENT로 거부되는 것을 관측 -->

| 쓴 것 | 결과 |
| --- | --- |
| 1000 KiB 문자열 필드 | 성공 |
| 1100 KiB 문자열 필드 | **gRPC 3** `INVALID_ARGUMENT` — `longer than 1048487 bytes` |

**gRPC 3은 이 팩의 판별 함수(5·6·9·10)에 없다** — 그래서 `INTERNAL`(500)로 접힌다. 문서를
작게 유지해 이 코드를 만나지 않는 것이 유일한 대응이다: `title`의 길이 상한을 스키마에서
걸고(`input-validation.md`), 첨부·본문 같은 커지는 것은 문서가 아니라 Cloud Storage에 두고
문서에는 참조만 남긴다.

**배열을 무한히 키우지 않는다.** 문서 안 배열은 한 번의 쓰기가 문서 전체를 다시 쓰므로,
항목이 늘수록 쓰기 비용과 경합이 함께 커진다. 항목이 늘어나는 것은 서브컬렉션으로 뺀다.

**한 문서에 쓰기를 몰지 않는다.** 같은 문서를 읽고 쓰는 트랜잭션은 서로 **직렬화된다.**

<!-- verified: firestore-emulator 1.19.8에서 같은 방식의 트랜잭션 20개를 한 문서와 20개 문서에 각각 동시 실행하고 벽시계를 계측 -->

| 무엇을 | 걸린 시간 | 최종값 |
| --- | --- | --- |
| 문서 **하나**에 트랜잭션 20개 | **7749 ms** | 20 (정확하다) |
| 문서 **20개**에 하나씩 (대조군) | **32 ms** | — |

**결과는 맞고 처리량만 무너진다** — 그래서 부하가 오르기 전까지 아무도 눈치채지 못한다.
「작업 개수」 같은 요약 값을 사용자 문서 한 곳에 모으면 그 문서가 계정 전체의 직렬화 지점이
된다. 개수가 필요하면 요약 문서를 소유자별로 쪼개거나, 집계 쿼리로 읽는다.

## 오용 목록 ① — 다른 축의 관용구 → 이 축의 형태

| 구 습관 | 현재 형태 (이 축) |
| --- | --- |
| 규칙에 `request.auth` 조건을 걸어 소유권을 지킨다 | 규칙은 `if false`. 서버가 규칙을 우회한다 — 3절의 측정이 그것이다 |
| `firebase-admin`으로 붙고 규칙을 「관리자 우회」로 이해한다 | 이 축은 `@google-cloud/firestore`로 붙는다. 우회가 예외가 아니라 **유일한 경로**다 |
| RDB 습관: 소유자 컬럼 없이 조인으로 소유권을 판정한다 | 조인이 없다. `ownerId`가 **문서 필드**로 있어야 쿼리가 그것을 읽는다 |
| 인덱스는 느려질 때 추가한다 | 인덱스 없는 복합 쿼리는 느린 것이 아니라 **실패한다**(gRPC 9) |
| `createdAt`을 ISO 문자열로 저장한다 | `Timestamp`. 문자열은 시간대가 섞이는 순간 정렬이 무너진다 |
| 부모 문서를 지우면 하위도 지워진다고 가정한다 | 서브컬렉션은 남는다 — 하위를 열거해 지워야 한다 |

## 오용 목록 ② — 혼동 쌍

| 자주 잘못 고르는 것 | 정확한 적용 조건 |
| --- | --- |
| 루트 컬렉션 + `ownerId` vs 서브컬렉션 | 소유권을 **기계가 검사할 수 있어야 하면** 루트다. 경로에 숨으면 검사할 문자열이 없다 |
| `__name__` 정렬 키 vs 생략 | 정렬 키가 유일하지 않으면(같은 `createdAt`) 필수다. 이 팩은 항상 붙인다 |
| 인덱스 `ASCENDING` vs 쿼리 `desc` | 인덱스의 방향은 쿼리의 `orderBy` 방향과 **글자 그대로** 맞아야 한다 |
| 등호 필터 순서 vs 정렬 키 순서 | 인덱스 필드는 **등호 필터 먼저, 정렬 키 나중**이다 |
| 에뮬레이터 초록 vs 인덱스 존재 | 에뮬레이터는 인덱스를 요구하지 않는다(5절) — 초록은 증거가 아니다 |
| 문서 안 배열 vs 서브컬렉션 | 항목이 **늘어나면** 서브컬렉션. 배열은 쓸 때마다 문서 전체를 다시 쓴다 |
