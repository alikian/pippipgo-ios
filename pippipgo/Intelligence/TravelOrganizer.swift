import MapKit
import EventKit
import EventKitUI
import UniformTypeIdentifiers
import SwiftUI
import Observation

struct OrganizerPerson: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var age: Int? = nil
    var hometown = ""
    var interests = ""
    var notes = ""
}
struct OrganizerStop: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var destination = ""
    var arrival: String? = nil
    var departure: String? = nil
    var hotel = ""
    var hotel_address = ""
    var check_in: String? = nil
    var check_out: String? = nil
    // Travel from the preceding stop to this destination.
    var transport = ""
    var transport_details = ""
}
struct OrganizerParty: Codable, Equatable, Sendable {
    var adults: Int
    var children: Int
    var total: Int { adults + children }
    // Only recover explicitly labeled counts from older chat drafts, never infer from names.
    static func legacyNotes(_ notes: String) -> OrganizerParty? {
        let pattern = #"(?i)^Travelers: (\d+) adults? and (one|\d+) (\d+)-year-old(?:;|[ .])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: notes, range: NSRange(notes.startIndex..., in: notes)),
              let adultsRange = Range(match.range(at: 1), in: notes),
              let countRange = Range(match.range(at: 2), in: notes),
              let ageRange = Range(match.range(at: 3), in: notes),
              let adults = Int(notes[adultsRange]), let age = Int(notes[ageRange]), age < 18,
              let children = notes[countRange].lowercased() == "one" ? 1 : Int(notes[countRange]),
              adults + children > 0, adults + children <= 30 else { return nil }
        return OrganizerParty(adults: adults, children: children)
    }
}
struct OrganizerTrip: Codable, Equatable, Identifiable, Sendable {
    var party: OrganizerParty? = nil
    var budget: OrganizerBudget? = nil
    var id = UUID()
    var name = ""
    var include_me = true
    var companion_ids: [UUID] = []
    var stops: [OrganizerStop] = []
    var notes = ""
}
// Navigation transitions can keep a child alive after its stop is removed or reordered.
// Resolve by identity on every access; a stale child must never edit a different stop.
extension Binding where Value == OrganizerTrip {
    func stop(_ snapshot: OrganizerStop) -> Binding<OrganizerStop> {
        Binding<OrganizerStop>(
            get: { wrappedValue.stops.first { $0.id == snapshot.id } ?? snapshot },
            set: { updated in
                guard let index = wrappedValue.stops.firstIndex(where: { $0.id == snapshot.id }) else { return }
                wrappedValue.stops[index] = updated
            }
        )
    }
}

struct OrganizerData: Codable, Equatable, Sendable {
    var profile: OrganizerPerson? = nil
    var companions: [OrganizerPerson] = []
    var trips: [OrganizerTrip] = []
}

@MainActor @Observable
final class OrganizerStore {
    var data = OrganizerData()
    var version = 0
    var loaded = false
    var busy = false
    var error: String?
    var conflict: APIRecord<OrganizerData>?
    private(set) var pending: APIRequest<APIRecord<OrganizerData>>?
    private var epoch = UUID()
    private let client: APIClient
    private let authentication: any AccessTokenProviding
    init(client: APIClient, authentication: any AccessTokenProviding) {
        self.client = client; self.authentication = authentication
    }
    func reset() {
        epoch = UUID(); data = OrganizerData(); version = 0; loaded = false
        busy = false; error = nil; conflict = nil; pending = nil
    }
    func load() async {
        guard !busy, pending == nil else { return }
        busy = true; let ticket = epoch
        defer { if ticket == epoch { busy = false } }
        do {
            let result: APIRecord<OrganizerData> = try await client.send(.get(.organizer), using: authentication)
            guard ticket == epoch else { return }
            data = result.data; version = result.version; loaded = true; error = nil
        } catch { if ticket == epoch { self.error = error.localizedDescription } }
    }
    func save(_ draft: OrganizerData) async -> Bool {
        guard loaded, !busy, pending == nil else { return false }
        do { pending = try .put(.organizer, body: draft, expectedVersion: version) }
        catch { self.error = error.localizedDescription; return false }
        return await retry()
    }
    func retry() async -> Bool {
        guard !busy, conflict == nil, let request = pending else { return false }
        busy = true; let ticket = epoch
        defer { if ticket == epoch { busy = false } }
        do {
            _ = try await client.send(request, using: authentication)
            guard ticket == epoch else { return false }
            let current: APIRecord<OrganizerData> = try await client.send(.get(.organizer), using: authentication)
            guard ticket == epoch else { return false }
            data = current.data; version = current.version; pending = nil; error = nil
            return true
        } catch APIClientError.conflict(let body, _) {
            guard ticket == epoch else { return false }
            if let record = body.currentRecord, let decoded = try? record.data.decoded(as: OrganizerData.self) {
                conflict = APIRecord(id: record.id, kind: record.kind, version: record.version, revision: record.revision, updatedAt: record.updatedAt, deleted: record.deleted, data: decoded)
            }
            error = body.message
        } catch APIClientError.rejected(let status, let body, _) {
            guard ticket == epoch else { return false }
            error = body.message
            if [400, 403, 404, 413, 422].contains(status) { pending = nil }
        } catch { if ticket == epoch { self.error = error.localizedDescription } }
        return false
    }
    func useLatest() {
        guard let conflict else { return }
        data = conflict.data; version = conflict.version; self.conflict = nil; pending = nil; error = nil
    }
}

enum AppTab: String, Hashable { case trips, pip, translate, profile }
enum PipMode: String, Hashable { case chat, voice }

/// Signed-in shell: one tab per top-level destination. Editors are modal tasks owned here so
/// every tab presents the same sheet and Siri voice launches know when a sheet is open.
struct TravelOrganizerView: View {
    @Bindable var store: OrganizerStore
    let chat: TravelChatStore
    var profilePictureURL: URL? = nil
    let signOut: () -> Void
    @State private var tab = AppTab.pip
    @State private var pipMode = PipMode.voice
    @State private var editor: OrganizerEditorKind?
    @State private var reviewingTrip: OrganizerTrip?
    @State private var voiceStartRequest: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $tab) {
            TripsTab(store: store, editor: $editor, askPip: { pipMode = .chat; tab = .pip })
                .tabItem { Label("Trips", systemImage: "suitcase") }
                .tag(AppTab.trips)
            PipTab(chat: chat, organizer: store, mode: $pipMode, reviewingTrip: $reviewingTrip, voiceStartRequest: $voiceStartRequest, planTrip: { editor = .trip(UUID()) }, openTranslation: { tab = .translate }, isVisible: tab == .pip && editor == nil && reviewingTrip == nil)
                .tabItem { Label("Pip", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.pip)
            TranslateTab(store: chat.translator)
                .tabItem { Label("Translate", systemImage: "translate") }
                .tag(AppTab.translate)
            ProfileTab(store: store, chat: chat, location: chat.locationDisplay, profilePictureURL: profilePictureURL, editor: $editor, signOut: signOut)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .tint(.blue)
        .toolbarBackground(PipAppearance.cream, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .task { if !store.loaded { await store.load() } }
        .sheet(item: $editor) { kind in OrganizerEditor(store: store, kind: kind) }
        .onChange(of: TalkToPipLaunch.shared.requestID, initial: true) { _, _ in handleVoiceLaunch() }
        .onChange(of: scenePhase) { _, _ in handleVoiceLaunch() }
        .onChange(of: editor?.id) { _, _ in handleVoiceLaunch() }
        .onChange(of: reviewingTrip?.id) { _, _ in handleVoiceLaunch() }
        .onChange(of: chat.busy) { _, _ in handleVoiceLaunch() }
        .onChange(of: chat.pending == nil) { _, _ in handleVoiceLaunch() }
        .onChange(of: chat.translator.active) { _, _ in handleVoiceLaunch() }
        // The microphone is only ever live while the Talk to Pip page is on screen.
        .onChange(of: chat.voice.active) { _, active in
            if active && !(tab == .pip && pipMode == .voice) { chat.voice.stop(clearCaptions: true) }
        }
    }
    private func handleVoiceLaunch() {
        guard let request = TalkToPipLaunch.shared.take(
            isActive: scenePhase == .active,
            blocked: editor != nil || reviewingTrip != nil || chat.busy || chat.pending != nil || chat.translator.active
        ) else { return }
        pipMode = .voice
        tab = .pip
        voiceStartRequest = request
    }
}

// MARK: - Trips

enum OrganizerDay {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return formatter.date(from: value)
    }
}
extension OrganizerTrip {
    /// Earliest and latest saved day across all stops; nil until any date is entered.
    var days: (start: Date, end: Date)? {
        let all = stops.flatMap { [$0.arrival, $0.departure, $0.check_in, $0.check_out] }.compactMap { OrganizerDay.date($0) }
        guard let start = all.min(), let end = all.max() else { return nil }
        return (start, end)
    }
}
/// Uses the environment locale, so dates follow the selected app language.
struct OrganizerDateRange: View {
    let start: Date?
    let end: Date?
    private static let style = Date.FormatStyle().month(.abbreviated).day()
    var body: some View {
        HStack(spacing: 4) {
            if let start { Text(start, format: Self.style) }
            if let start, let end, start != end { Text(verbatim: "–") }
            if let end, end != start { Text(end, format: Self.style) }
        }
    }
}

struct TripsTab: View {
    @Environment(\.locale) private var locale
    @Bindable var store: OrganizerStore
    @Binding var editor: OrganizerEditorKind?
    let askPip: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        if !store.loaded { Button("Try again") { Task { await store.load() } } }
                    }
                }
                if store.loaded {
                    ForEach(store.data.trips) { trip in
                        NavigationLink(value: trip.id) { TripRow(trip: trip) }
                    }
                }
            }
            // List uses cached UIKit cells. Recreate its presentation on locale changes
            // so an RTL -> LTR switch cannot retain mirrored row transforms.
            .id(locale.identifier)
            .overlay {
                if !store.loaded {
                    if store.busy { ProgressView() }
                } else if store.data.trips.isEmpty && store.error == nil {
                    ContentUnavailableView {
                        Label("No trips yet", systemImage: "suitcase")
                    } description: {
                        Text("Add a trip yourself, or ask Pip to plan one with you.")
                    } actions: {
                        Button("Add trip") { editor = .trip(UUID()) }.buttonStyle(.borderedProminent)
                        Button("Ask Pip", action: askPip)
                    }
                }
            }
            .refreshable { await store.load() }
            .navigationTitle("Trips")
            .navigationDestination(for: UUID.self) { id in
                TripDetailView(store: store, tripID: id, editor: $editor)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add trip", systemImage: "plus") { editor = .trip(UUID()) }
                        .disabled(!store.loaded)
                }
            }
        }
    }
}

