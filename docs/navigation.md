# Navigation

October 1, 2026 (user-requested redesign): the signed-in app is a four-tab `TabView`, replacing the single organizer home list. Source was merged from `ui-redesign-tabs` into the default `develop` branch on October 1 (`0efb8fb`). The user confirmed on October 1 that it was tested on an iPhone and is working fine. This is user-reported physical-device acceptance; automated simulator/build validation for the redesign remains unrecorded.

| Tab | Contents |
| --- | --- |
| Trips | Large-title list of trips (name, route, date range). **+** adds a trip. A row pushes a read-only trip overview — destinations with dates, transport and hotel, travelers, budget summary and notes — whose **Edit** opens the existing trip editor. Empty state offers Add trip and Ask Pip. |
| Pip | Segmented control: **Ask Pip** (typed chat) and **Talk to Pip** (live voice). They remain separate pages sharing one saved conversation; New conversation / New talk sit in the navigation bar. |
| Translate | The two-way interpreter with its language bar. |
| Profile | Profile card, travel companions, nearby address, Language (globe, navigation bar) and Sign out with confirmation. |

Rules kept from the previous design:

- Creating and editing a profile, companion or trip is a modal draft with explicit Save/Cancel, so versioned saves, immutable retries and conflict review are unchanged. `TravelOrganizerView` owns the editor sheet for every tab.
- The microphone is live only while its page is visible. Leaving the Talk to Pip page or the Translate tab stops the session and clears captions, as Done did before. The Ask Pip / Talk to Pip control is disabled during a call so a call is ended explicitly.
- Siri/Shortcuts **Talk to Pip** selects the Pip tab's voice page and starts the call. It waits while an editor or trip-review sheet is open, chat is busy or awaiting retry, or translation is running.
- Ask Pip reloads the shared conversation whenever its page appears, replacing the former **Continue conversation** button.
- The selected tab is restored per scene (`pip.selectedTab`).

Travel companions are managed on the Profile tab and are no longer listed inside the My Profile editor; the trip editor's **Add someone** is unchanged.

October 1 physical-device acceptance: the user reported “I tested on iphone is working fine.” Device model, iOS version and individual test scenarios were not specified; this records overall UI acceptance without inferring specific regression coverage.

## Delete account — October 7, 2026

Profile includes **Delete account**, next to Sign out. Its destructive confirmation
explains that the PipPipGo profile, companions, trips, preferences and conversations
will be permanently deleted; it does not delete the user's Google account. Cancel
performs no operation. The existing authenticated `DELETE /v1/me` endpoint disables
writes, purges application records and deletes the Cognito user while retaining the
server's account-disable marker and AWS infrastructure.

Confirmation stops voice/translation, cancels Siri launch, clears in-memory private
state and shows a blocking progress screen. A failed/unknown request stays on an
explicit retry/sign-out screen; it never claims success or resumes normal writes.
Confirmed success clears device tokens. A device-storage cleanup failure offers a
separate retry without attempting to delete the account again. Authentication epoch
checks prevent an in-flight refresh from restoring a cleared session.

Validation: signed Local app/test compilation and two mocked deletion lifecycle
tests passed on the physical iPhone. Tests use fake account data and do not delete
any real account. No backend deployment required in Dev or Prod; public app rollout
and live deletion acceptance with a disposable test account remain separate.

Installation: normal signed Local build 27 installed and launched on Sara’s iPhone after the two mocked tests. Latest Cloud build 26 verified before building. Real account deletion was not performed.

## Compact learned profile — October 7, 2026

Profile shows **What Pip knows about you** as a collapsed folder row with the
saved-detail count. Expanding it shows two-line previews with explicit **Edit**
actions. The editor retains the full text, supporting evidence, Save and
**Delete this detail**. Existing versioned updates, immutable retries and conflict
review remain unchanged. No stored user information is removed by this layout
change; no backend deployment is required in Dev or Prod.

## Explicit profile saves and voice previews — October 7, 2026

Travel style has a persistent bottom **Save & Done** action as well as the toolbar
action. It closes only after server-confirmed success and shows **Changes saved**
on Profile. Cancel asks to save/discard/keep editing when changes exist; swipe
dismissal is blocked while dirty, saving, or awaiting an immutable retry. Existing
error, retry and conflict-review controls remain available. Profile/companion and
learned-detail editors also use **Save & Done** and guard unsaved dismissal.

Voice selection is separate from sample playback: Preview does not choose or save
a voice. Changes apply to the next conversation after saving. No backend deployment
is needed for these iOS-only changes.

## Visual Profile — October 8, 2026

Profile now opens with a photo/name/edit card and an adaptive grid of nine rounded icon tiles: Pip’s voice, Travel style, Companions, Plan a trip, Bookings, Calendars, About you, Nearby and Settings. Existing voice previews and Save & Done, travel questions, companion/trip editors, receipt import and calendar review are reused. About you opens the existing saved-detail folder with edit/delete and retry/conflict handling. Nearby retains the address and location permission controls. Settings contains waiting hum, Sign out, Delete account and version details; account confirmations are attached to the navigation stack. The language menu remains in the Profile toolbar, and pull-to-refresh remains available. No backend change or deployment is needed for this layout.
