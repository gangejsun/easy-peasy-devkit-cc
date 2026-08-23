<!-- epcc-pack-policies: frontend/vue v3.12.0 -->

# vue 팩 — 파일 간 불변식

이 팩이 **선언한 정책을 이음매가 지키는지** 게이트가 대조한다. 정책을 선언한 곳과 그
정책을 강제하는 곳이 다르고 둘을 맞춰볼 의무가 없으면 정책은 문서로만 남는다 —
이 파일이 그 의무다.

## 기계 검사 (게이트 `check_policies`)

**검사 대상은 `codelines()`가 추출한 행뿐이다** — 코드펜스 안 · 주석 아님 · ❌/Bad 구간
아님. 산문과 안티패턴 예시를 세면 전부 위양성이 된다.

**Vue 특유의 주의**: `.vue` 펜스의 안티패턴은 `<!-- ❌ -->`로 표시해도 제외되지 않는다.
`codelines()`가 인정하는 주석 접두사는 `//` · `#` · `*` · `--`뿐이라 HTML 주석은 코드
행으로 세어진다. 그래서 이 팩의 SFC 안티패턴은 **펜스 바로 앞 산문 행에 ❌를 두어**
펜스 전체를 제외시킨다. 이 규약이 깨지면 아래 forbid 규칙들이 자기 자신의 나쁜 예를
잡는다 (선언 시점에 8건 전부 실측 확인).

| id | 판정 | 대상 | 정규식 | 예외 파일 | 설명 |
| --- | --- | --- | --- | --- | --- |
| `env-single-reader` | forbid | guide | `import\.meta\.env\.[A-Z_]+` | `types-and-testing.md` | 환경 값은 `src/config.ts` 한 곳에서만 읽는다. 다른 파일이 직접 읽으면 타입도 검증도 우회된다. **정규식이 실제 키 접근까지 요구하는 이유**: 맨 `import.meta.env`는 규칙을 설명하는 산문·주석에 등장해 위양성이 된다 |
| `http-in-api-layer` | forbid | pack | `\bfetch\(` | — | 원시 `fetch`는 이음매의 HTTP 클라이언트 모듈에만 둔다. 화면이 직접 부르면 인증 헤더·에러 정규화·베이스 URL이 갈라진다. **대상이 `pack`인 이유**: 이음매의 클라이언트 파일은 정당하게 `fetch(`를 쓴다 — `guide` 전체에 걸면 이음매를 잡는 위양성이 된다 |
| `no-secret-env-prefix` | forbid | guide | `VITE_[A-Z_]*(SECRET\|PASSWORD\|PRIVATE\|CREDENTIAL)` | — | `VITE_*`는 빌드 시점에 번들로 인라인된다. 접두사는 보호가 아니다 |
| `no-server-data-in-store` | forbid | guide | `state:[[:space:]]*\(\)[[:space:]]*=>[[:space:]]*\(\{[^}]*\b(tasks\|items\|rows)\b` | — | 서버 컬렉션을 Pinia state에 담으면 캐시가 둘이 된다. 서버 상태는 쿼리 캐시가 단독 소유한다. setup 스토어의 `ref<Task[]>([])`는 컴포넌트의 같은 표현과 정규식으로 구분되지 않아 기계 검사에 올리지 않았다 — 아래 사람 검사에 있다 |
| `no-scoped-style` | forbid | guide | `<style[^>]*(scoped\|module)` | — | Tailwind가 유일한 스타일 체계다. scoped CSS를 허용하면 같은 여백이 클래스에도 CSS에도 존재하게 되고 디자인 토큰 대조가 불가능해진다 |
| `no-dynamic-class-string` | forbid | guide | `:class=.{0,80}(\$\{\|['\"][a-z-]+['\"][[:space:]]*\+)` | — | Tailwind는 소스를 문자열로 훑는다. 조립한 클래스명은 빌드된 CSS에 없어 스타일이 조용히 사라진다. **템플릿 리터럴과 문자열 연결을 모두 본다** — 연결형(`'text-' + tone`)만 잡히지 않던 것을 감사가 실측으로 찾았다 |
| `no-options-api` | forbid | guide | `export default[[:space:]]+defineComponent` | — | 이 스택의 컴포넌트는 전부 `<script setup lang="ts">`다. 두 작성 방식이 섞이면 props 선언·반응성 규칙·테스트 접근법이 파일마다 달라진다. **`export default { setup() {} }` 형태는 여기서 잡지 않는다** — `export default {`로 넓히면 `tailwind.config.js`가 걸린다(실측 확인). 설정 파일과 컴포넌트를 줄 단위로 구분할 수 없어 사람 검사로 내렸다 |
| `no-v-html` | forbid | guide | `v-html` | — | Vue의 보간(`{{ }}`)은 자동 이스케이프하지만 `v-html`은 그 방어를 통째로 끈다. 신뢰할 수 없는 문자열이 한 번이라도 들어오면 XSS다 |
| `return-to-validated` | require | **seam** | `safeReturnTo` | — | 복귀 경로를 `router.replace`에 넘기기 전에 반드시 통과시킨다. **대상이 `seam`인 이유**: 이 함수는 팩이 정의하므로 `guide`로 걸면 팩이 배포되는 한 절대 실패하지 않는다 — 정작 검증해야 할 이음매의 로그인 화면은 검사되지 않는다 (감사 지적) |
| `three-states` | require | **seam** | `isPending` | — | 데이터 화면은 로딩·빈·에러 3상태를 모두 렌더링한다. 위와 같은 이유로 이음매를 겨눈다 |
| `storetorefs-required` | require | guide | `storeToRefs` | — | 스토어 상태를 꺼내는 정본 통로다. 이 이름이 조립본에서 사라졌다면 누군가 스토어를 그냥 구조 분해하는 예제로 바꿨다는 뜻이다 |
| `no-react-query` | forbid | guide | `@tanstack/react-query` | — | **이 축의 최대 위험**: React 팩을 형식 참조로 볼 때 가장 먼저 새어 들어오는 것이 이 import다. Vue는 `@tanstack/vue-query`를 쓴다. 산문 경고만 있고 기계 방어가 없던 자리다 |
| `no-fullpath-key` | forbid | guide | `:key="route\.fullPath"` | — | `fullPath`는 쿼리·해시를 포함하므로 필터 변경·앵커 이동마다 페이지가 재마운트되어 입력 중이던 폼이 날아간다. `route.path`를 쓴다 (감사가 실행으로 확인한 결함) |
| `no-hash-history` | forbid | guide | `createWebHashHistory` | — | 산문 금지(§routing)에 기계 방어를 붙인다 |
| `no-vue-shim` | forbid | guide | `declare module '\*\.vue'` | — | 도구에 따라 전 컴포넌트 타입을 `any`로 덮는다. 산문 금지에 기계 방어를 붙인다 |

