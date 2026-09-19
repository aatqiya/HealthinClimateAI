# Resilio — environmental planning for iOS

Open `ExposureNavigator.xcodeproj` with Xcode 16+ and run the `ExposureNavigator` scheme on an iOS 17+ device or simulator. The installed app is named **Resilio**; the existing project/bundle identity is retained to preserve local data. The supplied logo is used for the app icon and in-app branding, with sage, forest green, white, and adaptive gray surfaces.

## What changed

- Onboarding: honest local-device entry, optional location/manual place search, separately required terms/privacy acceptance, optional health-data explanation, and profile setup/selection. Completion and agreement version/date persist.
- Exactly four tabs: **Home · Schedule · Calendar · Profile**. No About or AI tab.
- Home: active profile, real current-hour forecast cards, hourly outlook, local planning assistant, upcoming plans, and Calendar event deep links.
- Schedule: profile, event name/type, exact place/address, date, start, fixed duration, bounded time flexibility. Autocomplete and an explicit Search fallback both require selecting a real location. Times use the location's time zone. No duration-shortening control.
- Results: original conditions, up to five useful time alternatives, explicit selected plan, keep-original choice, source/methodology disclosure, public-health context, and save/update. Failed analysis offers retry or an explicit save-without-analysis action.
- Calendar: month grid with event dots, selected-day and upcoming plans, live event details, stale forecast checks, edit, re-analyze, delete, Apple Calendar reading, and export through Apple's native editor.
- Profile: create/edit/switch/delete, optional validated age/home ZIP, reusable suggestions/custom tags, case-insensitive duplicate prevention, and 25-entry limits per health field. Profile deletion also removes its Resilio plans after confirmation.
- Settings: temperature units, saved manual location, iOS permission shortcut, privacy, and truthful service connection states.

## Preserved and hardened

The baseline time-weighted exposure integral and 75% coverage threshold for displaying available estimates remain. Comparisons require complete particle data for both plans so missing hours cannot appear as a reduction. The 10% display threshold is described as a product threshold, not a health threshold. Fixed-time plans never shift. Candidate starts remain inside the user's window, never in the past, and keep duration fixed. Heat is displayed alongside options; arbitrary Celsius percentages are not used as exposure reductions.

Events retain profile IDs and original baseline times independently from chosen start times. Re-analysis updates the same event ID. No health details are copied into events or environmental requests. JSON storage reports failures and refuses to overwrite unreadable files. Existing file names and profile decoding compatibility are retained.

Shared forecast caching avoids repeated upstream requests, preserves retrieval provenance, and distinguishes app checks from source updates. Forecast update times not supplied by the source are not invented. All application environmental values are real; only the explicitly selected Maya demo profile is synthetic.

## Verify

Run `Tests/run.sh` for deterministic regression checks covering exposure integration, coverage, feasibility, storage, profile ownership, assistant extraction, and caching. Test fixtures are isolated from app data and never displayed in the product.

See [IMPLEMENTATION_REPORT.md](IMPLEMENTATION_REPORT.md) for the change inventory, verified behavior, known limitations, and exact demo script. See [INTEGRATIONS.md](INTEGRATIONS.md) for available services and configuration requirements.
