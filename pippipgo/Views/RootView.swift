import SwiftUI

struct RootView: View {
    let store: AuthenticationStore
    @State private var aiConsent = AISharingConsent.shared
    @State private var guestSessionID: UUID?
    @State private var siriSignInRequired = false
    @State private var showDownloadedTour = false
    @Environment(\.scenePhase) private var scenePhase
    var environment: AppEnvironment = AppConfiguration.live.environment

    var body: some View {
        VStack(spacing: 0) {
            // The map screens show this on the map, so the map can reach the top of the screen.
            if environment != .prod && !showsMap {
                HStack {
                    Spacer()
                    BuildEnvironmentIndicator(environment: environment)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
            }
            Group {
                switch store.state {
                case .restoring:
                    StartupLoadingView(message: "Restoring your session…")
                // Signed-out entry offers account sign-in or an explicit guest session.
                case .signedOut:
                    #if DEBUG
                    // Simulator layout review only: `-PipPreviewHome` shows the signed-in map
                    // without an account; network features stay unavailable.
                    if ProcessInfo.processInfo.arguments.contains("-PipPreviewHome") {
                        TravelOrganizerView(store: store.organizer, chat: store.chat, signOut: {}, deleteAccount: {})
                    } else {
                        signedOutEntry
                    }
                    #else
                    signedOutEntry
                    #endif
                case .signingIn:
                    LoginEntryView(signIn: {}, guest: {}, signingIn: true)
                case .signInError:
                    signedOutEntry
                case .loadingAccount:
                    AccountLoadingView()
                case .signedIn:
                    if aiConsent.allowed {
                        TravelOrganizerView(store: store.organizer, chat: store.chat, profilePictureURL: store.profilePictureURL, signOut: { Task { await store.signOut() } }, deleteAccount: { Task { await store.deleteAccount() } })
                    } else {
                        AISharingConsentView(consent: aiConsent, deleteAccount: { Task { await store.deleteAccount() } })
                    }
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
        .safeAreaInset(edge: .bottom) {
            if offersDownloadedTour, !store.chat.liveGuide.downloadedTours.isEmpty {
                Button("My Tours", systemImage: "arrow.down.circle") { showDownloadedTour = true }
                    .frame(maxWidth: .infinity, minHeight: 48).background(.regularMaterial)
            }
        }
        .sheet(isPresented: $showDownloadedTour) { MyToursView(guide: store.chat.liveGuide) }
        .animation(.easeInOut(duration: 0.2), value: store.state)
        .onChange(of: store.state, initial: true) { _, _ in checkVoiceLaunch(); syncLocationDisplay() }
        .onChange(of: store.state) { _, state in
            if case .signedOut = state { return }
            guestSessionID = nil
        }
        .onChange(of: aiConsent.allowed) { _, _ in syncLocationDisplay() }
        .onChange(of: scenePhase, initial: true) { _, _ in syncLocationDisplay() }
        .task {
            WatchPhoneBridge.shared.start(readState: { (watchAccountID, watchState) }, perform: performWatchCommand)
            while !Task.isCancelled {
                WatchPhoneBridge.shared.publish()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: store.state) { _, _ in WatchPhoneBridge.shared.publish() }
        .onChange(of: aiConsent.allowed) { _, _ in WatchPhoneBridge.shared.publish() }
        .onChange(of: scenePhase) { _, _ in WatchPhoneBridge.shared.publish() }
        .onDisappear { store.chat.locationDisplay.stop() }
        .onChange(of: TalkToPipLaunch.shared.requestID) { _, _ in checkVoiceLaunch() }
        .alert("Sign in to talk to Pip", isPresented: $siriSignInRequired) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Sign in to PipPipGo, then ask Siri to start Talk to Pip again.")
        }
    }
    @ViewBuilder private var signedOutEntry: some View {
        if let guestSessionID {
            GuestExploreView(signIn: { self.guestSessionID = nil })
                .id(guestSessionID)
        } else {
            LoginEntryView(signIn: beginSignIn, guest: beginGuestSession, errorMessage: signInErrorMessage)
        }
    }

    private var signInErrorMessage: String? {
        if case .signInError(let message) = store.state { return message }
        return nil
    }

    private func beginGuestSession() { guestSessionID = UUID() }

    private func beginSignIn() {
        guestSessionID = nil
        Task { await store.signIn() }
    }

    private var offersDownloadedTour: Bool {
        switch store.state { case .restoring, .loadingAccount, .signedOut, .signInError, .accountError: true; default: false }
    }
    private var showsMap: Bool {
        switch store.state {
        case .signedOut, .signInError: guestSessionID != nil
        case .signingIn: false
        case .signedIn: aiConsent.allowed
        default: false
        }
    }
    private func syncLocationDisplay() {
        if case .signedIn = store.state, aiConsent.allowed, scenePhase == .active { store.chat.locationDisplay.start() }
        else { store.chat.locationDisplay.stop() }
    }
    private var watchAccountID: String? {
        guard case .signedIn(let account) = store.state else { return nil }
        return account.id
    }

    private var watchState: WatchControlState {
        let guide = store.chat.liveGuide
        return WatchControlState(sessionID: UUID(), updatedAt: Date(),
                                 ready: watchAccountID != nil && aiConsent.allowed,
                                 foreground: UIApplication.shared.applicationState == .active,
                                 exploring: guide.enabled && guide.activeTour == nil, talking: store.chat.voice.active,
                                 canSkip: guide.announcementSpeaking,
                                 hasTour: guide.activeTour != nil, language: AppLanguage.current.rawValue)
    }

    private func performWatchCommand(_ command: WatchCommand) -> WatchControlResult {
        // Recheck here as well as at the transport boundary. No watch authentication or AI bypass.
        guard watchAccountID != nil, aiConsent.allowed else { return .signIn }
        let guide = store.chat.liveGuide
        switch command {
        case .refresh: return .success
        case .skip:
            guard guide.announcementSpeaking else { return .nothingToSkip }
            guide.skipAnnouncement()
        case .stopExplore:
            guard guide.activeTour == nil else { return .finishTour }
            guide.enabled = false
        case .endTalk:
            store.chat.voice.stop()
        case .explore:
            guard UIApplication.shared.applicationState == .active else { return .openPhone }
            guard guide.activeTour == nil else { return .finishTour }
            guard !store.chat.translator.active else { return .busy }
            guide.enabled = true
            WatchPhoneBridge.shared.navigate(to: .explore)
        case .talk:
            guard UIApplication.shared.applicationState == .active else { return .openPhone }
            guard !store.chat.translator.active, !store.chat.busy, store.chat.pending == nil else { return .busy }
            if !store.chat.voice.active { guide.toggleConversation() }
            guard store.chat.voice.active else { return .openPhone }
            WatchPhoneBridge.shared.navigate(to: .pip)
        }
        return .success
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


private struct LoginEntryView: View {
    let signIn: () -> Void
    let guest: () -> Void
    var signingIn = false
    var errorMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                PipWelcomeArtwork().frame(maxWidth: 280).accessibilityHidden(true)
                Text(verbatim: "PipPipGo").font(.largeTitle.bold())
                if let errorMessage {
                    Text(LocalizedStringKey(errorMessage)).foregroundStyle(.secondary)
                }
                Button(action: signIn) {
                    HStack {
                        if signingIn { ProgressView() }
                        Text("Sign in or create account").font(.headline)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .disabled(signingIn)
                .accessibilityIdentifier("login.signIn")
                Button("Continue as guest", action: guest)
                    .frame(minHeight: 44)
                    .disabled(signingIn)
                    .accessibilityIdentifier("login.guest")
            }
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemBackground))
    }
}
