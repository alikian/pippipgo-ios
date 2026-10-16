import XCTest
@testable import pippipgo

final class WatchCommandGateTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)
    private func state() -> WatchControlState {
        var state = WatchControlState.unavailable
        state.ready = true
        state.foreground = true
        state.canSkip = true
        return state
    }
    private func request(_ command: WatchCommand, _ state: WatchControlState) -> WatchControlRequest {
        WatchControlRequest(command: command, sessionID: state.sessionID, sentAt: now)
    }

    func testRejectsCommandsFromPreviousAccountSession() {
        let state = state()
        var request = request(.talk, state)
        request.sessionID = UUID()
        XCTAssertEqual(WatchCommandGate.validate(request, state: state, now: now), .expired)
    }
    func testNeverRunsDelayedOrFutureDatedTap() {
        let state = state()
        for offset in [-11.0, 11.0] {
            var request = request(.explore, state)
            request.sentAt = now.addingTimeInterval(offset)
            XCTAssertEqual(WatchCommandGate.validate(request, state: state, now: now), .expired)
        }
    }
    func testSignedOutAndConsentGateBlocksEveryAction() {
        var state = state()
        state.ready = false
        for command in WatchCommand.allCases where command != .refresh {
            XCTAssertEqual(WatchCommandGate.validate(request(command, state), state: state, now: now), .signIn)
        }
        XCTAssertNil(WatchCommandGate.validate(request(.refresh, state), state: state, now: now))
    }
    func testBackgroundAllowsStopAndSkipButNeverStartsAudioOrLocation() {
        var state = state()
        state.foreground = false
        for command in [WatchCommand.talk, .explore] {
            XCTAssertEqual(WatchCommandGate.validate(request(command, state), state: state, now: now), .openPhone)
        }
        for command in [WatchCommand.endTalk, .stopExplore, .skip] {
            XCTAssertNil(WatchCommandGate.validate(request(command, state), state: state, now: now))
        }
    }
    func testExploreCannotReplaceCurrentTour() {
        var state = state()
        state.hasTour = true
        for command in [WatchCommand.explore, .stopExplore] {
            XCTAssertEqual(WatchCommandGate.validate(request(command, state), state: state, now: now), .finishTour)
        }
    }
    func testSkipUnavailableWithoutAnnouncement() {
        var state = state()
        state.canSkip = false
        XCTAssertEqual(WatchCommandGate.validate(request(.skip, state), state: state, now: now), .nothingToSkip)
    }
    func testWireRoundTrip() throws {
        let state = state()
        let original = request(.explore, state)
        let decoded = try JSONDecoder().decode(WatchControlRequest.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.command, .explore)
        XCTAssertNil(WatchCommandGate.validate(decoded, state: state, now: now))
    }
}
