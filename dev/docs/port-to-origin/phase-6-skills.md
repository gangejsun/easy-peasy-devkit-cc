# Phase 6 — 스킬 33개 정제

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 5의 DoD를 통과한 뒤에.**

---

9단계 중 **6단계**다. `.claude/skills/` 33개를 정리한다. **개수를 줄이는 것이 목표가 아니다** —
목표는 ⓐ 상주 비용 회수 ⓑ 빌트인과의 충돌 제거 ⓒ 깨진 참조 수리다.

## 먼저 읽을 것 — 이 단계에서 실제로 실패한 기록

출처 저장소에서 이 작업을 한 번 잘못했다. 스킬 5종을 "Claude Code 네이티브와 중복"이라는
이유로 제거했는데 **5건 중 4건이 오판**이었고 다음 커밋에서 3종을 복원해야 했다. 원인 둘:

1. **"네이티브가 존재한다"를 "커스텀이 열등하다"의 증거로 썼다.** 그건 중복의 증거일 뿐이다.
   **우열은 양쪽 본문을 열어봐야 안다.**
2. **비교 대상이 이미 훼손된 버전이었다.** 직전 커밋이 원본을 68~84% 삭감해둔 상태였고,
   그 잔해를 네이티브와 비교하며 "빈 껍데기"라고 판정했다
   (`skill-generator` 194→61줄 · `security-review` 172→42줄 · `requesting-code-review` 290→44줄).

그래서 이 단계의 제1규율은 이것이다:

> **커스텀 폐기를 제안하려면 양쪽 본문을 실제로 열어 커버 영역을 비교한다.
> 비교 대상은 훼손되지 않은 최선 버전이어야 한다** — 과거 커밋이 내용을 삭감했을 수 있으므로
> `git log --follow`로 최대 분량 시점을 확인한다.

그리고 제2규율:

> **측정 없이 컬링하지 않는다.** Phase 5의 `track-skill.sh`가 붙어 있으므로,
> **최소 2주 실사용 로그를 쌓은 뒤**에 무호출 스킬을 판단한다. 로그가 없으면
> 이 단계에서 "미사용"을 근거로 지우지 않는다 — 아래 1·2·3번만 하고 4번은 미룬다.

## 할 일

### 1. 깨진 참조 수리 (측정 불필요 — 지금 한다)

```bash
# 자작 치환 표기 — 공식 변수는 ${CLAUDE_SKILL_DIR} 하나뿐이다
grep -rn '<skill-dir>\|<Base directory>\|<스킬 디렉토리>' .claude/skills/
# SKILL.md가 참조하는데 실재하지 않는 파일
bash .claude/scripts/doctor.sh --fast   # 「스킬 내부 참조」 절
```

출처 저장소에서 자작 표기가 **28곳/5스킬**에 있었고 올바른 사용은 0곳이었다.
이 저장소에서는 스킬이 프로젝트 로컬이라 상대 경로가 우연히 맞을 수 있지만,
`${CLAUDE_SKILL_DIR}`로 통일한다 — 우연히 맞는 것은 계약이 아니다.

부재 스크립트를 참조하는 스킬은 **스크립트를 실제로 작성하거나 그 절을 지운다.**
"있다고 선언하고 없는" 상태를 남기지 않는다.

### 2. description 위생 (측정 불필요 — 지금 한다)

**스킬 description은 호출하지 않아도 전량이 매 세션 상주한다.** Phase 0에서 잰 값이
전체 상주 비용의 대부분일 것이다(출처 저장소에서는 71%였다).

| 정리 대상 | 왜 |
| --- | --- |
| YAML 블록 스칼라(`\|`·`>`) → **단일 행** | 여러 줄 description은 라우팅 정확도를 올리지 않고 비용만 늘린다 |
| `(project)` 접미사 제거 | 라우팅에 무의미하다 |
| **`Use ONLY when the active preset matches` 제거** | **프리셋 게이팅은 구현된 적이 없다.** `activeSkills`/`disabledSkills`를 읽어 스킬을 켜고 끄는 코드가 어디에도 없고 Claude Code에 그런 메커니즘도 없다. **모델이 추론해야 하는 게이팅은 게이팅이 아니다** |
| `P0`~`P6` 번호와 옛 에이전트명(`planning-agent`·`review-agent`) | Phase 4·3에서 바뀐 어휘로 교체 |
| 마케팅 계열 4스킬의 중복 트리거 어휘 | `marketing-workflow`가 셋을 오케스트레이션하는데 개별 트리거 문구가 중복. 어휘를 상위로 모으고 하위 3개는 짧은 지시로 |

description은 **언제 부르는지**만 적는다. 무엇을 하는지는 본문이 담당한다.

### 3. 스택 불일치 스킬 처분 (측정 불필요 — 지금 한다)

이 저장소는 **Next.js 15 + Supabase + Toss Payments** 단일 스택이다.

| 스킬 | 처분 |
| --- | --- |
| `react-vite-frontend-guide` · `react-vite-backend-guide` | **폐기** — 이 저장소의 스택이 아니다. `.claude/deprecated/`로 |
| `frontend-dev-guidelines` · `backend-dev-guidelines` | **Phase 7이 흡수한다.** 지금 손대지 않는다 |
| `nextjs-ui-ux-design`류가 있으면 `ui-ux-design`과 **병합** | 데이터셋 보유본을 남기고 하나로 |

