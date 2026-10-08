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

- Signed-in Pip/Translate/Profile/Language tabs; language choices are inspected without changing selection.
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
