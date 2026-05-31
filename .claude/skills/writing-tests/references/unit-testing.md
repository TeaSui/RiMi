# Unit Testing Reference

Scope: example-based unit tests, property-based testing, mutation testing, and how to make unit/integration tests survive blue-green deploys. Cycle discipline (RED-GREEN-REFACTOR) lives in `test-driven-development` — don't duplicate; follow it.

## Table of Contents

1. Structure: AAA and Given-When-Then
2. Test Doubles Taxonomy (Meszaros)
3. What Coverage Means (and Doesn't)
4. Property-Based Testing
5. Mutation Testing
6. **Backward Compatibility** (load-bearing)
7. **Blue-Green Deploy** (load-bearing)
8. Rollback Drill
9. Sources

---

## 1. Structure: AAA and Given-When-Then

**Arrange-Act-Assert** (AAA) — three visual blocks in every test. Popularized by Bill Wake, 2001 [1].

```python
def test_transfer_decrements_source_balance():
    # Arrange
    src = Account(balance=Money(100, "SGD"))
    dst = Account(balance=Money(0, "SGD"))

    # Act
    src.transfer_to(dst, Money(30, "SGD"))

    # Assert
    assert src.balance == Money(70, "SGD")
```

**Given-When-Then** (GWT) is the same shape, borrowed from BDD [2]. Use GWT when the behavior is user-visible; AAA when it's implementation-internal. Don't mix both styles in one file.

**One logical assertion per test.** Multiple `assert` lines are fine if they verify one concept; if you're asserting three unrelated things, split the test — otherwise one failure masks two others.

---

## 2. Test Doubles Taxonomy (Meszaros)

Gerard Meszaros, *xUnit Test Patterns* (2007) [3], with Fowler's summary [4]:

| Double | Purpose | When to use |
|---|---|---|
| **Dummy** | Filler for a required arg, never used | Satisfying signatures |
| **Stub** | Returns canned answers | Controlling indirect inputs |
| **Fake** | Working implementation, unsuitable for prod (in-mem DB) | Fast integration of multi-step logic |
| **Spy** | Stub + records calls | Asserting interactions after the fact |
| **Mock** | Pre-programmed with expectations, fails if called wrong | Verifying interactions with collaborators |

**Rule of thumb:** Prefer fakes over mocks for anything with non-trivial state. Mocks test implementation; fakes test behavior. See Fowler, *Mocks Aren't Stubs* [4].

---

## 3. What Coverage Means (and Doesn't)

Line/branch coverage measures **which code was executed**, not **which behavior was verified**. A test that calls `f()` and asserts nothing still covers every line of `f`. Treat coverage as a **floor, not a ceiling**:

- <60%: suspicious — likely large untested areas
- 60–85%: normal range for most projects
- >95%: diminishing returns; the last 5% is often error paths that are genuinely hard to hit — don't chase it

To measure whether tests actually test, use **mutation testing** (§5).

---

## 4. Property-Based Testing

Invented by Claessen & Hughes, QuickCheck (2000) [5]. Modern ports: **Hypothesis** (Python) [6], **jqwik** (Java) [7], **gopter** (Go).

**Idea:** instead of hand-picking inputs, describe the property that holds for all inputs in a class; the framework generates hundreds and shrinks failures to the minimal counterexample.

```python
# Python, Hypothesis
from hypothesis import given, strategies as st

@given(st.lists(st.integers()))
def test_reverse_twice_is_identity(xs):
    assert list(reversed(list(reversed(xs)))) == xs
```

**Where it pays off:**
- Parsers, serializers, codecs (round-trip: `decode(encode(x)) == x`)
- Money / time / unit math (associativity, commutativity, identity)
- Schema translators and version converters (see §6 — ideal for compat)
- Idempotent operations (`f(f(x)) == f(x)`)

**Where it doesn't:** UI flows, single-example business rules, anything with hard-to-generate inputs (images, auth tokens). Use example-based tests there.

---

## 5. Mutation Testing

**PIT** for Java [8], **mutmut** / **Cosmic Ray** for Python [9], **go-mutesting** for Go. The tool mutates your source (`+` → `-`, `<` → `<=`, `return x` → `return null`) and re-runs the tests. Surviving mutants = tests don't detect the change = test weakness.

Use sparingly: mutation runs are slow (N × test-suite time). Target it at the modules you care most about — pricing, auth, migrations.

---

## 6. Backward Compatibility

During any rolling deploy, at least two code versions see the same data. Tests that only exercise the "current" version ship bugs into the compat window.

### 6.1 Expand-Contract Schema Migration

From Pramod Sadalage & Scott Ambler, *Refactoring Databases* (2006) [10]. Canonical pattern, four releases:

1. **Expand** — add the new column *nullable* with a default. Old code ignores it; new code may read/write it.
2. **Migrate writes** — new code writes both old and new columns.
3. **Backfill** — batch-populate new column for existing rows.
4. **Contract** — once all readers use the new column and a full rollback window has passed, drop the old column.

**Test rule:** every migration PR MUST have a test that runs the *previous* binary against the *new* schema and passes.

```python
# Python, pytest — integration test against a real Postgres
def test_previous_binary_writes_succeed_with_new_schema(pg_with_new_schema):
    # Arrange: schema has new nullable column 'phone_number'; old binary doesn't know about it
    old_binary = spawn_binary(VERSION_N_MINUS_1)

    # Act
    resp = old_binary.post("/users", {"name": "A"})

    # Assert
    assert resp.status == 201
    row = pg_with_new_schema.query_one("select phone_number from users where id = %s", resp.json["id"])
    assert row["phone_number"] is None   # nullable tolerates the absence
```

### 6.2 Tolerant Reader

Robinson, *Tolerant Reader* (2008) [11]: consumers MUST ignore unknown fields and MUST NOT fail on missing optional fields.

```python
def test_consumer_ignores_unknown_future_fields():
    payload = {"id": 1, "name": "A", "phone_number": "+6591", "new_field_from_future": "xyz"}
    user = User.from_dict(payload)
    assert user.id == 1
    # no KeyError, no failure on unknown field
```

### 6.3 Contract Tests Pinned to N and N-1

Every producer/consumer pair maintains contract tests for the **current** and **previous** minor versions. See `api-contract-testing` skill for Pact mechanics. The rule this reference adds: **do not delete a contract test in the same PR that changes the contract**. Delete it one release later, after the N-1 binary is decommissioned.

### 6.4 Dual-Version Table-Driven Test

Single test drives the compat matrix:

```go
// Go, table-driven
func TestUserPayloadAcrossVersions(t *testing.T) {
    cases := []struct{
        name           string
        writerVersion  string
        readerVersion  string
        payload        map[string]any
        wantStoredPhone string
    }{
        {"v1-writes-v1-reads", "v1", "v1", map[string]any{"name": "A"}, ""},
        {"v1-writes-v2-reads", "v1", "v2", map[string]any{"name": "A"}, ""},                      // v2 tolerates missing
        {"v2-writes-v1-reads", "v2", "v1", map[string]any{"name": "A", "phone": "+6591"}, ""},    // v1 ignores unknown
        {"v2-writes-v2-reads", "v2", "v2", map[string]any{"name": "A", "phone": "+6591"}, "+6591"},
    }
    for _, tc := range cases {
        t.Run(tc.name, func(t *testing.T) {
            stored := writeThenRead(tc.writerVersion, tc.readerVersion, tc.payload)
            if stored.Phone != tc.wantStoredPhone {
                t.Fatalf("phone = %q, want %q", stored.Phone, tc.wantStoredPhone)
            }
        })
    }
}
```

---

## 7. Blue-Green Deploy

Fowler, *BlueGreenDeployment* (2010) [12]: run two identical environments, switch traffic at the LB. During the switch, **both serve live traffic**. If the new one misbehaves, switch back instantly.

**What tests must cover:**

1. **Dual-read** — new code reads rows/messages written by BOTH old and new binaries.
2. **Dual-write** — when a migration is in flight, new code writes in *both* formats until cutover.
3. **Unknown-field tolerance** — old code reads new payloads without crashing.
4. **Idempotency** — retries during the switch cannot double-charge, double-credit, or double-send.

### 7.1 Feature Flags as Version Gates

Wrap the new behavior behind a flag. Test **both** states in the same suite:

```python
@pytest.mark.parametrize("flag_on", [True, False])
def test_user_creation(flag_on, feature_flags):
    feature_flags.set("phone_number_required", flag_on)
    resp = client.post("/users", {"name": "A"})
    if flag_on:
        assert resp.status == 400   # phone missing → rejected
    else:
        assert resp.status == 201   # legacy path → accepted
```

A flag without off-path tests is not a safety net — it's an unexercised branch.

### 7.2 Dual-Read Verification

```python
def test_new_binary_reads_legacy_row_format():
    # Arrange: insert row written by the v1 binary's serializer
    legacy_row = serialize_as_v1({"name": "A"})
    db.insert_raw("users", legacy_row)

    # Act: new binary reads it
    user = v2_repo.get_by_name("A")

    # Assert: no error, sensible defaults
    assert user.name == "A"
    assert user.phone_number is None
```

---

## 8. Rollback Drill

**Every** blue-green or canary release MUST include a test that proves rollback is safe:

1. Deploy v2 binary against v2 schema.
2. v2 writes data (with the new field set).
3. Revert runtime to v1 *without* reverting schema (or with the schema in the expand phase).
4. v1 reads the rows v2 wrote → must succeed.
5. v1 writes new rows → must succeed.
6. Re-deploy v2 → must read rows v1 wrote during the revert window.

If any step fails, the release is not deploy-safe. Ship the expand-only part first; ship behavior changes in a later release after the rollback window closes.

```python
def test_rollback_preserves_data_consistency(binary_launcher, db):
    # Arrange: schema in expand phase (new nullable column present)
    v2 = binary_launcher.spawn("v2")
    v2.post("/users", {"name": "A", "phone": "+6591"})   # v2 row with new field
    v2.kill()

    # Act: roll back to v1 mid-traffic
    v1 = binary_launcher.spawn("v1")
    got = v1.get("/users?name=A").json
    v1.post("/users", {"name": "B"})   # v1 writes a row without phone

    # Assert
    assert got["name"] == "A"          # v1 reads v2's row without crashing
    v2 = binary_launcher.spawn("v2")   # now redeploy v2
    assert v2.get("/users?name=B").json["name"] == "B"   # v2 reads v1's row
```

---

## 9. Sources

[1] Wake, *Arrange-Act-Assert* — https://xp123.com/articles/3a-arrange-act-assert/
[2] North, *Introducing BDD* (2006) — https://dannorth.net/introducing-bdd/
[3] Meszaros, *xUnit Test Patterns*, Addison-Wesley, 2007 — http://xunitpatterns.com/
[4] Fowler, *Mocks Aren't Stubs* — https://martinfowler.com/articles/mocksArentStubs.html
[5] Claessen & Hughes, *QuickCheck* (ICFP 2000) — https://www.cs.tufts.edu/~nr/cs257/archive/john-hughes/quick.pdf
[6] Hypothesis — https://hypothesis.readthedocs.io/
[7] jqwik — https://jqwik.net/
[8] PIT Mutation Testing — https://pitest.org/
[9] mutmut — https://mutmut.readthedocs.io/ (source unverified this session)
[10] Ambler & Sadalage, *Refactoring Databases*, Addison-Wesley, 2006 — https://databaserefactoring.com/
[11] Robinson, *Tolerant Reader* — https://martinfowler.com/bliki/TolerantReader.html
[12] Fowler, *BlueGreenDeployment* — https://martinfowler.com/bliki/BlueGreenDeployment.html
