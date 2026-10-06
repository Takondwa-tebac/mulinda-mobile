# Mulinda Mobile

Flutter app (Dart ^3.10.8) for Mulinda, an AI personal-finance assistant for Malawi. Backend: `../mulinda-api` (Laravel, Sanctum bearer auth).

## Stack
Riverpod (state), go_router + app_links (routing), dio (network), flutter_secure_storage (tokens), easy_localization (Chichewa default + English), Firebase messaging, image_picker (receipts), flutter_sms_inbox (SMS capture).

## Structure
- `lib/core/` — env, network, router, storage, theme, localization, money, notifications, permissions, security, widgets
- `lib/features/<name>/` — activity, admin, auth, capture, coach, dashboard, export, insights, legal, onboarding, plan, profile, shell, subscription, summary

## Conventions
- Follow sibling-file structure and naming in the feature you touch.
- All user-facing strings go through localization with both Chichewa and English.
- Money arrives as integer minor units + currency; format via `lib/core/money`.
- AI-derived data (SMS/receipt) is propose-then-approve; never auto-commit to the ledger.
- Run `flutter analyze` and `flutter test` after changes.
