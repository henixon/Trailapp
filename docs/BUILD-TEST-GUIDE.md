# TrailApp — Build & Test Guide

Covers the full arc: Drop 1 (Foundation) → Drop 2 (Navigation) → Drop 3 (V2 Ultra) → Drop 4 (V3 Health).
Companion to `trailapp-full-design-v1-v3.md` (the *what*); this is the *how* and *how we verify*.

## 0. How we work

| Role | Does |
|---|---|
| K (me) | Writes code, pushes to `henixon/Trailapp` `main`, writes/updates this guide. Cannot compile (Linux VM, no Xcode) and cannot drive J's Mac (broken control channel). |
| J | Pulls, runs `xcodegen generate` when files are added, builds in Xcode, installs on physical iPhone + Apple Watch Ultra 3, runs every device/field test in this guide, reports results. |

**The loop:** K pushes → J pulls + builds → J tests → J reports pass/fail with details → K fixes → repeat. Nothing is "done" until it passes on the physical devices.

### Mac commands (J's side)

```bash
cd ~/Trailapp
git pull
git status            # must be clean before building
xcodegen generate     # required whenever Swift files were added/renamed
```

Then in Xcode: select the physical iPhone as the run destination, `⌘R`. The watch app installs automatically as the companion.

**Rules:**
- Never build on a dirty worktree. Stash or commit local changes first.
- If `git pull` fails on a modified `project.yml`, resolve (stash → pull → pop) and re-run `xcodegen generate`.
- Simulator is fine for UI layout; **all behavior tests run on physical devices** (§7).

## 1. Architecture map

```
TrailApp (iOS)                Shared (framework)              TrailAppWatch (watchOS)
─────────────                 ──────────────────              ───────────────────────
RouteStore ──import──▶ GPXParser          RoutePackage ──WCSession──▶ WatchSessionManager
WatchSyncManager ──transferFile──▶ Route, TurnCue, GeoMath          NavigationEngine ◀── GPS ── WorkoutManager
RouteList/DetailView           CueEngine, PromptPolicy              (snap-to-route, cues, off-route)
ElevationProfileView                                               VoicePrompter, HapticAnnouncer
(ActivityStore — Drop 1)                                           NavigationViewModel
                                                                   Views: Content/Preview/Map/Stats/Cues
```

**Data flow (navigation):** iPhone builds `RoutePackage` (route + cues + policy) → `transferFile` → watch receives → `NavigationEngine.start(package)` → GPS fixes from `WorkoutManager` → `process(location:)` → callbacks (`onSpeak`, `onHapticTurn`, …) → `NavigationViewModel` → UI + `VoicePrompter`/`HapticAnnouncer`.

**Data flow (activities, Drop 1):** watch records track + HR during hike → on save, `Activity` package transfers to iPhone → `ActivityStore` persists → history/detail UI.

**Key files today:** `Shared/Models/{Route,TurnCue,RoutePackage}.swift`, `Shared/Parsing/GPXParser.swift`, `Shared/Navigation/{CueEngine,PromptPolicy}.swift`, `Shared/Geo/GeoMath.swift`, `TrailApp/{RouteStore,WatchSyncManager}.swift`, `TrailAppWatch/{NavigationEngine,NavigationViewModel,WorkoutManager,VoicePrompter,HapticAnnouncer,WatchSessionManager}.swift`.

**Already verified:** scaffold compiles; route send iPhone→watch works; preview + manual screen lock added (commit `e1cabd7`, not yet device-tested).

---

## 2. Drop 1 — Foundation

**Goal:** the complete loop works end to end: import → preview → hike → save → review.

### Build tasks

**T1.1 GPX import UI (iPhone)** — `onOpenURL` import plumbing already exists in `TrailAppApp.swift`; add the UI around it: document picker (Files), duplicate-name handling ("… 2" suffix, never a silent duplicate), parse-failure errors naming the file and the reason, and a post-import landing on the new route's detail screen. Edge: GPX without `<ele>` tags → ascent shows "—", never a false 0. Files: `TrailApp/Views/ImportView.swift` (new), `TrailApp/RouteStore.swift` (extend).