### 4. 네이티브 중복 판정 (측정 필요 — 로그가 쌓인 뒤)

Claude Code가 제공하는 것: `/code-review` · `/simplify` · `/security-review` ·
`skill-creator` · `/init` · `/run` · `/loop`.

후보와 **본문 대조 결과**를 표로 남긴다. 출처 저장소의 실제 판정을 참고하되 **그대로
믿지 않는다** — 이 저장소의 본문은 다를 수 있다:

| 커스텀 | 네이티브 | 출처의 판정 | 근거 |
| --- | --- | --- | --- |
| `security-review` | `/security-review` | **중복 아님** | 전수 감사·의존성 CVE·시크릿 전수·**결제 보안**이 본문의 대부분. 내장은 "브랜치 diff에 새로 생긴 취약점"만 본다 |
| `receiving-code-review` | `/code-review` | **중복 아님** | 리뷰를 **생산**하는 게 아니라 **수신 후 사실 확인·반박**한다. 내장의 산출을 입력으로 받는다 |
| `requesting-code-review` | `/code-review` | **재검토 필요** | 원본 290줄. 훼손 전 버전으로 비교할 것 |
| `skill-generator` | `skill-creator` | **경계 선언 필요** | 이 스킬의 description이 "skill-creator 플러그인보다 우선 사용합니다"로 **공식 번들을 능동적으로 밀어내고 있다.** 그 문구는 지운다. 프로젝트 고유 규약(frontmatter 규칙·검증 체크리스트)만 남기고 생성·A/B는 `skill-creator`로 넘긴다 |

**중복이 아니라고 판정하면 그 경계를 본문에 명시한다.** 세 건 모두 출처에서는
"내장은 X를 본다, 이 스킬은 Y를 본다"가 본문에 실재했기 때문에 살아남았다.

### 5. 무호출 스킬 판정 (측정 필요)

```bash
bash .claude/scripts/doctor.sh --usage   # 스킬 호출 절
```

2주 이상의 로그에서 호출 0건인 스킬에 대해 **폐기 여부를 판단한다.**
판단 기준은 호출 수 하나가 아니다 — 연 1~2회 쓰는 스킬(배포 전 보안 감사 등)은
호출이 적은 것이 정상이다. `harness-change.md`의 3-질문을 다시 던진다:
**지금도 필요한가 · 모델 향상으로 불필요해지지 않았는가 · 문서 1~3줄로 될 것을 스킬로 만들지 않았는가.**

## 하지 말 것

- **"네이티브가 있으니 지운다"로 판정하지 않는다.** 양쪽 본문을 연다
- **훼손된 버전과 비교하지 않는다.** `git log --follow`로 최대 분량 시점을 확인한다
- **로그 없이 "미사용"을 근거로 지우지 않는다**
- description을 늘리지 않는다. 트리거 어휘를 추가하고 싶으면 **어느 것을 뺄지 함께 정한다**
- 폐기는 `rm`이 아니라 `.claude/deprecated/` 이동 + 만료일

## 검증

```bash
bash .claude/scripts/doctor.sh --fast    # 스킬 description 위생 · 스킬 내부 참조 절
bash .claude/scripts/doctor.sh --graph   # 스킬 노드 선언 ↔ 실물 (Phase 5 그래프도 갱신할 것)

grep -rn '<skill-dir>\|<Base directory>' .claude/skills/          # 0건
grep -rn 'Use ONLY when the active preset' .claude/skills/        # 0건
grep -rn '(project)$' .claude/skills/*/SKILL.md                    # 0건
grep -rn 'planning-agent\|review-agent' .claude/skills/            # 0건

# 상주 비용 재측정 — Phase 0 기준선과 대조
for f in .claude/skills/*/SKILL.md; do
  awk '/^description:/{f=1} f{print} /^---$/{if(f)exit}' "$f"
done | wc -c
```

**폐기한 스킬이 그래프·라우팅·다른 스킬에서 참조되지 않는지 확인한다** —
한 곳만 고치면 나머지가 조용히 어긋난다:

```bash
for s in <폐기한 스킬 이름들>; do grep -rn "$s" .claude/ CLAUDE.md dev/ ; done
```

## 완료 기준 (DoD)

1. 자작 치환 표기 **0건**, 스킬 내부 dangling 참조 **0건**
2. description이 전부 단일 행이고, `(project)`·프리셋 게이팅 문구·구 에이전트명이 0건
3. **스킬 description 총 문자 수가 Phase 0 기준선 대비 줄었고, 그 값이 기록됐다**
4. 스택 불일치 스킬이 `.claude/deprecated/`로 이동했다
5. 네이티브 중복 후보 4건에 대해 **양쪽 본문을 연 대조표**가 있고, 살린 것은 본문에
   경계 선언이 실재한다
6. 폐기한 스킬의 참조가 저장소 전체에서 0건이고 `workflow.graph.json`이 갱신됐다
7. 무호출 판정을 **미룬 경우 그 사실과 재판정 시점**이 기록돼 있다 (침묵 생략 금지)

---

**다음**: `phase-7-guides.md`
