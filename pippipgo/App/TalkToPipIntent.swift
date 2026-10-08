import AppIntents
import Foundation
import Observation

/// In-memory launch request survives cold-start view creation, but never sign-out.
@MainActor @Observable
final class TalkToPipLaunch {
    static let shared = TalkToPipLaunch()
    private(set) var requestID: UUID?
    private var requestedAt: Date?

    func request(now: Date = .now) {
        requestID = UUID()
        requestedAt = now
    }

    func cancel() { requestID = nil; requestedAt = nil }

    func take(isActive: Bool, blocked: Bool, now: Date = .now) -> UUID? {
        guard let requestID, let requestedAt else { return nil }
        guard now.timeIntervalSince(requestedAt) < 60 else { cancel(); return nil }
        guard isActive, !blocked else { return nil }
        cancel()
        return requestID
    }
}

struct StartTalkToPipIntent: AppIntent {
    static var title: LocalizedStringResource = "Start PipPipGo"
    static var description = IntentDescription("Open PipPipGo and start a live voice conversation with Pip. Sign in and allow microphone access first.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        TalkToPipLaunch.shared.request()
        return .result()
    }
}

struct PipPipGoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTalkToPipIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Start Talk to Pip in \(.applicationName)",
                "Talk to Pip in \(.applicationName)",
                "Start a conversation in \(.applicationName)"
            ],
            shortTitle: "Start PipPipGo",
            systemImageName: "mic.fill"
        )
    }
}
