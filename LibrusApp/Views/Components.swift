import LibrusKit
import SwiftUI
import WebKit

extension Color {
    init?(hex: String?) {
        guard var s = hex?.trimmingCharacters(in: .whitespaces) else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt64(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum Formatters {
    static let dayLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = Day.calendar.timeZone
        f.dateFormat = "EEEE, d MMMM"
        return f
    }()

    static let dayShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "pl_PL")
        f.timeZone = Day.calendar.timeZone
        f.dateFormat = "d MMM"
        return f
    }()

    static func average(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",")
    }

    static func weight(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }
}

extension Day {
    var longLabel: String {
        if self == .today { return "Dzisiaj" }
        if self == Day.today.adding(days: 1) { return "Jutro" }
        return Formatters.dayLong.string(from: date).capitalizedFirst
    }

    var shortLabel: String { Formatters.dayShort.string(from: date) }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

struct GradeChip: View {
    let grade: Grade

    var body: some View {
        Text(grade.name)
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .frame(minWidth: 26)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background((Color(hex: grade.colorHex) ?? .blue).opacity(0.85), in: RoundedRectangle(cornerRadius: 6))
            .foregroundStyle(.black.opacity(0.8))
            .opacity(grade.improvedByID != nil ? 0.45 : 1)
    }
}

struct WarningsSection: View {
    let warnings: [String]

    var body: some View {
        if !warnings.isEmpty {
            Section {
                ForEach(warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text("Nie wszystko się wczytało")
            }
        }
    }
}

struct ProfileMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.profiles.count > 1 {
            Menu {
                ForEach(model.profiles) { profile in
                    Button {
                        model.selectedProfileID = profile.id
                        Task { await model.refresh() }
                    } label: {
                        if profile.id == model.selectedProfileID {
                            Label(profile.studentName, systemImage: "checkmark")
                        } else {
                            Text(profile.studentName)
                        }
                    }
                }
            } label: {
                Label(model.currentProfile?.shortName ?? "Uczeń", systemImage: "person.crop.circle")
            }
        }
    }
}

/// Shared toolbar + pull-to-refresh behaviour for top-level tabs.
struct TabChrome: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { ProfileMenu() }
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isRefreshing { ProgressView() }
                }
            }
    }
}

extension View {
    func tabChrome() -> some View { modifier(TabChrome()) }
}

/// Renders an HTML fragment (message bodies) with system font, dark mode and external links.
struct HTMLView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != html else { return }
        context.coordinator.loaded = html
        let page = """
        <html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        :root { color-scheme: light dark; }
        body { font: -apple-system-body; margin: 16px; word-wrap: break-word; }
        img { max-width: 100%; height: auto; }
        a { color: #0a84ff; }
        </style></head><body>\(html)</body></html>
        """
        view.loadHTMLString(page, baseURL: URL(string: LibrusConstants.synergiaURL))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loaded: String?

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
