import Foundation
import CryptoKit

// Live local guide. Pure decision logic with no Core Location, networking or UI, so every
// timing rule is unit-testable. The phone decides when Pip speaks; the backend only supplies
// tiered candidates and writes the words. Walking looks around the traveller; driving looks
// ahead of the car and introduces worthwhile places a few minutes before reaching them.

enum GuideTier: String, Codable, Sendable, Equatable {
    case mustSee = "must_see", notable, minor
    var rank: Int { switch self { case .mustSee: 0; case .notable: 1; case .minor: 2 } }
}

/// The one setting the traveler controls: how talkative Pip is.
enum GuideChattiness: String, CaseIterable, Codable, Sendable, Identifiable {
    case quiet, normal, tourGuide = "tour_guide"
    var id: String { rawValue }
    var title: String { switch self { case .quiet: "Only major highlights"; case .normal: "Occasionally"; case .tourGuide: "Often" } }
    var detail: String {
        switch self {
        case .quiet: "Only the most important sights."
        case .normal: "A few interesting stories along the way."
        case .tourGuide: "More stories and details as you explore."
        }
    }
}

/// The traveller's explicit choice stays stable when a car stops at a light.
enum GuideTourMode: String, CaseIterable, Identifiable, Hashable {
    case walking, driving
    var id: String { rawValue }
    var title: String { self == .walking ? "Walking tour" : "Driving tour" }
    var symbol: String { self == .walking ? "figure.walk" : "car.fill" }
}

enum GuideMotion: String, Sendable, Equatable {
    case unknown, walking, cityDriving = "city_driving", highway
    var isDriving: Bool { self == .cityDriving || self == .highway }
}

struct GuideCandidate: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var latitude: Double
    var longitude: Double
    var radius_meters: Double = 0
    var categories: [String] = []
    var prominence: Double = 0
    var tier: GuideTier = .minor
    var summary: String?
    var wikipedia_url: String?
    var google_maps_uri: String?
    var rating: Double?
    var user_rating_count: Int?
    var profile_match: Double = 0.5
    /// Prominence weighted by how much visitors get from this kind of place (backend).
    var appeal: Double?
    /// Google's kind of place, e.g. "shopping_mall"; its open state; the town it is in.
    var primary_type: String?
    var open_now: Bool?
    var locality: String?
    var isArea: Bool { radius_meters > 0 }
    /// Older backends and Apple's fallback places have no appeal; prominence stands in.
    var visitorAppeal: Double { appeal ?? prominence * 0.8 }
    var isScenic: Bool { categories.contains("scenic") }
}

struct GuideNearbyRequest: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontal_accuracy_meters: Double?
    var radius_meters: Int
    var language: String
    /// "ahead" while driving: a wider circle centred in front of the car.
    var scope: String? = nil
}

struct GuideNearbyResponse: Codable, Sendable {
    var status: String
    var retrieved_at: String?
    var radius_meters: Int?
    var interests: [String] = []
    var sources: [String] = []
    var candidates: [GuideCandidate] = []
    var sun: GuideSun?
    var diagnostics: GuideNearbyDiagnostics?
}

/// Today's sunrise and sunset at the searched point (ISO 8601 UTC).
struct GuideSun: Codable, Sendable, Equatable {
    var sunrise: String?
    var sunset: String?
    var sunsetDate: Date? { sunset.flatMap { ISO8601DateFormatter.guide.date(from: $0) } }
}

extension ISO8601DateFormatter {
    /// Accepts the backend's "2026-10-16T01:17:00+00:00", with or without fractional seconds.
    nonisolated(unsafe) static let guide: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// What the backend searched and why places were left out; only written to the debug log.
struct GuideNearbyDiagnostics: Codable, Sendable {
    struct Group: Codable, Sendable {
        var types: Int?
        var returned: Int?
        var error: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            types = try? c.decodeIfPresent(Int.self, forKey: .types)
            returned = try? c.decodeIfPresent(Int.self, forKey: .returned)
            error = (try? c.decodeIfPresent(String.self, forKey: .error))
                ?? (try? c.decodeIfPresent(Int.self, forKey: .error)).flatMap { $0.map(String.init) }
        }
    }
    struct Dropped: Codable, Sendable { var name: String; var reason: String }
    var scope: String?
    var latency_ms: Int?
    var google_search_groups: Int?
    var radius_meters: Int?
    var groups: [String: Group]?
    var candidates: Int?
    var dropped: [Dropped]?
}

/// The candidate shape the backend accepts back (no ratings or Google review content).
struct GuideMentionPlace: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var tier: GuideTier
    var categories: [String]
    var summary: String?
    var distance_meters: Double?
    var side: String?
    /// Lets the model tell apart places that share a name.
    var latitude: Double?
    var longitude: Double?
    var primary_type: String?
    var open_now: Bool?
    var locality: String?
}

struct GuideMentionRequest: Codable, Sendable, Equatable {
    var place: GuideMentionPlace
    var highlights: [GuideMentionPlace] = []
    var situation: String
    var mode: String
    var language: String
    /// The zoo, park or campus the place is inside, e.g. "San Diego Zoo".
    var within: String?
    /// Ask the backend for Pip's voice as MP3 (text-to-speech), so no live session is needed.
    var audio: Bool = false
    /// Wall-clock time with its offset ("2026-10-15T17:30:00-07:00") and the map's weather.
    var local_time: String?
    var weather: String?
    /// Driving: estimated from distance along the direction of travel and current speed.
    var minutes_ahead: Int?
    /// How far the place lies from the line the car is travelling along.
    var off_route_meters: Int?
    /// Only when geometry says it is close beside the traveller; Pip never claims sight otherwise.
    var in_view: Bool?
    var visit_kind: String? = nil
    var tour_remaining_minutes: Int? = nil
}

struct GuideMentionResponse: Codable, Sendable {
    var text: String
    var source: String?
    /// Base64 MP3 in Pip's selected voice, when requested and available.
    var audio: String?
    var audio_format: String?
}

struct GuideSpeechRequest: Codable, Sendable { var text: String; var language: String }

/// Where the traveler is when a conversation starts from the Live Guide (X-Pip-Guide header).
struct GuideStartContext: Codable, Sendable {
    var venue: String?
    var nearby: [GuideMentionPlace]
    var tour_mode: String? = nil
    var planning_tour = false
    var heading: Double? = nil
    var heading_captured_at: String? = nil
}

struct GuideFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Horizontal accuracy in meters (Core Location's estimate).
    var accuracy: Double
    /// Meters per second; negative when unknown.
    var speed: Double = -1
    /// Direction of travel in degrees; negative when unknown.
    var course: Double = -1
    var timestamp: Date

    /// Animate only confirmed, recent movement; unknown speed is not evidence of walking.
    func isMoving(at now: Date) -> Bool {
        let age = now.timeIntervalSince(timestamp)
        return age >= 0 && age < 15 && speed.isFinite && speed >= 0.5
    }
}

enum GuideSituation: String, Sendable {
    case stoppedNearby = "stopped_nearby", approaching, upcoming, enteredArea = "entered_area", asked
    case approachingCity = "approaching_city", enteringCity = "entering_city"
}

struct GuideDecision: Sendable, Equatable {
    var place: GuideCandidate
    var highlights: [GuideCandidate]
    var situation: GuideSituation
    var side: String?
    var distance: Double
    var motion: GuideMotion
    /// Must-see mentions may break the normal talk budget.
    var breaksBudget: Bool
    /// Name of the venue (zoo, park) the traveler and this place are inside.
    var within: String? = nil
    var minutesAhead: Int? = nil
    var offRoute: Double? = nil
    var inView: Bool? = nil

    func request(language: String) -> GuideMentionRequest {
        GuideMentionRequest(
            place: GuideMentionPlace(place, distance: distance, side: side),
            highlights: highlights.map { GuideMentionPlace($0, distance: nil, side: nil) },
            situation: situation.rawValue,
            mode: motion.isDriving ? "driving" : "walking",
            language: language,
            within: within.map { String($0.prefix(160)) },
            minutes_ahead: minutesAhead.map { min(90, max(0, $0)) },
            off_route_meters: offRoute.map { Int(min(20_000, max(0, $0.rounded()))) },
            in_view: inView)
    }
}

