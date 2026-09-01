# Phase 3 — 규칙 14개(1,707줄) → 9개 3계층

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 2의 DoD를 통과한 뒤에.**

---

9단계 중 **3단계**다. 이 단계가 개편의 본체다.

## 무엇이 틀렸는가

v2 규칙 체계의 문제는 분량이 아니라 **축이 틀린 것**이다.

1. **규모(S/M/L)로 분류한다.** 규모는 사람 판단을 요구해 드리프트하고, **틀린 변수를 본다** —
   5줄 마이그레이션이 400줄 리팩토링보다 위험하다. 올바른 축은 **되돌림 가능성**이다.
2. **Phase 번호가 의무를 만든다.** P0~P6이 순서가 아니라 관문으로 읽혀 이미 아는 것을 적기
   위한 PRD·계획서가 생산됐다. 번호는 순서를 표시할 뿐 의무가 아니다.
3. **로드 시점이 뒤집혀 있다.** `self-improvement.md`가 `docs/lessons.md`에 걸려 있으면
   이미 기록하러 간 뒤에야 로드된다. `freshness-check.md`는 이전 작성물을 **인용하는 시점**에
   필요한데 그 시점은 `src/**` 편집과 무관하다.
4. **같은 규범을 여러 파일이 주장한다.** 사본은 드리프트 원천이다.

## 3계층 구조

| 계층 | 무엇 | 로드 | 예산 |
| --- | --- | --- | --- |
| **T0** 운영 규칙 | 되돌림 분류 · 작업 진입 4상태 · 최소 수정 · 검증 · 분기점 · 언어 | 매 세션 무조건 | **40줄** |
| **상시** | 작업 라우팅(Phase 표) · 참조 신선도 4축 | 매 세션 무조건 (`paths` 없음) | ~60줄 |
| **T1 카드** | 편집 경로별 조건부 | `paths:` 매칭 파일을 **읽을 때** | 카드당 50~90줄 |

`.claude/rules/`는 **Claude Code 네이티브 기능**이다(Phase 0의 platform-contract §3).
`paths:` 없음 → 매 세션 무조건 로드. `paths:` 있음 → 매칭 파일을 읽을 때.
**이 저장소에는 배포 경계가 없으므로 설치기가 필요 없다** — 파일을 놓으면 그것이 곧 도달이다.

> **T0를 훅으로도 출력할 것인가?**
> 출처 저장소는 플러그인이라 규칙을 배포할 수 없어서 SessionStart 훅으로 출력했다.
> 여기서는 `paths` 없는 규칙 파일 하나면 충분하다. **`.claude/rules/operating-contract.md`를
> 정본으로 삼고 `session-brief.sh`에서는 T0 출력 절을 뺀다.** 둘 다 하면 같은 내용이
> 두 번 상주하고, 사본은 드리프트 원천이다. Phase 2의 `session-brief.sh` ①번 절을 지금 정리한다.

## 폐기·흡수 매핑 (14 → 9)

**폐기는 `.claude/deprecated/`로 이동이다.** 만료일 14일. 흡수 대상이 실제로 그 내용을
담았는지 확인하기 전에 지우지 않는다.

| 기존 (14개, 1,707줄) | 처분 |
| --- | --- |
| `task-workflow.md` (97) · `task-workflow-detail.md` (187) | → **`workflow-routing.md`**(Phase 표) + **`reversibility.md`**(단계·워크스페이스). 번호를 의무에서 순서 표시로 강등 |
| `modification-guardrails.md` (150) | → **`code-change.md`**(최소 수정·자가 점검) + **`harness-change.md`**(하네스 변경 3-질문) |
| `decision-autopilot.md` (97) · `decision-autopilot-detail.md` (72) | → **T0의 「분기점」 절 6줄**. L2/L3 자율 레벨과 듀얼 추천 기계는 폐기 — 분기점 판정은 되돌림 클래스가 이미 한다. `dev/docs/digital-twin/` 축적은 유지하되 **읽는 노드가 없으면 폐지 검토**(Phase 8) |
| `self-improvement.md` (162) | → **`lessons.md`**(기록·승격) + Phase 8의 평가 스킬. **집계는 규칙이 아니라 doctor가 한다** |
| `freshness-check.md` (79) | → **`workflow-routing.md`의 「참조 신선도」 절**. `paths`를 붙이면 안 되는 대표 사례다 |
| `doc-dependency-sync-detail.md` (72) | → **`doc-dependency.md`** (6-edge 표 유지) |
| `agent-governance.md` (84) | → **`harness-change.md`의 「에이전트 예외」 절**. 에이전트는 `.claude/rules/`를 상속받지 않으므로 규범은 에이전트 프롬프트에 직접 적는다 |
| `claude-md-authoring.md` (89) | → **`harness-change.md`**로 흡수 (문서 저작 규약) |
| `data-modeling.md` (456) | **유지.** `paths`를 `supabase/**`·`packages/shared/src/types/**`·`dev/docs/database/**`로 그대로. 이것은 실전 검증된 자산이다 |
| `project-structure.md` (65) | **유지.** 모노레포 구조 카드 |
| `code-conventions.md` (43) | **유지.** |
| `security.md` (54) | **유지·개편** — 훅이 원리적으로 못 잡는 것만 남긴다 (아래) |

