#!/usr/bin/env python3
"""docs/manual/ 의 Pages 판에서 아티팩트본·다운로드본을 파생한다.

같은 페이지가 세 곳에 놓이는데 **언어 전환 링크의 형태가 서로 다르다**:

  Pages     상대 경로        en/user.html · ../user.html
  아티팩트   절대 URL         각 아티팩트는 별도 URL이라 상대 경로가 죽는다
  다운로드   로컬 파일명       같은 폴더에 나란히 놓이므로 파일명으로 잇는다

손으로 맞추면 한 곳이 반드시 빠진다 — 실제로 한국어 다운로드본에 English 링크가
없었고, 영어 아티팩트의 링크는 아무 데도 가지 않았다. 그래서 한 곳에서 파생한다.

사용:
  python3 scripts/gen/manual-variants.py [--artifact-dir DIR] [--download-dir DIR]
"""
import pathlib, re, sys, shutil

SRC = pathlib.Path("docs/manual")
args = sys.argv[1:]
def opt(name, default):
    return args[args.index(name) + 1] if name in args else default
ART_DIR = pathlib.Path(opt("--artifact-dir", "/tmp/epcc-manual-artifact"))
DL_DIR  = pathlib.Path(opt("--download-dir", str(pathlib.Path.home() / "Downloads")))

# 각 페이지의 아티팩트 URL — 새로 발행하면 여기만 고친다
ARTIFACT = {
    "user.html":    "https://claude.ai/code/artifact/692f95f0-40eb-4ebc-8699-0da5dde6d606",
    "ops.html":     "https://claude.ai/code/artifact/e64618f3-1748-4ee3-a805-e614a4fae8fc",
    "en/user.html": "https://claude.ai/code/artifact/6adc852e-f3ea-4e36-ba2e-57db69915cf8",
    "en/ops.html":  "https://claude.ai/code/artifact/d7ec6155-0e08-4b37-ad68-d2209bb7495c",
}
DOWNLOAD = {
    "user.html":    "EPCC-작업지도-사용자용.html",
    "ops.html":     "EPCC-관리자지도.html",
    "en/user.html": "EPCC-HarnessMap-EN.html",
    "en/ops.html":  "EPCC-AdminMap-EN.html",
}
# 페이지별 「이 상대 링크는 어느 페이지를 가리키는가」
LINKS = {
    "user.html":    {"en/user.html": "en/user.html", "ops.html": "ops.html"},
    "ops.html":     {"en/ops.html": "en/ops.html",   "user.html": "user.html"},
    "en/user.html": {"../user.html": "user.html",    "ops.html": "en/ops.html"},
    "en/ops.html":  {"../ops.html": "ops.html",      "user.html": "en/user.html"},
}

def rewrite(text, page, table):
    """상대 링크를 대상 표면에 맞는 주소로 바꾼다. 하나라도 못 바꾸면 알린다."""
    missed = []
    for href, target in LINKS[page].items():
        pat = 'href="%s"' % href
        if pat not in text:
            missed.append(href); continue
        text = text.replace(pat, 'href="%s"' % table[target])
    return text, missed

def check(text, page, label):
    """언어 전환이 양방향으로 살아 있는지 — 없는 것은 없다고 말한다."""
    other_lang = "en/" in page or page.startswith("en/")
    want = "한국어" if page.startswith("en/") else "English"
    if want not in text:
        print("  ✗ %-14s %s: 언어 전환 링크 없음 (%s)" % (page, label, want))
        return 1
    return 0

bad = 0
ART_DIR.mkdir(parents=True, exist_ok=True)
for page in LINKS:
    src = SRC / page
    if not src.exists():
        print("  ✗ 원본 없음: %s" % src); bad += 1; continue
    raw = src.read_text()

    art, m1 = rewrite(raw, page, ARTIFACT)
    dl,  m2 = rewrite(raw, page, DOWNLOAD)
    for href in set(m1 + m2):
        print("  ! %-14s 치환 대상 링크를 찾지 못함: %s" % (page, href)); bad += 1

    ap = ART_DIR / (page.replace("/", "-"))
    ap.write_text(art)
    dp = DL_DIR / DOWNLOAD[page]
    dp.write_text(dl)
    bad += check(art, page, "artifact")
    bad += check(dl, page, "download")
    bad += check(raw, page, "pages")
    print("  %-14s → %-34s · %s" % (page, ap.name, DOWNLOAD[page]))

print("\n아티팩트본 %s · 다운로드본 %s" % (ART_DIR, DL_DIR))
if bad:
    sys.exit("문제 %d건 — 위를 보세요" % bad)
print("언어 전환 링크: 세 표면 모두 양방향 확인")
