# TrailApp — Full Product & Technical Design (V1 → V3)

Date: 2026-10-02. Status: design draft for review, not yet approved.
Goal: the go-to app for Apple Watch Ultra owners.

## 1. Design principles (locked)

- **Aesthetic: Alpine Minimal in Muse colors** (locked 2026-10-02). Clean light theme, off-white surfaces, generous whitespace, Swiss-minimal Apple-native layout; single accent = Muse electric blue with subtle iridescent teal→magenta gradient touches (Start button, route line, key stats). Best sunlight readability of the three directions explored; Night Ops reserved for the red night mode.
- **Eyes for confidence, voice for decisions.** The map + position dot keep you confident; voice fires only for (a) pre-branch decision prompts and (b) per-km notifications. Nothing else.
- **One branch prompt, at 50 m.** Wording: "In 50 meters, turn left at the fork." (distance + action + landmark).
- **Distinct haptic per cue type.** Direction and cue type are distinguishable without looking.
- **Fully offline nav core on the watch.** GPS → map matching → cues → voice → haptics works with zero network. The basemap is the only network-dependent piece, fixed by the offline tile renderer.
- **Deliberate controls.** Pause/resume/end live behind a deliberate overlay, never as permanent on-map buttons. Screen lock for rain/sleeves.
- **V1 stays lean.** GPX in, navigate, record, review. Everything else is V2/V3.
- **No hunting, no learning.** Every primary task is reachable in ≤2 taps from where the user already is. Sensible defaults everywhere; settings exist but should rarely be needed. If a feature needs explaining, it's designed wrong. Clean and beautiful is a requirement, not a polish pass.

## 2. The full user journey

### Phase 1 — Get the route in (iPhone)
Share sheet / Files / AirDrop / download → GPX lands in TrailApp → parse → route detail. Route library holds everything: name, distance, ascent, est. duration, offline-pack status, thumbnail. Rename/delete from the library.

### Phase 2 — Before you start (watch)
Route list → preview (offline map if the pack transferred, else MapKit) → readiness line (GPS lock, HR, battery, "Saved offline" badge) → Start. If the user is far from the trailhead, a **go-to-start** state shows bearing + distance to the start instead of immediately matching the route.

### Phase 3 — During the hike (watch)
Three-page pager: **Map / Stats / Cues**. Map shows the route, position dot, breadcrumb, off-route banner, recenter control, lock. Stats shows HR (zone-colored from the manual max-HR setting), distance, elapsed, ascent, pace. Cues lists upcoming decision points with distances. Pause/resume/end sit behind a deliberate overlay (long-press / force-press style interaction, not a tap target). Voice + haptics fire per the principles above.

### Phase 4 — Finishing (watch)
End → summary flash (distance, time, ascent, avg HR) → Save / Discard → workout saved to HealthKit with route + HR samples → auto-syncs to iPhone.

### Phase 5 — Review later (iPhone)
Activity history list → activity detail: breadcrumb on the map against the planned route, stats (distance, moving vs elapsed, ascent/descent, avg/max HR, pace), elevation profile, HR zone distribution, per-km splits, off-route segments highlighted, planned-vs-actual comparison, notes + rating, export GPX/TCX/FIT.

## 3. App structure

### iPhone (4 tabs)
1. **Routes** — library list → route detail (preview map, stats, elevation profile, est. duration, cue count, offline status, Send to Watch, Delete).
2. **Activities** — history list → activity detail (as in Phase 5).
3. **Health** (V3) — recovery, sleep, training load, readiness.
4. **Settings** — max HR (manual), units, voice on/off, haptic strength, offline storage manager (per-pack size, delete, LRU info), about/attribution.

### Watch
- Route list → Route preview → (go-to-start if needed) → Hike pager (Map / Stats / Cues) → End summary.
- Free Hike: start screen → recording pager → end summary. Navigation and recording are independent (map-only view without recording, as today).
- Settings glance: minimal (voice toggle, lock) — full settings live on iPhone.

## 4. Data model

- **Route**: id, name, source GPX, distance, ascent/descent, est. duration (Naismith), cues[], corridorPackId, offlineStatus (not-started / building / on-phone / on-watch / failed), thumbnail.
- **Cue**: distanceAlongRoute, type (decision / km-marker / summit / hazard), direction, landmark text, voiceText.
- **Activity**: id, routeId (nullable — free hikes have none), startedAt, track[] (lat/lon/time), hrSamples[], stats, notes, rating, healthKitUUID.
- **OfflinePack**: id, routeId, tileBundle (extracted corridor tiles), status, sizeBytes, watchAck.

## 5. Feature inventory by version

### V1 — the complete loop
- GPX import (share sheet, Files, AirDrop) + route library + route detail.
- Watch: route list → preview → go-to-start → 3-page hike pager → protected pause/end → end summary.
- OSM decision-point cue engine (iPhone, at import): junctions where ≥2 ways meet within ~30 m of the track become cues; named GPX waypoints preferred; bend detection demoted to fallback.
- Voice (50 m, decision + per-km only) + distinct haptics.
- Free-hike recording + verified HealthKit save.
- Activity history + activity detail + GPX export.
- Est. duration, distance remaining, recenter.
- Offline vector corridor packs + custom watch renderer + "Saved offline" badge.