## 만들 것

### ① `.claude/rules/operating-contract.md` — T0, `paths` 없음, **40줄 예산**

머리에 유지자 주석(블록 HTML 주석은 컨텍스트 주입 전에 제거되므로 안전):

```
<!-- T0 상시 규범. 예산 40줄(doctor --fast가 강제).
     되돌림 클래스의 **정본은 아래 표** — 다른 카드·에이전트·README는 인용이다. -->
```

본문 6절:

**되돌림 분류** — 경로로 판정한다. 규모(줄 수·파일 수)로 판단하지 않는다.
검증 강도와 **실행자**를 이 표가 정한다.

| 클래스 | 판정 경로 | 요구 — 누가 하는가 |
| --- | --- | --- |
| Irreversible | `supabase/migrations/**` · auth/RLS · **Toss Payments 결제·정산** · 운영 데이터 | `epcc-reviewer` 다관점 팬아웃 + **사용자 확인** + 롤백 절차 |
| Costly | `packages/shared/**` · public API · 타입 계약 · `**/api/**` · `**/actions.ts` · `**/middleware.ts` · 생성 파일 | `epcc-reviewer` 필수 — **자기 리뷰로 대체하지 않는다** |
| Reversible | 그 외 전부, 테스트 코드 포함 (기본값) | 바로 진행. 마무리 문서화는 `/completion-review` |

> 판정 경로는 이 저장소의 실제 구조에 맞춘다 — 위 값은 모노레포(루트 Next.js 앱 +
> `packages/shared`) + Supabase + Toss Payments 기준이다.

**작업 진입** — 넷이 모두 충족되면 준비 작업 없이 바로 구현한다.
의도 명확 · 컨텍스트 최신 · 영향 반경 파악 · 검증 경로 존재.
미충족 항목만 채운다 — **충족된 항목을 위한 문서를 만들지 않는다.**
2개 이상 미충족이거나 영향 반경이 불명확하면 `epcc-planner`에 진단을 위임한다.

**최소 수정** — 요청된 것만 구현한다. 범위 밖 파일 수정이 필요하면 멈추고 확인한다.
리팩토링·추상화·의존성 추가는 별도 요청 없이 하지 않는다. "나중에 필요할 수 있으니"는 근거가 아니다.

**검증** — 소스를 고쳤으면 빌드/테스트까지가 한 동작이다. **"작성했다"는 "작동한다"가 아니다.**
스크립트·훅을 추가·수정하면 실제 실행 → exit 0 확인 → 예상 출력 확인까지 수행한다.

**분기점** — 결정의 결과가 되돌리기 어렵거나 사용자 워크플로우에 영향을 주면,
선택지와 **선택 간 실질 차이**를 제시하고 사용자가 고르게 한다.
사소한 결정은 스스로 정하고 진행한다 — 매 결정마다 묻지 않는다.

**언어** — 내부 추론은 영어, 사용자 출력은 한국어.

**더 읽을 것** (필요할 때만) — `src/**` 수정 → `code-change.md` · `.claude/**`·`scripts/**` 수정 →
`harness-change.md` · 사용자가 접근을 지적함 → `lessons.md`

### ② `.claude/rules/workflow-routing.md` — 상시, **`paths` 금지**

머리 주석에 이유를 남긴다:

