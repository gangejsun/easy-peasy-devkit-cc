# 코드 리뷰 프롬프트 템플릿

구조화된 코드 리뷰 수행 시 참조하는 6-area 리뷰 프레임워크.

## 리뷰 컨텍스트 변수

| 변수                 | 설명             | 수집 방법                                |
| -------------------- | ---------------- | ---------------------------------------- |
| WHAT_WAS_IMPLEMENTED | 구현된 기능 설명 | review-agent 입력의 "변경 요약"          |
| PLAN_OR_REQUIREMENTS | 계획/요구사항    | dev/active/<name>/ 문서 또는 사용자 설명 |
| DIFF_CONTENT         | 코드 변경 내용   | `git diff`                               |

## 6-Area 리뷰 프레임워크

### 1. 계획 정합성 (Plan Alignment)

dev/active/<name>/ 문서 대비 구현 검증:

- tasks.md의 모든 task가 구현되었는가
- plan.md의 아키텍처/접근법대로 구현되었는가
- 수정 범위(Scope) 섹션의 도메인 경계를 벗어나지 않았는가
- 계획에 없는 불필요한 추가(scope creep)가 있는가
- 미구현 항목이 있다면 의도적 제외인지, 누락인지

### 2. 코드 품질 (Code Quality)

`.claude/rules/code-conventions.md` 기준:

- **타입 안전성**: strict 모드 준수, `any` 사용 여부
- **에러 처리**: 적절한 예외 처리 패턴
- **네이밍**: 프로젝트 네이밍 규칙 준수
- **중복/매직넘버**: 중복 코드, 하드코딩된 숫자/문자열
- **Import 규칙**: 프로젝트 import 규칙 준수
- **함수/컴포넌트 선언**: 프로젝트 선언 패턴 준수

### 3. 아키텍처/설계 (Architecture & Design)

`.claude/rules/modification-guardrails.md` + 프로젝트 패턴 기준:

- **도메인 경계**: 도메인 간 경계 존중
- **공유 패키지**: 공유 코드 수정 시 영향 범위 확인
- **의존성 방향**: 단방향 의존성 유지
- **기존 패턴 일관성**: 유사 기능의 기존 구현 패턴과 일치하는가

### 4. 문서/표준 (Documentation & Standards)

- 자명하지 않은 로직에 인라인 주석이 있는가
- 커밋 메시지 규칙 준수
- 공유 타입이 적절한 위치에 정의
- 새 API/엔드포인트에 대한 문서화 필요성

### 5. 이슈 식별 (Issue Identification)

각 이슈를 다음 중 하나로 분류:

| 심각도         | 기준                                         | 예시                                                 |
| -------------- | -------------------------------------------- | ---------------------------------------------------- |
| **Critical**   | 보안 취약점, 데이터 손실, 프로덕션 장애 유발 | 인증 우회, 시크릿 노출, 무한 루프                    |
| **Important**  | 기능 오동작, 성능 저하, 컨벤션 심각 위반     | 에러 처리 누락, N+1 쿼리, any 타입, 도메인 경계 침범 |
| **Suggestion** | 코드 개선, 스타일, 선택적 최적화             | 네이밍 개선, 불필요한 재렌더링, 주석 보완            |

각 이슈에 반드시 포함:

- **파일:행** 위치
- **설명**: 무엇이 문제인지
- **영향**: 왜 문제인지
- **수정 권고**: 어떻게 고칠지 (코드 예시 포함 권장)

### 6. 커뮤니케이션 (Communication)

- 프로젝트 언어로 작성
- 비판이 아닌 건설적 피드백
- 잘 된 부분을 명시적으로 인정한 후 이슈를 제시
- 구체적이고 실행 가능한 피드백 (모호한 "에러 처리 개선 필요" 금지)

## 출력 형식

```
코드 리뷰 보고서
================

리뷰 범위: [N]개 파일, [+추가/-삭제] 행
작업 유형: [신규 기능/확장/버그 수정/리팩토링]

### 강점
- [잘 구현된 부분, 파일:행 참조]

### Critical ([N]건)
1. **[이슈 제목]**
   - 파일: [경로:행]
   - 발견: [구체적 설명]
   - 영향: [영향 범위]
   - 수정 권고: [코드 예시 포함]

### Important ([N]건)
(동일 형식)

### Suggestion ([N]건)
1. **[이슈 제목]**
   - 파일: [경로:행]
   - 설명: [개선 방향]

### 권고사항
- [전체적 개선 방향]

### 종합 평가
**판정**: [승인 / 조건부 승인 / 수정 필요]
**사유**: [1~2문장 기술적 평가]
```

## 리뷰 수행 규칙

**수행할 것:**

- 실제 심각도에 맞게 분류 (모든 것을 Critical로 올리지 말 것)
- 구체적 파일:행 참조 (모호한 피드백 금지)
- 이슈의 "왜"를 설명
- 잘 된 부분 인정 후 이슈 제시
- 명확한 종합 판정

**수행하지 않을 것:**

- 확인하지 않은 코드에 대한 피드백
- 사소한 것을 Critical로 올리기
- "좋아 보입니다"라는 확인 없는 승인
- 모호한 피드백 ("에러 처리 개선 필요")
- 판정 회피

---

## Minimal Mode Instructions (Small 작업 전용)

**작업 규모**: Small (1~2파일, ~50줄, 로직 포함)
**시간 제한**: 3~5분
**검증 범위**: Critical 이슈만

### You are reviewing a SMALL code change

Focus ONLY on Critical issues that could cause:

- **Type safety violations** (`any`, type assertions)
- **Domain boundary violations** (cross-domain imports)
- **Security issues** (hardcoded secrets, auth bypass)
- **Error handling gaps** (missing exception handling)

### SKIP the following (Large 작업 전용)

- Plan alignment (no dev/active/ for Small tasks)
- Architecture patterns
- Documentation requirements
- Suggestions (Important/Suggestion severity는 보고 안 함)

### Critical Detection Rules

**타입 안전성**:

- `any` 타입 사용 → Critical
- 타입 단언 남용 (3회 이상) → Critical
- strict 경고 무시 (`@ts-ignore` 등) → Critical

**도메인 경계**:

- 다른 도메인 직접 import → Critical
- 공유 패키지에 도메인 로직 포함 → Critical

**보안**:

- API 키/비밀번호 하드코딩 → Critical
- DB 접근 제어 미적용 → Critical
- 인증 체크 누락 (API 엔드포인트) → Critical
- 클라이언트에 민감 데이터 → Critical

**에러 처리**:

- async 함수의 예외 처리 누락 → Critical
- 에러 경계 미설정 (페이지 레벨) → Critical
- 사용자에게 기술적 에러 노출 → Critical

### Time limit: 3-5 minutes MAXIMUM

If you exceed 5 minutes, STOP and output whatever you have found so far.
