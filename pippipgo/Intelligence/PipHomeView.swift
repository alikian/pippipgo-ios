import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Speech
import AVFoundation

struct PipHomeView: View {
    @Bindable var store: IntelligenceStore
    let signOut: () -> Void
    @AppStorage("pip.language") private var language = "en"
    @State private var showIntake = false
    @State private var showMemory = false
    @State private var showSettings = false
    @State private var showIntroduction = false
    @State private var startTripAfterIntroduction = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(alignment: .top) {
                        Text("🦆").font(.system(size: 48)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            if let name = store.preferredName {
                                Text("Hi, \(name)").font(.title2.bold()).accessibilityIdentifier("pip.greeting")
                            } else {
                                Text("Hi there").font(.title2.bold()).accessibilityIdentifier("pip.greeting")
                                Button("Add your preferred name") { showMemory = true }.font(.subheadline)
                            }
                            Text(store.loaded && store.needsIntroduction ? "Let's get to know you" : "A little less planning.\nA little more exploring.").font(.largeTitle.bold())
                            Text("I'm Pip. Let's make this trip feel like you.").foregroundStyle(.secondary)
                        }
                    }.padding(.top, 16)
                    if store.loaded && store.needsIntroduction {
                        Text("Before we plan, I'd love to get to know you a little.").font(.title3)
                        Text("Tell me about a trip or day out you really enjoyed. What made it good?").font(.headline)
                        Button("Tell Pip about yourself", systemImage: "bubble.left.and.bubble.right") { showIntroduction = true }
                            .buttonStyle(.borderedProminent).disabled(store.busy || store.introduction == nil)
                        Button("Skip for now") {
                            Task {
                                await store.introduce(language: language, skip: true)
                                if store.error == nil && !store.hasPending { store.newTrip(language: language); showIntake = true }
                            }
                        }.disabled(store.busy || store.hasPending || store.introduction == nil)
                    } else if store.loaded {
                    Button {
                        store.newTrip(language: language); showIntake = true
                    } label: {
                        Label("Where are we going?", systemImage: "plus").frame(maxWidth: .infinity).padding(10)
                    }.buttonStyle(.borderedProminent).disabled(store.hasPending || store.busy).accessibilityIdentifier("pip.createTrip")
                    }
                    PipErrorView(store: store)
                    if store.busy { ProgressView() }
                    if store.loaded && store.journeys.isEmpty && !store.needsIntroduction {
                        ContentUnavailableView("Your next chapter starts here", systemImage: "suitcase.rolling", description: Text("Choose a destination and timing. We'll work out the rest together."))
                    }
                    ForEach(store.journeys) { trip in
                        NavigationLink {
                            PipTripView(store: store, tripID: UUID(uuidString: trip.id)!)
                        } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Image(systemName: "map").foregroundStyle(.teal)
                                    Text(trip.data.intake.destination).font(.title2.bold())
                                    Spacer(); Image(systemName: "chevron.right").font(.caption)
                                }
                                Text(trip.data.intake.approximate_dates.isEmpty ? "\(trip.data.intake.duration_days ?? 1) days" : trip.data.intake.approximate_dates).foregroundStyle(.secondary)
                                Text(LocalizedStringKey(trip.data.intake.planning_state)).font(.caption.weight(.semibold))
                            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                                .background(.background, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain)
                    }
                }.padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("PipPipGo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Get to know me", systemImage: "bubble.left.and.bubble.right") { showIntroduction = true }
                        Button("What Pip remembers", systemImage: "sparkles") { showMemory = true }
                        Button("Language", systemImage: "globe") { showSettings = true }
                        Button("Sign out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive, action: signOut)
                    } label: { Image(systemName: "person.crop.circle").accessibilityLabel("Settings") }
                }
            }
            .sheet(isPresented: $showIntroduction, onDismiss: { if startTripAfterIntroduction { startTripAfterIntroduction = false; showIntake = true } }) {
                TravelerIntroductionView(store: store, language: language) {
                    showIntroduction = false
                    store.newTrip(language: language); startTripAfterIntroduction = true
                }
            }
            .sheet(isPresented: $showIntake) { TripIntakeView(store: store) }
            .sheet(isPresented: $showMemory) { MemoryView(store: store) }
            .sheet(isPresented: $showSettings) {
                NavigationStack {
                    Form {
                        Picker("Application language", selection: $language) {
                            Text("English").tag("en"); Text("فارسی").tag("fa")
                        }
                        Text("Changing language keeps your trips and memories.")
                    }.navigationTitle("Language")
                }.presentationDetents([.medium])
            }
            .task { await store.refresh(); await store.loadIntroduction() }
            .refreshable { await store.refresh(); await store.loadIntroduction() }
        }
        .tint(.teal)
        .environment(\.locale, Locale(identifier: language))
        .environment(\.layoutDirection, language == "fa" ? .rightToLeft : .leftToRight)
    }
}

struct TravelerIntroductionView: View {
    @Bindable var store: IntelligenceStore
    let language: String
    let continueToTrip: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var speech = IntakeSpeech()
    @State private var keepTalking = false
    @State private var reviewMemory: String?
    @State private var showMemory = false
    private var done: Bool { store.introduction?.data.onboarding_done == true }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Let's get to know you").font(.largeTitle.bold())
                    if store.introduction?.data.messages.isEmpty != false {
                        Text("I'm Pip. I'll learn what matters to you, and you can correct me anytime.")
                        Text("Tell me about a trip or day out you really enjoyed. What made it good?").font(.title3.bold())
                    } else if let message = store.introduction?.data.messages.last(where: { $0.role == "pip" }) {
                        Text(message.text
                            .replacingOccurrences(of: "We can move on to your trip whenever you’re ready.", with: "")
                            .replacingOccurrences(of: "We can move on to your trip whenever you're ready.", with: "")
                            .trimmingCharacters(in: .whitespacesAndNewlines)).font(.title3)
                        ForEach(message.memory_observations ?? [], id: \.self) { value in
                            Button { reviewMemory = value; showMemory = true } label: { Text("Remember this? \(value)") }
                        }
                    }
                    if done && !keepTalking {
                        Text("That's enough to get started. I'll learn more as we go.")
                        Button("Continue with my trip") { speech.stop(); continueToTrip() }.buttonStyle(.borderedProminent)
                        Button("Keep talking") { keepTalking = true }
                    } else {
                        TextField("Type or speak…", text: $store.introductionAnswer, axis: .vertical)
                            .lineLimit(3...8).disabled(store.busy || store.hasPending).padding().background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                        Button(speech.recording ? "Stop" : "Speak", systemImage: speech.recording ? "stop.circle" : "mic") {
                            if speech.recording { speech.stop() }
                            else { let prefix = store.introductionAnswer; Task { await speech.start(language: language) { store.introductionAnswer = prefix.isEmpty ? $0 : prefix + " " + $0 } } }
                        }
                        if let error = speech.error { Text(error).font(.caption) }
                        Button("Continue") { speech.stop(); Task { await store.introduce(language: language) } }
                            .buttonStyle(.borderedProminent).disabled(store.busy || store.hasPending || store.introduction == nil || store.introductionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Skip for now") {
                            speech.stop()
                            Task { await store.introduce(language: language, skip: true); if store.error == nil && !store.hasPending { continueToTrip() } }
                        }.disabled(store.busy || store.hasPending || store.introduction == nil)
                    }
                    PipErrorView(store: store)
                    if store.busy { ProgressView("Pip is thinking…") }
                }.padding(22)
            }
                .scrollDismissesKeyboard(.interactively)
                .background(Color(.systemGroupedBackground))
                .toolbar { Button("Close") { speech.stop(); dismiss() } }
                .sheet(isPresented: $showMemory) { MemoryView(store: store, initialValue: reviewMemory ?? "") }
                .onDisappear { speech.stop() }
                .onChange(of: scenePhase) { _, phase in if phase == .background { speech.stop() } }
                .interactiveDismissDisabled(store.busy || store.hasPending || speech.recording)
        }
    }
}

