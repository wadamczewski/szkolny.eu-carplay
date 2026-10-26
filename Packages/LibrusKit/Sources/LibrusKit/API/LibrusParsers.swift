import Foundation

/// Pure JSON → model mapping, ported from the `LibrusApi*.kt` endpoint classes.
/// Kept free of networking so it can be checked against fixtures.
public enum LibrusParsers {
    public struct Dictionaries: Sendable {
        public var subjects: [Int: Subject] = [:]
        public var teachers: [Int: Teacher] = [:]
        public var classrooms: [Int: String] = [:]
        public var gradeCategories: [Int: GradeCategory] = [:]
        public var gradeComments: [Int: String] = [:]
        public var eventCategories: [Int: (name: String, colorHex: String?)] = [:]
        public var attendanceTypes: [Int: AttendanceType] = [:]
        public var noticeCategories: [Int: String] = [:]
        /// Lessons/Id → (subject, teacher), used by attendance entries.
        public var lessons: [Int: (subjectID: Int?, teacherID: Int?)] = [:]

        public init() {}

        func subjectName(_ id: Int?) -> String? { id.flatMap { subjects[$0]?.name } }
        func teacherName(_ id: Int?) -> String? { id.flatMap { teachers[$0]?.fullName } }
    }

    public struct GradeCategory: Sendable {
        public let name: String
        public let weight: Double
        public let colorHex: String?
    }

    public struct AttendanceType: Sendable {
        public let name: String
        public let short: String
        public let base: AttendanceBase
        public let colorHex: String?
    }

    // MARK: Dictionaries

    public static func subjects(_ json: JSON) -> [Int: Subject] {
        var result: [Int: Subject] = [:]
        for s in json["Subjects"].array {
            guard let id = s["Id"].int else { continue }
            result[id] = Subject(id: id, name: s["Name"].string ?? "", short: s["Short"].string ?? "")
        }
        result[1] = result[1] ?? Subject(id: 1, name: "Zachowanie", short: "zach")
        return result
    }

    public static func teachers(_ json: JSON) -> [Int: Teacher] {
        var result: [Int: Teacher] = [:]
        for u in json["Users"].array {
            guard let id = u["Id"].int else { continue }
            result[id] = Teacher(id: id,
                                 firstName: (u["FirstName"].string ?? "").fixedName,
                                 lastName: (u["LastName"].string ?? "").fixedName)
        }
        return result
    }

    public static func classrooms(_ json: JSON) -> [Int: String] {
        var result: [Int: String] = [:]
        for c in json["Classrooms"].array {
            guard let id = c["Id"].int else { continue }
            let name = c["Name"].string ?? ""
            let symbol = c["Symbol"].string ?? ""
            result[id] = (symbol.isEmpty || name.lowercased().contains(symbol.lowercased())) ? name : "\(symbol) \(name)"
        }
        return result
    }

