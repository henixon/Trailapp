# TrailApp

Offline-first GPX hiking navigation for iPhone + Apple Watch. V1 lets you
import a GPX file on iPhone, preview it with an elevation profile, send it to
your Apple Watch, and navigate it fully offline on the watch — with spoken
turn prompts, wrist haptics, and heart rate / distance / elapsed time overlaid
on the map.

## Setup (on your Mac)

1. Install Xcode 16 and XcodeGen:
   ```bash
   brew install xcodegen
   ```
2. Set your Apple Developer Team ID in `project.yml` (replace `YOUR_TEAM_ID`;
   find it at developer.apple.com/account → Membership details, 10 characters).
   Use the same bundle IDs or change `com.example.trailapp` to your own.
3. Generate and open:
   ```bash
   make open        # xcodegen generate + xed .
   ```
4. Select the **TrailApp** scheme, pick your iPhone + paired Apple Watch as
   destinations, and build (⌘R). The watch app is embedded in the iOS app.

## V1 scope

**iPhone**
- Import GPX via the Files picker or "Open in TrailApp" (Files, Safari, AirDrop)
- Route list, route detail with MapKit preview + elevation profile
- Turn-cue computation: named GPX `<rtept>` waypoints preferred, bend
  detection on track geometry as fallback
- "Send to Watch" via WatchConnectivity background file transfer

**Apple Watch**
- Receives route packages offline; stores them locally
- Navigation inside an `HKWorkoutSession`: GPS snap-to-route, along-track
  progress, proximity turn alerts
- Spoken prompts via `AVSpeechSynthesizer` ("Turn right in 50 meters",
  autoplayed) + directional wrist haptics (`.navigationLeftTurn` etc.)
- Heart rate, distance, elapsed time overlaid on the map
- Off-route detection (deviation + consecutive fixes → haptic + voice +
  arrow bearing back to the trail), pause / resume / end

**Deliberately out of v1:** route planning / routing engine (the GPX *is* the
route), elevation service (uses GPX elevation), custom offline tile renderer
(MapKit renders the backdrop; navigation itself is fully offline — see
BUILD_NOTES.md), phone-free watch independence (companion architecture, but
the watch already owns a real navigation engine).

## Architecture

```
iPhone                          WatchConnectivity              Apple Watch
┌──────────────┐   transferFile ┌─────────────────┐   ┌──────────────────┐
│ RouteStore   │ ──────────────▶│ RoutePackage    │──▶│ WatchSessionMgr  │
│ (GPX→Route)  │   route.json   │ route+cues+     │   │ (persist)        │
│ CueEngine    │                │ corridor+policy │   │                  │
│ WatchSyncMgr │                └─────────────────┘   │ NavigationVM     │
└──────────────┘                                     │  ├ WorkoutMgr    │
                                                     │  │  (GPS/HR/clk) │
Shared/ (both targets):                              │  ├ NavEngine     │
 GPXParser, Route/TurnCue/RoutePackage models,       │  ├ VoicePrompter │
 GeoMath, CueEngine, PromptPolicy                    │  └ HapticAnnounc.│
                                                     └──────────────────┘
```

`Shared/` compiles into both targets and is limited to Foundation +
CoreLocation so it builds on iOS and watchOS.

## Offline map packs

`Tools/build-corridor-pack.sh` builds a PMTiles vector-tile pack for a route's
corridor from OpenStreetMap (planetiler + Geofabrik extract). This is the
artifact the future on-watch offline tile renderer will consume. In v1 the
navigation core is fully offline; only the MapKit map *backdrop* needs
network/cache — see BUILD_NOTES.md for the full story.

## Roadmap (post-v1)

- Custom on-watch vector tile renderer (PMTiles) for true offline maps
- Elevation service (AWS Terrain Tiles) for routes without GPX elevation
- Valhalla-based routing engine for on-phone route planning
- Phone-free watch independence (route planning cues precomputed on phone,
  or on-watch routing if the tileset fits)
- Rerouting: rejoin-connector to nearest untraversed route point
- Complications, Live Activities, route sharing
