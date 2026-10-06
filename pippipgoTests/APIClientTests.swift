import AVFoundation
import Foundation
import SwiftUI
import Testing
@testable import pippipgo

@Suite(.serialized)
struct APIClientTests {
    #if !targetEnvironment(simulator)
    @MainActor @Test func physicalVoiceCaptureProducesAudioBuffers() async throws {
        let allowed = await AVAudioApplication.requestRecordPermission()
        guard allowed else {
            Issue.record("Allow PipPipGo microphone access to run the device capture check.")
            return
        }
        let audio = VoiceAudio()
        defer { audio.stop() }
        let stream = try await audio.start()
        let data = try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return try await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(4))
                throw APIClientError.invalidRequest("Microphone produced no PCM buffers within four seconds.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        #expect(data != nil && !data!.isEmpty && data!.count.isMultiple(of: 2))
    }
    @MainActor @Test func physicalBasicMicrophoneProducesFrames() async throws {
        try await checkBasicCapture(voiceProcessing: false)
    }

    @MainActor @Test func physicalVoiceProcessedMicrophoneProducesFrames() async throws {
        try await checkBasicCapture(voiceProcessing: true)
    }

    @MainActor @Test func physicalVoiceCaptureSustainsPlaybackAndRestart() async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            Issue.record("Allow microphone permission for the sustained capture check.")
            return
        }
        for _ in 0..<3 {
            try await checkSustainedVoiceCapture()
            await VoiceAudioSession.shared.flush()
        }
    }

    @MainActor private func checkSustainedVoiceCapture() async throws {
        let audio = VoiceAudio()
        defer { audio.stop() }
        let stream = try await audio.start()
        // Exercise simultaneous output without recording or playing the user's speech.
        try audio.play(Data(repeating: 0, count: 9600))
        let bytes = try await withThrowingTaskGroup(of: Int.self) { group in
            group.addTask {
                var count = 0
                for try await data in stream {
                    guard !data.isEmpty, data.count.isMultiple(of: 2) else {
                        throw APIClientError.invalidRequest("Invalid PCM capture data.")
                    }
                    count += data.count
                    if count >= 96_000 { return count }
                }
                return count
            }
            group.addTask {
                try await Task.sleep(for: .seconds(6))
                throw APIClientError.invalidRequest("Capture did not sustain two seconds of PCM audio.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        #expect(bytes >= 96_000)
    }

    @MainActor private func checkBasicCapture(voiceProcessing: Bool) async throws {
        guard await AVAudioApplication.requestRecordPermission() else {
            Issue.record("Allow microphone permission for the capture comparison.")
            return
        }
        let owner = UUID()
        try await VoiceAudioSession.shared.activate(owner: owner)
        let engine = AVAudioEngine()
        if voiceProcessing { try engine.inputNode.setVoiceProcessingEnabled(true) }
        let stream = AsyncThrowingStream<UInt32, Error> { continuation in
            engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
                continuation.yield(buffer.frameLength)
            }
        }
        defer {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            VoiceAudioSession.shared.deactivate(owner: owner)
        }
        try engine.start()
        let frames = try await withThrowingTaskGroup(of: UInt32?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return try await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(4))
                throw APIClientError.invalidRequest("Basic microphone produced no frames within four seconds.")
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
        #expect((frames ?? 0) > 0)
    }
    #endif

    @MainActor @Test func stoppedVoiceCaptureCannotStartLater() async {
        let audio = VoiceAudio()
        audio.stop()
        do {
            _ = try await audio.start()
            Issue.record("A stopped call must not activate its microphone.")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test func audioSessionChangesRunOffMainAndIgnoreStaleCleanup() async throws {
        let changes = AudioSessionChanges()
        let session = VoiceAudioSession(activate: {
            #expect(!Thread.isMainThread)
            changes.append("activate")
        }, deactivate: {
            #expect(!Thread.isMainThread)
            changes.append("deactivate")
        })
        let first = UUID(), second = UUID()
        try await session.activate(owner: first)
        session.deactivate(owner: first)
        try await session.activate(owner: second)
        session.deactivate(owner: first)
        await session.flush()
        #expect(changes.values == ["activate", "deactivate", "activate"])
        session.deactivate(owner: second)
        await session.flush()
        #expect(changes.values == ["activate", "deactivate", "activate", "deactivate"])
    }

    @Test func voiceBubblesPreserveOverlappingSpeechAndLateFragments() {
        var transcript = VoiceTranscript()
        transcript.append("Hi, I’m Pip.", speaker: .pip, startMilliseconds: 0, endMilliseconds: 800)
        transcript.append("I’d like", speaker: .user, startMilliseconds: 1000, endMilliseconds: 1500)
        let userID = transcript.messages[1].id
        transcript.append("Sure.", speaker: .pip, startMilliseconds: 2200, endMilliseconds: 2400)
        transcript.append(" to visit Paris.", speaker: .user, startMilliseconds: 1500, endMilliseconds: 3000)
        #expect(transcript.messages.count == 3)
        #expect(transcript.messages[1].id == userID)
        #expect(transcript.messages[1].text == "I’d like to visit Paris.")
        transcript.append("Also Rome.", speaker: .user, startMilliseconds: 8000, endMilliseconds: 8800)
        transcript.append(" Paris.", speaker: .user, startMilliseconds: 3000, endMilliseconds: 3300)
        #expect(transcript.messages.count == 4)
        #expect(transcript.messages[1].text == "I’d like to visit Paris. Paris.")
        #expect(transcript.messages.last?.text == "Also Rome.")
        #expect(transcript.messages[1].fragments.last?.startMilliseconds == 3000)
    }

    @Test func voiceBubblesOrderDelayedSpeakersAndClearTransientHistory() {
        var transcript = VoiceTranscript()
        transcript.append("Of course.", speaker: .pip, startMilliseconds: 4000, endMilliseconds: 4800)
        transcript.append("Can you help?", speaker: .user, startMilliseconds: 1000, endMilliseconds: 2500)
        #expect(transcript.messages.map(\.speaker) == [.user, .pip])
        transcript.clear()
        #expect(transcript.messages.isEmpty)
        transcript.append("Hello", speaker: .user, startMilliseconds: nil, endMilliseconds: nil)
        transcript.append(" hello", speaker: .user, startMilliseconds: nil, endMilliseconds: nil)
        transcript.append("Hi", speaker: .pip, startMilliseconds: .nan, endMilliseconds: .infinity)
        #expect(transcript.messages.map(\.text) == ["Hello hello", "Hi"])
    }

    @Test func resumedTalkStreamsBelowHistoryWithoutMergingOldBubbles() {
        var transcript = VoiceTranscript()
        transcript.appendHistory("Old question", speaker: .user)
        transcript.appendHistory("Old answer", speaker: .pip)
        let oldID = transcript.messages.last?.id
        transcript.append("New reply", speaker: .pip, startMilliseconds: 2000, endMilliseconds: 2500)
        transcript.append("New question", speaker: .user, startMilliseconds: 1000, endMilliseconds: 1500)
        transcript.append(" continues", speaker: .pip, startMilliseconds: 2500, endMilliseconds: 3000)
        #expect(transcript.messages.map(\.text) == ["Old question", "Old answer", "New question", "New reply continues"])
        #expect(transcript.messages[1].id == oldID)
        transcript.clear()
        transcript.append("Fresh talk", speaker: .pip, startMilliseconds: nil, endMilliseconds: nil)
        #expect(transcript.messages.map(\.text) == ["Fresh talk"])
    }

    @Test func voiceBubblesBoundSessionMemory() {
        var transcript = VoiceTranscript()
        for index in 0..<600 {
            let time = Double(index) * 2000
            transcript.append(String(repeating: "x", count: 100), speaker: index.isMultiple(of: 2) ? .user : .pip,
                              startMilliseconds: time, endMilliseconds: time + 100)
        }
        #expect(transcript.messages.count <= 64)
        #expect(transcript.messages.reduce(0) { $0 + $1.text.count } <= 8000)
        #expect(transcript.messages.reduce(0) { $0 + $1.fragments.count } <= 512)
    }

    @Test func microphoneLevelDetectsSignedPCMAndSilence() {
        #expect(LiveVoiceStore.level(Data(repeating: 0, count: 960)) == 0)
        #expect(LiveVoiceStore.level(Data([0, 128])) == 1)
        #expect(LiveVoiceStore.level(Data([0, 64])) == 0.5)
        #expect(LiveVoiceStore.level(Data([0])) == 0)
    }

    @MainActor @Test func liveVoiceUsesBackendAuthorizationWithoutURLTokens() throws {
        let request = try LiveVoiceStore.request(baseURL: URL(string: "https://api-dev.pippipgo.com?discard=1#fragment")!, token: "test-access-token")
        #expect(request.url?.absoluteString == "wss://api-dev.pippipgo.com/v1/travel-chat/live")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-access-token")
        #expect(throws: (any Error).self) {
            try LiveVoiceStore.request(baseURL: URL(string: "https://name:password@example.com")!, token: "token")
        }
    }

    @Test func legacyPartyIncludesUnnamedTravelers() throws {
        let party = OrganizerParty.legacyNotes("Travelers: 3 adults and one 14-year-old; select travelers during review.")
        #expect(party == OrganizerParty(adults: 3, children: 1))
        #expect(party?.total == 4)
        #expect(OrganizerParty.legacyNotes("Visit 3 adult attractions") == nil)
        var trip = OrganizerTrip(name: "Party")
        trip.party = party
        #expect(try JSONDecoder().decode(OrganizerTrip.self, from: JSONEncoder().encode(trip)).party == party)
    }

    @Test func chatDraftDecodesAndLegacyMessagesRemainReadable() throws {
        let old = Data(#"{"id":"old","role":"assistant","text":"A plan"}"#.utf8)
        #expect(try JSONDecoder().decode(TravelChatMessage.self, from: old).trip_draft == nil)
        var trip = OrganizerTrip(name: "London")
        trip.budget = OrganizerBudget(currency: "GBP", total: "2000")
        trip.stops = [OrganizerStop(destination: "London", arrival: "2026-10-10")]
        let message = TravelChatMessage(id: "draft", role: "assistant", text: "Review trip", trip_draft: trip)
        let restored = try JSONDecoder().decode(TravelChatMessage.self, from: JSONEncoder().encode(message))
        #expect(restored.trip_draft == trip)
    }

    @Test func budgetTotalsAreExactAndOldTripsStillDecode() throws {
        var budget = OrganizerBudget(); budget.total = "15000"
        budget.flights.estimated = "6000"; budget.hotels.estimated = "3600"
        budget.flights.actual = "6200.50"; budget.food.actual = "0.10"; budget.other.actual = "0.20"
        #expect(budget.estimatedTotal == 9600)
        #expect(budget.actualTotal == Decimal(string: "6200.80"))
        #expect(budget.remaining == Decimal(string: "8799.20"))
        #expect(budget.unallocated == 5400)
        budget.total = "100"; #expect(budget.remaining! < 0)
        budget.currency = "JPY"; #expect(!budget.isValid)
        budget.currency = "USD"; budget.food.actual = "-1"; #expect(!budget.isValid)
        let old = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"name\":\"Old trip\",\"include_me\":true,\"companion_ids\":[],\"stops\":[],\"notes\":\"\"}".utf8)
        #expect(try APIJSON.decoder().decode(OrganizerTrip.self, from: old).budget == nil)
        var trip = OrganizerTrip(); trip.budget = OrganizerBudget(total: "15000")
        let roundTrip = try APIJSON.decoder().decode(OrganizerTrip.self, from: APIJSON.encoder().encode(trip))
        #expect(roundTrip.budget?.total == "15000")
    }

    @Test func chatMarkdownRendersPlanFormatting() {
        let blocks = ChatMarkdownBlock.parse("## Tokyo\n\n**Four nights** near the station.\n- **Hotel:** apartment\n2. Take the train\n\n[Details](https://example.com)")
        #expect(blocks.map(\.kind) == [.heading(2), .paragraph, .bullet, .numbered("2."), .paragraph])
        #expect(String(blocks[1].attributed.characters) == "Four nights near the station.")
        #expect(blocks[1].attributed.runs.contains { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true })
        #expect(blocks[2].text == "**Hotel:** apartment")
        #expect(blocks[4].attributed.runs.contains { $0.link?.absoluteString == "https://example.com" })
        let unsafe = ChatMarkdownBlock.parse("[Open](pippipgo://auth/logout)")[0]
        #expect(!unsafe.attributed.runs.contains { $0.link != nil })
    }

    @MainActor @Test func travelChatTimeoutRetainsOnlyMessageAndExactRetry() async throws {
        let data = TravelChatData(messages: [TravelChatMessage(id: "1", role: "assistant", text: "Which area?")])
        let record = APIRecord(id: "me", kind: "travel_chat", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: data)
        let body = try APIJSON.encoder().encode(record)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([
            .init(error: .timedOut), .init(status: 200, body: body), .init(status: 200, body: body)]))
        let store = TravelChatStore(client: client, authentication: TestTokens(), captureContext: { .snapshot() })
        store.loaded = true; store.composer = "Where is a locker?"
        await store.send()
        let request = try #require(store.pending)
        let payload = try #require(JSONSerialization.jsonObject(with: request.body!) as? [String: Any])
        #expect(payload["text"] as? String == "Where is a locker?")
        #expect(payload["conversation_context"] is [String: Any])
        await store.retry()
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(store.messages.count == 1 && store.pending == nil && store.composer.isEmpty)
        store.reset(); #expect(store.messages.isEmpty && !store.loaded && store.version == 0)
    }

    @MainActor @Test func destinationBindingSurvivesReorderAndRemoval() {
        let first = OrganizerStop(destination: "Vancouver", arrival: "2026-09-28")
        let second = OrganizerStop(destination: "Victoria")
        var trip = OrganizerTrip(name: "Canada", stops: [first, second])
        let binding = Binding(get: { trip }, set: { trip = $0 }).stop(first)
        trip.stops.reverse()
        binding.wrappedValue.hotel = "Vancouver Hotel"
        #expect(trip.stops[1].hotel == "Vancouver Hotel")
        #expect(trip.stops[0].hotel.isEmpty)
        trip.stops.removeAll { $0.id == first.id }
        // SwiftUI can read the date binding during the outgoing screen transition.
        #expect(binding.wrappedValue.arrival == "2026-09-28")
        binding.wrappedValue.arrival = nil
        #expect(trip.stops == [second])
        trip.stops.removeAll()
        #expect(binding.wrappedValue.destination == "Vancouver")
    }

    @MainActor @Test func organizerRetryFreezesBodyAndResetsSession() async throws {
        var data = OrganizerData(); data.profile = OrganizerPerson(name: "Ali", age: 35, hometown: "San Diego")
        let record = APIRecord(id: "me", kind: "organizer", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: data)
        let body = try APIJSON.encoder().encode(record)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([
            .init(error: .timedOut), .init(status: 200, body: body), .init(status: 200, body: body)]))
        let store = OrganizerStore(client: client, authentication: TestTokens()); store.loaded = true
        #expect(await store.save(data) == false)
        let frozen = try #require(store.pending)
        data.profile?.name = "Changed after timeout"
        #expect(await store.save(data) == false)
        #expect(store.pending?.body == frozen.body)
        #expect(await store.retry())
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(store.data.profile?.name == "Ali")
        store.reset(); #expect(!store.loaded && store.data.profile == nil && store.pending == nil)
    }

    @MainActor @Test func organizerConflictRequiresExplicitReview() async throws {
        var latest = OrganizerData(); latest.profile = OrganizerPerson(name: "Saved elsewhere")
        let current = APIRecord(id: "me", kind: "organizer", version: 2, revision: 2, updatedAt: Date(), deleted: false, data: latest)
        let json = try JSONSerialization.jsonObject(with: APIJSON.encoder().encode(current))
        let body = try JSONSerialization.data(withJSONObject: ["error": ["code": "version_conflict", "message": "Review changes", "details": ["current": json]]])
        let store = OrganizerStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 409, body: body)])), authentication: TestTokens())
        store.loaded = true
        var draft = OrganizerData(); draft.profile = OrganizerPerson(name: "My edit")
        #expect(await store.save(draft) == false)
        #expect(store.conflict?.version == 2 && store.pending != nil)
        #expect(await store.retry() == false)
        store.useLatest()
        #expect(store.data.profile?.name == "Saved elsewhere" && store.version == 2 && store.pending == nil)
    }

    @Test func doorToDoorRoundTripAndExternalSearch() throws {
        var intake = TripIntake(); intake.destination = "New York"; intake.start_date = "2026-10-10"; intake.end_date = "2026-10-14"
        var travel = DoorToDoorTravel(); travel.mode = "fly"; travel.departure_airport = "SAN"
        var flight = FlightSegment(); flight.arrival_airport = "EWR"; flight.departure_airport = "SAN"
        flight.departure_timezone = "America/Los_Angeles"; flight.arrival_timezone = "America/New_York"
        flight.departure_local = "2026-10-10T23:00"; flight.arrival_local = "2026-10-11T07:00"
        travel.flights = [flight]; travel.transfers = [GroundTransfer(leg: "airport_to_hotel")]; intake.door_to_door = travel
        let decoded = try APIJSON.decoder().decode(TripIntake.self, from: APIJSON.encoder().encode(intake))
        #expect(decoded == intake)
        let url = travel.flightSearchURL(destination: intake.destination, when: "", start: intake.start_date, end: intake.end_date)
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value ?? ""
        #expect(url.host == "www.google.com")
        #expect(query.contains("SAN") && query.contains("New York") && query.contains("2026-10-14"))
    }

    @Test func olderJourneyIntakeDecodesWithoutDoorToDoorFields() throws {
        var intake = TripIntake(); intake.destination = "San Diego"
        let encoded = try APIJSON.encoder().encode(intake)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "door_to_door")
        let decoded = try APIJSON.decoder().decode(TripIntake.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.door_to_door == nil)
        #expect(decoded.destination == "San Diego")
    }

    @MainActor @Test func preferredNameRequiresExplicitPersistentMemory() {
        let store = IntelligenceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!), authentication: TestTokens())
        var memory = TravelerMemory(); memory.key = "preferred_name"; memory.value = "Sara"; memory.status = "inferred"
        func record(_ value: TravelerMemory) -> APIRecord<TravelerMemory> {
            APIRecord(id: UUID().uuidString.lowercased(), kind: "memory", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: value)
        }
        store.memories = [record(memory)]; #expect(store.preferredName == nil)
        memory.status = "confirmed"; store.memories = [record(memory)]; #expect(store.preferredName == "Sara")
        memory.scope = "trip_specific"; store.memories = [record(memory)]; #expect(store.preferredName == nil)
        store.selectedID = UUID(); store.newTrip(language: "en"); #expect(store.selectedID == nil)
    }

    @Test func savedConversationAndPlanChangesSurviveReload() throws {
        let progress = try APIJSON.decoder().decode(IntakeProgress.self, from: Data(#"{"next_step":"lodging","question":"Where are you staying?","turns":2,"skipped":["flights"],"answers":{"travel_mode":{"text":"train"}}}"#.utf8))
        #expect(progress.next_step == "lodging")
        #expect(progress.skipped == ["flights"])
        let changes = PlanChanges(unchanged: ["Hotel"], added: ["Market"], changed: [], removed: ["Long walk"])
        #expect(try APIJSON.decoder().decode(PlanChanges.self, from: APIJSON.encoder().encode(changes)) == changes)
        let request = try APIRequest<Journey>.put(.journeyAction(UUID()), body: PipAction(action: "skip_intake", skip_topic: "lodging"), expectedVersion: 3)
        let body = try APIJSON.decoder().decode(JSONValue.self, from: request.body!)
        #expect(body["skip_topic"] == .string("lodging"))
    }

    @MainActor @Test func importReviewRejectionDoesNotFreezeActions() async throws {
        let id = UUID()
        var intake = TripIntake(); intake.destination = "New York"
        let record = APIRecord(id: id.uuidString.lowercased(), kind: "journey", version: 1, revision: 1, updatedAt: Date(), deleted: false,
            data: Journey(intake: intake, messages: [], plan: [], proposal: nil, imports: [], onboarding_done: false, temporary_context: ""))
        let error = Data(#"{"error":{"code":"import_review_required","message":"Review the import first"}}"#.utf8)
        let store = IntelligenceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 409, body: error)])), authentication: TestTokens())
        store.journeys = [record]; store.selectedID = id; store.edit(record)
        await store.act(PipAction(action: "plan"))
        #expect(!store.hasPending)
        #expect(store.error == "Review the import first")
        #expect(store.selected?.data.intake.destination == "New York")
    }

    @MainActor @Test func preferredNameAloneDoesNotSkipTravelerIntroduction() {
        let store = IntelligenceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!), authentication: TestTokens())
        var memory = TravelerMemory(); memory.key = "preferred_name"; memory.value = "Sara"
        store.memories = [APIRecord(id: UUID().uuidString, kind: "memory", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: memory)]
        #expect(store.needsIntroduction)
        store.introduction = APIRecord(id: "me", kind: "introduction", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: TravelerIntroduction(messages: [], onboarding_done: true))
        #expect(!store.needsIntroduction)
        store.reset()
        #expect(store.needsIntroduction)
        #expect(store.introduction == nil)
    }

    @MainActor @Test func introductionTimeoutKeepsAnswerAndRequestForExactRetry() async throws {
        let intro = APIRecord(id: "me", kind: "introduction", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: TravelerIntroduction(messages: [], onboarding_done: false))
        let body = try APIJSON.encoder().encode(intro)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(error: .timedOut), .init(status: 200, body: body), .init(status: 200, body: body), .init(status: 200, body: Data(#"{"items":[]}"#.utf8))]))
        let store = IntelligenceStore(client: client, authentication: TestTokens())
        store.introduction = APIRecord(id: "me", kind: "introduction", version: 0, revision: 0, updatedAt: Date(), deleted: false, data: intro.data)
        store.introductionAnswer = "Wandering in Italy"
        await store.introduce(language: "en")
        #expect(store.hasPending)
        #expect(store.introductionAnswer == "Wandering in Italy")
        let frozen = store.pendingIntroduction?.body
        await store.retryIntroduction()
        #expect(!store.hasPending)
        #expect(StubURLProtocol.bodies[0] == frozen)
        #expect(StubURLProtocol.bodies[1] == frozen)
        #expect(store.journeys.isEmpty)
    }

    @Test func mapsUnauthorizedResponse() async {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: makeSession(status: 401, body: Data()))
        await #expect(throws: APIClientError.unauthorized) { try await client.account(accessToken: "not-a-real-token") }
    }

    @Test func surfacesBackendErrorMessage() async {
        let body = Data(#"{"error":{"code":"identity_unavailable","message":"Identity provider is unavailable"}}"#.utf8)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: makeSession(status: 503, body: body))
        await #expect(throws: APIClientError.rejected(status: 503, error: APIErrorBody(code: "identity_unavailable", message: "Identity provider is unavailable"), requestID: nil)) {
            try await client.account(accessToken: "not-a-real-token")
        }
    }

    @Test func decodesBackendAccountTimestampWithFractionalSeconds() async throws {
        let body = Data(
            #"{"id":"account-1","kind":"account","version":1,"revision":1,"updated_at":"2026-09-25T12:34:56.123456Z","deleted":false,"data":{}}"#.utf8
        )
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: makeSession(status: 200, body: body))

        let account = try await client.account(accessToken: "not-a-real-token")

        #expect(account.id == "account-1")
        #expect(account.updatedAt.timeIntervalSince1970 > 0)
    }

    @Test func frozenWriteSurvivesAuthenticationRetry() async throws {
        let session = queuedSession([.init(status: 401), .init(status: 200, body: Data("{}".utf8))])
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: session)
        let tokens = TestTokens()
        let id = UUID(), key = UUID()
        var draft: JSONValue = .object(["nickname": .string("Original"), "home_base": .null])
        let operation = try APIRequest<JSONValue>.put(.traveler(id), body: draft, expectedVersion: 3, idempotencyKey: key)
        draft = .object(["nickname": .string("Changed after request construction")])
        _ = try await client.send(operation, using: tokens)
        let calls = StubURLProtocol.requests
        #expect(calls.count == 2)
        #expect(calls[0].url?.path == "/v1/travelers/\(id.uuidString.lowercased())")
        #expect(calls[0].httpMethod == "PUT")
        #expect(calls[0].value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(calls[0].value(forHTTPHeaderField: "Authorization") == "Bearer original-token")
        #expect(calls[1].value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token")
        for call in calls {
            #expect(call.value(forHTTPHeaderField: "Idempotency-Key") == key.uuidString.lowercased())
            #expect(call.value(forHTTPHeaderField: "X-Expected-Version") == "3")
        }
        #expect(StubURLProtocol.bodies[0] == operation.body)
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        let encoded = try APIJSON.decoder().decode(JSONValue.self, from: StubURLProtocol.bodies[0])
        #expect(encoded["nickname"] == .string("Original"))
        #expect(encoded["home_base"] == .null)
        #expect(await tokens.refreshFlags == [false, true])
    }

    @Test func secondUnauthorizedResponseDoesNotLoop() async throws {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 401), .init(status: 401)]))
        let tokens = TestTokens()
        await #expect(throws: APIClientError.unauthorized) { try await client.account(using: tokens) }
        #expect(StubURLProtocol.requests.count == 2)
        #expect(await tokens.refreshFlags == [false, true])
    }

    @Test func refreshFailureDoesNotSendAnotherWrite() async throws {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 401)]))
        let tokens = TestTokens(failRefresh: true)
        let operation = try APIRequest<JSONValue>.put(.journey(UUID()), body: JSONValue.object(["destinations": .array([.string("San Diego")])]), expectedVersion: 0)
        await #expect(throws: AuthenticationError.sessionExpired) { try await client.send(operation, using: tokens) }
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func timeoutCanBeRetriedWithIdenticalOperation() async throws {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(error: .timedOut), .init(status: 200, body: Data("{}".utf8))]))
        let operation = try APIRequest<JSONValue>.put(.journeyAction(UUID()), body: PipAction(action: "plan"), expectedVersion: 1)
        await #expect(throws: APIClientError.connection) { try await client.send(operation, accessToken: "token") }
        #expect(StubURLProtocol.requests.count == 1)
        _ = try await client.send(operation, accessToken: "token")
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "X-Expected-Version") == "1")
    }

    @Test func conflictPreservesServerRecordAndRequestWithoutRetry() async throws {
        let body = Data(#"{"error":{"code":"version_conflict","message":"Resolve conflict","request_id":"req-409","details":{"expected_version":1,"current":{"id":"me","kind":"profile","version":2,"revision":5,"updated_at":"2026-09-25T12:34:56Z","deleted":false,"data":{"nickname":"Server"}}}}}"#.utf8)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 409, body: body)]))
        let tokens = TestTokens()
        let operation = try APIRequest<JSONValue>.put(.preferences, body: JSONValue.object(["nickname": .string("Local")]), expectedVersion: 1)
        do {
            _ = try await client.send(operation, using: tokens)
            Issue.record("Expected a conflict")
        } catch APIClientError.conflict(let error, let requestID) {
            #expect(error.code == "version_conflict")
            #expect(error.details?["expected_version"] == .integer(1))
            #expect(error.currentRecord?.version == 2)
            #expect(error.currentRecord?.data["nickname"] == .string("Server"))
            #expect(requestID == "req-409")
        }
        #expect(operation.expectedVersion == 1)
        #expect(try APIJSON.decoder().decode(JSONValue.self, from: #require(operation.body))["nickname"] == .string("Local"))
        #expect(StubURLProtocol.requests.count == 1)
        #expect(await tokens.refreshFlags == [false])
    }

    @Test func nonVersionConflictRetainsItsCode() async throws {
        let body = Data(#"{"error":{"code":"idempotency_conflict","message":"Different request","details":null}}"#.utf8)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 409, body: body)]))
        do {
            _ = try await client.account(accessToken: "token")
            Issue.record("Expected conflict")
        } catch APIClientError.conflict(let error, _) {
            #expect(error.code == "idempotency_conflict")
            #expect(error.currentRecord == nil)
        }
    }

    @Test func validationErrorRetainsFieldDetailsAndHeaderRequestID() async throws {
        let body = Data(#"{"error":{"code":"validation_error","message":"Invalid request","details":[{"location":["body","destinations"],"message":"Required","type":"missing"}]}}"#.utf8)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 422, body: body, headers: ["X-Request-ID": "header-id"])]))
        do {
            _ = try await client.account(accessToken: "token")
            Issue.record("Expected validation error")
        } catch APIClientError.rejected(let status, let error, let requestID) {
            #expect(status == 422)
            #expect(error.code == "validation_error")
            #expect(requestID == "header-id")
            guard case .array(let fields) = error.details else { Issue.record("Missing field details"); return }
            #expect(fields.first?["location"] == .array([.string("body"), .string("destinations")]))
        }
    }

    @Test func preservesNotFoundAndDoesNotRetryServiceFailures() async throws {
        for status in [404, 429, 503] {
            let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: status, body: Data("<html>unavailable</html>".utf8))]))
            let tokens = TestTokens()
            do { _ = try await client.account(using: tokens); Issue.record("Expected failure") }
            catch APIClientError.rejected(let actual, let error, _) {
                #expect(actual == status)
                #expect(error.code == "http_error")
                #expect(!error.message.contains("html"))
            }
            #expect(StubURLProtocol.requests.count == 1)
            #expect(await tokens.refreshFlags == [false])
        }
    }

    @Test func decodesListsSyncAndTombstones() async throws {
        let record = #"{"id":"trip-id","kind":"trip","version":3,"revision":6,"updated_at":"2026-09-25T12:34:56.123456+00:00","deleted":true,"data":{}}"#
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([
            .init(status: 200, body: Data("{\"items\":[\(record)]}".utf8)),
            .init(status: 200, body: Data("{\"cursor\":6,\"changes\":[\(record)]}".utf8))]))
        let list = try await client.send(APIRequest<APIRecordList<JSONValue>>.get(.journeys), accessToken: "token")
        #expect(list.items.first?.deleted == true)
        let sync = try await client.send(APIRequest<APISyncResponse>.get(.sync(after: 4)), accessToken: "token")
        #expect(sync.cursor == 6)
        #expect(sync.changes.first?.data == .object([:]))
        #expect(StubURLProtocol.requests.last?.url?.query == "after=4")
        #expect(StubURLProtocol.requests.last?.value(forHTTPHeaderField: "Idempotency-Key") == nil)
    }

    @Test func deleteUsesVersionAndKeyWithoutBody() async throws {
        let id = UUID()
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 200, body: Data("{}".utf8))]))
        let operation = try APIRequest<JSONValue>.delete(.journey(id), expectedVersion: 2)
        _ = try await client.send(operation, accessToken: "token")
        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "X-Expected-Version") == "2")
        #expect(request.value(forHTTPHeaderField: "Idempotency-Key") != nil)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
        #expect(StubURLProtocol.bodies.first?.isEmpty == true)
        let accountDelete = APIRequest<JSONValue>.deleteAccount()
        #expect(accountDelete.expectedVersion == nil)
        #expect(accountDelete.idempotencyKey == nil)
    }

    @Test func rejectsInvalidMethodsAndVersionsBeforeSending() throws {
        #expect(throws: APIClientError.self) { try APIRequest<JSONValue>.delete(.journey(UUID()), expectedVersion: 0) }
        #expect(throws: APIClientError.self) { try APIRequest<JSONValue>.put(.preferences, body: JSONValue.null, expectedVersion: -1) }
        #expect(throws: APIClientError.self) { try APIRequest<JSONValue>.post(.journeys, body: JSONValue.null) }
        #expect(throws: APIClientError.self) { try APIRequest<JSONValue>.get(.sync(after: -1)) }
    }


    @Test func cancellationIsNotConvertedToConnectionFailure() async throws {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(error: .cancelled)]))
        do { _ = try await client.account(accessToken: "token"); Issue.record("Expected cancellation") }
        catch let error as URLError { #expect(error.code == .cancelled) }
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test func malformedSuccessfulResponseIsDecodingFailure() async throws {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 200, body: Data("{}".utf8))]))
        await #expect(throws: APIClientError.decoding) { try await client.account(accessToken: "token") }
    }



    private func queuedSession(_ responses: [StubReply]) -> URLSession {
        let session = makeSession(status: 200, body: Data())
        StubURLProtocol.replies = responses
        return session
    }



    @MainActor @Test func intakeTimeoutPreservesRequestAndDraft() async throws {
        let id = UUID()
        var intake = TripIntake(); intake.destination = "San Diego"
        let record = APIRecord(id: id.uuidString.lowercased(), kind: "journey", version: 1, revision: 2, updatedAt: Date(), deleted: false,
            data: Journey(intake: intake, messages: [], plan: [], proposal: nil, imports: [], onboarding_done: false, temporary_context: ""))
        let body = try APIJSON.encoder().encode(record)
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(error: .timedOut), .init(status: 200, body: body), .init(status: 200, body: body), .init(status: 200, body: Data(#"{"items":[]}"#.utf8))]))
        let store = IntelligenceStore(client: client, authentication: TestTokens())
        store.draft = intake; store.draftID = id
        await store.saveIntake()
        #expect(store.pending != nil); #expect(store.draft.destination == "San Diego")
        await store.retry()
        #expect(store.pending == nil); #expect(store.selected?.id == record.id)
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        #expect(StubURLProtocol.requests[2].httpMethod == "GET")
    }

    @MainActor @Test func intakeValidationFailureAllowsCorrection() async throws {
        let error = Data(#"{"error":{"code":"validation_error","message":"Provide timing"}}"#.utf8)
        let store = IntelligenceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([.init(status: 422, body: error)])), authentication: TestTokens())
        store.draft.destination = "Kyoto"
        await store.saveIntake()
        #expect(store.pending == nil); #expect(store.draft.destination == "Kyoto"); #expect(store.error == "Provide timing")
    }

    @MainActor @Test func memoryTimeoutRetainsExactOperation() async throws {
        let client = APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([
            .init(error: .timedOut), .init(status: 200, body: Data(#"{"id":"memory","kind":"memory","version":1,"revision":1,"updated_at":"2026-09-27T12:00:00Z","deleted":false,"data":{}}"#.utf8)),
            .init(status: 200, body: Data(#"{"items":[]}"#.utf8)), .init(status: 200, body: Data(#"{"items":[]}"#.utf8))]))
        let store = IntelligenceStore(client: client, authentication: TestTokens())
        var memory = TravelerMemory(); memory.key = "pace"; memory.value = "Room to explore"
        await store.saveMemory(memory)
        #expect(store.pendingAux != nil)
        await store.retryAux()
        #expect(store.pendingAux == nil)
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
    }

    @MainActor @Test func signOutResetClearsAllProductState() {
        let store = IntelligenceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!), authentication: TestTokens())
        store.draft.destination = "Private trip"; store.composer = "Private message"; store.error = "Old error"; store.selectedID = UUID()
        store.reset()
        #expect(store.draft.destination.isEmpty); #expect(store.composer.isEmpty)
        #expect(store.selectedID == nil); #expect(store.memories.isEmpty); #expect(!store.hasPending)
    }

    @Test func guideRecapKeepsOlderUsefulConversations() throws {
        let now = Date()
        let iso = ISO8601DateFormatter()
        let data = GuideData(version: 1, welcome_due: true, welcome: "Hi Sara!", summary: [
            GuideHighlight(text: "Recent", at: iso.string(from: now.addingTimeInterval(-3600)), source_id: "one"),
            GuideHighlight(text: "Expired", at: iso.string(from: now.addingTimeInterval(-25 * 3600)), source_id: "two")
        ], preferences: [])
        #expect(data.recentSummary.map(\.text) == ["Recent", "Expired"])
        #expect(try APIJSON.decoder().decode(GuideData.self, from: APIJSON.encoder().encode(data)).welcome_due)
    }

    @MainActor @Test func guidePreferenceRetryIsImmutableAndResetClearsMemory() async throws {
        let pref = GuidePreference(id: "cafes", topic: "cafes", category: "food", kind: "like", text: "Quiet cafes", evidence: "I like quiet cafes", updated_at: "2026-10-06T00:00:00Z", edited: false)
        var guide = GuideData(version: 1, welcome_due: false, welcome: "Hi!", summary: [], preferences: [pref])
        guide.version = 2
        let store = TravelChatStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([
            .init(error: .timedOut), .init(status: 200, body: try APIJSON.encoder().encode(guide))
        ])), authentication: TestTokens())
        guide.version = 1; store.guide = guide
        await store.editPreference(pref, text: "Outdoor cafes", remove: false)
        #expect(store.pendingGuideEdit != nil)
        await store.retryGuideEdit()
        #expect(store.pendingGuideEdit == nil)
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        store.reset()
        #expect(store.guide == nil && store.pendingGuideEdit == nil && store.guideError == nil)
    }

    @MainActor @Test func guideSetupRetriesFrozenChoicesAndResets() async throws {
        var choices = GuideSetup(); choices.voice = "sage"; choices.interview = "no"
        let record = APIRecord(id: "me", kind: "guide_setup", version: 1, revision: 1, updatedAt: Date(), deleted: false, data: choices)
        let store = GuideSetupStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!, urlSession: queuedSession([
            .init(error: .timedOut), .init(status: 200, body: try APIJSON.encoder().encode(record))
        ])), authentication: TestTokens())
        store.loaded = true
        #expect(await store.save(choices) == false)
        #expect(store.pending != nil)
        choices.voice = "ash"
        #expect(await store.retry())
        #expect(store.data.voice == "sage" && store.data.interview == "no")
        #expect(StubURLProtocol.bodies[0] == StubURLProtocol.bodies[1])
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Idempotency-Key") == StubURLProtocol.requests[1].value(forHTTPHeaderField: "Idempotency-Key"))
        store.reset()
        #expect(!store.loaded && store.pending == nil && store.data == GuideSetup())
    }

    private var configuration: AppConfiguration {
        AppConfiguration(cognitoDomain: URL(string: "https://auth-dev.pippipgo.com")!, clientID: "test-client", callbackURL: URL(string: "pippipgo://auth/callback")!, logoutURL: URL(string: "pippipgo://auth/logout")!, backendBaseURL: URL(string: "https://example.invalid")!)
    }

    @Test func authorizationUsesPKCEAndState() throws {
        let client = CognitoClient(configuration: configuration)
        let url = try client.authorizationURL(state: "random-state", challenge: "challenge")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "auth-dev.pippipgo.com")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["state"] == "random-state")
        #expect(values["redirect_uri"] == "pippipgo://auth/callback")
        #expect(values["identity_provider"] == nil)
        #expect(values["prompt"] == "select_account")
    }

    @Test func productionOffersProviderChoiceWithIsolatedIdentityAndPKCE() throws {
        let prod = AppConfiguration(cognitoDomain: URL(string: "https://auth.pippipgo.com")!, clientID: "23sk8qfmpotjj40jbnl9tn33em", callbackURL: configuration.callbackURL, logoutURL: configuration.logoutURL, backendBaseURL: URL(string: "https://api.pippipgo.com")!, environment: .prod)
        let url = try CognitoClient(configuration: prod).authorizationURL(state: "state", challenge: "challenge")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host == "auth.pippipgo.com")
        #expect(values["client_id"] == prod.clientID)
        #expect(values["identity_provider"] == nil)
        #expect(values["state"] == "state")
        #expect(values["code_challenge"] == "challenge")
        #expect(values["code_challenge_method"] == "S256")
        #expect(values["redirect_uri"] == "pippipgo://auth/callback")
    }

    @Test func exchangesCodeWithVerifierAndEncodedPlus() async throws {
        let body = Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":900}"#.utf8)
        let client = CognitoClient(configuration: configuration, urlSession: makeSession(status: 200, body: body))
        let tokens = try await client.tokens(code: "code+value", verifier: "verifier")
        #expect(tokens.accessToken == "access")
        #expect(tokens.refreshToken == "refresh")
        let request = try #require(StubURLProtocol.request)
        #expect(request.url?.path == "/oauth2/token")
        #expect(request.httpMethod == "POST")
        let form = String(data: StubURLProtocol.requestBody, encoding: .utf8) ?? ""
        #expect(form.contains("code=code%2Bvalue"))
        #expect(form.contains("code_verifier=verifier"))
        #expect(form.contains("grant_type=authorization_code"))
    }

    @Test func refreshesAndPreservesRefreshToken() async throws {
        let body = Data(#"{"access_token":"new-access","expires_in":900}"#.utf8)
        let client = CognitoClient(configuration: configuration, urlSession: makeSession(status: 200, body: body))
        let old = TokenSet(accessToken: "old", idToken: nil, refreshToken: "refresh+token", tokenType: "Bearer", expiresAt: .distantPast)
        let tokens = try await client.refresh(old)
        #expect(tokens.accessToken == "new-access")
        #expect(tokens.refreshToken == "refresh+token")
        let form = String(data: StubURLProtocol.requestBody, encoding: .utf8) ?? ""
        #expect(form.contains("grant_type=refresh_token"))
        #expect(form.contains("refresh_token=refresh%2Btoken"))
    }

    @Test func revokesRefreshTokenAndBuildsLogout() async throws {
        let client = CognitoClient(configuration: configuration, urlSession: makeSession(status: 200, body: Data()))
        try await client.revoke(refreshToken: "refresh")
        #expect(StubURLProtocol.request?.url?.path == "/oauth2/revoke")
        #expect(String(data: StubURLProtocol.requestBody, encoding: .utf8)?.contains("token=refresh") == true)
        let url = try client.logoutURL()
        #expect(url.path == "/logout")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        #expect(items.contains(URLQueryItem(name: "logout_uri", value: "pippipgo://auth/logout")))
    }





    private func makeSession(status: Int, body: Data) -> URLSession {
        StubURLProtocol.response = HTTPURLResponse(url: URL(string: "https://example.invalid/v1/me")!, statusCode: status, httpVersion: nil, headerFields: nil)!
        StubURLProtocol.body = body
        StubURLProtocol.replies = []
        StubURLProtocol.requests = []
        StubURLProtocol.bodies = []
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var response: HTTPURLResponse!
    nonisolated(unsafe) static var body = Data()

    nonisolated(unsafe) static var request: URLRequest?
    nonisolated(unsafe) static var requestBody = Data()

    nonisolated(unsafe) static var replies: [StubReply] = []
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.request = request
        Self.requestBody = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                Self.requestBody.append(contentsOf: buffer.prefix(count))
            }
        }
        Self.requests.append(request)
        Self.bodies.append(Self.requestBody)
        if !Self.replies.isEmpty {
            let reply = Self.replies.removeFirst()
            if let error = reply.error {
                client?.urlProtocol(self, didFailWithError: URLError(error))
                return
            }
            Self.response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!
            Self.body = reply.body
        }
        client?.urlProtocol(self, didReceive: Self.response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

private struct StubReply {
    var status: Int = 200
    var body = Data()
    var headers: [String: String] = [:]
    var error: URLError.Code? = nil
}

private actor TestTokens: AccessTokenProviding {
    var refreshFlags: [Bool] = []
    let failRefresh: Bool
    init(failRefresh: Bool = false) { self.failRefresh = failRefresh }
    func validAccessToken(forceRefresh: Bool) async throws -> String {
        refreshFlags.append(forceRefresh)
        if forceRefresh && failRefresh { throw AuthenticationError.sessionExpired }
        return forceRefresh ? "refreshed-token" : "original-token"
    }
}

private final class AudioSessionChanges: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    func append(_ value: String) { lock.lock(); defer { lock.unlock() }; recorded.append(value) }
    var values: [String] { lock.lock(); defer { lock.unlock() }; return recorded }
}


