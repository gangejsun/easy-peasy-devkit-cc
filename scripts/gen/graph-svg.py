#!/usr/bin/env python3
"""workflow.graph.json → 작업 흐름 SVG.

레이아웃은 손으로 정하고(POS), 라벨·kind·엣지는 그래프에서 읽는다.
자산이 늘거나 이름이 바뀌면 다시 돌리면 된다 — 사본을 손으로 고치지 않는다.
"""
import json, pathlib, sys

G = json.load(open(sys.argv[1] if len(sys.argv) > 1 else "workflow.graph.json"))
NODES = {n["id"]: n for n in G["nodes"]}

W, H = 200, 56          # 노드 박스
BAND1 = (44, 40, 1512, 620)   # x, y, w, h
BAND2 = (44, 700, 1512, 366)

# ── 한글 라벨 · 위치 (x, y = 박스 좌상단) ───────────────────────────
KO = {
    "session-start": "세션 시작 브리핑", "understand": "탐색", "plan": "계획",
    "build": "구현", "verify": "리뷰 맡김", "cross-check": "리뷰어의 추가 단계",
    "epcc-planner": "설계 위임", "epcc-reviewer": "독립 리뷰",
    "security-check": "시크릿·파괴 명령 차단", "build-gate": "검증 게이트",
    "track-skill": "스킬 사용 기록", "handoff": "핸드오프",
    "prd-generator": "PRD 생성", "dev-docs-generator": "개발 문서",
    "ui-ux-design": "디자인 시스템", "completion-review": "마무리 문서화",
    "codex-claude-loop": "외부 모델 검증", "receiving-code-review": "받은 지적 검증",
    "doctor": "자기검증", "lessons": "교훈 기록", "eval-report": "평가 보고",
    "rule-promotion": "자산 승격", "user-report": "사람에게 보고",
    "harness-evaluation": "하네스 평가", "skill-enhancer": "스킬 재설계",
}
POS = {
    # ── 작업 흐름 ──
    "session-start":        (60, 300),
    "understand":           (320, 96),
    "plan":                 (320, 186),
    "prd-generator":        (60, 452),
    "dev-docs-generator":   (60, 542),
    "epcc-planner":         (320, 372),
    "ui-ux-design":         (320, 486),
    "security-check":       (620, 76),
    "build":                (620, 236),
    "build-gate":           (620, 336),
    "track-skill":          (620, 436),
    "handoff":              (620, 526),
    "completion-review":    (920, 96),
    "verify":               (920, 246),
    "epcc-reviewer":        (1230, 96),
    "cross-check":          (1230, 246),
    "codex-claude-loop":    (1230, 396),
    "receiving-code-review":(1230, 506),
    # ── 피드백 루프 ──
    "lessons":              (1240, 744),
    "doctor":               (900, 748),
    "rule-promotion":       (560, 744),
    "user-report":          (160, 744),
    "harness-evaluation":   (900, 936),
    "eval-report":          (560, 940),
    "skill-enhancer":       (200, 936),
}
BLOCKING = {"security-check", "build-gate"}
GROUPS = [
    (300, 348, 240, 104, "서브에이전트 · 별도 컨텍스트"),
    (1210, 72, 240, 108, "서브에이전트 · 별도 컨텍스트"),
    (1210, 222, 240, 340, "Irreversible 전용 묶음"),
]

def anchors(x, y, w=W, h=H):
    return dict(l=(x, y + h / 2), r=(x + w, y + h / 2),
                t=(x + w / 2, y), b=(x + w / 2, y + h))

def pick(a, b):
    """두 박스 사이에서 가장 짧고 겹치지 않는 앵커 쌍을 고른다."""
    ax, ay = a; bx, by = b
    A, B = anchors(*a), anchors(*b)
    dx, dy = bx - ax, by - ay
    if abs(dx) > 90:
        return (A["r"], B["l"]) if dx > 0 else (A["l"], B["r"])
    return (A["b"], B["t"]) if dy > 0 else (A["t"], B["b"])

def curve(p, q):
    (x1, y1), (x2, y2) = p, q
    if abs(x2 - x1) >= abs(y2 - y1):
        k = max(46, abs(x2 - x1) * 0.45)
        s = 1 if x2 >= x1 else -1
        return f"M{x1:.0f},{y1:.0f} C{x1+s*k:.0f},{y1:.0f} {x2-s*k:.0f},{y2:.0f} {x2:.0f},{y2:.0f}"
    k = max(46, abs(y2 - y1) * 0.45)
    s = 1 if y2 >= y1 else -1
    return f"M{x1:.0f},{y1:.0f} C{x1:.0f},{y1+s*k:.0f} {x2:.0f},{y2-s*k:.0f} {x2:.0f},{y2:.0f}"

