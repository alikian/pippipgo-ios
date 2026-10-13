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
