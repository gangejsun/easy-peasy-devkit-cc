#!/usr/bin/env node

/**
 * scripts/security-check.mjs
 * @harness-type: configurable (epcc.config.json 참조)
 *
 * PreToolUse Hook: security 규칙을 보완하는 최후 방어선
 *
 * 목적: Rule(사전 교육)을 통과한 명백한 보안 실수만 차단
 * 전략: epcc.config.json의 security.secretPatterns에서 동적 패턴 로드
 *
 * 실행 시점: Claude가 Edit/Write 도구 사용 직전
 * 토큰 사용: 0T
 */

import { loadConfig, readStdin } from './lib/config-loader.mjs';

// ─── Main ────────────────────────────────────────────────────────────

async function main() {
  const input = await readStdin();

  const toolName = input.tool_name || '';
  const filePath = input.tool_input?.file_path || '';
  const content = input.tool_input?.content || '';
  const newString = input.tool_input?.new_string || '';

  // Edit/Write 도구만 검증
  if (!['Edit', 'Write'].includes(toolName)) {
    process.exit(0);
  }

  // 검사 대상 텍스트 결합
  const searchText = content + newString;

  // ─── Config에서 패턴 로드 ──────────────────────────────────────

  const config = loadConfig();
  const patterns = config.security?.secretPatterns || [];

  // ─── 기본 내장 패턴 (config 패턴과 병합) ─────────────────────

  const builtinPatterns = [
    { name: 'AWS Access Key ID', pattern: 'AKIA[0-9A-Z]{16}', action: 'block' },
    { name: 'GitHub PAT', pattern: 'ghp_[a-zA-Z0-9]{36}', action: 'block' },
    { name: 'Generic API Key', pattern: '(?:api[_-]?key|apikey)\\s*[:=]\\s*["\'][a-zA-Z0-9]{20,}', action: 'warn' },
  ];

  // config 패턴이 있으면 builtin과 병합, 없으면 builtin만 사용
  const allPatterns = patterns.length > 0
    ? [...builtinPatterns, ...patterns.filter(p => !builtinPatterns.some(b => b.pattern === p.pattern))]
    : builtinPatterns;

  // ─── 패턴 매칭 ────────────────────────────────────────────────

  for (const sp of allPatterns) {
    try {
      const regex = new RegExp(sp.pattern);
      if (regex.test(searchText)) {
        if (sp.action === 'block') {
          process.stderr.write(
            `\u274C ERROR: ${sp.name} \uD558\uB4DC\uCF54\uB529 \uAC10\uC9C0!\n\n` +
            `\uD83D\uDD12 \uAC10\uC9C0\uB41C \uD328\uD134: ${sp.pattern}\n\n` +
            `\u2705 \uC62C\uBC14\uB978 \uBC29\uBC95:\n` +
            `  1. \uD658\uACBD \uBCC0\uC218 \uC0AC\uC6A9\n` +
            `  2. .env \uD30C\uC77C\uC5D0 \uC800\uC7A5 (.gitignore \uD544\uC218)\n`
          );
          process.exit(2); // 차단
        } else {
          // warn: 경고만, 차단하지 않음
          process.stderr.write(
            `\u26A0\uFE0F WARNING: ${sp.name} \uC758\uC2EC \uD328\uD134 \uAC10\uC9C0\n\n` +
            `\uD83D\uDD12 \uD328\uD134: ${sp.pattern}\n\n` +
            `\u2705 \uD655\uC778 \uC0AC\uD56D:\n` +
            `  - \uC2E4\uC81C \uC2DC\uD06C\uB9BF\uC778\uAC00\uC694? \u2192 \uD658\uACBD \uBCC0\uC218\uB85C \uC774\uB3D9\n` +
            `  - \uD14C\uC2A4\uD2B8 \uB370\uC774\uD130\uC778\uAC00\uC694? \u2192 \uC8FC\uC11D\uC73C\uB85C \uBA85\uC2DC\n`
          );
        }
      }
    } catch {
      // 잘못된 정규식은 무시
    }
  }

  // ─── .env 파일 차단 ───────────────────────────────────────────

  if (/\.env$/.test(filePath) && !/\.env\.(example|template)$/.test(filePath)) {
    process.stderr.write(
      `\u26A0\uFE0F WARNING: .env \uD30C\uC77C \uC218\uC815 \uAC10\uC9C0!\n\n` +
      `\uD83D\uDCCB \uD30C\uC77C: ${filePath}\n\n` +
      `\u2705 \uD655\uC778 \uC0AC\uD56D:\n` +
      `  1. .gitignore\uC5D0 .env \uD3EC\uD568 \uC5EC\uBD80 \uD655\uC778\n` +
      `  2. .env.example\uC740 OK, .env\uB294 Git \uCEE4\uBC0B \uAE08\uC9C0\n`
    );
    // WARNING만, 차단하지 않음
  }

  // 통과
  process.exit(0);
}

main().catch(() => process.exit(0));