def shape(nid, x, y):
    """kind 가 모양을 정한다 — 어디서 보든 같은 모양이면 같은 종류다."""
    kind = NODES[nid].get("kind", "stage")
    out = []
    if nid in BLOCKING:                      # 차단 훅 — 깃발형 + 경고색
        out.append(f'<path d="M{x},{y} h{W-16} l16,{H/2:.0f} l-16,{H/2:.0f} h-{W-16} z" '
                   f'fill="var(--g-hookbg)" stroke="var(--g-block)" stroke-width="2.2"/>')
    elif kind == "hook":                     # 훅 — 깃발형
        out.append(f'<path d="M{x},{y} h{W-16} l16,{H/2:.0f} l-16,{H/2:.0f} h-{W-16} z" '
                   f'fill="var(--g-surface)" stroke="var(--g-hook)" stroke-width="1.6"/>')
    elif kind == "store":                    # 저장소 — 원통
        out.append(f'<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="{H/2:.0f}" '
                   f'fill="var(--g-surface)" stroke="var(--g-store)" stroke-width="1.6"/>')
    elif kind == "tool":                     # 도구 — 육각
        out.append(f'<path d="M{x+18},{y} h{W-36} l18,{H/2:.0f} l-18,{H/2:.0f} h-{W-36} l-18,-{H/2:.0f} z" '
                   f'fill="var(--g-surface)" stroke="var(--g-tool)" stroke-width="1.8"/>')
    elif kind == "terminal":                 # 종단 — 알약
        out.append(f'<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="{H/2:.0f}" '
                   f'fill="var(--g-termbg)" stroke="var(--g-term)" stroke-width="1.6"/>')
    elif kind == "agent":                    # 에이전트
        out.append(f'<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="8" '
                   f'fill="var(--g-surface)" stroke="var(--g-agent)" stroke-width="1.8"/>')
    elif kind == "skill":                    # 스킬 — 왼쪽 바
        out.append(f'<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="6" '
                   f'fill="var(--g-surface)" stroke="var(--g-line)" stroke-width="1.4"/>')
        out.append(f'<rect x="{x+9}" y="{y+11}" width="3" height="{H-22}" fill="var(--g-skill)"/>')
    else:                                    # 스테이지 — 라운드 렉트, 굵게
        out.append(f'<rect x="{x}" y="{y}" width="{W}" height="{H}" rx="10" '
                   f'fill="var(--g-stagebg)" stroke="var(--g-stage)" stroke-width="2"/>')
    col = {"hook": "var(--g-hook)", "store": "var(--g-store)", "tool": "var(--g-tool)",
           "terminal": "var(--g-term)", "agent": "var(--g-agent)", "skill": "var(--g-skill)"}\
          .get(kind, "var(--g-ink)")
    if nid in BLOCKING:
        col = "var(--g-block)"
    cx = x + W / 2
    out.append(f'<text class="gn" x="{cx:.0f}" y="{y+24}" text-anchor="middle" fill="{col}">{nid}</text>')
    out.append(f'<text class="gk" x="{cx:.0f}" y="{y+42}" text-anchor="middle" fill="var(--g-soft)">'
               f'{KO.get(nid, "")}</text>')
    return "\n".join(out)

# ── 조립 ────────────────────────────────────────────────────────────
parts = [
  '<svg viewBox="0 0 1600 1090" role="img" aria-label="'
  'workflow.graph.json 의 핵심 경로를 노드와 엣지로 그린 그림. 위 띠는 작업 흐름으로 세션 시작에서 '
  '탐색·계획을 거쳐 구현으로 모이고 검증과 교차검증으로 이어진다. 구현 주변에 훅 네 개가 붙어 있고 '
  '차단하는 둘은 경고색이다. 아래 띠는 피드백 루프로 계측이 doctor 로, doctor 가 평가와 자산 승격으로, '
  '결과가 사람에게 보고된다. 모양이 자산 종류를 나타내고 청록 엣지만 코드가 실제로 방출한다.">',
  '<defs>',
  '<marker id="ga" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7.5" markerHeight="7.5" orient="auto-start-reverse">'
  '<path d="M0 0 L10 5 L0 10 z" fill="var(--g-edge)"/></marker>',
  '<marker id="gi" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7.5" markerHeight="7.5" orient="auto-start-reverse">'
  '<path d="M0 0 L10 5 L0 10 z" fill="var(--g-inst)"/></marker>',
  '</defs>',
]
# 띠
for (bx, by, bw, bh, label) in [(*BAND1, "작업 흐름"), (*BAND2, "피드백 루프 — 하네스가 자기를 고치는 곳")]:
    parts.append(f'<rect x="{bx}" y="{by}" width="{bw}" height="{bh}" rx="10" '
                 f'fill="var(--g-band)" stroke="var(--g-line)" stroke-width="1"/>')
    parts.append(f'<text class="gb" x="{bx+18}" y="{by+24}" fill="var(--g-faint)">{label}</text>')
parts.append(f'<line x1="{BAND1[0]}" y1="{BAND1[1]+BAND1[3]+40}" x2="{BAND1[0]+BAND1[2]}" '
             f'y2="{BAND1[1]+BAND1[3]+40}" stroke="var(--g-line)" stroke-width="1" stroke-dasharray="3 7"/>')
# 점선 묶음
for (gx, gy, gw, gh, glabel) in GROUPS:
    parts.append(f'<rect x="{gx}" y="{gy}" width="{gw}" height="{gh}" rx="8" fill="none" '
                 f'stroke="var(--g-agent)" stroke-width="1.2" stroke-dasharray="6 5" opacity=".7"/>')
    parts.append(f'<text class="gg" x="{gx+4}" y="{gy-6}" fill="var(--g-faint)">{glabel}</text>')

# 엣지 먼저(노드 아래에 깔린다)
drawn = 0
for e in G["edges"]:
    a, b = e["from"], e["to"]
    if a not in POS or b not in POS:
        continue
    p, q = pick(POS[a], POS[b])
    inst = e.get("instrumented")
    stroke = "inst" if inst else "edge"
    width = "1.7" if inst else "1.3"
    op = "" if inst else 'opacity="0.85" '
    mk = "gi" if inst else "ga"
    parts.append('<path d="%s" fill="none" stroke="var(--g-%s)" stroke-width="%s" %smarker-end="url(#%s)"/>'
                 % (curve(p, q), stroke, width, op, mk))
    drawn += 1

for nid, (x, y) in POS.items():
    parts.append(shape(nid, x, y))
parts.append("</svg>")

pathlib.Path("parts/graph.svg").write_text("\n".join(parts))
print("노드 %d개 · 엣지 %d개 → parts/graph.svg (%d bytes)"
      % (len(POS), drawn, pathlib.Path("parts/graph.svg").stat().st_size))
