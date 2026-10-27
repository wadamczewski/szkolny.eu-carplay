#if DEBUG
import Foundation
import LibrusKit

/// FAKE, GENERATED DATA for screenshots and UI work — no real student, teacher or school.
/// Enabled with the `-DemoData` launch argument (Debug builds only). Built as fake API JSON /
/// Synergia HTML and run through the real parsers, so it exercises the same code paths.
enum DemoData {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-DemoData") }

    static let profile = StudentProfile(accountID: UUID(uuidString: "00000000-0000-0000-0000-00000000DE00")!,
                                        login: "demo", studentName: "Jan Przykładowy", isParent: true)
    static let account = StoredAccount(id: profile.accountID, kind: .synergia, displayName: "demo", profiles: [profile])

    // MARK: API data

    private static let subjects: [(Int, String, String)] = [
        (10, "Matematyka", "mat"), (11, "Język polski", "pol"), (12, "Język angielski", "ang"),
        (13, "Historia", "his"), (14, "Biologia", "bio"), (15, "Chemia", "chem"), (16, "Fizyka", "fiz"),
        (17, "Geografia", "geo"), (18, "Informatyka", "inf"), (19, "Wychowanie fizyczne", "wf"),
    ]
    private static let teachers: [(Int, String, String)] = [
        (500, "Anna", "Kowalska"), (501, "Piotr", "Nowak"), (502, "Maria", "Wiśniewska"), (503, "Tomasz", "Wójcik"),
        (504, "Katarzyna", "Kamińska"), (505, "Michał", "Lewandowski"), (506, "Agnieszka", "Zielińska"),
        (507, "Paweł", "Szymański"), (508, "Ewa", "Dąbrowska"), (509, "Krzysztof", "Kozłowski"),
    ]
    private static let hours = [("08:00", "08:45"), ("08:55", "09:40"), ("09:50", "10:35"), ("10:55", "11:40"),
                                ("11:50", "12:35"), ("12:45", "13:30"), ("13:40", "14:25")]
    /// Monday…Friday, subject ids per lesson.
    private static let plan: [[Int]] = [
        [10, 11, 12, 13, 19, 19], [14, 10, 11, 15, 17, 18, 12], [16, 12, 10, 11, 13, 14],
        [11, 10, 15, 16, 12, 17, 18], [13, 14, 10, 12, 19],
    ]

    static var currentSemester: Int {
        let month = Day.calendar.component(.month, from: Date())
        return (2...8).contains(month) ? 2 : 1
    }

