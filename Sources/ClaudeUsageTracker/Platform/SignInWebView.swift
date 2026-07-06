import SwiftUI
import WebKit

struct SignInWebView: NSViewRepresentable {
    var onSessionKey: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        context.coordinator.startPolling(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSessionKey: onSessionKey) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let onSessionKey: (String) -> Void
        private var pollTask: Task<Void, Never>?

        init(onSessionKey: @escaping (String) -> Void) { self.onSessionKey = onSessionKey }

        func startPolling(_ webView: WKWebView) {
            pollTask = Task { @MainActor [weak self, weak webView] in
                while !Task.isCancelled {
                    guard let webView else { return }
                    let cookies: [HTTPCookie] = await withCheckedContinuation { cont in
                        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cont.resume(returning: $0) }
                    }
                    if let cookie = cookies.first(where: { $0.name == "sessionKey" }), !cookie.value.isEmpty {
                        self?.onSessionKey(cookie.value)
                        return
                    }
                    try? await Task.sleep(for: .seconds(1.5))
                }
            }
        }

        deinit { pollTask?.cancel() }
    }
}
