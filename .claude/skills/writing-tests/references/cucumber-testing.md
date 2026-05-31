# Cucumber Testing Reference (Compat & Rollback Focus)

Scope: **scenario design** for BDD tests that exercise backward compatibility and blue-green rollouts. Gherkin syntax, step-def scaffolding, hooks, and tag mechanics already live in the `bdd-cucumber` skill — invoke it for those. This reference covers what `bdd-cucumber` doesn't: how to **shape scenarios** so the suite catches compat breakage during a rolling deploy.

## Table of Contents

1. Why Cucumber for Compat Testing
2. The Version Matrix Scenario Pattern
3. Step Defs That Route to Multiple Versions (Java + Go)
4. Data Tables for Version Matrices
5. Hooks for Multi-Version Setup/Teardown
6. **Backward Compatibility** (load-bearing)
7. **Blue-Green Deploy** (load-bearing)
8. Rollback Drill Scenario
9. Sources

---

## 1. Why Cucumber for Compat Testing

Cucumber scenarios are the **readable contract** between Product, Ops, and Eng. During a blue-green release, rollback decisions are made under time pressure — a scenario titled `Client v1 creates user on server v2 during blue-green cutover` is something an on-call engineer can read in 30 seconds and decide whether to proceed with the switch.

Use Cucumber for compat when:

- The scenario expresses a **cross-version user-visible behavior** (e.g., "old mobile app continues to work after backend upgrade").
- You need a **living document** that Ops / QA can run as a release gate.
- The acceptance criterion is versioned (the business explicitly promised N-1 mobile builds keep working).

Don't use Cucumber for compat when:

- The check is a pure serialization round-trip → use property-based (see `references/unit-testing.md`).
- The check is a schema migration at the DB level → use a migration unit test.

---

## 2. The Version Matrix Scenario Pattern

The core pattern is a **Scenario Outline** whose `Examples:` table is a client × server version grid.

```gherkin
Feature: User creation remains compatible across deploy boundaries

  Scenario Outline: User creation during blue-green deploy
    Given a running server on version "<server_version>"
    And a client on version "<client_version>"
    When the client creates a user with payload <payload>
    Then the server responds with status <status>
    And the stored user's phone_number is "<stored_phone>"

    Examples:
      | client_version | server_version | payload                            | status | stored_phone |
      | v1             | v1             | {"name":"A"}                       | 201    | NULL         |
      | v1             | v2             | {"name":"A"}                       | 201    | NULL         |
      | v2             | v1             | {"name":"A","phone":"+6591234567"} | 201    | NULL         |
      | v2             | v2             | {"name":"A","phone":"+6591234567"} | 201    | +6591234567  |
```

Read the matrix carefully:

- Row 2 (v1→v2): new server **tolerates missing field** that will later become required. This row fails if v2 prematurely made `phone` non-null.
- Row 3 (v2→v1): old server **ignores unknown field**. This row fails if v1 was never built with tolerant-reader discipline — which means v2 cannot ship until v1 is patched or retired.

**The matrix is the contract.** Every payload-touching PR adds a row for the new format and keeps the existing rows green.

---

## 3. Step Defs That Route to Multiple Versions

The step def needs to resolve `"<server_version>"` to an actual running binary (or in-process handler). Two common approaches:

### Java — Cucumber-JVM

```java
// src/test/java/com/example/steps/VersionRoutingSteps.java
public class VersionRoutingSteps {
    private final VersionedFixtures fixtures;   // injected via PicoContainer
    private HttpClient client;
    private ServerHandle server;

    @Given("a running server on version {string}")
    public void a_running_server_on_version(String version) {
        server = fixtures.launchServer(version);   // spawns v1 or v2 binary / loads v1 or v2 handler
    }

    @Given("a client on version {string}")
    public void a_client_on_version(String version) {
        client = fixtures.client(version);          // client that serializes payloads in that version's shape
    }

    @When("the client creates a user with payload {string}")
    public void the_client_creates_a_user_with_payload(String payloadJson) {
        fixtures.lastResponse = client.post(server.url("/users"), payloadJson);
    }

    @Then("the server responds with status {int}")
    public void the_server_responds_with_status(int expected) {
        assertEquals(expected, fixtures.lastResponse.status());
    }
}
```

`VersionedFixtures.launchServer(version)` is the choke point — it knows where the v1 and v2 binaries/jars live. Keep them on a shared CI cache or pull them from the artifact registry.

### Go — godog

```go
// features/steps/version_routing_steps.go
type versionCtx struct {
    server  *serverHandle
    client  *httpClient
    lastRes *http.Response
}

func (c *versionCtx) aRunningServerOnVersion(version string) error {
    h, err := launchServer(version) // "v1" or "v2"
    if err != nil {
        return err
    }
    c.server = h
    return nil
}

func (c *versionCtx) aClientOnVersion(version string) error {
    c.client = clientForVersion(version)
    return nil
}

func (c *versionCtx) theClientCreatesAUserWithPayload(payload string) error {
    res, err := c.client.Post(c.server.URL("/users"), payload)
    if err != nil {
        return err
    }
    c.lastRes = res
    return nil
}

func InitializeScenario(ctx *godog.ScenarioContext) {
    c := &versionCtx{}
    ctx.Step(`^a running server on version "([^"]*)"$`, c.aRunningServerOnVersion)
    ctx.Step(`^a client on version "([^"]*)"$`, c.aClientOnVersion)
    ctx.Step(`^the client creates a user with payload (.+)$`, c.theClientCreatesAUserWithPayload)
}
```

---

## 4. Data Tables for Version Matrices

When the compat surface has multiple fields, promote the payload to a `DataTable` so the test reads like a spec:

```gherkin
Scenario: v1 client reads v2 response without breaking
  Given a server on version "v2"
  When a v1 client requests user 42
  Then the v1 client sees these fields:
    | name   | "Alice"       |
    | email  | "a@ex.com"    |
  And the v1 client ignores these future fields:
    | phone_number          |
    | referral_code         |
    | loyalty_tier          |
