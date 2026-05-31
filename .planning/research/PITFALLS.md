# Pitfalls Research

**Domain:** Flutter + Supabase offline-first multi-tenant F&B SaaS — Vietnamese market
**Researched:** 2026-05-31
**Confidence:** HIGH

## Critical Pitfalls

### Pitfall 1: RLS Policy Missing on New Tables

**What goes wrong:**
A new table is added (e.g., `invoice_items`) without enabling RLS or without a policy. Any authenticated user can read/write all rows across all workspaces.

**Why it happens:**
Developer creates the migration, tests it locally with a single workspace, and never tests cross-workspace isolation. Supabase doesn't enforce RLS unless explicitly enabled.

**How to avoid:**
- Always run `ALTER TABLE <name> ENABLE ROW LEVEL SECURITY;` in the same migration as `CREATE TABLE`.
- Create a CI test that lists all tables and asserts `rowsecurity = true` in `pg_tables`.
- Code review checklist: "Does every migration with CREATE TABLE also ENABLE ROW LEVEL SECURITY?"

**Warning signs:**
- Migration file has `CREATE TABLE` but no `ENABLE ROW LEVEL SECURITY` in the same file.
- Integration test with two workspace users shows cross-workspace data visible.

**Phase to address:** Phase 1 (Foundation) — establish the pattern from the very first table.

---

### Pitfall 2: Recursive RLS Policy Causing Query Timeouts

**What goes wrong:**
A policy on `workspace_members` checks membership via a subquery that also hits `workspace_members`, causing infinite recursion → query hangs or returns a Supabase "too many recursive calls" error.

**Why it happens:**
Developers write "self-referential" membership checks, e.g.: `USING (workspace_id IN (SELECT workspace_id FROM workspace_members WHERE user_id = auth.uid()))` directly on the `workspace_members` table.

**How to avoid:**
Use a `SECURITY DEFINER` function for membership lookup, or ensure the `workspace_members` policy only references `auth.uid()` directly (no subquery back to the same table).

```sql
-- Safe pattern for workspace_members itself:
CREATE POLICY "own_memberships" ON workspace_members
  USING (user_id = auth.uid());

-- Other tables use a helper function:
CREATE OR REPLACE FUNCTION is_workspace_member(wsid uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER AS $$
  SELECT EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = wsid AND user_id = auth.uid()
  );
$$;
```

**Warning signs:**
- Queries to workspace-scoped tables hang for > 5 seconds.
- Supabase logs show "too many recursive calls" or query plan shows nested loop explosion.

**Phase to address:** Phase 1 (Foundation schema).

---

### Pitfall 3: Offline Inventory Conflict (Two Devices Decrement Same Stock)

**What goes wrong:**
Device A (seller's phone, offline) creates an order deducting 2 units of "Bún bò". Device B (helper's tablet, also offline) independently creates another order deducting 2 units. Both sync when connectivity returns → stock goes to -4 when actual available was 3.

**Why it happens:**
Optimistic local writes don't know about concurrent mutations on other devices.

**How to avoid:**
- Inventory adjustments use a server-side atomic function (`rpc('adjust_inventory', { delta: -2 })`), not a direct `UPDATE`.
- The atomic function uses `FOR UPDATE` row lock + check available stock → returns error if insufficient.
- Flutter sync manager catches the conflict response and surfaces an alert to the user.
- Display "reserved stock" vs "confirmed stock" separately in UI.

**Warning signs:**
- Negative stock values appearing in inventory table.
- Users reporting "sold items that were out of stock."

**Phase to address:** Phase 3 (Inventory module) — build atomic stock functions from day one.

---

### Pitfall 4: Duplicate Orders from Platform Webhook Retries

**What goes wrong:**
ShopeeFood/GrabFood retry their webhooks if they don't receive a 200 in < 2 seconds (e.g., Edge Function cold start). The same order gets inserted twice, creating duplicate entries in the orders table.

**Why it happens:**
No idempotency key check. Edge Function inserts a new row on every call.

