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

Compact Pip header (October 4, 2026): Chat Pip / Talk to Pip picker now occupies the top navigation title position, preserving new-conversation actions and removing the second header row. Swift syntax and diff checks passed; app build/install and visual device acceptance pending. No backend deployment required in Dev or Prod.

Automatic web location (October 4, 2026): removed large location panel/buttons and request browser location on Ask Pip send or Talk to Pip start. Translation excludes location; browser permission and account-reset late-response fences retained. Privacy wording updated; 21 web tests, lint/build/audit passed. Dev/Prod website publication pending; no backend deployment required.

Web Profile/account consolidation (October 4, 2026): Profile includes companions and account controls; separate Account tab and Download my data UI removed. Account deletion confirmation/reset retained. 21 web tests, lint/build and diff checks passed; Dev/Prod website deployment pending, no backend deployment required.

Local web OAuth repair (October 4, 2026): Dev CloudFormation callbacks/logout for localhost/127.0.0.1:5173 deployed; local Dev API proxy added. Page/proxy 200 and Google redirect verified; full simulator login retry pending. 360 backend tests (one skipped), Ruff and 21 web tests/lint/build passed. No backend image deployment required; Prod unchanged.

Web sign-out placement (October 4, 2026): Sign out moved into Profile account section. Existing confirmation and account-reset handling retained. 21 tests, lint/build and diff checks passed; local preview updated. Dev/Prod website deployment pending; no backend deployment required.

Website header spacing (October 4, 2026): reduced vertical padding to 6px mobile / 10px desktop. Lint/build and diff checks passed; local preview updated. Website publication pending; no backend deployment required.

Compact website toolbar controls (October 4, 2026): reduced header language/Open app control minimum height to 34px and Open app vertical padding to 4px. Lint/build and diff checks passed; local preview updated. Website deployment pending; no backend deployment required.

Web save bar (October 4, 2026): hide idle saved state; preserve save for edits, retry and conflict review. Web lint/build/tests passed; local preview updated; website deployment pending, no backend deployment required.

Web app footer (October 4, 2026): public footer removed from /app routes and retained on public pages. Web lint/build/tests passed; local preview updated; website deployment pending, no backend deployment required.

Web translation layout (October 4, 2026): compact iOS-style language controls, direction indicator, short disclosure, centered captions and bottom start/stop button; promotional heading hidden on Translate. Browser headphone mode remains unavailable. Web lint/build/tests passed; website deployment/visual acceptance pending; no backend deployment required.

Final Dev/Prod web publication (October 4, 2026): both websites published, CloudFront invalidations completed and live app/environment/assets match verified builds. Per-environment 21 tests/lint/build/audit passed. Prod release gate enabled after verified reviewed main publication; Dev and Prod backend workflows succeeded and readiness passed. Web SSR correction d4ff79d published to both branches. Physical-device microphone/GPS acceptance remains separate.

Native-style web Pip conversations (October 4, 2026): blue user/white Pip bubbles, speaker labels, gray background and bottom voice action; voice deltas grouped by speaker. 21 tests/lint/build passed. Local preview updated; website deployment and visual acceptance pending; no backend deployment required.

Web headphone translation (October 4, 2026): one-way headphone checkbox/direction/help, browser protocol mapped to existing interpreter mode, fail-closed session confirmation. 22 web tests/lint/build and 360 backend tests (one skipped)/Ruff passed. Requires Dev/Prod backend deployment before web rollout; live device acceptance pending.

Web headphone release (October 4, 2026): source pushed to develop/main; Dev backend revision 50 and Prod revision 11 COMPLETED before website publication. Both CloudFront invalidations Completed, live app/environment/assets match validated builds. 22 web tests per environment, lint/build/audit passed. Native-style web Pip conversation bubbles included. Physical-device headphone acceptance remains pending.

Unified iOS Pip input (October 4, 2026): removed Chat Pip / Talk to Pip segmented tabs; one rounded composer has left dictation, editable draft and blue waveform live-voice action, switching to Send for text and End during a call. Shared history, explicit New conversation and Siri launch retained; dictation stops on disappearance/inactivity and cannot overlap voice. Swift syntax parsing and diff checks passed. Xcode Cloud latest number not verified; build number unchanged, full build/simulator/device acceptance pending. No backend deployment required in Dev or Prod.