**T1.2 Route detail completeness** — add estimated duration (Naismith: 12 min/km + 10 min/100 m ascent, shown as a range), offline-pack status row (placeholder until Drop 2), cue count. Files: `TrailApp/Views/RouteDetailView.swift`.

**T1.3 Watch hike pager** — replace single map screen with 3 pages: **Map / Stats / Cues** (`TabView`, `.tabViewStyle(.page)`). Map: route polyline, position dot, breadcrumb, off-route banner, recenter button, lock button. Stats: HR (large, zone-gray until Drop 2), distance, elapsed, ascent, pace. Cues: upcoming decision points with remaining distances. Files: `TrailAppWatch/Views/HikePagerView.swift` (new), `MapPageView.swift`, `StatsPageView.swift`, `CuesPageView.swift` (new).

**T1.4 Protected pause/end** — remove pause/stop from the map surface. Pause/resume/end live behind a deliberate overlay: long-press (≥0.8 s) on a small "•••" control opens it; End requires a second confirm. Same treatment in `FreeHikeView`. Files: `TrailAppWatch/Views/HikeControlsOverlay.swift` (new), `NavigationView.swift`, `FreeHikeView.swift`.

**T1.5 Remaining distance + recenter** — `NavigationEngine` already publishes `distanceRemaining`; surface it on the Map page; recenter snaps the map camera back to the user. Files: `NavigationViewModel.swift`, `MapPageView.swift`.

**T1.6 HealthKit save (verify + harden)** — audit `WorkoutManager`: end-of-workout builds `HKWorkout` with route (`HKWorkoutRouteBuilder`) + HR samples, saves to HealthKit, returns the UUID. Handle: save failure (surface "not saved" state, keep local copy), user denies HealthKit auth (degraded mode, local-only). Files: `TrailAppWatch/WorkoutManager.swift`.

**T1.7 Activity sync + history (iPhone)** — new `ActivityStore` (JSON in Documents/Activities, same pattern as `RouteStore`); every persisted model (Route, Activity, cues) carries a `schemaVersion` field so Drops 2–4 can migrate old JSON. Watch→iPhone transfer of the finished `Activity` via `WCSession.transferFile` with a retry queue on both sides (a failed transfer must never lose the activity); history list (date, name, distance, time) + detail (track on map vs planned route, stats, elevation profile, per-km splits, notes field, rating). Files: `Shared/Models/Activity.swift` (new), `TrailApp/ActivityStore.swift` (new), `TrailApp/Views/{ActivityListView,ActivityDetailView}.swift` (new), `WatchSyncManager.swift`, `WatchSessionManager.swift`.

**T1.8 GPX export** — from activity detail: share sheet with the recorded track as `.gpx`. File: `Shared/Parsing/GPXExporter.swift` (new).

**T1.9 App structure: tabs, settings, onboarding** — the iPhone app is currently a single `RouteListView`; introduce the tab bar: **Routes / Activities / Settings** (Health tab arrives in Drop 4). Settings: max HR (manual entry — required by T2.5/T4.4), units, voice on/off, haptic strength, offline storage manager (per-pack sizes, delete). Onboarding (first launch only): location → HealthKit → motion permission flow with plain-language reasons; empty states for Routes ("Import your first GPX…") and Activities. Files: `TrailApp/Views/{SettingsView,OnboardingView}.swift` (new), `TrailAppApp.swift` (TabView).

**T1.10 Watch preview readiness line** — the design promises a readiness line on the route preview: GPS lock state, HR signal, watch battery, and offline-pack status ("Saved offline" badge wired to the real pack state in Drop 2; "Online maps" until then). This blocks the most common field failure — starting a hike with no GPS lock. Files: `TrailAppWatch/Views/RoutePreviewView.swift`, `WorkoutManager.swift` (expose fix quality).

### Drop 1 tests

