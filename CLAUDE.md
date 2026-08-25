# CLAUDE.md

`easy-peasy-devkit-cc` — Claude Code 플러그인의 **소스 저장소**다. 소비자 프로젝트가 아니다.
여기에 `epcc.config.json`·`dev/active/`·스택 가이드를 만들지 않는다. `rules/`는 소비자에게
배포될 자산이지 여기서 자동 로드되는 설정이 아니다 — 그래서 이 파일이 필요하다.

## 작업 전에 읽을 것

정본은 아래 파일들이다. **여기에 옮겨 적지 않는다** (사본은 드리프트 원천이다).

| 언제 | 읽을 것 |
| --- | --- |
| 훅·규칙·스킬·에이전트·스크립트를 건드릴 때 | `rules/harness-change.md` |
| 모든 작업의 기본 계약 | `templates/operating-contract.md` |
| 코드 변경 일반 | `rules/code-change.md` |
| 되돌림 클래스 판정과 5단계 | `rules/reversibility.md` |
| 결함·교훈 기록 | `rules/lessons.md` |

## 이 저장소 고유 사실

**버전은 4곳을 동시에 올린다** — `plugin.json` · `package.json` · `README.md` 배지 · `marketplace.json`(2군데). doctor가 대조한다.

**스크립트 배치** — 스킬 전용이면 `skills/<스킬>/scripts/`에 두고 **`${CLAUDE_SKILL_DIR}`**로 호출한다 (자작 표기는 치환되지 않아 소비자에서 실패 — doctor가 검출).
루트 `scripts/`는 훅·doctor·**설치기**(`install-rules.sh`·`install-guide.sh`) 전용이다. 여기
두면 ⓐ doctor 자기 lint가 검사 스크립트의 정규식 문자열을 오탐하고 ⓑ 이중 루트 전제와 어긋난다.

**셸 규약** — 훅은 `scripts/lib/common.sh`를 source한다. **검사 스크립트는 하지 않는다**:
`set -Eeuo pipefail`과 ERR trap이 "모든 검사를 끝까지 돌린다"는 정책과 충돌한다. 대신
`scripts/doctor.sh`의 `ok/warn/bad/sec` + `num()` + 종료 코드 0/1/2 + `--help`=헤더 주석을
**복사**하고 `return 0`을 명시한다 (원본 `bad`/`warn`은 `$2`가 비면 반환값이 1이다).

**가이드는 스킬이 아니라 `guides/` 자산이다** — 사전 제작 단위가 조합(32)이 아니라 축
(프론트 5 · 백엔드 8)이라서다. **팩 리소스를 고치면 `ledger.md`·`pack.json`·`policies.md`도
함께 본다** — 팩 단독 검증은 `guide-gate.sh --pack`, 실행 검증은 `pack-smoke.sh`이고 정책
표의 `증명 예`와 `fixesVariants`는 **의무**다(누락 시 FAIL). 계약(`seams/*/contract.md`)의
**값은 목록·표 행에만** 쓴다: 산문의 백틱은 설명이고, 부정문을 목록에 쓰면 양쪽 요구가 된다.

**차단 장치를 만들었으면 차단을 증명한다** — 결함을 심은 픽스처가 실제로 exit 1을 받는지,
그리고 **의도한 이유로** 받는지 확인한다(`EPCC_FX_WHY=1`). 살아있음 ≠ 작동함이다.

## 변경 후 필수

```bash
bash scripts/doctor.sh --fast && bash scripts/doctor.sh --self-test
bash scripts/doctor.sh --consumer   # 훅·설치기를 건드렸으면 — 소비자 레이아웃 실증
# 가이드 하네스를 건드렸으면. 버전 올릴 때는 --self-test 대신 --regress (출하 자산 회귀)
bash skills/stack-guide-generator/scripts/guide-gate.sh --self-test
bash skills/stack-guide-generator/scripts/pack-smoke.sh --self-test
```

## 커밋

사용자가 요청할 때만 커밋한다. 메시지 끝에 트레일러를 붙인다:
`Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

## 실사용 검증은 여기서 할 수 없다

이 저장소에는 소비자가 없다. 따라서 **규칙이 소비자 프로젝트에 도달하는지는 여기서 확인할
수 없다.** 신규 프로젝트에 플러그인을 설치해 검증할 때 `.claude/rules/`에 T1 카드가 실제로
설치됐는지 반드시 확인한다 — v2가 4개월간 놓친 것이 정확히 이 한 가지다.
