import SwiftUI
import WidgetKit

/// Widget extension. Small widgets also appear on the CarPlay Dashboard (iOS 26+) without a
/// CarPlay app or entitlement, which is how Dziennik gets into the car.
@main
struct DziennikWidgets: WidgetBundle {
    var body: some Widget {
        NextLessonWidget()
        LuckyNumberWidget()
        UpcomingEventWidget()
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Reads the app's snapshot. `lessonTimes` adds an entry at every lesson start/end, so "Teraz"
/// and "Następna" switch on time without the app running.
struct SnapshotProvider: TimelineProvider {
    var lessonTimes = false

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        let midnight = WidgetDay.startOfNextDay(after: now)
        var dates = [now, midnight]
        if lessonTimes, let snapshot {
            dates += snapshot.lessonBoundaries(after: now)
        }
        let entries = Array(Set(dates)).sorted().map { SnapshotEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(entries.last.map { max($0.date, midnight) } ?? midnight)))
    }
}

struct NextLessonWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextLesson", provider: SnapshotProvider(lessonTimes: true)) { entry in
            NextLessonWidgetView(snapshot: entry.snapshot, date: entry.date)
        }
        .configurationDisplayName("Następna lekcja")
        .description("Trwająca albo najbliższa lekcja: przedmiot, godzina i sala.")
        .supportedFamilies([.systemSmall])
    }
}

struct LuckyNumberWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LuckyNumber", provider: SnapshotProvider()) { entry in
            LuckyNumberWidgetView(snapshot: entry.snapshot, date: entry.date)
        }
        .configurationDisplayName("Szczęśliwy numerek")
        .description("Szczęśliwy numerek na dziś lub najbliższy dzień.")
        .supportedFamilies([.systemSmall])
    }
}

struct UpcomingEventWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpcomingEvent", provider: SnapshotProvider()) { entry in
            UpcomingEventWidgetView(snapshot: entry.snapshot, date: entry.date)
        }
        .configurationDisplayName("Terminarz")
        .description("Najbliższy sprawdzian, kartkówka lub wydarzenie.")
        .supportedFamilies([.systemSmall])
    }
}

extension WidgetSnapshot {
    /// Shown in the widget gallery before the first sync. Fake.
    static var placeholder: WidgetSnapshot {
        let today = WidgetDay.string(Date())
        return WidgetSnapshot(
            studentName: "Uczeń",
            updatedAt: Date(),
            lessons: [Lesson(day: today, number: 3, start: "09:50", end: "10:35", subject: "Matematyka", classroom: "12", status: nil, isCancelled: false)],
            events: [Event(day: WidgetDay.adding(1, to: today), category: "Sprawdzian", subject: "Historia", lessonNumber: 2)],
            luckyNumber: 13,
            luckyDay: today
        )
    }
}
