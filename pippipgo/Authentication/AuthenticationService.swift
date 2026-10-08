import Foundation

actor AuthenticationService: AccessTokenProviding {
    private let cognito: CognitoClient
    private let keychain: any TokenStoring
    private var tokens: TokenSet?
    private var refreshTask: Task<TokenSet, Error>?
    private var sessionEpoch = UUID()

    init(configuration: AppConfiguration = .live, keychain: (any TokenStoring)? = nil, urlSession: URLSession = .shared) {
        cognito = CognitoClient(configuration: configuration, urlSession: urlSession)
        self.keychain = keychain ?? KeychainStore(environment: configuration.environment)
    }

    func restore() async throws -> Bool {
        tokens = try keychain.load()
        guard tokens != nil else { return false }
        _ = try await validAccessToken()
        return true
    }

    func authorizationURL(state: String, challenge: String) throws -> URL { try cognito.authorizationURL(state: state, challenge: challenge) }

    func completeSignIn(code: String, verifier: String) async throws {
        let newTokens = try await cognito.tokens(code: code, verifier: verifier)
        try keychain.save(newTokens)
        tokens = newTokens
    }

    func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let tokens else { throw AuthenticationError.sessionExpired }
        guard forceRefresh || tokens.needsRefresh else { return tokens.accessToken }
        if let refreshTask {
            let ticket = sessionEpoch
            let refreshed = try await refreshTask.value
            guard sessionEpoch == ticket else { throw AuthenticationError.sessionExpired }
            return refreshed.accessToken
        }
        let task = Task { try await cognito.refresh(tokens) }
        let ticket = sessionEpoch
        refreshTask = task
        defer { if sessionEpoch == ticket { refreshTask = nil } }
        do {
            let refreshed = try await task.value
            guard sessionEpoch == ticket else { throw AuthenticationError.sessionExpired }
            try keychain.save(refreshed)
            self.tokens = refreshed
            return refreshed.accessToken
        } catch {
            guard sessionEpoch == ticket else { throw AuthenticationError.sessionExpired }
            try? keychain.delete()
            self.tokens = nil
            throw error
        }
    }

    func clearAndRevoke() async throws {
        let refreshToken = tokens?.refreshToken
        try clearLocalSession()
        if let refreshToken { try await cognito.revoke(refreshToken: refreshToken) }
    }

    func clearLocalSession() throws {
        sessionEpoch = UUID()
        refreshTask?.cancel(); refreshTask = nil
        tokens = nil
        try keychain.delete()
    }

    func profilePictureURL() async throws -> URL? {
        let token = try await validAccessToken()
        return try await cognito.profile(accessToken: token).pictureURL
    }

    func logoutURL() throws -> URL { try cognito.logoutURL() }
}
