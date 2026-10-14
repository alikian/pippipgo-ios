> Current product scope: [simple travel organizer](simple-travel-organizer.md), selected September 28, 2026. The traveler-intelligence material below is retained history; AI credentials remain configured.

# Traveler intelligence — implementation and delivery

The [source requirements](traveler-intelligence-requirements.md) replace the old questionnaire,
check-in and companion-package product sequence. Pip understands the trip, gets to know the
traveler, suggests a light plan, learns during the current journey and proposes adaptations.
**Pip never overplans.**

## Rebuilt source

The new iPhone product screens provide progressive trip intake, a Pip conversation, trip details,
import review, an accepted plan plus proposed changes, and traveler memory controls. The old
profile/companion/trip/check-in screens are removed from the target and recoverable through Git.
Google/Cognito authentication, PKCE, Keychain, refresh/revocation and account loading are retained.

The API replaces legacy product routes with journeys, memory, travelers, preferences, actions and
imports. Existing DynamoDB transaction/version/idempotency semantics, account ownership, export,
delete fence and ECS architecture remain. New product records use separate kinds; existing legacy
records are retained without being reinterpreted or deleted. No deployed data migration occurred.

A journey is a versioned aggregate containing intake, accepted optional plan, pending proposal,
conversation, temporary context, feedback and imports. Fixed commitments and confirmed import
facts are separate inputs to the planner. The provider can only propose optional suggestions.
Accept/reject requires the current proposal ID and journey version; intake changes invalidate
pending proposals. Confirmed import facts require traveler review/edit/acceptance first.

Memory has explicit/confirmed/inferred status, confidence, source, original text, timestamps and
persistent/trip-specific scope. Conversation output can atomically remember, correct or forget scoped memory alongside the
journey write. Existing IDs are required for correction/forgetting; temporary observations and
sensitive inferences are excluded. Explicit memory controls remain available.
Temporary feedback never automatically becomes persistent memory. Forget removes an item from
active use; retained idempotency receipts/export history mean this is not permanent erasure.

## Provider

User-selected model: **GPT-6 Astra via the direct OpenAI Responses API**, `gpt-6-astra`.
The backend posts to `https://api.openai.com/v1/responses`. Set `OPENAI_API_KEY` locally or
configure `PIPGOGO_OPENAI_SECRET_ID` for a JSON Secrets Manager value with `OPENAI_API_KEY`.
Hosted Dev expects `pipgogo/dev/openai` in us-west-2; Prod uses `pipgogo/prod/openai`.
The key stays on the server. Dev IAM and ECS template changes are deployed.
The user populated `pipgogo/dev/openai`; a local backend adapter successfully read it and
validated one live structured GPT-6 Astra conversation response on September 27, 2026.
A separate temporary Fargate task using deployed revision 3 also verified the runtime task
role, secret access and a live structured Astra response, then exited successfully.
Full planning/import/device acceptance remains pending. Bedrock is no longer used; its previously
accepted agreements remain active, but its account runtime calls returned HTTP 403.

Limits: 50-second provider timeout, 6,000 output tokens, 100 KB prompt, 60 AI attempts per account
per UTC day including failures, 20 imports per journey, 5 MB client attachment cap. These are
per-account controls, not an AWS-wide spend ceiling. Add deployment budgets before live rollout.

PDF/JPEG/PNG input is forwarded to the provider; DOCX text uses bounded ZIP/XML parsing. Raw files
are not saved in DynamoDB; proposed/confirmed facts, source filename and timestamps are retained.
Media extraction has mocked coverage only and still needs live model and physical-device checks.
No live weather, opening-hours, places or transport-data provider is connected.

## Deployment and acceptance boundary

The rebuilt backend is deployed to `https://dev.pippipgo.com` from commit `e0e2dc0`,
using ECS task definition `pippipgo-dev-backend:7`. The new app requires `/v1/journeys`.
Old app product endpoints are retired; authentication remains compatible. No data purge occurred.
Public health/readiness returned 200 and unauthenticated journey access returned 401.
A synthetic runtime AI task exited 0 and logged its success marker without credentials or
traveler records. This verifies provider/runtime access, not an authenticated phone journey.
The matching iOS source is published on `develop` as `1a2c9a1`; the signed Dev build is ready.
Device installation and acceptance remain pending.

Deployment run: https://github.com/alikian/pippipgo-backend/actions/runs/36379145134
Image digest: `sha256:bb4bfc4d94856e3324a7a7ec721823861ac4b907f84350ede7c6de3a8588c5ef`.
Legacy-product rollback image: `sha256:70420e259fc435ead60004180ccb67452b4acb9b2fdc4eb0e6c3957d372460c7`.
Rollback restores the prior product API and requires its matching older client.

