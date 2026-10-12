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
        #expect(e.fetchPlan()?.radius_meters == 900)
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
        // Stopping for 20 s within 45 m of it: Pip speaks.
        let now = stand(&e, north: 14, from: t0.addingTimeInterval(11), seconds: 21)
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
        var e = engine([place("a", tier: .notable, north: 10), place("b", tier: .notable, north: 15, east: 30)])
        var now = stand(&e, from: t0, seconds: 21)
        let firstResult = e.decide(at: now)
        let first = try #require(firstResult)
        #expect(first.place.id == "a")
        e.markMentioned(first, at: now)
        // Still stopped and b is in range, but the 3.5-minute talk budget is closed.
        now = stand(&e, from: now.addingTimeInterval(1), seconds: 30)
        #expect(e.decide(at: now) == nil)
        // Once the budget reopens, b is allowed; a never repeats.
        now = stand(&e, from: now.addingTimeInterval(e.budget), seconds: 21)
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

    @Test func drivingLeadScalesWithSpeed() {
        // At 25 mph, a 400 m landmark is within the 45 s window. At 10 mph it is not.
        for (speed, shouldAnnounce) in [(11.176, true), (4.4704, false)] {
            var e = engine([place("ahead", tier: .mustSee, north: 400)])
            e.selectTourMode(.driving)
            for second in 0...4 {
                e.ingest(fix(at: t0.addingTimeInterval(Double(second)), speed: speed, course: 0))
            }
            #expect((e.decide(at: t0.addingTimeInterval(4)) != nil) == shouldAnnounce)
        }
    }

    @Test func drivingLeadRejectsBehindAndOutsideCorridor() {
        var e = engine([place("behind", tier: .mustSee, north: -300),
                        place("off road", tier: .mustSee, north: 300, east: 250)])
        e.selectTourMode(.driving)
        for second in 0...4 {
            e.ingest(fix(at: t0.addingTimeInterval(Double(second)), speed: 11.176, course: 0))
        }
        #expect(e.decide(at: t0.addingTimeInterval(4)) == nil)
    }

    @Test func highwayOnlyMentionsMustSees() {
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
        now = stand(&e, from: now.addingTimeInterval(e.venueBudget), seconds: 21)
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

    @Test func guideEndpointsArePostOnly() throws {
        #expect(throws: APIClientError.self) { try APIRequest<GuideNearbyResponse>.get(.guideNearby) }
        let body = GuideNearbyRequest(latitude: 32.7, longitude: -117.1, radius_meters: 500, language: "en")
        let request = try APIRequest<GuideNearbyResponse>.post(.guideNearby, body: body)
        #expect(request.endpoint.path == "/v1/guide/nearby" && request.method == "POST")
        #expect(APIEndpoint.guideMention.path == "/v1/guide/mention" && APIEndpoint.guideMention.canPost)
    }

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