extension GuideMentionPlace {
    init(_ candidate: GuideCandidate, distance: Double?, side: String?) {
        self.init(id: String(candidate.id.prefix(300)), name: String(candidate.name.prefix(160)), tier: candidate.tier,
                  categories: Array(candidate.categories.filter { GuideMentionPlace.allowedCategories.contains($0) }.prefix(8)),
                  summary: candidate.summary.map { String($0.prefix(1200)) },
                  distance_meters: distance.map { min(20_000, max(0, $0.rounded())) }, side: side,
                  latitude: candidate.latitude, longitude: candidate.longitude,
                  primary_type: candidate.primary_type.flatMap { $0.range(of: "^[a-z_]{1,40}$", options: .regularExpression) != nil ? $0 : nil },
                  open_now: candidate.open_now,
                  locality: candidate.locality.map { String($0.prefix(80)) }.flatMap { $0.isEmpty ? nil : $0 })
    }
    static let allowedCategories: Set<String> = ["history", "art", "nature", "food", "family", "culture", "shopping", "landmark",
                                                 "scenic", "entertainment", "neighborhood", "practical"]
}

enum GuideGeo {
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1, dl = (lon2 - lon1) * .pi / 180
        let sinLat: Double = sin(dp / 2)
        let sinLon: Double = sin(dl / 2)
        let a: Double = sinLat * sinLat + cos(p1) * cos(p2) * sinLon * sinLon
        return 2 * r * asin(min(1, sqrt(a)))
    }

    static func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    static func offset(_ lat: Double, _ lon: Double, meters: Double, bearing: Double) -> (Double, Double) {
        let r = 6_371_000.0, d = meters / r, b = bearing * .pi / 180
        let p1 = lat * .pi / 180, l1 = lon * .pi / 180
        let p2 = asin(sin(p1) * cos(d) + cos(p1) * sin(d) * cos(b))
        let l2 = l1 + atan2(sin(b) * sin(d) * cos(p1), cos(d) - sin(p1) * sin(p2))
        return (p2 * 180 / .pi, l2 * 180 / .pi)
    }

    /// Signed angle from `heading` to `target`, in -180..<180 (positive = to the right).
    static func relative(_ target: Double, to heading: Double) -> Double {
        var delta = (target - heading).truncatingRemainder(dividingBy: 360)
        if delta >= 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    static func side(relative angle: Double) -> String {
        switch abs(angle) {
        case ..<20: "ahead"
        case 160...: "behind"
        default: angle > 0 ? "right" : "left"
        }
    }
}

/// Configurable starting values for driving discovery, not fixed rules. Search circles are
/// centred ahead of the car (city ≈ 0–3 mi ahead, highway ≈ 0–8 mi ahead), and worthwhile places
/// are introduced a few minutes before the car reaches them.
struct GuideDrivingConfig: Sendable {
    var cityAhead = 2_000.0
    var cityRadius = 3_000
    var highwayAhead = 6_000.0
    var highwayRadius = 7_000
    /// Look again once this far into the searched stretch (each search costs four lookups).
    var cityRefetch = 1_500.0
    var highwayRefetch = 5_000.0
    var turnRefetchDegrees = 55.0
    var turnRefetchDistance = 150.0
    /// Introduce a place this many seconds before reaching it ("in a few minutes…").
    var upcoming: ClosedRange<TimeInterval> = 100...330
    /// Within this many seconds it is "coming up on your right", if it was never introduced.
    var passing: TimeInterval = 100
    /// How far off the line of travel a place may lie and still be worth suggesting.
    func detour(_ tier: GuideTier, highway: Bool) -> Double {
        switch (tier, highway) {
        case (.mustSee, true): 5_000
        case (.notable, true): 2_500
        case (.minor, true): 0
        case (.mustSee, false): 2_000
        case (.notable, false): 1_000
        case (.minor, false): 300
        }
    }
    /// Passing mentions are only for places right beside the road.
    func beside(highway: Bool) -> Double { highway ? 500 : 250 }
    /// Places introduced together when they sit this close to each other.
    var groupRadius = 1_500.0
    /// Sunset spots get priority this many minutes before sunset.
    var sunsetWindow: ClosedRange<Double> = 10...75
}

/// Why a candidate was or wasn't chosen, for the debug log ("why didn't Pip mention X?").
struct GuideTrace: Sendable, Equatable {
    var name: String
    var reason: String
}

/// Explainable experience scoring. No provider calls or city-specific rules.
struct GuideExperienceWeights: Sendable {
    var appeal = 0.35
    var personal = 0.30
    var major = 0.30
    var notable = 0.15
    var timely = 0.25
    var lateralPenalty = 0.15
    var repetitionPenalty = 0.12
    var closedPenalty = 0.25

    func factors(_ place: GuideCandidate, timely: Bool, across: Double, limit: Double, repeatedCategory: Bool) -> [(String, Double)] {
        [("appeal", place.visitorAppeal * appeal),
         ("personal", place.profile_match * personal),
         ("significance", place.tier == .mustSee ? major : place.tier == .notable ? notable : 0),
         ("timing", timely ? self.timely : 0),
         ("lateral", -min(1, across / max(limit, 1)) * lateralPenalty),
         ("variety", repeatedCategory ? -repetitionPenalty : 0),
         ("closed", place.open_now == false ? -closedPenalty : 0)]
    }
}

/// Projection onto a supplied route, not road map matching or proof of access.
/// Uses local segment geometry with wrapped longitude differences (including the date line).
enum GuideCorridor {
    struct Projection { var along: Double; var across: Double; var segment: Int; var fraction: Double }
    static func project(latitude: Double, longitude: Double, path: [GuideRoute.Point]) -> Projection? {
        guard path.count >= 2, latitude.isFinite, longitude.isFinite else { return nil }
        var best: Projection?
        var travelled = 0.0
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let length = GuideGeo.distance(a.latitude, a.longitude, b.latitude, b.longitude)
            guard length.isFinite, length > 0 else { continue }
            let bearing = GuideGeo.bearing(a.latitude, a.longitude, b.latitude, b.longitude)
            let distance = GuideGeo.distance(a.latitude, a.longitude, latitude, longitude)
            let angle = GuideGeo.relative(GuideGeo.bearing(a.latitude, a.longitude, latitude, longitude), to: bearing) * .pi / 180
            let fraction = min(1, max(0, distance * cos(angle) / length))
            let across = hypot(distance * sin(angle), distance * cos(angle) - fraction * length)
            if best == nil || across < best!.across {
                best = Projection(along: travelled + fraction * length, across: across, segment: i, fraction: fraction)
            }
            travelled += length
        }
        return best
    }

    static func ahead(_ meters: Double, from origin: Projection, path: [GuideRoute.Point]) -> GuideRoute.Point {
        var remaining = meters
        for i in origin.segment..<(path.count - 1) {
            let a = path[i], b = path[i + 1]
            let length = GuideGeo.distance(a.latitude, a.longitude, b.latitude, b.longitude)
            let start = i == origin.segment ? origin.fraction : 0
            let available = length * (1 - start)
            if remaining <= available {
                let point = GuideGeo.offset(a.latitude, a.longitude, meters: length * start + remaining,
                                            bearing: GuideGeo.bearing(a.latitude, a.longitude, b.latitude, b.longitude))
                return GuideRoute.Point(latitude: point.0, longitude: point.1)
            }
            remaining -= available
        }
        return path.last!
    }
}

struct GuideEngine {
    // Thresholds from the design doc ("Location and triggering", "Choosing what to mention").
    static let maxAccuracy = 50.0
    static let walkingMaxSpeed = 2.2          // ≈ 5 mph
    static let highwayMinSpeed = 22.0         // ≈ 50 mph
    static let stopWindow: TimeInterval = 20
    static let stopSpread = 15.0
    static let notableWalkingRange = 10.0
    static let mustSeeWalkingRange = 125.0
    static let minorWalkingRange = 25.0
    static let groupRadius = 60.0
    static let minimumGap: TimeInterval = 45  // never talk over the previous mention
    static let fetchInterval: TimeInterval = 20
    /// A town is announced at most once in this long, however often GPS drifts across its edge.
    static let areaMemory: TimeInterval = 2 * 3600
    /// A new town counts once two lookups at least this far apart agree.
    static let areaConfirmation: TimeInterval = 20

