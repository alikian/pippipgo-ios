import Foundation

protocol AccessTokenProviding: Sendable {
    func validAccessToken(forceRefresh: Bool) async throws -> String
}

/// Fixed routes prevent accidentally sending a bearer token to a caller-supplied host.
enum APIEndpoint: Sendable, Equatable {
    case introduction, organizer, travelChat, guide, guideSetup, guideBooking
    case account, accountExport, journeys, journey(UUID), journeyAction(UUID), journeyImport(UUID)
    case memory, memoryItem(UUID), travelers, traveler(UUID), preferences, sync(after: Int)
    var path: String {
        switch self {
        case .guideSetup: "/v1/guide/setup"
        case .guideBooking: "/v1/guide/booking"
        case .guide: "/v1/guide"
        case .travelChat: "/v1/travel-chat"
        case .organizer: "/v1/travel-organizer"
        case .introduction: "/v1/traveler-conversation"
        case .account: "/v1/me"
        case .accountExport: "/v1/me/export"
        case .journeys: "/v1/journeys"
        case .journey(let id): "/v1/journeys/\(id.uuidString.lowercased())"
        case .journeyAction(let id): "/v1/journeys/\(id.uuidString.lowercased())/actions"
        case .journeyImport(let id): "/v1/journeys/\(id.uuidString.lowercased())/imports"
        case .memory: "/v1/memory"
        case .memoryItem(let id): "/v1/memory/\(id.uuidString.lowercased())"
        case .travelers: "/v1/travelers"
        case .traveler(let id): "/v1/travelers/\(id.uuidString.lowercased())"
        case .preferences: "/v1/preferences"
        case .sync: "/v1/sync"
        }
    }
    var canRead: Bool {
        switch self { case .guideBooking, .journeyAction, .journeyImport: false; default: true }
    }
    var canPut: Bool {
        switch self { case .guideSetup, .guide, .travelChat, .organizer, .introduction, .journey, .journeyAction, .journeyImport, .memoryItem, .traveler, .preferences: true; default: false }
    }
    var canPost: Bool { self == .guide || self == .guideBooking }
    var canDelete: Bool {
        switch self { case .journey, .memoryItem, .traveler: true; default: false }
    }
}

/// Construct once per user intent; retain this exact value for retries. A changed draft or
/// deliberate conflict resolution is a new operation. No automatic conflict overwrites.
struct APIRequest<Response: Decodable & Sendable>: Sendable {
    let endpoint: APIEndpoint
    let method: String
    let body: Data?
    let idempotencyKey: UUID?
    let expectedVersion: Int?

    private init(endpoint: APIEndpoint, method: String, body: Data? = nil, key: UUID? = nil, version: Int? = nil) {
        self.endpoint = endpoint
        self.method = method
        self.body = body
        idempotencyKey = key
        expectedVersion = version
    }

    static func get(_ endpoint: APIEndpoint) throws -> Self {
        guard endpoint.canRead else { throw APIClientError.invalidRequest("This endpoint does not support reading.") }
        if case .sync(let cursor) = endpoint, cursor < 0 { throw APIClientError.invalidRequest("Sync cursor must not be negative.") }
        return Self(endpoint: endpoint, method: "GET")
    }

    static func put<Body: Encodable>(_ endpoint: APIEndpoint, body: Body, expectedVersion: Int, idempotencyKey: UUID = UUID()) throws -> Self {
        guard endpoint.canPut, expectedVersion >= 0 else { throw APIClientError.invalidRequest("Invalid update endpoint or version.") }
        return try Self(endpoint: endpoint, method: "PUT", body: APIJSON.encoder().encode(body), key: idempotencyKey, version: expectedVersion)
    }

    static func post<Body: Encodable>(_ endpoint: APIEndpoint, body: Body, idempotencyKey: UUID = UUID()) throws -> Self {
        guard endpoint.canPost else { throw APIClientError.invalidRequest("This endpoint does not support creation by POST.") }
        return try Self(endpoint: endpoint, method: "POST", body: APIJSON.encoder().encode(body), key: idempotencyKey)
    }

