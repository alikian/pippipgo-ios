# PipPipGo roadmap — simple travel organizer

Rebaselined September 28, 2026 to the [simple product scope](docs/simple-travel-organizer.md).

| Milestone | Implementation | Acceptance |
| --- | --- | --- |
| 1 · My Profile | Name, age, home town, optional interests/notes; saved edits | Source implemented; device acceptance pending |
| 2 · Companions | Add/edit/delete reusable companions; referenced-person deletion protection | Source implemented; device acceptance pending |
| 3 · Trips | Traveler selection, ordered destinations, hotel stays, plane/train/car details, edit/delete | Source implemented; device acceptance pending |
| 4 · Reliable delivery | Versioned persistence, immutable retries, conflict review and account reset | Backend/iOS checks recorded in implementation notes; Dev revision 9 deployed; phone acceptance pending |

Preserve Google/Cognito sign-in, ECS/DynamoDB, account isolation and existing data.
Keep AI credentials and GPT-6 Luna configuration (user selected September 29, 2026). Optional Ask Pip chat supports travel questions, follow-ups and revisions to chat plans. Chat messages/history and the authorized traveler profile are shared; saved companions and trips stay separate.
The prior [traveler-intelligence roadmap](docs/archive/2026-09-28-traveler-intelligence-ROADMAP.md) is historical, not an active implementation queue.

