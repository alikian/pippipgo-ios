# Talk to Pip — GPT-Live

Requested September 28, 2026. The organizer home and fixed Ask Pip controls have a Talk to Pip button opening a dedicated voice sheet. The sheet includes an explicit Start voice conversation control, live user/assistant captions, streamed speech, and End voice. Typed Ask Pip uses GPT-6 Luna (selected September 29, 2026). Voice uses `gpt-live-1`, Marin, mono PCM16 at 24 kHz and GPT-6 Luna Responses delegation without tools. Native AVAudioEngine voice processing handles microphone/speaker echo cancellation. Voice and typed requests cannot run together.

The app opens `wss://<backend>/v1/travel-chat/live` with the existing Cognito access token in the Authorization header. The backend verifies identity, the retained account-disable fence and the existing daily AI quota before opening OpenAI's Live WebSocket. No OpenAI credential reaches iOS. Each session is limited to five minutes; credentials and account state are checked every 15 seconds. The existing server environment/Secrets Manager key and IAM grant are reused. No new infrastructure resource is required.

Only allowlisted profile fields and bounded prior chat text seed the session. Saved trips are included as read-only context at the user’s September 29 request. Saved companions are also included at the user’s subsequent September 29 request, with selected companions resolved for each trip. Structured chat drafts remain excluded. All saved traveler profile fields (name, age, hometown, interests and notes) are included in full, bounded by the organizer schema. Prior chat text has a separate 6,500-byte budget so a long profile does not displace all conversation history. Provider storage is disabled. Audio and captions are neither logged nor saved by PipPipGo. Captions disappear when the chat closes or the account resets. A voice session cannot write organizer data; saving a plan uses typed chat and the existing explicit review/Save flow.

The backend only accepts PCM audio appends and session close, so a client cannot change the model, instructions or tools. It filters outgoing events to audio/captions and closes the provider connection on cancellation, disconnect, account disable or timeout. The app stops capture/playback on chat dismissal, account reset, interruption and headphone disconnection. As requested September 29, an established voice conversation continues during screen lock/backgrounding using the audio background mode; an unfinished connection is cancelled when entering the background. Slow input/output queues terminate instead of accumulating stale audio. It does not reconnect or resume microphone capture automatically.

## Verification and release boundaries

