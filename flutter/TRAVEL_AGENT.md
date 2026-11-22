# HEIST Travel Agent

Route: `/travel/planner`. Desktop: Travel Agent in the rail. Mobile: More → Travel Agent.

## Delivered

- Trip brief: starting city, destination, departure, 1–14 days, 1–30 travelers, total group budget, currency, pace and preferences.
- Two server steps: live Groq browser research, then a structured itinerary based on those sources. Research is saved to SQLite before planning. Retrying after failure/restart skips completed research. Editing the brief resets research and itinerary after confirmation; local recovery preserves the previous revision.
- Day-by-day stops, manual additions, ordering, removal, source links, Google Maps place searches and day routes. Maps open externally and require network; no offline map tiles or automatic route optimization is claimed.
- Suggested stays with area, estimated nightly cost, amenity/name search and budget filter. Direct dated Booking.com search, Tripadvisor discovery and Google search restricted to MakeMyTrip hotel pages. Provider reviews, cancellation policies, taxes, prices and availability are checked on the provider. No booking inventory/API affiliation or fabricated ratings.
- Per-trip expenses, remaining budget, named payers and equal splits with deterministic cent rounding. Trip expenses are separate from the main spending ledger. No automatic exchange rates or payments.
- Itinerary sharing as a versioned JSON copy without expenses. Full restorable backups, including trip expenses and research, use the existing versioned backup flow under Backup & settings. Shared copies are not simultaneous collaboration; live group itinerary editing is not implemented.
- SQLite persistence, Hive recovery snapshots and existing encrypted vault synchronization include `travelTrips`. Existing account conflict handling applies to the full vault. Preferences remain in Hive. AI generation is not queued automatically: the user retries/resumes explicitly to avoid unexpected API usage.

## Server configuration

Deploy `supabase/functions/travel` and update `supabase/functions/ai`, including `_shared/groq_pool.ts`. New travel requests require a valid existing Supabase user session, verified through Auth. Do not disable authentication. Native clients may omit Origin; browser origins must exactly match `ALLOWED_ORIGINS`.

Keep the deployed `GROQ_API_KEY` as primary. Add comma-separated `GROQ_FALLBACK_KEYS` as Supabase server secrets. The supplied fallback keys are stored only in ignored `supabase/.env.travel.local`, not in Flutter configuration, APK assets, public JS or Git. Template: `supabase/.env.travel.example`.

The pool retries the identical complete request on another available key for 401/403/408/429, network errors and 5xx. Cooldowns honor numeric Retry-After (minimum 60 seconds); invalid keys cool for an hour. Configuration errors stop rather than consume all keys. Provider/account-wide quotas can affect every key: rotation does not increase shared account limits. Fallback restarts an incomplete request; it does not resume an internal model token stream. The saved research checkpoint is retained across retries.

Default travel model: `openai/gpt-oss-20b`, configurable through server `TRAVEL_GROQ_MODEL`. Research requires Groq `browser_search`; planning uses JSON mode separately because browser search and structured output cannot be combined. No Google Search API key is needed for this provider's built-in search. Google links are external discovery/navigation links.

Only trip destination, dates, traveler count, budget, currency, origin, pace and preferences are sent for AI research. Names, wallet balances and recorded expense history are excluded. Web text is treated as untrusted data; external links allow HTTPS only. Budget values and imported trips are validated before local replacement. Per-user rate counters and key cooldowns are instance-local safeguards, not a distributed billing limit; configure provider spending limits for production.

## Reference study

1. Wanderlog: itinerary beside maps, route planning, cost categories and shared planning. https://wanderlog.com/plan-a-trip
2. Tripadvisor: review-led discovery, AI recommendations and editable itinerary. https://www.tripadvisor.in/AIAssistant
3. MakeMyTrip: Indian hotel and multimodal travel discovery. https://www.makemytrip.com/hotels/
4. Booking.com: accommodation comparison, guest reviews, filters and price transparency. https://www.booking.com/content/how_we_work.html
5. TravelSpend: offline expense entry, category budgets and shared balances. https://travel-spend.com/
6. Groq: browser search support and request shape. https://console.groq.com/docs/tool-use/built-in-tools/browser-search

## Verification

Backend tests: `node --experimental-strip-types --test tests/travel-agent.test.mjs` from repository root. These mock provider responses and cover quota fallback, unchanged request context, cooldowns, failures without key leakage, origin/auth guards, source filtering and two-step planning.

Flutter tests cover checkpoint recovery after restart, failed plan retry without repeated research, backup preservation, validation and group rounding. Existing app route tests include Travel Agent. Tests distinguish mocked backend behavior from actual live provider validation; consult the completion report for build/deployment results.

### Verified on 2026-11-22

- 45 Flutter tests passed, including the saved trip's five panels at 360 pixels and all nine desktop sections.
- Six backend tests passed. Static analysis: no issues. Git whitespace checks passed; no provider key values were found in publishable changes.
- Android release 1.0.2 (version code 3), package `io.github.tejjj777.heist.flutter`, 95,027,565 bytes. APK ZIP integrity and APK Signature Scheme v2 verified. This remains a test-signed build.
- APK SHA-256: `127269671fecbd18fa136588e6bdc2b0c571a86f8bb009318fae3ab9844d4aee`.
- Final Android release build and final web release build succeeded. Web Wasm dry run also succeeded; a Wasm production build was not run.
- Supabase dashboard confirmed the new `travel` function, updated `ai` function (deployment 19), and saved `GROQ_FALLBACK_KEYS`. Existing primary key and authentication settings were retained.
- Live Groq key checks from this Windows environment returned HTTP 403 with a non-JSON Cloudflare response; this does not establish whether a key is valid. Live search and real account end-to-end itinerary generation are unverified. Backend tests use controlled mocked provider responses.
- Motorola was absent from ADB on the final device check. The new release was not installed on the phone.
- The existing GitHub Pages frontend was preserved; the updated Flutter web build has not been published there. Live itinerary collaboration, in-app offline maps, booking transactions, live hotel inventory and automatic foreign exchange are not included.
