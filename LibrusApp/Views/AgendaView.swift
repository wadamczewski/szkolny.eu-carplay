import LibrusKit
import SwiftUI

struct AgendaView: View {
    @Environment(AppModel.self) private var model
    @State private var showPast = false

    var body: some View {
        List {
            Toggle("Pokaż minione", isOn: $showPast)
            let events = (model.data?.events ?? []).filter { showPast || $0.day >= .today }
            let days = Dictionary(grouping: events, by: \.day).sorted { showPast ? $0.key > $1.key : $0.key < $1.key }
            if days.isEmpty {
                ContentUnavailableView("Brak wydarzeń", systemImage: "calendar.badge.checkmark")
            }
            ForEach(days, id: \.key) { day, events in
                Section(day.longLabel) {
                    ForEach(events) { EventRow(event: $0) }
                }
            }
        }
        .navigationTitle("Terminarz")
        .refreshable { await model.refresh() }
    }
}

struct EventRow: View {
    let event: AgendaEvent
    @State private var expanded = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(hex: event.colorHex) ?? .blue)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(event.category).font(.subheadline.weight(.semibold))
                    if let subject = event.subject {
                        Text(subject).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                if !event.topic.isEmpty {
                    Text(event.topic)
                        .font(.subheadline)
                        .lineLimit(expanded ? nil : 3)
                        .textSelection(.enabled)
                }
                Text([
                    event.lessonNumber.map { "lekcja \($0)" },
                    event.time,
                    event.teacher,
                ].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { expanded.toggle() }
    }
}
