# Phase 5 — 워크플로우 그래프 + 계측 (`--graph` · `--usage` · `--lessons`)

> `~/Documents/easy-peasy-claudecode-devkit`에서 붙여넣는다. **Phase 4의 DoD를 통과한 뒤에.**

---

9단계 중 **5단계**다. 하네스를 **기계 판독 가능한 그래프**로 선언하고, 그 그래프가
실제로 밟히는지 계측한다.

## 왜 필요한가

v2에서 이 그래프는 마크다운 표와 산문에 흩어져 있어 **검증도 계측도 불가능했다.**
그 결과 "선언됐지만 도달 불가능한 자산"(규칙 697줄)이 4개월간 아무에게도 발견되지 않았다.

그리고 **측정 없이 컬링하지 않는다.** 스킬 33개 중 무엇이 쓰이는지 모르는 상태에서
"이건 안 쓰는 것 같다"로 지우면 되돌릴 근거도 남지 않는다. Phase 6이 스킬을 정제하려면
이 단계의 계측이 먼저다.

## 만들 것

### ① `.claude/workflow.graph.json`

파일 머리 `$comment`에 이 파일이 존재하는 이유를 적는다 (위 「왜 필요한가」).

**노드 스키마**

| 키 | 뜻 |
| --- | --- |
| `id` | 고유 식별자. 스킬이면 스킬 이름과 **정확히** 일치 |
| `kind` | `hook` · `stage` · `skill` · `agent` · `store` · `tool` · `terminal` |
| `path` | 실물 파일 경로 (doctor가 실재를 확인한다) |
| `event` | 훅이면 배선된 이벤트 |
| `phase` | `workflow-routing.md`의 Phase 어휘(`P0-A`~`P0-E`·`P1`~`P6`)와 잇는다. **두 어휘가 어긋나면 라우팅이 기계 검사 불가가 된다** |
| `when` | 발동 조건 (산문) |
| `produces` | **하네스가 나중에 다시 읽는 산출물**에만 붙인다. 사용자에게 최종 전달되고 끝나는 산출물(마케팅 사이트·파비콘 등)은 store가 아니다 |
| `blocks` | 차단 능력이 있는 노드 |
| `manual` | 수동 호출 전용 |
| `tools` | 에이전트의 도구 목록 (frontmatter와 대조) |
| `entry` | 진입 가능 노드 (도달 불가 판정에서 제외) |
| `on_error` | 실패 시 어디로 |
| `note` | 판단 근거 |

**엣지 스키마**: `from` · `to` · `cond` · `instrumented`

> **`instrumented`는 "훅이 실제로 방출하는 엣지"에만 붙인다.** stage 간 전이는 모델 행동이라
> 코드가 방출할 수 없다. 그것까지 "죽었다"고 보고하면 **영원히 꺼지지 않는 경고**가 되고,
> 꺼지지 않는 경고는 무시를 학습시킨다.

**`store` 노드 규율** — 쓰기(인바운드)와 읽기(아웃바운드) 엣지를 **모두** 가져야 한다.
**읽는 노드가 없는 저장소는 비용만 있고 드리프트의 원천이다.** 이 저장소의
`dev/docs/insights/`·`dev/docs/digital-twin/`이 정확히 그 상태일 가능성이 높다 —
선언해보면 드러난다. 드러나면 소비 경로를 만들거나 **폐지한다.**

선언 대상: 훅 5개(Phase 2) · 에이전트 2개(Phase 4) · 스킬 전량 · stage 6개
(understand·plan·build·verify·cross-check·terminal) · store(`docs/lessons.md` ·
`dev/handoff/` · `dev/docs/insights/` · `dev/docs/digital-twin/` 등 실재하는 것).

### ② `doctor.sh --graph`

