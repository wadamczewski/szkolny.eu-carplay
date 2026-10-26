import LibrusKit
import SwiftUI
import WebKit

/// Konto Librus login in a web view. The portal handles e-mail, password, 2FA and reCAPTCHA;
/// we only catch the final `app://librus?code=...` redirect (what the official app receives).
/// The password never passes through this app.
struct PortalLoginView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isExchanging = false
    @State private var error: String?
    @State private var reloadID = UUID()
    @State private var isPageLoading = true

    var body: some View {
        NavigationStack {
            ZStack {
                PortalWebView(onCode: handle(code:), onError: { error = $0 }, isLoading: $isPageLoading)
                    .id(reloadID)
                if isPageLoading && !isExchanging {
                    ProgressView("Łączenie z portal.librus.pl…")
                }
                if isExchanging {
                    ProgressView("Pobieranie kont uczniów…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Konto Librus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Anuluj") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { reloadID = UUID() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .alert("Logowanie nieudane", isPresented: .constant(error != nil)) {
                Button("OK") { error = nil; reloadID = UUID() }
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func handle(code: String) {
        guard !isExchanging else { return }
        isExchanging = true
        Task {
            do {
                try await model.finishPortalLogin(code: code)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            isExchanging = false
        }
    }
}

private struct PortalWebView: UIViewRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void
    @Binding var isLoading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.customUserAgent = LibrusConstants.userAgent
        view.navigationDelegate = context.coordinator
        view.load(Coordinator.withHeader(URLRequest(url: LibrusConstants.portalAuthorizeURL)))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode, onError: onError, onLoading: { isLoading = $0 })
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let onCode: (String) -> Void
        let onError: (String) -> Void
        let onLoading: (Bool) -> Void
        private var finished = false

        init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void,
             onLoading: @escaping (Bool) -> Void) {
            self.onCode = onCode
            self.onError = onError
            self.onLoading = onLoading
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            onLoading(true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onLoading(false)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onLoading(false)
        }

        /// The official app's web view sends this header; the portal may expect it.
        static func withHeader(_ request: URLRequest) -> URLRequest {
            var request = request
            request.setValue(LibrusConstants.portalHeader, forHTTPHeaderField: "X-Requested-With")
            return request
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.allow) }
            if handleRedirect(url) { return decisionHandler(.cancel) }

            if url.host?.hasSuffix("portal.librus.pl") == true,
               action.request.httpMethod == "GET",
               action.targetFrame?.isMainFrame == true,
               action.request.value(forHTTPHeaderField: "X-Requested-With") == nil {
                decisionHandler(.cancel)
                webView.load(Coordinator.withHeader(action.request))
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            // A redirect to the custom scheme can surface as a failed navigation instead.
            let failing = (error as NSError).userInfo[NSURLErrorFailingURLStringErrorKey] as? String
            if let failing, let url = URL(string: failing), handleRedirect(url) { return }
            if (error as NSError).code == NSURLErrorCancelled { return }
            onLoading(false)
            if (error as NSError).domain == "WebKitErrorDomain", (error as NSError).code == 102 { return } // frame load interrupted
            onError(error.localizedDescription)
        }

        private func handleRedirect(_ url: URL) -> Bool {
            guard url.absoluteString.hasPrefix(LibrusConstants.portalRedirectURL) else {
                if url.absoluteString.contains("rejected_client") {
                    report("Librus odrzucił identyfikator aplikacji (rejected_client). Ta metoda logowania mogła przestać działać.")
                    return true
                }
                return false
            }
            let items = URLComponents(string: url.absoluteString)?.queryItems ?? []
            if let code = items.first(where: { $0.name == "code" })?.value {
                guard !finished else { return true }
                finished = true
                DispatchQueue.main.async { self.onCode(code) }
            } else if items.contains(where: { $0.name == "command" && $0.value == "close" }) {
                report("Librus ma przerwę techniczną. Spróbuj później.")
            } else {
                report("Nieoczekiwana odpowiedź portalu: \(url.absoluteString)")
            }
            return true
        }

        private func report(_ message: String) {
            DispatchQueue.main.async { self.onError(message) }
        }
    }
}
