# 스킬 전수 검토 — skill-creator 방법론 대조

- 날짜: 2026-08-19 · 대상: skills/ 34개 · 기준: `/skill-creator:skill-creator` 실제 로드 후 대조
- 방식: 정적 기준 대조 (실측 A/B 평가 루프는 후보 선별 후 별도 실행 — §5)

## 1. 비교 기준 (skill-creator 방법론에서 추출)

| # | 기준 | 요지 |
| --- | --- | --- |
| C1 | description = 트리거 계약 | what+when 모두 포함, 약간 "pushy"(undertrigger 대응). **본문이 못 지키는 약속 금지** |
| C2 | 점진적 공개 | SKILL.md <500줄, 리소스는 "언제 읽을지" 안내와 함께 분리 |
| C3 | 명령형 + 이유 설명 | MUST/ALWAYS 남발은 황색 신호 — why를 설명 |
| C4 | 출력 형식·예시 | 출력 템플릿 명시, Input/Output 예시 동봉 |
| C5 | 반복 작업의 스크립트화 | 매 실행이 재발명할 작업은 scripts/로 동봉. **동봉했으면 실재해야 함** |
| C6 | 평가 기반 반복 | 테스트 프롬프트 → with/without 실측 → 개선 루프 |

## 2. 전수 판정표

판정: ✅ 기존 우세 (skill-creator 재생성 대비 손해) · 🔧 부분 보완 · ❌ 재생성/재구성 필요

| 스킬 | 판정 | 근거 (기준 위반) |
| --- | --- | --- |
| nextjs-frontend-guide | ✅ | 교과서적 C2 — Quick Start 체크리스트 + 태스크→리소스 매핑 테이블 + 리소스 10개. skill-creator가 권하는 도메인 분할 그대로 |
| nextjs-backend-guide | ✅ | 동일 구조. 리소스 10개 분리 |
| ui-ux-design | 🔧 | 데이터 자산(CSV 15종+BM25 스크립트)은 재생성 불가 수준의 우위. 단 **호출 경로가 `.claude/skills/` 하드코딩** — 플러그인 배포 시 실패 (C5 위반). 스킬 base 상대 경로로 수정 필요 |
| security-review | ✅ | C1 모범 — 내장 /security-review와의 경계를 description에서 선언. 심각도 테이블 구체적 |
| receiving-code-review | ✅ | 행동 설계 우수 (금지 응답 패턴, 검증 우선). C3 준수 |
| council-review | ✅ | 팬아웃·합의 규칙·부분 실패 처리·재질의 상한. 커밋 1·3에서 라우팅·템플릿 보수 완료 |
| codex-claude-loop | ✅ | 커밋 2에서 본체 복구·상한 부여 완료. 플러그인/CLI 이중 모드 구체적 |
| gemini-claude-loop | 🔧 | 공유 본문은 수리됐으나 SKILL.md 자체의 Step 0·6이 빈 제목 (C4 미비 잔존) |
| harness-evaluation | ✅ | 금일 재작성 — 기계 판정 명령 내장, 결함 목록 출력, 커버리지 맵 |
| epcc-init | ✅ | 대화형 절차·생성물 명세 구체적. manual trigger 명시 |
| epcc-migrate | ✅ | allow-stale-refs 마커, "측정으로 지운다" 원칙. C3 모범 |
| prd-reviewer | ✅ | 6축 진단 + "반영 위치 명시" 의무 — 출력이 곧 실행 가능 백로그 |
| fix-issue | ✅ | gh 명령 구체적, 추측 금지 명시 |
| brainstorming | ✅ | 질문 규율(한 번에 하나, 가설 옵션) 명확. 커밋 1에서 라우팅 보수 |
| prompt-enhancer | ✅ | 커밋 1에서 라우팅 보수. 경량/심층 분기 명확 |
| insight-saver | ✅ | 소형·단일 목적·경계 명시. 예시 부재는 아쉬우나 치명적이지 않음 |
| execution-dashboard | ✅ | 커밋 3에서 로그 재배선 완료 |
| profile-update | ✅ | 듀얼 A/B 설계는 34개 중 가장 정교. 커밋 3에서 참조 정리 완료 |
| completion-review | ✅ | 작업 유형별 범위 테이블 + Pitfalls 구체적 |
| research | ✅ | 커밋 3에서 경로 정정. 소형 오케스트레이터로 적정 |
| marketing-workflow | ✅ | 모드 라우팅 테이블 명확. 커밋 3에서 템플릿 인라인 완료 |
| scroll-stop-prompter | ✅ | 참조 가이드 실재, 모드 분기 명확 |
| scroll-stop-builder | 🔧 | 구조는 좋으나 전제 조건(FFmpeg·흰 배경·로컬 서버)이 검증 스텝 없이 나열 — 실패 시 안내 부재 |
| seo-strategy | 🔧 | 3모드 라우팅 좋음. 리소스 4종에 "언제 읽을지" 안내 부족 (C2 부분 위반) |
| service-planner | ✅ | 커밋 3에서 완전판 승격 완료 |
| business-planner | ✅ | 동일 |
| prd-generator | 🔧 | Step 2·4·5·6이 **빈 제목** — PRD 출력 템플릿 부재 (C4 위반). 실행마다 구조가 달라짐. assets/prd-template.md 동봉 필요 |
| dev-docs-generator | 🔧 | 빈 Step 뼈대 + **죽은 참조 2건** (`dev/templates/`·`docs/dev-docs-pattern.md` 부재). plan/context/tasks 템플릿 동봉 필요 |
| test-driven-development | 🔧 | 방법론 본문은 우수하나 ① 삭제된 v2 훅(stop-guard.sh) 참조 ② 특정 스택(Vitest·pnpm·경로) 하드코딩 — 범용 플러그인 부적합 (C1 위반: 소비 프로젝트에서 거짓 정보) |
| health-check | ❌ | **Step 2·3 전체가 존재하지 않는 `scripts/build-parser.sh`에 의존.** C5 최악 위반 — 선언한 엔진이 없음. 스크립트 동봉 또는 본문 재설계 필요 |
| web-asset-generator | ❌ | **지시하는 스크립트 3종 전부 부재** (check_dependencies·generate_favicons·generate_og_images). + `.claude/skills/` 경로 하드코딩. health-check와 동일 병 |
| react-vite-frontend-guide | ❌ | **본문이 TODO placeholder.** description은 완성 가이드처럼 선언 — 트리거되면 빈 내용 로드 (C1 정면 위반) |
| react-vite-backend-guide | ❌ | 동일 placeholder |
| python-fastapi-backend-guide | ❌ | 동일 placeholder |

