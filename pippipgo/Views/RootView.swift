import SwiftUI

struct RootView: View {
    let store: AuthenticationStore
    @State private var siriSignInRequired = false
    @Environment(\.scenePhase) private var scenePhase
    var environment: AppEnvironment = AppConfiguration.live.environment

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                BuildEnvironmentIndicator(environment: environment)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            Group {
                switch store.state {
                case .restoring:
                    StartupLoadingView(message: "Restoring your session…")
                case .signedOut:
                    WelcomeView(isBusy: false, errorMessage: nil) { Task { await store.signIn() } }
                case .signingIn:
                    WelcomeView(isBusy: true, errorMessage: nil) {}
                case .signInError(let message):
                    WelcomeView(isBusy: false, errorMessage: message) { Task { await store.signIn() } }
                case .loadingAccount:
                    AccountLoadingView()
                case .signedIn:
                    TravelOrganizerView(store: store.organizer, chat: store.chat, profilePictureURL: store.profilePictureURL, signOut: { Task { await store.signOut() } }, deleteAccount: { Task { await store.deleteAccount() } })
                case .accountError(let message):
                    AccountErrorView(message: message, retry: { Task { await store.loadAccount() } }, signOut: { Task { await store.signOut() } })
                case .signingOut:
                    ProgressView("Signing out…")
                case .deletingAccount:
                    ProgressView("Deleting your account…")
                case .accountDeletionFailed(let message):
                    AccountDeletionErrorView(message: message, retry: { Task { await store.deleteAccount() } }, signOut: { Task { await store.signOut() } })
                case .accountDeletionCleanupFailed:
                    ContentUnavailableView {
                        Label("Your account was deleted", systemImage: "checkmark.circle")
                    } description: {
                        Text("This device could not clear its saved sign-in. Retry to finish signing out.")
                    } actions: {
                        Button("Finish signing out") { Task { await store.finishAccountDeletion() } }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: store.state)
        .onChange(of: store.state, initial: true) { _, _ in checkVoiceLaunch(); syncLocationDisplay() }
        .onChange(of: scenePhase, initial: true) { _, _ in syncLocationDisplay() }
        .onDisappear { store.chat.locationDisplay.stop() }
        .onChange(of: TalkToPipLaunch.shared.requestID) { _, _ in checkVoiceLaunch() }
        .alert("Sign in to talk to Pip", isPresented: $siriSignInRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in to PipPipGo, then ask Siri to start Talk to Pip again.")
        }
    }
    private func syncLocationDisplay() {
        if case .signedIn = store.state, scenePhase == .active { store.chat.locationDisplay.start() }
        else { store.chat.locationDisplay.stop() }
    }
    private func checkVoiceLaunch() {
        guard TalkToPipLaunch.shared.requestID != nil else { return }
        switch store.state {
        case .restoring, .loadingAccount, .signedIn: break
        default:
            TalkToPipLaunch.shared.cancel()
            siriSignInRequired = true
        }
    }
}


struct BuildEnvironmentIndicator: View {
    let environment: AppEnvironment

    private var title: LocalizedStringKey {
        switch environment {
        case .local: "Environment: Local"
        case .dev: "Environment: Dev"
        case .prod: "Environment: Production"
        }
    }

    private var color: Color {
        switch environment {
        case .local: .blue
        case .dev: .orange
        case .prod: .green
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5).accessibilityHidden(true)
            Text(title).font(.caption2.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.regularMaterial, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityIdentifier("app.buildEnvironment")
    }
}

/// Shows the welcome artwork while the saved session is restored.
struct StartupLoadingView: View {
    let message: String

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    PipWelcomeArtwork()
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    Text("PipPipGo").font(.largeTitle.bold())
                    ProgressView(LocalizedStringKey(message))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
    }
}
