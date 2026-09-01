# Phase 7 — 개발 가이드를 축 팩 + 이음매 체계로

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 6의 DoD를 통과한 뒤에.**

---

9단계 중 **7단계**다. `.claude/skills/frontend-dev-guidelines`·`backend-dev-guidelines`를
**축 팩 + 이음매** 구조로 재편하고, 그 구조가 스스로 부패를 드러내게 만든다.

## 왜 구조를 바꾸는가

개발 가이드는 하네스에서 **가장 조용히 썩는 자산**이다. 규칙은 짧아서 틀린 게 보이고
훅은 실행되니 죽으면 티가 나지만, 가이드는 2,000줄짜리 문서라서 절반이 낡아도 아무도 모른다.

출처 저장소가 이 문제를 겪고 도달한 답은 셋이다:

1. **절단선을 축에 긋는다.** 가이드 내용의 대부분은 **한 축**(프론트엔드 또는 백엔드)만의
   함수다. 조합에 종속된 부분(HTTP 봉투·에러 형식·클라이언트 생성·인증 배선)만 **이음매**로 뺀다.
   그러면 축을 고칠 때 조합 수만큼 반복하지 않아도 된다.
2. **선언한 정책과 강제하는 곳을 맞춰볼 의무를 만든다.** 실측에서 감사 지적의 최대 부류
   (57건 중 26건)가 "정책을 선언한 곳과 강제하는 곳이 다르고 둘을 맞춰볼 의무가 없다"였다.
3. **부패를 날짜가 아니라 패키지 메이저로 판정한다.** 6개월이 지나도 메이저가 안 올랐으면
   안 낡았고, 2개월 만에 프레임워크 메이저가 오르면 낡았다.

**이 저장소의 조합은 하나다** — `nextjs` × `supabase`. 축이 2개, 이음매가 1쌍이다.
그래서 출처의 「생성기」(임의 스택용 `stack-guide-generator`)는 필요 없다.
**구조와 게이트만 가져온다.**

## 만들 것

### ① 디렉토리 구조

```
.claude/guides/
├── frontend/nextjs/
│   ├── pack.json          축 메타 (아래 스키마)
│   ├── PACK.md            허브 조각 — 리소스 목차와 진입 규칙
│   ├── ledger.md          심볼 원장 (provides / requires)
│   ├── policies.md        파일 간 불변식 (기계 검사 + 사람이 지킬 것)
│   └── resources/*.md     축 안에서 닫히는 내용
├── backend/supabase/
│   └── (동일 5종)
└── seams/nextjs+supabase/
    ├── seam.json
    ├── contract.md        와이어 계약 (조합의 정본)
    ├── frontend/{HUB.md,resources/}
    └── backend/{HUB.md,resources/}
```

### ② `pack.json` 스키마

| 필드 | 뜻 |
| --- | --- |
| `axis` · `name` · `displayName` | 축 식별 |
| `packVersion` · `verified` | 버전과 마지막 실측 날짜 |
| `pkgs` | **메이저를 명시한 패키지 목록** (`["@supabase/ssr@0.12", "zod@4"]`). 부패 판정의 입력이다. **0.x는 마이너가 파괴 축이므로 마이너까지 적는다** |
| `fixesVariants` | 이 팩이 **못박은 변형**. 여기 걸린 패키지의 메이저가 오르면 "팩 전제가 바뀐 것"이라 부분 수리가 아니라 재저작이다 |
| `symbolSurface` | 이 팩이 최상위 `export`를 정의하는가. `false`면 게이트가 원장 역방향 검사를 건너뛴다 |
| `exampleDomain` | `{entity, collection, route, korean}` — **양 축과 이음매가 같은 리소스 이름을 쓰게 한다.** 실측에서 프론트가 `/tasks`, 백엔드가 `/notes`를 써서 완전 예제가 서로 실행 불가였다 |
| `resources` | `[{file, nav}]` — 리소스와 그 목차 한 줄 |
| `seamSlots` | 이 축이 **이음매에 넘긴** 주제 목록 |
| `knownGaps` | **아직 통과한 적 없는 검증을 여기 적는다.** 침묵 생략 금지 |
| `thinPackNote` / `policyEngineNote` 등 | 형태가 특이하면 그 이유를 값으로 남긴다 |

**`policyEngineNote`는 이 저장소에서 특히 중요하다.** Supabase 축은 데이터 계층에
행 수준 정책 엔진(RLS)이 **있다**. "데이터 계층이 백업해 준다"는 서술을 정책 엔진이 없는
축에 옮기면 **정확히 반대 지침**이 된다.

