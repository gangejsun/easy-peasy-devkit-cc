#!/usr/bin/env node

/**
 * scripts/session-start.mjs
 *
 * SessionStart Hook — 런타임 플러그인의 핵심 허브
 *
 * 역할:
 *   1. epcc.config.json 읽기 (없으면 Zero-config 모드)
 *   2. 활성 프리셋 스킬 라우팅 컨텍스트 출력
 *   3. 비활성 스킬 목록 출력 (Claude가 호출하지 않도록)
 *   4. dev/active/ 진행 중 작업 감지
 *   5. 도메인 경계 값 주입 (Configurable Rule 대체)
 *   6. CLAUDE.md 존재 여부 체크
 *
 * 실행 시점: Claude Code 세션 시작 시
 * 토큰 사용: ~100-300T
 */

import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { loadConfig, getProjectRoot } from './lib/config-loader.mjs';

// ─── 프리셋별 스킬 매핑 ─────────────────────────────────────────────

const PRESET_SKILLS = {
  'nextjs-supabase': [
    'nextjs-frontend-guide',
    'nextjs-backend-guide',
    'nextjs-ui-ux-design',
  ],
  'react-vite': [
    'react-vite-frontend-guide',
    'react-vite-backend-guide',
  ],
  'python-fastapi': [
    'python-fastapi-backend-guide',
  ],
  'blank': [],
};

// 모든 프리셋 스킬 (비활성 목록 산출용)
const ALL_PRESET_SKILLS = Object.values(PRESET_SKILLS).flat();

// ─── Main ────────────────────────────────────────────────────────────

