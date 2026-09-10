---
name: pr-prep
description: 변경을 PR/MR로 낼 수 있게 준비합니다 — diff 수집, 되돌림 클래스 판정, 검증 명령 실행, 클래스가 요구하는 섹션(롤백 절차·호출처·개입 근거)을 갖춘 본문 생성. 사용자가 "PR 준비", "MR 준비", "PR 올려줘", "PR 본문"을 요청할 때 사용합니다.
---

# PR Prep

**본문은 요약이 아니라 리뷰어가 판단하는 데 필요한 것의 목록이다.**

> **경계** — diff의 결함을 찾는 것은 내장 `/code-review`, 계약·명세 정합을 보는 것은
> `epcc-reviewer`, 문서를 최신화하는 것은 `/completion-review`다. 이 스킬은 그 셋이
> 만들지 않는 **변경 요청 본문과 그 전제 조건**을 맡는다. 코드를 고치지 않는다 — 결함을
> 발견하면 보고하고 build로 되돌린다.

**호스트 판정** — `epcc.config.json`의 `techStack.vcsPlatform`을 읽는다. 없으면
`git remote get-url origin`에 `github.com`/`gitlab.com`이 있는지 본다. 그래도 불명이면
**사용자에게 묻는다** — Step 6까지는 어느 쪽이든 같으므로, 물어야 할 시점은 Step 7이다.
GitHub는 PR, GitLab은 MR이다.

## Step 1: 무엇이 바뀌었는가

```bash
git rev-parse -q --verify HEAD >/dev/null 2>&1 || { echo "커밋 0개 — PR 대상 없음"; exit; }
git rev-parse --abbrev-ref HEAD
git log --oneline "$(git merge-base HEAD main 2>/dev/null || echo HEAD~1)"..HEAD
git diff "$(git merge-base HEAD main 2>/dev/null || echo HEAD~1)"..HEAD --stat
```

기준 브랜치가 `main`이 아닌 저장소가 있다. `git symbolic-ref refs/remotes/origin/HEAD`로
확인하고, 없으면 사용자에게 묻는다 — **추측한 기준으로 만든 diff는 틀린 PR을 만든다.**

**현재 브랜치가 기준 브랜치면 멈춘다.** 브랜치를 먼저 만들어야 하고, 그건 사용자 결정이다.

## Step 2: 되돌림 클래스 판정

판정표의 정본은 세션 시작 시 주입되는 **T0 운영 규칙의 「되돌림 분류」**다.
여기에 옮겨 적지 않는다. 변경 **경로**로 판정한다 — diff 줄 수로 판단하지 않는다.

둘 이상에 해당하면 높은 쪽을 따른다. 애매하면 Costly로 본다.

## Step 3: 클래스가 본문 섹션을 정한다

| 클래스 | 본문에 **의무** |
| --- | --- |
| Reversible | Summary · Changes · Tests |
| Costly | + **영향 반경** — 호출처 목록 (grep으로 실제 확인한 것만) |
| Irreversible | + **롤백 절차** — 실패했을 때 되돌리는 구체적 순서, 데이터 손실 지점 |

`.claude/**` · `scripts/**` · `hooks/**` · `rules/**` · `agents/**` · `skills/**`를
건드렸으면 **개입 근거 2줄**이 추가 의무다 (`.claude/rules/harness-change.md`):

- (a) **막으려는 실패** — 2회 이상 반복 관측된 것
- (b) **잘 되던 것을 망칠 위험**

(a)를 못 쓰면 그것은 가설이지 패턴이 아니다. 그 사실을 본문에 적거나, 변경을 되돌린다.

**의무 섹션을 채울 수 없으면 미완성이다.** 빈 제목만 남기고 넘어가지 않는다 —
"롤백 절차: (없음)"인 Irreversible 변경 요청은 리뷰어가 판단할 근거가 없다.
그 상태를 보고하고 멈춘다.

## Step 4: 검증을 실제로 돌린다

`epcc.config.json`의 `techStack.commands`(빌드·테스트·린트)를 **실행하고 결과를 본문에 적는다.**
"작성했다"는 "작동한다"가 아니다.

| 결과 | 본문 표기 |
| --- | --- |
| 통과 | 명령 + `✓` |
| 실패 | 명령 + 실패 출력 요약. **PR/MR을 만들지 않고 보고한다** |
| 명령 없음 | 「검증 경로 없음」 + 수동 확인 절차. 통과로 적지 않는다 |

세 번째를 통과로 적는 것이 가장 흔한 거짓말이다. 없는 것을 있다고 쓰지 않는다.

## Step 5: 선행 결정 인용

`docs/decisions.md`에 이 변경과 관련된 결정이 있으면 Decisions 줄에 인용한다
(형식 정본은 `.claude/rules/reversibility.md`).

인용하기 전에 **현재 정본으로 재검증한다** — 결정 이후 코드가 바뀌었을 수 있다
(`.claude/rules/workflow-routing.md` 「참조 신선도」). 재검증하지 않은 인용은 넣지 않는다.

## Step 6: 본문

```md
## Summary
<왜 이 변경이 필요한가 — 무엇을 했는가가 아니라>

## Changes
- <파일군> — <무엇이 어떻게>

## Tests
- <명령> — <결과>

## Risks / Notes
- <되돌림 클래스> — <근거 경로>
- <알려진 한계 · 범위에서 뺀 것>

## Rollback            ← Irreversible 의무
1. <되돌리는 순서>
- 데이터 손실 지점: <있으면 명시, 없으면 「없음」>

## Impact              ← Costly 이상 의무
- 호출처: <grep으로 확인한 목록>

## Intervention        ← 하네스 경로 변경 시 의무
- 막으려는 실패: <2회 이상 관측된 것>
- 망칠 위험: <잘 되던 것>
```

빈 섹션은 **넣지 않는다.** 해당 없는 섹션이 제목만 남아 있으면 리뷰어는 그것을
누락으로 읽는다.

## Step 7: 제안까지만

본문을 사용자에게 보여주고 **확인을 받은 뒤에** 명령을 실행한다.
PR/MR 생성은 저장소 밖으로 나가는 발신이다 — 되돌리려면 사람의 손이 필요하다.

**GitHub**

```bash
gh pr create --base <기준> --title "<제목>" --body-file <파일>
```

**GitLab** — 기본은 push 옵션이다. 별도 CLI 설치·인증이 필요 없다.

```bash
git push -o merge_request.create \
         -o merge_request.target=<기준> \
         -o merge_request.title="<제목>" origin HEAD
```

push 옵션은 제목과 대상 브랜치까지만 안정적으로 싣는다. **본문 파일은 어느 경로에서든
그대로 만든다** — 그것이 이 스킬의 산출물이다. 생성된 MR에 사용자가 붙여넣도록 경로를
알려주고, 사용자가 `glab`을 원하면 그때 쓴다:

```bash
glab mr create --target-branch <기준> --title "<제목>" --description-file <파일>
```

호스트가 끝내 판정되지 않으면 **본문 파일까지만 만들고 멈춘다.** 어느 쪽 명령도
추측해서 실행하지 않는다.

푸시가 필요하면 **강제 푸시를 쓰지 않는다.** 필요해 보이면 그 이유를 먼저 보고한다 —
공유 브랜치 강제 푸시는 `security-check` 훅이 차단한다.

## 상한

Changes는 **파일군 단위로 최대 12행**이다. 파일을 전부 나열하지 않는다 —
`--stat`이 이미 하는 일이고, 리뷰어가 읽는 것은 묶음의 의미다.
넘으면 커밋이 너무 크다는 신호이므로, 나누자고 제안한다.
