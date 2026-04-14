---
name: health-check
description: |
  프로젝트 상태 일괄 점검 (빌드, 린트, 타입체크, 테스트).
  사용자가 "상태 점검", "health check", "빌드 확인", "프로젝트 상태" 등을 요청할 때 사용합니다.
  수동 호출 전용 (/health-check). 자동 트리거되지 않습니다. (project)
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

```bash
scripts/build-parser.sh build
```

- build-parser.sh를 활용하여 빌드 에러를 JSON 구조화
- TypeScript 에러: 파일, 행, 열, 메시지 추출
- 성공 시 `"success": true` 확인

### Step 3: 린트 검사

```bash
scripts/build-parser.sh lint
```

- ESLint 에러/경고를 JSON 구조화
- severity별 (error/warning) 분류

### Step 4: 테스트 실행

```bash
pnpm test 2>&1
```

- 테스트 결과 요약 (통과/실패/스킵 수)
- 실패 테스트는 파일명과 테스트명 포함

### Step 5: 의존성 점검

```bash
pnpm audit 2>&1
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
