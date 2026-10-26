import Foundation

/// Keeps tokens of one stored account fresh. Refresh tokens rotate on every use, so each
/// refresh is single-flight and the updated account is handed to `persist` right away.
public actor AccountSession {
    public private(set) var account: StoredAccount
    private let persist: @Sendable (StoredAccount) async -> Void
    let http = HTTPClient()

    private var portalAccess: TimedTokenValue?
    private var apiTokens: [String: TimedTokenValue] = [:]
    private var portalRefreshTask: Task<String, Error>?
    private var apiRefreshTask: Task<String, Error>?

    public init(account: StoredAccount, persist: @escaping @Sendable (StoredAccount) async -> Void) {
        self.account = account
        self.persist = persist
    }

    /// Synergia API bearer token for one student.
    public func apiToken(for login: String, forceRefresh: Bool = false) async throws -> String {
        if !forceRefresh, let cached = apiTokens[login], cached.isValid {
            return cached.value
        }
        switch account.kind {
        case .portal:
            let portalToken = try await portalAccessToken()
            do {
                let fresh = try await LibrusAuth.portalFreshAccountToken(login: login, portalToken: portalToken, http: http)
                apiTokens[login] = fresh
                return fresh.value
            } catch LibrusError.portalAccessDenied {
                portalAccess = nil
                let retried = try await portalAccessToken()
                let fresh = try await LibrusAuth.portalFreshAccountToken(login: login, portalToken: retried, http: http)
                apiTokens[login] = fresh
                return fresh.value
            }
        case .synergia:
            return try await refreshSynergiaToken(login: login)
        }
    }

    public func invalidateAPIToken(for login: String) {
        apiTokens[login] = nil
    }

    /// Used right after a fresh login, to avoid an extra refresh round-trip.
    public func seed(portalTokens: LibrusAuth.Tokens?, apiToken: (login: String, tokens: LibrusAuth.Tokens)?) {
        if let portalTokens {
            portalAccess = TimedTokenValue(value: portalTokens.accessToken, expiry: portalTokens.expiry)
        }
        if let apiToken {
            apiTokens[apiToken.login] = TimedTokenValue(value: apiToken.tokens.accessToken, expiry: apiToken.tokens.expiry)
        }
    }

    public func updateProfiles(_ profiles: [StudentProfile]) async {
        account.profiles = profiles
        await persist(account)
    }

    private func portalAccessToken() async throws -> String {
        if let portalAccess, portalAccess.isValid { return portalAccess.value }
        if let task = portalRefreshTask { return try await task.value }
        guard let refreshToken = account.portalRefreshToken else { throw LibrusError.notLoggedIn }
        let http = self.http
        let task = Task<String, Error> {
            let tokens = try await LibrusAuth.portalRefresh(refreshToken, http: http)
            await self.storePortal(tokens)
            return tokens.accessToken
        }
        portalRefreshTask = task
        defer { portalRefreshTask = nil }
        return try await task.value
    }

    private func storePortal(_ tokens: LibrusAuth.Tokens) async {
        portalAccess = TimedTokenValue(value: tokens.accessToken, expiry: tokens.expiry)
        account.portalRefreshToken = tokens.refreshToken
        await persist(account)
    }

    private func refreshSynergiaToken(login: String) async throws -> String {
        if let task = apiRefreshTask { return try await task.value }
        guard let refreshToken = account.apiRefreshToken else { throw LibrusError.notLoggedIn }
        let http = self.http
        let task = Task<String, Error> {
            let tokens = try await LibrusAuth.synergiaRefresh(refreshToken, http: http)
            await self.storeSynergia(tokens, login: login)
            return tokens.accessToken
        }
        apiRefreshTask = task
        defer { apiRefreshTask = nil }
        return try await task.value
    }

    private func storeSynergia(_ tokens: LibrusAuth.Tokens, login: String) async {
        apiTokens[login] = TimedTokenValue(value: tokens.accessToken, expiry: tokens.expiry)
        account.apiRefreshToken = tokens.refreshToken
        await persist(account)
    }
}

// MARK: - First login

public enum LibrusLogin {
    /// After the web view returned `code`: exchange it and list the Synergia accounts.
    public static func finishPortalLogin(code: String, email: String?) async throws -> (StoredAccount, LibrusAuth.Tokens) {
        let http = HTTPClient()
        let tokens = try await LibrusAuth.portalExchangeCode(code, http: http)
        let accounts = try await LibrusAuth.portalAccounts(portalToken: tokens.accessToken, http: http)
        var stored = StoredAccount(kind: .portal, displayName: email ?? "Konto Librus", portalRefreshToken: tokens.refreshToken)
        stored.profiles = accounts.map {
            StudentProfile(accountID: stored.id, login: $0.login, studentName: $0.studentName, isParent: $0.isParent)
        }
        return (stored, tokens)
    }

    /// Synergia login + password. The password is only sent to Librus here and never stored.
    public static func synergiaLogin(login: String, password: String) async throws -> (StoredAccount, LibrusAuth.Tokens) {
        let http = HTTPClient()
        let tokens = try await LibrusAuth.synergiaLogin(login: login, password: password, http: http)
        let api = LibrusAPI(http: http) { _ in tokens.accessToken }
        let me = try await api.get("Me")["Me"]
        let account = me["Account"]
        let user = me["User"]
        let groupID = account["GroupId"].int ?? 0
        let studentName = [user["FirstName"].string, user["LastName"].string]
            .compactMap { $0 }.joined(separator: " ").fixedName
        let realLogin = account["Login"].string ?? login
        var stored = StoredAccount(kind: .synergia, displayName: realLogin, apiRefreshToken: tokens.refreshToken)
        stored.profiles = [StudentProfile(
            accountID: stored.id, login: realLogin,
            studentName: studentName.isEmpty ? realLogin : studentName,
            isParent: (5...6).contains(groupID)
        )]
        return (stored, tokens)
    }
}
