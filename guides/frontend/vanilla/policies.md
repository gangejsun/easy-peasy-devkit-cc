<!-- epcc-pack-policies: frontend/vanilla v3.14.0 -->

# vanilla 팩 — 파일 간 불변식 (L0 초안)

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

**`require` 정규식은 정의가 아니라 「강제 지점」을 겨눈다.** 파일 단위 퇴화(「팩 전체에 한 번이라도 있으면 통과」)는 이미 `file:`로 좁혀 막았는데, **같은 퇴화가 줄 단위에서 재발했다**(감사 C 실측): `safeReturnTo`라는 이름은 소유 파일에 13번 등장하고 그중 **강제 호출은 한 줄뿐**이라, 그 한 줄을 지워도 정의·테스트·산문이 정규식을 충족시켜 **FAIL 0**이 나왔다. 정규식이 「이름이 있는가」를 물으면 그 정책은 죽은 것이다 — **호출 형태**를 물어야 한다.

**정규식에 선택 그룹을 쓰지 않는다.** 넓은 쪽 하나로 충족돼 정작 검증하려던 좁은 경로를
전혀 측정하지 못한다. 정규식이 **통과시키면 안 되는 문자열**로도 확인한다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 반례 | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `env-single-entry` | forbid | guide | `import\.meta\.env` | `types-and-testing.md` | `const base = import.meta.env.VITE_API_BASE` | `import.meta.env['VITE_API_BASE']` | 환경 값은 `config` 한 곳에서만 읽는다. 다른 파일이 직접 읽으면 검증도 부팅 시점 실패도 우회된다. **Vite는 이 표현식을 빌드 시점에 문자열로 인라인하므로**, 비밀이 들어가면 번들에 박힌다 — 읽는 자리가 하나여야 그 검토가 한 곳에서 끝난다 |
| `no-inner-html` | forbid | guide | `\.innerHTML[[:space:]]*[+]?=` | — | `row.innerHTML = task.title` | `row.innerHTML += task.title` | **프레임워크의 자동 이스케이프가 없다.** 한 줄로 XSS가 되고, 이 축에는 그것을 막아 주는 층이 없다. `textContent`와 `<template>`이 기본이다 |
| `no-framework` | forbid | guide | `from ['\"](react\|vue\|svelte)` | — | `import { useState } from 'react'` | `import { useState } from "react"` | 이 축은 프레임워크가 없다. 하나라도 끌어오면 팩의 전제(정리 함수 계약 · DOM 직접 조작)가 무의미해지고 그 조합은 다른 축 팩이 소유한다 |
| `typecheck-on` | require | file:types-and-testing.md | `"checkJs"[[:space:]]*:[[:space:]]*true` | — | `"checkJs": true` | `"checkJs": false` | **JSDoc을 실제로 강제하는 유일한 장치다.** 꺼져 있으면 `@param`·`@returns`는 주장일 뿐 아무것도 검사하지 않는다. `allowJs`만으로는 파싱만 하고 타입 오류를 하나도 내지 않는다(실측) |
| `typecheck-strict` | require | file:types-and-testing.md | `"strict"[[:space:]]*:[[:space:]]*true` | — | `"strict": true` | `"strict": false` | `strict: false`면 같은 파일이 무오류가 된다(파일럿 대조 실행: `strict: true`에서 TS7006, false에서 0건). **앞 정책과 짝이다** — 켜기만 하고 느슨하면 검사가 도는 시늉만 한다 |
| `boundary-parse` | require | file:types-and-testing.md | `safeParse\(` | — | `const r = TaskSchema.safeParse(raw)` | `TaskSchema.parse(raw)` | **JSDoc은 런타임에 아무것도 하지 않는다.** 네트워크·`localStorage`·URL에서 온 값에 `@type`을 붙이는 것은 주장이지 검증이 아니다 |
| `store-unsubscribe` | require | file:state-management.md | `return\s+\(\)\s*=>` | — | `return () => listeners.delete(fn)` | `return (fn) => fn` | `subscribe`가 해지 함수를 반환하지 않으면 언마운트 훅이 없는 이 축에서 **구독이 영구히 남는다** |
| `delegate-not-per-row` | require | file:component-patterns.md | `=[[:space:]]*delegate\(` | — | `const off = delegate(root, 'click', '[data-task-id]', onRow)` | `export function delegate(root, type, selector, handler)` | 목록 항목마다 리스너를 달면 재렌더마다 리스너가 쌓이고 해지 대상이 N개가 된다. 뿌리 하나에 위임한다 |
| `abort-on-reload` | require | file:loading-error-states.md | `new AbortController\(` | — | `const ctl = new AbortController()` | `/** @type {AbortController} */` | 취소하지 않으면 **늦게 온 앞 응답이 뒤 응답을 덮어쓴다**. 라우트 전환이 잦은 SPA에서 이 부류가 재현이 어려운 결함이 된다 |
| `intercept-modifier-keys` | require | file:routing.md | `e\.metaKey` | — | `if (e.metaKey \|\| e.ctrlKey) return` | `const metaKeyLabel = "cmd"` | **가로채지 않을 것의 목록은 줄일 수 없다** — 수정자 키가 빠지면 「새 탭으로 열기」가 조용히 깨진다. C3가 변이 시험으로 확인했다: 이 검사만 지워도 나머지는 전부 초록이다. 목록 전체를 정규식으로 강제할 수는 없으므로 **가장 먼저 빠지는 한 항목**을 표식으로 삼는다 |
| `safe-return-to` | require | file:routing.md | `requireSession\([^,]+,[[:space:]]*safeReturnTo\(` | — | `requireSession(navigate, safeReturnTo(here))` | `export function safeReturnTo(raw)` | 이 저장소에서 **오픈 리다이렉트가 세 번 재발한 자리**다. 복귀 경로 검증 함수가 존재해야 `pack-smoke.sh`의 벡터 12건이 실제로 돌아간다 |
| `seam-parse-response` | require | seam | `=>[[:space:]]*parseTask\(` | — | `const tasks = raw.map((r) => parseTask(r))` | `export function parseTask(raw)` | 응답은 신뢰 입력이 아니다. 이음매가 파싱을 건너뛰면 스키마가 선언만 남고 **팩의 모든 `@type` 주장이 거짓**이 된다. 증명 예를 `raw.map(parseTask)`로 적었더니 게이트가 **죽은 정규식**으로 잡았다 — 함수 참조 전달은 `parseTask(`에 걸리지 않는다 |
| `seam-signal-passed` | require | seam | `\{[[:space:]]*signal[[:space:]]*\}` | — | `await fetch(url, { signal })` | `const signal = null` | `createResource`가 시그널을 주는데 이음매가 `fetch`에 넘기지 않으면 취소가 무효가 되고 경합이 되살아난다 |
| `vocab-task` | forbid | guide | `\bnotes?\b\|노트` | — | `const notes = []` | `노트를 만든다` | 어휘는 Task/작업 (L0 발행). 클러스터를 갈라 쓰면 어휘가 갈린다 — 실측에서 `task` 217회 ↔ `note` 166회로 벌어졌고 완전 예제가 서로 실행 불가였다 |

