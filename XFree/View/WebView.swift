import SwiftUI
import WebKit
import AppKit

/// Per-column WKWebView cache. SwiftUI rebuilds the view tree on compact toggle and frame
/// changes; without an external cache each rebuild creates a fresh WKWebView and reloads the
/// page. We key by stable column id and let the same WKWebView ride through layout swaps.
///
/// Tracks `isXcom` per entry so sign-out can evict only x.com WebViews and leave custom
/// columns (Reddit, HN, etc.) intact across the logout transition.
final class WebViewCache {
    static let shared = WebViewCache()

    private struct Entry {
        let webView: WKWebView
        let isXcom: Bool
    }

    private var cache: [String: Entry] = [:]

    func webView(forKey key: String, isXcom: Bool, factory: () -> WKWebView) -> WKWebView {
        if let entry = cache[key] { return entry.webView }
        let fresh = factory()
        cache[key] = Entry(webView: fresh, isXcom: isXcom)
        return fresh
    }

    func evict(_ key: String) {
        cache[key]?.webView.stopLoading()
        cache.removeValue(forKey: key)
    }

    func evictXcom() {
        for (key, entry) in cache where entry.isXcom {
            entry.webView.stopLoading()
            cache.removeValue(forKey: key)
        }
    }
}

struct WebView: NSViewRepresentable {
    typealias NSViewType = WKWebView

    @Binding var isLoading: Bool
    @Binding var url: URL
    @Binding var alertMessage: String?
    @Binding var messageFromWebView: String?
    @Binding var scriptExecutionRequest: String?

    @AppStorage("pageZoom") var pageZoom: Double = 1

    var isDarkMode: Bool = false
    var refreshSwitch: Bool = false
    var configuration: WKWebViewConfiguration? = nil
    var cacheKey: String? = nil
    var cacheIsXcom: Bool = false

    func makeNSView(context: Context) -> WKWebView {
        if let cacheKey {
            let webView = WebViewCache.shared.webView(forKey: cacheKey, isXcom: cacheIsXcom) {
                makeFreshWebView(context: context)
            }
            // Cached view is being parented to a new SwiftUI host; detach from the old one first
            // and rebind delegates/handler to the freshly created Coordinator.
            webView.removeFromSuperview()
            attachCoordinator(webView, context: context)
            return webView
        }
        return makeFreshWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let expectedUnderPageColor: NSColor = isDarkMode ? .black : .white
        if webView.underPageBackgroundColor != expectedUnderPageColor {
            webView.underPageBackgroundColor = expectedUnderPageColor
        }
        // Reload only when the caller swapped the URL out from under us (e.g. column URL edited
        // in Settings). Don't react to webView.url drifting via in-page SPA navigation — that's
        // the user clicking around on x.com, not a request to reload.
        if context.coordinator.lastRequestedUrl != url {
            context.coordinator.lastRequestedUrl = url
            webView.load(URLRequest(url: url))
        }
        if refreshSwitch != context.coordinator.refreshSwitch {
            webView.load(URLRequest(url: url))
            context.coordinator.refreshSwitch = refreshSwitch
        } else if let script = scriptExecutionRequest {
            webView.evaluateJavaScript(script)
            DispatchQueue.main.async {
                self.scriptExecutionRequest = nil
            }
        }
        if webView.pageZoom != pageZoom {
            webView.pageZoom = CGFloat(pageZoom)
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(owner: self)
    }

    private func makeFreshWebView(context: Context) -> WKWebView {
        let webView: WKWebView
        if let configuration {
            webView = HorizontalScrollSwallowingWebView(frame: .zero, configuration: configuration)
        } else {
            webView = HorizontalScrollSwallowingWebView()
        }
        // Pretend Safari because 𝕏 bans the user agent of WebView
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        webView.underPageBackgroundColor = isDarkMode ? .black : .white
        attachCoordinator(webView, context: context)
        NightModeCookie.writeFireAndForget(isDark: isDarkMode)
        webView.load(URLRequest(url: url))
        return webView
    }

    private func attachCoordinator(_ webView: WKWebView, context: Context) {
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        let ucc = webView.configuration.userContentController
        ucc.removeAllScriptMessageHandlers()
        ucc.add(context.coordinator, name: WebViewConfigurations.handlerName)
    }
}

/// WKWebView subclass that forwards horizontal-dominant scroll events up the responder chain
/// instead of letting x.com handle them (it hijacks horizontal swipes to switch For you ↔ Following).
/// Forwarding lets an outer SwiftUI ScrollView receive the event when columns overflow,
/// while preventing in-page tab switching either way.
private final class HorizontalScrollSwallowingWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            nextResponder?.scrollWheel(with: event)
            return
        }
        super.scrollWheel(with: event)
    }
}

class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let owner: WebView
    var lastRequestedUrl: URL
    var refreshSwitch: Bool

    init(owner: WebView) {
        self.owner = owner
        self.lastRequestedUrl = owner.url
        self.refreshSwitch = false
        super.init()
    }

    // MARK: WKNavigationDelegate
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        owner.isLoading = true
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner.isLoading = false
        if let script = owner.scriptExecutionRequest {
            webView.evaluateJavaScript(script)
            owner.scriptExecutionRequest = nil
        }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if case .linkActivated = navigationAction.navigationType, let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: WKUIDelegate
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        owner.alertMessage = message
        print("🚨️ \(message)")
    }

    // MARK: WKScriptMessageHandler
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == WebViewConfigurations.handlerName else { return }
        print("[WKScriptMessage] \(message.body)")
        owner.messageFromWebView = message.body as? String
    }
}
