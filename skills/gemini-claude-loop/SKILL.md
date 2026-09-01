---
name: gemini-claude-loop
description: 외부 AI(Gemini)로 코드를 독립 검증합니다. Claude Code가 설계/구현하고 Gemini CLI가 검증/리뷰하는 듀얼 AI 루프를 오케스트레이션합니다. epcc-reviewer의 cross-check 조건 충족 시 사용자 확인 후 호출되거나, 사용자가 코드 품질 검증을 요청할 때 사용하세요. 소스가 외부 모델로 전송되므로 사전 동의 없이 실행하지 않습니다.
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

```bash
command -v gemini >/dev/null 2>&1 && gemini --version || echo "CLI 미설치 — 전제조건 참조"
[ -n "$GEMINI_API_KEY" ] || echo "GEMINI_API_KEY 미설정 — 사용자에게 키 요청"
```

미설치·미설정이면 사용자에게 안내 후 이 스킬을 건너뛴다.

### Step 0.5: 외부 전송 동의 — 건너뛰지 않는다

이 스킬은 **코드를 저장소 밖으로 내보낸다.** 실행 전에 무엇이 나가는지 보이고 동의를 받는다.

| 전송 대상 | 범위 | 비고 |
| --- | --- | --- |
| 계획 검증(Step 2) | 계획 텍스트만 | 소스 미포함 |
| 코드 리뷰·재검증 | **`git diff` 산출물** | 전체 트리를 보내지 않는다 — diff에 한정한다 |

- 사용자가 직접 호출했더라도 **전송 범위는 고지한다**. 자동 경로(epcc-reviewer의
  cross-check)에서는 **동의 없이 실행하지 않는다**
- 시크릿·자격증명이 diff에 포함되면 중단한다 (`security-check` 훅은 파일 쓰기만 본다 —
  외부 전송은 보지 않는다)

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

`references/shared-workflow.md`의 Step 6을 따른다 — **재검증 최대 2회**,
미해결 Critical은 사용자 tie-break.

## 명령어 참조

| 단계      | 명령어 패턴                                            | 목적               |
| --------- | ------------------------------------------------------ | ------------------ |
| 계획 검증 | `gemini -p "계획 리뷰: [계획]" -m gemini-2.5-pro`      | 구현 전 로직 확인  |
| 코드 리뷰 | `gemini -p "리뷰: $(git diff)" -m gemini-2.5-pro`      | Gemini가 구현 검증 |
| 재검증    | `gemini -p "수정 확인: $(git diff)" -m gemini-2.5-pro` | 수정 후 재확인     |