## October 5 — Friendly local guide, return welcome and memory

User-selected direction: Pip is a friendly, useful, informative AI local guide and kind listener. Local implementation adds a profile-name welcome on returning after more than 30 minutes, a rolling 24-hour recap, and evidence-backed travel likes/dislikes/preferences with review/edit/forget controls. Existing profile and trip records remain separate. Translation conversations are excluded. The backend must precede the app rollout.

Backend full regression suite passed (375 passed, one skipped); final expanded memory suite passed all 18 tests; Ruff passed. Synthetic live extraction produced a grounded recap and three preferences. Signed Local app compilation succeeded; focused device tests/install remain pending a reachable, unlocked iPhone. Local backend restarted with the changes. Hosted Dev/Prod deployment pending; physical greeting and screen acceptance separate. See backend docs/local-guide-memory.md.


### October 5, 2026 — lasting recaps and personal local-guide setup

Implemented last-five useful conversation recaps without a 24-hour cutoff, voice-only return welcomes, optional personal travel stories and five voice/tone/planning choices. Added reviewed booking-receipt import into trip notes and optional on-device Apple/synced-Google calendar conflict checks/event review. Backend: 384 tests passed, one skipped; final 62 affected tests and Ruff passed; five real voice sessions accepted. Signed Local app/test builds passed; local backend restarted and healthy. Hosted deployment pending, backend before app. See backend `docs/local-guide-memory.md` for limitations and device acceptance.


### October 5, 2026 — proactive spoken profile starter repair

Fixed long voice-opening instructions (observed 15.9-second silence), generic short-return branch skipping profile setup, and Voice mode being reset to Chat. Final synthetic live test spoke in 3.7 seconds with a single interest question. Added explicit Chat/Voice selector and welcome-preparation status. Backend regression checks and signed Local build passed after updating two obsolete prompt assertions; local backend active; hosted rollout pending. See backend local-guide-memory documentation for device installation/acceptance evidence.


### October 6, 2026 — guided introduction and everyday local-guide check-ins

Added evidence-backed introduction progress, optional ten-minute consent, one-question-at-a-time continuation, group-aware interests and a clear completion transition to present-day check-ins. Live three-turn dialogue and progress extraction passed with synthetic data; 397 backend tests passed, one skipped, final 15 affected checks and Ruff passed. Local backend active; hosted Dev/Prod rollout pending. Event schedules still require verified sources; no new event feed is claimed.

### October 6, 2026 — opening-page Pip artwork

Added the user-selected seaside Pip image to the welcome and session-restoration pages. The original asset is retained intact; the view frames the illustration to exclude embedded mock controls, with native accessible sign-in and language controls. Signed Local build and wired iPhone installation passed; device visual acceptance pending. Xcode Cloud latest build number could not be verified, so the existing local number was retained for validation. No backend deployment required.

### October 6, 2026 — signed-in Pip tab visual redesign

Redesigned the active organizer PipTab (not authentication) with approved Pip artwork, warm cream surfaces, direct text/voice composer, compact history/new-conversation actions and existing trip/translation suggestions. Voice selection remains in Profile, now clearly labeled. Existing stores, API calls and navigation reused; consumer build strip removed. Xcode Cloud latest build 25 verified; signed Local 26 built, installed and launched, with signed-in physical-screen capture. Simulator runtimes unavailable; full interaction/device-size acceptance remains separate. No backend deployment required.

### October 6, 2026 — timely openers, waiting cue and contact cards

Added day-aware spoken check-ins, startup retry/cooldown and bounded GPS wait; optional quiet local lookup hum; digit telephone/web links in typed/voice captions; verified place contact cards and attributed photos. 408 backend tests passed/one skipped; Ruff and signed app/test builds passed; two contact tests ran successfully on physical iPhone. Synthetic live greeting audible at 2.26 seconds; live Google contact/photo lookup passed after bounded response-size correction. Final phone audio/launch acceptance awaits unlock. Local backend updated; hosted Dev/Prod rollout pending, backend before app.