Backend deployed to `https://dev.pippipgo.com` from `e1e3d2a` through successful run [36391002936](https://github.com/alikian/pippipgo-backend/actions/runs/36391002936). ECS revision 9 is stable; HTTPS health/readiness and unauthenticated organizer protection passed. Device installation and authenticated phone acceptance remain pending.

Destination-editor crash fix: preserve the trip draft across navigation and use stable destination bindings. 49 simulator tests and signed Dev build passed; fixed Dev app relaunched on the affected simulator. Interactive/device acceptance remains pending.

Destination controls simplified: swipe-to-delete and Add opens the form immediately; ordering remains available through a long-press menu. Dev device/simulator builds passed.

Google profile photo added to home with fallback and account-switch fencing. Cognito picture mapping deployed in place; 50 iOS tests and Dev builds passed. User confirmed Google photo works. Home title and Sign out now share a compact row; Dev builds passed.

Companions moved into Profile with a compact home-card summary and in-trip Add someone. 50 simulator tests and Dev builds passed; simulator updated.

Home companion summary displays up to three names, followed by +N for additional companions. Dev device/simulator builds passed.

Ask Pip: 105 backend tests (1 skipped), 51 iOS tests, signed Dev/simulator builds and synthetic live conversation/revision/off-topic checks passed. Deployed to Dev as stable ECS revision 11 through run 36397771743; updated simulator app installed. Phone acceptance pending.

Assistant Markdown rendering added; 52 simulator tests and Dev builds passed. Optional trip budgets and estimated/actual category costs are implemented; 109 backend tests (1 skipped), 53 simulator tests and Dev builds passed. Budget API deployed to Dev through successful run 36400462253 (ECS revision 12); simulator app updated. Phone acceptance pending.

Ask Pip → review → Save: new trip drafts prefill destinations, dates, notes and budgets; existing trips stay separate. 111 backend tests (1 skipped), 54 iOS tests, signed Dev/simulator builds and synthetic live schema checks passed. Deployed through run 36401831517, ECS revision 13; simulator app updated. Physical-device acceptance pending.

Party size fix: retain adult/child counts independently of named companions, recover explicit counts in older draft notes, and show everyone in Who is traveling. 113 backend and 55 iOS tests plus synthetic inference and Dev builds passed. Deployed through run 36402973166; ECS revision 14 stable and simulator app updated. Physical-device acceptance pending.

Talk to Pip live voice: `gpt-live-1` streaming audio/captions with server-owned credentials and GPT-6 Astra delegation; bounded sessions, account fences and iOS audio cleanup implemented. 133 backend tests (1 skipped), 56 simulator tests, Ruff checks and signed Dev iPhone build passed. Real OpenAI access and synthetic audio inference passed. Backend deployment, public WebSocket verification and physical-device voice acceptance remain pending; see [live voice evidence](docs/live-voice.md).

Voice-button visibility: Talk to Pip now appears on the organizer home and in fixed Ask Pip controls; voice opens in a dedicated sheet. 56 simulator tests and the signed Dev build passed. Installation is pending coordinated backend deployment; automatic approval review requires explicit approval for the develop push/deployment. No remote mutation occurred.

Approved voice rollout: backend `c196372` deployed through [run 36521766502](https://github.com/alikian/pippipgo-backend/actions/runs/36521766502); ECS revision 15 stable, health/readiness and unauthenticated chat/voice protection passed. Signed Dev app with visible home/chat Talk to Pip buttons installed and launched on Ali’s iPhone. Physical voice conversation acceptance remains pending.

Silent-voice investigation: full relay synthetic audio/caption inference passed. Added iOS microphone-level feedback, capture-stall detection and permission/interruption lifecycle fixes; 57 simulator tests and signed Dev build passed. Update installed on Ali’s iPhone; launch blocked by locked device. Reported physical speech silence remains unverified pending an unlocked-device check.

Voice greeting: each session opens with “Hi, I’m Pip, your travel companion.” Real-provider silent-input test returned the exact greeting and audio; 133 backend tests (1 skipped), Ruff and CI passed. Deployed `ca3dfe8` through run 36523013127, ECS revision 16 stable. No app reinstall needed.

Microphone capture fixed: reproduced zero-buffer timeout on Ali’s iPhone, added an explicit voice-processing input sink, and passed the same physical capture test (0.649 s). 57 simulator tests and clean signed Dev build passed. Update installed; normal launch blocked by the phone relocking. Full spoken-conversation acceptance remains pending.

Audio-session threading: moved Talk to Pip activation/deactivation off the main thread with serialized ownership and cancellation fences; 59 simulator tests and signed Dev build passed. Device logs no longer show the main-thread warning. Capture still times out with both new and original activation timing, including after AirPods disconnection; prior one-off capture success is not reliable acceptance. Physical conversation remains unresolved.


September 29 threading fix: clean signed Dev app installed on Ali’s iPhone. Automatic normal launch failed with a CoreDevice remote-service connection error; open the installed app manually.

iPhone 16 Pro Max comparison: iOS 27.0 reproduces the full capture timeout. Minimal plain and voice-processed microphone tests pass (0.382 s / 0.841 s) using the same activation helper, narrowing the failure to the combined app audio graph. Exact cause and full conversation acceptance remain unresolved; unsuccessful graph experiments were reverted.

The comparison app was rebuilt in a fresh output directory after an incremental build had an invalid asset signature. The clean signed Dev build and signature verification passed; installed on Akiphone. Normal launch was denied because the phone had locked. Manual Talk to Pip acceptance remains pending.

Voice capture repair: physical comparisons isolated the final mixer/output connection ordering. Explicitly connect the mixer to device output after attaching Pip’s player; remove the redundant sink and read the input format after graph setup. The production capture pipeline and three sustained playback/restart cycles pass on iPhone 16 Pro Max; 59 simulator tests pass. Installed-app greeting and spoken response acceptance remains to be confirmed.

The same capture fix also passes first-buffer and three sustained playback/restart checks on iPhone 12 (focused rerun after an activation error). Fresh signed Dev build verified, installed and launched on iPhone 16 Pro Max; manual greeting/reply confirmation requested.

The verified fix is installed on both physical phones. Akiphone launched successfully; normal launch on Ali’s iPhone 12 was denied after it relocked. User confirmation of the updated Akiphone greeting and spoken reply is pending.

User accepted working voice conversation on iPhone 16 Pro Max. Voice captions now use live conversation bubbles (Pip left, traveler right), timestamp-based grouping that supports overlapping speech, bounded transient retention, automatic scrolling with a manual-history mode, and fixed call controls. 62 simulator tests plus signed Dev build/signature verification passed; light/dark previews visually checked.

The chat-bubble Dev app is installed on Akiphone. Normal launch was denied because the phone had locked; open PipPipGo manually to use the updated conversation view.

GPT-6 Luna selected September 29: typed Ask Pip and voice reasoning now use `gpt-6-luna`; audio retains `gpt-live-1`. Synthetic live structured inference and Live session acceptance passed. 133 backend tests (one skipped), Ruff and CI passed. Dev commit `de4298f` deployed through [run 36541532191](https://github.com/alikian/pippipgo-backend/actions/runs/36541532191); ECS revision 17 is steady, health/readiness return 200 and unauthenticated access returns 401. IAM unchanged; no app rebuild required. Physical-device acceptance of Luna remains pending.

Locked-screen voice: established Talk to Pip sessions now continue in the background with audio mode enabled in all app configurations. 62 simulator tests and signed Dev build passed; installed on Akiphone. Five-minute session limit and explicit/interrupt cleanup remain. Physical locked-screen speech acceptance pending.

Full traveler profile in voice: all saved name, age, hometown, interests and notes are sent without truncation at session start. 135 backend tests (one skipped), Ruff and real-provider session acceptance passed. Dev `c82188f`, [run 36542495094](https://github.com/alikian/pippipgo-backend/actions/runs/36542495094), ECS revision 18 steady; public health/readiness passed. No app reinstall needed; spoken profile recall remains a device acceptance check.

Saved trips in voice: explicitly authorized September 29; trip details now included read-only at session start. 135 backend tests (one skipped), Ruff, live synthetic Luna flight recall and signed Dev build passed; disclosure update installed on Akiphone. Backend `a066f88` deployed through [run 36543283464](https://github.com/alikian/pippipgo-backend/actions/runs/36543283464), ECS revision 19 steady and health/readiness 200. Spoken saved-trip recall on the phone remains to be confirmed.

Companion and session lifecycle rollout: companion context `9f69d87` deployed through run 36544111413 (ECS revision 20); signed disclosure update installed on Akiphone. Session presence `9ec9f06` deployed through [run 36545154254](https://github.com/alikian/pippipgo-backend/actions/runs/36545154254), ECS revision 21 steady and health/readiness 200. 142 backend tests (one skipped), Ruff and CI checks passed. Real relay silence test asked “Are you still there?” and closed at 52.3 seconds; final synthesized goodbye test gave one farewell and closed at 16.9 seconds. Physical-device acceptance remains pending.

Goodbye recognition fix: `07905fc` deployed successfully through [run 36546544327](https://github.com/alikian/pippipgo-backend/actions/runs/36546544327), ECS revision 22 steady and health/readiness 200. 157 tests (one skipped), Ruff and real-provider natural sign-off closure passed. User-specific phone recheck remains pending.

Siri Start Talk to Pip: foreground App Intent and App Shortcut implemented with automatic voice start, cold-launch handling, duplicate-call reuse, editor preservation and account reset. 66 simulator tests, signed Dev build, signature and generated Siri metadata checks passed. Physical Siri acceptance remains pending; lock-screen startup is deferred. See [Siri setup and evidence](docs/live-voice.md).

Siri rollout: signed Dev app installed and launched on Akiphone (iPhone 16 Pro Max). Spoken Siri invocation and conversation acceptance remain pending.

Siri checkpoint: user confirms Start Pip runs successfully via the Shortcuts play button. Spoken shortcut-name recognition remains unresolved; no application-code change from this diagnosis.

Conversation-start context: local time/timezone and permission-based approximate location implemented for typed Ask Pip and Talk to Pip. Account reset and immutable retry safeguards retained. Weather provider authorization remains pending; deployment and physical-device acceptance pending. See [context contract and rollout](docs/live-voice.md).

Context checks: 170 backend tests (one skipped), 68 simulator tests, Ruff, signed Dev build and signature verification passed.

Conversation-context backend deployed: `015fb65` through [run 36649006631](https://github.com/alikian/pippipgo-backend/actions/runs/36649006631). CI and CloudFormation completed successfully; ECS revision 24 is stable. Public health/readiness returned 200 and unauthenticated account/chat endpoints returned 401. 170 backend tests (one skipped), Ruff, CloudFormation validation and container smoke checks passed. No IAM/model changes. Updated iPhone app installation and physical location-context acceptance remain pending; weather remains unavailable pending provider authorization.

Admin viewer: React project `pippipgo-admin`, backend-owned typed/voice capture and exact available LLM context, read-only latest-20 inspection, Cognito verified-email authorization for `alikian@gmail.com`, Amplify deployment at `admin-dev.pippipgo.com`. 186 backend tests (one skipped), eight frontend tests, production build, Ruff, CloudFormation lint and npm audit passed. Deployed backend `618a115` through successful run 36651207096 (ECS revision 25 stable), and Amplify app `d12w50ml3j5534` job 3 at `https://admin-dev.pippipgo.com`. Live HTTPS, React/CSP rendering, CORS/auth rejection and Cognito-to-Google redirect passed; synthetic desktop/mobile transcript/context checks passed. Real admin sign-in/data acceptance remains pending. The retention disclosure passes a signed Dev build but is not installed; historical voice/context cannot be recovered.

Admin callback repair: user screenshot showed Amplify returning `/auth/callback/` with 404 while the frontend recognized only `/auth/callback`. Explicit HTTP-200 callback/logout rewrites and normalized path handling are deployed (Amplify job 4, frontend `cb67115`, CloudFormation UPDATE_COMPLETE). 13 frontend tests, build, audit and template lint passed. Live browser checks for both callback forms verify HTTP 200, retained OAuth state, PKCE verifier, canonical redirect URI and query cleanup with a mocked token endpoint. Full Google account sign-in still requires user retry.

Admin account usage extension: super-admin `alikian@gmail.com` can page across retained accounts, see Cognito email and available voice/response duration, and open transcripts/context. Backend-owned usage ledger separates typed tokens and live billed seconds/delegation tokens, deduplicates provider reports, estimates USD using versioned rates, and marks unavailable history/partial reports. Admin remains read-only. Validation: 203 backend tests (one skipped), 15 frontend tests, build/audit/Ruff/CloudFormation lint, desktop/mobile synthetic browser checks, actual synthetic Responses token usage and a final two-second Live billing report. Full real-account admin and physical-device acceptance remain separate.

Account usage rollout completed: backend `3f75075` through successful CI run 36652892167, ECS revision 27 stable; admin `1a5d26c`, Amplify job 5 succeeded. HTTPS health, deployed asset identity and live Cognito email resolution verified.

Precise location context: at the user’s request, iOS requests best available accuracy, sends unrounded coordinates plus measured horizontal accuracy, and excludes fixes older than one minute. Permission/disclosure text updated; precise access remains controlled by iOS. Optional backend accuracy metadata supports older clients; model prompt respects radius/freshness. 207 backend tests (one skipped), Ruff, 69 simulator tests and a signed Dev build with strict signature verification passed. Updated iPhone installation and actual GPS acceptance remain pending.

Precise-location rollout: backend `0c3576f` deployed through successful [run 36654620576](https://github.com/alikian/pippipgo-backend/actions/runs/36654620576); ECS revision 28 stable, one running task, zero pending, health OK. 207 backend tests (one skipped), Ruff, 69 simulator tests and signed Dev build/strict signature verification passed. The signed app contains the revised precise-location permission text. The updated iPhone build is not installed; physical GPS/permission acceptance remains unverified.

Admin currency display: estimates now round to cents (for example $0.066667 → $0.07), retaining underlying calculation precision. Frontend `dc39a87`, Amplify job 6 deployed; 15 tests, build and audit passed.

Admin layout rollout: latest working-tree layout, channel filters and j/k navigation deployed through Amplify app `d12w50ml3j5534` job 7. All 16 frontend tests, production build and npm audit passed (zero vulnerabilities). Live HTTPS index and JavaScript/CSS assets match the tested build byte-for-byte. Authenticated browser acceptance was not repeated.

Location reliability and visible field: fresh-fix acquisition now waits through stale samples/transient errors, reports capture status, refreshes missing/stale typed context while preserving retries, and displays Current location with coordinates/accuracy/time in typed and voice screens. Typed Update and permission-settings guidance added. 212 backend tests (one skipped), 74 automated simulator tests and signed device build passed; physical diagnostic is opt-in.

Deployment evidence: backend `c1940b3` through successful run 36656492499, ECS revision 29 stable with one running task and zero pending. Signed repaired app with the Current location field installed on Akiphone using devicectl. The opt-in physical diagnostic could not launch because the phone was locked; it was stopped, so no live GPS/permission result is claimed. Final focused simulator run passed all eight location/context tests after the last cleanup change.

Home location field: Current location now appears below My Profile on the home page, showing the newest typed/voice capture with Update and permission guidance. Eight focused simulator tests and signed Dev build/strict signature verification passed; updated app installed on Akiphone. No backend change required.

Nearby address display: automatic foreground refresh replaces manual coordinate/accuracy display across home/chat/voice. Native Apple lookup is cached/rate-limited, coarse locations show broader areas, and account changes cancel stale work. 78 automated simulator tests and signed build passed; installed on Akiphone. Live on-device address resolution remains unverified.

Google Places and weather: backend function tools added to typed Ask Pip and GPT-Live Responses delegation, with bounded lookups, recent-location checks, Google attribution and explicit failure states. Places API (New) enabled and API-restricted key created in existing Google project; retained AWS secret container and scoped IAM deployed through CloudFormation. 227 backend tests (one skipped), Ruff and template lint passed. The user completed secret transfer; Weather API is enabled and the key allows only Places New and Weather. Live Places, weather and typed Luna tool use passed with public test coordinates. Live relay testing with generated speech executed both real Google tools and returned attributed spoken results. ECS revision 30 is stable on Dev; health/readiness returned 200 and unauthenticated account access returned 401. The approved signed Dev app is installed on Akiphone; physical-device acceptance remains pending. See [setup and evidence](docs/google-places-weather.md).

Places/weather additional validation: live GPT-6 Luna executed the Places function with synthetic Google results; GPT-Live accepted both tool definitions. Three conversation-context simulator tests, signed Dev build and strict signature verification passed. These initial checks were followed by the real-Google and approved app-installation checks above.

Talk to Pip layout: removed the top information paragraph and nearby-address card at user request, giving the transcript the full content area. Signed Dev build/signature verification passed; installed on Akiphone. Location context still supports nearby places and weather.

Voice nearby-location regression: the reported failed session had fresh device location but the model skipped the Places tool and incorrectly claimed location was missing. Added validated session-location instructions and nearby-distance lookup guidance. 229 backend tests and a live generated-speech gas-station query passed; the real Places tool ran and returned spoken results. Deployed `9d42a88` to Dev revision 31 through successful run 36664046537; health/readiness and authentication checks passed. Start a new voice session; device retry remains pending.

Inactivity goodbye: Pip now says “I’ll end our call for now. Goodbye!” after the unanswered check-in, then allows audio playback to finish before closing. Resumed speech cancels closure. 230 tests and live silence verification passed; deployed `7c17bef` to Dev revision 32 through successful run 36664788740. CloudFormation and HTTPS/authentication checks passed; phone acceptance pending.

Road distances deployed: typed/voice tool compares Google driving distance and estimated time for up to five nearby candidates, with strict gas-station filtering and safe partial-route failures. 244 tests/Ruff and signed Dev disclosure build/signature passed. Approved Routes API enabled and key restricted to Places New, Weather and Routes. Real matrix/typed/voice mileage and driving-time checks passed; signed disclosure update installed. Deployed `3bc09e6` to Dev revision 33 through successful run 36666007388; health/readiness and authentication checks passed. New phone-session acceptance remains pending.

Visible app startup: replaced empty launch configuration with a light/dark PipPipGo launch storyboard and matching session/account loading feedback. 16 existing configuration/authentication simulator tests, signed Dev build and strict signature verification passed; installed on Akiphone. Physical cold-launch timing and visual acceptance remain pending; this change does not establish a launch-speed improvement.

Voice driving directions: “Take me there” resolves a verified place from the current session and opens Google Maps after Pip’s handoff and voice shutdown. Capability-gated for older clients; session/account fences and duplicate suppression retained. 249 backend tests (one skipped), nine simulator checks, signed build/signature and real spoken tool handoff passed. Installed on Akiphone; deployed `fc34457` to stable ECS revision 34 through successful run 36670302146. HTTPS/auth checks passed; physical Maps-opening acceptance remains pending.

Live translation (September 30): two-way interpreter via `gpt-live-1` at `/v1/translate/live`, Translate button and 22-language picker on home; no traveler/location context or travel tools. 276 backend tests (one skipped), Ruff, six translation simulator tests, signed Dev build and signature verification passed. Local simulator app installed/launched and local backend health/readiness passed. Hosted deployment, live interpreter quality and device acceptance pending. See [live voice](docs/live-voice.md#live-translation--september-30-2026).

Local iPhone translation testing: backend listener corrected from loopback to LAN at `192.168.0.156:8765`; LAN health/readiness passed and unauthenticated account requests rejected. Physical iPhone connection/translation retry pending.

Development-domain migration (September 30): deployed sign-in `auth-dev.pippipgo.com` and API `api-dev.pippipgo.com` through CloudFormation; original pool/client/accounts/data and ECS revision 35 retained. Google redirect and live sign-in, PKCE exchange, hosted API verification, refresh, revocation rejection and logout passed. API health/readiness and unauthenticated HTTP/WebSocket checks passed. Admin Amplify job 9 deployed with live asset/CSP verification; temporary old-host IAM permission removed. 276 backend tests (one skipped), Ruff, 68 iOS simulator checks, signed Local/Dev builds/signatures, and 16 admin tests/build/audit passed. Physical-device auth acceptance remains pending; existing app installations must be rebuilt. Details: backend `infra/auth-dev-migration.md`.

Dev/Prod isolation preparation (September 30): standardized `Environment=prod` and reserved `auth.pippipgo.com`, `api.pippipgo.com`, and `admin.pippipgo.com`; separate foundation/table/pool/client/secrets and environment-specific AWS names, callbacks, CORS, deployment guards and admin artifacts. Local/Dev retain existing accounts/data; Prod iOS identity is generated only from a verified separate foundation. 303 backend tests (one skipped), 54 simulator tests, 26 admin tests plus three deployment guard tests, signed Dev/Prod builds, Ruff, CloudFormation lint and AWS template validation passed. Live Dev foundation/delivery pass the new read-only preflight. **Prepared only: Prod provisioning, IAM deployment, Google/provider setup and live device/cross-environment acceptance remain pending.** See backend `infra/environments.md`; shared-account administrators and DNS remain shared boundaries.

Prod provisioned September 30: `auth.pippipgo.com`, `api.pippipgo.com`, and `admin.pippipgo.com` are live with separate pool/client/table/secrets/repository/network/roles. Prod ECS revision 1 and Dev’s guarded/tagged update are stable (one running, zero pending each); Amplify Prod app `dqy9q975h2ywb` job 2 succeeded. Real Google login, refresh/revocation/logout, organizer/admin access, exact CORS and bidirectional cross-environment token rejection passed. AWS IAM simulations confirm own-table access and other-environment denial. Generated real Prod iOS identity; signed build and eight Prod simulator checks passed. Final 303 backend tests (one skipped), 26 admin tests plus three deploy guards, Ruff and template lint passed. **Remaining launch work:** Google consent remains Testing; independent Prod OpenAI/Places secret containers are empty; physical-device/provider/load/rollback acceptance is pending. Automatic GitHub production releases remain gated until validated source reaches `main`; source changes are uncommitted. See backend `infra/prod-deployment.md`.

Prod translation recovery September 30: populated a dedicated restricted OpenAI key in `pippipgo/prod/openai` (existing OpenAI project; console expiry October 30), verified real `gpt-live-1` translation audio and `gpt-6-luna` Responses completion, and deployed readable provider-configuration errors without charging quota when the key is missing. Prod revision 2 / CloudFormation UPDATE_COMPLETE, one running task and zero pending; fresh authenticated translation and health checks passed. 307 backend tests passed (one skipped), Ruff and container smoke passed. Dev unchanged; physical iPhone acceptance remains pending. See backend `infra/prod-deployment.md`.

Xcode Cloud CI/CD (September 30): shared marketing version and automatic cloud build numbers, generated isolated Prod identity, production-only archive guards and actual archive metadata checks implemented in the iOS repository. Ten hook tests, 88 Prod simulator tests, eight fresh-checkout cloud-configuration tests, and a signed local archive/signature check passed (`1.0 (42)`; next generated test build `43`). Apple Xcode Cloud enrollment, distribution signing/upload, TestFlight delivery and physical-device acceptance remain pending; UI automation is blocked by the symlinked iOS workspace root. See iOS `docs/ios-ci-cd.md`. No paid plan or public release was activated.

iOS rename (September 30): user-requested `pippipgo.xcodeproj`, module/product, source/test folders, `com.pippipgo.ios`, build-setting names and native callback scheme implemented. 88 iOS tests, 10 CI tests, unsigned Prod archive metadata and 307 backend tests (1 skipped) passed; Ruff passed. New bundle requires fresh sign-in; backend accounts/data and old callback compatibility retained. Callback-only Dev/Prod CloudFormation change sets are prepared but not executed. Apple registration/provisioning and Cognito execution require explicit approval after automatic-review rejection; new cloud product enrollment and device acceptance pending. See iOS `docs/ios-rename.md`.

Approved iOS identity activation (September 30): both foundation stacks reached UPDATE_COMPLETE with callback-only changes and no resource replacement; old/new native authorize and logout redirects passed on Dev/Prod after propagation. Signed `com.pippipgo.ios` archive and App Store export passed; embedded distribution profile confirms explicit registration under team U47SMLD234. No App Store upload/release performed. New-product Xcode Cloud enrollment, full OAuth exchange and physical-device acceptance remain pending.

App Store validation correction (October 1): new Xcode Cloud product is enrolled and internal TestFlight group configured, but distribution failed. Local Apple validation identified missing supported orientations in `com.pippipgo.ios`. Added all four orientations in app plists and an archive metadata guard, retained test signing-team edits and restored configuration-driven display names. Ten CI tests, eight Prod simulator configuration tests and a signed archive/signature check passed; orientation build warning cleared. Apple revalidation, successful cloud delivery and iPad/device layout acceptance remain pending.

Voice selection (October 1): Talk to Pip and live translation configured for Ballad at the user’s request. Deployment and live/device acceptance pending.

App languages (October 1): English/Persian home and welcome language picker, persistent app-wide locale and Persian right-to-left layout; current organizer translations completed. Simulator and signed build validation recorded in the time log; physical-device acceptance pending. See iOS `docs/app-languages.md`.

App language extension (October 1): Japanese (日本語) and Spanish (Español) added to the existing home/welcome picker with current interface translations and packaged-resource regression checks. Physical-device acceptance pending.

App language extension (October 1): French (Français), Italian (Italiano) and Simplified Chinese (简体中文) added to the home/welcome picker, with 208 translated current-interface entries per language. Packaged-resource tests and signed build validation recorded in the time log; physical-device acceptance pending.

Home language placement (October 1): moved the language picker from the navigation toolbar into a visible first row on the organizer home, showing the current selection and available before data loading completes.

Home header adjustment (October 1): language picker moved to the leading side of the home navigation bar and PipPipGo header title removed at the user’s request.

Voice app language (October 1): new Talk to Pip sessions capture the home-page language and use it for greeting/default speech and Responses delegation, with backend allowlisting and English fallback for older clients. Deployment and live/device acceptance pending.

Conversation continuation (October 1): current typed/voice history resumes by default; explicit New conversation archives previous history through idempotent/versioned mutation. Late voice writes fenced against restarted conversations. Mocked backend/iOS validation recorded in time log; deployment and live/device acceptance pending.

Language-switch presentation repair (October 1): rebuild home List presentation on locale changes to clear mirrored rows during Persian/English switching; preserve parent account/editor/chat state. Physical regression acceptance pending.

Conversation control placement (October 1): removed New conversation from home, retained it on Ask Pip; added explicit New talk on the voice page while normal voice startup continues saved history. App/backend rollout remains pending.

Shared conversation controls (October 1): Ask Pip offers Continue conversation/New conversation; Talk to Pip offers Continue last talk/New talk. Both continue the same saved history; either New action explicitly starts fresh. Updated iOS tests/build evidence in time log; rollout pending.

Ask Pip text-only (October 1): voice entry and voice-launch handling removed from typed chat; home Talk to Pip remains a separate voice page using shared history. Updated device install pending.

Dev backend rollout (October 1): `3b275fd` deployed via run 36939509105; ECS 37 completed, CloudFormation UPDATE_COMPLETE, one running/zero pending; public health/readiness 200 and account/chat unauthenticated 401. Ballad, selected voice language and shared conversation history deployed. Prod unchanged; app installation and live/device acceptance pending.

Tab navigation redesign (October 1): the signed-in app now uses a tab bar — Trips, Pip, Translate, Profile — instead of one home list; see [navigation](docs/navigation.md). Organizer saves, retries, conflict review, chat/voice history and the API contract are unchanged. Source change only on branch `ui-redesign-tabs`: compile, simulator tests, signed build and device acceptance are all pending.

Tab redesign device acceptance (October 1): user confirmed testing on an iPhone and that the app is working fine. Overall UI acceptance recorded; device details and individual scenario coverage were not supplied. Automated redesign checks remain unrecorded.

Default-branch merge (October 1): user-tested iOS UI redesign and multilingual/shared-conversation changes merged into `develop` and pushed as `0efb8fb`; checkout now uses `develop`. Unrelated local Xcode build/cloud edits preserved.

Live-caption repair (October 1): keep restored history before current session captions so streamed speech stays visible at the bottom; prevent live/history bubble merging. 92 simulator tests and signed Dev build/signature passed; updated device installation and live-caption acceptance pending.

Apple Maps chat previews (October 2, 2026): iOS renders up to three destination snapshots from explicit supported map links in assistant messages, resolves destinations with MapKit, and opens Apple Maps driving directions on tap. Failed previews retain a directions link. Plain place names, shortened Google links, and place-ID-only links do not generate previews. Existing Google place search is unchanged. Dev simulator tests and signed build passed; live map rendering and physical-device navigation acceptance remain pending.

Apple Maps backend Dev deployment (October 2, 2026): deployed current local app/places.py, app/voice_navigation.py and prompt.md to pippipgo-dev-backend task revision 38, image sha256:9b3d1da56c4ad4e6ee30ba7438eb3115d701124b016d26e463ca3dff5461aab3. CloudFormation update and ECS rollout completed; live HTTPS /health and /ready returned 200, unauthenticated /v1/me returned 401. Python default CA verification failed locally; smoke checks passed using /etc/ssl/cert.pem and independently with curl. Prod unchanged; no live AI response or iPhone navigation acceptance inferred. iOS changes still require a new app build.


Production Google Maps repair (October 2, 2026): configured a dedicated Places New/Routes/Weather restricted key in the existing Prod secret after the retained gas-station voice session failed because AWSCURRENT was absent. Live local backend/provider checks with Prod credentials and GPT-6 Luna passed; production HTTPS health/readiness 200. No image/app deployment or Dev credential copying. Production phone retry remains pending; see backend infra/prod-deployment.md.


Translation headphone mode (October 2, 2026): shortened startup to “Ready to translate.” Added an optional saved Headphone mode toggle that translates only the other person’s selected language into the traveler’s language, staying silent for the traveler’s language; two-way remains the default. Languages/mode change only while inactive. Backend header X-Pip-Translate-Listen-Only=1 supplies interpreter-only instructions without traveler/organizer/location context. Deploy backend support before releasing the new iOS control; source validation is separate from live provider/device acceptance.


Translation direction UI (October 2, 2026): language-bar arrows now indicate two-way translation or, in headphone mode, one-way translation from the other person to the traveler; follows layout direction. Replaced swap action with a noninteractive direction indicator. Shortened headphone help and speech-sharing disclosure. No backend behavior change or deployment.


Production backend rollout (October 2, 2026): deployed manual runtime image sha256:d6a9d6f773226ea00f7df72d271e42c9de0edee4a9fe5070fb896cecc54efc6e through reviewed image-only CloudFormation update. Prod task revision 3 completed, one running/zero pending; health/readiness 200 and unauthorized account/admin/translation rejection passed. Headphone interpreter and short greeting are deployed, along with pending Maps/prompt runtime changes. 328 backend tests passed (one skipped), Ruff passed. No iOS release; headphone UI/direction arrows and physical-device audio acceptance remain pending.


Local headphone regression repair (October 2, 2026): real synthetic English audio exposed old headphone prompt translating the traveler’s speech; tightened one-way role and verified English silence plus allowed French-to-English output. Added backend mode acknowledgement and iOS fail-closed headphone startup. 328 backend tests (one skipped), Ruff and eight Local simulator tests passed; verified Xcode Cloud 17, installed Local simulator build 18 pointing to localhost:8765. User English/Persian retry pending. No cloud deployment; updated backend deployment required in Dev/Prod before app rollout.


Talk to Pip corrected-goodbye hangup repair (October 2, 2026): the retained user transcript was “No, I said Goodbye,” followed by Pip’s sign-off but no presence_goodbye event. The farewell parser now accepts explicit correction prefixes; punctuation-only late transcript fragments no longer cancel pending closure. Regression replays the exact captured fragment timings and closes after sign-off drainage, while mention/correction-resume protections remain. 333 backend tests passed (one skipped), Ruff passed. Restarted Local backend on all interfaces at port 8765; LAN health 200. No cloud deployment or app build; backend deployment required after local acceptance. Akiphone retry pending.


Local live-voice startup credit exhaustion (October 2, 2026): Akiphone reached the LAN backend, but OpenAI rejected session.start with invalid_request_error/credit_balance_exhausted. Default TLS upstream connection passed; a direct synthetic empty-account Talk to Pip startup reproduced the same provider error. No provider model substitution or billing action was performed. Added credential-free exception type/location logging and a safe explicit AI-service-credit exhaustion message instead of generic disconnect. 335 backend tests passed (one skipped), Ruff passed; restarted LAN local backend and health 200. Actual voice remains blocked until account credits are replenished. No hosted deployment; backend deployment required for this improved error handling.

- October 2: Admin conversation list USD estimates implemented and locally validated; Dev backend-before-admin deployment and authenticated browser acceptance pending.

- October 2: Conversation list estimates now separate LLM token costs (including delegation) from Voice session costs; Dev deployment pending.

- October 2: Separate conversation LLM/Voice USD columns deployed to Dev (backend revision 41 then admin job 10); hosted assets and health verified, authenticated browser acceptance pending. Prod unchanged.

- October 2: Production admin USD columns and backend 5-second inactivity/4-second reply timing deployed; full repository publication underway. CI Prod automatic-deploy gate remains disabled.

- October 2: All pending admin/backend/iOS work prepared for develop/main pushes. Current cloud build 17 verified, signed Local build 18 and 96 tests passed (one skipped). Backend Dev CI release running; Prod CI gate remains false.

- October 2: Talk to Pip brief-response prompt implemented; backend deployment and live speech acceptance pending.

- October 2: Brief Talk to Pip prompt deployed to Dev revision 43 and Prod revision 6; stable stacks/services and HTTPS verified. New-session spoken brevity acceptance pending.

- October 4: Mobile-friendly web app published at pippipgo.com/app (Prod) and dev.pippipgo.com/app (Dev), after additive Cognito callbacks and backend Dev revision 44/Prod revision 7. Organizer/chat/voice/translation/account tools implemented; synthetic organizer/isolation and live Production Google login/logout passed. Web controls English; Dev browser DNS-cache and live microphone/physical-device acceptance remain pending. See backend infra/web-hosting.md.

- October 4: Browser voice handshake and translation URL corrected, deployed to backend Dev revision 45/Prod revision 8 and both websites. Four synthetic authenticated provider-backed voice/translation sessions returned session.started with pippipgo protocol selected. 348 backend and 13 web tests passed; microphone/playback/device acceptance remains separate.

Chat Pip compact display (October 4, 2026): removed Nearby address card and display only latest two chat messages while preserving stored history and location context. Swift syntax parsing and diff checks passed. App build/install and physical-device acceptance pending; latest Xcode Cloud build number not verified, no build number changed. No backend deployment required in Dev or Prod.

Default iOS launch page (October 4, 2026): signed-in app opens Pip / Talk to Pip; prior persisted tab selection no longer overrides launch. Voice starts on explicit user action. Swift syntax and diff checks passed; app build/install/device acceptance pending. No backend deployment required in Dev or Prod; build number unchanged.

- October 4: Accepted responsive web redesign and opt-in Ask Pip/Talk to Pip browser location deployed to Dev and Prod, after backend revision 47/9 and same-origin geolocation policy. 360 backend tests (one skipped), 21 web tests, builds/lint/audit/container checks passed; four synthetic provider-backed voice/translation setups and both Google sign-in/sign-out flows passed. Live artifacts match; public/app responsive widths 320–1280px checked. Real GPS/microphone/device acceptance remains separate.

Translation header (October 4, 2026): removed top Translate title/navigation bar while retaining language controls and bottom tab. Swift syntax and diff checks passed; app build/install pending, no backend deployment required in Dev or Prod.
