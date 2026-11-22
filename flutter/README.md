# HEIST Flutter frontend

Additive migration of https://github.com/tejjj777/heist at `4caae4b15e956bbc8a9d7c0f49f429b4d21848d3`. Original HTML/JavaScript files and the published site remain intact. See [SOURCE_AUDIT.md](SOURCE_AUDIT.md) for routes/models/contracts and [VALIDATION.md](VALIDATION.md) for executed checks. This implementation has not reached full legacy feature parity.

## Setup and builds

Official stable Flutter 3.50.1 / Dart 3.14.0 are installed in `../../sdk/flutter`. `tool/workspace.ps1` sets process-local SDK, cache, preferences and Android/JDK paths. It does not change machine PATH. Dependencies are locked in `pubspec.lock`. Material widgets use the maintained `material_ui` package following Flutter 3.50's package split; Hive uses maintained `hive_ce`.

Copy `config.example.json` to ignored `config.local.json`, or run `node tool/prepare_config.mjs` to obtain the existing public Supabase configuration from the original client. Build defines are public. Never add service-role keys, tokens, OTPs, passphrases, recovery keys or email credentials. Configure an auth redirect URL approved in Supabase. Android supports email codes; native email deep links are not configured.

```powershell
. ./tool/workspace.ps1
flutter pub get
dart tool/setup_web.dart
flutter analyze
flutter test
flutter build web --release --base-href=/heist/ --no-web-resources-cdn --pwa-strategy=none --dart-define-from-file=config.local.json
node tool/build_offline.mjs
node --test tool/offline.test.mjs
```

SQLite setup compiles the package's shared worker and downloads its matching WASM version. Run the offline build tool after every web build: it hashes and precaches the local bundle including CanvasKit, fonts, SQLite and OCR files. Serve `build/web/` over HTTPS or localhost. `node tool/preview_server.mjs` serves `/heist/` at localhost port 8765. For a domain root use base href `/`. The root GitHub workflow validates and uploads web/debug APK artifacts without deployment; it has not been executed on GitHub.

Android needs Java 21, Android SDK tools and accepted Google SDK licenses. The verified APK's minimum API is 24. Application ID `io.github.tejjj777.heist.flutter` allows installation beside the existing app. Debug builds use `flutter build apk --debug --dart-define-from-file=config.local.json`; release-mode test builds use `flutter build apk --release --dart-define-from-file=config.local.json`. The supplied release-mode APK uses an Android Debug test certificate, verified with apksigner. Publication needs the owner's signing configuration. Windows native additionally requires Visual Studio's C++ desktop workload.

## Implemented workflows

All audited dashboard, spend, budget, split, goals, debt and legacy wallet routes have Flutter screens. Layouts provide desktop navigation and a phone drawer. The shell normalizes existing hash links and uses the original logo/fonts with purple outlined cards.

| Area | Implemented |
| --- | --- |
| Today | Balances, daily limits, upcoming reserves, forecast/habits, semester planning, calendar, spending charts |
| Spend | Expense CRUD/search, categories, insights/heatmap, recurring bill planning/manual posting, cash ledger |
| Budget | Income/month overrides, category plans, allocations, annual bills, subscriptions, automatic recurring posting, month rollover/carry-over and snapshots |
| Split | Local IOUs/settled history, equal/item-assigned bills with exact cents and proportional charges, INR UPI/QR links, group create/join, cached data, balances, settlement recording and queued shared expenses |
| Goals | Savings summary, emergency fund, contributions with linked expenses, wishlist, gifts, basic challenges |
| Debt | Debts, linked principal payments, avalanche/snowball projections, loan amortization |
| Wallet | Cash/income, bank baseline, deadlines, transport/tax logs, manual payslip records |
| Import | CSV/SMS review and duplicate filtering, local receipt OCR with review |
| Account | Email code/link sign-in, vault creation/unlock/recovery, device/account choice, secure session persistence, sign-out, conflict resolution, protection rotation, cloud account deletion |
| Data | Versioned export/import, checksum validation, revision restore, sync pause after restoration, queue/error inspection and retry |

Linked goal/debt/split/group expenses are protected against generic direct edits. Debt payment entry records principal; projection tools model interest separately. Cash/transport/tax logs do not automatically create budget expenses. Subscriptions need matching recurring bills to reserve money. Forecasts/charts currently offer fewer views than the original.

Financial parity limits: daily allowances currently use monthly pay-date anchors and calendar-month fallback for other frequencies. Full legacy irregular-income, early-period closure and semester forecast calculations are not ported. Rollover records category carry-in, but some category/balance displays still omit its legacy treatment. Legacy wallet tab paths currently show consolidated wallet tools; IOUs and subscriptions remain available in Split and Budget. These are implementation gaps, separate from the environment/test blockers below.

