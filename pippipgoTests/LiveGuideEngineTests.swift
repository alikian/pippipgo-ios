import Foundation
import Testing
@testable import pippipgo

/// Piazza-sized fixtures around a point in San Diego (the phase 1 pilot city).
private let origin = (latitude: 32.7314, longitude: -117.1506)

private func point(north: Double = 0, east: Double = 0) -> (Double, Double) {
    let north = GuideGeo.offset(origin.latitude, origin.longitude, meters: north, bearing: 0)
    return GuideGeo.offset(north.0, north.1, meters: east, bearing: 90)
}

private func place(_ id: String, tier: GuideTier, north: Double = 0, east: Double = 0, radius: Double = 0,
                   match: Double = 0.5, prominence: Double? = nil, summary: String? = "A summary.") -> GuideCandidate {
    let p = point(north: north, east: east)
    return GuideCandidate(id: id, name: id, latitude: p.0, longitude: p.1, radius_meters: radius, categories: ["history"],
                          prominence: prominence ?? (tier == .mustSee ? 0.95 : tier == .notable ? 0.75 : 0.4),
                          tier: tier, summary: summary, profile_match: match)
}

private func fix(north: Double = 0, east: Double = 0, at time: Date, speed: Double = 0, course: Double = -1, accuracy: Double = 8) -> GuideFix {
    let p = point(north: north, east: east)
    return GuideFix(latitude: p.0, longitude: p.1, accuracy: accuracy, speed: speed, course: course, timestamp: time)
}

private func engine(_ candidates: [GuideCandidate], chattiness: GuideChattiness = .normal) -> GuideEngine {
    var engine = GuideEngine(chattiness: chattiness)
    let request = GuideNearbyRequest(latitude: origin.latitude, longitude: origin.longitude, radius_meters: 500, language: "en")
    engine.update(candidates: candidates, for: request, at: Date(timeIntervalSince1970: 0))
    return engine
}

/// Walks past (or stands at) `north` metres for `seconds`, one fix per second.
private func stand(_ engine: inout GuideEngine, north: Double = 0, from start: Date, seconds: Int) -> Date {
    var now = start
    for second in 0...seconds {
        now = start.addingTimeInterval(Double(second))
        engine.ingest(fix(north: north + Double(second % 2), at: now, speed: 0.1))
    }
    return now
}

struct LiveGuideEngineTests {
    let t0 = Date(timeIntervalSince1970: 1_000)

    @Test func markerStopsForStationaryUnknownAndStaleSpeed() {
        #expect(fix(at: t0, speed: 1.2).isMoving(at: t0))
        #expect(!fix(at: t0, speed: 0).isMoving(at: t0))
        #expect(!fix(at: t0, speed: 0.49).isMoving(at: t0))
        #expect(!fix(at: t0, speed: -1).isMoving(at: t0))
        #expect(!fix(at: t0, speed: 1.2).isMoving(at: t0.addingTimeInterval(15)))
        #expect(!fix(at: t0, speed: .nan).isMoving(at: t0))
    }

    @Test func personalHighlightCanOutrankMoreFamousNearbyPlace() {
        var e = engine([
            place("small gallery", tier: .notable, north: 5, match: 1, prominence: 0.3),
            place("popular church", tier: .notable, north: 5, match: 0.5, prominence: 0.8)
        ])
        let now = stand(&e, from: t0, seconds: 21)
        #expect(e.decide(at: now)?.place.id == "small gallery")
    }

    @Test func ignoresInaccurateAndOutOfOrderFixes() {
        var e = engine([])
        let inaccurateAccepted = e.ingest(fix(at: t0, accuracy: 80))
        #expect(!inaccurateAccepted)
        let freshAccepted = e.ingest(fix(at: t0))
        #expect(freshAccepted)
        let oldAccepted = e.ingest(fix(at: t0.addingTimeInterval(-1)))
        #expect(!oldAccepted)
        #expect(e.recent.count == 1)
    }

    @Test func picksModeFromSpeed() {
        #expect(GuideEngine.motion(for: 1.4) == .walking)
        #expect(GuideEngine.motion(for: 13) == .cityDriving)
        #expect(GuideEngine.motion(for: 27) == .highway)
    }

    @Test func selectedDrivingTourStaysDrivingWhenStopped() {
        var e = engine([place("museum", tier: .notable, north: 25)])
        e.selectTourMode(.driving)
        let now = stand(&e, from: t0, seconds: 25)
        #expect(e.motion == .cityDriving)
        #expect(!e.isStopped(at: now))
        let stoppedDecision = e.decide(at: now)
        #expect(stoppedDecision == nil)
        // Driving looks ahead in a wider circle (parked, with no direction yet, it centres on the car).
        #expect(e.fetchPlan()?.radius_meters == 3000)
        #expect(e.fetchPlan()?.scope == "ahead")
        e.ingest(fix(at: now.addingTimeInterval(20), speed: 27, course: 0))
        #expect(e.motion == .highway)
    }

    @Test func modeSwitchChangesTriggersWithoutRepeatingPlaces() throws {
        var e = engine([place("landmark", tier: .mustSee, north: 110)])
        e.ingest(fix(at: t0, speed: 12, course: 0))
        let decisionResult = e.decide(at: t0)
        let decision = try #require(decisionResult)
        e.markMentioned(decision, at: t0)
        e.selectTourMode(.walking)
        #expect(e.motion == .walking)
        #expect(e.fetchPlan()?.radius_meters == 500)
        #expect(e.needsFetch(at: t0))
        #expect(e.mentioned.contains("landmark"))
        #expect(!e.budgetOpen(at: t0, mustSee: true))
        #expect(!e.isStopped(at: t0))
        e.ingest(fix(at: t0.addingTimeInterval(1), speed: 27, course: 0))
        #expect(e.motion == .walking)
    }

    @Test func notablePlacesWaitForTheTravelerToStop() {
        var e = engine([place("church", tier: .notable, north: 30)])
        // Walking past at normal pace: no mention.
        for second in 0...10 {
            e.ingest(fix(north: Double(second) * 1.4, at: t0.addingTimeInterval(Double(second)), speed: 1.4))
        }
        #expect(e.decide(at: t0.addingTimeInterval(10)) == nil)
        // Stopping for 20 s within the current 10 m range: Pip speaks.
        let now = stand(&e, north: 24, from: t0.addingTimeInterval(11), seconds: 21)
        #expect(e.isStopped(at: now))
        let decision = e.decide(at: now)
        #expect(decision?.place.id == "church")
        #expect(decision?.situation == .stoppedNearby)
    }

