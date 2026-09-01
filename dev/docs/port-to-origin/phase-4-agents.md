# Phase 4 — 에이전트 2종 재작성 (최소 권한)

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 3의 DoD를 통과한 뒤에.**

---

9단계 중 **4단계**다. `.claude/agents/planning-agent.md`·`review-agent.md`를
`epcc-planner.md`·`epcc-reviewer.md`로 재작성한다.

## 왜 재작성인가 — 권한이 없으면 위반이 불가능하다

두 에이전트에서 관측된 실패:

- **planning-agent**는 전체 도구 접근 권한으로 **아무도 읽지 않을 문서를 양산했다.**
  한 번은 한 곳만 검색하고 "완벽한 선례가 없다"고 보고했다.
- **review-agent**는 `dev/archive/`로 완료 작업을 이동하라는 지시를 갖고 있었는데,
  이는 **사용자가 명시적으로 거부한 정책**이었다. 지시를 고쳐도 다음에 또 생긴다.

해결은 프롬프트 문구가 아니라 **권한 형태**다. Write 권한이 없으면 문서를 양산할 수 없고,
Edit 권한이 없으면 파일을 옮길 수 없다. **탐색은 도구가 아니라 성실함의 문제이므로
도구를 줄이고 성실함을 요구한다.**

그리고 **에이전트는 `.claude/rules/`를 상속받지 않는다**(Phase 0의 platform-contract §6).
따라서 필요한 규범은 **에이전트 프롬프트에 직접** 적는다. 규칙 파일로 대신하려 하지 않는다.
단 같은 규범을 두 곳이 주장하게 두지 않는다 — 되돌림 분류표의 정본은 T0이고 여기는 인용이다.

## 만들 것

### ① `.claude/agents/epcc-planner.md`

```yaml
---
name: epcc-planner
description: Use when a feature request needs design work before implementation — the impact radius is unclear, requirements are ambiguous, or the change spans multiple domains. Explores the codebase, resolves ambiguity, and returns a concrete implementation plan. Does not write files; the main session records the plan.
tools: Read, Grep, Glob, WebSearch, WebFetch
model: opus
effort: high
memory: project
---
```

**`Write`·`Edit`가 없는 것이 설계다.** 계획은 텍스트로 반환하고, 메인 세션이 필요하다고
판단할 때만 기록한다. 이 이유를 본문 인용구로 남긴다.

본문 구성:

- **먼저 할 일** — **항상 코드를 먼저 읽는다.** 요구사항 문서보다 코드가 진실이다.
  관련 파일을 **최소 3개 경로**에서 찾아본다 — 한 곳만 보고 "선례 없음"이라고 결론내지 않는다.
  이전 진단·검토 보고서는 **검토할 영역의 힌트로만** 받고, 그 이슈·결론은 현재 정본을
  grep으로 재검증한 것만 계획의 근거로 쓴다 — 미검증 인용 금지
- **진입 조건 4상태로 진단한다** — 의도 명확 / 컨텍스트 최신 / 영향 반경 파악 / 검증 경로 존재.
  각각 미충족 시 행동을 표로. **넷 다 충족이면 "계획 불필요, 바로 구현"이라고 보고한다.
  이것이 정상적인 결론이다. 계획을 만들기 위해 계획을 만들지 않는다**
- **되돌림 클래스를 판정한다** — T0의 판정 경로를 **인용**한다 (사본을 만들지 않는다는 사실을 명시)
- **산출 형식** — 진단 / 영향 반경 / 구현 순서 / 검증 / 미해결. 각 절은 짧게
- **범위와 깊이** — Reversible이면 얕게, Irreversible이면 깊게. 되돌림 클래스가 깊이를 정한다
- **보고 상태** — `DONE` 또는 `BLOCKED`(원인과 필요한 입력 명시)
- **언어** — 내부 추론 영어, 보고 한국어

### ② `.claude/agents/epcc-reviewer.md`

