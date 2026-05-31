---
name: goal
description: >
  Autonomous end-to-end execution skill. Use this whenever the user sets a high-level goal and
  wants Codex to work independently until done — no hand-holding, no asking for clarification
  mid-task. Triggers on: /goal, "just build it", "do it autonomously", "work on this until done",
  "don't stop until finished", "handle it end-to-end", "ship it", or any request phrased as a
  complete outcome rather than a step-by-step. This skill locks in context + success criteria up
  front and then runs the PLAN → BUILD → TEST → DEBUG → DELIVER loop without interruption.
  Invoke this skill even if the user only gives a one-line description — you'll gather the rest.
---

# /goal — Autonomous Execution

Turn a one-line goal into a shipped result. Gather context once, plan, execute, and deliver
evidence — no mid-task check-ins unless truly blocked.

---

## Phase 1 — Intake (do this once, then stop asking)

If the user gave `/goal <description>`, you have the goal. Now gather the rest in **one message**
using the AskUserQuestion tool or inline questions — do not spread intake across multiple
back-and-forth rounds.

Collect:

| Field | Prompt if missing |
|-------|------------------|
| **Project** | What are you building / what's the repo? |
| **Stack** | Language, framework, key infrastructure |
| **Current state** | What already exists (greenfield, partial, running service)? |
| **Work directory** | Path or repo root |
| **Constraints** | Budget, deadline, files/areas forbidden to touch |
| **Target users** | Who is this product for? |

If the user's original message already answers a field, don't re-ask it.

After intake, **confirm the goal and success criteria** before starting work:

```
Goal: <one sentence>

Success criteria (all must pass):
1. <measurable outcome>
2. <measurable outcome>
3. <measurable outcome>
4. Deliverable runs without errors end-to-end
5. Evidence produced: screenshot / test output / URL
```

Ask the user to confirm or adjust criteria. Once confirmed, proceed immediately — do NOT ask
any more questions unless you hit a hard blocker.

---

## Phase 2 — Autonomous Execution

### The 10 Operating Rules

These are non-negotiable for the duration of the goal:

1. **Plan first.** Generate a concrete task list before writing any code. Use TodoWrite.
   Mark each task in-progress when you start it, completed when done.

2. **Auto-run.** If you're not blocked, don't ask — just proceed to the next task.

3. **Auto-test.** After every task, run the relevant tests or commands and read the output.
   Confirm it works before moving on.

4. **Auto-debug.** If something fails: diagnose → fix → re-test. Do not explain the error back
   to the user and wait. If two fix attempts fail on the same issue, log it as a blocker and
   continue with unblocked tasks.

5. **Use every tool.** Terminal, MCP, file reads, test runners, curl — whatever gets the job
   done. Don't simulate results by inspection alone.

6. **No placeholders.** No TODO, no stub, no "implement later". Every component is complete
   and in its final state before you move on.

7. **Log progress visibly.** After completing each task: one line — what was done, status
   (✅ done / ⚠️ concern / 🔴 blocked). This keeps the user informed without interrupting you.

8. **Stay focused on the goal.** If you discover out-of-scope improvements, log them as
   follow-ups and continue. Do not expand scope mid-execution.

9. **If blocked:** log the blocker clearly, then immediately continue with any tasks that
   can run in parallel. Surface blockers in the final deliverable.

10. **Check criteria before stopping.** Before declaring done, re-read every success criterion
    and confirm each one is met with evidence. Do not stop if any criterion is unmet unless
    all remaining work is blocked.

### Quality Bar

Every output should pass this bar without needing the user to ask:

- Clean code, typed, follows the project's existing conventions
- Reasoning is independent — don't wait to be told the obvious next step
- Output quality exceeds what a senior developer would accept in code review
- Every non-obvious decision, env var, or pattern is documented (one-line comment or README
  note — not an essay)

---

## Phase 3 — Final Deliverable

When all success criteria are met (or execution is fully blocked), produce this report:

```
## Goal Complete: <goal description>

### ✅ Success Criteria
- [criterion 1]: met — <evidence>
- [criterion 2]: met — <evidence>
- [criterion 3]: met — <evidence>
- Runs without errors: met — <command + output>
- Evidence: <screenshot path / test output path / URL>

### 📋 Files Changed
- Created: <path>
- Modified: <path>
- Deleted: <path>

### 🚀 How to Run / Test / Deploy
<exact commands>

### 📊 Evidence
<test output, screenshot, or URL>

### ⚠️ Limitations & Follow-ups
<anything deferred, known gaps, suggested next steps>

### 💡 Key Decisions
<non-obvious choices made and why>
```

If any criterion is not met due to a blocker, include:

```
### 🔴 Blockers
- <what failed, what was tried, what needs to change to unblock>
```

---

## What "Done" Means

Done means:
- Every success criterion is verified with evidence
- The deliverable runs without intervention on first try
- Someone else can pick it up from the deliverable section alone

"I think it works" is not done. "Tests pass and here's the output" is done.