    @Test func mustSeesSpeakWithoutStoppingAndBestCandidateWins() {
        var e = engine([place("plaque", tier: .minor, north: 5), place("pantheon", tier: .mustSee, north: 110)])
        e.ingest(fix(at: t0, speed: 1.3))
        let decision = e.decide(at: t0)
        #expect(decision?.place.id == "pantheon")
        #expect(decision?.breaksBudget == true)
    }

    @Test func talkBudgetLimitsUnpromptedMentionsAndNothingRepeats() throws {
        var e = engine([place("a", tier: .notable, north: 10), place("b", tier: .notable, north: 18)])
        var now = stand(&e, from: t0, seconds: 21)
        let firstResult = e.decide(at: now)
        let first = try #require(firstResult)
        #expect(first.place.id == "a")
        e.markMentioned(first, at: now)
        // Still stopped and b is in range, but the 3.5-minute talk budget is closed.
        now = stand(&e, from: now.addingTimeInterval(1), seconds: 30)
        #expect(e.decide(at: now) == nil)
        // Once the budget reopens, b is allowed; a never repeats.
        now = stand(&e, north: 15, from: now.addingTimeInterval(e.budget), seconds: 21)
        #expect(e.decide(at: now)?.place.id == "b")
    }

    @Test func chattinessControlsWhatIsEligible() {
        let notableOffProfile = place("gallery", tier: .notable, match: 0)
        #expect(!engine([notableOffProfile], chattiness: .normal).eligible(notableOffProfile))
        #expect(engine([notableOffProfile], chattiness: .tourGuide).eligible(notableOffProfile))
        #expect(!engine([notableOffProfile], chattiness: .quiet).eligible(notableOffProfile))
        let mustSee = place("trevi", tier: .mustSee)
        #expect(engine([mustSee], chattiness: .quiet).eligible(mustSee))
        #expect(GuideEngine(chattiness: .quiet).budget > GuideEngine(chattiness: .tourGuide).budget)
    }

    @Test func clustersBecomeOneGroupedMention() throws {
        var e = engine([
            place("square", tier: .notable, north: 10, prominence: 0.8),
            place("fountain", tier: .notable, north: 20),
            place("church", tier: .notable, north: 25, east: 20),
            place("far", tier: .notable, north: 300),
        ])
        let now = stand(&e, from: t0, seconds: 21)
        let decisionResult = e.decide(at: now)
        let decision = try #require(decisionResult)
        #expect(Set(decision.highlights.map(\.id)).isSubset(of: ["square", "fountain", "church"]))
        #expect(decision.highlights.count == 2)
        e.markMentioned(decision, at: now)
        #expect(e.mentioned.count == 3)
    }

    @Test func parksAreAnnouncedOnEntryOnly() {
        var e = engine([place("park", tier: .mustSee, north: 400, radius: 300)])
        e.ingest(fix(north: 0, at: t0, speed: 1.4))
        #expect(e.decide(at: t0) == nil) // 100 m outside the boundary
        e.ingest(fix(north: 110, at: t0.addingTimeInterval(70), speed: 1.4))
        let decision = e.decide(at: t0.addingTimeInterval(70))
        #expect(decision?.situation == .enteredArea)
        #expect(decision?.side == "here")
    }

    @Test func drivingAnnouncesWhatIsComingUpWithItsSide() throws {
        // 13 m/s (≈ 30 mph) heading north; a notable place 200 m ahead and 60 m to the east.
        var e = engine([place("bridge", tier: .notable, north: 200, east: 60), place("behind", tier: .mustSee, north: -150)])
        for second in 0...4 {
            e.ingest(fix(north: Double(second) * 13 - 52, at: t0.addingTimeInterval(Double(second)), speed: 13, course: 0))
        }
        #expect(e.motion == .cityDriving)
        let decisionResult = e.decide(at: t0.addingTimeInterval(4))
        let decision = try #require(decisionResult)
        #expect(decision.place.id == "bridge")
        #expect(decision.situation == .approaching)
        #expect(decision.side == "right")
        #expect(decision.request(language: "en").mode == "driving")
    }

    @Test func drivingIntroducesPlacesMinutesBeforeReachingThem() throws {
        // At 30 mph (13.4 m/s) a must-see 3 km ahead is about 4 minutes away: introduce it now.
        // One 8 km ahead (10 minutes) waits until it is closer.
        for (north, shouldAnnounce) in [(3_000.0, true), (8_000.0, false)] {
            var e = engine([place("theme park", tier: .mustSee, north: north, east: 800)])
            e.selectTourMode(.driving)
            for second in 0...4 {
                e.ingest(fix(at: t0.addingTimeInterval(Double(second)), speed: 13.4, course: 0))
            }
            let decision = e.decide(at: t0.addingTimeInterval(4))
            #expect((decision != nil) == shouldAnnounce)
            if let decision {
                #expect(decision.situation == .upcoming)
                #expect(decision.minutesAhead == 4)
                #expect(decision.side == "right")
                #expect(decision.inView == false)
                let request = decision.request(language: "en")
                #expect(request.minutes_ahead == 4 && request.off_route_meters == 800)
            }
        }
    }

    @Test func drivingLeadRejectsBehindAndOutsideCorridor() {
        var e = engine([place("behind", tier: .mustSee, north: -300),
                        place("off road", tier: .mustSee, north: 300, east: 2_500)])
        e.selectTourMode(.driving)
        for second in 0...4 {
            e.ingest(fix(at: t0.addingTimeInterval(Double(second)), speed: 11.176, course: 0))
        }
        #expect(e.decide(at: t0.addingTimeInterval(4)) == nil)
        #expect(e.lastTrace.contains(GuideTrace(name: "behind", reason: "behind")))
        #expect(e.lastTrace.contains { $0.name == "off road" && $0.reason.contains("off the way") })
    }

    @Test func highwayPrefersMustSees() {
        var e = engine([place("museum", tier: .notable, north: 500), place("landmark", tier: .mustSee, north: 700, east: -150)])
        for second in 0...4 {
            e.ingest(fix(north: Double(second) * 30 - 120, at: t0.addingTimeInterval(Double(second)), speed: 30, course: 0))
        }
        #expect(e.motion == .highway)
        let decision = e.decide(at: t0.addingTimeInterval(4))
        #expect(decision?.place.id == "landmark")
        #expect(decision?.side == "left")
    }

    @Test func fetchesOncePerAreaNotPerFix() throws {
        var e = GuideEngine()
        e.ingest(fix(at: t0, speed: 1.4))
        #expect(e.needsFetch(at: t0))
        let plan = try #require(e.fetchPlan())
        #expect(plan.radius_meters == 500)
        e.markFetchAttempt(at: t0)
        e.update(candidates: [], for: plan, at: t0)
        e.ingest(fix(north: 100, at: t0.addingTimeInterval(70), speed: 1.4))
        #expect(!e.needsFetch(at: t0.addingTimeInterval(70)))
        e.ingest(fix(north: 300, at: t0.addingTimeInterval(220), speed: 1.4))
        #expect(e.needsFetch(at: t0.addingTimeInterval(220)))
    }