struct TripRow: View {
    let trip: OrganizerTrip
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: trip.name).font(.headline)
            Group {
                if trip.stops.isEmpty { Text("Add destinations when you're ready") }
                else { Text(verbatim: trip.stops.map(\.destination).joined(separator: " → ")) }
            }
            .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            if let days = trip.days {
                OrganizerDateRange(start: days.start, end: days.end)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// Read-only overview. Editing stays a modal draft with explicit Save, so versioned saves,
/// retries and conflict review are unchanged.
struct TripDetailView: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: OrganizerStore
    let tripID: UUID
    @Binding var editor: OrganizerEditorKind?
    private var trip: OrganizerTrip? { store.data.trips.first { $0.id == tripID } }

    var body: some View {
        List {
            if let trip {
                Section("Destinations · in travel order") {
                    if trip.stops.isEmpty {
                        Text("Add destinations when you're ready").foregroundStyle(.secondary)
                    }
                    ForEach(Array(trip.stops.enumerated()), id: \.element.id) { index, stop in
                        TripStopSummary(stop: stop, previous: index > 0 ? trip.stops[index - 1].destination : nil)
                    }
                }
                travelers(trip)
                if let budget = trip.budget {
                    Section("Budget & costs") {
                        if let total = OrganizerBudget.amount(budget.total) {
                            LabeledContent("Total budget", value: budget.formatted(total))
                        }
                        LabeledContent("Estimated total", value: budget.formatted(budget.estimatedTotal))
                        LabeledContent("Actual spent", value: budget.formatted(budget.actualTotal))
                        if let remaining = budget.remaining {
                            LabeledContent(remaining < 0 ? "Over budget" : "Remaining budget", value: budget.formatted(abs(remaining)))
                                .foregroundStyle(remaining < 0 ? Color.red : Color.primary)
                        }
                    }
                }
                if !trip.notes.isEmpty {
                    Section("Trip notes") { Text(verbatim: trip.notes).textSelection(.enabled) }
                }
            }
        }
        .id(locale.identifier)
        .navigationTitle(trip?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editor = .trip(tripID) }.disabled(trip == nil)
            }
        }
        // Deleted here or on another device: return to the list instead of showing an empty page.
        .onChange(of: trip == nil) { _, missing in if missing { dismiss() } }
    }

    @ViewBuilder private func travelers(_ trip: OrganizerTrip) -> some View {
        let companions = store.data.companions.filter { trip.companion_ids.contains($0.id) }
        if trip.party != nil || trip.include_me || !companions.isEmpty {
            Section("Who is traveling?") {
                if let party = trip.party {
                    Text("\(party.adults) adults · \(party.children) children · \(party.total) travelers total")
                }
                if trip.include_me {
                    Label { Text("Me") } icon: { Image(systemName: "person.fill") }
                }
                ForEach(companions) { companion in
                    Label { Text(verbatim: companion.name) } icon: { Image(systemName: "person") }
                }
            }
        }
    }
}

struct TripStopSummary: View {
    let stop: OrganizerStop
    let previous: String?
    private var transport: (name: String, icon: String)? {
        switch stop.transport {
        case "plane": return ("Plane", "airplane")
        case "train": return ("Train", "tram")
        case "car": return ("Car", "car")
        default: return nil
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Group {
                    if stop.destination.isEmpty { Text("New destination") }
                    else { Text(verbatim: stop.destination) }
                }
                .font(.headline)
                Spacer()
                OrganizerDateRange(start: OrganizerDay.date(stop.arrival), end: OrganizerDay.date(stop.departure))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if transport != nil || !stop.transport_details.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        if let transport { Text(LocalizedStringKey(transport.name)) }
                        if !stop.transport_details.isEmpty {
                            Text(verbatim: stop.transport_details).foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: transport?.icon ?? "arrow.triangle.turn.up.right.diamond")
                }
                .font(.subheadline)
            }
            if !stop.hotel.isEmpty {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: stop.hotel)
                        if !stop.hotel_address.isEmpty {
                            Text(verbatim: stop.hotel_address).foregroundStyle(.secondary)
                        }
                        OrganizerDateRange(start: OrganizerDay.date(stop.check_in), end: OrganizerDay.date(stop.check_out))
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "bed.double")
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pip

enum PipAppearance {
    static let cream = Color(red: 250 / 255, green: 248 / 255, blue: 243 / 255)
    static let navy = Color(red: 7 / 255, green: 29 / 255, blue: 61 / 255)
    static let secondary = Color(red: 94 / 255, green: 112 / 255, blue: 135 / 255)
}

/// One signed-in conversation surface, backed by the existing text and voice stores.
struct PipTab: View {
    @Bindable var chat: TravelChatStore
    @Bindable var organizer: OrganizerStore
    @Binding var mode: PipMode
    @Binding var reviewingTrip: OrganizerTrip?
    @Binding var voiceStartRequest: UUID?
    let planTrip: () -> Void
    let openTranslation: () -> Void
    var isVisible = true
    @State private var showingHistory = false
    @State private var editingText = false
    @State private var hasOpenedVoice = false
    @State private var lastVoiceEntry: Date?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if !editingText {
                        PipCompanionHero(compact: hasConversation, availableHeight: geometry.size.height)
                            .padding(.horizontal, 24)
                    }
                    if mode == .voice {
                        LiveVoiceView(store: chat.voice, showsControls: false, companionStyle: true)
                    } else {
                        TravelChatView(store: chat, organizer: organizer, reviewingTrip: $reviewingTrip,
                                       name: organizer.data.profile?.name, showsComposer: false, companionStyle: true)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(PipAppearance.cream.ignoresSafeArea())
            .preferredColorScheme(.light)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    PipComposer(store: chat, beginTyping: {
                        mode = .chat
                    }, editingChanged: { editingText = $0 }, companionStyle: true) {
                        editingText = false
                        mode = .voice
                        hasOpenedVoice = true
                        lastVoiceEntry = Date()
                        chat.voice.start()
                    }
                    if !editingText {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                suggestion("Plan a trip", icon: "suitcase", action: planTrip)
                                suggestion("Translate for me", icon: "translate", action: openTranslation)
                                suggestion("Find something fun nearby", icon: "sparkles") {
                                    mode = .chat
                                    chat.composer = "Find something fun nearby"
                                }
                                .disabled(chat.busy || chat.pending != nil || chat.translator.active || !chat.composer.isEmpty)
                            }.padding(.horizontal, 16)
                        }
                        .padding(.bottom, 12)
                    }
                }.background(PipAppearance.cream)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("PipPipGo").font(.subheadline.weight(.semibold)).fixedSize().foregroundStyle(PipAppearance.navy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingHistory = true } label: { Image(systemName: "clock.arrow.circlepath") }
                        .accessibilityLabel("Conversation history")
                        .accessibilityIdentifier("pip.history")
                }
            }
            .toolbarBackground(PipAppearance.cream, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingHistory) {
                NavigationStack {
                    TravelChatView(store: chat, organizer: organizer, reviewingTrip: $reviewingTrip,
                                   showsComposer: false, fullHistory: true)
                        .navigationTitle("Conversations")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingHistory = false } } }
                }
            }
            .onChange(of: chat.voice.active) { _, active in
                if !active && mode == .voice {
                    Task { await chat.loadGuide(refresh: true) }
                }
            }
            .onChange(of: chat.busy) { _, busy in if !busy { startWelcomeIfDue() } }
            .onChange(of: scenePhase, initial: true) { _, _ in startRequestedConversation() }
            .onChange(of: voiceStartRequest) { _, _ in startRequestedConversation() }
            .onChange(of: mode) { _, selected in
                if selected == .voice, isVisible, scenePhase == .active {
                    hasOpenedVoice = true
                    chat.voice.start()
                } else if selected == .chat { chat.voice.stop() }
            }
            .onChange(of: chat.composer) { _, text in
                if !text.isEmpty { mode = .chat }
            }
            .task(id: isVisible && scenePhase == .active) {
                guard isVisible, scenePhase == .active else { return }
                await chat.loadGuide()
                guard !Task.isCancelled, isVisible, scenePhase == .active else { return }
                startWelcomeIfDue()
                await chat.loadGuide(refresh: true)
            }
        }
    }

    private func startWelcomeIfDue() {
        guard isVisible, scenePhase == .active, chat.loaded,
              !chat.voice.active, !chat.translator.active, !editingText,
              (mode == .voice && !hasOpenedVoice) || chat.guide?.welcome_due == true,
              chat.pending == nil, !chat.busy, chat.composer.isEmpty,
              lastVoiceEntry.map({ Date().timeIntervalSince($0) >= 1800 }) ?? true else { return }
        lastVoiceEntry = Date()
        hasOpenedVoice = true
        mode = .voice
        chat.beginVisit()
        chat.voice.start()
    }

    private var hasConversation: Bool {
        mode == .voice ? !chat.voice.transcript.messages.isEmpty : !chat.visibleMessages.isEmpty
    }

    private func suggestion(_ title: LocalizedStringKey, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.caption.weight(.medium)).padding(.horizontal, 12).padding(.vertical, 10) }
            .buttonStyle(.plain)
            .foregroundStyle(PipAppearance.navy)
            .background(.white.opacity(0.8), in: Capsule())
            .frame(minHeight: 44)
    }

    private func startRequestedConversation() {
        guard scenePhase == .active, voiceStartRequest != nil else { return }
        voiceStartRequest = nil
        lastVoiceEntry = Date()
        hasOpenedVoice = true
        mode = .voice
        chat.voice.start()
    }
}

