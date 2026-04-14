---
name: insight-saver
description: |
  대화에서 나중에 참조할 가치가 있는 교훈/결론/인사이트가 나왔을 때 사용합니다.
  분석, 검토, 문제 해결 과정에서 얻은 핵심 교훈을 dev/docs/insights/에 구조화된 문서로 저장합니다.
  "요약기록", "기록저장", "인사이트 저장" 등의 키워드 사용 시 트리거됩니다. (project)
---

# Insight Saver

대화 중 중요한 인사이트, 교훈, 분석 결과를 구조화된 문서로 자동 저장.

> **경계**: 사용자 수정/지적에 해당하는 교훈은 이 스킬이 아닌 `docs/lessons.md`에 기록 (self-improvement.md 참조).

## 워크플로우

### Step 1: 컨텍스트 분석

최근 5-10개 메시지를 분석하여 핵심 정보 추출: 주제 식별, 카테고리 자동 추론, 핵심 인사이트 추출.

### Step 2: 파일명 생성

형식: `{category}/{topic-slug}-{YYYY-MM-DD}.md`

### Step 3: 문서 작성

### Step 4: 파일 저장

경로: `dev/docs/insights/{category}/{filename}.md`

### Step 5: 사용자 피드백

## 주의사항

- 중복 파일명 발생 시 자동으로 숫자 접미사 추가
- 카테고리 디렉토리가 없으면 자동 생성
- 파일명에 날짜 필수 포함
