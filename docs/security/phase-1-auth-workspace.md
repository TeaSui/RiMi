# Threat Model & Security Rules — RiMi Phase 1 (Auth + Workspace + Tenancy)

**Author:** security-engineer-subagent (Level 1, advisory)
**Status:** Authoritative — implementation agents (Go backend, Flutter) treat these rules as binding constraints.
**Phase:** 1 (Foundation). Covers AUTH-01..AUTH-07.
**Produced:** 2026-05-31 — BEFORE implementation.
**Consumes:** `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/research/PITFALLS.md`, plan `luminous-tinkering-robin.md`, `references/security-review/checklist.md`, `references/data-privacy-patterns.md`, skill `fintech-security`.

> Run-order note: this document is produced before any Phase-1 code. If an implementer finds it after starting, treat divergences as gap-analysis items and surface to the orchestrator.

---

## 1. Scope & locked decisions (do not relitigate)

- Backend = Go (chi/echo) + Postgres, self-hosted (NOT Supabase). DB access via `pgx`.
- Tenancy isolation = Postgres Row-Level Security (defense-in-depth) **PLUS** application-layer query scoping.
- RLS uses per-request session GUCs `rimi.user_id` / `rimi.workspace_id`, set with `SET LOCAL` at the start of each request transaction, derived from the validated JWT. Policies read `current_setting('rimi.workspace_id', true)`. `SECURITY DEFINER` function `app.is_workspace_member(wsid)` gates non-membership tables; `workspace_members` uses a non-recursive own-row policy.
- App connects as restricted role (`NOSUPERUSER NOBYPASSRLS`, non-owner); migrations run as a separate owner role.
- Auth = email/password (bcrypt or argon2) + RS256 JWT access (~15 min) + durable revocable refresh tokens with rotation + reuse-detection (revoke family). Email verification required before login; password reset via emailed single-use expiring token; active workspace carried as a signed JWT claim re-issued at `/workspaces/{id}/switch`.
- Money is OUT of scope for Phase 1.

---

## 2. Assets & data classification

Classification per `references/data-privacy-patterns.md`. **Jurisdiction is Vietnam** — the binding privacy regime is **Decree 13/2023/NĐ-CP (PDPD)**, not Singapore PDPA/MAS. The PII tiers below are reused as a sensitivity model; the *regulatory* obligations are PDPD.

| Asset | Classification | Notes |
|-------|---------------|-------|
| Password (plaintext, transient) | Level 1 (credential) | Never stored; only in-memory during hash/verify. |
| Password hash | Level 1 derivative | Stored in `profiles`/auth table. |
| Email address | Level 2 PII | Login identifier + verification/reset channel. |
| Phone number (profile) | Level 2 PII | Captured in `profiles`. |
| Display name | Level 2 PII | In `profiles`. |
| Access JWT | Level 1 (credential-equivalent) | Bearer — possession = identity. |
| Refresh token (raw) | Level 1 (credential) | Stored **hashed** at rest; raw only transits to client. |
| Email-verification token (raw) | Level 1 (credential) | Stored **hashed** at rest; raw only in the email. |
| Password-reset token (raw) | Level 1 (credential) | Stored **hashed** at rest; raw only in the email. |
| JWT RS256 private signing key | Level 1 (secret) | Env/secret store; never committed; never on device. |
| `workspace_id` / membership / role | Authorization data | Tenancy boundary; integrity-critical. |
| Cross-workspace business data | Confidential (tenant-isolated) | Phase-1 schema is created for all phases; RLS must protect rows from sibling tenants now. |

**Actors:** unauthenticated visitor; authenticated user (one or more workspace memberships, role owner/member); attacker (network MITM, stolen device, leaked token, malicious tenant attempting cross-tenant access, credential-stuffer, account-enumerator); the RiMi backend service identity (`rimi_app` DB role); the migrator identity (`rimi_migrator`); the email provider.

**Trust boundaries:**
1. Flutter client ↔ backend API (public internet, TLS). Everything from the client is untrusted.
2. Backend ↔ Postgres (the `rimi_app` role is the enforcement seam for RLS).
3. Backend ↔ email provider (SMTP/SES/Resend) — tokens leave the trust domain via email.
4. Device storage boundary — JWTs at rest on a potentially compromised device.
5. **Tenant ↔ tenant** — the most important Phase-1 boundary: workspace A must never see workspace B's rows.

---

## 3. STRIDE analysis

Each finding has an ID `F-NN`, the affected component/flow, the threat, and the rule(s) that mitigate it. OWASP 2021 mapping in brackets.

### 3.1 Spoofing (identity)