    @Test func whatsThisReturnsNearestThreeWithSides() {
        var e = engine([
            place("left church", tier: .minor, north: 20, east: -15),
            place("fountain", tier: .notable, north: 25, east: 15),
            place("palazzo", tier: .minor, north: 40),
            place("far museum", tier: .mustSee, north: 400),
        ])
        e.ingest(fix(at: t0))
        let results = e.whatsThis(heading: 0)
        #expect(results.count == 3)
        #expect(!results.contains { $0.candidate.id == "far museum" })
        #expect(results.first { $0.candidate.id == "left church" }?.side == "left")
        #expect(results.first { $0.candidate.id == "fountain" }?.side == "right")
    }

    @Test func startingInsideTheZooTalksAboutTheZooRightAway() throws {
        var e = engine([place("zoo", tier: .notable, north: 50, radius: 250), place("cafe", tier: .notable, north: 20)])
        e.ingest(fix(at: t0, speed: 1.2))
        let opening = try #require(e.opening())
        #expect(opening.place.id == "zoo")
        #expect(opening.situation == .enteredArea)
        // Outside any area, the best notable place within 250 m is used, stop or no stop.
        var street = engine([place("museum", tier: .notable, north: 180), place("plaque", tier: .minor, north: 5)])
        street.ingest(fix(at: t0, speed: 1.4))
        #expect(street.opening()?.place.id == "museum")
        #expect(engine([place("far", tier: .notable, north: 900)]).opening() == nil)
    }

    @Test func insideTheZooExhibitsAreMentionedAsPartOfIt() throws {
        // Zoo centred 100 m north, 250 m across; an elephant exhibit Google ranks as "minor".
        var e = engine([place("San Diego Zoo", tier: .mustSee, north: 100, radius: 250),
                        place("Elephant Odyssey", tier: .minor, north: 20, match: 0),
                        place("Shop outside", tier: .minor, north: -400)])
        var now = stand(&e, from: t0, seconds: 21)
        let entryResult = e.decide(at: now)
        let entry = try #require(entryResult)
        #expect(entry.place.id == "San Diego Zoo")
        e.markMentioned(entry, at: now)
        // Stay at the exhibit past the in-venue budget (2 minutes on Normal).
        now = stand(&e, north: 15, from: now.addingTimeInterval(e.venueBudget), seconds: 21)
        let exhibitResult = e.decide(at: now)
        let exhibit = try #require(exhibitResult)
        #expect(exhibit.place.id == "Elephant Odyssey")
        #expect(exhibit.within == "San Diego Zoo")
        #expect(exhibit.request(language: "en").within == "San Diego Zoo")
        // Outside a venue, the same minor place stays quiet.
        #expect(!engine([place("Shop outside", tier: .minor)]).eligible(place("Shop outside", tier: .minor)))
    }

    @Test func walkingRoutesDecodeGooglePolylinesAndVoiceEvents() throws {
        let path = GuideRoute.decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@")
        #expect(path.count == 3)
        #expect(abs(path[0].latitude - 38.5) < 1e-6 && abs(path[0].longitude + 120.2) < 1e-6)
        #expect(abs(path[2].latitude - 43.252) < 1e-6 && abs(path[2].longitude + 126.453) < 1e-6)
        let route = try #require(GuideRoute(event: [
            "destination": ["name": "Africa Rocks Penguin Beach", "latitude": 32.738, "longitude": -117.1525],
            "walking_minutes": 9, "distance_meters": 640, "polyline": "_p~iF~ps|U",
        ]))
        #expect(route.minutes == 9 && route.meters == 640 && route.path.count == 1)
        #expect(GuideRoute(event: ["destination": ["name": "x", "latitude": 200.0, "longitude": 0.0]]) == nil)
    }

    #if !SWIFT_PACKAGE
    @Test func guideEndpointsArePostOnly() throws {
        #expect(throws: APIClientError.self) { try APIRequest<GuideNearbyResponse>.get(.guideNearby) }
        let body = GuideNearbyRequest(latitude: 32.7, longitude: -117.1, radius_meters: 500, language: "en")
        let request = try APIRequest<GuideNearbyResponse>.post(.guideNearby, body: body)
        #expect(request.endpoint.path == "/v1/guide/nearby" && request.method == "POST")
        #expect(APIEndpoint.guideMention.path == "/v1/guide/mention" && APIEndpoint.guideMention.canPost)
    }

    #endif

    @Test func mentionRequestCarriesNoRatings() throws {
        var candidate = place("p", tier: .mustSee)
        candidate.rating = 4.9; candidate.user_rating_count = 10_000; candidate.categories = ["history", "unknown"]
        let decision = GuideDecision(place: candidate, highlights: [], situation: .stoppedNearby, side: "left", distance: 12.4, motion: .walking, breaksBudget: true)
        let json = String(decoding: try JSONEncoder().encode(decision.request(language: "en")), as: UTF8.self)
        #expect(!json.contains("rating"))
        #expect(!json.contains("unknown"))
        #expect(json.contains("\"situation\":\"stopped_nearby\""))
    }
}

/// The October 2026 test drive, replayed: Carmel Valley → Del Mar Highlands → One Paseo →
/// I-5 North → Del Mar Fairgrounds → Solana Beach → Carlsbad. Positions are approximate real
/// coordinates; places mirror what the backend returned for this route (tier, appeal, town).
struct LiveGuideDriveReplayTests {
    struct Mentioned { var decision: GuideDecision; var at: Date; var along: Double }

    static func spot(_ id: String, _ lat: Double, _ lon: Double, _ tier: GuideTier, appeal: Double,
                     _ categories: [String], town: String?, match: Double = 0.5) -> GuideCandidate {
        GuideCandidate(id: id, name: id, latitude: lat, longitude: lon, categories: categories,
                       prominence: appeal, tier: tier, profile_match: match, appeal: appeal, locality: town)
    }

