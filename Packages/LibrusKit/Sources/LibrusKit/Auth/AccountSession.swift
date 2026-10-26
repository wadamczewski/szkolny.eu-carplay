import Foundation

/// Keeps tokens of one stored account fresh. Refresh tokens rotate on every use, so each
/// refresh is single-flight and the updated account is handed to `persist` right away.
public actor AccountSession {
    public private(set) var account: StoredAccount
    private let persist: @Sendable (StoredAccount) async -> Void
    let http = HTTPClient()
    /// For `.synergia` accounts: the website session shared by the API gateway and messages.
    public nonisolated let credentialSession: CredentialSynergiaSession?

    private var portalAccess: TimedTokenValue?
    private var apiTokens: [String: TimedTokenValue] = [:]
    private var portalRefreshTask: Task<String, Error>?

    public init(account: StoredAccount, persist: @escaping @Sendable (StoredAccount) async -> Void) {
        self.account = account
        self.persist = persist
        if account.kind == .synergia, let login = account.profiles.first?.login, let password = account.synergiaPassword {
            credentialSession = CredentialSynergiaSession(login: login, password: password)
        } else {
            credentialSession = nil
        }
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
            // Synergia login accounts use the gateway API with cookies, not bearer tokens.
            throw LibrusError.notLoggedIn
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

    /// Synergia login + password via the website login form. The password is kept (Keychain)
    /// because Synergia sessions can't be renewed without it.
    public static func synergiaLogin(login: String, password: String) async throws -> StoredAccount {
        let session = CredentialSynergiaSession(login: login, password: password)
        try await session.ensureLoggedIn(force: false)
        let me = try await LibrusAPI.gateway(session: session).get("Me")["Me"]
        let account = me["Account"]
        let user = me["User"]
        let groupID = account["GroupId"].int ?? 0
        let studentName = [user["FirstName"].string, user["LastName"].string]
            .compactMap { $0 }.joined(separator: " ").fixedName
        var stored = StoredAccount(kind: .synergia, displayName: login, synergiaPassword: password)
        stored.profiles = [StudentProfile(
            accountID: stored.id, login: login,
            studentName: studentName.isEmpty ? login : studentName,
            isParent: (5...6).contains(groupID)
        )]
        return stored
    }
}