- Model agreement: user explicitly requested GPT Live; `gpt-live-1` used, GPT-6 Astra preserved.
- Account access: existing Dev OpenAI secret successfully opened and closed a real GPT-Live session.
- Live inference: the full configured session accepted synthetic speech asking for Paris travel help; returned 602,880 audio bytes, eight input-caption events and ten output-caption events, with zero provider errors. This verifies OpenAI audio inference, not a deployed app connection or physical microphone quality.
- Backend validation: 133 tests passed, one skipped; Ruff checks/format passed. Mocked voice cases include authorization, disabled accounts, context filtering, injected commands, audio validity, normal close, abrupt disconnect, active-account deletion and session expiry.
- iOS validation: 56 simulator tests passed; signed Dev iPhone build passed. These do not establish physical-device voice acceptance.
- Deployment/IAM: user approved rollout. Backend commit `c196372` deployed successfully through [run 36521766502](https://github.com/alikian/pippipgo-backend/actions/runs/36521766502), ECS revision 15, CloudFormation UPDATE_COMPLETE and ECS steady state. No IAM change was needed. Public health/readiness passed; unauthenticated chat returned 401 and voice WebSocket returned 403. Authenticated audio through the public ALB remains a device acceptance check.
- Physical-device acceptance: pending. Check speaker/headphones, two-way speech and interruptions, backgrounding, network loss, microphone denial, account switching, five-minute expiry and Cognito expiry. Run the organizer multi-destination acceptance scenario as a regression.

## Rollout

Deploy the backend containing `/v1/travel-chat/live` using the existing CloudFormation-managed ECS delivery workflow. Verify authenticated WebSocket upgrade and a synthetic audio exchange through the public ALB before releasing the app. Keep request payloads and Authorization headers out of proxy/application logs. Then install the signed Dev app and perform the physical-device checks above. The endpoint is now deployed to Dev. The signed app with home and fixed-chat Talk to Pip buttons was installed and launched on Ali’s iPhone (`00008101-0009498E2647001E`). Physical microphone/conversation acceptance is still pending.

## Official protocol references

- [GPT-Live WebSockets](https://developers.openai.com/api/docs/guides/voice-websockets)
- [Session configuration and captions](https://developers.openai.com/api/docs/guides/live-conversations)
- [Responses delegation](https://developers.openai.com/api/docs/guides/live-delegation)

September 28 visibility follow-up: the previous build had not been installed on the phone, and chat auto-scroll could hide the inline voice section. The updated home/fixed buttons passed 56 simulator tests and a signed Dev build. Automatic approval review blocked the develop push/deployment pending explicit user approval; no push, deployment or phone installation occurred.

Approved rollout completed September 28: the earlier approval block was resolved by the user. Dev deployment succeeded, the phone app was installed, and `devicectl` confirmed successful launch. Tap Talk to Pip below Ask Pip, then Start voice conversation.

## Silent Listening investigation — September 28

User reported Listening with no spoken response. Dev logs confirmed authenticated voice connections were accepted. A synthetic speech test through the full local backend relay and real GPT-Live provider returned 147 audio events, nine input-caption events and 15 output-caption events with normal closure. This isolates a working relay path but does not establish physical microphone capture.

The iOS update adds a live microphone level and capture watchdog, labels the state Starting microphone until the first captured buffer, allows the permission prompt's temporary inactive state, and handles only beginning audio interruptions as a stop. 57 simulator tests and signed Dev build passed. Installed on Ali’s iPhone; iOS denied launch because the phone is locked. Physical speech input and the root cause of the reported silence remain unverified; the user has been asked whether captions appear and whether testing is on the phone or simulator.

## Spoken greeting

Each new voice session now says “Hi, I’m Pip, your travel companion.” once, then listens. The backend sends the instruction after the first microphone audio packet so the GPT-Live timeline is advancing. A real-provider test with only silent input returned that exact caption and 132 audio events. 133 backend tests (one skipped), Ruff checks and CI passed. Commit `ca3dfe8` deployed through [run 36523013127](https://github.com/alikian/pippipgo-backend/actions/runs/36523013127); ECS revision 16 reached steady state and public health/readiness passed. No app reinstall is needed for this backend change. Physical microphone/speaker acceptance remains separate.

## Microphone input graph fix — September 28, 23:50 PDT

The user's capture-timeout screenshot was reproduced by a physical iPhone regression test: the original input tap returned no PCM buffers within four seconds. Connecting the voice-processing input to an explicit `AVAudioSinkNode` keeps the microphone graph rendering before assistant playback; the identical physical test then passed in 0.649 seconds. The PCM converter separately produced valid output from synthetic input. The timeout copy no longer claims that another call caused the failure.

Validation: one physical capture regression passed, all 57 simulator tests passed, and a clean signed Dev build passed signature verification. Installed on Ali’s iPhone; the final normal launch was denied because the phone had relocked. The user can unlock and open the installed app. This verifies physical capture-buffer delivery, not yet a complete user-spoken conversation or speaker quality. The automated capture test saves/uploads no audio and is compiled only for physical-device test destinations.

Reference: [Apple AVAudioSinkNode documentation](https://developer.apple.com/documentation/avfaudio/avaudiosinknode).

## Audio-session threading — September 29

Moved Talk to Pip category/activation/deactivation to one serial background queue, with call ownership checks to prevent stale cleanup deactivating a replacement call. Startup awaits activation and checks cancellation before creating the audio graph. The graph is initialized after activation; stopping before startup no longer creates an engine. This supports the iOS 17 deployment target; the SDK's native asynchronous activation/deactivation APIs require iOS 27.

Validation: 59 simulator tests passed, including off-main execution, stale cleanup and stopped-start cancellation; the signed Dev build passed. Physical capture runs no longer emitted the reported AVAudioSession main-thread warning. However, physical capture timed out repeatedly, initially on the AirPods HFP route and again after the user disconnected AirPods. A control using original synchronous main-thread activation and the existing input sink also timed out and reproduced the warning. A muted mixer experiment did not resolve capture and was reverted. The earlier single passing microphone test is therefore not sufficient evidence of a reliable fix. Full physical capture/conversation acceptance remains unresolved. No recorded speech was saved or uploaded during these tests.

September 29 threading fix: clean signed Dev app installed on Ali’s iPhone. Automatic normal launch failed with a CoreDevice remote-service connection error; open the installed app manually.

## iPhone 16 Pro Max comparison — September 29

User requested testing on the connected iPhone 16 Pro Max, Akiphone (`00008140-001405023E88801C`), running iOS 27.0 build 24A437. The Talk to Pip capture test failed repeatedly with the same four-second no-PCM timeout after microphone permission was granted. Two minimal controls passed: a basic AVAudioEngine input tap (0.382 s) and a tap with voice processing enabled (0.841 s). These controls use the same audio-session activation helper. This isolates a difference in the app's combined input/playback/conversion graph; it does not yet identify the exact faulty operation or prove an OS defect.

Explicit output formatting, removing the input sink with a default-format tap, and keeping playback supplied with looped silence did not fix the full capture test. These experiments were reverted. Retained physical-only tests now compare basic capture, voice-processed capture and the full production pipeline, and request microphone permission on a new test device. They retain/upload no microphone audio. No backend runtime change was made.

The comparison app was rebuilt in a fresh output directory after an incremental build had an invalid asset signature. The clean signed Dev build and signature verification passed; installed on Akiphone. Normal launch was denied because the phone had locked. Manual Talk to Pip acceptance remains pending.

## Full-duplex output connection fix — September 29

User confirmed the normal iPhone 16 Pro Max app also timed out. Dev WebSocket connections were accepted at 07:48:58, 07:51:02 and 07:54:02 UTC; this does not by itself prove audio delivery. A controlled physical-test matrix then isolated the app graph: adding a player with automatic mixer output failed at both 24 kHz and the native output sample rate, while explicitly reconnecting the final mixer output **after attaching the player** passed (0.716 s). An earlier explicit-output experiment had connected the mixer before the player and did not resolve capture.

Production startup now creates the voice-processing input, attaches the 24 kHz player, explicitly connects the main mixer to the output using its native format, and only then reads the input format and installs its tap. The redundant sink was removed. The real PCM pipeline passed on Akiphone in 0.580 s, followed by three successive starts delivering at least two seconds of 24 kHz PCM each while scheduling silent playback (7.902 s total). All 59 simulator tests passed. Physical tests retain/upload no recorded audio. The added sustained-capture regression exercises playback and teardown/restart, not merely first-buffer delivery. Full provider greeting and user-spoken response acceptance remains separate until confirmed on the installed app.

Additional device validation: Ali’s iPhone 12 passed first-buffer capture (0.632 s). Its first sustained run encountered an AVAudioSession activation error; a focused rerun passed all three sustained playback/restart cycles in 7.768 s. A fresh signed Dev build passed signature verification and was installed and launched successfully on Akiphone. The user has been asked to confirm the greeting and a spoken reply in the updated app.

The verified fix is installed on both physical phones. Akiphone launched successfully; normal launch on Ali’s iPhone 12 was denied after it relocked. User confirmation of the updated Akiphone greeting and spoken reply is pending.

## Conversation acceptance and caption bubbles — September 29

The user confirmed on Akiphone that voice conversation now works (“talk is fine”) and requested chat-style message bubbles. This records successful user-spoken conversation acceptance after the output-connection repair; other physical scenarios listed above remain separate.

Live captions now appear as chronological message bubbles: Pip on the left, the traveler in blue on the right. Speech fragments grow within their bubble; each speaker is grouped independently using provider timeline intervals, including overlap and delayed delivery. A gap of more than 1.2 seconds starts a new bubble for that speaker; these are display boundaries, not provider-defined completed turns. Original fragment text/timing is retained within bounded transient memory (8,000 characters, 64 bubbles, 512 fragments). Starting a new session or closing the sheet clears the transcript. Nothing is added to saved typed-chat history.

The conversation fills a scrollable area with fixed microphone/start/end controls. New captions follow the latest message until the user drags to read earlier messages; “Latest messages” resumes following. Light and dark synthetic conversation previews were visually checked. The temporary simulator launch route was removed before the phone build; the reusable Xcode preview remains debug-only. All 62 simulator tests passed, including overlap, late fragments, timestamp ordering, exact repeated words, clearing and bounded retention. Signed Dev build and signature verification passed. The backend relay already includes transcript intervals, so no backend runtime deployment is needed.

Protocol reference: [Managing GPT-Live sessions — transcript deltas](https://developers.openai.com/api/docs/guides/live-conversations).

The chat-bubble Dev app is installed on Akiphone. Normal launch was denied because the phone had locked; open PipPipGo manually to use the updated conversation view.

## September 29 model change

The user selected `gpt-6-luna` for typed Ask Pip and voice Responses delegation.
A synthetic travel question returned a valid live Luna structured reply, and a real
OpenAI Live session accepted the full `gpt-live-1` configuration with Luna delegation.
The session was closed without audio; this does not verify an executed delegated
response or physical-device Luna acceptance. Existing credentials/IAM are reused.
Backend checks: 133 passed, one skipped; Ruff lint/format and hosting template lint passed.

GPT-6 Luna selected September 29: typed Ask Pip and voice reasoning now use `gpt-6-luna`; audio retains `gpt-live-1`. Synthetic live structured inference and Live session acceptance passed. 133 backend tests (one skipped), Ruff and CI passed. Dev commit `de4298f` deployed through [run 36541532191](https://github.com/alikian/pippipgo-backend/actions/runs/36541532191); ECS revision 17 is steady, health/readiness return 200 and unauthenticated access returns 401. IAM unchanged; no app rebuild required. Physical-device acceptance of Luna remains pending.

## Screen-lock continuation — September 29, 2026

Enabled `UIBackgroundModes: audio` in Debug and Release app plists and retained
established voice sessions on background transitions. The existing play-and-record
voice-chat audio session supports continuous microphone/speaker use with the screen
locked. The voice sheet explains this behavior. End voice, dismissal, account reset,
interruptions, headphone removal and the server five-minute limit still end sessions.
Removed a duplicate microphone permission plist key so the live-voice explanation
is the single declared permission message. Simulator regressions and signed Dev build
passed; physical locked-screen conversation acceptance remains pending.

## Complete profile — September 29, 2026

At the user’s request, live voice now receives all five saved traveler fields in full:
name, age, hometown, interests and notes. Removed the 1,200-byte per-field cutoff;
the persisted organizer schema still bounds field lengths. Prior chat has an independent
6,500-byte budget. Internal record IDs, saved companions/trips and unknown fields stay
excluded. Profile edits are picked up when the next voice session starts.
135 backend tests passed (one skipped), including exact long multilingual profile
preservation with chat history; Ruff passed. OpenAI accepted a real Live session
with an 11,194-byte synthetic profile context; no audio was sent. This is session
acceptance evidence, not spoken profile-recall or physical-device acceptance.

Full traveler profile in voice: all saved name, age, hometown, interests and notes are sent without truncation at session start. 135 backend tests (one skipped), Ruff and real-provider session acceptance passed. Dev `c82188f`, [run 36542495094](https://github.com/alikian/pippipgo-backend/actions/runs/36542495094), ECS revision 18 steady; public health/readiness passed. No app reinstall needed; spoken profile recall remains a device acceptance check.

## Saved-trip voice context — September 29, 2026

The user requested access to saved trips in voice. Each new session includes the
authenticated account’s trip names, destinations/dates, hotels, transport, party counts,
budgets and notes. Internal trip/companion references and saved companion records are
excluded. Trips are a read-only snapshot; voice cannot silently edit organizer data.
The shared prompt now permits supplied trip context, while typed chat continues to
receive only its existing context. The iOS disclosure now names saved trips.
135 backend tests (one skipped), Ruff and CI checks passed, including trip inclusion
and cross-account isolation. A live Luna Responses check recalled the synthetic
saved flight AF123 from the exact context; this does not prove a spoken GPT-Live
response on the phone. Signed Dev app built, signature verified and installed on Akiphone.

Saved trips in voice: explicitly authorized September 29; trip details now included read-only at session start. 135 backend tests (one skipped), Ruff, live synthetic Luna flight recall and signed Dev build passed; disclosure update installed on Akiphone. Backend `a066f88` deployed through [run 36543283464](https://github.com/alikian/pippipgo-backend/actions/runs/36543283464), ECS revision 19 steady and health/readiness 200. Spoken saved-trip recall on the phone remains to be confirmed.

## Saved companions — September 29, 2026

User authorized companion context. New sessions include every saved companion’s
name, age, hometown, interests and notes, plus each trip’s selected companion details.
Unselected companions remain available in the general list but are not treated as
traveling on every trip. Internal person IDs and unknown fields are excluded. This
is read-only context; typed chat still receives its existing context.
135 backend tests (one skipped), Ruff and CI checks passed. Tests cover selected versus
unselected companions, complete fields and account isolation. Live Luna synthetic
context recalled the selected Sam and their train preference. This checks reasoning
recall, not physical spoken acceptance. Signed Dev build passed and the updated
sharing disclosure was installed on Akiphone.

## Session presence and goodbye — September 29, 2026

After 30 seconds without transcribed user speech or assistant output, the backend
asks Pip to say “Are you still there?” once. It waits 15 seconds after the check-in’s
last output for a user reply, then closes both connections. A reply resets the timer;
continuous silent microphone packets do not count as speech. No timer starts before
capture begins. A short explicit English farewell (for example “bye”, “goodbye Pip”,
or “see you later”) followed by a two-second pause requests a brief goodbye and ends
after playback drains, bounded to 12 seconds. Incidental mentions such as “How do I
say goodbye in French?” do not trigger closure; resumed speech cancels pending closure.
Five-minute maximum and account/interruption cleanup remain. Transcript fragments
used by this policy stay transient and bounded.
142 backend tests (one skipped) and Ruff passed, including policy timing, replies,
fragmented/corrected goodbyes, long assistant speech and relay close cleanup.
Implementation follows [OpenAI live session controls](https://developers.openai.com/api/docs/guides/live-conversations).

Real-provider relay acceptance: continuous silent PCM produced the greeting and
“Are you still there?”, then closed automatically at 52.3 seconds with zero errors.
Synthesized “Goodbye, Pip” was transcribed and closed at 18.8 seconds with zero errors.
An initial check exposed continuously emitted silent output packets; those are now
excluded from activity using PCM energy, with a regression test. The final farewell
instruction avoids repeating a goodbye the model has already spoken. These are
synthetic live checks; physical-device silence/goodbye acceptance remains pending.

Companion and session lifecycle rollout: companion context `9f69d87` deployed through run 36544111413 (ECS revision 20); signed disclosure update installed on Akiphone. Session presence `9ec9f06` deployed through [run 36545154254](https://github.com/alikian/pippipgo-backend/actions/runs/36545154254), ECS revision 21 steady and health/readiness 200. 142 backend tests (one skipped), Ruff and CI checks passed. Real relay silence test asked “Are you still there?” and closed at 52.3 seconds; final synthesized goodbye test gave one farewell and closed at 16.9 seconds. Physical-device acceptance remains pending.

## Goodbye recognition correction — September 29, 2026

User reported goodbye did not end their conversation. Exact user transcript was not
available. The prior exact-phrase detector missed “good bye”, polite lead-ins and
a goodbye attached to an earlier sentence; whitespace-only transcript fragments
were also discarded. Recognition now preserves fragment spacing and matches natural
explicit farewells in the final sentence, while excluding incidental mentions,
negations and corrections. 157 tests passed (one skipped), Ruff passed. A real relay
check transcribed “Okay, thank you for your help. Goodbye, Pip”, gave a farewell and
closed at 18.8 seconds from session start with no provider errors. This does not
establish acceptance of the user’s exact failed utterance; device recheck remains.

Goodbye recognition fix: `07905fc` deployed successfully through [run 36546544327](https://github.com/alikian/pippipgo-backend/actions/runs/36546544327), ECS revision 22 steady and health/readiness 200. 157 tests (one skipped), Ruff and real-provider natural sign-off closure passed. User-specific phone recheck remains pending.

## Siri: Start Talk to Pip — September 29, 2026

Implemented the foreground Siri/Shortcuts action **Start Talk to Pip**. Say
“Hey Siri, talk to Pip in PipPipGo” or “Hey Siri, start Talk to Pip in PipPipGo”.
For the shorter “Hey Siri, start Pip”, create a personal shortcut in Shortcuts,
add PipPipGo’s **Start Talk to Pip** action, and name the shortcut **Start Pip**.
Open the updated app once and sign in before trying Siri. Grant microphone access
when prompted. This release targets an unlocked phone; new calls from a locked
phone still require foreground access. Existing connected background audio is unchanged.

An in-memory request survives cold-launch session restoration and is consumed only
when a signed-in view is active. It opens the existing voice sheet and starts voice
automatically, including from Ask Pip. Active calls are reused. Requests wait for an
open editor or pending typed-chat operation, expire after 60 seconds, and are cleared
on sign-in/sign-out so they cannot carry over to another account. Manual voice buttons
retain their existing behavior. No backend API, model, credential or context changes.

Validation: 66 simulator tests passed (four new launch lifecycle regressions), signed
Dev iPhone build and codesign verification passed, and generated App Intents metadata
contains the action and all three supported phrases. No new live provider check was
performed. Physical Siri recognition, cold/warm launch, microphone handoff, AirPods,
repeat invocation, signed-out behavior and launch while editing remain acceptance checks.

Apple references: [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts)
and [running shortcuts with Siri](https://support.apple.com/en-ie/guide/shortcuts/apd07c25bb38/ios).

Siri rollout: signed Dev app installed and launched on Akiphone (iPhone 16 Pro Max). Spoken Siri invocation and conversation acceptance remain pending.

Siri acceptance follow-up: user confirms tapping the Start Pip shortcut’s play button works. Spoken invocation still fails to resolve correctly (earlier Siri response treated Pip as a contact). Shortcut execution is user-confirmed; Siri phrase recognition remains unaccepted.

## Conversation-start context — September 29, 2026

Typed Ask Pip captures device time, IANA timezone and optional approximate location on the first send after opening the conversation; voice captures them before its session connects. Coordinates are rounded to two decimals. iOS asks for When In Use permission, waits at most eight seconds and proceeds without location on denial, timeout or failure. Fixes older than five minutes are omitted on device; the backend rejects fixes more than ten minutes from current time. Account reset fences late capture results; typed retries retain the exact serialized body/key/version.

The user explicitly authorized sending this context to OpenAI. Context is request/session data, not a new organizer record or stored chat-history field. Model-generated replies can still mention contextual facts. Existing model selection, ownership and saved-data permissions remain unchanged. The app disclosures and iOS permission text describe location sharing.

The backend accepts optional `conversation_context` on `/v1/travel-chat`; voice uses a bounded base64 JSON `X-Pip-Context` header. Older clients remain supported. Device `captured_at` and location `captured_at` require an offset; `timezone` must resolve in IANA tzdata. The backend supplies an ISO local time with UTC offset.

Weather is explicitly unavailable in this implementation pending the separately requested authorization to send approximate coordinates to Open-Meteo. No weather provider is contacted. Never infer present position from hometown or saved trips, and never invent weather.

Rollout: deploy the backend before installing this app version (the earlier typed endpoint rejects unknown fields). Backend deployment, device installation, real-provider context recall, and physical permission/denial testing remain pending. No IAM or AI model changes.

Context validation: 170 backend tests passed (one skipped), Ruff lint/format passed, 68 simulator tests passed, and the signed Dev build plus strict signature verification passed. Tests use mocked context/provider behavior; these are not live weather or physical-device acceptance.

Location diagnosis (September 29 Pacific / September 30 UTC): AWS readback confirms ECS revision 23 is running image tagged `sha-b4104fd932150d8bb303e06ce5201c1e5e2a39db`, deployed before the local conversation-context implementation. That commit supplies UTC/profile/saved-trip context but no current device location. The new context code remains uncommitted and the context build was not installed in the preceding session. The exact last voice exchange cannot be replayed because audio/transcripts are transient. This is a rollout gap; location behavior on a deployed updated app remains unverified.

Conversation-context backend deployed: `015fb65` through [run 36649006631](https://github.com/alikian/pippipgo-backend/actions/runs/36649006631). CI and CloudFormation completed successfully; ECS revision 24 is stable. Public health/readiness returned 200 and unauthenticated account/chat endpoints returned 401. 170 backend tests (one skipped), Ruff, CloudFormation validation and container smoke checks passed. No IAM/model changes. Updated iPhone app installation and physical location-context acceptance remain pending; weather remains unavailable pending provider authorization.


## Admin viewer capture — September 29 request

The user explicitly authorized backend retention of future voice transcripts and LLM context for the read-only admin viewer at `https://admin-dev.pippipgo.com`. This supersedes earlier transient-caption/context statements for new sessions. Audio remains transient and is never recorded. The backend captures exact session configuration, appended instructions and bounded transcript deltas, checkpoints every ten seconds and finalizes at close. Provider-internal delegation context is unavailable. Account deletion purges captures and fences late writes. Earlier sessions cannot be reconstructed. See backend `docs/admin-viewer.md` for access controls, retention, limitations and deployment evidence.

### Precise location context (September 30 UTC)

The user's precise-location request supersedes the earlier approximate-coordinate policy. iOS now requests `kCLLocationAccuracyBest`, preserves coordinates without rounding, and sends `horizontal_accuracy_meters` with the fix timestamp. The device omits invalid fixes and fixes older than 60 seconds. The existing one-shot capture timing, eight-second timeout, optional permission, cancellation and account-switch fences remain. This is a context snapshot, not continuous tracking; typed retries keep their original body and location.

The backend accepts optional nonnegative finite accuracy for compatibility with older clients and passes it to both typed and voice model context. The prompt instructs Pip to respect measured accuracy and freshness and not infer a building/street from coarse data. Precise permission does not guarantee a precise GPS fix: iOS can return reduced accuracy when Precise Location is off, and the measured radius is reported honestly. See [Apple desiredAccuracy](https://developer.apple.com/documentation/CoreLocation/CLLocationManager/desiredAccuracy). Disclosures and permission descriptions now describe precise coordinates when permitted. Captured model context, including these coordinates, follows the existing administrator-review retention policy.

Precise-location rollout: backend `0c3576f` deployed through successful [run 36654620576](https://github.com/alikian/pippipgo-backend/actions/runs/36654620576); ECS revision 28 stable, one running task, zero pending, health OK. 207 backend tests (one skipped), Ruff, 69 simulator tests and signed Dev build/strict signature verification passed. The signed app contains the revised precise-location permission text. The updated iPhone build is not installed; physical GPS/permission acceptance remains unverified.

### Location acquisition repair

The user's latest September 30 01:39 UTC voice request had device time/timezone but no location. This confirms missing capture, not dropped context transport; the old client supplied no failure reason. The precise-location collector's one-shot/eight-second path could terminate on a stale fix or temporary Core Location error.

The collector now listens for updates for up to 15 seconds after authorization, ignores stale/invalid fixes and temporary `locationUnknown`, finishes early at 25 meters or better, and otherwise sends the best fresh fix with its actual accuracy. Reduced-accuracy permission remains respected. The permission prompt has its own bounded wait rather than consuming the acquisition window. Every completion stops updates and respects cancellation. Typed new messages recapture missing/stale context; an existing pending retry still uses exactly its original body/key/version.

Optional `location_status` reports `available`, `approximate`, `permission_denied`, `permission_restricted`, `permission_pending`, `timed_out`, `stale`, `unavailable` or `cancelled` in the saved model context. Historical missing locations cannot be reconstructed. The device acceptance test is opt-in with `PIPPIPGO_LOCATION_DIAGNOSTIC=1` and logs status/accuracy only, never coordinates.

The app now displays a Current location card in typed chat and live voice: coordinate snapshot, accuracy radius and capture time, with explicit missing-location reasons. Typed chat has an Update button that respects pending retries and account changes. Denied/reduced permission offers Open location settings. Voice displays its session-start snapshot. This does not add ongoing background tracking.

Automated validation: 212 backend tests passed (one existing skipped); Ruff passed. The simulator suite passed 74 automated tests with the opt-in physical diagnostic skipped. Signed device build and strict signature verification passed. The diagnostic logs status and accuracy only.

Deployment evidence: backend `c1940b3` through successful run 36656492499, ECS revision 29 stable with one running task and zero pending. Signed repaired app with the Current location field installed on Akiphone using devicectl. The opt-in physical diagnostic could not launch because the phone was locked; it was stopped, so no live GPS/permission result is claimed. Final focused simulator run passed all eight location/context tests after the last cleanup change.

Automatic nearby-address display: at the user’s request, home/chat/voice cards now show an Apple-resolved nearby address and update time, without coordinates, accuracy readouts or a manual Update button. One shared account-scoped display store starts on signed-in foreground activation, refreshes after roughly one minute, and cancels on background/sign-out. Address lookup uses native MapKit reverse geocoding on iOS 26+ and Core Location on older supported versions, with a ten-second lookup timeout. Results within 50 meters are reused for up to five minutes; lookups are limited to at most one per minute. Coarse fixes request a city/region rather than a street address. Lookup failure is explicit and never falls back to displaying coordinates. Automatic display updates do not modify pending chat retries or active voice-session context; fresh fixes can be reused for new requests.

Validation: 78 automated simulator tests passed, with one opt-in physical diagnostic skipped; signed Dev build and strict signature verification passed. New tests cover caching, request throttling, coarse lookup, late account-reset responses and single automatic worker/cancellation. Installed on Akiphone; live Apple address resolution on the phone was not independently observed. No backend API deployment was needed.

## Inactivity sign-off

After 30 seconds without conversational activity, Pip asks “Are you still there?”
and waits 15 seconds after finishing the check-in. If there is no reply, it now
says “I’ll end our call for now. Goodbye!” before ending the session. The relay
allows the sign-off audio to finish and the playback queue to drain; a 12-second
upper bound prevents a stuck provider from leaving a silent call open. New speech
cancels the pending inactivity closure. Manual hang-up and security termination
remain immediate.

230 backend tests passed (one skipped), including sign-off ordering, delayed audio,
resumed speech, bounded provider silence and both socket closures. A live synthetic
silence test heard the greeting, check-in and goodbye in order, then closed after
58.3 seconds with no provider errors. Physical-device acceptance remains pending.

Deployed `7c17bef` as ECS revision 32 through successful [run 36664788740](https://github.com/alikian/pippipgo-backend/actions/runs/36664788740). CloudFormation completed; public health/readiness returned 200 and unauthenticated `/v1/me` returned 401. No iOS update is required; start a new voice session.

### Voice driving-directions handoff (September 29, 2026)

The iOS client advertises `X-Pip-Navigation: 1`. Only those sessions expose
`open_driving_directions`; typed chat and older clients keep their existing tool set.
On an explicit navigation request (for example, “Take me there”), the model selects a
place ID returned by a Places/road-distance tool during this voice session. Unknown IDs
require a search; ambiguous references must be clarified. Search alone does not navigate.
The backend rechecks account access before emitting `navigation.open`, containing only
the verified destination name and ID. Duplicate tool calls cannot emit a second event.

The app constructs a fixed HTTPS Google Maps directions URL, with the destination place
ID, driving mode and navigation action. No credentials or origin coordinates are embedded.
Maps obtains the starting location itself. The app allows Pip to announce the handoff,
waits for playback to drain (with a 15-second cap), stops voice and opens Maps only while
foregrounded. Ending voice or resetting the account cancels a pending handoff. Opening
failure is shown in voice UI. Maps may present route preview instead of navigation;
the universal URL supports the installed app or browser fallback.

Validation: 249 backend tests passed (one skipped), Ruff passed, nine configuration/navigation
simulator tests passed, and signed Dev build/signature verification passed. Live provider
and deployment evidence follows separately; these checks do not prove physical-device Maps
handoff or measured audio completion.

Live provider check: generated speech asked for the nearest gas station and then requested
driving directions. Real Google road lookup succeeded; the relay emitted exactly one
`navigation.open` for the returned Shell place ID, and GPT-Live spoke “Opening driving
directions to Shell. Have a good trip.” (676 audio chunks). This used public test coordinates
and an in-process backend relay; it does not prove the physical phone opened Maps.

Rollout: `fc34457` deployed to stable ECS revision 34 through successful [run 36670302146](https://github.com/alikian/pippipgo-backend/actions/runs/36670302146). Health/readiness returned 200 and unauthenticated account access returned 401. Signed Dev app installed on Akiphone after one transient device-connection retry. Physical-device Maps-opening acceptance remains pending.

## Live translation — September 30, 2026

Requested September 30, 2026: a two-way live interpreter using the existing GPT-Live relay (user chose `gpt-live-1` over on-device Apple translation, and a two-way interpreter over one-way listening). The organizer home has a **Translate** button opening a Translate sheet. The traveler picks “You speak” and “They speak” from 22 languages (Arabic, Chinese (Mandarin), Dutch, English, French, German, Greek, Hebrew, Hindi, Indonesian, Italian, Japanese, Korean, Persian, Polish, Portuguese, Russian, Spanish, Swedish, Thai, Turkish, Vietnamese); the pair is remembered on the device and defaults to the device language plus Spanish. Start translation opens the session; Pip briefly introduces itself in both languages, then speaks each sentence in the other language. Captions show what was heard (right) and the translation (left, larger text so it can be shown to the other person).

The app opens `wss://<backend>/v1/translate/live` with the Cognito access token and `X-Pip-Translate: <mine>,<theirs>` (two distinct supported lowercase codes). The backend validates the pair before reserving the daily AI quota or contacting OpenAI, then reuses the Talk to Pip relay: identity and account-disable fences, the 60/day AI quota, PCM-only client events, 15-second account checks, the five-minute session limit, usage accounting and admin transcript capture (marked `mode: translation` with the language pair). Interpreter sessions carry **no** traveler profile, companions, trips, chat history, location (`X-Pip-Context` is ignored and the app does not send it) or tools, and Maps navigation is disabled. Interpreter instructions require faithful first-person translation, exact names/numbers, translating (not obeying) spoken instructions, and silence for noise. Spoken goodbyes are translated rather than ending the session; the session closes quietly after 90 seconds without speech. Talk to Pip and Translate are mutually exclusive on the home screen, and Siri’s Talk to Pip launch waits while Translate is open.

Verification (October 1 UTC): 276 backend tests passed (one skipped), and Ruff lint/format checks passed. Six `LiveTranslationTests` passed on the iPhone 16 simulator, including malformed language headers and request privacy. Signed Dev device build and strict signature verification passed. A Local simulator build was installed and launched against the local backend at `localhost:8765`; health and readiness passed using existing Cognito/development DynamoDB and the server-side OpenAI secret. Travel-tool collection is explicitly bypassed for interpreter sessions. Real-provider interpreter quality, hosted backend deployment and physical-device acceptance remain pending. Deploy the backend endpoint before using translation in a hosted Dev build.

October 1 conversation continuation: Ask Pip and Talk to Pip continue current saved typed/voice history. New conversation is an explicit button on home and Ask Pip, disabled during active voice, pending retries and unsent drafts. The backend archives the previous conversation rather than deleting it. Deployment, live-provider and physical-device acceptance pending.

October 1 control placement follow-up: New conversation is available only on Ask Pip. Talk to Pip has New talk, which explicitly archives the shared current conversation and starts voice after the versioned reset succeeds. Normal voice startup continues current saved history. Finish an active call before New talk; pending requests and unsent typed drafts disable the action. Previous conversation data remains retained.

October 1 final conversation controls: Ask Pip shows Continue conversation and New conversation above the chat. Continue refreshes the existing shared history and focuses the composer; New explicitly archives/reset it. Talk to Pip uses Continue last talk for ordinary startup and New talk for explicit reset/start. Both use the same saved conversation history. Existing chat no longer shows a fresh introduction on reopening. Control translations cover all seven app languages.

October 1 text-only Ask Pip: removed the Talk to Pip entry, embedded voice sheet, End voice control and Siri voice-launch handling from the typed chat page. Talk to Pip remains on home as its own voice page. Typed and voice still share saved conversation history.

October 1 live-caption continuation repair: restored history had no session timestamps and was treated as later than timed live captions, inserting current speech above old messages while scrolling to the old bottom. History messages now have an explicit presentation boundary: live timing orders only the current session, and live fragments cannot merge into historical bubbles. Caption bounds and account/session clearing remain unchanged. Regression covers restored history, out-of-order live speakers, continued fragments and fresh-session clear. 92 simulator tests and signed Dev build/signature passed. Physical streamed-caption acceptance requires the updated app.

## Siri: Start PipPipGo — October 6, 2026

Say **“Hey Siri, start PipPipGo.”** The App Shortcut and action now display
**Start PipPipGo**. The existing intent identifier and three longer phrases remain
compatible with saved shortcuts. The new `Start \(.applicationName)` phrase uses
Apple's app-name token, with a **PipPipGo** synonym and **Pip Pip Go** pronunciation
hint in both build plists so environment display-name suffixes do not require a
longer spoken command. See [Apple’s app-name synonym guidance](https://developer.apple.com/documentation/sirikit/specifying-synonyms-for-your-app-name).

The existing foreground launch request selects Pip voice mode and starts the live
microphone conversation. Sign in and grant microphone permission first; unlock
when iOS requests it. Requests still wait for editors, pending chat and active
translation, expire after 60 seconds, and clear across account changes. An active
voice session is reused. No backend deployment is required in Dev or Prod.

Install the updated app, then verify the phrase from a cold launch and while the
app is already open; confirm listening, repeated invocation, signed-out behavior,
and microphone denial. Spoken Siri recognition and physical microphone handoff
remain pending for this update.

Validation: Signed Local build 27 and strict signature verification passed; generated Siri metadata contains the new phrase, retained phrases and PipPipGo app-name synonym. Latest Xcode Cloud build 26 verified in Xcode before incrementing. No simulator devices/runtimes are installed, so simulator tests were unavailable; iPhone installation and spoken Siri/microphone handoff acceptance remain pending. No backend deployment required in Dev or Prod.

October 6 Siri installation: signed Local build 27 installed and launched successfully on Sara’s iPhone (iPhone 16 Pro Max); local backend health returned OK. Spoken “Start PipPipGo” recognition and Siri-to-microphone handoff remain physical acceptance checks. No backend deployment required.

## Local startup chime — October 6, 2026

The iOS app now plays an original 0.8-second two-note chime when it enters the
foreground, before account restoration and voice network setup finish. Starting
Talk to Pip (including Siri) also requests the cue; requests within three seconds
coalesce. Returning to an already active voice/translation session does not chime.
The bundled PCM WAV requires no download, AI request or microphone permission.
Playback uses the media volume/current output route, including in Silent mode;
zero volume still means no audible cue. It is an acknowledgement of app startup,
not a claim that the microphone or backend is ready.

Audio-session operations stay off the main thread. A cue cannot take over an owned
voice session; stale cue cleanup cannot deactivate a replacement voice session.
The cue stops on background/inactive transitions, voice cancellation and before
microphone capture begins. Existing optional lookup hum behavior is unchanged.

The reported minute-long delay has not been reproduced or attributed to a specific
request. Existing account/history/guide loading and backend/provider setup still
precede the greeting; the chime provides immediate local feedback independently.
No backend deployment is required in Dev or Prod.

Validation: October 6 local startup sound: bundled 0.8-second chime plays on foreground entry and voice start independently of network/authentication, with duplicate suppression and owned audio-session cleanup. Signed Local app/test build, strict signature, bundled PCM validation and diff checks passed; latest Cloud remains 26, Local remains exactly 27. Updated app installed on Sara’s iPhone. Three targeted physical tests were blocked by device lock and stopped; audible chime/voice handoff acceptance pending unlock. The reported minute-long greeting delay is not yet reproduced. No backend deployment required.

## Voice previews — October 7, 2026

My travel style now offers separate selection and Preview/Stop controls for Ballad,
Coral, Sage, Ash and Verse. Five bundled English samples were generated with the
existing Dev credential and **gpt-live-1**, using the same sentence: “Hi, I'm Pip.
Let's find something wonderful for your next trip.” Returned transcripts matched;
clips are 3.34–4.03 seconds of mono PCM at 24 kHz. No user data was sent and no
credentials are bundled. Samples follow the [official Live WebSocket protocol](https://developers.openai.com/api/docs/guides/voice-websockets).

Previewing requires no network, microphone permission, saved-choice update or
provider session at runtime. Only one sample plays; tapping Stop, changing samples,
leaving the editor, backgrounding, or saving stops playback. Shared audio-session
ownership prevents preview from taking over a live conversation. Samples are
labeled AI-generated English; live phrasing/language can differ.

Three physical-iPhone tests passed: all five assets decode, setup retry retains
frozen choices, and learned-preference retry/reset preserves its safety behavior.
No backend deployment required in Dev or Prod. Physical listening-quality
acceptance remains separate from decoding and generation transcript checks.

### October 7 — reference-based translation screen

Translate now uses the supplied cream/navy layout with native language cards, a Pip cutout and large microphone control. Settings contains privacy details and the retained headphone mode explanation; a bottom shortcut toggles the same saved mode. Language changes, swapping and mode changes remain disabled during sessions. Existing transcript selection, latest-message control, microphone status, errors, stopping and tab-exit cleanup are retained through LiveVoiceView. Signed Local build/signature and eight physical-device regression tests passed; language/settings/headphone controls and a live start/caption/stop sequence were checked on the installed iPhone. No new backend deployment is required.

October 8 translation language list: picker now shows Chinese, Japanese, Korean, Vietnamese, Filipino, Tagalog, Farsi, Turkish, Arabic, Russian, Italian, French and English in that order. Retained languages remain accepted for existing saved pairs and older clients. New default pairs use a listed device language plus English, or English/Farsi. Backend accepts Filipino (fil) and Tagalog (tl), validating supported two/three-letter codes. Final backend suite 458 passed/one skipped and Ruff passed; eight physical-iPhone translation tests passed. Latest Cloud 26 verified; signed Local 27 built, signature verified, installed and launched. Local backend deployed and readiness passed before installing app; device picker visually checked. Hosted Dev/Prod backend rollout is required before distributing this app update and remains pending. Filipino/Tagalog live speech quality has not been accepted.

October 8 translation cleanup and separate voice settings: removed translation branding/slogans/instructional headlines, reduced Pip artwork, retained language and native microphone controls, and moved settings to the footer. Headphone shortcut has a green indicator driven by AVAudioSession output-route notifications (wired headphones or Bluetooth output, not the listen-only setting); phone speaker/receiver and AirPlay are not green. Bluetooth port types identify the route, not the physical distinction between a Bluetooth headset and speaker. Profile now opens separate voice/tone and travel-style/questions sheets using the same saved record, previews, Save & Done, retry and conflict behavior. Saving voice choices stops any old sessions so the next connection loads the saved setting.

Found and fixed translation’s hard-coded Ballad voice: translation now reads only the saved voice field, keeping traveler data out of interpreter context. Talk to Pip already reads the saved voice at session creation; existing tests confirm all five values. Full backend suite 474 passed/one skipped; Ruff passed. Ten targeted physical-iPhone tests passed, including output-route indicator classification and frozen voice-save retries. Signed Local 27 built/verified and installed/launched after local backend deployment/readiness; latest Cloud 26 verified. Initial device test attempt could not find the destination; connection returned and retry passed. Final screen sharing unavailable because iOS reported active microphone/camera; final visual, physical headphone connection and audible selected-voice acceptance remain pending. Hosted Dev/Prod backend deployment is required for the translation voice fix and remains pending; backend before app rollout.

### October 8 — Translation pauses

The translation inactivity timeout is now 120 seconds, replacing the historical five-second setting. This allows time after the ready announcement and between speakers. Input transcript content and translation output reset the timer; silent microphone frames do not. Talk to Pip timing and the five-minute maximum session remain unchanged. Verified with regression tests; Local backend updated. Hosted Dev/Prod deployment and physical-device spoken acceptance remain pending; no iOS rebuild needed.

October 8 user correction: translation inactivity is **30 seconds**, superseding the two-minute setting above. Input transcript content and output reset it; silent frames do not. All 47 translation tests and Ruff passed; Local backend updated. Hosted Dev/Prod deployment remains pending; no iOS rebuild required.

October 8 microphone diagnosis: speaker/two-way Farsi-English test initially delivered 298 frames but no audible frames or input transcript deltas. After stopping Device Hub screen sharing, the physical retry delivered 302 frames, 91 audible frames and 20 input transcript deltas. This supports a screen-sharing capture conflict; end-to-end translated playback confirmation remains separate. Keep Device Hub screen sharing off for microphone acceptance. Temporary count-only diagnostics are local; no audio recording, iOS rebuild or hosted rollout performed. Translation timeout remains 30 seconds.