**Simulator (Mac):**
| # | Test | Expect |
|---|------|--------|
| S1 | Import the two sample GPX + a downloaded GPX via Files | Route appears in library with correct name/distance/ascent |
| S2 | Import a corrupt GPX (truncated XML) | Clear error naming the file; app doesn't crash; library unchanged |
| S3 | Import the same GPX twice | Second import renamed ("… 2") or rejected with a clear message — no silent duplicate |
| S4 | Route detail | Est. duration shown as range; elevation profile renders |
| S5 | Simulate hike (GPX playback via Xcode location simulation) | Pager swipes Map/Stats/Cues; pause/end only via long-press overlay |
| S6 | End hike → activity appears on iPhone history | Track, stats, map all present; GPX export opens share sheet |

**Device (J — field protocol F1, "the parking-lot loop"):**
1. Walk a ~1 km loop you know, with the phone in your pocket and the watch on wrist.
2. Before starting: confirm GPS lock indicator and HR reading on the preview screen.
3. During: at one point, deliberately walk 60 m off the loop. **Expect:** off-route banner + voice "Off route…" within ~30 s; walk back → "Back on route."
4. Long-press "•••" → pause → resume → end → confirm → summary flash shows.
5. iPhone: activity appears in history within 1 min, track matches the loop, HealthKit (Health app → Workouts) shows the workout with HR.
6. Play a podcast/music during the hike. **Expect:** voice prompts duck (not kill) audio; report what actually happens.

**Pass criteria:** all S1–S6 + F1 green; no crash; no data loss (activity always recoverable on iPhone even if HealthKit save fails).

---

## 3. Drop 2 — Navigation

**Goal:** cues you can trust + a map that works with zero bars.

### Build tasks

**T2.1 OSM decision-point importer (iPhone)** — at import time (the iPhone has network here): query the **Overpass API** for `highway=*` ways + nodes inside the route bbox, find nodes shared by ≥2 ways within 30 m of the track → decision-point cues with landmark text from OSM tags (`name`, `natural=peak`, `tourism=*`). Named GPX waypoints still win; bend detection stays as last-resort fallback; if Overpass fails or rate-limits, the import still succeeds with bend cues and a "basic cues" badge. (Deliberately not bundling a PBF parser + 100 MB extract on the phone.) Works worldwide, not just Hong Kong. Files: `Shared/Navigation/OSMJunctionImporter.swift` (new), `CueEngine.swift` (integrate), `RouteStore.swift` (run at import, show "analyzing trail…" progress).

**T2.2 Cue policy enforcement** — single 50 m voice prompt per decision cue ("In 50 meters, turn left at the fork."); per-km distance notifications; distinct haptic per direction/type. Remove the old long/short/imminent triple-announce in `NavigationEngine.fireBands` or re-map bands to the new policy. Files: `NavigationEngine.swift`, `PromptPolicy.swift`, `VoicePrompter.swift`, `HapticAnnouncer.swift`.

**T2.3 Go-to-start** — if distance to route start > 300 m at Start: show bearing + distance to start ("Trailhead 2.3 km ↗"); transition to normal navigation automatically when within 300 m. Files: `TrailAppWatch/Views/GoToStartView.swift` (new), `NavigationViewModel.swift`.

**T2.4 Offline tile pipeline** — pack *building* runs on the Mac: `Tools/build-corridor-pack.sh` already does this (Planetiler needs Java and cannot run on iOS — this was misstated in an earlier draft). Flow: (a) J builds a corridor `.pmtiles` per route on his Mac (one command, documented in README); packs are published as versioned artifacts (GitHub release assets for now). (b) iPhone: "Download offline map" on route detail fetches the pack and extracts the corridor tiles into a compact bundle. (c) The bundle transfers to the watch via `transferFile` alongside the route package. Sync is explicit per-route ("Send to Watch") — no auto-sync-everything, packs are megabytes; the watch LRU-evicts old packs and the iPhone can "Remove from Watch". (d) Watch: `MVTTileDecoder` (protobuf → geometry, via SwiftProtobuf SPM) + `VectorTileRenderer` (Core Graphics, hardcoded hiking style: landcover, water, trails, contours, labels) + tile cache. The Map page renders **MapKit when online or when no pack exists, and the custom tile canvas when an offline pack is present** — identical overlays (route line, position dot, breadcrumb) in both modes. (e) "Saved offline" badge on the watch preview + iPhone detail, shown only after the watch ACKs receipt. Files: `TrailApp/OfflinePackManager.swift` (new), `TrailAppWatch/Map/{MVTTileDecoder,VectorTileRenderer,OfflineMapView,TileCache}.swift` (new), `MapPageView.swift` (dual-mode).

