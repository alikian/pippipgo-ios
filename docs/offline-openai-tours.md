# Downloaded tours with Pip's OpenAI voice

## Current confirmed implementation — October 17, 2026

This section supersedes historical designs below. The user confirmed implementation after choosing
separate Apple Maps offline navigation. The [backend contract](../../pippipgo-backend/docs/offline-openai-tours.md)
describes independent Wikimedia/OSM waypoint resolution, source-only GPT-6 Luna story generation,
separate source checks, licensed image filtering and pre-generated OpenAI speech.

New downloads use version 3: accepted stop stories plus intro/completion, revision snapshots,
attribution, modification notices, exact evidence quotations, explicit silent stops and bundled
license texts. Stories and recordings carry CC BY-SA 4.0; every image retains its own license.
All declared MP3 assets, hashes, metadata and the protected durable copy must verify before
**Tour downloaded** / Ready Offline is shown. Incomplete staging is never playable. Version 2
packages and their existing road maps remain supported. New version 3 packages do not generate
prepared Q&A or require a downloaded road map. Current optional image support accepts exact
CC BY-SA 4.0, CC BY 4.0 and CC0 metadata; other images are omitted.

Sources and licenses opens saved revision/credit information and bundled license text without
network access. Excerpts are expandable. An unresolved visit is omitted with a clear notice before Start; independently located stops
without enough article facts remain silent. Essential anchors and an entirely unresolved visit list
fail preparation. Nearby OSM parking can replace the provider-selected lot; known restricted-access
lots are excluded. The configured regional OSM index is preferred for covered locations, and named
cemeteries/towers/other POIs require the expanded waypoint index. Local configuration selects a
separate 209,927-record Southern California index, retaining the original file. Hosted provisioning
and reliable worldwide waypoint coverage remain pending.

Share stories and sources exports the licensed package,
including voice/images/rights metadata, without origin or playback progress. Independently sourced
OSM waypoint coordinates have source/copyright links. Google selections remain online search hints;
Google data is excluded from downloads.

While connected, walking/driving tours, including downloaded tours, use transient Apple MapKit
routes, turn text/voice and deviation refresh inside PipPipGo. Downloaded tours route to their
saved independent waypoint coordinates without a place-name search. Directions stay in memory;
they are never added to the saved package. Losing connectivity cancels pending Apple requests
and clears the in-app route and turn prompts; saved GPS narration continues. Older downloaded
road maps appear only without connectivity. Public transit opens Apple Maps, since MapKit does not provide transit
route geometry. Uber/Lyft handoff prepares the destination; internet and user-confirmed booking are
required. Without a connection, navigation opens the separate Apple Maps app for the current leg. The user must
manually download that region there before departure. PipPipGo cannot inspect those downloads or
use Apple's offline routing engine in the embedded map. The iOS 17-compatible MKMapItem handoff
does not require a new Apple search for independently sourced offline coordinates.

Area plans combine approach driving to parking or transit/rideshare to an arrival point with a
multi-stop walking loop. Arrival requires **Start walking** confirmation. The saved tour retains
ordered points and leg modes, rather than a local road-routing graph. GPS story triggers continue
using saved MP3s without API/auth requests. Offline questions requiring new information still need
internet; no local generative fallback is added.

My Tours exposes **Start Tour**, or **Resume Tour** / **Start Again** when a checkpoint exists.
Starting from the signed-in Guide dismisses My Tours and shows the selected name at the top,
even with the panel collapsed. The account-error/offline entry keeps playback controls on the
saved-tour screen. No tour starts automatically on app launch. Stop saves progress; completion
removes the checkpoint. Account reset/late-response fences are retained.

Brief audio uses voicePrompt with ducking where supported; longer explicit stories use spokenAudio.
Calls/navigation interruptions take priority; resume follows the system's shouldResume flag and
manual-pause state. Background location/audio are configured for a foreground-started tour.
Actual screen-lock, Apple Maps offline availability, audible playback, Bluetooth/radio/CarPlay and
interruption/resume behavior require physical acceptance; a simulator background app state is not
proof of those behaviors.