    static func studentData() -> StudentData {
        var dict = LibrusParsers.Dictionaries()
        dict.subjects = LibrusParsers.subjects(json(["Subjects": subjects.map { ["Id": $0.0, "Name": $0.1, "Short": $0.2] }]))
        dict.teachers = LibrusParsers.teachers(json(["Users": teachers.map { ["Id": $0.0, "FirstName": $0.1, "LastName": $0.2] }]))
        dict.classrooms = LibrusParsers.classrooms(json(["Classrooms": (1...12).map { ["Id": $0, "Name": "sala", "Symbol": "\(100 + $0)"] }]))
        dict.gradeCategories = LibrusParsers.gradeCategories(json(["Categories": [
            ["Id": 1, "Name": "Sprawdzian", "Weight": 3, "CountToTheAverage": true, "Color": ["Id": 27]],
            ["Id": 2, "Name": "Kartkówka", "Weight": 2, "CountToTheAverage": true, "Color": ["Id": 2]],
            ["Id": 3, "Name": "Odpowiedź ustna", "Weight": 1, "CountToTheAverage": true, "Color": ["Id": 16]],
            ["Id": 4, "Name": "Praca domowa", "Weight": 1, "CountToTheAverage": true, "Color": ["Id": 29]],
            ["Id": 5, "Name": "Aktywność", "Weight": 1, "CountToTheAverage": false, "Color": ["Id": 22]],
        ]]))
        dict.gradeComments = [1: "Bardzo dobrze rozwiązane zadania tekstowe"]
        dict.eventCategories = LibrusParsers.eventCategories(json(["Categories": [
            ["Id": 1, "Name": "Sprawdzian", "Color": ["Id": 27]],
            ["Id": 2, "Name": "Kartkówka", "Color": ["Id": 28]],
            ["Id": 3, "Name": "Wycieczka", "Color": ["Id": 16]],
            ["Id": 4, "Name": "Zebranie z rodzicami", "Color": ["Id": 22]],
        ]]))
        dict.attendanceTypes = LibrusParsers.attendanceTypes(json(["Types": [
            ["Id": 1, "Name": "nieobecność", "Short": "nb", "Standard": true, "ColorRGB": "E57373"],
            ["Id": 2, "Name": "spóźnienie", "Short": "sp", "Standard": true, "ColorRGB": "FFD54F"],
            ["Id": 3, "Name": "nieobecność uspr.", "Short": "u", "Standard": true, "ColorRGB": "81C784"],
            ["Id": 100, "Name": "obecność", "Short": "ob", "Standard": true],
        ]]))
        dict.noticeCategories = [1: "Pochwała", 2: "Informacja"]
        dict.lessons = LibrusParsers.lessons(json(["Lessons": plan.enumerated().flatMap { weekday, subjectsOfDay in
            subjectsOfDay.enumerated().map { number, subject in
                ["Id": lessonID(weekday: weekday, number: number + 1), "Subject": ["Id": subject], "Teacher": ["Id": 500 + subject - 10]]
            }
        }]))

        var data = StudentData()
        data.studentName = profile.studentName
        data.subjects = dict.subjects.values.filter { $0.id != 1 }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        data.grades = LibrusParsers.grades(gradesJSON(), dict: dict)
        data.events = LibrusParsers.events(eventsJSON(), dict: dict)
        data.attendance = LibrusParsers.attendance(attendanceJSON(), dict: dict)
        data.notices = LibrusParsers.notices(json(["Notes": [
            ["Id": 1, "Text": "Wzorowo przygotował prezentację na lekcję historii.", "Category": ["Id": 1],
             "Teacher": ["Id": 503], "Date": Day.today.adding(days: -9).string, "Positive": 1],
            ["Id": 2, "Text": "Brak stroju na lekcji wychowania fizycznego.", "Category": ["Id": 2],
             "Teacher": ["Id": 509], "Date": Day.today.adding(days: -23).string, "Positive": 2],
        ]]), dict: dict)
        data.announcements = LibrusParsers.announcements(json(["SchoolNotices": [
            ["Id": "a1", "Subject": "Dzień otwarty szkoły", "Content": "Zapraszamy uczniów i rodziców na dzień otwarty w sobotę. Program w sekretariacie.",
             "StartDate": Day.today.adding(days: -2).string, "EndDate": Day.today.adding(days: 12).string, "AddedBy": ["Id": 500], "WasRead": false],
            ["Id": "a2", "Subject": "Zmiana godzin pracy biblioteki", "Content": "Od poniedziałku biblioteka czynna w godz. 8:00–15:00.",
             "StartDate": Day.today.adding(days: -6).string, "EndDate": Day.today.adding(days: 20).string, "AddedBy": ["Id": 508], "WasRead": true],
        ]]), dict: dict)
        data.luckyNumber = LibrusParsers.luckyNumber(json(["LuckyNumber": ["LuckyNumber": 13, "LuckyNumberDay": Day.today.string]]))
        data.timetable[Day.defaultTimetableWeek.string] = timetable(week: Day.defaultTimetableWeek, dict: dict)
        data.timetable[Day.today.weekStart.string] = timetable(week: Day.today.weekStart, dict: dict)
        data.fetchedAt = Date()
        return data
    }

    static func timetable(week: Day) -> [TimetableDay] {
        var dict = LibrusParsers.Dictionaries()
        dict.subjects = LibrusParsers.subjects(json(["Subjects": subjects.map { ["Id": $0.0, "Name": $0.1, "Short": $0.2] }]))
        dict.teachers = LibrusParsers.teachers(json(["Users": teachers.map { ["Id": $0.0, "FirstName": $0.1, "LastName": $0.2] }]))
        dict.classrooms = LibrusParsers.classrooms(json(["Classrooms": (1...12).map { ["Id": $0, "Name": "sala", "Symbol": "\(100 + $0)"] }]))
        return timetable(week: week, dict: dict)
    }

    private static func timetable(week: Day, dict: LibrusParsers.Dictionaries) -> [TimetableDay] {
        var days: [String: Any] = [:]
        for (index, subjectsOfDay) in plan.enumerated() {
            let day = week.adding(days: index)
            days[day.string] = subjectsOfDay.enumerated().map { number, subject -> [[String: Any]] in
                var lesson: [String: Any] = [
                    "LessonNo": number + 1, "HourFrom": hours[number].0, "HourTo": hours[number].1,
                    "Subject": ["Id": subject], "Teacher": ["Id": 500 + (subject - 10)],
                    "Classroom": ["Id": (subject % 12) + 1], "IsCanceled": false, "IsSubstitutionClass": false,
                ]
                if index == 2 && number == 4 { lesson["IsCanceled"] = true }
                if index == 3 && number == 2 {
                    lesson["IsSubstitutionClass"] = true
                    lesson["Teacher"] = ["Id": 506]
                    lesson["OrgDate"] = day.string
                    lesson["OrgLessonNo"] = number + 1
                    lesson["OrgSubject"] = ["Id": 15]
                    lesson["OrgTeacher"] = ["Id": 505]
                }
                return [lesson]
            }
        }
        days[week.adding(days: 5).string] = []
        days[week.adding(days: 6).string] = []
        return LibrusParsers.timetable(json(["Timetable": days]), dict: dict)
    }

