# Resilio integration status

## Available now

- **Apple Maps / MapKit:** autocomplete plus explicit search results and address resolution. Selecting a result stores name, formatted address, coordinates, and location time zone. No map screen or location-coordinate input.
- **Open-Meteo:** live hourly weather and CAMS air-quality forecasts, including provider US AQI. Requests use coordinates, time range, and environmental variable names; no health fields. Unix timestamps avoid daylight-saving ambiguity. A shared actor coalesces requests and caches successful responses for 15 minutes; Home checks about every minute while active. A failed request preserves the last successful Home forecast for that location. Retrieval time is distinct from app check time. The APIs used do not expose a reliable source update timestamp, so that is explicitly unavailable.
- **NYC DOHMH / Queens College street-level PM2.5:** when the planned coordinates fall inside an NYC bounding box, Resilio overlays observed hourly PM2.5 from the nearest NYCCAS monitor onto matching forecast hours. Ozone, heat, and future hours stay on Open-Meteo. A failed monitor fetch does not block analysis. Neighborhood/annual Open Data tables (for example `c3uy-2p5r`) are not used as hourly planner input. Monitor values are preliminary and are not a route ranking.
- **Apple Calendar:** EventKit full-access request only on Connect; reads events for the displayed month and observes store changes. EventKitUI exports an individual plan through Apple's review/save editor. No automatic two-way synchronization. Resilio never edits imported events. Export does not include profile health details. Disconnect stops reading in Resilio; iOS Settings controls system permission.
- **On-device assistant:** a local plan parser preserves the baseline functionality and supports multiple explicit dates/times/durations. Ambiguous AM/PM and missing fields are called out. The result enters the same Schedule → exposure engine → results flow. It is labeled as a local fallback, not a hosted AI connection.

## Setup required

### Account authentication and hosted AI

No authentication backend, account credentials, or hosted AI credentials were supplied or present in the baseline. The app uses honest local-device entry. `AccountAuthenticating` and `PlanAssisting` define replacement boundaries. Do not put server secrets in the iOS bundle. A hosted implementation needs an authenticated backend and clear data disclosures. Send only necessary request context, not entire health profiles.

### LiveKit voice planner

Text Plan with AI works on-device. Voice is **Setup required** until you deploy the worker in `VoiceAgent/` and set a non-secret `RESILIO_VOICE_ENDPOINT` Info.plist string (HTTPS, or http://127.0.0.1 for local testing).

The iOS client requests a short-lived room token from that endpoint, joins a LiveKit room, and registers RPC methods. The Python agent only talks and calls those methods. `PlanningAgent` still searches places, fetches forecasts, scores exposure, builds guidance, and saves events on the device. Snapshots sent back to the agent include spoken replies, missing slots, place names, and computed PM2.5/heat summaries. They never include medical conditions, medications, age, or home ZIP.

```
cd VoiceAgent
cp .env.example .env   # add LIVEKIT_URL, LIVEKIT_API_KEY, LIVEKIT_API_SECRET, OPENAI_API_KEY
python3 -m pip install -r requirements.txt
python3 token_server.py          # POST /token → { url, token, room }
python3 agent.py dev             # LiveKit worker named resilio-planner
```

Point `RESILIO_VOICE_ENDPOINT` at `https://your-host/token`. LiveKit and OpenAI keys stay in `.env`. This path has not been live-tested because no LiveKit project was supplied.

### Google Maps / Routes

Google credentials and a backend are absent. Apple Maps remains the working address provider. Routes show **Setup required** and do not block event analysis.

`GoogleRoutesService` is an HTTPS client adapter, **not a deployed Google backend**. To enable it, deploy a backend using Google's Routes API and configure a non-secret `RESILIO_ROUTES_ENDPOINT` Info.plist string. The backend must enforce its own authentication/rate limits, keep Google credentials server-side, and follow Google attribution and route-display requirements before production use. The adapter and configured route UI have not been live-tested because no endpoint was supplied.

Request: POST JSON with `origin` and `destination` as ActivityLocation objects, plus `mode` (`walking`, `cycling`, `driving`). The backend maps modes to `WALK`, `BICYCLE`, `DRIVE`, calls Google `directions/v2:computeRoutes`, and returns a JSON array of RouteOption objects:

```json
[{
  "id": "F5C78871-96B8-438C-83C2-D2886E453C5A",
  "name": "Route 1",
  "durationMinutes": 18,
  "distanceMeters": 1400,
  "encodedPolyline": "GOOGLE_ENCODED_POLYLINE",
  "mode": "walking",
  "environmentalComparisonAvailable": false
}]
```

The values above illustrate the wire contract only; the app has no sample route results. Optional origin/destination are assigned from the user's selected places. Google returns time and geometry. The current forecast grid cannot support block-level exposure claims; the adapter always sets environmentalComparisonAvailable to false. Travel duration does not shorten or alter the activity duration.

### Google Calendar / Microsoft Outlook

Both are labeled **Setup required**. `ExternalCalendarConnecting` is the service boundary; neither OAuth flow nor sync has been implemented. Each requires its provider application registration, redirect URI, appropriate calendar scopes, Keychain-backed token storage, refresh/revocation handling, and backend support where needed. Do not describe these as connected until their complete implementations are tested. Calendars already present in the device's Apple Calendar can be read through EventKit with the user's permission, and remain attributed to their device calendar name.

## Sources

- [Open-Meteo Air Quality API](https://open-meteo.com/en/docs/air-quality-api)
- [NYC DOHMH real-time PM2.5](https://a816-dohbesp.nyc.gov/IndicatorPublic/data-features/realtime-air-quality/)
- [nychealth/nyccas-data](https://github.com/nychealth/nyccas-data)
- [Google Routes API](https://developers.google.com/maps/documentation/routes/compute_route_directions)
- [Apple EventKit access](https://developer.apple.com/documentation/EventKit/accessing-the-event-store)
- [LiveKit Agents tools / frontend RPC](https://docs.livekit.io/agents/logic/tools/forwarding/)

Open-Meteo's public endpoint usage and licensing should be reviewed for the intended production deployment. No commercial service configuration is included in this repository.
