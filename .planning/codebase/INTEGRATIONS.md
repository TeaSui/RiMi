# External Integrations

**Analysis Date:** 2026-05-31

## APIs & External Services

**Payment Processing:**
- None — not integrated

**Email/SMS:**
- None — not integrated

**External APIs:**
- Google Fonts CDN - Runtime font delivery for Bricolage Grotesque and Be Vietnam Pro typefaces
  - Integration method: HTTP fetch via `google_fonts ^6.2.1` package at app startup / first render
  - Auth: None (public CDN)
  - Fonts are cached locally on-device via `path_provider` after first download
  - Note: app requires internet access on first launch to load fonts; subsequent runs use cache

## Data Storage

**Databases:**
- None — all data is in-memory mock data defined in `flutter/lib/data/mock_data.dart`
- `OrderStore`, `ProductStore`, `CustomerStore` are `ChangeNotifier` singletons holding hardcoded seed lists

**File Storage:**
- None

**Caching:**
- Font cache only (managed automatically by `google_fonts` via `path_provider`)

## Authentication & Identity

**Auth Provider:**
- None — app launches directly into the main shell with no login gate
- Explicitly described as "no auth gate" in `flutter/README.md`

**OAuth Integrations:**
- None

## Monitoring & Observability

**Error Tracking:**
- None — not integrated

**Analytics:**
- None — not integrated

**Logs:**
- `avoid_print` lint rule enforced (`flutter/analysis_options.yaml`) — print statements are disallowed
- No structured logging or remote log sink

## CI/CD & Deployment

**Hosting:**
- Not configured — project is a UI prototype with no deployment pipeline

**CI Pipeline:**
- Not configured — no `.github/`, `.gitlab-ci.yml`, or equivalent CI config found

## Environment Configuration

**Development:**
- Required env vars: None
- Secrets location: Not applicable — no secrets required
- Mock/stub services: All data is in-process mock (`flutter/lib/data/mock_data.dart`); no external service stubs needed

**Staging:**
- Not applicable

**Production:**
- Not applicable — prototype only

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## Integration Readiness Notes

The codebase is explicitly designed for integration extension. From `flutter/README.md`:

> "Swap the `ChangeNotifier` stores for your real data source; the widgets read them through `ListenableBuilder`."

The three stores (`OrderStore`, `ProductStore`, `CustomerStore` in `flutter/lib/data/mock_data.dart`) are the single integration seam — replacing them with real API clients requires no widget changes. The `flutter/lib/features/ai/ai_page.dart` AI chat feature (bot list + chat UI) is currently purely mock and is the most likely candidate for a real LLM/API integration.

---

*Integration audit: 2026-05-31*
*Update when adding/removing external services*
