import MapKit
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
            PipTab(chat: chat, organizer: store, mode: $pipMode, reviewingTrip: $reviewingTrip, voiceStartRequest: $voiceStartRequest)
                .tabItem { Label("Pip", systemImage: "bubble.left.and.bubble.right") }
                .tag(AppTab.pip)
            TranslateTab(store: chat.translator)
                .tabItem { Label("Translate", systemImage: "translate") }
                .tag(AppTab.translate)
            ProfileTab(store: store, location: chat.locationDisplay, profilePictureURL: profilePictureURL, editor: $editor, signOut: signOut)
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
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

/// Typed chat and live voice share one conversation but stay separate pages.
struct PipTab: View {
    @Bindable var chat: TravelChatStore
    @Bindable var organizer: OrganizerStore
    @Binding var mode: PipMode
    @Binding var reviewingTrip: OrganizerTrip?
    @Binding var voiceStartRequest: UUID?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if mode == .voice {
                    LiveVoiceView(store: chat.voice, showsControls: false)
                } else {
                    TravelChatView(store: chat, organizer: organizer, reviewingTrip: $reviewingTrip, name: organizer.data.profile?.name, showsComposer: false)
                }
                PipComposer(store: chat) {
                    mode = .voice
                    chat.voice.start()
                }
            }
            .navigationTitle("Pip")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: chat.voice.active) { _, active in
                if !active && mode == .voice {
                    mode = .chat
                }
            }
            .onChange(of: scenePhase, initial: true) { _, _ in startRequestedConversation() }
            .onChange(of: voiceStartRequest) { _, _ in startRequestedConversation() }
            .onAppear { if !chat.voice.active { mode = .chat } }
        }
    }

    private func startRequestedConversation() {
        guard scenePhase == .active, voiceStartRequest != nil else { return }
        voiceStartRequest = nil
        mode = .voice
        chat.voice.start()
    }
}

// MARK: - Profile

struct ProfileTab: View {
    @Environment(\.locale) private var locale
    @Bindable var store: OrganizerStore
    let location: CurrentLocationStore
    var profilePictureURL: URL? = nil
    @Binding var editor: OrganizerEditorKind?
    let signOut: () -> Void
    @State private var confirmSignOut = false

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
}
struct TravelChatData: Codable, Sendable { var messages: [TravelChatMessage] = [] }
struct TravelChatRequest: Codable, Sendable {
    var text: String
    var new_conversation = false
    var conversation_context: ConversationContext = .snapshot()
}

@MainActor @Observable
final class TravelChatStore {
    let voice: LiveVoiceStore
    /// Two-way interpreter; shares no traveler context with the backend session.
    let translator: LiveVoiceStore
    let locationDisplay: CurrentLocationStore
    var messages: [TravelChatMessage] = []
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
        self.captureContext = captureContext
        self.client = client; self.authentication = authentication
        let display = CurrentLocationStore(capture: captureContext)
        self.locationDisplay = display
        self.voice = LiveVoiceStore(client: client, authentication: authentication, locationDisplay: display)
        self.translator = LiveVoiceStore(client: client, authentication: authentication, mode: .translate(.saved()))
    }
    func reset() {
        voice.stop(clearCaptions: true)
        translator.stop(clearCaptions: true)
        locationDisplay.reset()
        conversationContext = nil; capturingLocation = false
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
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if store.messages.isEmpty {
                            Text("\(name.map { "Hi, \($0)!" } ?? "Hi!") I'm Pip, your travel companion. How can I help with your trip?").font(.headline)
                        }
                        ForEach(store.messages.suffix(2)) { message in
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
                .background(Color(.systemGroupedBackground))
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
    let startVoice: () -> Void
    @AppStorage("pip.language") private var language = "en"
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = IntakeSpeech()
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
                Text(store.voice.connected ? "Listening — you can speak naturally" : "Connecting…")
                    .font(.caption).foregroundStyle(.secondary)
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
                    .disabled(unavailable || store.voice.active || speech.recording)
                Button {
                    speech.stop(); composing = false
                    if store.voice.active { store.voice.stop() }
                    else if hasText { Task { await store.send() } }
                    else { startVoice() }
                } label: {
                    Image(systemName: store.voice.active ? "phone.down.fill" : (hasText ? "arrow.up" : "waveform"))
                        .font(.title2.weight(.semibold)).foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(store.voice.active ? Color.red : Color.blue, in: Circle())
                }
                .accessibilityLabel(store.voice.active ? "End voice conversation" : (hasText ? "Send message" : "Talk to Pip"))
                .disabled(!store.voice.active && (unavailable || (hasText && (!store.loaded || store.composer.count > 4000))))
            }
            .padding(8).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 36))
            if store.composer.count > 4000 { Text("Keep your message under 4,000 characters.").font(.caption).foregroundStyle(.red) }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).background(Color(.systemGroupedBackground))
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
        .onDisappear { speech.stop() }
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
        var result = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        // Only ordinary web links can be opened from AI-generated text.
        for run in result.runs {
            if let link = run.link, !["https", "http"].contains(link.scheme?.lowercased() ?? "") {
                result[run.range].link = nil
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
            ForEach(ChatMarkdownBlock.parse(displayText)) { block in
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