집계: ✅ 21 · 🔧 8 · ❌ 5

## 3. 구조적 발견 — skill-creator라면 생기지 않았을 결함의 공통 형태

**❌ 5건의 공통점은 "description이 본문이 못 지키는 약속을 한다"는 것이다.**
skill-creator 프로세스는 본문·스크립트를 먼저 만들고 테스트 실행을 거친 뒤 description을
최적화한다 — 이 순서에서는 placeholder에 완성형 description이 붙을 수 없고,
존재하지 않는 스크립트를 지시하는 본문이 테스트 1회를 통과할 수 없다.
현재 ❌ 5건은 전부 **선언 먼저, 구현 나중(또는 없음)** 순서의 산물이다.

**34개 공통 gap (skill-creator 기준):**

| Gap | 실측 | 영향 |
| --- | --- | --- |
| Input/Output 예시 0/34 | 예시 패턴 전무 | 생성계 스킬(prd·research·insight)의 출력 편차 |
| 평가 루프 부재 | evals/ 디렉토리 0개 | 어떤 스킬도 with/without 실측 근거 없음 |
| 트리거 desc 미최적화 | 600자+ 장문 desc 6개 (최장 889자) | 상주 컨텍스트 비용 + 최적화 실측 없음 |

## 4. 권고 조치 (우선순위순)

| # | 조치 | 대상 | 성격 |
| --- | --- | --- | --- |
| 1 | **placeholder 3종 처리 결정** — (a) 본문 실작성 (b) 스킬 제거 + 프리셋에서 제외. 현 상태(거짓 트리거)가 최악 | react-vite×2 · python-fastapi | 결정 필요 |
| 2 | **부재 스크립트 해소** — 동봉 작성 또는 본문을 "모델이 직접 수행" 방식으로 재설계 | health-check · web-asset-generator | 재구성 |
| 3 | 경로 하드코딩 수정 — `.claude/skills/` → 스킬 base 상대 | ui-ux-design · web-asset-generator | 1줄급 |
| 4 | TDD 스킬의 프로젝트 잔재 절제 — stop-guard.sh·Vitest 블록을 epcc.config 참조로 치환 | test-driven-development | 보완 |
| 5 | 빈 Step 뼈대 채움 + 출력 템플릿 동봉 | prd-generator · dev-docs-generator · gemini-claude-loop | 보완 |
| 6 | doctor B-6 확장 — 스킬이 지시하는 **프로젝트 루트 경로·스크립트** 실재 검사 (이번 발견 5건 전부 이 사각지대) | scripts/doctor.sh | 재발 방지 |

## 5. 실측 A/B 후보 (skill-creator 본령 — 별도 세션 권장)

정적 대조로 판정 불가한 접전은 실측이 맞다:

| 후보 | 검증 질문 |
| --- | --- |
| test-driven-development | 잔재 절제판 vs 현행 — 강제력이 유지되는가 |
| prd-generator (템플릿 동봉 후) | 출력 일관성이 실제로 오르는가 |
| 장문 desc 6종 | description optimizer로 트리거 정확도 유지하며 축약 가능한가 |

방법: skill-creator의 평가 루프 (테스트 프롬프트 2-3개 → with/without 서브에이전트 → 벤치마크 뷰어).
