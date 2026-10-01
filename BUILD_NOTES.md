# BUILD_NOTES — things to verify on the Mac (Xcode 16, iOS 17 / watchOS 10 SDK)

This scaffold was written without a compiler (Linux VM, no Xcode). The logic
is complete and idiomatic, but the following API details should be confirmed
on first build. Fix and delete each line as you verify it.

## Must verify

1. **`CLLocationUpdate.liveUpdates(.fitness)`** (WorkoutManager.swift) —
   confirm the exact signature on the watchOS 10 SDK (parameter type for the
   activity configuration) and that the AsyncSequence is non-throwing.
2. **`HKWorkoutSession` async lifecycle** (WorkoutManager.swift) —
   `try HKWorkoutSession(healthStore:configuration:)`, `try await
   session.start()`, `await session.pause()/resume()/stop()`. If the SDK
   still exposes only the `HKHealthStore.start(_:)` family, adapt.
3. **`CLBackgroundActivitySession()`** — confirm throwing initializer on
   watchOS 10+ and that `invalidate()` exists.
4. **`MapCameraPosition.userLocation(fallback:)`** (NavigationViewModel.swift)
   — confirm the factory name/signature on watchOS 10.
5. **XcodeGen watch embedding** (project.yml) — confirm the generated
   `TrailApp.xcodeproj` contains an "Embed Watch Content" phase from the
   `- target: TrailAppWatch` dependency, and that
   `WKCompanionAppBundleIdentifier` is correct for a companion (non-watch-only)
   app. Adjust `WKApplication`/`WKWatchOnly` keys if Xcode complains.
6. **`UTType(filenameExtension: "gpx")`** (TrailAppApp.swift) — confirm it
   resolves once the exported type declaration is installed; the `.xml`
   fallback covers the simulator edge case.
7. **Swift Charts on iOS 17** (ElevationProfileView.swift) — `Chart`,
   `AreaMark`, `LineMark` need no extra package; confirm import compiles.

## Verify on device (not the simulator)

8. **Spoken prompts during a workout** (VoicePrompter.swift) —
   `AVSpeechSynthesizer` is available on watchOS, but confirm audio actually
   plays while an `HKWorkoutSession` is active, through the watch speaker and
   through paired Bluetooth headphones, and how it interacts with the
   silent-mode switch. An `AVAudioSession` category tweak may be needed.
9. **Haptics while navigating** — `WKInterfaceDevice.play(.navigationLeftTurn
   / .navigationRightTurn / .navigationGenericManeuver)` requires the app to
   be foreground or inside an active workout session; confirm the workout
   session keeps them firing with the wrist down.
10. **Heart-rate delivery** — `HKAnchoredObjectQuery` on `.heartRate` should
    stream during the workout; confirm update frequency is usable (~every few
    seconds) and that authorization prompts appear as expected.
11. **GPS accuracy on trail** — the 40 m off-route threshold and 3-fix streak
    are starting values from road-navigation practice; switchbacks 10–20 m
    apart may need tighter tuning. Tune `PromptPolicy` on real hikes.
12. **Battery** — GPS + display + speech during a full hike; compare against
    the ~10 h (Series) / ~25 h (Ultra, full GPS+HR) figures.

## Known v1 limitations (by design)

13. **Map backdrop offline**: MapKit on watchOS has no public offline tile
    API. The navigation core (GPS fix → snap-to-route → cues → voice/haptics)
    is 100% offline, but the map *tiles behind the route line* need network
    or MapKit tile cache. `Tools/build-corridor-pack.sh` already builds the
    PMTiles corridor pack; the missing piece is an on-watch vector tile
    renderer (the WorkOutDoors approach). That is the single biggest
    post-v1 work item if true offline maps matter on day one.
14. **No on-watch rerouting**: without a routing graph on the watch,
    off-route recovery is bearing-and-distance back to the nearest route
    point. A rejoin-connector needs either phone connectivity or an on-device
    tileset (valhalla-mobile is the candidate).
15. **Bend-detection cue gaps**: pure geometry cues can miss forks/roundabouts
    where the path barely bends. Prefer GPX files with named `<rtept>`
    waypoints; the engine already prefers them when present.
16. **`transferFile` sizes**: route packages are kilobytes and fine. If/when
    tile packs are synced, keep them to low hundreds of MB; there is no
    published per-app watch storage cap, but be conservative.
