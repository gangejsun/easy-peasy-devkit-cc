# 와이어 계약 — nextjs × supabase

<!-- epcc-wire-contract: nextjs+supabase v3.12.0 -->

사전 제작 이음매의 정본 계약이다. 이 조합은 이미 확정돼 있으므로 **실물 이음매에서
도출해 고정**했다. 게이트 `--pair --contract <이 파일>`이 양쪽을 이 문서로 대조한다.

## 0. 도메인 어휘 (신규 항목)

두 축 팩과 이음매가 **같은 리소스 이름**을 쓴다. 실측에서 사전 제작 두 쌍 모두 프론트가
`/tasks`를, 백엔드가 `/notes`를 써서 완전 예제가 서로 실행 불가였다 — 계약 양식의
구멍이었고 이 절이 그 수리다.

- 엔티티: `Task` · 컬렉션: `tasks` · 한국어 표기: 작업

이 조합의 프론트는 자기 REST 라우트를 fetch로 부르지 않는다 — Server Component가 데이터
계층을 직접 읽고 변이는 Server Action으로 간다. 그래서 경로(`/tasks`·`/api/tasks`)는
어휘 대조 대상이 아니라 백엔드 마운트 지점의 기록일 뿐이다.

## 0.5. 경계가 둘이다 (이 조합 고유)

Next.js는 서버 런타임을 내장하므로 클라이언트↔서버 경계가 **두 가지 형태**로 존재한다.
와이어 계약 5항목은 ①에만 적용되고, ②는 별도 계약이다. 한 가지만 고정하고 생성하면
폼 에러 흐름이 통째로 어긋난다.

경계 ①은 Route Handler ↔ fetch이고 아래 §1~§5의 HTTP 봉투를 쓴다. 경계 ②는 Server
Action ↔ useActionState이고 HTTP 상태 코드가 없다 — §6의 타입 계약을 쓴다.

**이 조합에서는 ②가 주(主)다.** 프론트의 서버 컴포넌트가 데이터 계층을 직접 읽으므로
①은 외부 소비자·웹훅을 위한 표면에 가깝다. 그래서 §1~§5는 `surface: backend`로 선언한다 —
양쪽에 요구하면 정상 조합이 영구 FAIL이 된다.

## 1. 성공 응답 봉투

> surface: backend

Route Handler 경계(①)의 계약이다. 프론트는 이 봉투를 소비하지 않는다 — §6의 액션 계약을 쓴다.

- 단건: `data` 하나만 담는다 — `{ data: Task }`
- 목록: `data` 배열 + `page` · `total`
- 삭제: 200, 본문 `{ data: null }`

## 2. 에러 응답 봉투

> surface: backend

위와 같다.

`error` 안에 `code`·`message`·`details`(선택). 코드는 **소문자 snake_case**다
(`validation_error`) — SCREAMING_SNAKE이 아니다.

## 3. 페이지네이션 모델

> surface: backend

위와 같다. 프론트의 목록 화면은 서버 컴포넌트가 직접 조회한다.

- 모델: **offset 하나만**
- 요청 파라미터: `page`, `limit`
- 응답 필드: `page` · `total` (Supabase `range()`로 구현)

totalPages는 와이어 필드가 아니다 — 프론트가 total과 페이지 크기로 파생시킨다.

커서 계열 필드(nextCursor)는 이 계약에 없다.

## 4. 에러 코드 ↔ 상태 매핑

> surface: backend

HTTP 상태는 Route Handler 경계에만 있다. 액션 경계에는 상태 코드가 없다.

| code | status | 언제 |
| --- | --- | --- |
| `validation_error` | 400 | Zod 실패, FK/CHECK 위반 |
| `invalid_json` | 400 | 본문 파싱 불가 |
| `unauthenticated` | 401 | `getUser()`가 null |
| `forbidden` | 403 | 로그인했으나 불허 (RLS `42501`) |
| `not_found` | 404 | 부재 **또는** RLS가 가림 (`PGRST116`) — 존재 누설 금지 |
| `conflict` | 409 | unique 충돌 (`23505`) |
| `rate_limited` | 429 | 외부 저장소 기반 제한 (인메모리 금지) |
| `internal_error` | 500 | 예상 못 한 예외 — 내부 메시지 노출 금지 |

## 5. 인가 실패의 표면

> surface: backend

HTTP 응답 형태의 계약이다. 프론트 쪽 인증 흐름(미들웨어 세션 갱신·보호 라우트)은
상태 코드가 아니라 리다이렉트로 나타나므로 여기 토큰을 요구하지 않는다.

- 미인증: 401 `unauthenticated`
- 인가 실패: **404 `not_found`** — RLS가 가린 행은 `PGRST116`으로 오며 이를 403으로
  구분하면 존재가 누설된다. 403은 역할 부족(`42501`)에만 쓴다
- 인증 만료 후 복귀: 미들웨어가 세션을 갱신하고, 실패하면 복귀 경로를 보존한 채
  로그인으로 리다이렉트한다. 복귀 경로는 `safeInternalPath`를 통과한 값만 쓴다
- **응답 형식을 경로에 맞춘다**: `/api/*`는 위 에러 봉투를, 페이지 경로는 리다이렉트를 반환

## 6. Server Action 계약 (경계 ②)

> surface: frontend

액션은 프론트가 정의하고 프론트가 소비한다. 백엔드 가이드에는 이 타입이 없다.

```ts
export interface ActionState {
  error?: string                       // 사용자에게 보일 단문
  fieldErrors?: Record<string, string[]>
  values?: Record<string, string>      // 실패 시 폼 재채움
}
```

- 도메인 에러를 경계 밖으로 `throw`하지 않는다 — 타입으로 돌려준다
- 성공은 `redirect()` 또는 `revalidatePath()` 후 빈 상태 반환
- `useActionState`의 이전 상태가 첫 인자로 온다 (`_prev`)
