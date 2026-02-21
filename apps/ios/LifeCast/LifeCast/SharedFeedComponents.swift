import SwiftUI
import AVFoundation
import UIKit

let appBottomBarHeight: CGFloat = 50

enum FeedSwipeAction {
    case openPanel
    case closePanel
    case nextItem
    case previousItem
    case none
}

enum VerticalFeedMotionDirection {
    case next
    case previous

    var transition: AnyTransition {
        switch self {
        case .next:
            return .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
        case .previous:
            return .asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom))
        }
    }
}

func resolveFeedSwipeAction(
    dx: CGFloat,
    dy: CGFloat,
    isPanelOpen: Bool,
    canMoveNext: Bool,
    canMovePrevious: Bool,
    panelVerticalThreshold: CGFloat = 36,
    gestureThreshold: CGFloat = 50
) -> FeedSwipeAction {
    if isPanelOpen && abs(dy) > panelVerticalThreshold {
        if dy < 0 {
            return canMoveNext ? .nextItem : .closePanel
        }
        return canMovePrevious ? .previousItem : .closePanel
    }

    if abs(dx) > abs(dy) {
        if dx < -gestureThreshold { return .openPanel }
        if dx > gestureThreshold { return .closePanel }
        return .none
    }

    if dy < -gestureThreshold { return .nextItem }
    if dy > gestureThreshold { return .previousItem }
    return .none
}

struct SlidingFeedPanelLayer<VideoLayer: View, PanelLayer: View>: View {
    let isPanelOpen: Bool
    let cornerRadius: CGFloat
    let dragOffsetX: CGFloat
    @ViewBuilder let videoLayer: () -> VideoLayer
    @ViewBuilder let panelLayer: (_ width: CGFloat) -> PanelLayer

    init(
        isPanelOpen: Bool,
        cornerRadius: CGFloat,
        dragOffsetX: CGFloat = 0,
        @ViewBuilder videoLayer: @escaping () -> VideoLayer,
        @ViewBuilder panelLayer: @escaping (_ width: CGFloat) -> PanelLayer
    ) {
        self.isPanelOpen = isPanelOpen
        self.cornerRadius = cornerRadius
        self.dragOffsetX = dragOffsetX
        self.videoLayer = videoLayer
        self.panelLayer = panelLayer
    }

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width
            let clampedDrag: CGFloat = {
                if isPanelOpen {
                    return min(max(dragOffsetX, 0), panelWidth)
                }
                return max(min(dragOffsetX, 0), -panelWidth)
            }()
            ZStack(alignment: .leading) {
                videoLayer()
                    .offset(x: (isPanelOpen ? -panelWidth : 0) + clampedDrag)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isPanelOpen)

                panelLayer(panelWidth)
                    .offset(x: geo.size.width - (isPanelOpen ? panelWidth : 0) + clampedDrag)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isPanelOpen)
            }
            .if(cornerRadius > 0) { view in
                view.clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }
        }
    }
}

struct FeedPageIndicatorDots: View {
    let currentIndex: Int
    let totalCount: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(totalCount, 1), id: \.self) { idx in
                Circle()
                    .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.28))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

struct InteractiveHorizontalPager<Page: View>: View {
    let pageCount: Int
    @Binding var currentIndex: Int
    let onSwipeBeyondLeadingEdge: (() -> Void)?
    let onLeadingEdgeDragChanged: ((CGFloat) -> Void)?
    @ViewBuilder let page: (_ index: Int) -> Page

    @State private var dragTranslation: CGFloat = 0
    @State private var isHorizontalDragging = false

