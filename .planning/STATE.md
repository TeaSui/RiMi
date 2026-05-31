# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-05-31)

**Core value:** RiMi lets Vietnamese food sellers run their entire business from one app — orders, inventory, finances, customers.
**Current focus:** Phase 2 — Offline Core

## Current Position

Phase: 2 of 8 (Offline Core — ready to plan)
Plan: 3/3 in Phase 1 completed
Status: Phase 1 DONE — ready to begin Phase 2 planning
Last activity: 2026-05-31 — Phase 1 implemented (server/, flutter auth gate, schema+RLS)

Progress: [█░░░░░░░░░] 13%

## Performance Metrics

**Velocity:**
- Total plans completed: 3 (Phase 1: 01-01, 01-02, 01-03)
- Average duration: —
- Total execution time: ~1 session

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| Phase 1 | 3/3 | 1 session | — |

**Recent Trend:** First phase complete

## Accumulated Context

### Decisions

See PROJECT.md Key Decisions table (updated 2026-05-31). Summary:

- **Backend = Go + Postgres (self-hosted).** Chosen over Supabase/NestJS/Spring Boot on pure engineering merit: per-request Postgres RLS via SET LOCAL is cleanest in Go+pgx; Go fits the webhook/offline-sync surface in later phases.
- **Tenancy = Postgres RLS + application-layer query scoping (defense-in-depth).** Two DB roles: `rimi_migrator` (owner, runs migrations) and `rimi_app` (NOSUPERUSER NOBYPASSRLS, non-owner, DML only). RLS gated by `current_setting('rimi.user_id', true)` GUC set via SET LOCAL at transaction start.
- **All-tables-upfront schema.** Full 8-phase table list created in Phase 1 migrations; later phases ADD COLUMN / add logic only.
- **Active workspace as signed JWT claim.** RS256 access token carries `workspace_id`; re-issued only at `/workspaces/{id}/switch`. Never a client header.
- **Client-generated UUIDs** on all entities (offline-first prerequisite).
- **Flutter: go_router top-level only + AppNav kept for in-shell tabs** via nested Navigator inside RootShell.
- **Email verify/reset: interim paste-the-code flow** (no deep links) in Phase 1. Revisit for Phase 4+ if UX feedback demands it.

### Phase 1 Artifacts (produced, readable)

- `server/` — Go backend (chi router, golang-migrate, pgx, testcontainers integration tests)
- `server/migrations/` — 000001_init_schema + 000002_rls_policies
- `flutter/lib/core/{auth,workspace,network,config,router}/` — auth state, token storage, dio+interceptor, router
- `flutter/lib/features/auth/` — 6 screens (Vietnamese copy)
- `flutter/lib/features/workspace/` — create + switcher
- `docs/security/phase-1-auth-workspace.md` — 67 security rules (Security subagent)
- `docs/contracts/auth-workspace.yaml` — OpenAPI 3.1 spec (TechLead)
- `docs/contracts/README.md` — data model, ADRs, error-code catalog

### Pending Todos

- Pick email-verify/password-reset deep-link strategy before Phase 4+ (currently interim "paste code").
- Decide webhook ingestion location (Go monolith vs. separate service) before Phase 4.

### Blockers/Concerns

None. Phase 1 blocker (stack decision) resolved: Go + Postgres confirmed 2026-05-31.

## Session Continuity

Last session: 2026-05-31
Stopped at: Phase 1 complete. All 3 plans done. Ready to begin Phase 2 (Offline Core: Drift schema + DAOs, SyncManager, RealtimeManager planning).
Resume file: None
