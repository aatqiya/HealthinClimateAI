# Resilio refinement

## Implemented

- Shared spacing, surfaces, corners, button states, and native form treatment across Home, Schedule, results, Calendar, Profile, Settings, and sheets. Home now has one integrated brand/greeting/profile header. The removed Schedule introduction remains removed.
- Shared US AQI logic, full category badges, numeric peak readings, partial-coverage labels, and a compact six-category scale with a position marker and expandable explanation. Option selection has a separate checkmark and accessibility selected trait. Category meaning never depends on color alone.
- A weekly Home overview with one segmented ring, a seven-day timeline, an optional category breakdown, one data-derived insight, PM2.5 coverage and mean, and a detailed calculation/contributing-plan sheet.
- One shared privacy explanation linked from Home, optional health fields, onboarding, and Settings. The assistant is accurately described as running on-device.
- Native Dynamic Type, light/dark surfaces, VoiceOver descriptions, and native interactions. At accessibility text sizes, Home stacks its overview and Calendar uses a native date picker. No custom movement or chart animation is introduced; native transitions retain system Reduce Motion behavior.

## Calculation and persistence

AQI uses the highest valid provider-reported US AQI in any hour overlapping the activity. Nonfinite, negative, missing, or unrepresentable readings are unavailable. Values are rounded once to the nearest integer, then graded using the [AirNow US AQI categories](https://www.airnow.gov/aqi/aqi-basics/). AQI is independent of raw PM2.5 concentration and its exposure comparison. Existing fixed durations, flexibility limits, coverage eligibility, and minimum percentage improvement are preserved.

The weekly period is today plus the six preceding calendar days, ending at the current time, in the device's reporting timezone. Only the selected profile's saved Resilio plans contribute, using their selected start times. External calendar events must first become a Resilio plan for that profile.

A boundary sweep divides elapsed scheduled time at event, hourly-record, retrieval, and local-day boundaries. Every interval is counted at most once. Same-coordinate overlapping events use the latest eligible saved reading for each metric, with deterministic ties. Different-coordinate overlaps are counted as scheduled time but excluded from both environmental metrics and disclosed as conflicts.

Each interval contributes its duration to its hourly AQI category. PM2.5 has separate coverage: its mean is the time-weighted concentration over valid covered time; its cumulative modeled estimate is concentration × covered hours in µg·h/m³. Missing time is never zero exposure. The overview describes estimated outdoor ambient conditions, not attendance, personal dose, indoor conditions, or progress toward a health goal.

Newly analyzed plans save an optional `SavedEnvironmentalWindow`: selected-window hourly values, location, source, measurement kind, retrieval/update times, timezone, interval semantics, and attribution. Older JSON remains compatible. Legacy aggregate summaries cannot establish hourly coverage and remain missing in the weekly view. No historical service or substitution with today's forecast was added; forecast records retrieved after an interval are excluded from that past interval.

## Privacy review

Reviewed profile/event storage, Open-Meteo requests, MapKit search and reverse geocoding, the local assistant, EventKit reading/export, HealthKit, route-service requests, project dependencies, and existing terms/privacy text.

- Profiles, health details, plans, preferences, and environmental snapshots are local. Weekly computation adds no network requests.
- Open-Meteo receives coordinates, not names, health profiles, or calendar titles.
- Apple Maps receives search text, including ZIP searches; Apple location services resolve coordinates to place names.
- External services receive ordinary connection information, including IP addresses.
- Calendar export copies title, selected times, address, and timezone through Apple's editor only when the user saves; the selected calendar service may sync that copy.
- HealthKit currently requests permission without reading or storing measurements.
- The optional route adapter sends origin/destination place objects and travel mode to a configured server. It is not configured in this build. Hosted AI, accounts, Google Calendar, and Outlook are not enabled.
- No advertising or analytics SDKs were found. A broader promise about selling information or using it for advertising was omitted because an applicable business policy is not present in the repository. Third-party retention, AI training, anonymity, encryption guarantees, and compliance are not asserted.
- The explanation includes deletion, permission management, separate exported calendar copies, and device backups.

## Verification

- `bash Tests/run.sh`: **85 regression checks passed** (32 existing plus 53 additional checks).
- AQI tests cover every boundary, fractional rounding, invalid/missing values, partial/multiple hours, duplicate-hour coverage, and a 20% lower PM2.5 alternative that remains Unhealthy.
- Weekly tests cover weighted category/particle totals, reporting boundaries, elapsed portions, missing and invalid values, separate metric coverage, overlapping/conflicting events, profile isolation, timezone/DST, old records, provenance round trips, and rejection of later forecasts for past intervals.
- Xcode Debug build succeeded for the generic iOS Simulator destination (arm64 and x86_64). Only the nonblocking AppIntents metadata warning appeared; this app has no AppIntents dependency.
- Visual review on an isolated iPhone SE (3rd generation), iOS 18.2: onboarding, Home, Schedule, live results, Calendar, event details, Profile/editor, Settings, weekly details, and privacy. Checked light/dark appearances and accessibility text sizes, including the largest size for Home and weekly details. Inspected accessibility labels and selection state through the simulator accessibility tree.
- Live Open-Meteo refresh and comparison flow succeeded for a public test location. Saving the analyzed test plan preserved all eight fixture plans and persisted the selected-hour forecast with provenance.
- `git diff --check` passed.

Full spoken VoiceOver navigation and Reduce Motion on physical hardware were not separately exercised. No third-party route backend or calendar export was sent during verification. Saved forecasts remain estimates; older plans without hourly records cannot be backfilled by this implementation.

## Screenshots

Screenshots use an isolated simulator with the fictional **Alex · Preview** profile. Weekly numbers come from explicitly synthetic QA fixtures, never from production data. The results screenshot uses a live forecast for the fixture's public location.

- [Home, light](Tests/VisualQA/Screenshots/home-light.png)
- [Home, dark](Tests/VisualQA/Screenshots/home-dark.png)
- [Scheduling results](Tests/VisualQA/Screenshots/results.png)
- [Schedule](Tests/VisualQA/Screenshots/schedule.png)
- [Calendar, larger text](Tests/VisualQA/Screenshots/calendar-large-text.png)
- [Profile privacy note](Tests/VisualQA/Screenshots/profile-privacy.png)
- [Privacy, larger text](Tests/VisualQA/Screenshots/privacy-large-text.png)
- [Weekly details, largest text](Tests/VisualQA/Screenshots/weekly-accessibility.png)

To generate repeatable synthetic data into a scratch directory, run `python3 Tests/VisualQA/make_fixtures.py /tmp/resilio-visual-fixtures`. Copy those files only into a dedicated QA simulator's Application Support directory. The generator does not modify app data or production services.
