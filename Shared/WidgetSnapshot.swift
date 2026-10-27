import Foundation

/// What the widgets show, written by the app into the App Group container after every sync.
/// Widgets don't log in or touch the network: they only read this file. Shared by both targets.
struct WidgetSnapshot: Codable, Equatable {
    struct Lesson: Codable, Equatable, Hashable {
        var day: String
        var number: Int
        var start: String
        var end: String
        var subject: String
        var classroom: String?
        /// "odwołana", "zastępstwo"… or nil for a normal lesson.
        var status: String?
        var isCancelled: Bool
    }

    struct Event: Codable, Equatable, Hashable {
        var day: String
        var category: String
        var subject: String?
        var lessonNumber: Int?
    }

    var studentName: String
    var updatedAt: Date
    var lessons: [Lesson]
    var events: [Event]
    var luckyNumber: Int?
    var luckyDay: String?

    // MARK: Storage

    /// The App Group from the installed provisioning profile (Xcode, AltStore and SideStore may
    /// rename it), else `group.<prefix>` for bundle ids `<prefix>.app` / `<prefix>.app.widgets`.
    static let appGroup: String? = provisionedAppGroup() ?? derivedAppGroup()

    private static func derivedAppGroup() -> String? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let prefix = id.hasSuffix(".app.widgets") ? String(id.dropLast(".app.widgets".count))
            : id.hasSuffix(".app") ? String(id.dropLast(".app".count)) : id
        return "group.\(prefix)"
    }

    /// embedded.mobileprovision is a signed plist; the XML part lists the granted entitlements.
    private static func provisionedAppGroup() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.range(of: "<?xml"), let end = text.range(of: "</plist>") else { return nil }
        let xml = Data(text[start.lowerBound..<end.upperBound].utf8)
        let plist = try? PropertyListSerialization.propertyList(from: xml, format: nil) as? [String: Any]
        let entitlements = plist?["Entitlements"] as? [String: Any]
        return (entitlements?["com.apple.security.application-groups"] as? [String])?.first { !$0.contains("*") }
    }

    private static var fileURL: URL? {
        appGroup.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }?
            .appendingPathComponent("widget-snapshot.json")
    }

    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Saves (or with nil removes) the snapshot. Returns false when the App Group isn't available.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot?) -> Bool {
        guard let url = fileURL else { return false }
        guard let snapshot else {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return false }
        // Readable while the phone is locked (CarPlay), like the rest of the app's data after first unlock.
        return (try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
}

/// School days as "yyyy-MM-dd" in Polish time, and labels for the widgets.
enum WidgetDay {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        c.locale = Locale(identifier: "pl_PL")
        c.firstWeekday = 2
        return c
    }()

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let short: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "pl_PL")
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func string(_ date: Date) -> String { parser.string(from: date) }

    static func adding(_ days: Int, to day: String) -> String {
        guard let date = parser.date(from: day), let next = calendar.date(byAdding: .day, value: days, to: date) else { return day }
        return string(next)
    }

    /// The moment "HH:mm" happens on `day`.
    static func date(_ day: String, _ hhmm: String) -> Date? {
        guard let base = parser.date(from: day) else { return nil }
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base)
    }

    static func startOfNextDay(after date: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date.addingTimeInterval(86_400)
    }

    /// "Dziś", "Jutro" or "śr 4 lis".
    static func label(_ day: String, now: Date = Date()) -> String {
        let today = string(now)
        if day == today { return "Dziś" }
        if day == adding(1, to: today) { return "Jutro" }
        guard let date = parser.date(from: day) else { return day }
        return short.string(from: date)
    }
}

extension WidgetSnapshot {
    /// The lesson running at `now`, else the next one today, else the first one of the next school day.
    func nextLesson(at now: Date) -> (lesson: Lesson, isNow: Bool)? {
        let upcoming = lessons
            .compactMap { lesson -> (Lesson, Date, Date)? in
                guard let start = WidgetDay.date(lesson.day, lesson.start), let end = WidgetDay.date(lesson.day, lesson.end) else { return nil }
                return (lesson, start, end)
            }
            .filter { $0.2 > now }
            .sorted { $0.1 < $1.1 }
        guard let first = upcoming.first(where: { !$0.0.isCancelled }) ?? upcoming.first else { return nil }
        return (first.0, first.1 <= now)
    }

    /// Lesson start/end times from `now` on, for widget timeline entries.
    func lessonBoundaries(after now: Date, limit: Int = 40) -> [Date] {
        let times = lessons.flatMap { lesson in
            [WidgetDay.date(lesson.day, lesson.start), WidgetDay.date(lesson.day, lesson.end)].compactMap { $0 }
        }
        return Array(Set(times.filter { $0 > now })).sorted().prefix(limit).map { $0 }
    }

    func nextEvent(at now: Date) -> (event: Event, more: Int)? {
        let today = WidgetDay.string(now)
        let coming = events.filter { $0.day >= today }.sorted { $0.day < $1.day }
        guard let first = coming.first else { return nil }
        let weekEnd = WidgetDay.adding(7, to: today)
        return (first, coming.dropFirst().filter { $0.day <= weekEnd }.count)
    }

    /// The lucky number while it still applies (today or later).
    func lucky(at now: Date) -> (number: Int, day: String)? {
        guard let number = luckyNumber, let day = luckyDay, day >= WidgetDay.string(now) else { return nil }
        return (number, day)
    }
}
