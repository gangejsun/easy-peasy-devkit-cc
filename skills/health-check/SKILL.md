---
name: health-check
description: 프로젝트 상태 일괄 점검 (빌드, 린트, 타입체크, 테스트). 사용자가 "상태 점검", "health check", "빌드 확인", "프로젝트 상태" 등을 요청할 때 사용합니다. 수동 호출 전용.
---

# Health Check

프로젝트의 빌드, 린트, 타입체크, 테스트, 의존성 상태를 일괄 점검하고 구조화된 보고서를 생성합니다.

## 워크플로우

### Step 1: 점검 범위 결정

| 범위      | 트리거                         | 실행 항목         |
| --------- | ------------------------------ | ----------------- |
| 전체 점검 | 기본값, "전체", "health check" | 2 → 3 → 4 → 5 → 6 |
| 빌드만    | "빌드 확인", "build check"     | 2 → 6             |
| 특정 항목 | 사용자가 항목 지정             | 해당 Step → 6     |

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

종합 상태: [양호/주의/위험]

--- 상세 ---

[FAIL 항목만 상세 내용 표시]
```

## 종합 상태 판정

| 상태 | 조건                                                   |
| ---- | ------------------------------------------------------ |
| 양호 | 모든 항목 PASS                                         |
| 주의 | 린트 warning만 존재 또는 Low/Medium 취약점만           |
| 위험 | 빌드 실패, 테스트 실패, 또는 Critical/High 취약점 존재 |

## 주의사항

- build-parser.sh 출력이 JSON이므로 원시 빌드 로그보다 토큰 효율적
- 각 검사는 독립적 — 하나가 실패해도 나머지 검사 계속 진행
- FAIL 항목에 대해서만 상세 내용을 표시하여 출력 최소화
