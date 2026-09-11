#!/usr/bin/env python3
"""workflow.graph.json → 작업 흐름 SVG (docs/manual/user.html 의 그래프 그림).

읽는 사람이 답할 수 있어야 하는 것은 셋이다 — 무엇이 먼저인가 · 어디서 어디로 가는가 ·
되돌아오는 것은 무엇인가. 그래서 레이아웃을 자유롭게 두지 않는다:

  1. **열이 순서다.** 왼쪽에서 오른쪽으로만 진행한다. x 좌표가 곧 시간이다.
  2. **선은 직교로만 꺾는다.** 자유곡선은 겹치면 방향을 잃는다.
  3. **되돌아가는 선은 본문을 지나지 않는다.** 띠 아래 전용 채널로 빠져 한 줄로 합류한다.
  4. **왕복은 한 선에 양끝 화살표.** 같은 쌍을 두 번 그리지 않는다.
  5. **세로 이동은 열 사이 빈 차선에서만 한다.** 열 중앙으로 내려가면 아래 노드를 관통한다.
     그래서 먼 엣지는 전부 「오른쪽으로 나가 → 차선 → 채널 → 대상의 왼쪽으로 들어간다」 한 형태다.

레이아웃(COL·ROW)만 손으로 정하고 라벨·kind·엣지는 그래프에서 읽는다.
자산이 늘거나 이름이 바뀌면 다시 돌려서 나온 SVG 를 user.html 에 갈아넣는다.

사용:
  python3 scripts/gen/graph-svg.py [그래프.json] [출력.svg]
  기본값: workflow.graph.json → docs/manual/graph.svg
"""
import json, pathlib, sys

SRC = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "workflow.graph.json")
OUT = pathlib.Path(sys.argv[2] if len(sys.argv) > 2 else "docs/manual/graph.svg")
if not SRC.exists():
    sys.exit("그래프를 찾지 못했습니다: %s (저장소 루트에서 실행하세요)" % SRC)

G = json.load(open(SRC))
NODES = {n["id"]: n for n in G["nodes"]}

# ── 격자 ────────────────────────────────────────────────────────────
W, H = 200, 56
COLX = [60, 310, 560, 810, 1060, 1310, 1560]      # 열 = 진행 순서
GAP = 50
CANVAS_W = 1820
BAND1 = (40, 88, 1740, 596)                        # x, y, w, h
BAND2 = (40, 736, 1740, 372)
CH1 = 640                                          # 띠1 되돌림 채널
CH2 = 1060                                         # 띠2 되돌림 채널
LANES = [672, 686, 700, 714]                       # 띠 사이 가로 차선

RULER = [("진입", 0), ("탐색·계획", 1), ("준비 산출", 2), ("구현", 3),
         ("검증", 4), ("교차검증", 5), ("되받기", 6)]

KO = {
    "session-start": "세션 시작 브리핑", "understand": "탐색", "plan": "계획",
    "build": "구현", "verify": "리뷰 맡김", "cross-check": "리뷰어의 추가 단계",
    "epcc-planner": "설계 위임", "epcc-reviewer": "독립 리뷰",
    "security-check": "시크릿·파괴 명령 차단", "build-gate": "검증 게이트",
    "track-skill": "스킬 사용 기록", "handoff": "핸드오프",
    "prd-generator": "PRD 생성", "dev-docs-generator": "개발 문서",
    "completion-review": "마무리 문서화", "codex-claude-loop": "외부 모델 검증",
    "receiving-code-review": "받은 지적 검증", "doctor": "자기검증",
    "lessons": "교훈 기록", "eval-report": "평가 보고", "rule-promotion": "자산 승격",
    "user-report": "사람에게 보고", "harness-evaluation": "하네스 평가",
    "skill-enhancer": "스킬 재설계",
}
# id: (열, y)
POS = {
    "session-start":        (0, 232),
    "understand":           (1, 120),
    "plan":                 (1, 210),
    "epcc-planner":         (2, 316),
    "prd-generator":        (2, 406),
    "dev-docs-generator":   (2, 496),
    "build":                (3, 210),
    "completion-review":    (4, 112),
    "verify":               (4, 210),
    "epcc-reviewer":        (5, 112),
    "cross-check":          (5, 210),
    "codex-claude-loop":    (6, 210),
    "receiving-code-review":(6, 316),
    # ── 피드백 루프: 오른쪽에서 왼쪽으로 되먹인다 ──
    "lessons":              (6, 784),
    "doctor":               (4, 784),
    "rule-promotion":       (1, 784),
    "user-report":          (0, 900),
    "harness-evaluation":   (4, 908),
    "eval-report":          (2, 908),
    "skill-enhancer":       (1, 908),
}
# 훅은 구현 아래 버스에 매단다 — 개별 곡선을 그리면 그것만으로 엉킨다
HOOKBUS = ["security-check", "build-gate", "track-skill", "handoff"]
HOOK_Y0, HOOK_DY = 332, 74
HOOK_X = COLX[3] + 36
TRUNK_X = COLX[3] + 8
BLOCKING = {"security-check", "build-gate"}