    public static func gradeCategories(_ json: JSON) -> [Int: GradeCategory] {
        var result: [Int: GradeCategory] = [:]
        for c in json["Categories"].array {
            guard let id = c["Id"].int else { continue }
            let weight = c["CountToTheAverage"].bool == true ? (c["Weight"].double ?? 0) : 0
            result[id] = GradeCategory(
                name: (c["Name"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                weight: weight,
                colorHex: librusColor(c["Color"].refID)
            )
        }
        return result
    }

    public static func gradeComments(_ json: JSON) -> [Int: String] {
        var result: [Int: String] = [:]
        for c in json["Comments"].array {
            guard let id = c["Id"].int, let text = c["Text"].string else { continue }
            result[id] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    public static func eventCategories(_ json: JSON) -> [Int: (name: String, colorHex: String?)] {
        var result: [Int: (name: String, colorHex: String?)] = [:]
        for c in json["Categories"].array {
            guard let id = c["Id"].int else { continue }
            result[id] = (c["Name"].string ?? "", librusColor(c["Color"].refID))
        }
        return result
    }

    public static func attendanceTypes(_ json: JSON) -> [Int: AttendanceType] {
        var result: [Int: AttendanceType] = [:]
        for t in json["Types"].array {
            guard let id = t["Id"].int else { continue }
            let standard = t["Standard"].bool ?? false
            let base: AttendanceBase
            switch t["StandardType"].refID ?? id {
            case 1: base = .absent
            case 2: base = .belated
            case 3: base = .absentExcused
            case 4: base = .released
            default: base = standard ? .present : .presentCustom
            }
            result[id] = AttendanceType(
                name: t["Name"].string ?? "",
                short: t["Short"].string ?? "?",
                base: base,
                colorHex: t["ColorRGB"].string.map { "#\($0)" }
            )
        }
        return result
    }

    public static func noticeCategories(_ json: JSON) -> [Int: String] {
        var result: [Int: String] = [:]
        for c in json["Categories"].array {
            guard let id = c["Id"].int else { continue }
            result[id] = c["CategoryName"].string ?? ""
        }
        return result
    }

    public static func lessons(_ json: JSON) -> [Int: (subjectID: Int?, teacherID: Int?)] {
        var result: [Int: (subjectID: Int?, teacherID: Int?)] = [:]
        for l in json["Lessons"].array {
            guard let id = l["Id"].int else { continue }
            result[id] = (l["Subject"].refID, l["Teacher"].refID)
        }
        return result
    }

    // MARK: Data

    public static func grades(_ json: JSON, dict: Dictionaries) -> [Grade] {
        var grades: [Grade] = []
        var improvements: [Int: Int] = [:] // old grade id → new grade id
        for g in json["Grades"].array {
            guard let id = g["Id"].int, let semester = g["Semester"].int else { continue }
            let name = g["Grade"].string ?? ""
            let category = g["Category"].refID.flatMap { dict.gradeCategories[$0] }
            let kind: GradeKind
            if g["IsConstituent"].bool == true { kind = .normal }
            else if g["IsSemester"].bool == true { kind = .semesterFinal }
            else if g["IsSemesterProposition"].bool == true { kind = .semesterProposed }
            else if g["IsFinal"].bool == true { kind = .yearFinal }
            else if g["IsFinalProposition"].bool == true { kind = .yearProposed }
            else { kind = .normal }
            let value = GradeMath.value(of: name)
            let zeroWeight = ["-", "+", "np", "bz"].contains(name.lowercased())
            let comment = g["Comments"].array.first?.refID.flatMap { dict.gradeComments[$0] }
            if let oldID = g["Improvement"].refID { improvements[oldID] = id }
            grades.append(Grade(
                id: id, name: name, kind: kind, value: value,
                weight: zeroWeight ? 0 : (category?.weight ?? 0),
                category: category?.name ?? "",
                colorHex: category?.colorHex,
                comment: comment,
                semester: semester,
                teacherName: dict.teacherName(g["AddedBy"].refID),
                subjectID: g["Subject"].refID ?? -1,
                addedDate: Day.parseDateTime(g["AddDate"].string),
                isImprovement: !g["Improvement"].isNull,
                improvedByID: nil
            ))
        }
        return grades.map { grade in
            var grade = grade
            grade.improvedByID = improvements[grade.id]
            if grade.improvedByID != nil, grade.name.lowercased() == "nb" {
                grade.weight = 0
            }
            return grade
        }
    }

    public static func timetable(_ json: JSON, dict: Dictionaries) -> [TimetableDay] {
        guard let days = json["Timetable"].object else { return [] }
        return days.compactMap { dateString, dayJSON -> TimetableDay? in
            guard let day = Day(dateString) else { return nil }
            let lessons = dayJSON.array.flatMap { $0.array }.compactMap { lesson(day: day, $0, dict: dict) }
            return TimetableDay(day: day, lessons: lessons.sorted { ($0.number, $0.start) < ($1.number, $1.start) })
        }.sorted { $0.day < $1.day }
    }

    static func lesson(day: Day, _ l: JSON, dict: Dictionaries) -> Lesson? {
        guard let number = l["LessonNo"].int,
              let start = l["HourFrom"].string, let end = l["HourTo"].string else { return nil }
        let isSubstitution = l["IsSubstitutionClass"].bool ?? false
        let isCancelled = l["IsCanceled"].bool ?? false
        let subject = l["Subject"]["Name"].string ?? dict.subjectName(l["Subject"].refID)
        let teacher = dict.teacherName(l["Teacher"].refID)
            ?? [l["Teacher"]["FirstName"].string, l["Teacher"]["LastName"].string].compactMap { $0 }.joined(separator: " ").nilIfEmpty
        let classroom = l["Classroom"].refID.flatMap { dict.classrooms[$0] }

        if isSubstitution && isCancelled {
            // Lesson moved away from here.
            return Lesson(day: day, number: number, start: start, end: end, kind: .shiftedSource,
                          subject: subject, teacher: teacher, classroom: classroom,
                          oldSubject: nil, oldTeacher: nil,
                          otherDay: Day(l["NewDate"].string), otherNumber: l["NewLessonNo"].int)
        }
        if isSubstitution {
            let orgDay = Day(l["OrgDate"].string)
            let orgNumber = l["OrgLessonNo"].int
            let moved = orgDay != nil && (orgDay != day || orgNumber != number)
            return Lesson(day: day, number: number, start: start, end: end,
                          kind: moved ? .shiftedTarget : .change,
                          subject: subject, teacher: teacher, classroom: classroom,
                          oldSubject: dict.subjectName(l["OrgSubject"].refID),
                          oldTeacher: dict.teacherName(l["OrgTeacher"].refID),
                          otherDay: moved ? orgDay : nil, otherNumber: moved ? orgNumber : nil)
        }
        return Lesson(day: day, number: number, start: start, end: end,
                      kind: isCancelled ? .cancelled : .normal,
                      subject: subject, teacher: teacher, classroom: classroom,
                      oldSubject: nil, oldTeacher: nil, otherDay: nil, otherNumber: nil)
    }

    public static func events(_ json: JSON, dict: Dictionaries) -> [AgendaEvent] {
        json["HomeWorks"].array.compactMap { e in
            guard let id = e["Id"].int, let day = Day(e["Date"].string) else { return nil }
            var topic = (e["Content"].string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let online = e["onlineLessonUrl"]
            if let url = online["url"].string {
                topic += "\n\n" + (online["text"].string.map { "\($0) - " } ?? "") + url
            }
            let category = e["Category"].refID.flatMap { dict.eventCategories[$0] }
            return AgendaEvent(
                id: id, day: day,
                time: e["TimeFrom"].string.map { String($0.prefix(5)) },
                lessonNumber: e["LessonNo"].int,
                topic: topic,
                category: category?.name ?? "Wydarzenie",
                colorHex: category?.colorHex,
                subject: dict.subjectName(e["Subject"].refID),
                teacher: dict.teacherName(e["CreatedBy"].refID),
                addedDate: Day.parseDateTime(e["AddDate"].string)
            )
        }.sorted { $0.day < $1.day }
    }

    public static func attendance(_ json: JSON, dict: Dictionaries) -> [AttendanceEntry] {
        json["Attendances"].array.compactMap { a in
            guard let rawID = a["Id"].string,
                  let number = a["LessonNo"].int,
                  let day = Day(a["Date"].string),
                  let semester = a["Semester"].int,
                  let typeID = a["Type"].refID else { return nil }
            let type = dict.attendanceTypes[typeID]
            let lesson = a["Lesson"].refID.flatMap { dict.lessons[$0] }
            return AttendanceEntry(
                id: rawID, day: day, lessonNumber: number,
                typeName: type?.name ?? "nieznany rodzaj",
                typeShort: type?.short ?? "?",
                base: type?.base ?? .unknown,
                colorHex: type?.colorHex,
                subject: dict.subjectName(lesson?.subjectID),
                teacher: dict.teacherName(a["AddedBy"].refID ?? lesson?.teacherID),
                semester: semester
            )
        }.sorted { ($0.day, $0.lessonNumber) > ($1.day, $1.lessonNumber) }
    }

    public static func notices(_ json: JSON, dict: Dictionaries) -> [Notice] {
        json["Notes"].array.compactMap { n in
            guard let id = n["Id"].int, let day = Day(n["Date"].string) else { return nil }
            let kind: NoticeKind
            switch n["Positive"].int {
            case 0: kind = .negative
            case 1: kind = .positive
            default: kind = .neutral
            }
            return Notice(id: id, day: day, kind: kind,
                          category: n["Category"].refID.flatMap { dict.noticeCategories[$0] } ?? "",
                          text: n["Text"].string ?? "",
                          teacher: dict.teacherName(n["Teacher"].refID))
        }.sorted { $0.day > $1.day }
    }

    public static func announcements(_ json: JSON, dict: Dictionaries) -> [Announcement] {
        json["SchoolNotices"].array.compactMap { a in
            guard let id = a["Id"].string else { return nil }
            return Announcement(
                id: id,
                subject: a["Subject"].string ?? "",
                text: a["Content"].string ?? "",
                startDay: Day(a["StartDate"].string),
                endDay: Day(a["EndDate"].string),
                author: dict.teacherName(a["AddedBy"].refID),
                read: a["WasRead"].bool ?? false
            )
        }.sorted { ($0.startDay?.string ?? "") > ($1.startDay?.string ?? "") }
    }

    public static func luckyNumber(_ json: JSON) -> LuckyNumber? {
        let l = json["LuckyNumber"]
        guard let number = l["LuckyNumber"].int, let day = Day(l["LuckyNumberDay"].string) else { return nil }
        return LuckyNumber(day: day, number: number)
    }

    /// Librus color ids → hex (table from `DataLibrus.getColor`).
    public static func librusColor(_ id: Int?) -> String? {
        let table: [Int: String] = [
            1: "#F0E68C", 2: "#87CEFA", 3: "#B0C4DE", 4: "#F0F8FF", 5: "#F0FFFF", 6: "#F5F5DC",
            7: "#FFEBCD", 8: "#FFF8DC", 9: "#A9A9A9", 10: "#BDB76B", 11: "#8FBC8F", 12: "#DCDCDC",
            13: "#DAA520", 14: "#E6E6FA", 15: "#FFA07A", 16: "#32CD32", 17: "#66CDAA", 18: "#66CDAA",
            19: "#C0C0C0", 20: "#D2B48C", 21: "#3333FF", 22: "#7B68EE", 23: "#BA55D3", 24: "#FFB6C1",
            25: "#FF1493", 26: "#DC143C", 27: "#FF0000", 28: "#FF8C00", 29: "#FFD700", 30: "#ADFF2F",
            31: "#7CFC00",
        ]
        return id.flatMap { table[$0] } ?? "#2196F3"
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

public enum GradeMath {
    public static var plusValue = 0.5
    public static var minusValue = 0.25

    /// "4+" → 4.5, "3-" → 2.75, "np" → nil.
    public static func value(of grade: String) -> Double? {
        let trimmed = grade.trimmingCharacters(in: .whitespaces)
        guard let first = trimmed.first, let base = first.wholeNumberValue, (0...6).contains(base) else { return nil }
        let rest = trimmed.dropFirst()
        if rest.isEmpty { return Double(base) }
        if rest == "+" { return Double(base) + plusValue }
        if rest == "-" { return Double(base) - minusValue }
        if let decimal = Double(trimmed.replacingOccurrences(of: ",", with: ".")) { return decimal }
        return Double(base)
    }

    /// Weighted average of grades that count (normal grades with weight > 0).
    public static func average(_ grades: [Grade]) -> Double? {
        let counted = grades.filter(\.countsToAverage)
        let weights = counted.reduce(0) { $0 + $1.weight }
        guard weights > 0 else { return nil }
        return counted.reduce(0) { $0 + ($1.value ?? 0) * $1.weight } / weights
    }
}
