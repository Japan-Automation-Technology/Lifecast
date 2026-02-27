import SwiftUI
import AVFoundation
import UIKit

let appBottomBarHeight: CGFloat = 50
let feedPanelTopPadding: CGFloat = 132

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

struct FeedPrimaryActionButton: View {
    let title: String
    let isChecked: Bool
    let isNeutral: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if !isNeutral && isChecked {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var foregroundColor: Color {
        if isNeutral || isChecked {
            return Color.black.opacity(0.9)
        }
        return Color.white
    }

    private var backgroundColor: Color {
        if isNeutral || isChecked {
            return Color.white.opacity(0.72)
        }
        return Color.green.opacity(0.92)
    }
}

struct FeedMetricButton: View {
    let icon: String
    let value: Int
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            FeedMetricView(icon: icon, value: value)
        }
        .foregroundStyle(isActive ? Color.pink : Color.white)
    }
}

struct FeedMetricView: View {
    let icon: String
    let value: Int
    let labelOverride: String?

    init(icon: String, value: Int, labelOverride: String? = nil) {
        self.icon = icon
        self.value = value
        self.labelOverride = labelOverride
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
            Text(labelOverride ?? feedShortCount(value))
                .font(.caption)
        }
    }
}

struct FeedCreatorAvatarView: View {
    let urlString: String?
    let username: String

    var body: some View {
        let normalized = urlString?.trimmingCharacters(in: .whitespacesAndNewlines)
        let validURL = (normalized?.isEmpty == false) ? URL(string: normalized ?? "") : nil
        return Group {
            if let url = validURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Circle().fill(Color.white.opacity(0.2))
                    }
                }
            } else {
                Circle().fill(Color.white.opacity(0.2))
            }
        }
        .frame(width: 38, height: 38)
        .overlay {
            if validURL == nil {
                Text(String(username.prefix(1)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
    }
}

struct FeedFundingMetaView: View {
    let project: FeedProjectSummary

    var body: some View {
        let percentRaw = Double(project.fundedAmountMinor) / Double(project.goalAmountMinor)
        let percent = Int(percentRaw * 100)

        return VStack(alignment: .leading, spacing: 6) {
            Text("\(project.remainingDays)d left · From \(feedFormatJPY(project.minPlanPriceMinor))")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.9))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.2))
                    RoundedRectangle(cornerRadius: 6)
                        .fill(fundingProgressTint(percentRaw))
                        .frame(width: geo.size.width * CGFloat(min(percentRaw, 1)))
                }
            }
            .frame(height: 10)

            Text("\(percent)% (\(feedFormatJPY(project.fundedAmountMinor)) / \(feedFormatJPY(project.goalAmountMinor)))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: 280)
    }
}

struct FeedProjectPanelBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.08, blue: 0.14),
                    Color(red: 0.06, green: 0.14, blue: 0.2),
                    Color(red: 0.09, green: 0.09, blue: 0.14)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color.cyan.opacity(0.24),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )
            RadialGradient(
                colors: [
                    Color.indigo.opacity(0.2),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 30,
                endRadius: 440
            )
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.18)
        }
    }
}

struct FeedPanelSectionCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 8)
    }
}

struct FeedProjectOverviewPanelContentView: View {
    let project: FeedProjectSummary
    let detail: MyProjectResult?
    let isLoading: Bool

    var body: some View {
        FeedPanelSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                if let detail {
                    FeedProjectOverviewImageView(detail: detail, fallbackThumbnailURL: project.thumbnailURL)
                    Text(detail.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let subtitle = detail.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.92))
                    }
                    Text((detail.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (detail.description ?? "") : "-")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.96))
                        .padding(.top, 4)
                    Text("Funded: \(feedFormatJPY(detail.funded_amount_minor)) / \(feedFormatJPY(detail.goal_amount_minor))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Supporters: \(detail.supporter_count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Period: \(feedFormatDate(detail.created_at)) ~ \(feedFormatDate(detail.deadline_at))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Status: \(detail.status)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                } else if isLoading {
                    ProgressView("Loading project...")
                        .tint(.white)
                        .foregroundStyle(.white.opacity(0.82))
                } else {
                    if let thumbnail = project.thumbnailURL, let url = URL(string: thumbnail) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                Rectangle().fill(Color.secondary.opacity(0.12))
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Rectangle().fill(Color.secondary.opacity(0.12))
                            @unknown default:
                                Rectangle().fill(Color.secondary.opacity(0.12))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 172)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    Text(project.caption)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.96))
                    Text("-")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(.top, 4)
                    Text("Funded: \(feedFormatJPY(project.fundedAmountMinor))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Supporters: -")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Period: -")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
    }
}

struct FeedPlanPanelContentView: View {
    let plan: ProjectPlanResult

    var body: some View {
        FeedPanelSectionCard {
            VStack(alignment: .leading, spacing: 10) {
                if let raw = plan.image_url, let url = URL(string: raw) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.secondary.opacity(0.12))
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Rectangle().fill(Color.secondary.opacity(0.12))
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.12))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 148)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(plan.name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("\(plan.price_minor.formatted()) \(plan.currency)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(red: 0.58, green: 1.0, blue: 0.86))
                Text(plan.reward_summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : plan.reward_summary)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.96))
                Text((plan.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (plan.description ?? "") : "-")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.86))
                    .padding(.top, 4)
            }
        }
    }
}

struct FeedProjectOverviewImageView: View {
    let detail: MyProjectResult
    let fallbackThumbnailURL: String?

    var body: some View {
        let detailImage = (detail.image_urls?.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            ?? detail.image_url
        if let raw = detailImage, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(Color.secondary.opacity(0.12))
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(Color.secondary.opacity(0.12))
                @unknown default:
                    Rectangle().fill(Color.secondary.opacity(0.12))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 172)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let thumb = fallbackThumbnailURL, let url = URL(string: thumb) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(Color.secondary.opacity(0.12))
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(Color.secondary.opacity(0.12))
                @unknown default:
                    Rectangle().fill(Color.secondary.opacity(0.12))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 172)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

struct FeedActionSheetRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    let destructive: Bool
    let action: () -> Void

    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(destructive ? Color.red : Color.primary)
                    .frame(width: 28, height: 28)
                    .background((destructive ? Color.red : Color.primary).opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: subtitle == nil ? 0 : 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(destructive ? Color.red : Color.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

func feedFormatJPY(_ amountMinor: Int) -> String {
    NumberFormatterProvider.jpy.string(from: NSNumber(value: Double(amountMinor))) ?? "JPY \(amountMinor)"
}

func feedShortCount(_ value: Int) -> String {
    if value >= 1000 {
        return String(format: "%.1fK", Double(value) / 1000.0)
    }
    return "\(value)"
}

func feedFormatDate(_ iso8601: String) -> String {
    guard let date = feedParseISO8601Date(iso8601) else { return iso8601 }
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

func feedParseISO8601Date(_ value: String) -> Date? {
    let parser = ISO8601DateFormatter()
    parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = parser.date(from: value) { return date }
    parser.formatOptions = [.withInternetDateTime]
    return parser.date(from: value)
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
            .simultaneousGesture(
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
            , including: .gesture)
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