```
<!-- **paths: 프론트매터를 넣지 마세요.** 넣는 순간 조건부 로딩으로 바뀌어 세션 시작 시
     뜨지 않습니다. 이 카드는 "작업을 시작하기 전"에 필요하므로 어떤 파일도 아직 열지
     않은 시점에 이미 로드되어 있어야 합니다. doctor --fast가 이 파일에 paths가 생기면 실패시킵니다. -->
```

**두 축이 직교한다** — 이 표가 *무엇을 어떤 순서로 만들지*를, 되돌림 클래스가
*얼마나 검증할지*를 정한다.

작업 유형 → Phase 순서 표: 신규 기능(PRD 없음) `P0→P1→P2→P3→P4→P5` · 신규 기능(PRD 있음)
`P3→P4→P5` · 기존 기능 확장/수정/삭제 `P4→P5` · 버그 수정 `P4→P5` · 리팩토링 `P3→P4→P5` ·
문서/도구/탐색 미적용(단 `dev/docs/prd/` 수정 시 `/prd-reviewer`).

Phase → 발동 조건 → 호출 표: 이 저장소에 실재하는 스킬로 채운다 (`/brainstorming`·`/research`·
`/business-planner`·`/service-planner`·`/council-review`·`/prompt-enhancer`·`/prd-generator`·
`/dev-docs-generator`·`/completion-review`·`epcc-reviewer`).
**P5는 되돌림 클래스가 강도를 정한다** — Reversible → `/completion-review`, Costly 이상 → `epcc-reviewer`.

그리고 **진입 조건 4상태가 모두 충족되면 P0~P3을 건너뛴다. 번호는 순서를 표시할 뿐 의무가 아니다.**

**「참조 신선도」 절** (이 절이 상시인 이유를 본문에 적는다: 이전 코드·문서·SQL·리뷰 보고서를
인용하는 시점은 `src/` 편집과 무관하다. 조건부로 두면 정작 필요한 순간에 없다):

1. 사용 중단된 이름·패턴의 잔재가 아닌가
2. 정본은 진화했는데 인용본(타입·미러·fragment)이 멈춰 있지 않은가 — **base는 진화 체인의 말단이다**
   (DB 함수는 최초 정의가 아니라 가장 최근 `OR REPLACE` 본문)
3. 같은 정보가 여러 곳에 있을 때 정본(SSOT) 방향이 그대로인가 — 미러는 통째 복사하지 않고 변경 섹션만
4. 도구·라이브러리 **메이저 버전 업그레이드 후**에도 같은 패턴이 유효한가

> 이전 진단·리뷰 보고서는 **검토 영역의 힌트로만** 받는다. "Critical N건"이라 적혀 있으면
> N건이 여전히 미해결인지 현재 정본을 grep으로 하나씩 재검증한 것만 채택한다.

위반 시그널("이미 갱신된 항목의 회귀" 지적, "이전에 처리한 것 같은데")은
`docs/lessons.md`에 `[category: freshness]`로 기록한다.

### ③ T1 카드 7장

각 카드 머리에 `<!-- epcc-rule-version: 3.0.0 -->` 스탬프를 넣는다 (doctor가 검사).

| 카드 | `paths:` | 핵심 |
| --- | --- | --- |
| `code-change.md` | `src/**` `app/**` `packages/**` `lib/**` | 변경 후 역추적(grep으로 미사용 잔재 정리) · 동일 패턴 전파 · **배선 확인(존재 ≠ 실행)** · 공유 경계(`packages/shared` 수정 전 소비처 전수 grep + 사용자 확인) · 검증까지가 한 동작 · **의존성 추가 전 5단계 점검**(출처·이력·의존성 트리·커뮤니티·audit — Critical/High면 설치 중단 후 보고. 10줄로 대체 가능하면 추가하지 않는다) · 자가 점검 3문 |
| `harness-change.md` | `.claude/**` `scripts/**` | 아래 별도 |
| `reversibility.md` | `src/**` `app/**` `packages/**` `supabase/**` `**/migrations/**` `dev/active/**` | 클래스 판정 **이후**를 담는다(판정표 정본은 T0, 여기 옮겨 적지 않는다) · **접근 정책 분기점**(라우트 가드 추가/이동/제거, 라우트 그룹 신설, `middleware.*` 가드 분기, 비인증 노출 정책 — 코드 변경으로 보여도 본질은 UX/접근 정책 결정이므로 auth 축=Irreversible) · 진입 조건 4상태 표 · **단계(번호 없음)**: understand/plan/build/verify/cross-check · 워크스페이스는 세션을 넘어갈 때만, 종결은 `dev/archive/`로 **이동**해서 증명 · cross-check 다관점 팬아웃(correctness·security·reversibility, 과반 통과) |
| `lessons.md` | `src/**` `app/**` `packages/**` `lib/**` `.claude/**` `scripts/**` `dev/docs/**` `docs/lessons.md` | 아래 별도 |
| `security.md` | `src/**` `app/**` `packages/**` `lib/**` | 아래 별도 |
| `doc-dependency.md` | `dev/docs/{prd,database,design,architecture,api}/**` | 6-edge 의존성 그래프 표 · 불일치 발견 시 분기점(지금 갱신 vs TODO 분리) · 완료 기준 · **면제(Semantic Materiality)**: 오탈자·어휘 통일·포맷은 면제, **필드명/상태값/엔티티 네이밍/비즈니스 규칙/API 계약/스키마 컬럼은 면제 불가** · **PRD 수정 시 `/prd-reviewer` 트리거가 이 카드다** |
| `data-modeling.md` | (기존 유지) | 내용 유지. 버전 스탬프만 추가 |