**T2.5 HR zone colors (watch)** — max HR from iPhone settings → 5-zone colors on the Stats page HR + (Drop 4) zone-colored track.

### Drop 2 tests

**Simulator:**
| # | Test | Expect |
|---|------|--------|
| S7 | Import HK50 test GPX (24.88 km, no named waypoints) | Cue count roughly 5–15, and every cue corresponds to a real fork visible on OSM; zero phantom U-turns. (Old engine: 42.) |
| S8 | Import a GPX *with* named waypoints | Named cues used verbatim; no duplicates with OSM cues |
| S9 | Build corridor pack for a 25 km route | `.pmtiles` < 15 MB; bundle extracts; watch renderer draws land/water/trails/contours at z12–16 |
| S10 | Airplane mode on watch simulator | Map renders fully from the bundle; no blank tiles |

**Device (J — field protocol F2, "the real trail"):**
1. Hike a trail with known forks (record which forks you take).
2. **Expect:** exactly one voice prompt per fork at ~50 m, wording "In 50 meters, turn … at the fork"; per-km notifications ("3 kilometers, 45 minutes"); nothing else spoken.
3. **Expect:** haptic pattern differs between left/right/straight/km-marker — eyes closed, you can tell them apart.
4. Phone in airplane mode (watch on wrist, no phone connection): map renders, position dot tracks, cues fire. This is the offline proof.
5. Start 2 km from a trailhead: go-to-start screen shows bearing/distance; navigation engages on arrival.
6. Report: cue count vs actual forks, any phantom prompts, renderer frame rate (any stutter while panning?), battery % per hour.

**Pass criteria:** cue list matches reality (no phantom turns); offline map fully functional in airplane mode; voice/haptics per policy; battery drain acceptable for a day hike.

---

## 4. Drop 3 — V2 Ultra set

**Goal:** the watch earns its "Ultra" name. (Live sharing cut per J — no backend work.)

### Build tasks

**T3.1 Action Button** — assignable App Intent: start/pause/resume/waypoint. Files: `TrailAppWatch/Intents/` (new).

**T3.2 Backtrack** — reverse guidance along the recorded breadcrumb: "Backtrack" action from the controls overlay; engine follows the breadcrumb backwards with bearing + distance to start. Files: `NavigationEngine.swift` (backtrack mode), UI affordance.

**T3.3 Check-in timer + emergency contact** — timer set at hike start (iPhone). If no check-in and no movement: escalating loud alerts on watch + iPhone. Final escalation is a **one-tap SOS**: a pre-drafted message (location, route, battery) in a compose sheet the user confirms — iOS does not allow silent automatic SMS, so the design is "impossible to ignore, one tap to send", not auto-send. Built for watchOS background limits (extended runtime session). Files: new.

**T3.4 GPS accuracy indicator** — show fix quality (dual-frequency lock state, horizontal accuracy) on the Map page; warn when accuracy degrades. Small UI, uses existing `CLLocation` data.

**T3.5 Complications** — Wayfinder + Modular Ultra: current hike status (distance/time or next cue). WidgetKit. Files: `TrailAppWatch/Complications/` (new).

**T3.6 Red night mode** — full-red UI variant, toggle in controls overlay + auto after sunset. Files: theme support in watch views.

**T3.7 Expedition mode** — multi-day: per-day segments in one activity, power-conscious GPS cadence option, overnight pause that preserves the track.

