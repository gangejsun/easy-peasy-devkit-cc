---
name: codex-claude-loop
description: OpenAI Codex로 코드를 독립 교차검증하는 듀얼 AI 루프. Irreversible 리뷰에서 외부 모델 렌즈를 사용자가 요청·수락했을 때, 또는 사용자가 코드 품질 검증을 요청할 때 사용합니다. 소스가 외부 모델로 전송되므로 사전 동의 없이 실행하지 않습니다.
---

# Codex-Claude Engineering Loop

Claude Code가 구현하고 Codex가 검증하는 듀얼 AI 품질 보증 루프입니다.

> 공통 워크플로우(Step 1/3/4/6, 에러 처리, 모범 사례): `references/shared-workflow.md` 참조

## 실행 경로는 둘, 인증은 하나다

| 경로 | 조건 | 실행 수단 |
| --- | --- | --- |
| **플러그인 모드** (권장) | OpenAI 공식 `codex` 플러그인 설치됨 — 스킬 목록에 `/codex:setup`이 보인다 | `/codex:review` · `/codex:adversarial-review` |
| **CLI 모드** (폴백) | 플러그인 없음, `codex` CLI만 있음 | `codex exec -s read-only "…"` |

두 경로는 **같은 `codex` CLI와 같은 자격증명**(`~/.codex/auth.json`)을 쓴다. 인증은 codex
자신의 `codex login`으로만 한다 — **이 스킬은 키를 어디에도 저장하지 않는다.**

> **왜 환경변수가 아닌가** — `export OPENAI_API_KEY`는 다음 Bash 호출에 남지 않고(셸 상태
> 비보존), `~/.zshrc`에 쓰는 명령은 이 하네스의 `security-check` 훅이 "API 키 하드코딩"으로
> 차단하며, 공식 문서상 API 키는 `codex login --with-api-key`로 **로그인해야** 적용된다.
> 셋 다 재현으로 확인됐다(평가 v7 · E-45).

## 워크플로우

### Step 0: 준비 판정 — 3상태 (차단 장치 규율과 같다)

**플러그인 모드**: `/codex:setup`을 실행한다. `ready: true`면 진행. 아니면 그 출력의
`nextSteps`(설치 · `codex login`)를 사용자에게 그대로 보이고, 인증이 필요하면 아래 「인증」으로.

**CLI 모드**: 존재가 아니라 **실행**으로 판정한다 — `command -v`는 래퍼만 남고 바이너리가
없는 설치(ENOENT)를 "사용 가능"으로 오판한다.

```bash
codex --version    # exit 0 = 실행 가능. 실패면 미설치 또는 실행 불가
codex login status # exit 0 = 인증됨
```

| 판정 | 행동 |
| --- | --- |
| 실행 가능 · 인증됨 | 진행 |
| 실행 가능 · 미인증 | 「인증」 절 |
| 실행 불가 (미설치·ENOENT) | `npm install -g @openai/codex` 설치를 **사용자 확인 후** 실행. 거절하면 건너뜀 |
| **판정 불가** (오프라인·타임아웃) | **차단하지 않는다.** 사유를 명시하고 이 스킬을 건너뛴다 — 교차검증 없이 진행했음을 리뷰 보고에 적는다 |

### 인증 — `codex login`만 쓴다

`AskUserQuestion` **1회**로 방식을 고른다.

| 방식 | 명령 | 비고 |
| --- | --- | --- |
| ChatGPT 계정 (Recommended) | 사용자가 터미널에서 `codex login` (브라우저 열림) · 막히면 `codex login --device-auth` | 키 입력 없음 |
| OpenAI API 키 | 키를 입력받아 `printf '%s' "<키>" \| codex login --with-api-key` | codex가 `~/.codex/auth.json`에 보관 |

- 적용 후 **`codex login status`로 재확인**한다. exit 0이 아니면 진행하지 않는다.
- API 키를 대화로 받으면 **그 키는 대화록에 남는다** — 입력 전에 고지하고, 사용 후 회전(rotate)을 권한다.
- `~/.zshrc` · `.env` · `epcc.config.json` · `settings.json`에 키를 쓰지 않는다.