/// Shared approved artwork, framed in the UI without changing the source image.
private struct PipCompanionHero: View {
    var compact: Bool
    var availableHeight: CGFloat
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: compact ? 4 : 10) {
            PipWelcomeArtwork()
                .frame(width: imageWidth, height: imageWidth * 700 / 851)
                .clipShape(RoundedRectangle(cornerRadius: 32))
            Text("Hi, I’m Pip.")
                .font(compact ? .title3.weight(.semibold) : .largeTitle.weight(.semibold))
                .foregroundStyle(PipAppearance.navy)
            if !compact {
                Text("Where are we going today?")
                    .font(.title3).foregroundStyle(PipAppearance.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .accessibilityElement(children: .combine)
        .padding(.top, compact ? 4 : 12)
        .padding(.bottom, 8)
    }

    private var imageWidth: CGFloat {
        if typeSize.isAccessibilitySize { return compact ? 60 : 100 }
        return compact ? 100 : min(300, max(130, availableHeight * 0.56))
    }
}

// MARK: - Profile

struct ProfileTab: View {
    @Environment(\.locale) private var locale
    @Bindable var store: OrganizerStore
    @Bindable var chat: TravelChatStore
    let location: CurrentLocationStore
    var profilePictureURL: URL? = nil
    @Binding var editor: OrganizerEditorKind?
    let signOut: () -> Void
    @State private var confirmSignOut = false
    @State private var travelStyle = false
    @State private var booking = false
    @State private var calendars = false
    @AppStorage("pip.waitingHum") private var waitingHum = true

    var body: some View {
        NavigationStack {
            List {
                if let error = store.error, !store.loaded {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Try again") { Task { await store.load() } }
                    }
                }
                if store.loaded {
                    Section {
                        Button { editor = .profile } label: {
                            HStack(spacing: 14) {
                                AsyncImage(url: profilePictureURL) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { Image(systemName: "person.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.secondary) }
                                }
                                .frame(width: 60, height: 60)
                                .clipShape(Circle())
                                .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 4) {
                                    Group {
                                        if let name = store.data.profile?.name, !name.isEmpty { Text(verbatim: name) }
                                        else { Text("Add your profile") }
                                    }
                                    .font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                    if let hometown = store.data.profile?.hometown, !hometown.isEmpty {
                                        Text(verbatim: hometown).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                    Section("Travel companions") {
                        ForEach(store.data.companions) { companion in
                            Button { editor = .person(companion.id) } label: {
                                HStack {
                                    Text(verbatim: companion.name).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "chevron.forward").font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Button("Add companion", systemImage: "person.badge.plus") { editor = .person(UUID()) }
                    }
                } else if store.busy {
                    ProgressView()
                }
                Section("Make the most of Pip") {
                    Text("Help Pip learn how you like to travel for ideas that feel like you.").font(.footnote)
                    Toggle("Pip’s waiting hum", isOn: $waitingHum)
                    Button("Travel style & Pip’s voice", systemImage: "slider.horizontal.3") { travelStyle = true }
                    Button("Plan a trip", systemImage: "suitcase") { editor = .trip(UUID()) }
                    Button("Upload a booking receipt", systemImage: "doc.badge.plus") { booking = true }
                    Button("Calendars", systemImage: "calendar") { calendars = true }
                }
                GuidePreferencesSection(store: chat)
                Section {
                    ConversationLocationView(store: location).buttonStyle(.borderless)
                }
                Section {
                    Button("Sign out", role: .destructive) { confirmSignOut = true }
                }
                Section {
                    AppVersionView()
                }
            }
            .id(locale.identifier)
            .refreshable { await store.load() }
            .navigationTitle("Profile")
            .sheet(isPresented: $travelStyle) { GuideSetupView(store: chat.setup) }
            .sheet(isPresented: $booking) { GuideBookingView(setup: chat.setup, organizer: store) }
            .sheet(isPresented: $calendars) { GuideCalendarView() }
            .task { await chat.loadGuide(refresh: true) }
            .toolbar {
                // Stays outside the list so switching language never rebuilds its own menu.
                ToolbarItem(placement: .topBarTrailing) { AppLanguageMenu() }
            }
            .confirmationDialog("Sign out of PipPipGo?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive, action: signOut)
            }
        }
    }
}
enum OrganizerEditorKind: Identifiable {
    case profile, person(UUID), trip(UUID)
    var id: String {
        switch self { case .profile: "profile"; case .person(let id): "person-\(id)"; case .trip(let id): "trip-\(id)" }
    }
}
struct OrganizerEditor: View {
    @Bindable var store: OrganizerStore
    let kind: OrganizerEditorKind
    @Environment(\.dismiss) private var dismiss
    @State private var person = OrganizerPerson()
    @State private var trip = OrganizerTrip()
    private let initialTrip: OrganizerTrip?
    private let onSaved: (UUID) -> Void
    @State private var companionEditor: OrganizerEditorKind?
    @State private var editingStop: OrganizerStop?
    @State private var confirmDelete = false
    init(store: OrganizerStore, kind: OrganizerEditorKind, initialTrip: OrganizerTrip? = nil, onSaved: @escaping (UUID) -> Void = { _ in }) {
        self.store = store
        self.kind = kind
        self.initialTrip = initialTrip
        self.onSaved = onSaved
        // State is initialized once for this sheet, not whenever the parent reappears.
        switch kind {
        case .profile:
            _person = State(initialValue: store.data.profile ?? OrganizerPerson())
        case .person(let id):
            _person = State(initialValue: store.data.companions.first { $0.id == id } ?? OrganizerPerson(id: id))
        case .trip(let id):
            var draft = store.data.trips.first { $0.id == id } ?? initialTrip ?? OrganizerTrip(id: id)
            if draft.party == nil { draft.party = OrganizerParty.legacyNotes(draft.notes) }
            _trip = State(initialValue: draft)
        }
    }
    private var isTrip: Bool { if case .trip = kind { true } else { false } }
    private var isProfile: Bool { if case .profile = kind { true } else { false } }
    private var exists: Bool {
        isTrip ? store.data.trips.contains { $0.id == trip.id } : !isProfile && store.data.companions.contains { $0.id == person.id }
    }
    var body: some View {
        NavigationStack {
            Form {
                Group {
                    if isTrip { tripFields } else { personFields }
                    if exists { Button("Delete", role: .destructive) { confirmDelete = true } }
                }.disabled(store.busy || store.pending != nil)
                if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
                if let conflict = store.conflict {
                    Section("Review changes from another device") {
                        Text("Your edit has not overwritten the saved version. Reload the latest version to review and edit it.")
                        Text("Saved trips: \(conflict.data.trips.map(\.name).joined(separator: ", "))")
                        Button("Discard this edit and load latest") { store.useLatest(); loadDraft() }
                    }
                } else if store.pending != nil {
                    Button("Retry same save") { Task { if await store.retry() { onSaved(isTrip ? trip.id : person.id); dismiss() } } }.disabled(store.busy)
                }
            }
            .navigationDestination(item: $editingStop) { stop in
                OrganizerStopEditor(stop: $trip.stop(stop), previous: previousStop(stop.id))
            }
            .navigationTitle(LocalizedStringKey(isTrip ? "Trip" : isProfile ? "My Profile" : "Companion"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(store.pending != nil || store.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save(deleting: false) } }
                        .disabled(store.busy || store.pending != nil || (isTrip ? trip.name : person.name).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(item: $companionEditor) { kind in
                OrganizerEditor(store: store, kind: kind) { id in
                    if isTrip, store.data.companions.contains(where: { $0.id == id }), !trip.companion_ids.contains(id) {
                        trip.companion_ids.append(id)
                    }
                }
            }
            .interactiveDismissDisabled(store.pending != nil || store.busy)
            .confirmationDialog(LocalizedStringKey(isTrip ? "Delete this trip?" : "Delete this companion?"), isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await save(deleting: true) } }
            }
        }
    }
    private var personFields: some View {
        Group {
            Section("Details") {
                TextField("Name", text: $person.name)
                TextField("Age (optional)", value: $person.age, format: .number).keyboardType(.numberPad)
                TextField("Home town", text: $person.hometown)
            }
            Section("Optional") {
                TextField("Interests", text: $person.interests, axis: .vertical)
                TextField("Important notes, dietary or accessibility needs", text: $person.notes, axis: .vertical)
            }
        }
    }
    private var tripFields: some View {
        Group {
            Section { TextField("Trip name", text: $trip.name) }
            Section("Who is traveling?") {
                if let party = trip.party {
                    Text("\(party.adults) adults · \(party.children) children · \(party.total) travelers total").font(.headline)
                    Stepper("Adults: \(party.adults)", value: Binding(get: { trip.party?.adults ?? 0 }, set: { trip.party?.adults = $0 }), in: 0...30)
                    Stepper("Children: \(party.children)", value: Binding(get: { trip.party?.children ?? 0 }, set: { trip.party?.children = $0 }), in: 0...30)
                    let unnamed = max(0, party.total - trip.companion_ids.count - (trip.include_me ? 1 : 0))
                    if unnamed > 0 { Text("\(unnamed) travelers without names assigned").foregroundStyle(.secondary) }
                    Text("Party size includes you and everyone selected below. Names are optional; selecting someone does not add to the total.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Button("Set party size") { trip.party = OrganizerParty(adults: max(1, trip.companion_ids.count + (trip.include_me ? 1 : 0)), children: 0) }
                }
                Toggle("Me", isOn: $trip.include_me)
                ForEach(store.data.companions) { companion in
                    Toggle(companion.name, isOn: Binding(get: { trip.companion_ids.contains(companion.id) }, set: { selected in
                        trip.companion_ids.removeAll { $0 == companion.id }
                        if selected { trip.companion_ids.append(companion.id) }
                    }))
                }
                Button("Add someone", systemImage: "person.badge.plus") { companionEditor = .person(UUID()) }
            }
            Section("Destinations · in travel order") {
                ForEach(trip.stops) { stop in
                    HStack(spacing: 8) {
                        Button { editingStop = stop } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Group {
                                        if stop.destination.isEmpty { Text("New destination") }
                                        else { Text(verbatim: stop.destination) }
                                    }
                                    if !stop.hotel.isEmpty { Text(stop.hotel).font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            trip.stops.removeAll { $0.id == stop.id }
                        }
                    }
                    .contextMenu {
                        Button("Move earlier", systemImage: "arrow.up") { moveStop(stop.id, by: -1) }
                            .disabled(trip.stops.first?.id == stop.id)
                        Button("Move later", systemImage: "arrow.down") { moveStop(stop.id, by: 1) }
                            .disabled(trip.stops.last?.id == stop.id)
                    }
                }
                Button("Add destination", systemImage: "plus") {
                    let stop = OrganizerStop()
                    trip.stops.append(stop)
                    editingStop = stop
                }
                Text("Travel details belong to the destination you're arriving at. Review them after reordering stops.").font(.caption).foregroundStyle(.secondary)
            }
            Section {
                NavigationLink {
                    OrganizerBudgetView(budget: Binding(get: { trip.budget ?? OrganizerBudget() }, set: { trip.budget = $0 }))
                } label: {
                    HStack {
                        Label("Budget & costs", systemImage: "creditcard")
                        Spacer()
                        if let budget = trip.budget, let total = OrganizerBudget.amount(budget.total) {
                            Text(budget.formatted(total)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section { TextField("Trip notes", text: $trip.notes, axis: .vertical) }
        }
    }
    private func moveStop(_ id: UUID, by offset: Int) {
        guard let index = trip.stops.firstIndex(where: { $0.id == id }),
              trip.stops.indices.contains(index + offset) else { return }
        trip.stops.swapAt(index, index + offset)
    }
    private func previousStop(_ id: UUID) -> String? {
        guard let index = trip.stops.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return trip.stops[index - 1].destination
    }
    private func loadDraft() {
        switch kind {
        case .profile: person = store.data.profile ?? OrganizerPerson()
        case .person(let id): person = store.data.companions.first { $0.id == id } ?? OrganizerPerson(id: id)
        case .trip(let id): trip = store.data.trips.first { $0.id == id } ?? initialTrip ?? OrganizerTrip(id: id)
        }
    }
    private func save(deleting: Bool) async {
        if !deleting, isTrip, let party = trip.party,
           (party.total < 1 || party.total > 30 || trip.companion_ids.count + (trip.include_me ? 1 : 0) > party.total) {
            store.error = "Check the party size: use 1–30 travelers, with enough places for everyone selected."; return
        }
        if !deleting, isTrip, let budget = trip.budget, !budget.isValid {
            store.error = "Check Budget & costs: enter positive numbers or zero, with up to two decimal places (whole amounts for JPY)."; return
        }
        var draft = store.data
        switch kind {
        case .profile: draft.profile = person
        case .person:
            if deleting && draft.trips.contains(where: { $0.companion_ids.contains(person.id) }) {
                store.error = "Remove this companion from their trips before deleting them."; return
            }
            draft.companions.removeAll { $0.id == person.id }
            if !deleting { draft.companions.append(person) }
        case .trip:
            draft.trips.removeAll { $0.id == trip.id }
            if !deleting { draft.trips.append(trip) }
        }
        if await store.save(draft) { onSaved(isTrip ? trip.id : person.id); dismiss() }
    }
}
struct OrganizerStopEditor: View {
    @Binding var stop: OrganizerStop
    var previous: String?
    var body: some View {
        Form {
            Section("Destination") {
                TextField("City or destination", text: $stop.destination)
                OptionalOrganizerDate(title: "Arrival", value: $stop.arrival)
                OptionalOrganizerDate(title: "Departure", value: $stop.departure)
            }
            Section("Hotel stay (optional)") {
                TextField("Hotel name", text: $stop.hotel)
                TextField("Address", text: $stop.hotel_address, axis: .vertical)
                OptionalOrganizerDate(title: "Check-in", value: $stop.check_in)
                OptionalOrganizerDate(title: "Check-out", value: $stop.check_out)
            }
            Section {
                Picker("Transport", selection: $stop.transport) {
                    Text("Not decided").tag(""); Text("Plane").tag("plane")
                    Text("Train").tag("train"); Text("Car").tag("car")
                }
                TextField("Flight/train number, departure time or driving notes", text: $stop.transport_details, axis: .vertical)
            } header: {
                if let previous { Text("Travel from \(previous)") }
                else { Text("Travel to first destination (optional)") }
            }
        }.navigationTitle("Destination")
    }
}
struct OptionalOrganizerDate: View {
    let title: String
    @Binding var value: String?
    private static var formatter: DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }
    var body: some View {
        Toggle(LocalizedStringKey(title), isOn: Binding(get: { value != nil }, set: { value = $0 ? Self.formatter.string(from: Date()) : nil }))
        if value != nil {
            DatePicker(LocalizedStringKey(title), selection: Binding(get: { Self.formatter.date(from: value ?? "") ?? Date() }, set: { value = Self.formatter.string(from: $0) }), displayedComponents: .date)
        }
    }
}

struct TravelChatMessage: Codable, Identifiable, Sendable {
    var id: String
    var role: String
    var text: String
    var trip_draft: OrganizerTrip? = nil
    var at: String? = nil
}
struct TravelChatData: Codable, Sendable { var messages: [TravelChatMessage] = [] }
struct TravelChatRequest: Codable, Sendable {
    var text: String
    var new_conversation = false
    var conversation_context: ConversationContext = .snapshot()
}

@MainActor @Observable
final class TravelChatStore {
    let setup: GuideSetupStore
    let voice: LiveVoiceStore
    /// Two-way interpreter; shares no traveler context with the backend session.
    let translator: LiveVoiceStore
    let locationDisplay: CurrentLocationStore
    var messages: [TravelChatMessage] = []
    var guide: GuideData?
    var guideError: String?
    var refreshingGuide = false
    var pendingGuideEdit: APIRequest<GuideData>?
    var guideEditConflict = false
    private var displaySince = Date()
    var visibleMessages: [TravelChatMessage] {
        messages.filter { message in
            guard let value = message.at, let date = GuideData.date(value) else { return false }
            return date >= displaySince
        }
    }
    var composer = ""
    var version = 0
    var loaded = false
    var busy = false
    var error: String?
    var conflict: APIRecord<TravelChatData>?
    private(set) var pending: APIRequest<APIRecord<TravelChatData>>?
    private var epoch = UUID()
    private let client: APIClient
    private let authentication: any AccessTokenProviding
    private(set) var conversationContext: ConversationContext?
    private(set) var capturingLocation = false
    private let captureContext: @MainActor () async -> ConversationContext
    init(client: APIClient, authentication: any AccessTokenProviding, captureContext: @escaping @MainActor () async -> ConversationContext = { await ConversationContext.capture() }) {
        self.setup = GuideSetupStore(client: client, authentication: authentication)
        self.captureContext = captureContext
        self.client = client; self.authentication = authentication
        let display = CurrentLocationStore(capture: captureContext)
        self.locationDisplay = display
        self.voice = LiveVoiceStore(client: client, authentication: authentication, locationDisplay: display)
        self.translator = LiveVoiceStore(client: client, authentication: authentication, mode: .translate(.saved()))
    }
    func reset() {
        setup.reset()
        voice.stop(clearCaptions: true)
        translator.stop(clearCaptions: true)
        locationDisplay.reset()
        conversationContext = nil; capturingLocation = false
        guide = nil; guideError = nil; refreshingGuide = false; pendingGuideEdit = nil; guideEditConflict = false; displaySince = Date()
        epoch = UUID(); messages = []; composer = ""; version = 0; loaded = false
        busy = false; error = nil; conflict = nil; pending = nil
    }
    func load() async {
        guard !busy, pending == nil else { return }
        busy = true; let ticket = epoch
        defer { if ticket == epoch { busy = false } }
        do {
            let result: APIRecord<TravelChatData> = try await client.send(.get(.travelChat), using: authentication)
            guard ticket == epoch else { return }
            messages = result.data.messages; version = result.version; loaded = true; error = nil
            conversationContext = nil
        } catch { if ticket == epoch { self.error = error.localizedDescription } }
    }
    func beginVisit() { displaySince = Date() }
    func loadGuide(refresh: Bool = false) async {
        let startingEpoch = epoch
        while refreshingGuide {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            guard epoch == startingEpoch, !Task.isCancelled else { return }
        }
        guard pendingGuideEdit == nil else { return }
        let ticket = epoch
        refreshingGuide = true
        defer { if ticket == epoch { refreshingGuide = false } }
        do {
            let request: APIRequest<GuideData> = refresh
                ? try .post(.guide, body: [String: String]()) : try .get(.guide)
            let result = try await client.send(request, using: authentication)
            guard ticket == epoch, !Task.isCancelled else { return }
            guide = result
            guideError = result.refresh_pending == true ? "Your recap will update when Pip reconnects." : nil
        } catch { if ticket == epoch { guideError = "Pip couldn't refresh your recap. Your saved information is safe." } }
    }
    func editPreference(_ preference: GuidePreference, text: String, remove: Bool) async {
        guard pendingGuideEdit == nil, !refreshingGuide, let guide else { return }
        do {
            pendingGuideEdit = try .put(.guide, body: GuidePreferenceEdit(id: preference.id, text: text, remove: remove), expectedVersion: guide.version)
            await retryGuideEdit()
        } catch { guideError = error.localizedDescription }
    }
    func retryGuideEdit() async {
        guard !refreshingGuide, !guideEditConflict, let request = pendingGuideEdit else { return }
        let ticket = epoch
        refreshingGuide = true
        defer { if ticket == epoch { refreshingGuide = false } }
        do {
            let result = try await client.send(request, using: authentication)
            guard ticket == epoch else { return }
            guide = result; pendingGuideEdit = nil; guideError = nil
        } catch APIClientError.conflict {
            guard ticket == epoch else { return }
            guideEditConflict = true
            guideError = "Preferences changed elsewhere. Load the latest and review your edit."
        } catch { if ticket == epoch { guideError = error.localizedDescription } }
    }
    func reloadGuideAfterConflict() async {
        pendingGuideEdit = nil; guideEditConflict = false
        await loadGuide()
    }
    func send() async {
        guard loaded, !busy, !voice.active, pending == nil, !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let ticket = epoch
        let text = composer
        busy = true
        let context: ConversationContext
        if let existing = locationDisplay.context, existing.hasFreshLocation() { context = existing }
        else if let existing = conversationContext, existing.hasFreshLocation() { context = existing }
        else {
            capturingLocation = true
            context = await captureContext()
        }
        guard ticket == epoch, !Task.isCancelled else {
            if ticket == epoch { busy = false; capturingLocation = false }
            return
        }
        conversationContext = context
        capturingLocation = false
        busy = false
        do {
            pending = try .put(.travelChat, body: TravelChatRequest(text: text, conversation_context: context), expectedVersion: version)
            await retry()
        } catch { self.error = error.localizedDescription }
    }
    func newConversation() async -> Bool {
        guard loaded, !busy, !voice.active, !translator.active, pending == nil, composer.isEmpty else { return false }
        do {
            pending = try .put(.travelChat, body: TravelChatRequest(text: "", new_conversation: true), expectedVersion: version)
            await retry()
            return pending == nil && error == nil && conflict == nil
        } catch { self.error = error.localizedDescription; return false }
    }
    func retry() async {
        guard !busy, !voice.active, conflict == nil, let request = pending else { return }
        busy = true; let ticket = epoch
        defer { if ticket == epoch { busy = false } }
        do {
            _ = try await client.send(request, using: authentication)
            guard ticket == epoch else { return }
            let current: APIRecord<TravelChatData> = try await client.send(.get(.travelChat), using: authentication)
            guard ticket == epoch else { return }
            messages = current.data.messages; version = current.version; pending = nil; composer = ""; error = nil
            Task { await self.loadGuide(refresh: true) }
        } catch APIClientError.conflict(let body, _) {
            guard ticket == epoch else { return }
            if let record = body.currentRecord, let data = try? record.data.decoded(as: TravelChatData.self) {
                conflict = APIRecord(id: record.id, kind: record.kind, version: record.version, revision: record.revision, updatedAt: record.updatedAt, deleted: record.deleted, data: data)
            }
            error = body.message
        } catch APIClientError.rejected(let status, let body, _) {
            guard ticket == epoch else { return }
            error = body.message
            if [400, 403, 404, 413, 422, 429].contains(status) { pending = nil }
        } catch { if ticket == epoch { self.error = error.localizedDescription } }
    }
    func useLatest() {
        guard let conflict else { return }
        messages = conflict.data.messages; version = conflict.version
        self.conflict = nil; pending = nil; error = nil
    }
}

struct TravelChatView: View {
    @Bindable var store: TravelChatStore
    @Bindable var organizer: OrganizerStore
    @Binding var reviewingTrip: OrganizerTrip?
    @State private var savedTripName: String?
    @FocusState private var composing: Bool
    var name: String? = nil
    var showsComposer = true
    var companionStyle = false
    var fullHistory = false
    private var displayedMessages: [TravelChatMessage] { fullHistory ? store.messages : store.visibleMessages }
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if !companionStyle { GuideRecapView(guide: store.guide) }
                        if displayedMessages.isEmpty && !companionStyle {
                            Text("Open voice to talk with Pip, your friendly local guide, or write a message below.").foregroundStyle(.secondary)
                        }
                        ForEach(displayedMessages) { message in
                            let isUser = message.role == "user"
                            HStack(spacing: 0) {
                                if isUser { Spacer(minLength: 40) }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(LocalizedStringKey(message.role == "user" ? "You" : "Pip")).font(.caption.bold()).foregroundStyle(.secondary)
                                    if message.role == "assistant" { ChatMarkdownView(text: message.text) }
                                    else { Text(message.text).textSelection(.enabled) }
                                    if let draft = message.trip_draft {
                                        if organizer.data.trips.contains(where: { $0.id == draft.id }) {
                                            Label("Trip saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                                        } else {
                                            Button("Review trip", systemImage: "suitcase") { reviewingTrip = draft }
                                                .buttonStyle(.borderedProminent)
                                                .disabled(!organizer.loaded || organizer.busy || organizer.pending != nil)
                                        }
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: isUser ? nil : .infinity, alignment: .leading)
                                .background(isUser ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                            }
                            .id(message.id)
                        }
                        if let savedTripName { Text("Saved \(savedTripName) to your trips.").foregroundStyle(.green) }
                        if store.busy { ProgressView("Pip is thinking…") }
                        if let error = store.error { Text(error).foregroundStyle(.red) }
                        if store.conflict != nil {
                            Text("This chat changed elsewhere. Load it to review before sending your draft again.")
                            Button("Load latest chat") { store.useLatest() }
                        } else if store.pending != nil && !store.busy {
                            Button("Retry same message") { Task { await store.retry() } }
                        } else if !store.loaded && !store.busy {
                            Button("Try again") { Task { await store.load() } }
                        }
                    }.padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .background(companionStyle ? PipAppearance.cream : Color(.systemGroupedBackground))
                .onChange(of: store.messages.last?.id) { _, id in
                    if let id { withAnimation { scroll.scrollTo(id, anchor: .bottom) } }
                }
            }
            if showsComposer {
                PipComposer(store: store) { store.voice.start() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if showsComposer { Button("New conversation", systemImage: "square.and.pencil") {
                    Task { if await store.newConversation() { composing = true } }
                }
                .disabled(!store.loaded || store.busy || store.pending != nil || store.voice.active || store.translator.active || !store.composer.isEmpty)
                }
            }
        }
        // Runs whenever this page appears, so talks held on the voice page show up here.
        .task { await store.load() }
        .sheet(item: $reviewingTrip) { draft in
            OrganizerEditor(store: organizer, kind: .trip(draft.id), initialTrip: draft) { _ in
                savedTripName = organizer.data.trips.first { $0.id == draft.id }?.name
            }
        }
    }
}

/// Dictation fills a reviewable draft; the separate waveform starts live conversation.
struct PipComposer: View {
    @Bindable var store: TravelChatStore
    var beginTyping: () -> Void = {}
    var editingChanged: (Bool) -> Void = { _ in }
    var companionStyle = false
    let startVoice: () -> Void
    @AppStorage("pip.language") private var language = "en"
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = IntakeSpeech()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var composing: Bool
    private var hasText: Bool { !store.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var unavailable: Bool { store.busy || store.pending != nil || store.translator.active }

    var body: some View {
        VStack(spacing: 8) {
            if let error = speech.error ?? store.voice.error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if speech.recording { Text("Dictating… Tap the microphone to stop.").font(.caption).foregroundStyle(.secondary) }
            if store.voice.active {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    Text(store.voice.connected ? (store.voice.isPlayingResponse ? "Pip is speaking…" : (store.voice.lookingUp ? "Pip is finding out more…" : (store.voice.waitingForWelcome ? "Pip is getting ready to welcome you…" : "Listening — you can speak naturally"))) : "Connecting…")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                Button {
                    if speech.recording { speech.stop() }
                    else {
                        composing = false
                        let prefix = store.composer
                        Task { await speech.start(language: language) { store.composer = prefix.isEmpty ? $0 : prefix + " " + $0 } }
                    }
                } label: {
                    Image(systemName: speech.recording ? "stop.circle.fill" : "mic")
                        .font(.title2).foregroundStyle(speech.recording ? Color.red : Color.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(speech.recording ? "Stop dictation" : "Dictate message")
                .disabled(unavailable || store.voice.active)
                TextField("Ask me anything…", text: $store.composer, axis: .vertical)
                    .lineLimit(1...5).focused($composing)
                    .disabled(unavailable || speech.recording)
                Button {
                    speech.stop(); composing = false
                    if store.voice.active { store.voice.stop() }
                    else if hasText { Task { await store.send() } }
                    else { startVoice() }
                } label: {
                    Image(systemName: store.voice.active ? "phone.down.fill" : (hasText ? "arrow.up" : "waveform"))
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(companionStyle ? Color.blue : (store.voice.active ? Color.red : Color.blue), in: Circle())
                        .symbolEffect(.variableColor, isActive: store.voice.connected && !reduceMotion)
                }
                .accessibilityLabel(store.voice.active ? "End voice conversation" : (hasText ? "Send message" : "Talk to Pip"))
                .disabled(!store.voice.active && (unavailable || (hasText && (!store.loaded || store.composer.count > 4000))))
            }
            .padding(8).background(companionStyle ? Color.white : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 36))
            .foregroundStyle(companionStyle ? PipAppearance.navy : Color.primary)
            if store.composer.count > 4000 { Text("Keep your message under 4,000 characters.").font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(companionStyle ? PipAppearance.cream : Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New conversation", systemImage: "square.and.pencil") {
                    speech.stop()
                    Task { if await store.newConversation() { composing = true } }
                }
                .disabled(!store.loaded || unavailable || store.voice.active || speech.recording || !store.composer.isEmpty)
            }
        }
        .task { if !store.loaded { await store.load() } }
        .onChange(of: composing) { _, focused in
            editingChanged(focused)
            if focused { store.voice.stop(); beginTyping() }
        }
        .onDisappear { speech.stop(); editingChanged(false) }
        .onChange(of: store.voice.active) { _, active in if active { speech.stop() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active { speech.stop() } }
    }
}

/// Native text rendering keeps AI replies selectable and avoids executing HTML.
struct ChatMarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable { case paragraph, heading(Int), bullet, numbered(String), quote, code }
    var id: Int
    var kind: Kind
    var text: String

    static func parse(_ source: String) -> [Self] {
        var blocks: [Self] = []
        var paragraph: [String] = []
        var code: [String]? = nil
        func append(_ kind: Kind, _ text: String) {
            blocks.append(Self(id: blocks.count, kind: kind, text: text))
        }
        func flush() {
            if !paragraph.isEmpty { append(.paragraph, paragraph.joined(separator: "\n")); paragraph = [] }
        }
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                if let lines = code { append(.code, lines.joined(separator: "\n")); code = nil }
                else { code = [] }
                continue
            }
            if code != nil { code?.append(line); continue }
            if trimmed.isEmpty { flush(); continue }
            let hashes = trimmed.prefix { $0 == "#" }.count
            if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                flush(); append(.heading(hashes), String(trimmed.dropFirst(hashes + 1))); continue
            }
            if ["- ", "* ", "+ ", "• "].contains(where: { trimmed.hasPrefix($0) }) {
                flush(); append(.bullet, String(trimmed.dropFirst(2))); continue
            }
            let digits = trimmed.prefix { $0.isNumber }
            let remainder = trimmed.dropFirst(digits.count)
            if !digits.isEmpty, remainder.hasPrefix(". ") || remainder.hasPrefix(") ") {
                flush(); append(.numbered(String(digits) + "."), String(remainder.dropFirst(2))); continue
            }
            if trimmed.hasPrefix("> ") {
                flush(); append(.quote, String(trimmed.dropFirst(2))); continue
            }
            paragraph.append(line)
        }
        flush()
        if let code { append(.code, code.joined(separator: "\n")) }
        return blocks
    }

    var attributed: AttributedString {
        var result = (try? AttributedString(markdown: PipContactLinks.digitText(text), options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in result.runs {
            if let link = run.link, !PipContactLinks.allowed(link) { result[run.range].link = nil }
        }
        let plain = String(result.characters)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue) {
            for match in detector.matches(in: plain, range: NSRange(plain.startIndex..., in: plain)) {
                guard let range = Range(match.range, in: plain),
                      let start = AttributedString.Index(range.lowerBound, within: result),
                      let end = AttributedString.Index(range.upperBound, within: result) else { continue }
                let url = match.phoneNumber.flatMap(PipContactLinks.phoneURL) ?? match.url
                if let url, PipContactLinks.allowed(url), result[start..<end].runs.allSatisfy({ $0.link == nil }) {
                    result[start..<end].link = url
                }
            }
        }
        return result
    }
}

struct ChatMarkdownView: View {
    let text: String
    private var displayText: String {
        text.replacingOccurrences(of: "According to Google Maps, ", with: "")
            .replacingOccurrences(of: "According to Google Maps", with: "")
            .replacingOccurrences(of: "Google Maps directions", with: "Apple Maps directions")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ChatMarkdownBlock.parse(PipPhotoLink.removingImages(displayText))) { block in
                switch block.kind {
                case .heading(let level):
                    Text(block.attributed).font(level == 1 ? .title3.bold() : .headline)
                case .bullet:
                    HStack(alignment: .top, spacing: 8) { Text("•"); Text(block.attributed) }
                case .numbered(let marker):
                    HStack(alignment: .top, spacing: 8) { Text(marker).monospacedDigit(); Text(block.attributed) }
                case .quote:
                    HStack(alignment: .top, spacing: 8) {
                        Rectangle().fill(.secondary).frame(width: 3)
                        Text(block.attributed).foregroundStyle(.secondary)
                    }.fixedSize(horizontal: false, vertical: true)
                case .code:
                    Text(block.text).font(.system(.body, design: .monospaced))
                case .paragraph:
                    Text(block.attributed)
                }
            }
            ForEach(PipPhotoLink.parse(text)) { photo in PipPhotoView(photo: photo) }
            ForEach(ChatMapDestination.parse(text)) { destination in
                ChatMapPreview(destination: destination)
            }
        }
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            guard let destination = ChatMapDestination(url: url, title: "") else { return .systemAction }
            destination.openDirections()
            return .handled
        })
    }
}

struct OrganizerCategoryCost: Codable, Equatable, Sendable {
    var estimated = ""
    var actual = ""
}
struct OrganizerBudget: Codable, Equatable, Sendable {
    var currency = "USD"
    var total = ""
    var flights = OrganizerCategoryCost()
    var hotels = OrganizerCategoryCost()
    var transport = OrganizerCategoryCost()
    var food = OrganizerCategoryCost()
    var activities = OrganizerCategoryCost()
    var other = OrganizerCategoryCost()
    var categories: [OrganizerCategoryCost] { [flights, hotels, transport, food, activities, other] }
    static func amount(_ text: String) -> Decimal? {
        guard !text.isEmpty else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
    var estimatedTotal: Decimal { categories.reduce(0) { $0 + (Self.amount($1.estimated) ?? 0) } }
    var actualTotal: Decimal { categories.reduce(0) { $0 + (Self.amount($1.actual) ?? 0) } }
    var remaining: Decimal? { Self.amount(total).map { $0 - actualTotal } }
    var unallocated: Decimal? { Self.amount(total).map { $0 - estimatedTotal } }
    var isValid: Bool {
        let pattern = currency == "JPY" ? #"^[0-9]{1,9}(?:\.0{1,2})?$"# : #"^[0-9]{1,9}(?:\.[0-9]{1,2})?$"#
        return ([total] + categories.flatMap { [$0.estimated, $0.actual] }).allSatisfy {
            $0.isEmpty || $0.range(of: pattern, options: .regularExpression) != nil
        }
    }
    func formatted(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: currency))
    }
}

struct OrganizerBudgetView: View {
    @Binding var budget: OrganizerBudget
    var body: some View {
        Form {
            Section("Trip budget") {
                Picker("Currency", selection: $budget.currency) {
                    ForEach(["USD", "CAD", "EUR", "GBP", "AUD", "JPY"], id: \.self) { Text($0).tag($0) }
                }
                BudgetAmountField(title: "Total budget", value: $budget.total)
                Text("All costs use this currency. Changing it does not convert amounts.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Summary") {
                LabeledContent("Estimated total", value: budget.formatted(budget.estimatedTotal))
                LabeledContent("Actual spent", value: budget.formatted(budget.actualTotal))
                if let unallocated = budget.unallocated {
                    LabeledContent(unallocated < 0 ? "Estimates over budget" : "Not yet allocated", value: budget.formatted(abs(unallocated)))
                        .foregroundStyle(unallocated < 0 ? Color.red : Color.primary)
                }
                if let remaining = budget.remaining {
                    LabeledContent(remaining < 0 ? "Over budget" : "Remaining budget", value: budget.formatted(abs(remaining)))
                        .foregroundStyle(remaining < 0 ? Color.red : Color.primary)
                }
                Text("Totals include entered costs only. Leave unknown costs blank. Estimates and actual spending are counted separately.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            costSection("Flights", cost: $budget.flights)
            costSection("Hotels & stays", cost: $budget.hotels)
            costSection("Transport", cost: $budget.transport)
            costSection("Food", cost: $budget.food)
            costSection("Activities", cost: $budget.activities)
            costSection("Other", cost: $budget.other)
            if !budget.isValid {
                Text("Use numbers with up to two decimal places, or whole yen for JPY. Negative amounts are not supported.").foregroundStyle(.red)
            }
        }
        .navigationTitle("Budget & costs")
        .navigationBarTitleDisplayMode(.inline)
    }
    private func costSection(_ title: String, cost: Binding<OrganizerCategoryCost>) -> some View {
        Section(LocalizedStringKey(title)) {
            BudgetAmountField(title: "Estimated", value: cost.estimated)
            BudgetAmountField(title: "Actual", value: cost.actual)
        }
    }
}
struct BudgetAmountField: View {
    let title: String
    @Binding var value: String
    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
            Spacer()
            TextField("Not entered", text: Binding(get: { value }, set: { value = $0.replacingOccurrences(of: ",", with: ".") }))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .accessibilityLabel(Text(LocalizedStringKey(title)))
        }
    }

}


/// Only explicit map links produce previews; ordinary prose is never guessed as a place.
struct ChatMapDestination: Identifiable {
    let query: String
    let title: String
    var id: String { query }

    init?(url: URL, title: String) {
        guard url.scheme == "https", let host = url.host?.lowercased(),
              host == "maps.apple.com" || host == "maps.google.com" || host == "www.google.com" || host == "google.com",
              host == "maps.apple.com" || host == "maps.google.com" || url.path.hasPrefix("/maps"),
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let values = parts.queryItems ?? []
        let query = ["destination", "daddr", "query", "q", "ll"].compactMap { key in
            values.first { $0.name == key }?.value
        }.first ?? (url.path.components(separatedBy: "/place/").dropFirst().first?.components(separatedBy: "/").first?.removingPercentEncoding)
        guard let query, !query.isEmpty, query.count <= 512, !query.hasPrefix("place_id:") else { return nil }
        self.query = query.replacingOccurrences(of: "+", with: " ")
        self.title = title.isEmpty ? self.query : title
    }

    static func parse(_ text: String) -> [Self] {
        guard let attributed = try? AttributedString(markdown: text) else { return [] }
        var result: [Self] = []
        for run in attributed.runs {
            if let url = run.link,
               let destination = Self(url: url, title: String(attributed[run.range].characters)),
               !result.contains(where: { $0.id == destination.id }) {
                result.append(destination)
            }
        }
        return Array(result.prefix(3))
    }

    func openDirections() {
        var parts = URLComponents(string: "https://maps.apple.com/")!
        parts.queryItems = [.init(name: "daddr", value: query), .init(name: "dirflg", value: "d")]
        if let url = parts.url { UIApplication.shared.open(url) }
    }
}

struct ChatMapPreview: View {
    let destination: ChatMapDestination
    @State private var image: UIImage?
    @State private var mapItem: MKMapItem?
    @State private var failed = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            if let mapItem { mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]) }
            else { destination.openDirections() }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit()
                        .overlay { Image(systemName: "mappin.circle.fill").font(.largeTitle).foregroundStyle(.red).accessibilityHidden(true) }
                } else if !failed {
                    ProgressView().frame(maxWidth: .infinity).frame(height: 160)
                }
                Text(verbatim: destination.title).font(.headline)
                Label("Open in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond")
                    .font(.caption)
            }.padding(10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .task(id: "\(destination.id)-\(colorScheme)") { await load() }
    }

    @MainActor private func load() async {
        image = nil; mapItem = nil; failed = false
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = destination.query
        let search = MKLocalSearch(request: request)
        do {
            let response = try await withTaskCancellationHandler { try await search.start() } onCancel: { search.cancel() }
            try Task.checkCancellation()
            guard let place = response.mapItems.first else { failed = true; return }
            mapItem = place
            let options = MKMapSnapshotter.Options()
            options.region = MKCoordinateRegion(center: place.placemark.coordinate, latitudinalMeters: 1500, longitudinalMeters: 2200)
            options.size = CGSize(width: 600, height: 320)
            options.scale = 2
            options.traitCollection = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
            let snapshotter = MKMapSnapshotter(options: options)
            let snapshot = try await withTaskCancellationHandler { try await snapshotter.start() } onCancel: { snapshotter.cancel() }
            try Task.checkCancellation()
            image = snapshot.image
        } catch {
            if !Task.isCancelled { failed = true }
        }
    }
}

// MARK: - Local guide recap and preferences

struct GuideHighlight: Codable, Sendable, Identifiable {
    var text: String
    var at: String
    var source_id: String
    var id: String { source_id + text }
}
struct GuidePreference: Codable, Sendable, Identifiable {
    var id: String
    var topic: String
    var category: String
    var kind: String
    var text: String
    var evidence: String
    var updated_at: String
    var edited: Bool
}
struct GuideData: Codable, Sendable {
    var version: Int
    var welcome_due: Bool
    var welcome: String
    var summary: [GuideHighlight]
    var preferences: [GuidePreference]
    var updated_at: String?
    var refresh_pending: Bool?

    static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
    var recentSummary: [GuideHighlight] {
        return summary.filter { Self.date($0.at).map { $0 <= Date() } ?? false }
    }
}
struct GuidePreferenceEdit: Codable, Sendable {
    var id: String
    var text: String
    var remove: Bool
}

struct GuideRecapView: View {
    var guide: GuideData?
    var compact = false
    @State private var expanded = true
    var body: some View {
        if let guide, !guide.recentSummary.isEmpty {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(guide.recentSummary) { highlight in
                        Label { VStack(alignment: .leading, spacing: 3) { Text(verbatim: highlight.text); if let date = GuideData.date(highlight.at) { Text(date, style: .date).font(.caption).foregroundStyle(.secondary) } } } icon: {
                            Image(systemName: "smallcircle.filled.circle").font(.caption2)
                        }
                    }
                    Text("A recap of what we discussed, not live availability or confirmed bookings.")
                        .font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline).padding(.top, 8)
            } label: {
                Label("Our recent conversations", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
            }
            .padding(compact ? 12 : 16)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, compact ? 16 : 0)
            .accessibilityIdentifier("pip.recentRecap")
            .onAppear { expanded = !compact }
        }
    }
}

struct GuidePreferencesSection: View {
    @Bindable var store: TravelChatStore
    @State private var editing: GuidePreference?
    @State private var draft = ""
    var body: some View {
        Section {
            Text("Pip learns the travel likes, dislikes and preferences you share to offer more personal suggestions. Review, edit or forget them here.")
                .font(.footnote).foregroundStyle(.secondary)
            if let preferences = store.guide?.preferences, !preferences.isEmpty {
                ForEach(preferences) { preference in
                    Button {
                        draft = preference.text
                        editing = preference
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: preference.text).foregroundStyle(.primary)
                            Text(preference.kind == "dislike" ? "Dislike" : preference.kind == "like" ? "Like" : "Preference")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                Text("No learned preferences yet. Tell Pip what you enjoy—or what you'd rather skip.")
                    .foregroundStyle(.secondary)
            }
            if let error = store.guideError { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if store.guideEditConflict {
                Button("Load latest preferences") { Task { await store.reloadGuideAfterConflict() } }
            } else if store.pendingGuideEdit != nil {
                Button("Retry preference change") { Task { await store.retryGuideEdit() } }
                    .disabled(store.refreshingGuide)
            }
        } header: {
            Text("What Pip knows about you")
        }
        .sheet(item: $editing) { preference in
            NavigationStack {
                Form {
                    Section("Preference") { TextField("Preference", text: $draft, axis: .vertical) }
                    Section("Based on what you shared") { Text(verbatim: preference.evidence) }
                    Section {
                        Button("Forget this preference", role: .destructive) {
                            Task {
                                await store.editPreference(preference, text: "", remove: true)
                                if store.pendingGuideEdit == nil, store.guideError == nil { editing = nil }
                            }
                        }.disabled(store.refreshingGuide || store.pendingGuideEdit != nil)
                    }
                    if let error = store.guideError { Text(error).foregroundStyle(.red) }
                }
                .navigationTitle("What Pip remembers")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { editing = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task {
                                await store.editPreference(preference, text: draft, remove: false)
                                if store.pendingGuideEdit == nil, store.guideError == nil { editing = nil }
                            }
                        }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.refreshingGuide || store.pendingGuideEdit != nil)
                    }
                }
            }
        }
    }
}


