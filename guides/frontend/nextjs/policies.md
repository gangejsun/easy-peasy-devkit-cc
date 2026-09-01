<!-- epcc-pack-policies: frontend/nextjs v3.12.0 -->

# nextjs 팩 — 파일 간 불변식

이 팩이 **선언한 정책을 이음매가 지키는지** 게이트가 대조한다. 실측에서 감사 지적의
최대 부류(57건 중 26건)가 "정책을 선언한 곳과 강제하는 곳이 다르고 둘을 맞춰볼 의무가
없다"였다 — 이 파일이 그 의무다.

## 기계 검사 (게이트 `check_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간
아님. 아래는 전부 **추출 시점에 사전 제작 이음매로 시험해 위반 0을 확인**했다.

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 반례 | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `no-inline-style` | forbid | guide | `style=\{[[:space:]]*\{` | — | `style={{ marginTop: 8 }}` | `style={ { marginTop: 8 } }` | 스타일은 Tailwind 유틸리티 + `cn()`. 인라인 `style`은 디자인 토큰 밖으로 새는 통로다 |
| `cn-for-classnames` | require | guide | `className=\{cn\(` | — | `className={cn('px-4 py-2', className)}` | `export function cn(...inputs: ClassValue[])` | 조건부 클래스는 문자열 접합이 아니라 `cn()`으로 병합한다 |
| `await-request-apis` | require | guide | `await (params\|searchParams\|cookies\(\))` | — | `const { id } = await params` | `const h = headers()` | Next 15에서 `params`·`searchParams`·`cookies()`는 Promise다. await 없이 쓰면 런타임에 조용히 undefined가 흐른다 |
| `no-data-client-in-pack` | forbid | pack | `create[A-Za-z]*Client\(` | — | `const db = createClient(url, key)` | `const db = createBrowserClient(url, key)` | **팩 자신을 검사한다.** 프론트엔드 축 팩은 데이터 클라이언트를 직접 만들지 않는다 — 만들면 그 순간 백엔드 축에 묶여 다른 조합에서 틀린 지침이 된다 (추출 시 4곳을 이 규칙으로 걷어냈다) |

`대상`: `guide`=조립된 가이드 전체 · `seam`=이음매 파일만 · `pack`=이 팩의 리소스만 ·
`file:<이름>`=그 파일만. `require`는 최소 1회 등장이면 충족이다.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 그 정규식이 실제로 잡는 문자열 하나를
적는다. 게이트가 두 가지를 단언한다: ① 예가 자기 정규식에 매치되는가 — 매치되지 않으면
아무것도 못 잡는 죽은 정규식이다 ② `forbid`면 그 예가 대상 파일에 실재하지 않는가 —
실재하면 팩이 자기 정책을 어긴 것이다. 실측(2026-08-23) vue 팩 저작에서 정책마다 결함
픽스처를 만들어 돌리는 일이 벽시계를 지배했고, 이 열이 그 왕복을 밀리초로 대체한다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 게이트가 scope로 인식하지
못해 정책이 조용히 전 파일을 겨눈다 — vue 팩에서 실제로 그랬고, "이음매를 겨눈다"는
감사 수리가 무효인 채로 출하됐다. 게이트가 이제 강조를 벗기지만 표에는 맨 값을 쓴다.

## 사람이 지킬 것 (기계로 판정 불가)

- **Server Component가 기본이고 `'use client'`는 상호작용 잎에만 붙인다.** 트리 위쪽에
  붙이면 하위 전체가 클라이언트 번들로 끌려 들어간다 — 어느 깊이가 "잎"인지는 정규식이
  판정할 수 없다
- **서버 데이터는 서버에서 가져와 props로 내린다.** 컴포넌트가 데이터 계층을 직접
  호출하지 않는다 (무엇을 직접 호출하면 안 되는가는 백엔드 축이 정한다)
- **반복 UI는 2회에서 검토하고 3회에서 반드시 추출한다.** 만들기 전에 공통 디렉토리를
  먼저 검색한다 — 중복의 다수는 추출 실패가 아니라 탐색 실패다
- **서버 컴포넌트에서 클라이언트 컴포넌트로 함수·클래스 인스턴스·데이터 클라이언트
  객체를 넘기지 않는다** (직렬화 경계)
- **상태는 계층으로 나눈다.** 서버 상태는 props, URL에 담을 것은 URL, 나머지 전역
  클라이언트 상태만 스토어