struct PlanChangesView: View {
    let changes: PlanChanges
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !changes.unchanged.isEmpty { Text("Stays: \(changes.unchanged.joined(separator: ", "))") }
            if !changes.added.isEmpty { Text("Adds: \(changes.added.joined(separator: ", "))") }
            if !changes.changed.isEmpty { Text("Changes: \(changes.changed.joined(separator: ", "))") }
            if !changes.removed.isEmpty { Text("Removes: \(changes.removed.joined(separator: ", "))") }
        }.font(.subheadline)
    }
}

struct PipErrorView: View {
    @Bindable var store: IntelligenceStore
    var body: some View {
        if let error = store.error {
            VStack(alignment: .leading, spacing: 12) {
                Text(error).foregroundStyle(.red)
                if let conflict = store.conflict {
                    Text("This trip changed elsewhere. Your draft is still here.").font(.headline)
                    Text("Saved destination: \(conflict.data.intake.destination)")
                    Text("Saved notes: \(conflict.data.intake.notes)")
                    DisclosureGroup("Review saved trip") {
                        Text(String(data: (try? APIJSON.encoder().encode(conflict.data.intake)) ?? Data(), encoding: .utf8) ?? "").font(.caption).textSelection(.enabled)
                    }
                    Button("Keep my draft for a new save") { store.keepDraftAfterReview() }
                    Button("Use the saved trip", role: .destructive) { store.useServerAfterReview() }
                } else if store.hasPending {
                    Text("Your request is kept unchanged for a safe retry.").font(.caption)
                    Button("Retry same request") { Task { if store.pendingIntroduction != nil { await store.retryIntroduction() } else if store.pending != nil { await store.retry() } else { await store.retryAux() } } }.disabled(store.busy)
                } else {
                    Button("Reload") { Task { await store.refresh(); await store.loadIntroduction() } }.disabled(store.busy)
                }
            }.padding().background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct TripIntakeView: View {
    @Bindable var store: IntelligenceStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var inputNotice: String?
    @State private var waitingForReply = false
    @State private var answeringFollowup = false
    @State private var answer = ""
    @State private var acknowledgement = ""
    @State private var editSummary = false
    @State private var openedInitialSummary = false
    @State private var showPlan = false
    @State private var showUpload = false
    @State private var showTravel = false
    @State private var review: TripImport?
    @State private var speech = IntakeSpeech()
    private var locked: Bool { store.busy || store.hasPending }
    private var destination: String { store.draft.destination.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var heading: String {
        let place = destination.isEmpty ? String(localized: "your next trip") : destination
        if let name = store.preferredName { return String(localized: "\(name), let's plan \(place)") }
        return String(localized: "Let's plan \(place)")
    }
    private var activeAnswer: Binding<String> {
        Binding(get: { answeringFollowup ? answer : store.draft.existing_plans }, set: { text in
            if answeringFollowup { answer = text } else { store.draft.existing_plans = text }
        })
    }
    private var proposedImports: [TripImport] { store.selected?.data.imports.filter { $0.status == "proposed" } ?? [] }
    private var hasReviewedBooking: Bool { store.selected?.data.imports.contains { $0.status == "confirmed" } == true }
    private var step: String { store.selected?.data.conversation?.next_step ?? "bookings" }
    private var readyToPlan: Bool { step == "ready_to_plan" }
    private var needsTravelMode: Bool { ["travel_mode", "flights"].contains(step) }
    private var progressQuestion: String? { store.selected?.data.conversation?.question }
    private var inputLayout: AnyLayout { dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14)) : AnyLayout(HStackLayout(spacing: 18)) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(heading).font(.title.bold()).accessibilityAddTraits(.isHeader)
                    if !destination.isEmpty {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(destination).font(.headline)
                                Text(tripTiming).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Edit") { speech.stop(); editSummary = true }
                        }.padding(14).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }
                    if destination.isEmpty {
                        Button("Add destination and timing") { editSummary = true }.buttonStyle(.borderedProminent)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            if answeringFollowup {
                                Text(acknowledgement.isEmpty ? (progressQuestion ?? "") : acknowledgement).font(.title3).accessibilityIdentifier("intake.nextQuestion")
                            } else {
                                Text("What's already decided?").font(.title2.bold())
                                Text("Tell me in your own words, or add a booking.").foregroundStyle(.secondary)
                            }
                            if !readyToPlan && step != "review_import" {
                            TextField("Type or speak…", text: activeAnswer, axis: .vertical)
                                .lineLimit(3...7).padding(14)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                                .accessibilityIdentifier("intake.answer")
                            inputLayout {
                                Button(speech.recording ? "Stop" : "Speak", systemImage: speech.recording ? "stop.circle" : "mic") {
                                    if speech.recording { speech.stop() }
                                    else { let prefix = activeAnswer.wrappedValue; Task { await speech.start(language: store.draft.language) { activeAnswer.wrappedValue = prefix.isEmpty ? $0 : prefix + " " + $0 } } }
                                }
                                Button("Upload", systemImage: "paperclip") { Task { await upload() } }
                                if !answeringFollowup {
                                    Button("Nothing yet") { store.draft.existing_plans = String(localized: "Nothing booked or decided yet."); Task { await continueConversation() } }.foregroundStyle(.secondary)
                                }
                            }.font(.subheadline)
                            }
                            if let message = speech.error { Text(message).font(.caption).foregroundStyle(.secondary) }
                            if answeringFollowup && needsTravelMode {
                                ViewThatFits(in: .horizontal) {
                                    HStack { travelChoices }
                                    VStack(alignment: .leading, spacing: 10) { travelChoices }
                                }
                            }
                            if answeringFollowup && !readyToPlan && ["bookings", "travel_mode", "flights", "lodging", "transfers"].contains(step) {
                                Button("I don't know yet; skip") { Task { await skipQuestion() } }.font(.subheadline)
                            }
                            if answeringFollowup && step == "transfers" {
                                Button("Add arranged transfers") { showTravel = true }
                            }
                            if answeringFollowup && step != "review_import" && !readyToPlan {
                                Button("Start a provisional plan") { Task { await makePlan() } }.font(.subheadline)
                            }
                            ForEach(proposedImports) { item in
                                Button("Review \(item.filename)", systemImage: "doc.text.magnifyingglass") { speech.stop(); review = item }
                            }
                        }.disabled(locked)
                    }
                    if let inputNotice { Text(inputNotice).font(.caption).foregroundStyle(.secondary) }
                    PipErrorView(store: store)
                    if store.busy { ProgressView("Pip is thinking…") }
                }.padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .tint(.teal)
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { if let item = proposedImports.first { review = item } else if readyToPlan { await makePlan() } else { await continueConversation() } }
                } label: {
                    Text(!proposedImports.isEmpty ? "Review imported details" : readyToPlan ? "Create a lightweight plan" : "Continue").font(.headline).frame(maxWidth: .infinity).padding(12)
                }.buttonStyle(.borderedProminent)
                    .disabled(locked || destination.isEmpty)
                    .padding(.horizontal, 22).padding(.vertical, 10).background(.regularMaterial)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { speech.stop(); dismiss() } } }
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                guard !openedInitialSummary else { return }
                openedInitialSummary = true
                if destination.isEmpty { editSummary = true }
                else if let current = store.selected {
                    let progress = current.data.conversation
                    if (progress?.turns ?? 0) > 0 || progress?.next_step != "bookings" && progress != nil {
                        answeringFollowup = true
                        acknowledgement = progress?.question ?? current.data.messages.last(where: { $0.role == "pip" })?.text ?? ""
                    } else if !current.data.messages.isEmpty {
                        answeringFollowup = true
                        acknowledgement = current.data.messages.last(where: { $0.role == "pip" })?.text ?? ""
                    }
                }
            }
            .sheet(isPresented: $editSummary) { TripSummaryEditor(intake: $store.draft) }
            .sheet(isPresented: $showPlan) {
                if let id = store.selectedID { NavigationStack { PipTripView(store: store, tripID: id, tab: "plan") } }
            }
            .sheet(isPresented: $showUpload) { ImportView(store: store) }
            .sheet(item: $review, onDismiss: refreshDraft) { item in ImportReviewView(store: store, item: item) }
            .sheet(isPresented: $showTravel, onDismiss: {
                refreshDraft()
                if !answer.isEmpty && !store.hasPending && store.error == nil { Task { await continueConversation() } }
            }) { DoorToDoorView(store: store) }
            .onDisappear { speech.stop() }
            .onChange(of: scenePhase) { _, phase in if phase == .background { speech.stop() } }
            .onChange(of: store.selected?.version) { _, _ in
                if waitingForReply && !store.hasPending && store.error == nil { finishReply() }
            }
            .interactiveDismissDisabled(locked || speech.recording)
        }
    }
    private var tripTiming: String {
        let timing = [store.draft.start_date, store.draft.end_date].compactMap { $0 }.joined(separator: " – ")
        let when = timing.isEmpty ? store.draft.approximate_dates : timing
        let days = store.draft.duration_days.map { String(localized: "\($0) days") } ?? ""
        return [when, days].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    @ViewBuilder private var travelChoices: some View {
        Button("I have flights") { Task { await chooseFlying(booked: true) } }.buttonStyle(.bordered)
        Button("Help me find flights") { Task { await chooseFlying(booked: false) } }.buttonStyle(.bordered)
        Menu("Other ways") {
            ForEach(["drive", "train", "other"], id: \.self) { mode in
                Button(LocalizedStringKey(mode)) {
                    var travel = store.draft.door_to_door ?? DoorToDoorTravel(); travel.mode = mode; store.draft.door_to_door = travel
                    answer = "I will travel by " + mode
                }
            }
        }
    }
    private func refreshDraft() {
        if let current = store.selected, !store.hasPending {
            store.edit(current)
            if let progress = current.data.conversation, progress.next_step != "bookings" {
                answeringFollowup = true
                acknowledgement = progress.question ?? ""
            }
        }
    }
    private func skipQuestion() async {
        speech.stop()
        await store.act(PipAction(action: "skip_intake", skip_topic: step))
        if store.error == nil && !store.hasPending { refreshDraft(); answer = "" }
    }
    private func makePlan() async {
        speech.stop()
        await store.saveIntake()
        guard store.error == nil && !store.hasPending else { return }
        await store.act(PipAction(action: "plan"))
        if store.error == nil && !store.hasPending { showPlan = true }
    }
    private func chooseFlying(booked: Bool) async {
        speech.stop()
        var travel = store.draft.door_to_door ?? DoorToDoorTravel(); travel.mode = "fly"; travel.booking_status = booked ? "booked" : "not_booked"
        store.draft.door_to_door = travel
        answer = booked ? "I have booked flights; use the reviewed details I added." : "I want help finding flights; nothing is booked yet."
        await store.saveIntake()
        if store.error == nil && !store.hasPending { showTravel = true }
    }
    private func upload() async {
        speech.stop(); await store.saveIntake()
        if store.error == nil && !store.hasPending { showUpload = true }
    }
    private func continueConversation() async {
        speech.stop()
        let response = activeAnswer.wrappedValue.isEmpty && !answeringFollowup && hasReviewedBooking ? "Use the booking details I reviewed and confirmed." : activeAnswer.wrappedValue
        guard !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            inputNotice = String(localized: "Tell Pip a little, add a booking, or choose Nothing yet."); return
        }
        inputNotice = nil
        if store.draft.start_date == nil && store.draft.approximate_dates.localizedCaseInsensitiveContains("long weekend") {
            editSummary = true; return
        }
        await store.saveIntake()
        guard store.error == nil && !store.hasPending else { return }
        waitingForReply = true
        await store.act(PipAction(action: "intake", text: response))
        guard store.error == nil && !store.hasPending else { return }
        finishReply()
    }
    private func finishReply() {
        guard waitingForReply else { return }
        refreshDraft()
        acknowledgement = store.selected?.data.messages.last(where: { $0.role == "pip" })?.text ?? ""
        waitingForReply = false; answeringFollowup = true; answer = ""
    }
}

