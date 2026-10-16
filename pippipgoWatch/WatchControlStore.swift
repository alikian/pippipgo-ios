import AVFoundation
import Foundation
import Observation
import WatchConnectivity
import WatchKit

@MainActor @Observable
final class WatchControlStore: NSObject, WCSessionDelegate {
    var state = WatchControlState.unavailable
    var reachable = false
    var pendingID: UUID?
    var result: WatchControlResult?
    var connectionFailed = false
    private var microphone: AVAudioEngine?
    private var microphoneTask: Task<Void, Never>?
    private var preparingMicrophone = false
    private var visible = false
    func resume() { visible = true }

    func talk() {
        if state.talking { stopMicrophone(); send(.endTalk); return }
        guard canControl, !preparingMicrophone else { return }
        preparingMicrophone = true
        Task {
            let allowed = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { continuation.resume(returning: $0) }
            }
            preparingMicrophone = false
            guard visible else { return }
            guard allowed, canControl else { connectionFailed = true; return }
            send(.talk)
        }
    }

    func suspend() {
        visible = false
        if microphone != nil { stopMicrophone(); send(.endTalk) }
    }

    private func stopMicrophone() {
        microphoneTask?.cancel(); microphoneTask = nil
        if let microphone { microphone.inputNode.removeTap(onBus: 0); microphone.stop() }
        microphone = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func startMicrophone(conversationID: UUID, sessionID: UUID) {
        stopMicrophone()
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let source = input.outputFormat(forBus: 0)
            guard source.sampleRate > 0,
                  let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24_000, channels: 1, interleaved: true),
                  let converter = AVAudioConverter(from: source, to: format) else { throw NSError(domain: "WatchMicrophone", code: 1) }
            let stream = AsyncThrowingStream<Data, Error>(bufferingPolicy: .bufferingNewest(6)) { continuation in
                input.installTap(onBus: 0, bufferSize: 4096, format: source) { buffer, _ in
                    let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 24_000 / source.sampleRate) + 32)
                    guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
                    var supplied = false
                    var error: NSError?
                    let status = converter.convert(to: pcm, error: &error) { _, state in
                        if supplied { state.pointee = .noDataNow; return nil }
                        supplied = true; state.pointee = .haveData; return buffer
                    }
                    guard status != .error else { continuation.finish(throwing: error ?? NSError(domain: "WatchMicrophone", code: 2)); return }
                    guard pcm.frameLength > 0, let samples = pcm.int16ChannelData else { return }
                    if case .dropped = continuation.yield(Data(bytes: samples[0], count: Int(pcm.frameLength) * 2)) {
                        continuation.finish(throwing: NSError(domain: "WatchMicrophone", code: 3))
                    }
                }
            }
            microphone = engine
            try engine.start()
            microphoneTask = Task { [weak self] in
                do {
                    var sequence: UInt64 = 0
                    for try await pcm in stream {
                        guard let self, !Task.isCancelled, self.state.sessionID == sessionID,
                              self.state.talking, let session = self.session, session.isReachable else { throw CancellationError() }
                        let packet = WatchMicrophonePacket(conversationID: conversationID, sessionID: sessionID,
                                                           sequence: sequence, sentAt: Date(), pcm: pcm)
                        sequence += 1
                        let encoded = try JSONEncoder().encode(packet)
                        let response: Data = try await withCheckedThrowingContinuation { continuation in
                            session.sendMessageData(encoded, replyHandler: { continuation.resume(returning: $0) },
                                                    errorHandler: { continuation.resume(throwing: $0) })
                        }
                        guard response == Data([1]) else { throw NSError(domain: "WatchMicrophone", code: 4) }
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    self?.stopMicrophone()
                    self?.send(.endTalk)
                    self?.connectionFailed = true
                }
            }
        } catch {
            stopMicrophone(); send(.endTalk); connectionFailed = true
        }
    }

    private var session: WCSession?
    private var timeout: Task<Void, Never>?
    var fresh: Bool { abs(state.updatedAt.timeIntervalSinceNow) < 15 }
    var canControl: Bool { reachable && fresh && state.ready && pendingID == nil }

    func activate() {
        guard WCSession.isSupported(), session == nil else { return }
        session = .default
        session?.delegate = self
        session?.activate()
    }

    func send(_ command: WatchCommand) {
        guard pendingID == nil else { return }
        guard let session, session.activationState == .activated, session.isReachable else {
            reachable = false
            connectionFailed = true
            return
        }
        let request = WatchControlRequest(command: command, sessionID: state.sessionID)
        guard let data = try? JSONEncoder().encode(request) else { return }
        pendingID = request.id
        connectionFailed = false
        if command != .refresh { result = nil }
        session.sendMessageData(data, replyHandler: { [weak self] data in
            Task { @MainActor in
                guard let self, self.pendingID == request.id else { return }
                self.timeout?.cancel()
                self.pendingID = nil
                guard let reply = try? JSONDecoder().decode(WatchControlReply.self, from: data),
                      reply.requestID == request.id else { self.connectionFailed = true; return }
                self.apply(reply.state)
                if command == .talk, reply.result == .success, reply.state.talking {
                    if self.visible { self.startMicrophone(conversationID: request.id, sessionID: reply.state.sessionID) }
                    else { self.send(.endTalk) }
                }
                self.result = reply.result == .success ? nil : reply.result
                if command != .refresh {
                    WKInterfaceDevice.current().play(reply.result == .success ? .success : .failure)
                }
            }
        }, errorHandler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.pendingID == request.id else { return }
                self.timeout?.cancel()
                self.pendingID = nil
                self.connectionFailed = true
            }
        })
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, let self, self.pendingID == request.id else { return }
            self.pendingID = nil
            self.connectionFailed = true
        }
    }

    private func apply(_ next: WatchControlState) {
        // Reject older context delivered after a live reply.
        guard next.updatedAt >= state.updatedAt else { return }
        if !next.talking || next.sessionID != state.sessionID { stopMicrophone() }
        state = next
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.reachable = session.isReachable
            // Cached context is informational; refresh is required before controls enable.
            if let data = session.receivedApplicationContext["state"] as? Data,
               let state = try? JSONDecoder().decode(WatchControlState.self, from: data) { self.apply(state) }
            if self.reachable { self.send(.refresh) }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            if !session.isReachable { self?.stopMicrophone() }
            self?.reachable = session.isReachable
            if session.isReachable { self?.send(.refresh) }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["state"] as? Data,
              let state = try? JSONDecoder().decode(WatchControlState.self, from: data) else { return }
        Task { @MainActor [weak self] in self?.apply(state) }
    }
}