    init(
        pageCount: Int,
        currentIndex: Binding<Int>,
        onSwipeBeyondLeadingEdge: (() -> Void)? = nil,
        onLeadingEdgeDragChanged: ((CGFloat) -> Void)? = nil,
        @ViewBuilder page: @escaping (_ index: Int) -> Page
    ) {
        self.pageCount = pageCount
        self._currentIndex = currentIndex
        self.onSwipeBeyondLeadingEdge = onSwipeBeyondLeadingEdge
        self.onLeadingEdgeDragChanged = onLeadingEdgeDragChanged
        self.page = page
    }

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            HStack(spacing: 0) {
                ForEach(0..<max(pageCount, 1), id: \.self) { idx in
                    page(idx)
                        .frame(width: width, alignment: .topLeading)
                }
            }
            .offset(x: (-CGFloat(currentIndex) * width) + dragTranslation)
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        if abs(dx) > abs(dy) {
                            isHorizontalDragging = true
                            if currentIndex == 0, dx > 0 {
                                // Keep page content fixed and move the whole panel layer only.
                                dragTranslation = 0
                                onLeadingEdgeDragChanged?(dx)
                            } else {
                                dragTranslation = dx
                                onLeadingEdgeDragChanged?(0)
                            }
                        }
                    }
                    .onEnded { value in
                        let dx = value.translation.width
                        let dy = value.translation.height
                        guard isHorizontalDragging, abs(dx) > abs(dy) else {
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
                                dragTranslation = 0
                            }
                            onLeadingEdgeDragChanged?(0)
                            isHorizontalDragging = false
                            return
                        }
                        let threshold = min(max(width * 0.18, 40), 120)
                        let current = currentIndex
                        var next = current
                        var handledLeadingEdgeClose = false
                        if dx < -threshold {
                            next = min(current + 1, pageCount - 1)
                        } else if dx > threshold {
                            if current == 0 {
                                onSwipeBeyondLeadingEdge?()
                                handledLeadingEdgeClose = true
                            }
                            next = max(current - 1, 0)
                        }

                        if handledLeadingEdgeClose {
                            // Parent close animation uses the last drag offset and finishes smoothly.
                            isHorizontalDragging = false
                            return
                        }

                        onLeadingEdgeDragChanged?(0)
                        if next != current {
                            let targetDrag = next > current ? -width : width
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.92)) {
                                dragTranslation = targetDrag
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                                currentIndex = next
                                dragTranslation = 0
                                isHorizontalDragging = false
                            }
                        } else {
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.9)) {
                                dragTranslation = 0
                            }
                            isHorizontalDragging = false
                        }
                    }
            )
        }
        .clipped()
    }
}

struct InteractiveVerticalFeedPager<Item: Identifiable, ItemView: View>: View {
    let items: [Item]
    @Binding var currentIndex: Int
    let verticalDragDisabled: Bool
    let allowHorizontalChildDrag: Bool
    let horizontalActionExclusionBottomInset: CGFloat
    let onWillMove: () -> Void
    let onDidMove: () -> Void
    let onHorizontalDragChanged: (CGFloat) -> Void
    let onNonVerticalEnded: (DragGesture.Value) -> Void
    @ViewBuilder let content: (_ item: Item, _ isActive: Bool) -> ItemView

    @State private var dragOffset: CGFloat = 0
    @State private var dragDirection: Int = 0
    @State private var containerHeight: CGFloat = 0

    init(
        items: [Item],
        currentIndex: Binding<Int>,
        verticalDragDisabled: Bool,
        allowHorizontalChildDrag: Bool,
        horizontalActionExclusionBottomInset: CGFloat,
        onWillMove: @escaping () -> Void,
        onDidMove: @escaping () -> Void,
        onHorizontalDragChanged: @escaping (CGFloat) -> Void = { _ in },
        onNonVerticalEnded: @escaping (DragGesture.Value) -> Void,
        @ViewBuilder content: @escaping (_ item: Item, _ isActive: Bool) -> ItemView
    ) {
        self.items = items
        self._currentIndex = currentIndex
        self.verticalDragDisabled = verticalDragDisabled
        self.allowHorizontalChildDrag = allowHorizontalChildDrag
        self.horizontalActionExclusionBottomInset = horizontalActionExclusionBottomInset
        self.onWillMove = onWillMove
        self.onDidMove = onDidMove
        self.onHorizontalDragChanged = onHorizontalDragChanged
        self.onNonVerticalEnded = onNonVerticalEnded
        self.content = content
    }

    private var currentItem: Item? {
        guard currentIndex >= 0, currentIndex < items.count else { return nil }
        return items[currentIndex]
    }

