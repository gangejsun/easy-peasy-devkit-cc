# 와이어 계약 — vue × node-api

<!-- epcc-wire-contract: vue+node-api v3.13.0 -->

이 조합의 정본 계약이다. 게이트 `--pair --contract <이 파일>`이 양쪽을 이 문서로 대조한다.

> 계약 값은 **목록 항목과 표 행에만** 쓴다. 산문과 인용문의 백틱은 설명으로 취급된다 —
> 부정문이나 한쪽 전용 헬퍼 이름은 산문에 쓴다.

## 0. 도메인 어휘

두 축 팩의 `pack.json`이 이미 같은 값을 고정하고 있다(`vue`와 `node-api` 모두
`entity: Task` · `collection: tasks`). 그대로 옮긴다.

- 엔티티: `Task` · 컬렉션: `tasks` · 한국어 표기: 작업
- 프론트 호출 경로: `/api/tasks` · 백엔드 마운트 경로: `/api/tasks`

이 조합은 **경계가 하나뿐이다.** Vue는 SPA이고 node-api는 별도 서버이므로 브라우저의
`fetch`와 Express 라우터 사이에 HTTP 경계 하나만 있다 — `nextjs × supabase`처럼
서버 컴포넌트·Server Action이라는 두 번째 경계가 없다. 그래서 아래 전 절이 양쪽에
적용된다(`surface:` 선언이 없다).

## 1. 성공 응답 봉투

- 단건: `data` 하나만 담는다 — `{ data: Task }`
- 목록: `data` 배열 + `nextCursor`
- 생성: 201, `data`에 생성된 행
- 삭제: 204, 본문 없음

## 2. 에러 응답 봉투

- `error` 안에 `code` · `message` · `details`(선택)
- 최상위에 `requestId`

`details`는 필드별 오류이고 형태는 `Record<string, string[]>`다. 검증 실패에서만 실린다.

## 3. 페이지네이션 모델

- 모델: cursor
- 요청 파라미터: `limit` · `cursor`
- 응답 필드: `nextCursor` (마지막 페이지에서 null)

오프셋(`page`·`skip`)은 쓰지 않는다 — 목록이 자주 바뀌면 페이지 경계에서 행이 중복되거나
누락된다. 백엔드 팩이 `take: limit + 1`로 다음 페이지 유무를 판단한다.

## 4. 에러 코드 ↔ 상태 매핑

프론트가 `code`로 화면을 분기하므로 이 표가 양쪽에 그대로 있어야 한다.

| code | status | 언제 |
| --- | --- | --- |
| `VALIDATION_FAILED` | 400 | 요청 본문·쿼리가 스키마에 맞지 않다. `details`가 실린다 |
| `UNAUTHENTICATED` | 401 | 토큰이 없거나 검증에 실패했다 |
| `FORBIDDEN` | 403 | 인증은 됐으나 역할이 부족하다. **소유권 실패에는 쓰지 않는다** |
| `NOT_FOUND` | 404 | 행이 없거나 남의 행이다 — 둘을 구분하지 않는다 |
| `CONFLICT` | 409 | 고유 제약 충돌 |
| `PAYLOAD_TOO_LARGE` | 413 | 본문이 파서 한도를 넘었다 |
| `INTERNAL` | 500 | 그 밖의 전부. 원인을 응답에 싣지 않는다 |

`NETWORK_ERROR` · `TIMEOUT` · `BAD_SHAPE`는 클라이언트가 스스로 만드는 코드다 —
서버가 보내지 않으므로 프론트 가이드에만 둔다.

## 5. 인가 실패의 표면

- 미인증: 401 `UNAUTHENTICATED`
- 인가 실패(소유권): 404 `NOT_FOUND` — **존재를 누설하지 않는다**
- 인가 실패(역할): 403 `FORBIDDEN`
- 인증 만료 후 복귀: 401을 받으면 프론트가 1회 재발급을 시도하고, 재실패면 로그인으로 보낸다

소유권 실패를 404로 내는 이유는 백엔드 축의 전제 때문이다 — 데이터 계층 정책 엔진이
없어 애플리케이션 층이 유일한 경계이고, 403과 404를 구분하면 미인가 사용자가 리소스
존재를 열거할 수 있다. 프론트는 404를 「없거나 내 것이 아니다」로 한 화면에 처리한다.

## 6. 인증 표면

이 조합은 SPA(별도 오리진) + 자체 서버라 인증이 HTTP 경계를 건넌다 — 그래서 이 절이 있다.

**양쪽이 다 보는 값만 목록에 쓴다.** 쿠키 속성은 서버만 정하고 프론트는 보지 못한다
(httpOnly) — 목록에 쓰면 게이트가 프론트에도 요구해 정상 조합이 FAIL한다.

- 마운트 경로: `/api/auth` · 엔드포인트: `/login` · `/refresh` · `/logout`
- 액세스 토큰 전달: `Authorization` 헤더의 `Bearer`
- 로그인 성공 봉투: `accessToken`
- 교차 오리진: 프론트가 `credentials`를 보낸다

**서버 전용(프론트가 보지 못한다)**: 재발급 토큰은 `httpOnly` 쿠키에 담고 이름은 `rt`,
경로는 `/api/auth`로 좁히며 교차 사이트이므로 `SameSite=None; Secure`다. 서버는 구체
오리진을 되비추고 `Access-Control-Allow-Credentials`와 `Vary: Origin`을 낸다.
로그인 응답의 만료 힌트(`expires_in` 류)도 서버가 낼 수 있으나 **이 조합의 프론트는
쓰지 않는다** — 401을 받고 반응적으로 재발급하므로 시계 동기화에 기대지 않는다.

**프론트 전용**: `/api/auth/login`·`/logout`은 프론트가 부르는 완전 경로이고, 서버는
`/api/auth`에 라우터를 마운트한 뒤 `/login`으로 등록한다 — 문자열이 갈리는 것이 정상이다.

재발급은 **1회**다(§5). 회전된 재발급 토큰이 재사용되면 패밀리를 무효화한다.
