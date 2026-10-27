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

#if DEBUG
/// The widgets on a CarPlay-sized dark canvas (800×480 pt, a common CarPlay screen), written to
/// Documents/carplay-widgety.png at 2× for the README (`-DemoData -CarPlayPreview`). Only a plain
/// background, no CarPlay chrome: it is a render of the widget views, not a screenshot from a car.
struct CarPlayPreviewView: View {
    @Environment(AppModel.self) private var model
    @State private var savedTo: String?

    static let fileName = "carplay-widgety.png"

    var body: some View {
        VStack(spacing: 16) {
            canvas
                .scaleEffect(0.45)
                .frame(width: 800 * 0.45, height: 480 * 0.45)
            Text(savedTo ?? "Renderowanie…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task(id: model.data == nil) {
            guard model.data != nil else { return }
            let renderer = ImageRenderer(content: canvas)
            renderer.scale = 2
            guard let png = renderer.uiImage?.pngData() else { return }
            let url = URL.documentsDirectory.appending(path: Self.fileName)
            try? png.write(to: url)
            savedTo = url.path
        }
    }

    /// CarPlay Dashboard is dark; tiles get a background themselves because
    /// `containerBackground(for: .widget)` only paints inside a widget host.
    private var canvas: some View {
        let moment = Day.calendar.date(bySettingHour: 10, minute: 5, second: 0, of: Date()) ?? Date()
        let snapshot = model.data.map { WidgetBridge.makeSnapshot($0, profile: model.currentProfile, now: moment) }
        return HStack(spacing: 20) {
            tile(NextLessonWidgetView(snapshot: snapshot, date: moment))
            tile(LuckyNumberWidgetView(snapshot: snapshot, date: moment))
            tile(UpcomingEventWidgetView(snapshot: snapshot, date: moment))
        }
        .frame(width: 800, height: 480)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
    }

    private func tile<V: View>(_ view: V) -> some View {
        view
            .padding(16)
            .frame(width: 220, height: 220)
            // Dark-gray platter: on the black Dashboard a black widget background would vanish.
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}
#endif
