import Foundation

/// Librus API 2.0 client. Port of `LibrusApi.apiGet` incl. its error mapping.
/// Works against `api.librus.pl` (bearer token) or the Synergia gateway (session cookies).
public struct LibrusAPI: Sendable {
    let http: HTTPClient
    let baseURL: String
    /// Returns extra request headers; `true` asks for a forced re-authentication.
    let authorize: @Sendable (_ forceRefresh: Bool) async throws -> [String: String]

    public init(http: HTTPClient, baseURL: String = LibrusConstants.apiURL,
                authorize: @escaping @Sendable (_ forceRefresh: Bool) async throws -> [String: String]) {
        self.http = http
        self.baseURL = baseURL
        self.authorize = authorize
    }

    /// `api.librus.pl/2.0` with a bearer token (Konto Librus accounts).
    public static func bearer(http: HTTPClient, token: @escaping @Sendable (_ forceRefresh: Bool) async throws -> String) -> LibrusAPI {
        LibrusAPI(http: http) { force in ["Authorization": "Bearer \(try await token(force))"] }
    }

    /// `synergia.librus.pl/gateway/api/2.0` with the website session (Synergia login accounts).
    public static func gateway(session: CredentialSynergiaSession) -> LibrusAPI {
        LibrusAPI(http: session.http, baseURL: LibrusConstants.gatewayAPIURL) { force in
            if force {
                if !(try await session.refreshGatewayToken()) {
                    try await session.ensureLoggedIn(force: true)
                }
            } else {
                try await session.ensureLoggedIn(force: false)
            }
            return [:]
        }
    }

    public func get(_ endpoint: String, method: String = "GET") async throws -> JSON {
        do {
            return try await request(endpoint, method: method, forceRefresh: false)
        } catch LibrusError.tokenExpired {
            return try await request(endpoint, method: method, forceRefresh: true)
        }
    }

    private func request(_ endpoint: String, method: String, forceRefresh: Bool) async throws -> JSON {
        let headers = try await authorize(forceRefresh)
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw LibrusError.invalidResponse("zły adres \(endpoint)")
        }
        let response = try await http.send(url, method: method, headers: headers)
        if response.status == 503 { throw LibrusError.maintenance }
        let json = (try? response.json()) ?? .null
        if response.status == 200 { return json }
        // Expired token/session: retry once with fresh authentication.
        if response.status == 401 && !forceRefresh { throw LibrusError.tokenExpired }
        try LibrusAPI.throwError(json: json, status: response.status)
        return json
    }

    static func throwError(json: JSON, status: Int) throws {
        let code = json["Code"].string ?? json["Message"].string ?? json["Status"].string ?? "HTTP \(status)"
        let message = json["Message"].string
        switch code {
        case "TokenIsExpired": throw LibrusError.tokenExpired
        case "Maintenance": throw LibrusError.maintenance
        case "AccessDeny":
            if message == "Student timetable is not public" { throw LibrusError.timetableNotPublic }
            throw LibrusError.accessDenied(message ?? code)
        case "Request is denied", "Insufficient scopes": throw LibrusError.accessDenied(code)
        case "LuckyNumberIsNotActive": throw LibrusError.featureNotActive("szczęśliwy numerek")
        case "NotesIsNotActive": throw LibrusError.featureNotActive("uwagi")
        default:
            if status == 401 { throw LibrusError.tokenExpired }
            throw LibrusError.api(code: code, message: message)
        }
    }
}
