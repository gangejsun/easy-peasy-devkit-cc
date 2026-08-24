<!-- epcc-pack-policies: backend/firebase v3.14.0 -->

# firebase 팩 — 파일 간 불변식 (L0 초안)

이 팩이 **선언한 정책을 팩 자신과 이음매가 지키는지** 게이트가 대조한다.

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간 아님.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). **`대상` 값에 마크다운 강조를 쓰지 않는다.**
**정규식에 선택 그룹을 쓰지 않는다** — 성공 경로만으로 충족돼 실패 경로를 측정하지 못한다.

## 기계 검사 (게이트 `check_policies` · `check_pack_policies`)

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `no-console-log` | forbid | guide | `console\.log\(` | — | `console.log('created', id)` | 구조적 필드가 사라져 Cloud Logging에서 질의할 수 없다. `logger`를 쓴다 |
| `single-app-init` | forbid | guide | `initializeApp\(` | `data-access.md` | `initializeApp()` | 두 번 부르면 예외다. 클라이언트를 만드는 자리만 예외 |
| `owner-in-query` | require | guide | `where\(\s*'ownerId'\s*,\s*'=='` | — | `.where('ownerId', '==', ownerId)` | 문서 ID만으로는 남의 것도 읽힌다. **소유권은 쿼리에 있어야 한다** — admin SDK는 규칙을 우회하므로 이것이 함수 경로의 유일한 경계다 |
| `tx-for-check-then-write` | require | guide | `runTransaction\(` | — | `await db.runTransaction(async (tx) => {` | 존재+소유 확인과 쓰기를 나누면 그 사이에 소유자가 바뀔 수 있다 |
| `no-client-timestamp` | forbid | guide | `createdAt:\s*new Date\(` | — | `createdAt: new Date()` | 클라이언트·함수 인스턴스의 시각을 믿지 않는다. `FieldValue.serverTimestamp()`를 쓴다 |
| `rules-split-write` | forbid | guide | `allow write:` | — | `allow write: if isOwner(resource);` | `write` 하나로 묶으면 생성과 수정의 불변식이 달라 둘 중 하나가 반드시 헐거워진다. `create`·`update`·`delete`를 따로 쓴다 |
| `params-value-in-handler` | forbid | guide | `^const \w+ = \w+\.value\(\)` | — | `const key = apiKey.value()` | 모듈 최상위에서 `.value()`를 부르면 배포 분석 단계에서 터진다. 핸들러 안에서 부른다 |
| `vocab-task` | forbid | guide | `\bnote(s)?\b\|노트` | — | `const notes = []` | 어휘는 Task/작업 (L0 발행). 클러스터를 갈라 쓰면 어휘가 갈린다 |

## 사람이 지킬 것 (기계가 판정할 수 없다)

- **규칙과 쿼리는 함께 바뀐다.** Firestore는 규칙을 만족하지 못하는 쿼리를 **결과 0건이 아니라
  거부**로 답한다 — 규칙에 `ownerId` 조건이 있으면 쿼리에도 그 `where`가 있어야 한다
- **복합 인덱스는 쿼리의 함수다.** `where` + `orderBy` 조합을 바꾸면 `firestore.indexes.json`도
  바뀌고, 인덱스 없이 배포하면 그 쿼리만 런타임에 실패한다
- **`clientAccessPolicy`가 `functions-only`인데 규칙을 느슨하게 두지 않는다.** 함수만 쓸 계획이어도
  규칙은 잠가 둔다 — 나중에 누가 SDK를 붙이는 순간 문이 열려 있다
- **에뮬레이터 없이 규칙을 「읽어서」 검증하지 않는다.** 규칙 언어의 평가 순서와 `resource` /
  `request.resource` 구분은 읽기로 틀리기 쉬운 대표 자리다
