---
name: codex-claude-loop
description: |
  Claude Code가 설계/구현하고 OpenAI Codex가 검증/리뷰하는 듀얼 AI 엔지니어링 루프를 오케스트레이션합니다.
  review-agent의 P6(TDD 검증) 조건 충족 시 사용자 확인 후 호출되거나, 사용자가 코드 품질 검증을 요청할 때 사용하세요.
---

# Codex-Claude Engineering Loop

Claude Code가 구현하고 Codex가 검증하는 듀얼 AI 품질 보증 루프입니다.

> 공통 워크플로우(Step 1/3/4/6, 에러 처리, 모범 사례): `references/shared-workflow.md` 참조

## 전제조건

### 방법 A: Claude Code 플러그인 (권장)

1. 플러그인 설치 확인: 스킬 목록에 `codex-claude-loop`이 표시되면 준비 완료
2. 미설치 시: `/plugin marketplace add openai/codex-plugin-cc` → `/plugin install codex@openai-codex`

### 방법 B: Codex CLI (플러그인 미사용 시)

- **설치**: `npm install -g @openai/codex` 또는 [공식 설치 가이드](https://github.com/openai/codex)
- **확인**: `codex --version`

### API 키 설정

스킬 실행 시 `OPENAI_API_KEY` 환경변수를 확인합니다.

1. **키가 있으면**: 그대로 진행
2. **키가 없으면**: `AskUserQuestion`으로 사용자에게 OpenAI API 키를 요청
3. **키를 받으면**: 아래 명령으로 현재 세션 + 영구 저장하여 다시 묻지 않음

```bash
export OPENAI_API_KEY="<사용자가 입력한 키>"
grep -q 'OPENAI_API_KEY' ~/.zshrc 2>/dev/null || echo 'export OPENAI_API_KEY="<키>"' >> ~/.zshrc
```

미설정 시 사용자에게 안내 후 이 스킬을 건너뜁니다.

## 워크플로우

### Step 0: 환경 확인

```bash
if [ -z "$OPENAI_API_KEY" ]; then
  echo "OPENAI_API_KEY 미설정 — 사용자에게 키 요청 필요"
fi
command -v codex >/dev/null 2>&1 && echo "Codex CLI 사용 가능" || echo "CLI 미설치 — 플러그인 모드 사용"
```

### Step 1~4: 공통 워크플로우

`references/shared-workflow.md`의 Step 1, 3, 4를 따릅니다.

### Step 2: 계획 검증 (Codex)

**플러그인 모드**: `/codex:review` 또는 `/codex:adversarial-review` 슬래시 커맨드 사용

**CLI 모드**:

```bash
codex exec -s read-only "다음 구현 계획을 검토하고 문제점을 식별해주세요:

[Claude의 계획]

검토 항목:
- 로직 오류
- 누락된 엣지 케이스
- 아키텍처 결함
- 보안 우려사항"
```

**기본 모델**: `o4-mini` (변경 시 `-m <model>` 플래그 사용)

### Step 5: 교차 리뷰 (Codex)

**플러그인 모드**:

- `/codex:review` — 표준 코드 리뷰
- `/codex:adversarial-review` — 심층 리뷰
- 비동기: `/codex:status`로 진행 확인, `/codex:result`로 결과 조회

**CLI 모드**:

```bash
codex exec -s read-only "다음 코드 변경사항을 리뷰해주세요:

$(git diff)

검토 항목:
- 버그 탐지
- 성능 이슈
- 모범 사례 준수
- 보안 취약점"
```

Claude가 Codex의 피드백을 분석하여:

- Critical 이슈: 즉시 수정
- 아키텍처 변경 필요: 사용자와 논의
- 결정사항 문서화

## 명령어 참조

### 플러그인 모드

| 커맨드                      | 목적                          |
| --------------------------- | ----------------------------- |
| `/codex:review`             | 표준 코드 리뷰                |
| `/codex:adversarial-review` | 설계 결정 질문 + 리스크 분석  |
| `/codex:rescue`             | 조사/수정 작업을 Codex에 위임 |
| `/codex:status`             | 백그라운드 작업 진행 확인     |
| `/codex:result`             | 완료된 작업 결과 조회         |
| `/codex:cancel`             | 활성 백그라운드 작업 중단     |

### CLI 모드

| 단계      | 명령어 패턴                                        | 목적              |
| --------- | -------------------------------------------------- | ----------------- |
| 계획 검증 | `codex exec -s read-only "계획 리뷰: [계획]"`      | 구현 전 로직 확인 |
| 코드 리뷰 | `codex exec -s read-only "리뷰: $(git diff)"`      | Codex가 구현 검증 |
| 재검증    | `codex exec -s read-only "수정 확인: $(git diff)"` | 수정 후 재확인    |

### CLI 주요 플래그

| 플래그         | 용도                                           |
| -------------- | ---------------------------------------------- |
| `-s read-only` | 읽기 전용 샌드박스 (검증 시 기본)              |
| `-m <model>`   | 모델 지정 (기본: o4-mini)                      |
| `--json`       | JSON 형식 출력 (파이프라인 연동 시)            |
| `-o <path>`    | 결과를 파일로 저장                             |
| `--full-auto`  | 자동화 모드 (workspace 쓰기 + on-request 승인) |