    var driving = GuideDrivingConfig()
    var plannedOnly = false
    var experienceWeights = GuideExperienceWeights()
    /// Routes must explicitly match the travel mode; existing voice directions are walking.
    private(set) var activeRoute: GuideRoute?
    private var lastCategories: Set<String> = []

    mutating func setRoute(_ route: GuideRoute?) {
        guard activeRoute != route else { return }
        activeRoute = route
        fetchedCenter = nil
    }

    private func routeProjection(_ fix: GuideFix) -> GuideCorridor.Projection? {
        guard let route = activeRoute, route.mode == (motion.isDriving ? .driving : .walking),
              let projection = GuideCorridor.project(latitude: fix.latitude, longitude: fix.longitude, path: route.path),
              projection.across <= max(75, fix.accuracy * 2) else { return nil }
        return projection
    }
    /// Today's sunset where the traveller is, from the backend.
    var sunset: Date?
    /// Candidates checked by the last `decide`, with the reason each was or wasn't chosen.
    private(set) var lastTrace: [GuideTrace] = []
    /// The town (and, for the most talkative setting, neighbourhood) the traveller is in.
    private(set) var currentArea: String?
    private(set) var pendingArea: (name: String, since: Date)?
    private(set) var announcedAreas: [String: Date] = [:]
    /// A town arrival or approach waiting for a quiet moment.
    private(set) var areaEvent: (name: String, situation: GuideSituation, at: Date)?

    var chattiness: GuideChattiness = .normal
    private(set) var candidates: [GuideCandidate] = []
    private(set) var fetchedCenter: (latitude: Double, longitude: Double, radius: Double)?
    private(set) var fetchedAt: Date?
    private(set) var lastFetchAttempt: Date?
    private(set) var mentioned: Set<String> = []
    private(set) var lastMentionAt: Date?
    /// Areas the traveler is inside, with when they entered.
    private(set) var insideAreas: [String: Date] = [:]
    private(set) var recent: [GuideFix] = []
    private(set) var motion: GuideMotion = .unknown
    private(set) var tourMode: GuideTourMode?

    mutating func selectTourMode(_ mode: GuideTourMode) {
        guard tourMode != mode else { return }
        tourMode = mode
        // Keep the latest position, but don't reuse a stop or area entry from the old mode.
        recent = recent.last.map { [$0] } ?? []
        insideAreas = [:]
        fetchedCenter = nil
        fetchedAt = nil
        lastFetchAttempt = nil
        updateMotion()
    }

    private mutating func updateMotion() {
        switch tourMode {
        case .walking: motion = .walking
        case .driving: motion = speed >= Self.highwayMinSpeed ? .highway : .cityDriving
        case nil: motion = Self.motion(for: speed)
        }
    }

    init(chattiness: GuideChattiness = .normal, mentioned: Set<String> = []) {
        self.chattiness = chattiness
        self.mentioned = mentioned
    }

    var latest: GuideFix? { recent.last }

    /// Discards fixes worse than ~50 m and fixes older than the last accepted one.
    @discardableResult
    mutating func ingest(_ fix: GuideFix) -> Bool {
        guard fix.accuracy >= 0, fix.accuracy <= Self.maxAccuracy,
              fix.latitude.isFinite, fix.longitude.isFinite else { return false }
        if let last = recent.last, fix.timestamp <= last.timestamp { return false }
        recent.append(fix)
        recent.removeAll { fix.timestamp.timeIntervalSince($0.timestamp) > 60 }
        updateMotion()
        return true
    }

    /// Median of reported speeds (falling back to distance over time) for the last 15 s.
    var speed: Double {
        guard let last = recent.last else { return 0 }
        let window = recent.filter { last.timestamp.timeIntervalSince($0.timestamp) <= 15 }
        var speeds = window.compactMap { $0.speed >= 0 ? $0.speed : nil }
        if speeds.isEmpty, let first = window.first, first != last {
            let elapsed = last.timestamp.timeIntervalSince(first.timestamp)
            if elapsed > 0 { speeds = [GuideGeo.distance(first.latitude, first.longitude, last.latitude, last.longitude) / elapsed] }
        }
        guard !speeds.isEmpty else { return 0 }
        let sorted = speeds.sorted()
        return sorted[sorted.count / 2]
    }

    static func motion(for speed: Double) -> GuideMotion {
        if speed < walkingMaxSpeed { return .walking }
        if speed >= highwayMinSpeed { return .highway }
        return .cityDriving
    }

    /// Prefer travel direction while moving: phone orientation may differ from walking direction.
    func direction(heading: Double?) -> Double? {
        if motion.isDriving, let course = latest?.course, course >= 0 { return course }
        if let fix = latest, fix.speed >= 0.5, fix.course >= 0 { return fix.course }
        if let heading, heading >= 0 { return heading }
        if let course = latest?.course, course >= 0, speed > 0.8 { return course }
        return nil
    }

    /// On foot: stayed within ~15 m for 20 s or more.
    func isStopped(at now: Date) -> Bool {
        guard let last = recent.last, motion == .walking, now.timeIntervalSince(last.timestamp) < 15 else { return false }
        let window = recent.filter { now.timeIntervalSince($0.timestamp) <= Self.stopWindow + 5 }
        guard let first = window.first, last.timestamp.timeIntervalSince(first.timestamp) >= Self.stopWindow - 2 else { return false }
        let lat = window.map(\.latitude).reduce(0, +) / Double(window.count)
        let lon = window.map(\.longitude).reduce(0, +) / Double(window.count)
        let spread = window.map { GuideGeo.distance(lat, lon, $0.latitude, $0.longitude) }.max() ?? 0
        return spread <= Self.stopSpread + min(10, last.accuracy / 3)
    }

    // MARK: Fetching candidates (one Google lookup per area, never per GPS update)

    /// Where and how wide to look: walking around you; driving in a wide circle centred ahead of
    /// the car, so places several minutes up the road are known before you reach them.
    func fetchPlan() -> GuideNearbyRequest? {
        guard let fix = latest else { return nil }
        let ahead: Double
        let radius: Int
        switch motion {
        case .highway: (ahead, radius) = (driving.highwayAhead, driving.highwayRadius)
        case .cityDriving: (ahead, radius) = (driving.cityAhead, driving.cityRadius)
        case .walking, .unknown:
            if let projection = routeProjection(fix), let route = activeRoute {
                let center = GuideCorridor.ahead(350, from: projection, path: route.path)
                return GuideNearbyRequest(latitude: center.latitude, longitude: center.longitude,
                                          horizontal_accuracy_meters: fix.accuracy, radius_meters: 500, language: "en")
            }
            return GuideNearbyRequest(latitude: fix.latitude, longitude: fix.longitude, horizontal_accuracy_meters: fix.accuracy,
                                      radius_meters: 500, language: "en")
        }
        // Without a direction yet, centre on the car so nothing nearby is missed.
        if let projection = routeProjection(fix), let route = activeRoute {
            let center = GuideCorridor.ahead(ahead, from: projection, path: route.path)
            return GuideNearbyRequest(latitude: center.latitude, longitude: center.longitude,
                                      horizontal_accuracy_meters: fix.accuracy, radius_meters: radius, language: "en", scope: "ahead")
        }
        let center = fix.course >= 0 ? GuideGeo.offset(fix.latitude, fix.longitude, meters: ahead, bearing: fix.course)
                                     : (fix.latitude, fix.longitude)
        return GuideNearbyRequest(latitude: center.0, longitude: center.1, horizontal_accuracy_meters: fix.accuracy,
                                  radius_meters: radius, language: "en", scope: "ahead")
    }

