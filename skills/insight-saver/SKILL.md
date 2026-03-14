---
name: insight-saver
description: 대화 중 중요한 인사이트를 자동으로 문서화하여 dev/docs/insights/에 저장합니다. "요약기록", "기록저장", "인사이트 저장" 등의 키워드 사용 시 트리거됩니다. 분석, 검토, 문제 해결 과정에서 얻은 핵심 교훈을 기록할 때 사용하세요. Claude와의 대화에서 유용한 정보, 설계 결정, 기술적 인사이트를 발견했을 때도 사용할 수 있습니다.
---

# Insight Saver

대화 중 중요한 인사이트, 교훈, 분석 결과를 구조화된 문서로 자동 저장.

## 워크플로우

### Step 1: 컨텍스트 분석

최근 5-10개 메시지를 분석하여 핵심 정보 추출:

1. **주제 식별**
   - 대화의 주요 주제 파악 (예: "Rule vs Hook 거버넌스")
   - 기술 스택, 개념, 문제 영역 추출

2. **카테고리 자동 추론**

   키워드 기반 매칭으로 카테고리 결정:

   | 카테고리 | 키워드 |
   |----------|--------|
   | governance | rule, hook, policy, convention, governance, workflow |
   | architecture | design, pattern, structure, component, architecture, system |
   | testing | test, tdd, coverage, integration, unit, e2e |
   | debugging | bug, error, fix, troubleshoot, debug, issue |
   | general | 위 카테고리 외 모든 경우 |

3. **핵심 인사이트 추출**
   - 사용자와 Claude의 대화에서 "깨달음", "교훈", "결론" 식별
   - 3-5개 핵심 인사이트로 요약
   - 기술적 세부사항보다 "왜"와 "무엇을" 중심으로 추출

### Step 2: 파일명 생성

1. **슬러그 생성**
   - 주제를 소문자로 변환
   - 공백을 하이픈(-)으로 변환
   - 특수문자 제거 (알파벳, 숫자, 하이픈만 유지)
   - 예: "Rule vs Hook 거버넌스" → "rule-vs-hook-governance"

2. **파일명 구성**
   - 형식: `{category}/{topic-slug}-{YYYY-MM-DD}.md`
   - 예: `governance/rule-vs-hook-lessons-2026-03-07.md`

3. **중복 처리**
   - 동일 파일명 존재 시 숫자 접미사 추가 (`-2.md`, `-3.md`)

### Step 3: 문서 작성

다음 템플릿으로 Markdown 문서 생성:

```markdown
# {주제 제목}

**작성일**: {YYYY-MM-DD}
**출처**: Claude Code 세션
**카테고리**: {자동 추론된 카테고리}

---

## 핵심 인사이트

1. {인사이트 1}
2. {인사이트 2}
3. {인사이트 3}
...

## 상세 내용

{대화 내용 요약}

대화에서 논의된 주요 내용:
- {핵심 포인트 1}
- {핵심 포인트 2}
...

## 관련 파일

- [{파일명1}]({상대경로1})
- [{파일명2}]({상대경로2})
...

---

*이 문서는 /insight-saver 스킬로 자동 생성되었습니다.*
```

**작성 원칙**:
- 핵심 인사이트는 간결하게 (각 항목 1-2문장)
- 상세 내용은 대화 흐름을 요약 (전체 대화 복사 금지)
- 관련 파일은 대화에서 언급된 파일 경로만 포함

### Step 4: 파일 저장

1. **디렉토리 확인**
   - `dev/docs/insights/{category}/` 디렉토리가 없으면 생성

2. **Write 도구 사용**
   - 경로: `dev/docs/insights/{category}/{filename}.md`
   - 내용: Step 3에서 생성한 Markdown

### Step 5: 사용자 피드백

저장 완료 후 다음 형식으로 출력:

```
✅ 인사이트를 저장했습니다:
📁 dev/docs/insights/{category}/{filename}.md

핵심 내용:
- {인사이트 1 요약}
- {인사이트 2 요약}
- {인사이트 3 요약}
```

## 예시

**입력 (사용자)**:
```
Rule과 Hook의 차이를 이제 완벽히 이해했어!
요약기록
```

**출력 (Claude)**:
```
✅ 인사이트를 저장했습니다:
📁 dev/docs/insights/governance/rule-vs-hook-core-lessons-2026-03-07.md

핵심 내용:
- Rule = 사고 단계 예방 (코드 작성 전 교육)
- PreToolUse Hook = 실행 단계 예방 (파일 기록 전 차단)
- 하이브리드 전략 (Rule 95% + Hook 5%) = 100% 준수율
```

**생성된 파일 내용**:
```markdown
# Rule vs Hook 거버넌스 시스템의 핵심 교훈

**작성일**: 2026-03-07
**출처**: Claude Code 세션
**카테고리**: governance

---

## 핵심 인사이트

1. **Rule = 사고 단계 예방**: Claude가 코드를 작성하기 전에 영향을 주어 처음부터 올바른 코드를 생성
2. **PreToolUse Hook = 실행 단계 예방**: 코드 작성 후 파일 기록 전에 차단하여 강제 검증
3. **하이브리드 전략 최적**: Rule 95% 예방 + Hook 5% 추가 차단 = 100% 보안 보장

## 상세 내용

사용자가 "Hooks는 .sh 파일이므로 토큰 절약"이라는 가정을 검증 요청...
(대화 요약)

## 관련 파일

- [governance-comparison-2026-03-07.md](dev/docs/analysis/governance-comparison-2026-03-07.md)
- [rule-vs-hook-security-2026-03-07.md](dev/docs/analysis/rule-vs-hook-security-2026-03-07.md)

---

*이 문서는 /insight-saver 스킬로 자동 생성되었습니다.*
```

## 주의사항

- 중복 파일명 발생 시 자동으로 숫자 접미사 추가
- 카테고리 디렉토리가 없으면 자동 생성
- 파일명에 날짜 필수 포함 (중복 방지 + 시간순 정렬)
- 관련 파일 경로는 상대 경로로 작성 (dev/docs/ 기준)
