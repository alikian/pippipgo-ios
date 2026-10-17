# Create My Tour — October 15, 2026

## Experience

The main Guide panel offers **Create My Tour** as its primary action and retains **Explore Freely**, walking/driving tours, conversation, translation, nearby search and the existing map. A single sheet presents time, walking/driving/mixed mode and multiple mood choices. Companions, energy, walking limit, food, optional cuisine/dietary preferences, destination/direction and return-to-start sit under “Make it more personal.” Known explicit profile interests preselect matching moods; the server also reuses existing profile/preference categories. New choices do not edit the saved profile, companions or trips. Draft choices survive Adjust Tour and repeat planning.

A recent GPS fix and reliable movement heading are reused; an existing destination is reused when available. When moving in driving/mixed mode, setup offers Talk to Pip instead of requiring form interaction. Voice asks for missing essentials, submits a proposal and requires explicit acceptance before starting. Camera, microphone, location and AI-sharing permissions retain their existing consent behavior; first-time permissions still need setup before departure.

Preview shows total estimated time, highlights versus passing stories, food status, walking/driving breakdown, optional credited destination photos, Start Tour, Download Offline and Adjust Tour. Google route previews open in Google Maps through the documented Maps URL interface; they are not rendered on the Apple basemap. Google Maps may recalculate its displayed route. Mixed tour previews list the walking loop; active guidance opens the appropriate walking or driving directions. A native embedded Google map is not implemented.

## Planning and guidance

New authenticated POST `/v1/guide/tour-plan` accepts a transient origin with capture time/accuracy; 5–480 minutes; mode; direction/destination; optional round trip; moods, explicit companions/energy/food/cuisine/dietary choices; and a walking-distance limit. Destination ambiguity asks for a more specific name rather than silently choosing another city. A destination that exceeds the available time is rejected.

`app/tour_planning.py` uses a provider boundary and the existing discovery, deduplication, categories, appeal and explicit-interest ranking. Nearby Search supplies candidate destinations. Google Routes verifies candidate roads and full waypoint routes. Text Search uses `searchAlongRouteParameters` on the chosen route to supplement attractions, scenery, culture, shopping and food. Selection favors appeal, personal fit and category variety, with sunrise/sunset and available current/forecast weather as timing signals. Known closed-now and practical-only places are excluded from visits. No city-specific attraction list is used.

Greedy insertion is bounded and deterministic for the same provider results; it is not an exhaustive route optimizer. Every accepted insertion checks the **whole** route against travel + visits + parking allowance + buffer. Walking distance is a hard bound. Mixed tours require an independently routed walking out-and-back and account for that walk and its brief visit before returning to the driving anchor. The walking/driving session follows arrival, dwell/departure and return, not narration completion. The tour ends at its time budget or completed endpoint; a requested return trip remains active until returning to its origin. Unplanned city introductions and proximity narration do not displace the selected tour. Existing conversation/translation audio gates remain in effect.

Visit allowances are conservative configuration values, not verified venue dwell times: theme/water parks 120 minutes, zoos 90, aquariums/museums 60, galleries/markets 20, malls 30; ordinary short outdoor stops use 5–10 minutes. Meals allow 45 minutes, snacks 15. Unknown-duration `tourist_attraction` points are passing stories, not invented five-minute admission visits. Driving stops include a three-minute parking allowance; a legal/available space is **not** verified. The total includes a 10% buffer, at least one minute. Tour narration receives the passing/visit role and remaining time and uses the existing configured Responses model/voice pipeline. Route facts and summaries are prepared; online prose/audio is generated at delivery, not downloaded in advance.

Food is excluded when declined. Snack requests restrict candidate types; a named cuisine must come from the corresponding food query. Search relevance does not verify a menu. Dietary suitability is never inferred: unverified food is withheld and preview explains that the venue must confirm suitability. Step-free access, stairs, parking availability, admission queues, tickets, accessibility and hours at arrival are not guaranteed. User walking limits are enforced; physical accessibility needs separate authoritative data and acceptance.

## Offline

