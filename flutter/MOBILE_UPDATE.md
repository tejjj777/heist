# Mobile update — 22 November 2026

## Source changes

- Settings routes now have separate Basics, Money, Data and Help interfaces. Data retains encrypted-account controls, pending writes, conflict resolution, JSON export/import and recovery history. Money contains currency, allowance and bank balance controls. Basics contains appearance, language and amount privacy.
- Amount privacy can be toggled from the app bar or Basics. Displayed monetary values use masked text rather than a reversible visual blur. The preference is saved locally in Hive; the underlying financial records are unchanged. Input/edit forms and explicit exports still contain actual values.
- Wallet routes now show cash, IOUs, subscriptions, transport, income/payslips and other records separately. Case-insensitive search, date ranges and cash direction filters are applied to collection records. Cash ledger balance remains the total balance, independent of the displayed-record filters.
- English, Telugu and Hindi choices persist in Hive. Bundled translations cover navigation, settings, onboarding, common actions and wallet filters. Flutter Material controls use the selected locale. Noto Telugu/Devanagari fonts and their OFL licenses are bundled for offline rendering. Some advanced descriptions, financial reports, validation/errors and account workflows remain in English; complete application localization is not claimed.
- A five-step tutorial appears on first app use, persists completion/skipping, and can be replayed from Help. It introduces budget setup, receipt review, offline saving, sync/backup restoration and privacy/language. Existing users see it once on the first launch of this revision.
- Receipt scanning has a persistent app-bar entry, plus Spend and Help controls. Android/iOS offer camera and gallery; web uses the browser's image/capture support. Android interrupted-picker recovery is handled. Existing bundled Latin OCR runs before an editable review form; financial records are saved only after the user confirms. Telugu/Hindi receipt OCR is not provided by the Latin model. Physical camera capture/OCR remains unverified.
- Mobile navigation now exposes Today, Spend, Wallet and More; More opens all sections in the drawer. Cards use smaller phone padding and fit narrow screens. Desktop navigation remains available.

## Validation status

Dependency resolution succeeded with Flutter 3.50.1/Dart 3.14.0, adding official Flutter localizations and image_picker 1.2.4. Google Fonts downloads and licenses are present. Git whitespace checks passed. These are not substitutes for compilation or runtime checks.

Fresh validation completed:

- `dart format lib test`: completed.
- `flutter analyze --no-pub`: no issues found on the final application/test sources (71.5 seconds).
- `flutter test --no-pub --reporter expanded`: **42 passed** (19 seconds), including separate settings screens, wallet routes/search/date filters, tutorial dismissal/replay, phone privacy/language/scanner choices and Hive preference persistence after reopening storage. Native camera/OCR calls are not exercised by widget tests.
- Android release APK built successfully in 369.4 seconds, 94,781,229 bytes (90.4 MiB). Package `io.github.tejjj777.heist.flutter`, version `1.0.1`, version code `2`, API 36 build. APK Signature Scheme v2 verification passed. It remains signed with the Android Debug test certificate.
- APK SHA-256: `15ff6ea2595a09850a998e0487b4f7864832508657a67397b0168e9550c80866`.

Automatic approval review initially rejected unrelated Visual Studio telemetry. Validation succeeded with external network proxies disabled. The Android build needed repository metadata/dependencies for the new camera picker. A loopback download proxy allowed only official build repository hosts through the existing managed proxy, rejecting unknown hosts before connecting. This allowed the build without authorizing telemetry or bypassing TLS certificate validation. The temporary proxy was stopped after the build.

ADB detected the authorized Motorola Edge 50 Pro. Its previous installed app reported version 1.0.0/code 1. Update-only installation was attempted without uninstalling or clearing data. The USB connection disappeared during streamed transfer and later during push transfer (`failed to read copy response: EOF`). A successful installation or launch of 1.0.1 is **not verified**. Reconnect/unlock the phone before retrying; verify installed version after reconnecting. Existing app data was never deliberately removed.

Live backend sign-in/sync still requires a disposable test account. Actual Moto camera/OCR, offline restart/reconnect and interactive backup restoration remain unverified. Previously documented financial/feature parity gaps remain unless explicitly addressed above. The previously distributed web ZIP predates this mobile update.

## Configuration and data

No backend API/schema change, embedded secrets, production data changes, website deployment or remote push. SQLite local-first persistence, the durable owner-bound synchronization queue, backup validation and restore-time sync pause are retained. Device-local Hive UI preferences are intentionally separate from portable planner backups and do not enqueue financial synchronization changes.

## Reinstallation follow-up

The 1.0.1 APK was saved successfully as an updated downloadable copy (94,781,229 bytes). Further ADB attempts could briefly detect the Moto, but normal file-sync transfers failed even with a 1 MiB test. A shell-input test stored only 729 bytes, matching the first DOS EOF control byte in the input, suggesting a binary stdin handling issue. An encoded-transfer test was prepared to avoid that issue, but could not run because the phone remained disconnected during its bounded connection wait. Version 1.0.1 installation remains unverified; the last observed installed version was 1.0.0. No uninstall or data-clear operation was performed.
