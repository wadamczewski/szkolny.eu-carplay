import Foundation

/// Thin URLSession wrapper. Unlike OkHttp in the Android app, URLSession follows redirects
/// by default, so callers that need the `Location` header pass `followRedirects: false`.
public final class HTTPClient: @unchecked Sendable {
    public let session: URLSession
    public let cookieStorage: HTTPCookieStorage

    /// Ephemeral sessions keep a private in-memory cookie jar, so Synergia sessions of
    /// different students don't mix.
    public init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        let storage = config.httpCookieStorage ?? HTTPCookieStorage()
        config.httpCookieStorage = storage
        cookieStorage = storage
        session = URLSession(configuration: config)
    }

    public struct Response {
        public let data: Data
        public let http: HTTPURLResponse

        public var status: Int { http.statusCode }
        public var location: String? { http.value(forHTTPHeaderField: "Location") }
        public var text: String { HTTPClient.decodeText(data, response: http) }
        public func json() throws -> JSON {
            do { return try JSON(data: data) } catch {
                throw LibrusError.invalidResponse("HTTP \(status), \(text.prefix(200))")
            }
        }
    }

    public func send(
        _ url: URL,
        method: String = "GET",
        headers: [String: String] = [:],
        form: [(String, String)]? = nil,
        body: Data? = nil,
        userAgent: String = LibrusConstants.userAgent,
        followRedirects: Bool = true
    ) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let form {
            request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
            request.httpBody = HTTPClient.formEncode(form).data(using: .utf8)
        } else if let body {
            request.httpBody = body
        }
        do {
            let delegate: URLSessionTaskDelegate? = followRedirects ? nil : NoRedirectDelegate()
            let (data, response) = try await session.data(for: request, delegate: delegate)
            guard let http = response as? HTTPURLResponse else {
                throw LibrusError.invalidResponse("brak odpowiedzi HTTP")
            }
            return Response(data: data, http: http)
        } catch let error as LibrusError {
            throw error
        } catch {
            throw LibrusError.network(error.localizedDescription)
        }
    }

    public func cookie(named name: String, domain: String) -> String? {
        cookieStorage.cookies?.first { $0.name == name && $0.domain.hasSuffix(domain) }?.value
    }

    public func clearCookies() {
        cookieStorage.cookies?.forEach { cookieStorage.deleteCookie($0) }
    }

    /// application/x-www-form-urlencoded with UTF-8 percent-encoding (ASCII-only safe set,
    /// so Polish characters become e.g. `%C5%9B`).
    public static func formEncode(_ pairs: [(String, String)]) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._*")
        func encode(_ s: String) -> String {
            s.split(separator: " ", omittingEmptySubsequences: false)
                .map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
                .joined(separator: "+")
        }
        return pairs.map { "\(encode($0))=\(encode($1))" }.joined(separator: "&")
    }

    static func decodeText(_ data: Data, response: HTTPURLResponse?) -> String {
        let contentType = response?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("iso-8859-2") || contentType.contains("windows-1250") {
            if let s = String(data: data, encoding: .windowsCP1250) { return s }
        }
        return String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1250)
            ?? String(decoding: data, as: UTF8.self)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