# 띠를 건너는 엣지: (차선, 진입변) — 본문을 지나지 않게 차선을 나눠 준다
CROSS = {
    ("session-start", "doctor"):            (0, "t", COLX[4] + 100),
    ("session-start", "harness-evaluation"):(1, "r", 1530),
    ("track-skill", "doctor"):              (2, "t", COLX[4] + 60),
    ("verify", "lessons"):                  (3, "t", COLX[6] + 100),
    ("cross-check", "lessons"):             (1, "t", COLX[6] + 60),
    ("completion-review", "user-report"):   (0, "t", COLX[0] + 100),
}
GROUPS = [
    (COLX[2] - 14, 296, W + 28, 96,  "서브에이전트 · 별도 컨텍스트"),
    (COLX[5] - 14, 92,  W + 28, 96,  "서브에이전트 · 별도 컨텍스트"),
    (COLX[5] - 14, 190, W + 28, 100, "Irreversible 전용 묶음"),
]

def x_of(nid):  return COLX[POS[nid][0]]
def y_of(nid):  return POS[nid][1]
def cx(nid):    return x_of(nid) + W / 2
def cy(nid):    return y_of(nid) + H / 2

def elbow(x1, y1, x2, y2, mx, r=10):
    """가로 → 세로 → 가로. 꺾임은 둥글게. 방향이 한눈에 읽히는 유일한 형태다."""
    if abs(y1 - y2) < 2:
        return "M%.0f,%.0f H%.0f" % (x1, y1, x2)
    sy = 1 if y2 > y1 else -1
    sx1 = 1 if mx > x1 else -1
    sx2 = 1 if x2 > mx else -1
    return ("M%.0f,%.0f H%.0f Q%.0f,%.0f %.0f,%.0f V%.0f Q%.0f,%.0f %.0f,%.0f H%.0f"
            % (x1, y1, mx - sx1 * r, mx, y1, mx, y1 + sy * r,
               y2 - sy * r, mx, y2, mx + sx2 * r, y2, x2))

def band_of(nid):
    """띠1은 왼→오른쪽이 정방향, 띠2(피드백 루프)는 오른→왼쪽이 정방향이다.
    이 구분이 없으면 되먹임의 주 흐름이 통째로 「되돌림」으로 잘못 분류돼 채널에 몰린다."""
    return 1 if y_of(nid) < BAND2[1] else 2

def elbow_left(a, b, k=0, r=10):
    """오른쪽 노드에서 왼쪽 노드로 — 띠2의 정방향."""
    x1, y1 = x_of(a), cy(a)
    x2, y2 = x_of(b) + W, cy(b)
    if abs(y1 - y2) < 2:
        return "M%.0f,%.0f H%.0f" % (x1, y1, x2)
    mx = take(lambda c, k: x_of(a) - GAP / 2 - k * 13, POS[a][0], y1, y2)
    sy = 1 if y2 > y1 else -1
    return ("M%.0f,%.0f H%.0f Q%.0f,%.0f %.0f,%.0f V%.0f Q%.0f,%.0f %.0f,%.0f H%.0f"
            % (x1, y1, mx + r, mx, y1, mx, y1 + sy * r,
               y2 - sy * r, mx, y2, mx - r, y2, x2))

def rlane(col, k=0):
    """열 오른쪽 빈 차선. 노드가 없는 자리라 세로로 내려가도 안전하다."""
    return COLX[col] + W + 14 + k * 16

def llane(col, k=0):
    """열 왼쪽 빈 차선."""
    return COLX[col] - 14 - k * 16

_USED = {}

