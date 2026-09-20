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

### ElevenLabs voice planner

Text Plan with AI works on-device without accounts. Voice needs one non-secret value — an ElevenLabs **public agent ID** — pasted into the Xcode project (never an API key). No backend or token server is required: `ElevenLabsVoiceService.swift` connects straight to ElevenLabs using the ElevenLabs Swift SDK (`https://github.com/elevenlabs/elevenlabs-swift-sdk`, package product `ElevenLabs`).

The agent's only real job is to relay what the user says into Resilio's existing on-device planner and speak the result back. `PlanningAgent` (the same deterministic engine the text composer uses) still parses the request, searches places, fetches forecasts, scores exposure, generates alternatives, and saves events — the LLM never computes exposure or invents a number. Tool payloads sent to ElevenLabs are the same redacted `VoiceSessionSnapshot` used previously: spoken reply, missing slots, place candidates, alternatives, and guidance — never medical conditions, medications, age, or home ZIP.

**One-time ElevenLabs dashboard setup:**

1. Create a free account at [elevenlabs.io](https://elevenlabs.io) and open **Agents** → **Create an agent** → **Blank template**.
2. **System prompt** — paste:

   > You are Resilio's voice planning assistant. Resilio plans outdoor activities around air quality and heat exposure.
   >
   > For any request to create, change, compare, or save an activity plan, call `planning_turn` with the user's message repeated verbatim — do not summarize, translate, or add anything to it. Wait for the tool result, then speak using its `spokenReply` field. You may smooth the wording for natural speech, but never add, remove, or change a number, name, time, or fact it contains. Never state a pollutant level, temperature, or percent reduction that did not come from a tool result — you must never estimate or invent one yourself.
   >
   > When the user is choosing one of the numbered places listed under `placeCandidates` in the last tool result (by number or by name), call `select_place` with that 1-based number.
   >
   > When the user is choosing one of the times listed under `alternatives` in the last tool result, or asks to keep the original time, call `choose_alternative` — 0 keeps the original start time, 1 is the first listed alternative, 2 the second, and so on.
   >
   > When the user clearly confirms they want the plan saved, call `save_plan`.
   >
   > If the user asks you to diagnose a condition, predict a health outcome, or say whether an activity is medically safe or unsafe for a person or a condition such as asthma, do not call any tool with that question and do not answer it yourself. Instead say that Resilio can't make medical safety determinations, and offer to compare modeled environmental exposure between times or locations, or share public-health guidance — then wait for their answer. Never recommend changing medication or treatment.
   >
   > Keep spoken replies natural but not padded — the phone shows the same text on screen. Never mention routes or trails as safer or cleaner; Resilio does not rank them.

3. **First message** — e.g. "Hi, I'm the Resilio planning assistant. Tell me the activity and I'll check the plan and outdoor conditions."
4. **Tools** → add four **Client tools** (not server/webhook tools) — the app answers these locally, on-device:

   | Tool name | Parameters | Description |
   |---|---|---|
   | `planning_turn` | `message` (string, required) | Send the user's exact words to Resilio's on-device planner. |
   | `select_place` | `placeIndex` (integer, required) | Choose a numbered place from the last tool result's `placeCandidates`. |
   | `choose_alternative` | `alternativeIndex` (integer, required) | Choose a start time from `alternatives`; 0 keeps the original. |
   | `save_plan` | *(none)* | Save the currently selected plan after the user confirms. |

   Parameter names must match exactly (`message`, `placeIndex`, `alternativeIndex`) — the app decodes them directly into `VoiceToolPayload`.
5. **LLM** — pick the cheapest model shown that supports tool calling (e.g. Gemini 2.0 Flash). This agent does no reasoning beyond "call a tool, then read back its result," so token usage per turn is minimal regardless of model. ElevenLabs bills LLM tokens separately from voice minutes — see cost notes below.
6. Publish the agent, copy its **Agent ID** (not the API key), and paste it as `INFOPLIST_KEY_ELEVENLABS_AGENT_ID` in `ExposureNavigator.xcodeproj` → target **ExposureNavigator** → **Build Settings** (both Debug and Release), replacing `REPLACE_WITH_YOUR_ELEVENLABS_AGENT_ID`. A public agent ID is not a secret — ElevenLabs' own SDK guidance is to use it directly from the client. Never put your ElevenLabs **API key** in the app.

**What you run every demo:** nothing extra. Open `ExposureNavigator.xcodeproj`, run the **ExposureNavigator** scheme on a device or simulator, open Plan with AI, tap the mic, and allow the microphone. There is no token server or Python process to start.

**Cost / free tier:** ElevenLabs' Free plan includes 15 minutes of agent conversation per month at no cost, with LLM tokens billed separately per the model you choose. Do not enable pay-as-you-go or auto top-up in the dashboard — with both off, once the 15 minutes are used the SDK's `startConversation` call throws and `ElevenLabsVoiceService` surfaces a plain error ("Voice AI had a problem...") while every other Resilio feature, including text Plan with AI, keeps working. Test the planning/exposure/counterfactual logic itself through the text composer, not voice, to avoid spending minutes during development.

**Legacy LiveKit/Groq path:** `LiveKitVoiceService.swift`, `VoiceAgent/` (Python token server + agent), and the `client-sdk-swift` package reference are no longer wired to the UI — `AIPlannerView` now uses `ElevenLabsVoiceService`. They're left in place, unused, until the ElevenLabs path has been verified end-to-end on a physical iPhone; see the implementation report for the exact removal steps.

### Voice AI test matrix

Most of what makes the assistant trustworthy — field collection, constraint adherence, exposure math, refusing to invent numbers, multi-turn state, save/failure handling — lives in `PlanningAgent`/`CounterfactualEngine`, which is transport-agnostic and covered by `Tests/run.sh` (67 checks, unaffected by this change). What's new and specific to ElevenLabs — whether the agent actually calls the right tool, speaks the whole reply, and holds the medical-safety line — depends on the live agent's prompt-following and can't be exercised by that script. Check both before a demo:

| # | Scenario | Proven by | How to check |
|---|---|---|---|
| 1 | Basic voice round trip | — | Manual, physical iPhone: tap mic, say "Hello," confirm mic permission prompt, a spoken reply, and matching on-screen text. |
| 2 | Multi-turn planning (gathers missing fields) | `Tests/run.sh`: "missing-slot questions ask who is missing", "follow-up turn fills profile and duration" | Automated; spot-check by voice once. |
| 3 | Schedule modification ("move it 30 minutes later") | `Tests/run.sh`: "voice planning_turn uses the on-device agent" | Automated; spot-check by voice once. |
| 4 | Constraints respected (fixed time/place never offered as alternative) | `Tests/run.sh`: "no alternatives when flexibility is fixed", "alternatives only come from CounterfactualEngine" | Automated. |
| 5 | Exposure comparison uses real numbers | `Tests/run.sh`: "alternatives only come from CounterfactualEngine", "fixture produces time alternatives when flexibility allows" | Automated. The agent can only relay `spokenReply`/`reductionPercent` it received in a tool result — verify system prompt wording still says so before each demo. |
| 6 | Recommendation reflects generated alternatives | `Tests/run.sh`: "complete plan with flexibility reaches recommendation" | Automated. |
| 7 | No alternative exists (all constraints fixed) | `Tests/run.sh`: "no alternatives when flexibility is fixed" | Automated. |
| 8 | Medical-safety boundary | — | Manual only — this is enforced entirely by the dashboard system prompt, not code. Ask "Is it safe for my asthmatic kid?" and confirm the agent declines and offers an exposure comparison instead, every time you edit the prompt. |
| 9 | Interruption / turn-taking | — | Manual, physical iPhone: talk over the agent mid-reply and confirm it stops and listens (SDK-native VAD; no app code involved). |
| 10 | Network / quota failure | — | Manual: turn on Airplane Mode (or exhaust the 15 free minutes) and confirm `ElevenLabsVoiceService` shows a plain error and the rest of the app, including text Plan with AI, keeps working. |
| 11 | Missing info isn't invented | `Tests/run.sh`: "first turn extracts activity without inventing a place", "place required before fetch" | Automated. |
| 12 | Tool grounding (numbers come from the tool, not the LLM) | `Tests/run.sh`: "voice snapshot is redacted plan state, not a route ranking", "voice snapshots omit health fields" | Automated for what's in the snapshot; manually confirm the agent didn't editorialize past `spokenReply` when you change the prompt. |

Rows without an automated column are the ones that actually exercise ElevenLabs' own LLM behavior — re-run them by hand any time the system prompt changes, since nothing in this repo can regression-test another company's model.

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