    static let places: [GuideCandidate] = [
        spot("Del Mar Highlands Town Center", 32.9506, -117.2337, .notable, appeal: 0.59, ["shopping"], town: "San Diego"),
        spot("One Paseo", 32.9555, -117.2383, .notable, appeal: 0.48, ["shopping"], town: "San Diego"),
        spot("Torrey Pines High School", 32.9585, -117.2405, .minor, appeal: 0.26, ["history"], town: nil),
        spot("Torrey Pines State Beach", 32.9330, -117.2600, .notable, appeal: 0.60, ["scenic", "nature"], town: "San Diego"),
        spot("Del Mar Fairgrounds", 32.9750, -117.2600, .notable, appeal: 0.72, ["entertainment"], town: "Del Mar"),
        spot("Fletcher Cove Beach Park", 32.9910, -117.2730, .notable, appeal: 0.60, ["scenic"], town: "Solana Beach"),
        spot("Cedros Avenue Design District", 32.9930, -117.2700, .notable, appeal: 0.62, ["art", "shopping"], town: "Solana Beach"),
        spot("San Diego Botanic Garden", 33.0530, -117.2810, .notable, appeal: 0.62, ["nature"], town: "Encinitas"),
        spot("Moonlight State Beach", 33.0480, -117.2980, .notable, appeal: 0.66, ["scenic"], town: "Encinitas"),
        spot("LEGOLAND California Resort", 33.1260, -117.3110, .mustSee, appeal: 0.98, ["family"], town: "Carlsbad"),
        spot("Carlsbad Premium Outlets", 33.1270, -117.3200, .notable, appeal: 0.68, ["shopping"], town: "Carlsbad"),
        spot("In-N-Out Burger", 33.1300, -117.3235, .notable, appeal: 0.61, ["food"], town: "Carlsbad"),
        spot("Costco Wholesale", 33.1275, -117.3010, .notable, appeal: 0.33, ["practical"], town: "Carlsbad"),
    ]

    /// Driving route: (latitude, longitude, metres per second) waypoints.
    static let northbound: [(Double, Double, Double)] = [
        (32.9330, -117.2330, 13), (32.9540, -117.2333, 13),   // El Camino Real north, past Del Mar Highlands
        (32.9556, -117.2440, 13),                              // Del Mar Heights Rd west, past One Paseo
        (32.9790, -117.2540, 29), (32.9960, -117.2600, 29),   // I-5 North past the Fairgrounds, Solana Beach
        (33.0450, -117.2860, 29), (33.0950, -117.3050, 29),   // Encinitas, Carlsbad
        (33.1370, -117.3290, 29),
    ]

    static func town(at latitude: Double) -> String {
        switch latitude {
        case ..<32.9580: "San Diego"
        case ..<32.9850: "Del Mar"
        case ..<33.0040: "Solana Beach"
        case ..<33.0900: "Encinitas"
        default: "Carlsbad"
        }
    }

    /// One fix per second along the route; the backend is simulated from `places`; Pip is asked
    /// every 5 s (like the phone's ticker) and each mention is treated as delivered at once.
    static func drive(_ route: [(Double, Double, Double)], chattiness: GuideChattiness = .normal,
                      sunsetIn minutes: Double? = nil, places: [GuideCandidate] = places) -> (mentions: [Mentioned], engine: GuideEngine) {
        var engine = GuideEngine(chattiness: chattiness)
        engine.selectTourMode(.driving)
        var now = Date(timeIntervalSince1970: 1_000_000)
        let sunset = minutes.map { now.addingTimeInterval($0 * 60) }
        var mentions: [Mentioned] = []
        var travelled = 0.0
        for (from, to) in zip(route, route.dropFirst()) {
            let length = GuideGeo.distance(from.0, from.1, to.0, to.1)
            let course = GuideGeo.bearing(from.0, from.1, to.0, to.1)
            var covered = 0.0
            while covered < length {
                let position = GuideGeo.offset(from.0, from.1, meters: covered, bearing: course)
                engine.ingest(GuideFix(latitude: position.0, longitude: position.1, accuracy: 8, speed: to.2, course: course, timestamp: now))
                if engine.needsFetch(at: now), let plan = engine.fetchPlan() {
                    engine.markFetchAttempt(at: now)
                    let found = places.filter { GuideGeo.distance(plan.latitude, plan.longitude, $0.latitude, $0.longitude) <= Double(plan.radius_meters) }
                    engine.update(candidates: found, for: plan, at: now, sunset: sunset)
                }
                let second = Int(now.timeIntervalSince1970)
                if second % 30 == 0 { engine.observeArea(town(at: position.0), at: now) }
                if second % 5 == 0, let decision = engine.decide(at: now) {
                    engine.markMentioned(decision, at: now)
                    let g = GuideEngine.geometry(of: decision.place, from: engine.latest!, course: course)
                    mentions.append(Mentioned(decision: decision, at: now, along: g.along))
                }
                covered += to.2
                travelled += to.2
                now = now.addingTimeInterval(1)
            }
        }
        return (mentions, engine)
    }

    static func names(_ mentions: [Mentioned]) -> [String] {
        mentions.flatMap { [$0.decision.place.name] + $0.decision.highlights.map(\.name) }
    }

    @Test func pipIntroducesTheDrivesHighlightsBeforeReachingThem() throws {
        let (mentions, _) = Self.drive(Self.northbound)
        let said = Self.names(mentions)
        for expected in ["Del Mar Highlands Town Center", "One Paseo", "Del Mar Fairgrounds", "LEGOLAND California Resort",
                         "Carlsbad Premium Outlets"] {
            #expect(said.contains(expected), "Pip never mentioned \(expected); said \(said)")
        }
        // Every place is introduced before the car passes it, never after.
        for mention in mentions where !mention.decision.place.id.hasPrefix("locality:") {
            #expect(mention.along > 0, "\(mention.decision.place.name) was mentioned after passing it")
        }
        // LEGOLAND comes with Carlsbad: "Carlsbad is coming up! LEGOLAND, the outlets…".
        let carlsbad = try #require(mentions.first { $0.decision.place.name == "Carlsbad" })
        #expect(carlsbad.decision.situation == .approachingCity)
        #expect(carlsbad.decision.highlights.first?.name == "LEGOLAND California Resort")
        // One Paseo is introduced together with Del Mar Highlands, before reaching either.
        let highlands = try #require(mentions.first { $0.decision.place.name == "Del Mar Highlands Town Center" })
        #expect(highlands.decision.situation == .upcoming)
        #expect(highlands.decision.highlights.map(\.name) == ["One Paseo"])
    }

    @Test func schoolsAndPracticalStopsStayQuietWithoutAnInterest() {
        let said = Self.names(Self.drive(Self.northbound).mentions)
        #expect(!said.contains("Torrey Pines High School"))
        #expect(!said.contains("Costco Wholesale"))
        // Someone who said they love road-trip stops hears about Costco.
        let shopper = Self.places.map { place in
            var copy = place
            if place.name == "Costco Wholesale" { copy.profile_match = 1 }
            return copy
        }
        let (mentions, _) = Self.drive(Self.northbound, chattiness: .tourGuide, places: shopper)
        #expect(Self.names(mentions).contains("Costco Wholesale"))
    }