Validation: 54 pure Swift tour/source/package/GPS tests passed. A live public Old Town package
contains two Wikimedia revision snapshots, two checked GPT-6 Luna stories and four coral audio
clips (1,185,408 bytes). It was imported only as a uniquely identified QA package, without replacing
existing tours. Separate simulator UI checks verify source/license access, saved-tour Start/title
and Stop/Resume choices; this imported-package run does not establish authenticated Create/Download
UI acceptance. No Full Test, cloud upload or physical acceptance is implied.

**Backend deployment is required and remains pending in Dev and Prod; deploy backend before app.**
Local uses build 113, after observing Dev Xcode Cloud 112 and Prod 102 in Xcode during this session.
No release/upload was prepared. See the final acceptance entry below for build/handoff results.

## Historical implementation and evidence

October 16 update: the backend fix removes the per-stop Wikipedia gate at the
user's request. GPT-6 Luna prepares narration for selected waypoints, including
parking and returns, with uncertainty/current-information limits. Existing package,
per-clip audio and durable-file checks stay unchanged. Local phone retry is in
progress; hosted Dev/Prod rollout is pending. The October 15 source-grounded
implementation and verification below are historical evidence.

October 15, 2026. This replaces the initial Create My Tour implementation's device-speech offline playback. Existing device-speech downloads must be downloaded again; they cannot become OpenAI audio without online preparation.

## Preparation and package

Download Offline explicitly uses the app's AI-sharing consent. The authenticated backend resolves each selected stop independently against licensed Wikipedia text, then uses the configured **GPT-6 Luna Responses API** to prepare localized introductions, stop stories, deeper explanations, transitions, two likely questions/answers per stop and completion. Source indexes accompany the generated scripts; invalid/missing references or clips fail preparation. This is grounded generation, not independent factual verification of every generated sentence. Unknown or time-sensitive claims must not be invented.

Only independently retrieved public facts, explicitly chosen tour preferences, personality and profile interests enter this prompt. Saved organizer trips and companion records do not. Selected companion categories such as family are explicit temporary tour choices. No organizer records are modified.

The app requests each clip through the authenticated backend speech endpoint, using the manifest's selected voice/personality and the existing `gpt-4o-mini-tts` configuration. MP3 files are generated through OpenAI's developer API, never recorded from ChatGPT Voice. Credentials stay on the server. Preparation shows a story/voice status, followed by clip progress and received byte size. Successful clips are staged for retrying the same tour/settings; staging is not a playable download. The staging request comparison stores a digest, not Google names/coordinates.

The version 2 package contains independent destination coordinates and ordered route waypoints, user-selected duration/return setting, mode per leg, source facts and attribution, scripts/questions, language, voice/personality/model identifiers and base64 MP3 assets with byte lengths and SHA-256 hashes. Mixed plans retain the walking point and return-to-car waypoint. Optional Commons thumbnails are included only with an accepted free license, author, source and license metadata; unverified photos are omitted. Google photos/road geometry/ratings/traffic are excluded. Supported photo licenses are currently CC BY-SA 4.0, CC BY 4.0, CC0 and public domain, with provider metadata checks.

**Ready Offline** requires all mandatory scripts and matching audio assets, valid hashes/lengths/voice/model, decodable audio and images, an atomic protected write and verification of the durable copy. Partial, corrupt and legacy packages cannot start. The prior complete download remains available if a replacement fails. Download size is actual received media size; no invented total is shown before generation finishes.

## Playback and questions

Downloaded playback uses AVAudioPlayer with a spoken-audio playback session and the normal audio output route, including connected Bluetooth headphones. It never calls OpenAI or substitutes device speech. GPS selects local clips; introductions, transitions and completion are prepared as well as stop narration. Deeper stories and prepared answers are optional. Pause, resume, repeat and skip are available in the app and remote playback controls. Interruptions and headphone removal pause playback; conversations/translation take priority.