// MARK: - Your travel style
struct GuideSetup: Codable, Equatable, Sendable {
    var preferred_name = ""
    var home_city = ""
    var work = ""
    var hobbies = ""
    var free_time = ""
    var curiosities = ""
    var bucket_list = ""
    var favorite_travel_memory = ""
    var voice = "ballad"
    var personality = "warm"
    var planning_style = "not_set"
    var offer_opinions = true
    var compliments = "ask"
    var film_references = "ask"
    var interview = "open"
}
struct GuideBooking: Codable, Sendable {
    var explanation: String
    var facts: [ImportFact]
    var flights: [FlightSegment]
    var notes: String {
        (facts.map { [$0.title, $0.details, $0.timing, $0.location].filter { !$0.isEmpty }.joined(separator: " · ") }
        + flights.map { "\($0.airline) \($0.flight_number): \($0.departure_airport) → \($0.arrival_airport), \($0.departure_local) – \($0.arrival_local)" }).joined(separator: "\n")
    }
}
@MainActor @Observable
final class GuideSetupStore {
    var data = GuideSetup()
    var version = 0
    var loaded = false
    var busy = false
    var conflict = false
    var error: String?
    private(set) var pending: APIRequest<APIRecord<GuideSetup>>?
    private var epoch = UUID()
    private let client: APIClient
    private let authentication: any AccessTokenProviding
    init(client: APIClient, authentication: any AccessTokenProviding) {
        self.client = client; self.authentication = authentication
    }
    func reset() {
        epoch = UUID(); data = GuideSetup(); version = 0; loaded = false
        busy = false; conflict = false; error = nil; pending = nil
    }
    func load() async {
        guard !busy, pending == nil else { return }
        busy = true; let ticket = epoch
        defer { if ticket == epoch { busy = false } }
        do {
            let result: APIRecord<GuideSetup> = try await client.send(.get(.guideSetup), using: authentication)
            guard ticket == epoch else { return }
            data = result.data; version = result.version; loaded = true; error = nil
        } catch { if ticket == epoch { self.error = error.localizedDescription } }
    }
    func save(_ draft: GuideSetup) async -> Bool {
        guard loaded, !busy, pending == nil else { return false }
        do { pending = try .put(.guideSetup, body: draft, expectedVersion: version) }
        catch { self.error = error.localizedDescription; return false }
        return await retry()
    }
    func retry() async -> Bool {
        guard !busy, !conflict, let request = pending else { return false }
        busy = true; let ticket = epoch
        defer { if ticket == epoch { busy = false } }
        do {
            let result = try await client.send(request, using: authentication)
            guard ticket == epoch else { return false }
            data = result.data; version = result.version; pending = nil; error = nil
            return true
        } catch APIClientError.conflict {
            if ticket == epoch { conflict = true; error = "Your choices changed elsewhere. Load the latest and review before saving." }
        } catch { if ticket == epoch { self.error = error.localizedDescription } }
        return false
    }
    func loadLatest() async { pending = nil; conflict = false; await load() }
    func extract(_ request: PipImportRequest) async throws -> GuideBooking {
        let ticket = epoch
        let result: GuideBooking = try await client.send(.post(.guideBooking, body: request), using: authentication)
        guard ticket == epoch else { throw CancellationError() }
        return result
    }
}
struct GuideSetupView: View {
    @Bindable var store: GuideSetupStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GuideSetup()
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Help Pip learn how you like to travel, so ideas for destinations, local gems and activities feel more like you. Share in your own words, or skip anything.")
                    TextField("What should Pip call you?", text: $draft.preferred_name)
                    TextField("Home city", text: $draft.home_city)
                    TextField("Hobbies and fun", text: $draft.hobbies, axis: .vertical)
                    TextField("When you're not working…", text: $draft.free_time, axis: .vertical)
                    TextField("Work (optional)", text: $draft.work, axis: .vertical)
                    TextField("What are you curious about?", text: $draft.curiosities, axis: .vertical)
                    TextField("Your bucket list", text: $draft.bucket_list, axis: .vertical)
                    TextField("A trip you loved—what made it special?", text: $draft.favorite_travel_memory, axis: .vertical)
                } header: { Text("A little about you") }
                .disabled(store.pending != nil)
                Section("Make Pip your own") {
                    Picker("Voice", selection: $draft.voice) {
                        Text("Ballad").tag("ballad"); Text("Coral").tag("coral"); Text("Sage").tag("sage")
                        Text("Ash").tag("ash"); Text("Verse").tag("verse")
                    }
                    Text("Your voice choice takes effect the next time you open voice.").font(.footnote)
                    Picker("Pip's tone", selection: $draft.personality) {
                        Text("Warm and friendly").tag("warm"); Text("Playful").tag("playful")
                        Text("Calm").tag("calm"); Text("Friendly and direct").tag("direct")
                    }
                    Picker("Planning feels best when…", selection: $draft.planning_style) {
                        Text("Let's discover together").tag("not_set"); Text("There's room for spontaneity").tag("spontaneous")
                        Text("There's a little of both").tag("balanced"); Text("Everything is organized").tag("organized")
                    }
                    Toggle("Offer your honest opinion", isOn: $draft.offer_opinions)
                    Picker("A little sincere encouragement?", selection: $draft.compliments) {
                        Text("Ask me first").tag("ask"); Text("Yes, occasionally").tag("gentle"); Text("Skip compliments").tag("none")
                    }
                    Picker("Fun film and TV references?", selection: $draft.film_references) {
                        Text("Ask me first").tag("ask"); Text("Yes, please").tag("yes"); Text("No thanks").tag("no")
                    }
                    Picker("Getting-to-know-you questions", selection: $draft.interview) {
                        Text("One at a time is welcome").tag("open"); Text("Maybe later").tag("later"); Text("Don't ask").tag("no")
                    }
                }
                .disabled(store.pending != nil)
                if let error = store.error { Section { Text(error).foregroundStyle(.red) } }
                if store.conflict {
                    Button("Load latest choices") { Task { await store.loadLatest(); draft = store.data } }
                } else if store.pending != nil {
                    Button("Retry saving these choices") { Task { if await store.retry() { dismiss() } } }
                }
            }
            .disabled(store.busy)
            .navigationTitle("My travel style")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { if await store.save(draft) { dismiss() } } }
                        .disabled(!store.loaded || store.busy || store.pending != nil)
                }
            }
            .task {
                await store.load()
                if let body = store.pending?.body, let frozen = try? APIJSON.decoder().decode(GuideSetup.self, from: body) { draft = frozen }
                else { draft = store.data }
            }
        }
    }
}
struct GuideBookingView: View {
    @Bindable var setup: GuideSetupStore
    @Bindable var organizer: OrganizerStore
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false
    @State private var busy = false
    @State private var error: String?
    @State private var extracted = false
    @State private var title = "My trip"
    @State private var notes = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Upload a booking receipt to help prepare your trip. Pip reads it with AI; you'll review the details before saving. Check dates and times against your receipt.")
                    Button("Choose receipt", systemImage: "doc.badge.plus") { choosing = true }
                        .disabled(busy || organizer.pending != nil)
                    Text("PDF, JPEG, PNG or Word document, up to 5 MB.").font(.footnote)
                    if busy { ProgressView("Reading your receipt…") }
                }
                if extracted {
                    Section("Review your trip") {
                        TextField("Trip name", text: $title)
                        TextEditor(text: $notes).frame(minHeight: 200)
                        Text("\(notes.count)/2000 characters").font(.caption)
                        Button("Save as a trip") { Task {
                            var data = organizer.data
                            var trip = OrganizerTrip(); trip.name = title; trip.notes = notes
                            data.trips.append(trip)
                            if await organizer.save(data) { dismiss() }
                        } }.disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || notes.count > 2000 || !organizer.loaded || organizer.busy || organizer.pending != nil)
                    }.disabled(organizer.pending != nil)
                }
                if let error = error ?? organizer.error { Text(error).foregroundStyle(.red) }
                if organizer.pending != nil { Text("The save needs attention. Close this sheet and review the pending change in Trips before trying again.") }
            }
            .navigationTitle("Booking receipt")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.pdf, .jpeg, .png, UTType(filenameExtension: "docx")!]) { result in
                Task { await read(result) }
            }
        }
    }
    private func read(_ result: Result<URL, Error>) async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 5 * 1024 * 1024 else { error = "Choose a receipt smaller than 5 MB."; return }
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= 5 * 1024 * 1024 else { error = "Choose a receipt smaller than 5 MB."; return }
            let result = try await setup.extract(PipImportRequest(filename: url.lastPathComponent, content_base64: bytes.base64EncodedString()))
            notes = result.notes; extracted = true
            if notes.isEmpty { error = "Pip couldn't find booking details. You can add them yourself or choose another receipt." }
        } catch { self.error = error.localizedDescription }
    }
}