    @Test func townsAreWelcomedOnceWithTheirHighlights() throws {
        let (mentions, _) = Self.drive(Self.northbound)
        let towns = mentions.filter { $0.decision.place.id.hasPrefix("locality:") }
        let townNames = towns.map(\.decision.place.name)
        // No welcome to the town the tour started in, and no town twice.
        #expect(!townNames.contains("San Diego"))
        #expect(Set(townNames).count == townNames.count)
        #expect(townNames.contains("Carlsbad"))
        let carlsbad = try #require(towns.first { $0.decision.place.name == "Carlsbad" })
        // Announced ahead of time from the places waiting there, with them as highlights.
        #expect(carlsbad.decision.situation == .approachingCity)
        #expect(carlsbad.decision.highlights.map(\.name).contains("LEGOLAND California Resort"))
        #expect(!carlsbad.decision.highlights.map(\.name).contains("Costco Wholesale"))
        // Del Mar comes before Solana Beach, which comes before Encinitas.
        let order = townNames.filter { ["Del Mar", "Solana Beach", "Encinitas"].contains($0) }
        #expect(order == ["Del Mar", "Solana Beach", "Encinitas"])
    }

    @Test func gpsDriftAcrossATownLineIsNotAnnouncedAgain() {
        var engine = GuideEngine()
        let t = Date(timeIntervalSince1970: 0)
        engine.observeArea("San Diego", at: t)
        engine.observeArea("Del Mar", at: t.addingTimeInterval(30))
        #expect(engine.areaEvent == nil) // one lookup is not enough
        engine.observeArea("Del Mar", at: t.addingTimeInterval(60))
        #expect(engine.areaEvent?.name == "Del Mar" && engine.areaEvent?.situation == .enteringCity)
        engine.observeArea("San Diego", at: t.addingTimeInterval(90))
        engine.observeArea("San Diego", at: t.addingTimeInterval(120))
        engine.observeArea("Del Mar", at: t.addingTimeInterval(150))
        engine.observeArea("Del Mar", at: t.addingTimeInterval(180))
        // Back and forth across the line: San Diego was already known and Del Mar already welcomed.
        #expect(engine.areaEvent?.at == t.addingTimeInterval(60))
        #expect(GuideEngine.key("Solana Beach") == GuideEngine.key("solana beach"))
    }

    @Test func pipDoesNotTalkConstantly() {
        let (mentions, _) = Self.drive(Self.northbound, chattiness: .normal)
        for (earlier, later) in zip(mentions, mentions.dropFirst()) {
            #expect(later.at.timeIntervalSince(earlier.at) >= GuideEngine.minimumGap)
        }
        // About 25 km in roughly 17 minutes: a handful of moments, not a running commentary.
        #expect((4...12).contains(mentions.count), "Pip spoke \(mentions.count) times")
    }

    @Test func sidesFollowTheDirectionOfTravel() throws {
        // The Del Mar Fairgrounds are west of I-5: left going north, right going south.
        var fairgrounds = try #require(Self.places.first { $0.name == "Del Mar Fairgrounds" })
        fairgrounds.locality = nil
        let interstate = [(32.9200, -117.2330, 29.0), (32.9440, -117.2400, 29.0), (32.9790, -117.2540, 29.0),
                          (32.9960, -117.2600, 29.0), (33.0200, -117.2780, 29.0)]
        func first(_ route: [(Double, Double, Double)], _ place: GuideCandidate) -> GuideDecision? {
            Self.drive(route, places: [place]).mentions.first { $0.decision.place.id == place.id }?.decision
        }
        #expect(try #require(first(interstate, fairgrounds)).side == "left")
        #expect(try #require(first(interstate.reversed(), fairgrounds)).side == "right")
        // LEGOLAND is east of I-5: right going north, left going south.
        var legoland = try #require(Self.places.first { $0.name == "LEGOLAND California Resort" })
        legoland.locality = nil
        let route = [(33.1080, -117.3100, 13.0), (33.1450, -117.3330, 13.0)]
        #expect(try #require(first(route, legoland)).side == "right")
        #expect(try #require(first(route.reversed(), legoland)).side == "left")
    }

    @Test func decodesTheBackendsAheadResponse() throws {
        let json = """
        {"status":"ok","scope":"ahead","interests":[],"sources":["google","wikipedia"],"candidates":[{"id":"g-lego","name":"LEGOLAND California Resort",
        "latitude":33.126,"longitude":-117.311,"radius_meters":0,"categories":["family"],"prominence":0.98,
        "tier":"must_see","profile_match":0.5,"appeal":0.98,"primary_type":"amusement_park","open_now":true,
        "locality":"Carlsbad","sources":["google"]}],
        "sun":{"sunrise":"2026-10-16T13:52:52+00:00","sunset":"2026-10-16T01:17:10+00:00"},
        "diagnostics":{"scope":"ahead","radius_meters":7000,"groups":{"food":{"types":7,"error":400},
        "scenic":{"types":6,"error":"unavailable"},"attractions":{"types":19,"returned":20}},
        "candidates":1,"dropped":[{"name":"The Flower Fields","reason":"google: closed_temporarily"}]}}
        """
        let response = try JSONDecoder().decode(GuideNearbyResponse.self, from: Data(json.utf8))
        let lego = try #require(response.candidates.first)
        #expect(lego.visitorAppeal == 0.98 && lego.locality == "Carlsbad" && lego.open_now == true)
        #expect(response.sun?.sunsetDate == Date(timeIntervalSince1970: 1_792_113_430))
        #expect(response.diagnostics?.groups?["food"]?.error == "400")
        #expect(response.diagnostics?.groups?["scenic"]?.error == "unavailable")
        #expect(response.diagnostics?.dropped?.first?.reason == "google: closed_temporarily")
        let place = GuideMentionPlace(lego, distance: 900, side: "right")
        #expect(place.primary_type == "amusement_park" && place.locality == "Carlsbad")
    }

    @Test func aSunsetBeachWinsShortlyBeforeSunset() throws {
        let route = [(32.9790, -117.2540, 29.0), (33.0450, -117.2860, 29.0)]
        let beach = Self.spot("Sunset beach", 33.0080, -117.2820, .notable, appeal: 0.55, ["scenic"], town: "Solana Beach")
        let mall = Self.spot("Big mall", 33.0080, -117.2600, .notable, appeal: 0.65, ["shopping"], town: "Solana Beach")
        let evening = try #require(Self.drive(route, sunsetIn: 30, places: [beach, mall]).mentions.first)
        #expect(evening.decision.place.name == "Sunset beach")
        let night = try #require(Self.drive(route, sunsetIn: -60, places: [beach, mall]).mentions.first)
        #expect(night.decision.place.name == "Big mall")
    }
}

struct ExperienceCorridorTests {
    let now = Date(timeIntervalSince1970: 1000)

