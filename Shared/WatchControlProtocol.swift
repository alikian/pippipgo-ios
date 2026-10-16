import Foundation

/// Only control state crosses to the paired watch; no credentials, location or transcripts.
enum WatchCommand: String, Codable, CaseIterable, Sendable {
    case refresh, skip, explore, stopExplore, talk, endTalk
}

struct WatchControlState: Codable, Equatable, Sendable {
    var sessionID: UUID
    var updatedAt: Date
    var ready: Bool
    var foreground: Bool
    var exploring: Bool
    var talking: Bool
    var canSkip: Bool
    var hasTour: Bool
    var language: String

    static var unavailable: Self {
        Self(sessionID: UUID(), updatedAt: .distantPast, ready: false, foreground: false,
             exploring: false, talking: false, canSkip: false, hasTour: false, language: "en")
    }
}

struct WatchControlRequest: Codable, Sendable {
    var id: UUID = UUID()
    var command: WatchCommand
    var sessionID: UUID
    var sentAt: Date = Date()
}

/// Stable localization keys, interpreted on the watch rather than transmitting English prose.
enum WatchControlResult: String, Codable, Sendable {
    case success, openPhone, signIn, expired, busy, finishTour, nothingToSkip, invalidRequest
}

struct WatchControlReply: Codable, Sendable {
    var requestID: UUID
    var result: WatchControlResult
    var state: WatchControlState
}

/// Freshness and session checks prevent delayed taps from running after account switches.
struct WatchCommandGate {
    static func validate(_ request: WatchControlRequest, state: WatchControlState,
                         now: Date = Date()) -> WatchControlResult? {
        guard abs(request.sentAt.timeIntervalSince(now)) <= 10 else { return .expired }
        if request.command == .refresh { return nil }
        guard state.ready else { return .signIn }
        guard request.sessionID == state.sessionID else { return .expired }
        switch request.command {
        case .talk, .explore:
            guard state.foreground else { return .openPhone }
        default: break
        }
        if [WatchCommand.explore, .stopExplore].contains(request.command) && state.hasTour { return .finishTour }
        if request.command == .skip && !state.canSkip { return .nothingToSkip }
        return nil
    }
}