#### `harness-change.md` 상세

- **추가 전 3-질문**: Q1 기존 훅/규칙/스킬/**Claude Code 빌트인**과 겹치는가 · Q2 모델 성능
  향상으로 이제 불필요한 것 아닌가 · Q3 이미 잘 동작하는 것을 굳이 바꾸는 건 아닌가.
  하나라도 YES면 중단. **Q1의 빌트인은 실제로 확인한다** — `/code-review`·`/simplify`·
  `/security-review`·`skill-creator`·`/init`·`/run`·`/loop`은 Claude Code가 제공한다.
- **해결 수단 우선순위**: 1. 기존 문서 수정(1~3줄) ← 최선 → 2. 기존 훅 로직 확장 →
  3. 기존 스크립트에 기능 추가 → 4. 신규 스크립트 ← 최후
- **플랫폼 동작은 확인하고 주장한다** — `.claude/docs/platform-contract.md`를 본다. 없으면
  공식 문서를 확인해 **출처 URL과 확인 날짜를 적어 추가한다.** 기억으로 단정하지 않는다
- **차단 장치는 3상태다** — 위반 확인/위반 없음 확인/**판정 불가**. 판정 불가를 차단으로
  접으면 오탐이 되고, 오탐은 훅을 끄게 만들며, 꺼진 훅의 차단력은 0이다
- **침묵 실패 방지(필수)** — 새 훅·스크립트를 만들거나 고쳤으면 ① `lib/common.sh` source +
  `epcc_begin` ② 출력은 `epcc_emit_*`로만(이벤트마다 지원 필드가 다르고 미지원 필드는
  **조용히 무시**된다) ③ `doctor --fast` + `--self-test` 통과 ④ 훅을 배선했으면
  `workflow.graph.json`에도 노드/엣지 추가(Phase 5)
- **개입 근거 2줄** — (a) 막으려는 실패(2회 이상 관측) (b) 잘 되던 것을 망칠 위험.
  **(a)를 못 쓰면 그것은 가설이지 패턴이 아니다 — 추가하지 않는다**
- **도달 경로 검증** — 규칙·점검 장치를 추가할 때 그 파일이 **의도한 시점에 실제로
  로드되는지** 즉시 확인한다. `paths:` 조건부면 대상 파일의 paths가 실제 편집 경로를 포함하는가
- **자산 부재 판정 3-위치 검색** — "없다"고 단정하려면 ① 프로젝트 `.claude/`
  ② `~/.claude/plugins/cache/` ③ `~/.claude/plugins/marketplaces/` 를 **모두** 확인한다
- **폐기 프로토콜(Shadow 미러)** — `.claude/deprecated/`로 이동 + 만료일 파일명에 새김(기본 14일).
  만료까지 문제 없으면 삭제 확정, 문제 생기면 원위치 복구
- **에이전트 예외** — 에이전트는 `.claude/rules/`를 상속받지 않는다. 필요한 규범은 에이전트
  프롬프트에 직접 기재한다. 단 같은 규범을 두 곳이 주장하게 두지 않는다 — 한 곳이 원본, 다른 곳은 인용

#### `lessons.md` 상세

**paths는 "교훈 파일을 편집할 때"가 아니라 "지적이 나올 만한 작업을 할 때" 걸려야 한다.**
`docs/lessons.md`만 걸어두면 이미 기록하러 간 뒤에야 로드된다 — 트리거가 뒤집힌다.
(이 저장소의 `self-improvement.md`가 정확히 그 상태다.)

- **언제**: 사용자가 코드·접근 방식·워크플로우를 수정하거나 지적했을 때. 그 즉시
- **형식**: `## [category: <카테고리>] <제목>` + 날짜·상황·실수·교훈
- **카테고리는 구체적으로.** `misc`·`general` 금지 — 집계가 무의미해진다.
  예: `validation` `tdd` `architecture` `security` `naming` `scope` `workflow` `skill`
  `rule` `agent` `infra` `tooling` `false-positive`
- **`false-positive`는 승격이 아니라 수축이 답이다.** 같은 장치에서 2건 이상이면 규칙을
  만드는 게 아니라 **조건을 좁히거나 그 장치를 폐기한다**
- **반복 요청**: 같은 유형 작업을 2회 이상 수행했으면 `## [request: <요청유형>]` 기록.
  3건 이상이면 doctor가 자동화 후보(스킬 승격)로 보고
- **승격**: 집계와 후보 판정은 **doctor가 한다**(`--lessons`). 규칙이 모델에게 세도록 시키지 않는다.
  동일 카테고리 3건 이상 → ① doctor 출력에서 후보 확인 ② 형태 선택(패턴 매칭 가능 → 훅/린트 ·
  반복 워크플로우 → 스킬 · 의미 판단 필요 → 규칙 카드) ③ 사용자 승인 1회
  ④ **승인 후 해당 항목을 `docs/lessons-archive.md`로 물리적으로 이동**
  > **④가 핵심이다.** v2는 "✅ 승격됨"을 22건 선언하고 규칙은 0건 바뀌었다. 승격의 증거는
  > 선언이 아니라 **① 대응 자산의 diff ② 파일에서 사라진 항목**이다.
  > 루프가 제대로 돌면 `lessons.md`는 **줄어든다.**
- **상한**: 30건 초과 시 오래된 것부터 아카이브. 6개월간 동일 카테고리 재발이 없는 항목도 대상

#### `security.md` 상세 (기존 54줄 개편)

훅(`security-check.sh`)은 하드코딩된 시크릿 **문자열**만 정규식으로 막는다.
이 카드는 **그 정규식이 원리적으로 못 잡는 것**을 담는다 — 값이 아니라 **배치**의 문제,
즉 "올바른 값을 잘못된 쪽에 둔" 경우다. 이 분업을 카드 머리 주석에 명시한다.

- **시크릿의 경계** — 종류별 「둘 곳」 표: 서비스 롤·관리자 키(`service_role`, admin SDK) ·
  **Toss Payments 시크릿 키** · AI/외부 API 키 · PEM/서비스 계정 JSON → **서버 전용**.
  공개 클라이언트 키(anon key)만 클라이언트 가능 — **단 그것이 공개용으로 설계된 키일 때만**
- **공개 접두사를 붙이면 번들에 들어간다.** `NEXT_PUBLIC_`·`VITE_`·`PUBLIC_`·`EXPO_PUBLIC_`은
  빌드 시 값이 정적으로 치환된다. **서버 전용 키에 이 접두사를 붙이는 것은 노출이지 설정이 아니다**
- **입력 검증 경계** — 외부 입력은 스키마 검증을 통과한 뒤에만 로직/DB에. 파일 업로드
  타입·크기 상한은 **서버에서** 강제(클라이언트 검증은 UX이지 경계가 아니다)
- **인가 경계** — 서버 진입점에서 인증 주체를 **먼저** 확인하고 클라이언트가 보낸 식별자를
  신뢰하지 않는다. 보호 경로는 라우트 단위가 아니라 **데이터 접근 단위**로도 막는다.
  **RLS는 유일한 경계가 아니다 — 정책 + 애플리케이션 검사 둘 다**
  (테이블 생성 시 정책 동반 체크리스트는 `data-modeling.md`)
- **출력 보안** — `dangerouslySetInnerHTML` 금지(불가피하면 sanitize + **왜 불가피한지 주석**) ·
  에러 응답에 스택 트레이스/DB 스키마/내부 경로 금지 · **리다이렉트 대상을 사용자 입력에서
  받으면 허용 목록으로 좁힌다**(오픈 리다이렉트)
- **여기에 없는 것** — 의존성 도입 전 5단계 점검 → `code-change.md`

### ④ `CLAUDE.md` 축소

현재 55줄 중 「의사결정 자동조종」·「정본 최신성 점검」·「작업 워크플로우」 절은
규칙 카드가 상시 로드하므로 **중복이다.** 세 절을 지우고 아래 한 블록으로 대체한다:

```markdown
## 하네스

운영 규칙(되돌림 분류·진입 조건·최소 수정)과 작업 라우팅(P0~P6)·참조 신선도는
`.claude/rules/`가 매 세션 로드합니다. 나머지 작업 규칙은 편집 경로에 따라 조건부 로드됩니다.

| 명령 | 용도 |
| --- | --- |
| `bash .claude/scripts/doctor.sh` | 하네스 자기검증 |
| `bash .claude/scripts/doctor.sh --usage` | 훅 생존·스킬 호출·엣지 계측 |
| `bash .claude/scripts/doctor.sh --lessons` | 교훈 집계 + 승격 후보 |
```

기술 스택·개발 명령어·User Profile 절은 **그대로 둔다.**

## 하지 말 것

- **규칙을 늘리지 않는다.** 9장을 넘기면 `harness-change.md`의 3-질문을 통과했는지 근거를 적는다
- **되돌림 분류표를 두 곳에 적지 않는다.** T0가 정본이고 나머지는 인용이다.
  출처 저장소에서 이 표의 사본이 5벌까지 자랐다
- 폐기 규칙을 `rm`하지 않는다 — `.claude/deprecated/`로 만료일과 함께 이동
- **T0를 40줄 넘기지 않는다.** 넘치면 T1 카드로 내린다
- `workflow-routing.md`에 `paths:`를 붙이지 않는다
- 일반적인 코딩 상식을 카드에 담지 않는다. **모델이 반복해서 틀리는 것**만 남긴다

## 검증

```bash
bash .claude/scripts/doctor.sh --fast   # 규칙 도달성 절: 예산·paths·버전 스탬프·dangling
ls .claude/rules/                        # 9개
wc -l .claude/rules/operating-contract.md   # 40 이하
for f in .claude/rules/*.md; do printf '%-40s ' "$f"; head -1 "$f" | grep -q '^---' && echo cond || echo ALWAYS; done
# ALWAYS 는 operating-contract.md 와 workflow-routing.md 둘뿐이어야 한다
```

**도달을 실측한다** — 이 저장소는 소비자가 실재하므로 실제 세션에서 확인할 수 있다.
출처 저장소가 4개월간 놓친 것이 정확히 이 한 가지다.

1. 새 세션을 열고 **아무 파일도 열기 전에** T0의 되돌림 분류표와 Phase 라우팅 표가
   컨텍스트에 있는지 확인한다 (모델에게 "지금 로드된 규칙 파일을 나열하라"고 묻는다)
2. `src/` 파일을 하나 읽고 `code-change.md`·`security.md`·`reversibility.md`가 뜨는지
3. `supabase/migrations/` 파일을 읽고 `data-modeling.md`·`reversibility.md`가 뜨는지
4. `dev/docs/prd/` 문서를 읽고 `doc-dependency.md`가 뜨는지

## 완료 기준 (DoD)

1. `.claude/rules/`가 **9개**이고 폐기 6개가 `.claude/deprecated/`에 만료일과 함께 있다
2. `paths` 없는 파일이 **정확히 2개** (`operating-contract.md`, `workflow-routing.md`)
3. `operating-contract.md`가 **40줄 이하**이고 되돌림 분류표를 담는다
4. `grep -rn 'Irreversible' .claude/rules/ | grep -c '판정 경로'` 가 **1** — 판정표 정본이 하나다
5. 9개 전부 `epcc-rule-version` 스탬프를 갖는다
6. 위 「도달을 실측한다」 4항목이 실제 세션에서 확인됐고 그 결과가 기록됐다
7. `doctor --fast`의 규칙 도달성 절이 실패 0이다
8. `CLAUDE.md`에서 중복 3절이 제거됐다

---

**다음**: `phase-4-agents.md`