    @Test func routeFollowsBendInEveryHemisphere() throws {
        // Synthetic bends at worldwide origins: geometry tests, not live discovery acceptance.
        for (lat, lon) in [(35.68, 139.76), (48.85, 2.35), (41.01, 28.97), (43.65, -79.38),
                           (32.95, -117.24), (35.69, 51.39), (25.20, 55.27), (-44.0, 170.5)] {
            let a = GuideRoute.Point(latitude: lat, longitude: lon)
            let n = GuideGeo.offset(lat, lon, meters: 1000, bearing: 0)
            let e = GuideGeo.offset(n.0, n.1, meters: 3000, bearing: 90)
            let path = [a, .init(latitude: n.0, longitude: n.1), .init(latitude: e.0, longitude: e.1)]
            let projection = try #require(GuideCorridor.project(latitude: lat, longitude: lon, path: path))
            let ahead = GuideCorridor.ahead(2500, from: projection, path: path)
            let result = try #require(GuideCorridor.project(latitude: ahead.latitude, longitude: ahead.longitude, path: path))
            #expect(abs(result.along - 2500) < 5)
            #expect(result.across < 5)
            #expect(result.segment == 1)
        }
    }

    @Test func walkingRouteCannotDriveTheDiscovery() throws {
        var e = GuideEngine()
        e.selectTourMode(.driving)
        e.ingest(fix(at: now, speed: 15, course: 0))
        let end = point(east: 5000)
        let route = GuideRoute(name: "Walk", destination: .init(latitude: end.0, longitude: end.1), minutes: 30, meters: 5000,
                               path: [.init(latitude: origin.latitude, longitude: origin.longitude), .init(latitude: end.0, longitude: end.1)])
        e.setRoute(route)
        let plan = try #require(e.fetchPlan())
        #expect(plan.latitude > origin.latitude)
        #expect(abs(plan.longitude - origin.longitude) < 0.001)
    }

    @Test func turningRefreshesWithoutWaitingFiveKilometers() throws {
        var e = GuideEngine()
        e.selectTourMode(.driving)
        e.ingest(fix(at: now, speed: 27, course: 0))
        let plan = try #require(e.fetchPlan())
        e.update(candidates: [], for: plan, at: now)
        e.markFetchAttempt(at: now)
        e.ingest(fix(north: 250, at: now.addingTimeInterval(60), speed: 27, course: 90))
        #expect(e.needsFetch(at: now.addingTimeInterval(60)))
    }

    @Test func scoringExplainsVarietyAndClosedPlaces() {
        let weights = GuideExperienceWeights()
        var p = place("gallery", tier: .notable, match: 1)
        let baseline = weights.factors(p, timely: false, across: 0, limit: 1000, repeatedCategory: false).reduce(0) { $0 + $1.1 }
        p.open_now = false
        let factors = weights.factors(p, timely: false, across: 0, limit: 1000, repeatedCategory: true)
        #expect(factors.reduce(0) { $0 + $1.1 } < baseline)
        #expect(factors.contains { $0.0 == "variety" && $0.1 < 0 })
        #expect(factors.contains { $0.0 == "closed" && $0.1 < 0 })
    }

    @Test func malformedPolylineIsBounded() {
        #expect(GuideRoute.decode(String(repeating: "~", count: 500)).isEmpty)
        #expect(GuideRoute.decode("\n\n").isEmpty)
    }
}

struct WorldwideExperienceReplayTests {
    @Test func predictiveMentionsAcrossWorldwideOrigins() throws {
        // Generated geographic fixtures test the same engine everywhere. They do not assert
        // that Google returned these places or that the synthetic line is a drivable road.
        for (lat, lon) in [(35.68, 139.76), (48.85, 2.35), (41.01, 28.97), (43.65, -79.38), (46.80, -71.21)] {
            for speed in [12.0, 27.0, 40.0] {
                for navigation in [false, true] {
                    var e = GuideEngine()
                    e.selectTourMode(.driving)
                    let target = GuideGeo.offset(lat, lon, meters: speed * 180, bearing: 0)
                    let end = GuideGeo.offset(lat, lon, meters: speed * 600, bearing: 0)
                    if navigation {
                        var route = GuideRoute(name: "Synthetic replay", destination: .init(latitude: end.0, longitude: end.1),
                                               minutes: 10, meters: Int(speed * 600),
                                               path: [.init(latitude: lat, longitude: lon), .init(latitude: end.0, longitude: end.1)])
                        route.mode = .driving
                        e.setRoute(route)
                    }
                    let candidate = GuideCandidate(id: "gallery", name: "Gallery", latitude: target.0, longitude: target.1,
                                                   categories: ["art"], prominence: 0.8, tier: .notable, profile_match: 1, appeal: 0.7)
                    var mentions: [GuideDecision] = []
                    for second in stride(from: 0, through: 300, by: 5) {
                        let now = Date(timeIntervalSince1970: 1000 + Double(second))
                        let location = GuideGeo.offset(lat, lon, meters: speed * Double(second), bearing: 0)
                        e.ingest(.init(latitude: location.0, longitude: location.1, accuracy: 8, speed: speed, course: 0, timestamp: now))
                        if e.needsFetch(at: now), let request = e.fetchPlan() {
                            e.markFetchAttempt(at: now)
                            e.update(candidates: [candidate], for: request, at: now)
                        }
                        if let decision = e.decide(at: now) {
                            mentions.append(decision)
                            e.markMentioned(decision, at: now)
                        }
                    }
                    let decision = try #require(mentions.first)
                    #expect(mentions.count == 1)
                    #expect(decision.situation == .upcoming)
                    #expect(decision.minutesAhead == 3)
                    #expect(decision.inView == false)
                }
            }
        }
    }
}

struct ActiveRouteDiscoveryTests {
    @Test func curvedRouteChangesSearchAndNarration() throws {
        var e = GuideEngine()
        e.selectTourMode(.driving)
        let now = Date(timeIntervalSince1970: 1000)
        e.ingest(fix(at: now, speed: 12, course: 0))
        let bend = point(north: 1000)
        let end = GuideGeo.offset(bend.0, bend.1, meters: 5000, bearing: 90)
        var route = GuideRoute(name: "Synthetic bend", destination: .init(latitude: end.0, longitude: end.1), minutes: 10, meters: 6000,
                               path: [.init(latitude: origin.latitude, longitude: origin.longitude),
                                      .init(latitude: bend.0, longitude: bend.1), .init(latitude: end.0, longitude: end.1)])
        route.mode = .driving
        e.setRoute(route)
        let plan = try #require(e.fetchPlan())
        #expect(plan.longitude > origin.longitude + 0.005)
        let target = GuideGeo.offset(bend.0, bend.1, meters: 2500, bearing: 90)
        let candidate = GuideCandidate(id: "around-bend", name: "Around bend", latitude: target.0, longitude: target.1,
                                       categories: ["art"], prominence: 0.8, tier: .notable, profile_match: 1, appeal: 0.7)
        e.update(candidates: [candidate], for: plan, at: now)
        let result = e.decide(at: now)
        let decision = try #require(result)
        #expect(decision.place.id == "around-bend")
        #expect(decision.situation == .upcoming)
        #expect((decision.offRoute ?? 9999) < 5)
        #expect(e.lastTrace.first?.reason.contains("appeal=") == true)
        // Removing navigation returns to conservative straight-ahead prediction.
        e.setRoute(nil)
        #expect(e.decide(at: now) == nil)
    }
}

