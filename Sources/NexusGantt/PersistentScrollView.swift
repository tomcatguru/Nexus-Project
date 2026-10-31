import AppKit
import SwiftUI

enum ScrollDocumentPointerEvent {
    case moved(CGPoint)
    case exited
    case down(CGPoint)
    case dragged(location: CGPoint, translation: CGSize)
    case up(CGPoint)
}

/// An AppKit-backed scroll view that exposes the two pieces of viewport state
/// SwiftUI's ScrollView does not provide on macOS 14: pixel offset and magnification.
@MainActor
struct PersistentScrollView<Content: View>: NSViewRepresentable {
    @Binding var magnification: Double
    @Binding var contentOffset: CGPoint
    let minimumMagnification: Double
    let onPointerEvent: (ScrollDocumentPointerEvent) -> Void
    @ViewBuilder let content: () -> Content

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.allowsMagnification = true
        scrollView.minMagnification = CGFloat(minimumMagnification)
        scrollView.maxMagnification = 2
        scrollView.contentView.postsBoundsChangedNotifications = true

        let hostingView = PointerTrackingHostingView(rootView: content())
        hostingView.onPointerEvent = onPointerEvent
        hostingView.isFlipped = true
        hostingView.frame = CGRect(origin: .zero, size: hostingView.fittingSize)
        scrollView.documentView = hostingView
        scrollView.layoutSubtreeIfNeeded()

        context.coordinator.connect(to: scrollView)
        context.coordinator.restoreViewport()
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let hostingView = scrollView.documentView as? PointerTrackingHostingView<Content> else { return }

        hostingView.onPointerEvent = onPointerEvent
        hostingView.rootView = content()
        hostingView.invalidateIntrinsicContentSize()
        let fittingSize = hostingView.fittingSize
        if hostingView.frame.size != fittingSize {
            hostingView.frame = CGRect(origin: .zero, size: fittingSize)
        }

        scrollView.minMagnification = min(
            max(CGFloat(minimumMagnification), 0.65),
            scrollView.maxMagnification
        )
        let targetZoom = min(max(CGFloat(magnification), scrollView.minMagnification), scrollView.maxMagnification)
        if abs(magnification - Double(targetZoom)) > 0.001 {
            context.coordinator.synchronizeMagnification(to: Double(targetZoom))
        }
        let zoomChanged = abs(scrollView.magnification - targetZoom) > 0.001
        if zoomChanged {
            context.coordinator.isApplyingState = true
            // Toolbar zoom keeps the current document origin stable. Trackpad
            // magnification still uses AppKit's native cursor-centered behavior.
            scrollView.magnification = targetZoom
            context.coordinator.isApplyingState = false
        }

        let targetOffset = context.coordinator.constrainedOffset(contentOffset, in: scrollView)
        if targetOffset.distance(to: contentOffset) > 0.5 {
            context.coordinator.synchronizeContentOffset(to: targetOffset)
        }
        if scrollView.contentView.bounds.origin.distance(to: targetOffset) > 0.5 {
            context.coordinator.isApplyingState = true
            scrollView.contentView.scroll(to: targetOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            context.coordinator.isApplyingState = false
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.disconnect()
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: PersistentScrollView
        var isApplyingState = false
        private weak var scrollView: NSScrollView?

        init(parent: PersistentScrollView) {
            self.parent = parent
        }

        func connect(to scrollView: NSScrollView) {
            self.scrollView = scrollView
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(didEndMagnify(_:)),
                name: NSScrollView.didEndLiveMagnifyNotification,
                object: scrollView
            )
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard !isApplyingState, let scrollView else { return }
            let origin = scrollView.contentView.bounds.origin
            if parent.contentOffset != origin {
                parent.contentOffset = origin
            }
        }

        @objc private func didEndMagnify(_ notification: Notification) {
            guard !isApplyingState, let scrollView else { return }
            let zoom = Double(scrollView.magnification)
            if abs(parent.magnification - zoom) > 0.001 {
                parent.magnification = zoom
            }
        }

        func restoreViewport() {
            guard let scrollView else { return }
            isApplyingState = true
            let zoom = min(max(CGFloat(parent.magnification), scrollView.minMagnification), scrollView.maxMagnification)
            scrollView.magnification = zoom
            let offset = constrainedOffset(parent.contentOffset, in: scrollView)
            scrollView.contentView.scroll(to: offset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingState = false
            if offset.distance(to: parent.contentOffset) > 0.5 {
                synchronizeContentOffset(to: offset)
            }
        }

        func synchronizeMagnification(to value: Double) {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      abs(self.parent.magnification - value) > 0.001 else { return }
                self.parent.magnification = value
            }
        }

        func synchronizeContentOffset(to value: CGPoint) {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.parent.contentOffset.distance(to: value) > 0.5 else { return }
                self.parent.contentOffset = value
            }
        }

        func constrainedOffset(_ offset: CGPoint, in scrollView: NSScrollView) -> CGPoint {
            guard let documentView = scrollView.documentView else { return .zero }
            let visibleSize = scrollView.contentView.bounds.size
            let documentSize = documentView.bounds.size
            return CGPoint(
                x: min(max(offset.x, 0), max(documentSize.width - visibleSize.width, 0)),
                y: min(max(offset.y, 0), max(documentSize.height - visibleSize.height, 0))
            )
        }

        func disconnect() {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

@MainActor
private final class PointerTrackingHostingView<Content: View>: NSHostingView<Content> {
    var onPointerEvent: (ScrollDocumentPointerEvent) -> Void = { _ in }
    private var pointerTrackingArea: NSTrackingArea?
    private var mouseDownPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let pointerTrackingArea {
            removeTrackingArea(pointerTrackingArea)
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        pointerTrackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        onPointerEvent(.moved(documentPoint(for: event)))
    }

    override func mouseExited(with event: NSEvent) {
        onPointerEvent(.exited)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = documentPoint(for: event)
        mouseDownPoint = point
        onPointerEvent(.down(point))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = documentPoint(for: event)
        let start = mouseDownPoint ?? point
        onPointerEvent(.dragged(
            location: point,
            translation: CGSize(width: point.x - start.x, height: point.y - start.y)
        ))
    }

    override func mouseUp(with event: NSEvent) {
        let point = documentPoint(for: event)
        onPointerEvent(.up(point))
        mouseDownPoint = nil
    }

    private func documentPoint(for event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }
}

private extension CGPoint {
    func distance(to other: CGPoint) -> CGFloat {
        hypot(x - other.x, y - other.y)
    }
}
