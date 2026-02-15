import SwiftUI

enum FeedSwipeAction {
    case openPanel
    case closePanel
    case nextItem
    case previousItem
    case none
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
    @ViewBuilder let videoLayer: () -> VideoLayer
    @ViewBuilder let panelLayer: (_ width: CGFloat) -> PanelLayer

    var body: some View {
        GeometryReader { geo in
            let panelWidth = geo.size.width
            ZStack(alignment: .leading) {
                videoLayer()
                    .offset(x: isPanelOpen ? -panelWidth : 0)
                    .animation(.spring(response: 0.28, dampingFraction: 0.9), value: isPanelOpen)

                panelLayer(panelWidth)
                    .offset(x: geo.size.width - (isPanelOpen ? panelWidth : 0))
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
