import Foundation
// Offline checks of the widget logic (WidgetSnapshot) on FAKE data. Run: ./scripts/check-widgets.sh
var failures = 0
func check(_ ok: Bool, _ name: String) { print(ok ? "  ok   \(name)" : "  FAIL \(name)"); if !ok { failures += 1 } }
let day = "2026-10-27", next = "2026-10-28"
func L(_ d: String, _ n: Int, _ s: String, _ e: String, _ subj: String, cancelled: Bool = false) -> WidgetSnapshot.Lesson {
    .init(day: d, number: n, start: s, end: e, subject: subj, classroom: "12", status: cancelled ? "odwołana" : nil, isCancelled: cancelled)
}
let snap = WidgetSnapshot(studentName: "Uczeń Testowy", updatedAt: Date(), lessons: [
    L(day, 1, "08:00", "08:45", "Matematyka"), L(day, 2, "08:55", "09:40", "Fizyka", cancelled: true),
    L(day, 3, "09:50", "10:35", "Historia"), L(next, 1, "08:00", "08:45", "Biologia")],
    events: [.init(day: next, category: "Sprawdzian", subject: "Historia", lessonNumber: 2), .init(day: "2026-10-30", category: "Kartkówka", subject: nil, lessonNumber: nil)],
    luckyNumber: 13, luckyDay: day)
func at(_ d: String, _ t: String) -> Date { WidgetDay.date(d, t)! }
check(snap.nextLesson(at: at(day, "08:10"))?.lesson.subject == "Matematyka" && snap.nextLesson(at: at(day, "08:10"))?.isNow == true, "during lesson 1 → Teraz Matematyka")
check(snap.nextLesson(at: at(day, "08:50"))?.lesson.subject == "Historia", "break before cancelled lesson → skips to Historia")
check(snap.nextLesson(at: at(day, "08:50"))?.isNow == false, "next, not now")
check(snap.nextLesson(at: at(day, "11:00"))?.lesson.day == next, "after school → tomorrow's first lesson")
check(WidgetDay.label(next, now: at(day, "11:00")) == "Jutro" && WidgetDay.label(day, now: at(day, "11:00")) == "Dziś", "labels Dziś/Jutro")
check(snap.lucky(at: at(day, "12:00"))?.number == 13 && snap.lucky(at: at(next, "08:00")) == nil, "lucky number expires next day")
check(snap.nextEvent(at: at(day, "12:00"))?.event.category == "Sprawdzian" && snap.nextEvent(at: at(day, "12:00"))?.more == 1, "next event + 1 more this week")
let b = snap.lessonBoundaries(after: at(day, "09:00"))
check(b.first == at(day, "09:40") && b.contains(at(next, "08:00")), "timeline boundaries from now on")
check(WidgetDay.adding(1, to: "2026-10-31") == "2026-11-01", "date math across month")
let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
check((try? dec.decode(WidgetSnapshot.self, from: enc.encode(snap))) != nil, "codable round trip")
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED"); exit(failures == 0 ? 0 : 1)
