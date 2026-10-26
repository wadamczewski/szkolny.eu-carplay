import Foundation

/// Something that can put a logged-in Synergia website session (cookies) into `http`.
public protocol SynergiaSessionProvider: Sendable {
    var http: HTTPClient { get }
    func ensureLoggedIn(force: Bool) async throws
}

/// Konto Librus accounts: Synergia session opened with an API `AutoLoginToken`
/// (port of `LibrusLoginSynergia`).
public actor AutoLoginSynergiaSession: SynergiaSessionProvider {
    public nonisolated let http = HTTPClient()
    private let api: LibrusAPI
    private var expiry: Date?
    private var loginTask: Task<Void, Error>?

    public init(api: LibrusAPI) {
        self.api = api
    }

    public func ensureLoggedIn(force: Bool) async throws {
        if !force, let expiry, expiry.timeIntervalSinceNow > 60 { return }
        if let loginTask { return try await loginTask.value }
        let task = Task { try await self.login() }
        loginTask = task
        defer { loginTask = nil }
        try await task.value
    }

    private func login() async throws {
        let json = try await api.get("AutoLoginToken", method: "POST")
        guard let token = json["Token"].string else {
            throw LibrusError.synergiaSession("brak tokenu AutoLoginToken")
        }
        http.clearCookies()
        let url = URL(string: LibrusConstants.synergiaTokenLoginURL.replacingOccurrences(of: "TOKEN", with: token)
                      + "/uczen/widok/centrum_powiadomien")!
        // Like Android: success only when Synergia redirects to the notification centre.
        let response = try await http.send(url, followRedirects: false)
        let location = response.location ?? ""
        if location.hasSuffix("przerwa_techniczna") || response.text.contains("Przerwa techniczna") {
            throw LibrusError.maintenance
        }
        guard location.contains("centrum_powiadomien") else {
            throw LibrusError.synergiaSession("token logowania odrzucony (HTTP \(response.status))")
        }
        expiry = Date().addingTimeInterval(40 * 60)
    }
}

/// Synergia login + password: the website login form (as used by the maintained librus-apix
/// project), since `api.librus.pl/OAuth/Token` no longer accepts the password grant
/// (`unsupported_grant_type`). The same cookies then give access to the API 2.0 through
/// `synergia.librus.pl/gateway/api/2.0`.
public actor CredentialSynergiaSession: SynergiaSessionProvider {
    public nonisolated let http = HTTPClient()
    private let login: String
    private let password: String
    private var expiry: Date?
    private var loginTask: Task<Void, Error>?

    public init(login: String, password: String) {
        self.login = login
        self.password = password
    }

    public func ensureLoggedIn(force: Bool) async throws {
        if !force, let expiry, expiry.timeIntervalSinceNow > 60 { return }
        if let loginTask { return try await loginTask.value }
        let task = Task { try await self.performLogin() }
        loginTask = task
        defer { loginTask = nil }
        try await task.value
    }

    /// Short-lived `oauth_token` cookie needed by the gateway API.
    func refreshGatewayToken() async throws -> Bool {
        let response = try await http.send(URL(string: "\(LibrusConstants.synergiaURL)/refreshToken")!,
                                           userAgent: LibrusConstants.webUserAgent)
        return response.status == 200
    }

    private func performLogin() async throws {
        http.clearCookies()
        let ua = LibrusConstants.webUserAgent
        let api = LibrusConstants.apiOAuthURL
        let start = try await http.send(URL(string: "\(LibrusConstants.synergiaURL)/loguj/portalRodzina?v=\(Int(Date().timeIntervalSince1970))")!,
                                        userAgent: ua)
        if start.status == 503 || start.text.contains("Przerwa techniczna") { throw LibrusError.maintenance }

        let response = try await http.send(URL(string: "\(api)/Authorization?client_id=\(LibrusConstants.synergiaWebClientID)")!,
                                           method: "POST",
                                           form: [("action", "login"), ("login", login), ("pass", password)],
                                           userAgent: ua)
        if response.status == 503 { throw LibrusError.maintenance }
        let json = try response.json()
        if json["status"].string == "error" {
            let message = json["errors"].array.first?["message"].string ?? "nieznany błąd"
            if message.lowercased().contains("nieprawidłowy login") { throw LibrusError.invalidLogin }
            throw LibrusError.synergiaSession(message)
        }

        let finish = try await http.send(URL(string: "\(api)/Authorization/2FA?client_id=\(LibrusConstants.synergiaWebClientID)")!,
                                         userAgent: ua)
        let finalURL = finish.http.url?.absoluteString ?? ""
        if finalURL.contains("error=") {
            throw LibrusError.synergiaSession("Librus odrzucił logowanie (\(finalURL.contains("access_denied") ? "brak dostępu" : "błąd"))")
        }
        guard try await refreshGatewayToken() else {
            throw LibrusError.synergiaSession("nie udało się uzyskać tokenu API")
        }
        expiry = Date().addingTimeInterval(30 * 60)
    }
}
