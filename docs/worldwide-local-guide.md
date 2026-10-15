# Worldwide local guide — October 15, 2026

The [user request](worldwide-local-guide-requirements.md) expands tour intelligence while retaining the organizer and existing interface. This is an incremental implementation, not worldwide live acceptance.

## Pipeline and causes

`GuideLocationFeed` → `LiveGuideStore.advance` → `GuideEngine.fetchPlan` → authenticated POST `/v1/guide/nearby` → backend `live_guide.fetch` → Google Nearby Search and language-specific Wikipedia → deduplication/visitor appeal/profile ranking → `GuideEngine.decide` → conversation/translation audio priority gates → POST `/v1/guide/mention` → configured Responses model and existing voice output. Delivery, not selection, records a mention. Account epoch fences remain in the store.

The checkout already had category searches, school demotion, sunset calculation, city debounce, forward circles and a Carmel Valley–Carlsbad replay. Those mechanisms were retained. Without a capture from the actual drive, source inspection identifies failure mechanisms, not proof of which provider results the phone received:

- Forward searches did not refresh after a turn until the distance threshold was reached.
- Routes were displayed but never used by discovery or ranking. All current `pip.route` events describe **walking**, not driving, routes.
- Lateral distance was treated in narration instructions as proof a place was along the road. Nearby geometry also incorrectly enabled visibility claims.
- Category repetition and known closed-now state did not affect driving ranking.
- Fuel, charging, rest areas and restrooms were not explicitly searched; popular practical places could receive sightseeing tiers.
- Independent category requests waited sequentially, increasing delay when any provider request was slow.

## Changes

- Pure `GuideCorridor` projection follows a supplied route's bends, rejects projections when the traveler is too far from the route, and never uses a walking route for a driving tour. Walking discovery now looks 350 m along an active walking route. Driving-route support is exercised with synthetic inputs; the app currently has no driving-polyline feed.
- Driving refreshes after a turn of at least 55° and 150 m, respecting the existing request interval. Existing speed tiers and no-route fallback remain.
- `GuideExperienceWeights` exposes appeal, explicit personal relevance, significance, sunset timing, lateral separation, category variety and known-closed penalties. Each evaluated driving candidate has factor-level diagnostics. Unknown opening state is not treated as closed. Weights are runtime-configurable Swift values, not new UI settings.
- Practical discovery has its own bounded Google type group. Practical places stay minor by default; explicit matching interests can still promote them. Existing eligibility keeps unsolicited practical narration quiet without an explicit interest.
- Category searches run concurrently with five bounded workers and merge in stable category order; a group failure remains isolated. No new Google cache, storage, field-mask expansion or provider credentials.
- Responses diagnostics include total discovery latency, number of searched groups and candidate ranking inputs. The phone logs latency and decision factors. No new persistent GPS logging.
- Driving mentions do not assert visibility. Narration instructions state that lateral separation does not establish a route, exit, road access or detour time.
- Malformed polyline decoding is bounded and rejects invalid coordinates.

## Verification

Run pure macOS engine tests/replays with `python3 scripts/test_guide_engine.py`; this builds a temporary Swift package using Xcode's toolchain. The networking endpoint test remains in the iOS test target and is excluded from that package. This is not an iOS simulator or signed app build.

Coverage includes the existing approximated Carmel Valley → Del Mar Highlands → I-5 → Carlsbad replay, sunset/night, explicit practical interests, cooldowns, grouped announcements, direction and city deduplication; new tests cover turns, route bends, mode isolation, factor explanations, malformed polylines and synthetic driving replays at Tokyo, Paris, Istanbul, Toronto and a smaller-city origin at 12/27/40 m/s, with and without supplied navigation. Geometry tests also cover Tehran, Dubai and a southern-hemisphere origin. These generated routes and fixture places do not prove live provider coverage or road accessibility.

Three old walking fixtures failed against the unchanged engine because they assumed a wider range than the current 10 m threshold. Their positions now match the existing threshold; walking behavior was preserved.

Verified October 15: 37 pure Swift tests passed with Xcode’s toolchain. Backend: 713 passed, 1 skipped; Ruff lint and format checks passed. Patch whitespace checks passed in both repositories.

## Remaining boundaries and rollout

- Backend deployment is required and **pending in both Dev and Prod**. Deploy and verify Dev first, then Prod; deploy the backend before rolling out the accompanying app. The API changes are additive; old clients continue decoding existing fields.
- No live Google/OpenAI calls, IAM changes, signed iOS builds, simulator app tests, device drives, Bluetooth/headphone checks or physical-device acceptance were performed for this change. Xcode Cloud's current build number was not verified; no app build number was changed or release build prepared.
- The current app has no active driving route geometry. External driving navigation remains separate. Real map matching, exit lead time, route-derived detour duration and legal road access remain unimplemented; forward/no-route estimates must not be described as verified navigation.
- Google search-along-route is a Text Search feature and needs a supplied route plus separate request/cost integration. This change uses existing Nearby Search, not that API. See [Google documentation](https://developers.google.com/maps/documentation/places/web-service/search-along-route).
- No new offline corpus, event feed, visibility/terrain source or geographic boundary provider was added. Existing fallback/offline paths are retained. Ocean views, public art, neighborhood character and current events cannot be asserted from proximity alone. City approaches inferred from candidate address localities are not authoritative boundary crossings; confirmed current areas still use reverse geocoding and debounce.
- Worldwide provider coverage, localized preference interpretation, true road geometry replays and end-to-end narration factuality require further implementation and live evaluation. The full product vision is not complete.
- Driving discovery now uses **five rather than four Nearby Search requests** per refresh, plus the existing Wikipedia request. Parallel execution reduces network wait, not billing. Cost diagnostics deliberately report no dollar estimate: billing region, field-mask SKU and account pricing must be verified. Existing per-account daily quota remains.
- [Google Places policies](https://developers.google.com/maps/documentation/places/web-service/policies) govern caching and attribution. No offline Google data download was added. Existing Google-content display/Apple-map attribution compatibility needs a separate provider-policy review before claiming full compliance; this change does not establish that compliance.
