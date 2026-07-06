import SwiftUI
import WebKit

struct SignInWebView: NSViewRepresentable {
    var onSessionKey: (String) -> Void

    // A current desktop Safari UA so the login page doesn't treat us as an embedded browser.
    static let userAgent =
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
        private var popupWindow: NSWindow?
        private var popupWebView: WKWebView?

        init(onSessionKey: @escaping (String) -> Void) { self.onSessionKey = onSessionKey }

        // Open OAuth popups (e.g. "Continue with Google") as a real second window so the
        // window.opener relationship survives and the provider can post the token back.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 650), configuration: configuration)
            popup.customUserAgent = SignInWebView.userAgent
            popup.navigationDelegate = self
            popup.uiDelegate = self

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 650),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false)
            window.title = "Sign in"
            window.contentView = popup
            window.isReleasedWhenClosed = false
            window.center()
            window.makeKeyAndOrderFront(nil)

            popupWindow = window
            popupWebView = popup
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            let window = popupWindow
            popupWindow = nil
            popupWebView = nil
            DispatchQueue.main.async { window?.close() }
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
