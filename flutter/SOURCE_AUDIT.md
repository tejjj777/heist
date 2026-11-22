# Source and contract audit

Source repository: https://github.com/tejjj777/heist

Base inspected: `4caae4b15e956bbc8a9d7c0f49f429b4d21848d3`. The existing HTML/JS frontend is preserved alongside the additive `flutter/` directory. The live application was inspected in Chrome, including Today, Spend, Budget, Split, Goals, Debt, Settings, and the signed-in Account panel. No production user records or account settings were changed during inspection.

## Navigation inventory

| Section | Existing tabs |
| --- | --- |
| dashboard | overview, forecast, semester, calendar, charts |
| spend | log, categories, insights, recurring, cash |
| budget | plan, where, yearly, history |
| split | ious, groups, history |
| goals | savings, goals, wishlist, challenges, gifts |
| debt | debts, plan, emi |
| wallet (legacy) | cash, ious, subs, transport |
| settings | Basics, Money, Data, Help |
| account | Email link / code, new vault, passphrase unlock, recovery, device/account choice, manual sync, sign out, conflict copy, change passphrase, replace recovery key, delete account |

Additional flows in source: quick-add and command palette, AI costed planning, bill item assignment and settlement, UPI links/QR, receipt/payment-screenshot OCR, bank CSV/SMS import, PDF payslips, subscription check-in, carry-over/month rollover, weekly challenges, crew heists, Money Wrapped, Slime/XP/rewards, localization, simple view, student/working modes, tours, calendar export, privacy mode and legal pages.

## Data model

The legacy `heist.v1` document has `version: 1`. Principal collections are `budget.categories`, `budget.expenses`, `goals`, `gifts`, `debts`, `subscriptions`, `recurring`, `yearlyBills`, `incomeLog`, `history`, `rules`, `wishlist`, `challenges`, `payslips`, `wallet.cash`, `wallet.ious`, `wallet.transport`, `wallet.taxes`, `wallet.deadlines`, `groups`, `groupData`, and `groupRecurring`. Expenses link to recurring payments, group expenses, split bills, debt payments and goal roundups. Flutter retains unknown keys so imports do not discard data belonging to features that have not yet reached parity.

## Account synchronization

The account API is Supabase GoTrue plus PostgREST. The frontend uses a **publishable** API key; no service-role key belongs in the frontend.

- Email sign-in: `POST /auth/v1/otp`, verification: `POST /auth/v1/verify` with `{type:'email',email,token}`.
- Refresh: `POST /auth/v1/token?grant_type=refresh_token`; sign-out: `POST /auth/v1/logout?scope=local`.
- One `vaults` row per user, enforced by RLS (`user_id = auth.uid()`). Columns: `user_id`, `kdf`, `key_pass`, `key_recovery`, `data`, `version`, `device`, `updated_at`.
- Updates use `PATCH /rest/v1/vaults?user_id=eq.<uid>&version=eq.<expected>`, with `Prefer: return=representation` and `{data,version:expected+1,device}`.
- Data envelope: JSON `{v:1,z:0|1,c:<base64>}`; compressed payload is gzip when `z=1`.
- AES-256-GCM packing: nonce (12 bytes), ciphertext, authentication tag (16 bytes).
- Passphrase wrapping: PBKDF2-HMAC-SHA256, 600,000 iterations, random 16-byte salt, 256-bit wrapping key.
- Recovery wrapping: normalized 32-character Crockford base32 secret, PBKDF2-HMAC-SHA256, 1,000 iterations and a separate salt. Recovery retains the existing wire format rather than changing existing account keys.

The Flutter queue uses a conditional version update and recognizes an already-applied snapshot after a lost response. Divergence parks both documents and requires an explicit choice. It does not replace server access controls or deploy database changes.

## Live groups and crew heists

The legacy group client uses a separate anonymous Supabase identity from the email-encrypted vault account. Flutter keeps those credentials separate too. A new device must join with the group code to establish its own member identity; an imported member ID alone does not prove authorization.

Existing tables: `groups`, `group_members`, `group_expenses`, `group_expense_splits`. Join RPC: `join_group({code,member_name})`. The authenticated payer owns update/delete rights; all requests continue to be subject to server RLS. Public member names and shared expenses remain unencrypted in those existing tables, unlike the personal account vault.

Crew heists encode metadata in `group_expenses.description`: `HEIST_GOAL {json}` and `HEIST_DEPOSIT`. These rows must be excluded from debt balances and personal spending.

The repository contains `supabase/heist-fixes.sql`, documenting missing deployed group edit/delete policies. This migration does not execute that script: it also deletes old production test data, and server policy deployment needs separate review/access.

## AI, OCR and files

`POST /functions/v1/ai` receives `{task,input}`. Commands send text plus rounded numeric financial context; the planner sends conversation messages, currency and date. Vision receives `{image,today}` and returns `{txns}`. External model secrets exist only in server environment variables. The original frontend bundles Tesseract.js and PDF.js for on-device fallback. Browser origin allowlists may need to include a newly deployed Flutter origin; native requests are subject to the endpoint's existing rules.

## Validation boundary

Production account synchronization cannot be tested end to end without the user explicitly signing in and unlocking a test account. Tests must use mock transport or a separate authorized test account. Reading the existing signed-in panel does not grant access to its tokens or passphrase.
