import SwiftUI
import WebKit

struct ContentView: View {
    @EnvironmentObject var store: AppConfigStore

    @AppStorage("pageZoom") var pageZoom: Double = 1
    @AppStorage("appearance") var appearance: AppearanceMode = .light
    @AppStorage("hideAds") var hideAds: Bool = true
    @AppStorage("compactMode") var compactMode: Bool = false

    @State var isLoading: Bool = false
    @State var isShowingAlert: Bool = false
    @State var alertMessage: String? = nil

    @State var refreshSwitch: Bool = false
    @State var scriptExecutionRequest: String? = nil

    @State var webViewMessage: String? = nil
    @State var loginViewMessage: String? = nil

    @State var homeUrl: URL = URL(string: "https://x.com/home")!
    @State var notificationsUrl: URL = URL(string: "https://x.com/notifications")!
    @State var profileUrl: URL? = nil
    @State var compactPageIndex: Int = 0

    private var isDarkMode: Bool {
        appearance.colorScheme == .dark
    }

    private var backgroundColor: Color {
        isDarkMode ? .black : .white
    }

    private func applyAppearanceChange() {
        let dark = isDarkMode
        Task {
            await NightModeCookie.write(isDark: dark)
            await MainActor.run { refreshSwitch.toggle() }
        }
    }

