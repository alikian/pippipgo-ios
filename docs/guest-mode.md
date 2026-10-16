# Explore without an account (App Review 5.1.1(v))

App Review rejected 1.0 (17) on October 12, 2026 partly because every feature required signing in. The welcome screen now offers **Explore without an account**, which opens an Apple Maps-style screen (`pippipgo/Views/GuestExploreView.swift`):

- Full-screen Apple map with the traveller's location and Apple's own place labels.
- **Find nearby**: restrooms, public transport, groceries, food, hotels, pharmacy, cash machines and parking, found with Apple Maps points of interest (`MKLocalPointsOfInterestRequest`, 1.5 km, nearest first). A result opens a card with walking **Directions** in Apple Maps.
- **Translate a phrase** with Apple's on-device translation (iOS 17.4+).
- App language menu and the system location button.
- The blue raised-hand **Ask Pip** explains that Pip uses the profile and AI and offers sign-in.

Nothing on this screen is sent to PipPipGo or an AI provider; only Apple services are used. Ask Pip, live voice and translation, personalised suggestions, trips, profile and companions remain account features.

Also in this change: Live Translate shows a notice in the other person's language; `PrivacyInfo.xcprivacy` declares collected data and the UserDefaults reason; the welcome text mentions Apple sign-in.

Debug-only simulator review: launch with `-PipGuestExplore` and optionally `-PipGuestCategory restrooms`.

Validation (October 13, 2026): Local simulator builds passed; catalog checks passed; simulator review at the Colosseum showed real nearby restrooms. Existing unrelated failures remain in LiveGuideEngineTests (3) and AppConfigurationTests (1). Not yet done: physical iPhone/iPad check, App Review screen recording of account deletion, release build number from Xcode Cloud.

## Map-first home for signed-in travellers (October 13, 2026)

The approved Apple Maps-style redesign (Requirements.md section 5) replaces the four-tab bar:

- Home is the tour map (`LiveGuideTab`). Profile floats top left; Translate, language, tour settings and recenter float top right.
- One bottom panel: status and what Pip is saying, the blue raised-hand **Ask Pip** (the existing guide conversation), **Type to Pip** (typed chat), **Search places** (the shared `NearbyFinder` used by the guest screen, with results pinned on the map), walking/driving as universal icons, and Start/Stop.
- Chat, Translate and Profile open full screen with **‹ Map** to return. Voice-session rules are unchanged: the map counts as the Tour Guide, so leaving it ends a guide conversation.
- Full Test navigation updated for the new labels.

Debug-only simulator review: `-PipHomeTab profile|pip|translate`, `-PipGuestCategory pharmacy`. Opening `pip` directly uses voice mode and starts a live session.

Validation: Local simulator builds; signed-in home, Find nearby (pharmacies near the Colosseum), Profile and chat reviewed by screenshot; catalog and Full Test runner tests pass; the same four unrelated tests fail as before. Not yet: physical-device check, hands-free wake word, headphone skip, auto parking, music, P-pin sharing (later phases).

## October 13, 2026 — opens on the map, distance choice

- Signed out, PipPipGo now opens directly on the map (no welcome page); a **Sign in** button sits top left and Ask Pip also offers sign-in.
- Find nearby offers **0.5 mi · 3 mi · 15 mi** (1 · 5 · 25 km in metric regions). Results stay within the chosen distance; when nothing is that close the search widens to the next distance and selects it. The map frames the traveler and all results.
- Verified in the simulator at Carmel Valley, San Diego: Hotels within 0.5 mi finds DoubleTree by Hilton Del Mar.

## Guest Search and disclosure — October 15, 2026

Guests default to Search with the standard Pip/Guide/Explore/Translation/Search tab bar. Selecting another tab keeps Search selected and presents a sign-in prompt; the translation shortcut also requires sign-in. Apple Maps Search and directions remain available without an account. The earlier guest Start Guide/Ask Pip panel buttons are replaced by this tab navigation.

Guest disclosure version 2 requires explicit Accept and continue before constructing the map or starting location updates. Acceptance is stored on-device and is distinct from account-specific OpenAI consent; it grants no AI permission. Existing guest acceptance is renewed once for this version. NearbyPlacesModel authorization callbacks now respect whether its location feed was started, preventing already-authorized devices from starting updates before the disclosure is accepted. The disclosure scrolls for large text, cannot be dismissed, and links to the privacy policy. No backend deployment is required. Device acceptance remains pending.

## Login-first entry and per-guest disclosure — October 15, 2026

This supersedes automatic signed-out map entry and device-persisted guest disclosure. Signed-out users see the PipPipGo login page with Sign in or create account and a Continue as guest link. Each explicit guest entry creates a new in-memory session and requires Accept and continue before Search or location updates start. Cancel returns to the login page; re-entering requires acceptance again, including after relaunch. Guest tab sign-in prompts return to the login page. The guest link remains available after a sign-in error. Guest acceptance never grants OpenAI consent.

Regular accounts retain the existing account-scoped, versioned disclosure after first sign-in; acceptance is remembered for that account. Existing authenticated-session restoration and refresh remain unchanged. No backend deployment or build-number change is required. Device acceptance remains pending.