October 6 unlocked-phone follow-up: one targeted physical microphone capture test passed; normal signed-in app relaunched and automatic voice playback confirmed by device screenshot. Local backend ready. Hum preference/quality and real tap-to-call acceptance remain separate; hosted deployment pending.

October 6 Siri start phrase: added **“Start PipPipGo”** to the existing foreground voice-launch intent, with matching action/shortcut names and app-name/pronunciation aliases. Signed Local build 27 and strict signature verification passed; generated Siri metadata contains the new phrase, retained phrases and PipPipGo app-name synonym. Latest Xcode Cloud build 26 verified in Xcode before incrementing. No simulator devices/runtimes are installed, so simulator tests were unavailable; iPhone installation and spoken Siri/microphone handoff acceptance remain pending. No backend deployment required in Dev or Prod.

October 6 Siri installation: signed Local build 27 installed and launched successfully on Sara’s iPhone (iPhone 16 Pro Max); local backend health returned OK. Spoken “Start PipPipGo” recognition and Siri-to-microphone handoff remain physical acceptance checks. No backend deployment required.

### October 6: personalized Pip backend deployed to Dev

Backend commit `7eca985d78b781c20f3086ec69459845b3431c32` deployed successfully through [Actions run 37548185465](https://github.com/alikian/pippipgo-backend/actions/runs/37548185465). Local checks: 408 passed, one skipped; Ruff passed. CI tests, infrastructure validation, container smoke check and deployment passed. Dev ECS task revision 52 runs image `sha256:19867237dae5272af4a91d11f2d9fe69ec890d04ea1ab234243f53240c637870`, matching the commit image. CloudFormation UPDATE_COMPLETE; api-dev.pippipgo.com health/ready returned 200, and me/guide/guide setup returned 401 without credentials. The backend prerequisite for the updated Dev iOS app is now deployed; hosted authenticated feature/device acceptance remains separate. Prod rollout remains pending.

October 6 local startup sound: bundled 0.8-second chime plays on foreground entry and voice start independently of network/authentication, with duplicate suppression and owned audio-session cleanup. Signed Local app/test build, strict signature, bundled PCM validation and diff checks passed; latest Cloud remains 26, Local remains exactly 27. Updated app installed on Sara’s iPhone. Three targeted physical tests were blocked by device lock and stopped; audible chime/voice handoff acceptance pending unlock. The reported minute-long greeting delay is not yet reproduced. No backend deployment required.

October 7 account deletion: Profile now offers Delete account with permanent-deletion confirmation, existing fenced DELETE /v1/me integration, private-state/voice reset, explicit unknown-outcome retry, and local-token cleanup with late-refresh protection. Signed Local app/test builds and two mocked lifecycle tests passed on iPhone; normal app signature verified, installed and launched. Latest Cloud 26 checked, Local 27. No real account deleted; disposable-account live acceptance/public app rollout remain pending. No backend deployment required in Dev or Prod.

October 7 compact learned profile: What Pip knows about you now appears as a collapsed folder/count row; expanded entries show two-line previews and explicit Edit actions with full-text editing and Delete this detail. Existing retry/conflict handling retained. Signed Local build/signature and installation/launch passed on iPhone; Cloud 26 rechecked, Local 27. Visual acceptance pending; no backend deployment required.

October 7 voice previews/profile saves: bundled actual gpt-live-1 Ballad/Coral/Sage/Ash/Verse samples, separate Preview/Stop and selection, persistent Save & Done, confirmed-save notice and unsaved dismissal guards. Three physical-iPhone tests, signed build and signature passed; installed updated Local 27 (latest Cloud 26 checked). Synthetic sample generation used Dev credentials with no user data; subjective audio/UX acceptance remains separate. No backend deployment required in Dev or Prod.

### October 7, 2026 — natural openings and explicit conversation endings

Implemented the first two approved polish steps separately. Greeting guidance uses existing context, avoids repeated openings and invented facts, respects the welcome cooldown, and retains profiling opt-outs with local-time context. Explicit end requests include “I’m done,” “hang up,” and equivalent complete commands. The existing two-second transcript-settle window protects against fragments such as “I’m done packing”; after recognition, the existing session.closed event promptly asks iOS to stop capture/playback without waiting for a spoken sign-off or provider cleanup. Shielded transcript saving remains in place. Existing iOS stop handling and startup guards were inspected; no iOS source changes were needed for these steps.

Validation: greeting phase 411 passed/one skipped; ending phase full suite 427 passed/one skipped; final affected tests 123 passed, Ruff lint/format passed. Used the existing .venv Python because uv was unavailable. Mocked integration verifies client closure precedes provider cleanup and the final user transcript is saved; tests also cover misleading phrases, fragmented transcripts and a terminal ended state. These checks do not establish live greeting quality, physical microphone/playback shutdown or device automatic-restart behavior. APIs, models and data structures are unchanged; existing uncommitted voice previews, account deletion, collapsed details and Save & Done remain preserved.

Backend deployment is required and remains pending for Dev and Prod. Deploy the backend before live iPhone acceptance; the existing iOS client understands the closure event, so no new app build is required for these two changes. Later automatic-startup, interruption verification, voice-quality and visual-cleanup work has not begun in this step.

October 7 iPhone rollout: updated the existing Local backend at 192.168.0.208:8765 and relaunched installed build 27 on Sara’s iPhone. Health/readiness passed; physical phone authenticated account, organizer, chat and guide requests returned 200 and live voice connection was accepted. No app rebuild or new build number was needed. Natural greeting quality, spoken end recognition, physical audio shutdown and restart prevention remain user acceptance checks. Local backend rollout completed; hosted Dev/Prod deployment remains pending.

October 7 expanded farewells: added end of conversation, ciao/ciao ciao, see you soon, talk to you soon/talk soon, catch you later and finish/close call variants; retained bye, bye now and talk to you later. Complete-phrase matching and the existing transcript-settle window protect ordinary mentions and continued greeting fragments. Full backend suite 450 passed/one skipped, Ruff lint/format passed using the existing .venv (uv unavailable). Local backend update completed before relaunching installed iPhone build 27; readiness, authenticated phone requests and live voice socket acceptance verified. No iOS source or build change required; spoken acceptance remains separate. Hosted Dev/Prod deployment remains pending.

October 7 polite hang-up requests: added “Can you hang up now?” and “You can hang up now,” including please/Pip suffixes, with misleading-phrase regression checks. Full backend suite 458 passed/one skipped; Ruff passed via existing .venv. Local backend deployment completed and readiness passed. Existing iPhone app needs no rebuild; relaunch was blocked by the locked device, so phone connection/spoken acceptance for this update remains pending unlock. Hosted Dev/Prod deployment remains pending.

October 7 live translation design: implemented supplied reference with cream/navy branding, transparent Pip artwork, language cards/flags and swap control, large native microphone, headphone shortcut and settings/privacy sheet. Reused the existing live transcript, start/stop, errors, microphone meter and audio interruption/tab-exit lifecycle. Latest Xcode Cloud 26 verified; signed Local 27 built, signature verified and installed on iPhone. Eight existing translation regression tests passed on physical device; no simulator runtimes available. Device visual checks confirmed language menu, settings, headphone mode on/off restored to original setting, live startup/Farsi caption and stop. Left Translate idle. No backend deployment required for this UI update; prior hosted greeting/end-command Dev/Prod rollout remains pending.

October 8 translation language list: picker now shows Chinese, Japanese, Korean, Vietnamese, Filipino, Tagalog, Farsi, Turkish, Arabic, Russian, Italian, French and English in that order. Retained languages remain accepted for existing saved pairs and older clients. New default pairs use a listed device language plus English, or English/Farsi. Backend accepts Filipino (fil) and Tagalog (tl), validating supported two/three-letter codes. Final backend suite 458 passed/one skipped and Ruff passed; eight physical-iPhone translation tests passed. Latest Cloud 26 verified; signed Local 27 built, signature verified, installed and launched. Local backend deployed and readiness passed before installing app; device picker visually checked. Hosted Dev/Prod backend rollout is required before distributing this app update and remains pending. Filipino/Tagalog live speech quality has not been accepted.

October 8 translation cleanup and separate voice settings: removed translation branding/slogans/instructional headlines, reduced Pip artwork, retained language and native microphone controls, and moved settings to the footer. Headphone shortcut has a green indicator driven by AVAudioSession output-route notifications (wired headphones or Bluetooth output, not the listen-only setting); phone speaker/receiver and AirPlay are not green. Bluetooth port types identify the route, not the physical distinction between a Bluetooth headset and speaker. Profile now opens separate voice/tone and travel-style/questions sheets using the same saved record, previews, Save & Done, retry and conflict behavior. Saving voice choices stops any old sessions so the next connection loads the saved setting.

Found and fixed translation’s hard-coded Ballad voice: translation now reads only the saved voice field, keeping traveler data out of interpreter context. Talk to Pip already reads the saved voice at session creation; existing tests confirm all five values. Full backend suite 474 passed/one skipped; Ruff passed. Ten targeted physical-iPhone tests passed, including output-route indicator classification and frozen voice-save retries. Signed Local 27 built/verified and installed/launched after local backend deployment/readiness; latest Cloud 26 verified. Initial device test attempt could not find the destination; connection returned and retry passed. Final screen sharing unavailable because iOS reported active microphone/camera; final visual, physical headphone connection and audible selected-voice acceptance remain pending. Hosted Dev/Prod backend deployment is required for the translation voice fix and remains pending; backend before app rollout.

October 8 visual Profile: replaced the industrial list with a cream photo/name/Pip card and nine colorful rounded icon tiles. All settings remain accessible through reused editors and detail screens, including voice previews/Save & Done, questions, companions, saved-detail edits, nearby address, waiting hum, language, version and confirmed account actions. Adaptive columns scale with text size; observed Companions label wrapping corrected in final build. Signed Local 27 build/signature passed (latest Cloud 26 verified), installed and launched on iPhone. Physical layout screenshot reviewed; full destination navigation acceptance remains pending because preview taps were unreliable. No new unit tests for this presentation-only change; no backend deployment required.

### October 8 — GitHub synchronization

Committed and pushed accumulated improvements to develop: iOS 0f6a0b8, backend 0fde3b1. Both branches matched origin after push; web was clean. Latest local validation remains recorded above; backend push triggers automatic Dev deployment, whose result has not been verified. Hosted rollout completion and physical acceptance remain separate. Prod is unchanged.

### October 8 — Xcode Cloud archive repair

Build 27 was canceled; build 28 compiled/exported but failed the post-build release validator because a project override named the Prod app PipPipGo Dev. Restored the existing environment-driven display-name setting (Prod PipPipGo, Dev PipPipGo Dev, Local PipPipGo Local). Latest Cloud build 28 verified before setting local fallback 29. Signed Prod build, exact release validator and codesign verification passed locally using the Cloud public identity setup; Cloud rerun and TestFlight acceptance remain pending. No backend deployment required.

### October 8 — Translation inactivity correction

Translation previously closed after only five seconds without transcript/output activity, consistent with the reported disconnect just after the ready introduction. Increased translation-only timeout to two minutes; speech/output reset it and silent microphone frames do not. Five-minute maximum session retained. Backend checks: 476 passed, one skipped; Ruff passed. Local backend restarted; hosted Dev/Prod rollout and physical-device acceptance pending. No iOS rebuild required; deploy backend before hosted acceptance.

October 8 user correction: translation inactivity is **30 seconds**, superseding the two-minute setting above. Input transcript content and output reset it; silent frames do not. All 47 translation tests and Ruff passed; Local backend updated. Hosted Dev/Prod deployment remains pending; no iOS rebuild required.

October 8 microphone diagnosis: speaker/two-way Farsi-English test initially delivered 298 frames but no audible frames or input transcript deltas. After stopping Device Hub screen sharing, the physical retry delivered 302 frames, 91 audible frames and 20 input transcript deltas. This supports a screen-sharing capture conflict; end-to-end translated playback confirmation remains separate. Keep Device Hub screen sharing off for microphone acceptance. Temporary count-only diagnostics are local; no audio recording, iOS rebuild or hosted rollout performed. Translation timeout remains 30 seconds.

### October 8 — Appium QA tooling

User-requested Appium 3.8.0 and official XCUITest driver 12.16.0 installed on the development Mac. Driver doctor: zero required fixes; optional applesimutils/ffmpeg absent. Localhost-only server started, reported ready, then stopped. Physical-device WebDriverAgent setup and app acceptance tests have not yet run. No iOS build or backend deployment required.

October 8 Appium physical-device smoke test passed: Profile opens, five voice/preview controls and Save & Done are accessible, Translate controls and 13-language menu are present, settings opens/closes. No saved selections changed. Voice playback, speech recognition, saving and destructive operations are not covered. Signed WDA helper setup completed; Appium session/server stopped. No app rebuild or backend deployment required. See iOS docs/appium-smoke-test.md.

October 8 extended Appium pass: Profile submenus and close/back flows, Ballad preview playback state, and translation connection/capture/transcript/stop verified on iPhone. Current headphone/listen-only mode remained on. Audible translated playback quality, editing/saving and destructive actions remain outside test coverage. No code/deployment change; see iOS docs/appium-smoke-test.md.

### October 8 — Reusable Full Test

Added iOS scripts/full_test.py and docs/full-test.md: on-demand safe regression coverage, persistent Appium/server/helper reuse, explicit teardown, timestamped reports and separate manual/test-account acceptance requirements. Four offline runner tests passed; the new device suite has not been executed. Runs only when requested; no scheduler or CI trigger. No iOS rebuild or backend deployment required.

### October 8 — Complete interface-language coverage

Filled missing translations across 695 UI catalog entries for the seven existing interface languages; dynamic menus, states, accessibility labels and non-SwiftUI strings follow the selected language. User content preserved. Local build 30 installed after verifying Cloud 29; signing, three catalog checks and five focused physical-device language tests passed (including six parameterized cases). Appium verified all seven core Profile/tab selections, Persian settings/RTL layout and French voice/translation settings; English restored. An older broad configuration test has stale simulator/LAN assertions, documented in iOS docs/interface-localization.md. Full Test not run. No backend deployment required; hosted Dev/Prod unchanged. Native-speaker review remains pending.

### October 8 — All 13 requested interface languages

Added Korean, Vietnamese, Filipino, Tagalog, Turkish, Arabic and Russian across all 695 UI entries. All 13 translation choices now have interface equivalents; Spanish retained as a fourteenth choice. Arabic RTL and separate Filipino/Tagalog resources verified. Cloud 29 rechecked; Local 30 rebuilt/installed. Three catalog checks, six device language tests (13 resource cases), all 13 Appium core menu/tab checks and Arabic screenshot review passed; English restored, focused tests finished. Backend voice-language mapping extended: 490 tests passed/one skipped, Ruff passed, Local restart/readiness passed. Hosted Dev/Prod voice mapping deployment remains pending (backend before hosted app). Full Test not run; native-speaker review remains separate. See iOS docs/interface-localization.md.

### October 8 — Visible backend environment

Restored the existing environment badge above primary iOS screens, showing localized Local/Dev/Production from validated build configuration (not a server-health claim). Signed Local build 30 installed after confirming latest Cloud 29; signature and three catalog checks passed. Appium verified the Local badge across Pip/Profile/Translate/Trips; Translate screenshot checked, Spanish preference preserved. No backend deployment needed; Full Test not run.

### October 8 — Language tab and Profile Trips tile

Moved app language selection into its own globe tab beside Profile; moved Trips into a larger suitcase tile at the top of Profile, reusing the existing trip list/detail/editor flow. Existing settings and saved data retained. Signed Local 30 built and installed after verifying latest Cloud 29. Physical screenshot and accessibility inspection confirmed the new bottom tabs and Trips tile; remaining navigation/language-switch checks were interrupted by device lock. Four offline runner checks and three localization catalog checks passed; Full Test updated for the new navigation but not run. Spanish preference preserved. No backend deployment required.

### October 8 — GitHub synchronization

User authorized committing/pushing accumulated localization, navigation, environment indicator, Appium tooling and translation updates to develop. Pre-push verification: 490 backend tests passed/one skipped, Ruff passed; three catalog/four offline runner checks passed. Existing signed/device acceptance evidence and outstanding checks remain as recorded above. Backend develop push triggers Dev deployment; completion remains pending and Prod is unchanged. Hosted language support requires backend rollout before hosted app acceptance. Full Test was not run.
