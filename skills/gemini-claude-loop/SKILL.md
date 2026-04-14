---
name: gemini-claude-loop
description: |
  외부 AI(Gemini)로 코드를 독립 검증하고 싶을 때, 또는 review-agent의 P6 조건 충족 시 사용합니다.
  Claude Code가 설계/구현하고 Gemini CLI가 검증/리뷰하는 듀얼 AI 엔지니어링 루프를 오케스트레이션합니다.
  사용자가 코드 품질의 교차 검증을 요청할 때도 직접 호출 가능합니다.
---

# Gemini-Claude Engineering Loop

Claude Code가 구현하고 Gemini가 검증하는 듀얼 AI 품질 보증 루프입니다.

> 공통 워크플로우(Step 1/3/4/6, 에러 처리, 모범 사례): `references/shared-workflow.md` 참조

## 전제조건

- **Gemini CLI 설치**: `npm install -g @anthropic-ai/gemini-cli` 또는 [공식 설치 가이드](https://github.com/google-gemini/gemini-cli)
- **확인**: `gemini --version` 으로 설치 확인

### API 키 설정

스킬 실행 시 `GEMINI_API_KEY` 환경변수를 확인합니다.

## 워크플로우

### Step 0: 환경 확인

### Step 1~4: 공통 워크플로우

`references/shared-workflow.md`의 Step 1, 3, 4를 따릅니다.

### Step 2: 계획 검증 (Gemini)

```bash
gemini -p "다음 구현 계획을 검토하고 문제점을 식별해주세요: [Claude의 계획]" -m gemini-2.5-pro
```

### Step 5: 교차 리뷰 (Gemini)

```bash
gemini -p "다음 코드 변경사항을 리뷰해주세요: $(git diff)" -m gemini-2.5-pro
```

### Step 6: 반복 개선

## 명령어 참조

| 단계      | 명령어 패턴                                            | 목적               |
| --------- | ------------------------------------------------------ | ------------------ |
| 계획 검증 | `gemini -p "계획 리뷰: [계획]" -m gemini-2.5-pro`      | 구현 전 로직 확인  |
| 코드 리뷰 | `gemini -p "리뷰: $(git diff)" -m gemini-2.5-pro`      | Gemini가 구현 검증 |
| 재검증    | `gemini -p "수정 확인: $(git diff)" -m gemini-2.5-pro` | 수정 후 재확인     |