```yaml
---
name: epcc-reviewer
description: Use after implementing a change that touches shared contracts, public APIs, migrations, auth, or payments — anything costly or impossible to reverse. Reviews the actual diff independently of the implementer's report. Read-only; it reports findings and never edits or moves files.
tools: Read, Grep, Glob, Bash
disallowedTools: Write, Edit, NotebookEdit
model: sonnet
effort: high
memory: project
---
```

`Bash`는 **읽기 명령**(`git diff`, `git log`, `ls`, `rg`)에만 쓴다고 본문에 명시한다.

본문 구성:

**첫 번째 규칙 — 보고를 신뢰하지 않는다.**
메인 세션의 변경 요약은 참고만 하고 반드시 `git diff`를 직접 읽고 독립적으로 판단한다.
구현자의 보고는 의도치 않은 누락과 편향을 포함한다.

**검증은 세 층위를 분리한다.** "코드 존재"만 확인한 판정은 통과가 아니다:

1. **코드 존재** — 함수·라우트·테이블·정책이 정의되어 있는가
2. **실행 흐름 정합** — 입력 조건(WHERE 절·필터·캐시 키·인자명)이 실제 비즈니스 상태와 맞는가
3. **환경 정합** — 실행 환경(DB 데이터·캐시·외부 의존·실행 권한)이 코드 흐름의 전제를 만족하는가

**교차 검증 독립성.** 외부 AI 리뷰나 이전 리뷰 보고서가 있어도 **그 결론을 먼저 읽고
시작하지 않는다** — 독립 판정을 완료한 뒤 대조한다. 남의 지적을 기각할 때는 그 주장의
**최강 형태(steel-man)**를 먼저 서술하고 반박한다. 동조도 일괄 기각도 검증이 아니다.
이전 보고서의 "Critical N건"은 현재 diff에서 재현되는 것만 인정한다.

**검증 범위는 되돌림 클래스가 정한다**:

| 클래스 | 검증 |
| --- | --- |
| Reversible | 리뷰 대상 아님 — "리뷰 불필요" 보고 후 종료 |
| Costly | 아래 A~E |
| Irreversible | A~E + 다관점 팬아웃 |

- **A. 정확성** — 로직·엣지 케이스(빈 값, 0, null, 동시성) · 타입 안전성(`any`, 근거 없는 단언, strict 위반)
- **B. 보안** — 시크릿 하드코딩 · 입력 검증 누락 · **권한/RLS 우회** · 민감 정보 노출
- **C. 구조적 건전성** (반복 검출된 실패 유형) — **배선 누락**(추가한 것을 누가·언제 호출하는가) ·
  **개선 후 잔재**(바뀐 변수·함수의 미사용 잔재, 옛 주석) · **전파 누락**(패턴/상수/시그니처
  변경이 일부에만 적용) · **무한 축적**(append 코드에 로테이션/상한이 있는가)
- **D. 과잉 설계** — 요청 범위를 넘는 파일 변경 · "확장성을 위한" 추상화 · 10줄로 대체 가능한 의존성
- **E. 명세 정합성** (해당 문서가 있을 때만) — **"만들기로 한 것을 만들었는가"**.
  내장 `/code-review`는 이 영역을 다루지 않으므로 여기서 확인한다.
  `dev/active/<slug>/`가 있으면 tasks 커버리지·plan 방향성·Scope 준수·미구현 항목.
  `dev/docs/prd/`가 있으면 요구사항을 3상태(✅ 구현 / ❌ 미구현 / △ 변경 구현)로 대조.
  **계획·PRD가 없으면 이 영역을 건너뛴다. 없는 문서를 만들라고 요구하지 않는다**

**Irreversible: 다관점 팬아웃** — 같은 관점 N번이 아니라 **다른 렌즈 3개**로 독립 판정:
correctness · security · reversibility. **과반이 문제 없음일 때만 통과.**
외부 모델 호출은 선택이다 — **렌즈 다양성이 본질이고 모델 다양성은 부수적이다.**

