# Configuration Reference

## epcc.config.json

The configuration file lives at the project root. All fields are optional except `project.name` and `techStack.preset`.

### project

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `name` | string | (required) | Project name |
| `description` | string | | Project description |
| `language` | `"ko" \| "en" \| "ja" \| "zh"` | `"en"` | Claude response language |
| `experienceLevel` | `"senior" \| "mid" \| "junior"` | `"senior"` | Affects response detail level |

### techStack

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `preset` | string | (required) | Preset name: `nextjs-supabase`, `react-vite`, `python-fastapi`, `blank` |
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

### security

| Field | Type | Description |
|-------|------|-------------|
| `secretPatterns` | array | Secret detection patterns |
| `secretPatterns[].name` | string | Display name for the pattern |
| `secretPatterns[].pattern` | string | Regular expression |
| `secretPatterns[].action` | `"block" \| "warn"` | Block (exit 2) or warn (stderr) |

### workflow

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `p0.enabled` | boolean | `true` | Enable P0 (Ideation/Research) phase |
| `p6.enabled` | boolean | `true` | Enable P6 (TDD/Gemini Loop) phase |

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
    "preset": "nextjs-supabase",
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
  },
  "security": {
    "secretPatterns": [
      { "name": "Supabase Key", "pattern": "eyJhbGci...", "action": "block" }
    ]
  }
}
```
