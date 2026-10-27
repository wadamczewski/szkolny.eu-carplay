import Foundation
import LibrusKit
import WidgetKit

/// Hands the current student's data to the widgets (Home Screen, StandBy, CarPlay Dashboard).
enum WidgetBridge {
    /// Writes the snapshot only when it changed, then asks WidgetKit to reload.
    static func update(_ data: StudentData?, profile: StudentProfile?) {
        let snapshot = data.map { makeSnapshot($0, profile: profile) }
        guard snapshot != WidgetSnapshot.load() else { return }
        WidgetSnapshot.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func makeSnapshot(_ data: StudentData, profile: StudentProfile?, now: Date = Date()) -> WidgetSnapshot {
        let today = Day(date: now)
        let lastLessonDay = today.adding(days: 7)
        let lessons = data.timetable.values
            .flatMap { $0 }
            .filter { $0.day >= today && $0.day <= lastLessonDay }
            .flatMap(\.lessons)
            .sorted { ($0.day, $0.number) < ($1.day, $1.number) }
            .map { lesson in
                WidgetSnapshot.Lesson(
                    day: lesson.day.string,
                    number: lesson.number,
                    start: lesson.start,
                    end: lesson.end,
                    subject: lesson.subject ?? "Lekcja",
                    classroom: lesson.classroom,
                    status: status(lesson),
                    isCancelled: lesson.kind == .cancelled || lesson.kind == .shiftedSource
                )
            }
        let lastEventDay = today.adding(days: 14)
        let events = data.events
            .filter { $0.day >= today && $0.day <= lastEventDay }
            .map { WidgetSnapshot.Event(day: $0.day.string, category: $0.category, subject: $0.subject, lessonNumber: $0.lessonNumber) }
        let lucky = data.luckyNumber.flatMap { $0.day >= today ? $0 : nil }
        return WidgetSnapshot(
            studentName: data.studentName ?? profile?.studentName ?? "Uczeń",
            updatedAt: data.fetchedAt,
            lessons: lessons,
            events: events,
            luckyNumber: lucky?.number,
            luckyDay: lucky?.day.string
        )
    }

    private static func status(_ lesson: Lesson) -> String? {
        switch lesson.kind {
        case .normal: return nil
        case .cancelled: return "odwołana"
        case .change: return lesson.oldSubject.map { "zastępstwo za: \($0)" } ?? "zastępstwo"
        case .shiftedSource: return "przeniesiona"
        case .shiftedTarget: return "przeniesiona tutaj"
        }
    }
}
