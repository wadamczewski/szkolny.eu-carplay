import Foundation

public enum AccountKind: String, Codable, Sendable {
    /// Konto Librus (e-mail) — one portal login gives access to several Synergia accounts.
    case portal
    /// Direct Synergia login (e.g. `1234567u`) via the Synergia website login form.
    case synergia
}

/// Everything needed to log in again without asking for a password. Stored in the Keychain.
public struct StoredAccount: Codable, Identifiable, Sendable, Equatable {
    public var id: UUID
    public var kind: AccountKind
    public var displayName: String
    public var portalRefreshToken: String?
    /// Only for `.synergia`: Synergia sessions can't be refreshed without logging in again.
    /// Kept in the Keychain together with the rest of this struct.
    public var synergiaPassword: String?
    public var profiles: [StudentProfile]

    public init(id: UUID = UUID(), kind: AccountKind, displayName: String,
                portalRefreshToken: String? = nil, synergiaPassword: String? = nil,
                profiles: [StudentProfile] = []) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.portalRefreshToken = portalRefreshToken
        self.synergiaPassword = synergiaPassword
        self.profiles = profiles
    }
}

/// One student (one Synergia account).
public struct StudentProfile: Codable, Identifiable, Sendable, Hashable {
    public var id: String { "\(accountID.uuidString)-\(login)" }
    public var accountID: UUID
    public var login: String
    public var studentName: String
    public var isParent: Bool

    public init(accountID: UUID, login: String, studentName: String, isParent: Bool) {
        self.accountID = accountID
        self.login = login
        self.studentName = studentName
        self.isParent = isParent
    }

    public var shortName: String {
        let parts = studentName.split(separator: " ")
        guard parts.count > 1, let last = parts.last?.first else { return studentName }
        return "\(parts.first!) \(last)."
    }
}

extension TimedTokenValue {
    var isValid: Bool { expiry.timeIntervalSinceNow > 60 }
}

extension String {
    /// "KOWALSKI JAN" / "jan kowalski" → "Jan Kowalski" (port of `fixName()`).
    var fixedName: String {
        lowercased()
            .split(separator: " ", omittingEmptySubsequences: true)
            .map { word in
                word.split(separator: "-", omittingEmptySubsequences: false)
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: "-")
            }
            .joined(separator: " ")
    }
}