function main() {
  const projectRoot = getProjectRoot();
  const config = loadConfig();
  const preset = config.techStack?.preset || 'blank';
  const hasConfig = existsSync(resolve(projectRoot, 'epcc.config.json'));

  const output = [];

  // ─── 헤더 ─────────────────────────────────────────────────────

  if (hasConfig) {
    output.push(`## EPCC Devkit Active (Runtime Plugin)`);
    output.push('');
    if (config.project?.name) {
      output.push(`**Project**: ${config.project.name}`);
    }
    output.push(`**Preset**: ${preset}`);
    if (config.techStack?.framework) {
      const stack = [config.techStack.framework];
      if (config.techStack.language) stack.push(config.techStack.language);
      output.push(`**Tech Stack**: ${stack.join(' + ')}`);
    }
    if (config.project?.language && config.project.language !== 'en') {
      output.push(`**Response Language**: ${config.project.language}`);
    }
    output.push('');
  } else {
    output.push(`## EPCC Devkit Active (No Config)`);
    output.push('');
    output.push('No `epcc.config.json` found. Core workflow active with defaults.');
    output.push('To customize: run `/epcc-init` or create `epcc.config.json` manually.');
    output.push('');
  }

  // ─── 프리셋 스킬 라우팅 ───────────────────────────────────────

  const activeSkills = PRESET_SKILLS[preset] || [];
  const inactiveSkills = ALL_PRESET_SKILLS.filter(s => !activeSkills.includes(s));
  const disabledSkills = config.disabledSkills || [];

  if (activeSkills.length > 0) {
    output.push('### Active Preset Skills');
    output.push('For framework-specific guidance, use these skills:');
    for (const skill of activeSkills) {
      if (!disabledSkills.includes(skill)) {
        output.push(`- \`/${skill}\``);
      }
    }
    output.push('');
  }

  if (inactiveSkills.length > 0) {
    output.push(
      `**Inactive preset skills** (different preset): ` +
      inactiveSkills.map(s => `\`${s}\``).join(', ') +
      ` \u2014 do NOT use these.`
    );
    output.push('');
  }

  if (disabledSkills.length > 0) {
    output.push(
      `**Disabled skills** (by config): ` +
      disabledSkills.map(s => `\`${s}\``).join(', ')
    );
    output.push('');
  }

  // ─── 도메인 경계 (Configurable Rule 대체) ─────────────────────

  const domains = config.domains || {};
  if (domains.sourceDir || domains.sharedPackage) {
    output.push('### Domain Boundaries');
    if (domains.sourceDir) {
      output.push(`- Source dir: \`${domains.sourceDir}/\``);
    }
    if (domains.sharedPackage) {
      output.push(
        `- Shared package: \`${domains.sharedPackage}/\` (modification requires user approval)`
      );
    }
    if (domains.importAlias) {
      output.push(`- Import alias: \`${domains.importAlias}\``);
    }
    output.push('');
  }

  // ─── 보안 패턴 주입 ───────────────────────────────────────────

  const securityPatterns = config.security?.secretPatterns || [];
  if (securityPatterns.length > 0) {
    output.push('### Security Patterns');
    output.push('The following secret patterns are actively monitored by the security hook:');
    for (const sp of securityPatterns.slice(0, 5)) {
      const action = sp.action === 'block' ? 'BLOCK' : 'WARN';
      output.push(`- ${sp.name}: [${action}]`);
    }
    if (securityPatterns.length > 5) {
      output.push(`- ... and ${securityPatterns.length - 5} more`);
    }
    output.push('');
  }

  // ─── 빌드/테스트 명령 ─────────────────────────────────────────

  const commands = config.techStack?.commands || {};
  if (commands.build || commands.test || commands.lint) {
    output.push('### Build & Test Commands');
    if (commands.build) output.push(`- Build: \`${commands.build}\``);
    if (commands.test) output.push(`- Test: \`${commands.test}\``);
    if (commands.lint) output.push(`- Lint: \`${commands.lint}\``);
    output.push('');
  }

  // ─── 워크플로우 설정 ──────────────────────────────────────────

  const workflow = config.workflow || {};
  const workflowNotes = [];
  if (workflow.p0?.enabled === false) {
    workflowNotes.push('P0 (Ideation/Research) is disabled');
  }
  if (workflow.p6?.enabled === false) {
    workflowNotes.push('P6 (TDD/Gemini Loop) is disabled');
  }
  if (workflowNotes.length > 0) {
    output.push('### Workflow Configuration');
    for (const note of workflowNotes) {
      output.push(`- ${note}`);
    }
    output.push('');
  }

  // ─── 진행 중 작업 감지 ────────────────────────────────────────

  const devActive = resolve(projectRoot, 'dev', 'active');
  if (existsSync(devActive)) {
    try {
      const taskDirs = readdirSync(devActive, { withFileTypes: true })
        .filter(d => d.isDirectory())
        .map(d => d.name);

      if (taskDirs.length > 0) {
        output.push('### Active Work in Progress');
        for (const dir of taskDirs) {
          const tasksPath = resolve(devActive, dir, 'tasks.md');
          if (existsSync(tasksPath)) {
            try {
              const tasksContent = readFileSync(tasksPath, 'utf-8');
              const total = (tasksContent.match(/- \[.\]/g) || []).length;
              const completed = (tasksContent.match(/- \[x\]/g) || []).length;
              output.push(
                `- **${dir}**: ${completed}/${total} tasks completed \u2014 \`dev/active/${dir}/\``
              );
            } catch {
              output.push(`- **${dir}**: \`dev/active/${dir}/\``);
            }
          } else {
            output.push(`- **${dir}**: \`dev/active/${dir}/\``);
          }
        }
        output.push('');
      }
    } catch { /* ignore */ }
  }

  // ─── CLAUDE.md 존재 여부 ──────────────────────────────────────

  const claudeMdPath = resolve(projectRoot, 'CLAUDE.md');
  if (!existsSync(claudeMdPath)) {
    output.push('### Setup Notice');
    output.push('No `CLAUDE.md` found. Run `/epcc-init` to generate project-specific CLAUDE.md.');
    output.push('');
  }

  // ─── 커스텀 리소스 안내 ───────────────────────────────────────

  const customResources = config.customResources || {};
  const existingResources = [];
  for (const [key, path] of Object.entries(customResources)) {
    const absPath = resolve(projectRoot, path);
    if (existsSync(absPath)) {
      existingResources.push({ key, path });
    }
  }

  if (existingResources.length > 0) {
    output.push('### Custom Resources');
    output.push('Skills will reference these project-specific resources:');
    for (const { key, path } of existingResources) {
      output.push(`- ${key}: \`${path}/\``);
    }
    output.push('');
  }

  // ─── 출력 ─────────────────────────────────────────────────────

  if (output.length > 0) {
    process.stdout.write(output.join('\n'));
  }
}

try {
  main();
} catch {
  // SessionStart 실패는 치명적이지 않음 — 조용히 통과
  process.exit(0);
}