// Calendar content stays on this device. Only explicitly reviewed events are added.
struct GuideCalendarView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = EKEventStore()
    @State private var calendars: [EKCalendar] = []
    @State private var selected: Set<String> = []
    @State private var events: [EKEvent] = []
    @State private var error: String?
    @State private var title = "Trip plans"
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var editing = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Connect calendars on this iPhone, including Apple Calendar and Google calendars you've synced in Settings. Select which calendars to check. Their contents stay on this device.")
                    Button("Connect calendars") { Task {
                        do {
                            if try await store.requestFullAccessToEvents() {
                                calendars = store.calendars(for: .event)
                            } else { error = "Calendar access is off. You can allow it in iPhone Settings whenever you're ready." }
                        } catch { self.error = error.localizedDescription }
                    } }
                }
                if !calendars.isEmpty {
                    Section("Check these calendars") {
                        ForEach(calendars, id: \.calendarIdentifier) { calendar in
                            Toggle("\(calendar.title) · \(calendar.source.title)", isOn: Binding(
                                get: { selected.contains(calendar.calendarIdentifier) },
                                set: { if $0 { selected.insert(calendar.calendarIdentifier) } else { selected.remove(calendar.calendarIdentifier) }; events = [] }
                            ))
                        }
                    }
                    Section("Review a time for your plans") {
                        TextField("Event title", text: $title)
                        DatePicker("Starts", selection: $start)
                        DatePicker("Ends", selection: $end, in: start...)
                        Button("Check for schedule conflicts") {
                            let chosen = calendars.filter { selected.contains($0.calendarIdentifier) }
                            guard !chosen.isEmpty, end > start else { error = "Choose a calendar and an end time after the start."; return }
                            events = store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: chosen))
                            error = events.isEmpty ? "No conflicts found in your selected calendars." : "These events overlap your plans:"
                        }
                        ForEach(events, id: \.eventIdentifier) { event in
                            VStack(alignment: .leading) { Text(event.title ?? "Busy"); Text(event.startDate, style: .date); Text(event.startDate, style: .time) }
                        }
                        Button("Review and add to calendar") { editing = true }.disabled(end <= start || title.isEmpty)
                    }
                }
                if let error { Text(error) }
            }
            .onChange(of: start) { events = []; error = nil; if end <= start { end = start.addingTimeInterval(3600) } }
            .onChange(of: end) { events = []; error = nil }
            .navigationTitle("Calendars")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $editing) { GuideCalendarEditor(store: store, title: title, start: start, end: end) }
        }
    }
}
struct GuideCalendarEditor: UIViewControllerRepresentable {
    let store: EKEventStore
    let title: String
    let start: Date
    let end: Date
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let controller = EKEventEditViewController()
        controller.eventStore = store
        let event = EKEvent(eventStore: store)
        event.title = title; event.startDate = start; event.endDate = end; event.calendar = store.defaultCalendarForNewEvents
        controller.event = event; controller.editViewDelegate = context.coordinator
        return controller
    }
    func updateUIViewController(_ uiViewController: EKEventEditViewController, context: Context) {}
    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let close: () -> Void
        init(close: @escaping () -> Void) { self.close = close }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { close() }
    }
}

