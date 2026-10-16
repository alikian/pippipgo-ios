import SwiftUI

@main
struct PipPipGoWatchApp: App {
    @State private var controls = WatchControlStore()
    var body: some Scene {
        WindowGroup { WatchControlsView(controls: controls) }
    }
}

struct WatchControlsView: View {
    @Bindable var controls: WatchControlStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if !controls.reachable || controls.connectionFailed {
                        Text("Open PipPipGo on your iPhone.").font(.footnote).foregroundStyle(.secondary)
                    } else if !controls.state.ready {
                        Text("Sign in and finish setup on your iPhone.").font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        controls.send(controls.state.exploring ? .stopExplore : .explore)
                    } label: {
                        Label(LocalizedStringKey(controls.state.exploring ? "Stop exploring" : "Explore"), systemImage: controls.state.exploring ? "stop.fill" : "safari.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent).tint(.blue)
                    .disabled(!controls.canControl || (!controls.state.exploring && controls.state.hasTour))
                    .accessibilityIdentifier("watch.explore")
                    Button {
                        controls.send(.skip)
                    } label: {
                        Label("Skip", systemImage: "forward.end.fill").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!controls.canControl || !controls.state.canSkip)
                    .accessibilityIdentifier("watch.skip")
                    Button {
                        controls.send(controls.state.talking ? .endTalk : .talk)
                    } label: {
                        Label(LocalizedStringKey(controls.state.talking ? "End conversation" : "Talk to Pip"), systemImage: controls.state.talking ? "stop.fill" : "mic.fill")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .disabled(!controls.canControl)
                    .accessibilityIdentifier("watch.talk")
                    Text("Voice uses your iPhone or its connected headphones.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if let result = controls.result { Text(message(for: result)).font(.footnote) }
                    if controls.pendingID != nil { ProgressView().accessibilityLabel("Connecting…") }
                    if !controls.fresh || controls.connectionFailed {
                        Button("Reconnect", systemImage: "arrow.clockwise") { controls.send(.refresh) }
                            .disabled(controls.pendingID != nil)
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("PipPipGo")
        }
        .task(id: scenePhase) {
            controls.activate()
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                controls.send(.refresh)
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
            }
        }
    }

    private func message(for result: WatchControlResult) -> LocalizedStringKey {
        switch result {
        case .success: "Done"
        case .openPhone: "Open PipPipGo on your iPhone."
        case .signIn: "Sign in and finish setup on your iPhone."
        case .expired: "Connection changed. Try again."
        case .busy: "Pip is busy. Try again shortly."
        case .finishTour: "Finish your current tour on your iPhone first."
        case .nothingToSkip: "Nothing is playing to skip."
        case .invalidRequest: "Update PipPipGo on both devices."
        }
    }
}
