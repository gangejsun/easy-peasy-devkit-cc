<!-- epcc-pack-policies: frontend/react-vite v3.12.0 -->

# react-vite 팩 — 파일 간 불변식

이 팩이 **선언한 정책을 이음매가 지키는지** 게이트가 대조한다. 실측에서 감사 지적의
최대 부류(57건 중 26건)가 "정책을 선언한 곳과 그 정책을 강제하는 곳이 다르고 둘을
맞춰볼 의무가 없다"였다. 심볼에는 원장이 있었으나 정책에는 대응 장치가 없었다 —
이 파일이 그 장치다.

## 기계 검사 (게이트 `check_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간
아님. 산문과 안티패턴 예시를 세면 전부 위양성이 된다 (추출 시점에 5건 확인).

| id | 판정 | 대상 | 정규식 | 예외 파일 | 증명 예 | 반례 | 설명 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `env-single-reader` | forbid | guide | `import\.meta\.env[.\[]` | `types-and-testing.md` | `import.meta.env.VITE_FEATURE_FLAGS` | `import.meta.env['VITE_API_BASE']` | 환경 값은 `src/config.ts` 한 곳에서만 읽는다. 다른 파일이 직접 읽으면 타입도 검증도 우회된다. **정규식이 실제 키 접근(`.VITE_X`)까지 요구하는 이유**: 맨 `import.meta.env`는 규칙을 설명하는 산문·주석에 등장해 위양성이 된다 (게이트 최초 실행에서 2건 확인) |
| `http-only-in-api-layer` | forbid | guide | `\bfetch\(` | `data-fetching.md` | `const res = await fetch('/api/tasks')` | `const res = await window.fetch(url)` | 원시 `fetch`는 HTTP 클라이언트 모듈에만. 화면이 직접 부르면 인증 헤더·에러 정규화·베이스 URL이 갈라진다 |
| `no-secret-env-prefix` | forbid | guide | `VITE_[A-Z_]*(SECRET\|PASSWORD\|PRIVATE\|CREDENTIAL)` | — | `VITE_SESSION_SECRET` | `VITE_STRIPE_PRIVATE_KEY` | `VITE_*`는 빌드 시점에 번들로 인라인된다. 접두사는 보호가 아니다 |
| `no-server-data-in-store` | forbid | guide | `set\(\{[^}]*\b(tasks\|items\|rows)\b` | — | `set({ tasks: data })` | `set({ list: rows })` | 서버 응답을 Zustand에 복제하면 캐시가 둘이 된다. 서버 상태는 쿼리 캐시가 단독 소유 |
| `return-to-validated` | require | guide | `navigate\(safeReturnTo\(` | — | `navigate(safeReturnTo(params.get('returnTo')))` | `export function safeReturnTo(raw: unknown)` | 복귀 경로를 `navigate`에 넘기기 전에 반드시 통과시킨다. `//host`·`/\host`는 prefix 검사로 막히지 않는다 |
| `three-states` | require | guide | `if \(isPending` | — | `if (isPending) return <ListSkeleton />` | `const { data, isPending } = useQuery(opts)` | 데이터 화면은 로딩·빈·에러 3상태를 모두 렌더링한다 |

`대상`이 `guide`면 조립된 가이드 전체(팩 + 이음매)에서 판정한다. `seam`이면 이음매
파일만 본다. `require`는 조립 후 최소 1회 등장이면 충족이다.

**`증명 예` 열은 의무다** (없으면 게이트 FAIL). 그 정규식이 실제로 잡는 문자열 하나를
적는다. 게이트가 두 가지를 단언한다: ① 예가 자기 정규식에 매치되는가 — 매치되지 않으면
아무것도 못 잡는 죽은 정규식이다 ② `forbid`면 그 예가 대상 파일에 실재하지 않는가 —
실재하면 팩이 자기 정책을 어긴 것이다. 실측(2026-08-23) vue 팩 저작에서 정책마다 결함
픽스처를 만들어 돌리는 일이 벽시계를 지배했고, 이 열이 그 왕복을 밀리초로 대체한다.

**`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 게이트가 scope로 인식하지
못해 정책이 조용히 전 파일을 겨눈다 — vue 팩에서 실제로 그랬고, "이음매를 겨눈다"는
감사 수리가 무효인 채로 출하됐다. 게이트가 이제 강조를 벗기지만 표에는 맨 값을 쓴다.

## 사람이 지킬 것 (기계로 판정 불가)

정규식으로 판정하면 위양성이 위양성을 부르는 항목이다. 감사자에게 넘긴다.

- **공통 컴포넌트는 `useNavigate`·`useQuery`를 호출하지 않는다.** 호출하면 재사용이
  막힌다 — 필요한 것은 props로 받는다
- **공통 컴포넌트가 소유하는 디자인 토큰(높이·타이포·여백)은 사용처에서 덮어쓰지 않는다.**
  덮어쓰면 공통 컴포넌트가 껍데기가 된다
- **새 공통 컴포넌트를 만들기 전에 `src/components/common/`·`layout/`을 검색한다.**
  중복의 다수는 추출 실패가 아니라 탐색 실패다
- **인가 UI는 신뢰 경계가 아니다.** 숨김은 UX이고 실제 판정은 서버다 — 숨겼다면 그에
  대응하는 실패 응답 처리도 함께 있어야 한다
