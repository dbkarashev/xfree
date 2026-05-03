import SwiftUI
import WebKit
import AppKit

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

    func makeNSView(context: Context) -> WKWebView {
        let webView: WKWebView
        if let configuration = configuration {
            webView = HorizontalScrollSwallowingWebView(frame: .zero, configuration: configuration)
        } else {
            webView = HorizontalScrollSwallowingWebView()
        }
        // Pretend Safari because 𝕏 bans the user agent of WebView
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Safari/605.1.15"
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.underPageBackgroundColor = isDarkMode ? .black : .white

        NightModeCookie.writeFireAndForget(isDark: isDarkMode)

        let request = URLRequest(url: url)
        webView.load(request)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let expectedUnderPageColor: NSColor = isDarkMode ? .black : .white
        if webView.underPageBackgroundColor != expectedUnderPageColor {
            webView.underPageBackgroundColor = expectedUnderPageColor
        }
        // Reload when caller swapped the URL out from under us (e.g. column URL edited in Settings).
        if context.coordinator.lastRequestedUrl != url {
            context.coordinator.lastRequestedUrl = url
            context.coordinator.lastUrl = url
            webView.load(URLRequest(url: url))
        } else if let current = webView.url, current != context.coordinator.lastUrl {
            context.coordinator.lastUrl = current
            webView.load(URLRequest(url: current))
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
    var lastUrl: URL
    var lastRequestedUrl: URL
    var refreshSwitch: Bool

    init(owner: WebView) {
        self.owner = owner
        self.lastUrl = owner.url
        self.lastRequestedUrl = owner.url
        self.refreshSwitch = false
        super.init()
        owner.configuration?.userContentController.add(self, name: WebViewConfigurations.handlerName)
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
