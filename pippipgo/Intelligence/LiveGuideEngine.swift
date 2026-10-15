import Foundation

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
struct GuideStartContext: Codable, Sendable { var venue: String?; var nearby: [GuideMentionPlace] }

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
            return GuideNearbyRequest(latitude: fix.latitude, longitude: fix.longitude, horizontal_accuracy_meters: fix.accuracy,
                                      radius_meters: 500, language: "en")
        }
        // Without a direction yet, centre on the car so nothing nearby is missed.
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
        observeAreas(at: now)
        let travelDirection = self.direction(heading: heading)
        switch motion {
        case .walking:
            if let neighbourhood = areaDecision(at: now, fix: fix) { return neighbourhood }
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
            observeAreaAhead(fix: fix, course: course, at: now)
            if let city = areaDecision(at: now, fix: fix) { return city }
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
            let g = Self.geometry(of: candidate, from: fix, course: course)
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
            var value = candidate.visitorAppeal * 0.35 + candidate.profile_match * 0.3
            value += candidate.tier == .mustSee ? 0.3 : candidate.tier == .notable ? 0.15 : 0
            value += timely ? 0.25 : 0
            value -= min(1, g.across / max(detour, 1)) * 0.15
            if best == nil || value > best!.value {
                best = (candidate, situation, eta, g.across, g.angle, g.distance, value)
            }
            skip(String(format: "candidate, score %.2f", value))
        }
        guard let chosen = best else {
            lastTrace = trace.sorted { $0.1 > $1.1 }.prefix(12).map(\.0)
            return nil
        }
        let highlights = drivingGroup(around: chosen.place, fix: fix, course: course)
        lastTrace = [GuideTrace(name: chosen.place.name, reason: "chosen: \(chosen.situation.rawValue), \(Int(chosen.eta / 60)) min ahead, \(Int(chosen.across)) m off the way")]
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
                             inView: chosen.across < 250 && chosen.distance < 600)
    }

    /// Other worthwhile places beside the chosen one (One Paseo and Del Mar Highlands), so they
    /// are introduced together in one natural sentence.
    func drivingGroup(around place: GuideCandidate, fix: GuideFix, course: Double) -> [GuideCandidate] {
        candidates
            .filter { other in
                other.id != place.id && eligible(other) && other.tier != .minor
                    && GuideGeo.distance(place.latitude, place.longitude, other.latitude, other.longitude) <= driving.groupRadius
                    && Self.geometry(of: other, from: fix, course: course).along > 0
            }
            .sorted { $0.visitorAppeal > $1.visitorAppeal }
            .prefix(2).map { $0 }
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
            let g = Self.geometry(of: candidate, from: fix, course: course)
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
                index += 1
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : (result >> 1) }
            }
            return nil
        }
        while index < bytes.count, points.count < 5000 {
            guard let dLat = next(), let dLon = next() else { break }
            latitude += dLat; longitude += dLon
            points.append(Point(latitude: Double(latitude) / 1e5, longitude: Double(longitude) / 1e5))
        }
        return points
    }
}
