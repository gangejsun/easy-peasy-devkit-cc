# Getting Started

## Quick Start

### 1. Install the Plugin

```bash
claude plugin install epcc-devkit
```

### 2. Initialize Your Project

Start Claude Code in your project directory, then run:

```
/epcc-init
```

This will interactively:
- Ask you to choose a preset (nextjs-supabase, react-vite, python-fastapi, or blank)
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

| Preset | Stack | Active Skills |
|--------|-------|---------------|
| `nextjs-supabase` | Next.js 15 + Supabase + Tailwind + shadcn/ui | frontend, backend, ui-ux-design |
| `react-vite` | React + Vite + Tailwind | frontend, backend |
| `python-fastapi` | FastAPI + SQLAlchemy + Pydantic | backend |
| `blank` | Custom | None (Core only) |

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
