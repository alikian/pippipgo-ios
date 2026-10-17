# Full Test

Reusable, on-demand Appium regression test for the installed PipPipGo iPhone app.
Ask **“Run the Full Test”** to execute it. Nothing is scheduled or connected to CI.
Creating this runner did not execute it on the phone; its offline runner checks passed.

## Commands

From the iOS repository:

```sh
python3 scripts/full_test.py setup     # Start local server only
python3 scripts/full_test.py run       # Run requested checks; keep setup/session alive
python3 scripts/full_test.py status
python3 scripts/full_test.py teardown  # Explicit cleanup before rebuilding/reinstalling
```

Use `--device UDID --team TEAM_ID` or `PPG_TEST_DEVICE` / `PPG_TEST_TEAM` for another device/team. Defaults target the existing development iPhone/team. Keep the iPhone unlocked, PipPipGo signed in, English UI selected, and start from a main tab with no unsaved editor. Keep Device Hub screen sharing off for audio checks. Appium and XCUITest must already be installed. The runner uses the configured full Xcode path without changing global Xcode selection.

## Persistence

Server, session ID, helper build and timestamped JSON reports live in ignored `.full-test/`. The server binds only to 127.0.0.1. Normal runs reuse the server, signed WebDriverAgent helper and live session. A lost session is recreated without resetting app data. The test stops any active test audio but does not automatically stop the server, uninstall the helper or clear user data. Use teardown when rebuilding/reinstalling or explicitly asked to stop the setup. A computer restart may require setup again. No recurring automation is created.

## Automated scope

- Signed-in Pip/Live Guide/Translate/Profile tabs; the top globe language menu is inspected without changing selection; Live Guide tab opens.
- Profile’s large Trips tile, existing trip list, new trip editor and cancel/back navigation.
- Profile travel style, companions/new companion editor, bookings, calendars, personalization folder, nearby and account settings navigation.
- All five voice preview start/finish states; Save & Done control availability.
- Pip conversation history navigation.
- Translation controls, requested 13-language menu, settings, live connection/microphone-running status, manual stop and restored controls.

Preview audio and the live translator may play aloud. Translation uses the currently selected mode and languages, uses the existing provider quota, and follows the app's existing transcript policy. The test never deliberately changes a selected voice/language/mode or saves new records. Account deletion and sign-out controls are inspected, never activated. It stops on the first failure, records a failure instead of claiming later checks passed, and attempts to stop active voice/translation.

## Full acceptance coverage — explicit outstanding checks

Every report includes manual/test-account requirements: authentication/account switching; disposable multi-destination trips/companions and saving/retry/conflict behavior; profile/voice persistence; calendar/receipt/location permissions and imports; offline handling; Siri, greetings, interruptions and end phrases; audible translation quality in both directions, headphones/Bluetooth and 30-second inactivity; account deletion on an explicitly approved disposable account.

These are **not marked passed by the automated navigation run**. Never delete a real account, change real travel records, submit chat prompts, or grant new permissions merely to make the report green. A successful automation result means `automated_checks_passed_manual_checks_pending`, not complete product acceptance. Live speech cannot be proven by a “microphone running” label alone; use provider transcript evidence and a physical listening check.

## Offline runner validation

```sh
python3 -m unittest discover -s tests/full_test -v
```

These tests check persistent-server reuse, session reuse, no-reset capabilities, failure reporting, and no automatic teardown. They do not contact an iPhone. The full device suite must be run separately when requested. UI-label changes may require updating the runner; app changes do not require recreating the test definition.

## Targeted offline tour UI test

`scripts/offline_tour_ui_test.py` follows the current Guide UI using the existing
`tourBuilder.download`, `tourBuilder.name` and `liveGuide.myTours` accessibility IDs.
On an unlocked signed-in iPhone with English UI, prepare a tour and leave its
preview open. Then run:

```sh
python3 scripts/offline_tour_ui_test.py
```

This test gives the download a unique name, downloads the full package through the
real backend (provider usage applies), checks that My Tours contains that name and
opens its playback screen, then terminates/reopens PipPipGo and repeats the check.
It fails on a download error, timeout, missing list entry or missing playback
control. It retains the download and existing app data, reuses the Appium setup,
and writes a separate `.full-test/offline-tour-*.json` report. It does not run the
Full Test. Start from the tour preview with no other unsaved work because the test
relaunches the app. Airplane-mode audio playback still requires a listening check.
Physical-device execution evidence is recorded below. Installed build acceptance
is separate from any newer Guide source changes.


### Current tour controls — October 17, 2026

The targeted download test requires the explicit Ready Offline success message, then checks
`myTours.start`, `tour.downloadComplete` and the separate Apple Maps download instructions.
It no longer requires an OSM road map or treats a re-enabled Download button as success.
The optional delete regression remains limited to the runner's uniquely named generated tour.

To check an explicitly named saved QA package instead of creating/downloading one:

