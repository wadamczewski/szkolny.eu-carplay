import LibrusKit
import SwiftUI

struct GradesView: View {
    @Environment(AppModel.self) private var model
    @State private var semester = 1

    var body: some View {
        NavigationStack {
            List {
                if let data = model.data {
                    let rows = subjectRows(data)
                    Section {
                        Picker("Semestr", selection: $semester) {
                            Text("Semestr 1").tag(1)
                            Text("Semestr 2").tag(2)
                        }
                        .pickerStyle(.segmented)
                        HStack {
                            Text("Średnia ze średnich")
                            Spacer()
                            Text(Formatters.average(overall(rows)))
                                .font(.headline)
                                .monospacedDigit()
                        }
                    }
                    if rows.isEmpty {
                        ContentUnavailableView("Brak ocen", systemImage: "list.number")
                    }
                    ForEach(rows, id: \.subject.id) { row in
                        NavigationLink {
                            SubjectGradesView(subject: row.subject, grades: row.grades, semester: semester)
                        } label: {
                            SubjectRow(subject: row.subject, grades: row.grades)
                        }
                    }
                }
            }
            .navigationTitle("Oceny")
            .tabChrome()
            .onAppear {
                // Default to the semester with the newest grade.
                if let latest = model.data?.grades.max(by: { ($0.addedDate ?? .distantPast) < ($1.addedDate ?? .distantPast) }) {
                    semester = latest.semester
                }
            }
        }
    }

    private func subjectRows(_ data: StudentData) -> [(subject: Subject, grades: [Grade])] {
        let bySubject = Dictionary(grouping: data.grades.filter { $0.semester == semester }, by: \.subjectID)
        return data.subjects.compactMap { subject in
            guard let grades = bySubject[subject.id], !grades.isEmpty else { return nil }
            return (subject, grades.sorted { ($0.addedDate ?? .distantPast) < ($1.addedDate ?? .distantPast) })
        }
    }

    private func overall(_ rows: [(subject: Subject, grades: [Grade])]) -> Double? {
        let averages = rows.compactMap { GradeMath.average($0.grades) }
        guard !averages.isEmpty else { return nil }
        return averages.reduce(0, +) / Double(averages.count)
    }
}

private struct SubjectRow: View {
    let subject: Subject
    let grades: [Grade]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(subject.name).font(.headline)
                Spacer()
                if let proposed = grades.last(where: { $0.kind != .normal }) {
                    Text("\(proposed.kind == .semesterProposed || proposed.kind == .yearProposed ? "przew." : "końc.") \(proposed.name)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.tint.opacity(0.15), in: Capsule())
                }
                Text(Formatters.average(GradeMath.average(grades)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(grades.filter { $0.kind == .normal }) { GradeChip(grade: $0) }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct SubjectGradesView: View {
    let subject: Subject
    let grades: [Grade]
    let semester: Int

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Średnia ważona")
                    Spacer()
                    Text(Formatters.average(GradeMath.average(grades))).font(.headline).monospacedDigit()
                }
            } footer: {
                Text("Liczona lokalnie: + = +0,5, − = −0,25; oceny z wagą 0 i „nb” poprawione później nie są liczone. Średnia w Librusie może się różnić, jeśli szkoła liczy inaczej.")
            }

            let finals = grades.filter { $0.kind != .normal }
            if !finals.isEmpty {
                Section("Oceny okresowe") {
                    ForEach(finals) { grade in
                        HStack {
                            GradeChip(grade: grade)
                            Text(grade.kind.label)
                        }
                    }
                }
            }

            Section("Semestr \(semester)") {
                ForEach(grades.filter { $0.kind == .normal }.reversed()) { grade in
                    GradeDetailRow(grade: grade, improvedBy: grades.first { $0.id == grade.improvedByID })
                }
            }
        }
        .navigationTitle(subject.name)
    }
}

private struct GradeDetailRow: View {
    let grade: Grade
    let improvedBy: Grade?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            GradeChip(grade: grade)
            VStack(alignment: .leading, spacing: 2) {
                Text(grade.category.isEmpty ? "Ocena" : grade.category)
                    .font(.body.weight(.medium))
                if let comment = grade.comment, !comment.isEmpty {
                    Text(comment).font(.subheadline)
                }
                Text([
                    grade.weight > 0 ? "waga \(Formatters.weight(grade.weight))" : "nie liczy się do średniej",
                    grade.teacherName,
                    grade.addedDate.map { Day(date: $0).shortLabel },
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
                if let improvedBy {
                    Text("Poprawiona na \(improvedBy.name)")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if grade.isImprovement {
                    Text("Poprawa")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
    }
}