struct TripSummaryEditor: View {
    @Binding var intake: TripIntake
    @Environment(\.dismiss) private var dismiss
    @State private var useDates = false
    @State private var start = Date()
    @State private var end = Date()
    private var ambiguous: Bool { intake.start_date == nil && intake.approximate_dates.localizedCaseInsensitiveContains("long weekend") }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Destination", text: $intake.destination).accessibilityIdentifier("intake.destination")
                TextField("When?", text: $intake.approximate_dates)
                Stepper("\(intake.duration_days ?? 3) days", value: Binding(get: { intake.duration_days ?? 3 }, set: { intake.duration_days = $0 }), in: 1...365)
                if ambiguous { Text("Which dates do you mean by next long weekend? Holidays and travel dates vary, so please confirm.") }
                if ambiguous { Text("Suggested dates are a starting point, not a holiday assumption. Adjust them before confirming.").font(.caption) }
                Toggle("Use exact dates", isOn: $useDates)
                if useDates {
                    DatePicker("Start", selection: $start, displayedComponents: .date)
                    DatePicker("End", selection: $end, in: start..., displayedComponents: .date)
                }
            }.navigationTitle("Destination and timing")
                .toolbar { Button("Done") {
                    if useDates {
                        let format = DateFormatter(); format.calendar = Calendar(identifier: .gregorian); format.locale = Locale(identifier: "en_US_POSIX"); format.dateFormat = "yyyy-MM-dd"
                        intake.start_date = format.string(from: start); intake.end_date = format.string(from: max(start, end))
                        intake.duration_days = (Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: start), to: Calendar.current.startOfDay(for: max(start, end))).day ?? 0) + 1
                    } else { intake.start_date = nil; intake.end_date = nil }
                    dismiss()
                }.disabled(intake.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (ambiguous && !useDates)) }
                .onAppear {
                    let format = DateFormatter(); format.dateFormat = "yyyy-MM-dd"; format.locale = Locale(identifier: "en_US_POSIX")
                    if let value = intake.start_date.flatMap({ format.date(from: $0) }) { start = value; useDates = true }
                    if let value = intake.end_date.flatMap({ format.date(from: $0) }) { end = value }
                    else { end = Calendar.current.date(byAdding: .day, value: max(0, (intake.duration_days ?? 3) - 1), to: start) ?? start }
                    if ambiguous {
                        useDates = true
                        start = Calendar.current.nextDate(after: Date(), matching: DateComponents(hour: 12, weekday: 6), matchingPolicy: .nextTime) ?? Date()
                        end = Calendar.current.date(byAdding: .day, value: max(0, (intake.duration_days ?? 3) - 1), to: start) ?? start
                    }
                }
        }
    }
}

