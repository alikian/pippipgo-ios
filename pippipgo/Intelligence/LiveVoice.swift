import AVFoundation
import SwiftUI

private final class VoiceSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Serializes the process-wide session without blocking the UI on supported iOS versions.
final class VoiceAudioSession: @unchecked Sendable {
    static let shared = VoiceAudioSession()
    private let queue = DispatchQueue(label: "com.pippipgo.voice.audio-session", qos: .userInitiated)
    private var owner: UUID?
    private let activateSession: @Sendable () throws -> Void
    private let deactivateSession: @Sendable () -> Void

    init(activate: @escaping @Sendable () throws -> Void = {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
    }, deactivate: @escaping @Sendable () -> Void = {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }) {
        activateSession = activate
        deactivateSession = deactivate
    }

    func activate(owner: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.activateSession()
                    self.owner = owner
                    continuation.resume()
                } catch {
                    self.deactivateSession()
                    self.owner = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func deactivate(owner: UUID) {
        queue.async {
            // A delayed cleanup must not deactivate a replacement call.
            guard self.owner == owner else { return }
            self.deactivateSession()
            self.owner = nil
        }
    }

    func flush() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }
}

/// The audio tap owns its converter; the main actor owns engine setup and playback.
final class VoiceAudio: @unchecked Sendable {
    private lazy var engine = AVAudioEngine()
    private lazy var player = AVAudioPlayerNode()
    private let sessionOwner = UUID()
    private var stopped = false
    private var tapped = false
    private var queuedFrames = 0
    @MainActor var hasPendingPlayback: Bool { queuedFrames > 0 }
    private var generation = UUID()
    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 24_000, channels: 1)!

    @MainActor func start() async throws -> AsyncThrowingStream<Data, Error> {
        guard !stopped else { throw CancellationError() }
        try await VoiceAudioSession.shared.activate(owner: sessionOwner)
        guard !stopped, !Task.isCancelled else {
            VoiceAudioSession.shared.deactivate(owner: sessionOwner)
            throw CancellationError()
        }
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        let output = engine.outputNode
        let hardwareOutput = output.inputFormat(forBus: 0)
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)
        // Connecting the player can reconfigure the mixer's automatic output link.
        // Finalize that link afterward or VoiceProcessingIO may never deliver input.
        engine.connect(engine.mainMixerNode, to: output, format: hardwareOutput)
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0,
              let pcm = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: sourceFormat, to: pcm) else {
            throw APIClientError.invalidRequest("The microphone is unavailable.")
        }
        let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingNewest(12)) { continuation in
            input.installTap(onBus: 0, bufferSize: 2048, format: nil) { buffer, _ in
                let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24_000 / sourceFormat.sampleRate) + 32)
                guard let converted = AVAudioPCMBuffer(pcmFormat: pcm, frameCapacity: capacity) else { return }
                var supplied = false
                var conversionError: NSError?
                let status = converter.convert(to: converted, error: &conversionError) { _, state in
                    if supplied { state.pointee = .noDataNow; return nil }
                    supplied = true; state.pointee = .haveData; return buffer
                }
                if status == .error {
                    continuation.finish(throwing: conversionError ?? NSError(domain: "VoiceAudio", code: 1)); return
                }
                guard converted.frameLength > 0, let samples = converted.int16ChannelData else { return }
                let data = Data(bytes: samples[0], count: Int(converted.frameLength) * 2)
                if case .dropped = continuation.yield(data) {
                    continuation.finish(throwing: APIClientError.connection)
                }
            }
            tapped = true
        }
        try engine.start()
        player.play()
        return stream
    }

    @MainActor func play(_ data: Data) throws {
        guard !data.isEmpty, data.count % 2 == 0 else { return }
        let frames = data.count / 2
        // End a stalled connection instead of playing a growing backlog of stale speech.
        guard queuedFrames + frames <= 24_000 * 3,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frames)),
              let output = buffer.floatChannelData else { throw APIClientError.connection }
        buffer.frameLength = AVAudioFrameCount(frames)
        data.withUnsafeBytes { bytes in
            for index in 0..<frames {
                output[0][index] = Float(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: index * 2, as: Int16.self))) / 32768
            }
        }
        queuedFrames += frames
        let ticket = generation
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                self.queuedFrames = max(0, self.queuedFrames - frames)
            }
        }
    }

    @MainActor func stop() {
        stopped = true
        generation = UUID(); queuedFrames = 0
        if tapped {
            engine.inputNode.removeTap(onBus: 0); tapped = false
            player.stop(); engine.stop()
        }
        VoiceAudioSession.shared.deactivate(owner: sessionOwner)
    }
}