| 검사 | 판정 |
| --- | --- |
| dangling `path` | 선언된 파일이 실재하지 않으면 FAIL |
| 고아 자산 | 실재하는데 그래프에 선언되지 않은 훅·에이전트·스킬 |
| 도달 불가 노드 | 인바운드 엣지가 없고 `entry`도 아닌 노드 |
| dangling 엣지 | `from`/`to`가 존재하지 않는 id를 가리킴 |
| Phase 어휘 대조 | 노드의 `phase` 값이 `workflow-routing.md`의 표에 실재하는가 (양방향) |
| `on_error` 누락 | 차단 능력이 있는 노드(`blocks`)에 에러 엣지가 있는가 |
| store 읽기 경로 | 아웃바운드 엣지가 없는 store → **경고**(폐지 후보) |

### ③ `doctor.sh --usage` — 계측

Phase 2의 `epcc_heartbeat`·`epcc_edge`·`track-skill.sh`가 남긴 로그를 읽는다.

| 절 | 내용 |
| --- | --- |
| 훅 하트비트 | `.claude/.epcc/hookrun.log` — 훅별 실행 횟수·최근 시각·**비정상 종료 건수** |
| 그래프 엣지 traversal | `graph.log` — 밟힌 엣지. **`instrumented:true`인데 한 번도 안 밟힌 엣지**를 보고 |
| 스킬 호출 | `skilluse.log` — 호출 횟수. **무호출 스킬 목록**(Phase 6의 입력) |
| 상주 컨텍스트 비용 | CLAUDE.md + 상시 규칙 + 스킬 description 문자 수. Phase 0 기준선과 대조 |

#### 여기서 고쳐서 만드는 것 — 출처의 현존 결함 2건

**E-10 — `&& warn … || ok …`를 쓰지 않는다.**

```bash
# ✗ 출처의 실제 결함. warn 은 $2 가 비면 반환값이 1이라
#   실패가 **있을 때** warn 과 ok 가 둘 다 실행된다.
#   출력: "! 비정상 종료 2건" 바로 아래 "✓ 비정상 종료 없음"
#   PASS 카운터도 함께 증가해 헤더의 통과 수에 유령이 섞이고, 실제 신호가 덮인다.
[ "$(num "$fails")" -gt 0 ] && warn "비정상 종료 ${fails}건" || ok "비정상 종료 없음"

# ✓
if [ "$(num "$fails")" -gt 0 ]; then warn "비정상 종료 ${fails}건" "훅 로그의 exit 코드 확인"
else ok "비정상 종료 없음"; fi
```

작성 후 전수 조사한다: `grep -n '&& \(warn\|bad\|ok\).*|| ' .claude/scripts/*.sh` → **0건**이어야 한다.

**E-11 — `살아있는 훅 N/M`의 분모.**
분모를 `settings.json`의 **엔트리 수**로 잡으면 `handoff.sh`가 `PreCompact`·`SessionEnd`
두 이벤트에 걸려 있으므로 **분자가 구조적으로 분모에 도달할 수 없다** → 영원히 미달을 표시한다.
분모는 **고유 스크립트 수**로 잡는다:

```bash
expected=$(python3 -c "
import json;h=json.load(open('.claude/settings.json'))['hooks']
print(len({c['command'] for v in h.values() for e in v for c in e['hooks']}))")
```

**꺼지지 않는 경고를 만들지 않는다.** 매 실행마다 미달을 표시하지만 아무도 무엇을 해야
하는지 모르는 지표는, 없는 지표보다 나쁘다.

### ④ `doctor.sh --lessons` — 되먹임 루프

| 절 | 내용 |
| --- | --- |
| 교훈 집계 | `docs/lessons.md`의 `[category: X]` 카테고리별 건수. **동일 카테고리 3건 이상 → 승격 후보로 보고** |
| 반복 요청 집계 | `[request: X]` 3건 이상 → **자동화 후보(스킬 승격)** |
| Shadow 폐기 미러 | `.claude/deprecated/`의 만료일 경과분 보고 |
| `false-positive` | 이 카테고리는 **승격이 아니라 수축 후보**로 보고한다. 같은 장치에서 2건 이상이면 조건을 좁히거나 폐기 |