@MainActor @Observable
final class IntakeSpeech {
    var recording = false
    var error: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    func start(language: String, update: @escaping @MainActor (String) -> Void) async {
        stop(); error = nil
        let ticket = generation
        let speechPermission = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard ticket == generation else { return }
        guard speechPermission == .authorized else { error = String(localized: "Allow speech recognition in Settings, or type your answer."); return }
        let microphone = await withCheckedContinuation { continuation in AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) } }
        guard ticket == generation else { return }
        guard speechPermission == .authorized && microphone else { error = String(localized: "Allow microphone and speech recognition in Settings, or type your answer."); return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language)), recognizer.isAvailable else { error = String(localized: "Speech isn't available right now. You can still type."); return }
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.record, mode: .measurement); try session.setActive(true)
            let engine = AVAudioEngine(); let request = SFSpeechAudioBufferRecognitionRequest(); request.shouldReportPartialResults = true
            let input = engine.inputNode; let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            self.engine = engine; self.request = request
            task = recognizer.recognitionTask(with: request) { result, failure in
                let text = result?.bestTranscription.formattedString; let finished = result?.isFinal == true || failure != nil
                Task { @MainActor in
                    guard ticket == self.generation else { return }
                    if let text { update(text) }
                    if finished { self.stop() }
                }
            }
            engine.prepare(); try engine.start(); recording = true
        } catch { self.error = String(localized: "Couldn't start the microphone. You can still type."); stop() }
    }
    func stop() {
        generation = UUID(); recording = false
        let hadAudioSession = engine != nil
        engine?.stop(); engine?.inputNode.removeTap(onBus: 0); engine = nil
        request?.endAudio(); request = nil; task?.cancel(); task = nil
        if hadAudioSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
}

