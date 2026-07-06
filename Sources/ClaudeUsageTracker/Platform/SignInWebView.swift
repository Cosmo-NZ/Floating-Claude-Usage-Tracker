import SwiftUI
import WebKit

struct SignInWebView: NSViewRepresentable {
    var onSessionKey: (String) -> Void

    // A current desktop Safari UA so the login page doesn't treat us as an embedded browser.
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.customUserAgent = Self.userAgent
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: URL(string: "https://claude.ai/login")!))
        context.coordinator.startPolling(webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSessionKey: onSessionKey) }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let onSessionKey: (String) -> Void
        private var pollTask: Task<Void, Never>?

        init(onSessionKey: @escaping (String) -> Void) { self.onSessionKey = onSessionKey }

        // Handle popup windows (e.g. "Continue with Google") by loading them in the same web view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

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
