---
name: refactor-with-rollback
description: Use when refactoring across multiple files — creates a git branch, requires upfront list of all planned changes, validates with build/tests/app after implementing, and automatically rolls back with evidence after 3 failed validation attempts
---

# Refactor with Rollback

**Announce at start:** "Using refactor-with-rollback skill to execute this safely."

## Step 1: Create a git branch

```bash
git checkout -b refactor/<short-description>
```

If working tree is dirty: `git stash`, create branch, `git stash pop`.
Report branch name before proceeding.

## Step 2: List ALL planned changes (HARD GATE)

Present this table before touching any file:

| File | Change | Reason |
|------|--------|--------|
| src/... | what changes | why |

**Do not touch any file until this table is presented.**
If user says "just do it" / "no need to ask" — still output the table, then proceed.
If you discover an unlisted file needs changing mid-implementation, add it to the table and note the addition.

## Step 3: Implement changes

Follow the table. Do NOT add scope beyond what is listed.

## Step 4: Validate (track attempt number — start at 1)

State acceptance criteria upfront (before Step 3) based on what the refactor is trying to achieve.

Run in order:
1. **Build:** `npm run build` / `go build ./...` / `cargo build` / `python -m py_compile`
2. **Tests:** `npm test` / `go test ./...` / `pytest`
3. **App start + smoke** (if relevant): start, wait for readiness, hit smoke URL
4. **Acceptance criteria:** run the specific checks that prove the refactor goal (e.g., `grep -r "mock" src/auth/ | wc -l` → should be 0)

## Step 5: If validation passes

```
## Validation Passed (Attempt N)

Build: ✓  Tests: N passed  App: started on port N
Criteria: all met

Refactor complete on branch refactor/<name>.
```

Offer next step: merge, PR, or `finishing-a-development-branch` skill.

## Step 6: If validation fails (attempt < 3)

```
## Validation Failed (Attempt N of 3)

Failure: <exact error>
Root cause: <one sentence>
Fix: <one specific change>
```

Apply the fix. Increment attempt counter. Return to Step 4.

## Step 7: If validation fails on attempt 3 — ROLLBACK (hard stop)

```bash
git stash
```

```
## Rollback (3 failed attempts)

Attempt 1: <error summary>
Attempt 2: <error summary>
Attempt 3: <error summary>

Changes stashed to stash@{0}.
To inspect: git stash show -p
To discard: git stash drop
To retry:   git stash pop

Guidance needed: <specific question about what is blocking>
```

**Stop. Do not attempt a 4th fix. Wait for the user.**

## Red flags

- Never start editing before the table in Step 2 is output
- Never attempt a 4th fix — rollback at attempt 3, no exceptions
- Never claim "validation passed" without running each criterion explicitly