```

The "ignores" table asserts that new fields do not cause the v1 parser to throw — codifying the **tolerant reader** contract.

---

## 5. Hooks for Multi-Version Setup/Teardown

Blue-green fixtures are expensive (two binaries, shared DB). Use `@Before` / `@After` with **tags** to scope setup:

```gherkin
@blue-green
Scenario: ...
```

```java
@Before("@blue-green")
public void setUpBlueGreen() { fixtures.launchBothBinaries(); fixtures.seedSharedDb(); }

@After("@blue-green")
public void tearDownBlueGreen() { fixtures.stopBothBinaries(); /* keep DB for next scenario */ }
```

Don't reset the DB between scenarios in a blue-green suite — the *whole point* is to observe how binaries interact with each other's written state.

---

## 6. Backward Compatibility

### 6.1 N and N-1 Scenarios Co-Exist

Every payload/schema change adds **new rows** to the Examples table; it does NOT remove the old rows. Old rows are deleted only after the old binary is decommissioned (usually one release later than the deploy).

### 6.2 Feature Flags as Version Gates

```gherkin
Scenario Outline: Phone number enforcement respects rollout flag
  Given the feature flag "phone_number_required" is "<flag>"
  And a v2 server
  When a v2 client creates a user with payload {"name":"A"}
  Then the server responds with status <status>

  Examples:
    | flag | status |
    | off  | 201    |   # rollout phase — legacy behavior
    | on   | 400    |   # post-rollout — field required
```

A flag without both an `off` and `on` scenario is unexercised risk. Ship both states in the same suite.

### 6.3 Expand-Contract in Scenario Form

For a DB migration, the scenario pins the **migration phase**:

```gherkin
Scenario: Expand phase tolerates missing phone_number
  Given the schema is in phase "expand"    # new column nullable, no backfill yet
  When the v1 binary writes user "A"
  Then the row exists with phone_number = NULL
  And the v2 binary reads user "A" successfully
```

When `phase` becomes `contract` (old column dropped) in a later release, add a scenario asserting that v2 no longer needs the old column and fails gracefully if rolled back to a v1 that expected it. That's how you discover you skipped a release step.

---

## 7. Blue-Green Deploy

During a cutover, the LB routes some traffic to v1 and some to v2 **at the same time**. A single user's session may hit both. Scenarios must cover:

| Direction | Assertion |
|---|---|
| v1 client → v2 server | v2 tolerates missing fields, applies sensible defaults |
| v2 client → v1 server | v1 ignores unknown fields (tolerant reader) |
| v1 writes, v2 reads | v2 reads v1's on-disk/on-wire format |
| v2 writes, v1 reads | v1 reads v2's on-disk/on-wire format OR the feature is behind a flag that's off |

The **four-cell matrix** from §2 covers all four directions. If a cell is missing, the matrix is incomplete.

### 7.1 Canary Subset

Canary is blue-green with a weighted LB. Add a scenario that proves the canary cohort's writes are readable by the non-canary cohort:

```gherkin
Scenario: Canary cohort writes are readable by stable cohort
  Given 10% of traffic routes to the canary (v2) binary
  And 90% routes to the stable (v1) binary
  When a user on the canary creates a record
  Then a subsequent request routed to the stable binary can read the record
```

---

## 8. Rollback Drill Scenario

Every release's suite MUST contain this scenario (or equivalent). If it fails, the release is not deploy-safe.

```gherkin
@rollback-drill @blue-green
Scenario: Mid-traffic rollback preserves data consistency
  Given the schema is in phase "expand"
  And the v2 binary is live and serving traffic
  When a v2 client creates user "A" with phone "+6591234567"
  And the runtime is rolled back to v1
  Then a v1 client can read user "A"
  And the v1 client can create user "B" without phone
  When the runtime is rolled forward to v2
  Then a v2 client can read both user "A" and user "B"
  And user "B" has phone_number = NULL
```

Failure modes this scenario catches:

- v2 wrote data in a format v1 cannot parse (backward compat broken).
- The migration is in `contract` phase when it should be `expand` (dropped too early).
- v2's default handling of nullable fields diverged from v1's (silent data corruption after forward-roll).

Tag with `@rollback-drill` and run it as a required gate in CI **before** any blue-green deploy.

---

## 9. Sources

[1] North, *Introducing BDD* (2006) — https://dannorth.net/introducing-bdd/
[2] Cucumber Docs — Gherkin Reference — https://cucumber.io/docs/gherkin/reference/
[3] godog (Cucumber for Go) — https://github.com/cucumber/godog
[4] Fowler, *BlueGreenDeployment* — https://martinfowler.com/bliki/BlueGreenDeployment.html
[5] Robinson, *Tolerant Reader* — https://martinfowler.com/bliki/TolerantReader.html
[6] Ambler & Sadalage, *Refactoring Databases* — https://databaserefactoring.com/
[7] Existing skill: `bdd-cucumber` — Gherkin syntax and step-def scaffolding (invoke for mechanics, not duplicated here)
