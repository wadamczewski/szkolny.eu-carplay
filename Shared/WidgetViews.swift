import SwiftUI
import WidgetKit

/// Small widgets (`systemSmall`): on the Home Screen, in StandBy and, since iOS 26, on the
/// CarPlay Dashboard. Big type, few words: they are read at a glance in the car.
/// Shared with the app so the debug widget gallery renders exactly the same views.

struct NextLessonWidgetView: View {
    let snapshot: WidgetSnapshot?
    let date: Date

    var body: some View {
        WidgetFrame(title: "Lekcja", systemImage: "book.closed.fill", snapshot: snapshot) { snapshot in
            if let (lesson, isNow) = snapshot.nextLesson(at: date) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNow ? "Teraz" : lesson.day == WidgetDay.string(date) ? "Następna" : WidgetDay.label(lesson.day, now: date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isNow ? Color.dziennik : .secondary)
                        .widgetAccentable()
                    Text(lesson.subject)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .strikethrough(lesson.isCancelled)
                    Spacer(minLength: 0)
                    Text("\(lesson.start)–\(lesson.end)")
                        .font(.headline.monospacedDigit())
                    Text([lesson.classroom, lesson.status].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(lesson.status == nil ? .secondary : Color.orange)
                        .lineLimit(1)
                }
            } else {
                EmptyLine(text: "Brak lekcji w planie")
            }
        }
    }
}

struct LuckyNumberWidgetView: View {
    let snapshot: WidgetSnapshot?
    let date: Date

    var body: some View {
        WidgetFrame(title: "Numerek", systemImage: "star.fill", snapshot: snapshot) { snapshot in
            if let lucky = snapshot.lucky(at: date) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 0)
                    Text("\(lucky.number)")
                        .font(.system(size: 64, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color.dziennik)
                        .widgetAccentable()
                        .minimumScaleFactor(0.5)
                    Text("Szczęśliwy numerek · \(WidgetDay.label(lucky.day, now: date))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } else {
                EmptyLine(text: "Brak szczęśliwego numerka")
            }
        }
    }
}

struct UpcomingEventWidgetView: View {
    let snapshot: WidgetSnapshot?
    let date: Date

    var body: some View {
        WidgetFrame(title: "Terminarz", systemImage: "calendar", snapshot: snapshot) { snapshot in
            if let (event, more) = snapshot.nextEvent(at: date) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetDay.label(event.day, now: date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.dziennik)
                        .widgetAccentable()
                    Text(event.category)
                        .font(.title3.weight(.bold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(event.subject ?? "")
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                    Text([event.lessonNumber.map { "lekcja \($0)" }, more > 0 ? "+\(more) więcej" : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                EmptyLine(text: "Nic w terminarzu")
            }
        }
    }
}

/// Header, the content, and a "not logged in" state shared by all widgets.
private struct WidgetFrame<Content: View>: View {
    let title: String
    let systemImage: String
    let snapshot: WidgetSnapshot?
    @ViewBuilder let content: (WidgetSnapshot) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title)
                Spacer(minLength: 0)
                if let snapshot {
                    Text(snapshot.studentName.split(separator: " ").first.map(String.init) ?? "")
                        .lineLimit(1)
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)

            if let snapshot {
                content(snapshot)
            } else {
                EmptyLine(text: "Otwórz Dziennik i zaloguj się")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }
}

private struct EmptyLine: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading) {
            Spacer(minLength: 0)
            Text(text)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}

extension Color {
    /// The app's accent (AccentColor in the app's assets), also used where the widget has no asset catalog.
    static let dziennik = Color(red: 0.91, green: 0.42, blue: 0.18)
}
