import AVFoundation
import CoreLocation
import Foundation
import MapKit
import CryptoKit
import Network
import MediaPlayer
import Observation
import OSLog
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
    var isPaused: Bool { player != nil && player?.isPlaying == false }
    var position: TimeInterval { player?.currentTime ?? 0 }
    func pause() { player?.pause() }
    func resume() { if player != nil { try? AVAudioSession.sharedInstance().setActive(true); player?.play() } }
    func seek(_ seconds: TimeInterval) { player?.currentTime = max(0, seconds) }


    func play(_ data: Data) -> Bool {
        do {
            let session = AVAudioSession.sharedInstance()
            let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.mp3.rawValue)
            // Short cues lower music briefly; longer explicit stories take spoken-audio focus.
            let short = player.duration <= 8
            try session.setCategory(.playback, mode: short ? .voicePrompt : .spokenAudio,
                                    options: short ? [.duckOthers, .interruptSpokenAudioAndMixWithOthers] : [])
            try session.setActive(true)
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

/// Connected tours, including downloaded tours, use transient Apple directions.
/// Without a connection, navigation belongs to the Maps app.
@MainActor @Observable final class TourNavigator {
    private(set) var route: GuideRoute?
    private(set) var instruction = ""
    private(set) var loading = false
    private(set) var unavailable = false
    private var ticket = UUID()
    private var request: MKDirections?
    private var key = ""
    private var checked = Date.distantPast
    private var turns: [(String, Double)] = []
    private var spoken: Set<Int> = []
    var onPrompt: ((String) -> Void)?

    func stop() {
        ticket = UUID(); request?.cancel(); request = nil; route = nil
        instruction = ""; key = ""; turns = []; spoken = []; loading = false; unavailable = false
    }
    private static func routeKey(_ progress: GuideTourProgress) -> String {
        "\(progress.plan.id):\(progress.index):\(progress.walkingStage):\(progress.navigationMode)"
    }
    func arrivalPoint(for progress: GuideTourProgress) -> GuideRoute.Point? {
        guard progress.plan.offline != true, key == Self.routeKey(progress) else { return nil }
        return route?.destination
    }
    static func resolve(_ progress: GuideTourProgress) async throws -> MKMapItem {
        guard let target = progress.navigationTarget else { throw APIClientError.invalidResponse }
        if progress.plan.offline == true || (progress.next == nil && progress.plan.round_trip) {
            // Downloaded waypoints are independently sourced coordinates. Preserve
            // the saved destination instead of searching for a similarly named place.
            let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: target.latitude, longitude: target.longitude)))
            item.name = target.name
            return item
        }
        if progress.index < progress.plan.stops.count,
           progress.plan.stops[progress.index].reason == "transport_change",
           progress.next?.id == progress.plan.stops[progress.index].place.id {
            // Provider lot names can differ. Apple independently supplies nearby
            // parking, rather than treating a golf-course name as the car park.
            let search = MKLocalPointsOfInterestRequest(center: .init(latitude: target.latitude, longitude: target.longitude), radius: 300)
            search.pointOfInterestFilter = MKPointOfInterestFilter(including: [.parking])
            let response = try await MKLocalSearch(request: search).start()
            let nearby = response.mapItems.filter {
                $0.pointOfInterestCategory == .parking && GuideGeo.distance(target.latitude, target.longitude, $0.placemark.coordinate.latitude, $0.placemark.coordinate.longitude) <= 150
            }
            guard let item = nearby.min(by: {
                GuideGeo.distance(target.latitude, target.longitude, $0.placemark.coordinate.latitude, $0.placemark.coordinate.longitude)
                    < GuideGeo.distance(target.latitude, target.longitude, $1.placemark.coordinate.latitude, $1.placemark.coordinate.longitude)
            }) else { throw APIClientError.invalidResponse }
            return item
        }
        return try await resolve(target)
    }
    static func resolve(_ target: GuideTourPlan.Point) async throws -> MKMapItem {
        let search = MKLocalSearch.Request()
        search.naturalLanguageQuery = target.name
        search.region = MKCoordinateRegion(center: .init(latitude: target.latitude, longitude: target.longitude), latitudinalMeters: 1000, longitudinalMeters: 1000)
        let response = try await MKLocalSearch(request: search).start()
        guard let item = response.mapItems.first(where: {
            GuideGeo.distance(target.latitude, target.longitude, $0.placemark.coordinate.latitude, $0.placemark.coordinate.longitude) < 500
                && ($0.name?.localizedCaseInsensitiveContains(target.name ?? "") == true || (target.name ?? "").localizedCaseInsensitiveContains($0.name ?? "----"))
        }) else { throw APIClientError.invalidResponse }
        return item
    }
    func update(_ fix: GuideFix, progress: GuideTourProgress, networkAvailable: Bool) {
        guard networkAvailable, !progress.needsWalkingConfirmation, ["walking", "driving"].contains(progress.navigationMode), let target = progress.navigationTarget else { stop(); return }
        let nextKey = Self.routeKey(progress)
        let projection = route.flatMap { GuideCorridor.project(latitude: fix.latitude, longitude: fix.longitude, path: $0.path) }
        let deviated = (projection?.across ?? 0) > (progress.navigationMode == "walking" ? 60 : 100)
        if key == nextKey, !deviated, let projection {
            if let (offset, turn) = turns.enumerated().first(where: { $0.element.1 >= projection.along - 15 }) {
                instruction = turn.0
                let lead = progress.navigationMode == "walking" ? 50.0 : 180.0
                if turn.1 - projection.along < lead, !spoken.contains(offset) {
                    spoken.insert(offset); onPrompt?(turn.0)
                }
            }
            return
        }
        guard !loading || key != nextKey, key != nextKey || Date().timeIntervalSince(checked) > 20 else { return }
        stop(); key = nextKey; checked = Date(); loading = true
        let token = ticket
        Task {
            do {
                let destination = try await Self.resolve(progress)
                guard token == ticket else { return }
                let input = MKDirections.Request()
                input.source = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: fix.latitude, longitude: fix.longitude)))
                input.destination = destination
                input.transportType = progress.navigationMode == "walking" ? .walking : .automobile
                input.requestsAlternateRoutes = false
                let directions = MKDirections(request: input); request = directions
                let response = try await directions.calculate()
                guard token == ticket else { return }
                guard let result = response.routes.first else { throw APIClientError.invalidResponse }
                var path = [CLLocationCoordinate2D](repeating: .init(), count: result.polyline.pointCount)
                result.polyline.getCoordinates(&path, range: NSRange(location: 0, length: path.count))
                route = GuideRoute(name: destination.name ?? target.name ?? "", destination: .init(latitude: destination.placemark.coordinate.latitude, longitude: destination.placemark.coordinate.longitude),
                    minutes: Int(ceil(result.expectedTravelTime / 60)), meters: Int(result.distance),
                    path: path.map { .init(latitude: $0.latitude, longitude: $0.longitude) })
                route?.mode = progress.navigationMode == "walking" ? .walking : .driving
                var along = 0.0
                turns = result.steps.compactMap { step in
                    defer { along += step.distance }
                    return step.instructions.isEmpty ? nil : (step.instructions, along)
                }
                instruction = turns.first?.0 ?? ""; unavailable = false
            } catch { if token == ticket { unavailable = true; route = nil; instruction = "" } }
            if token == ticket { loading = false }
        }
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

    /// Off whenever the app opens: the traveller starts every tour themselves.
    var enabled: Bool {
        didSet { refreshActivity() }
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
            let wasPlanned = activeTour != nil
            let wasRunning = feed != nil && !wasPlanned
            // Invalidate old requests and speech before applying the new tour mode.
            stop()
            engine.selectTourMode(tourMode)
            if wasPlanned { enabled = false; tourNotice = "Create a new tour after changing travel mode." }
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
    private(set) var suggestedTour: GuideTourPlan?
    private(set) var tourDraft: GuideTourRequest?
    private(set) var activeTour: GuideTourProgress?
    /// Saved offline tours, most recently downloaded first. Each has its own name, chosen by
    /// the traveler or a plain fallback, and can be renamed or deleted independently.
    private(set) var downloadedTours: [GuideTourPlan] = []
    private(set) var offlineRoadMap: GuideRoadMapData?
    private(set) var offlineLocation: GuideRoute.Point?
    /// A device keeps a modest number of complete voice tours; the oldest is dropped first.
    static let maxDownloadedTours = 8
    private(set) var planningTour = false
    private(set) var downloadingTour = false
    var tourNotice: String?
    @ObservationIgnored private var tourTask: Task<Void, Never>?
    @ObservationIgnored private var tourTicket = UUID()
    /// Downloads outlive the builder screen and starting a tour; only sign-out cancels them.
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var downloadTicket = UUID()
    private(set) var downloadProgress: Double = 0
    private(set) var downloadBytes = 0
    private(set) var offlinePaused = false
    var offlineQuestion = ""
    private(set) var networkAvailable = false
    private(set) var offlineClipID: String?
    @ObservationIgnored private var offlineSpoken: Set<String> = []
    @ObservationIgnored private var offlinePending: [String] = []
    @ObservationIgnored private let networkMonitor = NWPathMonitor()
    @ObservationIgnored private var interruptedAudioWasPlaying = false
    @ObservationIgnored private var audioObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var remoteTargets: [(MPRemoteCommand, Any)] = []
    private struct OfflinePlayback: Codable {
        var checkpoint: GuideTourProgress.Checkpoint; var spoken: Set<String>; var clipID: String?; var position: Double; var savedAt: Date; var pending: [String]
    }
    private static func playbackURL(_ tourID: String) -> URL { tourURL(tourID).appendingPathExtension("playback") }
    private static var stagingURL: URL { toursDirectory.appending(path: "download.partial") }
    private struct OfflineStaging: Codable { var sourceID: String; var request: String; var plan: GuideTourPlan }


    private static func playable(_ plan: GuideTourPlan) -> Bool {
        guard let package = plan.offline_package, package.verified(stopCount: plan.stops.count) else { return false }
        return package.audio.values.allSatisfy { asset in
            guard let data = Data(base64Encoded: asset.data), let player = try? AVAudioPlayer(data: data) else { return false }
            return player.duration > 0
        } && (package.images ?? []).allSatisfy { image in
            Data(base64Encoded: image.data).flatMap { UIImage(data: $0) } != nil
        }
    }
    var offlineAnswers: [GuideOfflinePackage.Clip] {
        activeTour?.plan.offline_package?.clips.filter { $0.kind == "answer" && $0.stop_index == activeTour?.index } ?? []
    }
    var offlineStories: [GuideOfflinePackage.Clip] {
        activeTour?.plan.offline_package?.clips.filter { ($0.kind == "deeper" || ($0.kind == "stop" && activeTour?.plan.offline_package?.version == 3)) && $0.stop_index == activeTour?.index } ?? []
    }
    func askOfflineQuestion() {
        guard let package = activeTour?.plan.offline_package else { return }
        if let clip = package.answer(for: offlineQuestion) { playOfflineClip(clip.id, explicit: true) }
        else { tourNotice = "That answer is not downloaded. Connect to the internet to ask Pip." }
    }
    func pauseOffline() { voicePlayer.pause(); offlinePaused = true; saveOfflinePlayback() }
    func resumeOffline() {
        guard !translator.active, !voice.active else { return }
        offlinePaused = false
        if voicePlayer.isPaused { voicePlayer.resume() }
        else if let id = offlineClipID { playOfflineClip(id, explicit: true) }
    }
    func repeatOffline() { if let id = offlineClipID { playOfflineClip(id, explicit: true) } }
    func playOfflineStory(_ id: String) { playOfflineClip(id, explicit: true) }

    private func playOfflineClip(_ id: String, explicit: Bool = false) {
        guard let progress = activeTour, let package = progress.plan.offline_package,
              !translator.active, !voice.active, !offlinePaused || explicit,
              let clip = package.clips.first(where: { $0.id == id }),
              let asset = package.audio[id], let data = Data(base64Encoded: asset.data) else { return }
        if explicit { voicePlayer.stop(); offlinePaused = false }
        guard voicePlayer.play(data) else {
            tourNotice = "Downloaded audio could not be played. Try downloading the tour again online."
            return // Never substitute device speech.
        }
        offlineClipID = id; offlineSpoken.insert(id); lastVoiceWasPip = true
        let place = clip.stop_index.flatMap { progress.plan.stops.indices.contains($0) ? progress.plan.stops[$0].place : nil }
        lastMention = LiveGuideMention(placeID: place?.id ?? id, placeName: clip.title, text: clip.text, at: Date(),
                                       inVoiceSession: false, wikipediaURL: place?.wikipedia_url.flatMap(URL.init(string:)))
        installOfflineRemoteControls()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: clip.title, MPMediaItemPropertyArtist: "PipPipGo"]
        saveOfflinePlayback()
    }
    private func installOfflineRemoteControls() {
        guard remoteTargets.isEmpty else { return }
        let commands = MPRemoteCommandCenter.shared()
        for (command, action) in [(commands.pauseCommand, 0), (commands.playCommand, 1),
                                   (commands.nextTrackCommand, 2), (commands.previousTrackCommand, 3)] {
            let token = command.addTarget { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.activeTour?.plan.offline == true else { return }
                    switch action { case 0: self.pauseOffline(); case 1: self.resumeOffline(); case 2: self.skipAnnouncement(); default: self.repeatOffline() }
                }
                return .success
            }
            remoteTargets.append((command, token))
        }
    }
    private func saveOfflinePlayback() {
        guard let progress = activeTour, progress.plan.offline == true else { return }
        let state = OfflinePlayback(checkpoint: progress.checkpoint, spoken: offlineSpoken, clipID: (voicePlayer.isPlaying || voicePlayer.isPaused) ? offlineClipID : nil, position: voicePlayer.position, savedAt: Date(), pending: offlinePending)
        let url = Self.playbackURL(progress.plan.id)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) { try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
    }


    private static var toursDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "pippipgo-tours", directoryHint: .isDirectory)
    }
    /// A filename-safe form of the server-issued tour id; ids are opaque so this never collides.
    private static func tourURL(_ tourID: String) -> URL {
        let safe = tourID.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
        return toursDirectory.appending(path: String(safe) + ".json")
    }

    /// Every verified, playable tour saved on this device, newest first.
    private static func loadDownloadedTours() -> [GuideTourPlan] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: toursDirectory, includingPropertiesForKeys: nil) else { return [] }
        let plans = files.filter { $0.pathExtension == "json" }.compactMap { url -> GuideTourPlan? in
            guard let data = try? Data(contentsOf: url), let plan = try? JSONDecoder().decode(GuideTourPlan.self, from: data),
                  plan.offline == true, playable(plan) else { return nil }
            return plan
        }
        return plans.sorted { $0.created_at > $1.created_at } // ISO 8601: newest first.
    }

    var voiceTourPlanID: String? { voice.tourPlan?.id }
    var voiceTourStartID: String? { voice.tourStartID }

    func receiveVoiceTour(start: Bool = false) {
        guard let plan = voice.tourPlan else { return }
        suggestedTour = plan
        tourDraft = plan.request
        if start, voice.tourStartID == plan.id { beginTour(plan) }
    }

    func planTourByVoice(mode: String, location: CLLocation?, transportModes: [String]? = nil) {
        guard !translator.active else { tourNotice = "Pause live translation before talking to Pip."; return }
        if voice.active { voice.stop() }
        let reliable = location.flatMap { abs($0.timestamp.timeIntervalSinceNow) < 15 && $0.course >= 0 && $0.speed >= 0.8 && (0...50).contains($0.horizontalAccuracy) ? $0 : nil }
        let context = GuideStartContext(venue: nil, nearby: [], tour_mode: mode, transport_modes: transportModes, planning_tour: true,
                                       heading: reliable?.course, heading_captured_at: reliable.map { ISO8601DateFormatter().string(from: $0.timestamp) })
        voice.start(guide: try? JSONEncoder().encode(context))
    }

    func createTour(_ request: GuideTourRequest) {
        tourDraft = request
        tourTask?.cancel()
        let ticket = UUID(); tourTicket = ticket
        planningTour = true; tourNotice = nil; suggestedTour = nil
        tourTask = Task {
            defer { if tourTicket == ticket { planningTour = false } }
            do {
                let reply: GuideTourReply = try await client.send(.post(.guideTourPlan, body: request), using: authentication)
                guard tourTicket == ticket, !Task.isCancelled else { return }
                guard let plan = reply.plan, plan.isUsable else {
                    switch reply.status {
                    case "budget_too_short": tourNotice = "The destination needs more time. Try a longer tour."
                    case "destination_ambiguous", "destination_not_found": tourNotice = "Please use a more specific destination."
                    case "route_unavailable": tourNotice = "No route was found. Try another destination or travel mode."
                    case "no_suitable_mixed_tour":
                        tourNotice = "Pip could not verify a walk back to the car within your time and walking limits. Add more time, increase the walking limit, or choose walking or driving."
                    case "ok": tourNotice = "The server returned an invalid response."
                    default: tourNotice = "No suitable tour was found. Try another direction or more time."
                    }
                    return
                }
                suggestedTour = plan
            } catch {
                guard tourTicket == ticket, !Task.isCancelled else { return }
                switch error as? APIClientError {
                case .connection:
                    tourNotice = "Could not connect to tour planning. Check your connection and try again."
                case .unauthorized:
                    tourNotice = "Your session has expired. Please sign in again."
                case .decoding, .invalidResponse:
                    tourNotice = "The server returned data this app could not read."
                case .rejected(let status, let detail, _):
                    if detail.code == "location_required" {
                        tourNotice = "Waiting for a recent location. Check location access and try again."
                    } else if status == 429 {
                        tourNotice = "You have reached today’s tour limit. Try again tomorrow."
                    } else if status == 422 {
                        tourNotice = "Tour details could not be accepted. Check your choices and try again."
                    } else {
                        tourNotice = "Tour planning is unavailable. Please try again."
                    }
                default:
                    tourNotice = "Tour planning is unavailable. Please try again."
                }
            }
        }
    }

    func cancelTourPlanning() {
        tourTicket = UUID(); tourTask?.cancel(); tourTask = nil
        planningTour = false
    }

    private func cancelDownload() {
        downloadTicket = UUID(); downloadTask?.cancel(); downloadTask = nil
        downloadingTour = false
    }

    /// Keeps any already-downloaded tour and clears the current proposal, so the builder
    /// returns to a blank form ready to plan another, separate tour.
    func planAnotherTour() {
        cancelTourPlanning()
        suggestedTour = nil; tourDraft = nil; tourNotice = nil
    }

    func hasSavedProgress(_ plan: GuideTourPlan) -> Bool { FileManager.default.fileExists(atPath: Self.playbackURL(plan.id).path) }
    func startSavedTour(_ plan: GuideTourPlan, resume: Bool) {
        if !resume { try? FileManager.default.removeItem(at: Self.playbackURL(plan.id)) }
        beginTour(plan, resume: resume)
    }
    func confirmWalking() {
        activeTour?.confirmWalking(); navigator.stop(); saveOfflinePlayback()
    }
    func beginTour(_ plan: GuideTourPlan, resume: Bool = false) {
        guard plan.isUsable, plan.offline == true || ISO8601DateFormatter.guide.date(from: plan.created_at).map({ abs($0.timeIntervalSinceNow) < 900 }) == true else {
            tourNotice = "This tour needs to be refreshed before starting."; return
        }
        if plan.offline == true, !Self.playable(plan) {
            tourNotice = "Download the complete OpenAI voice tour before offline playback."; return
        }
        cancelTourPlanning()
        enabled = false
        lastMention = nil; options = []; candidateCount = plan.stops.count
        tourMode = plan.mode == "walking" ? .walking : .driving
        engine = GuideEngine(chattiness: chattiness)
        engine.selectTourMode(tourMode); engine.plannedOnly = true
        engine.setRoute(plan.offline == true ? nil : plan.route)
        offlineSpoken = []; offlinePending = []
        activeTour = GuideTourProgress(plan: plan, started: Date())
        offlineRoadMap = plan.offline_package?.road_map?.decoded()
        offlinePaused = false; offlineClipID = nil
        if resume, plan.offline == true,
           let data = try? Data(contentsOf: Self.playbackURL(plan.id)), let saved = try? JSONDecoder().decode(OfflinePlayback.self, from: data), saved.checkpoint.planID == plan.id {
            // Explicit resume after relaunch; time away from the app does not consume the tour budget.
            var checkpoint = saved.checkpoint
            checkpoint.started = Date().addingTimeInterval(-min(Double(plan.duration_minutes * 60 - 1), max(0, saved.checkpoint.started.distance(to: saved.savedAt))))
            activeTour = GuideTourProgress(plan: plan, checkpoint: checkpoint)
            offlineSpoken = saved.spoken; offlinePending = saved.pending; offlineClipID = saved.clipID
            if let id = saved.clipID { playOfflineClip(id, explicit: true); voicePlayer.seek(saved.position) }
        }
        places = plan.offline == true ? plan.stops.map(\.place) : []
        tourNotice = nil
        enabled = true
        greetPending = false
        if plan.offline == true, !offlineSpoken.contains("intro") { playOfflineClip("intro") }
    }

    func downloadTour(_ plan: GuideTourPlan, name: String) {
        guard !downloadingTour else { return }
        let ticket = UUID(); downloadTicket = ticket
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        downloadingTour = true; tourNotice = "Preparing Pip’s stories and voice…"; downloadProgress = 0; downloadBytes = 0
        var stops: [GuideOfflineRequest.Stop] = []
        for stop in plan.stops {
            let anchor = GuideOfflineRequest.Stop(name: stop.place.name, latitude: stop.place.latitude, longitude: stop.place.longitude,
                                                  travel_mode: plan.mode == "mixed" ? "driving" : plan.mode, stop_seconds: stop.stop_seconds, role: plan.walking_segments?.contains(where: { $0.anchor_id == stop.place.id }) == true ? (plan.mode == "mixed" ? "parking" : "transfer") : "visit")
            stops.append(anchor)
            if let walk = plan.walking_segments?.first(where: { $0.anchor_id == stop.place.id }) {
                for (index, place) in walk.visits.enumerated() {
                    let seconds = walk.visit_seconds?.indices.contains(index) == true ? walk.visit_seconds![index] : (walk.stop_seconds ?? 120)
                    stops.append(.init(name: place.name, latitude: place.latitude, longitude: place.longitude, travel_mode: "walking", stop_seconds: seconds))
                }
                var returning = anchor; returning.travel_mode = "walking"; returning.stop_seconds = 0; returning.return_to_anchor = true
                stops.append(returning)
            }
        }
        let request = GuideOfflineRequest(stops: stops,
                                         duration_minutes: plan.duration_minutes, language: language, mode: plan.mode,
                                         preferences: .init(moods: plan.request?.moods ?? [], companions: plan.request?.companions ?? "solo", energy: plan.request?.energy ?? "balanced"),
                                         round_trip: plan.round_trip, origin: .init(name: "Start", latitude: plan.origin.latitude, longitude: plan.origin.longitude), include_road_map: false)
        downloadTask = Task {
            defer { if downloadTicket == ticket { downloadingTour = false } }
            do {
                let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
                let requestData = SHA256.hash(data: try encoder.encode(request)).map { String(format: "%02x", $0) }.joined()
                let cached = (try? Data(contentsOf: Self.stagingURL)).flatMap { try? JSONDecoder().decode(OfflineStaging.self, from: $0) }
                let prepared: GuideTourPlan?
                if let cached, cached.sourceID == plan.id, cached.request == requestData, cached.plan.offline_package?.version == 3 { prepared = cached.plan }
                else {
                    let reply: GuideTourReply = try await client.send(.post(.guideTourOffline, body: request), using: authentication)
                    prepared = reply.plan
                }
                guard downloadTicket == ticket, !Task.isCancelled else { return }
                guard var offline = prepared, offline.offline == true, offline.isUsable, var package = offline.offline_package, package.version == 3, package.clips.count >= 2 else {
                    tourNotice = "Offline stories are not available for every stop in this tour."; return
                }
                offline.name = name.isEmpty ? nil : String(name.prefix(60))
                try FileManager.default.createDirectory(at: Self.toursDirectory, withIntermediateDirectories: true)
                try encoder.encode(OfflineStaging(sourceID: plan.id, request: requestData, plan: offline)).write(to: Self.stagingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                downloadBytes = package.byteCount
                downloadProgress = Double(package.audio.count) / Double(package.clips.count)
                for (index, clip) in package.clips.enumerated() {
                    if package.audio[clip.id] != nil { continue }
                    let audio: GuideOfflinePackage.Audio = try await client.send(.post(.guideTourOfflineAudio, body: GuideOfflineAudioRequest(text: clip.text, voice: package.voice, personality: package.personality)), using: authentication)
                    guard downloadTicket == ticket, !Task.isCancelled else { return }
                    package.audio[clip.id] = audio
                    downloadBytes = package.byteCount
                    downloadProgress = Double(index + 1) / Double(package.clips.count)
                    offline.offline_package = package
                    try encoder.encode(OfflineStaging(sourceID: plan.id, request: requestData, plan: offline)).write(to: Self.stagingURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                }
                offline.offline_package = package
                guard Self.playable(offline) else { try? FileManager.default.removeItem(at: Self.stagingURL); throw APIClientError.invalidResponse }
                let encoded = try JSONEncoder().encode(offline)
                guard encoded.count <= 55_000_000 else { throw APIClientError.invalidResponse }
                let url = Self.tourURL(offline.id)
                try FileManager.default.createDirectory(at: Self.toursDirectory, withIntermediateDirectories: true)
                try encoded.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                // Verify the durable copy, not just the in-memory response, before claiming readiness.
                let saved = try JSONDecoder().decode(GuideTourPlan.self, from: Data(contentsOf: url))
                guard Self.playable(saved) else { throw APIClientError.invalidResponse }
                recordDownloadedTour(saved)
                try? FileManager.default.removeItem(at: Self.stagingURL)
                tourNotice = "Ready Offline. Pip’s stories and OpenAI voice are downloaded."
            } catch {
                guard downloadTicket == ticket, !Task.isCancelled else { return }
                if let apiError = error as? APIClientError,
                   case .rejected(_, let response, _) = apiError, response.code == "offline_stop_unavailable" {
                    tourNotice = "A tour stop could not be independently sourced for offline use. Try another tour."
                } else {
                    tourNotice = "The complete voice tour could not be downloaded. Please try again online."
                }
            }
        }
    }

    /// Adds or replaces a saved tour, oldest dropped first past the device limit.
    private func recordDownloadedTour(_ plan: GuideTourPlan) {
        downloadedTours.removeAll { $0.id == plan.id }
        downloadedTours.insert(plan, at: 0)
        while downloadedTours.count > Self.maxDownloadedTours {
            let removed = downloadedTours.removeLast()
            try? FileManager.default.removeItem(at: Self.tourURL(removed.id))
            try? FileManager.default.removeItem(at: Self.playbackURL(removed.id))
        }
    }

    /// A short, traveler-chosen label; blank restores the plain default name.
    func renameTour(_ tourID: String, to name: String) {
        guard let index = downloadedTours.firstIndex(where: { $0.id == tourID }) else { return }
        var plan = downloadedTours[index]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        plan.name = trimmed.isEmpty ? nil : String(trimmed.prefix(60))
        guard let data = try? JSONEncoder().encode(plan) else { return }
        try? data.write(to: Self.tourURL(tourID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        downloadedTours[index] = plan
    }

    /// Removes a saved tour from this device; it cannot be recovered without downloading again.
    func deleteTour(_ tourID: String) {
        if activeTour?.plan.id == tourID { enabled = false }
        downloadedTours.removeAll { $0.id == tourID }
        try? FileManager.default.removeItem(at: Self.tourURL(tourID))
        try? FileManager.default.removeItem(at: Self.playbackURL(tourID))
    }

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
    /// The map's latest weather ("Sunny, 24°C"), so Pip can suit suggestions to it.
    @ObservationIgnored private var weatherSummary: String?
    /// Town lookups (Apple's reverse geocoder), throttled well below Apple's limits.
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var lastAreaLookup: Date = .distantPast
    @ObservationIgnored private var lastTraceLogged: (names: [String], at: Date) = ([], .distantPast)
    /// "Why didn't Pip mention X?": searches, ranking and decisions, on the device only.
    /// Place names are public data; coordinates are never logged.
    private static let log = Logger(subsystem: "com.pippipgo.ios", category: "LiveGuide")
    @ObservationIgnored private var lastMovementFix: GuideFix?
    @ObservationIgnored private var lastSharedFix: GuideFix?
    private let speech = AVSpeechSynthesizer()
    private let voicePlayer = GuideVoicePlayer()
    let navigator = TourNavigator()
    private let navigationSpeech = AVSpeechSynthesizer()
    private var navigationSuspendedStory = false
    var navigationSpeaking: Bool { navigationSpeech.isSpeaking }
    func navigationPrompt(_ text: String) {
        guard enabled, !voice.active, !translator.active, !navigationSpeech.isSpeaking else { return }
        if voicePlayer.isPlaying { navigationSuspendedStory = true; voicePlayer.pause() }
        if speech.isSpeaking { speech.pauseSpeaking(at: .word) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: language)
        navigationSpeech.speak(utterance)
    }
    func openNavigation(provider: String? = nil) {
        guard let progress = activeTour, let target = progress.navigationTarget else { return }
        let token = epoch
        Task {
            guard epoch == token, activeTour?.plan.id == progress.plan.id else { return }
            if progress.navigationMode == "rideshare", let provider {
                guard networkAvailable else { tourNotice = "Connect to the internet to book a ride."; return }
                guard let url = progress.rideShareURL(provider: provider) else { return }
                await UIApplication.shared.open(url)
                return
            }
            if progress.plan.offline == true {
                // Independent saved coordinates work with the Maps handoff on iOS 17 too;
                // unified /directions URLs require iOS 18.4 or later.
                let item = MKMapItem(placemark: MKPlacemark(coordinate: .init(latitude: target.latitude, longitude: target.longitude)))
                item.name = target.name
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: progress.navigationMode == "walking" ? MKLaunchOptionsDirectionsModeWalking : progress.navigationMode == "transit" ? MKLaunchOptionsDirectionsModeTransit : MKLaunchOptionsDirectionsModeDriving])
            } else {
                do {
                    let item = try await TourNavigator.resolve(progress)
                    guard epoch == token, activeTour?.plan.id == progress.plan.id else { return }
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: progress.navigationMode == "walking" ? MKLaunchOptionsDirectionsModeWalking : progress.navigationMode == "transit" ? MKLaunchOptionsDirectionsModeTransit : MKLaunchOptionsDirectionsModeDriving])
                } catch {
                    guard epoch == token, activeTour?.plan.id == progress.plan.id else { return }
                    tourNotice = "Navigation is unavailable. Try again online."
                }
            }
        }
    }

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
        // Never resume a tour automatically on launch; clear the flag older builds saved.
        defaults.removeObject(forKey: Self.enabledKey)
        self.enabled = false
        self.engine = GuideEngine(chattiness: chattiness, mentioned: Set(defaults.stringArray(forKey: Self.mentionedKey) ?? []))
        self.engine.selectTourMode(tourMode)
        self.motion = engine.motion
        downloadedTours = Self.loadDownloadedTours()
        // The system manages its own audio session for the iPhone voice, leaving Talk to Pip's alone.
        speech.usesApplicationAudioSession = false
        navigationSpeech.usesApplicationAudioSession = false
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                self.networkAvailable = available
                if !available {
                    self.navigator.stop()
                    self.navigationSpeech.stopSpeaking(at: .immediate)
                }
            }
        }
        navigator.onPrompt = { [weak self] text in self?.navigationPrompt(text) }
        networkMonitor.start(queue: DispatchQueue(label: "pippipgo.tour-connectivity"))
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification] {
            let observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let interruption = notification.name == AVAudioSession.interruptionNotification
                    && (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                let unplugged = notification.name == AVAudioSession.routeChangeNotification
                    && (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue
                Task { @MainActor in
                    guard let self else { return }
                    if unplugged { self.pauseOffline(); self.interruptedAudioWasPlaying = false }
                    else if interruption {
                        self.interruptedAudioWasPlaying = self.voicePlayer.isPlaying
                        self.voicePlayer.pause(); self.saveOfflinePlayback()
                    } else if notification.name == AVAudioSession.interruptionNotification,
                              (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.ended.rawValue {
                        let options = AVAudioSession.InterruptionOptions(rawValue: notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
                        if options.contains(.shouldResume), self.interruptedAudioWasPlaying, !self.offlinePaused, !self.voice.active, !self.translator.active {
                            self.voicePlayer.resume()
                        } else if self.interruptedAudioWasPlaying { self.offlinePaused = true }
                        self.interruptedAudioWasPlaying = false
                    }
                }
            }
            audioObservers.append(observer)
        }
    }

    private var language: String {
        AppLanguage.selected(UserDefaults.standard.string(forKey: "pip.language") ?? "en").rawValue
    }

    /// Pip's picks for you: up to three nearby places chosen for this traveller; empty when unavailable.
    func picks(at location: CLLocation, weather: String?) async -> [PipPick] {
        guard activeTour?.plan.offline != true else { return [] }
        let time = Date().formatted(Date.FormatStyle(locale: Locale(identifier: "en_US_POSIX")).weekday(.abbreviated).hour().minute())
        let body = PicksRequest(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                language: language, local_time: time, weather: weather)
        let response: PicksResponse? = try? await client.send(.post(.guidePicks, body: body), using: authentication)
        return response?.picks ?? []
    }

    /// Current conditions for the map's weather chip (signed in only); nil when unavailable.
    func currentWeather(at location: CLLocation) async -> CurrentWeather? {
        guard activeTour?.plan.offline != true else { return nil }
        let body = WeatherRequest(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        let weather: CurrentWeather? = try? await client.send(.post(.weather, body: body), using: authentication)
        if let weather {
            let words = weather.description ?? weather.condition
            let temperature = weather.temperature_celsius.map { "\(Int($0.rounded()))°C" }
            weatherSummary = [words, temperature].compactMap { $0 }.joined(separator: ", ").prefix(80).description
            if weatherSummary?.isEmpty == true { weatherSummary = nil }
        }
        return weather
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
        saveOfflinePlayback()
        for (command, target) in remoteTargets { command.removeTarget(target) }
        remoteTargets = []
        if activeTour?.plan.offline == true { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil }
        navigator.stop(); navigationSpeech.stopSpeaking(at: .immediate)
        navigationSuspendedStory = false
        activeTour = nil; offlineRoadMap = nil; offlineLocation = nil
        engine.plannedOnly = false
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
        cancelTourPlanning()
        cancelDownload()
        suggestedTour = nil; downloadedTours = []; tourDraft = nil; tourNotice = nil
        stop()
        try? FileManager.default.removeItem(at: Self.toursDirectory)
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
        offlineLocation = activeTour?.plan.offline == true ? .init(latitude: fix.latitude, longitude: fix.longitude) : nil
        lastMovementFix = fix
        isWalking = fix.isMoving(at: Date())
        if isWalking { movingMapFix = fix }
        motion = engine.motion
        if status != .unavailable { status = .listening }
        if activeTour?.plan.offline != true { lookUpArea(location, ticket: ticket) }
        advance(now: Date())
    }

    /// Which town the traveller is in, every 30 s while driving and every 60 s on foot.
    private func lookUpArea(_ location: CLLocation, ticket: UUID) {
        let now = Date()
        guard now.timeIntervalSince(lastAreaLookup) >= (motion.isDriving ? 30 : 60), !geocoder.isGeocoding else { return }
        lastAreaLookup = now
        geocoder.reverseGeocodeLocation(location, preferredLocale: AppLanguage.currentLocale) { [weak self] placemarks, _ in
            Task { @MainActor in
                guard let self, self.epoch == ticket, let mark = placemarks?.first else { return }
                let area = mark.locality ?? mark.subLocality
                let before = self.engine.currentArea
                self.engine.observeArea(area, at: Date())
                if self.engine.currentArea != before, let area = self.engine.currentArea {
                    Self.log.info("area: now in \(area, privacy: .public)")
                }
            }
        }
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
        if var progress = activeTour, let fix = engine.latest {
            let previousIndex = progress.index
            if progress.plan.offline == true, let next = progress.next,
               GuideGeo.distance(fix.latitude, fix.longitude, next.latitude, next.longitude) < (progress.currentMode == .walking ? 120 : 300) {
                let id = "stop_\(progress.index)"
                if progress.plan.offline_package?.clips.contains(where: { $0.id == id }) == true, !offlineSpoken.contains(id), !offlinePending.contains(id) { offlinePending.append(id) }
            }
            progress.update(fix, at: now, arrivalPoint: navigator.arrivalPoint(for: progress))
            activeTour = progress
            if navigationSuspendedStory, !navigationSpeech.isSpeaking {
                navigationSuspendedStory = false
                if !offlinePaused { voicePlayer.resume() }
                if speech.isPaused { speech.continueSpeaking() }
            }
            navigator.update(fix, progress: progress, networkAvailable: networkAvailable)
            if progress.plan.offline == true {
                if progress.index != previousIndex, previousIndex < progress.plan.stops.count {
                    let id = "transition_\(previousIndex)"
                    if progress.plan.offline_package?.clips.contains(where: { $0.id == id }) == true, !offlineSpoken.contains(id), !offlinePending.contains(id) { offlinePending.append(id) }
                }
                offlinePending.removeAll { offlineSpoken.contains($0) }
                saveOfflinePlayback()
                if translator.active || voice.active { if voicePlayer.isPlaying { pauseOffline() }; return }
                if offlinePaused { return }
                if !offlineSpoken.contains("intro") {
                    if !busyElsewhere { playOfflineClip("intro") }
                    return
                }
                if !busyElsewhere, !offlinePending.isEmpty {
                    let id = offlinePending.removeFirst()
                    playOfflineClip(id); return
                }
            }
            if progress.expired || (progress.next == nil && (!progress.plan.round_trip || GuideGeo.distance(fix.latitude, fix.longitude, progress.plan.destination.latitude, progress.plan.destination.longitude) < 100)) {
                if progress.plan.offline == true {
                    if !busyElsewhere, !offlineSpoken.contains("complete") { playOfflineClip("complete"); return }
                    if busyElsewhere { return }
                }
                enabled = false; try? FileManager.default.removeItem(at: Self.playbackURL(progress.plan.id)); tourNotice = "Your tour is complete."; return
            }
            engine.selectTourMode(progress.currentMode)
            engine.setRoute(progress.plan.offline == true ? nil : (navigator.route ?? progress.currentRoute))
            if let next = progress.next {
                var candidate = next; candidate.tier = .mustSee
                let request = GuideNearbyRequest(latitude: fix.latitude, longitude: fix.longitude, radius_meters: 500, language: language)
                engine.update(candidates: [candidate], for: request, at: now)
                if progress.plan.offline == true {
                    let id = "stop_\(progress.index)"
                    if !busyElsewhere, !asking, !offlineSpoken.contains(id),
                       GuideGeo.distance(fix.latitude, fix.longitude, next.latitude, next.longitude) < (progress.currentMode == .walking ? 120 : 300) {
                        playOfflineClip(id)
                    }
                    return
                }
            } else { return }
            shareShortlistIfNeeded(now: now)
            evaluate(now: now)
            return
        }
        engine.setRoute(voice.route)
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
        if activeTour?.plan.offline == true { offlinePaused = false; saveOfflinePlayback() }
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
        if activeTour?.plan.offline == true, !networkAvailable {
            pauseOffline()
            tourNotice = "Offline questions use downloaded answers. Connect to the internet for a live conversation."
            return
        }
        if activeTour?.plan.offline == true { pauseOffline() }
        startConversation()
    }

    var route: GuideRoute? { activeTour == nil ? voice.route : navigator.route }
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
        let start = GuideStartContext(venue: venue.map { String($0.name.prefix(160)) }, nearby: Array(nearby.prefix(3)), tour_mode: tourMode.rawValue)
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
                engine.update(candidates: response.candidates, for: plan, at: Date(), sunset: response.sun?.sunsetDate)
                Self.logSearch(plan, response, kept: engine.candidates.count)
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

    private static func logSearch(_ plan: GuideNearbyRequest, _ response: GuideNearbyResponse, kept: Int) {
        log.info("discovery latency=\(response.diagnostics?.latency_ms ?? -1) ms search groups=\(response.diagnostics?.google_search_groups ?? -1)")
        let groups = (response.diagnostics?.groups ?? [:]).sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value.returned.map(String.init) ?? "error \($0.value.error ?? "?")")" }
            .joined(separator: " ")
        let top = response.candidates.filter { $0.tier != .minor }.prefix(10)
            .map { "\($0.name) [\($0.tier.rawValue) \(String(format: "%.2f", $0.visitorAppeal))]" }
            .joined(separator: "; ")
        let dropped = (response.diagnostics?.dropped ?? []).prefix(10).map { "\($0.name): \($0.reason)" }.joined(separator: "; ")
        log.info("search \(plan.scope ?? "around", privacy: .public) radius=\(plan.radius_meters) m found=\(response.candidates.count) keeping=\(kept) groups: \(groups, privacy: .public)")
        log.info("ranked: \(top, privacy: .public)")
        if !dropped.isEmpty { log.info("left out: \(dropped, privacy: .public)") }
    }

    /// Logs why candidates were skipped at most every 30 s, and every decision.
    private func logTrace(_ decision: GuideDecision?) {
        let trace = engine.lastTrace
        let names = trace.map(\.name)
        let now = Date()
        guard decision != nil || (names != lastTraceLogged.names && now.timeIntervalSince(lastTraceLogged.at) >= 30) else { return }
        lastTraceLogged = (names, now)
        let text = trace.map { "\($0.name): \($0.reason)" }.joined(separator: " | ")
        if let decision {
            Self.log.info("speak \(decision.situation.rawValue, privacy: .public) \(decision.place.name, privacy: .public) with \(decision.highlights.map(\.name).joined(separator: ", "), privacy: .public) — \(text, privacy: .public)")
        } else if !text.isEmpty {
            Self.log.debug("quiet — \(text, privacy: .public)")
        }
    }

    // MARK: Speaking

    private var busyElsewhere: Bool {
        interruptedAudioWasPlaying || navigationSpeech.isSpeaking || translator.active || speech.isSpeaking || voicePlayer.isPlaying || (voice.active && (!voice.acceptsGuideEvents || voice.guideShouldWait))
    }

    private func evaluate(now: Date) {
        // Never interrupts a conversation, translation or Pip already speaking.
        guard deliverTask == nil, !asking, !busyElsewhere else { return }
        let decision = engine.decide(at: now, heading: heading)
        logTrace(decision)
        if let decision { deliver(decision, asked: false) }
    }

    private func deliver(_ decision: GuideDecision, asked: Bool) {
        let ticket = epoch
        var request = decision.request(language: language)
        if let progress = activeTour {
            request.visit_kind = progress.plan.stops.first { $0.place.id == decision.place.id }?.visit_kind
            request.tour_remaining_minutes = max(0, progress.plan.duration_minutes - Int(Date().timeIntervalSince(progress.started) / 60))
        }
        let clock = ISO8601DateFormatter()
        clock.timeZone = .current
        clock.formatOptions = [.withInternetDateTime]
        request.local_time = clock.string(from: Date())
        request.weather = weatherSummary
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
    private func speak(_ text: String, audio: String? = nil, languageOverride: String? = nil) {
        guard activeTour?.plan.offline != true else { return }
        if let audio, let data = Data(base64Encoded: audio), voicePlayer.play(data) {
            lastVoiceWasPip = true
            return
        }
        lastVoiceWasPip = false
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.bestVoice(for: languageOverride ?? AppLanguage.selected(language).localizationIdentifier)
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
        let format: String.LocalizationValue = switch decision.situation {
        case .enteringCity: "Welcome to %@!"
        case .approachingCity: "You’re heading toward %@."
        case .upcoming, .approaching: "Coming up: %@."
        default: "You’re at %@."
        }
        let lead = String(format: String(localized: format, bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale), decision.place.name)
        if decision.situation == .enteringCity || decision.situation == .approachingCity { return lead }
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
            case .beach, .marina: kind = "scenic"
            case .park, .nationalPark: kind = "nature"
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
        if let progress = activeTour, progress.plan.offline == true { playOfflineClip("stop_\(progress.index)", explicit: true); return }
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
        guard activeTour?.plan.offline != true else { return }
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
        if let progress = activeTour, progress.plan.offline == true { playOfflineClip("stop_\(progress.index)", explicit: true); return }
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
    func shareMapLocation(_ location: CLLocation) {
        guard !enabled, voice.active, (0...50).contains(location.horizontalAccuracy), abs(location.timestamp.timeIntervalSinceNow) < 15 else { return }
        let fix = GuideFix(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                           accuracy: location.horizontalAccuracy, speed: location.speed, course: location.course, timestamp: location.timestamp)
        if engine.ingest(fix) { shareShortlistIfNeeded(now: Date()) }
    }

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
        if fix.course >= 0, fix.speed >= 0.8 { shortlist["heading"] = fix.course }
        if let venue = engine.enclosingVenue() { shortlist["venue"] = String(venue.name.prefix(160)) }
        Task { await voice.sendGuideEvent(["type": "guide.shortlist", "shortlist": shortlist]) }
    }
}

// MARK: - Views

/// Home screen: the tour map in the style of Apple Maps. Profile sits top left; translate,
/// language, settings and recenter float top right; one bottom panel holds what Pip is saying,
/// the blue raised-hand Ask Pip, Find nearby and the walking/driving tour controls.
/// The one map that stays on screen in every tab. Each tab adds its own panel over the map:
/// Pip's conversation, the tour, Live Translation, or Search.
struct LiveGuideTab: View {
    @Bindable var guide: LiveGuideStore
    let chat: TravelChatStore
    let tab: AppTab
    var selectTab: (AppTab) -> Void = { _ in }
    var startVoice: () -> Void = {}
    var openProfile: () -> Void = {}
    var openHistory: () -> Void = {}
    var profileName: String? = nil
    var profilePhoto: URL? = nil
    var profileInterests: String = ""
    /// Tonight's (or the next) hotel from Trips, shown on the map.
    var hotel: TripHotel? = nil
    @State private var position: MapCameraPosition = .userLocation(followsHeading: false, fallback: .automatic)
    /// The first location fix after the app opens zooms to the traveler's neighbourhood.
    @State private var zoomedToStart = false
    @State private var showTourBuilder = false
    @State private var editActiveTour = false
    @State private var showMyTours = false
    @State private var createAfterMyTours = false
    @State private var showSettings = false
    @State private var showActiveTourSources = false
    @State private var showStopQuestions = false
    @State private var confirmStopTour = false
    /// The area last fitted around the route; the camera refits only when the traveler leaves it.
    @State private var fittedRouteRect: MKMapRect?
    @State private var mapLocationFeed: LiveGuideLocationFeed?
    // Detect the marker's travel mode independently of the selected tour mode.
    @State private var currentMapCamera: MapCamera?
    @State private var nearby = NearbyPlacesModel()
    #if DEBUG
    @State private var collapsed = ProcessInfo.processInfo.arguments.contains("-PipPanelCollapsed")
    #else
    @State private var collapsed = false
    #endif
    /// Screen positions of the map's edges, the floating top bar's bottom and the panel's top, so
    /// the map frames places, the traveler and Apple's attribution between them while still
    /// drawing edge to edge under the status bar, panel and tab bar.
    @State private var panelTop: CGFloat?
    @State private var topBarBottom: CGFloat = 0
    @State private var topBarHeight: CGFloat = 220
    @State private var selectedPlace: NearbyPlace?
    @State private var pinSelection: NearbyPlace.ID?
    @State private var weather: CurrentWeather?
    @State private var weatherFetched: (location: CLLocation, at: Date)?
    @State private var hotelCoordinate: CLLocationCoordinate2D?
    @State private var lastLocation: CLLocation?
    /// "lat,lon,unix time" of where the car was left; forgotten after a day.
    @AppStorage("pip.parking") private var parking = ""
    @AppStorage("pip.mapSatellite") private var satellite = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var controlsFloatOnMap: Bool {
        guide.activeTour != nil && (tab == .guide || tab == .explore)
    }

    /// Keep controls beside the map when the window has room, including in Split View.
    /// Accessibility text uses the wider bottom panel instead of a narrow column.
    private var adaptiveMap: some View {
        GeometryReader { geometry in
            let hasPanel = tab != .search || nearby.category != nil || selectedPlace != nil
            let sidebar = horizontalSizeClass == .regular && geometry.size.width >= 760
                && geometry.size.height >= topBarHeight + 200
                && !dynamicTypeSize.isAccessibilitySize && hasPanel
            let panelWidth: CGFloat = 360
            // Measure the independent viewport, never the padded Map itself.
            // This breaks the safe-area feedback loop during keyboard presentation.
            let frame = geometry.frame(in: .global)
            map(top: frame.minY - geometry.safeAreaInsets.top,
                bottom: frame.maxY + geometry.safeAreaInsets.bottom,
                leadingInset: sidebar ? panelWidth + 32 : 0)
                .overlay(alignment: sidebar ? .bottomLeading : .bottom) {
                    if sidebar {
                        ScrollView {
                            panel
                        }
                        .frame(width: panelWidth)
                        .frame(maxHeight: collapsed ? 60 : max(160, geometry.size.height - topBarHeight - 32), alignment: .bottom)
                        .background {
                            if !controlsFloatOnMap {
                                RoundedRectangle(cornerRadius: 20).fill(.bar)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                        .padding(.leading, 16)
                        .padding(.bottom, 16)
                    } else {
                        Group {
                            if controlsFloatOnMap {
                                ViewThatFits(in: .vertical) {
                                    panel
                                    ScrollView { panel }
                                }
                                .frame(maxHeight: max(160, geometry.size.height - topBarHeight - 32), alignment: .bottom)
                            } else { panel }
                        }
                            .frame(maxWidth: 560)
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { panelTop = $0 }
                            .onDisappear { panelTop = nil }
                    }
                }
        }
    }

    var body: some View {
        ZStack {
            if showTourBuilder || showMyTours {
                // Even a covered SwiftUI Map receives keyboard inset updates on the
                // phone and simulator. Detach it during tour presentation; camera state stays here.
                Color(.systemBackground)
            } else {
                adaptiveMap
            }
        }
            .ignoresSafeArea(.keyboard)
            .overlay(alignment: .top) {
                if !showTourBuilder && !showMyTours {
                    topBar
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topBarHeight = $0 }
                }
            }
            .onAppear {
                locateMapInitially()
                updateMapPerspective()
                nearby.ratingsProvider = { [guide] category, location, radius in
                    await guide.placeRatings(category: category, location: location, radius: radius)
                }
                syncNearby()
            }
            .onChange(of: tab) { _, _ in
                collapsed = false
                syncNearby()
                updateMapPerspective()
            }
            .onChange(of: chat.translator.active) { _, active in
                if active, guide.activeTour?.plan.offline == true { guide.pauseOffline() }
            }
            .onChange(of: chat.voice.active) { _, active in
                if active, guide.activeTour?.plan.offline == true { guide.pauseOffline() }
            }
            .onChange(of: guide.voiceTourPlanID) { _, id in
                if id != nil { editActiveTour = false; guide.receiveVoiceTour(); showTourBuilder = true }
            }
            .onChange(of: guide.voiceTourStartID) { _, id in
                if id != nil { guide.receiveVoiceTour(start: true); showTourBuilder = false }
            }
            .onChange(of: scenePhase) { _, _ in syncNearby() }
            // Driving, then walking: that is where the car was left.
            .onChange(of: guide.motion) { old, new in
                if old.isDriving, new == .walking { rememberParking() }
            }
            .onChange(of: guide.tourMode) { old, new in
                if guide.enabled, old == .driving, new == .walking { rememberParking() }
            }
            .task(id: hotel) { await locateHotel() }
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
            #if DEBUG
            // Simulator review: `-PipSampleMap` shows sample weather with air quality and a parked car.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("-PipSampleMap") else { return }
                weather = CurrentWeather(temperature_celsius: 24, condition: "CLEAR", description: "Sunny",
                                         is_daytime: true, time_zone: nil, aqi: 72, aqi_category: "Good air quality")
                parking = "32.9412,-117.2318,\(Date().timeIntervalSince1970)"
            }
            // Simulator review: `-PipHomeTab search -PipGuestCategory restrooms` searches once located.
            .task {
                let arguments = ProcessInfo.processInfo.arguments
                guard let index = arguments.firstIndex(of: "-PipGuestCategory"), index + 1 < arguments.count,
                      let category = GuestCategory(rawValue: arguments[index + 1]) else { return }
                for _ in 0..<40 where nearby.location == nil { try? await Task.sleep(for: .milliseconds(250)) }
                nearby.search(category)
            }
            #endif
            .onDisappear {
                mapLocationFeed?.stop()
                mapLocationFeed = nil
                nearby.stop()
            }
            // Editing in a sheet over the live Map triggers MapKit edge-inset/corner
            // observation loops on the connected iOS 27 phone when its keyboard opens.
            // Present full-screen while the background map is detached above.
            .fullScreenCover(isPresented: $showTourBuilder, onDismiss: { guide.cancelTourPlanning() }) {
                TourBuilderView(guide: guide, location: lastLocation, profileInterests: profileInterests, editActiveTour: editActiveTour)
            }
            .fullScreenCover(isPresented: $showMyTours, onDismiss: {
                if createAfterMyTours {
                    createAfterMyTours = false; editActiveTour = false; showTourBuilder = true
                }
            }) {
                MyToursView(guide: guide, onStart: { showMyTours = false }, createTour: {
                    createAfterMyTours = true; showMyTours = false
                })
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form { LiveGuideSettingsSection(guide: guide) }
                        .navigationTitle("Tour Guide").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showSettings = false } } }
                }
                .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showActiveTourSources) {
                if let package = guide.activeTour?.plan.offline_package {
                    OfflineTourSourcesView(package: package)
                }
            }
            .sheet(isPresented: $showStopQuestions) {
                NavigationStack {
                    ScrollView { OfflineTourQuestions(guide: guide).padding() }
                        .navigationTitle("Ask about this stop").navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showStopQuestions = false } } }
                }
                .presentationDetents([.medium, .large])
            }
    }

    /// Search uses location only while its tab is open and the app is on screen.
    private func syncNearby() {
        if tab == .search && scenePhase == .active { nearby.start() } else { nearby.stop() }
    }

    /// Keep map location separate from the tour so Stop still allows GPS following.
    /// This foreground-only feed stops when the map disappears.
    private func locateMapInitially() {
        guard mapLocationFeed == nil else { return }
        let feed = LiveGuideLocationFeed()
        mapLocationFeed = feed
        feed.onLocation = { location in
            guard location.horizontalAccuracy >= 0,
                  abs(location.timestamp.timeIntervalSinceNow) < 15,
                  CLLocationCoordinate2DIsValid(location.coordinate) else { return }
            lastLocation = location
            guide.shareMapLocation(location)
            refreshWeather(location)
            if !zoomedToStart {
                // Before any fix the map shows a whole continent; never keep that zoom.
                zoomedToStart = true
                if tab != .explore, guide.activeTour != nil, let route = guide.route {
                    fitRoute(route, including: location)
                } else if tab == .explore {
                    position = .camera(MapCamera(centerCoordinate: location.coordinate, distance: 1_200, pitch: 60))
                } else {
                    withAnimation { position = .region(MKCoordinateRegion(center: location.coordinate,
                                                                          latitudinalMeters: 1_200, longitudinalMeters: 1_200)) }
                }
                return
            }
            let usable = currentMapCamera.flatMap { $0.distance < 50_000 ? $0 : nil }
            var camera = usable ?? MapCamera(
                centerCoordinate: location.coordinate,
                distance: max(800, location.horizontalAccuracy * 4), heading: 0, pitch: 0)
            camera.centerCoordinate = location.coordinate
            if tab == .explore {
                guard !position.positionedByUser else { return }
                camera.pitch = 60
                position = .camera(camera)
            } else if let route = guide.route, guide.activeTour != nil {
                // Keep the route framed; refit only once the traveler moves outside it.
                guard !position.positionedByUser else { return }
                if fittedRouteRect.map({ !$0.contains(MKMapPoint(location.coordinate)) }) ?? true {
                    fitRoute(route, including: location)
                }
            } else if guide.enabled {
                withAnimation(.linear(duration: 0.5)) { position = .camera(camera) }
            } else {
                // Keep native tracking enabled, including zero-speed coordinate updates.
                position = .userLocation(followsHeading: false, fallback: .camera(camera))
            }
        }
        feed.start()
    }

    /// Frames the traveler, route path and destination with a little margin, never closer
    /// than about 500 m across so a short walk keeps its surroundings.
    private func fitRoute(_ route: GuideRoute, including location: CLLocation?) {
        var points = route.path.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        points.append(MKMapPoint(CLLocationCoordinate2D(latitude: route.destination.latitude, longitude: route.destination.longitude)))
        if let location { points.append(MKMapPoint(location.coordinate)) }
        var rect = points.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: MKMapSize(width: 0, height: 0))) }
        guard !rect.isNull else { return }
        let minimum = 500 * MKMapPointsPerMeterAtLatitude(MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude)
        rect = rect.insetBy(dx: -max(0, minimum - rect.width) / 2, dy: -max(0, minimum - rect.height) / 2)
        rect = rect.insetBy(dx: -rect.width * 0.06, dy: -rect.height * 0.06)
        fittedRouteRect = rect
        withAnimation { position = .rect(rect) }
    }

    private func updateMapPerspective() {
        if tab != .explore, guide.activeTour != nil, let route = guide.route {
            fitRoute(route, including: lastLocation); return
        }
        guard var camera = currentMapCamera ?? lastLocation.map({ MapCamera(centerCoordinate: $0.coordinate, distance: 1_200) }) else { return }
        camera.pitch = tab == .explore ? 60 : 0
        position = .camera(camera)
    }

    private var showsOfflineRoadMap: Bool {
        tab == .guide && !guide.networkAvailable && guide.activeTour?.plan.offline == true && guide.offlineRoadMap != nil
    }

    @ViewBuilder private func map(top mapTop: CGFloat, bottom mapBottom: CGFloat, leadingInset: CGFloat) -> some View {
        if showsOfflineRoadMap, let roads = guide.offlineRoadMap {
            OfflineRoadMapView(data: roads, stops: guide.activeTour?.plan.stops ?? [],
                               location: guide.offlineLocation ?? lastLocation.map { .init(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) },
                               origin: guide.activeTour.map { .init(latitude: $0.plan.origin.latitude, longitude: $0.plan.origin.longitude) })
                .safeAreaPadding(.top, max(0, topBarBottom - mapTop))
                .safeAreaPadding(.bottom, max(0, mapBottom - (panelTop ?? mapBottom)))
                .ignoresSafeArea()
        } else {
        Map(position: $position, selection: $pinSelection) {
            UserAnnotation()
            ForEach(guide.places) { place in
                Marker(place.name, systemImage: place.tier == .mustSee ? "star.fill" : "mappin",
                       coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                    .tint(place.tier == .mustSee ? .orange : .blue)
            }
            // The traveller's own places show on every tab.
            if let hotel, let hotelCoordinate {
                Marker(hotel.name, systemImage: "bed.double.fill", coordinate: hotelCoordinate).tint(.indigo)
            }
            if let car = parkedCar {
                Marker("You parked here", systemImage: "car.fill", coordinate: car.coordinate).tint(.blue)
            }
            if tab == .search {
                ForEach(nearby.places) { place in
                    Marker(place.name, systemImage: nearby.category?.symbol ?? "mappin", coordinate: place.coordinate)
                        .tint(nearby.category?.tint ?? .red)
                        .tag(place.id)
                }
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
        // Keep the Metal-backed map alive across tab/annotation changes. The tour
        // editor temporarily detaches it to avoid the device keyboard observation loop.
        .onChange(of: guide.route) { old, route in
            // Show the whole route: traveler, path and destination, not every marker on the map.
            guard let route else { fittedRouteRect = nil; return }
            if old?.destination != route.destination || !position.positionedByUser {
                fitRoute(route, including: lastLocation)
            }
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            currentMapCamera = context.camera
        }
        .mapStyle(satellite
            ? .hybrid(elevation: tab == .explore ? .realistic : .flat, pointsOfInterest: .excludingAll)
            : .standard(elevation: tab == .explore ? .realistic : .flat, pointsOfInterest: .excludingAll))
        .safeAreaPadding(.leading, leadingInset)
        .safeAreaPadding(.top, max(0, topBarBottom - mapTop))
        .safeAreaPadding(.bottom, max(0, mapBottom - (panelTop ?? mapBottom)))
        // Full screen like Google Maps: the map runs under the status bar, panel and tab bar.
        .ignoresSafeArea()
        }
    }

    private var parkedCar: CLLocation? {
        let parts = parking.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 3, Date().timeIntervalSince1970 - parts[2] < 86_400 else { return nil }
        return CLLocation(latitude: parts[0], longitude: parts[1])
    }

    private func rememberParking() {
        guard let location = lastLocation else { return }
        parking = "\(location.coordinate.latitude),\(location.coordinate.longitude),\(Date().timeIntervalSince1970)"
    }

    /// "🚗 Car · 6 min": walking directions back to the car; hold to forget the spot.
    private func parkingChip(_ car: CLLocation) -> some View {
        let minutes = lastLocation.map { max(1, Int(($0.distance(from: car) / 80).rounded())) }
        return Button {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: car.coordinate))
            item.name = String(localized: "You parked here", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "car.fill").foregroundStyle(.blue)
                Text("Car")
                if let minutes {
                    Text(Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated)))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Forget parking spot", systemImage: "trash", role: .destructive) { parking = "" }
        }
        .accessibilityIdentifier("map.parking")
    }

    /// Finds the hotel's address with Apple Maps, on the phone.
    private func locateHotel() async {
        hotelCoordinate = nil
        guard let hotel else { return }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = [hotel.name, hotel.address].filter { !$0.isEmpty }.joined(separator: ", ")
        hotelCoordinate = try? await MKLocalSearch(request: request).start().mapItems.first?.placemark.coordinate
    }

    /// Google Maps-style top: one floating search bar, category chips, then weather and the
    /// round map controls.
    private var topBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    if let active = guide.activeTour, tab == .guide || tab == .explore {
                        Text(verbatim: active.plan.displayName).font(.headline).lineLimit(2)
                            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("tour.activeName")
                        Spacer(minLength: 0)
                    } else if tab == .search {
                        searchBar
                    } else {
                        Spacer(minLength: 0)
                    }
                    Button(action: openProfile) {
                        ProfileAvatar(name: profileName, photo: profilePhoto, size: 36)
                            .frame(width: 52, height: 52)
                    }
                    .accessibilityLabel(Text("Profile"))
                    .accessibilityIdentifier("navigation.profile")
                }
                .padding(.horizontal, 12)
                if tab == .search { categoryChips }
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { topBarBottom = $0 }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    if !showsOfflineRoadMap {
                    if let weather, tab != .guide, tab != .explore { WeatherChip(weather: weather) }
                    if let car = parkedCar { parkingChip(car) }
                    Button { satellite.toggle() } label: {
                        Image(systemName: satellite ? "map" : "square.2.layers.3d").font(.title3).mapControlCircle()
                    }
                    .accessibilityLabel(Text("Map style"))
                    .accessibilityIdentifier("map.style")
                    }
                    if AppConfiguration.live.environment != .prod {
                        BuildEnvironmentIndicator(environment: AppConfiguration.live.environment)
                    }
                }
                Spacer(minLength: 8)
                if !showsOfflineRoadMap { floatingControls }
            }
            .padding(.horizontal, 12)
            // During a tour the route is shown in the Next card at the bottom instead.
            if let route = guide.route, !controlsFloatOnMap {
                LiveGuideRouteCard(route: route, close: guide.clearRoute).padding(.horizontal, 60)
            }
        }
        .padding(.top, 4)
    }

    /// "Search or ask Pip": tap to search nearby; the microphone talks to Pip.
    private var searchBar: some View {
        HStack(spacing: 10) {
            Button { selectTab(.search) } label: {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    Text("Search or ask Pip").foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("map.search")
            Button { if guide.activeTour?.plan.offline == true { guide.toggleConversation() } else { startVoice() } } label: {
                TimelineView(.periodic(from: .now, by: 0.3)) { _ in
                    Group {
                        switch PipVoicePhase(chat.voice) {
                        case .none:
                            Image(systemName: "mic.fill").foregroundStyle(.blue)
                        case .speaking?:
                            Image(systemName: "waveform").foregroundStyle(.blue)
                                .symbolEffect(.variableColor.iterative, isActive: true)
                        case .listening?:
                            Image(systemName: "mic.fill").foregroundStyle(.green)
                                .symbolEffect(.pulse, isActive: true)
                        default:
                            ProgressView()
                        }
                    }
                    .font(.title3).frame(width: 40, height: 40)
                }
            }
            .accessibilityLabel(Text("Ask Pip"))
            .accessibilityIdentifier("map.askPip")
        }
        .font(.body)
        .padding(.leading, 16).padding(.trailing, 6)
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
    }

    /// One tap: Restrooms, Transit, Food… opens Search with that category on the map.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(GuestCategory.allCases) { category in
                    Button {
                        selectTab(.search)
                        collapsed = false
                        selectedPlace = nil
                        nearby.search(category)
                    } label: {
                        Label { Text(category.title) } icon: {
                            Image(systemName: category.symbol).foregroundStyle(category.tint)
                        }
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(.regularMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("map.chip.\(category.rawValue)")
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 2)
        }
    }

    /// Only while the app is open on screen; every 15 minutes, or after moving about 3 km.
    private func refreshWeather(_ location: CLLocation) {
        guard scenePhase == .active else { return }
        if let last = weatherFetched, Date().timeIntervalSince(last.at) < 900,
           location.distance(from: last.location) < 3_000 { return }
        weatherFetched = (location, Date())
        Task { if let current = await guide.currentWeather(at: location) { weather = current } }
    }

    /// Apple Maps-style floating buttons.
    private var floatingControls: some View {
        VStack(spacing: 8) {
            AppLanguageMenu().mapControlCircle()
            AudioOutputButton().mapControlCircle()
            if (tab == .guide || tab == .explore) && guide.activeTour == nil {
                // Settings here are specifically how often Pip speaks; during a tour they are in More.
                Button { showSettings = true } label: {
                    Image(systemName: "speaker.wave.2").font(.title3).mapControlCircle()
                }
                .accessibilityLabel(Text("Settings"))
                .accessibilityIdentifier("liveGuide.settings")
            }
            if tab == .pip {
                Button(action: openHistory) {
                    Image(systemName: "clock.arrow.circlepath").font(.title3).mapControlCircle()
                }
                .accessibilityLabel(Text("Conversation history"))
                .accessibilityIdentifier("pip.history")
            }
            Button {
                withAnimation { position = .userLocation(followsHeading: false, fallback: .automatic) }
            } label: {
                Image(systemName: "location.fill").font(.title3).mapControlCircle()
            }
            .accessibilityLabel(Text("Recenter"))
        }
    }

    /// One Apple Maps-style panel above the tab bar; its content follows the selected tab.
    @ViewBuilder private var panel: some View {
        if controlsFloatOnMap {
            activeTourMapControls
                .padding(.horizontal, 16).padding(.vertical, 12)
        } else if tab != .search || nearby.category != nil || selectedPlace != nil {
            VStack(alignment: .leading, spacing: 14) {
                if !controlsFloatOnMap { PanelHandle(collapsed: $collapsed) }
                switch tab {
                case .pip:
                    PipPanel(chat: chat, collapsed: collapsed)
                case .translate:
                    if !collapsed { InlineTranslationPanel(store: chat.translator) }
                case .search:
                    if !collapsed {
                        NearbyFinder(model: nearby, selected: $selectedPlace) { place in
                            withAnimation { position = .item(place.item) }
                        }
                    }
                case .guide, .explore:
                    guidePanel
                }
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
            .background {
                if !controlsFloatOnMap {
                    UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16)
                        .fill(.bar).opacity(collapsed ? 0 : 1)
                        .ignoresSafeArea(edges: .bottom)
                }
            }
        }
    }

    /// One card: where to go next, one primary navigation button, one row of equal playback
    /// buttons, and everything else in the More menu.
    @ViewBuilder private var activeTourMapControls: some View {
        if let progress = guide.activeTour {
            let offline = progress.plan.offline == true
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        if let next = progress.next {
                            let route = guide.navigator.route
                            let name = guide.navigator.arrivalPoint(for: progress) == nil ? next.name : (route?.name ?? next.name)
                            if let route {
                                Image(systemName: route.mode == .driving ? "car.fill" : "figure.walk").font(.title3).foregroundStyle(.white)
                                    .frame(width: 44, height: 44).background(Color.blue, in: Circle())
                                    .accessibilityHidden(true)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Next: \(name)").font(.headline).lineLimit(2)
                                if let route { RouteETA(route: route) }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(route == nil ? "tour.next" : "tour.routeCard")
                        } else {
                            Spacer(minLength: 0)
                        }
                        activeTourMenu(progress)
                    }
                    TourNavigationControls(guide: guide, endTour: { confirmStopTour = true })
                    if offline {
                        OfflineTourPlaybackControls(guide: guide)
                    } else if guide.announcementSpeaking, !guide.talking {
                        TourControlButton(title: "Skip", systemImage: "forward.end.fill") { guide.skipAnnouncement() }
                            .accessibilityIdentifier("liveGuide.skipAnnouncement")
                    }
                }
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                if let notice = guide.notice {
                    Label(LocalizedStringKey(notice), systemImage: "exclamationmark.circle")
                        .font(.subheadline).padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if let message = guide.tourNotice {
                    Text(LocalizedStringKey(message)).font(.subheadline).padding(8)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if guide.status == .denied {
                    Button("Open location settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }.buttonStyle(.bordered).frame(minHeight: 44)
                }
                if !offline, let mention = guide.lastMention {
                    LiveGuideMentionView(mention: mention, guide: guide)
                }
            }
            .confirmationDialog("End this tour?", isPresented: $confirmStopTour, titleVisibility: .visible) {
                Button("End Tour", role: .destructive) { withAnimation(.spring) { guide.enabled = false } }
                    .accessibilityIdentifier("tour.stopConfirm")
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    /// Less frequent tour actions.
    private func activeTourMenu(_ progress: GuideTourProgress) -> some View {
        Menu {
            Button("Adjust Tour", systemImage: "slider.horizontal.3") { editActiveTour = true; showTourBuilder = true }
                .accessibilityIdentifier("liveGuide.adjustTour")
            if progress.plan.offline == true, progress.plan.offline_package?.version != 3 {
                Button("Ask about this stop", systemImage: "questionmark.bubble") { showStopQuestions = true }
                    .accessibilityIdentifier("tour.askStop")
            }
            if progress.plan.offline == true, guide.networkAvailable {
                Button("Talk to Pip online", systemImage: "waveform") { guide.toggleConversation() }
            }
            if progress.plan.offline_package != nil {
                Button("Sources and licenses", systemImage: "doc.text") { showActiveTourSources = true }
                    .accessibilityIdentifier("tour.sources")
            }
            Button("Settings", systemImage: "speaker.wave.2") { showSettings = true }
                .accessibilityIdentifier("liveGuide.settings")
        } label: {
            Image(systemName: "ellipsis").font(.title3.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(.thinMaterial, in: Circle())
                .contentShape(Circle())
        }
        .accessibilityLabel(Text("More options"))
        .accessibilityIdentifier("tour.more")
    }

    /// Explore Freely and tour start. An active tour uses `activeTourMapControls` instead.
    @ViewBuilder private var guidePanel: some View {
        if guide.enabled {
            Button(role: .destructive) { withAnimation(.spring) { guide.enabled = false } } label: {
                Label("Stop tour", systemImage: "stop.fill")
                    .font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(Color(red: 0.75, green: 0.15, blue: 0.12))
            .accessibilityIdentifier("liveGuide.enabled")
        } else {
            if tab == .guide {
                if !guide.networkAvailable, !guide.downloadedTours.isEmpty {
                    // Offline: guide the traveler straight to what will actually work.
                    Text("You’re offline. Play one of your downloaded tours.").font(.subheadline).foregroundStyle(.secondary)
                    Button { showMyTours = true } label: {
                        Label("My Tours (\(guide.downloadedTours.count))", systemImage: "list.bullet")
                            .font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("liveGuide.myTours")
                } else {
                    Button { editActiveTour = false; showTourBuilder = true } label: {
                        Label("Create My Tour", systemImage: "sparkles")
                            .font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    .disabled(!guide.networkAvailable)
                    .accessibilityIdentifier("liveGuide.createTour")
                    if !guide.networkAvailable {
                        Text("You’re offline. Connect to the internet to plan a new tour.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button { showMyTours = true } label: {
                        Label {
                            if guide.downloadedTours.isEmpty { Text("My Tours") }
                            else { Text("My Tours (\(guide.downloadedTours.count))") }
                        } icon: { Image(systemName: "list.bullet") }
                    }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("liveGuide.myTours")
                }
            }
            if tab == .explore {
                Picker("Tour mode", selection: $guide.tourMode) {
                    ForEach(GuideTourMode.allCases) { mode in
                        Image(systemName: mode.symbol)
                            .accessibilityLabel(Text(LocalizedStringKey(mode.title)))
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("liveGuide.tourMode")
                Button {
                    withAnimation(.spring) { guide.enabled = true }
                } label: {
                    Label("Explore Freely", systemImage: "play.fill")
                        .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .tint(.accentColor)
                .accessibilityIdentifier("liveGuide.startGuide")
            }
        }
        if guide.downloadingTour, !collapsed { TourDownloadProgressRow(guide: guide) }
        else if let message = guide.tourNotice { Text(LocalizedStringKey(message)).font(.subheadline).foregroundStyle(.secondary) }
        if guide.enabled, guide.status != .listening {
            Label(LocalizedStringKey(guide.status.message), systemImage: statusSymbol)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        if let notice = guide.notice {
            Label(LocalizedStringKey(notice), systemImage: "exclamationmark.circle")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        if guide.status == .denied {
            Button("Open location settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .buttonStyle(.bordered)
        }
        if !collapsed, guide.enabled, guide.tourMode == .driving {
            Label("Driving? Keep your eyes on the road and talk to Pip instead.", systemImage: "car.fill")
                .font(.footnote).foregroundStyle(.secondary)
        }
        if guide.enabled, guide.announcementSpeaking, !guide.talking {
            Button { guide.skipAnnouncement() } label: {
                Label("Skip announcement", systemImage: "forward.end.fill").frame(minHeight: 44)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("liveGuide.skipAnnouncement")
        }
        if !collapsed, guide.enabled, let mention = guide.lastMention {
            LiveGuideMentionView(mention: mention, guide: guide)
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
            Image(systemName: route.mode == .driving ? "car.fill" : "figure.walk").font(.title2).foregroundStyle(.white)
                .frame(width: 44, height: 44).background(Color.blue, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: route.name).font(.headline).foregroundStyle(.primary).lineLimit(2)
                RouteETA(route: route)
            }
            Spacer(minLength: 0)
            Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }
                .accessibilityLabel(Text("Close"))
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tour.routeCard")
    }
}

/// "19 min  17 mi" in the traveler's locale and units.
struct RouteETA: View {
    let route: GuideRoute
    var body: some View {
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
    var aqi: Int? = nil
    var aqi_category: String? = nil
}

/// Tonight's or the next hotel from the traveller's trips.
struct TripHotel: Equatable, Hashable {
    let name: String
    let address: String
}

/// Apple Maps-style weather chip with temperature in local units.
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
                    if let aqi = weather.aqi {
                        // Universal AQI: higher is cleaner air.
                        Circle().fill(aqi >= 60 ? Color.green : aqi >= 40 ? .yellow : aqi >= 20 ? .orange : .red)
                            .frame(width: 8, height: 8).accessibilityHidden(true)
                        Text(verbatim: "AQI \(aqi)").foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.semibold))
                if expanded {
                    if let description = weather.description { Text(verbatim: description).font(.caption) }
                    if let category = weather.aqi_category { Text(verbatim: category).font(.caption) }
                    Text(verbatim: "Google Weather").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map.weather")
    }

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

extension View {
    /// See-through round map control, spaced apart like Apple Maps buttons.
    func mapControlCircle() -> some View {
        self.frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: Circle())
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1)
    }
}

/// The traveler's photo, or their initials (such as "SN") on a coloured circle.
struct ProfileAvatar: View {
    let name: String?
    let photo: URL?
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photo {
                AsyncImage(url: photo) { image in image.resizable().scaledToFill() } placeholder: { initials }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 2))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 1)
        .frame(width: max(44, size + 4), height: max(44, size + 4))
    }

    private var initials: some View {
        let letters = (name ?? "")
            .split(separator: " ").prefix(2)
            .compactMap(\.first).map { String($0).uppercased() }.joined()
        return ZStack {
            Circle().fill(Color(red: 0.16, green: 0.39, blue: 0.85))
            if letters.isEmpty {
                Image(systemName: "person.fill").foregroundStyle(.white)
            } else {
                Text(verbatim: letters).font(.headline).foregroundStyle(.white)
            }
        }
    }
}

struct PicksRequest: Encodable, Sendable {
    let latitude: Double
    let longitude: Double
    let language: String
    let local_time: String?
    let weather: String?
}

struct PipPick: Decodable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let latitude: Double
    let longitude: Double
    let rating: Double?
    let user_rating_count: Int?
    let reason: String?
}

struct PicksResponse: Decodable, Sendable {
    let picks: [PipPick]
}

/// Apple supplies preview geometry independently of the planner's route provider.
private struct AppleTourPreview: View {
    let plan: GuideTourPlan
    @State private var routes: [MKRoute] = []
    @State private var loading = true
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview route in Apple Maps").font(.headline)
            Map {
                Marker("Start", systemImage: "flag", coordinate: coordinate(plan.origin))
                ForEach(Array(plan.stops.enumerated()), id: \.element.place.id) { index, stop in
                    Marker("\((index + 1).formatted()). \(stop.place.name)", coordinate: CLLocationCoordinate2D(latitude: stop.place.latitude, longitude: stop.place.longitude))
                }
                ForEach(plan.walking_segments ?? [], id: \.place.id) { walk in
                    ForEach(walk.visits) { place in
                        Marker(place.name, systemImage: "figure.walk", coordinate: CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude))
                    }
                }
                Marker("Destination", systemImage: "flag.checkered", coordinate: coordinate(plan.destination))
                ForEach(Array(routes.enumerated()), id: \.offset) { _, route in
                    MapPolyline(route.polyline).stroke(.blue, lineWidth: 4)
                }
            }
            .mapControls { MapCompass(); MapScaleView() }
            .frame(height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityIdentifier("tourBuilder.appleMap")
            if loading { ProgressView().accessibilityLabel("Preview route in Apple Maps") }
            if failed {
                Text("Map preview is unavailable. You can still review the stops below.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Apple Maps may update the route and travel estimate.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: plan.id) { await loadRoutes() }
    }

    private func coordinate(_ point: GuideTourPlan.Point) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
    }

    @MainActor private func loadRoutes() async {
        routes = []; loading = true; failed = false
        defer { loading = false }
        var points = [coordinate(plan.origin)]
        points += plan.stops.map { CLLocationCoordinate2D(latitude: $0.place.latitude, longitude: $0.place.longitude) }
        points.append(coordinate(plan.destination))
        var legs = zip(points, points.dropFirst()).map { ($0, $1, plan.mode == "walking") }
        for walk in plan.walking_segments ?? [] {
            guard let anchor = plan.stops.first(where: { $0.place.id == walk.anchor_id }) else { continue }
            let from = CLLocationCoordinate2D(latitude: anchor.place.latitude, longitude: anchor.place.longitude)
            let points = [from] + walk.visits.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } + [from]
            legs += zip(points, points.dropFirst()).map { ($0.0, $0.1, true) }
        }
        var calculated: [MKRoute] = []
        do {
            for (from, to, walking) in legs {
                try Task.checkCancellation()
                if CLLocation(latitude: from.latitude, longitude: from.longitude).distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude)) < 20 { continue }
                let request = MKDirections.Request()
                request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
                request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
                request.transportType = walking ? .walking : plan.mode == "transit" ? .transit : .automobile
                let directions = MKDirections(request: request)
                let response = try await withTaskCancellationHandler {
                    try await directions.calculate()
                } onCancel: { directions.cancel() }
                try Task.checkCancellation()
                guard let route = response.routes.first else { failed = true; return }
                calculated.append(route)
            }
            routes = calculated
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

private struct TourPlanningProgressView: View {
    var cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floating = false

    var body: some View {
        VStack(spacing: 20) {
            PipWelcomeArtwork()
                .frame(width: 120)
                .offset(y: reduceMotion ? 0 : floating ? -6 : 6)
                .animation(reduceMotion ? nil : .easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: floating)
                .accessibilityHidden(true)
            if !reduceMotion { ProgressView().controlSize(.large).accessibilityHidden(true) }
            Text("Creating your tour…").font(.title2.weight(.semibold))
                .accessibilityAddTraits(.updatesFrequently)
            Text("Finding places and checking routes.")
                .font(.body).foregroundStyle(.secondary)
            Button("Cancel", action: cancel)
                .frame(minWidth: 100, minHeight: 44).buttonStyle(.bordered)
                .accessibilityIdentifier("tourBuilder.cancelPlanning")
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("tourBuilder.planning")
        .onAppear { floating = true }
    }
}

/// One page: the three main choices, optional personal details, then a reviewable tour.
private struct TourBuilderView: View {
    @Bindable var guide: LiveGuideStore
    let location: CLLocation?
    var profileInterests: String = ""
    var editActiveTour = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var liveLocation: CLLocation?
    @State private var locationFeed: LiveGuideLocationFeed?
    @State private var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @State private var locationClock = Date()

    private var currentLocation: CLLocation? { liveLocation ?? location }

    @State private var minutes = 30
    @State private var customTime = false
    @State private var transportModes: Set<String> = ["walking"]
    private var mode: String { transportModes.sorted().first ?? "walking" }
    private let transportOptions = [("walking", "Walking"), ("driving", "Driving"),
                                    ("rideshare", "Ride Share"), ("transit", "Public transport")]
    @State private var moods: Set<String> = []
    @State private var personal = false
    @State private var companions = ""
    @State private var energy = "balanced"
    @State private var food = "none"
    @State private var cuisine = ""
    @State private var dietary = ""
    @State private var direction = "surprise"
    @State private var area = ""
    @State private var activities = ""
    @State private var destination = ""
    @State private var roundTrip = false
    @State private var walkingLimit = 4000
    @State private var preview = false
    @State private var tourName = ""
    @State private var failureMessage: String?

    private var reliableHeading: Double? {
        guard let location = currentLocation, abs(location.timestamp.timeIntervalSinceNow) < 15,
              location.course >= 0, location.speed >= 0.8,
              location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 50 else { return nil }
        return location.course
    }
    private var locationReady: Bool {
        guard locationAuthorization != .denied, locationAuthorization != .restricted,
              let location = currentLocation else { return false }
        return abs(location.timestamp.timeIntervalSince(locationClock)) < 120 && (0...100).contains(location.horizontalAccuracy)
            && CLLocationCoordinate2DIsValid(location.coordinate)
    }
    private var movingDriver: Bool { transportModes == ["driving"] && (currentLocation?.speed ?? 0) > 2.2 }
    private let columns = [GridItem(.adaptive(minimum: 115), spacing: 8)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let message = guide.tourNotice, !preview {
                        Label { Text(LocalizedStringKey(message)) } icon: { Image(systemName: "info.circle") }
                            .font(.subheadline)
                            .accessibilityIdentifier("tourBuilder.notice")
                    }
                    if preview, let plan = guide.suggestedTour {
                        tourPreview(plan)
                    } else {
                        HStack(spacing: 16) {
                            PipWelcomeArtwork().frame(width: 88).accessibilityHidden(true)
                            Text("Let’s make a little time for something wonderful.").font(.title3.weight(.medium))
                        }
                        section("How much time do you have?") {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach([30, 60, 120, 240, 480], id: \.self) { value in
                                    chip(durationTitle(value), selected: minutes == value && !customTime) { minutes = value; customTime = false }
                                }
                                chip("Custom", selected: customTime) { customTime = true }
                            }
                            if customTime { Stepper("\(minutes) minutes", value: $minutes, in: 5...480, step: 5) }
                        }
                        section("How would you like to explore?") {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(transportOptions, id: \.0) { id, title in
                                    chip(title, selected: transportModes.contains(id)) {
                                        if !transportModes.insert(id).inserted { transportModes.remove(id) }
                                    }
                                    .accessibilityIdentifier("tourBuilder.transport.\(id)")
                                }
                            }
                        }
                        section("Have something in mind?") {
                            TextField("Area or park (optional)", text: $area)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("tourBuilder.area")
                            TextField("What would you like to do? (optional)", text: $activities, axis: .vertical)
                                .lineLimit(2...4).textFieldStyle(.roundedBorder)
                                .accessibilityIdentifier("tourBuilder.activities")
                            if transportModes.contains("walking") && transportModes.contains("driving") {
                                Text("Drive to your chosen area, then explore on foot. Travel time is included.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else if transportModes.contains("walking") && !transportModes.isDisjoint(with: ["transit", "rideshare"]) {
                                Text("Travel to your chosen area, then explore on foot. Travel time is included.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text("Leave blank to let Pip choose. The tour starts in your chosen area. Travel there is not included.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        // Everything past this point is optional, so the first screen asks only
                        // the two questions every traveler needs to answer.
                        DisclosureGroup("Make it more personal", isExpanded: $personal) {
                            VStack(alignment: .leading, spacing: 22) {
                                section("What are you in the mood for?") {
                                    LazyVGrid(columns: columns, spacing: 8) {
                                        ForEach(moodOptions, id: \.0) { id, title in
                                            chip(title, selected: moods.contains(id)) {
                                                if !moods.insert(id).inserted { moods.remove(id) }
                                            }
                                        }
                                    }
                                }
                                section("Who’s coming?") {
                                    choices([("solo", "Solo"), ("partner", "Partner"), ("friends", "Friends"), ("kids", "Kids"), ("family", "Family")], selection: $companions)
                                }
                                section("What’s your energy level?") {
                                    choices([("easygoing", "Easygoing"), ("balanced", "Balanced"), ("active", "Active")], selection: $energy)
                                    Stepper(value: $walkingLimit, in: 100...20000, step: 100) {
                                        Text("Walking limit: \(Measurement(value: Double(walkingLimit), unit: UnitLength.meters).formatted(.measurement(width: .abbreviated, usage: .road)))")
                                    }
                                }
                                section("Would you like food stops?") {
                                    choices([("none", "None"), ("snack", "Coffee or snack"), ("meal", "A meal"), ("surprise", "Surprise me")], selection: $food)
                                    if food != "none" {
                                        TextField("Cuisine (optional)", text: $cuisine).textFieldStyle(.roundedBorder)
                                        TextField("Dietary preferences (optional)", text: $dietary).textFieldStyle(.roundedBorder)
                                        if !dietary.isEmpty { Text("Menus and dietary suitability need to be confirmed with the venue.").font(.footnote).foregroundStyle(.secondary) }
                                    }
                                }
                                if area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                section("Where should we go?") {
                                    LazyVGrid(columns: columns, spacing: 8) {
                                        chip("Surprise me", selected: direction == "surprise") { direction = "surprise" }
                                        if reliableHeading != nil { chip("Current direction", selected: direction == "current") { direction = "current" } }
                                        chip("A destination", selected: direction == "destination") { direction = "destination" }
                                        ForEach([("north", "North"), ("south", "South"), ("east", "East"), ("west", "West")], id: \.0) { id, title in
                                            chip(title, selected: direction == id) { direction = id }
                                        }
                                    }
                                    if direction == "destination" { TextField("Destination or city", text: $destination).textFieldStyle(.roundedBorder) }
                                }
                                }
                                Toggle("Return to where I started", isOn: $roundTrip)
                            }.padding(.top, 12)
                        }
                        if !locationReady {
                            Text(LocalizedStringKey(locationAuthorization == .denied
                                ? "Location access is off. Allow While Using the App in Settings."
                                : locationAuthorization == .restricted
                                ? "Location access is restricted on this iPhone."
                                : "Waiting for a recent location. Check location access and try again."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        if movingDriver {
                            Text("Driving? Talk to Pip to plan your tour, or set it up before departure.").font(.subheadline)
                            Button("Talk to Pip") { guide.planTourByVoice(mode: mode, location: currentLocation, transportModes: transportModes.sorted()); dismiss() }.buttonStyle(.borderedProminent)
                        } else {
                            Button(action: create) {
                                HStack { if guide.planningTour { ProgressView() }; Text("Create My Tour") }.frame(maxWidth: .infinity, minHeight: 52)
                            }
                            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                            .disabled(transportModes.isEmpty || !locationReady || guide.planningTour || (area.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && direction == "destination" && destination.trimmingCharacters(in: .whitespaces).isEmpty))
                            .accessibilityIdentifier("tourBuilder.create")
                        }
                    }
                }.padding(20)
            }
            .disabled(guide.planningTour)
            .overlay {
                if guide.planningTour {
                    TourPlanningProgressView { guide.cancelTourPlanning() }
                }
            }
            .navigationTitle("Create My Tour").navigationBarTitleDisplayMode(.inline)
            .alert("Could not create tour", isPresented: Binding(
                get: { failureMessage != nil }, set: { if !$0 { failureMessage = nil } }
            )) {
                Button("OK", role: .cancel) { failureMessage = nil }
            } message: {
                if let failureMessage { Text(LocalizedStringKey(failureMessage)) }
            }
            .onChange(of: guide.planningTour) { wasPlanning, isPlanning in
                if wasPlanning, !isPlanning, guide.suggestedTour == nil, let message = guide.tourNotice {
                    failureMessage = message
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if preview {
                        Button("Adjust Tour", action: adjustTour)
                            .disabled(guide.downloadingTour)
                            .accessibilityIdentifier("tourBuilder.adjust")
                    }
                }
            }
            .onAppear {
                startLocationUpdates()
                transportModes = [guide.tourMode == .walking ? "walking" : "driving"]
                preview = !editActiveTour && guide.suggestedTour != nil
                if reliableHeading != nil { direction = "current" }
                if let active = guide.route, active.mode == guide.tourMode, !active.name.isEmpty {
                    direction = "destination"; destination = active.name
                }
                let draft = editActiveTour ? guide.activeTour?.plan.request : guide.tourDraft ?? guide.suggestedTour?.request
                if let draft {
                    area = draft.area ?? ""; activities = draft.activities ?? ""
                    minutes = draft.duration_minutes; transportModes = Set(draft.transport_modes ?? (draft.mode == "mixed" ? ["walking", "driving"] : [draft.mode])); moods = Set(draft.moods)
                    companions = draft.companions ?? ""; energy = draft.energy; food = draft.food
                    direction = draft.direction; destination = draft.destination ?? ""; roundTrip = draft.round_trip
                    walkingLimit = draft.walking_limit_meters; cuisine = draft.cuisine ?? ""; dietary = draft.dietary ?? ""
                    customTime = ![30, 60, 120, 240, 480].contains(minutes)
                }
                let words = Set((guide.tourDraft == nil ? profileInterests : "").lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
                for (word, mood) in [("art", "arts"), ("history", "arts"), ("food", "food"), ("shopping", "shopping"), ("nature", "scenic"), ("photography", "scenic")] where words.contains(word) { moods.insert(mood) }
            }
            .onDisappear { stopLocationUpdates() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { startLocationUpdates() }
                else { stopLocationUpdates() }
            }
            .task {
                while !Task.isCancelled {
                    locationClock = Date()
                    do { try await Task.sleep(for: .seconds(5)) }
                    catch { return }
                }
            }
            .onChange(of: moods) { _, value in if value.contains("food"), food == "none" { food = "surprise" } }
            .onChange(of: energy) { _, value in
                if value == "easygoing" { walkingLimit = min(walkingLimit, 1500) }
            }
            .onChange(of: guide.suggestedTour?.id) { _, id in
                if id != nil { preview = true }
                if let plan = guide.suggestedTour, tourName.isEmpty { tourName = plan.displayName }
            }
        }
    }

    private var moodOptions: [(String, String)] {
        [("relaxing", "Relaxing"), ("scenic", "Scenic"), ("food", "Food"), ("adventure", "Adventure"),
         ("arts", "Arts and culture"), ("romantic", "Romantic"), ("shopping", "Shopping"), ("family", "Family fun")]
    }
    private func durationTitle(_ minutes: Int) -> String {
        switch minutes {
        case 30: String(localized: "30 minutes", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
        case 60: String(localized: "1 hour", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
        case 120: String(localized: "2 hours", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
        case 240: String(localized: "Half day", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
        default: String(localized: "Full day", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
        }
    }
    private func startLocationUpdates() {
        locationClock = Date()
        guard locationFeed == nil else { return }
        let feed = LiveGuideLocationFeed()
        locationFeed = feed
        locationAuthorization = feed.authorization
        feed.onAuthorization = { locationAuthorization = $0 }
        feed.onLocation = { fix in
            guard (0...100).contains(fix.horizontalAccuracy),
                  abs(fix.timestamp.timeIntervalSinceNow) < 120,
                  CLLocationCoordinate2DIsValid(fix.coordinate),
                  liveLocation == nil || fix.timestamp >= liveLocation!.timestamp else { return }
            liveLocation = fix
            locationClock = Date()
        }
        feed.start()
    }

    private func stopLocationUpdates() {
        locationFeed?.stop()
        locationFeed = nil
    }

    private func adjustTour() {
        guide.cancelTourPlanning()
        guide.tourNotice = nil
        preview = false
    }

    private func create() {
        locationClock = Date()
        guard !transportModes.isEmpty, let location = currentLocation, locationReady else { return }
        let selectedArea = area.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedActivities = activities.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedDirection = selectedArea.isEmpty ? direction : "surprise"
        let request = GuideTourRequest(origin: .init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                                                     horizontal_accuracy_meters: location.horizontalAccuracy,
                                                     captured_at: ISO8601DateFormatter().string(from: location.timestamp)),
                                       mode: mode, duration_minutes: minutes, direction: selectedDirection,
                                       destination: selectedDirection == "destination" ? destination : nil,
                                       heading: reliableHeading, round_trip: roundTrip,
                                       language: AppLanguage.selected(UserDefaults.standard.string(forKey: "pip.language") ?? "en").rawValue,
                                       area: selectedArea.isEmpty ? nil : selectedArea,
                                       activities: selectedActivities.isEmpty ? nil : selectedActivities,
                                       moods: moods.sorted(), companions: companions.isEmpty ? nil : companions, energy: energy, food: food,
                                       cuisine: cuisine.isEmpty ? nil : cuisine, dietary: dietary.isEmpty ? nil : dietary,
                                       walking_limit_meters: walkingLimit, transport_modes: transportModes.sorted())
        guide.createTour(request)
    }
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) { Text(LocalizedStringKey(title)).font(.headline); content() }
    }
    private func choices(_ values: [(String, String)], selection: Binding<String>) -> some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(values, id: \.0) { id, title in chip(title, selected: selection.wrappedValue == id) { selection.wrappedValue = id } }
        }
    }
    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                Text(LocalizedStringKey(title)).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8).padding(.vertical, 4)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : .clear, lineWidth: 2))
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private func tourPreview(_ plan: GuideTourPlan) -> some View {
        AppleTourPreview(plan: plan)
        Text("About \(Int(ceil(Double(plan.estimated_seconds) / 60))) minutes in total").font(.title2.bold())
        if plan.round_trip { Label("Return to where I started", systemImage: "arrow.uturn.backward").font(.subheadline) }
        if plan.mode == "mixed", let walk = plan.walking_seconds, let drive = plan.driving_seconds {
            Text("Walking: \(Int(ceil(Double(walk) / 60))) min · Driving: \(Int(ceil(Double(drive) / 60))) min").font(.subheadline)
        }
        if let title = transportOptions.first(where: { $0.0 == plan.mode })?.1 {
            Text(LocalizedStringKey(title)).font(.subheadline)
        }
        if plan.mode == "rideshare" {
            Text("Includes a pickup time allowance. Availability and fares are not confirmed.").font(.footnote).foregroundStyle(.secondary)
        }
        if let parking = plan.parking_seconds, parking > 0 {
            Text("Includes time for parking. Parking availability is not confirmed.").font(.footnote).foregroundStyle(.secondary)
        }
        ForEach(Array(plan.stops.enumerated()), id: \.element.place.id) { index, stop in
            HStack(alignment: .top, spacing: 12) {
                Text((index + 1).formatted()).font(.headline).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: stop.place.name).font(.headline)
                    if let photo = stop.photo, let url = PipPhotoLink.validURL(photo.url) {
                        PipPhotoView(photo: PipPhotoLink(url: url, caption: stop.place.name))
                        ForEach(Array(photo.authors.enumerated()), id: \.offset) { _, author in
                            if let name = author.displayName { Text(verbatim: name).font(.caption2).foregroundStyle(.secondary) }
                        }
                    }
                    Text(LocalizedStringKey(stop.reason == "transport_change" ? "Park here, then walk" : stop.reason == "arrival_transfer" ? "Arrive here, then walk" : stop.visit_kind == "pass_by" ? "Hear the story while passing" : stop.place.categories.contains("food") ? "Food stop" : "Time to explore")).font(.subheadline).foregroundStyle(.secondary)
                    if stop.reason == "interest_match" { Text("Matches your interests").font(.caption).foregroundStyle(.secondary) }
                    if let walk = plan.walking_segments?.first(where: { $0.anchor_id == stop.place.id }) {
                        ForEach(Array(walk.visits.enumerated()), id: \.element.id) { offset, place in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: "\(offset + 1). \(place.name)").font(.subheadline.weight(.semibold))
                                if let summary = place.google_summary { Text(verbatim: summary).font(.subheadline) }
                                if let address = place.google_address { Text(verbatim: address).font(.caption).foregroundStyle(.secondary) }
                                if let raw = place.google_maps_uri, let url = URL(string: raw), url.scheme == "https" {
                                    Link("Google Maps", destination: url).font(.caption).frame(minHeight: 44)
                                }
                            }
                        }
                        Text("Places and ratings from Google Maps.").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }.padding(.vertical, 5)
        }
        if plan.food_status == "not_included" { Text("No food stop fits this tour. Adjust the time or preferences to try again.").font(.footnote) }
        if plan.food_status == "unverified_dietary" { Text("Menus and dietary suitability need to be confirmed with the venue.").font(.footnote) }
        Text("Estimates may change. Confirm opening hours and access before visiting.").font(.footnote).foregroundStyle(.secondary)
        Button("Start Tour") { var named = plan; named.name = tourName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : tourName; guide.beginTour(named); if guide.enabled { dismiss() } }
            .frame(maxWidth: .infinity, minHeight: 52).buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            .accessibilityIdentifier("tourBuilder.start")
        TextField("Tour name", text: $tourName)
            .textFieldStyle(.roundedBorder).frame(minHeight: 44)
            .accessibilityIdentifier("tourBuilder.name")
        HStack {
            Button { guide.downloadTour(plan, name: tourName) } label: {
                if guide.downloadingTour { ProgressView(value: guide.downloadProgress).frame(width: 70) } else { Text("Download Offline") }
            }.disabled(guide.downloadingTour).frame(minHeight: 44)
            .accessibilityIdentifier("tourBuilder.download")
        }
        if let message = guide.tourNotice {
            if message == "Ready Offline. Pip’s stories and OpenAI voice are downloaded." {
                Label("Tour downloaded", systemImage: "checkmark.circle.fill")
                    .accessibilityIdentifier("tourBuilder.downloadComplete")
                if guide.downloadedTours.first?.offline_package?.omitted_waypoints?.isEmpty == false {
                    Text("Some stops are unavailable offline. Review the saved stops before starting.")
                        .font(.footnote).accessibilityIdentifier("tour.omittedStops")
                }
            } else {
                Text(LocalizedStringKey(message)).font(.subheadline)
                    .accessibilityIdentifier("tourBuilder.notice")
            }
        }
        if guide.downloadingTour {
            Text(Int64(guide.downloadBytes), format: .byteCount(style: .file)).font(.caption)
        }
        Text("Downloads include available sourced stories and voice.").font(.footnote).foregroundStyle(.secondary)
        Text("Places and routes from Google Maps.").font(.caption2).foregroundStyle(.secondary)
        if !guide.downloadingTour {
            Button("Plan Another Tour") { tourName = ""; guide.planAnotherTour() }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("tourBuilder.planAnother")
        }
    }
}


/// Equal-size icon-over-label tour button, so a row of them reads as one group.
struct TourControlButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage).font(.title3)
                Text(title).font(.footnote.weight(.semibold)).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered).buttonBorderShape(.roundedRectangle(radius: 14))
    }
}

/// Repeat, Pause/Resume and Skip in the familiar media-player order.
struct OfflineTourPlaybackControls: View {
    let guide: LiveGuideStore
    var body: some View {
        HStack(spacing: 8) {
            TourControlButton(title: "Repeat", systemImage: "backward.end.fill") { guide.repeatOffline() }
            TourControlButton(title: LocalizedStringKey(guide.offlinePaused ? "Resume" : "Pause"),
                              systemImage: guide.offlinePaused ? "play.fill" : "pause.fill") {
                guide.offlinePaused ? guide.resumeOffline() : guide.pauseOffline()
            }
            TourControlButton(title: "Skip", systemImage: "forward.end.fill") { guide.skipAnnouncement() }
        }
    }
}

/// Prepared offline answers for the current stop.
struct OfflineTourQuestions: View {
    @Bindable var guide: LiveGuideStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(guide.offlineAnswers) { answer in
                Button { guide.playOfflineStory(answer.id) } label: { Text(verbatim: answer.question ?? answer.title) }.frame(minHeight: 44)
            }
            HStack {
                TextField("Your question", text: $guide.offlineQuestion).textFieldStyle(.roundedBorder)
                    .onSubmit { guide.askOfflineQuestion() }
                Button("Ask") { guide.askOfflineQuestion() }.frame(minWidth: 44, minHeight: 44)
            }
            Text("Offline answers are prepared in advance. Current hours and conditions need internet.").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct OfflineTourControls: View {
    @Bindable var guide: LiveGuideStore
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OfflineTourPlaybackControls(guide: guide)
            if guide.activeTour?.plan.offline_package?.version != 3 {
                DisclosureGroup("Ask about this stop") { OfflineTourQuestions(guide: guide) }
            }
            if guide.networkAvailable {
                Button("Talk to Pip online", systemImage: "waveform") { guide.toggleConversation() }.frame(minHeight: 44)
            }
        }
    }
}

/// Every tour saved on this iPhone, newest first. One plain list: open a tour to play it,
/// rename it or delete it; swipe to delete here too, the familiar iOS way.
struct MyToursView: View {
    @Bindable var guide: LiveGuideStore
    var onStart: () -> Void = {}
    var createTour: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var deletingTourID: String?
    @State private var confirmDelete = false
    var body: some View {
        NavigationStack {
            Group {
                if guide.downloadedTours.isEmpty && !guide.downloadingTour {
                    ContentUnavailableView("No saved tours yet", systemImage: "list.bullet",
                                           description: Text("Download a tour to play it here later, even offline."))
                } else {
                    List {
                        if guide.downloadingTour {
                            TourDownloadProgressRow(guide: guide)
                        }
                        ForEach(guide.downloadedTours, id: \.id) { plan in
                            HStack(spacing: 12) {
                                // Play starts straight away; the row opens details.
                                if guide.activeTour?.plan.id != plan.id {
                                    let resume = guide.hasSavedProgress(plan)
                                    Button { guide.startSavedTour(plan, resume: resume); onStart() } label: {
                                        Image(systemName: "play.fill").font(.title3)
                                            .frame(width: 48, height: 48)
                                            .background(Color.accentColor, in: Circle())
                                            .foregroundStyle(.white)
                                    }
                                    .buttonStyle(.borderless)
                                    .accessibilityLabel(Text(resume ? "Resume Tour" : "Start Tour"))
                                    .accessibilityIdentifier("myTours.play.\(plan.id)")
                                } else {
                                    Image(systemName: "waveform").font(.title3).foregroundStyle(Color.accentColor)
                                        .symbolEffect(.variableColor.iterative)
                                        .frame(width: 48, height: 48)
                                        .accessibilityHidden(true)
                                }
                                NavigationLink { DownloadedTourView(guide: guide, tourID: plan.id, onStart: onStart) } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: plan.displayName).font(.headline)
                                        Text("\(plan.stops.count) stops · \(plan.duration_minutes) min")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                            .swipeActions(allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deletingTourID = plan.id
                                    confirmDelete = true
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Tours")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Delete this tour?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) {
                    if let deletingTourID { guide.deleteTour(deletingTourID) }
                    deletingTourID = nil
                }
                Button("Cancel", role: .cancel) { deletingTourID = nil }
            } message: {
                Text("This removes the downloaded tour from this iPhone. It cannot be undone.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { createTour() } label: { Label("New Tour", systemImage: "plus") }
                        .disabled(!guide.networkAvailable)
                        .accessibilityIdentifier("myTours.createTour")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !guide.networkAvailable {
                    Text("You’re offline. Connect to the internet to plan a new tour.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .padding()
                }
            }
        }
    }
}

struct TourDownloadProgressRow: View {
    let guide: LiveGuideStore
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Downloading tour…").font(.headline)
            ProgressView(value: guide.downloadProgress)
            Text(guide.downloadProgress, format: .percent.precision(.fractionLength(0)))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("tour.downloadProgress")
    }
}

/// Local assets remain available when token refresh or the account API cannot be reached.
/// This screen exposes only the downloaded package, never organizer/account data.
struct DownloadedTourView: View {
    @Bindable var guide: LiveGuideStore
    let tourID: String
    var onStart: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmDelete = false
    @State private var roadMap: GuideRoadMapData?
    @State private var showSources = false
    private var plan: GuideTourPlan? { guide.downloadedTours.first { $0.id == tourID } }
    /// Pushed from My Tours, so this relies on that screen's own navigation bar and back button.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let plan {
                    Text("Pip’s voice is AI-generated.").font(.footnote).foregroundStyle(.secondary)
                    if plan.offline_package?.omitted_waypoints?.isEmpty == false {
                        Text("Some stops are unavailable offline. Review the saved stops before starting.")
                            .font(.footnote).accessibilityIdentifier("tour.omittedStops")
                    }
                    if let roads = roadMap {
                        OfflineRoadMapView(data: roads, stops: plan.stops,
                                           location: guide.activeTour?.plan.id == tourID ? guide.offlineLocation : nil,
                                           origin: .init(latitude: plan.origin.latitude, longitude: plan.origin.longitude))
                            .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text("Downloaded roads · No offline rerouting").font(.footnote)
                    }
                    if guide.activeTour?.plan.id != tourID {
                        if guide.hasSavedProgress(plan) {
                            Button("Resume Tour", systemImage: "play.fill") { guide.startSavedTour(plan, resume: true); onStart() }
                                .buttonStyle(.borderedProminent).frame(minHeight: 48).accessibilityIdentifier("myTours.resume")
                            Button("Start Again") { guide.startSavedTour(plan, resume: false); onStart() }
                                .frame(minHeight: 44).accessibilityIdentifier("myTours.restart")
                        } else {
                            Button("Start Tour", systemImage: "play.fill") { guide.startSavedTour(plan, resume: false); onStart() }
                                .buttonStyle(.borderedProminent).frame(minHeight: 48).accessibilityIdentifier("myTours.start")
                        }
                    } else {
                        TourNavigationControls(guide: guide)
                        OfflineTourControls(guide: guide)
                    }
                    if plan.offline_package?.version == 3 {
                        Label("Tour downloaded", systemImage: "checkmark.circle.fill").accessibilityIdentifier("tour.downloadComplete")
                        Button("Sources and licenses") { showSources = true }.frame(minHeight: 44).accessibilityIdentifier("tour.sources")
                    }
                    if let mention = guide.lastMention { Text(verbatim: mention.placeName).font(.headline); Text(verbatim: mention.text) }
                    if let notice = guide.tourNotice { Text(LocalizedStringKey(notice)).foregroundStyle(.secondary) }
                    ForEach(Array(plan.stops.enumerated()), id: \.offset) { index, stop in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index + 1). \(stop.place.name)").font(.headline)
                            if let image = plan.offline_package?.images?.first(where: { $0.stop_index == index }) { OfflineTourImageView(image: image) }
                            if let story = plan.offline_package?.clips.first(where: { $0.id == "stop_\(index)" }) {
                                Text(verbatim: story.text).font(.body)
                            } else { Text("No sourced story is available for this stop.").font(.footnote).foregroundStyle(.secondary) }
                            if let raw = stop.place.wikipedia_url, let url = URL(string: raw) {
                                Link("Story source", destination: url)
                                Link("CC BY-SA 4.0", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                            }
                            if let raw = stop.place.coordinate_source, let url = URL(string: raw), url.host == "www.openstreetmap.org" {
                                Link("OpenStreetMap", destination: url).font(.caption).frame(minHeight: 44)
                                Link("ODbL", destination: URL(string: "https://www.openstreetmap.org/copyright")!).font(.caption).frame(minHeight: 44)
                            }
                        }
                    }
                    Text(plan.attribution ?? "").font(.caption2).foregroundStyle(.secondary)
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("myTours.delete")
                }
            }.padding()
        }
        .navigationTitle(plan?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") { newName = plan?.displayName ?? ""; renaming = true }
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel(Text("Tour options"))
                .accessibilityIdentifier("myTours.options")
            }
        }
        .alert("Rename tour", isPresented: $renaming) {
            TextField("Tour name", text: $newName)
            Button("Save") { guide.renameTour(tourID, to: newName) }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Delete this tour?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { guide.deleteTour(tourID); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the downloaded tour from this iPhone. It cannot be undone.")
        }
        .sheet(isPresented: $showSources) {
            if let package = plan?.offline_package { OfflineTourSourcesView(package: package) }
        }
        .onAppear { roadMap = plan?.offline_package?.road_map?.decoded(); guide.setForeground(true) }
        .onChange(of: scenePhase) { _, phase in guide.setForeground(phase == .active) }
        .onChange(of: plan == nil) { _, missing in if missing { dismiss() } }
    }
}