// MARK: - Verified contact links and optional place photos

enum PipContactLinks {
    static func phoneURL(_ value: String) -> URL? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.allSatisfy({ $0.isNumber || "+ ()-.".contains($0) }),
              raw.filter({ $0 == "+" }).count <= 1,
              !raw.contains("+") || raw.hasPrefix("+") else { return nil }
        let digits = raw.compactMap(\.wholeNumberValue).map(String.init).joined()
        guard (7...15).contains(digits.count) else { return nil }
        return URL(string: "tel:" + (raw.hasPrefix("+") ? "+" : "") + digits)
    }

    static func allowed(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https", "http": return url.host != nil && url.user == nil && url.password == nil
        case "tel":
            let raw = String(url.absoluteString.dropFirst(4)).removingPercentEncoding ?? ""
            return phoneURL(raw) != nil
        default: return false
        }
    }

    /// Convert only long runs of spoken single digits, never ordinary number phrases.
    static func digitText(_ text: String) -> String {
        let words = ["zero": "0", "oh": "0", "one": "1", "two": "2", "three": "3", "four": "4", "five": "5", "six": "6", "seven": "7", "eight": "8", "nine": "9"]
        let word = "(?:zero|oh|one|two|three|four|five|six|seven|eight|nine)"
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\b" + word + "(?:[ -]+" + word + "){6,14}\\b") else { return text }
        var output = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: output) else { continue }
            let digits = output[range].lowercased().split(whereSeparator: { $0 == " " || $0 == "-" }).compactMap { words[String($0)] }.joined()
            output.replaceSubrange(range, with: digits)
        }
        return output
    }
}

