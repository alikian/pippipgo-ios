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
