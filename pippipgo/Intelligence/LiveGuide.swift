import AVFoundation
import CoreLocation
import Foundation
import MapKit
import Observation
import SwiftUI

// A started guide continues location-triggered TTS with the screen locked.
// Location stays on the phone. Only the area being looked up is sent to the backend, once per
// area, and only the chosen place is sent back when Pip should say something about it.

enum LiveGuideStatus: Equatable {
    case off, needsPermission, denied, locating, listening, unavailable
    var message: String {
        switch self {
        case .off: "Paused"
        case .needsPermission: "Allow location access to use the live guide."
        case .denied: "Location access is off. Allow While Using the App in Settings."
        case .locating: "Finding your location…"
        case .listening: "Looking around you"
        case .unavailable: "Nearby places are unavailable right now."
        }
    }
}

struct LiveGuideMention: Identifiable, Equatable {
    let id = UUID()
    var placeID: String
    var placeName: String
    var text: String
    var at: Date
    /// Spoken inside a Talk to Pip session (Pip's own voice) rather than the iPhone voice.
    var inVoiceSession: Bool
    var wikipediaURL: URL?
}

struct LiveGuideOption: Identifiable, Equatable {
    var candidate: GuideCandidate
    var distance: Double
    var side: String?
    var id: String { candidate.id }
}

@MainActor final class LiveGuideLocationFeed: NSObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onLocation: @MainActor (CLLocation) -> Void = { _ in }
    var onHeading: @MainActor (Double) -> Void = { _ in }
    var onAuthorization: @MainActor (CLAuthorizationStatus) -> Void = { _ in }

    var authorization: CLAuthorizationStatus { manager.authorizationStatus }

    func start(background: Bool = false) {
        manager.delegate = self
        manager.allowsBackgroundLocationUpdates = background
        manager.showsBackgroundLocationIndicator = background
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .other
        manager.pausesLocationUpdatesAutomatically = false
        manager.headingFilter = 10
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: begin()
        default: break
        }
    }

    private func begin() {
        manager.startUpdatingLocation()
        if CLLocationManager.headingAvailable() { manager.startUpdatingHeading() }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        manager.delegate = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorization(manager.authorizationStatus)
        if [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) { begin() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations { onLocation(location) }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard (0...25).contains(newHeading.headingAccuracy), abs(newHeading.timestamp.timeIntervalSinceNow) < 10 else { return }
        onHeading(newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as? CLError)?.code == .denied { onAuthorization(.denied) }
    }
}

/// Give location-triggered network requests time to finish after screen lock.
@MainActor private final class GuideBackgroundRequest {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Live Guide announcement") { [weak self] in
            Task { @MainActor in self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

/// Plays Pip's text-to-speech announcements (MP3 from the backend). No microphone, no live session.
@MainActor final class GuideVoicePlayer: NSObject, @preconcurrency AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    var isPlaying: Bool { player?.isPlaying == true }

    func play(_ data: Data) -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
            player.delegate = self
            self.player = player
            return player.play()
        } catch {
            return false
        }
    }

    func stop() {
        guard player != nil else { return }
        player?.stop(); player = nil
        deactivate()
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        deactivate()
    }

    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor @Observable
final class LiveGuideStore {
    private(set) var isWalking = false
    private(set) var movingMapFix: GuideFix?
    static let enabledKey = "pip.liveGuide.enabled"
    static let tourModeKey = "pip.liveGuide.tourMode"
    static let chattinessKey = "pip.liveGuide.chattiness"
    static let mentionedKey = "pip.liveGuide.mentioned"