enum VoiceSpeaker: Equatable {
    case user, pip
    var label: String { self == .user ? "You" : "Pip" }
}

struct VoiceTranscriptFragment: Equatable {
    let text: String
    let startMilliseconds: Double?
    let endMilliseconds: Double?
}

struct VoiceMessage: Identifiable, Equatable {
    let id = UUID()
    let speaker: VoiceSpeaker
    var fragments: [VoiceTranscriptFragment]
    var text: String { fragments.map(\.text).joined() }
    var startMilliseconds: Double? { fragments.compactMap(\.startMilliseconds).min() }
    var endMilliseconds: Double? { fragments.compactMap(\.endMilliseconds).max() }
}

/// Display-only, bounded session captions. Timestamps group overlapping speakers independently.
struct VoiceTranscript: Equatable {
    private(set) var messages: [VoiceMessage] = []
    private(set) var revision = 0
    private var historyIDs: Set<UUID> = []

    mutating func appendHistory(_ text: String, speaker: VoiceSpeaker) {
        guard !text.isEmpty else { return }
        let message = VoiceMessage(speaker: speaker, fragments: [VoiceTranscriptFragment(text: String(text.suffix(4000)), startMilliseconds: nil, endMilliseconds: nil)])
        messages.append(message)
        historyIDs.insert(message.id)
        trim()
        revision += 1
    }

    mutating func append(_ text: String, speaker: VoiceSpeaker, startMilliseconds: Double?, endMilliseconds: Double?) {
        guard !text.isEmpty else { return }
        let validTiming = startMilliseconds.map { $0.isFinite && $0 >= 0 } == true
            && endMilliseconds.map { $0.isFinite && $0 >= (startMilliseconds ?? 0) } == true
        let start = validTiming ? startMilliseconds : nil
        let end = validTiming ? endMilliseconds : nil
        let fragment = VoiceTranscriptFragment(text: String(text.suffix(4000)), startMilliseconds: start, endMilliseconds: end)
        let matching = messages.indices.reversed().first { index in
            let message = messages[index]
            guard !historyIDs.contains(message.id), message.speaker == speaker else { return false }
            if let start, let end, let previousStart = message.startMilliseconds, let previousEnd = message.endMilliseconds {
                // Use speech timing rather than packet arrival time. Short acknowledgments
                // from the other speaker must not break an ongoing utterance.
                return start <= previousEnd + 1200 && end >= previousStart - 1200
            }
            return index == messages.indices.last
        }
        if let matching {
            messages[matching].fragments.append(fragment)
        } else {
            let message = VoiceMessage(speaker: speaker, fragments: [fragment])
            if let start, let index = messages.firstIndex(where: { !historyIDs.contains($0.id) && ($0.startMilliseconds ?? .infinity) > start }) {
                messages.insert(message, at: index)
            } else {
                messages.append(message)
            }
        }
        trim()
        revision += 1
    }

    private mutating func trim() {
        while messages.count > 64 { messages.removeFirst() }
        // Keep only recent captions, with the same 8,000-character total as before.
        while messages.reduce(0, { $0 + $1.text.count }) > 8000
            || messages.reduce(0, { $0 + $1.fragments.count }) > 512 {
            messages[0].fragments.removeFirst()
            if messages[0].fragments.isEmpty { messages.removeFirst() }
        }
        historyIDs.formIntersection(Set(messages.map(\.id)))
    }

    mutating func clear() { messages.removeAll(); historyIDs.removeAll(); revision += 1 }
}

@MainActor @Observable
final class LiveVoiceStore {
    let locationDisplay: CurrentLocationStore
    /// Talk to Pip, or a two-way interpreter. Changes only while no session is active.
    private(set) var mode: LiveVoiceMode
    private(set) var active = false
    private(set) var connected = false
    private(set) var conversationContext: ConversationContext?
    private(set) var capturingLocation = false
    private(set) var microphoneLevel = 0.0
    private(set) var microphoneReceiving = false
    private var lastInputAt: Date?
    private(set) var transcript = VoiceTranscript()
    var error: String?
    private var epoch = UUID()
    private var worker: Task<Void, Never>?
    private var sender: Task<Void, Never>?
    private var watchdog: Task<Void, Never>?
    private var captureWatchdog: Task<Void, Never>?
    private var navigationTask: Task<Void, Never>?
    private var lastOutputAt = Date.distantPast
    private var socket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var audio: VoiceAudio?
    private let client: APIClient
    private let authentication: any AccessTokenProviding

