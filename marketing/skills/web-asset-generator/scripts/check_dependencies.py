#!/usr/bin/env python3
"""web-asset-generator 의존성 확인. Pillow 부재 시 exit 2 + 설치 안내."""
import sys

def main() -> int:
    try:
        import PIL
        from PIL import Image  # noqa: F401
        print(f"OK Pillow {PIL.__version__}")
        return 0
    except ImportError:
        print("MISSING Pillow — 설치: pip3 install Pillow (또는 uv pip install Pillow)")
        return 2

if __name__ == "__main__":
    sys.exit(main())
