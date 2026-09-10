---
name: fix-issue
description: 이슈 트래커 기반 버그 수정 (이슈 컨텍스트 자동 주입). 사용자가 "이슈 수정", "fix issue", "fix #123", "이슈 해결" 등을 요청할 때 사용합니다. 이슈 번호가 제공되면 gh(GitHub)·glab(GitLab) CLI로 컨텍스트를 자동 수집합니다. 수동 호출 전용.
disable-model-invocation: true
---

# Fix Issue

이슈의 컨텍스트를 자동 수집하여 버그 수정 워크플로우에 주입합니다.

**호스트 판정** — `epcc.config.json`의 `techStack.vcsPlatform`을 읽는다. 없으면
`git remote get-url origin`에 `github.com`/`gitlab.com`이 있는지 본다. 그래도 불명이면
사용자에게 묻는다. GitHub는 PR, GitLab은 MR이고 **MR 참조 기호는 `#N`이 아니라 `!N`**이다.

## 워크플로우

### Step 1: 이슈 컨텍스트 수집

이슈 번호를 확인하고 호스트의 CLI로 정보 수집:

```bash
# GitHub
gh issue view <NUMBER> --json title,body,labels,assignees,comments
gh pr list --search "<NUMBER>" --json number,title,state      # 관련 PR (있으면)

# GitLab
glab issue view <NUMBER> --output json
glab mr list --search "<NUMBER>"                              # 관련 MR (있으면)
```

추출할 정보:

- **제목**: 이슈 핵심 요약
- **본문**: 재현 단계, 기대 동작, 실제 동작
- **라벨**: bug/feature/priority 분류
- **코멘트**: 추가 컨텍스트, 디버깅 시도

### Step 2: 재현 조건 파악

이슈 본문에서 다음을 식별:

| 항목        | 추출 대상                         |
| ----------- | --------------------------------- |
| 재현 단계   | Steps to Reproduce 또는 순서 목록 |
| 기대 동작   | Expected Behavior                 |
| 실제 동작   | Actual Behavior                   |
| 환경 정보   | 브라우저, OS, 버전 등             |
| 에러 메시지 | 스택 트레이스, 콘솔 로그          |

정보가 부족한 경우: 사용자에게 보충 요청 (추측하지 않음).

### Step 3: 관련 코드 탐색

이슈에서 파악한 키워드, 에러 메시지, 파일 경로를 기반으로:

1. **에러 메시지 기반**: Grep으로 에러 문자열 검색
2. **도메인 기반**: 이슈 라벨/제목에서 도메인 추론 → 해당 디렉토리 탐색
3. **스택 트레이스 기반**: 언급된 파일:행 직접 읽기

### Step 4: 진단 — 재현 루프

이슈 본문의 재현 단계는 **읽은 것**이지 **돌려본 것**이 아니다.
`.claude/rules/code-change.md`의 「버그를 고칠 때 — 재현 루프가 가설보다 먼저다」를
그대로 따른다 (판정 기준은 그 카드가 정본이다):

빨갛게 되는 명령 하나를 실제로 실행 → 최소화 → 반증 가능한 가설 3~5개 →
한 번에 한 변수 계측 → 올바른 이음매가 있으면 회귀 테스트 먼저.

**멈춤 조건** — 루프를 못 만들면 추측으로 넘어가지 않는다.
시도한 것을 적고 이슈 작성자에게 재현 환경이나 캡처 아티팩트(HAR·로그 덤프·녹화)를 요청한다.
이슈 코멘트에 붙은 로그는 시크릿이 섞여 있을 수 있다 — 인용 시 `<REDACTED>`로 가린다.

### Step 5: 수정 및 검증

이 시점부터 일반 build(구현) 단계 규칙을 따름 (코드 변경 카드가 편집 시 자동 로드됨):

1. 확인된 가설에 근거해 수정
2. `/simplify` 코드 정리
3. `pnpm build && pnpm test` 검증 + Step 4의 루프를 다시 돌려 초록 확인
4. `[DEBUG-` 계측 전수 제거 확인

### Step 6: 결과 보고

```
이슈 수정 보고서
===============

이슈: #<NUMBER> — <제목>
재현 루프: [실제로 실행한 명령 한 줄]
근본 원인: [확인된 가설 — 1-2줄]

수정 파일:
- <파일경로>: [변경 내용 요약]

검증:
- 빌드: [PASS/FAIL]
- 테스트: [PASS/FAIL]
```

## 이슈 번호 없이 호출된 경우

이슈 번호가 제공되지 않으면:

1. 열린 버그 이슈 목록 표시 — GitHub는 `gh issue list --state open --label bug`,
   GitLab은 `glab issue list --state opened --label bug`
   (GitLab의 상태값은 `open`이 아니라 **`opened`**다)
2. 사용자에게 이슈 선택 요청
3. 선택 후 Step 1부터 진행

## 주의사항

- 호스트 CLI(`gh` 또는 `glab`) 인증이 필요 — 미설치/미인증 시 사용자에게 안내하고,
  이슈 내용을 직접 붙여넣게 해서 Step 2부터 진행한다
- 이슈 컨텍스트를 100% 신뢰하지 않음 — 코드에서 직접 확인 필수
- 이슈에 명시된 범위만 수정 — 관련 없는 리팩토링/개선 금지
