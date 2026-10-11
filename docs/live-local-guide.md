# Live local guide — phase 1 (iPhone)

Opt-in from the Pip tab ("Live local guide" suggestion) or Profile → Nearby, where the one setting
lives: Quiet (must-sees only), Normal (must-sees plus notable places matching explicit interests),
Tour Guide (everything notable, more often). Runs only while the app is in the foreground with
While Using location permission; background "Always" location is phase 4.

- `LiveGuideEngine.swift` — pure decision logic, unit-tested in `LiveGuideEngineTests.swift`:
  fixes worse than 50 m ignored; speed picks walking (< 5 mph), city driving, or highway (≥ 50 mph);
  on foot, notable places need a 20-second stop within 45 m, must-sees speak within 125 m without a
  stop, parks/areas speak on entry; driving announces what is 18 s (30 s on highway) ahead within
  200 m (400 m) of the path, with left/right; one unprompted mention per 3.5 min on foot (Quiet 5,
  Tour Guide 100 s; must-sees may break it after 45 s); nothing is mentioned twice; clusters become
  one grouped mention; "what's this?" returns the 2–3 nearest with sides.
- `LiveGuide.swift` — Core Location feed, one `/v1/guide/nearby` lookup per area, delivery and UI.
  During a Talk to Pip session the mention is sent on the voice socket and Pip speaks it in her own
  voice; otherwise `/v1/guide/mention` returns the sentence and the iPhone's built-in voice reads it
  (system audio session, so Talk to Pip's session is untouched). Translation sessions are never
  interrupted. Mentioned place IDs persist per account and are cleared on sign-out.

Backend contract and sources: backend `docs/live-local-guide.md`. Backend deployment must precede
the app rollout.

Validation status (October 8): the signed Local build compiled (after splitting one slow
type-check expression in `whatsThis`) and launched on Sara's iPhone. `LiveGuideEngineTests` have not
been run yet; run them with ⌘U before relying on the thresholds. 21 new UI
strings were added to the catalog in all 13 interface languages; the three catalog checks pass.
Physical walk-test in San Diego (Balboa Park / Gaslamp) is the phase 1 acceptance.

## Field test runs

Settings for every run: Live local guide on, Normal, app in the foreground, Dev environment.
Note for each mention: time, place, whether it felt right, and anything missed or wrong.

1. **San Diego — Balboa Park (walking).** Cabrillo Bridge → El Prado → Plaza de Panama. Expect an
   entry mention for the park, one mention when you stop in the plaza (grouped with 2–3 museums),
   and silence for at least 3.5 minutes after it. Try "What's this?" in front of a museum.
2. **Carlsbad (October 8 afternoon; walking, then driving).**
   - Walk Carlsbad Village: State Street → Carlsbad Village Drive → the seawall above Carlsbad
     State Beach. Stop 20+ seconds near Alt Karlsbad (the Hanseatic house by the original mineral
     spring) and try "What's this?" there. Expect few, well-spaced mentions; minor shops stay quiet.
   - Drive Carlsbad Boulevard south toward Batiquitos Lagoon (city driving): expect "coming up on
     your right/left" announcements 15–20 seconds ahead, only for notable or must-see places.
   - Optional: I-5 past Legoland California (highway): must-sees only, about 30 seconds ahead.
   - Passenger operates the phone while driving.
   - Try once with Talk to Pip open to hear the mention in Pip's own voice, and once without.

## October 9 — decluttered main page

User request: the Pip page was crowded. Live Guide is now its own bottom tab (Pip · Live Guide ·
Translate · Profile) holding the "What's this?" card and the settings; the Language tab moved to a
globe menu at the top of the Pip page, replacing the "PipPipGo" title. Place cards show large
call / website / map icons instead of the phone number, full URL and "Source: Google Maps" text;
only the photographer's name stays under photos. Typed replies use 📞/🌐 icon links and no source
notes (backend prompt). Built and launched in the iPhone 17 simulator (Local scheme); layout not yet
visually reviewed. Full Test navigation updated for the new tabs and top language menu.

## October 9 — map-first Live Guide tab

The tab now opens straight to a full-screen map instead of a settings list: the traveler is a large
walking (or car) figure with pulsing green rings while the guide runs; must-see places are orange
stars and notable places blue pins. One large round button starts and stops the guide (▶ green /
■ red, labelled Start/Stop), flanked by "What’s this?" (binoculars) and recenter (location arrow).
The chattiness setting is a strip at the top using speaker-volume icons (1/2/3 waves); the info
button opens the full settings and privacy note. Pip's latest mention appears as a card above the
buttons. Built and launched in the iPhone 17 simulator; visual review pending.

Translation catalog: Xcode rewrites `Localizable.xcstrings` into its own key order on every build,
and it now extracts "%@ saved details · Review & edit" instead of the stored "%lld" key. The catalog
is kept in Xcode's order with translations for both keys, so builds stop producing large diffs. The
first commit carries a one-time reordering diff.

## October 9 — zoo test: silence and no microphone

Field report: at the San Diego Zoo the Live Guide said nothing and offered no microphone. Cause of
the silence: the phone ran the Local scheme (backend on the Mac, unreachable outside home) and the
live-guide backend was not yet deployed, so no places were found. Fixes:
- Pressing Start now always produces speech: Pip names the area you are in (zoo, park) or the best
  notable place within 250 m, ignoring the stop rule and talk budget; otherwise it says it is
  looking around.
- If the PipPipGo backend can't be reached, places come from Apple Maps points of interest (zoo,
  aquarium, museum, park, stadium, theater, beach...) and Pip names them in the iPhone voice.
