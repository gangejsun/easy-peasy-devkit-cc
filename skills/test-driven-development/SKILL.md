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

Write one minimal test showing what should happen. One behavior, clear name, real code.
Mock only at **system boundaries** (see [Seams](#seams--where-tests-go)).

### Verify RED - Watch It Fail

**MANDATORY. Never skip.** Confirm test fails because feature missing.

### GREEN - Minimal Code

Write simplest code to pass the test. Don't add features, refactor other code, or "improve" beyond the test.

### Verify GREEN - Watch It Pass

**MANDATORY.** Confirm test passes and other tests still pass.

### REFACTOR - Clean Up

After green only: Remove duplication, improve names, extract helpers. Keep tests green. Don't add behavior.

## Seams — where tests go

A **seam** is the public boundary you observe behaviour at, without reaching inside.
Tests live at seams, never against internals.

**Agree the seams before writing the first test.** You cannot test everything; naming the
seams up front is how the effort lands on critical paths instead of every edge case.
State them, get confirmation, then start the loop. No test at an unconfirmed seam.

- **The interface is the test surface.** Callers and tests cross the same boundary.
  If you must test *past* the interface to see the behaviour, the module is the wrong shape.
- **Prefer an existing seam to a new one, and the highest one that still shows the bug.**
  Fewer seams is better; one is ideal.
- **Mock only at system boundaries** — third-party APIs, clocks, randomness, the network.
  Never mock your own modules or internal collaborators. If a mock is needed to reach
  the behaviour, the seam is in the wrong place.

## Test quality — three ways a passing test is worthless

A green suite proves nothing if the tests cannot disagree with the code.
Check each new test against all three before moving on.

| Anti-pattern | The tell | Fix |
| --- | --- | --- |
| **Implementation-coupled** | Test breaks on a refactor although behaviour did not change | Assert through the interface, not on internals, call counts, or the database |
| **Tautological** | The expected value is computed the way the code computes it, so it passes by construction | Expected values come from an independent source — a known literal, a worked example, the spec |
| **Horizontal slicing** | All tests written first, then all implementation | One test → one implementation → repeat. Each test is a tracer bullet that answers to what the last cycle taught you |

```typescript
// BAD — tautological: recomputes the implementation
const expected = items.reduce((sum, i) => sum + i.price, 0);
expect(calculateTotal(items)).toBe(expected);

// GOOD — independent literal
expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
```

Mock-specific failure modes (asserting on mock behaviour, test-only production methods,
incomplete mocks, over-complex mocks) are catalogued with gate functions in
[testing-anti-patterns.md](testing-anti-patterns.md). Read it when a test needs a mock.

## Common Rationalizations

| Excuse | Reality |
| ------ | ------- |
| "Too simple to test" | Simple code breaks. Test takes 30 seconds. |
| "I'll test after" | Tests passing immediately prove nothing. |
| "Already manually tested" | Ad-hoc is not systematic. |
| "Deleting X hours is wasteful" | Sunk cost fallacy. |
| "TDD will slow me down" | TDD faster than debugging. |

## Project Test Strategy

### 테스트 인프라 확인

프로젝트의 테스트 명령은 `epcc.config.json`의 `techStack.commands.test`에서 읽는다.
없으면 `package.json` scripts(JS/TS)나 `pyproject.toml`(Python)에서 확인하고,
그것도 없으면 **테스트 인프라 셋업을 먼저 제안한다** — 검증 경로 없는 TDD는 성립하지 않는다.

하네스 강제 장치: `build-gate` 훅(Stop)이 소스 변경 후 빌드/테스트 미실행을 차단한다.

### 테스트 우선순위 (확충 시)

| 순위 | 대상 | 이유 |
| ---- | ---- | ---- |
| 1 | 비즈니스 로직 (액션·서비스·도메인 함수) | 실패 비용이 가장 큼 |
| 2 | 공유 유틸/훅 | 사용처가 많아 회귀 파급이 큼 |
| 3 | API 핸들러/라우터 | 계약 위반 검출 |
| 4 | 타입 가드/변환 | 경계 데이터 안전성 |

구체적 경로는 프로젝트의 frontend/backend-guide 스킬(스택 맞춤 생성본)을 따른다.

## Final Rule

```
Production code → test exists and failed first
Otherwise → not TDD
```

No exceptions without your human partner's permission.