## Persistence and synchronization

SQLite is authoritative: typed expense/category/goal tables, generic entities, document revisions, owner-tagged queue, sync metadata and parked conflicts. A local edit and its queue entry commit in one transaction before publishing UI state. Writes are serialized. Twenty SQL revisions and ten flushed Hive recovery documents are retained. Hive also stores device preferences. Web SQLite uses IndexedDB through sqflite_common_ffi_web; Hive uses browser storage. Browser eviction, clearing site data and app removal can delete local data.

Personal sync retains the existing AES-256-GCM/gzip envelope, PBKDF2-SHA256 passphrase wrapping at 600,000 rounds and separate legacy recovery wrapping. Personal vault uploads contain encrypted documents. Tokens and the unlocked data key use flutter_secure_storage; passphrases are not persisted. Android uses protected platform storage. Web requires HTTPS/localhost and the plugin's WebCrypto storage; its protection depends on page/browser security. Local SQL/Hive data and JSON exports are not application-encrypted. Android OS backup is disabled to avoid copying credential material across installations.

Pending personal snapshots coalesce at upload. Conditional server versions detect divergence. Decrypted document comparison recognizes a committed upload after its response was lost. Transient errors back off; permanent failures remain visible for review/retry. Conflicts retain both copies and require an explicit choice. Account-owner tagging and an explicit bound-owner check prevent one email account receiving another account's pending writes. Sync stays suspended during account-copy selection; newly unlocked keys are persisted only after the user's choice is committed. Switching email accounts requires sign-out first.

Groups retain the separate anonymous identity and existing RLS. Stable expense/split UUIDs and record comparison support interrupted insert retries. Imported member IDs do not prove authorization; new devices must join online. No backend policies or production records were changed. Crew-heist sentinel records remain preserved and are excluded from personal expense creation.

Sync runs while the app is open: local changes, reconnection, manual requests and periodic polling. OS background execution and closed-browser uploads are not implemented. An online network interface can still lack internet; request failures retain the queue.

## Offline use

Web needs one complete online installation before offline launch; installed native apps can start without internet. Expenses, budgets, local IOUs, goals, debt/loan tools, imports, backups and cached shared data work locally. Existing device memberships can queue shared expenses offline. Receipt OCR uses bundled English Tesseract data on web and bundled Latin ML Kit on Android. Simple expense/affordability commands run locally.

Internet is required for first web installation, sign-in/token refresh, first group create/join, remote updates/uploads, cloud account changes/deletion and cloud AI. Costed AI plans/cloud vision are not yet ported; the client does not bypass native-origin restrictions in the existing backend.

## Backups and migration

Export creates a `heist-backup` version 2 envelope with the legacy version 1 document, timestamp and canonical SHA-256 checksum. It excludes credentials, data keys and private queue metadata. Checksums detect accidental alteration; they are not signatures or encryption.

Import accepts version 2 and original raw HEIST version 1 JSON up to 20 MB. It validates structure, IDs, expense dates, nonnegative finite amounts and checksums before writing; unknown fields remain. The UI previews filename/expense count and confirms replacement. Restoration creates a new revision, retains the prior planner and pauses sync for review. It does not merge records or immediately upload the restored planner. Group identity credentials are not restored.

On the existing web origin, a fresh Flutter database automatically imports the original `heist.v1` planner into SQLite. It leaves the original browser value and account credentials unchanged. Existing SQL/Hive data takes priority; invalid legacy data is rejected before creating a replacement. The user signs in again rather than importing old credentials. Native/different-origin previews cannot read the original site's localStorage: import an existing HEIST JSON export there. Keep exports outside this device; local recovery history is separate from disaster backup.

## Remaining parity and release gates

Outstanding: group expense edit/delete and crew-heist UI; costed AI plans/cloud vision; PDF payslip extraction; Money Wrapped image/story exports; Slime/XP/rewards; localization, full simple/student/working modes and tours; calendar export and push alerts. Preserving their fields does not implement their workflows. Native email deep links, owner release signing, authenticated production integration tests and physical-device OCR/storage checks remain release gates. Do not replace production until these gaps are resolved.
# Travel Agent update (1.0.2)

Open **More → Travel Agent** on mobile, or **Travel Agent** on desktop. Create a trip and use **Research & build trip** after signing in. Saved itineraries, manual stops, trip expenses and split balances work offline. Live research, maps and booking comparisons need internet.

See [TRAVEL_AGENT.md](TRAVEL_AGENT.md) for features, reference research, server configuration and validation limits. The production `travel` function and AI fallback update were deployed to the existing HEIST Supabase project. No provider keys belong in Flutter configuration.
