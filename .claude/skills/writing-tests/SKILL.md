---
name: writing-tests
description: Use when writing any new test, preparing a deployable change, or rolling out behind blue-green / canary — selects the right test type (unit, contract, BDD, property, mutation) and enforces backward-compatibility and rollback-safety discipline so tests pass against BOTH the old and new code versions during a deployment switch. Complements test-driven-development (cycle), bdd-cucumber (Gherkin), and api-contract-testing (Pact/OpenAPI).
---

# Writing Tests

## Core Principle

**A test that passes only against the new code is a deploy-time bug.** Blue-green and canary serve old and new binaries *simultaneously*. Tests that can't distinguish "broken for users" from "broken for one build" block safe rollback.

This skill is the **meta-layer**: pick the test type, then enforce compat + rollback on top. It does not replace:

- `test-driven-development` — the RED-GREEN-REFACTOR cycle
- `bdd-cucumber` — Gherkin syntax and step-def scaffolding
- `api-contract-testing` — Pact / OpenAPI specifics

Invoke those for mechanics. Invoke this one for **which test, at what layer, covering which compat axis**.

## When to Use

- Writing any new test
- Adding/changing a public API, DB column, message schema, or config key
- Shipping behind blue-green, canary, or a feature flag
- Reviewing a suite for rollback safety

## Test-Type Selection

| Goal | Test type | Reference |
|---|---|---|
| Pure function / class behavior | Unit (AAA/GWT) | `references/unit-testing.md` |
| Behavior across an input space | Property-based (Hypothesis, jqwik, gopter) | `references/unit-testing.md` |
| Test-suite defect sensitivity | Mutation (PIT, mutmut) | `references/unit-testing.md` |
| Business acceptance criteria | BDD / Cucumber | `references/cucumber-testing.md` + `bdd-cucumber` |
| Service-to-service API compat | Consumer-driven contract | `api-contract-testing` |
| Schema/field compat across versions | Contract + dual-version matrix | both references below |
| End-to-end user journey | E2E (sparingly — top of pyramid) | — |

## The Pyramid

Fowler's *Practical Test Pyramid* (2018) [1]: many fast unit tests, fewer integration, very few E2E. Variants (Honeycomb, Trophy) shift the middle — the principle holds: **push tests down to the fastest reliable layer that can catch the defect.**

## The Compat Axis (Load-Bearing)

Every test touching a public contract — HTTP, RPC, message schema, DB column, on-disk format — MUST answer:

1. **Forward compat** — does old code still work when new code writes?
2. **Backward compat** — does new code still work when old code writes?
3. **Rollback** — if we revert mid-traffic, does persisted state stay valid for the reverted binary?

"We don't test for it" = not deploy-safe. See each reference's **Backward Compatibility** and **Blue-Green Deploy** sections for concrete techniques (expand-contract migrations, tolerant reader, dual-version matrices, rollback drills).

## Red Flags

| Thought | Reality |
|---|---|
| "Old version will be gone in 10 minutes" | Blue-green serves both simultaneously; rollback brings it back for hours |
| "The migration just adds a column, it's safe" | `NOT NULL` without default breaks the old binary. Test it. |
| "Coverage is 95%" | Coverage measures executed lines, not assertions. Use mutation testing [2]. |
| "I mocked the DB, tests are fast" | Mocks drift. Keep one integration test per contract point. |
| "Gherkin step says 'user logs in' — details in step def" | Good. Now add an `Examples:` row for client v1 ↔ server v2. |
| "Rollback worked in dev" | Test it with live data shaped by the new version, read by the old binary. That's the real failure mode. |

## Rationalizations

- *"This field is internal"* — crosses a process boundary or is persisted = contract. Test it.
- *"Property-based is overkill"* — parsers, money math, timezone logic, schema translators hide edge cases. Cheap to try.
- *"Contract test next sprint"* — uncaught contracts become production incidents. Write the N↔N-1 test in the same PR.

## Workflow

1. **Classify**: pure logic / contract-touching / schema-touching / business-acceptance.
2. **Pick** the lowest layer that catches the defect.
3. **Write** the test TDD-style (`test-driven-development`).
4. If contract-touching → add a dual-version matrix case.
5. If schema-touching → add an expand-contract migration test.
6. If blue-green/canary → add a rollback-drill test.
7. **Verify** per `verification-before-completion` — run the suite, cite the log path.

## References

- `references/unit-testing.md` — AAA/GWT, test doubles (Meszaros), property-based, mutation, compat + blue-green for unit/integration tests.
- `references/cucumber-testing.md` — scenario design for compat/rollback (NOT Gherkin syntax — see `bdd-cucumber`).

## Sources

[1] Fowler, *The Practical Test Pyramid*, 2018 — https://martinfowler.com/articles/practical-test-pyramid.html
[2] PIT Mutation Testing — https://pitest.org/