**집계는 규칙이 아니라 doctor가 한다.** 규칙이 모델에게 세도록 시키면 매번 다르게 센다.

승격 후보 보고에는 **형태 선택 힌트**를 함께 낸다: 패턴 매칭으로 결정론적 검출 가능 →
훅/린트 · 반복 워크플로우 → 스킬 · 의미 판단 필요 → 규칙 카드.

### ⑤ `--all` 추가

`--fast` → `--self-test` → `--graph` → `--usage` → `--lessons` 순으로 전부 돌린다.

## 하지 말 것

- 계측 지표를 늘리지 않는다. **산출이 행동으로 이어지지 않는 지표는 만들지 않는다**
- `instrumented`를 stage 간 엣지에 붙이지 않는다
- 그래프를 문서로 두 번 적지 않는다. `workflow.graph.json`이 정본이고 문서는 인용이다
- **Phase 1의 `epcc_state_dir` 규약을 되돌리지 않는다.** `--usage`가 읽는 데이터가
  doctor 자신의 픽스처 흔적이면 이 단계 전체가 무의미해진다 (출처의 E-09).
  새 훅을 추가할 때 `.claude/.epcc`를 직접 조립하면 같은 오염이 다시 시작된다

## 검증

```bash
bash .claude/scripts/doctor.sh --graph;   echo "exit=$?"
bash .claude/scripts/doctor.sh --usage;   echo "exit=$?"
bash .claude/scripts/doctor.sh --lessons; echo "exit=$?"
bash .claude/scripts/doctor.sh --all;     echo "exit=$?"

# E-10 형태 전수 조사 — 0건
grep -n '&& \(warn\|bad\|ok\).*|| ' .claude/scripts/*.sh

# 계측 오염 확인 — self-test 전후로 로그 행 수가 변하지 않아야 한다
b=$(wc -l < .claude/.epcc/hookrun.log 2>/dev/null || echo 0)
bash .claude/scripts/doctor.sh --self-test >/dev/null
a=$(wc -l < .claude/.epcc/hookrun.log 2>/dev/null || echo 0)
[ "$b" = "$a" ] && echo "격리 OK" || echo "오염"
```

**차단을 증명한다**:

```bash
# ① 그래프에 없는 id를 to 로 가진 엣지를 임시로 추가 → --graph 가 FAIL
# ② 노드의 path 를 없는 파일로 바꿈 → FAIL
# ③ 상시 규칙에 없는 phase 값을 노드에 넣음 → Phase 어휘 대조 FAIL
# ④ 훅을 하나 배선 해제 → 고아 자산으로 검출
```

## 완료 기준 (DoD)

1. `.claude/workflow.graph.json`이 훅 5·에이전트 2·스킬 전량·stage·store를 선언한다
2. `--graph`가 dangling 0 · 도달 불가 0 · Phase 어휘 불일치 0
3. `--usage`가 훅 하트비트·엣지·스킬 호출·상주 비용 4절을 낸다
4. **`살아있는 훅` 지표의 분자와 분모가 실제로 일치할 수 있다** — 5개 훅을 모두 한 번씩
   실행시킨 뒤 `5/5`가 나온다
5. `grep -n '&& \(warn\|bad\|ok\).*|| ' .claude/scripts/*.sh` 가 **0건**
6. `--lessons`가 카테고리 집계와 승격 후보를 낸다
7. 아웃바운드 엣지가 없는 `store` 노드가 있으면 **경고로 보고되고, 그 처분(소비 경로 신설
   또는 폐지)이 결정돼 기록**돼 있다
8. `--all`이 exit 0 또는 1이고 각 절이 전부 실행된다

---

**다음**: `phase-6-skills.md`