struct PipTripView: View {
    @Bindable var store: IntelligenceStore
    let tripID: UUID
    @State private var showIntake = false
    @State private var showContext = false
    @State private var showImport = false
    @State private var showTravel = false
    @State private var review: TripImport?
    @State var tab = "conversation"
    @State private var memorySuggestion: String?
    @State private var showMemory = false
    var body: some View {
        Group {
            if let trip = store.journeys.first(where: { $0.id == tripID.uuidString.lowercased() }) {
                VStack(spacing: 0) {
                    Picker("View", selection: $tab) {
                        Text("Talk to Pip").tag("conversation"); Text("Our plan").tag("plan"); Text("Trip details").tag("details")
                    }.pickerStyle(.segmented).padding()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if trip.data.plan_needs_review == true {
                                Text("Travel details changed. Review the new transfer times and update your activity suggestions. Confirmed reservations are protected.").foregroundStyle(.orange)
                                Button("Update affected plans") { Task { await store.act(PipAction(action: "plan")); tab = "plan" } }.disabled(store.busy || store.hasPending)
                            }
                            if tab == "conversation" {
                                if let progress = trip.data.conversation, trip.data.plan.isEmpty && trip.data.proposal == nil {
                                    Button(progress.next_step == "review_import" ? "Review imported details" : "Continue planning") { store.edit(trip); showIntake = true }
                                }
                                if trip.data.messages.isEmpty {
                                    Text("🦆 Hi, I'm Pip.").font(.title2.bold())
                                    Text("I'll travel with you, help when you need me, and get to know what you like along the way.")
                                    if store.memories.isEmpty && !trip.data.onboarding_done {
                                        Text("Tell me about a trip, vacation, or even a day out that you really enjoyed. What made it good?").font(.headline)
                                    } else { Text("What would make this trip feel right for you?").font(.headline) }
                                }
                                ForEach(trip.data.messages) { message in
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(message.role == "pip" ? "Pip 🦆" : "You").font(.caption.bold()).foregroundStyle(.secondary)
                                        Text(message.text).textSelection(.enabled)
                                        ForEach(message.memory_observations ?? [], id: \.self) { observation in
                                            Button { memorySuggestion = observation; showMemory = true } label: { Text("Remember this? \(observation)") }.font(.caption)
                                        }
                                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(message.role == "pip" ? Color.teal.opacity(0.08) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                                }
                                if trip.data.onboarding_done || !store.memories.isEmpty {
                                    Button("Create a lightweight plan", systemImage: "sparkles") { Task { await store.act(PipAction(action: "plan")); tab = "plan" } }
                                } else {
                                    Button("Skip; continue with my trip") { Task { await store.act(PipAction(action: "skip_onboarding")) } }
                                }
                            } else if tab == "plan" {
                                Text("Room to explore").font(.title.bold())
                                if trip.data.proposal == nil, let message = trip.data.messages.last, message.role == "pip", message.action == "feedback" {
                                    Text(message.text).font(.headline)
                                }
                                TravelSummaryView(trip: trip.data)
                                Button("Flights and transfers") { store.edit(trip); showTravel = true }
                                Text("Suggestions are not bookings. Live hours, weather and availability have not been verified.").font(.caption).foregroundStyle(.secondary)
                                ForEach(trip.data.intake.commitments) { item in
                                    Label(item.title, systemImage: "lock.fill").font(.headline)
                                    Text(item.timing + " · " + item.location).foregroundStyle(.secondary)
                                }
                                ForEach(trip.data.imports.filter { $0.status == "confirmed" }) { item in
                                    ForEach(Array(item.confirmed_facts.enumerated()), id: \.offset) { _, fact in
                                        Label(fact.title, systemImage: "checkmark.seal")
                                        Text(fact.details).font(.caption)
                                    }
                                }
                                ForEach(trip.data.plan) { item in PlanItemView(item: item) }
                                if let proposal = trip.data.proposal {
                                    Divider(); Text("A suggestion for you").font(.title2.bold()); Text(proposal.explanation)
                                    if let changes = proposal.changes {
                                        PlanChangesView(changes: changes)
                                    }
                                    Text("Confirmed bookings stay unchanged.").font(.caption).foregroundStyle(.secondary)
                                    ForEach(proposal.items) { item in PlanItemView(item: item) }
                                    HStack {
                                        Button("Accept changes") { Task { await store.act(PipAction(action: "accept_plan", proposal_id: proposal.id)) } }.buttonStyle(.borderedProminent)
                                        Button("Keep current plan") { Task { await store.act(PipAction(action: "reject_plan", proposal_id: proposal.id)) } }.buttonStyle(.bordered)
                                    }
                                } else if trip.data.plan.isEmpty {
                                    Button("Create a lightweight plan") { Task { await store.act(PipAction(action: "plan")) } }.buttonStyle(.borderedProminent)
                                }
                            } else {
                                Text(trip.data.intake.destination).font(.title.bold())
                                Text(trip.data.intake.constraints)
                                Text(trip.data.intake.lodging.property_name)
                                Text(trip.data.intake.lodging.address)
                                Text(trip.data.intake.existing_plans)
                                TravelSummaryView(trip: trip.data)
                                Button("Flights and transfers") { store.edit(trip); showTravel = true }
                                Button("Travelers and reservations") { store.edit(trip); showContext = true }
                                Button("Edit trip details") { store.edit(trip); showIntake = true }
                                Button("Import existing plans", systemImage: "paperclip") { showImport = true }
                                ForEach(trip.data.imports) { item in
                                    VStack(alignment: .leading) {
                                        Text(item.filename).font(.headline)
                                        Text(LocalizedStringKey(item.status))
                                        if item.status == "proposed" { Button("Review extracted details") { review = item } }
                                    }.padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                                }
                            }
                            PipErrorView(store: store)
                            if store.busy { ProgressView("Pip is thinking…") }
                        }.padding(20)

                    }
                    if tab != "details" {
                        HStack(alignment: .bottom) {
                            Button { showImport = true } label: { Image(systemName: "plus.circle.fill").font(.title2).accessibilityLabel("Attach existing plans") }
                            TextField("Tell Pip…", text: $store.composer, axis: .vertical).lineLimit(1...5).padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                            Button {
                                Task { await store.act(PipAction(action: (tab == "plan" || !trip.data.plan.isEmpty) ? "feedback" : (trip.data.conversation != nil && !trip.data.onboarding_done ? "intake" : "conversation"), text: store.composer)) }
                            } label: { Image(systemName: "arrow.up.circle.fill").font(.title).accessibilityLabel("Send") }
                            .disabled(store.composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }.padding().disabled(store.busy || store.hasPending)
                    }
                }
                .navigationTitle(trip.data.intake.destination).navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showMemory) { MemoryView(store: store, initialValue: memorySuggestion ?? "") }
                .sheet(isPresented: $showIntake) { TripIntakeView(store: store) }
                .sheet(isPresented: $showContext) { DetailedTripContextView(store: store) }
                .sheet(isPresented: $showImport) { ImportView(store: store) }
                .sheet(isPresented: $showTravel) { DoorToDoorView(store: store) }
                .sheet(item: $review) { item in ImportReviewView(store: store, item: item) }
            } else { ContentUnavailableView("Trip unavailable", systemImage: "suitcase") }
        }.onAppear { store.selectedID = tripID }
    }
}
struct PlanItemView: View {
    let item: PipPlanItem
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.timing).font(.caption).foregroundStyle(.teal)
            Text(item.title).font(.headline); Text(item.location).font(.subheadline)
            Text(item.rationale).font(.caption).foregroundStyle(.secondary)
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
struct ImportView: View {
    @Bindable var store: IntelligenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var file: PipImportRequest?
    @State private var photo: PhotosPickerItem?
    @State private var pickFile = false
    @State private var message: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Send a booking, itinerary, or screenshot. Pip proposes details for you to review before anything is used in your plan.")
                    Text("The selected content is sent to Pip's server and OpenAI for extraction. Raw files are not saved by Pip. Extracted details stay with this trip.").font(.caption)
                }
                Section("Already booked anything?") {
                    TextField("Paste booking details", text: $text, axis: .vertical).lineLimit(4...10)
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose photo", systemImage: "photo") }
                    Button("Choose PDF or DOCX", systemImage: "doc") { pickFile = true }
                    if let file { Text(file.filename) }
                    if let message { Text(message).foregroundStyle(.red) }
                }
                Button("Extract for review") {
                    Task {
                        var request = file ?? PipImportRequest(filename: "Pasted details"); request.text = text
                        await store.importDetails(request)
                        if store.error == nil { dismiss() }
                    }
                }.disabled(store.busy || store.hasPending || (file == nil && text.isEmpty))
                PipErrorView(store: store)
            }.navigationTitle("Send it to Pip")
                .toolbar { Button("Close") { dismiss() } }
                .fileImporter(isPresented: $pickFile, allowedContentTypes: [.pdf, UTType(filenameExtension: "docx")!]) { result in
                    do {
                        let url = try result.get(); let access = url.startAccessingSecurityScopedResource()
                        defer { if access { url.stopAccessingSecurityScopedResource() } }
                        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                        guard size <= 5_000_000 else { message = String(localized: "Please use a file smaller than 5 MB."); return }
                        let data = try Data(contentsOf: url)
                        file = PipImportRequest(filename: url.lastPathComponent, content_base64: data.base64EncodedString())
                    } catch { message = error.localizedDescription }
                }
                .onChange(of: photo) { _, selection in
                    Task {
                        do {
                            if let data = try await selection?.loadTransferable(type: Data.self), let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.7) {
                                guard jpeg.count <= 5_000_000 else { message = String(localized: "Please use a file smaller than 5 MB."); return }
                                file = PipImportRequest(filename: "Photo.jpg", content_base64: jpeg.base64EncodedString())
                            }
                        } catch { message = error.localizedDescription }
                    }
                }
        }
    }
}
struct ImportReviewView: View {
    @Bindable var store: IntelligenceStore
    let item: TripImport
    @Environment(\.dismiss) private var dismiss
    @State private var facts: [ImportFact] = []
    @State private var flights: [FlightSegment] = []
    var body: some View {
        NavigationStack {
            Form {
                Text(item.explanation)
                ForEach(facts.indices, id: \.self) { index in
                    Section {
                        TextField("Title", text: $facts[index].title)
                        TextField("Details", text: $facts[index].details, axis: .vertical)
                        TextField("Date and time", text: $facts[index].timing)
                        TextField("Location", text: $facts[index].location)
                        Button("Remove this detail", role: .destructive) { facts.remove(at: index) }
                    }
                }
                if !flights.isEmpty {
                    Section { Text("Review every flight. Direction and segment order replace any saved flight with the same direction/order. Other bookings remain unchanged.") }
                    ForEach($flights) { $flight in
                        Section("Flight") {
                            FlightFields(flight: $flight)
                            Button("Remove flight", role: .destructive) { flights.removeAll { $0.id == flight.id } }
                        }
                    }
                }
                Button("Confirm these details") { Task { await review(facts, flights: flights) } }.disabled((facts.isEmpty && flights.isEmpty) || store.busy || store.hasPending)
                Button("Reject import", role: .destructive) { Task { await review([]) } }
                PipErrorView(store: store)
            }.navigationTitle("Review before adding")
                .onAppear { facts = item.facts; flights = item.flights ?? [] }
        }
    }
    func review(_ selected: [ImportFact], flights: [FlightSegment] = []) async {
        await store.act(PipAction(action: "review_import", import_id: item.id, facts: selected, flights: flights))
        if store.error == nil { dismiss() }
    }
}
struct MemoryView: View {
    @Bindable var store: IntelligenceStore
    var initialValue = ""
    @State private var editing: APIRecord<TravelerMemory>?
    @State private var value = ""
    @State private var tripOnly = false
    @State private var forgetting: APIRecord<TravelerMemory>?
    @State private var preferredName = ""
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("You can correct Pip anytime. Temporary trip needs stay separate from what you want remembered.") }
                Section("What should Pip call you?") {
                    TextField("Preferred name", text: $preferredName).textContentType(.nickname)
                    Button("Save name") {
                        Task {
                            let existing = store.memories.filter { !$0.deleted && $0.data.key == "preferred_name" && $0.data.scope == "persistent" }.max { $0.revision < $1.revision }
                            var memory = TravelerMemory()
                            memory.key = "preferred_name"
                            memory.value = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
                            memory.original_text = memory.value
                            memory.status = "explicit"
                            await store.saveMemory(memory, id: existing.flatMap { UUID(uuidString: $0.id) } ?? UUID(), version: existing?.version ?? 0)
                        }
                    }.disabled(preferredName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy || store.hasPending)
                }
                ForEach(store.memories) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.data.value)
                        Text(LocalizedStringKey(item.data.scope)).font(.caption).foregroundStyle(.secondary)
                        Button("Correct this") { editing = item; value = item.data.value; tripOnly = item.data.scope == "trip_specific" }
                        Button("Don't remember that", role: .destructive) { forgetting = item }
                    }
                }
                Section("Something you'd like Pip to remember?") {
                    TextField("In your own words", text: $value, axis: .vertical)
                    if store.selectedID != nil { Toggle("Only for this trip", isOn: $tripOnly) }
                    Button("Remember this") {
                        Task {
                            var memory = TravelerMemory(); memory.key = UUID().uuidString; memory.value = value; memory.original_text = value
                            if tripOnly { memory.scope = "trip_specific"; memory.trip_id = store.selectedID }
                            if !initialValue.isEmpty { memory.status = "confirmed"; memory.source_type = "conversation_review" }
                            if let editing { memory.key = editing.data.key; memory.status = "confirmed" }
                            await store.saveMemory(memory, id: editing.flatMap { UUID(uuidString: $0.id) } ?? UUID(), version: editing?.version ?? 0)
                            if store.error == nil { value = ""; editing = nil }
                        }
                    }.disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.busy)
                }
                PipErrorView(store: store)
            }.navigationTitle("What Pip remembers")
                .onAppear { preferredName = store.preferredName ?? ""; if !initialValue.isEmpty { value = initialValue } }
                .confirmationDialog("Forget this memory?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
                    Button("Forget", role: .destructive) { if let forgetting { Task { await store.forget(forgetting); self.forgetting = nil } } }
                }
        }
    }
}

