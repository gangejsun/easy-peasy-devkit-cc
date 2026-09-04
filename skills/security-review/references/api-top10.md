# OWASP API Security Top 10 (2023) — 델타만

<!-- 착안: davila7/claude-code-templates `owasp-security` (MIT · Copyright (c) 2025 Daniel (San) Ávila)
     내용 정본: OWASP API Security Top 10 2023 공개 표준. -->

**웹 Top 10과 겹치는 항목은 여기서 다시 쓰지 않는다.** API 고유의 표면만 담는다.
겹치는 것은 `owasp-top10.md`로 간다: API7(SSRF)→A10 · API8(Misconfiguration)→A05 ·
API2(Broken Authentication)→A07.

| ID | 이름 | 이 하네스에서 |
| --- | --- | --- |
| API1:2023 | Broken Object Level Authorization (BOLA) | **위임** — 소유권·IDOR은 우리 자산이 상위 호환이다 (`owasp-top10.md` A01) |
| API2:2023 | Broken Authentication | 위임 → A07 |
| API3:2023 | Broken Object Property Level Authorization | **아래** |
| API4:2023 | Unrestricted Resource Consumption | **아래** |
| API5:2023 | Broken Function Level Authorization | **아래** |
| API6:2023 | Unrestricted Access to Sensitive Business Flows | **아래** |
| API7:2023 | Server Side Request Forgery | 위임 → A10 |
| API8:2023 | Security Misconfiguration | 위임 → A05 |
| API9:2023 | Improper Inventory Management | **아래** |
| API10:2023 | Unsafe Consumption of APIs | **아래** |

---

### API3:2023 Broken Object Property Level Authorization — CWE-915 · CWE-213

객체 **단위**의 인가는 있는데 **속성 단위**가 없는 경우다. 두 방향 모두 결함이다 —
받으면 안 되는 필드를 받거나(mass assignment), 주면 안 되는 필드를 준다(과다 노출).

- [ ] 요청 본문을 모델에 통째로 넘기지 않는다. **받을 필드를 명시적으로 고른다**
      (`role`·`isAdmin`·`ownerId`·`balance`가 사용자 입력으로 덮이지 않는가)
- [ ] 응답은 **직렬화 스키마를 거쳐** 나간다. ORM 엔티티를 그대로 반환하지 않는다
- [ ] 역할에 따라 보이는 필드가 다르면 그 분기가 **서버에서** 일어난다
- [ ] 스키마 검증기가 알 수 없는 키를 **거부**하도록 설정돼 있다 (zod `.strict()` 등)

### API4:2023 Unrestricted Resource Consumption — CWE-770

- [ ] 인증·비인증 경로 모두에 **rate limit**이 있다 (특히 로그인·검색·파일 업로드)
- [ ] 요청 본문·업로드 크기 상한이 있다
- [ ] 목록 조회에 **페이지 크기 상한**이 있다 (`limit=999999`가 통하지 않는가)
- [ ] 비용이 큰 작업(리포트·내보내기·이미지 변환)에 동시 실행 제한이나 큐가 있다
- [ ] GraphQL이면 쿼리 깊이·복잡도 상한이 있다

### API5:2023 Broken Function Level Authorization — CWE-285

- [ ] 관리자 전용 동작이 **역할 검사**를 거친다. 경로가 안 알려진 것에 기대지 않는다
- [ ] 라우터에 인증 미들웨어가 **누락된 엔드포인트가 없다** (축 가이드의 `requireAuth`
      배선 정책이 이것을 기계로 본다)
- [ ] HTTP 메서드별로 권한이 갈리면 그 분기가 실제로 있다 (`GET`은 되고 `DELETE`는 안 되는가)

### API6:2023 Unrestricted Access to Sensitive Business Flows — CWE-799

기술적으로는 정상 요청인데 **비즈니스적으로 남용**되는 경우다. 예매 싹쓸이, 쿠폰 자동
소진, 대량 계정 생성.

- [ ] 남용되면 곤란한 흐름이 식별돼 있다 (구매·예약·초대·환불)
- [ ] 그 흐름에 사람 확인·기기 지문·속도 제한 중 최소 하나가 있다
- [ ] 실패해도 재고·한도가 정확히 복구된다

### API9:2023 Improper Inventory Management — CWE-1059

- [ ] 배포된 API 버전 목록이 있고, **구버전이 살아 있지 않다**
- [ ] 스테이징·디버그 엔드포인트가 프로덕션에 노출되지 않는다
- [ ] 문서와 실제 라우트가 일치한다 (문서에 없는 살아 있는 엔드포인트가 가장 위험하다)

### API10:2023 Unsafe Consumption of APIs — CWE-1104

**우리가 호출하는 외부 API도 신뢰 경계 밖이다.**

- [ ] 외부 응답을 **검증한 뒤** 쓴다. 서드파티라고 스키마 검증을 건너뛰지 않는다
- [ ] 외부 호출에 타임아웃과 재시도 상한이 있다
- [ ] 외부가 준 URL을 그대로 따라가지 않는다 (SSRF와 같은 축 — A10)
- [ ] 외부 응답을 그대로 화면에 렌더링하지 않는다 (XSS와 같은 축 — A03)