- **F-01 Forged / tampered JWT** — attacker mints or alters an access token to impersonate a user or claim a `workspace_id` they don't belong to. [A07] → AUTH-10, AUTH-11, AUTH-12, TENANCY-08.
- **F-02 Algorithm-confusion (`alg:none` / HS256-with-public-key)** — attacker submits a token signed with `none` or HS256 using the public key as the HMAC secret. [A02/A07] → AUTH-11.
- **F-03 Credential stuffing / brute force on `/auth/login`** — attacker tries leaked credential pairs. [A07] → AUTH-04, RATE-01, RATE-02.
- **F-04 Stolen refresh token replay** — attacker who exfiltrates a refresh token reuses it after the legitimate client rotated. [A07] → SESSION-03, SESSION-04, SESSION-05.
- **F-05 Login as unverified / non-existent account** — bypassing email verification. [A07] → AUTH-02, AUTH-03.
- **F-06 MITM on client↔API** — downgraded/plaintext transport lets an attacker capture credentials/tokens. [A02] → NET-01, PII-04.

### 3.2 Tampering (integrity)

- **F-07 SQL injection** via login/email/workspace-name inputs. [A03] → INPUT-02.
- **F-08 Client-supplied `workspace_id` used for scoping** — request body/path/header `workspace_id` is trusted for data scoping instead of the signed claim. [A01] → TENANCY-05, TENANCY-08.
- **F-09 Forged active-workspace via client header** — client sets an "active workspace" header the server trusts. [A01] → TENANCY-08, SESSION-08.
- **F-10 Mass assignment** — register/profile payload sets `role`, `email_verified`, `id` of someone else, or arbitrary columns. [A08/A01] → INPUT-04.
- **F-11 RLS bypass because the app connects as owner/superuser** — Postgres skips RLS for table owners and superusers; if `rimi_app` is the owner or has `BYPASSRLS`, every policy is silently inert. [A01] → TENANCY-02, TENANCY-03.
- **F-12 `rowsecurity=true` but no policy / permissive default** — enabling RLS without a restrictive policy, or a new later-phase table shipped without RLS. [A01] → TENANCY-01, TENANCY-04.

### 3.3 Repudiation

- **F-13 No audit trail for auth-security events** — account takeover, password reset, family-revocation can't be reconstructed. [A09] → LOG-01, LOG-02.
- **F-14 Logs are mutable / PII-laden so unusable as evidence** — see also Information Disclosure. [A09] → LOG-03, PII-01.

### 3.4 Information Disclosure

- **F-15 Account enumeration** via register, login, and password-reset responses/timing (distinct messages or timing for "email exists" vs not). [A07/A01] → AUTH-03, EMAIL-04, EMAIL-05.
- **F-16 PII / secrets in logs** — email, phone, password, tokens, full JWT logged. [A09/A02] → PII-01, PII-02, SECRETS-04.
- **F-17 Verbose errors leak internals** — stack traces, SQL fragments, table names in client responses. [A05] → INPUT-06, LOG-04.
- **F-18 Tokens at rest on device readable by other apps / backup** — JWTs in plaintext `SharedPreferences`/`UserDefaults` or app docs. [A02] → CLIENT-01, CLIENT-02.
- **F-19 Refresh/verification/reset tokens stored in plaintext in DB** — a DB read (backup leak, SQLi) yields usable credentials. [A02] → SESSION-02, EMAIL-01.
- **F-20 Reset/verify tokens leaked via URL/referrer/logs** — token in a GET query string ends up in access logs / Referer. [A05] → EMAIL-06.

### 3.5 Denial of Service

- **F-21 Unbounded request body / JSON** — large payload exhausts memory. [A05] → INPUT-05, NET-03.
- **F-22 No rate limiting on auth endpoints** — credential stuffing, reset/verify-email spam (also an email-cost / reputation DoS). [A04/A07] → RATE-01, RATE-02, RATE-03.
- **F-23 Password-hash CPU exhaustion** — attacker floods `/auth/register` or `/auth/login` to force expensive hashing. [A04] → RATE-01, AUTH-01 (params tuned, not unbounded).
- **F-24 Missing server timeouts / slowloris** — no Read/Write/Idle timeouts. [A04] → NET-02.

### 3.6 Elevation of Privilege