struct ChatMapDestinationTests {
    @Test func previewsOnlySupportedMapsLinksAndDeduplicates() {
        let text = "[Cafe](https://www.google.com/maps/search/?api=1&query=Cafe%20Paris) [Again](https://www.google.com/maps/search/?api=1&query=Cafe%20Paris) [Other](https://example.com/?q=Paris)"
        let destinations = ChatMapDestination.parse(text)
        #expect(destinations.count == 1)
        #expect(destinations.first?.query == "Cafe Paris")
        #expect(destinations.first?.title == "Cafe")
    }
    @Test func rejectsUntrustedAndUnresolvableLinks() throws {
        #expect(ChatMapDestination(url: try #require(URL(string: "https://google.com.evil.invalid/maps?q=Paris")), title: "") == nil)
        #expect(ChatMapDestination(url: try #require(URL(string: "https://www.google.com/search?q=Paris")), title: "") == nil)
        #expect(ChatMapDestination(url: try #require(URL(string: "https://www.google.com/maps?q=place_id:abc")), title: "") == nil)
        #expect(ChatMapDestination.parse("Visit Paris tomorrow.").isEmpty)
    }
}

struct PipContactTests {
    @Test func digitRunsBecomeDialableButOrdinaryProseDoesNot() throws {
        let text = PipContactLinks.digitText("Call eight five eight five five five one two one two. Take one or two walks.")
        #expect(text == "Call 8585551212. Take one or two walks.")
        #expect(PipContactLinks.phoneURL("+1 (858) 555-1212")?.absoluteString == "tel:+18585551212")
        #expect(PipContactLinks.phoneURL("*21*18585551212#") == nil)
        #expect(PipContactLinks.phoneURL("18585551212,999") == nil)
        let block = ChatMarkdownBlock(id: 0, kind: .paragraph, text: "Call +1 (858) 555-1212 or https://example.com")
        #expect(block.attributed.runs.contains { $0.link?.scheme == "tel" })
        #expect(block.attributed.runs.contains { $0.link?.host == "example.com" })
        #expect(!PipContactLinks.allowed(try #require(URL(string: "pippipgo://auth/logout"))))
    }
    @Test func photoPreviewRequiresProviderURLAndIsBounded() {
        #expect(PipPhotoLink.validURL("https://googleusercontent.com.evil.invalid/a") == nil)
        #expect(PipPhotoLink.validURL("http://lh3.googleusercontent.com/a") == nil)
        #expect(PipPhotoLink.parse("![Cafe — A](https://lh3.googleusercontent.com/a) ![Cafe again](https://lh3.googleusercontent.com/a)").count == 1)
    }
}
