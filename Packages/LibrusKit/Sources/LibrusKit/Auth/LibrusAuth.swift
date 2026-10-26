import Foundation

/// Stateless login requests. Ported from `LibrusLoginPortal`, `LibrusLoginApi`,
/// `LibrusFirstLogin` and `SynergiaTokenExtractor`.
public enum LibrusAuth {
    public struct Tokens: Sendable {
        public let accessToken: String
        public let refreshToken: String
        public let expiry: Date
    }

    public struct PortalSynergiaAccount: Sendable {
        public let id: Int
        public let login: String
        public let accessToken: String
        public let studentName: String
        public let isParent: Bool
    }

    // MARK: Konto Librus (portal)

    /// Exchange the `code` from `app://librus?code=...` (caught by the login web view).
    public static func portalExchangeCode(_ code: String, http: HTTPClient) async throws -> Tokens {
        try await portalToken(http: http, params: [
            ("client_id", LibrusConstants.portalClientID),
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", LibrusConstants.portalRedirectURL),
        ])
    }

    public static func portalRefresh(_ refreshToken: String, http: HTTPClient) async throws -> Tokens {
        try await portalToken(http: http, params: [
            ("client_id", LibrusConstants.portalClientID),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
        ])
    }

    private static func portalToken(http: HTTPClient, params: [(String, String)]) async throws -> Tokens {
        let response = try await http.send(LibrusConstants.portalTokenURL, method: "POST", form: params)
        let json = try response.json()
        if response.status != 200 {
            let hint = json["hint"].string ?? json["error"].string ?? "HTTP \(response.status)"
            switch hint {
            case "Cannot decrypt the refresh token", "Token has been revoked",
                 "Authorization code has expired", "Authorization code has been revoked":
                throw LibrusError.portalAccessDenied
            default:
                throw LibrusError.api(code: hint, message: json["message"].string)
            }
        }
        guard let access = json["access_token"].string, let refresh = json["refresh_token"].string else {
            throw LibrusError.invalidResponse("brak tokenu portalu")
        }
        let expiresIn = json["expires_in"].double ?? 86400
        return Tokens(accessToken: access, refreshToken: refresh, expiry: Date().addingTimeInterval(expiresIn))
    }

    public static func portalAccounts(portalToken: String, http: HTTPClient) async throws -> [PortalSynergiaAccount] {
        let json = try await portalGet(LibrusConstants.portalAccountsPath, portalToken: portalToken, http: http)
        return try json["accounts"].array.compactMap { account in
            switch account["state"].string {
            case "requiring_an_action": throw LibrusError.portalAccountDisconnected
            case "need-activation": throw LibrusError.portalAccountNotActivated
            default: break
            }
            guard let id = account["id"].int,
                  let login = account["login"].string,
                  let token = account["accessToken"].string else { return nil }
            return PortalSynergiaAccount(
                id: id,
                login: login,
                accessToken: token,
                studentName: (account["studentName"].string ?? login).fixedName,
                isParent: account["group"].string == "parent"
            )
        }
    }

    /// Fresh Synergia API token for one account (valid ~6 h).
    public static func portalFreshAccountToken(login: String, portalToken: String, http: HTTPClient) async throws -> TimedTokenValue {
        let json = try await portalGet(LibrusConstants.portalFreshAccountPath + login, portalToken: portalToken, http: http)
        guard let token = json["accessToken"].string else {
            throw LibrusError.invalidResponse("brak tokenu Synergii")
        }
        return TimedTokenValue(value: token, expiry: Date().addingTimeInterval(6 * 3600))
    }

    private static func portalGet(_ path: String, portalToken: String, http: HTTPClient) async throws -> JSON {
        let url = URL(string: LibrusConstants.portalAPIURL + path)!
        let response = try await http.send(url, headers: ["Authorization": "Bearer \(portalToken)"])
        let json = try response.json()
        if response.status != 200 {
            let reason = json["reason"].string ?? json["message"].string ?? json["hint"].string ?? json["Code"].string
            switch reason {
            case "requires_an_action": throw LibrusError.portalAccountDisconnected
            case "Access token is invalid": throw LibrusError.portalAccessDenied
            case "ApiDisabled": throw LibrusError.portalAPIDisabled
            case "Account not found": throw LibrusError.api(code: "AccountNotFound", message: "Nie znaleziono konta Synergia")
            case "Unable to refresh the account": throw LibrusError.maintenance
            default:
                if json["hint"].string == "Error while decoding to JSON" { throw LibrusError.portalAccessDenied }
                throw LibrusError.api(code: reason ?? "HTTP \(response.status)", message: nil)
            }
        }
        return json
    }
}

public struct TimedTokenValue: Sendable {
    public let value: String
    public let expiry: Date
}
