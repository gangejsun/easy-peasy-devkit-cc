---
name: test-driven-development
description: Use when implementing any feature or bugfix, before writing implementation code
---

# Test-Driven Development (TDD)

## Overview

Write the test first. Watch it fail. Write minimal code to pass.

**Core principle:** If you didn't watch the test fail, you don't know if it tests the right thing.

**Violating the letter of the rules is violating the spirit of the rules.**

## When to Use

**Always:** New features, Bug fixes, Refactoring, Behavior changes

**Exceptions (ask your human partner):** Throwaway prototypes, Generated code, Configuration files

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Write code before the test? Delete it. Start over. No exceptions.

## Red-Green-Refactor

### RED - Write Failing Test

Write one minimal test showing what should happen. One behavior, clear name, real code (no mocks unless unavoidable).

### Verify RED - Watch It Fail

**MANDATORY. Never skip.** Confirm test fails because feature missing.

### GREEN - Minimal Code

Write simplest code to pass the test. Don't add features, refactor other code, or "improve" beyond the test.

### Verify GREEN - Watch It Pass

**MANDATORY.** Confirm test passes and other tests still pass.

### REFACTOR - Clean Up

After green only: Remove duplication, improve names, extract helpers. Keep tests green. Don't add behavior.

## Common Rationalizations

| Excuse | Reality |
| ------ | ------- |
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc is not systematic. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. |
| "TDD will slow me down" | TDD faster than debugging. |

## Project Test Strategy

### 테스트 인프라

- **프레임워크**: Vitest (`pnpm test`)
- **커버리지**: v8 provider, 임계값 30%
- **CI**: GitHub Actions — type-check → lint → build → test
- **Git 훅**: Husky pre-commit(lint-staged) + commit-msg(commitlint)
- **Claude Code 훅**: stop-guard.sh — 소스 코드 변경 시 build/test 미실행 차단

### 테스트 우선순위 (확충 시)

| 순위 | 대상               | 위치                         |
| ---- | ------------------ | ---------------------------- |
| 1    | Server Actions     | `src/lib/actions/**`         |
| 2    | 공유 유틸/훅       | `packages/shared/src/`       |
| 3    | API Route Handlers | `src/app/api/**`             |
| 4    | 타입 가드/변환     | `packages/shared/src/types/` |

### 테스트 명령어

```bash
pnpm test                    # 전체 테스트 실행
pnpm test:watch              # 변경 감지 모드
pnpm test:coverage           # 커버리지 보고서 생성
```

## Final Rule

```
Production code → test exists and failed first
Otherwise → not TDD
```

No exceptions without your human partner's permission.