struct OfflineTourImageView: View {
    let image: GuideOfflinePackage.OfflineImage
    var body: some View {
        if let data = Data(base64Encoded: image.data), let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage).resizable().scaledToFit().frame(maxHeight: 220).accessibilityHidden(true)
            Text(verbatim: image.credit + " · " + image.license + " · " + image.modified).font(.caption2).foregroundStyle(.secondary)
            if let license = URL(string: image.license_url) { Link(image.license, destination: license).font(.caption).frame(minHeight: 44) }
            if let url = URL(string: image.source) { Link("Photo source", destination: url).font(.caption).frame(minHeight: 44) }
        }
    }
}

/// A local vector renderer. No MapKit tiles, network calls or computed directions.
struct OfflineRoadMapView: View {
    let data: GuideRoadMapData
    let stops: [GuideTourPlan.Stop]
    let location: GuideRoute.Point?
    var origin: GuideRoute.Point? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var following = false
    @GestureState private var drag: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let targets = stops.map { GuideRoute.Point(latitude: $0.place.latitude, longitude: $0.place.longitude) } + (origin.map { [$0] } ?? [])
            let south = (targets.map(\.latitude).min() ?? data.bounds.south) - 0.002
            let north = (targets.map(\.latitude).max() ?? data.bounds.north) + 0.002
            let west = (targets.map(\.longitude).min() ?? data.bounds.west) - 0.002
            let east = (targets.map(\.longitude).max() ?? data.bounds.east) + 0.002
            let width = max(0.00001, (east - west) * cos((south + north) / 2 * .pi / 180))
            let height = max(0.00001, north - south)
            let unit = min(max(1, size.width - 40) / width, max(1, size.height - 40) / height) * zoom
            let center = following ? location : nil
            let latitude = center?.latitude ?? (south + north) / 2
            let longitude = center?.longitude ?? (west + east) / 2
            let cosine = cos((south + north) / 2 * .pi / 180)
            let shift = CGSize(width: offset.width + drag.width, height: offset.height + drag.height)
            let point: (GuideRoute.Point) -> CGPoint = { coordinate in
                CGPoint(x: size.width / 2 + (coordinate.longitude - longitude) * cosine * unit + shift.width,
                        y: size.height / 2 - (coordinate.latitude - latitude) * unit + shift.height)
            }
            Canvas { context, _ in
                for road in data.roads {
                    let minor = ["service", "footway", "path", "steps", "cycleway", "track"].contains(road.kind)
                    if minor && zoom < 4 { continue }
                    var path = Path()
                    for (index, coordinate) in road.points.enumerated() {
                        let position = point(coordinate)
                        if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                    }
                    let major = ["motorway", "trunk", "primary", "secondary"].contains(road.kind.replacingOccurrences(of: "_link", with: ""))
                    let walking = ["footway", "path", "steps", "cycleway"].contains(road.kind)
                    let roadColor: Color = colorScheme == .dark ? (major ? .white : .gray) : Color(white: major ? 0.32 : 0.5)
                    context.stroke(path, with: .color(roadColor), style: StrokeStyle(lineWidth: major ? 2.4 : 0.8,
                                    lineCap: .round, lineJoin: .round, dash: walking ? [3, 3] : []))
                }
                // Measure labels so long names cannot overlap their neighbours.
                var names = Set<String>()
                var occupied: [CGRect] = []
                if zoom >= 2 {
                    let priority = ["motorway", "trunk", "primary", "secondary", "tertiary", "residential"]
                    let roads = data.roads.sorted {
                        (priority.firstIndex(of: $0.kind) ?? 99) < (priority.firstIndex(of: $1.kind) ?? 99)
                    }
                    for road in roads where !road.name.isEmpty && !road.points.isEmpty {
                        guard names.count < (zoom >= 8 ? 24 : 12), !names.contains(road.name) else { continue }
                        let position = point(road.points[road.points.count / 2])
                        let text = context.resolve(Text(verbatim: road.name).font(.caption).foregroundColor(.primary))
                        let measured = text.measure(in: CGSize(width: 1000, height: 40))
                        let rect = CGRect(x: position.x - measured.width / 2 - 5, y: position.y - measured.height / 2 - 5,
                                          width: measured.width + 10, height: measured.height + 10)
                        guard measured.width < size.width * 0.6, CGRect(origin: .zero, size: size).contains(rect),
                              !occupied.contains(where: { $0.intersects(rect) }) else { continue }
                        occupied.append(rect); names.insert(road.name)
                        context.draw(text, at: position)
                    }
                }
                var pins: [(CGPoint, [Int])] = []
                for (index, stop) in stops.enumerated() {
                    let position = point(.init(latitude: stop.place.latitude, longitude: stop.place.longitude))
                    if let nearby = pins.firstIndex(where: { hypot($0.0.x - position.x, $0.0.y - position.y) < 32 }) {
                        pins[nearby].1.append(index + 1)
                    } else { pins.append((position, [index + 1])) }
                }
                for (position, numbers) in pins {
                    let title = numbers.map { $0.formatted() }.joined(separator: ", ")
                    let width = max(26, CGFloat(title.count * 7 + 12))
                    let badge = CGRect(x: position.x - width / 2, y: position.y - 13, width: width, height: 26)
                    context.fill(Path(roundedRect: badge, cornerRadius: 13), with: .color(.red))
                    context.draw(Text(title).font(.caption.bold()).foregroundColor(.white), at: position)
                }
                if let location {
                    let position = point(location)
                    context.fill(Path(ellipseIn: CGRect(x: position.x - 11, y: position.y - 11, width: 22, height: 22)), with: .color(.white))
                    context.fill(Path(ellipseIn: CGRect(x: position.x - 7, y: position.y - 7, width: 14, height: 14)), with: .color(.blue))
                    context.stroke(Path(ellipseIn: CGRect(x: position.x - 11, y: position.y - 11, width: 22, height: 22)), with: .color(.black), lineWidth: 1)
                }
            }
            .background(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.95))
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture().updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset.width += value.translation.width
                    offset.height += value.translation.height
                })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Offline road map"))
            .accessibilityValue(stops.enumerated().map { "\($0.offset + 1). \($0.element.place.name)" }.joined(separator: ", "))
            .accessibilityIdentifier("tour.offlineRoadMap")
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 4) {
                    Button { zoom = min(64, zoom * 2) } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text("Zoom in"))
                    Button { zoom = max(1, zoom / 2); offset = .zero } label: { Image(systemName: "minus").frame(width: 44, height: 44) }
                        .accessibilityLabel(Text("Zoom out"))
                    Button { following = location != nil; offset = .zero; zoom = following ? max(zoom, 4) : 1 } label: {
                        Image(systemName: "location.fill").frame(width: 44, height: 44)
                    }.accessibilityLabel(Text("Recenter"))
                }
                .buttonStyle(.plain).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(12)
            }
            .overlay(alignment: .bottomLeading) {
                Link("© OpenStreetMap contributors", destination: URL(string: data.license_url)!)
                    .font(.caption).padding(8).frame(minHeight: 44)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)).padding(8)
            }
        }
    }
}