The first acceptance journey is source section 28: four-day San Diego, partly planned; hotel and
itinerary imports; review; travelers/needs/transport; get-to-know or restored memory; light plan;
less-walking feedback; accept/reject proposed changes; account isolation. Include auth regressions,
network failures, exact retries, conflicts, language switching and denied media permissions.

Location/live context, pilot, hands-free hardware and custom wearable remain later milestones.

## Source verification

Backend: 64 tests passed, 1 skipped (DynamoDB pagination under the memory fixture); Ruff lint
and formatting passed. Browser authentication harness: 9 tests passed. iOS: 39 tests across
4 suites passed. Signed Dev build and CloudFormation template validation passed. These automated checks
cover source and mocked behavior; separate runtime evidence appears above. Device acceptance is pending.

## Added requirement — door-to-door journeys

Section 29 of the requirements adds progressive travel-mode/flight intake, upload/manual/search
entry paths, reviewed structured flight segments, outbound and return ground transfers, time-zone
aware first/last-day availability, and flight-change recalculation that protects reservations.
Implemented in source: additive `door_to_door` intake with validated flight segments, four
transfer legs, actual-airport summaries and UTC-based elapsed-time arithmetic. The initial screen
now asks destination, timing and “Anything already decided?”; flight/transfer entry follows later.
Manual flight entry, external search and confirmation uploads are available. Extracted flights
remain proposed until corrected/confirmed; reviewed direction/order replaces the matching segment.
Save recalculates transfer windows and flags accepted activity plans for review. “Save and update
activity suggestions” creates a proposal; reservations and the accepted plan remain unchanged
until deliberate acceptance. Old clients omitting the additive field preserve existing flights.

Live flight status, traffic, pickup instructions and airline-specific buffers are not connected.
Travelers enter transfer estimates and confirm buffers; missing timing remains provisional.
Ambiguous/nonexistent local DST times are rejected for airline clarification. Connecting flights
must follow the previous arrival; cross-airport connections are explicitly flagged.

Verification: 73 backend tests passed, 1 skipped; 41 iOS tests and signed Dev build passed.
A synthetic live GPT-6 confirmation extracted outbound/return EWR flights. Physical-device,
real-media and external search acceptance remain pending.

## Conversational intake

The `intake` action reuses current trip context and reviewed imports, returns a short acknowledgement
and one next question, and can set inferred planning_state without a questionnaire. It creates no
activity proposal and does not complete personality onboarding. iOS displays the latest confirmed
persistent preferred_name/nickname only; a name is never inferred from an email or companion.
The first screen is a compact summary plus one answer area. Reviewed uploads can advance without
retyping their contents. Ambiguous long-weekend dates require explicit confirmation; a suggested
Friday-based range is editable and is not asserted to be an actual holiday. Microphone/speech
permissions are requested only on Speak; audio stops on close/background and text is reviewable.

75 backend tests (1 skipped), 42 iOS tests and signed Dev build passed. A live synthetic intake
reply acknowledged a known Manhattan hotel and asked only how the traveler is getting to New York.
The isolated synthetic Sara/New York simulator preview was visually checked: compact summary, one
question, Speak/Upload/Nothing yet and visible Continue. No real account or credentials were used.
Device voice/privacy permissions and full conversational acceptance remain pending.

Dev rollout 36357597703 succeeded; CloudFormation UPDATE_COMPLETE, ECS revision 5 steady,
health/readiness 200 and unauthenticated journey access 401 were verified. Synthetic live
extraction, EWR first/last-day planning and intake checks passed; these do not prove a real
authenticated device journey.

Home greeting: uses the saved explicit/confirmed preferred name, with a neutral fallback.
“What Pip remembers” now offers a dedicated preferred-name field; saving updates both home
and trip-intake greetings. Signed Dev build passed; physical-device acceptance remains pending.

Empty trips now open Destination and timing immediately. The compact summary and Edit appear
only after a destination exists. Signed Dev build passed; device acceptance remains pending.

## Master-prompt vertical slice — September 27, 2026 PDT

[Implementation map and acceptance matrix](conversation-slice.md) document the saved conversation
controller, deterministic routing, review gates, bounded intake, inferred-memory review and plan
revision protections. Backend `e0e2dc0` deployed through successful run 36379145134; ECS revision 7
is stable and CloudFormation UPDATE_COMPLETE. Health/readiness 200 and unauthenticated journeys
401 verified. Matching iOS source `1a2c9a1` is published; signed Dev build passed.

91 backend tests passed, 1 skipped; Ruff passed. 44 iOS tests passed. Live synthetic GPT-6
extraction/review/plan/accept/feedback preserved the fixed museum and changed one evening while
retaining four suggestions. Screenshots verify the first/follow-up screen and compact iPhone SE
layout; large text was inspected. Real authenticated phone and VoiceOver acceptance remain pending.
