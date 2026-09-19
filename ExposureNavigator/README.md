# Exposure Navigator — iOS SwiftUI

Open `ExposureNavigator.xcodeproj` in Xcode 16+, select an iOS 17+ simulator, and Run.

## What works
- Four-tab, local-first app: Home, Schedule, Calendar, Profile.
- First-run consent flow with optional location and optional-health-data explanation.
- Multiple profiles, active-profile switching, editable free-text tag fields, and local storage.
- Exact place/address suggestions and geocoding through Apple's MapKit search.
- Open-Meteo weather and air-quality forecasts, cached for five minutes while the UI checks each minute.
- Existing time-weighted exposure engine and data-coverage checks.
- Up to five feasible time alternatives; duration stays fixed.
- Event save, Home/Calendar propagation, selected-event navigation, and re-analysis.
- Apple Calendar permission is requested only when Connect is tapped.
- A local plan parser prefills the shared Schedule flow; it does not provide medical recommendations.

## Configuration status
- Google Maps/Routes: not configured. Address search currently uses MapKit. No route exposure claims are made.
- Google Calendar and Microsoft Outlook: integration points are shown as Setup required; no OAuth is faked.
- Apple Calendar: permission request works. Import/export is not implemented yet.
- Account authentication and hosted AI: not configured. Data remains on device; the plan assistant uses local extraction only.

Environmental APIs receive coordinates and time only. Health information is never sent to them.
