#!/bin/bash
# .claude/hooks/post-tool-use-tracker.sh
# @harness-type: portable
# PostToolUse(Edit|Write) 시 수정된 파일을 추적 기록
# Stop hook에서 빌드/테스트 판단 근거로 활용

SESSION_ID="${CLAUDE_SESSION_ID:-default}"
LOG_FILE="/tmp/modified-files-${SESSION_ID}.log"

# stdin에서 tool use 정보 읽기
INPUT=$(cat /dev/stdin 2>/dev/null)

# tool_input.file_path 추출 (Edit, Write 모두 file_path 사용)
FILE_PATH=$(echo "$INPUT" | node -e "
  const chunks = [];
  process.stdin.on('data', c => chunks.push(c));
  process.stdin.on('end', () => {
    try {
      const data = JSON.parse(Buffer.concat(chunks).toString());
      const fp = data.tool_input?.file_path || '';
      if (fp) process.stdout.write(fp);
    } catch {}
  });
" 2>/dev/null)

if [ -n "$FILE_PATH" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $FILE_PATH" >> "$LOG_FILE"
fi

# 7일 이상 된 로그 파일 정리
find /tmp -name "modified-files-*.log" -mtime +7 -delete 2>/dev/null