**How to avoid:**
- Store `platform_order_id` (the platform's native ID) as a `UNIQUE` constraint on the `orders` table.
- Use `upsert` with `onConflict: 'platform_order_id'` in the Edge Function.
- Return 200 immediately after validating the signature; process asynchronously if needed.

**Warning signs:**
- Seller reports seeing the same order twice.
- `platform_order_id` is not indexed or not unique in the schema.

**Phase to address:** Phase 4 (Platform integrations) — add unique constraint in the orders migration.

---

### Pitfall 5: Realtime Subscription Leaks

**What goes wrong:**
Flutter screens subscribe to Supabase Realtime channels but never unsubscribe. After navigating away and back 10 times, there are 10 duplicate subscriptions. App becomes slow; Supabase hits connection limit.

**Why it happens:**
`supabase.channel(...).subscribe()` called in widget `initState` or Riverpod `build`, but `channel.unsubscribe()` never called in `dispose`.

**How to avoid:**
- Use the central `RealtimeManager` pattern (see ARCHITECTURE.md) — ref-count subscriptions.
- Never subscribe directly inside a widget — always via a Riverpod provider with a `ref.onDispose` callback.
- Test: navigate to Orders screen 10× and back; assert only 1 active channel.

```dart
// In a Riverpod provider:
final ordersRealtimeProvider = Provider((ref) {
  final channel = realtimeManager.subscribeOrders(workspaceId);
  ref.onDispose(() => realtimeManager.unsubscribe('orders:$workspaceId'));
  return channel;
});
```

**Warning signs:**
- Supabase dashboard shows connection count growing over time.
- App memory usage grows with each screen navigation.

**Phase to address:** Phase 2 (Core infrastructure / Realtime setup).

---

### Pitfall 6: `service_role` Key Exposed in Flutter App

**What goes wrong:**
Developer hardcodes or accidentally includes the Supabase `service_role` key in the Flutter app (e.g., in a `.env` file bundled in the APK, or in `flutter_dotenv`). Anyone who decompiles the APK gets full database access, bypassing all RLS.

**Why it happens:**
Developers use service role locally "to skip RLS during dev" and forget to swap it out before production.

**How to avoid:**
- `service_role` key ONLY in Supabase Edge Functions via `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')`.
- Flutter app uses ONLY the `anon` (public) key.
- Add a pre-commit hook or CI step that scans for `service_role` strings in Flutter source files.

**Warning signs:**
- Any `.env` or `config.dart` file in the Flutter project contains `service_role`.
- Supabase dashboard shows API calls from Flutter clients bypassing RLS.

**Phase to address:** Phase 1 (Foundation) — enforce in code review checklist.

---

### Pitfall 7: Payment Webhook Signature Not Verified

**What goes wrong:**
MoMo/ZaloPay/VNPAY webhooks are processed without verifying the HMAC signature. An attacker crafts a fake "payment confirmed" webhook → order marked as paid without real payment.

**Why it happens:**
Developers focus on happy-path integration and skip or defer signature verification.

**How to avoid:**
- Signature verification is the FIRST thing in every payment Edge Function — reject before any DB writes.
- Each provider has different signature schemes; implement per-provider (see STACK.md).
- Write integration tests that send tampered payloads and assert 401 response.

**Warning signs:**
- Payment Edge Function processes request body before checking any headers.
- No `HMAC_SECRET` environment variable configured for the function.

**Phase to address:** Phase 5 (Payment integrations) — non-negotiable.

---

### Pitfall 8: AI Agent Token Blowup / Cost Explosion

**What goes wrong:**
The Finance Agent is asked to "analyze my business" and sends the entire orders history (10,000 rows) as context. Single call costs $50. Multiply by all users → monthly AI bill exceeds revenue.

**Why it happens:**
No token budget enforcement; "more context = better answers" fallacy.

**How to avoid:**
- Always pre-aggregate before sending to Claude: send summary stats, not raw rows.
- Enforce `max_tokens` limits per agent type: Content Agent ≤ 500 tokens output; Finance Agent ≤ 1024.
- Add per-workspace monthly AI credit cap (configurable; default: 100 Claude calls/month).
- Log token usage per call to Supabase `ai_usage` table; alert at 80% of cap.

**Warning signs:**
- No `max_tokens` set in Claude API calls.
- Edge Function builds prompt by joining raw database rows.
- No usage tracking table in schema.

**Phase to address:** Phase 7 (AI Agents) — bake in from first agent.

---

### Pitfall 9: E-Invoice Invalid Fields (NĐ 123/2020 Compliance)

**What goes wrong:**
Invoice issued without required fields (seller tax code, buyer address, item unit price in VND, correct tax category). Invoice is rejected by tax authority system; seller faces penalty.

**Why it happens:**
Developers test with a provider sandbox that accepts any payload; production API has stricter validation.

**How to avoid:**
- Implement a client-side validator (checklist per NĐ 123/2020) before submitting to provider API.
- Required fields: `mst_nguoi_ban` (seller tax code), `ten_hang_hoa` (item name), `don_vi_tinh` (unit), `so_luong`, `don_gia`, `thanh_tien`, `thue_suat`.
- Test the full cancellation/adjustment flow (hóa đơn thay thế / hóa đơn điều chỉnh) — not just creation.
- Store raw provider response including `ma_tra_cuu` (lookup code) per invoice.

**Warning signs:**
- Invoice submission succeeds in sandbox but fails in production.
- No validation step before calling the provider API.
- Cancellation flow not implemented.

**Phase to address:** Phase 8 (E-Invoice module) — validate before every submission.

---

### Pitfall 10: Flutter BuildContext Across Async Gaps

**What goes wrong:**
`Navigator.push(context, ...)` called after an `await` inside a widget method. The widget may have been disposed during the async operation; using its `context` crashes with "Looking up a deactivated widget's ancestor is unsafe."

**Why it happens:**
Common Flutter anti-pattern when mixing async calls with navigation/snackbar.

**How to avoid:**
```dart
// Always check mounted before using context after await:
Future<void> _submitOrder() async {
  await orderRepository.create(order);
  if (!mounted) return;   // guard
  ScaffoldMessenger.of(context).showSnackBar(...);
}
```

**Warning signs:**
- Flutter analyzer warning: "Don't use BuildContext across async gaps."
- Crash reports: "Looking up a deactivated widget."

**Phase to address:** Phase 2+ — code review checklist for all async widget methods.

---

### Pitfall 11: Bank Transfer False Positive Matching

**What goes wrong:**
Auto-detect matches the wrong order to a bank transfer because the payment reference (nội dung chuyển khoản) is ambiguous or user didn't follow the format. Order is marked paid incorrectly; finance records are wrong.

**Why it happens:**
VN bank transfers use free-text reference fields. Sellers tell customers "transfer with code XYZ123" but customers write "thanh toan mon an" instead.

**How to avoid:**
- Generate a unique short code per order (e.g., `RM-00142`) and instruct customer to use it.
- Matching algorithm: exact code match = auto-confirm; amount-only match = "likely match" (requires manual confirmation).
- Never auto-confirm on amount alone.
- Surface "unmatched transfers" list in Finance module for manual reconciliation.

**Warning signs:**
- Matching solely on `amount` without reference code.
- No manual review queue for ambiguous matches.

**Phase to address:** Phase 5 (Finance + Payments).

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Hardcode workspace_id in dev fixtures | Fast local testing | Masks RLS gaps until production | Never — use test workspace via auth |
| Skip platform HMAC verification in dev | Faster webhook testing | Security hole if forgotten in prod | Local dev only, with env flag guard |
| Use `SELECT *` in Supabase queries | Less typing | Over-fetches; exposes future sensitive columns | Never in production queries |
| Single "catch-all" Realtime channel | Simpler setup | Floods client with irrelevant events; battery drain | Never |
| Store AI API key in Flutter | One less Edge Function | Key exposed in APK | Never |

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| ShopeeFood | Treating webhook as guaranteed delivery | Implement idempotency + platform polling fallback |
| GrabFood | Assuming order IDs are globally unique | Namespace as `grabfood:{order_id}` in platform_order_id |
| MoMo | Not handling `resultCode` variants | Handle: 0 (success), 9000 (pending), 1006 (cancel) separately |
| ZaloPay | Trusting `data` field without signature check | Always verify `mac` before processing |
| VNPAY | Using redirect-only (no IPN) | Always implement IPN; redirect can be blocked/spoofed |
| TPBank | Assuming webhook is real-time | Can have 1–5 min delay; don't block UX on it |
| Claude API | Sending user order notes verbatim | Sanitise for prompt injection (remove `\n---\nHuman:` patterns) |

## Performance Traps

| Trap | Symptoms | Prevention | When It Breaks |
|------|----------|------------|----------------|
| Loading all orders on app start | Slow startup; high memory | Paginate (limit 20, cursor-based) | > 500 orders per workspace |
| Rebuilding entire order list on any Realtime event | UI jank on order updates | Use Riverpod family + targeted invalidation | > 50 concurrent orders |
| Syncing full Drift DB on every reconnect | Battery drain; slow sync | Delta sync: only queue items with `synced_at IS NULL` | Always — use delta from day one |
| RLS policy without index on workspace_id | Slow queries | `CREATE INDEX ON orders(workspace_id)` on every table | > 10k rows per table |
| Opening DB connection per repository | Connection pool exhaustion | Singleton Drift DB instance via Riverpod provider | Dev time — start right |

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Prompt injection via order notes sent to AI | Exfiltrate workspace data; manipulate AI output | Sanitise user content; system prompt hardening; output validation |
| No rate limit on Edge Functions | Abuse billing (AI calls) or DoS | Supabase rate limiting + per-workspace call cap |
| Storing customer PII in unencrypted columns | Data breach exposure | Supabase Vault for sensitive fields; mask in logs |
| Not rotating platform tokens when employee leaves | Persistent access after offboarding | Workspace-level token management with revocation |

## UX Pitfalls

| Pitfall | User Impact | Better Approach |
|---------|-------------|-----------------|
| No optimistic UI on order creation | App feels slow offline | Write to Drift immediately; show "syncing" indicator |
| Showing raw platform order IDs | Confusing to non-tech sellers | Generate friendly human IDs (`#142`) displayed alongside platform ID |
| Finance reports in accounting terminology | "Debit/Credit" confuses hộ kinh doanh | Use plain language: "Thu vào", "Chi ra", "Lợi nhuận" |
| Blocking UI while syncing | Frustrating during poor connectivity | All sync is background; UI always responsive |
| Error messages in English | Most sellers read Vietnamese only | All user-facing strings in Vietnamese; English only in dev logs |

## "Looks Done But Isn't" Checklist

- [ ] **RLS:** Every table has `ENABLE ROW LEVEL SECURITY` + at least one policy — verify with `SELECT tablename FROM pg_tables WHERE rowsecurity = false AND schemaname = 'public'`
- [ ] **Offline sync:** Disconnect device, create an order, reconnect — verify order appears in Supabase
- [ ] **Realtime:** Open two devices, create order on one — verify it appears on the other within 2s
- [ ] **Webhook idempotency:** Send same ShopeeFood webhook twice — verify only one order row exists
- [ ] **Payment HMAC:** Send MoMo webhook with invalid signature — verify 401 response
- [ ] **AI cost cap:** Exceed per-workspace call limit — verify error returned, not a successful expensive call
- [ ] **E-invoice cancellation:** Issue an invoice, cancel it — verify cancellation recorded with provider
- [ ] **Bank transfer ambiguous match:** Send transfer without reference code — verify it goes to manual review queue, not auto-confirmed

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| RLS missing on table | HIGH | Add policy + audit all rows for cross-workspace leaks; notify affected users |
| Duplicate orders from webhook | MEDIUM | Deduplicate via platform_order_id; merge finance records; alert sellers |
| Negative inventory | LOW | Manual adjustment with reason code; add constraint `CHECK (quantity >= 0)` |
| AI cost blowup | MEDIUM | Immediately cap; refund if overcharged; add retroactive limit |
| Invalid e-invoice issued | HIGH | Issue replacement invoice (hóa đơn thay thế); file with tax authority |

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| RLS missing on tables | Phase 1 | CI query: all public tables have rowsecurity=true |
| Recursive RLS policy | Phase 1 | Integration test: two-workspace isolation |
| service_role in Flutter | Phase 1 | Pre-commit hook: grep for service_role in lib/ |
| Realtime subscription leaks | Phase 2 | Navigate 10× and assert 1 active channel |
| BuildContext async gaps | Phase 2+ | Flutter analyzer + code review checklist |
| Offline inventory conflict | Phase 3 | Two-device concurrent order test |
| Duplicate orders from webhook | Phase 4 | Send webhook twice; assert single row |
| Payment signature not verified | Phase 5 | Send tampered webhook; assert 401 |
| Bank transfer false positive | Phase 5 | Send amount-only match; assert manual review queue |
| AI token blowup | Phase 7 | Verify max_tokens set; usage logged per call |
| E-invoice invalid fields | Phase 8 | Submit incomplete invoice; assert client-side validation rejects |

## Sources

- Supabase documentation: RLS patterns, common policy mistakes
- Flutter documentation: BuildContext lifecycle warnings
- Supabase community forum: Realtime subscription gotchas
- Vietnamese fintech developer community: VN payment integration notes
- NĐ 123/2020/NĐ-CP: e-invoice required fields
- Anthropic documentation: prompt injection mitigation

---
*Pitfalls research for: RiMi — Flutter + Supabase F&B SaaS*
*Researched: 2026-05-31*
