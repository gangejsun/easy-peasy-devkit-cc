---
name: gemini-claude-loop
description: |
  Claude Code가 설계/구현하고 Gemini CLI가 검증/리뷰하는 듀얼 AI 엔지니어링 루프를 오케스트레이션합니다.
  review-agent의 P6(TDD 검증) 조건 충족 시 사용자 확인 후 호출되거나, 사용자가 코드 품질 검증을 요청할 때 사용하세요.
---

# Gemini-Claude Engineering Loop

Claude Code가 구현하고 Gemini가 검증하는 듀얼 AI 품질 보증 루프입니다.

## 전제조건

- **Gemini CLI 설치**: `npm install -g @anthropic-ai/gemini-cli` 또는 [공식 설치 가이드](https://github.com/google-gemini/gemini-cli)
- **인증**: Google AI API 키 설정 또는 Google Cloud 인증
- **확인**: `gemini --version` 으로 설치 확인

미설치 시 사용자에게 안내 후 이 스킬을 건너뜁니다.

## 핵심 철학

- **Claude Code**: 아키텍처 설계, 구현, 수정
- **Gemini**: 검증, 코드 리뷰, 품질 보증
- **지속적 교차 검증**: 각 AI가 상대의 작업을 리뷰

## 워크플로우

### Step 1: 계획 수립 (Claude)

1. 작업에 대한 상세 계획 작성
2. 구현 단계를 명확하게 분리
3. 가정사항과 잠재적 이슈 문서화

### Step 2: 계획 검증 (Gemini)

Gemini CLI 비대화형 모드로 계획을 검증합니다:

```bash
gemini -p "다음 구현 계획을 검토하고 문제점을 식별해주세요:

[Claude의 계획]

검토 항목:
- 로직 오류
- 누락된 엣지 케이스
- 아키텍처 결함
- 보안 우려사항" -m gemini-3.1-pro
```

**기본 모델**: `gemini-3.1-pro` (사용 불가 시 `gemini-2.5-pro`)

### Step 3: 피드백 루프

Gemini가 이슈를 발견한 경우:
1. Gemini의 우려사항을 사용자에게 요약
2. 피드백 기반으로 계획 수정
3. `AskUserQuestion`으로 사용자에게 확인: "계획을 수정하여 재검증할까요, 수정 사항을 반영하고 진행할까요?"
4. 필요 시 Step 2 반복

### Step 4: 구현 (Claude)

계획 검증 완료 후:
1. Claude가 Edit/Write/Read 도구로 코드 구현
2. 구현을 관리 가능한 단위로 분리
3. 각 단계별 에러 처리 포함
4. 구현 내용 문서화

### Step 5: 교차 리뷰 (Gemini)

구현 완료 후 Gemini로 코드 리뷰:

```bash
gemini -p "다음 코드 변경사항을 리뷰해주세요:

$(git diff)

검토 항목:
- 버그 탐지
- 성능 이슈
- 모범 사례 준수
- 보안 취약점" -m gemini-3.1-pro
```

Claude가 Gemini의 피드백을 분석하여:
- Critical 이슈: 즉시 수정
- 아키텍처 변경 필요: 사용자와 논의
- 결정사항 문서화

### Step 6: 반복 개선

1. Gemini 리뷰 후 Claude가 수정 적용
2. 중대한 변경 시 다시 Gemini로 재검증:

```bash
gemini -p "이전 리뷰에서 [이슈 목록]을 지적했습니다.
수정된 변경사항을 확인해주세요:

$(git diff)" -m gemini-3.1-pro
```

3. 코드 품질 기준 충족 시까지 반복

## 명령어 참조

| 단계 | 명령어 패턴 | 목적 |
|------|-----------|------|
| 계획 검증 | `gemini -p "계획 리뷰: [계획]" -m gemini-3.1-pro` | 구현 전 로직 확인 |
| 구현 | Claude의 Edit/Write/Read 도구 | 검증된 계획 구현 |
| 코드 리뷰 | `gemini -p "리뷰: $(git diff)" -m gemini-3.1-pro` | Gemini가 구현 검증 |
| 재검증 | `gemini -p "수정 확인: $(git diff)" -m gemini-3.1-pro` | 수정 후 재확인 |
| 수정 적용 | Claude의 Edit/Write 도구 | Gemini 피드백 반영 |

## 에러 처리

1. Gemini CLI 비정상 종료 코드 시 중단
2. Gemini 피드백을 요약하고 `AskUserQuestion`으로 방향 결정
3. 아래 경우 사용자 확인 후 진행:
   - 중대한 아키텍처 변경 필요
   - 다수 파일 영향
   - 하위 호환 깨지는 변경
4. Gemini 경고 발생 시 Claude가 심각도 평가 후 다음 단계 결정

## 모범 사례

- 구현 전 **반드시 계획 검증** 수행
- 변경 후 **교차 리뷰 생략 금지**
- AI 간 **명확한 핸드오프** 유지
- **누가 무엇을 했는지** 문서화

## 루프 다이어그램

```
계획 (Claude) → 계획 검증 (Gemini) → 피드백 →
구현 (Claude) → 코드 리뷰 (Gemini) →
수정 (Claude) → 재검증 (Gemini) → 품질 충족 시까지 반복
```
