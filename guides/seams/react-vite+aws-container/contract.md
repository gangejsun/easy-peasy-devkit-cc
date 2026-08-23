# 와이어 계약 — react-vite × aws-container

<!-- epcc-wire-contract: react-vite+aws-container v3.12.0 -->

사전 제작 이음매의 정본 계약이다. 생성 경로에서는 메인 세션이 L0에서 이 양식을 채우지만,
이 조합은 이미 확정돼 있으므로 **실물 이음매에서 도출해 고정**했다. 게이트
`--pair --contract <이 파일>`이 프론트·백엔드 양쪽을 이 문서로 대조한다.

## 0. 도메인 어휘 (신규 항목)

두 축 팩과 이음매가 **같은 리소스 이름**을 쓴다. 실측에서 사전 제작 두 쌍 모두 프론트가
`/tasks`를, 백엔드가 `/notes`를 써서 완전 예제가 서로 실행 불가였다 — 계약 양식의 구멍이
었고 이 절이 그 수리다.

- 엔티티: `Task` · 컬렉션: `tasks` · 한국어 표기: 작업
- 프론트 호출 경로: `/tasks`
- 백엔드 마운트 경로: `/api/tasks`

프론트의 base URL(`config.apiBaseUrl`)이 `/api`까지 포함하므로 두 경로가 같은 곳을 가리킨다.

## 1. 성공 응답 봉투

- 단건: `data` 하나만 담는다 — `{ data: Task }`
- 목록: `data` 배열 + `nextCursor`
- 삭제: 204, 본문 없음

## 2. 에러 응답 봉투

`error` 안에 `code`·`message`·`details`(선택), 최상위에 `requestId`.

## 3. 페이지네이션 모델

- 모델: cursor **하나만**
- 요청 파라미터: `limit`, `cursor`
- 응답 필드: `nextCursor` (마지막 페이지에서 null)

offset 계열 필드(page·offset·totalCount)는 이 계약에 없다. 목록이 아니라 여기에 적는
이유는 게이트가 목록의 백틱을 "양쪽 모두에 있어야 할 값"으로 읽기 때문이다.

## 4. 에러 코드 ↔ 상태 매핑

| code | status | 언제 |
| --- | --- | --- |
| `BAD_REQUEST` | 400 | JSON 파싱 불가, 잘못된 쿼리 형식 |
| `UNAUTHORIZED` | 401 | 토큰 없음·만료·서명 불일치 (사유 구분 없음) |
| `FORBIDDEN` | 403 | 인증됐으나 역할·스코프 부족 (소유권 아님) |
| `NOT_FOUND` | 404 | 리소스 부재 **또는** 미인가 접근 |
| `CONFLICT` | 409 | unique 제약 위반, 상태 충돌 |
| `PAYLOAD_TOO_LARGE` | 413 | 본문 크기 상한 초과 |
| `VALIDATION_FAILED` | 422 | 스키마 검증 실패 |
| `INTERNAL` | 500 | 예상 못 한 예외 (내부 메시지 노출 금지) |

클라이언트가 스스로 만드는 코드(NETWORK_ERROR·TIMEOUT·BAD_SHAPE)는 프론트 가이드에만 둔다 — 백엔드가 내보내지 않으므로 표에 넣지 않는다.

## 5. 인가 실패의 표면

- 미인증: 401 `UNAUTHORIZED`
- 인가 실패: **404 `NOT_FOUND`** — 존재 누설 금지. 프론트가 403만 다루면 어긋난다.
  403은 소유자 아닌 축(역할 부족)에만 온다
- 인증 만료 후 복귀: 401 1회에서만 조용히 갱신을 시도하고, 재실패면 복귀 경로를 보존한
  채 로그인으로 보낸다

복귀 경로는 각 축의 검증 헬퍼를 통과한 값만 쓴다 — 프론트는 safeReturnTo, 백엔드는
safeReturnPath다. 축마다 이름이 다르므로 목록이 아니라 여기에 적는다.
