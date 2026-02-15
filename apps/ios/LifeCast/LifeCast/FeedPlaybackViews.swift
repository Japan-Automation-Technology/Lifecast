import SwiftUI
import AVFoundation
struct PostedVideosListView: View {
    let videos: [MyVideo]
    let errorText: String
    let onRefreshVideos: () -> Void
    @State private var selectedVideo: MyVideo?
    @State private var thumbnailCacheBust = UUID().uuidString

    private var newestFirstVideos: [MyVideo] {
        videos.sorted { lhs, rhs in
            lhs.created_at > rhs.created_at
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Posted videos")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    thumbnailCacheBust = UUID().uuidString
                    onRefreshVideos()
                }
                .font(.caption)
            }
            .padding(.horizontal, 16)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            if newestFirstVideos.isEmpty {
                Text("No uploaded videos yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                    ForEach(Array(newestFirstVideos.enumerated()), id: \.element.video_id) { index, video in
                        Button {
                            selectedVideo = video
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                if let thumbnail = video.thumbnail_url, let thumbnailURL = thumbnailURL(base: thumbnail) {
                                    AsyncImage(url: thumbnailURL) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        LinearGradient(
                                            colors: [Color.blue.opacity(0.5), Color.pink.opacity(0.6)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    }
                                } else {
                                    Rectangle()
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.5), Color.pink.opacity(0.6)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                }
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 28))
                                    .foregroundStyle(.white.opacity(0.9))
                                LinearGradient(
                                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("posted-grid-video-\(index)")
                        .accessibilityLabel("Open posted \(index)")
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            CreatorPostedFeedView(
                videos: newestFirstVideos,
                initialVideoId: video.video_id,
                client: LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!),
                projectContext: sampleProjects.first ?? FeedProjectSummary(
                    id: UUID(),
                    creatorId: UUID(),
                    username: "lifecast_maker",
                    caption: "Prototype update",
                    videoId: nil,
                    playbackURL: nil,
                    thumbnailURL: nil,
                    minPlanPriceMinor: 1000,
                    goalAmountMinor: 1_000_000,
                    fundedAmountMinor: 0,
                    remainingDays: 12,
                    likes: 4500,
                    comments: 173,
                    isSupportedByCurrentUser: false
                ),
                isCurrentUserVideo: true,
                onVideoDeleted: {
                    onRefreshVideos()
                }
            )
        }
    }

    private func thumbnailURL(base: String) -> URL? {
        guard var components = URLComponents(string: base) else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "cb", value: thumbnailCacheBust))
        components.queryItems = items
        return components.url
    }
}

struct CreatorPostedFeedView: View {
    let videos: [MyVideo]
    let initialVideoId: UUID
    let client: LifeCastAPIClient
    let projectContext: FeedProjectSummary
    let isCurrentUserVideo: Bool
    let onVideoDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedVideos: [MyVideo]
    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var postedFeedPlayerCache: [URL: AVPlayer] = [:]
    @State private var showFeedProjectPanel = false
    @State private var feedProjectDetail: MyProjectResult?
    @State private var feedProjectDetailLoading = false
    @State private var feedProjectDetailError = ""
    @State private var showComments = false
    @State private var showShare = false
    @State private var showActions = false
    @State private var deleteErrorText = ""