    init(client: APIClient, authentication: any AccessTokenProviding, locationDisplay: CurrentLocationStore? = nil, mode: LiveVoiceMode = .pip) {
        self.locationDisplay = locationDisplay ?? CurrentLocationStore()
        self.client = client; self.authentication = authentication
        self.mode = mode
    }

    func setMode(_ mode: LiveVoiceMode) {
        guard !active else { return }
        self.mode = mode
    }

    func start() {
        guard !active else { return }
        active = true; error = nil; transcript.clear()
        conversationContext = nil; capturingLocation = false
        microphoneReceiving = false; microphoneLevel = 0; lastInputAt = nil
        let ticket = UUID(); epoch = ticket
        let mode = self.mode
        worker = Task { [weak self] in
            guard let self else { return }
            do {
                let allowed = await AVAudioApplication.requestRecordPermission()
                guard self.epoch == ticket, !Task.isCancelled else { return }
                guard allowed else {
                    throw APIClientError.invalidRequest(mode.translation == nil
                        ? "Allow microphone access in Settings to talk to Pip."
                        : "Allow microphone access in Settings to translate conversations.")
                }
                let token = try await authentication.validAccessToken(forceRefresh: false)
                guard self.epoch == ticket, !Task.isCancelled else { return }
                var request = try Self.request(baseURL: client.baseURL, token: token, mode: mode)
                if mode == .pip {
                    // Interpreter sessions never send location or other traveler context.
                    capturingLocation = true
                    let context: ConversationContext
                    if let recent = locationDisplay.context, recent.hasFreshLocation() { context = recent }
                    else { context = await ConversationContext.capture() }
                    guard self.epoch == ticket, !Task.isCancelled else { return }
                    conversationContext = context; capturingLocation = false
                    request.setValue(try JSONEncoder().encode(context).base64EncodedString(), forHTTPHeaderField: "X-Pip-Context")
                }
                let session = URLSession(configuration: .ephemeral, delegate: VoiceSessionDelegate(), delegateQueue: nil)
                self.session = session
                let socket = session.webSocketTask(with: request)
                socket.maximumMessageSize = 1_000_000
                self.socket = socket; socket.resume()
                watchdog = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(30))
                    guard let self, !Task.isCancelled, self.epoch == ticket, !self.connected else { return }
                    self.fail(mode.translation == nil ? "Pip could not connect. Please try again." : "Translation could not connect. Please try again.", ticket: ticket)
                }
                while !Task.isCancelled {
                    let message = try await socket.receive()
                    guard self.epoch == ticket else { return }
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    guard let event = try JSONSerialization.jsonObject(with: data) as? [String: Any], let type = event["type"] as? String else { continue }
                    switch type {
                    case "session.started":
                        guard Self.acceptsTranslationSession(event, mode: mode) else {
                            fail("This backend does not support headphone mode yet. Use the updated local backend or turn headphone mode off.", ticket: ticket)
                            return
                        }
                        if mode == .pip, let history = event["messages"] as? [[String: Any]] {
                            for message in history {
                                if let text = message["text"] as? String {
                                    transcript.appendHistory(text, speaker: message["role"] as? String == "user" ? .user : .pip)
                                }
                            }
                        }
                        guard !connected else { continue }
                        let audio = VoiceAudio(); self.audio = audio
                        let stream = try await audio.start()
                        guard self.epoch == ticket, !Task.isCancelled else { audio.stop(); return }
                        connected = true; watchdog?.cancel()
                        lastInputAt = Date()
                        captureWatchdog = Task { [weak self] in
                            while !Task.isCancelled {
                                try? await Task.sleep(for: .seconds(2))
                                guard let self, !Task.isCancelled, self.epoch == ticket else { return }
                                if Date().timeIntervalSince(self.lastInputAt ?? .distantPast) > 6 {
                                    self.fail("Pip couldn’t receive microphone audio. Please try starting voice again.", ticket: ticket)
                                    return
                                }
                            }
                        }
                        sender = Task { [weak self] in
                            do {
                                for try await chunk in stream {
                                    guard let self, self.epoch == ticket, !Task.isCancelled else { return }
                                    self.lastInputAt = Date()
                                    self.microphoneReceiving = true
                                    self.microphoneLevel = Self.level(chunk)
                                    let payload = try JSONSerialization.data(withJSONObject: ["type": "session.input_audio.append", "audio": chunk.base64EncodedString()])
                                    try await socket.send(.string(String(decoding: payload, as: UTF8.self)))
                                }
                            } catch { self?.fail("The voice connection was interrupted. Please try again.", ticket: ticket) }
                        }
                    case "navigation.open":
                        if mode == .pip { scheduleNavigation(event, ticket: ticket) }
                    case "session.output_audio.delta":
                        lastOutputAt = Date()
                        if let delta = event["delta"] as? String, let bytes = Data(base64Encoded: delta) { try audio?.play(bytes) }
                    case "session.input_transcript.delta":
                        appendCaption(event, speaker: .user)
                    case "session.output_transcript.delta":
                        appendCaption(event, speaker: .pip)
                    case "session.closed": stop(); return
                    case "error":
                        fail(event["message"] as? String ?? "Live voice is unavailable. Please try again.", ticket: ticket); return
                    default: break
                    }
                }
            } catch {
                if case APIClientError.invalidRequest(let message) = error {
                    fail(message, ticket: ticket)
                } else {
                    fail(mode.translation == nil
                         ? "Live voice could not connect. Check your connection, then try again."
                         : "Translation could not connect. Check your connection, then try again.", ticket: ticket)
                }
            }
        }
    }

    static func drivingURL(_ event: [String: Any]) -> URL? {
        guard let placeID = event["place_id"] as? String, !placeID.isEmpty, placeID.count <= 512,
              let name = event["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 200 else { return nil }
        var url = URLComponents(string: "https://maps.apple.com/")!
        let address = event["address"] as? String ?? ""
        let destination = address.isEmpty ? name : "\(name), \(address.prefix(512))"
        url.queryItems = [URLQueryItem(name: "daddr", value: destination),
                          URLQueryItem(name: "dirflg", value: "d")]
        return url.url
    }

    private func scheduleNavigation(_ event: [String: Any], ticket: UUID) {
        guard navigationTask == nil, let url = Self.drivingURL(event) else { return }
        let requestedAt = Date()
        navigationTask = Task { [weak self] in
            // Give Pip time to announce the handoff, then drain scheduled audio.
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self, !Task.isCancelled, self.epoch == ticket else { return }
                let elapsed = Date().timeIntervalSince(requestedAt)
                let quiet = Date().timeIntervalSince(self.lastOutputAt) >= 2
                if elapsed >= 15 || (elapsed >= 5 && self.lastOutputAt >= requestedAt && quiet && self.audio?.hasPendingPlayback != true) {
                    guard UIApplication.shared.applicationState == .active else {
                        self.fail("Return to PipPipGo and ask for directions again.", ticket: ticket)
                        return
                    }
                    self.stop()
                    let stoppedEpoch = self.epoch
                    UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                        guard let self, self.epoch == stoppedEpoch else { return }
                        if !opened { self.error = "Google Maps could not open. Please try again." }
                    }
                    return
                }
            }
        }
    }

    private func appendCaption(_ event: [String: Any], speaker: VoiceSpeaker) {
        guard let text = event["delta"] as? String else { return }
        transcript.append(text, speaker: speaker, startMilliseconds: (event["start_ms"] as? NSNumber)?.doubleValue,
                          endMilliseconds: (event["end_ms"] as? NSNumber)?.doubleValue)
    }

    #if DEBUG
    static var preview: LiveVoiceStore {
        let store = LiveVoiceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!), authentication: VoicePreviewTokens())
        store.transcript.append("Hi, I’m Pip, your travel companion. Where would you like to go?", speaker: .pip, startMilliseconds: 0, endMilliseconds: 4000)
        store.transcript.append("I’m planning a weekend in Paris. I’d love a relaxed trip with good food.", speaker: .user, startMilliseconds: 5000, endMilliseconds: 9000)
        store.transcript.append("That sounds lovely. We can plan a morning in Montmartre, lunch at a neighborhood bistro, and a walk along the Seine. What dates do you have in mind?", speaker: .pip, startMilliseconds: 10000, endMilliseconds: 18000)
        store.active = true; store.connected = true; store.microphoneReceiving = true; store.microphoneLevel = 0.04
        return store
    }

    static var translationPreview: LiveVoiceStore {
        let store = LiveVoiceStore(client: APIClient(baseURL: URL(string: "https://example.invalid")!), authentication: VoicePreviewTokens(),
                                   mode: .translate(TranslationPair(mine: "en", theirs: "es")!))
        store.transcript.append("Where is the closest pharmacy?", speaker: .user, startMilliseconds: 0, endMilliseconds: 2000)
        store.transcript.append("¿Dónde está la farmacia más cercana?", speaker: .pip, startMilliseconds: 2500, endMilliseconds: 4500)
        store.transcript.append("Está a dos calles, a la izquierda.", speaker: .user, startMilliseconds: 6000, endMilliseconds: 8000)
        store.transcript.append("It’s two blocks away, on the left.", speaker: .pip, startMilliseconds: 8500, endMilliseconds: 10000)
        return store
    }
    #endif

    nonisolated static func level(_ pcm: Data) -> Double {
        guard pcm.count >= 2 else { return 0 }
        return pcm.withUnsafeBytes { bytes in
            var peak = 0
            for offset in stride(from: 0, to: pcm.count - 1, by: 2) {
                peak = max(peak, abs(Int(Int16(littleEndian: bytes.loadUnaligned(fromByteOffset: offset, as: Int16.self)))))
            }
            return min(1, Double(peak) / 32768)
        }
    }

    static func acceptsTranslationSession(_ event: [String: Any], mode: LiveVoiceMode) -> Bool {
        guard mode.translation?.listenOnly == true else { return true }
        return event["translation_mode"] as? String == "listen_only"
    }

    static func request(baseURL: URL, token: String, mode: LiveVoiceMode = .pip, language: String? = nil) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appending(path: mode.path), resolvingAgainstBaseURL: false),
              let scheme = components.scheme, ["https", "http"].contains(scheme), components.host != nil,
              components.user == nil, components.password == nil else { throw APIClientError.invalidRequest("Invalid backend URL.") }
        components.scheme = scheme == "https" ? "wss" : "ws"
        components.query = nil; components.fragment = nil
        guard let url = components.url else { throw APIClientError.invalidRequest("Invalid backend URL.") }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let pair = mode.translation {
            request.setValue(pair.headerValue, forHTTPHeaderField: "X-Pip-Translate")
            if pair.listenOnly { request.setValue("1", forHTTPHeaderField: "X-Pip-Translate-Listen-Only") }
        } else {
            request.setValue("1", forHTTPHeaderField: "X-Pip-Navigation")
            let selected = AppLanguage.selected(language ?? UserDefaults.standard.string(forKey: "pip.language") ?? "en")
            request.setValue(selected.rawValue, forHTTPHeaderField: "X-Pip-Language")
        }
        return request
    }

    private func fail(_ message: String, ticket: UUID) {
        guard epoch == ticket else { return }
        stop(); error = message
    }

    func stop(clearCaptions: Bool = false) {
        epoch = UUID(); active = false; connected = false; capturingLocation = false
        worker?.cancel(); worker = nil; sender?.cancel(); sender = nil; watchdog?.cancel(); watchdog = nil
        captureWatchdog?.cancel(); captureWatchdog = nil
        navigationTask?.cancel(); navigationTask = nil
        microphoneLevel = 0; microphoneReceiving = false
        audio?.stop(); audio = nil
        let ending = socket; let endingSession = session
        socket = nil; session = nil
        ending?.cancel(with: .normalClosure, reason: nil)
        endingSession?.invalidateAndCancel()
        if clearCaptions { transcript.clear(); error = nil; conversationContext = nil }
    }
}