### ③ `ledger.md` — 심볼 원장

| 절 | 내용 |
| --- | --- |
| `provides` | 이 팩이 정의하는 최상위 export. 없으면 **없다고 쓰고 그 이유**를 쓴다(패턴 지식형 팩) |
| `requires` | **이음매가 제공해야 하는 심볼**. 심볼명·종류·가정하는 형태·왜 이음매인가 |
| 추출 시 제거한 것 | 무엇을 어디로 왜 옮겼는지. 나중에 "이게 왜 여기 없지"를 막는다 |

`requires`는 **소유 파일로 좁힌다.** 전 파일에 요구하면 파일 수가 늘수록 정책이
반비례해 무력해진다.

### ④ `policies.md` — 파일 간 불변식

**기계 검사 표**의 열: `id` · `판정`(forbid/require) · `대상`(guide/seam/pack/`file:<이름>`) ·
`정규식` · `예외 파일` · **`증명 예`** · `반례` · `설명`

> **`증명 예` 열은 의무다 (없으면 게이트 FAIL).** 그 정규식이 실제로 잡는 문자열 하나를 적는다.
> 게이트가 두 가지를 단언한다: ① 예가 자기 정규식에 매치되는가 — **매치되지 않으면
> 아무것도 못 잡는 죽은 정규식이다** ② `forbid`면 그 예가 대상 파일에 실재하지 않는가 —
> 실재하면 팩이 자기 정책을 어긴 것이다.
>
> **`대상` 값에 마크다운 강조를 쓰지 않는다.** `**seam**`은 게이트가 scope로 인식하지 못해
> 정책이 조용히 전 파일을 겨눈다 — 실측에서 "이음매를 겨눈다"는 감사 수리가 무효인 채로 출하됐다.

이 저장소의 supabase 축에 실제로 들어갈 정책 예:

| id | 판정 | 정규식 | 왜 |
| --- | --- | --- | --- |
| `getUser-not-getSession` | forbid | `getSession\(` | 서버에서 사용자 확인은 항상 `getUser()`. `getSession()`은 쿠키를 그대로 신뢰하므로 **인증 경계로 쓸 수 없다** |
| `no-select-star` | forbid | `select\('\*'\)` | 스키마 변경 시 조용히 payload가 커지고 비밀 컬럼을 끌고 온다 |
| `no-module-singleton-client` | forbid | `^(const\|let\|var) \w+ = createClient\(` | 클라이언트는 요청 단위. 모듈 싱글턴은 요청 간 인증 컨텍스트를 섞는다 |
| `error-is-checked` | require | `if \(error\)` | Supabase 쿼리는 throw하지 않고 `error`를 반환한다. 확인하지 않으면 **실패가 빈 결과로 둔갑한다** |

**사람이 지킬 것** 절도 함께 둔다 (기계로 판정 불가): 모든 테이블에 RLS를 켠다 ·
service role 키는 서버의 격리된 경로에서만 · **부재와 미인가를 같은 응답으로 낸다**
(RLS가 가린 행을 403으로 구분하면 존재가 누설된다).

### ⑤ `seams/nextjs+supabase/contract.md` — 와이어 계약

**계약의 값은 목록·표 행에만 쓴다.** 산문의 백틱은 설명이고, 부정문을 목록에 쓰면
양쪽 요구가 된다.

절 구성:

- **§0 도메인 어휘** — 엔티티·컬렉션·한국어 표기. 양 축이 같은 이름을 쓰게 하는 절
- **§0.5 경계가 둘이다 (Next.js 고유)** — Next.js는 서버 런타임을 내장하므로 경계가 둘이다:
  ① Route Handler ↔ fetch (HTTP 봉투) ② **Server Action ↔ `useActionState`** (HTTP 상태 코드 없음).
  **이 조합에서는 ②가 주(主)다** — 서버 컴포넌트가 데이터 계층을 직접 읽으므로 ①은
  외부 소비자·웹훅을 위한 표면에 가깝다. 그래서 §1~§5는 `surface: backend`로 선언한다.
  **양쪽에 요구하면 정상 조합이 영구 FAIL이 된다**
- **§1 성공 응답 봉투** · **§2 에러 봉투**(코드는 소문자 snake_case) · **§3 페이지네이션**
  (offset 하나만, `page`/`limit`, Supabase `range()`) · §4 인증 전달 · §5 검증 실패 형식
- **§6 인증 표면** — Server Action 경계의 타입 계약

### ⑥ `guide-gate.sh` — 기계 게이트

