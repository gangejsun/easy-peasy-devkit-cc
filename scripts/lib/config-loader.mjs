/**
 * EPCC Devkit — 2-Tier Config 로더
 *
 * 런타임 플러그인용 config 로더.
 * Hook 스크립트에서 import하여 사용.
 *
 * 우선순위:
 * 1. $EPCC_CONFIG_PATH 환경변수
 * 2. process.cwd()/epcc.config.json (프로젝트 레벨)
 * 3. 하드코딩된 DEFAULT_CONFIG (최종 폴백)
 */

import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

// ─── Default Config ─────────────────────────────────────────────────

const DEFAULT_CONFIG = {
  project: { name: '', language: 'en', experienceLevel: 'senior' },
  techStack: {
    preset: 'blank',
    framework: '',
    language: '',
    packageManager: 'npm',
    commands: {},
    additionalStack: [],
  },
  domains: { sourceDir: 'src', sharedPackage: '', importAlias: '' },
  security: { secretPatterns: [] },
  workflow: { p0: { enabled: true }, p6: { enabled: true } },
  customResources: {},
  disabledSkills: [],
};

// ─── Path Helpers ───────────────────────────────────────────────────

export function getProjectRoot() {
  return process.cwd();
}

export function getPluginRoot() {
  return (
    process.env.CLAUDE_PLUGIN_ROOT ||
    resolve(new URL('.', import.meta.url).pathname, '..', '..')
  );
}

// ─── Config Loading ─────────────────────────────────────────────────

export function loadConfig() {
  const projectRoot = getProjectRoot();
  const configPath =
    process.env.EPCC_CONFIG_PATH ||
    resolve(projectRoot, 'epcc.config.json');

  if (existsSync(configPath)) {
    try {
      const userConfig = JSON.parse(readFileSync(configPath, 'utf-8'));
      return deepMerge(structuredClone(DEFAULT_CONFIG), userConfig);
    } catch {
      // 파싱 실패 시 기본값 반환
    }
  }
  return structuredClone(DEFAULT_CONFIG);
}

// ─── stdin 읽기 (Hook input) ────────────────────────────────────────

export function readStdin() {
  return new Promise((res) => {
    const chunks = [];
    let settled = false;
    const settle = (value) => { if (!settled) { settled = true; res(value); } };
    process.stdin.on('data', (chunk) => chunks.push(chunk));
    process.stdin.on('end', () => {
      try {
        settle(JSON.parse(Buffer.concat(chunks).toString()));
      } catch {
        settle({});
      }
    });
    // 타임아웃 (500ms)
    setTimeout(() => settle({}), 500);
  });
}

// ─── Deep Merge ─────────────────────────────────────────────────────

function deepMerge(target, source) {
  for (const key of Object.keys(source)) {
    if (
      source[key] &&
      typeof source[key] === 'object' &&
      !Array.isArray(source[key]) &&
      target[key] &&
      typeof target[key] === 'object' &&
      !Array.isArray(target[key])
    ) {
      deepMerge(target[key], source[key]);
    } else {
      target[key] = source[key];
    }
  }
  return target;
}
