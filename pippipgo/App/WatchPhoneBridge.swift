import Foundation
import Observation
import WatchConnectivity

/// Live commands only: never queue an audio action for later delivery.
@MainActor @Observable
final class WatchPhoneBridge: NSObject, WCSessionDelegate {
    static let shared = WatchPhoneBridge()
    private(set) var selectedTab: AppTab?
    private(set) var navigationID = UUID()
    private var session: WCSession?
    private var accountID: String?
    private var state = WatchControlState.unavailable
    private var replies: [UUID: WatchControlReply] = [:]
    private var replyOrder: [UUID] = []
    private var readState: (() -> (String?, WatchControlState))?
    private var perform: ((WatchCommand) -> WatchControlResult)?

    func start(readState: @escaping () -> (String?, WatchControlState),
               perform: @escaping (WatchCommand) -> WatchControlResult) {
        self.readState = readState
        self.perform = perform
        guard WCSession.isSupported(), session == nil else { return }
        session = .default
        session?.delegate = self
        session?.activate()
    }

    func navigate(to tab: AppTab) {
        selectedTab = tab
        navigationID = UUID()
    }

    func publish(force: Bool = false) {
        guard let (accountID, snapshot) = readState?() else { return }
        var current = snapshot
        let changedSession = self.accountID != accountID || state.ready != current.ready
        if changedSession {
            self.accountID = accountID
            state.sessionID = UUID()
            replies.removeAll()
            replyOrder.removeAll()
        }
        current.sessionID = state.sessionID
        current.updatedAt = state.updatedAt
        guard force || changedSession || current != state else { return }
        current.updatedAt = Date()
        state = current
        guard let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled,
              let data = try? JSONEncoder().encode(state) else { return }
        try? session.updateApplicationContext(["state": data])
    }

    private func receive(_ data: Data) -> Data? {
        guard let request = try? JSONDecoder().decode(WatchControlRequest.self, from: data) else { return nil }
        publish(force: true) // Re-read account, consent and foreground state for every tap.
        if let reply = replies[request.id] { return try? JSONEncoder().encode(reply) }
        let result = WatchCommandGate.validate(request, state: state)
            ?? (request.command == .refresh ? .success : perform?(request.command) ?? .openPhone)
        publish()
        let reply = WatchControlReply(requestID: request.id, result: result, state: state)
        replies[request.id] = reply
        replyOrder.append(request.id)
        if replyOrder.count > 100 { replies.removeValue(forKey: replyOrder.removeFirst()) }
        return try? JSONEncoder().encode(reply)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data,
                             replyHandler: @escaping (Data) -> Void) {
        Task { @MainActor [weak self] in replyHandler(self?.receive(messageData) ?? Data()) }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor [weak self] in self?.publish(force: true) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in self?.publish(force: true) }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
}