    static func delete(_ endpoint: APIEndpoint, expectedVersion: Int, idempotencyKey: UUID = UUID()) throws -> Self {
        guard endpoint.canDelete, expectedVersion > 0 else { throw APIClientError.invalidRequest("Deletion requires an existing record version.") }
        return Self(endpoint: endpoint, method: "DELETE", key: idempotencyKey, version: expectedVersion)
    }

    /// Account deletion is idempotent on the server and has no version/key headers.
    static func deleteAccount() -> Self { Self(endpoint: .account, method: "DELETE") }
}

struct APIClient: Sendable {
    let baseURL: URL
    var urlSession: URLSession = .shared

    func account(accessToken: String) async throws -> AccountRecord {
        try await send(.get(.account), accessToken: accessToken)
    }

    func account(using authentication: any AccessTokenProviding) async throws -> AccountRecord {
        try await send(.get(.account), using: authentication)
    }

    func send<Response>(_ operation: APIRequest<Response>, using authentication: any AccessTokenProviding) async throws -> Response {
        let data = try await authenticatedData(operation, using: authentication)
        return try decode(Response.self, from: data)
    }

    /// For callers that already manage their token lifecycle; performs no authentication retry.
    func send<Response>(_ operation: APIRequest<Response>, accessToken: String) async throws -> Response {
        let data = try await perform(operation, accessToken: accessToken)
        return try decode(Response.self, from: data)
    }

    private func authenticatedData<Response>(_ operation: APIRequest<Response>, using authentication: any AccessTokenProviding) async throws -> Data {
        try Task.checkCancellation()
        let token = try await authentication.validAccessToken(forceRefresh: false)
        do {
            return try await perform(operation, accessToken: token)
        } catch APIClientError.unauthorized {
            try Task.checkCancellation()
            let refreshed = try await authentication.validAccessToken(forceRefresh: true)
            // Retry the frozen request once. A second 401 escapes to the caller.
            return try await perform(operation, accessToken: refreshed)
        }
    }

    private func perform<Response>(_ operation: APIRequest<Response>, accessToken: String) async throws -> Data {
        try Task.checkCancellation()
        guard var components = URLComponents(url: baseURL.appending(path: operation.endpoint.path), resolvingAgainstBaseURL: false),
              ["https", "http"].contains(components.scheme), components.host != nil,
              components.user == nil, components.password == nil else { throw APIClientError.invalidRequest("Invalid backend URL.") }
        components.query = nil
        components.fragment = nil
        if case .sync(let cursor) = operation.endpoint { components.queryItems = [.init(name: "after", value: String(cursor))] }
        guard let url = components.url else { throw APIClientError.invalidRequest("Invalid backend URL.") }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 65)
        request.httpMethod = operation.method
        request.httpBody = operation.body
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if operation.body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let key = operation.idempotencyKey { request.setValue(key.uuidString.lowercased(), forHTTPHeaderField: "Idempotency-Key") }
        if let version = operation.expectedVersion { request.setValue(String(version), forHTTPHeaderField: "X-Expected-Version") }
        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIClientError.invalidResponse }
            if http.statusCode == 401 { throw APIClientError.unauthorized }
            guard (200..<300).contains(http.statusCode) else {
                let decoded = try? APIJSON.decoder().decode(APIErrorEnvelope.self, from: data).error
                let error = decoded ?? APIErrorBody(code: "http_error", message: "The server returned HTTP \(http.statusCode).")
                let requestID = error.requestID ?? http.value(forHTTPHeaderField: "X-Request-ID")
                if http.statusCode == 409 { throw APIClientError.conflict(error, requestID: requestID) }
                throw APIClientError.rejected(status: http.statusCode, error: error, requestID: requestID)
            }
            return data
        } catch let error as URLError where [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut, .dnsLookupFailed].contains(error.code) {
            // The outcome of a write can be unknown. Do not regenerate its key or silently retry.
            throw APIClientError.connection
        }
    }

    private func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        do { return try APIJSON.decoder().decode(type, from: data) }
        catch { throw APIClientError.decoding }
    }
}