struct PipPhotoLink: Identifiable {
    var url: URL
    var caption: String
    var id: String { url.absoluteString }
    static let pattern = #"!\[([^\]]*)\]\((https://[^\s)]+)\)"#
    static func validURL(_ text: String) -> URL? {
        guard let url = URL(string: text), url.scheme == "https", url.user == nil, url.password == nil,
              url.host?.hasSuffix(".googleusercontent.com") == true else { return nil }
        return url
    }
    static func parse(_ text: String) -> [Self] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<String>()
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let caption = Range(match.range(at: 1), in: text), let raw = Range(match.range(at: 2), in: text),
                  let url = validURL(String(text[raw])), seen.insert(url.absoluteString).inserted else { return nil }
            return Self(url: url, caption: String(text[caption]))
        }.prefix(2).map { $0 }
    }
    static func removingImages(_ text: String) -> String {
        text.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }
}

struct PipPhotoView: View {
    let photo: PipPhotoLink
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AsyncImage(url: photo.url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit().frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel(photo.caption)
                } else if phase.error != nil {
                    Text("Photo unavailable").font(.caption).foregroundStyle(.secondary)
                } else { ProgressView().frame(height: 60) }
            }
            Text(photo.caption).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PipPlaceResult: Decodable, Identifiable {
    struct Name: Decodable { var text: String }
    struct Author: Decodable { var displayName: String?; var uri: String? }
    struct Photo: Decodable { var url: String; var authors: [Author] }
    var id: String
    var displayName: Name?
    var internationalPhoneNumber: String?
    var websiteUri: String?
    var googleMapsUri: String?
    var photo: Photo?
}

