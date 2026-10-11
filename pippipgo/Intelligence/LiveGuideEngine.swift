import Foundation

// Live local guide, phase 1. Pure decision logic with no Core Location, networking or UI, so
// every timing rule is unit-testable. The phone decides when Pip speaks; the backend only
// supplies tiered candidates and writes the words.

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
enum GuideTourMode: String, CaseIterable, Identifiable {
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
    var isArea: Bool { radius_meters > 0 }
}

struct GuideNearbyRequest: Codable, Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    var horizontal_accuracy_meters: Double?
    var radius_meters: Int
    var language: String
}

struct GuideNearbyResponse: Codable, Sendable {
    var status: String
    var retrieved_at: String?
    var radius_meters: Int?
    var interests: [String] = []
    var sources: [String] = []
    var candidates: [GuideCandidate] = []
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
}

enum GuideSituation: String, Sendable { case stoppedNearby = "stopped_nearby", approaching, enteredArea = "entered_area", asked }

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

    func request(language: String) -> GuideMentionRequest {
        GuideMentionRequest(
            place: GuideMentionPlace(place, distance: distance, side: side),
            highlights: highlights.map { GuideMentionPlace($0, distance: nil, side: nil) },
            situation: situation.rawValue,
            mode: motion.isDriving ? "driving" : "walking",
            language: language,
            within: within.map { String($0.prefix(160)) })
    }
}

extension GuideMentionPlace {
    init(_ candidate: GuideCandidate, distance: Double?, side: String?) {
        self.init(id: String(candidate.id.prefix(300)), name: String(candidate.name.prefix(160)), tier: candidate.tier,
                  categories: Array(candidate.categories.filter { GuideMentionPlace.allowedCategories.contains($0) }.prefix(8)),
                  summary: candidate.summary.map { String($0.prefix(1200)) },
                  distance_meters: distance.map { min(20_000, max(0, $0.rounded())) }, side: side,
                  latitude: candidate.latitude, longitude: candidate.longitude)
    }
    static let allowedCategories: Set<String> = ["history", "art", "nature", "food", "family", "culture", "shopping", "landmark"]
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

struct GuideEngine {
    // Thresholds from the design doc ("Location and triggering", "Choosing what to mention").
    static let maxAccuracy = 50.0
    static let walkingMaxSpeed = 2.2          // ≈ 5 mph
    static let highwayMinSpeed = 22.0         // ≈ 50 mph
    static let stopWindow: TimeInterval = 20
    static let stopSpread = 15.0
    static let notableWalkingRange = 45.0
    static let mustSeeWalkingRange = 125.0
    static let minorWalkingRange = 25.0
    static let groupRadius = 60.0
    static let minimumGap: TimeInterval = 45  // never talk over the previous mention
    static let fetchInterval: TimeInterval = 20

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

    /// Driving uses the direction of travel; walking only when a compass heading is supplied.
    func direction(heading: Double?) -> Double? {
        if motion.isDriving, let course = latest?.course, course >= 0 { return course }
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

    /// Where and how wide to look, sized for speed: walking around you, driving ahead of you.
    func fetchPlan() -> GuideNearbyRequest? {
        guard let fix = latest else { return nil }
        let center: (Double, Double)
        let radius: Int
        switch motion {
        case .highway:
            radius = 1500
            center = fix.course >= 0 ? GuideGeo.offset(fix.latitude, fix.longitude, meters: 1000, bearing: fix.course) : (fix.latitude, fix.longitude)
        case .cityDriving:
            radius = 900
            center = fix.course >= 0 ? GuideGeo.offset(fix.latitude, fix.longitude, meters: 400, bearing: fix.course) : (fix.latitude, fix.longitude)
        case .walking, .unknown:
            radius = 500
            center = (fix.latitude, fix.longitude)
        }
        return GuideNearbyRequest(latitude: center.0, longitude: center.1, horizontal_accuracy_meters: fix.accuracy, radius_meters: radius, language: "en")
    }

    func needsFetch(at now: Date) -> Bool {
        guard let fix = latest else { return false }
        if let attempt = lastFetchAttempt, now.timeIntervalSince(attempt) < Self.fetchInterval { return false }
        guard let area = fetchedCenter, let fetchedAt else { return true }
        if now.timeIntervalSince(fetchedAt) > 30 * 60 { return true }
        // Refetch before the covered area runs out (sooner on the highway, where look-ahead is 900 m).
        let travelled = GuideGeo.distance(area.latitude, area.longitude, fix.latitude, fix.longitude)
        return travelled > area.radius * (motion == .highway ? 0.4 : 0.5)
    }

    mutating func markFetchAttempt(at now: Date) { lastFetchAttempt = now }

    mutating func update(candidates: [GuideCandidate], for request: GuideNearbyRequest, at now: Date) {
        self.candidates = candidates
        fetchedCenter = (request.latitude, request.longitude, Double(request.radius_meters))
        fetchedAt = now
    }

    // MARK: Choosing what to mention

    func eligible(_ candidate: GuideCandidate) -> Bool {
        guard !mentioned.contains(candidate.id) else { return false }
        if motion == .highway { return candidate.tier == .mustSee }
        switch (chattiness, candidate.tier) {
        case (_, .mustSee): return true
        case (.quiet, _): return false
        case (.normal, .notable): return candidate.profile_match >= 0.5
        case (.normal, .minor): return false
        case (.tourGuide, .notable): return true
        case (.tourGuide, .minor): return candidate.summary != nil && motion == .walking
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

    func budgetOpen(at now: Date, mustSee: Bool, inVenue: Bool = false) -> Bool {
        guard let last = lastMentionAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed >= (mustSee ? Self.minimumGap : (inVenue ? venueBudget : budget))
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
        return candidate.prominence * 0.45 + proximity * 0.25 + candidate.profile_match * 0.2 + (stopped ? 0.1 : 0)
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
            guard let course = travelDirection else { return nil }
            let lookahead: Double = motion == .highway ? 30 : 18
            let reach = speed * lookahead
            let corridor: Double = motion == .highway ? 400 : 200
            var best: (GuideCandidate, Double, Double, Double)?
            for candidate in candidates where eligible(candidate) {
                let distance = GuideGeo.distance(fix.latitude, fix.longitude, candidate.latitude, candidate.longitude)
                let angle = GuideGeo.relative(GuideGeo.bearing(fix.latitude, fix.longitude, candidate.latitude, candidate.longitude), to: course)
                let along = distance * cos(angle * .pi / 180)
                let across = abs(distance * sin(angle * .pi / 180))
                // Coming up ahead, reached within the look-ahead window, near the projected path.
                guard along > 0, along <= reach + candidate.radius_meters, across <= corridor + candidate.radius_meters else { continue }
                guard budgetOpen(at: now, mustSee: candidate.tier == .mustSee) else { continue }
                let value = score(candidate, distance: along, range: reach, stopped: false) - Double(candidate.tier.rank) * 0.3
                if best == nil || value > best!.3 { best = (candidate, distance, angle, value) }
            }
            guard let chosen = best else { return nil }
            let angle = chosen.2
            let side = abs(angle) < 10 ? "ahead" : (angle > 0 ? "right" : "left")
            return GuideDecision(place: chosen.0, highlights: [], situation: .approaching, side: side,
                                 distance: chosen.1, motion: motion, breaksBudget: chosen.0.tier == .mustSee)
        case .unknown:
            return nil
        }
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
