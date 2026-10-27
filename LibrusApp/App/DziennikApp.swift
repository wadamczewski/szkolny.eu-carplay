import BackgroundTasks
import LibrusKit
import SwiftUI

@main
struct DziennikApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background, model.isLoggedIn { Self.scheduleRefresh() }
                    // Refresh when coming back, if the data is older than 15 minutes.
                    guard phase == .active, model.isLoggedIn else { return }
                    if (model.data?.fetchedAt.timeIntervalSinceNow ?? -.infinity) < -15 * 60 {
                        Task { await model.refresh() }
                    }
                }
        }
        // Keeps the widgets (and CarPlay Dashboard) current without opening the app. iOS decides
        // when it actually runs, usually a few times a day for apps that are used.
        .backgroundTask(.appRefresh(Self.refreshTask)) {
            Self.scheduleRefresh()
            await model.refresh()
        }
    }

    static let refreshTask = "\(Bundle.main.bundleIdentifier ?? "dziennik").refresh"

    static func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTask)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-WidgetGallery") {
            WidgetGalleryView()
        } else if ProcessInfo.processInfo.arguments.contains("-CarPlayPreview") {
            CarPlayPreviewView()
        } else {
            tabs
        }
        #else
        tabs
        #endif
    }

    @ViewBuilder
    private var tabs: some View {
        if model.isLoggedIn {
            TabView {
                HomeView()
                    .tabItem { Label("Start", systemImage: "house") }
                GradesView()
                    .tabItem { Label("Oceny", systemImage: "list.number") }
                TimetableView()
                    .tabItem { Label("Plan", systemImage: "calendar") }
                MessagesView()
                    .tabItem { Label("Wiadomości", systemImage: "envelope") }
                MoreView()
                    .tabItem { Label("Więcej", systemImage: "ellipsis.circle") }
            }
        } else {
            LoginView()
        }
    }
}
