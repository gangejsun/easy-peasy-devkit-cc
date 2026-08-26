# Getting Started

## Quick Start

### 1. Install the Plugin

```bash
claude plugin install epcc-devkit
```

> **Note — the published marketplace build is still v2.0.0.** The command above installs from
> `origin/main`, so the v3 harness is only available once a release tag has been pushed and merged
> (`claude plugin tag --push` → merge to main). Until then, install from this repository directly:
>
> ```bash
> claude plugin marketplace add <path to this repo>
> claude plugin install epcc-devkit@easy-peasy-devkit
> ```

### 2. Initialize Your Project

Start Claude Code in your project directory, then run:

```
/epcc-init
```

This will interactively:
- Ask you to choose a frontend preset (nextjs / react-vite / vue / vanilla / none) and a backend preset (supabase / firebase / aws-serverless / aws-container / gcp-serverless / fastapi / node-api / node-nest / none)
- Collect project information
- Generate `epcc.config.json` and `CLAUDE.md`
- Install rule cards into `.claude/rules/`
- Create the `dev/` directory structure

### 3. Start Working

```bash
claude
```

The plugin automatically:
- Loads your project context via SessionStart hook
- Blocks hardcoded secrets before they are written
- Blocks stopping when source changed but build/test never ran
- Routes work by reversibility class (Reversible / Costly / Irreversible)

## Zero-Config Mode

The plugin works without `epcc.config.json` — the five hooks and the reversibility-class workflow are always active. Adding a config enables:
- Project-specific secret patterns
- Build/test command awareness (`build-gate` names the exact command)

## Available Presets

Presets are chosen on two axes — pick one from each.

| Frontend | Stack |
|----------|-------|
| `nextjs` | Next.js 15 App Router + React 19 + Tailwind v4 + shadcn/ui + Zustand |
| `react-vite` | React + Vite SPA + Tailwind + React Router + TanStack Query + Zustand |
| `vue` | Vue 3 Composition API + Vite SPA + Tailwind + Vue Router + Pinia |
| `vanilla` | No framework — standard DOM + ES modules (Vite bundle) |
| `none` | API-only project |

| Backend | Stack |
|---------|-------|
| `supabase` | PostgreSQL + RLS + Auth + Storage + Realtime (BaaS) |
| `firebase` | Firestore + Auth + Storage + Cloud Functions (BaaS) |
| `aws-serverless` | Lambda + API Gateway + DynamoDB + Cognito |
| `aws-container` | ECS/Fargate + ALB + RDS PostgreSQL + Drizzle + Cognito (portable to on-prem) |
| `gcp-serverless` | Cloud Run/Functions + Firestore + Identity Platform |
| `fastapi` | FastAPI + SQLAlchemy 2.0 + Pydantic v2 + Alembic (self-hosted) |
| `node-api` | Express 5 + PostgreSQL + Prisma (self-hosted) |
| `node-nest` | NestJS 11 + PostgreSQL + TypeORM 1 + class-validator (self-hosted) |
| `none` | No backend / external REST API |

The **combination** decides the guides. Two combinations ship pre-built guides —
`nextjs` × `supabase` and `react-vite` × `aws-container` — and every other combination
generates project-owned guides. The system picks without asking. See `docs/presets.md`.

## Project Override

To customize any plugin skill, copy it to your project's `.claude/skills/`:

```bash
# Example: override brainstorming skill
mkdir -p .claude/skills/brainstorming
# Create your custom SKILL.md there
```

Project files always take priority over plugin files.

## Next Steps

- [Configuration Reference](configuration.md) — Full `epcc.config.json` options
- [Presets Guide](presets.md) — Detailed preset documentation
- Upgrading from v2? Run `/epcc-migrate`
