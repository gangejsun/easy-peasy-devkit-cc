# Configuration Reference

## epcc.config.json

The configuration file lives at the project root. All fields are optional except `project.name` and `techStack.preset`.

### project

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | (required) | Project name |
| `description` | string | | Project description |
| `language` | BCP-47 tag | `"en"` | Response language. `/epcc-init` offers `ko` · `en` · `id` · `vi` plus free entry, so any tag is valid. Internal reasoning stays English; industry-standard technical terms (`Bottom Sheet`, `GNB`, `middleware`) stay English in every language |
| `languageLabel` | string | | Endonym shown in the T0 language directive (`한국어`, `Bahasa Indonesia`, `Tiếng Việt`). Falls back to `language` |
| `experienceLevel` | `"senior" \| "mid" \| "junior"` | `"senior"` | Affects response detail level |

### techStack

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `presets` | object | (required) | Two-axis selection: `{frontend, backend}`. See `docs/presets.md` |
| `preset` | string | | Legacy/compat notation `<frontend>+<backend>` |
| `frontend` | object | | Frontend axis: framework, language, packageManager, commands, sourceDir, additionalStack |
| `framework` | string | | Primary framework |
| `language` | string | | Primary language |
| `packageManager` | string | `"npm"` | Package manager: `npm`, `pnpm`, `yarn`, `bun`, `uv`, `pip` |
| `commands.build` | string | | Build command |
| `commands.test` | string | | Test command |
| `commands.lint` | string | | Lint command |
| `additionalStack` | string[] | `[]` | Additional technologies |

### domains

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `sourceDir` | string | `"src"` | Source code root directory |
| `sharedPackage` | string | | Shared package path (requires approval to modify) |
| `importAlias` | string | | Import alias (e.g., `@/`) |

### security — not configurable

Secret blocking is **built into the `security-check` hook**, not a config section. The hook
matches vendor-published key shapes (AWS `AKIA`, GitHub `ghp_`, Stripe, 토스페이먼츠,
카카오페이, OpenAI `sk-proj-`, Anthropic `sk-ant-`, Google `AIza`, Supabase, PEM private
keys, GCP service-account JSON) and blocks the write with exit 2.

Writing a secret into a `.env*` file that `git check-ignore` confirms is ignored is
**allowed** — that is where secrets belong. A `.env` file that is *not* ignored (e.g.
`.env.example`) is still blocked. See `docs/harness-anatomy.md` § `security-check`.

### workflow

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `p0.enabled` | boolean | `true` | Enable 기획 (Ideation/Research) phase |
| `p6.enabled` | boolean | `true` | Enable cross-check (TDD/Gemini Loop) phase |

### customResources

Key-value pairs mapping resource names to directory paths. Skills reference these paths to load project-specific resources.

```json
{
  "customResources": {
    "design-principles": ".claude/resources/design-principles",
    "coding-standards": ".claude/resources/coding-standards"
  }
}
```

### disabledSkills

Array of skill names to disable. Disabled skills are excluded from SessionStart routing.

```json
{
  "disabledSkills": ["gemini-claude-loop", "business-planner"]
}
```

## Example Configuration

```json
{
  "project": {
    "name": "My SaaS App",
    "language": "ko",
    "experienceLevel": "senior"
  },
  "techStack": {
    "presets": { "frontend": "nextjs", "backend": "supabase" },
    "preset": "nextjs+supabase",
    "framework": "Next.js 15 (App Router)",
    "language": "TypeScript (strict mode)",
    "packageManager": "pnpm",
    "commands": {
      "build": "pnpm build",
      "test": "pnpm test",
      "lint": "pnpm lint"
    },
    "additionalStack": ["Tailwind CSS v4", "shadcn/ui", "Zustand", "Supabase"]
  },
  "domains": {
    "sourceDir": "src",
    "sharedPackage": "packages/shared",
    "importAlias": "@/"
  }
}
```
