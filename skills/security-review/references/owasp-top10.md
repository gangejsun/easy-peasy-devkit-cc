# OWASP Top 10 (2021) — 이 하네스에서의 지도

<!-- 착안: davila7/claude-code-templates `owasp-security` (MIT · Copyright (c) 2025 Daniel (San) Ávila)
     내용 정본: OWASP Top 10 2021 공개 표준. 산문을 옮기지 않고 이 하네스의 강제 모델에 맞춰 다시 썼다. -->

**각 항목은 「위임」이거나 「신규」이지 둘 다가 아니다.** 보안 지식이 이미 네 곳
(`.claude/rules/security.md` · 축 가이드의 `policies.md` · `security-vectors.md` ·
이음매 `contract.md`)에 있다. 여기서 같은 내용을 다시 쓰면 다섯 번째 사본이 되고,
사본은 드리프트 원천이다. 위임 항목은 **어디를 볼지만** 말한다.

---

## 위임 — 이미 하네스가 두껍게 덮는 축

### A01:2021 Broken Access Control — CWE-284 · CWE-639 · CWE-862

**이 하네스에서 가장 강한 축이다. 여기서 다시 쓰지 않는다.**

- 보편 규범 → `.claude/rules/security.md` 「인가 경계」
- 스택별 절차 → 설치된 축 가이드의 인증/권한 리소스
- 실패 표면 계약 → 이음매 `contract.md` §5 (미인증 401 · 소유권 실패 404 · 역할 실패 403)
- 오픈 리다이렉트 벡터 → `stack-guide-generator/assets/security-vectors.md` A절

감사 시 확인할 것은 하나다: **소유권이 쿼리 조건에 들어가 있는가**, 아니면 조회 후
비교하는가. 후자는 0행 변이·열거 공격에 열려 있다.

### A04:2021 Insecure Design — CWE-1173 · CWE-657

**위임.** 설계 국면은 되돌림 분류(T0)와 `epcc-planner`·`brainstorming`이 담당한다.
`Irreversible`(auth/RLS·결제·마이그레이션)로 판정되면 다관점 팬아웃과 사용자 확인이
강제되는 것이 이 하네스의 위협 모델링 자리다.

### A06:2021 Vulnerable and Outdated Components — CWE-1104 · CWE-1035

**위임.** 의존성 도입 전 5단계 점검은 `.claude/rules/code-change.md`,
설치본 감사는 이 스킬 Step 4(락파일 판별 → 매니저별 audit).

---

## 신규 — 하네스에 정본이 없던 축

### A02:2021 Cryptographic Failures — CWE-327 · CWE-311 · CWE-326

탐지 신호: 평문 저장된 민감 데이터 · `MD5`/`SHA1`을 비밀번호에 사용 · `DES`·`RC4`·
ECB 모드 · TLS 미강제 · 직접 구현한 암호 루틴.

- [ ] 전송 구간은 TLS 1.2 이상. HTTP로 떨어지는 경로가 없다
- [ ] 저장 시 암호화가 필요한 필드(주민번호·카드·건강정보)가 식별돼 있다
- [ ] 대칭 암호는 **인증된 모드**(AES-GCM 등). ECB를 쓰지 않는다
- [ ] 키는 코드가 아니라 환경/시크릿 매니저에 있고, 회전 절차가 문서화돼 있다
- [ ] 난수는 CSPRNG(`crypto.randomBytes` · `secrets` 모듈). `Math.random()`을 토큰에 쓰지 않는다

### A03:2021 Injection — CWE-89 · CWE-78 · CWE-79 · CWE-943

**보편 규범은 `.claude/rules/security.md` 「입력 검증 경계」에 있다. 여기는 그 상세다.**

탐지 신호: 쿼리 문자열 결합(`"SELECT … " + id`) · 템플릿 리터럴로 만든 SQL ·
`exec`/`spawn`에 사용자 입력 · NoSQL 연산자 주입(`{$gt: ""}`) · 동적 `eval`.

- [ ] 모든 쿼리가 **파라미터화**(placeholder/prepared statement)돼 있다. ORM을 쓰더라도
      raw 이스케이프 해치(`$queryRaw`·`text()`)에 결합이 없다
- [ ] 식별자(테이블·컬럼·정렬 방향)처럼 파라미터화할 수 없는 자리는 **허용 목록**으로 좁힌다
- [ ] 셸 호출은 인자 배열로 넘긴다. 문자열 하나로 조립해 셸에 넘기지 않는다
- [ ] NoSQL은 사용자 입력이 **객체가 아니라 값**임을 보장한다(연산자 주입 방지)
- [ ] XSS는 컨텍스트별 이스케이프 — HTML 본문·속성·URL·JS·CSS가 각각 다르다

### A05:2021 Security Misconfiguration — CWE-16 · CWE-1188 · CWE-209

탐지 신호: 프로덕션 디버그 모드 · 기본 자격증명 · 스택 트레이스 응답 · 디렉토리 리스팅 ·
과도하게 넓은 CORS(`*` + credentials) · 미설정 보안 헤더.