The initial device-speech exporter has been replaced by [downloaded OpenAI narration packages](offline-openai-tours.md). Preparation generates grounded personalized scripts with GPT-6 Luna and MP3 clips with Pip's selected API voice. Complete verified packages support GPS playback, saved progress, local stories/prepared answers and playback controls. Device speech is never substituted for downloaded audio. Independent Wikipedia facts and explicitly licensed Commons images may be saved; Google photos and road routes are excluded. Offline road maps/rerouting remain unsupported. The linked document records compatibility, licensing, package validation and acceptance limits.

## Limits, costs and rollout

Planning is capped at 20 requests per account/day, 12 Routes calls and a 45-second soft provider deadline (an in-flight bounded request can finish later). A full planning request can use five Nearby Searches, up to three Text Searches, current weather and forecast, plus up to two photo-details/media lookups. Wikipedia is independent; no unsupported scraping is used. Charges depend on actual API SKUs, billing region and account terms; these are not per-GPS-update calls. No provider credentials are placed in the app. Models remain `gpt-6-luna`, `gpt-live-1` and the existing TTS configuration.

**Backend deployment completed in Dev and Prod on October 15, 2026.** Backend source `733d2bb` is deployed on Dev task revision 71 and Prod revision 20 with matching immutable image digests. Both environments passed health/readiness and authentication enforcement for all three tour endpoints. The backend-before-app prerequisite is satisfied; the iOS release and physical acceptance remain separate. [Deployment evidence and rollback](https://github.com/alikian/pippipgo-backend/blob/develop/infra/prod-deployment.md#create-my-tour-and-offline-openai-narration--october-15-2026).

Xcode Cloud's latest build number could not be verified because the browser session was logged out. The checked-in build number is unchanged. Simulator validation is not a signed release build; signed builds, physical walking/driving tests, voice acceptance, GPS accuracy, offline field use and Bluetooth/headphone acceptance remain separate.

## Verification

Local results: **734 backend tests passed, 1 skipped**; Ruff lint and format checks passed. **162 iOS simulator tests passed** in an isolated device. The pure Swift replay suite passed **41 tests**. These checks do not establish physical-device or audible voice acceptance.

- Simulator UI review: verified the main Create My Tour and Explore Freely actions, selectable time/mode/mood cards and expandable personal preferences on an isolated iOS 27 simulator. Preview used ad-hoc simulator signing; no account or physical device was used.
- New deterministic backend coverage: complete-route time accounting, round trips, unavailable/over-budget routes, heading validation, closed/practical filtering, walking tolerance, food/cuisine/dietary behavior, major-attraction visit time, passing stories, mixed walking/parking accounting, authenticated transient API, explicit voice acceptance, preference forwarding and licensed offline exports/failures.
- Pure Swift simulations: walking, driving, mixed walking/return stages, offline progress, time-budget expiry and invalid plan rejection, alongside the existing international/corridor and Carmel Valley–Carlsbad guide replays.
- Live Dev-provider smoke, public Toronto coordinates: revised plan returned Roundhouse Park and Harbourfront Centre, total **1,340 seconds (22 min 20 sec)**. Nine Routes calls, two Text Searches, one discovery cycle, current weather + forecast, two photo-details/media lookups; no reported provider errors. No traveler records or AI were used for planning. This does not prove worldwide route quality, safe access or device acceptance.
- Localization: all 83 new UI keys have all 14 app language resources, including Tagalog's `fil-PH` resource. Existing user entries were checked unchanged. Remaining public-copy translations were generated with the configured GPT-6 Luna via the backend adapter; no traveler data was sent. This localization inference is separate from app/device acceptance and tour-narration inference.

Provider references: [Google search along route](https://developers.google.com/maps/documentation/places/web-service/search-along-route), [Routes waypoints](https://developers.google.com/maps/documentation/routes/intermed_waypoints), [Maps URLs](https://developers.google.com/maps/documentation/urls/get-started), [hourly forecasts](https://developers.google.com/maps/documentation/weather/hourly-forecast), [Places policies](https://developers.google.com/maps/documentation/places/web-service/policies), [Wikipedia reuse](https://en.wikipedia.org/wiki/Wikipedia:Reusing_Wikipedia_content).

## Optional area and activities — October 15, 2026

The builder now shows optional area/park and activity inputs before personal options. Blank inputs keep automatic planning. Requests carry `area` (up to 160 characters) and `activities` (up to 300); voice tools support the same fields. Area requests resolve a single place and filter every selected stop, including mixed-mode walking stops, to its provider viewport. These rectangular map bounds are approximate, not administrative boundaries. Travel from the current location and road routes can leave the bounds. Ambiguous/unresolved areas or unavailable matching experiences produce non-success instead of a broader tour. Activity text drives Places Text Search; generic along-route suggestions are disabled for activity requests. Search relevance does not verify venue offerings or availability. No organizer records are modified.

Backend deployment is pending in Dev and Prod; deploy before releasing the updated iOS app. Live area/activity provider checks and physical-device acceptance remain pending. No iOS release build number has been changed.

## Tour adjustment — October 15, 2026

The proposal has an Adjust Tour button in the navigation bar, visible without scrolling through stops. An active tour also offers Adjust Tour, opening the form with its original request. Users can change time, transport, area, activities and preferences and create a new proposal. The active tour continues until the revised proposal is explicitly started. No backend change or deployment is required for these controls.

## Tour failure feedback — October 15, 2026

Creation failures now display a localized alert and a notice above the form, retaining inputs. The app distinguishes unreachable service, expired sign-in, unreadable response, invalid details, daily limits, unresolved/ambiguous destinations, unavailable routes and insufficient time. HTTP 200 alone does not establish successful planning: the local log previously recorded a 2.6-second HTTP 200 tour request without its application result, so its exact failure reason cannot be recovered. The backend now logs `tour_plan_result` with request ID, result status, stop count and available provider diagnostics; HTTP failures log `tour_plan_error` with status and error code. Neither log includes request bodies, place names, coordinates or activity text.

Updated backend restarted locally. Dev and Prod deployment of these diagnostics remains pending; the new app error feedback works with the existing response contract. Simulator app build and Apple string-catalog compilation passed; physical-device failure feedback acceptance remains pending.

## Planning animation — October 15, 2026

While creating a tour, the builder displays a full loading view with gently floating Pip artwork, an indeterminate spinner, localized planning text and Cancel. Reduce Motion keeps Pip still and hides the spinner. The form is disabled during planning, and the loading view disappears when planning succeeds, fails or is canceled. No backend deployment is needed.

## Apple Maps preview — October 15, 2026

The tour review screen now embeds Apple Maps with the start, destination, numbered stops and mixed-mode walking stops. MapKit independently calculates each route leg with walking or driving directions; only Apple route geometry is rendered in this preview. Requests cancel when the preview closes or changes. If Apple routing is unavailable, stop pins and the review remain available with an explicit message. The backend planning budget and route validation remain unchanged, and active-tour navigation controls retain their existing behavior. No backend deployment is required. Live Apple routing/device acceptance remains pending.

### Specific mixed-mode failure explanation

Local logs recorded two `no_suitable_mixed_tour` outcomes followed by a successful two-stop tour. This status means the planner could not validate a walking loop returning to the car within the requested time and walking limits; it does not identify whether route availability or a particular limit was the blocker. The app now explains this and suggests adding time, raising the walking limit or selecting a single travel mode. Failed results now retain available provider counters/errors for diagnostics. Backend restarted locally; Dev/Prod deployment of the additional diagnostics remains pending. The app message uses the existing response status and needs no backend-first rollout.

## Adjust Tour location refresh — October 15, 2026

The builder previously relied on the location value supplied when its sheet opened; after the 120-second freshness window, Create My Tour could remain disabled during editing. The builder now owns a foreground location feed while visible, validates fresh accurate coordinates, and uses the latest fix for typed or voice planning. It stops updates on dismissal/background and resumes on foreground. A five-second freshness check keeps the button state current even without GPS callbacks. Denied/restricted access displays the corresponding existing localized message. The backend freshness requirement remains unchanged. No backend deployment is required. Physical-device GPS and permission acceptance remains separate.

## Area tours start in the area — October 15, 2026

This supersedes the earlier approach-drive behavior: when `area` is supplied, the planner uses the resolved area's location as tour origin, discovers stops within its viewport and budgets only the tour there. A return trip returns to that area origin, not the phone. Weather, sunset and route-search ranking use the area as well. The original phone location remains in the request for validation but is not a route leg. Apple Maps previews use the returned area origin, so the approach drive is excluded automatically. Generic nearby tours and explicit destination directions preserve their existing behavior. Map bounds remain approximate; roads between stops can cross them. No change to ownership, organizer data, credentials or AI model.

Local backend restarted with this fix. Dev and Prod backend deployment is pending and must precede rollout of this behavior to those environments. Existing proposals must be regenerated. Live provider and physical-device acceptance remain pending; mocked tests cover remote-origin walking/driving tours, with and without a return trip.

Live public-coordinate provider check (no traveler records): a 120-minute driving request for Santa Monica from public downtown Los Angeles coordinates returned `ok`, a Santa Monica origin, and Ocean View Park, Downtown Santa Monica, Palisades Park and Santa Monica Pier (108 estimated minutes). Provider errors: none. An initial check exposed Venice inside the rectangular viewport; matching provider locality is now required when the resolved area provides a locality, excluding that neighboring-city stop. Unknown locality is excluded conservatively. Neighborhood/park boundaries remain approximate within the matching city. Simulator app build passed. This provider check does not establish device acceptance.

## Area field keyboard freeze — October 16, 2026

The attached Akiphone Local session logged `Observation tracking feedback loop detected!` with repeated layout invalidations on the root hosting view. Pausing the unresponsive app showed UIKit safe-area updates during `TUIKeyboardTrackingCoordinator` keyboard presentation. This was a live hang; the inspected session had not terminated with a crash.

The map previously measured its own frame plus safe-area insets, stored those measurements in state, then used them to set its own safe-area padding. The map now reads bounds from an independent full-screen GeometryReader and keeps its background viewport stable while sheet keyboards appear. The tour form retains normal keyboard avoidance.

Validation: signed Local device build passed with `CURRENT_PROJECT_VERSION=109`, following latest visible Xcode Cloud Dev build 108 (Prod 102). The shared fallback version is unchanged. Physical-device typing after installing the fix and iOS 27 runtime acceptance remain pending; compilation does not prove the hang is resolved. No backend changes or deployment are required.

### Keyboard UI regression coverage

`TourBuilderUITests.testAreaOrParkTypingKeepsTourBuilderResponsive` uses the existing debug home preview, opens Create My Tour, types “Balboa Park,” enters an activity, returns to the area field, and dismisses/reopens the sheet. It checks field contents, keyboard presence and continued navigation, and retains a screenshot with the keyboard open. It does not submit a tour or use account credentials.

Passed October 16 on an isolated iPhone 16 / iOS 18.6 simulator with ad-hoc signing: 1 test, 0 failures. Result bundle: `/private/tmp/pippipgo-tour-keyboard-final.xcresult`. Unsigned simulator execution could not restore Keychain state; the signed run used the normal app entitlements. Text checks ignore keyboard-added trailing whitespace. iOS 27 physical-device acceptance remains pending. No backend deployment is required.

## Multiple transport choices — October 16, 2026

“How would you like to explore?” now offers independently selectable Walking, Driving, Ride Share and Public transport buttons, with Walking selected initially. At least one option is required. Choices are encoded in the optional `transport_modes` array and restored from draft/active requests when adjusting a tour; old requests without this field still decode. Voice handoff preserves the allowed options. The planner chooses a primary route from the allowed options rather than requiring every option to be used. Review displays that transport; ride share includes a localized pickup-allowance explanation without promising availability or fares. New strings are translated in every supported catalog locale.

`TourBuilderUITests.testTransportChoicesAllowMultipleSelection` checks that all four options can remain selected, individual deselection preserves other choices, and clearing all choices disables creation. Both this and the area keyboard test passed on isolated iPhone 16 / iOS 18.6 (2 tests, 0 failures; `/private/tmp/pippipgo-transport-ui.xcresult`). The Swift guide suite passed 46 tests, including selection serialization, old-request decoding and passenger-mode plan validation. A signed Local device build passed using build override 109, following latest observed Xcode Cloud Dev 108 (Prod 102). Physical-device and live provider acceptance for new transport modes remain pending.

Backend deployment is required before updated app rollout and remains pending for both Dev and Prod. See backend `docs/create-my-tour.md` for routing budgets and transit/ride-share limitations. No organizer-data migration is required.

Integration on current develop preserved the adaptive iPad map sidebar while measuring the independent viewport. Both tour UI tests passed again after this merge (2 tests, 0 failures; `/private/tmp/pippipgo-develop-tour-ui.xcresult`).

## Physical-device keyboard recurrence — October 16, 2026

The user reproduced the Area-field failure after the independent-viewport change. Xcode's device console identified repeated `constraints` and `corners` invalidations on `_MapKit_SwiftUI._SwiftUIMKMapView`, with `__mapkit_edgeInsetsSentinel` animations and `Observation tracking feedback loop detected!`. The earlier viewport change and iOS 18.6 simulator pass therefore did not establish a physical-device fix.

The existing Area UI test reproduced the hang on Akiphone (iPhone 16 Pro Max, iOS 27.0.1 / 24A446): it reached `tourBuilder.area`, tapped it at 12.26 seconds, then received no app event-loop idle notification and exceeded the 60-second test allowance. Baseline report: `/private/tmp/pippipgo-device-keyboard-before.xcresult`.

A full-screen presentation alone also reproduced the Area-tap hang on the unlocked phone (`/private/tmp/pippipgo-device-keyboard-unlocked.xcresult`), while its transport-selection test passed. Create My Tour now uses full-screen presentation **and temporarily removes the background SwiftUI Map from the view hierarchy** while editing. The existing camera, route and parent view state are retained; the map is restored on dismissal. The UI test additionally reopens the form and enters a second park name before dismissing it again. This targets the observed sheet/map/keyboard interaction without removing keyboard avoidance from the form. No backend deployment is required for this presentation change.

The physical-device build uses override 110 after verifying Xcode Cloud Dev build 109 (Prod 102); the shared fallback number is unchanged. The earlier full-screen-only simulator suite passed, which again did not prove device behavior. A locked-phone run was stopped without treating it as a keyboard result.

Final validation on unlocked Akiphone: **2 tests passed, 0 failures** in 39.1 seconds after the background-map removal. The Area test typed “Balboa Park,” switched to activities, returned to Area, dismissed the form, reopened it, typed “Golden Gate Park,” then dismissed it and verified the Guide action returned. The transport multi-selection test also passed. Signed build-for-testing passed. Report: `/private/tmp/pippipgo-device-keyboard-detached.xcresult`. This validates these interactions on this physical iPhone/iOS version; it is not a complete device regression or manual acceptance of tour generation. No tour was created or saved by these tests.

## Local planning endpoint address — October 16, 2026

The Local app still targeted `192.168.0.208:8765`; that address answered `/health` but its API schema had no `/v1/guide/tour-plan`. The current Mac address was `192.168.0.155`, with no Local API listener. The current backend was started on the Mac's port 8765 using the existing ignored `.env.city-packs.local` Dev configuration (Cognito and Dev DynamoDB/server-side secrets). `/ready` returned ready and the current tour endpoint/multiple-transport schema was verified. No credentials were copied into the app.

Updated `Configurations/Local.xcconfig` and its matching narrow ATS exception to `.155`. The simulator still uses localhost. Configuration tests now cover the built backend host on devices as well as the simulator, removing a stale assertion for a historical `.156` address. Tests passed; signed Local build 111 passed and was installed/launched on Akiphone after verifying latest Xcode Cloud build 110. Phone `/v1/me`, `/v1/travel-organizer` and weather requests then returned HTTP 200 from the corrected local server.

Live smoke checks used fixed public San Francisco coordinates rather than traveler/account data: Google walking route verification passed; the full transient planner returned `ok` with four stops, 3,307 estimated seconds and no provider errors. No account tour quota or saved organizer records were used in that smoke check. A traveler-selected tour from the phone still needs the user's retry. This is a Local service/configuration correction; no hosted Dev or Prod backend deployment is required. The Local server log is `/private/tmp/pippipgo-local-tour-backend.log`.