    @ViewBuilder
    private func makeColumn(
        column: AppConfigStore.Column,
        profileUrl: Binding<URL?>,
        columnWidth: CGFloat
    ) -> some View {
        let width = columnWidth

        let baseConfiguration: [WebViewConfigurations.OnLoadScript] = {
            var scripts: [WebViewConfigurations.OnLoadScript] = [.global]
            if column.isXColumn {
                scripts.append(contentsOf: [.hideSideHeader, .hidePostArea])
            }
            if hideAds {
                scripts.append(.hideAds)
            }
            return scripts
        }()

        let cacheKey = column.id.uuidString

        switch column.type {
        case .forYou:
            WebView(
                isLoading: $isLoading, url: $homeUrl, alertMessage: $alertMessage,
                messageFromWebView: $webViewMessage,
                scriptExecutionRequest: $scriptExecutionRequest,
                isDarkMode: isDarkMode,
                refreshSwitch: refreshSwitch,
                configuration: WebViewConfigurations.makeConfiguration(
                    onLoadScripts: baseConfiguration + [.clickForYouTab]),
                cacheKey: cacheKey
            ).frame(width: width)
        case .following:
            WebView(
                isLoading: $isLoading, url: $homeUrl, alertMessage: $alertMessage,
                messageFromWebView: $webViewMessage,
                scriptExecutionRequest: $scriptExecutionRequest,
                isDarkMode: isDarkMode,
                refreshSwitch: refreshSwitch,
                configuration: WebViewConfigurations.makeConfiguration(
                    onLoadScripts: baseConfiguration + [.clickFollowingTab]),
                cacheKey: cacheKey
            ).frame(width: width)
        case .notifications:
            WebView(
                isLoading: $isLoading, url: $notificationsUrl,
                alertMessage: $alertMessage,
                messageFromWebView: $webViewMessage,
                scriptExecutionRequest: $scriptExecutionRequest,
                isDarkMode: isDarkMode,
                refreshSwitch: refreshSwitch,
                configuration: WebViewConfigurations.makeConfiguration(
                    onLoadScripts: baseConfiguration),
                cacheKey: cacheKey
            ).frame(width: width)
        case .profile:
            if let url = Binding(profileUrl) {
                WebView(
                    isLoading: $isLoading, url: url, alertMessage: $alertMessage,
                    messageFromWebView: $webViewMessage,
                    scriptExecutionRequest: column.isXColumn
                        ? $scriptExecutionRequest : .constant(nil),
                    isDarkMode: isDarkMode,
                    refreshSwitch: refreshSwitch,
                    configuration: WebViewConfigurations.makeConfiguration(
                        onLoadScripts: baseConfiguration),
                    cacheKey: cacheKey
                ).frame(width: width)
            }
        case .custom:
            if let urlString = column.url, let url = URL(string: urlString) {
                WebView(
                    isLoading: $isLoading, url: .constant(url), alertMessage: $alertMessage,
                    messageFromWebView: $webViewMessage,
                    scriptExecutionRequest: $scriptExecutionRequest,
                    isDarkMode: isDarkMode,
                    refreshSwitch: refreshSwitch,
                    configuration: WebViewConfigurations.makeConfiguration(
                        onLoadScripts: baseConfiguration),
                    cacheKey: cacheKey
                ).frame(width: width)
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let columnCount = store.columns.count
            let isCompact = compactMode
            let baseWidth: CGFloat = {
                if isCompact { return geometry.size.width }
                switch store.widthMode {
                case .auto:
                    let computed = geometry.size.width / CGFloat(max(columnCount, 1))
                    return max(computed, AppConfigStore.minColumnWidth)
                case .manual:
                    return CGFloat(store.columnWidth)
                }
            }()
            let dynamicColumnWidth = baseWidth * CGFloat(pageZoom)
            let totalContentWidth = CGFloat(columnCount) * dynamicColumnWidth
            let canScroll = !isCompact && totalContentWidth > geometry.size.width + 0.5

            ZStack {
                Button("+") { pageZoom += 0.2 }
                    .keyboardShortcut("+").opacity(0)
                Button("-") { pageZoom -= 0.2 }
                    .keyboardShortcut("-").opacity(0)
                Button("r") { refreshSwitch.toggle() }
                    .keyboardShortcut("r").opacity(0)

                ForEach(1...9, id: \.self) { num in
                    Button("\(num)") {
                        let target = num - 1
                        if target < store.columns.count {
                            compactPageIndex = target
                        }
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(num)")), modifiers: .command)
                    .opacity(0)
                    .frame(width: 0, height: 0)
                }

                if profileUrl != nil {
                    if isCompact {
                        compactPager(columnWidth: geometry.size.width)
                            .alert(isPresented: $isShowingAlert) {
                                Alert(title: Text(alertMessage ?? ""))
                            }
                    } else {
                        columnsStack(dynamicColumnWidth: dynamicColumnWidth, canScroll: canScroll)
                            .alert(isPresented: $isShowingAlert) {
                                Alert(title: Text(alertMessage ?? ""))
                            }
                    }
                } else {
                    LoginView(
                        isShowingAlert: $isShowingAlert,
                        alertMessage: $alertMessage,
                        loginViewMessage: $loginViewMessage
                    )
                }
            }
            .background(backgroundColor)
            .preferredColorScheme(appearance.colorScheme)
            .onChange(of: appearance) { _ in applyAppearanceChange() }
            .onChange(of: hideAds) { newValue in
                scriptExecutionRequest = newValue
                    ? WebViewConfigurations.hideAds
                    : WebViewConfigurations.showAds
            }
            .onChange(of: loginViewMessage) { handleMessage($0) }
            .onChange(of: webViewMessage) { handleMessage($0) }
            .onChange(of: alertMessage) { isShowingAlert = $0 != nil }
        }
    }

    @ViewBuilder
    private func compactPager(columnWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            PagingScrollView(
                pageCount: store.columns.count,
                pageWidth: columnWidth,
                currentPage: $compactPageIndex
            ) { index in
                let column = store.columns[index]
                makeColumn(
                    column: column,
                    profileUrl: $profileUrl,
                    columnWidth: columnWidth
                )
            }
            .onAppear {
                if compactPageIndex >= store.columns.count {
                    compactPageIndex = defaultCompactPageIndex
                } else if compactPageIndex == 0 {
                    compactPageIndex = defaultCompactPageIndex
                }
            }

            if store.columns.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<store.columns.count, id: \.self) { index in
                        Circle()
                            .frame(width: 6, height: 6)
                            .foregroundStyle(index == compactPageIndex ? Color.primary : Color.primary.opacity(0.25))
                            .onTapGesture { compactPageIndex = index }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var defaultCompactPageIndex: Int {
        if let i = store.columns.firstIndex(where: {
            $0.type == .custom && $0.url == "https://x.com/home"
        }) { return i }
        if let i = store.columns.firstIndex(where: { $0.isXColumn }) { return i }
        return 0
    }

    @ViewBuilder
    private func columnsStack(dynamicColumnWidth: CGFloat, canScroll: Bool) -> some View {
        let stack = HStack(spacing: 0) {
            ForEach(store.columns) { column in
                makeColumn(
                    column: column,
                    profileUrl: $profileUrl,
                    columnWidth: dynamicColumnWidth
                )
            }
        }
        if canScroll {
            ScrollView(.horizontal) { stack }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        } else {
            stack.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func handleMessage(_ raw: String?) {
        guard let raw,
              let data = raw.data(using: .utf8),
              let message = try? JSONDecoder().decode(WebViewMessage.self, from: data)
        else { return }
        switch message.type {
        case .userName:
            if let url = URL(string: "https://x.com/\(message.body)") {
                profileUrl = url
            }
        }
    }
}
