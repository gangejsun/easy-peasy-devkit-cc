#!/usr/bin/env node

/**
 * scripts/pre-tool-use-guard.mjs
 * @harness-type: configurable (epcc.config.json 참조)
 *
 * PreToolUse Hook: domain-boundaries 규칙을 동적으로 강제
 *
 * 기능:
 * 1. 공유 패키지 무단 수정 차단 + 허용 목록 지원
 * 2. 도메인 패턴 확인 가이드 (기존 코드 읽기 유도)
 *
 * epcc.config.json 참조:
 * - domains.sourceDir: 소스 디렉토리 경로
 * - domains.sharedPackage: 공유 패키지 경로
 * - domains.importAlias: import 별칭
 *
 * 실행 시점: Claude가 Edit/Write 도구 사용 직전
 * 토큰 사용: 0T (패턴 가이드 시 ~50T additionalContext)
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve, relative } from 'node:path';
import { execSync } from 'node:child_process';
import { loadConfig, readStdin, getProjectRoot } from './lib/config-loader.mjs';

// ─── Main ────────────────────────────────────────────────────────────

async function main() {
  const input = await readStdin();

  const toolName = input.tool_name || '';
  const filePath = input.tool_input?.file_path || '';

  // Edit/Write 도구만 검증
  if (!['Edit', 'Write'].includes(toolName)) {
    process.exit(0);
  }

  // 파일 경로가 없으면 통과
  if (!filePath) {
    process.exit(0);
  }

  const config = loadConfig();
  const projectRoot = getProjectRoot();
  const relPath = relative(projectRoot, resolve(filePath));

  // ─── 공유 패키지 수정 차단 ────────────────────────────────────

  const sharedPackage = config.domains?.sharedPackage;

  if (sharedPackage && relPath.startsWith(sharedPackage + '/')) {
    // 허용 목록 확인
    const allowlistPath = resolve(
      projectRoot, '.claude', 'governance', 'dynamic-rules', 'shared-allowlist.json'
    );

    if (existsSync(allowlistPath)) {
      try {
        const allowlist = JSON.parse(readFileSync(allowlistPath, 'utf-8'));
        if (allowlist.allowed_files?.includes(relPath)) {
          process.exit(0); // 허용 목록에 있으면 통과
        }
      } catch { /* ignore */ }
    }

    // 차단
    process.stderr.write(
      `\u274C ERROR: ${sharedPackage}/ \uD328\uD0A4\uC9C0 \uC218\uC815 \uCC28\uB2E8\uB428\n\n` +
      `\uD83D\uDCCB \uACF5\uC720 \uD328\uD0A4\uC9C0\uB294 \uC804\uCCB4 \uD504\uB85C\uC81D\uD2B8\uC5D0 \uC601\uD5A5\uC744 \uC8FC\uBBC0\uB85C \uC2E0\uC911\uD55C \uAC80\uD1A0\uAC00 \uD544\uC694\uD569\uB2C8\uB2E4.\n\n` +
      `\uD83D\uDCA1 \uC218\uC815\uC774 \uD544\uC694\uD55C \uACBD\uC6B0:\n` +
      `  1. \uC0AC\uC6A9\uC790\uC5D0\uAC8C \uC218\uC815 \uC774\uC720 \uC124\uBA85\n` +
      `  2. \uC601\uD5A5 \uBC94\uC704 \uBD84\uC11D\n` +
      `  3. \uC0AC\uC6A9\uC790 \uC2B9\uC778 \uD68D\uB4DD\n` +
      `  4. .claude/governance/dynamic-rules/shared-allowlist.json\uC5D0 \uD30C\uC77C \uCD94\uAC00\n`
    );
    process.exit(2);
  }

  // ─── 도메인 패턴 확인 가이드 ──────────────────────────────────

  const sourceDir = config.domains?.sourceDir || 'src';

  // 도메인 추출 (sourceDir 기반)
  let domain = '';
  const domainPatterns = [
    new RegExp(`^${sourceDir}/components/([^/]+)/`),
    new RegExp(`^${sourceDir}/app/\\([^)]+\\)/([^/]+)/`),
    new RegExp(`^${sourceDir}/app/([^/]+)/`),
    new RegExp(`^${sourceDir}/lib/actions/([a-zA-Z]+)`),
    new RegExp(`^${sourceDir}/routers/([^/]+)/`),
    new RegExp(`^${sourceDir}/services/([^/]+)/`),
    // Python FastAPI 패턴
    /^app\/routers\/([^/]+)/,
    /^app\/services\/([^/]+)/,
  ];

  for (const pattern of domainPatterns) {
    const match = relPath.match(pattern);
    if (match) {
      domain = match[1];
      break;
    }
  }

  // 도메인 없는 파일 (config, shared 등) 또는 .claude/ 내부 파일은 스킵
  if (!domain || relPath.startsWith('.claude/')) {
    process.exit(0);
  }

  // 도메인 내 기존 파일 탐색 (최대 5개, 수정 대상 제외)
  let relatedFiles = [];
  try {
    const codeExtensions = '\\( -name "*.tsx" -o -name "*.ts" -o -name "*.jsx" -o -name "*.js" -o -name "*.py" \\)';
    const result = execSync(
      `find "${resolve(projectRoot, sourceDir)}" -type f ${codeExtensions} ` +
      `-path "*${domain}*" ! -path "*/__tests__/*" ! -path "*node_modules*" ` +
      `! -path "${resolve(projectRoot, filePath)}" ! -name "*.test.*" ! -name "*.spec.*" 2>/dev/null | head -5`,
      { encoding: 'utf-8', timeout: 3000 }
    ).trim();
    if (result) {
      relatedFiles = result.split('\n').map(f => relative(projectRoot, f));
    }
  } catch { /* ignore find errors */ }

  // 기존 파일 없으면 (완전히 새 도메인) 스킵
  if (relatedFiles.length === 0) {
    process.exit(0);
  }

  // Read 로그 확인: 이 세션에서 관련 도메인 파일을 읽었는지
  const sessionId = process.env.CLAUDE_SESSION_ID || 'default';
  const readLogPath = `/tmp/read-files-${sessionId}.log`;
  let readAny = false;

  if (existsSync(readLogPath)) {
    try {
      const readLog = readFileSync(readLogPath, 'utf-8');
      readAny = relatedFiles.some(f => readLog.includes(f));
    } catch { /* ignore */ }
  }

  // 안 읽었으면 additionalContext로 안내 (차단하지 않음)
  if (!readAny) {
    const fileList = relatedFiles.map(f => `- ${f}`).join('\n');
    const output = {
      hookSpecificOutput: {
        hookEventName: 'PreToolUse',
        additionalContext:
          `\u26A0\uFE0F \uB3C4\uBA54\uC778 [${domain}] \uC218\uC815 \uC804 \uAE30\uC874 \uD328\uD134 \uD655\uC778 \uD544\uC694\n\n` +
          `\uB2E4\uC74C \uD30C\uC77C \uC911 \uCD5C\uC18C 1\uAC1C\uB97C Read\uB85C \uBA3C\uC800 \uD655\uC778\uD558\uC138\uC694:\n${fileList}\n\n` +
          `\uD655\uC778 \uD6C4 \uB3D9\uC77C \uD328\uD134(\uB124\uC774\uBC0D, import, Props \uAD6C\uC870, \uC5D0\uB7EC \uD578\uB4E4\uB9C1)\uC744 \uB530\uB77C \uAD6C\uD604\uD558\uC138\uC694.`,
      },
    };
    process.stdout.write(JSON.stringify(output));
  }

  // 통과
  process.exit(0);
}

main().catch(() => process.exit(0));