```sh
python3 scripts/offline_tour_ui_test.py --device SIMULATOR_UDID --saved-tour 'Old Town Source QA' --maps-handoff
```

This variant checks saved source credits/licenses, the active tour title after sheet dismissal,
Stop/Resume/Start Again, and optionally foreground Apple Maps/background PipPipGo state followed
by return. It stops only that test tour and never books a ride. It does not prove Create/Download
UI, physical GPS movement, audible background playback or Apple Maps offline availability.
The named public Old Town package was generated with live Wikimedia/OpenAI providers and imported
without replacing existing tours. Reports identify this coverage separately.

### Offline tour device run — October 16, 2026

Tested Akiphone, installed **PipPipGo Local 1.0 (32)**, English UI. Created a fresh
tour from the existing Del Mar, one-hour, Walking + Driving choices. Creation
reached a Start Tour preview: about 37 minutes, Del Mar Plaza parking, with a walk
to Del Mar and return. Download Offline failed before saving. Reopening My Tours confirmed “No saved tours yet.” The previous attempt
also displayed “Offline stories are not available for every stop in this tour.”
The targeted runner recorded `blocked_or_failed`, not a pass, in
`.full-test/offline-tour-20261017T033417636578Z.json`.

The first two automation attempts were blocked by scrolling across the tour-name
keyboard. The runner now scrolls above the keyboard; the third attempt reached the
actual download action and detected the app error. The backend requires a matching
Wikipedia story for every exported stop, including parking/return anchors; a
missing matching story is a suspected cause, not a verified response trace. No
backend or app deployment was performed. Relaunch persistence and offline audio
acceptance were not reached because download failed. Newer uninstalled Guide
changes are outside this device result.

### Offline map simulator acceptance — October 16, 2026

The user moved testing to the existing signed-in iPhone 16 simulator. Its GPS was
set to the user-specified address through an explicitly approved Apple geocoder
lookup, then restored to that origin after motion replay. Exact residential
coordinates are not added to this repository's documentation.

Local 113 created a fresh one-hour Del Mar Walking + Driving tour. Real download,
map display/zoom and relaunch persistence passed. Saved package: 9,211,991 bytes,
17 voice clips, 4,130,738 map-data bytes. Cold map-provider requests timed out;
successful UI acceptance used the verified public regional road map in the Local
backend's one-hour bounded cache. This is not a cold-provider availability pass.

Reports/artifacts (ignored local files):
- `.full-test/offline-tour-20261017T041058253894Z.json`
- `.full-test/offline-tour-map-fitted.png`
- `.full-test/offline-tour-gps-replay.json`
- `.full-test/offline-tour-delete-simulator.json`

Timed valid-speed GPS replay passed driving arrival, departure and walking-stop
controls. Static position-only fixes did not prove motion/arrival. Delete Cancel,
confirmed disappearance and absence after relaunch passed; only the uniquely named
generated test tour was deleted. The runner waits for confirmation to finish
before restarting and scopes alert actions to alert buttons.

For a new end-to-end run including deletion:

```sh
python3 scripts/offline_tour_ui_test.py --device SIMULATOR_UDID --delete
```

Start from a prepared signed-in tour preview. The runner now requires an actual
saved road map, checks zoom, and captures a map screenshot. Existing real tours are
not deleted. Physical movement/audible quality, airplane-mode, screen lock and
Bluetooth remain separate acceptance work. Backend Dev/Prod rollout is pending;
backend map support must precede updated app rollout.

### Current targeted commands and acceptance — October 17, 2026

Start from a main tab with no unsaved work, English UI and fresh simulator GPS at the approved
origin. The create variant chooses two hours and verifies both Driving and Walking selections.
It preserves organizer records and uses normal provider quotas. Review available download space
before running: the app keeps at most eight saved tours.

```sh
python3 scripts/offline_tour_ui_test.py --device SIMULATOR_UDID --create-area 'Old Town San Diego'
python3 scripts/offline_tour_ui_test.py --device SIMULATOR_UDID --saved-tour 'Offline UI 818bac5bb1' --maps-handoff
python3 scripts/offline_tour_ui_test.py --device SIMULATOR_UDID --create-area 'Old Town San Diego' --online-navigation
```

These passed as separate real Local runs: four Create/Download/persistence checks, five saved-tour/
source/title/Resume/Maps handoff checks, and two Create/online Apple turn-display checks. Reports are
in ignored `.full-test/offline-tour-*.json`; test downloads remain for review. Static simulator GPS
was refreshed during creation because the app requires a recent fix, then restored to the original
user-selected location. No private address/coordinates are stored in this documentation.

The runner uses explicit source-sheet and license identifiers, current visible control frames,
selected accessibility traits and asynchronous app-state waits. It distinguishes imported-package
checks from real UI downloads, and cannot pass solely because Download becomes enabled again.
Physical GPS/audio/CarPlay and Apple Maps offline-region coverage remain manual acceptance.
