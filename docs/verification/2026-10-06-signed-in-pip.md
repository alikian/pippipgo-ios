# Signed-in Pip visual redesign — October 6, 2026

## Screen and existing actions

`TravelOrganizerView` in `pippipgo/Intelligence/TravelOrganizer.swift` selects the Pip tab by default and renders `PipTab`. The historical `PipHomeView` is not the active organizer tab. Authentication and welcome views are not redesigned in this change.

`PipTab` continues using `TravelChatStore`, `LiveVoiceStore`, `TravelChatView`, `LiveVoiceView`, and `PipComposer`. Text entry selects the existing chat mode, stops the current voice session and preserves the draft. The composer retains dictation, send, voice start/stop, new conversation, pending/retry and conflict guards. The internal mode remains for routing, with no mode picker in the consumer UI. Automatic voice entry and Siri routing remain in place.

The toolbar history sheet uses the existing recap and chat renderer with saved messages rather than only this visit's messages. Trip review actions are retained. Three suggestions call the existing trip editor, select the existing Translate tab, or prepare an editable nearby-fun draft. Profile's existing travel-style/voice picker is labeled “Travel style & Pip’s voice.”

## Appearance

Warm cream, navy text, white composer, blue voice control; existing approved `PipWelcome` asset framed in a compact hero. Hero reduces during conversation and hides for keyboard entry. Suggestions scroll horizontally at larger text sizes. The composer stays in the bottom safe area. The existing native Trips/Pip/Translate/Profile navigation remains. The build indicator is removed from the root consumer view; no backend or authentication changes.

## Validation

- Xcode Cloud report navigator showed latest Default/develop build 25; local build set to 26.
- Signed Local build, wired installation and launch succeeded.
- A physical iPhone screenshot confirmed the signed-in Pip tab, selected Pip navigation, approved hero, input and suggestions; old mode selector, recap heading and build indicator were absent.
- This first screenshot exposed a truncated toolbar wordmark under the device's larger text settings; intrinsic-width branding and an explicit image frame were added for the final build.
- Final signed build 26 was reinstalled and launched. The final physical screenshot confirmed the full wordmark, rounded artwork and “Pip is speaking…” during active playback. Screenshot: `/Users/saranoorafkan/.codex/visualizations/2026/10/06/01a10f32-3759-7a52-9553-92c153241a18/pip-signed-in-final.png`.
- No simulator devices/runtimes were available. Visual verification on this phone is not a claim of interaction testing across all device sizes or every voice/error state.
- Backend deployment is not required.