    func needsFetch(at now: Date) -> Bool {
        guard let fix = latest else { return false }
        if let attempt = lastFetchAttempt, now.timeIntervalSince(attempt) < Self.fetchInterval { return false }
        guard let area = fetchedCenter, let fetchedAt else { return true }
        if now.timeIntervalSince(fetchedAt) > 30 * 60 { return true }
        if motion.isDriving, fix.course >= 0, let fetchCourse,
           distanceFromFetch >= driving.turnRefetchDistance,
           abs(GuideGeo.relative(fix.course, to: fetchCourse)) >= driving.turnRefetchDegrees { return true }
        switch motion {
        // Driving searches reach several minutes ahead: look again after covering part of that
        // stretch, or when speeding up onto a highway needs a wider search.
        case .highway:
            return area.radius < Double(driving.highwayRadius) || distanceFromFetch > driving.highwayRefetch
        case .cityDriving:
            return distanceFromFetch > driving.cityRefetch
        case .walking, .unknown:
            let travelled = GuideGeo.distance(area.latitude, area.longitude, fix.latitude, fix.longitude)
            return travelled > area.radius * 0.5
        }
    }

    /// Where the traveller was when the last search was planned.
    private(set) var fetchCourse: Double?
    private(set) var fetchOrigin: (latitude: Double, longitude: Double)?
    private var distanceFromFetch: Double {
        guard let origin = fetchOrigin, let fix = latest else { return .infinity }
        return GuideGeo.distance(origin.latitude, origin.longitude, fix.latitude, fix.longitude)
    }

    mutating func markFetchAttempt(at now: Date) { lastFetchAttempt = now }

    /// Driving keeps places found earlier that are still ahead and unmentioned, so a theme park
    /// spotted ten minutes away is not forgotten by the next search.
    mutating func update(candidates: [GuideCandidate], for request: GuideNearbyRequest, at now: Date, sunset: Date? = nil) {
        let fresh = Set(candidates.map(\.id))
        var kept: [GuideCandidate] = []
        if request.scope == "ahead", let fix = latest {
            kept = self.candidates.filter { old in
                !fresh.contains(old.id) && !mentioned.contains(old.id)
                    && GuideGeo.distance(fix.latitude, fix.longitude, old.latitude, old.longitude) <= 15_000
            }
        }
        self.candidates = Array((candidates + kept).prefix(120))
        fetchedCenter = (request.latitude, request.longitude, Double(request.radius_meters))
        fetchOrigin = latest.map { ($0.latitude, $0.longitude) }
        fetchCourse = latest.flatMap { $0.course >= 0 ? $0.course : nil }
        fetchedAt = now
        if let sunset { self.sunset = sunset }
    }

    // MARK: Choosing what to mention

    func eligible(_ candidate: GuideCandidate) -> Bool {
        guard !mentioned.contains(candidate.id) else { return false }
        if motion.isDriving { return eligibleWhileDriving(candidate) }
        switch (chattiness, candidate.tier) {
        case (_, .mustSee): return true
        case (.quiet, _): return false
        case (.normal, .notable): return candidate.profile_match >= 0.5
        case (.normal, .minor): return false
        case (.tourGuide, .notable): return true
        case (.tourGuide, .minor): return candidate.summary != nil && motion == .walking
        }
    }

    /// From the road, broadly appealing places matter as much as personal ones; practical stops
    /// (Costco, groceries) only for travellers who said they want them.
    func eligibleWhileDriving(_ candidate: GuideCandidate) -> Bool {
        if candidate.categories == ["practical"] { return candidate.profile_match >= 1 && chattiness != .quiet }
        switch (chattiness, candidate.tier) {
        case (_, .mustSee): return true
        case (.quiet, _): return false
        case (.normal, .notable): return candidate.visitorAppeal >= 0.45 || candidate.profile_match >= 1
        case (.normal, .minor): return false
        case (.tourGuide, .notable): return true
        case (.tourGuide, .minor): return motion == .cityDriving && candidate.profile_match >= 1 && candidate.visitorAppeal >= 0.35
        }
    }

    /// Minimum seconds between unprompted mentions: 3 to 5 minutes on foot, scaled by setting.
    var budget: TimeInterval {
        switch (chattiness, motion.isDriving) {
        case (.quiet, _): 300
        case (.normal, false): 210
        case (.normal, true): 120
        case (.tourGuide, false): 100
        case (.tourGuide, true): 60
        }
    }

    /// Inside a zoo or park there is more to see per minute, so Pip may speak more often.
    var venueBudget: TimeInterval {
        switch chattiness {
        case .quiet: 300
        case .normal: 120
        case .tourGuide: 75
        }
    }

    func budgetOpen(at now: Date, mustSee: Bool, inVenue: Bool = false, dense: Bool = false) -> Bool {
        guard let last = lastMentionAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= (mustSee ? Self.minimumGap : (inVenue ? venueBudget : budget * (dense ? 0.75 : 1)))
    }

    /// The notable zoo, park or campus the traveler is inside, if any.
    func enclosingVenue() -> GuideCandidate? {
        guard let fix = latest else { return nil }
        var venue: GuideCandidate?
        for area in candidates where area.isArea && area.tier != .minor {
            let distance = GuideGeo.distance(fix.latitude, fix.longitude, area.latitude, area.longitude)
            guard distance <= area.radius_meters else { continue }
            if venue == nil || area.prominence > venue!.prominence { venue = area }
        }
        return venue
    }

    /// Inside a venue the traveler chose to visit, its exhibits count as notable and match their
    /// interests, so Pip talks about the elephants, not only the zoo's front gate.
    func promoted(_ candidate: GuideCandidate, in venue: GuideCandidate?) -> GuideCandidate {
        guard let venue, candidate.id != venue.id, !candidate.isArea else { return candidate }
        let distance = GuideGeo.distance(venue.latitude, venue.longitude, candidate.latitude, candidate.longitude)
        guard distance <= venue.radius_meters else { return candidate }
        var inside = candidate
        if inside.tier == .minor { inside.tier = .notable }
        inside.profile_match = max(inside.profile_match, 1)
        return inside
    }

    /// Distance to a place, treating parks and districts as areas with a boundary.
    static func edgeDistance(_ fix: GuideFix, _ candidate: GuideCandidate) -> Double {
        max(0, GuideGeo.distance(fix.latitude, fix.longitude, candidate.latitude, candidate.longitude) - candidate.radius_meters)
    }

    private func score(_ candidate: GuideCandidate, distance: Double, range: Double, stopped: Bool) -> Double {
        let proximity = max(0, 1 - distance / max(range, 1))
        return candidate.prominence * 0.25 + proximity * 0.25 + candidate.profile_match * 0.4 + (stopped ? 0.1 : 0)
    }

    /// Keeps `insideAreas` current. An area is announced on entry (within two minutes of it),
    /// not because the traveler happens to be somewhere inside a large park.
    mutating func observeAreas(at now: Date) {
        guard let fix = latest else { return }
        for area in candidates where area.isArea {
            let distance = GuideGeo.distance(fix.latitude, fix.longitude, area.latitude, area.longitude)
            if distance <= area.radius_meters {
                if insideAreas[area.id] == nil { insideAreas[area.id] = now }
            } else if distance > area.radius_meters + 50 {
                insideAreas[area.id] = nil
            }
        }
    }

    func justEntered(_ area: GuideCandidate, at now: Date) -> Bool {
        guard let entered = insideAreas[area.id] else { return false }
        return now.timeIntervalSince(entered) <= 120
    }

