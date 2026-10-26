import Foundation

/// Plain, cacheable models shown by the app. Dates of school days are `Day` ("yyyy-MM-dd")
/// so they don't shift with time zones.
public struct Day: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let string: String

    public init?(_ string: String?) {
        guard let s = string?.prefix(10), s.count == 10, Day.parser.date(from: String(s)) != nil else { return nil }
        self.string = String(s)
    }

    public init(date: Date) {
        string = Day.parser.string(from: date)
    }

    public var date: Date { Day.parser.date(from: string) ?? Date() }
    public var description: String { string }
    public static func < (a: Day, b: Day) -> Bool { a.string < b.string }
    public static var today: Day { Day(date: Date()) }

    public func adding(days: Int) -> Day {
        Day(date: Day.calendar.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Week shown by default: the current one, or the coming one on weekends (like Android).
    public static var defaultTimetableWeek: Day {
        let weekday = calendar.component(.weekday, from: Date())
        return weekday == 7 || weekday == 1 ? today.weekStart.adding(days: 7) : today.weekStart
    }

    /// Monday of this day's week.
    public var weekStart: Day {
        let weekday = Day.calendar.component(.weekday, from: date) // 1 = Sunday
        return adding(days: -((weekday + 5) % 7))
    }

    public static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Warsaw")!
        c.locale = Locale(identifier: "pl_PL")
        c.firstWeekday = 2
        return c
    }()

    static let parser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let dateTimeParser: DateFormatter = {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func parseDateTime(_ s: String?) -> Date? {
        guard let s else { return nil }
        return dateTimeParser.date(from: String(s.prefix(19))) ?? parser.date(from: String(s.prefix(10)))
    }
}

public struct Subject: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let short: String
}

public struct Teacher: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let firstName: String
    public let lastName: String
    public var fullName: String { "\(firstName) \(lastName)".trimmingCharacters(in: .whitespaces) }
}

public enum GradeKind: String, Codable, Sendable, CaseIterable {
    case normal
    case semesterProposed
    case semesterFinal
    case yearProposed
    case yearFinal

    public var label: String {
        switch self {
        case .normal: return "Ocena"
        case .semesterProposed: return "Przewidywana śródroczna"
        case .semesterFinal: return "Śródroczna"
        case .yearProposed: return "Przewidywana roczna"
        case .yearFinal: return "Roczna"
        }
    }
}

public struct Grade: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let kind: GradeKind
    public let value: Double?
    public var weight: Double
    public let category: String
    public let colorHex: String?
    public let comment: String?
    public let semester: Int
    public let teacherName: String?
    public let subjectID: Int
    public let addedDate: Date?
    public let isImprovement: Bool
    /// Set on a grade that was later improved — the improvement grade's id.
    public var improvedByID: Int?

    public var countsToAverage: Bool { kind == .normal && weight > 0 && value != nil }
}

public enum LessonKind: String, Codable, Sendable {
    case normal, cancelled, change, shiftedSource, shiftedTarget
}

public struct Lesson: Codable, Hashable, Identifiable, Sendable {
    public var id: String { "\(day)-\(number)-\(kind.rawValue)-\(subject ?? "")" }
    public let day: Day
    public let number: Int
    public let start: String
    public let end: String
    public let kind: LessonKind
    public let subject: String?
    public let teacher: String?
    public let classroom: String?
    public let oldSubject: String?
    public let oldTeacher: String?
    /// For shifted lessons: where it moves to / comes from.
    public let otherDay: Day?
    public let otherNumber: Int?
}

public struct TimetableDay: Codable, Hashable, Sendable {
    public let day: Day
    public let lessons: [Lesson]
}

public struct AgendaEvent: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let day: Day
    public let time: String?
    public let lessonNumber: Int?
    public let topic: String
    public let category: String
    public let colorHex: String?
    public let subject: String?
    public let teacher: String?
    public let addedDate: Date?
}

public enum AttendanceBase: String, Codable, Sendable {
    case present, presentCustom, absent, absentExcused, belated, released, unknown

    public var isAbsence: Bool { self == .absent || self == .absentExcused }
}

public struct AttendanceEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let day: Day
    public let lessonNumber: Int
    public let typeName: String
    public let typeShort: String
    public let base: AttendanceBase
    public let colorHex: String?
    public let subject: String?
    public let teacher: String?
    public let semester: Int
}

public enum NoticeKind: String, Codable, Sendable { case positive, negative, neutral }

public struct Notice: Codable, Hashable, Identifiable, Sendable {
    public let id: Int
    public let day: Day
    public let kind: NoticeKind
    public let category: String
    public let text: String
    public let teacher: String?
}

public struct Announcement: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let subject: String
    public let text: String
    public let startDay: Day?
    public let endDay: Day?
    public let author: String?
    public let read: Bool
}

public struct LuckyNumber: Codable, Hashable, Sendable {
    public let day: Day
    public let number: Int
}

/// Everything fetched for one student, cached to disk for offline use.
public struct StudentData: Codable, Sendable {
    public var fetchedAt: Date
    public var studentName: String?
    public var accountName: String?
    public var subjects: [Subject]
    public var grades: [Grade]
    public var events: [AgendaEvent]
    public var attendance: [AttendanceEntry]
    public var notices: [Notice]
    public var announcements: [Announcement]
    public var luckyNumber: LuckyNumber?
    public var timetable: [String: [TimetableDay]]
    /// Sections that failed to load (shown, but don't block the rest).
    public var warnings: [String]

    public init(fetchedAt: Date = Date(), studentName: String? = nil, accountName: String? = nil,
                subjects: [Subject] = [], grades: [Grade] = [], events: [AgendaEvent] = [],
                attendance: [AttendanceEntry] = [], notices: [Notice] = [], announcements: [Announcement] = [],
                luckyNumber: LuckyNumber? = nil, timetable: [String: [TimetableDay]] = [:], warnings: [String] = []) {
        self.fetchedAt = fetchedAt
        self.studentName = studentName
        self.accountName = accountName
        self.subjects = subjects
        self.grades = grades
        self.events = events
        self.attendance = attendance
        self.notices = notices
        self.announcements = announcements
        self.luckyNumber = luckyNumber
        self.timetable = timetable
        self.warnings = warnings
    }
}
