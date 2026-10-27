#if DEBUG
import LibrusKit
import SwiftUI

/// The widgets as they look at a fixed moment, for screenshots and design work (Debug builds,
/// `-DemoData -WidgetGallery` launch arguments). Uses the same views as the widget extension.
struct WidgetGalleryView: View {
    @Environment(AppModel.self) private var model

    /// 10:05 today: during lesson 3 in the demo plan, so "Teraz" is shown.
    private var moment: Date {
        Day.calendar.date(bySettingHour: 10, minute: 5, second: 0, of: Date()) ?? Date()
    }

    var body: some View {
        let snapshot = model.data.map { WidgetBridge.makeSnapshot($0, profile: model.currentProfile, now: moment) }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Widgety Dziennika")
                    .font(.largeTitle.bold())
                Text("Ekran główny, StandBy i CarPlay (iOS 26+). Dane fikcyjne.")
                    .foregroundStyle(.secondary)
                row(snapshot, scheme: .light)
                row(snapshot, scheme: .dark)
            }
            .padding(24)
        }
    }

    private func row(_ snapshot: WidgetSnapshot?, scheme: ColorScheme) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158, maximum: 158), spacing: 16)], spacing: 16) {
            tile(NextLessonWidgetView(snapshot: snapshot, date: moment), scheme: scheme)
            tile(LuckyNumberWidgetView(snapshot: snapshot, date: moment), scheme: scheme)
            tile(UpcomingEventWidgetView(snapshot: snapshot, date: moment), scheme: scheme)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(scheme == .dark ? Color.black : Color(white: 0.92), in: RoundedRectangle(cornerRadius: 28))
    }

    private func tile<V: View>(_ view: V, scheme: ColorScheme) -> some View {
        view
            .padding(14)
            .frame(width: 158, height: 158)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, scheme)
    }
}
#endif