/// Directions for the next stop. With `endTour`, the action sits beside an End Tour button.
struct TourNavigationControls: View {
    @Bindable var guide: LiveGuideStore
    var endTour: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        if let progress = guide.activeTour {
            if progress.navigationMode == "rideshare", !progress.needsWalkingConfirmation {
                Text("Confirm pickup, price and booking in the ride app. Internet is required.").font(.footnote).foregroundStyle(.secondary)
            } else if !progress.needsWalkingConfirmation, guide.networkAvailable, ["walking", "driving"].contains(progress.navigationMode) {
                if guide.navigator.loading { ProgressView("Finding directions…") }
                if !guide.navigator.instruction.isEmpty {
                    Text(verbatim: guide.navigator.instruction).font(.headline).accessibilityIdentifier("tour.nextTurn")
                }
                if guide.navigator.unavailable { Text("Navigation is unavailable. Try again online.").font(.footnote) }
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                primaryAction(progress)
                if let endTour {
                    Button(role: .destructive, action: endTour) {
                        Label("End Tour", systemImage: "stop.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .accessibilityIdentifier("liveGuide.enabled")
                }
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    @ViewBuilder private func primaryAction(_ progress: GuideTourProgress) -> some View {
        if progress.needsWalkingConfirmation {
            Button { guide.confirmWalking() } label: {
                Label("Start walking", systemImage: "figure.walk").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).accessibilityIdentifier("tour.confirmWalking")
        } else if progress.navigationMode == "rideshare" {
            Menu {
                Button("Uber") { guide.openNavigation(provider: "uber") }
                Button("Lyft") { guide.openNavigation(provider: "lyft") }
            } label: {
                Label("Book a ride", systemImage: "car.fill").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).accessibilityIdentifier("tour.bookRide")
        } else {
            Button { guide.openNavigation() } label: {
                Label(LocalizedStringKey(progress.navigationMode == "transit" ? "Transit directions" : "Open Maps"), systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent).buttonBorderShape(.capsule).accessibilityIdentifier("tour.openAppleMaps")
        }
    }
}

struct OfflineTourSourcesView: View {
    let package: GuideOfflinePackage
    @Environment(\.dismiss) private var dismiss
    @State private var exportURL: URL?
    var body: some View {
        NavigationStack {
            List {
                if let modifications = package.modifications { Text(verbatim: modifications).font(.footnote) }
                ForEach(package.sources ?? [], id: \.stop_index) { source in
                    Section {
                        Text(verbatim: source.attribution)
                        Text(verbatim: source.revision_date).font(.caption)
                        if let url = URL(string: source.revision_url) { Link("Story source", destination: url) }
                        Text(verbatim: source.source_modifications).font(.caption)
                        DisclosureGroup { Text(verbatim: source.excerpt).font(.body) } label: { Text(verbatim: source.title) }
                    } header: { Text(verbatim: source.title) }
                }
                ForEach((package.licenses ?? [:]).keys.sorted(), id: \.self) { key in
                    if let license = package.licenses?[key] {
                        DisclosureGroup(license.name) { Text(verbatim: license.text).font(.caption).textSelection(.enabled) }
                            .accessibilityIdentifier("tour.sourceLicense.\(key)")
                    }
                }
                if let exportURL { ShareLink(item: exportURL) { Label("Share stories and sources", systemImage: "square.and.arrow.up") } }
            }
            .navigationTitle("Sources and licenses").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("tour.sourcesDone") } }
            .task {
                // Only licensed content is exported, without the traveler's start location or progress.
                let url = FileManager.default.temporaryDirectory.appending(path: "pippipgo-stories-\(UUID().uuidString).json")
                if let data = try? JSONEncoder().encode(package) {
                    do { try data.write(to: url, options: .atomic); exportURL = url } catch { exportURL = nil }
                }
            }
            .onDisappear { if let exportURL { try? FileManager.default.removeItem(at: exportURL) } }
        }
    }
}