- **F-25 Cross-tenant access (the headline tenancy threat)** — a member of workspace A reads/writes workspace B rows. [A01] → TENANCY-01..TENANCY-08.
- **F-26 Fail-open when session GUC is unset** — a code path runs a query in a transaction where `SET LOCAL rimi.*` was not set (e.g., a background job, a missed middleware, a non-transactional query), and the policy treats "unset" as "allow all". [A01] → TENANCY-06, TENANCY-07.
- **F-27 `SET LOCAL` leaking across pooled connections** — using session-scoped `SET` (not `SET LOCAL`) or running queries outside the tx that set the GUC, so a pooled connection carries one user's `workspace_id` into another user's request. [A01] → TENANCY-05, TENANCY-06.
- **F-28 Recursive policy on `workspace_members`** — self-referential subquery causes recursion/timeout AND can mask a logic error that opens access. [A01] → TENANCY-09.
- **F-29 `SECURITY DEFINER` function with mutable `search_path`** — attacker shadows a referenced object; definer's elevated rights execute attacker code. [A01/A03] → TENANCY-10.
- **F-30 Privilege fields set at registration** — user self-assigns owner role on a workspace they shouldn't, or verifies their own email by setting a column. [A01] → INPUT-04, AUTH-13.
- **F-31 Reset does not invalidate existing sessions** — attacker who had a session keeps it after the victim resets the password. [A07] → AUTH-09, SESSION-06.

**OWASP 2021 coverage:** A01 Broken Access Control (TENANCY-*, F-08/09/11/12/25-31), A02 Crypto Failures (AUTH-01/10/11, SESSION-02, EMAIL-01, NET-01, CLIENT-*), A03 Injection (INPUT-02, F-07), A04 Insecure Design (RATE-*, NET-02/03 — design-level DoS/abuse controls), A05 Security Misconfiguration (INPUT-05/06, NET-*, LOG-04), A07 Identification & Auth Failures (AUTH-*, SESSION-*, EMAIL-04/05), A08 Software & Data Integrity (INPUT-04 mass-assignment, DEP-01 supply chain), A09 Logging & Monitoring Failures (LOG-*), A10 SSRF — **not applicable**: Phase 1 makes no server-side fetches of user-supplied URLs (email provider endpoint is config, not user input); revisit at webhook/integration phases. A06 Vulnerable Components → DEP-01/DEP-02.

---

## 4. Security Rules

All rules are testable. Each cites the STRIDE finding it mitigates and the AUTH requirement(s) it supports. **WHAT, not HOW** — implementers choose libraries/values within the stated bounds.

### AUTH — authentication & credentials

- **AUTH-01** (CRITICAL · backend · F-23) — Passwords MUST be hashed with a memory-hard or deliberately-slow algorithm (argon2id preferred, bcrypt acceptable) tuned so a single verification takes ≈250ms on target hardware; parameters MUST be config-driven, not hardcoded literals. *Test:* benchmark verify ≥150ms and ≤500ms; grep shows no plaintext password column. Supports AUTH-01.
- **AUTH-02** (CRITICAL · backend · F-05) — Login MUST reject any account whose email is not verified, with the same generic failure shape as a wrong password (no "please verify" leak that confirms the account exists). *Test:* register → login-before-verify returns the generic auth-failure envelope, not success and not an enumerating message. Supports AUTH-01, AUTH-02.
- **AUTH-03** (HIGH · backend · F-15) — Authentication responses MUST NOT reveal whether an email is registered. `/auth/register` with an existing email, `/auth/login` with wrong/absent account, and both reset endpoints MUST return responses indistinguishable to the caller (same status/body shape). *Test:* responses for known vs unknown email are byte-equivalent except for non-correlatable fields. Supports AUTH-01, AUTH-03.
- **AUTH-04** (HIGH · backend · F-03) — Failed-login lockout MUST be enforced per-account with progressive backoff (e.g., lock/slow after a small threshold of consecutive failures). Lockout state MUST NOT leak account existence (see AUTH-03). *Test:* N consecutive failures triggers backoff; behaviour identical for existent vs non-existent accounts. Supports AUTH-01.
- **AUTH-05** (MEDIUM · backend · F-03) — A minimum password policy MUST be enforced server-side at the boundary (length floor; reject trivially weak/breached-common values). Client-side checks are advisory only. *Test:* sub-minimum password rejected by the API regardless of client. Supports AUTH-01.
- **AUTH-09** (HIGH · backend · F-31) — A successful password reset MUST revoke all of the user's existing refresh-token families (force re-login everywhere). *Test:* hold a valid refresh token, complete reset, the held token is rejected on next `/auth/refresh`. Supports AUTH-03.
- **AUTH-10** (CRITICAL · backend · F-01) — Access tokens MUST be JWTs signed with **RS256 (asymmetric)**; the private key loads only from env/secret store and MUST NOT be committed or shipped to the client. *Test:* gitleaks finds no private key; only the public key is needed to verify. Supports AUTH-01, AUTH-04, AUTH-06.
- **AUTH-11** (CRITICAL · backend · F-01, F-02) — JWT verification MUST pin the accepted algorithm to RS256 and reject `none`/HS256 and any `alg` mismatch; it MUST validate signature, `exp`, `iss`, and `aud`. *Test:* tokens with `alg:none`, HS256-signed-with-public-key, expired, wrong-issuer, wrong-audience all return 401. Supports AUTH-01, AUTH-04, AUTH-06.
- **AUTH-12** (HIGH · backend · F-01) — Access-token lifetime MUST be short (~15 min); the access token alone MUST NOT be the only revocation surface (long-lived state lives in refresh tokens). *Test:* decode token, `exp - iat` ≈ 15 min. Supports AUTH-04.
- **AUTH-13** (HIGH · backend · F-30) — Registration MUST set server-controlled fields server-side: `email_verified=false`, no role, server-generated timestamps. The client MUST NOT be able to set verification state or role via the register payload. *Test:* register with `email_verified:true`/`role:owner` in the body → those values are ignored. Supports AUTH-01, AUTH-02.

