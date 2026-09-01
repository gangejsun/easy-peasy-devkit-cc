#!/bin/bash
# 비디오 → 스크롤 애니메이션용 프레임 시퀀스 추출.
# 사용: extract-frames.sh <VIDEO_PATH> <OUTPUT_DIR> [TARGET_FPS=12]
# 전제 조건(FFmpeg·비디오 실재·길이 3~10초)을 여기서 검증한다 — 실패는 즉시, 구체적으로.
set -u

VIDEO="${1:-}"; OUT="${2:-}"; FPS="${3:-12}"

command -v ffmpeg >/dev/null 2>&1 || { echo "FAIL FFmpeg 미설치 — brew install ffmpeg"; exit 2; }
command -v ffprobe >/dev/null 2>&1 || { echo "FAIL ffprobe 미설치 (ffmpeg 패키지에 포함)"; exit 2; }
[ -f "$VIDEO" ] || { echo "FAIL 비디오 없음: $VIDEO"; exit 2; }
case "$FPS" in ''|*[!0-9]*) echo "FAIL TARGET_FPS는 정수: $FPS"; exit 2;; esac

DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$VIDEO" 2>/dev/null | cut -d. -f1)
case "$DUR" in ''|*[!0-9]*) DUR=0;; esac
if [ "$DUR" -lt 3 ] || [ "$DUR" -gt 10 ]; then
  echo "WARN 권장 길이 3~10초 벗어남 (${DUR}초) — 프레임 수가 스크롤 UX에 부적합할 수 있음"
fi

mkdir -p "$OUT" || { echo "FAIL 출력 디렉토리 생성 실패: $OUT"; exit 2; }

# WebP 시퀀스 — JPEG 대비 ~40% 작아 페이지 로드에 유리. 폭 1600 상한(레티나 절충)
ffmpeg -y -v error -i "$VIDEO" -vf "fps=${FPS},scale='min(1600,iw)':-2" \
  -c:v libwebp -quality 82 "$OUT/frame-%04d.webp" || { echo "FAIL ffmpeg 추출 실패"; exit 2; }

N=$(ls "$OUT"/frame-*.webp 2>/dev/null | wc -l | tr -d ' ')
TOTAL=$(du -sh "$OUT" 2>/dev/null | cut -f1)
echo "OK 프레임 ${N}개 (${FPS}fps · 총 ${TOTAL}) → $OUT"
[ "$N" -gt 0 ] || { echo "FAIL 프레임 0개"; exit 2; }
echo "frameCount=${N}"
