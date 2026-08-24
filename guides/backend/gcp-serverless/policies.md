<!-- epcc-pack-policies: backend/gcp-serverless v3.14.0 -->

# gcp-serverless 팩 — 파일 간 불변식 (L0 초안)

이 팩이 **선언한 정책을 팩 자신과 이음매가 지키는지** 게이트가 대조한다. 정책을 선언한 곳과
강제하는 곳이 다르고 둘을 맞춰볼 의무가 없으면 정책은 문서로만 남는다 — 이 파일이 그 의무다.

## 기계 검사 (게이트 `check_policies` · `check_pack_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간 아님.
산문과 안티패턴 예시를 세면 전부 위양성이 된다.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 게이트가 ① 예가 자기 정규식에 매치되는가
② `forbid`면 그 예가 대상 파일에 실재하지 않는가를 단언한다.

**`require`의 대상은 소유 파일까지 좁힌다.** `대상`은 `guide`·`seam` 말고 **`file:<파일명>`**을
받는다. `guide`로 두면 「팩 전체에 한 번이라도 있으면 통과」로 퇴화하고 **파일이 늘수록 더
무력해진다** — fastapi 실측에서 감사 C가 소유 파일의 검사를 통째로 지워도 형제 파일이 같은
문자열을 날라 정책이 통과하는 것을 실행으로 보였다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 scope로 인식되지 않아 정책이
조용히 전 파일을 겨눈다 — vue 팩에서 실제로 그랬다.

**정규식에 선택 그룹을 쓰지 않는다.** `verify(IdToken)?\(` 부류는 넓은 쪽 하나로 충족돼
정작 검증하려던 좁은 경로를 전혀 측정하지 못한다. 정규식이 **통과시키면 안 되는 문자열**로도
확인한다 — 그것이 통과하면 그 정책은 죽은 것이다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 설명 |
| --- | --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | guide | `process\.env` | `input-validation.md`, `testing-and-deploy.md` | `const projectId = process.env.GCP_PROJECT_ID` | 환경 값은 `settings` 한 곳에서만 읽는다. 다른 파일이 직접 읽으면 타입도 검증도 부팅 시점 실패도 우회된다. 예외는 **둘뿐**이다: 스키마를 정의하는 자리와 테스트가 에뮬레이터 호스트를 주입하는 자리 |
| `no-firebase-admin` | forbid | guide | `firebase-admin` | — | `import { getFirestore } from 'firebase-admin/firestore'` | 이 축은 `@google-cloud/firestore`로 붙는다. `firebase-admin`을 끌어오면 **`firebase` 축 팩과 코드가 겹치고**, 두 축의 보안 경계가 섞인다 — 그쪽은 규칙이 클라이언트를 막는 전제 위에 있고 이 축은 규칙이 전면 거부다 |
| `converter-required` | require | file:data-access.md | `withConverter\(` | — | `firestore.collection('tasks').withConverter(taskConverter)` | converter 없는 컬렉션 참조는 원시 문서를 준다 — 타입은 통과하는데 필드가 없거나 `Timestamp`가 아닌 값이 들어온다. 문서는 코드 밖에서 바뀌므로 **읽을 때 다시 파싱하는 자리**가 converter다 |
| `ownership-in-query` | require | file:data-access.md | `where\('ownerId'` | — | `tasksRef.where('ownerId', '==', ownerId)` | 이 축에는 **동작하는 정책 엔진이 없다**(규칙은 전면 거부이고 서버는 그것을 우회한다). 소유권은 쿼리에 있어야 하고, 읽은 뒤 자바스크립트에서 거르는 형태는 남의 문서를 이미 읽은 뒤다 |
| `mutation-in-transaction` | require | file:data-access.md | `runTransaction\(` | — | `await firestore.runTransaction(async (tx) => { … })` | 수정·삭제는 **읽고 소유권을 확인한 뒤 쓴다.** 확인과 쓰기를 나누면 그 사이에 바뀐 문서를 덮어쓰고, `delete()`는 없는 문서에도 성공하므로 확인 없이는 남의 것을 지우라는 요청도 성공으로 응답된다 |
| `strict-schema` | require | file:input-validation.md | `\.strict\(\)` | — | `const TaskQuery = z.object({ … }).strict()` | 미지 키를 허용하면 오타 난 필터가 조용히 무시된 목록을 정상 응답으로 준다. 쿼리·본문 양쪽에 건다 |
| `rules-deny-all` | forbid | guide | `allow read, write: if request\.auth` | — | `allow read, write: if request.auth != null;` | 이 축의 `firestore.rules`는 **전면 거부**다. 규칙에 인증 조건을 쓰면 「규칙이 지켜 준다」는 전제가 생기는데, 서버는 서비스 계정으로 붙어 규칙을 통째로 우회한다 — 그 전제는 거짓이고 애플리케이션 검사를 느슨하게 만든다 |
| `seam-no-direct-token-parse` | forbid | seam | `jwtVerify\(` | — | `const { payload } = await jwtVerify(token, jwks)` | 이음매가 토큰을 직접 검증하면 발급자·수신자 확인이 둘로 갈리고, 그 둘은 반드시 어긋난다. 이음매는 자격 증명을 꺼내는 일만 하고 검증은 `verifyIdToken`(팩 제공)에 넘긴다 |
| `seam-status-lookup` | forbid | seam | `ERROR_STATUS\[` | — | `const status = ERROR_STATUS[err.code]` | 첨자 접근은 코드표에 없는 코드에서 `undefined`를 내고, 그것이 상태 코드 자리에 들어가면 런타임 오류가 다시 500으로 접혀 원인이 사라진다. `ERROR_STATUS[code] ?? 500`을 쓴다 |
| `vocab-task` | forbid | guide | `\bnotes?\b\|노트` | — | `const notes = []` | 어휘는 Task/작업 (L0 발행). 클러스터를 갈라 쓰면 어휘가 갈린다 — 실측에서 `task` 217회 ↔ `note` 166회로 벌어졌고 완전 예제가 서로 실행 불가였다 |

## 사람이 지킬 것 (기계가 판정할 수 없다)

- **부재와 권한 없음을 같은 응답으로 낸다.** 남의 문서에 `403`을, 없는 문서에 `404`를 주면
  그 차이가 곧 존재 증명이다. 이 팩은 **둘 다 `NOT_FOUND`**로 접는다
- **`sub`가 주체다.** `email`은 사용자가 바꿀 수 있고 재사용될 수 있으므로 `ownerId`로 쓰지
  않는다. 토큰의 어느 클레임을 소유권 키로 삼는지는 되돌릴 수 없는 결정이다
- **`FAILED_PRECONDITION`(코드 9)을 4xx로 접지 않는다.** 대부분 인덱스 누락이고, 그것은
  사용자 입력 문제가 아니라 배포 누락이다 — 4xx로 접으면 원인이 로그에서 사라진다
- **모듈 최상위 인스턴스를 요청마다 만들지 않는다.** Cloud Run은 상주 프로세스이므로
  `firestore`와 `jwks`의 캐시가 실제로 산다. 핸들러 안에서 만들면 그 이득이 전부 사라지고
  gRPC 채널과 JWKS 왕복이 요청 수만큼 늘어난다
- **`shutdown(server)`는 시그널 핸들러 안에서 부른다.** 톱레벨에서 부르면 컨테이너가 부팅
  직후 종료된다. Cloud Run이 주는 시간은 SIGTERM 후 10초다