### SESSION — refresh tokens & session lifecycle

- **SESSION-01** (HIGH · backend · F-04) — Refresh tokens MUST be durable and server-revocable (stored server-side), not stateless-only. *Test:* logout revokes; revoked token rejected. Supports AUTH-04.
- **SESSION-02** (CRITICAL · backend · F-19) — Refresh tokens MUST be stored **hashed** at rest (one-way; a DB/backup read yields no usable token). The raw token exists only in transit and on the client. *Test:* inspect the refresh-token table — column holds a hash, not a usable token. Supports AUTH-04.
- **SESSION-03** (CRITICAL · backend · F-04) — `/auth/refresh` MUST rotate: issue a new refresh token and invalidate the presented one atomically. *Test:* after refresh, the old refresh token is rejected. Supports AUTH-04.
- **SESSION-04** (CRITICAL · backend · F-04) — Refresh tokens MUST be tracked as a **family/chain**; presenting an already-rotated (revoked) token MUST be treated as reuse/theft and MUST revoke the entire family. *Test:* refresh once (rotates), then replay the original → entire family revoked, subsequent legitimate refresh also rejected. Supports AUTH-04.
- **SESSION-05** (HIGH · backend · F-04) — Refresh tokens MUST have an absolute expiry and be unguessable (≥128 bits CSPRNG entropy if opaque). *Test:* token entropy ≥128 bits; expired refresh rejected. Supports AUTH-04.
- **SESSION-06** (HIGH · backend · F-31) — Logout MUST revoke the presented refresh-token family server-side (not merely drop the client copy). *Test:* logout, then `/auth/refresh` with that family → rejected. Supports AUTH-04.
- **SESSION-08** (HIGH · backend · F-09) — The active workspace MUST be carried as a signed JWT claim re-issued at `/workspaces/{id}/switch`; the server MUST NEVER read active-workspace from a client-supplied header/body/query for authorization. *Test:* request with a forged `X-Workspace-Id` header but a token scoped to a different workspace → server uses the claim, ignores the header. Supports AUTH-06, AUTH-07.

### TENANCY / RLS — multi-tenant isolation

