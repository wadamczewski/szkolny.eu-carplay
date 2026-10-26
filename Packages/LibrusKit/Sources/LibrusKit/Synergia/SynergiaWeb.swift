import Foundation
import SwiftSoup

public enum MessageFolder: String, Codable, Sendable {
    case inbox = "5"
    case sent = "6"
}

public struct MessageSummary: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let folder: MessageFolder
    /// Sender (inbox) or recipient (sent).
    public let correspondent: String
    public let subject: String
    public let date: String
    public let unread: Bool
    public let hasAttachments: Bool
}

public struct MessageAttachment: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let messageID: String
    public let filename: String

    public init(id: String, messageID: String, filename: String) {
        self.id = id
        self.messageID = messageID
        self.filename = filename
    }
}

public struct MessageDetail: Codable, Hashable, Sendable {
    public let id: String
    public let sender: String
    public let subject: String
    public let date: String
    /// HTML fragment of the message body.
    public let bodyHTML: String
    public let attachments: [MessageAttachment]
}

public struct RecipientGroup: Hashable, Identifiable, Sendable {
    public var id: String { value }
    public let value: String
    public let name: String
}

public struct Recipient: Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// The Synergia website session (cookie `DZIENNIKSID`), opened with an `AutoLoginToken`
/// from the API — port of `LibrusLoginSynergia`. Messages are scraped from the same pages
/// as `LibrusSynergiaGetMessages` and the maintained librus-apix project.
public actor SynergiaWeb {
    private let api: LibrusAPI
    let http = HTTPClient()
    private var sessionExpiry: Date?
    private var loginTask: Task<Void, Error>?

    public init(api: LibrusAPI) {
        self.api = api
    }

    // MARK: Session

    public func ensureSession(force: Bool = false) async throws {
        if !force, let sessionExpiry, sessionExpiry.timeIntervalSinceNow > 60 { return }
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
        guard http.cookie(named: "DZIENNIKSID", domain: "librus.pl") != nil else {
            throw LibrusError.synergiaSession("brak ciasteczka sesji")
        }
        sessionExpiry = Date().addingTimeInterval(40 * 60)
    }

    /// Cookies for embedding Synergia pages in a web view (fallback UI).
    public func sessionCookies() async throws -> [HTTPCookie] {
        try await ensureSession()
        return http.cookieStorage.cookies ?? []
    }

    private func page(_ path: String, form: [(String, String)]? = nil) async throws -> Document {
        try await ensureSession()
        var doc = try await fetch(path, form: form)
        if SynergiaParser.isLoggedOut(doc) {
            try await ensureSession(force: true)
            doc = try await fetch(path, form: form)
            if SynergiaParser.isLoggedOut(doc) { throw LibrusError.synergiaSession("sesja wygasła") }
        }
        return doc
    }

    private func fetch(_ path: String, form: [(String, String)]?) async throws -> Document {
        let url = URL(string: "\(LibrusConstants.synergiaURL)/\(path)")!
        let response = try await http.send(url, method: form == nil ? "GET" : "POST",
                                           form: form, userAgent: LibrusConstants.webUserAgent)
        if response.text.contains("Przerwa techniczna") { throw LibrusError.maintenance }
        do { return try SwiftSoup.parse(response.text, url.absoluteString) } catch {
            throw LibrusError.parse("HTML \(path)")
        }
    }

    // MARK: Messages

    public func messages(_ folder: MessageFolder, page: Int = 0) async throws -> [MessageSummary] {
        let doc = try await self.page("wiadomosci/1/\(folder.rawValue)", form: [
            ("numer_strony105", String(page)),
            ("porcjowanie_pojemnik105", "105"),
        ])
        return try SynergiaParser.messageList(doc, folder: folder)
    }

    public func message(id: String, folder: MessageFolder) async throws -> MessageDetail {
        let doc = try await page("wiadomosci/1/\(folder.rawValue)/\(id)/f0")
        return try SynergiaParser.messageDetail(doc, id: id)
    }

    public func recipientGroups() async throws -> [RecipientGroup] {
        try SynergiaParser.recipientGroups(try await page("wiadomosci/2/6"))
    }

    public func recipients(group: String) async throws -> [Recipient] {
        let doc = try await page("getRecipients", form: [
            ("typAdresata", group),
            ("poprzednia", "5"),
            ("tabZaznaczonych", ""),
            ("czyWirtualneKlasy", "False"),
            ("idGrupy", "0"),
        ])
        return try SynergiaParser.recipients(doc)
    }

    public func send(subject: String, body: String, recipientIDs: [String]) async throws {
        var form: [(String, String)] = [
            ("filtrUzytkownikow", "0"),
            ("idPojemnika", ""),
        ]
        form += recipientIDs.map { ("DoKogo", $0) }
        form += [
            ("Rodzaj", "0"),
            ("temat", subject),
            ("tresc", body),
            ("poprzednia", "5"),
            ("fileStorageIdentifier", ""),
            ("wyslij", "Wyślij"),
        ]
        let doc = try await page("wiadomosci/1/6", form: form)
        let result = try doc.select("div.container-background > p").first()?.text() ?? ""
        if result.lowercased().contains("nie zosta") {
            throw LibrusError.messageSendFailed(result)
        }
        if result.isEmpty {
            // Don't claim failure: the message may have gone out. Avoid duplicate sends.
            throw LibrusError.messageSendUnconfirmed
        }
    }

    // MARK: Attachments

    /// Downloads an attachment to a temporary file. Port of `LibrusSynergiaGetAttachment`
    /// + `LibrusSandboxDownloadAttachment` (single-use key polling).
    public func download(_ attachment: MessageAttachment) async throws -> URL {
        try await ensureSession()
        let url = URL(string: "\(LibrusConstants.synergiaURL)/wiadomosci/pobierz_zalacznik/\(attachment.messageID)/\(attachment.id)")!
        let redirect = try await http.send(url, userAgent: LibrusConstants.webUserAgent, followRedirects: false)
        guard let location = redirect.location else {
            throw LibrusError.parse("brak przekierowania do załącznika")
        }
        if location.contains("CSDownloadFailed") { throw LibrusError.parse("Librus nie znalazł załącznika") }

        let file: HTTPClient.Response
        if let key = location.firstMatch(of: #/singleUseKey=([0-9A-Za-z_]+)/#)?.1 {
            try await waitForSandbox(key: String(key))
            file = try await http.send(URL(string: "\(LibrusConstants.sandboxURL)CSDownload&singleUseKey=\(key)")!,
                                       method: "POST", userAgent: LibrusConstants.webUserAgent)
        } else {
            file = try await http.send(URL(string: location + "/get")!, userAgent: LibrusConstants.webUserAgent)
        }
        guard file.status == 200 else { throw LibrusError.invalidResponse("HTTP \(file.status) przy pobieraniu") }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("attachments/\(attachment.messageID)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeName = attachment.filename.replacingOccurrences(of: "/", with: "_")
        let target = dir.appendingPathComponent(safeName.isEmpty ? "zalacznik" : safeName)
        try file.data.write(to: target, options: .atomic)
        return target
    }

    private func waitForSandbox(key: String) async throws {
        for _ in 0..<8 {
            let response = try await http.send(URL(string: "\(LibrusConstants.sandboxURL)CSCheckKey")!,
                                               method: "POST", form: [("singleUseKey", key)],
                                               userAgent: LibrusConstants.webUserAgent)
            switch try response.json()["status"].string {
            case "ready": return
            case "not_downloaded_yet": try await Task.sleep(nanoseconds: 2_000_000_000)
            case let status: throw LibrusError.invalidResponse("sandbox: \(status ?? "?")")
            }
        }
        throw LibrusError.network("załącznik nie był gotowy na czas")
    }
}

/// HTML parsing, separated for fixture checks.
public enum SynergiaParser {
    static func isLoggedOut(_ doc: Document) -> Bool {
        if let h2 = try? doc.select("h2.inside").first(), (try? h2.text())?.contains("Brak dostępu") == true { return true }
        let html = (try? doc.outerHtml()) ?? ""
        return html.contains("stop.png") || html.contains("loguj/portalRodzina") && !html.contains("jesteś zalogowany")
    }

    public static func messageList(_ html: String, folder: MessageFolder) throws -> [MessageSummary] {
        try messageList(SwiftSoup.parse(html), folder: folder)
    }

    static func messageList(_ doc: Document, folder: MessageFolder) throws -> [MessageSummary] {
        guard let table = try doc.select("table.decorated.stretch").first() else {
            throw LibrusError.parse("lista wiadomości")
        }
        var result: [MessageSummary] = []
        for row in try table.select("tbody > tr") {
            let cells = try row.select("td").array()
            guard cells.count >= 6 else { continue }
            let link = try row.select("a[href*=/wiadomosci/]").first()?.attr("href") ?? ""
            let parts = link.split(separator: "/").map(String.init)
            // /wiadomosci/1/5/12345/f0
            guard let idx = parts.firstIndex(of: "wiadomosci"), parts.count > idx + 3 else { continue }
            let id = parts[idx + 3]
            let title = cells[3]
            let unread: Bool
            switch folder {
            case .inbox:
                let style = (try title.attr("style")) + (try cells[2].attr("style"))
                unread = style.replacingOccurrences(of: " ", with: "").contains("font-weight:bold")
            case .sent:
                let readFlag = cells.count >= 7 ? try cells[5].text() : ""
                unread = readFlag.trimmingCharacters(in: .whitespaces) == "NIE"
            }
            result.append(MessageSummary(
                id: id,
                folder: folder,
                correspondent: clean(try cells[2].text()),
                subject: clean(try title.text()),
                date: clean(try cells[4].text()),
                unread: unread,
                hasAttachments: !(try cells[1].select("img").isEmpty())
            ))
        }
        return result
    }

    public static func messageDetail(_ html: String, id: String) throws -> MessageDetail {
        try messageDetail(SwiftSoup.parse(html), id: id)
    }

    static func messageDetail(_ doc: Document, id: String) throws -> MessageDetail {
        guard let content = try doc.select("div.container-message-content").first() else {
            throw LibrusError.parse("treść wiadomości")
        }
        // Header table: rows "Nadawca", "Temat", "Wysłano" with values in td.left.
        var header: [String] = []
        if let table = try doc.select("table.stretch").first(where: { (try? $0.className()) == "stretch" })
            ?? doc.select("table.stretch").first() {
            for row in try table.select("tr").prefix(3) {
                header.append(clean(try row.select("td.left").first()?.text() ?? ""))
            }
        }
        var attachments: [MessageAttachment] = []
        for img in try doc.select("img[onclick*=pobierz_zalacznik]") {
            let onclick = try img.attr("onclick").replacingOccurrences(of: "\\/", with: "/")
            guard let match = onclick.firstMatch(of: #/pobierz_zalacznik\/(\d+)\/(\d+)/#) else { continue }
            let row = img.parents().first { $0.tagName() == "tr" }
            let name = clean(try row?.select("td").first()?.text() ?? "załącznik")
            attachments.append(MessageAttachment(id: String(match.2), messageID: String(match.1), filename: name))
        }
        return MessageDetail(
            id: id,
            sender: header[safe: 0] ?? "",
            subject: header[safe: 1] ?? "",
            date: header[safe: 2] ?? "",
            bodyHTML: try content.html(),
            attachments: attachments
        )
    }

    public static func recipientGroups(_ html: String) throws -> [RecipientGroup] {
        try recipientGroups(SwiftSoup.parse(html))
    }

    static func recipientGroups(_ doc: Document) throws -> [RecipientGroup] {
        try doc.select("table.message-recipients > tbody > tr").compactMap { row in
            guard let radio = try row.select("input.recipiantTypeRadio").first() else { return nil }
            let value = try radio.attr("value")
            let label = clean(try row.select("label").first()?.text() ?? row.text())
            return RecipientGroup(value: value, name: label.isEmpty ? value : label)
        }
    }

    public static func recipients(_ html: String) throws -> [Recipient] {
        try recipients(SwiftSoup.parse(html))
    }

    static func recipients(_ doc: Document) throws -> [Recipient] {
        try doc.select("label").compactMap { label in
            let id = try label.attr("for").split(separator: "_").last.map(String.init) ?? ""
            let name = clean(try label.text())
            return id.isEmpty || name.isEmpty ? nil : Recipient(id: id, name: name)
        }
    }

    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{a0}", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
