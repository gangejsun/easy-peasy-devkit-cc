# Migration from Code Generator

If you previously used `npx epcc-devkit generate` (the code generator version), follow this guide to migrate to the runtime plugin.

## Why Migrate?

| Aspect | Generator | Runtime Plugin |
|--------|-----------|----------------|
| Installation | `npx epcc-devkit init` + `generate` | `claude plugin install epcc-devkit` |
| File ownership | Files copied to your project | Files stay in plugin cache |
| Updates | Manual `generate` re-run | `claude plugin update epcc-devkit` |
| Hook registration | Manual `.claude/settings.json` | Automatic via `hooks/hooks.json` |
| Skills sync | `.agent/skills/` copies needed | Automatic sharing |

## Quick Migration

1. Install the runtime plugin:
```bash
claude plugin install epcc-devkit
```

2. Run the migration skill:
```
/epcc-migrate
```

The migration skill will:
- Analyze your `.claude/` directory
- Identify Core files (replaceable by plugin)
- Identify project-specific files (to keep)
- Generate a migration report
- Execute changes after your approval

## What Gets Removed

**Core Rules** (5 files) — plugin provides these:
- `task-workflow.md`, `agent-governance.md`, `self-improvement.md`
- `execution-transparency.md`, `claude-md-authoring.md`

**Core + Configurable Skills** (16 directories) — plugin provides these:
- All 14 Core skills + `requesting-code-review` + `security-review`

**All Hooks** — plugin's `hooks/hooks.json` replaces them:
- `.claude/hooks/*.sh` and `.claude/hooks/*.mjs`

**`.agent/` directory** — plugin skills are automatically shared:
- `.agent/skills/` and `.agent/workflows/`

**Hook entries in `.claude/settings.json`** — plugin manages hooks:
- All EPCC-related hook entries

## What Gets Kept

- `.claude/rules/code-conventions.md` (project-specific)
- `.claude/rules/project-structure.md` (project-specific)
- `.claude/skills/frontend-dev-guidelines/` (becomes a project override)
- `.claude/skills/backend-dev-guidelines/` (becomes a project override)
- `.claude/skills/ui-ux-design/` (becomes a project override)
- `.claude/governance/dynamic-rules/` (project-specific)
- `dev/` directory (work documents preserved)
- `CLAUDE.md` (may need minor updates)
- `epcc.config.json` (created if missing)

## Manual Migration

If you prefer manual control:

1. Delete Core rules from `.claude/rules/`:
   ```bash
   rm .claude/rules/{task-workflow,agent-governance,self-improvement,execution-transparency,claude-md-authoring}.md
   ```

2. Delete Core/Configurable skills from `.claude/skills/`

3. Delete `.claude/hooks/` directory

4. Delete `.agent/` directory

5. Remove EPCC hook entries from `.claude/settings.json`

6. Ensure `epcc.config.json` exists at project root

7. Restart Claude Code