```
guide-gate.sh --pack <팩디렉토리>        축 안에서 닫히는 검사만. 조합의 함수는 건너뛴 것을 **명시 보고**
guide-gate.sh --pair --contract <계약> --frontend <디렉토리> --backend <디렉토리>
guide-gate.sh --guide <가이드디렉토리> [--ledger <파일>] [--forbid kw,kw] [--pm pnpm]
guide-gate.sh --self-test               합성 픽스처만 (빠르다 — 하네스를 고칠 때마다)
guide-gate.sh --regress                 + 실물 팩·이음매 전량 (느리다 — 출하 전)
```

> **합성 픽스처는 미탐을 잡고 실물은 오탐을 잡는다.** 둘 다 필요하다.

판정은 **3단**이다: `FAIL`(설치 차단) · `WARN`(보고 의무) · `REVIEW`(한 항목씩 사람이 정당화).
**REVIEW를 자동 실패로 만들지 않는다** — 위양성에 묻혀 못 쓰게 된다.

**코드 판정은 코드펜스 안만 본다.** 주석 행과 `❌`/`Bad` 표식 이후 구간은 제외한다 —
가이드는 안티패턴 예시를 일부러 싣기 때문에 블라인드 스캔은 위양성투성이가 된다.
표식 판정에서 단어 경계에 `_`와 숫자를 빼야 계약 식별자(`BAD_REQUEST`)가 안티패턴 표식으로
오인되지 않는다. **오인되면 그 지점부터 코드 추출이 꺼져 이후 검사가 조용히 건너뛴다(미탐).**

검사 항목: dangling 리소스 참조 · 교차 누출 키워드(`--forbid`) · 패키지 매니저 불일치
(`--pm pnpm`이면 `npm run` 검출) · 원장 대조(정의·소비) · 정책 표 강제 · **`증명 예` 열 존재** ·
버전 주장 인벤토리 · 예산.

### ⑦ `pack-smoke.sh` — 실행 검증

게이트는 **읽어서 잡을 수 있는 것**을 잡는다. 실측에서 게이트 전항을 통과한 뒤 남은 결함은
**거의 전부 실행으로** 잡혔다 — 그중 하나가 출하본 네 곳에 있던 **오픈 리다이렉트**였다.

표시가 두 가지다:

| 표시 | 뜻 |
| --- | --- |
| `// src/foo.ts` (펜스 첫 줄) | **라벨.** 어느 파일의 조각인지 알린다. 복원은 하되 **구문·타입 검사는 걸지 않는다** |
| `<!-- file: src/foo.ts -->` | **완전 파일 주장.** 구문·타입 검사 대상 |

보안 원시함수·설정 파일·테스트 하네스에는 후자를 단다 — 실행으로 잡힌 결함이 전부 이 부류였다.
보안 벡터 시험은 두 표시 모두에서 함수를 찾는다.

**층 소유**: 추출·스텁·판정은 이 스크립트(툴체인 무관), 빌드·타입체크는 `profiles/<이름>.sh`.
프로필이 없는 툴체인은 **skip을 명시 보고한다 (침묵 생략 금지).**

주의: **JS 팩의 `allowJs`는 파싱만 한다.** 타입체크가 대상을 보고 있는지 실제로 확인한다 —
출처에서 이 팩의 타입체크가 한 번도 통과한 적이 없다는 사실이 뒤늦게 드러났다.
마크업·스타일 시트는 **구문 오류가 아니라 미검사**로 가른다.

### ⑧ `guide-freshness.sh` — 부패 판정

**날짜가 아니라 `pkgs` 메이저로 판정한다.**

| 상승한 패키지 | 뜻 | 동작 |
| --- | --- | --- |
| `fixesVariants`에 걸린 것 (프레임워크·ORM) | **팩 전제가 바뀌었다** | 부분 수리하지 않는다. 재저작 대상으로 보고 |
| 그 외 | 부분 부패 | **영향 리소스만** 재저작 + `--pack` + `pack-smoke` |
| 메이저 상승 없음 | 신선 | 0줄 |

오프라인이면 **`--offline`으로 판정 불가를 명시 보고한다.** 차단하지 않는다.

> **이 저장소에서 특히**: 스택 전제는 프로젝트가 고정한다. 이미 코드를 쌓은 프로젝트에
> 다른 메이저의 패턴을 들이미는 것은 낡은 것을 고치는 게 아니라 **이 프로젝트에 대해 틀린**
> 지침이다. 신선도 판정은 **가이드를 새로 깔 때만** 의미가 있다.

### ⑨ 기존 두 스킬 흡수