- [ ] 프로덕션 빌드에서 디버그·상세 에러가 꺼져 있다 (출력 규범은 `security.md` 「출력 보안」)
- [ ] 기본 계정·기본 비밀번호가 남아 있지 않다
- [ ] CORS의 `origin`이 허용 목록이다. `*`와 `credentials: true`를 함께 쓰지 않는다
- [ ] 보안 헤더: `Content-Security-Policy` · `X-Content-Type-Options: nosniff` ·
      `Strict-Transport-Security` · `Referrer-Policy` · 프레이밍 차단
- [ ] 관리·디버그 엔드포인트가 외부에 노출되지 않는다

### A07:2021 Identification and Authentication Failures — CWE-287 · CWE-916 · CWE-307 · CWE-384

탐지 신호: 비밀번호를 단방향 해시 없이 저장 · `md5(password)` · 로그인 rate limit 부재 ·
예측 가능한 세션 ID · 로그아웃 시 세션 미무효화 · 비밀번호 재설정 토큰의 낮은 엔트로피.

- [ ] 비밀번호는 **bcrypt · scrypt · Argon2** 중 하나. 범용 해시(SHA-256)를 쓰지 않는다
- [ ] 로그인·재설정·OTP에 **rate limit과 잠금**이 있다
- [ ] 세션 식별자는 CSPRNG로 128비트 이상. 로그인 성공 시 **재발급**한다(세션 고정 방지)
- [ ] 로그아웃과 비밀번호 변경이 기존 세션을 무효화한다
- [ ] 인증 실패 메시지가 계정 존재 여부를 누설하지 않는다 (실패 사유를 하나로 접는다)
- [ ] 재설정 토큰은 일회용이고 만료가 짧다

### A08:2021 Software and Data Integrity Failures — CWE-502 · CWE-345 · CWE-494

탐지 신호: `pickle.loads` · Java `ObjectInputStream` · PHP `unserialize` · YAML
`load`(safe_load 아님) · 서명 검증 없는 웹훅 · 무결성 검증 없는 외부 스크립트 로드.

- [ ] **신뢰할 수 없는 데이터를 역직렬화하지 않는다.** 직렬화 형식은 JSON을 쓴다
- [ ] YAML은 `safe_load` 계열만 쓴다
- [ ] 웹훅·콜백은 **시그니처를 검증한 뒤에** 처리한다 (결제 축은 이 스킬 Step 5)
- [ ] CDN 스크립트에 SRI(`integrity`)가 있거나, 애초에 번들에 포함한다
- [ ] CI가 잠금 파일을 신뢰하고 임의 후속 설치를 하지 않는다

### A09:2021 Security Logging and Monitoring Failures — CWE-778 · CWE-532 · CWE-223

**엔터프라이즈 감사에서 가장 먼저 요구되는 축인데 하네스에 정본이 없었다.**

탐지 신호: 인증·인가 실패가 로그에 남지 않음 · 로그에 토큰·비밀번호·주민번호가 그대로 ·
로그가 로컬 파일에만 있음 · 이상 징후 알림 없음.

- [ ] **보안 사건이 로그에 남는다** — 로그인 성공/실패, 권한 거부, 관리자 조작,
      결제 상태 변경, 시크릿 접근
- [ ] 각 기록에 **누가·무엇을·언제·어디서**가 있다 (주체 식별자 · 행위 · 타임스탬프 · 출처 IP)
- [ ] **로그에 시크릿을 쓰지 않는다** — 토큰·비밀번호·카드번호·개인식별정보는 마스킹한다
      (`security-check` 훅은 로그 문자열을 보지 않는다 — 여기는 사람이 봐야 하는 자리다)
- [ ] 로그가 중앙에 모이고 보존 기간이 정해져 있다
- [ ] 실패 급증·권한 거부 급증에 알림이 있다
- [ ] 로그 자체가 위변조되지 않는다 (append-only 또는 외부 전송)

### A10:2021 Server-Side Request Forgery — CWE-918

탐지 신호: 사용자가 준 URL로 서버가 `fetch`/`curl` · 웹훅 등록 기능 · 이미지 URL 가져오기 ·
PDF 렌더러가 외부 리소스를 로드.

- [ ] 외부에서 받은 URL은 **허용 목록**(도메인·스킴)을 통과해야 한다
- [ ] `http`/`https` 외 스킴(`file:`·`gopher:`·`dict:`)을 막는다
- [ ] **사설 대역과 링크로컬을 차단**한다 — `127.0.0.0/8` · `10/8` · `172.16/12` ·
      `192.168/16` · `169.254.169.254`(클라우드 메타데이터)
- [ ] DNS 재바인딩을 고려한다 — 검증한 호스트와 실제 연결 대상이 같은지 본다
- [ ] 리다이렉트를 따라갈 때 **각 홉마다** 다시 검증한다
