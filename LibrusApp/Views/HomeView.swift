import LibrusKit
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            List {
                if let error = model.lastError {
                    Section {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.red)
                    }
                }

                if let data = model.data {
                    content(data)
                } else if model.isRefreshing {
                    HStack { Spacer(); ProgressView("Pobieranie danych…"); Spacer() }
                } else {
                    ContentUnavailableView("Brak danych", systemImage: "tray",
                                           description: Text("Pociągnij w dół, aby pobrać dane z Librusa."))
                }
            }
            .navigationTitle(model.data?.studentName ?? model.currentProfile?.studentName ?? "Start")
            .tabChrome()
            .task {
                if model.data == nil { await model.refresh() }
            }
        }
    }

    @ViewBuilder
    private func content(_ data: StudentData) -> some View {
        if let lucky = data.luckyNumber, lucky.day >= .today {
            Section {
                HStack {
                    Image(systemName: "star.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading) {
                        Text("Szczęśliwy numerek")
                            .font(.headline)
                        Text(lucky.day.longLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(lucky.number)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                }
            }
        }

        if let (day, lessons) = nextSchoolDay(data) {
            Section(day.longLabel) {
                ForEach(lessons) { LessonRow(lesson: $0) }
            }
        }

        let upcoming = data.events.filter { $0.day >= .today && $0.day <= Day.today.adding(days: 7) }
        if !upcoming.isEmpty {
            Section("Najbliższe 7 dni") {
                ForEach(upcoming) { EventRow(event: $0) }
            }
        }

        let recent = data.grades
            .filter { $0.addedDate != nil }
            .sorted { $0.addedDate! > $1.addedDate! }
            .prefix(6)
        if !recent.isEmpty {
            Section("Ostatnie oceny") {
                ForEach(Array(recent)) { grade in
                    HStack {
                        GradeChip(grade: grade)
                        VStack(alignment: .leading) {
                            Text(data.subjects.first { $0.id == grade.subjectID }?.name ?? "Przedmiot")
                            Text(grade.category.isEmpty ? grade.kind.label : grade.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let date = grade.addedDate {
                            Text(Day(date: date).shortLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        WarningsSection(warnings: data.warnings)

        Section {
            Text("Zaktualizowano \(data.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Today's lessons, or the next day with lessons (after 16:00 → from tomorrow).
    private func nextSchoolDay(_ data: StudentData) -> (Day, [Lesson])? {
        let hour = Day.calendar.component(.hour, from: Date())
        let from = hour >= 16 ? Day.today.adding(days: 1) : Day.today
        return data.timetable.values
            .flatMap { $0 }
            .filter { $0.day >= from && !$0.lessons.isEmpty }
            .sorted { $0.day < $1.day }
            .first
            .map { ($0.day, $0.lessons) }
    }
}