### Step 0.5: 외부 전송 동의 — 건너뛰지 않는다

이 스킬은 **코드를 저장소 밖으로 내보낸다.** 실행 전에 무엇이 나가는지 보이고 동의를 받는다.

| 전송 대상 | 범위 | 비고 |
| --- | --- | --- |
| 계획 검증(Step 2) | 계획 텍스트만 | 소스 미포함 |
| 코드 리뷰·재검증 | **`git diff` 산출물** | 전체 트리를 보내지 않는다 — diff에 한정한다 |

- 사용자가 직접 호출했더라도 **전송 범위는 고지한다**. `epcc-reviewer`는 이 스킬을
  **제안만** 하고 실행하지 않는다 — 실행은 언제나 사용자 수락 뒤다
- 시크릿·자격증명이 diff에 포함되면 중단한다 (`security-check` 훅은 파일 쓰기만 본다 —
  외부 전송은 보지 않는다)

### Step 1~4: 공통 워크플로우

`references/shared-workflow.md`의 Step 1, 3, 4를 따릅니다.

### Step 2: 계획 검증 (Codex)

**플러그인 모드**: `/codex:rescue`에 계획 텍스트를 넘기되 **읽기 전용 검토**임을 명시한다
(rescue는 기본이 쓰기 가능이다 — 검토·진단만 요청하면 읽기 전용으로 돈다)

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

**모델은 지정하지 않는다** — Codex의 기본값을 쓴다. 사용자가 요구할 때만 `-m <model>`.

### Step 5: 교차 리뷰 (Codex)

**플러그인 모드**:

- `/codex:review` — 표준 코드 리뷰 (working tree 또는 `--base <ref>`)
- `/codex:adversarial-review` — 구현 접근·설계 전제까지 의심하는 리뷰
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

Codex의 결과는 **`receiving-code-review`로 넘긴다** — 맹목 수용하지 않고 실제 코드로
사실 확인한 뒤 채택한다. Critical은 즉시 수정, 아키텍처 변경은 사용자와 논의, 결정은 문서화.

## 명령어 참조

### 플러그인 모드

| 커맨드                      | 목적                          |
| --------------------------- | ----------------------------- |
| `/codex:setup`              | 설치·인증 준비 판정 (`ready`) |
| `/codex:review`             | 표준 코드 리뷰                |
| `/codex:adversarial-review` | 설계 결정 질문 + 리스크 분석  |
| `/codex:rescue`             | 조사/수정 작업을 Codex에 위임 |
| `/codex:status`             | 백그라운드 작업 진행 확인     |
| `/codex:result`             | 완료된 작업 결과 조회         |
| `/codex:cancel`             | 활성 백그라운드 작업 중단     |

### CLI 모드

| 단계      | 명령어 패턴                                        | 목적              |
| --------- | -------------------------------------------------- | ----------------- |
| 준비 판정 | `codex --version && codex login status`            | 실행 가능·인증됨  |
| 인증      | `codex login` · `printf '%s' "<키>" \| codex login --with-api-key` | ChatGPT · API 키 |
| 계획 검증 | `codex exec -s read-only "계획 리뷰: [계획]"`      | 구현 전 로직 확인 |
| 코드 리뷰 | `codex exec -s read-only "리뷰: $(git diff)"`      | Codex가 구현 검증 |
| 재검증    | `codex exec -s read-only "수정 확인: $(git diff)"` | 수정 후 재확인    |

### CLI 주요 플래그

| 플래그         | 용도                                           |
| -------------- | ---------------------------------------------- |
| `-s read-only` | 읽기 전용 샌드박스 (검증 시 기본)              |
| `-m <model>`   | 모델 지정 — 사용자가 요구할 때만               |
| `--json`       | JSON 형식 출력 (파이프라인 연동 시)            |
| `-o <path>`    | 결과를 파일로 저장                             |