`대상`이 `guide`면 조립된 가이드 전체(팩 + 이음매)에서 판정한다. `pack`이면 팩 파일만,
`seam`이면 이음매 파일만 본다. `require`는 조립 후 최소 1회 등장이면 충족이다.

## 사람이 지킬 것 (기계로 판정 불가)

- **`export default { setup() {} }` 형태도 쓰지 않는다.** `defineComponent`만 정규식으로
  잡히고 이 형태는 설정 파일의 `export default {`와 구분되지 않는다

정규식으로 판정하면 위양성이 위양성을 부르는 항목이다. 감사자에게 넘긴다.

- **Pinia 스토어를 그냥 구조 분해하지 않는다.** 상태·getter는 `storeToRefs`, 액션만
  직접 꺼낸다. 액션 구조 분해는 정당하므로 `const { x } = useXStore()` 자체를 금지할 수
  없다 — 꺼낸 이름이 상태인지 액션인지는 사람만 안다
- **props를 구조 분해하지 않는다.** `props.x`로 읽는다. Vue의 버전에 따라 컴파일러가
  구조 분해를 보정해 주기도 하는데, 보정 여부에 화면 갱신이 달리게 두지 않는다
- **setup 스토어에 서버 컬렉션을 담지 않는다.** `const tasks = ref<Task[]>([])`는
  컴포넌트에서는 정당하고 스토어에서는 결함이다 — 자리에 따라 판정이 갈린다
- **공통 컴포넌트는 `useRouter`·`useQuery`를 호출하지 않는다.** 호출하면 재사용이
  막힌다 — 필요한 것은 props와 슬롯으로 받는다
- **공통 컴포넌트가 소유하는 디자인 토큰(높이·타이포·여백)은 사용처에서 덮어쓰지 않는다.**
  Vue에서는 폴스루된 `class`가 `cn()`의 tailwind-merge를 거치지 않고 이어 붙기만 하므로,
  덮어쓰면 승자를 CSS 파일 순서가 정한다 — 덮어쓰기가 아예 성립하지 않는다
- **새 공통 컴포넌트를 만들기 전에 `src/components/common/`·`layout/`을 검색한다.**
  중복의 다수는 추출 실패가 아니라 탐색 실패다
- **`<Suspense>`와 top-level `await`를 화면 데이터 로딩에 쓰지 않는다.** 로딩 상태의
  소유자가 컴포넌트 밖으로 나가 3상태 규칙과 어긋난다
- **인가 UI는 신뢰 경계가 아니다.** 숨김은 UX이고 실제 판정은 서버다 — 숨겼다면 그에
  대응하는 실패 응답 처리도 함께 있어야 한다
