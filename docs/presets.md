# Presets Guide

Presets provide framework-specific skills, security patterns, and default configurations.

## Available Presets

### nextjs-supabase

**Stack**: Next.js 15 (App Router) + TypeScript + Supabase + Tailwind CSS v4 + shadcn/ui

**Active Skills**:
- `/nextjs-frontend-guide` — Server/Client Components, App Router, Tailwind, Zustand
- `/nextjs-backend-guide` — Route Handlers, Server Actions, Supabase, Zod
- `/ui-ux-design` — UI/UX design intelligence with 67 styles, 96 palettes

**Default Security Patterns**:
- Supabase Service Role key — `sb_secret_*` and legacy JWT (block)
- AWS Access Key (block)
- GitHub PAT (block)
- Generic API Key (warn)

### react-vite

**Stack**: React + Vite + TypeScript + Tailwind CSS

**Active Skills**:
- 가이드 스킬은 `/epcc-init`(또는 `/stack-guide-generator`)가 선택한 백엔드·DB 조합에
  맞춰 프로젝트의 `.claude/skills/frontend-guide`·`backend-guide`로 **생성**됩니다

### python-fastapi

**Stack**: Python 3.11+ + FastAPI + SQLAlchemy 2.0 + Pydantic v2

**Active Skills**:
- 가이드 스킬은 선택한 DB·데이터 액세스 조합에 맞춰 프로젝트에 **생성**됩니다 (`/stack-guide-generator`)

**Note**: No frontend skills — this is a backend-only preset.

### blank

**Stack**: None (user defines everything)

**Active Skills**: None — only Core skills are available.

Use this preset when your stack doesn't match any existing preset, or when you want full control over configuration.

## Choosing a Preset

Run `/epcc-init` and select your preset interactively. The preset determines:
1. Which framework-specific skills are activated
2. Default `techStack` values in `epcc.config.json`
3. Default security patterns

## Custom Presets

Custom presets are not yet supported in the runtime plugin. If you need framework-specific guidance for a stack not covered by existing presets:

1. Choose `blank` preset
2. Create custom skills in your project's `.claude/skills/`
3. These will be available alongside the Core skills
