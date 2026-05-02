import SwiftUI
import AppKit

/// Horizontal NSScrollView that snaps to whole-page boundaries after a swipe,
/// because SwiftUI's `.scrollTargetBehavior(.paging)` is unreliable for trackpad
/// momentum scrolling on macOS.
struct PagingScrollView<Page: View>: NSViewRepresentable {
    let pageCount: Int
    let pageWidth: CGFloat
    @Binding var currentPage: Int
    @ViewBuilder var pageBuilder: (Int) -> Page

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = false
        scrollView.horizontalScrollElasticity = .allowed
        scrollView.verticalScrollElasticity = .none
        scrollView.usesPredominantAxisScrolling = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let hosting = NSHostingView(rootView: stackContent)
        hosting.translatesAutoresizingMaskIntoConstraints = true
        hosting.autoresizingMask = [.height]
        hosting.frame = NSRect(
            x: 0, y: 0,
            width: pageWidth * CGFloat(pageCount),
            height: max(scrollView.bounds.height, 1)
        )
        scrollView.documentView = hosting

        context.coordinator.attach(
            scrollView: scrollView,
            hosting: hosting,
            parent: self
        )

        DispatchQueue.main.async {
            context.coordinator.scrollToPage(currentPage, animated: false)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self

        if let hosting = scrollView.documentView as? NSHostingView<AnyView> {
            hosting.rootView = stackContent
            let height = scrollView.contentView.bounds.height
            hosting.frame.size = NSSize(
                width: pageWidth * CGFloat(pageCount),
                height: max(height, hosting.frame.height)
            )
        }

        if !context.coordinator.isUserScrolling {
            let expected = CGFloat(currentPage) * pageWidth
            let actual = scrollView.contentView.bounds.origin.x
            if abs(expected - actual) > 0.5 {
                context.coordinator.scrollToPage(currentPage, animated: true)
            }
        }
    }

    private var stackContent: AnyView {
        AnyView(
            HStack(spacing: 0) {
                ForEach(0..<pageCount, id: \.self) { index in
                    pageBuilder(index)
                        .frame(width: pageWidth)
                }
            }
        )
    }

    final class Coordinator: NSObject {
        var parent: PagingScrollView?
        weak var scrollView: NSScrollView?
        weak var hosting: NSHostingView<AnyView>?
        var isUserScrolling = false

        func attach(scrollView: NSScrollView, hosting: NSHostingView<AnyView>, parent: PagingScrollView) {
            self.scrollView = scrollView
            self.hosting = hosting
            self.parent = parent

            let nc = NotificationCenter.default
            nc.addObserver(
                self, selector: #selector(willStartLiveScroll(_:)),
                name: NSScrollView.willStartLiveScrollNotification, object: scrollView
            )
            nc.addObserver(
                self, selector: #selector(didEndLiveScroll(_:)),
                name: NSScrollView.didEndLiveScrollNotification, object: scrollView
            )
        }

        @objc private func willStartLiveScroll(_ note: Notification) {
            isUserScrolling = true
        }

        @objc private func didEndLiveScroll(_ note: Notification) {
            isUserScrolling = false
            guard let parent, parent.pageWidth > 0, parent.pageCount > 0 else { return }
            let offset = scrollView?.contentView.bounds.origin.x ?? 0
            let nearest = max(0, min(parent.pageCount - 1, Int((offset / parent.pageWidth).rounded())))
            scrollToPage(nearest, animated: true)
            if parent.currentPage != nearest {
                DispatchQueue.main.async { [weak self] in
                    self?.parent?.currentPage = nearest
                }
            }
        }

        func scrollToPage(_ page: Int, animated: Bool) {
            guard let documentView = scrollView?.documentView,
                  let parent, parent.pageWidth > 0 else { return }
            let target = NSPoint(x: CGFloat(page) * parent.pageWidth, y: 0)
            if animated {
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.25
                    ctx.allowsImplicitAnimation = true
                    documentView.scroll(target)
                }
            } else {
                documentView.scroll(target)
            }
        }
    }
}