### V2 — the Ultra set
- Action Button (start/pause/waypoint via assignable intent).
- Backtrack (reverse guidance along recorded breadcrumb).
- Check-in timer + emergency contact alert.
- GPS accuracy indicator (dual-frequency status).
- Wayfinder/Modular Ultra complications.
- Red night mode.
- Multi-day expedition mode (power-conscious GPS cadence, per-day segments).
- *Live location sharing: cut per J, 2026-10-02.*

### V3 — see how you're doing
No proactive coaching — the user just sees what the captured data says, presented beautifully. No prescriptions, no "you should".
- HR zones + max-HR setting driving zone colors everywhere.
- Health dashboard: HR, HRV, sleep, recovery — trends and current state, plainly shown.
- Training load history (TRIMP-style), simple and visual.
- Zone-colored post-hike route map; time-in-zone breakdown per activity.
- *Proactive/adaptive coaching: cut per J, 2026-10-02.*

## 6. Technical architecture

### 6.1 Tile pipeline (offline maps)
1. On the Mac: `build-corridor-pack.sh` builds a PMTiles vector pack clipped to route bbox + corridor (Planetiler, OSM Geofabrik extract, z12–16, hiking-relevant layers + contours). Packs are published as versioned artifacts (GitHub release assets for now).
2. iPhone: "Download offline map" on route detail fetches the pack, extracts the corridor tiles into a compact tile bundle (this avoids implementing PMTiles range-reads on the watch).
3. Bundle transfers to the watch via WatchConnectivity file transfer, alongside the route package — explicit per-route "Send to Watch"; the watch LRU-evicts old packs.
4. Watch decodes MVT (protobuf) and renders with a **custom Core Graphics renderer** using a hardcoded minimal hiking style: landcover, water, trails/paths, contours, labels. No full style-spec engine in V1. The Map page shows MapKit when online or pack-less, the tile canvas when the pack is present.
5. "Saved offline" badge appears only after the watch acknowledges receipt. LRU eviction when watch storage fills.
6. MapKit remains the online fallback everywhere.

### 6.2 Cue engine
Runs on iPhone at import (network available): Overpass API query for `highway=*` junctions in the route bbox → decision points. Compact cue list syncs to the watch; the watch only does distance-along-route matching at runtime. No routing engine anywhere (GPX is the route).

### 6.3 Watch nav core
CoreLocation → map matching to route → off-route detection (threshold TBD in field testing; recovery = bearing + distance back to route) → cue triggering → AVSpeechSynthesizer + haptics. Workout session (HKWorkoutSession) wraps the whole hike for HR + HealthKit.

### 6.4 Sync & storage
WatchConnectivity for route packages, tile bundles, and completed activities (watch → iPhone). iPhone is the system of record (JSON files in Documents — the established pattern; every model carries a `schemaVersion` for cross-drop migration). HealthKit is the workout system of record for health data.

## 7. Risk & showstopper analysis

**Verdict: no hard showstoppers.** Everything listed is buildable with public APIs. Ranked risks:

1. **Custom vector renderer performance on watch** (highest effort + risk). MVT decode + label placement on a watch CPU. Mitigations: pre-simplified tiles, z12–16 only, in-memory tile cache, simple label de-dup (no full collision engine in V1), contours baked into tiles. WorkOutDoors (single dev) proves it can be done.
2. **Voice reliability during workouts on watchOS.** AVSpeechSynthesizer inside an active HKWorkoutSession needs device verification — behavior here is the unknown, not the API. Mitigation: verify in Drop 1; fallback is haptics + visual if voice misbehaves.
3. **Background execution limits** (V2 check-in timer). watchOS restricts background runtime; design around extended runtime sessions and the iPhone companion where possible. (Live sharing was cut, which removes the hardest background-networking case.)
4. **V3 data honesty.** No coaching means no sports-science claims to defend — but the presented data must still be correct and clearly labeled. This is a data-quality bar, not a coaching risk.
5. **Watch storage.** Corridor packs are small (a few MB per route), but cap stored packs with LRU eviction and surface sizes in Settings.

## 8. Build plan — one design, integration drops

Not one big-bang commit: several device-verified milestones de-risk each other, because voice, HR, GPS, and HealthKit can only be validated on J's physical iPhone + Ultra.

- **Drop 1 — Foundation.** GPX import, route library + detail, watch 3-page pager with protected pause/end, est. duration, remaining distance + recenter, HealthKit save, basic activity history + detail, GPX export. *Verify on device: voice during workout, HR streaming, HealthKit save.*
- **Drop 2 — Navigation.** OSM decision-point cues, go-to-start, offline vector renderer + pack transfer + "Saved offline", voice/haptic polish, HR zone colors on watch.
- **Drop 3 — V2 Ultra set.** Action Button, backtrack, check-in timer, GPS accuracy, complications, night mode, expedition mode.
- **Drop 4 — V3 Health, beautifully presented.** Health dashboard, recovery/sleep, training load history. Data only — no coaching.

Each drop: pushed to `henixon/Trailapp`, J pulls + builds + field-tests before the next begins.

## 9. Decisions (resolved with J, 2026-10-02)
1. Live location sharing: **cut.**
2. Strava sync: **cut.**
3. Proactive/adaptive coaching: **cut.** V3 is data presentation only — the user sees how he's doing from captured data.
4. Design bar: **clean, beautiful, zero learning curve.** Every primary task ≤2 taps; sensible defaults; if it needs explaining, it's designed wrong.