struct PlannedTourTests {
    private func plan(mode: String = "walking", offline: Bool = false) throws -> GuideTourPlan {
        let raw: [String: Any] = [
            "id": "test-tour", "created_at": "2026-10-15T19:00:00Z", "offline": offline,
            "mode": mode, "duration_minutes": 30, "round_trip": false,
            "origin": ["latitude": 48.85, "longitude": 2.35],
            "destination": ["latitude": 48.86, "longitude": 2.35],
            "estimated_seconds": 1200, "travel_seconds": 600, "stop_seconds": 300, "buffer_seconds": 300,
            "distance_meters": 1000, "polyline": offline ? "" : "_p~iF~ps|U_ulLnnqC_mqNvxq`@",
            "stops": [["place": ["id": "gallery", "name": "Gallery", "latitude": 48.86, "longitude": 2.35,
                                  "categories": ["art"], "tier": "notable", "prominence": 0.8, "radius_meters": 0, "profile_match": 1],
                        "stop_seconds": 300, "reason": "interest_match"]]
        ]
        return try JSONDecoder().decode(GuideTourPlan.self, from: JSONSerialization.data(withJSONObject: raw))
    }

    @Test func preservesTransportChoicesAndReadsLegacyRequests() throws {
        var request = GuideTourRequest(origin: .init(latitude: 48.85, longitude: 2.35,
                                                     captured_at: "2026-10-16T19:00:00Z"),
                                       mode: "walking", duration_minutes: 30, direction: "surprise",
                                       round_trip: false, language: "en")
        request.transport_modes = ["walking", "rideshare", "transit"]
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(GuideTourRequest.self, from: data)
        #expect(decoded.transport_modes == request.transport_modes)
        var legacy = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        legacy.removeValue(forKey: "transport_modes")
        let old = try JSONDecoder().decode(GuideTourRequest.self, from: JSONSerialization.data(withJSONObject: legacy))
        #expect(old.transport_modes == nil)
        #expect(old.mode == "walking")
        for mode in ["rideshare", "transit"] {
            let passenger = try plan(mode: mode)
            #expect(passenger.isUsable)
            let components = URLComponents(url: passenger.googleMapsURL!, resolvingAgainstBaseURL: false)
            #expect(components?.queryItems?.first(where: { $0.name == "travelmode" })?.value == (mode == "transit" ? "transit" : "driving"))
        }
    }

    @Test func validatesBudgetsAndKeepsOfflineDistinct() throws {
        let online = try plan()
        #expect(online.isUsable)
        #expect(online.route.mode == .walking)
        let offline = try plan(offline: true)
        #expect(offline.isUsable)
        #expect(offline.route.path.isEmpty)
        var invalid = online
        invalid.estimated_seconds = 1801
        #expect(!invalid.isUsable)
        invalid = online; invalid.polyline = ""
        #expect(!invalid.isUsable)
        let drive = try plan(mode: "driving")
        #expect(drive.route.mode == .driving)
    }

    @Test func arrivalAndDepartureDriveProgressForWalkingDrivingAndOffline() throws {
        for mode in ["walking", "driving"] {
            for offline in [false, true] {
                let p = try plan(mode: mode, offline: offline)
                let start = Date(timeIntervalSince1970: 1000)
                var progress = GuideTourProgress(plan: p, started: start)
                #expect(progress.next?.id == "gallery")
                var fix = GuideFix(latitude: 48.86, longitude: 2.35, accuracy: 8, speed: 0, course: 0, timestamp: start)
                progress.update(fix, at: start)
                #expect(progress.arrived)
                #expect(progress.next?.id == "gallery") // A narration alone cannot advance the tour.
                fix.latitude = 48.862; fix.timestamp = start.addingTimeInterval(30)
                progress.update(fix, at: fix.timestamp)
                #expect(progress.next == nil)
            }
        }
    }

    @Test func mixedProgressWalksOutAndReturnsBeforeNextDrive() throws {
        var p = try plan(mode: "mixed")
        let target = GuideCandidate(id: "garden", name: "Garden", latitude: 48.861, longitude: 2.35, categories: ["nature"], prominence: 0.8, tier: .notable)
        p.walking_segments = [.init(stop_seconds: 60, anchor_id: "gallery", place: target, polyline: p.polyline, seconds: 180, distance_meters: 400)]
        let start = Date(timeIntervalSince1970: 1000)
        var progress = GuideTourProgress(plan: p, started: start)
        var fix = GuideFix(latitude: 48.86, longitude: 2.35, accuracy: 8, speed: 0, course: 0, timestamp: start)
        progress.update(fix, at: start)
        progress.update(fix, at: start.addingTimeInterval(300))
        #expect(progress.currentMode == .walking)
        #expect(progress.next?.id == "garden")
        fix.latitude = target.latitude
        progress.update(fix, at: start.addingTimeInterval(360))
        progress.update(fix, at: start.addingTimeInterval(420))
        #expect(progress.next?.id == "gallery")
        fix.latitude = 48.86
        progress.update(fix, at: start.addingTimeInterval(480))
        #expect(progress.next == nil)
    }

    @Test func expiresAtTheTravelersTimeBudget() throws {
        let p = try plan()
        let start = Date(timeIntervalSince1970: 1000)
        var progress = GuideTourProgress(plan: p, started: start)
        let fix = GuideFix(latitude: 48.85, longitude: 2.35, accuracy: 8, speed: 1, course: 0, timestamp: start.addingTimeInterval(1800))
        progress.update(fix, at: fix.timestamp)
        #expect(progress.expired)
    }
}