    /// The single best thing to mention now, or nil. Does not mark anything as mentioned:
    /// call `markMentioned` only once the mention is actually delivered.
    mutating func decide(at now: Date, heading: Double? = nil) -> GuideDecision? {
        guard let fix = latest, now.timeIntervalSince(fix.timestamp) < 15 else { return nil }
        lastTrace = []
        observeAreas(at: now)
        let travelDirection = self.direction(heading: heading)
        switch motion {
        case .walking:
            if !plannedOnly, let neighbourhood = areaDecision(at: now, fix: fix) { return neighbourhood }
            let stopped = isStopped(at: now)
            let venue = enclosingVenue()
            let pool = candidates.map { promoted($0, in: venue) }
            var best: (GuideCandidate, Double, GuideSituation, Double)?
            for candidate in pool where eligible(candidate) {
                let distance = Self.edgeDistance(fix, candidate)
                let situation: GuideSituation
                let range: Double
                if candidate.isArea {
                    guard justEntered(candidate, at: now) else { continue }
                    situation = .enteredArea; range = candidate.radius_meters
                } else {
                    switch candidate.tier {
                    case .mustSee: range = Self.mustSeeWalkingRange
                    case .notable: range = Self.notableWalkingRange
                    case .minor: range = Self.minorWalkingRange
                    }
                    guard distance <= range else { continue }
                    // People stop in front of what interests them; only must-sees skip the stop.
                    guard candidate.tier == .mustSee || stopped else { continue }
                    situation = .stoppedNearby
                }
                guard budgetOpen(at: now, mustSee: candidate.tier == .mustSee, inVenue: venue != nil) else { continue }
                let value = score(candidate, distance: distance, range: range, stopped: stopped) - Double(candidate.tier.rank) * 0.3
                if best == nil || value > best!.3 { best = (candidate, distance, situation, value) }
            }
            guard let chosen = best else { return nil }
            let place = chosen.0, distance = chosen.1, situation = chosen.2
            // Exhibits are spoken about one at a time, as part of the venue.
            let highlights = situation == .enteredArea || venue != nil ? [] : group(around: place)
            let within = venue.flatMap { $0.id == place.id ? nil : $0.name }
            return GuideDecision(place: place, highlights: highlights, situation: situation,
                                 side: side(of: place, from: fix, direction: travelDirection, distance: distance),
                                 distance: distance, motion: .walking, breaksBudget: place.tier == .mustSee,
                                 within: within)
        case .cityDriving, .highway:
            guard let course = travelDirection else {
                lastTrace = [GuideTrace(name: "—", reason: "no direction of travel yet")]
                return nil
            }
            if !plannedOnly { observeAreaAhead(fix: fix, course: course, at: now) }
            if !plannedOnly, let city = areaDecision(at: now, fix: fix) { return city }
            return drivingDecision(at: now, fix: fix, course: course)
        case .unknown:
            return nil
        }
    }

    /// Where a candidate lies relative to the car: metres along the direction of travel, metres
    /// off that line, and the signed angle (positive = right).
    static func geometry(of candidate: GuideCandidate, from fix: GuideFix, course: Double) -> (along: Double, across: Double, angle: Double, distance: Double) {
        let distance = GuideGeo.distance(fix.latitude, fix.longitude, candidate.latitude, candidate.longitude)
        let angle = GuideGeo.relative(GuideGeo.bearing(fix.latitude, fix.longitude, candidate.latitude, candidate.longitude), to: course)
        return (distance * cos(angle * .pi / 180), abs(distance * sin(angle * .pi / 180)), angle, distance)
    }

    /// Minutes until sunset, when known.
    func minutesToSunset(at now: Date) -> Double? { sunset.map { $0.timeIntervalSince(now) / 60 } }

    /// The best place a few minutes up the road (introduced before the car gets there), or one
    /// right beside the road that was never introduced. Records why each candidate was skipped.
    private mutating func drivingDecision(at now: Date, fix: GuideFix, course: Double) -> GuideDecision? {
        let highway = motion == .highway
        let pace = max(speed, 3)
        let sunsetSoon = minutesToSunset(at: now).map { driving.sunsetWindow.contains($0) } ?? false
        var trace: [(GuideTrace, Double)] = []
        var best: (place: GuideCandidate, situation: GuideSituation, eta: Double, across: Double, angle: Double, distance: Double, value: Double)?
        let ahead = candidates.filter { !mentioned.contains($0.id) }
        // Many worthwhile places ahead: Pip may speak a little more often to keep up.
        let dense = ahead.filter { eligible($0) }.count >= 8
        for candidate in ahead {
            func skip(_ reason: String) { trace.append((GuideTrace(name: candidate.name, reason: reason), candidate.visitorAppeal)) }
            guard eligible(candidate) else { skip("not eligible (\(candidate.tier.rawValue), appeal \(String(format: "%.2f", candidate.visitorAppeal)))"); continue }
            var g = Self.geometry(of: candidate, from: fix, course: course)
            if let origin = routeProjection(fix), let route = activeRoute,
               let target = GuideCorridor.project(latitude: candidate.latitude, longitude: candidate.longitude, path: route.path) {
                g.along = target.along - origin.along
                g.across = target.across
            }
            guard g.along > -candidate.radius_meters else { skip("behind"); continue }
            let eta = max(0, g.along - candidate.radius_meters) / pace
            let detour = driving.detour(candidate.tier, highway: highway)
            guard g.across <= detour + candidate.radius_meters else { skip("\(Int(g.across)) m off the way (limit \(Int(detour)))"); continue }
            let situation: GuideSituation
            if driving.upcoming.contains(eta) {
                situation = .upcoming
            } else if eta < driving.passing, g.across <= driving.beside(highway: highway) + candidate.radius_meters {
                situation = .approaching
            } else if eta < driving.passing {
                skip("too close to suggest a detour"); continue
            } else {
                skip("\(Int(eta / 60)) min ahead: later"); continue
            }
            let timely = sunsetSoon && candidate.isScenic
            guard budgetOpen(at: now, mustSee: candidate.tier == .mustSee || timely, dense: dense) else { skip("waiting: talked recently"); continue }
            let factors = experienceWeights.factors(candidate, timely: timely, across: g.across, limit: detour,
                                                     repeatedCategory: !lastCategories.isDisjoint(with: candidate.categories))
            let value = factors.reduce(0) { $0 + $1.1 }
            if best == nil || value > best!.value {
                best = (candidate, situation, eta, g.across, g.angle, g.distance, value)
            }
            skip(String(format: "candidate, score %.2f: ", value) + factors.map { "\($0.0)=\(String(format: "%.2f", $0.1))" }.joined(separator: ", "))
        }
        guard let chosen = best else {
            lastTrace = trace.sorted { $0.1 > $1.1 }.prefix(12).map(\.0)
            return nil
        }
        let highlights = drivingGroup(around: chosen.place, fix: fix, course: course)
        lastTrace = [GuideTrace(name: chosen.place.name, reason: "chosen: \(chosen.situation.rawValue), \(Int(chosen.eta / 60)) min ahead, \(Int(chosen.across)) m lateral; " + (trace.first { $0.0.name == chosen.place.name }?.0.reason ?? ""))]
            + trace.filter { $0.0.name != chosen.place.name }.sorted { $0.1 > $1.1 }.prefix(11).map(\.0)
        if chosen.situation == .upcoming, let town = townIntroduction(for: chosen.place, fix: fix, at: now) { return town }
        // The side of the line of travel the place lies on, so a place a few kilometres up the
        // road is still "on your left" (a curve ahead can change this; nearer mentions refine it).
        let side = chosen.distance < 1_000
            ? (abs(chosen.angle) < 10 ? "ahead" : (chosen.angle > 0 ? "right" : "left"))
            : (chosen.across < 150 ? "ahead" : (chosen.angle > 0 ? "right" : "left"))
        return GuideDecision(place: chosen.place, highlights: highlights, situation: chosen.situation, side: side,
                             distance: chosen.distance, motion: motion, breaksBudget: chosen.place.tier == .mustSee,
                             minutesAhead: chosen.situation == .upcoming ? max(1, Int((chosen.eta / 60).rounded())) : nil,
                             offRoute: chosen.across,
                             inView: false) // Proximity cannot establish line of sight.
    }

    /// Other worthwhile places beside the chosen one (One Paseo and Del Mar Highlands), so they
    /// are introduced together in one natural sentence.
    func drivingGroup(around place: GuideCandidate, fix: GuideFix, course: Double) -> [GuideCandidate] {
        candidates
            .filter { other in
                other.id != place.id && eligible(other) && other.tier != .minor
                    && GuideGeo.distance(place.latitude, place.longitude, other.latitude, other.longitude) <= driving.groupRadius
                    && isAhead(other, fix: fix, course: course)
            }
            .sorted { $0.visitorAppeal > $1.visitorAppeal }
            .prefix(2).map { $0 }
    }

    private func isAhead(_ place: GuideCandidate, fix: GuideFix, course: Double) -> Bool {
        if let origin = routeProjection(fix), let route = activeRoute,
           let target = GuideCorridor.project(latitude: place.latitude, longitude: place.longitude, path: route.path) {
            return target.along > origin.along
        }
        return Self.geometry(of: place, from: fix, course: course).along > 0
    }

    // MARK: Towns and neighbourhoods