The protected package and playback checkpoint survive process termination. Restart requires an explicit Play downloaded tour action; it restores the last story/position, route progress and elapsed budget at the saved checkpoint. No background conversation automatically starts. Local downloads remain accessible from a dedicated screen when online sign-in refresh/account loading fails; that screen exposes no server account or organizer data. Account switch, sign-out and account deletion retain their existing reset behavior and remove local packages/staging/checkpoints. Failed or refused first-time GPS permission still requires permission before GPS playback.

Offline questions use local prepared Q&A with conservative normalized exact matching, plus browsable downloaded stories and facts. Unmatched questions explicitly require internet; there is no pretend live connection or local generative answer. When a network path returns, Talk to Pip online becomes available without replacing the downloaded package; the user explicitly starts live conversation and resumes local narration afterward. A network path is not a guarantee that OpenAI is reachable.

There are **no bundled road maps or offline rerouting**. The package preserves waypoint order/GPS triggers, not turn-by-turn navigation. Available basemap tiles may be missing. Opening hours, weather, traffic, closures and other current conditions may be stale or unavailable. Original sources and license credits remain in the package and UI.

## Voice compatibility and optional on-device models

Pip's selectable API voices (`coral`, `ballad`, `sage`, `ash`, `verse`) are available through the speech API. Downloads preserve the selected name and Pip's delivery instructions/personality. Live conversation uses `gpt-live-1`; downloaded announcements use the existing speech model. A shared voice name cannot guarantee identical timbre, prosody or pacing across models; multilingual pronunciation also needs listening acceptance. There is no silent substitute voice. See [OpenAI speech voices and disclosure](https://developers.openai.com/api/docs/guides/text-to-speech) and [speech API](https://developers.openai.com/api/reference/resources/audio/subresources/speech/methods/create). The UI and generated introduction disclose AI voice; commercial deployment remains subject to the applicable OpenAI API terms and source licenses.

Apple Foundation Models was evaluated as an optional retrieval aid, not enabled: this app supports iOS 17, while on-device availability depends on newer OS/device, enabled Apple Intelligence, downloaded models, region and language. It cannot be the worldwide offline baseline, and generating a novel spoken answer would still require an unavailable prerecorded OpenAI audio clip. A later optional implementation should retrieve an existing cited answer, rather than generate unsupported facts or change Pip's voice. See [Apple availability](https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models) and [language checks](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models).

## Validation and rollout

- Live Dev OpenAI access passed: public CN Tower facts, two-hour budget, GPT-6 Luna, selected coral voice, seven MP3 clips, 3,083,520 audio bytes and 192.7 seconds of prepared speech including optional content. Every file's audio metadata decoded. No traveler records, real traveler location or DynamoDB writes were used. Optional live photo retrieval returned no accepted image; no unverified image was substituted.
- Automated results: **751 backend tests passed, 1 skipped**; Ruff lint/format checks passed. **167 iOS simulator tests passed** and **45 pure Swift tests passed**. Latest simulator validation includes ad-hoc signing, not a signed device/release build. All 19 added offline interface keys cover the 14 app language resources; pre-existing catalog entries remain unchanged.
- Mocked backend checks cover source/context/language selection, required clips, invalid references, all five voices, audio integrity metadata, provider failure, deletion fences, photo licenses/credits and mixed return waypoints.
- Simulator UI review used the real OpenAI-generated public package: opened the downloaded-tour screen without signing in, started/paused playback, inspected prepared questions, force-terminated/relaunched the app and resumed the saved tour. The sample was loaded into the isolated simulator from the provider smoke output; this was not an authenticated app download or airplane-mode test. Wi-Fi remained enabled.
- Simulator tests cover local audio playback, pause/resume/repeat/skip, prepared/unavailable questions and zero authentication/API requests from offline playback and automatic picks/weather. These use a synthetic audio fixture; they do not prove audible live-voice similarity.
- Pure Swift tests cover integrity, missing/corrupt assets, voice/model mismatch, persistence and conservative question matching, alongside walking/driving/mixed route replays.
- Physical airplane-mode download → force quit → reopen → GPS playback, actual Bluetooth controls, languages, interruptions and audible voice matching remain **pending**. Simulator/network-failure checks are not physical airplane-mode acceptance. The on-demand Full Test was not run.

**Backend deployment completed in Dev and Prod on October 15, 2026.** Source `733d2bb`, Dev revision 71 and Prod revision 20 are stable with matching images. HTTPS readiness and authentication enforcement on `/v1/guide/tour-plan`, `/v1/guide/tour-offline` and `/v1/guide/tour-offline/audio` passed in both environments. A separate public-text Prod-key speech check generated a valid coral MP3; it does not establish authenticated hosted speech or device acceptance. [Deployment evidence and rollback](https://github.com/alikian/pippipgo-backend/blob/develop/infra/prod-deployment.md#create-my-tour-and-offline-openai-narration--october-15-2026).

The backend-before-app prerequisite is now satisfied. No iOS release build number was changed, signed device release prepared or physical airplane-mode acceptance claimed. Xcode Cloud's latest build number remains unverified. Existing server-side models, secrets, identity and data were retained.

## Road map and deletion update — October 16, 2026

New downloads request a road map from the backend and verify its saved asset along
with the voice clips. The downloaded-tour detail previews the map; playing that
tour uses local road geometry on Guide with zoom/pan, street names, numbered stops,
GPS position and recentering. Existing audio-only packages keep working and must be
downloaded again to add roads. No offline rerouting/turn-by-turn directions are added.
New UI strings cover the existing 14 language resources.

A visible Delete button in tour detail uses the existing confirmation. List swipe
deletion now also confirms and disables immediate full-swipe deletion. The targeted
runner's optional `--delete` check is restricted to its uniquely named test tour;
it tests Cancel, confirmation and absence after relaunch.

Build 113 is based on Xcode Cloud build 112 observed in Xcode on October 16.
Ad-hoc simulator and signed device builds passed. No app was uploaded or released.
The signed Local 113 build was installed on Akiphone before the user moved testing
to the simulator; subsequent timeout/recovery changes are being tested on the
signed-in iPhone 16 simulator. Backend rollout is Local only; Dev/Prod deployment
remains pending and must precede updated app rollout.

## Latest October 16: multi-stop walking loop and Wikipedia downloads

Driving + Walking at an area now follows the drive to parking, every ordered walking visit
(up to four), and return to the car. Progress checkpoints retain walking stages beyond the
first visit. Preview pins, walking legs, review cards and downloaded waypoints include every visit.
Online cards show unchanged Google editorial descriptions/addresses when available.

The latest user instruction replaces LLM-generated offline stories with independently matched
Wikipedia excerpts. No Responses call generates or translates offline text. Missing articles
produce a localized notice and waypoint details; parking/return points do not need an article.
OpenAI speech generation still supplies recorded audio. New packages identify
`script_model=wikipedia-excerpts-v1` and support six waypoints / 32 clips. Downloaded details show
the full excerpt, source article and CC BY-SA license link. Existing packages remain playable;
regenerate an old tour to replace its previous generated stories. Picks have also been removed
from the Guide/Explore panel, along with automatic picks fetching.

Verification: 50 Swift guide tests passed, including multi-visit arrival/dwell progression,
current walking directions and checkpoint restoration; signed Local simulator build 113 passed.
Latest visible Xcode Cloud build was rechecked as 112 (Dev; Prod 102). Backend suite passed
812 tests with one skip. Live Google returned four Old Town visits with parking approach;
Wikipedia matched the Presidio and Whaley House, while El Campo Santo had no accepted match.
These are model/build/provider checks, not physical navigation, audible playback or complete
UI acceptance of this update. Backend rollout is required first; Dev/Prod deployment and app
release remain pending.

The verified Local build was installed and launched on iPhone 16 / iOS 18.6. Native UI inspection
confirmed Environment: Local and the Guide panel without picks. The Local API was restarted and
its health check passed. A separate live Wikipedia preparation returned 12 complete manifest clips
for the Presidio and Whaley House, `script_model=wikipedia-excerpts-v1`, with an LLM guard that was
never invoked. Audio was not generated for this final source-content smoke.

## Final Local acceptance — October 17, 2026

- The real authenticated iPhone 16 / iOS 18.6 UI created Old Town Driving + Walking, downloaded it,
  displayed completion beside Download, opened it in My Tours and retained it after relaunch.
- `Offline UI 818bac5bb1` has three walking visits (El Campo Santo, Fort Stockton and the Presidio),
  parking/return, two Wikipedia snapshots, two checked stories and four OpenAI clips. Witches Tower
  was omitted because its location could not be independently sourced; the UI shows the omission
  notice. El Campo Santo stays as a silent, independently located visit. No image passed the current
  exact-license filters. The protected saved JSON is 948,823 bytes (about 0.95 MB); audio is 661,248
  bytes. This excludes the Apple Maps download, which must cover approach, walking and return areas.
- Start/Stop/Resume, explicit Start Again, top tour name, sources/licenses, Apple Maps foreground /
  PipPipGo background and return passed on this actual downloaded package. The earlier imported
  public package check remains separate evidence. The MapKit sheet-dismissal freeze was reproduced
  and sampled, then fixed by detaching the map during full-screen My Tours presentation.
- A separate real online UI test displayed Apple MapKit turn instructions inside PipPipGo. Parking
  uses Apple's bounded nearby-POI search, rather than requiring the Google lot label to match an
  Apple venue name. GPS arrival uses the resolved endpoint for that active leg; offline GPS always
  uses its saved independent point. An unlabeled total-route distance was removed from the turn cue.
- 823 backend tests passed, one skipped; Ruff passed. 54 pure Swift tests passed. The isolated UIKit
  offline playback/checkpoint/questions/pause/resume test passed with zero authentication/backend
  calls; it uses synthetic audio, separately from the real downloaded OpenAI MP3s. Simulator and
  signed Local device builds passed. The existing UIKit checkpoint test now chooses explicit Resume.

Backend Dev/Prod deployment remains pending and must precede the updated app. The expanded local
OSM index was not uploaded or provisioned in hosted environments. No release or infrastructure/IAM
change occurred. Xcode Cloud 112 (Dev) / 102 (Prod) was observed before Local 113; its window became
unavailable for a later refresh. Recheck Cloud before any release build. Physical movement,
background/screen-lock, airplane-mode listening, multilingual sound quality and car/Bluetooth/radio/
CarPlay acceptance remain pending. The on-demand Full Test was not run.

### Connected navigation for saved tours — October 17, 2026

Downloading a tour no longer disables the embedded Apple route and turn instructions while
connected. Saved waypoints are passed directly to MapKit without a place-name lookup. Losing
connectivity cancels transient directions; downloaded narration and independent GPS progress
continue. MapKit routes and turn text are not persisted in the offline package. Fully offline
Apple navigation still requires the separate Maps app and its downloaded region.

Twelve targeted simulator tests passed, including independent waypoint resolution, no-connection
routing and saved audio/checkpoint controls. Six real saved-tour UI checks passed, including an
in-app Apple route card and turn instructions after both Start and Resume of the existing generated
Old Town QA tour. The simulator build passed; Local remains 113 after checking Xcode Cloud Dev 112
and Prod 102. No Full Test or cloud upload occurred. Physical movement/audio acceptance remains
separate. This routing correction needs no backend deployment; the broader new offline-content
backend rollout described above remains pending in Dev and Prod.