    /// Opt-in, per signed-in account; account switches turn it off again.
    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            refreshActivity()
        }
    }
    var chattiness: GuideChattiness {
        didSet {
            engine.chattiness = chattiness
            UserDefaults.standard.set(chattiness.rawValue, forKey: Self.chattinessKey)
        }
    }
    var tourMode: GuideTourMode {
        didSet {
            guard tourMode != oldValue else { return }
            let wasRunning = feed != nil
            // Invalidate old requests and speech before applying the new tour mode.
            stop()
            engine.selectTourMode(tourMode)
            motion = engine.motion
            options = []; lastMention = nil
            lastShortlist = ([], .distantPast)
            if tourMode == .driving { clearRoute() }
            UserDefaults.standard.set(tourMode.rawValue, forKey: Self.tourModeKey)
            if wasRunning {
                start()
                greetPending = false // Switching modes doesn't restart the welcome conversation.
            }
        }
    }
    private(set) var status = LiveGuideStatus.off
    private(set) var motion = GuideMotion.unknown
    private(set) var candidateCount = 0
    /// Must-see and notable places around the traveler, for the map.
    private(set) var places: [GuideCandidate] = []
    private(set) var lastMention: LiveGuideMention?
    private(set) var options: [LiveGuideOption] = []
    private(set) var asking = false
    /// Which voice the last announcement used, so testers can tell Pip's voice from the fallback.
    private(set) var lastVoiceWasPip: Bool?
    var notice: String?

    @ObservationIgnored private var engine: GuideEngine
    @ObservationIgnored private var feed: LiveGuideLocationFeed?
    @ObservationIgnored private var foreground = false
    @ObservationIgnored private var rawHeading: Double?
    @ObservationIgnored private var headingReceivedAt: Date?
    private var heading: Double? {
        guard let headingReceivedAt, Date().timeIntervalSince(headingReceivedAt) < 10 else { return nil }
        return rawHeading
    }
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var deliverTask: Task<Void, Never>?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastShortlist: (ids: [String], at: Date) = ([], .distantPast)
    @ObservationIgnored private var epoch = UUID()
    /// Speak once as soon as the guide starts, so pressing Start always gets an answer.
    @ObservationIgnored private var greetPending = false
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var lastMovementFix: GuideFix?
    @ObservationIgnored private var lastSharedFix: GuideFix?
    private let speech = AVSpeechSynthesizer()
    private let voicePlayer = GuideVoicePlayer()
    private let client: APIClient
    private let authentication: any AccessTokenProviding
    private let voice: LiveVoiceStore
    private let translator: LiveVoiceStore

    init(client: APIClient, authentication: any AccessTokenProviding, voice: LiveVoiceStore, translator: LiveVoiceStore) {
        self.client = client; self.authentication = authentication
        self.voice = voice; self.translator = translator
        let defaults = UserDefaults.standard
        let chattiness = GuideChattiness(rawValue: defaults.string(forKey: Self.chattinessKey) ?? "") ?? .normal
        self.tourMode = GuideTourMode(rawValue: defaults.string(forKey: Self.tourModeKey) ?? "") ?? .walking
        self.chattiness = chattiness
        self.enabled = defaults.bool(forKey: Self.enabledKey)
        self.engine = GuideEngine(chattiness: chattiness, mentioned: Set(defaults.stringArray(forKey: Self.mentionedKey) ?? []))
        self.engine.selectTourMode(tourMode)
        self.motion = engine.motion
        // The system manages its own audio session for the iPhone voice, leaving Talk to Pip's alone.
        speech.usesApplicationAudioSession = false
    }

    private var language: String {
        AppLanguage.selected(UserDefaults.standard.string(forKey: "pip.language") ?? "en").rawValue
    }

    /// Current conditions for the map's weather chip (signed in only); nil when unavailable.
    func currentWeather(at location: CLLocation) async -> CurrentWeather? {
        let body = WeatherRequest(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        return try? await client.send(.post(.weather, body: body), using: authentication)
    }

    /// Live Google ratings for Find nearby (signed in only); nil when unavailable.
    func placeRatings(category: GuestCategory, location: CLLocation, radius: CLLocationDistance) async -> [GooglePlaceRating]? {
        let body = PlaceRatingsRequest(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                       radius_meters: Int(min(25_000, max(50, radius))), category: category.rawValue,
                                       language: language)
        let response: PlaceRatingsResponse? = try? await client.send(.post(.placeRatings, body: body), using: authentication)
        return response?.places
    }

    // MARK: Lifecycle

    func setForeground(_ active: Bool) {
        foreground = active
        refreshActivity()
    }

    func useTTSInBackground() {
        if enabled, voice.active { voice.stop() }
    }

    private func refreshActivity() {
        // A tour started in the foreground continues through screen lock. Never
        // start a restored tour in the background without a foreground start.
        let shouldRun = enabled && (foreground || feed != nil)
        if shouldRun, feed == nil { start() } else if !shouldRun, feed != nil { stop() }
        if !enabled {
            status = .off
            // Stop means stop: no live (billed) conversation keeps running after the guide.
            if voice.active { voice.stop() }
        }
    }

    private func start() {
        let ticket = UUID(); epoch = ticket
        greetPending = true
        startedAt = Date()
        let feed = LiveGuideLocationFeed()
        feed.onLocation = { [weak self] location in self?.handle(location, ticket: ticket) }
        feed.onHeading = { [weak self] value in self?.rawHeading = value; self?.headingReceivedAt = Date() }
        feed.onAuthorization = { [weak self] value in self?.authorizationChanged(value) }
        self.feed = feed
        authorizationChanged(feed.authorization)
        feed.start(background: true)
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard let self, self.epoch == ticket else { return }
                self.tick()
            }
        }
    }

    private func stop() {
        rawHeading = nil; headingReceivedAt = nil
        isWalking = false
        lastMovementFix = nil
        movingMapFix = nil
        epoch = UUID()
        feed?.stop(); feed = nil
        ticker?.cancel(); ticker = nil
        fetchTask?.cancel(); fetchTask = nil
        deliverTask?.cancel(); deliverTask = nil
        if speech.isSpeaking { speech.stopSpeaking(at: .word) }
        voicePlayer.stop()
        asking = false
        status = .off
    }

    /// Sign-out or account switch: forget everything this account's guide knew.
    func reset() {
        stop()
        enabled = false
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: Self.enabledKey)
        defaults.removeObject(forKey: Self.mentionedKey)
        tourMode = .walking
        defaults.removeObject(forKey: Self.tourModeKey)
        engine = GuideEngine(chattiness: chattiness)
        engine.selectTourMode(tourMode)
        lastMention = nil; options = []; notice = nil; candidateCount = 0; places = []; motion = .unknown
        lastShortlist = ([], .distantPast)
    }

    private func authorizationChanged(_ value: CLAuthorizationStatus) {
        switch value {
        case .notDetermined: status = .needsPermission
        case .denied, .restricted: status = .denied
        default: if status == .needsPermission || status == .denied || status == .off { status = .locating }
        }
    }

    // MARK: Location

    private func handle(_ location: CLLocation, ticket: UUID) {
        guard epoch == ticket, abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        let fix = GuideFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                           accuracy: location.horizontalAccuracy, speed: location.speed, course: location.course,
                           timestamp: location.timestamp)
        guard engine.ingest(fix) else { return }
        lastMovementFix = fix
        isWalking = fix.isMoving(at: Date())
        if isWalking { movingMapFix = fix }
        motion = engine.motion
        if status != .unavailable { status = .listening }
        advance(now: Date())
    }

    /// Core Location may go quiet when the traveler stands still; a still traveler is stopped.
    private func tick() {
        let now = Date()
        // Synthetic stationary fixes below must never refresh movement freshness.
        isWalking = lastMovementFix?.isMoving(at: now) ?? false
        if let last = engine.latest, (4..<30).contains(now.timeIntervalSince(last.timestamp)), last.speed < 0.5 {
            var copy = last; copy.timestamp = now
            engine.ingest(copy)
        }
        advance(now: now)
    }

    private func advance(now: Date) {
        if engine.needsFetch(at: now) { fetch(now: now) }
        shareShortlistIfNeeded(now: now)
        let waitedForPlaces = startedAt.map { now.timeIntervalSince($0) > 6 } ?? false
        if greetPending, deliverTask == nil, !asking, !busyElsewhere, engine.fetchedAt != nil || waitedForPlaces {
            greetPending = false
            // Starting the tour only requests text-to-speech. Talk is the explicit
            // opt-in to a microphone and a billed live conversation.
            if let opening = engine.opening(heading: heading) {
                deliver(opening, asked: false)
            } else {
                sayInPipsVoice(String(localized: "I’m looking around. I’ll tell you when we pass something interesting.",
                                      bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale))
            }
            return
        }
        evaluate(now: now)
    }

    // MARK: Talking with Pip from the Live Guide

    /// A Talk to Pip session is open; guide mentions are then spoken in Pip's own voice.
    var talking: Bool { voice.active }
    /// Includes downloaded TTS and the on-device fallback voice.
    var announcementSpeaking: Bool { voicePlayer.isPlaying || speech.isSpeaking }

    func skipAnnouncement() {
        // Cancel pending audio too; canceled responses must not restart playback.
        deliverTask?.cancel()
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        voicePlayer.stop()
        asking = false
    }
    var listening: Bool { voice.connected }
    var conversationError: String? { voice.error }
    /// Pip's latest spoken line in the current conversation, for a caption over the map.
    var latestPipLine: String? {
        voice.transcript.messages.last(where: { $0.speaker == .pip })?.text
    }

    /// The only place a live (per-second billed) conversation starts in the Live Guide. The
    /// session closes itself after silence; announcements then continue by text-to-speech.
    func toggleConversation() {
        if voice.active { voice.stop(); return }
        startConversation()
    }

    var route: GuideRoute? { voice.route }
    func clearRoute() { voice.clearRoute() }

    private func startConversation() {
        greetPending = false
        deliverTask?.cancel()
        asking = false
        if speech.isSpeaking { speech.stopSpeaking(at: .immediate) }
        voicePlayer.stop()
        translator.stop()
        let venue = engine.enclosingVenue()
        let nearby = engine.whatsThis(heading: heading)
            .filter { $0.candidate.id != venue?.id }
            .map { GuideMentionPlace($0.candidate, distance: $0.distance, side: $0.side) }
        // The greeting names these, so the guide won't announce them again.
        if let venue { engine.markAsked(venue.id) }
        if let first = nearby.first { engine.markAsked(first.id) }
        persistMentioned()
        let start = GuideStartContext(venue: venue.map { String($0.name.prefix(160)) }, nearby: Array(nearby.prefix(3)))
        lastShortlist = ([], .distantPast)  // share position right after connecting
        voice.start(guide: try? JSONEncoder().encode(start))
    }

    private func fetch(now: Date) {
        guard fetchTask == nil, var plan = engine.fetchPlan() else { return }
        plan.language = language
        engine.markFetchAttempt(at: now)
        let ticket = epoch
        fetchTask = Task { [weak self] in
            guard let self else { return }
            let backgroundRequest = GuideBackgroundRequest()
            defer { backgroundRequest.end() }
            defer { if self.epoch == ticket { self.fetchTask = nil } }
            do {
                let response: GuideNearbyResponse = try await client.send(.post(.guideNearby, body: plan), using: authentication)
                guard self.epoch == ticket else { return }
                engine.update(candidates: response.candidates, for: plan, at: Date())
                candidateCount = response.candidates.count
                places = response.candidates.filter { $0.tier != .minor }
                status = .listening
                notice = nil
            } catch {
                guard self.epoch == ticket, !Task.isCancelled else { return }
                if case APIClientError.rejected(let code, let body, _) = error, code == 429 { notice = body.message }
                // No PipPipGo connection: fall back to Apple Maps' own points of interest.
                let local = await Self.appleCandidates(plan)
                guard self.epoch == ticket, !Task.isCancelled else { return }
                if local.isEmpty { status = .unavailable; return }
                engine.update(candidates: local, for: plan, at: Date())
                candidateCount = local.count
                places = local.filter { $0.tier != .minor }
                status = .listening
            }
        }
    }

    // MARK: Speaking

    private var busyElsewhere: Bool {
        translator.active || speech.isSpeaking || voicePlayer.isPlaying || (voice.active && (!voice.acceptsGuideEvents || voice.guideShouldWait))
    }

    private func evaluate(now: Date) {
        guard deliverTask == nil, !asking, !busyElsewhere,
              let decision = engine.decide(at: now, heading: heading) else { return }
        deliver(decision, asked: false)
    }

    private func deliver(_ decision: GuideDecision, asked: Bool) {
        let ticket = epoch
        let request = decision.request(language: language)
        deliverTask = Task { [weak self] in
            guard let self else { return }
            let backgroundRequest = GuideBackgroundRequest()
            defer { backgroundRequest.end() }
            defer { if self.epoch == ticket { self.deliverTask = nil; self.asking = false } }
            if voice.acceptsGuideEvents, let mention = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) {
                // Pip says it herself in the live session, in her own voice.
                if await voice.sendGuideEvent(["type": "guide.mention", "mention": mention]) {
                    guard self.epoch == ticket else { return }
                    lastVoiceWasPip = true
                    record(decision, text: decision.place.summary.map(Self.firstSentence) ?? "", inVoice: true, asked: asked)
                    return
                }
            }
            do {
                // Text plus Pip's voice as an MP3: no microphone and no live session.
                var spoken = request
                spoken.audio = !voice.active && !translator.active
                let reply: GuideMentionResponse = try await client.send(.post(.guideMention, body: spoken), using: authentication)
                guard self.epoch == ticket, !Task.isCancelled else { return }
                record(decision, text: reply.text, inVoice: false, asked: asked)
                if !voice.active, !translator.active { speak(reply.text, audio: reply.audio) }
            } catch {
                guard self.epoch == ticket, !Task.isCancelled else { return }
                // Pip's writer is unreachable: still name the place, in the iPhone voice.
                let line = Self.localLine(decision)
                record(decision, text: line, inVoice: false, asked: asked)
                if !voice.active, !translator.active { speak(line) }
            }
        }
    }

    private func record(_ decision: GuideDecision, text: String, inVoice: Bool, asked: Bool) {
        if asked { engine.markAsked(decision.place.id) } else { engine.markMentioned(decision, at: Date()) }
        persistMentioned()
        lastMention = LiveGuideMention(placeID: decision.place.id, placeName: decision.place.name, text: text, at: Date(),
                                       inVoiceSession: inVoice, wikipediaURL: decision.place.wikipedia_url.flatMap(URL.init(string:)))
    }

    /// Pip's voice from the returned MP3 when there is one; the iPhone voice otherwise.
    private func speak(_ text: String, audio: String? = nil) {
        if let audio, let data = Data(base64Encoded: audio), voicePlayer.play(data) {
            lastVoiceWasPip = true
            return
        }
        lastVoiceWasPip = false
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: AppLanguage.selected(language).localizationIdentifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        utterance.pitchMultiplier = 1.05
        utterance.postUtteranceDelay = 0.1
        speech.speak(utterance)
    }

    /// The most natural installed iPhone voice for the language (Premium, then Enhanced), instead
    /// of the robotic compact default. Users can download better ones in Settings → Accessibility →
    /// Spoken Content → Voices.
    static func bestVoice(for identifier: String) -> AVSpeechSynthesisVoice? {
        let base = identifier.split(separator: "-").first.map(String.init) ?? identifier
        let matching = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == identifier || $0.language.hasPrefix(base + "-") || $0.language == base
        }
        let preferredRegion = Locale.current.region?.identifier
        let best = matching.max { a, b in
            if a.quality != b.quality { return a.quality.rawValue < b.quality.rawValue }
            return !a.language.hasSuffix(preferredRegion ?? "") && b.language.hasSuffix(preferredRegion ?? "")
        }
        return best ?? AVSpeechSynthesisVoice(language: identifier)
    }

    private func persistMentioned() {
        UserDefaults.standard.set(Array(engine.mentioned.prefix(500)), forKey: Self.mentionedKey)
    }

    static func localLine(_ decision: GuideDecision) -> String {
        let lead = String(format: String(localized: "You’re at %@.", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale), decision.place.name)
        guard let summary = decision.place.summary else { return lead }
        return lead + " " + firstSentence(summary)
    }

    /// Apple Maps points of interest, used when the PipPipGo backend can't be reached.
    static func appleCandidates(_ plan: GuideNearbyRequest) async -> [GuideCandidate] {
        let center = CLLocationCoordinate2D(latitude: plan.latitude, longitude: plan.longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: CLLocationDistance(plan.radius_meters))
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [
            .zoo, .aquarium, .museum, .park, .nationalPark, .amusementPark, .stadium, .theater, .beach, .marina,
        ])
        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }
        var result: [GuideCandidate] = []
        for item in response.mapItems {
            guard let name = item.name, let category = item.pointOfInterestCategory else { continue }
            let coordinate = item.placemark.coordinate
            let major: Set<MKPointOfInterestCategory> = [.zoo, .aquarium, .museum, .nationalPark, .amusementPark]
            let areaRadius: Double
            switch category {
            case .zoo, .amusementPark, .nationalPark: areaRadius = 250
            case .park: areaRadius = 120
            default: areaRadius = 0
            }
            let kind: String
            switch category {
            case .zoo, .aquarium, .amusementPark: kind = "family"
            case .museum: kind = "history"
            case .theater: kind = "culture"
            case .park, .nationalPark, .beach, .marina: kind = "nature"
            default: kind = "landmark"
            }
            let notable = major.contains(category)
            result.append(GuideCandidate(
                id: "apple:\(name):\(Int(coordinate.latitude * 10_000)):\(Int(coordinate.longitude * 10_000))",
                name: name, latitude: coordinate.latitude, longitude: coordinate.longitude,
                radius_meters: areaRadius, categories: [kind], prominence: notable ? 0.75 : 0.4,
                tier: notable ? .notable : .minor))
        }
        return result
    }

    static func firstSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let end = trimmed.firstIndex(where: { ".!?".contains($0) }) else { return String(trimmed.prefix(200)) }
        return String(trimmed[...end])
    }

    // MARK: "Pip, what's this?"

    func askWhatsThis() {
        guard enabled, !asking else { return }
        asking = true; notice = nil
        let ticket = epoch
        Task { [weak self] in
            guard let self else { return }
            if engine.candidates.isEmpty {
                if fetchTask == nil, engine.latest != nil { fetch(now: Date()) }
                await fetchTask?.value
            }
            guard self.epoch == ticket else { return }
            options = engine.whatsThis(heading: heading).map { LiveGuideOption(candidate: $0.candidate, distance: $0.distance, side: $0.side) }
            guard let first = options.first else {
                asking = false
                notice = engine.latest == nil ? LiveGuideStatus.locating.message : "Nothing notable within 150 m."
                return
            }
            describe(first)
        }
    }

    /// A short line (no place behind it) in Pip's voice, falling back to the iPhone voice.
    private func sayInPipsVoice(_ line: String) {
        let ticket = epoch
        deliverTask = Task { [weak self] in
            guard let self else { return }
            let backgroundRequest = GuideBackgroundRequest()
            defer { backgroundRequest.end() }
            defer { if self.epoch == ticket { self.deliverTask = nil } }
            let reply: GuideMentionResponse? = try? await client.send(
                .post(.guideSpeech, body: GuideSpeechRequest(text: line, language: language)), using: authentication)
            guard self.epoch == ticket, !Task.isCancelled, !voice.active, !translator.active else { return }
            speak(line, audio: reply?.audio)
        }
    }

    /// Tell me about this one (the first answer to "what's this?", or another of the options).
    func describe(_ option: LiveGuideOption) {
        guard deliverTask == nil else { asking = false; return }
        asking = true
        speech.stopSpeaking(at: .word)
        voicePlayer.stop()
        deliver(GuideDecision(place: option.candidate, highlights: [], situation: .asked, side: option.side,
                              distance: option.distance, motion: engine.motion == .unknown ? .walking : engine.motion,
                              breaksBudget: true), asked: true)
    }

    // MARK: Talk to Pip's "what's this?" uses the phone's latest shortlist

    /// Keeps a live conversation current: where the traveler is now, the venue they are in, and
    /// the nearest places — so "take me to the penguins" starts from here, not from the call start.
    private func shareShortlistIfNeeded(now: Date) {
        guard voice.acceptsGuideEvents, let fix = engine.latest else { return }
        let nearest = engine.whatsThis(heading: heading)
        let ids = nearest.map { $0.candidate.id }
        let moved = lastSharedFix.map { GuideGeo.distance($0.latitude, $0.longitude, fix.latitude, fix.longitude) } ?? .infinity
        guard ids != lastShortlist.ids || moved > 25 || now.timeIntervalSince(lastShortlist.at) > 45 else { return }
        lastShortlist = (ids, now)
        lastSharedFix = fix
        let places = nearest.map { GuideMentionPlace($0.candidate, distance: $0.distance, side: $0.side) }
        guard let encoded = try? JSONSerialization.jsonObject(with: JSONEncoder().encode(places)) else { return }
        var shortlist: [String: Any] = [
            "places": encoded,
            "captured_at": ISO8601DateFormatter().string(from: fix.timestamp),
            "latitude": fix.latitude,
            "longitude": fix.longitude,
            "horizontal_accuracy_meters": fix.accuracy,
        ]
        if let venue = engine.enclosingVenue() { shortlist["venue"] = String(venue.name.prefix(160)) }
        Task { await voice.sendGuideEvent(["type": "guide.shortlist", "shortlist": shortlist]) }
    }
}