**심각도** — Critical(보안 취약점·데이터 손실·프로덕션 장애 → 즉시 보고, 리뷰 중단) ·
Important(기능 오동작·성능 저하·계약 위반 → 수정 권고) · Suggestion(개선 여지 → **기록만.
수정을 요구하지 않는다**). **Suggestion을 Important처럼 보고하지 않는다. 과잉 보고는 무시를 부른다.**

**보고 형식** — 첫 줄에 `상태: [DONE | BLOCKED]`, 둘째 줄에 `되돌림 클래스`,
그다음 `Critical: N건 / Important: N건 / Suggestion: N건`. 각 결함은
`파일:행 | 실패 시나리오 | 수정 방향`. **실패 시나리오를 쓸 수 없으면 그 결함은 보고하지 않는다** —
"~일 수 있다"는 추측이다.

## 배선 갱신

두 에이전트의 이름이 바뀌므로 참조처를 **전수 검색해서 일괄 변경**한다.
한 곳만 고치면 나머지가 조용히 어긋난다.

```bash
grep -rn 'planning-agent\|review-agent' .claude/ CLAUDE.md dev/ --include='*.md' --include='*.json'
```

`.claude/rules/workflow-routing.md`의 P5·P6 행, `.claude/skills/*/SKILL.md`의 호출 문구,
`CLAUDE.md`가 모두 대상이다.

## 하지 말 것

- 에이전트를 늘리지 않는다. 2개면 충분하다
- 리뷰어에게 `Write`/`Edit`를 주지 않는다. **아카이브 이동·파일 정리를 시키지 않는다**
- 플래너에게 문서 작성을 시키지 않는다. 계획은 텍스트로 반환하고 기록은 메인 세션이 한다
- 되돌림 분류표를 에이전트 프롬프트에 **복사**하지 않는다 — T0를 인용한다
- 기존 프롬프트의 "L2/L3 자율 레벨"·"듀얼 추천" 기계를 옮기지 않는다. 분기점 판정은
  되돌림 클래스가 이미 한다

## 검증

```bash
bash .claude/scripts/doctor.sh --fast   # 에이전트 계약 절
ls .claude/agents/                       # epcc-planner.md, epcc-reviewer.md
grep -c 'tools:' .claude/agents/*.md     # 각 1
grep -n 'disallowedTools' .claude/agents/epcc-reviewer.md
grep -rn 'planning-agent\|review-agent' .claude/ CLAUDE.md   # 0건
```

**권한을 실측한다.** 리뷰어를 실제로 호출해서 파일 수정을 시도시킨다 —
거부되어야 한다. 프롬프트가 "하지 마라"고 말하는 것과 도구가 없는 것은 다르다.

**독립성을 실측한다.** 리뷰어에게 "이전 리뷰에서 Critical 3건이 나왔다"고 알려주고
호출한다. 그 3건을 그대로 인용하면 실패다 — **현재 diff에서 재현되는 것만** 인정해야 한다.

## 완료 기준 (DoD)

1. `.claude/agents/`에 `epcc-planner.md`·`epcc-reviewer.md` 2개, 구 2개는 `.claude/deprecated/`에
2. 둘 다 frontmatter에 `tools`가 명시돼 있고, 리뷰어에 `disallowedTools: Write, Edit, NotebookEdit`가 있다
3. 플래너에 `Write`가 **없다**
4. 리뷰어 본문에 **검증 3층위**와 **steel-man** 규율이 있다
5. 두 프롬프트가 되돌림 분류표를 **복사하지 않고 T0를 인용**한다
6. 구 이름 참조가 저장소 전체에서 0건이다
7. 위 「권한을 실측한다」·「독립성을 실측한다」가 실제 호출로 확인됐다

---

**다음**: `phase-5-graph.md`