- A microphone ("Talk") button beside Start opens a Talk to Pip conversation without leaving the
  map; Pip's live words show over the map, and guide mentions use Pip's own voice meanwhile.
  Leaving the tab ends that conversation.
New engine test covers the zoo case. Not yet compiled (Xcode was minimized during the change).

## October 9 — inside venues (zoo exhibits)

While the traveler is inside a notable area (zoo, park, campus), places inside its boundary are
treated as notable and matching their interests, so exhibits Google ranks as minor (an elephant
habitat, a skyride) are mentioned when the traveler stops at them. Inside a venue the talk budget is
2 minutes on Normal (5 Quiet, 75 s Tour Guide), exhibits are described one at a time, and the
mention carries `within` (e.g. "San Diego Zoo") so Pip talks about the exhibit itself rather than
re-introducing the zoo. Exhibits only appear when Google lists them nearby; the Apple Maps fallback
has the venue but rarely its exhibits. Backend 521 tests passed, one skipped; new engine test
`insideTheZooExhibitsAreMentionedAsPartOfIt`.

## October 9 — announcements by text-to-speech, live voice only on request

Cost decision (user): the Live Guide must not keep a per-second live voice session open.
Announcements now come back from `POST /v1/guide/mention` with `audio: true` as an MP3 in Pip's
selected voice, made by OpenAI text-to-speech (`/v1/audio/speech`, model `gpt-4o-mini-tts`,
configurable via `PIPGOGO_OPENAI_TTS_MODEL`; Ballad/Coral/Sage/Ash/Verse are supported). Short
lines with no place behind them use `POST /v1/guide/speech`. Nothing listens: no microphone, no
socket. If speech fails, the text still arrives and the iPhone voice reads it. Daily cap 300 speech
requests per account. Per OpenAI's terms the app discloses "Pip's voice is AI-generated" in the Live
Guide info panel and the response carries `voice_disclosure`.
gpt-live starts only when the traveler taps Talk on the Live Guide; switching into or out of the Live
Guide tab ends any open live session. Note: the Pip tab still opens a live voice session on launch
(the spoken welcome) — a separate cost lever, unchanged here.
Backend 525 tests passed, one skipped; Ruff passed. Text-to-speech not yet called live from this
environment. Source: https://developers.openai.com/api/docs/guides/text-to-speech

## October 9 — simpler controls and two-mile mapped walks

Live Guide uses text Start/Stop controls without playback symbols. Talk keeps a microphone
icon while the conversation is active; no mute symbol is used. The backend prompt and guide
greeting describe the map's traveler marker, orange must-see stars, blue notable pins, and
blue walking route/red destination flag with time and distance. Walking destinations are
filtered to two miles (3,218.688 m); actual route length must also fit that limit. Missing
route geometry, distance or duration produces an unavailable result rather than an invented
walking estimate. The map is a route preview, not continuous turn-by-turn navigation.

Local backend restarted and readiness passed. Hosted Dev/Prod deployment is pending and must
precede hosted app rollout. Cloud build number could not be verified because App Store Connect
is signed out; local validation keeps the existing number and is not a release-number claim.

Validation: 538 backend tests passed, one skipped; Ruff lint/format passed. All 13 walking
direction tests and 17 Live Guide simulator tests passed. Existing Swift Testing assertions
were adjusted to evaluate mutating engine calls before the macro, resolving compilation failures
without changing their expectations. Signed Local build 30 and strict signature verification
passed. No physical-device install or live provider walking-route acceptance was performed.

## October 9 — conversation from where you are, walking directions, cleaner screens

