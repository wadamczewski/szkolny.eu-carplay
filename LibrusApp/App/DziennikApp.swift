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
                    // Refresh when coming back, if the data is older than 15 minutes.
                    guard phase == .active, model.isLoggedIn else { return }
                    if (model.data?.fetchedAt.timeIntervalSinceNow ?? -.infinity) < -15 * 60 {
                        Task { await model.refresh() }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
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