struct FlightFields: View {
    @Binding var flight: FlightSegment
    var body: some View {
        Group {
            Picker("Journey", selection: $flight.direction) { Text("Outbound").tag("outbound"); Text("Return").tag("return") }
            Stepper("Segment \(flight.sequence)", value: $flight.sequence, in: 1...20)
            TextField("Airline", text: $flight.airline)
            TextField("Flight number", text: $flight.flight_number).textInputAutocapitalization(.characters)
            TextField("Departure airport, e.g. SAN", text: $flight.departure_airport).textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("Arrival airport, e.g. JFK, LGA, EWR", text: $flight.arrival_airport).textInputAutocapitalization(.characters).autocorrectionDisabled()
            TextField("Departure local: YYYY-MM-DDTHH:MM", text: $flight.departure_local).autocorrectionDisabled()
            TextField("Departure time zone, e.g. America/Los_Angeles", text: $flight.departure_timezone).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Arrival local: YYYY-MM-DDTHH:MM", text: $flight.arrival_local).autocorrectionDisabled()
            TextField("Arrival time zone, e.g. America/New_York", text: $flight.arrival_timezone).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Departure terminal (if known)", text: $flight.departure_terminal)
            TextField("Arrival terminal (if known)", text: $flight.arrival_terminal)
            TextField("Booking reference", text: $flight.booking_reference)
            Picker("Flight status", selection: $flight.status) {
                Text("Booked").tag("booked"); Text("Changed").tag("changed")
                Text("Cancelled").tag("cancelled"); Text("Unknown").tag("unknown")
            }
        }
    }
}

