# Framework-Specific Guides

Quick reference for enhancing prompts in Next.js/React projects.

## Next.js

**Key context to gather:**
- App Router vs Pages Router
- TypeScript usage
- API route patterns
- Server/Client component split
- State management approach
- CSS solution (Tailwind, CSS Modules, styled-components)

**Enhancement focus:**
```
- Route structure: app/[route]/page.tsx or pages/[route].tsx
- Server components: Default in App Router
- Client components: 'use client' directive
- Data fetching: async components, fetch, SWR, React Query
- Metadata: generateMetadata for SEO
- API routes: app/api/[route]/route.ts or pages/api/[route].ts
```

## React (Create React App / Vite)

**Key context to gather:**
- State management (Context, Redux, Zustand)
- Routing library (React Router)
- Component patterns (functional vs class)
- Build tool (Webpack, Vite)
- CSS approach

**Enhancement focus:**
```
- Component location: src/components/
- Hooks usage: useState, useEffect, custom hooks
- Route definitions: React Router configuration
- State structure: Global vs local state
- Build configuration: vite.config.ts or webpack config
```

## Enhancement Strategies for Component-Based Frameworks

1. Check existing component structure
2. Identify state management pattern
3. Review prop/event patterns
4. Check testing approach (component tests)
5. Verify styling solution

## Quick Detection Commands

```bash
# Next.js
ls app/ pages/ next.config.js

# React
ls src/App.tsx package.json vite.config.ts
```

## Version Considerations

- **Next.js 13+**: App Router vs Pages Router
- **React 18+**: Concurrent features, automatic batching

When enhancing prompts, always note the framework version if it affects implementation patterns.