def take(base, col, y1, y2):
    """비어 있는 세로 차선을 잡는다.

    두 선이 같은 x 를 통째로 공유하면 한 줄로 보여 어디로 가는지 구분되지 않는다.
    겹치는 구간이 있으면 옆 차선으로 밀어 항상 따로 읽히게 한다.
    """
    lo, hi = min(y1, y2), max(y1, y2)
    for k in range(7):
        x = base(col, k)
        if all(lo >= b - 10 or hi <= a + 10 for a, b in _USED.get(x, ())):
            _USED.setdefault(x, []).append((lo, hi))
            return x
    return base(col, 0)

def bus(a, b, ch, ka=0, kb=0, r=9):
    """한쪽으로 나가 → 차선 → 채널 → 대상 옆 차선 → 대상의 변으로 들어간다.

    먼 엣지를 전부 같은 형태로 묶으면 어느 선이 어디로 가는지가 한눈에 읽힌다.
    진입 변은 대상 띠의 정방향을 따른다 — 상류 쪽에서 들어와야 흐름과 싸우지 않는다.
    """
    right_in = band_of(b) == 2          # 띠2는 오른쪽이 상류다
    ya = cy(a)
    yb = cy(b) + 14                     # 정방향 화살표와 겹치지 않게 살짝 아래로
    x1 = take(rlane, POS[a][0], ya, ch)
    x2 = take(rlane if right_in else llane, POS[b][0], ch, yb)
    sx = 1 if x2 > x1 else -1
    return ("M%.0f,%.0f H%.0f Q%.0f,%.0f %.0f,%.0f V%.0f Q%.0f,%.0f %.0f,%.0f "
            "H%.0f Q%.0f,%.0f %.0f,%.0f V%.0f Q%.0f,%.0f %.0f,%.0f H%.0f"
            % (x_of(a) + W, ya, x1 - r, x1, ya, x1, ya + r,
               ch - r, x1, ch, x1 + sx * r, ch,
               x2 - sx * r, x2, ch, x2, ch - r,
               yb + r, x2, yb, x2 + (r if not right_in else -r), yb,
               x_of(b) + (W if right_in else 0)))