struct DoorToDoorView: View {
    @Bindable var store: IntelligenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var showUpload = false
    @State private var showTransfers = false
    @State private var review: TripImport?
    private var travel: Binding<DoorToDoorTravel> {
        Binding(get: { store.draft.door_to_door ?? DoorToDoorTravel() }, set: { store.draft.door_to_door = $0 })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("How will you get there?") {
                    Picker("Fly, drive, train, or something else?", selection: travel.mode) {
                        Text("Not sure yet").tag("unknown"); Text("Fly").tag("fly")
                        Text("Drive").tag("drive"); Text("Train").tag("train"); Text("Something else").tag("other")
                    }
                    TextField("Starting from (city or pickup point)", text: travel.home)
                }
                if travel.wrappedValue.mode == "fly" {
                    Section("Do you already have your flights?") {
                        Picker("Flights", selection: travel.booking_status) {
                            Text("Not yet").tag("not_booked"); Text("Booked").tag("booked"); Text("Not sure").tag("unknown")
                        }
                        TextField("Departure airport or city", text: travel.departure_airport)
                        Button("Upload flight confirmation", systemImage: "paperclip") {
                            Task {
                                await store.saveIntake()
                                if store.error == nil && !store.hasPending { showUpload = true }
                            }
                        }
                        Button("Enter flight details", systemImage: "airplane") { addFlight("outbound") }
                        Link("Find flights", destination: travel.wrappedValue.flightSearchURL(destination: store.draft.destination, when: store.draft.approximate_dates, start: store.draft.start_date, end: store.draft.end_date))
                        Text("Opens an external flight search with known trip details. Searching does not book a flight; add your booking whenever you're ready.").font(.caption)
                    }
                    ForEach(travel.flights) { $flight in
                        Section("Flight") {
                            FlightFields(flight: $flight)
                            Button("Remove flight", role: .destructive) { travel.wrappedValue.flights.removeAll { $0.id == flight.id } }
                        }
                    }
                    Section {
                        Button("Add outbound connection") { addFlight("outbound") }
                        Button("Add return flight or connection") { addFlight("return") }
                        Text("Review local dates, times and time zones before saving. Leave unknown fields blank; your plan will stay provisional.").font(.caption)
                    }
                    Section {
                        Button(showTransfers ? "Hide transfers for now" : "Next: airport transfers") { showTransfers.toggle() }
                    }
                    if showTransfers {
                    Section("What ground transportation is already arranged?") {
                        Text("Consider rideshare, a drop-off, parking, shuttle, transit, taxi or rental car. Pickup points and travel times need checking for your actual airport.")
                    }
                    ForEach(travel.transfers) { $transfer in
                        Section(LocalizedStringKey(transfer.leg)) {
                            Picker("Transport", selection: $transfer.mode) {
                                ForEach(["not_sure", "rideshare", "drop_off", "parking", "shuttle", "transit", "taxi", "rental_car"], id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                            }
                            Toggle("Already arranged", isOn: $transfer.arranged)
                            TextField("Pickup point", text: $transfer.pickup_point)
                            TextField("Luggage needs", text: $transfer.luggage)
                            TextField("Estimated travel minutes (unknown if blank)", value: $transfer.duration_minutes, format: .number).keyboardType(.numberPad)
                            if transfer.leg == "home_to_airport" || transfer.leg == "hotel_to_airport" {
                                Stepper("Airport buffer: \(transfer.airport_buffer_minutes) min", value: $transfer.airport_buffer_minutes, in: 0...600, step: 15)
                            } else {
                                Stepper("Arrival / baggage: \(transfer.baggage_minutes) min", value: $transfer.baggage_minutes, in: 0...300, step: 15)
                                if transfer.leg == "airport_to_hotel" { Stepper("Rest after arrival: \(transfer.rest_minutes) min", value: $transfer.rest_minutes, in: 0...1440, step: 15) }
                            }
                            TextField("Transfer notes", text: $transfer.notes, axis: .vertical)
                        }
                    }
                    Section { Text("Buffers are editable planning estimates, not airline advice or live traffic. Allow more time where your airline, international check-in, baggage or accessibility needs require it.").font(.caption) }
                    }
                } else {
                    Section { TextField("Journey details or anything already arranged", text: $store.draft.transportation_notes, axis: .vertical) }
                }
                if let trip = store.selected {
                    ForEach(trip.data.imports.filter { $0.status == "proposed" }) { item in
                        Button("Review \(item.filename)") {
                            Task {
                                await store.saveIntake()
                                if store.error == nil && !store.hasPending { review = item }
                            }
                        }
                    }
                }
                Section {
                    Button("Save reviewed travel details") { Task { await save(updatePlan: false) } }
                    Button("Save and update activity suggestions") { Task { await save(updatePlan: true) } }
                    Text("Updated transfer windows are recalculated on save. Existing activities stay unchanged until you accept new suggestions; confirmed reservations are protected.").font(.caption)
                }
            }
            .disabled(store.busy || store.hasPending)
            .safeAreaInset(edge: .bottom) { if store.error != nil { PipErrorView(store: store).padding() } }
            .navigationTitle("Door to door")
            .toolbar { Button("Close") { dismiss() } }
            .interactiveDismissDisabled(store.busy || store.hasPending)
            .onAppear { prepareTransfers() }
            .sheet(isPresented: $showUpload, onDismiss: reloadDraft) { ImportView(store: store) }
            .sheet(item: $review, onDismiss: reloadDraft) { item in ImportReviewView(store: store, item: item) }
        }
    }
    private func prepareTransfers() {
        var value = travel.wrappedValue
        for leg in DoorToDoorTravel.legs where !value.transfers.contains(where: { $0.leg == leg }) { value.transfers.append(GroundTransfer(leg: leg)) }
        travel.wrappedValue = value
    }
    private func reloadDraft() { if let trip = store.selected, !store.hasPending { store.edit(trip); prepareTransfers() } }
    private func addFlight(_ direction: String) {
        var flight = FlightSegment(); flight.direction = direction
        flight.sequence = (travel.wrappedValue.flights.filter { $0.direction == direction }.map(\.sequence).max() ?? 0) + 1
        travel.wrappedValue.flights.append(flight)
    }
    private func save(updatePlan: Bool) async {
        await store.saveIntake()
        guard store.error == nil && !store.hasPending else { return }
        if updatePlan { await store.act(PipAction(action: "plan")) }
        if store.error == nil && !store.hasPending { dismiss() }
    }
}

