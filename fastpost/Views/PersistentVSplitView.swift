import AppKit
import SwiftUI

struct PersistentVSplitView<Top: View, Bottom: View>: NSViewRepresentable {
    @Binding var bottomHeight: Double
    var minTopHeight: CGFloat = 260
    var minBottomHeight: CGFloat = 180
    var top: Top
    var bottom: Bottom

    init(
        bottomHeight: Binding<Double>,
        minTopHeight: CGFloat = 260,
        minBottomHeight: CGFloat = 180,
        @ViewBuilder top: () -> Top,
        @ViewBuilder bottom: () -> Bottom
    ) {
        self._bottomHeight = bottomHeight
        self.minTopHeight = minTopHeight
        self.minBottomHeight = minBottomHeight
        self.top = top()
        self.bottom = bottom()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(bottomHeight: $bottomHeight, minTopHeight: minTopHeight, minBottomHeight: minBottomHeight)
    }

    func makeNSView(context: Context) -> RestoringSplitView {
        let splitView = RestoringSplitView()
        splitView.isVertical = false
        splitView.dividerStyle = .thin
        splitView.delegate = context.coordinator

        let topHost = FillingHostingView(rootView: top)
        topHost.sizingOptions = []
        let bottomHost = FillingHostingView(rootView: bottom)
        bottomHost.sizingOptions = []

        splitView.addArrangedSubview(topHost)
        splitView.addArrangedSubview(bottomHost)
        splitView.setHoldingPriority(NSLayoutConstraint.Priority(NSLayoutConstraint.Priority.defaultLow.rawValue - 1), forSubviewAt: 0)
        splitView.setHoldingPriority(.defaultHigh, forSubviewAt: 1)

        context.coordinator.topHost = topHost
        context.coordinator.bottomHost = bottomHost
        splitView.onLayout = { [weak coordinator = context.coordinator] view in
            coordinator?.restoreIfNeeded(view)
        }
        return splitView
    }

    func updateNSView(_ splitView: RestoringSplitView, context: Context) {
        context.coordinator.bottomHeight = $bottomHeight
        context.coordinator.minTopHeight = minTopHeight
        context.coordinator.minBottomHeight = minBottomHeight
        context.coordinator.topHost?.rootView = top
        context.coordinator.bottomHost?.rootView = bottom
        context.coordinator.restoreIfNeeded(splitView)
    }

    final class Coordinator: NSObject, NSSplitViewDelegate {
        var bottomHeight: Binding<Double>
        var minTopHeight: CGFloat
        var minBottomHeight: CGFloat
        var topHost: FillingHostingView<Top>?
        var bottomHost: FillingHostingView<Bottom>?
        private var isApplying = false
        private var didRestore = false

        init(bottomHeight: Binding<Double>, minTopHeight: CGFloat, minBottomHeight: CGFloat) {
            self.bottomHeight = bottomHeight
            self.minTopHeight = minTopHeight
            self.minBottomHeight = minBottomHeight
        }

        func restoreIfNeeded(_ splitView: NSSplitView) {
            guard !didRestore, !splitView.inLiveResize else { return }
            guard splitView.bounds.height > 0, splitView.arrangedSubviews.count == 2 else { return }
            let target = CGFloat(bottomHeight.wrappedValue)
            guard target > 0 else { return }
            isApplying = true
            let position = max(0, splitView.bounds.height - target - splitView.dividerThickness)
            splitView.setPosition(position, ofDividerAt: 0)
            isApplying = false
            didRestore = true
        }

        func splitViewDidResizeSubviews(_ notification: Notification) {
            guard !isApplying, let splitView = notification.object as? NSSplitView, splitView.arrangedSubviews.count == 2 else {
                return
            }
            let height = splitView.arrangedSubviews[1].frame.height
            guard height > 1, abs(height - bottomHeight.wrappedValue) > 1 else { return }
            bottomHeight.wrappedValue = height
        }

        func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            minTopHeight
        }

        func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
            splitView.bounds.height - minBottomHeight - splitView.dividerThickness
        }
    }
}

final class RestoringSplitView: NSSplitView {
    var onLayout: ((NSSplitView) -> Void)?

    override func layout() {
        super.layout()
        onLayout?(self)
    }
}

final class FillingHostingView<Content: View>: NSHostingView<Content> {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