    init(
        videos: [MyVideo],
        initialVideoId: UUID,
        client: LifeCastAPIClient,
        projectContext: FeedProjectSummary,
        isCurrentUserVideo: Bool,
        onVideoDeleted: @escaping () -> Void
    ) {
        self.videos = videos
        self.initialVideoId = initialVideoId
        self.client = client
        self.projectContext = projectContext
        self.isCurrentUserVideo = isCurrentUserVideo
        self.onVideoDeleted = onVideoDeleted
        let initial = videos.firstIndex(where: { $0.video_id == initialVideoId }) ?? 0
        _feedVideos = State(initialValue: videos)
        _currentIndex = State(initialValue: initial)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if feedVideos.isEmpty {
                Text("No videos")
                    .foregroundStyle(.white)
            } else {
                InteractiveVerticalFeedPager(
                    items: feedVideos,
                    currentIndex: $currentIndex,
                    verticalDragDisabled: showFeedProjectPanel,
                    onWillMove: {
                        player?.pause()
                        closePostedFeedProjectPanel()
                    },
                    onDidMove: {
                        syncPlayerForCurrentIndex()
                    },
                    onNonVerticalEnded: { value in
                        handlePostedFeedDragEnded(value, project: currentProject)
                    },
                    content: { video, isActive in
                        feedPage(video: video, project: currentProject, useLivePlayer: isActive)
                    }
                )
                .accessibilityIdentifier("posted-feed-view")
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    }
                    label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.semibold))
                            .padding(10)
                            .background(Color.black.opacity(0.45))
                            .foregroundStyle(.white)
                            .clipShape(Circle())
                    }
                    .accessibilityIdentifier("posted-feed-back")

                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            postedFeedCommentBar
        }
        .sheet(isPresented: $showComments) {
            commentsSheet
        }
        .confirmationDialog("Share", isPresented: $showShare, titleVisibility: .visible) {
            Button("Export video") {}
            Button("Copy link") {}
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Choose one action")
        }
        .confirmationDialog("Video actions", isPresented: $showActions, titleVisibility: .visible) {
            Button("Insights (Coming Soon)") {}
            if isCurrentUserVideo {
                Button("Delete video", role: .destructive) {
                    Task {
                        await deleteCurrentVideo()
                    }
                }
            } else {
                Button("Not interested") {}
                Button("Report", role: .destructive) {}
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            if !deleteErrorText.isEmpty {
                Text(deleteErrorText)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 56)
            }
        }
        .onAppear {
            syncPlayerForCurrentIndex()
        }
        .onChange(of: currentIndex) { _, _ in
            syncPlayerForCurrentIndex()
        }
        .onDisappear {
            player?.pause()
            player = nil
            for prepared in postedFeedPlayerCache.values {
                prepared.pause()
            }
        }
    }

    private var currentProject: FeedProjectSummary {
        projectContext
    }

    private func feedPage(video: MyVideo, project: FeedProjectSummary, useLivePlayer: Bool) -> some View {
        ZStack(alignment: .bottom) {
            SlidingFeedPanelLayer(isPanelOpen: showFeedProjectPanel, cornerRadius: 0) {
                feedVideoLayer(video: video, useLivePlayer: useLivePlayer)
            } panelLayer: { width in
                feedProjectPanel(project: project, width: width)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("@\(project.username)")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(project.caption)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)

                    fundingMeta(project: project)
                    FeedPageIndicatorDots(currentIndex: showFeedProjectPanel ? 1 : 0, totalCount: 2)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                Spacer(minLength: 12)

                rightRail(project: project)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, appBottomBarHeight + 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feedVideoLayer(video: MyVideo, useLivePlayer: Bool) -> some View {
        Group {
            if useLivePlayer, let currentPlayer = player {
                FillVideoPlayerView(player: currentPlayer)
                    .ignoresSafeArea(edges: .top)
            } else if let thumbnail = video.thumbnail_url, let thumbnailURL = URL(string: thumbnail) {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    @unknown default:
                        Rectangle().fill(Color.gray.opacity(0.3))
                    }
                }
                .ignoresSafeArea(edges: .top)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .ignoresSafeArea(edges: .top)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feedProjectPanel(project: FeedProjectSummary, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Project")
                .font(.headline)
                .foregroundStyle(.white)

            if feedProjectDetailLoading {
                ProgressView("Loading project...")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.85))
            } else if let detail = feedProjectDetail {
                Text(detail.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                if let subtitle = detail.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
                Text("Goal: \(formatJPY(detail.goal_amount_minor))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Funded: \(formatJPY(detail.funded_amount_minor)) / \(formatJPY(detail.goal_amount_minor))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Supporters: \(detail.supporter_count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Deadline: \(formatDeliveryDate(from: detail.deadline_at))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                if let description = detail.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                }
            } else {
                Text(project.caption)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.9))
                Text("Goal: \(formatJPY(project.goalAmountMinor))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Funded: \(formatJPY(project.fundedAmountMinor))")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
            }

            if !feedProjectDetailError.isEmpty {
                Text(feedProjectDetailError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.86))
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            if !isCurrentUserVideo {
                Text(project.isSupportedByCurrentUser ? "Supported" : "Support")
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(project.isSupportedByCurrentUser ? Color.green.opacity(0.9) : Color.pink.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(Capsule())
            }

            metricView(icon: "heart.fill", value: project.likes)
            Button {
                showComments = true
            } label: {
                metricView(icon: "text.bubble.fill", value: project.comments)
            }
            Button {
                showShare = true
            } label: {
                metricView(icon: "square.and.arrow.up.fill", value: 0, labelOverride: "Share")
            }
            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
            }
            .accessibilityIdentifier("video-actions")
        }
        .foregroundStyle(.white)
    }

    private func metricView(icon: String, value: Int, labelOverride: String? = nil) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
            Text(labelOverride ?? shortCount(value))
                .font(.caption)
        }
    }

    private func fundingMeta(project: FeedProjectSummary) -> some View {
        let percentRaw = Double(project.fundedAmountMinor) / Double(project.goalAmountMinor)
        let percent = Int(percentRaw * 100)

        return VStack(alignment: .leading, spacing: 6) {
            Text("\(project.remainingDays)d left · From \(formatJPY(project.minPlanPriceMinor))")
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

            Text("\(percent)% (\(formatJPY(project.fundedAmountMinor)) / \(formatJPY(project.goalAmountMinor)))")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .frame(maxWidth: 280)
    }

    private var sortedComments: [FeedComment] {
        sampleComments.sorted { lhs, rhs in
            if lhs.isSupporter != rhs.isSupporter {
                return lhs.isSupporter && !rhs.isSupporter
            }
            if lhs.likes != rhs.likes {
                return lhs.likes > rhs.likes
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var commentsSheet: some View {
        NavigationStack {
            List(sortedComments) { comment in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("@\(comment.username)")
                                .font(.subheadline.weight(.semibold))
                            if comment.isSupporter {
                                Text("SUPPORTER")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.pink.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                        Text(comment.body)
                            .font(.body)
                    }
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "heart")
                        Text("\(comment.likes)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Comments")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        showComments = false
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    TextField("Add comment...", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                    Button("Send") {}
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func syncPlayerForCurrentIndex() {
        guard !feedVideos.isEmpty else {
            player?.pause()
            player = nil
            for prepared in postedFeedPlayerCache.values {
                prepared.pause()
            }
            postedFeedPlayerCache.removeAll()
            return
        }
        guard currentIndex >= 0 && currentIndex < feedVideos.count else {
            currentIndex = max(0, min(currentIndex, feedVideos.count - 1))
            return
        }
        guard let playbackUrl = feedVideos[currentIndex].playback_url, let url = URL(string: playbackUrl) else {
            player?.pause()
            player = nil
            return
        }

        let targetPlayer: AVPlayer
        if let cached = postedFeedPlayerCache[url] {
            targetPlayer = cached
        } else {
            let created = AVPlayer(url: url)
            postedFeedPlayerCache[url] = created
            targetPlayer = created
        }

        if player !== targetPlayer {
            player?.pause()
            player = targetPlayer
        }

        if showFeedProjectPanel {
            targetPlayer.pause()
        } else {
            targetPlayer.play()
        }

        warmPostedFeedPlayerCache(around: currentIndex)
    }

    private func showOlder() {
        guard currentIndex < feedVideos.count - 1 else { return }
        player?.pause()
        closePostedFeedProjectPanel()
        currentIndex += 1
        syncPlayerForCurrentIndex()
    }

    private func showNewer() {
        guard currentIndex > 0 else { return }
        player?.pause()
        closePostedFeedProjectPanel()
        currentIndex -= 1
        syncPlayerForCurrentIndex()
    }

    private func warmPostedFeedPlayerCache(around index: Int) {
        var keep: Set<URL> = []
        for neighbor in [index - 1, index, index + 1] {
            guard neighbor >= 0, neighbor < feedVideos.count else { continue }
            guard let playback = feedVideos[neighbor].playback_url, let url = URL(string: playback) else { continue }
            keep.insert(url)
            if postedFeedPlayerCache[url] == nil {
                let prepared = AVPlayer(url: url)
                prepared.pause()
                postedFeedPlayerCache[url] = prepared
            }
        }

        let stale = postedFeedPlayerCache.keys.filter { !keep.contains($0) }
        for key in stale {
            postedFeedPlayerCache[key]?.pause()
            postedFeedPlayerCache.removeValue(forKey: key)
        }
    }

    private func handlePostedFeedDragEnded(_ value: DragGesture.Value, project: FeedProjectSummary) {
        let dx = value.translation.width
        let dy = value.translation.height
        let action = resolveFeedSwipeAction(
            dx: dx,
            dy: dy,
            isPanelOpen: showFeedProjectPanel,
            canMoveNext: currentIndex < feedVideos.count - 1,
            canMovePrevious: currentIndex > 0
        )

        switch action {
        case .openPanel:
            openPostedFeedProjectPanel(for: project)
        case .closePanel:
            closePostedFeedProjectPanel()
        case .nextItem:
            showOlder()
        case .previousItem:
            showNewer()
        case .none:
            break
        }
    }

    private func openPostedFeedProjectPanel(for project: FeedProjectSummary) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showFeedProjectPanel = true
        }
        player?.pause()
        Task {
            await loadPostedFeedProjectDetail(for: project)
        }
    }

    private func closePostedFeedProjectPanel() {
        guard showFeedProjectPanel else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showFeedProjectPanel = false
        }
        syncPlayerForCurrentIndex()
    }

    private func loadPostedFeedProjectDetail(for project: FeedProjectSummary) async {
        await MainActor.run {
            feedProjectDetailLoading = true
            feedProjectDetailError = ""
        }
        defer {
            Task { @MainActor in
                feedProjectDetailLoading = false
            }
        }
        do {
            let page = try await client.getCreatorPage(creatorUserId: project.creatorId)
            await MainActor.run {
                feedProjectDetail = page.project
            }
        } catch {
            await MainActor.run {
                feedProjectDetailError = error.localizedDescription
            }
        }
    }

    private func deleteCurrentVideo() async {
        guard !feedVideos.isEmpty else { return }
        let target = feedVideos[currentIndex]
        do {
            try await client.deleteVideo(videoId: target.video_id)
            await MainActor.run {
                deleteErrorText = ""
                feedVideos.removeAll(where: { $0.video_id == target.video_id })
                if feedVideos.isEmpty {
                    onVideoDeleted()
                    dismiss()
                    return
                }
                currentIndex = min(currentIndex, feedVideos.count - 1)
                onVideoDeleted()
            }
        } catch {
            await MainActor.run {
                deleteErrorText = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func formatJPY(_ amountMinor: Int) -> String {
        NumberFormatterProvider.jpy.string(from: NSNumber(value: Double(amountMinor))) ?? "JPY \(amountMinor)"
    }

    private func shortCount(_ value: Int) -> String {
        if value >= 1000 {
            return String(format: "%.1fK", Double(value) / 1000.0)
        }
        return "\(value)"
    }

    private func formatDeliveryDate(from iso8601: String) -> String {
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: iso8601) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
        return iso8601
    }

    private var postedFeedCommentBar: some View {
        ZStack {
            Color.black
            HStack {
                Text("コメントする...")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 34)
            .background(Color.white.opacity(0.12))
            .clipShape(Capsule())
            .padding(.horizontal, 14)
        }
        .frame(height: appBottomBarHeight)
    }
}