    private static func gradesJSON() -> JSON {
        // (subject, grade, category, days ago)
        let entries: [(Int, String, Int, Int)] = [
            (10, "5", 1, 40), (10, "4+", 2, 31), (10, "5-", 3, 20), (10, "6", 4, 12), (10, "4", 2, 3),
            (11, "4", 1, 38), (11, "3+", 2, 27), (11, "5", 4, 15), (11, "4-", 3, 6),
            (12, "5", 2, 35), (12, "5", 1, 22), (12, "6", 3, 9), (12, "+", 5, 2),
            (13, "4", 3, 33), (13, "5", 1, 18), (13, "4+", 4, 4),
            (14, "3", 1, 36), (14, "4", 2, 21), (14, "5", 3, 8),
            (15, "nb", 1, 30), (15, "4", 1, 16), (15, "3+", 2, 5),
            (16, "4", 2, 29), (16, "3", 1, 14), (16, "4+", 3, 1),
            (17, "5", 3, 25), (17, "4", 2, 11),
            (18, "6", 4, 26), (18, "6", 1, 10),
            (19, "5", 3, 28), (19, "5", 3, 7),
        ]
        var grades: [[String: Any]] = entries.enumerated().map { index, entry in
            var grade: [String: Any] = [
                "Id": 1000 + index, "Grade": entry.1, "Semester": currentSemester, "IsConstituent": true,
                "Category": ["Id": entry.2], "Subject": ["Id": entry.0], "AddedBy": ["Id": 500 + entry.0 - 10],
                "AddDate": dateTime(daysAgo: entry.3),
            ]
            if index == 0 { grade["Comments"] = [["Id": 1]] }
            return grade
        }
        // The "nb" in chemistry (index 19) was later improved.
        grades.append(["Id": 1100, "Grade": "4", "Semester": currentSemester, "IsConstituent": true,
                       "Category": ["Id": 1], "Subject": ["Id": 15], "AddedBy": ["Id": 505],
                       "AddDate": dateTime(daysAgo: 13), "Improvement": ["Id": 1019]])
        grades.append(["Id": 1101, "Grade": "5", "Semester": currentSemester, "IsConstituent": false,
                       "IsSemesterProposition": true, "Subject": ["Id": 10], "AddedBy": ["Id": 500],
                       "AddDate": dateTime(daysAgo: 1)])
        return json(["Grades": grades])
    }

    private static func eventsJSON() -> JSON {
        let events: [(Int, Int, Int?, String, Int)] = [
            // (days ahead, category, subject, topic, lesson)
            (1, 2, 15, "Kartkówka z wiązań chemicznych", 4),
            (3, 1, 10, "Sprawdzian: funkcja kwadratowa (rozdział 4)", 2),
            (5, 3, nil, "Wycieczka do Centrum Nauki Kopernik — zbiórka 7:45 przed szkołą", 1),
            (8, 1, 12, "Test: Unit 5 — Past Perfect", 3),
            (11, 4, nil, "Zebranie z rodzicami — sala 104", 8),
        ]
        return json(["HomeWorks": events.enumerated().map { index, e in
            var event: [String: Any] = [
                "Id": 2000 + index, "Date": Day.today.adding(days: e.0).string, "Content": e.3,
                "Category": ["Id": e.1], "CreatedBy": ["Id": 500 + ((e.2 ?? 10) - 10)], "LessonNo": e.4,
                "AddDate": dateTime(daysAgo: 4),
            ]
            if let subject = e.2 { event["Subject"] = ["Id": subject] }
            return event
        }])
    }

    private static func attendanceJSON() -> JSON {
        var entries: [[String: Any]] = []
        var id = 3000
        for daysAgo in 1...20 {
            let day = Day.today.adding(days: -daysAgo)
            guard !Day.calendar.isDateInWeekend(day.date) else { continue }
            let weekday = (Day.calendar.component(.weekday, from: day.date) + 5) % 7
            for lesson in 1...min(6, plan[weekday].count) {
                var type = 100
                if daysAgo == 6 { type = 3 }
                if daysAgo == 13 && lesson == 1 { type = 2 }
                if daysAgo == 17 && lesson >= 5 { type = 1 }
                entries.append(["Id": "\(id)", "LessonNo": lesson, "Date": day.string, "Semester": currentSemester,
                                "Type": ["Id": type], "Lesson": ["Id": lessonID(weekday: weekday, number: lesson)],
                                "AddDate": dateTime(daysAgo: daysAgo)])
                id += 1
            }
        }
        return json(["Attendances": entries])
    }