Field report (San Diego Zoo): asked "take me to the penguins", Pip described SeaWorld; the screen had
a separate mute/talk button next to Start. Changes:
- Start opens a conversation that begins from the traveler's position: the phone sends the venue it
  is inside and the nearest places (`X-Pip-Guide`), and Pip's first sentence says where they are
  and asks where they want to go. While talking, the phone keeps sending its latest position and
  venue (`guide.shortlist`), so tools use where the traveler is now, not where the call began. The
  live session still closes itself after silence; Stop ends everything.
- New `walking_directions` tool (typed and voice): searches near the traveler, inside the venue when
  known ("penguins San Diego Zoo"), rejects matches beyond 5 km, and asks Google Routes for a WALK
  route: walking minutes, distance, first steps, polyline. Voice sends `pip.route`; the map draws
  the route with a destination flag and a "🚶 9 min · 640 m" card. Prompt: "location first" rule.
- One big Start/Stop button; a single labelled pill "Tap to talk" / "Listening… tap to end"; the
  separate binoculars and mic buttons are gone ("what's this?" is now asked by voice).
- Repetition removed: Pip-page shortcut chips (duplicated Trips, Translate and Live Guide), Profile
  "Plan a trip" and "Nearby" tiles, name/home city/hobbies in Travel style (already in Profile), and
  the on/off switch and picker in the Live Guide ⓘ panel (now a legend plus privacy note).
Backend 533 tests passed, one skipped; Ruff passed. iOS built and launched in the simulator.

## October 10 — plain-language guide frequency

Replaced the speaker-wave selector with “How often should Pip talk?” and a menu of
“Only major highlights”, “Occasionally”, and “Often”. The current choice and a short
explanation are visible on the map while the guide is enabled; the control is hidden
after Stop and is not added to ordinary chat. The info panel uses the same choices.
Saved raw values and all existing timing/selection rules are preserved. Labels support
Dynamic Type, VoiceOver and all 14 interface language resources. The new startup
intent conversation and spoken preference-setting remain separate, unimplemented work.

Xcode Cloud showed successful build 30; local version is now 31. No backend deployment
is required for this UI change. Existing guide backend rollout remains separate.

Validation: Local build 31 passed for the iPhone 17 simulator and signed generic iOS device; strict device signature verification passed outside the sandbox. All 17 existing LiveGuideEngineTests and all three catalog checks passed. Simulator UI inspection confirmed the frequency menu appears after Start, lists all three named choices with a selection checkmark, and hides after Stop. Physical-device installation, exhaustive Dynamic Type/RTL visual checks and spoken preference changes were not performed.

## October 10 — tour mode and preferences before Start

The speaking-frequency menu is now available before, during and after a tour, including
in the info panel. Added labelled Walking tour / Driving tour buttons with person/car icons.
The map marker matches the explicit choice and can be tapped to switch modes. MapKit's
cached user annotation is refreshed on mode changes while retaining the camera binding.
The mode is saved locally and resets to walking on account reset. Driving remains driving
at traffic lights; speed still distinguishes city/highway driving. Switching cancels stale
guide requests/speech, clears old stop/area observations and a walking route when entering
driving, refreshes the candidate area, and preserves mention history and talk budget.
All three new labels have all 14 interface language resources.

Validation: Cloud build 30 rechecked; local version remains 31. All 19 guide simulator tests
(including two new mode regressions), three catalog checks, simulator and signed device builds,
and strict signature verification passed. Simulator inspection verified changing frequency
before Start, both named mode buttons, persisted driving selection after relaunch, immediate
car/person marker updates and switching by tapping the marker. Original simulator speaking
preference restored and guide left stopped in walking mode. No physical phone install or
backend deployment; no Full Test. This UI/engine update requires only an app update; previous
hosted guide backend rollout remains separate.

## October 11 — simplified Live Guide screen

Redesigned under the new design rule (simple, clean, for all ages and cultures). The map stays
full screen with one bottom panel: status, what Pip is saying, and one large main button — Start
when off, Tap to talk while running — with a smaller Stop below it. The top holds only the Walking
tour / Driving tour choice and a settings button; recenter is a round button above the panel.
“How often should Pip talk?” (each choice with its explanation), the Pip/iPhone voice indicator and
privacy notes moved into settings. Buttons use white on navy for contrast in light and dark mode,
text uses system colours, “Read more” is a labelled button, nearby alternatives are full-size
buttons, and status messages carry icons. Existing strings only; no catalog changes. Accessibility
identifiers kept; new `liveGuide.settings`.

Validation: Local simulator build passed; three catalog checks passed. Visual review of the tab,
Dynamic Type/RTL checks and a physical-device run were not performed. No backend deployment needed.
