# Appium physical-iPhone smoke test — October 8, 2026

Result: PASS for the limited navigation/control checks below on Sara’s iPhone (iOS 27.0.1), installed com.pippipgo.ios.

- Appium 3.8.0 / XCUITest 12.16.0 connected to the installed app with noReset enabled.
- Profile tab opened; icon controls were available.
- Pip’s voice sheet opened with all five selection and preview buttons and Save & Done. Cancel returned to Profile.
- Translate tab opened with language selectors, swap, Start translation, headphone mode and settings controls.
- Language menu contained the requested 13 languages in its accessibility tree (last four below the visible area). Kept the existing Farsi selection.
- Translation settings opened and Done returned to Translate.
- Test session and local Appium server stopped cleanly.

Initial WebDriverAgent signing setup needed allowProvisioningDeviceRegistration; signed helper build succeeded. Device lock delayed startup until the user unlocked it. No saved voice or language selection was changed, no account/trip data edited, and no app rebuild/deployment performed.

Limits: this was a navigation smoke test, not a full regression suite. Voice sample playback, microphone input, spoken translation quality, saving changes, and destructive actions were not tested. Device Hub screen sharing stayed off. Appium reported the headphone-mode switch value as 1 during this run; the test did not toggle it.

Local diagnostic log: /tmp/pippipgo-appium-smoke.log. Temporary test helpers are under /tmp/pippipgo-appium-*.py; these paths are not durable test infrastructure.

## Extended pass — October 8, 18:48:52–18:51:27 UTC

PASS for these additional observed checks:
- Travel style opens; Cancel closes it.
- Companions opens; Back returns to Profile.
- Bookings opens its receipt screen; Close works.
- Calendars opens with Connect calendars; Done works (no permission/import requested).
- Ballad preview transitions to Stop Ballad voice, indicating playback state; Cancel closes voice settings without selecting or saving.
- Translation connects; backend reports 95 audio frames, 42 audible frames and 12 input transcript deltas. Translated output text appears in the app. Spoken output quality was not independently heard or scored.
- Stop translating returns to Start translation and re-enables language/mode controls.
- About you opens with the collapsed saved-details control accessible.

The current session was listen_only=True, consistent with the headphone-mode switch observed in the previous pass. This was preserved; no language/voice/mode settings were changed. No data editing, deletion, calendar access or receipt import was exercised. Appium session/server stopped after returning to Translate. No code fix, iOS rebuild, or backend deployment was needed for this test.