struct VoiceMessageBubble: View {
    let message: VoiceMessage
    var translating = false
    private var isUser: Bool { message.speaker == .user }
    private var label: LocalizedStringKey {
        translating ? (isUser ? "Heard" : "Translation") : (isUser ? "You" : "Pip")
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 5) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isUser ? Color.white.opacity(0.85) : Color.secondary)
                Text(verbatim: message.text)
                    // Larger translations are easier to show to the other person.
                    .font(translating && !isUser ? Font.title3 : Font.body)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .background(isUser ? Color.blue : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

struct LiveVoiceView: View {
    @Bindable var store: LiveVoiceStore
    var showsControls = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var followsLatest = true
    private var translating: Bool { store.mode.translation != nil }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroll in
                ScrollView {
                    LazyVStack(spacing: 14) {
                        if store.transcript.messages.isEmpty {
                            if translating {
                                ContentUnavailableView("Live Translation", systemImage: "translate",
                                                       description: Text("Tap Start translation once, then speak naturally. Pip translates aloud in real time—no need to hold a button."))
                                    .padding(.top, 32)
                            } else {
                                ContentUnavailableView("Say hello to Pip", systemImage: "bubble.left.and.bubble.right",
                                                       description: Text("Your conversation will appear here as you speak."))
                                    .padding(.top, 32)
                            }
                        }
                        ForEach(store.transcript.messages) { message in
                            VoiceMessageBubble(message: message, translating: translating).id(message.id)
                        }
                        Color.clear.frame(height: 1).id("latestVoiceMessage")
                    }
                    .padding(16)
                }
                .simultaneousGesture(DragGesture().onChanged { _ in followsLatest = false })
                .onChange(of: store.transcript.revision) { _, _ in
                    if followsLatest { scroll.scrollTo("latestVoiceMessage", anchor: .bottom) }
                }
                .onChange(of: store.active) { _, active in
                    if active { followsLatest = true; scroll.scrollTo("latestVoiceMessage", anchor: .bottom) }
                }
                .overlay(alignment: .bottomTrailing) {
                    if !followsLatest && !store.transcript.messages.isEmpty {
                        Button {
                            followsLatest = true
                            withAnimation { scroll.scrollTo("latestVoiceMessage", anchor: .bottom) }
                        } label: {
                            Label("Latest messages", systemImage: "arrow.down")
                        }
                        .font(.caption.weight(.semibold)).buttonStyle(.borderedProminent)
                        .padding(16)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) { if showsControls { controls } }
        .onChange(of: scenePhase) { _, phase in
            // Only established audio sessions can continue in the background.
            if phase == .background && !store.connected { store.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notification in
            if let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue { store.stop() }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
            if let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue { store.stop() }
        }
        .onDisappear { store.stop(clearCaptions: true) }
    }

    private var controls: some View {
        VStack(spacing: 10) {
            if let error = store.error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if store.active {
                Label(store.connected ? (store.microphoneReceiving ? (translating ? "Translating — take turns speaking" : "Listening — you can speak naturally") : "Starting microphone…") : "Connecting…", systemImage: "waveform")
                    .font(.subheadline).foregroundStyle(.secondary)
                if store.microphoneReceiving {
                    ProgressView(value: min(1, store.microphoneLevel * 5))
                        .accessibilityLabel("Microphone input level")
                }
                Button(role: .destructive) { store.stop() } label: {
                    Label(translating ? "Stop translating" : "End voice conversation", systemImage: translating ? "stop.fill" : "phone.down.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(.red).controlSize(.large)
            } else {
                Button { store.start() } label: {
                    Label(LocalizedStringKey(translating ? "Start translation" : "Continue last talk"), systemImage: translating ? "translate" : "mic.fill")
                        .frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).controlSize(.large)
            }
        }
        .padding(16)
        .background(.bar)
    }
}

/// Talk to Pip page inside the Pip tab. The parent supplies the navigation bar.
struct VoiceConversationView: View {
    let store: LiveVoiceStore
    /// A pending Siri/Shortcuts launch; consumed once so returning to this page never restarts a call.
    @Binding var startRequest: UUID?
    var newTalk: (() async -> Bool)? = nil
    var canCreateTalk = true
    @State private var creatingTalk = false
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        LiveVoiceView(store: store)
            .disabled(creatingTalk)
            .onChange(of: scenePhase, initial: true) { _, _ in startRequestedConversation() }
            .onChange(of: startRequest) { _, _ in startRequestedConversation() }
            .toolbar {
                if let newTalk {
                    Button("New talk", systemImage: "square.and.pencil") {
                        creatingTalk = true
                        Task {
                            if await newTalk(), scenePhase == .active { store.start() }
                            creatingTalk = false
                        }
                    }
                    .disabled(store.active || creatingTalk || !canCreateTalk)
                }
            }
    }
    private func startRequestedConversation() {
        guard scenePhase == .active, startRequest != nil else { return }
        startRequest = nil
        store.start() // Already-active calls are reused by the store.
    }
}

#if DEBUG
private struct VoicePreviewTokens: AccessTokenProviding {
    func validAccessToken(forceRefresh: Bool) async throws -> String { throw APIClientError.connection }
}

#Preview("Voice conversation") {
    NavigationStack {
        VoiceConversationView(store: .preview, startRequest: .constant(nil))
            .navigationTitle("Talk to Pip")
            .navigationBarTitleDisplayMode(.inline)
    }
}
#endif