struct OfflineVoicePackageTests {
    private func package() -> GuideOfflinePackage {
        // SHA256 of "abc": deterministic integrity fixture, not playable audio.
        let audio = GuideOfflinePackage.Audio(data: "YWJj", sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", bytes: 3, voice: "coral", model: "gpt-4o-mini-tts")
        var clips: [GuideOfflinePackage.Clip] = []
        for (id, kind) in [("intro", "introduction"), ("complete", "completion"), ("stop_0", "stop"), ("deep_0", "deeper"), ("transition_0", "transition"), ("qa_0_0", "answer"), ("qa_0_1", "answer")] {
            clips.append(.init(id: id, kind: kind, stop_index: id == "intro" || id == "complete" ? nil : 0, title: "Title", text: "Grounded story", question: kind == "answer" ? "When did it open?" : nil, fact_ids: [0]))
        }
        return .init(version: 2, script_model: "gpt-6-luna", tts_model: "gpt-4o-mini-tts", voice: "coral", personality: "warm", clips: clips,
                     audio: Dictionary(uniqueKeysWithValues: clips.map { ($0.id, audio) }), voice_disclosure: "AI-generated")
    }
    @Test func requiresEveryAudioAssetAndMatchingHashesVoiceAndModel() {
        let complete = package()
        #expect(complete.verified(stopCount: 1))
        var missing = complete; missing.audio.removeValue(forKey: "deep_0")
        #expect(!missing.verified(stopCount: 1))
        var corrupt = complete; corrupt.audio["stop_0"]?.data = "YWJk"
        #expect(!corrupt.verified(stopCount: 1))
        var wrongVoice = complete; wrongVoice.audio["intro"]?.voice = "alloy"
        #expect(!wrongVoice.verified(stopCount: 1))
        var wrongModel = complete; wrongModel.audio["intro"]?.model = "device"
        #expect(!wrongModel.verified(stopCount: 1))
        var old = complete; old.version = 1
        #expect(!old.verified(stopCount: 1))
    }
    @Test func missingScriptsAndWrongFactReferencesFailClosed() {
        var p = package(); p.clips.removeAll { $0.kind == "completion" }; p.audio.removeValue(forKey: "complete")
        #expect(!p.verified(stopCount: 1))
        p = package(); p.clips[2].fact_ids = [8]
        #expect(!p.verified(stopCount: 1))
    }
    @Test func questionsUseOnlyDownloadedAnswersWithoutInventingMatches() {
        let p = package()
        #expect(p.answer(for: "WHEN did it open?!")?.kind == "answer")
        #expect(p.answer(for: "Is it open now?") == nil)
        #expect(p.answer(for: "") == nil)
    }
    @Test func durableRoundTripKeepsScriptsAndAudioIntact() throws {
        let p = package()
        let data = try JSONEncoder().encode(p)
        let reopened = try JSONDecoder().decode(GuideOfflinePackage.self, from: data)
        #expect(reopened == p)
        #expect(reopened.verified(stopCount: 1))
        #expect(reopened.byteCount == 21)
    }
}

#if canImport(UIKit)
import AVFoundation
import CoreLocation

private actor OfflineTestTokens: AccessTokenProviding {
    var calls = 0
    func validAccessToken(forceRefresh: Bool) async throws -> String { calls += 1; throw URLError(.notConnectedToInternet) }
}

struct DownloadedTourPlaybackTests {
    @MainActor @Test func downloadedAudioQuestionsAndControlsNeverRequestAuthenticationOrNetwork() async throws {
        let audio = GuideOfflinePackage.Audio(data: "UklGRkQDAABXQVZFZm10IBAAAAABAAEAQB8AAIA+AAACABAAZGF0YSADAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==", sha256: "26131825c935435301fb05d3549d815bc93b1e717d6228d890ee9578dd00025e", bytes: 844, voice: "coral", model: "gpt-4o-mini-tts")
        var clips: [GuideOfflinePackage.Clip] = []
        for (id, kind) in [("intro", "introduction"), ("complete", "completion"), ("stop_0", "stop"), ("deep_0", "deeper"), ("transition_0", "transition"), ("qa_0_0", "answer"), ("qa_0_1", "answer")] {
            clips.append(.init(id: id, kind: kind, stop_index: id == "intro" || id == "complete" ? nil : 0, title: "A downloaded story", text: "Downloaded facts", question: kind == "answer" ? "What is this?" : nil, fact_ids: [0]))
        }
        let package = GuideOfflinePackage(version: 2, script_model: "gpt-6-luna", tts_model: "gpt-4o-mini-tts", voice: "coral", personality: "warm", clips: clips, audio: Dictionary(uniqueKeysWithValues: clips.map { ($0.id, audio) }), voice_disclosure: "AI-generated")
        let raw: [String: Any] = ["id": "offline-playback-test", "created_at": "2026-10-15T19:00:00Z", "offline": true, "language": "en", "mode": "walking", "duration_minutes": 120, "round_trip": false,
            "origin": ["latitude": 43.64, "longitude": -79.38], "destination": ["latitude": 43.64, "longitude": -79.38],
            "estimated_seconds": 7200, "travel_seconds": 0, "stop_seconds": 300, "buffer_seconds": 0, "distance_meters": 0, "polyline": "",
            "stops": [["place": ["id": "wiki:1", "name": "Public landmark", "latitude": 43.64, "longitude": -79.38, "radius_meters": 0, "profile_match": 0.5, "categories": ["landmark"], "prominence": 1, "tier": "must_see"], "stop_seconds": 300, "reason": "offline_story"]]]
        var plan = try JSONDecoder().decode(GuideTourPlan.self, from: JSONSerialization.data(withJSONObject: raw))
        plan.offline_package = package
        let tokens = OfflineTestTokens()
        let client = APIClient(baseURL: URL(string: "https://offline-test.invalid")!)
        let voice = LiveVoiceStore(client: client, authentication: tokens)
        let translator = LiveVoiceStore(client: client, authentication: tokens)
        let guide = LiveGuideStore(client: client, authentication: tokens, voice: voice, translator: translator)
        guide.beginTour(plan)
        #expect(guide.activeTour?.plan.id == plan.id)
        guide.playOfflineStory("stop_0")
        #expect(guide.lastVoiceWasPip == true)
        #expect(guide.lastMention?.text == "Downloaded facts")
        guide.pauseOffline(); #expect(guide.offlinePaused)
        guide.resumeOffline(); #expect(!guide.offlinePaused)
        guide.repeatOffline(); guide.pauseOffline()
        let reopened = LiveGuideStore(client: client, authentication: tokens, voice: voice, translator: translator)
        reopened.beginTour(plan)
        #expect(reopened.offlineClipID == guide.offlineClipID)
        #expect(reopened.activeTour?.index == guide.activeTour?.index)
        reopened.reset()
        guide.skipAnnouncement()
        guide.offlineQuestion = "What is this?"; guide.askOfflineQuestion()
        #expect(guide.offlineClipID == "qa_0_0")
        guide.offlineQuestion = "What is the weather now?"; guide.askOfflineQuestion()
        #expect(guide.tourNotice == "That answer is not downloaded. Connect to the internet to ask Pip.")
        #expect(await guide.picks(at: CLLocation(latitude: 43.64, longitude: -79.38), weather: nil).isEmpty)
        #expect(await guide.currentWeather(at: CLLocation(latitude: 43.64, longitude: -79.38)) == nil)
        #expect(await tokens.calls == 0)
        guide.reset()
    }
}
#endif