### Drop 3 tests
- Simulator: intent fires; complication renders in gallery; night mode recolors every page; backtrack reverses along a simulated breadcrumb.
- Device (F3): Action Button starts/pauses a real hike; backtrack guides you to your start point on an unfamiliar loop; check-in timer escalates correctly (test with a short 10-min timer); night mode is actually usable in the dark (no white flashes — check every sheet/alert).

---

## 5. Drop 4 — V3 Health, beautifully presented

**Goal:** see how you're doing from captured data. No coaching, no prescriptions. (Strava sync cut per J.)

### Build tasks

**T4.1 Health tab (iPhone)** — trends: resting HR, HRV, sleep duration/quality, all from HealthKit queries. Plain charts, plain language.

**T4.2 Training load** — TRIMP-style load per activity + 7/28-day trend chart. Visual only.

**T4.3 Zone-colored history** — activity detail: track colored by HR zone, time-in-zone stacked bar.

**T4.4 Settings: max HR** — manual entry (already decided); drives all zone colors on watch + iPhone.

### Drop 4 tests
- Simulator: Health tab renders with HealthKit sample data; zones consistent between watch Stats page and iPhone detail.
- Device (F4): after 3+ recorded hikes, trends look sane; zone colors match perceived effort; max-HR change re-colors history correctly.

---

## 6. Cross-cutting test rules (all drops)

1. **Every drop ends with a field test on the physical Ultra.** Simulator green ≠ done.
2. **Report template** (paste into chat after each field test): route, distance, duration, what you expected, what happened, battery start/end, any crash/log excerpt.
3. **No silent data loss, ever.** An activity must survive: app kill mid-hike, watch reboot, failed HealthKit save, failed transfer (retry queue on both sides).
4. **Permissions matrix** (test once per fresh install): deny location → clear guidance to Settings; deny HealthKit → local-only mode with a banner; deny motion → still works, note the gap.
5. **Upgrade test:** install new drop over the previous one; routes, activities, and settings survive.
6. **Performance budgets:** watch UI 60 fps while panning the offline map; tile decode < 100 ms per tile on Ultra; app launch < 2 s on watch.

## 7. Debugging

- **SDK drift:** BUILD_NOTES.md was written against Xcode 16 / watchOS 10 SDKs; J's Mac runs macOS 26.4.1 (Xcode 26-era SDKs). Re-verify every API check in BUILD_NOTES against the installed SDK before trusting it — signatures (e.g. `CLLocationUpdate.liveUpdates`, the `HKWorkoutSession` lifecycle) may have changed since those notes were written.
- **Watch logs:** Xcode → Devices → Apple Watch → Console; or Console.app with the watch paired. Use `os_log` with subsystem `app.trailapp` in new code.
- **Common failures:**
  - Watch doesn't receive route → check `WCSession.isReachable` / `isPaired`; `transferFile` completes only when the watch is reachable — queue and retry.
  - Voice silent during workout → check `AVAudioSession` category; test with silent switch on/off and with/without Bluetooth headphones (BUILD_NOTES #8).
  - Haptics not firing wrist-down → confirm workout session is active; haptics require foreground *or* active session (BUILD_NOTES #9).
  - HR flatlines → re-check HealthKit authorization; `HKAnchoredObjectQuery` update handler must be retained.
  - Tile pack too big → reduce zoom range or corridor width; check `TileCache` eviction logs.
- **Git hygiene:** one PR-worthy commit per task (T1.1, T1.2, …); commit messages start with the task id. Never force-push `main`.

## 8. Definition of done (per drop)

**Version → drop mapping: V1 = Drop 1 + Drop 2. V2 = Drop 3. V3 = Drop 4.**

- [ ] Compiles clean on J's Mac (zero warnings introduced).
- [ ] Installs on physical iPhone + Ultra.
- [ ] All simulator tests for the drop pass.
- [ ] Field protocol for the drop passes with a written report.
- [ ] BUILD_NOTES.md updated (verified lines deleted, new unknowns added).
- [ ] Pushed to `henixon/Trailapp` `main`; J confirms pull + build.
