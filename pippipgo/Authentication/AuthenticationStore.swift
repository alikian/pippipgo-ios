import Foundation
import Observation

@MainActor
@Observable
final class AuthenticationStore {
    enum State: Equatable {
        case restoring
        case signedOut
        case signingIn
        case loadingAccount
        case signedIn(AccountRecord)
        case accountError(String)
        case signInError(String)
        case signingOut
        case deletingAccount
        case accountDeletionFailed(String)
        case accountDeletionCleanupFailed
    }

    private(set) var state: State = .restoring
    private(set) var profilePictureURL: URL?
    private var sessionEpoch = UUID()
    let chat: TravelChatStore
    let organizer: OrganizerStore
    let intelligence: IntelligenceStore
    private let configuration: AppConfiguration
    private let authentication: AuthenticationService
    private let apiClient: APIClient
    private let webAuthentication = WebAuthenticationSession()

    init(configuration: AppConfiguration = .live, authentication: AuthenticationService? = nil, apiClient: APIClient? = nil) {
        let auth = authentication ?? AuthenticationService(configuration: configuration)
        let client = apiClient ?? APIClient(baseURL: configuration.backendBaseURL)
        chat = TravelChatStore(client: client, authentication: auth)
        organizer = OrganizerStore(client: client, authentication: auth)
        intelligence = IntelligenceStore(client: client, authentication: auth)
        self.configuration = configuration
        self.authentication = auth
        self.apiClient = client
    }

    func restoreSession() async {
        guard state == .restoring else { return }
        do {
            if try await authentication.restore() { await loadAccount() } else { state = .signedOut }
        } catch {
            state = .signInError(error.localizedDescription)
        }
    }

    func signIn() async {
        guard state != .deletingAccount else { return }
        TalkToPipLaunch.shared.cancel()
        sessionEpoch = UUID()
        profilePictureURL = nil
        intelligence.reset()
        organizer.reset()
        chat.reset()
        state = .signingIn
        do {
            let verifier = try PKCE.randomURLSafeString(byteCount: 64)
            let stateValue = try PKCE.randomURLSafeString()
            let url = try await authentication.authorizationURL(state: stateValue, challenge: PKCE.challenge(for: verifier))
            // Managed Login forwards select_account to Google. Share browser cookies
            // so Google can offer existing browser accounts rather than require email entry.
            let callback = try await webAuthentication.authenticate(url: url, callbackScheme: configuration.callbackURL.scheme ?? "pippipgo", prefersEphemeral: false)
            let code = try OAuthCallback.authorizationCode(from: callback, expectedCallback: configuration.callbackURL, expectedState: stateValue)
            try await authentication.completeSignIn(code: code, verifier: verifier)
            await loadAccount()
        } catch AuthenticationError.cancelled {
            state = .signedOut
        } catch {
            state = .signInError(error.localizedDescription)
        }
    }

    func loadAccount() async {
        guard state != .deletingAccount else { return }
        let ticket = sessionEpoch
        state = .loadingAccount
        do {
            let account = try await apiClient.account(using: authentication)
            guard ticket == sessionEpoch else { return }
            state = .signedIn(account)
            // Photo loading is optional and must never prevent opening the app.
            let photo = try? await authentication.profilePictureURL()
            guard ticket == sessionEpoch else { return }
            profilePictureURL = photo
        } catch {
            guard ticket == sessionEpoch else { return }
            state = .accountError(error.localizedDescription)
        }
    }

    func signOut() async {
        guard state != .deletingAccount else { return }
        TalkToPipLaunch.shared.cancel()
        sessionEpoch = UUID()
        profilePictureURL = nil
        intelligence.reset()
        organizer.reset()
        chat.reset()
        state = .signingOut
        var message: String?
        do { try await authentication.clearAndRevoke() }
        catch { message = "The local session was cleared, but Cognito token revocation could not be confirmed." }

        do {
            let logoutURL = try await authentication.logoutURL()
            let callback = try await webAuthentication.authenticate(url: logoutURL, callbackScheme: configuration.logoutURL.scheme ?? "pippipgo", prefersEphemeral: false)
            try OAuthCallback.validateLogout(callback, expectedCallback: configuration.logoutURL)
        } catch AuthenticationError.cancelled {
            message = message ?? "You are signed out locally. Cognito browser logout was cancelled."
        } catch {
            message = message ?? "You are signed out locally. Cognito browser logout could not be confirmed."
        }
        state = message.map(State.signInError) ?? .signedOut
    }

    func deleteAccount() async {
        switch state {
        case .signedIn, .accountDeletionFailed: break
        default: return
        }
        let ticket = UUID(); sessionEpoch = ticket
        TalkToPipLaunch.shared.cancel()
        profilePictureURL = nil
        intelligence.reset(); organizer.reset(); chat.reset()
        state = .deletingAccount
        do {
            let result: AccountDeletionResult = try await apiClient.send(.deleteAccount(), using: authentication)
            guard sessionEpoch == ticket else { return }
            guard result.status == "deleted" else { throw APIClientError.invalidResponse }
        } catch {
            guard sessionEpoch == ticket else { return }
            // A lost response may mean deletion already began. Do not resume ordinary writes.
            state = .accountDeletionFailed("Deletion could not be confirmed. Your account may already be disabled. Check your connection and retry deletion.")
            return
        }
        await finishAccountDeletion()
    }

    func finishAccountDeletion() async {
        guard state == .deletingAccount || state == .accountDeletionCleanupFailed else { return }
        let ticket = sessionEpoch
        state = .deletingAccount
        do {
            try await authentication.clearLocalSession()
            guard sessionEpoch == ticket else { return }
            state = .signedOut
        } catch {
            guard sessionEpoch == ticket else { return }
            state = .accountDeletionCleanupFailed
        }
    }
}

struct AccountDeletionResult: Decodable, Sendable {
    let status: String
}