// MARK: - Views

/// Home screen: the tour map in the style of Apple Maps. Profile sits top left; translate,
/// language, settings and recenter float top right; one bottom panel holds what Pip is saying,
/// the blue raised-hand Ask Pip, Find nearby and the walking/driving tour controls.
struct LiveGuideTab: View {
    @Bindable var guide: LiveGuideStore
    var openChat: (() -> Void)? = nil
    var openTranslate: (() -> Void)? = nil
    var openProfile: (() -> Void)? = nil
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    @State private var showSettings = false
    @State private var mapLocationFeed: LiveGuideLocationFeed?
    @State private var currentMapCamera: MapCamera?
    @State private var nearby = NearbyPlacesModel()
    @State private var finding = false
    @State private var collapsed = false
    @State private var selectedPlace: NearbyPlace?
    @State private var pinSelection: NearbyPlace.ID?
    @State private var weather: CurrentWeather?
    @State private var weatherFetched: (location: CLLocation, at: Date)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        map
            .safeAreaInset(edge: .bottom, spacing: 0) { panel.frame(maxWidth: 560) }
            .overlay(alignment: .topLeading) { profileButton }
            .overlay(alignment: .topTrailing) { floatingControls }
            .overlay(alignment: .top) {
                if let route = guide.route {
                    LiveGuideRouteCard(route: route, close: guide.clearRoute)
                        .padding(.horizontal, 72).padding(.top, 8)
                }
            }
            .onAppear {
                locateMapInitially()
                nearby.ratingsProvider = { [guide] category, location, radius in
                    await guide.placeRatings(category: category, location: location, radius: radius)
                }
            }
            .onChange(of: guide.enabled) { _, enabled in
                if !enabled {
                    // Restore MapKit's continuous user tracking when the tour ends.
                    // A fixed camera would otherwise retain the last tour position.
                    position = .userLocation(followsHeading: false,
                                             fallback: currentMapCamera.map { .camera($0) } ?? .automatic)
                    locateMapInitially()
                }
            }
            // Tapping a result pin selects the place, the same as tapping it in the list.
            .onChange(of: pinSelection) { _, id in
                if let id, let place = nearby.places.first(where: { $0.id == id }) { selectedPlace = place }
            }
            .onChange(of: selectedPlace?.id) { _, id in pinSelection = id }
            .onChange(of: nearby.places.map(\.id)) { _, _ in
                if let region = NearbyFinder.region(for: nearby) { withAnimation { position = .region(region) } }
            }
            .onChange(of: finding) { _, open in
                if open { nearby.start() } else { nearby.stop(); nearby.clear(); selectedPlace = nil }
            }
            #if DEBUG
            // Simulator review: `-PipGuestCategory restrooms` opens Find nearby and searches.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard let index = arguments.firstIndex(of: "-PipGuestCategory"), index + 1 < arguments.count,
                      let category = GuestCategory(rawValue: arguments[index + 1]) else { return }
                finding = true
                for _ in 0..<40 where nearby.location == nil { try? await Task.sleep(for: .milliseconds(250)) }
                nearby.search(category)
            }
            #endif
            .onDisappear {
                mapLocationFeed?.stop()
                mapLocationFeed = nil
                nearby.stop()
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form { LiveGuideSettingsSection(guide: guide) }
                        .navigationTitle("Tour Guide").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
                }
                .presentationDetents([.medium, .large])
            }
    }

    /// Keep map location separate from the tour so Stop still allows GPS following.
    /// This foreground-only feed stops when the Live Guide tab disappears.
    private func locateMapInitially() {
        guard mapLocationFeed == nil else { return }
        let feed = LiveGuideLocationFeed()
        mapLocationFeed = feed
        feed.onLocation = { location in
            guard location.horizontalAccuracy >= 0,
                  abs(location.timestamp.timeIntervalSinceNow) < 15,
                  CLLocationCoordinate2DIsValid(location.coordinate) else { return }
            refreshWeather(location)
            var camera = currentMapCamera ?? MapCamera(
                centerCoordinate: location.coordinate,
                distance: max(800, location.horizontalAccuracy * 4), heading: 0, pitch: 0)
            camera.centerCoordinate = location.coordinate
            if guide.enabled {
                withAnimation(.linear(duration: 0.5)) { position = .camera(camera) }
            } else {
                // Keep native tracking enabled, including zero-speed coordinate updates.
                position = .userLocation(followsHeading: false, fallback: .camera(camera))
            }
        }
        feed.start()
    }

    private var map: some View {
        Map(position: $position, selection: $pinSelection) {
            UserAnnotation { _ in
                Button {
                    guide.tourMode = guide.tourMode == .walking ? .driving : .walking
                } label: {
                    LiveGuideUserMarker(active: guide.enabled, driving: guide.tourMode == .driving, walking: guide.isWalking)
                        .id("\(guide.tourMode.rawValue)-\(guide.enabled)-\(guide.isWalking)")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(LocalizedStringKey(guide.tourMode.title)))
                .accessibilityHint(Text("Switch tour mode"))
                .accessibilityIdentifier("liveGuide.tourMarker")
            }
            ForEach(guide.places) { place in
                Marker(place.name, systemImage: place.tier == .mustSee ? "star.fill" : "mappin",
                       coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                    .tint(place.tier == .mustSee ? .orange : .blue)
            }
            ForEach(nearby.places) { place in
                Marker(place.name, systemImage: nearby.category?.symbol ?? "mappin", coordinate: place.coordinate)
                    .tint(nearby.category?.tint ?? .red)
                    .tag(place.id)
            }
            if let route = guide.route {
                if route.path.count > 1 {
                    MapPolyline(coordinates: route.path.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                        .stroke(.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }
                Marker(route.name, systemImage: "flag.checkered",
                       coordinate: CLLocationCoordinate2D(latitude: route.destination.latitude, longitude: route.destination.longitude))
                    .tint(.red)
            }
        }
        // MapKit caches UserAnnotation content; recreate it when the chosen marker changes.
        .id(guide.tourMode)
        .onChange(of: guide.route) { _, route in
            // Show the whole walk: traveler and destination together.
            if route != nil { withAnimation { position = .automatic } }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            currentMapCamera = context.camera
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .ignoresSafeArea(edges: .top)
    }

    /// Only while the app is open on screen; every 15 minutes, or after moving about 3 km.
    private func refreshWeather(_ location: CLLocation) {
        guard scenePhase == .active else { return }
        if let last = weatherFetched, Date().timeIntervalSince(last.at) < 900,
           location.distance(from: last.location) < 3_000 { return }
        weatherFetched = (location, Date())
        Task { if let current = await guide.currentWeather(at: location) { weather = current } }
    }

    @ViewBuilder private var profileButton: some View {
        if let openProfile {
            Button(action: openProfile) {
                Image(systemName: "person.crop.circle.fill").font(.title2)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(Text("Profile"))
            .accessibilityIdentifier("navigation.profile")
            .padding(.leading, 12).padding(.top, 8)
        }
        if let weather {
            WeatherChip(weather: weather).padding(.leading, 12).padding(.top, 64)
        }
    }

    /// Apple Maps-style floating buttons.
    private var floatingControls: some View {
        VStack(spacing: 10) {
            VStack(spacing: 0) {
                if let openTranslate {
                    Button(action: openTranslate) {
                        Image(systemName: "character.bubble").font(.title3).frame(width: 48, height: 48)
                    }
                    .accessibilityLabel(Text("Translate"))
                    .accessibilityIdentifier("navigation.translate")
                    Divider().frame(width: 48)
                }
                AppLanguageMenu().frame(width: 48, height: 48)
                Divider().frame(width: 48)
                AudioOutputButton()
                Divider().frame(width: 48)
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape").font(.title3).frame(width: 48, height: 48)
                }
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("liveGuide.settings")
            }
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            Button {
                withAnimation { position = .userLocation(followsHeading: false, fallback: .automatic) }
            } label: {
                Image(systemName: "location.fill").font(.title3)
                    .frame(width: 48, height: 48)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .accessibilityLabel(Text("Recenter"))
        }
        .padding(.trailing, 12).padding(.top, 8)
    }

    /// One Apple Maps-style panel: status, what Pip is saying (or Find nearby), Ask Pip, tour controls.
    private var panel: some View {
        VStack(alignment: .leading, spacing: 14) {
            PanelHandle(collapsed: $collapsed)
            if guide.enabled, guide.status != .listening {
                Label(LocalizedStringKey(guide.status.message), systemImage: statusSymbol)
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let notice = guide.notice {
                Label(LocalizedStringKey(notice), systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = guide.conversationError {
                Label(LocalizedStringKey(error), systemImage: "exclamationmark.circle")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("liveGuide.voiceError")
            }
            if guide.status == .denied {
                Button("Open location settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.bordered)
            }
            if !collapsed, guide.tourMode == .driving {
                Label("Driving? Keep your eyes on the road and talk to Pip instead.", systemImage: "car.fill")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if collapsed {
                EmptyView()
            } else if finding {
                NearbyFinder(model: nearby, selected: $selectedPlace) { place in
                    withAnimation { position = .item(place.item) }
                }
            } else if guide.talking, let line = guide.latestPipLine, !line.isEmpty {
                // What Pip is saying right now in the conversation.
                Text(verbatim: line).font(.body).foregroundStyle(.primary).lineLimit(5)
                    .fixedSize(horizontal: false, vertical: true)
            } else if guide.enabled, let mention = guide.lastMention {
                LiveGuideMentionView(mention: mention, guide: guide)
            }

            HStack(spacing: 10) {
                askPipButton
                if let openChat {
                    circleButton("keyboard", label: "Type to Pip", identifier: "navigation.pip", action: openChat)
                }
                circleButton(finding ? "xmark" : "magnifyingglass", label: finding ? "Close" : "Search places",
                             identifier: "liveGuide.findNearby") {
                    withAnimation { finding.toggle(); if finding { collapsed = false } }
                }
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack(spacing: 8) {
                    HStack(spacing: 4) { modeIcons }
                        .padding(3)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    if guide.enabled, guide.announcementSpeaking, !guide.talking {
                        Button { guide.skipAnnouncement() } label: {
                            Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(Text("Skip announcement"))
                        .accessibilityIdentifier("liveGuide.skipAnnouncement")
                    }
                    startStopButton
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                .fill(.regularMaterial).ignoresSafeArea(edges: .bottom)
        }
        .shadow(color: .black.opacity(0.12), radius: 12, y: -2)
    }

    /// Walking or driving as universal icons; the names are read by VoiceOver.
    @ViewBuilder private var modeIcons: some View {
        ForEach(GuideTourMode.allCases) { mode in
            let selected = guide.tourMode == mode
            Button { guide.tourMode = mode } label: {
                Image(systemName: mode.symbol).font(.title3)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .frame(width: 52, height: 44)
                    .background(selected ? PipAppearance.navy : Color.clear, in: RoundedRectangle(cornerRadius: 11))
                    .contentShape(RoundedRectangle(cornerRadius: 11))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(mode.title)))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier("liveGuide.mode.\(mode.rawValue)")
        }
    }

    /// The one blue button everywhere: raise your hand to ask Pip, with the guide's context.
    private var askPipButton: some View {
        Button { guide.toggleConversation() } label: {
            Label {
                Text(guide.talking ? "Listening… tap to end" : "Ask Pip").lineLimit(1).minimumScaleFactor(0.7)
            } icon: {
                Image(systemName: "hand.raised.fill").symbolEffect(.variableColor.iterative, isActive: guide.listening)
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.capsule)
        .tint(guide.talking ? Color(red: 0, green: 0.45, blue: 0.2) : .blue)
        .accessibilityIdentifier("liveGuide.talk")
    }

    private func circleButton(_ symbol: String, label: LocalizedStringKey, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3.weight(.semibold))
                .frame(width: 52, height: 52)
                .background(Color.secondary.opacity(0.15), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private var startStopButton: some View {
        if guide.enabled {
            Button(role: .destructive) { withAnimation(.spring) { guide.enabled = false } } label: {
                Text("Stop tour").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("liveGuide.enabled")
        } else {
            Button { withAnimation(.spring) { guide.enabled = true } } label: {
                Text("Start tour").font(.headline).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
            .accessibilityIdentifier("liveGuide.enabled")
        }
    }

    private var statusSymbol: String {
        switch guide.status {
        case .needsPermission, .denied: "location.slash"
        case .locating: "location"
        case .unavailable: "exclamationmark.circle"
        case .off, .listening: "pause.circle"
        }
    }
}

/// The traveler on the map; walking motion follows accepted location updates.
struct LiveGuideUserMarker: View {
    let active: Bool
    let driving: Bool
    let walking: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if active && !reduceMotion && walking {
                ForEach(0..<2) { ring in
                    Circle()
                        .stroke(Color.green.opacity(0.6), lineWidth: 3)
                        .frame(width: 70, height: 70)
                        .scaleEffect(pulse ? 2.4 : 0.8)
                        .opacity(pulse ? 0 : 0.9)
                        .animation(.easeOut(duration: 2).repeatForever(autoreverses: false).delay(Double(ring)), value: pulse)
                }
            }
            Circle().fill(.white).frame(width: 62, height: 62).shadow(radius: 6)
            Circle().fill(active ? Color.green : Color.blue).frame(width: 54, height: 54)
            Image(systemName: driving ? "car.fill" : (active && walking ? "figure.walk" : "figure.stand"))
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, options: .repeating, isActive: active && !driving && walking && !reduceMotion)
        }
        .onAppear { pulse = true }
        .accessibilityHidden(true)
    }
}

/// What Pip just said; tap another nearby name to hear about it instead.
struct LiveGuideMentionView: View {
    let mention: LiveGuideMention
    @Bindable var guide: LiveGuideStore
    @Environment(\.openURL) private var openURL
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if !mention.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(verbatim: mention.text.trimmingCharacters(in: .whitespacesAndNewlines))
                            .font(.body).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let url = mention.wikipediaURL {
                        Button { openURL(url) } label: { Label("Read more", systemImage: "book") }
                            .font(.subheadline.weight(.semibold))
                            .frame(minHeight: 44)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            } label: {
                Text(verbatim: mention.placeName).font(.headline).foregroundStyle(.primary)
                    .frame(minHeight: 44, alignment: .leading)
            }
            .fixedSize(horizontal: false, vertical: true)
            if guide.options.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(guide.options.dropFirst()) { option in
                            Button { guide.describe(option) } label: { Text(verbatim: option.candidate.name) }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .task(id: mention.id) {
            expanded = true
            // AVAudioPlayer and AVSpeechSynthesizer expose playback state without
            // observation. Follow both so fallback audio also collapses on completion.
            while guide.announcementSpeaking {
                do { try await Task.sleep(for: .milliseconds(200)) }
                catch { return }
            }
            guard !Task.isCancelled else { return }
            withAnimation { expanded = false }
        }
    }
}

/// Speaking frequency, the voice last used, and privacy information.
struct LiveGuideSettingsSection: View {
    @Bindable var guide: LiveGuideStore

    var body: some View {
        Section {
            Picker("How often should Pip talk?", selection: $guide.chattiness) {
                ForEach(GuideChattiness.allCases) { level in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(level.title))
                        Text(LocalizedStringKey(level.detail)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .tag(level)
                }
            }
            .pickerStyle(.inline)
            .accessibilityIdentifier("liveGuide.frequency")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                if let pip = guide.lastVoiceWasPip {
                    // So testers can tell Pip's voice from the iPhone fallback.
                    Label(pip ? "Pip’s voice" : "iPhone voice", systemImage: pip ? "waveform" : "iphone")
                }
                Text("Pip mentions notable places as you walk or drive while PipPipGo is open. Your location stays on this iPhone; only the area being looked up is sent to PipPipGo.")
                Text("Place data from Google Maps and Wikipedia (CC BY-SA).")
                Text("Pip’s voice is AI-generated.")
            }
        }
    }
}

/// "🚶 9 min · 640 m → Africa Rocks Penguin Beach", with a close button.
struct LiveGuideRouteCard: View {
    let route: GuideRoute
    let close: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "figure.walk").font(.title2).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Color.blue, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: route.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                HStack(spacing: 6) {
                    if let minutes = route.minutes {
                        Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                            .font(.subheadline.weight(.semibold))
                    }
                    if let meters = route.meters {
                        Text(Measurement(value: Double(meters), unit: UnitLength.meters)
                            .formatted(.measurement(width: .abbreviated, usage: .road)))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                .accessibilityLabel(Text("Close"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct WeatherRequest: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct CurrentWeather: Decodable, Sendable, Equatable {
    let temperature_celsius: Double?
    let condition: String?
    let description: String?
    let is_daytime: Bool?
    let time_zone: String?
}

/// Apple Maps-style chip: "☀️ 75° · 5:30 PM" in local units and the place's time zone.
/// Tap for the description and source.
struct WeatherChip: View {
    let weather: CurrentWeather
    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.snappy) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).symbolRenderingMode(.multicolor)
                    if let celsius = weather.temperature_celsius {
                        Text(Measurement(value: celsius, unit: UnitTemperature.celsius)
                            .formatted(.measurement(width: .narrow, usage: .weather,
                                                    numberFormatStyle: .number.precision(.fractionLength(0)))))
                    }
                    TimelineView(.everyMinute) { context in
                        Text(context.date, format: Date.FormatStyle(date: .omitted, time: .shortened,
                                                                    timeZone: zone))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                if expanded {
                    if let description = weather.description { Text(verbatim: description).font(.caption) }
                    Text(verbatim: "Google Weather").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map.weather")
    }

    private var zone: TimeZone { weather.time_zone.flatMap(TimeZone.init(identifier:)) ?? .current }

    private var symbol: String {
        let day = weather.is_daytime ?? true
        let type = weather.condition ?? ""
        if type.contains("THUNDER") { return "cloud.bolt.rain.fill" }
        if type.contains("SNOW") || type.contains("HAIL") { return "cloud.snow.fill" }
        if type.contains("RAIN") || type.contains("SHOWER") || type.contains("DRIZZLE") { return "cloud.rain.fill" }
        if type.contains("FOG") || type.contains("HAZE") { return "cloud.fog.fill" }
        if type.contains("WIND") { return "wind" }
        if type == "CLEAR" { return day ? "sun.max.fill" : "moon.stars.fill" }
        if type.contains("PARTLY") || type.contains("MOSTLY_CLEAR") { return day ? "cloud.sun.fill" : "cloud.moon.fill" }
        if type.contains("CLOUD") { return "cloud.fill" }
        return day ? "sun.max.fill" : "moon.fill"
    }
}