struct TravelSummaryView: View {
    let trip: Journey
    var body: some View {
        if let travel = trip.intake.door_to_door, travel.mode == "fly" {
            VStack(alignment: .leading, spacing: 10) {
                Text("Door to door").font(.headline)
                if trip.travel_summary?.provisional != false { Text("Provisional—some details or arrangements need confirmation.").font(.caption).foregroundStyle(.orange) }
                ForEach(travel.flights.sorted { ($0.direction, $0.sequence) < ($1.direction, $1.sequence) }) { flight in
                    Text("\(flight.departure_airport.isEmpty ? "?" : flight.departure_airport) → \(flight.arrival_airport.isEmpty ? "?" : flight.arrival_airport) · \(flight.airline) \(flight.flight_number)").font(.subheadline.bold())
                    Text("\(flight.departure_local) \(flight.departure_timezone) → \(flight.arrival_local) \(flight.arrival_timezone)").font(.caption)
                    Text(LocalizedStringKey(flight.status)).font(.caption)
                }
                if let summary = trip.travel_summary {
                    ForEach(summary.legs) { leg in
                        Text(LocalizedStringKey(leg.leg)).font(.subheadline.bold())
                        Text("\(leg.airport.isEmpty ? "Airport unknown" : leg.airport) · \(leg.time_zone)").font(.caption)
                        if let leave = leg.leave_at, let arrive = leg.arrive_at { Text("Leave \(leave) · arrive \(arrive)").font(.caption) }
                    }
                    ForEach(summary.windows.keys.sorted(), id: \.self) { key in
                        Text(LocalizedStringKey(key)).font(.caption.bold())
                        Text(summary.windows[key] ?? "").font(.caption)
                    }
                    ForEach(summary.warnings, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
                }
            }.padding().background(Color.teal.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

struct DetailedTripContextView: View {
    @Bindable var store: IntelligenceStore
    @Environment(\.dismiss) private var dismiss
    @State private var step = 1
    private var locked: Bool { store.busy || store.hasPending }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text("Only what matters for this trip. You can add more later.").foregroundStyle(.secondary) }
                if step == 1 {
                    Section("Who's coming?") {
                        if store.draft.travelers.isEmpty { Text("Just me for now").foregroundStyle(.secondary) }
                        ForEach($store.draft.travelers) { $traveler in
                            VStack(alignment: .leading) {
                                TextField("Name or nickname (optional)", text: $traveler.name)
                                TextField("Relationship (optional)", text: $traveler.relationship)
                                TextField("Age or age range (optional)", text: $traveler.age_or_range)
                                TextField("Preferred language (optional)", text: $traveler.language)
                                TextField("Interests for this trip", text: $traveler.preferences, axis: .vertical)
                                Picker("Anything to take into account?", selection: $traveler.needs_response) {
                                    Text("Not now").tag("not_asked"); Text("None").tag("none")
                                    Text("Add details").tag("provided"); Text("Prefer not to answer").tag("prefer_not_to_answer")
                                }
                                if traveler.needs_response == "provided" { TextField("Practical needs", text: $traveler.needs, axis: .vertical) }
                                Button("Save as a recurring traveler") { Task { await store.saveTraveler(traveler) } }.disabled(store.hasPending || store.busy)
                                Button("Remove traveler", role: .destructive) { store.draft.travelers.removeAll { $0.id == traveler.id } }
                            }
                        }
                        Button("Add traveler", systemImage: "person.badge.plus") { store.draft.travelers.append(TripTraveler()) }
                        ForEach(store.travelers) { saved in
                            Button(saved.data.name.isEmpty ? String(localized: "Saved traveler") : saved.data.name) {
                                var person = saved.data; person.id = UUID(); person.saved_traveler_id = UUID(uuidString: saved.id)
                                store.draft.travelers.append(person)
                            }
                        }
                    }
                } else {
                    Section("Where are we staying?") {
                        TextField("Property (leave blank if not booked)", text: $store.draft.lodging.property_name)
                        TextField("Address", text: $store.draft.lodging.address)
                        TextField("Check-in date and time", text: $store.draft.lodging.check_in)
                        TextField("Check-out date and time", text: $store.draft.lodging.check_out)
                        TextField("Confirmation reference", text: $store.draft.lodging.reference)
                        TextField("Arrival instructions", text: $store.draft.lodging.instructions, axis: .vertical)
                    }
                    Section("Anything booked that I should protect?") {
                        ForEach($store.draft.commitments) { $item in
                            VStack {
                                TextField("Booking or commitment", text: $item.title)
                                TextField("Date and time", text: $item.timing)
                                TextField("Location", text: $item.location)
                                Button("Remove commitment", role: .destructive) { store.draft.commitments.removeAll { $0.id == item.id } }
                            }
                        }
                        Button("Add fixed commitment") { store.draft.commitments.append(FixedCommitment()) }
                    }
                    Section("Anything else?") {
                        TextField("Optional needs, budget, must-dos or things to avoid", text: $store.draft.constraints, axis: .vertical)
                        TextField("Notes", text: $store.draft.notes, axis: .vertical)
                        Text("These details apply to this trip. They do not become permanent preferences.").font(.caption)
                    }
                }
                Section {
                    if step < 2 {
                        Button("Continue") { step += 1 }.disabled(store.draft.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Button(step < 2 ? "Save trip; add details later" : "Save trip") {
                        Task { await store.saveIntake(); if store.pending == nil && store.error == nil { dismiss() } }
                    }.disabled(store.draft.destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .disabled(locked)
                PipErrorView(store: store)
            }
            .disabled(locked)
            .safeAreaInset(edge: .bottom) { if store.error != nil { PipErrorView(store: store).padding() } }
            .navigationTitle(step == 0 ? "Your trip" : step == 1 ? "Traveling together" : "Make room for what matters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if step > 1 { ToolbarItem(placement: .topBarLeading) { Button("Back") { step -= 1 } } }
            }
        }.interactiveDismissDisabled(store.busy)
    }
}