    /// Feeds the town the traveller is in (from the phone's reverse geocoder). A change counts
    /// only after two agreeing lookups, so GPS drift across a boundary is never announced, and
    /// each town is welcomed at most once every two hours.
    mutating func observeArea(_ name: String?, at now: Date) {
        guard let name = name?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return }
        if currentArea == nil {
            // The tour starts here: no welcome to the town you are already in.
            currentArea = name; announcedAreas[Self.key(name)] = now; pendingArea = nil
            return
        }
        guard Self.key(name) != Self.key(currentArea!) else { pendingArea = nil; return }
        guard let pending = pendingArea, Self.key(pending.name) == Self.key(name) else {
            pendingArea = (name, now); return
        }
        guard now.timeIntervalSince(pending.since) >= Self.areaConfirmation else { return }
        currentArea = name; pendingArea = nil
        if recentlyAnnounced(name, at: now) { return }
        // Already introduced as "heading toward" a few minutes ago: no second welcome.
        if let event = areaEvent, Self.key(event.name) == Self.key(name), event.situation == .approachingCity { areaEvent = nil }
        announcedAreas[Self.key(name)] = now
        areaEvent = (name, .enteringCity, now)
    }

    /// While driving, the town most upcoming places belong to, when it differs from the current
    /// one: "You're heading toward Carlsbad…". Uses Google's address data for those places.
    mutating func observeAreaAhead(fix: GuideFix, course: Double, at now: Date) {
        guard motion.isDriving, let current = currentArea, areaEvent == nil else { return }
        let pace = max(speed, 3)
        // The nearest other town that places a few minutes ahead belong to; never one further on
        // while a nearer town is still to come.
        var nearest: (name: String, along: Double)?
        for candidate in candidates {
            guard let town = candidate.locality, Self.key(town) != Self.key(current) else { continue }
            var g = Self.geometry(of: candidate, from: fix, course: course)
            if let origin = routeProjection(fix), let route = activeRoute,
               let target = GuideCorridor.project(latitude: candidate.latitude, longitude: candidate.longitude, path: route.path) {
                g.along = target.along - origin.along
                g.across = target.across
            }
            guard g.along > 0, g.across <= 3_000, (60...300).contains(g.along / pace) else { continue }
            if nearest == nil || g.along < nearest!.along { nearest = (town, g.along) }
        }
        guard let town = nearest?.name, !recentlyAnnounced(town, at: now) else { return }
        announcedAreas[Self.key(town)] = now
        areaEvent = (town, .approachingCity, now)
    }

    func recentlyAnnounced(_ town: String, at now: Date) -> Bool {
        announcedAreas[Self.key(town)].map { now.timeIntervalSince($0) < Self.areaMemory } ?? false
    }

    /// "Carlsbad is coming up! LEGOLAND, the outlets…": when the best place ahead is in a town not
    /// yet introduced, the town is introduced with it and its other highlights.
    private mutating func townIntroduction(for place: GuideCandidate, fix: GuideFix, at now: Date) -> GuideDecision? {
        guard let town = place.locality, let current = currentArea, Self.key(town) != Self.key(current),
              !recentlyAnnounced(town, at: now) else { return nil }
        announcedAreas[Self.key(town)] = now
        let others = candidates.filter { other in
            other.id != place.id && eligible(other) && other.tier != .minor
                && other.locality.map { Self.key($0) == Self.key(town) } ?? false
        }
        let highlights = [place] + others.sorted { $0.visitorAppeal > $1.visitorAppeal }.prefix(2)
        let area = GuideCandidate(id: "locality:\(town)", name: town, latitude: fix.latitude, longitude: fix.longitude,
                                  categories: ["neighborhood"], prominence: 1, tier: .mustSee)
        lastTrace.insert(GuideTrace(name: town, reason: "town ahead, introduced with \(place.name)"), at: 0)
        return GuideDecision(place: area, highlights: highlights, situation: .approachingCity, side: nil, distance: 0,
                             motion: motion, breaksBudget: true)
    }

    /// A pending town announcement, with up to three of its best places as highlights.
    private mutating func areaDecision(at now: Date, fix: GuideFix) -> GuideDecision? {
        guard let event = areaEvent else { return nil }
        // Stale news is dropped rather than announced late.
        guard now.timeIntervalSince(event.at) < 180 else { areaEvent = nil; return nil }
        guard budgetOpen(at: now, mustSee: true) else { return nil }
        let inTown = candidates.filter { candidate in
            !mentioned.contains(candidate.id) && candidate.tier != .minor && candidate.categories != ["practical"]
                && candidate.locality.map { Self.key($0) == Self.key(event.name) } ?? false
        }
        let highlights = Array(inTown.sorted { $0.visitorAppeal > $1.visitorAppeal }.prefix(3))
        let town = GuideCandidate(id: "locality:\(event.name)", name: event.name, latitude: fix.latitude, longitude: fix.longitude,
                                  categories: ["neighborhood"], prominence: 1, tier: .mustSee)
        lastTrace = [GuideTrace(name: event.name, reason: "town: \(event.situation.rawValue), \(highlights.count) highlights")]
        return GuideDecision(place: town, highlights: highlights, situation: event.situation, side: nil, distance: 0,
                             motion: motion, breaksBudget: true)
    }

    /// Case- and accent-insensitive town key ("Solana Beach" from Apple matches Google's).
    static func key(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Several places clustered in a square: one sentence about the whole, two or three names.
    func group(around place: GuideCandidate) -> [GuideCandidate] {
        let neighbours = candidates.filter { other in
            other.id != place.id && !other.isArea && !mentioned.contains(other.id) && other.tier != .minor
                && GuideGeo.distance(place.latitude, place.longitude, other.latitude, other.longitude) <= Self.groupRadius
        }
        guard neighbours.count >= 2 else { return [] }
        let ordered = neighbours.sorted { left, right in
            left.tier.rank != right.tier.rank ? left.tier.rank < right.tier.rank : left.prominence > right.prominence
        }
        return Array(ordered.prefix(3))
    }

    private func side(of place: GuideCandidate, from fix: GuideFix, direction: Double?, distance: Double) -> String? {
        if distance <= 0 { return "here" }
        guard let direction else { return nil }
        return GuideGeo.side(relative: GuideGeo.relative(GuideGeo.bearing(fix.latitude, fix.longitude, place.latitude, place.longitude), to: direction))
    }

    mutating func markMentioned(_ decision: GuideDecision, at now: Date) {
        if decision.situation == .enteringCity || decision.situation == .approachingCity { areaEvent = nil }
        mentioned.insert(decision.place.id)
        for highlight in decision.highlights { mentioned.insert(highlight.id) }
        lastMentionAt = now
        lastCategories = Set(decision.place.categories)
    }

    /// What Pip says the moment the guide starts: the park/zoo/district you are in, otherwise the
    /// best notable place within 250 m. Ignores the stop rule and talk budget (the user just asked).
    func opening(heading: Double? = nil) -> GuideDecision? {
        guard let fix = latest else { return nil }
        let travelDirection = self.direction(heading: heading)
        var area: GuideCandidate?
        var nearest: (GuideCandidate, Double, Double)?
        for candidate in candidates where !mentioned.contains(candidate.id) && candidate.tier != .minor {
            let centre = GuideGeo.distance(fix.latitude, fix.longitude, candidate.latitude, candidate.longitude)
            if candidate.isArea, centre <= candidate.radius_meters {
                if area == nil || candidate.prominence > area!.prominence { area = candidate }
                continue
            }
            let distance = Self.edgeDistance(fix, candidate)
            guard distance <= 250 else { continue }
            let rank: Double = distance - candidate.prominence * 100
            if nearest == nil || rank < nearest!.2 { nearest = (candidate, distance, rank) }
        }
        if let area {
            return GuideDecision(place: area, highlights: [], situation: .enteredArea, side: "here",
                                 distance: 0, motion: motion == .unknown ? .walking : motion, breaksBudget: true)
        }
        guard let chosen = nearest else { return nil }
        return GuideDecision(place: chosen.0, highlights: group(around: chosen.0), situation: .stoppedNearby,
                             side: side(of: chosen.0, from: fix, direction: travelDirection, distance: chosen.1),
                             distance: chosen.1, motion: motion == .unknown ? .walking : motion, breaksBudget: true)
    }

    /// Answers to "what's this?" are never repeated unprompted, but don't use the talk budget.
    mutating func markAsked(_ id: String) { mentioned.insert(id) }

    // MARK: "Pip, what's this?"

    /// The two or three nearest candidates of any tier, nearest first, with left/right if known.
    func whatsThis(heading: Double? = nil, limit: Int = 3) -> [(candidate: GuideCandidate, distance: Double, side: String?)] {
        guard let fix = latest else { return [] }
        let travelDirection = self.direction(heading: heading)
        var nearby: [(candidate: GuideCandidate, distance: Double, rank: Double)] = []
        for candidate in candidates {
            let distance = Self.edgeDistance(fix, candidate)
            guard distance <= 150 else { continue }
            // Slight preference for well-known places at similar distances (GPS error is 10–30 m).
            let rank: Double = distance - candidate.prominence * 20
            nearby.append((candidate: candidate, distance: distance, rank: rank))
        }
        nearby.sort { $0.rank < $1.rank }
        var results: [(candidate: GuideCandidate, distance: Double, side: String?)] = []
        for item in nearby.prefix(limit) {
            let side = self.side(of: item.candidate, from: fix, direction: travelDirection, distance: item.distance)
            results.append((candidate: item.candidate, distance: item.distance, side: side))
        }
        return results
    }
}