def shape(nid, x, y):
    kind = NODES[nid].get("kind", "stage")
    o = []
    if nid in BLOCKING:
        o.append('<path d="M%d,%d h%d l16,%d l-16,%d h-%d z" fill="var(--g-hookbg)" stroke="var(--g-block)" stroke-width="2.2"/>'
                 % (x, y, W - 16, H // 2, H // 2, W - 16))
    elif kind == "hook":
        o.append('<path d="M%d,%d h%d l16,%d l-16,%d h-%d z" fill="var(--g-surface)" stroke="var(--g-hook)" stroke-width="1.6"/>'
                 % (x, y, W - 16, H // 2, H // 2, W - 16))
    elif kind in ("store", "terminal"):
        bg = "var(--g-termbg)" if kind == "terminal" else "var(--g-surface)"
        st = "var(--g-term)" if kind == "terminal" else "var(--g-store)"
        o.append('<rect x="%d" y="%d" width="%d" height="%d" rx="%d" fill="%s" stroke="%s" stroke-width="1.6"/>'
                 % (x, y, W, H, H // 2, bg, st))
    elif kind == "tool":
        o.append('<path d="M%d,%d h%d l18,%d l-18,%d h-%d l-18,-%d z" fill="var(--g-surface)" stroke="var(--g-tool)" stroke-width="1.8"/>'
                 % (x + 18, y, W - 36, H // 2, H // 2, W - 36, H // 2))
    elif kind == "agent":
        o.append('<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="var(--g-surface)" stroke="var(--g-agent)" stroke-width="1.8"/>'
                 % (x, y, W, H))
    elif kind == "skill":
        o.append('<rect x="%d" y="%d" width="%d" height="%d" rx="6" fill="var(--g-surface)" stroke="var(--g-line)" stroke-width="1.4"/>'
                 % (x, y, W, H))
        o.append('<rect x="%d" y="%d" width="3" height="%d" fill="var(--g-skill)"/>' % (x + 9, y + 11, H - 22))
    else:
        o.append('<rect x="%d" y="%d" width="%d" height="%d" rx="10" fill="var(--g-stagebg)" stroke="var(--g-stage)" stroke-width="2"/>'
                 % (x, y, W, H))
    col = {"hook": "var(--g-hook)", "store": "var(--g-store)", "tool": "var(--g-tool)",
           "terminal": "var(--g-term)", "agent": "var(--g-agent)", "skill": "var(--g-skill)"}.get(kind, "var(--g-ink)")
    if nid in BLOCKING:
        col = "var(--g-block)"
    o.append('<text class="gn" x="%.0f" y="%d" text-anchor="middle" fill="%s">%s</text>' % (x + W / 2, y + 24, col, nid))
    o.append('<text class="gk" x="%.0f" y="%d" text-anchor="middle" fill="var(--g-soft)">%s</text>' % (x + W / 2, y + 42, KO.get(nid, "")))
    return "\n".join(o)

def edge(d, kind="fwd", both=False):
    style = {
        "fwd":  ('var(--g-edge)', "1.5", "", "ga"),
        "inst": ('var(--g-inst)', "1.9", "", "gi"),
        "back": ('var(--g-back)', "1.5", ' stroke-dasharray="7 5"', "gb"),
    }[kind]
    start = ' marker-start="url(#%s)"' % ({"fwd": "gas", "inst": "gis", "back": "gbs"}[kind]) if both else ""
    return '<path d="%s" fill="none" stroke="%s" stroke-width="%s"%s marker-end="url(#%s)"%s/>' % (
        d, style[0], style[1], style[2], style[3], start)

# ── 엣지 분류 ───────────────────────────────────────────────────────
SHORTCUT = ("session-start", "build")
FORCE_BACK = {("eval-report", "lessons")}   # 의미가 되먹임이면 채널로 보낸다
# 정방향이지만 직선 코스가 막힌 엣지 — 채널로 우회하되 선 모양은 정방향 그대로 둔다
FORCE_BUS = {("harness-evaluation", "user-report")}
pairs, seen, fwd, back, cross, skipped = set(), set(), [], [], [], 0
E = [(e["from"], e["to"], bool(e.get("instrumented"))) for e in G["edges"]]
lookup = {(a, b): i for a, b, i in E}
for a, b, inst in E:
    if a in HOOKBUS or b in HOOKBUS:
        if (a, b) not in [("track-skill", "doctor")]:
            continue                                   # 훅 버스가 따로 그린다
    if a not in POS or b not in POS:
        skipped += 1
        continue
    if (b, a) in lookup and (b, a) not in seen:         # 왕복 — 한 선으로
        pairs.add((a, b)); seen.add((a, b)); continue
    if (a, b) in seen or (b, a) in seen:
        continue
    seen.add((a, b))
    if (a, b) == SHORTCUT:
        continue                                        # 상단 차선으로 따로 그린다
    if (a, b) in FORCE_BACK:
        back.append((a, b, inst)); continue
    if (a, b) in CROSS:
        cross.append((a, b, inst))
    elif POS[a][0] == POS[b][0]:
        (fwd if POS[a][1] < POS[b][1] else back).append((a, b, inst))
    elif band_of(a) == 1 and band_of(b) == 1:
        (fwd if POS[a][0] < POS[b][0] else back).append((a, b, inst))
    elif band_of(a) == 2 and band_of(b) == 2:
        (fwd if POS[a][0] > POS[b][0] else back).append((a, b, inst))
    else:
        back.append((a, b, inst))

parts = [
    '<svg viewBox="0 0 %d 1150" role="img" aria-label="'
    'workflow.graph.json 의 핵심 경로. 왼쪽에서 오른쪽으로 진행하며 열이 순서를 나타낸다. '
    '진입에서 탐색과 계획을 거쳐 준비 산출물을 만들고 구현으로 모인 뒤 검증과 교차검증으로 이어진다. '
    '구현 아래에는 훅 넷이 버스로 매달려 있고 차단하는 둘은 경고색이다. '
    '되돌아가는 선은 본문을 지나지 않고 띠 아래 전용 채널로 빠져 구현으로 합류한다. '
    '아래 띠는 피드백 루프이며 오른쪽 교훈 기록에서 왼쪽 사람에게 보고까지 되먹인다.">' % CANVAS_W,
    '<defs>',
]
for mid, col in [("ga", "--g-edge"), ("gi", "--g-inst"), ("gb", "--g-back")]:
    parts.append('<marker id="%s" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                 '<path d="M0 0 L10 5 L0 10 z" fill="var(%s)"/></marker>' % (mid, col))
    parts.append('<marker id="%ss" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                 '<path d="M10 0 L0 5 L10 10 z" fill="var(%s)"/></marker>' % (mid, col))
parts.append('</defs>')

# 띠
for (bx, by, bw, bh, label) in [(*BAND1, "작업 흐름 — 왼쪽에서 오른쪽으로"),
                                (*BAND2, "피드백 루프 — 오른쪽에서 왼쪽으로 되먹인다")]:
    parts.append('<rect x="%d" y="%d" width="%d" height="%d" rx="10" fill="var(--g-band)" stroke="var(--g-line)" stroke-width="1"/>'
                 % (bx, by, bw, bh))
    parts.append('<text class="gb" x="%d" y="%d" fill="var(--g-faint)">%s</text>' % (bx + 18, by + 24, label))

# 열 눈금 — 「무엇이 먼저인가」를 x 좌표로 답한다
parts.append('<line x1="%d" y1="72" x2="%d" y2="72" stroke="var(--g-line)" stroke-width="1"/>' % (BAND1[0], BAND1[0] + BAND1[2]))
for label, c in RULER:
    parts.append('<text class="gr" x="%.0f" y="62" text-anchor="middle" fill="var(--g-faint)">%s</text>' % (COLX[c] + W / 2, label))
    parts.append('<line x1="%.0f" y1="66" x2="%.0f" y2="78" stroke="var(--g-line)" stroke-width="1.5"/>' % (COLX[c] + W / 2, COLX[c] + W / 2))
parts.append('<text class="gr" x="%d" y="62" fill="var(--g-faint)">진행 →</text>' % (BAND1[0] + 8))

# 점선 묶음
for (gx, gy, gw, gh, glabel) in GROUPS:
    parts.append('<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="none" stroke="var(--g-agent)" stroke-width="1.2" stroke-dasharray="6 5" opacity="0.65"/>'
                 % (gx, gy, gw, gh))
    parts.append('<text class="gg" x="%d" y="%d" fill="var(--g-faint)">%s</text>' % (gx + 4, gy - 6, glabel))

# ── 엣지 ────────────────────────────────────────────────────────────
IN_Y = {}                                               # 같은 변에 여러 선이 몰리면 어긋나게 넣는다
for a, b, inst in fwd:
    ca, cb = POS[a][0], POS[b][0]
    kind = "inst" if inst else "fwd"
    if ca == cb:
        parts.append(edge("M%.0f,%d V%d" % (cx(a), y_of(a) + H, y_of(b)), kind))
        continue
    slot = IN_Y.get(b, 0); IN_Y[b] = slot + 1
    dy = (slot - 0.5) * 16 if slot else 0
    if (a, b) in FORCE_BUS:
        parts.append(edge(bus(a, b, CH2 if band_of(a) == 2 else CH1, ka=slot % 3, kb=slot % 2), kind))
        continue
    if band_of(a) == 2:
        parts.append(edge(elbow_left(a, b, k=slot), kind))
    else:
        mx = take(lambda c, k: COLX[c] + W + 16 + k * 13, ca, cy(a), cy(b) + dy)
        parts.append(edge(elbow(x_of(a) + W, cy(a), x_of(b), cy(b) + dy, mx), kind))

for a, b in sorted(pairs):
    ca, cb = POS[a][0], POS[b][0]
    if ca == cb:
        parts.append(edge("M%.0f,%d V%d" % (cx(a), y_of(a) + H, y_of(b)), "fwd", both=True))
    elif ca < cb:
        mx = COLX[ca] + W + GAP / 2
        parts.append(edge(elbow(x_of(a) + W, cy(a), x_of(b), cy(b), mx), "fwd", both=True))
    else:
        mx = COLX[cb] + W + GAP / 2
        parts.append(edge(elbow(x_of(b) + W, cy(b), x_of(a), cy(a), mx), "fwd", both=True))

for i, (a, b, inst) in enumerate(back):                  # 되돌아감 — 전용 채널
    ch = CH1 if y_of(a) < BAND2[1] else CH2
    parts.append(edge(bus(a, b, ch, ka=i % 3, kb=i % 2), "back"))

for i, (a, b, inst) in enumerate(cross):                 # 띠를 건넌다 — 같은 버스 형태
    parts.append(edge(bus(a, b, LANES[CROSS[(a, b)][0]], ka=i % 3, kb=i % 2),
                      "inst" if inst else "fwd"))

# 지름길 — 진입 조건이 충족되면 준비 단계를 통째로 건너뛴다. 상단 빈 차선으로 보낸다.
if SHORTCUT in lookup:
    a, b = SHORTCUT
    ty = 104
    parts.append(edge("M%.0f,%d V%d Q%.0f,%d %.0f,%d H%.0f Q%.0f,%d %.0f,%d V%d"
                      % (cx(a), y_of(a), ty + 9, cx(a), ty, cx(a) + 9, ty,
                         cx(b) - 9, cx(b), ty, cx(b), ty + 9, y_of(b)), "fwd"))
    parts.append('<text class="gg" x="%.0f" y="%d" text-anchor="middle" fill="var(--g-soft)">'
                 '진입 조건 4상태 충족 → 준비 단계를 건너뛴다</text>' % ((cx(a) + cx(b)) / 2, ty - 8))

# ── 훅 버스 ─────────────────────────────────────────────────────────
bus_bottom = HOOK_Y0 + HOOK_DY * (len(HOOKBUS) - 1) + H / 2
parts.append('<rect x="%d" y="%d" width="%d" height="%d" rx="8" fill="none" stroke="var(--g-hook)" stroke-width="1.1" stroke-dasharray="5 5" opacity="0.55"/>'
             % (TRUNK_X - 16, HOOK_Y0 - 22, W + 76, bus_bottom - HOOK_Y0 + 52))
parts.append('<text class="gg" x="%d" y="%d" fill="var(--g-hook)">구현하는 내내 · 기계가 실행</text>' % (TRUNK_X - 16, HOOK_Y0 - 30))
parts.append('<path d="M%.0f,%d V%.0f" fill="none" stroke="var(--g-hook)" stroke-width="1.6"/>'
             % (cx("build"), y_of("build") + H, HOOK_Y0 - 22))
parts.append('<path d="M%.0f,%d H%d V%.0f" fill="none" stroke="var(--g-hook)" stroke-width="1.6"/>'
             % (cx("build"), HOOK_Y0 - 22, TRUNK_X, bus_bottom))
for i, hid in enumerate(HOOKBUS):
    hy = HOOK_Y0 + HOOK_DY * i
    both = hid in BLOCKING
    parts.append('<path d="M%d,%.0f H%d" fill="none" stroke="var(--g-%s)" stroke-width="1.6" marker-end="url(#g%s)"%s/>'
                 % (TRUNK_X, hy + H / 2, HOOK_X, "block" if both else "hook",
                    "ba" if both else "ha", ' marker-start="url(#gbas)"' if both else ""))
for mid, col in [("gha", "--g-hook"), ("gba", "--g-block")]:
    parts.insert(9, '<marker id="%s" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                    '<path d="M0 0 L10 5 L0 10 z" fill="var(%s)"/></marker>' % (mid, col))
parts.insert(9, '<marker id="gbas" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
                '<path d="M10 0 L0 5 L10 10 z" fill="var(--g-block)"/></marker>')

# ── 노드 ────────────────────────────────────────────────────────────
for nid in POS:
    parts.append(shape(nid, x_of(nid), y_of(nid)))
for i, hid in enumerate(HOOKBUS):
    parts.append(shape(hid, HOOK_X, HOOK_Y0 + HOOK_DY * i))

# 채널 라벨 — 되돌아오는 선이 무엇인지 말해 준다
parts.append('<text class="gg" x="%d" y="%d" fill="var(--g-back)">← 결함이 나오면 구현으로 되돌아간다</text>' % (COLX[3] + 30, CH1 + 18))
parts.append('<text class="gg" x="%d" y="%d" fill="var(--g-back)">← 평가 결과가 교훈으로</text>' % (COLX[3], CH2 + 18))
parts.append('</svg>')

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(parts))
print("노드 %d개 · 진행 %d · 왕복 %d · 되돌림 %d · 띠건넘 %d → %s (%d bytes)"
      % (len(POS) + len(HOOKBUS), len(fwd), len(pairs), len(back), len(cross), OUT, OUT.stat().st_size))
if skipped:
    print("  (핵심 경로 밖이라 생략한 엣지 %d개)" % skipped)

missing = [n for n in list(POS) + HOOKBUS if n not in NODES]
if missing:
    sys.exit("그래프에 없는 노드가 POS 에 있습니다: %s" % ", ".join(missing))
