# TrailApp — Agent Handover

You are the local implementer and builder for TrailApp on this Mac. K (the
architect, in the Muse app) owns design, roadmap, and review; J owns the
devices and final verification. Read this file fully before touching code.

## What TrailApp is

Native iOS 17+ / watchOS 10+ hiking navigation: import a GPX → send to Apple
Watch → navigate fully offline with voice prompts at decision points, HR/distance
over the map. Komoot-class turn accuracy aimed at Apple Watch Ultra owners.
XcodeGen project (Team M6ZPV2R8F8, bundle com.example.trailapp). Public repo.

## Source of truth — read before any task

- `docs/DESIGN-V1-V3.md` — the full product design. Locked decisions live here.
- `docs/BUILD-TEST-GUIDE.md` — per-task build plan, test protocols, definitions of done.
- `docs/reference-alpine-muse.webp` — the locked visual direction.
- `BUILD_NOTES.md` — SDK API checks (re-verify against the installed Xcode's SDKs).

## Locked decisions — do not redesign these

- **Look:** Alpine Minimal in Muse colors — light/off-white surfaces, minimal
  layout, Muse electric-blue accent, subtle teal→magenta iridescent touches
  (route line, Start button, key stats). Sunlight readability first.
- **UX bar:** every primary task reachable in ≤2 taps; sensible defaults;
  if it needs explaining, it's designed wrong.
- **Voice:** fires ONLY for (a) one prompt 50 m before each decision point
  ("In 50 meters, turn left at the fork"), and (b) per-kilometre notifications.
  Nothing else. Distinct haptic per cue type/direction.
- **Cues:** from OSM junction cross-reference at GPX-import time (Overpass);
  named GPX waypoints outrank junctions; bend detection is fallback ONLY.
  (Today's bend engine produces ~44 noisy cues incl. phantom U-turns on the
  HK50 route — that is the known bug the junction importer fixes.)
- **Offline:** navigation core (GPS → cues → voice/haptics) works fully
  offline. Map backdrop offline comes via vector corridor packs (Drop 2).
  "Send to Watch" is explicit per route; "Saved offline" shows only after
  the watch acknowledges receipt. No auto-sync-everything.
- **Scope cuts:** NO live location sharing, NO Strava sync, NO coaching or
  prescriptions — V3 presents captured data (HR zones, recovery, sleep,
  training load) without "you should" language.
- **HealthKit:** the watch records workouts. Do NOT re-add the iOS HealthKit
  entitlement until T1.7 — it requires enabling the capability on the App ID
  first, otherwise automatic signing fails (profile error). Watch target
  already has it. Manual max-HR is set in iPhone Settings and drives watch
  HR-zone colors.
- Persisted models carry a `schemaVersion`.

## Working rules (this Mac)

- Work ONLY in `~/Trailapp`. Never build from copies under `~/Documents/Codex`
  (a stale Oct-1 copy cost hours of false errors).
- Loop per task: `git pull` → `xcodegen generate` → build. Regeneration is
  MANDATORY after pull (new .swift files are invisible to Xcode until then).
- Build: `xcodebuild -project TrailApp.xcodeproj -scheme TrailApp -destination 'platform=iOS,id=00008150-0011248C2130401C' build`
  Default DerivedData. NEVER override the build-products directory (causes
  "Multiple commands produce" for the watch app).
- Keep `git status` clean. One task = one local commit with a clear message.
  Do NOT push — K/J handle pushes and review.
- New files under `Shared/` must compile for BOTH iOS and watchOS
  (Foundation + CoreLocation only).
- After each task report: files changed, build result (SUCCESS or the full
  error verbatim), and what J should check on the devices.

## Current state (2026-10-02, commit 9a12c96)

Verified on J's iPhone + Watch Ultra 3: sample routes, free hike, watch route
preview + manual screen lock, T1.1 import polish (duplicate names get " 2",
file-named errors, import lands on route detail), T1.2 Naismith estimate
(Est. time on detail; ascent shows "—" when the GPX has no elevation).
SDK-modernization fixes are in main (HKWorkoutSession sync APIs,
`startActivity(with:)`/`end()`, throwing `liveUpdates`, @MainActor HR
callbacks, single-target watch app, SampleRoutes folder reference).
Test route: `SampleRoutes/HK50-Hong-Kong-Island-24kmBYAAE.gpx` (24.9 km,
267 m ↑ — rescued from stash, untracked; don't bundle without asking).

## Remaining Drop 1 work (details in BUILD-TEST-GUIDE.md)

- **T1.3** — three-page watch hike pager: Map / Stats / Cues (replaces today's
  5-tab layout; the Controls tab goes away, controls move into T1.4).
- **T1.4** — pause/resume/end behind a deliberate protected overlay (design
  doc §3.2); remove the permanent pause/stop buttons from the map.
- **T1.5** — remaining distance on the map + recenter.
- **T1.6** — HealthKit save hardening (end → save → Summary state machine,
  discard path, no silent data loss).
- **T1.7** — iPhone activity history + review (flag first: needs the iOS
  HealthKit entitlement + App ID capability).
- **T1.8** — free-hike verification pass (field protocol in the guide).
- **T1.9** — iPhone 4-tab bar, Settings (incl. manual max HR), onboarding /
  permissions, empty states.
- **T1.10** — watch preview readiness line (GPS / HR / battery / offline).

Then: Drop 2 (OSM junction cue engine, vector offline packs, real off-route),
Drop 3 = V2 (Ultra features: Action Button, Backtrack, night mode, check-in),
Drop 4 = V3 (data presentation only).

## How we work together

Implementation briefs come from K (via J) — one task at a time, with behavior
and acceptance checks. Implement the brief exactly; don't freelance design.
If a brief conflicts with a locked decision above or the spec is ambiguous,
STOP and ask instead of inventing. K reviews every diff before it ships.

## Always ask first

Signing / entitlements / provisioning changes; bundle ID; pushing to GitHub;
deleting stashes, backups, or any user file; developer-portal changes;
anything irreversible.
