import Foundation
import LibrusKit

// Offline check of the parsers against synthetic (fake) fixtures. No network, no real data.

var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        print("  ok   \(message)")
    } else {
        failures += 1
        print("  FAIL \(message) (line \(line))")
    }
}

func fixture(_ name: String) -> Data {
    let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!
    return try! Data(contentsOf: url)
}
func json(_ name: String) -> JSON { try! JSON(data: fixture(name)) }
func html(_ name: String) -> String { String(decoding: fixture(name), as: UTF8.self) }

print("Grade values")
check(GradeMath.value(of: "5") == 5, "5 → 5")
check(GradeMath.value(of: "4+") == 4.5, "4+ → 4.5")
check(GradeMath.value(of: "3-") == 2.75, "3- → 2.75")
check(GradeMath.value(of: "np") == nil, "np → nil")
check(GradeMath.value(of: "+") == nil, "+ → nil")

print("Form encoding")
check(HTTPClient.formEncode([("wyslij", "Wyślij")]) == "wyslij=Wy%C5%9Blij", "Polish chars percent-encoded")
check(HTTPClient.formEncode([("t", "a b+c&d=e")]) == "t=a+b%2Bc%26d%3De", "space, plus, ampersand, equals")
check(HTTPClient.formEncode([("x", "1"), ("x", "2")]) == "x=1&x=2", "repeated keys kept")

print("Dictionaries")
var dict = LibrusParsers.Dictionaries()
dict.subjects = LibrusParsers.subjects(json("subjects.json"))
dict.teachers = LibrusParsers.teachers(json("users.json"))
dict.classrooms = LibrusParsers.classrooms(json("classrooms.json"))
dict.gradeCategories = LibrusParsers.gradeCategories(json("grade_categories.json"))
dict.gradeComments = LibrusParsers.gradeComments(json("grade_comments.json"))
dict.attendanceTypes = LibrusParsers.attendanceTypes(json("attendance_types.json"))
dict.lessons = LibrusParsers.lessons(json("lessons.json"))
check(dict.subjects.count == 3, "subjects incl. synthetic Zachowanie")
check(dict.teachers[500]?.fullName == "Jan Testowy", "teacher name fixed")
check(dict.teachers[501]?.fullName == "Anna Przykładowa-Nowak", "double-barrelled name")
check(dict.gradeCategories[1]?.weight == 3 && dict.gradeCategories[1]?.name == "Sprawdzian", "category weight + trim")
check(dict.gradeCategories[2]?.weight == 2, "string weight")
check(dict.gradeCategories[3]?.weight == 0, "not counted → weight 0")
check(dict.classrooms[3] == "12 sala matematyczna", "classroom symbol + name")

print("Grades")
let grades = LibrusParsers.grades(json("grades.json"), dict: dict)
check(grades.count == 6, "6 grades")
let g1001 = grades.first { $0.id == 1001 }
check(g1001?.comment == "Bardzo dobra praca (dane fikcyjne)", "grade comment")
check(g1001?.colorHex == "#FF0000", "category color")
check(grades.first { $0.id == 1003 }?.weight == 0, "'+' has no weight")
check(grades.first { $0.id == 1004 }?.improvedByID == 1005, "nb improved by 1005")
check(grades.first { $0.id == 1004 }?.weight == 0, "improved nb weight 0")
check(grades.first { $0.id == 1005 }?.isImprovement == true, "improvement flag")
check(grades.first { $0.id == 1006 }?.kind == .semesterProposed, "proposed semester grade")
let mathAverage = GradeMath.average(grades.filter { $0.subjectID == 10 })
check(mathAverage.map { abs($0 - (5.0 * 3 + 2.75 * 2) / 5) < 0.0001 } == true, "weighted average math = 4.1")
check(GradeMath.average(grades.filter { $0.subjectID == 11 }) == 4.5, "average polish = 4.5")

print("Timetable")
let week = LibrusParsers.timetable(json("timetable.json"), dict: dict)
check(week.count == 2, "2 days")
let monday = week[0].lessons
check(monday.count == 3, "3 lessons on Monday")
check(monday[0].teacher == "Jan Testowy" && monday[0].classroom == "12 sala matematyczna", "lesson details")
check(monday[1].kind == .cancelled, "cancelled lesson")
check(monday[2].kind == .change && monday[2].oldSubject == "Język polski", "substitution")
check(week[1].lessons.isEmpty, "empty day")
check(Day("2025-10-08")!.weekStart.string == "2025-10-06", "week start is Monday")
check(Day("2025-10-12")!.weekStart.string == "2025-10-06", "Sunday belongs to previous week")

print("Attendance & lucky number")
let attendance = LibrusParsers.attendance(json("attendances.json"), dict: dict)
check(attendance.count == 2, "2 entries")
check(attendance.first { $0.id == "t123" }?.base == .absent, "absence type")
check(attendance.first { $0.id == "t123" }?.subject == "Matematyka", "subject via Lessons")
check(attendance.first { $0.id == "t123" }?.colorHex == "#FF0000", "type color")
check(LibrusParsers.luckyNumber(json("lucky.json"))?.number == 13, "lucky number")

print("Synergia messages HTML")
do {
    let inbox = try SynergiaParser.messageList(html("inbox.html"), folder: .inbox)
    check(inbox.count == 2, "2 messages")
    check(inbox[0].id == "111111" && inbox[0].unread && inbox[0].hasAttachments, "first unread with attachment")
    check(inbox[0].subject == "Wycieczka klasowa", "nbsp cleaned")
    check(!inbox[1].unread && !inbox[1].hasAttachments, "second read, no attachment")

    let detail = try SynergiaParser.messageDetail(html("message.html"), id: "111111")
    check(detail.sender == "Testowy Jan (Nauczyciel)", "sender")
    check(detail.subject == "Wycieczka klasowa", "subject")
    check(detail.date == "2025-10-01 12:00:00", "date")
    check(detail.bodyHTML.contains("<b>fikcyjna</b>"), "body html")
    check(detail.attachments == [MessageAttachment(id: "555", messageID: "111111", filename: "regulamin.pdf")], "attachment")

    let groups = try SynergiaParser.recipientGroups(html("groups.html"))
    check(groups.map(\.value) == ["nauczyciel", "wychowawca"], "recipient groups")
    check(groups.first?.name == "Nauczyciele", "group label")
    let recipients = try SynergiaParser.recipients(html("recipients.html"))
    check(recipients == [Recipient(id: "500", name: "Testowy Jan"), Recipient(id: "501", name: "Przykładowa Anna")], "recipients")
} catch {
    failures += 1
    print("  FAIL parser threw: \(error)")
}

print(failures == 0 ? "\nALL CHECKS PASSED" : "\n\(failures) CHECK(S) FAILED")
exit(failures == 0 ? 0 : 1)