## 사람이 지킬 것 (기계가 판정할 수 없다)

- **`@returns`가 없는 함수는 `strict`에서도 조용히 샌다.** 반환이 `any`인 함수(`JSON.parse` 계열)를 감싸면서 주석을 빠뜨리면 그 `any`가 그대로 흐른다 — 「타입이 없다」가 아니라 **「검사되지 않는다」**다. 게이트는 이것을 볼 수 없다: JSDoc 블록의 모든 줄이 `*`로 시작해 `codelines()`가 통째로 버리므로 `@returns`를 정규식으로 세는 정책은 **정상 코드에서 0건이 된다**(파일럿이 픽스처로 실증했다)
- **해지 함수를 만든 쪽이 반환하고, 받은 쪽이 보관한다.** 반환은 기계가 볼 수 있지만
  **호출자가 그것을 버리는 것**은 볼 수 없다. 누수는 테스트에서 보이지 않는다
- **`@type`은 주장이고 `safeParse`는 검증이다.** 둘을 같은 것으로 쓰는 순간 이 축의
  타입 표준이 무너진다 — 경계가 어디인지(네트워크·저장소·URL) 사람이 판단한다
- **`el`의 `props`에 사용자 입력을 속성으로 싣지 않는다.** `href`·`src`에 들어가는 값은
  스킴을 검사해야 하고, `javascript:`는 `textContent`로 막히지 않는다
- **파생 값에 `set`을 만들지 않는다.** 파생을 쓸 수 있게 하면 진실이 두 곳에 생긴다
- **`interceptLinks`가 가로채지 않을 것의 목록은 줄일 수 없다.** 수정자 키 · 가운데 클릭 ·
  `target` · 외부 출처 · `download` 중 하나만 빠져도 「새 탭으로 열기」가 조용히 깨진다
