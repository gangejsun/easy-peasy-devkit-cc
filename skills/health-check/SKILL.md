---
name: health-check
description: 프로젝트 상태 일괄 점검 (빌드, 린트, 타입체크, 테스트, SonarQube 정적 분석). 사용자가 "상태 점검", "health check", "빌드 확인", "프로젝트 상태" 등을 요청할 때 사용합니다. 수동 호출 전용.
disable-model-invocation: true
---

# Health Check

프로젝트의 빌드, 린트, 타입체크, 테스트, 의존성, 정적 분석(SonarQube) 상태를 일괄 점검하고
구조화된 보고서를 생성합니다. 정적 분석은 감지됐을 때 **사용자에게 물은 뒤에만** 실행합니다.

## 워크플로우

### Step 1: 점검 범위 결정

| 범위      | 트리거                         | 실행 항목         |
| --------- | ------------------------------ | ----------------- |
| 전체 점검 | 기본값, "전체", "health check" | 2 → 3 → 4 → 5 → 5.5 → 6 |
| 빌드만    | "빌드 확인", "build check"     | 2 → 6             |
| 특정 항목 | 사용자가 항목 지정             | 해당 Step → 6     |
| 정적 분석 | "sonar", "정적 분석"           | 5.5 → 6           |

### Step 2: 빌드 및 타입체크

`${CLAUDE_SKILL_DIR}`는 Claude Code가 치환한다 — 개인·프로젝트·플러그인 어디에 설치되어도 해석된다:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/build-parser.sh build
```

- 명령은 `epcc.config.json`의 `techStack.commands.build` → 없으면 `package.json` scripts에서 자동 해석
- 빌드 에러를 JSON 구조화 (파일·행·메시지, 최대 40건) — 원시 로그를 컨텍스트에 넣지 않는다
- 성공 시 `"success": true` 확인

### Step 3: 린트 검사

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/build-parser.sh lint
```

- ESLint 에러/경고를 JSON 구조화
- severity별 (error/warning) 분류

### Step 4: 테스트 실행

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/build-parser.sh test
```

- 테스트 결과 요약 (통과/실패/스킵 수)
- 실패 테스트는 파일명과 테스트명 포함

### Step 5: 의존성 점검

패키지 매니저를 락파일로 판별해 실행한다 (pnpm-lock.yaml→pnpm audit, yarn.lock→yarn audit,
package-lock.json→npm audit, uv.lock→pip-audit 등. 없으면 이 Step 생략):

```bash
pnpm audit 2>&1   # 예시 — 판별된 매니저로 치환
```

- Critical/High/Medium/Low 취약점 분류
- Critical/High 존재 시 즉시 조치 권고

### Step 5.5: 정적 분석 (SonarQube) — 묻고 실행한다

**감지** — 셋 중 하나라도 참일 때만 진입한다:

```bash
ls sonar-project.properties 2>/dev/null
jq -r '.techStack.commands.sonar // empty' epcc.config.json 2>/dev/null
command -v sonar-scanner
```

하나도 없으면 **설치를 요구하지 않고 생략한다.** 보고서 「미검사」에 한 줄만 남긴다 —
도구 부재를 결함 부재로 접지 않기 위해서다.

**감지되면 사용자에게 묻는다. 묻지 않고 실행하지 않는다** — 분석은 소스를 서버로 올리고
(원격 서버면 전송 범위를 고지한다) 수 분이 걸린다:

| 선택 | 동작 |
| --- | --- |
| 분석만 | 실행 → 보고서에 결과만 싣는다. 코드는 고치지 않는다 |
| 분석 + 자동 수정 | 실행 → Step 5.6 (수정 회귀) |
| 건너뛰기 | 미실행. 보고서에 「미검사 — 사용자 보류」로 적는다 (판정 불가와 구분한다) |

**실행**:

```bash
bash ${CLAUDE_SKILL_DIR}/scripts/build-parser.sh sonar
```

- `SONAR_HOST_URL`·`SONAR_TOKEN`은 **환경변수로만** 받는다. config나 파일에 적으면
  `security-check` 훅이 시크릿 쓰기로 차단한다
- 출력의 `undecidable: true`는 **실패가 아니라 판정 불가**다 (스캐너·서버·토큰 부재, 분석 미완료).
  `reason`을 보고서 「미검사」에 그대로 옮기고 **양호로 적지 않는다**

### Step 5.6: 수정 회귀 — 여기서 수정하지 않는다

사용자가 「분석 + 자동 수정」을 골랐을 때만 진입한다.

**Sonar 이슈를 그대로 고치지 않는다.** 규칙 엔진은 프로젝트 맥락을 모른다 — 오탐 필터가 먼저다.
이슈 목록을 `receiving-code-review`에 넘긴다. 검증(Step 2) → 심각도별 처리(Step 3) →
build 재진입(Step 4)은 **그 스킬이 이미 한다. 여기서 재구현하지 않는다.**

심각도 환산:

| Sonar | 하네스 |
| --- | --- |
| BLOCKER · CRITICAL | Critical |
| MAJOR | Important |
| MINOR · INFO | Suggestion (기록만) |

**자동 수정하지 않는 것** — 되돌림 비용이 큰 경로의 이슈는 **보고만 한다**:
`**/migrations/**` · auth/RLS · 결제·정산 · `**/api/**` · `**/actions.ts` · `**/middleware.ts`.
그 경로는 `epcc-reviewer`가 맡는다 (`.claude/rules/reversibility.md`) — 규칙 엔진의 기계 판정으로
사람 확인 없이 건드릴 자리가 아니다.

**재분석 상한 1회.** 수정이 끝나면 Sonar를 한 번만 다시 돌려 이슈가 줄었는지 확인하고 끝낸다.
종료 술어는 `신규 이슈 0건 OR 재분석 1회 소진`이고, 남은 이슈는 사용자에게 넘긴다.
두 번째 재분석은 하지 않는다 — 상한 없는 수정 루프는 결함이다.

### Step 6: 보고서 생성

다음 형식으로 보고서 작성:

```
프로젝트 상태 보고서
==================

점검 일시: [YYYY-MM-DD]
점검 범위: [전체/빌드/특정 항목]

빌드        [PASS/FAIL] — TS 에러 N건
린트        [PASS/FAIL] — 에러 N건, 경고 N건
테스트      [PASS/FAIL] — N passed, N failed, N skipped
의존성      [PASS/WARN] — Critical N, High N
정적 분석   [PASS/FAIL/미검사] — Blocker N, Critical N, Major N

종합 상태: [양호/주의/위험]

--- 상세 ---

[FAIL 항목만 상세 내용 표시]
```

## 종합 상태 판정

| 상태 | 조건                                                   |
| ---- | ------------------------------------------------------ |
| 양호 | 모든 항목 PASS. **미검사 항목이 있으면 양호로 적지 않는다** |
| 주의 | 린트 warning만 존재, Low/Medium 취약점만, 또는 Sonar Major 이하만 |
| 위험 | 빌드 실패, 테스트 실패, Critical/High 취약점, 또는 Sonar Blocker/Critical 존재 |

## 주의사항

- build-parser.sh 출력이 JSON이므로 원시 빌드 로그보다 토큰 효율적
- 각 검사는 독립적 — 하나가 실패해도 나머지 검사 계속 진행
- FAIL 항목에 대해서만 상세 내용을 표시하여 출력 최소화
- 「미검사」와 「PASS」를 섞지 않는다 — 도구가 없어 못 본 것을 통과로 적으면 보고서가 거짓이 된다