- **TENANCY-01** (CRITICAL · backend/data · F-12, F-25) — Every table holding workspace-scoped data MUST have `ENABLE ROW LEVEL SECURITY` **and** at least one restrictive policy, in the **same migration** that creates the table. RLS-enable without a policy is forbidden. *Test:* CI query `SELECT tablename FROM pg_tables WHERE schemaname='public' AND rowsecurity=false` returns empty; every public table has ≥1 row in `pg_policies`. Supports AUTH-07.
- **TENANCY-02** (CRITICAL · backend/devops · F-11) — The application MUST connect to Postgres as a role that is `NOSUPERUSER`, `NOBYPASSRLS`, and **not the owner** of the tables. Migrations run as a separate owner role. *Rationale (the `rowsecurity=true` gap):* Postgres **does not apply RLS to table owners or superusers, and skips it for `BYPASSRLS` roles** — so a table can show `rowsecurity=true` and still leak every row if the app connects as owner/superuser. The flag proves policies are *defined*, never that they are *enforced*; enforcement depends on the connecting role. *Test:* CI asserts the app role has `rolsuper=false`, `rolbypassrls=false`, and is not the table owner; an isolation IT runs as that exact role. Supports AUTH-07.
- **TENANCY-03** (CRITICAL · devops · F-11) — DB credentials for the app role and the migrator role MUST be distinct and both sourced from env/secret store (never committed). *Test:* gitleaks clean; compose/config shows two roles. Supports AUTH-07.
- **TENANCY-04** (HIGH · backend/data · F-12) — The CI `rowsecurity` gate is a release blocker and MUST also assert (a) ≥1 policy per public table and (b) the app-role privilege check from TENANCY-02. This gate MUST run on every future migration (later phases add tables via the same forcing function). *Test:* the gate fails a PR that adds a table without RLS+policy. Supports AUTH-07.
- **TENANCY-05** (CRITICAL · backend · F-08, F-27) — Application-layer scoping MUST filter by the `workspace_id` from the **validated JWT claim**, never from request body/path/query/header. This app guard is required *in addition to* RLS (defense in depth). *Test:* a repository query for workspace-scoped data includes the claim-derived `workspace_id`; a request supplying a different `workspace_id` in the body cannot widen scope. Supports AUTH-07.
- **TENANCY-06** (CRITICAL · backend · F-26, F-27) — Per-request tenancy GUCs MUST be set with **`SET LOCAL rimi.user_id` / `SET LOCAL rimi.workspace_id`** as the first statements inside the request transaction, and **all** queries for that request MUST run inside that same transaction. Session-scoped `SET` (without `LOCAL`) is forbidden. *Rationale (pooled-connection pitfall):* with a connection pool, a session-scoped `SET` persists on the physical connection and bleeds into the next request that reuses it — leaking one tenant's `workspace_id` into another's queries. `SET LOCAL` is transaction-scoped and auto-resets at commit/rollback, so it cannot leak across pooled requests. *Test:* an IT with a 1-connection pool runs request A (workspace W_A) then request B (workspace W_B) and asserts B never sees W_A's `current_setting`; grep shows no session-scoped `SET rimi.*`. Supports AUTH-06, AUTH-07.
- **TENANCY-07** (CRITICAL · backend/data · F-26) — Policies MUST **fail closed** when a GUC is unset: `current_setting('rimi.workspace_id', true)` returning NULL MUST result in zero rows (never all rows). The `app.is_workspace_member` function MUST return false/NULL when the GUC is absent. *Test:* run a workspace-scoped query in a transaction without setting the GUC → 0 rows returned (not an error that's caught-and-ignored, not all rows). Supports AUTH-07.
- **TENANCY-08** (CRITICAL · backend · F-08, F-09, F-25) — `/workspaces/{id}/switch` MUST be the **sole** membership gate: it verifies the caller is a member of `{id}` before re-issuing a token with that `workspace_id` claim. A token presented for a workspace the user is not a member of MUST yield empty/403 even if RLS were somehow bypassed. *Test:* forge/replay a token claiming a non-member `workspace_id` → switch is rejected; direct data calls with such a claim return empty/403 (the two-layer isolation IT). Supports AUTH-06, AUTH-07.
- **TENANCY-09** (HIGH · data · F-28) — The `workspace_members` policy MUST be **non-recursive**: it references only the GUC/`auth` identity directly (e.g., `user_id = current_setting('rimi.user_id', true)::uuid`) and MUST NOT subquery back into `workspace_members`. All *other* tables use the `SECURITY DEFINER` membership function. *Test:* a membership query completes in <100ms and Postgres logs show no recursion error; static review confirms no self-subquery. Supports AUTH-07.
- **TENANCY-10** (HIGH · data · F-29) — The `SECURITY DEFINER` function `app.is_workspace_member` MUST pin its `search_path` (e.g., `SET search_path = pg_catalog, public` or schema-qualify every object) so a caller cannot shadow referenced objects. *Test:* function definition includes a pinned/explicit `search_path`; a planted same-named object in a caller-controlled schema does not alter behaviour. Supports AUTH-07.
- **TENANCY-11** (MEDIUM · data · F-25 perf-adjacent) — Every workspace-scoped table MUST have an index on `workspace_id` (RLS predicates run per-row; an unindexed predicate degrades to scans and can become a DoS vector at scale). *Test:* `\d <table>` shows a `workspace_id` index. Supports AUTH-07.

### INPUT — validation & output hygiene

- **INPUT-02** (CRITICAL · backend · F-07) — All SQL MUST use parameterized queries / prepared statements (`pgx` placeholders); string concatenation of user input into SQL is forbidden. *Test:* grep shows no `fmt.Sprintf`/string-built SQL with user input; an injection probe on login/email/workspace-name fails. Supports AUTH-01, AUTH-05.
- **INPUT-03** (HIGH · backend · F-07/F-10) — All request DTOs MUST be validated at the handler boundary before reaching business logic: email format, length bounds on every string field, type/shape checks. *Test:* malformed email, over-length name, wrong types → 400 with the error envelope. Supports AUTH-01, AUTH-05.
- **INPUT-04** (HIGH · backend · F-10, F-30) — Request binding MUST be allow-listed (explicit DTO fields); the server MUST NOT bind client-supplied values to privileged/server-owned fields (`id` of others, `role`, `email_verified`, `workspace_id` for scoping, timestamps). *Test:* extra/privileged JSON fields are ignored or rejected, never persisted. Supports AUTH-02, AUTH-05.
- **INPUT-05** (HIGH · backend · F-21) — Request bodies MUST be size-limited (e.g., `http.MaxBytesReader`, ~1MB default for auth/workspace JSON) and JSON decoding MUST reject unknown fields where feasible. *Test:* an over-limit body → 413/400, not OOM. Supports AUTH-01.
- **INPUT-06** (HIGH · backend · F-17) — Error responses to clients MUST use the generic error envelope (`{ "error": {code,message,details} }`) with non-revealing messages; stack traces, SQL fragments, and table names MUST NOT appear in responses (debug detail goes to logs only). *Test:* induce a DB error → client gets a generic 500 envelope; the SQL/stack is only in server logs. Supports AUTH-01.

### EMAIL — verification & reset token handling

- **EMAIL-01** (CRITICAL · backend · F-19) — Email-verification and password-reset tokens MUST be stored **hashed** at rest; the raw token exists only in the email. *Test:* inspect `email_tokens` — values are hashes; a DB read does not yield a usable token. Supports AUTH-02, AUTH-03.
- **EMAIL-02** (CRITICAL · backend · F-15) — Verification and reset tokens MUST be **single-use**: consumed/invalidated atomically on first successful use. *Test:* reuse a just-used token → rejected. Supports AUTH-02, AUTH-03.
- **EMAIL-03** (HIGH · backend · F-15) — Tokens MUST expire (short window: verification hours, reset ~15–60 min) and be high-entropy (≥128-bit CSPRNG). *Test:* expired token rejected; token entropy ≥128 bits. Supports AUTH-02, AUTH-03.
- **EMAIL-04** (HIGH · backend · F-15) — `/auth/password-reset/request` MUST ALWAYS return the same success response (e.g., `sent:true`) regardless of whether the email exists. No enumeration via body or status. *Test:* known vs unknown email → identical response. Supports AUTH-03.
- **EMAIL-05** (MEDIUM · backend · F-15) — Enumeration-sensitive endpoints SHOULD normalize response timing (constant-time-ish work, e.g., do equivalent work for unknown accounts) so timing does not distinguish existence. *Test:* timing distribution for known vs unknown email overlaps. Supports AUTH-03.
- **EMAIL-06** (HIGH · backend/mobile · F-20) — Verification/reset tokens MUST NOT be transmitted or logged in URL query strings on the server side; the token MUST be consumed via a request body (POST) at the confirm endpoint. (Deep-link delivery to the app may carry the token, but the server endpoint that *consumes* it takes it in the body, and the token MUST NOT appear in server access logs.) *Test:* the confirm endpoint reads the token from the body; access logs contain no token. Supports AUTH-02, AUTH-03.

### PII — privacy & logging (Vietnam / PDPD context)

- **PII-01** (HIGH · backend · F-16, F-14) — Logs MUST NOT contain raw PII or credentials. Email/phone MUST be masked (`us***@***.com`, `+84****1234`); passwords, raw tokens, and full JWTs MUST NEVER be logged. *Test:* grep test fixtures/log output for an email/phone/token → only masked forms appear. Supports AUTH-01, AUTH-02, AUTH-03.
- **PII-02** (HIGH · backend · F-16) — PII MUST NOT appear in error messages returned to clients, nor in URLs/query params. *Test:* error envelopes carry no email/phone; no PII in any GET path. Supports AUTH-01.
- **PII-03** (MEDIUM · backend/data · PDPD) — The `profiles` PII (name/phone/email) SHOULD be modeled to support later data-subject rights (a tested `deleteUser`/erasure path) and minimization — collect only what AUTH-01/05 require in Phase 1. *Test:* schema review confirms no unnecessary PII columns; an erasure path is designable (full impl may be a later phase but the schema must not block it). Supports AUTH-01.
- **PII-04** (HIGH · backend · F-06) — PII and credentials MUST only transit over TLS (see NET-01); no auth/PII endpoint may be served over plaintext HTTP in any non-local environment. *Test:* prod/staging config rejects plaintext; HSTS or equivalent edge enforcement present. Supports AUTH-01.

### NET — transport & server hardening

- **NET-01** (CRITICAL · backend/devops · F-06) — All client↔API traffic MUST use TLS 1.2+ (1.3 preferred) in staging/prod; the API MUST NOT serve auth/PII over plaintext (TLS may terminate at an edge/proxy, in which case the proxy enforces it and the backend trusts only that network). *Test:* TLS scan shows MinVersion ≥1.2; plaintext request to a deployed env is refused/redirected. Supports AUTH-01, AUTH-04.
- **NET-02** (HIGH · backend · F-24) — The HTTP server MUST set explicit `ReadTimeout`, `WriteTimeout`, and `IdleTimeout` (no unbounded waits). *Test:* server config has all three set; a slowloris probe is cut off. Supports AUTH-01.
- **NET-03** (MEDIUM · backend · F-21) — Per NET/INPUT: request size caps (INPUT-05) plus connection limits SHOULD be in place at the edge. *Test:* oversized/many-connection probe is bounded. Supports AUTH-01.
- **NET-04** (LOW · backend · F-17) — CORS, if enabled, MUST use an explicit origin allow-list (never `*`) for credentialed requests. *Test:* config shows explicit origins; `*` with credentials is rejected. (Phase 1 is mobile-only; this is forward-looking for any future web surface.) Supports AUTH-01.

### SECRETS — secret management

- **SECRETS-01** (CRITICAL · backend/devops · F-16) — No secrets (JWT private key, DB passwords, SMTP/email-provider creds) in source, config files, or the repo. All MUST come from env/secret store. *Test:* `gitleaks detect` is clean and runs in CI as a blocker. Supports AUTH-01, AUTH-04.
- **SECRETS-02** (HIGH · backend · F-01) — The RS256 key pair MUST support rotation (key id/`kid` in the JWT header or a documented rotation procedure) so a leaked key can be retired without a full outage. *Test:* tokens carry a `kid`; verifier can hold ≥2 public keys during rotation. Supports AUTH-04.
- **SECRETS-03** (HIGH · devops · F-16) — The JWT **private** signing key MUST exist only on the backend, never in the Flutter bundle or any client artifact. *Test:* scan the built Flutter artifact for key material → none; only the API base URL (public) ships. Supports AUTH-04.
- **SECRETS-04** (HIGH · backend · F-16) — Secrets and tokens MUST NOT be logged even at debug level. *Test:* log review/grep finds no key/token material. Supports AUTH-01, AUTH-04.

### CLIENT — Flutter device-side handling

- **CLIENT-01** (CRITICAL · mobile · F-18) — Access tokens, refresh tokens, and the active-workspace id MUST be stored only in platform secure storage (`flutter_secure_storage` → Keychain / Keystore), never in `SharedPreferences`/`UserDefaults`/plaintext files/Drift. *Test:* grep client source — token persistence routes through secure storage only. Supports AUTH-04.
- **CLIENT-02** (HIGH · mobile · F-18) — On logout (and on refresh-failure-forced-logout), all tokens MUST be cleared from secure storage. *Test:* logout → secure-storage read returns nothing for token keys. Supports AUTH-04.
- **CLIENT-03** (HIGH · mobile · F-04) — The client MUST treat the access token as short-lived and use a single-flight refresh (queue concurrent 401s, refresh once, replay) so it never spams `/auth/refresh` or races rotation into a false reuse-detection. *Test:* fire N concurrent requests that 401 → exactly one refresh call; on refresh failure → forced logout. Supports AUTH-04.
- **CLIENT-04** (HIGH · mobile · F-08, F-09) — The client MUST NOT send `workspace_id` as an authorization signal; the server derives it from the token claim. Switching workspace goes through `/workspaces/{id}/switch` and the client stores the re-issued token. *Test:* no client code path sends a workspace header expecting the server to scope by it. Supports AUTH-06, AUTH-07.
- **CLIENT-05** (MEDIUM · mobile · F-16) — The client MUST NOT log tokens/PII; user-facing error copy (Vietnamese) MUST NOT echo server internals. *Test:* client log review finds no token/PII. Supports AUTH-01, AUTH-04.

### LOG — audit & monitoring

- **LOG-01** (HIGH · backend · F-13) — Security-relevant auth events MUST be logged with who/what/when/from-where/result (masked PII): login success/failure, lockout, email verification, password-reset request/confirm, refresh rotation, **refresh-reuse family revocation**, workspace switch. *Test:* each event produces a structured log line with those fields and masked PII. Supports AUTH-01..AUTH-07.
- **LOG-02** (MEDIUM · backend · F-13) — Refresh-token-reuse detection (SESSION-04) MUST emit a distinct high-severity event suitable for alerting (signals token theft). *Test:* triggering reuse emits a tagged security event. Supports AUTH-04.
- **LOG-03** (MEDIUM · devops · F-14) — Auth/security logs SHOULD be shipped to durable, append-oriented storage with a defined retention (align with PDPD; logs containing user identifiers ~1 year per the privacy reference). *Test:* retention configured; logs are not locally mutable-only. Supports AUTH-01.
- **LOG-04** (HIGH · backend · F-17) — Panics in HTTP handlers MUST be recovered, logged server-side, and returned to the client as a generic 500 envelope (never the panic message). *Test:* a forced panic → generic 500 to client, full detail in logs. Supports AUTH-01.

### DEP — supply chain

- **DEP-01** (HIGH · backend/devops · A06) — JWT and crypto/DB libraries MUST be currently-maintained (e.g., `golang-jwt/jwt/v5`, not abandoned forks); dependency vuln scanning (govulncheck / Trivy / Grype / Snyk) MUST run in CI. *Test:* CI dependency scan passes; no use of abandoned `dgrijalva/jwt-go`. Supports AUTH-01, AUTH-04.
- **DEP-02** (MEDIUM · mobile · A06) — Flutter dependencies (`flutter_secure_storage`, `dio`, etc.) MUST be version-pinned and scanned. *Test:* pinned versions in `pubspec.yaml`; advisory check passes. Supports AUTH-04.

---

## 5. Requirement → rule coverage matrix

| Req | Covered by (representative) |
|-----|-----------------------------|
| AUTH-01 signup | AUTH-01,02,03,05,13; INPUT-02,03,04,05; PII-01..04; NET-01,02 |
| AUTH-02 email verify | AUTH-02,13; EMAIL-01,02,03,06; AUTH-03 (anti-enum) |
| AUTH-03 password reset | AUTH-03,09; EMAIL-01..06; SESSION-06 |
| AUTH-04 session persists | SESSION-01..06; AUTH-10,11,12; CLIENT-01,02,03; SECRETS-01..04 |
| AUTH-05 create workspace | TENANCY-05,08; INPUT-03,04; AUTH-13 |
| AUTH-06 switch workspace | SESSION-08; TENANCY-06,08; CLIENT-04; AUTH-11 |
| AUTH-07 data isolation (RLS) | TENANCY-01..11; SESSION-08; CLIENT-04 |

Every AUTH-01..07 is referenced by ≥1 rule.

---

## 6. CI / tooling recommendations (advise DevOps)

- **Secret scanning (blocker):** gitleaks in CI + pre-commit; trufflehog for deep history. (SECRETS-01)
- **SAST:** Semgrep or CodeQL on the Go backend (SQL-build, alg-confusion, missing-recover rules).
- **Dependency/vuln:** govulncheck + Trivy/Grype on Go; advisory scan on Flutter deps. (DEP-01/02)
- **DAST (later, when a deployed env exists):** OWASP ZAP / Nuclei against auth endpoints (enumeration, missing rate limit).
- **Tenancy gates (custom, blockers):** the hardened `rowsecurity` + `pg_policies` + app-role-privilege SQL (TENANCY-01/02/04); the two-workspace isolation IT and the single-connection-pool GUC-leak IT run as `rimi_app` (TENANCY-06/07/08).

## 7. Compliance notes

- **PDPD (Decree 13/2023/NĐ-CP, Vietnam)** is the binding regime — not MAS/PDPA (those references are stack context, not jurisdiction). Phase-1 obligations: lawful processing of email/phone/name (Level 2 PII), data minimization (PII-03), security of processing (all CRYPTO/SESSION/EMAIL/TENANCY rules), and a designable erasure/data-subject-rights path (PII-03). Confirm Vietnamese localization obligations with legal before GA.
- **COMPLIANCE escalation:** if the orchestrator/stakeholder needs a definitive PDPD localization-and-consent posture (e.g., cross-border storage of Vietnamese PII), that is a legal scope decision and should be confirmed before GA — not blocking for Phase-1 implementation.

## 8. Quality-gate self-check

- All six STRIDE categories analyzed for every component/flow — done (§3).
- OWASP Top 10 mapped; A10 SSRF and A04 addressed (A10 N/A with reason) — done (§3 footer).
- Every rule traces to a STRIDE finding and is testable + domain-scoped + severity-marked — done (§4).
- Docs persisted to `docs/security/` — this file.
- No implementation code, no migrations, no OpenAPI written — confirmed (rules only).
- No secrets/keys/PII embedded in this model — confirmed.

---
*Last updated: 2026-05-31*