struct PipPlaceCard: View {
    let place: PipPlaceResult
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(place.displayName?.text ?? "Place details").font(.headline)
            if let photo = place.photo, let url = PipPhotoLink.validURL(photo.url) {
                PipPhotoView(photo: PipPhotoLink(url: url, caption: "Photo · Google Maps"))
                ForEach(Array(photo.authors.enumerated()), id: \.offset) { _, author in
                    if let raw = author.uri, let url = URL(string: raw), PipContactLinks.allowed(url), url.scheme == "https" {
                        Link(author.displayName ?? "Photo contributor", destination: url).font(.caption)
                    } else { Text(author.displayName ?? "Photo contributor").font(.caption) }
                }
            }
            if let phone = place.internationalPhoneNumber, let url = PipContactLinks.phoneURL(phone) {
                Link(destination: url) { Label(phone, systemImage: "phone") }.font(.subheadline)
            }
            if let raw = place.websiteUri, let url = URL(string: raw), ["https", "http"].contains(url.scheme ?? ""), PipContactLinks.allowed(url) {
                Link("Website", destination: url)
            }
            if let raw = place.googleMapsUri, let url = URL(string: raw), url.scheme == "https", PipContactLinks.allowed(url) {
                Link("Source: Google Maps", destination: url).font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }
}