    // MARK: Messages (fake Synergia HTML through the real parser)

    private static let inbox: [(String, String, String, Int, Bool, Bool)] = [
        // (id, sender, subject, days ago, unread, attachment)
        ("90001", "Kowalska Anna (Nauczyciel)", "Wyniki sprawdzianu z matematyki", 0, true, false),
        ("90002", "Sekretariat Szkoły (Sekretariat)", "Zgoda na wycieczkę — prosimy o podpis", 1, true, true),
        ("90003", "Nowak Piotr (Nauczyciel)", "Lektura na przyszły tydzień", 3, false, false),
        ("90004", "Dyrektor Szkoły (Dyrektor)", "Organizacja dnia otwartego", 6, false, true),
        ("90005", "Wójcik Tomasz (Wychowawca)", "Zebranie z rodzicami", 9, false, false),
    ]

    static func messages(_ folder: MessageFolder) -> [MessageSummary] {
        let rows: String
        switch folder {
        case .inbox:
            rows = inbox.map { m in
                let bold = m.4 ? " style=\"font-weight: bold;\"" : ""
                return "<tr class=\"line0\"><td></td><td>\(m.5 ? "<img src=\"a.png\">" : "")</td><td\(bold)><a href=\"/wiadomosci/1/5/\(m.0)/f0\">\(m.1)</a></td><td\(bold)><a href=\"/wiadomosci/1/5/\(m.0)/f0\">\(m.2)</a></td><td>\(dateTime(daysAgo: m.3))</td><td></td></tr>"
            }.joined()
        case .sent:
            rows = "<tr class=\"line0\"><td></td><td></td><td><a href=\"/wiadomosci/1/6/91001/f0\">Wójcik Tomasz</a></td><td><a href=\"/wiadomosci/1/6/91001/f0\">Usprawiedliwienie nieobecności</a></td><td>\(dateTime(daysAgo: 5))</td><td>TAK</td><td></td></tr>"
        }
        let html = "<table class=\"decorated stretch\"><tbody>\(rows)</tbody></table>"
        return (try? SynergiaParser.messageList(html, folder: folder)) ?? []
    }

    static func message(_ summary: MessageSummary) -> MessageDetail? {
        let attachment = summary.hasAttachments
            ? "<table><tr><td>zgoda_wycieczka.pdf</td><td><img onclick=\"otworz('\\/wiadomosci\\/pobierz_zalacznik\\/\(summary.id)\\/1')\"></td></tr></table>"
            : ""
        let html = """
        <table class="stretch"><tr><td class="left">\(summary.correspondent)</td></tr><tr><td class="left">\(summary.subject)</td></tr><tr><td class="left">\(summary.date)</td></tr></table>
        <div class="container-message-content">Dzień dobry,<br><br>uprzejmie informuję, że wyniki są już dostępne w dzienniku.
        W razie pytań zapraszam na konsultacje we wtorek po 7. lekcji.<br><br>Pozdrawiam serdecznie</div>\(attachment)
        """
        return try? SynergiaParser.messageDetail(html, id: summary.id)
    }

    static var recipientGroups: [RecipientGroup] {
        (try? SynergiaParser.recipientGroups("""
        <table class="message-recipients"><tbody>
        <tr><td><input class="recipiantTypeRadio" value="nauczyciel"><label>Nauczyciele</label></td></tr>
        <tr><td><input class="recipiantTypeRadio" value="wychowawca"><label>Wychowawca</label></td></tr>
        <tr><td><input class="recipiantTypeRadio" value="sekretariat"><label>Sekretariat</label></td></tr>
        </tbody></table>
        """)) ?? []
    }

    static var recipients: [Recipient] {
        let labels = teachers.map { "<label for=\"n_\($0.0)\">\($0.2) \($0.1)</label>" }.joined()
        return (try? SynergiaParser.recipients(labels)) ?? []
    }

    // MARK: helpers

    private static func lessonID(weekday: Int, number: Int) -> Int { 4000 + weekday * 10 + number }

    private static func json(_ object: Any) -> JSON {
        (try? JSON(data: JSONSerialization.data(withJSONObject: object))) ?? .null
    }

    private static func dateTime(daysAgo: Int) -> String {
        "\(Day.today.adding(days: -daysAgo).string) \(String(format: "%02d", 8 + daysAgo % 8)):\(String(format: "%02d", (daysAgo * 7) % 60)):00"
    }
}
#endif
