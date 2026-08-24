<!-- epcc-pack: frontend/vanilla v3.14.0 verified 2026-08-24 vite@8 zod@4 vitest@4 happy-dom@20 typescript@7 -->

# vanilla 축 팩 — 허브 조각

조립 시 `SKILL.md`로 옮겨지는 조각들이다. 각 조각은 `<!-- pack-slot: 이름 -->` ~
`<!-- /pack-slot -->` 사이에 있고, 축 안에서 닫혀 조합이 바뀌어도 그대로 쓰인다.
파일 끝의 「이음매가 채울 것」 표에 있는 슬롯만 이음매가 새로 쓴다.

<!-- pack-slot: directory-structure -->
## Directory Structure

```
index.html                   # 단일 진입점. <template> 마크업이 여기 산다
vite.config.js               # Vite 설정 (test 키로 Vitest 환경까지 함께 선언한다)
jsconfig.json                # **checkJs: true** — JSDoc 주석을 타입으로 검사한다
src/
├── main.js                  # 부팅만 — config 로드 → 라우터 start() → 정리 함수 보관
├── config.js                # import.meta.env 를 zod 로 파싱하는 **유일한 파일**
├── schemas/
│   └── task.js              # TaskSchema · TaskStatus · parseTask (값은 소문자 'open'·'done')
├── store/
│   ├── create.js            # createStore · derive — @template 이 없으면 값이 전부 any 다
│   └── tasks.js             # tasksStore — items 와 byId 를 같은 set 안에서 바꾼다
├── dom/
│   ├── el.js                # el · fromTemplate — 문자열 자식은 textContent 로 넣는다
│   └── delegate.js          # delegate(root, type, selector, handler) → 해지 함수
├── components/
│   ├── task-list.js         # mountTaskList — **반환이 정리 함수다** (언마운트 훅이 없다)
│   └── task-list.css        # 이 컴포넌트가 소유하는 토큰은 여기 한 곳에서만 정의한다
├── router/
│   ├── index.js             # createRouter — 각 라우트 render 는 정리 함수를 반환한다
│   ├── links.js             # interceptLinks — 수정자 키·가운데 클릭·target 은 가로채지 않는다
│   └── return-to.js         # safeReturnTo — 보안 원시함수. 벡터 12건을 통과시킨다
├── state/
│   ├── resource.js          # createResource — fetcher 가 AbortSignal 을 받는 것이 계약이다
│   └── render.js            # renderState — 에러 뷰에 서버 메시지를 그대로 싣지 않는다
├── api/
│   └── tasks.js             # fetchTasks · createTask — **이음매가 소유한다**
├── auth/
│   └── session.js           # session · requireSession — **이음매가 소유한다**
└── styles/
    ├── tokens.css           # 전역 커스텀 프로퍼티 (@layer tokens)
    └── base.css             # 리셋과 요소 기본값 (@layer base)

test/
├── setup.js                 # happy-dom 환경 준비
├── schemas.test.js          # 스키마 단위 — 부분 수정 · 미지 키 · 빈 객체
├── return-to.test.js        # 복귀 경로 — **차단과 정상 통과를 같은 파일에서 단언한다**
└── task-list.test.js        # 컴포넌트 — 정리 함수가 실제로 해지하는지까지 단언한다
```

**프레임워크가 없으므로 정리(cleanup)가 계약이다.** 언마운트 훅이 없다 — 구독·리스너·
`AbortController`를 만든 함수는 **해지 함수를 반환해야 하고**, 호출자는 그것을 보관해야
한다. 반환하지 않는 함수는 누수를 만들고, 그 누수는 테스트에서 보이지 않는다.

**`src/api/`와 `src/auth/`는 이음매 소유다.** 팩은 그것들을 부르기만 한다. 조립 전에는
정의가 없는 것이 정상이고, 게이트가 `--assembly`와 함께 그 충족을 검사한다.

**타입은 주석에만 있다.** `jsconfig.json`의 `checkJs`가 켜져 있어야 그 주석이 검사된다 —
꺼져 있으면 `@param`·`@returns`는 **주장일 뿐 아무것도 강제하지 않는다.**
<!-- /pack-slot -->

> **아래 슬롯은 L2가 쓴다** (L0는 디렉토리 트리만 동결한다):
> `core-principles-axis` · `common-imports-axis` · `architecture-overview` ·
> `quick-start-axis` · `anti-patterns-axis`.

## 이음매가 채울 것

| 슬롯 | 무엇을 |
| --- | --- |
| `data-fetching` | 실제 API 호출 · 봉투 파싱 · 캐시. **응답을 `parseTask`로 파싱하고 `AbortSignal`을 `fetch`에 넘긴다** |
| `auth-and-session` | 토큰·세션 보관과 갱신 · 로그인/로그아웃 흐름 · 보호 라우트 판정. **복귀 경로는 `safeReturnTo`를 반드시 통과시킨다** |
| `complete-example` | 스키마 → 스토어 → 컴포넌트 → 라우트 → 테스트 관통 |
