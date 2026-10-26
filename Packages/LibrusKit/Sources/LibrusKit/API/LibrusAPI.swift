import Foundation

/// `https://api.librus.pl/2.0` client. Port of `LibrusApi.apiGet` incl. its error mapping.
public struct LibrusAPI: Sendable {
    let http: HTTPClient
    /// Returns a bearer token; `true` asks for a forced refresh.
    let token: @Sendable (_ forceRefresh: Bool) async throws -> String

    public init(http: HTTPClient, token: @escaping @Sendable (_ forceRefresh: Bool) async throws -> String) {
        self.http = http
        self.token = token
    }

    public func get(_ endpoint: String, method: String = "GET") async throws -> JSON {
        do {
            return try await request(endpoint, method: method, forceRefresh: false)
        } catch LibrusError.tokenExpired {
            return try await request(endpoint, method: method, forceRefresh: true)
        }
    }

    private func request(_ endpoint: String, method: String, forceRefresh: Bool) async throws -> JSON {
        let bearer = try await token(forceRefresh)
        guard let url = URL(string: "\(LibrusConstants.apiURL)/\(endpoint)") else {
            throw LibrusError.invalidResponse("zły adres \(endpoint)")
        }
        let response = try await http.send(url, method: method, headers: ["Authorization": "Bearer \(bearer)"])
        if response.status == 503 { throw LibrusError.maintenance }
        let json = (try? response.json()) ?? .null
        if response.status == 200 { return json }
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
