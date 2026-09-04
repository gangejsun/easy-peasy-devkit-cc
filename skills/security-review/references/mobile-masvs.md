# 모바일 — OWASP MASVS v2.1.0

<!-- 착안: davila7/claude-code-templates `owasp-security` (MIT · Copyright (c) 2025 Daniel (San) Ávila)
     내용 정본: OWASP MASVS v2.1.0 (2024-01-18) — 8개 통제군. -->

**프로젝트에 모바일 앱이 있을 때만 읽는다.** 이 하네스의 축 가이드는 현재 전부 웹이므로
(프론트 4축·백엔드 8축), 모바일은 축 가이드가 덮지 못하는 자리다.

모바일의 핵심 전제 하나: **기기는 공격자의 손에 있다.** 클라이언트 검증·난독화·루팅 탐지는
난이도를 올릴 뿐 경계가 아니다. 경계는 언제나 서버다.

| 통제군 | 확인할 것 |
| --- | --- |
| **MASVS-STORAGE** | 민감 데이터가 평문으로 로컬에 남지 않는가. 자격증명은 Keychain(iOS)·Keystore(Android)에. 로그·백업·스크린샷 캐시에 새지 않는가 |
| **MASVS-CRYPTO** | 표준 라이브러리만 사용. 하드코딩된 키 없음. 키는 플랫폼 보안 저장소에서 나오고 회전 절차가 있는가 |
| **MASVS-AUTH** | 인증 판정이 **서버에서** 일어나는가. 생체 인증은 UX이지 인가가 아니다 — 잠금 해제 뒤 서버 토큰을 다시 확인한다 |
| **MASVS-NETWORK** | TLS 강제. 인증서·공개키 고정(pinning)을 쓴다면 회전 계획이 있는가. 평문 폴백이 없는가 |
| **MASVS-PLATFORM** | 노출된 컴포넌트(Android exported Activity/Service/Provider) 최소화. 딥링크 입력을 검증하는가. WebView에서 JS 브리지 노출 범위 |
| **MASVS-CODE** | 의존성 최신. 디버그 심볼·테스트 코드가 릴리스에 없는가. 입력 검증이 서버와 이중인가 |
| **MASVS-RESILIENCE** | 루팅/탈옥·디버거·변조 탐지. **이것은 심층 방어이지 경계가 아니다** — 이것만으로 보호되는 자산이 있으면 설계 결함이다 |
| **MASVS-PRIVACY** | 수집하는 데이터가 최소인가. 권한 요청이 실제 기능과 맞는가. 제3자 SDK가 무엇을 보내는가 |

**감사 순서**: STORAGE → NETWORK → AUTH가 실제 사고의 대부분이다. RESILIENCE는 마지막에
보고, 그것을 경계로 삼은 설계가 있는지만 확인한다.