/// A walking route from the traveler's position, drawn on the Live Guide map.
struct GuideRoute: Equatable, Sendable {
    struct Point: Equatable, Sendable { var latitude: Double; var longitude: Double }
    var mode: GuideTourMode = .walking
    var name: String
    var destination: Point
    var minutes: Int?
    var meters: Int?
    var path: [Point]

    init(name: String, destination: Point, minutes: Int?, meters: Int?, path: [Point]) {
        self.name = name; self.destination = destination; self.minutes = minutes; self.meters = meters; self.path = path
    }

    /// From the backend's `pip.route` voice event.
    init?(event: [String: Any]) {
        guard let destination = event["destination"] as? [String: Any],
              let name = destination["name"] as? String, !name.isEmpty,
              let latitude = destination["latitude"] as? Double, let longitude = destination["longitude"] as? Double,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        let polyline = event["polyline"] as? String
        self.init(name: String(name.prefix(160)), destination: Point(latitude: latitude, longitude: longitude),
                  minutes: event["walking_minutes"] as? Int, meters: event["distance_meters"] as? Int,
                  path: polyline.map(Self.decode) ?? [])
    }

    /// Google's encoded polyline format (precision 5).
    static func decode(_ encoded: String) -> [Point] {
        let bytes = Array(encoded.utf8)
        var index = 0, latitude = 0, longitude = 0
        var points: [Point] = []
        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.count {
                let byte = Int(bytes[index]) - 63
                guard (0...63).contains(byte), shift <= 30 else { return nil }
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while index < bytes.count, points.count < 5000 {
            guard let dLat = next(), let dLon = next() else { return [] }
            latitude += dLat; longitude += dLon
            guard (-9_000_000...9_000_000).contains(latitude), (-18_000_000...18_000_000).contains(longitude) else { return [] }
            points.append(Point(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
        }
        return points
    }
}

/// A tour is a transient proposal until explicitly started. It never edits saved trips.
struct GuideTourRequest: Codable, Sendable, Equatable {
    struct Origin: Codable, Sendable, Equatable {
        var latitude: Double
        var longitude: Double
        var horizontal_accuracy_meters: Double?
        var captured_at: String
    }
    var origin: Origin
    var mode: String
    var duration_minutes: Int
    var direction: String
    var destination: String?
    var heading: Double?
    var round_trip: Bool
    var language: String
    var area: String? = nil
    var activities: String? = nil
    var moods: [String] = []
    var companions: String? = nil
    var energy: String = "balanced"
    var food: String = "none"
    var cuisine: String? = nil
    var dietary: String? = nil
    var walking_limit_meters: Int = 4000
}

struct GuideTourPlan: Codable, Sendable, Equatable {
    struct Point: Codable, Sendable, Equatable { var latitude: Double; var longitude: Double; var name: String? }
    struct Photo: Codable, Sendable, Equatable {
        struct Author: Codable, Sendable, Equatable { var displayName: String?; var uri: String? }
        var url: String
        var authors: [Author]
    }
    struct Stop: Codable, Sendable, Equatable {
        var place: GuideCandidate
        var stop_seconds: Int
        var reason: String
        var travel_mode: String? = nil
        var visit_kind: String? = nil
        var photo: Photo? = nil
    }
    struct Walk: Codable, Sendable, Equatable {
        var stop_seconds: Int? = nil
        var anchor_id: String
        var place: GuideCandidate
        var polyline: String
        var seconds: Int
        var distance_meters: Double
    }
    var offline_package: GuideOfflinePackage? = nil
    var food_status: String? = nil
    var request: GuideTourRequest? = nil
    var walking_segments: [Walk]? = nil
    var id: String
    /// Set on the device only, when a tour is saved; the server never sends or sees this.
    var name: String? = nil
    var created_at: String
    var offline: Bool? = nil
    var language: String? = nil
    var attribution: String? = nil
    var parking_seconds: Int? = nil
    var walking_seconds: Int? = nil
    var driving_seconds: Int? = nil
    var walking_meters: Double? = nil
    var mode: String
    var duration_minutes: Int
    var round_trip: Bool
    var origin: Point
    var destination: Point
    var estimated_seconds: Int
    var travel_seconds: Int
    var stop_seconds: Int
    var buffer_seconds: Int
    var distance_meters: Double
    var polyline: String
    var stops: [Stop]

    /// The traveler's chosen name, or a plain fallback built from the tour itself.
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let place = destination.name, !place.isEmpty { return place }
        if let place = stops.first?.place.name, !place.isEmpty { return place }
        return String(localized: "My Tour", bundle: AppLanguage.currentBundle, locale: AppLanguage.currentLocale)
    }

    var googleMapsURL: URL? {
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [URLQueryItem(name: "api", value: "1"),
                          URLQueryItem(name: "origin", value: "\(origin.latitude),\(origin.longitude)"),
                          URLQueryItem(name: "destination", value: "\(destination.latitude),\(destination.longitude)"),
                          URLQueryItem(name: "travelmode", value: mode == "walking" ? "walking" : "driving"),
                          URLQueryItem(name: "waypoints", value: stops.filter { GuideGeo.distance($0.place.latitude, $0.place.longitude, destination.latitude, destination.longitude) > 20 }.prefix(3).map { "\($0.place.latitude),\($0.place.longitude)" }.joined(separator: "|"))]
        return url.url
    }
    var route: GuideRoute {
        var route = GuideRoute(name: destination.name ?? stops.last?.place.name ?? "", destination: .init(latitude: destination.latitude, longitude: destination.longitude),
                               minutes: Int(ceil(Double(estimated_seconds) / 60)), meters: Int(distance_meters), path: GuideRoute.decode(polyline))
        route.mode = mode == "walking" ? .walking : .driving
        return route
    }
    var isUsable: Bool {
        ["walking", "driving", "mixed"].contains(mode) && (5...480).contains(duration_minutes)
            && estimated_seconds > 0 && estimated_seconds <= duration_minutes * 60
            && distance_meters.isFinite && (0...40_000_000).contains(distance_meters)
            && !stops.isEmpty && (offline == true || route.path.count >= 2) && stops.count <= 4
            && Set(stops.map { $0.place.id }).count == stops.count
            && stops.allSatisfy { (-90...90).contains($0.place.latitude) && (-180...180).contains($0.place.longitude) && $0.stop_seconds >= 0 }
            && (mode != "mixed" || offline == true || walking_segments?.isEmpty == false)
    }
}

struct GuideTourReply: Decodable, Sendable {
    var status: String
    var plan: GuideTourPlan?
    var minimum_minutes: Int?
    private enum CodingKeys: String, CodingKey { case status, minimum_minutes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        minimum_minutes = try c.decodeIfPresent(Int.self, forKey: .minimum_minutes)
        plan = status == "ok" ? try GuideTourPlan(from: decoder) : nil
    }
}

struct GuideOfflineRequest: Encodable, Sendable {
    struct Stop: Encodable, Sendable {
        var name: String; var latitude: Double; var longitude: Double
        var travel_mode: String = "walking"; var stop_seconds: Int = 300; var return_to_anchor: Bool = false
    }
    var stops: [Stop]
    var duration_minutes: Int
    var language: String
    var mode: String
    var preferences: Preferences
    var round_trip: Bool
    var origin: Stop
    struct Preferences: Encodable, Sendable {
        var moods: [String]; var companions: String; var energy: String; var interests: String = ""
    }
}

struct GuideOfflinePackage: Codable, Sendable, Equatable {
    struct OfflineImage: Codable, Sendable, Equatable {
        var stop_index: Int; var data: String; var sha256: String; var bytes: Int
        var credit: String; var source: String; var license: String; var license_url: String; var modified: String
    }
    var images: [OfflineImage]? = nil
    struct Clip: Codable, Sendable, Equatable, Identifiable {
        var id: String; var kind: String; var stop_index: Int?; var title: String; var text: String
        var question: String?; var fact_ids: [Int]
    }
    struct Audio: Codable, Sendable, Equatable {
        var data: String; var sha256: String; var bytes: Int; var voice: String; var model: String
    }
    var version: Int; var script_model: String; var tts_model: String; var voice: String; var personality: String
    var clips: [Clip]; var audio: [String: Audio]; var voice_disclosure: String
    var byteCount: Int { audio.values.reduce(0) { $0 + $1.bytes } + (images ?? []).reduce(0) { $0 + $1.bytes } }
    // Fail closed: no partial packages or legacy device-speech downloads are playable.
    var structurallyComplete: Bool {
        version == 2 && !clips.isEmpty && clips.count <= 26 && Set(clips.map(\.id)).count == clips.count
            && Set(audio.keys) == Set(clips.map(\.id)) && clips.allSatisfy { !$0.text.isEmpty }
            && audio.values.allSatisfy { $0.bytes > 0 && $0.bytes <= 2_000_000 && $0.voice == voice && $0.model == tts_model }
    }
    func verified(stopCount: Int) -> Bool {
        guard structurallyComplete, (1...4).contains(stopCount) else { return false }
        var expected = ["intro": "introduction", "complete": "completion"]
        for i in 0..<stopCount {
            expected["stop_\(i)"] = "stop"; expected["deep_\(i)"] = "deeper"; expected["transition_\(i)"] = "transition"
            expected["qa_\(i)_0"] = "answer"; expected["qa_\(i)_1"] = "answer"
        }
        guard Set(expected.keys) == Set(clips.map(\.id)), clips.allSatisfy({ clip in
            expected[clip.id] == clip.kind && (clip.stop_index.map { (0..<stopCount).contains($0) && clip.fact_ids.contains($0) } ?? ["intro", "complete"].contains(clip.id))
                && clip.fact_ids.allSatisfy { (0..<stopCount).contains($0) } && (clip.kind != "answer" || !(clip.question ?? "").isEmpty)
        }) else { return false }
        return audio.values.allSatisfy { Self.validData($0.data, bytes: $0.bytes, hash: $0.sha256) }
            && (images ?? []).allSatisfy {
                (0..<stopCount).contains($0.stop_index) && $0.bytes <= 500_000
                    && Self.validData($0.data, bytes: $0.bytes, hash: $0.sha256)
                    && !$0.credit.isEmpty && ["CC BY-SA 4.0", "CC BY 4.0", "CC0", "Public domain"].contains($0.license)
                    && $0.source.hasPrefix("https://commons.wikimedia.org/")
            }
    }
    private static func validData(_ encoded: String, bytes: Int, hash: String) -> Bool {
        guard let data = Data(base64Encoded: encoded), data.count == bytes else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == hash
    }
    func answer(for question: String) -> Clip? {
        let normalized = Self.normalized(question)
        guard !normalized.isEmpty else { return nil }
        // Conservative matching avoids choosing a merely similar but unrelated factual answer.
        return clips.first { $0.kind == "answer" && Self.normalized($0.question ?? "") == normalized }
    }
    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
}

struct GuideOfflineAudioRequest: Encodable, Sendable { var text: String; var voice: String; var personality: String }

/// Progress follows arrival/departure, not whether narration has played.
struct GuideTourProgress: Sendable {
    struct Checkpoint: Codable, Sendable {
        var planID: String; var started: Date; var index: Int; var arrived: Bool; var arrivedAt: Date?; var walkingStage: Int
    }
    var checkpoint: Checkpoint { .init(planID: plan.id, started: started, index: index, arrived: arrived, arrivedAt: arrivedAt, walkingStage: walkingStage) }
    init(plan: GuideTourPlan, checkpoint: Checkpoint) {
        self.plan = plan; started = checkpoint.started; index = min(max(0, checkpoint.index), plan.stops.count)
        arrived = checkpoint.arrived; arrivedAt = checkpoint.arrivedAt; walkingStage = min(max(0, checkpoint.walkingStage), 2)
    }
    var plan: GuideTourPlan
    var started: Date
    private(set) var index = 0
    private(set) var arrived = false
    private var arrivedAt: Date?
    private(set) var walkingStage = 0 // 0: visit anchor, 1: walk out, 2: return to anchor
    var expired: Bool = false

    init(plan: GuideTourPlan, started: Date) { self.plan = plan; self.started = started }

    private var walk: GuideTourPlan.Walk? {
        guard index < plan.stops.count else { return nil }
        return plan.walking_segments?.first { $0.anchor_id == plan.stops[index].place.id }
    }
    var next: GuideCandidate? {
        guard index < plan.stops.count else { return nil }
        return walkingStage == 1 ? walk?.place : plan.stops[index].place
    }
    var googleMapsURL: URL? {
        guard plan.offline != true else { return nil }
        guard walkingStage > 0, let walk, index < plan.stops.count else { return plan.googleMapsURL }
        let anchor = plan.stops[index].place
        let from = walkingStage == 1 ? anchor : walk.place
        let to = walkingStage == 1 ? walk.place : anchor
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [.init(name: "api", value: "1"), .init(name: "travelmode", value: "walking"),
                          .init(name: "origin", value: "\(from.latitude),\(from.longitude)"),
                          .init(name: "destination", value: "\(to.latitude),\(to.longitude)")]
        return url.url
    }
    var currentMode: GuideTourMode {
        if plan.offline == true, index < plan.stops.count, let mode = plan.stops[index].travel_mode { return mode == "walking" ? .walking : .driving }
        return plan.mode == "walking" || walkingStage > 0 ? .walking : .driving
    }
    var currentRoute: GuideRoute {
        guard walkingStage > 0, let walk else { return plan.route }
        var route = GuideRoute(name: next?.name ?? "", destination: .init(latitude: plan.stops[index].place.latitude, longitude: plan.stops[index].place.longitude),
                               minutes: Int(ceil(Double(walk.seconds) / 60)), meters: Int(walk.distance_meters), path: GuideRoute.decode(walk.polyline))
        route.mode = .walking
        return route
    }
    mutating func update(_ fix: GuideFix, at now: Date) {
        expired = now.timeIntervalSince(started) >= Double(plan.duration_minutes * 60)
        guard let next else { return }
        let distance = GuideGeo.distance(fix.latitude, fix.longitude, next.latitude, next.longitude)
        let passing = plan.stops[index].stop_seconds == 0 && walkingStage == 0
        let triggerDistance = passing ? (currentMode == .walking ? 100.0 : 180.0) : (currentMode == .walking ? 40.0 : 65.0)
        if distance < triggerDistance, passing || (fix.speed >= 0 && fix.speed < 3) {
            arrived = true
            if arrivedAt == nil { arrivedAt = now }
        }
        let dwell = walkingStage == 1 ? (walk?.stop_seconds ?? 120) : walkingStage == 2 ? 0 : plan.stops[index].stop_seconds
        let visitedLongEnough = !passing && (arrivedAt.map { now.timeIntervalSince($0) >= Double(dwell) } ?? false)
        if arrived && (distance > (passing ? triggerDistance : 100) || visitedLongEnough) {
            if walkingStage == 0 && walk != nil && plan.offline != true { walkingStage = 1 }
            else if walkingStage == 1 { walkingStage = 2 }
            else { index += 1; walkingStage = 0 }
            arrived = false; arrivedAt = nil
        }
    }
}
