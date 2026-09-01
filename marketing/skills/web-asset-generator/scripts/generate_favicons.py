#!/usr/bin/env python3
"""로고 이미지 → favicon 세트 생성.

사용: generate_favicons.py <logo_path> <out_dir> <sizes|all> [--validate]
  sizes: 쉼표 구분 (예: 16,32,180) 또는 all
생성물: favicon-{N}x{N}.png · apple-touch-icon.png(180) ·
        android-chrome-{192,512}x*.png · favicon.ico(16+32+48)
"""
import sys
from pathlib import Path

FULL_SET = [16, 32, 48, 180, 192, 512]
NAMED = {180: "apple-touch-icon.png",
         192: "android-chrome-192x192.png",
         512: "android-chrome-512x512.png"}

def main() -> int:
    if len(sys.argv) < 4:
        print(__doc__); return 2
    logo, out_dir, sizes_arg = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    validate = "--validate" in sys.argv[4:]
    if not logo.is_file():
        print(f"FAIL 로고 없음: {logo}"); return 2

    from PIL import Image
    sizes = FULL_SET if sizes_arg == "all" else sorted({int(s) for s in sizes_arg.split(",")})
    out_dir.mkdir(parents=True, exist_ok=True)

    src = Image.open(logo).convert("RGBA")
    # 정사각 캔버스로 패딩 (파비콘은 정사각이어야 브라우저가 왜곡하지 않음)
    side = max(src.size)
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(src, ((side - src.width) // 2, (side - src.height) // 2))

    made = []
    for n in sizes:
        img = canvas.resize((n, n), Image.LANCZOS)
        name = NAMED.get(n, f"favicon-{n}x{n}.png")
        img.save(out_dir / name, "PNG")
        made.append(out_dir / name)
    ico_sizes = [(n, n) for n in (16, 32, 48) if n in sizes] or [(32, 32)]
    canvas.resize((48, 48), Image.LANCZOS).save(out_dir / "favicon.ico", sizes=ico_sizes)
    made.append(out_dir / "favicon.ico")

    for f in made:
        print(f"OK {f} ({f.stat().st_size:,}B)")

    if validate:
        fails = 0
        for f in made:
            if f.stat().st_size == 0:
                print(f"VALIDATE-FAIL 빈 파일: {f}"); fails += 1
            elif f.suffix == ".png":
                w, h = Image.open(f).size
                if w != h:
                    print(f"VALIDATE-FAIL 비정사각 {w}x{h}: {f}"); fails += 1
        big = [f for f in made if f.stat().st_size > 100_000]
        for f in big:
            print(f"VALIDATE-WARN 100KB 초과 ({f.stat().st_size:,}B): {f}")
        print(f"VALIDATE {'FAIL' if fails else 'PASS'} — 파일 {len(made)}개, 실패 {fails}")
        return 1 if fails else 0
    return 0

if __name__ == "__main__":
    sys.exit(main())
