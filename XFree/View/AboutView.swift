import SwiftUI
import AppKit

struct AboutView: View {
    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return short == build ? "Version \(short)" : "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
                .resizable()
                .frame(width: 96, height: 96)
                .padding(.top, 28)
                .padding(.bottom, 12)

            Text("X Free")
                .font(.system(size: 22, weight: .semibold))

            Text(versionString)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            HStack(spacing: 0) {
                Text("Forked from ").foregroundStyle(.secondary)
                LinkText("XDeck v2.3", url: "https://github.com/morishin/XDeck/releases/tag/2.3")
                Text(" by ").foregroundStyle(.secondary)
                LinkText("@morishin", url: "https://github.com/morishin")
                Text(" · MIT").foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .padding(.top, 16)

            HStack(spacing: 18) {
                IconLink(asset: "AuthorLogo", url: "https://dbkarashev.com", size: 30)
                IconLink(asset: "GitHubMark", url: "https://github.com/dbkarashev", size: 26)
            }
            .padding(.top, 14)

            Text("Copyright © 2026 Damir Karashev.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 18)
                .padding(.bottom, 28)
        }
        .frame(width: 380)
    }
}

private struct LinkText: View {
    let text: String
    let url: String

    init(_ text: String, url: String) {
        self.text = text
        self.url = url
    }

    var body: some View {
        Text(text)
            .foregroundStyle(.primary)
            .onHover { hover in
                if hover { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }
    }
}

private struct IconLink: View {
    let asset: String
    let url: String
    var size: CGFloat = 26

    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(.primary)
            .onHover { hover in
                if hover { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .onTapGesture {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }
    }
}