    private var neighborItem: Item? {
        guard dragDirection != 0 else { return nil }
        let neighbor = currentIndex + (dragDirection < 0 ? 1 : -1)
        guard neighbor >= 0, neighbor < items.count else { return nil }
        return items[neighbor]
    }

    var body: some View {
        GeometryReader { geo in
            let dragGesture = DragGesture(minimumDistance: 8)
                .onChanged { value in
                    handleDragChanged(value)
                }
                .onEnded { value in
                    handleDragEnded(value)
                }

            let pagerContent = ZStack {
                if let neighbor = neighborItem {
                    content(neighbor, false)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.black)
                        .offset(y: dragDirection < 0
                            ? geo.size.height + dragOffset
                            : -geo.size.height + dragOffset
                        )
                }

                if let current = currentItem {
                    content(current, true)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Color.black)
                        .offset(y: dragOffset)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .onAppear {
                containerHeight = geo.size.height
            }
            .onChange(of: geo.size.height) { _, newValue in
                containerHeight = newValue
            }

            if allowHorizontalChildDrag {
                pagerContent
                    .simultaneousGesture(dragGesture)
            } else {
                pagerContent
                    .highPriorityGesture(dragGesture)
            }
        }
    }

    private func handleDragChanged(_ value: DragGesture.Value) {
        guard !verticalDragDisabled else { return }

        let dx = value.translation.width
        let dy = value.translation.height
        if abs(dx) > abs(dy) {
            onHorizontalDragChanged(dx)
            return
        }
        guard abs(dy) > abs(dx) else { return }

        if dy < 0, currentIndex < items.count - 1 {
            dragDirection = -1
            dragOffset = max(dy, -containerHeight)
        } else if dy > 0, currentIndex > 0 {
            dragDirection = 1
            dragOffset = min(dy, containerHeight)
        }
    }

    private func handleDragEnded(_ value: DragGesture.Value) {
        onHorizontalDragChanged(0)
        guard dragDirection != 0 else {
            let startedInBottomExclusionZone =
                horizontalActionExclusionBottomInset > 0 &&
                value.startLocation.y >= (containerHeight - horizontalActionExclusionBottomInset)
            let isHorizontal = abs(value.translation.width) > abs(value.translation.height)
            if startedInBottomExclusionZone && isHorizontal {
                return
            }
            onNonVerticalEnded(value)
            return
        }

        let direction = dragDirection
        let threshold = min(140, max(70, containerHeight * 0.18))
        let shouldAdvance = abs(dragOffset) > threshold

        guard shouldAdvance else {
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                dragOffset = 0
            }
            dragDirection = 0
            return
        }

        let targetOffset = direction < 0 ? -containerHeight : containerHeight
        onWillMove()
        withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.92)) {
            dragOffset = targetOffset
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            currentIndex += (direction < 0 ? 1 : -1)
            dragOffset = 0
            dragDirection = 0
            onDidMove()
        }
    }
}

struct FeedPlaybackScrubber: View {
    let progress: Double
    let onScrubBegan: () -> Void
    let onScrubChanged: (Double) -> Void
    let onScrubEnded: (Double) -> Void

    private func clamped(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    var body: some View {
        GeometryReader { geo in
            let ratio = clamped(progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 1)

                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * ratio, height: 1)

                Circle()
                    .fill(Color.white)
                    .frame(width: 7, height: 7)
                    .offset(x: max(0, geo.size.width * ratio - 3.5))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let next = clamped(value.location.x / max(geo.size.width, 1))
                        onScrubBegan()
                        onScrubChanged(next)
                    }
                    .onEnded { value in
                        let next = clamped(value.location.x / max(geo.size.width, 1))
                        onScrubEnded(next)
                    }
            )
        }
        .frame(height: 10)
    }
}

struct FillVideoPlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        if uiView.playerLayer.player !== player {
            uiView.playerLayer.player = player
        }
    }
}

final class PlayerContainerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }
}

private extension View {
    @ViewBuilder
    func `if`<Transformed: View>(_ condition: Bool, transform: (Self) -> Transformed) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