`frontend-dev-guidelines`·`backend-dev-guidelines`의 본문을 위 구조로 옮긴다.
축에서 닫히는 것은 `resources/`로, 조합의 함수인 것(HTTP 봉투·에러 형식·클라이언트 생성·
인증 배선·핸들러 테스트)은 **이음매로** 옮기고 `ledger.md`의 「추출 시 제거한 것」에 기록한다.

두 스킬의 `SKILL.md`는 **허브로 남긴다** — 조립된 가이드로 가는 진입점이다.
`.claude/deprecated/`로 보내지 않는다 (스킬 발동 경로가 필요하다).

> **팩 본문이 필요하면**: 출처 저장소의 `guides/frontend/nextjs/` · `guides/backend/supabase/` ·
> `guides/seams/nextjs+supabase/`가 이 조합의 완성본이다. 참고하되 **그대로 믿지 않는다** —
> 이 저장소의 실제 코드(`src/`·`packages/shared`)와 대조해 맞지 않는 것은 고친다.
> 가이드가 코드와 다르면 **틀린 것은 가이드다.**

## 하지 말 것

- **팩과 이음매를 함께 고치면서 어느 쪽이 정본인지 정하지 않는 상태를 남기지 않는다**
- 축 팩에 조합 지식을 넣지 않는다. 넣는 순간 다음 조합에서 틀린 지침이 된다
- **정책 표에 `증명 예`를 비운 채 출하하지 않는다** (게이트가 FAIL시킨다)
- 분량을 목표로 삼지 않는다. **3,000줄 원본 vs 1,800줄 생성본에서 후자가 우세했다** —
  감사 없는 축적은 부패도 함께 쌓는다
- **예산 상한에 붙이지 않는다.** 상한에 도달한 파일은 다음 변경 때 저자가 아니라 예산이
  삭제 대상을 고른다
- 게이트 전항 통과를 완료로 보지 않는다. **읽어서 못 잡는 것이 남아 있고 그것은 실행으로 잡는다**

## 검증

```bash
bash .claude/guides/scripts/guide-gate.sh --self-test;  echo "exit=$?"
bash .claude/guides/scripts/pack-smoke.sh --self-test;  echo "exit=$?"
bash .claude/guides/scripts/guide-gate.sh --pack .claude/guides/backend/supabase
bash .claude/guides/scripts/guide-gate.sh --pack .claude/guides/frontend/nextjs
bash .claude/guides/scripts/guide-gate.sh --pair \
  --contract .claude/guides/seams/nextjs+supabase/contract.md \
  --frontend .claude/guides/seams/nextjs+supabase/frontend \
  --backend  .claude/guides/seams/nextjs+supabase/backend
bash .claude/guides/scripts/pack-smoke.sh --pack .claude/guides/backend/supabase --online
bash .claude/guides/scripts/guide-gate.sh --regress
```

**차단을 증명한다**:

```bash
# ① 정책의 증명 예를 지운다 → --pack 이 FAIL
# ② 정책 정규식이 아무것도 못 잡게 바꾼다 → "죽은 정규식" FAIL
# ③ 이음매에 getSession( 을 심는다 → getUser-not-getSession FAIL
# ④ 리소스 하나를 지운다 → dangling 참조 FAIL
# ⑤ pack.json 의 pkgs 메이저를 낮춘다 → guide-freshness 가 부패 보고
```

## 완료 기준 (DoD)

1. `.claude/guides/`에 축 2개(`frontend/nextjs`·`backend/supabase`)와 이음매 1쌍이 있고,
   각 팩이 `pack.json`·`PACK.md`·`ledger.md`·`policies.md`·`resources/`를 갖는다
2. `pack.json`의 `pkgs`가 **메이저를 명시**하고 0.x 항목은 마이너까지 적혀 있다
3. 정책 표의 모든 행에 **`증명 예`**가 있고, 게이트가 그 예의 자기 정규식 매치를 확인한다
4. `contract.md`가 **경계 둘(§0.5)**을 구분하고 `surface: backend` 선언이 있다
5. `guide-gate.sh --self-test` · `pack-smoke.sh --self-test` 실패 0
6. `--pack` 2건 · `--pair` 1건 실패 0. **건너뛴 검사가 명시 보고**된다
7. **차단 증명 ①~⑤가 전부 기대대로 동작한다**
8. `frontend/backend-dev-guidelines` 스킬이 허브로 남아 조립된 가이드를 가리킨다
9. 통과한 적 없는 검증이 있으면 `pack.json`의 `knownGaps`에 적혀 있다

---

**다음**: `phase-8-evaluation.md`
