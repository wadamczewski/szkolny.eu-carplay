import LibrusKit
import SwiftUI

struct TimetableView: View {
    @Environment(AppModel.self) private var model
    @State private var week = Day.defaultTimetableWeek
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Button { week = week.adding(days: -7) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        VStack {
                            Text("\(week.shortLabel) – \(week.adding(days: 6).shortLabel)")
                                .font(.headline)
                            if week != Day.today.weekStart {
                                Button("Bieżący tydzień") { week = Day.today.weekStart }
                                    .font(.caption)
                            }
                        }
                        Spacer()
                        Button { week = week.adding(days: 7) } label: { Image(systemName: "chevron.right") }
                    }
                    .buttonStyle(.borderless)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }

                let days = model.data?.timetable[week.string] ?? []
                if days.isEmpty && isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                }
                ForEach(days.filter { !$0.lessons.isEmpty || $0.day.date.isWeekday }, id: \.day) { day in
                    Section {
                        if day.lessons.isEmpty {
                            Text("Brak lekcji").foregroundStyle(.secondary)
                        }
                        ForEach(day.lessons) { LessonRow(lesson: $0) }
                        ForEach(model.data?.events.filter { $0.day == day.day } ?? []) { EventRow(event: $0) }
                    } header: {
                        Text(day.day.longLabel)
                            .foregroundStyle(day.day == .today ? Color.accentColor : .secondary)
                    }
                }
            }
            .navigationTitle("Plan lekcji")
            .tabChrome()
            .task(id: week) { await load() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await model.timetable(week: week)
            error = nil
        } catch {
            // Cached week stays visible.
            self.error = error.localizedDescription
        }
    }
}

private extension Date {
    var isWeekday: Bool { !Day.calendar.isDateInWeekend(self) }
}

struct LessonRow: View {
    let lesson: Lesson

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                Text("\(lesson.number)").font(.headline).monospacedDigit()
                Text(lesson.start).font(.caption2).foregroundStyle(.secondary)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(lesson.subject ?? "Lekcja")
                    .strikethrough(lesson.kind == .cancelled || lesson.kind == .shiftedSource)
                    .foregroundStyle(lesson.kind == .cancelled || lesson.kind == .shiftedSource ? .secondary : .primary)
                Text([lesson.classroom, lesson.teacher].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let note {
                    Text(note).font(.caption.weight(.semibold)).foregroundStyle(noteColor)
                }
            }
            Spacer()
            Text("\(lesson.start)–\(lesson.end)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private var note: String? {
        switch lesson.kind {
        case .normal: return nil
        case .cancelled: return "Odwołana"
        case .change:
            let old = [lesson.oldSubject, lesson.oldTeacher].compactMap { $0 }.joined(separator: ", ")
            return old.isEmpty ? "Zastępstwo" : "Zastępstwo (zamiast: \(old))"
        case .shiftedSource:
            return "Przeniesiona" + (lesson.otherDay.map { " na \($0.shortLabel)" } ?? "") + (lesson.otherNumber.map { ", lekcja \($0)" } ?? "")
        case .shiftedTarget:
            return "Przeniesiona" + (lesson.otherDay.map { " z \($0.shortLabel)" } ?? "") + (lesson.otherNumber.map { ", lekcja \($0)" } ?? "")
        }
    }

    private var noteColor: Color {
        lesson.kind == .cancelled ? .red : .orange
    }
}
