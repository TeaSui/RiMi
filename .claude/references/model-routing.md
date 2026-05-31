# Per-Dispatch Model Routing

**On-demand reference.** Loaded only when an agent is about to dispatch a `Task` and is choosing whether to override the target subagent's default model. Not always-loaded — paying the system-prompt cost on every turn would not be worth the per-dispatch benefit.

**Cited from:** `rules/agents.md` (Agent Registry), `skills/dispatching-parallel-agents/SKILL.md` (decision section).

---

## Three-Tier Table

| Tier | Model | When to use |
|---|---|---|
| **Lookup** | `haiku` | Pure file/symbol location, mechanical pattern aggregation, "list package.json deps", trivial cross-file enumeration. Examples: `/map-codebase` `tech` focus (mostly enumerating config files); a one-shot file listing dispatched as a probe. |
| **Implement** | `sonnet` | TDD code, contract execution, leaf implementers, code review, QA, most everyday dispatches. The default for almost everything. |
| **Design** | `opus` | Architecture, threat modeling, contract design, multi-step plans, ambiguous requirements, orchestration, hairy SCD/CDC/migration design without precedent. Cross-stack reasoning where no contract exists. |

## Static defaults (per-agent frontmatter)

These are the defaults baked into `~/.claude/agents/*.md`. Override only when the specific dispatch warrants it.

- **Opus:** `agent-orchestrator`, `tech-lead-subagent`, `security-engineer-subagent`
- **Sonnet:** `ai-engineer-subagent`, `api-test-agent`, `aws-infrastructure-subagent`, `backend-engineer-subagent`, `business-analyst-subagent`, `code-reviewer`, `codebase-mapper`, `data-engineer-subagent`, `devops-engineer-subagent`, `frontend-engineer-subagent`, `mobile-engineer-subagent`, `qa-subagent`, `ui-ux-designer-subagent`
- **Haiku:** none statically; opt-in per dispatch

## Override discipline

**Dispatchers MAY override in either direction.** When overriding, place a one-line justification in the dispatch prompt's `<context>` block per `rules/dispatch-prompt-contract.md`. Default = the agent's frontmatter model.

**Override-down examples (use weaker model than default):**
```
Note: this dispatch is mechanical (list config files only); using model: "haiku" to reduce cost.
```
```
Note: codebase-mapper tech focus — enumeration-only, no synthesis required; using model: "haiku".
```

**Override-up examples (use stronger model than default):**
```
Note: greenfield migration design with no existing contract; using model: "opus" for stronger reasoning.
```
```
Note: complex SCD Type 2 + late-arriving dimensions across 4 source systems; using model: "opus".
```

**Anti-patterns (do NOT do this):**
- Overriding without a justification line. The justification is what makes the choice auditable.
- Overriding down on a `code-reviewer` dispatch (rubber-stamp risk).
- Overriding down on `codebase-mapper` for `arch`, `quality`, or `concerns` focuses (writes ground-truth `.planning/` docs that downstream planning consumes as authoritative).
- Overriding up to "be safe" without naming a concrete reasoning load. Sonnet handles the median dispatch fine.

## Out of scope

This routing rule applies **only** to subagents reachable via the `Agent` tool with the `model` parameter. The following are NOT reassignable:

- `Explore` built-in harness agent (read-only search)
- `Plan` built-in harness agent
- The main session itself (governed by `settings.json` top-level `model` and `ANTHROPIC_MODEL` env var, not per-dispatch)

## Telemetry note

In this Bedrock-routed setup:

- **Opus / Sonnet** route through Bedrock **inference profile ARNs** in `settings.json:modelOverrides` → per-profile cost/latency telemetry available.
- **Haiku** routes through a **direct global model ID** via `ANTHROPIC_DEFAULT_HAIKU_MODEL` (`settings.json:env`) → functional but **no per-profile telemetry**.

If Haiku cost or latency tracking becomes load-bearing (e.g., chargeback by team, SLO monitoring), request a Haiku Bedrock inference profile ARN from the proxy team and append it to `modelOverrides`. Until then, Haiku usage is observable only via aggregate Bedrock metrics, not per-application-profile.
