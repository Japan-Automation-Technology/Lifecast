import SwiftUI
import AVFoundation
struct PostedVideosListView: View {
    let videos: [MyVideo]
    let errorText: String
    let onRefreshVideos: () -> Void
    let creatorProfile: CreatorPublicProfile?
    @State private var resolvedCreatorProfile: CreatorPublicProfile?
    @State private var selectedVideo: MyVideo?
    @State private var thumbnailCacheBust = UUID().uuidString

    private var newestFirstVideos: [MyVideo] {
        videos.sorted { lhs, rhs in
            lhs.created_at > rhs.created_at
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

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
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
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
                                LinearGradient(
                                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                HStack(spacing: 4) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text("\(video.play_count ?? 0)")
                                        .font(.caption2.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.45))
                                .clipShape(Capsule())
                                .padding(8)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("posted-grid-video-\(index)")
                        .accessibilityLabel("Open posted \(index)")
                    }
                }
            }
        }
        .padding(.top, -16)
        .fullScreenCover(item: $selectedVideo) { video in
            let effectiveProfile = resolvedCreatorProfile ?? creatorProfile
            CreatorPostedFeedView(
                videos: newestFirstVideos,
                initialVideoId: video.video_id,
                client: LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!),
                projectContext: FeedProjectSummary(
                    id: UUID(),
                    creatorId: effectiveProfile?.creator_user_id ?? UUID(),
                    username: effectiveProfile?.username ?? "lifecast_maker",
                    creatorAvatarURL: effectiveProfile?.avatar_url,
                    caption: "Prototype update",
                    videoId: nil,
                    playbackURL: nil,
                    thumbnailURL: nil,
                    minPlanPriceMinor: 1000,
                    goalAmountMinor: 1_000_000,
                    fundedAmountMinor: 0,
                    remainingDays: 12,
                    likes: 0,
                    comments: 0,
                    isLikedByCurrentUser: false,
                    isSupportedByCurrentUser: false
                ),
                isCurrentUserVideo: true,
                onSupportTap: { _, _ in },
                onVideoDeleted: {
                    onRefreshVideos()
                }
            )
        }
        .task {
            if resolvedCreatorProfile == nil {
                let api = LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!)
                if let fetched = try? await api.getMyProfile().profile {
                    resolvedCreatorProfile = fetched
                }
            }
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
    let onSupportTap: (MyProjectResult, UUID?) -> Void
    let onVideoDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedVideos: [MyVideo]
    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var postedFeedPlayerCache: [URL: AVPlayer] = [:]
    @State private var postedFeedPlayerObserver: Any?
    @State private var postedFeedObservedPlayer: AVPlayer?
    @State private var postedFeedPlaybackProgress: Double = 0
    @State private var isPostedFeedScrubbing = false
    @State private var showPostedPauseIndicator = false
    @State private var postedPauseIndicatorToken = UUID()
    @State private var isPostedFeedEdgeBoosting = false
    @State private var showFeedProjectPanel = false
    @State private var feedPanelPageIndex = 0
    @State private var postedFeedPanelDragOffsetX: CGFloat = 0
    @State private var feedProjectDetailsById: [UUID: MyProjectResult] = [:]
    @State private var feedProjectDetailLoadingIds: Set<UUID> = []
    @State private var feedProjectDetailErrorsById: [UUID: String] = [:]
    @State private var showComments = false
    @State private var showShare = false
    @State private var showActions = false
    @State private var deleteErrorText = ""
    @State private var engagementByVideoId: [UUID: VideoEngagementResult] = [:]
    @State private var commentsByVideoId: [UUID: [FeedComment]] = [:]
    @State private var commentsLoading = false
    @State private var commentsError = ""
    @State private var pendingCommentBody = ""
    @State private var commentsSubmitting = false
    @State private var selectedCreatorRoute: CreatorRoute?
    @State private var creatorProfileOverride: CreatorPublicProfile?
    @State private var trackedVideoId: UUID?
    @State private var trackedProjectId: UUID?
    @State private var trackedDurationMs = 0
    @State private var trackedMaxWatchMs = 0
    @State private var trackedDidComplete = false

    init(
        videos: [MyVideo],
        initialVideoId: UUID,
        client: LifeCastAPIClient,
        projectContext: FeedProjectSummary,
        isCurrentUserVideo: Bool,
        onSupportTap: @escaping (MyProjectResult, UUID?) -> Void = { _, _ in },
        onVideoDeleted: @escaping () -> Void
    ) {
        self.videos = videos
        self.initialVideoId = initialVideoId
        self.client = client
        self.projectContext = projectContext
        self.isCurrentUserVideo = isCurrentUserVideo
        self.onSupportTap = onSupportTap
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
                    verticalDragDisabled: false,
                    allowHorizontalChildDrag: showFeedProjectPanel,
                    horizontalActionExclusionBottomInset: 28,
                    onWillMove: {
                        player?.pause()
                        closePostedFeedProjectPanelForVerticalMove()
                    },
                    onDidMove: {
                        syncPlayerForCurrentIndex()
                    },
                    onHorizontalDragChanged: { dx in
                        guard !showFeedProjectPanel else { return }
                        postedFeedPanelDragOffsetX = min(0, dx)
                    },
                    onNonVerticalEnded: { value in
                        handlePostedFeedDragEnded(value, project: currentProject)
                    },
                    content: { video, isActive in
                        feedPage(video: video, project: currentProject, useLivePlayer: isActive)
                    }
                )
                .accessibilityIdentifier("posted-feed-view")
                .ignoresSafeArea(edges: .top)
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
        .sheet(isPresented: $showShare) {
            shareActionsSheet
        }
        .sheet(isPresented: $showActions) {
            videoActionsSheet
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
            Task {
                await prefetchPostedFeedProjectDetails(around: currentIndex)
                await refreshCurrentVideoEngagement()
                await refreshOwnCreatorProfileIfNeeded()
            }
        }
        .onChange(of: currentIndex) { _, _ in
            syncPlayerForCurrentIndex()
            Task {
                await prefetchPostedFeedProjectDetails(around: currentIndex)
                await refreshCurrentVideoEngagement()
            }
        }
        .onChange(of: selectedCreatorRoute) { _, newValue in
            if newValue != nil {
                player?.pause()
            } else if !showFeedProjectPanel {
                syncPlayerForCurrentIndex()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let endedItem = note.object as? AVPlayerItem else { return }
            guard let current = player, current.currentItem === endedItem else { return }
            trackedDidComplete = true
            trackedMaxWatchMs = max(trackedMaxWatchMs, trackedDurationMs)
            if let videoId = trackedVideoId, trackedDurationMs > 0 {
                Task {
                    await client.trackVideoWatchProgress(
                        videoId: videoId,
                        watchDurationMs: trackedDurationMs,
                        videoDurationMs: trackedDurationMs,
                        projectId: trackedProjectId
                    )
                }
            }
            current.seek(to: .zero)
            if !showFeedProjectPanel {
                current.play()
            }
        }
        .onDisappear {
            flushTrackedPlaybackProgress()
            setPostedFeedEdgeBoosting(false)
            player?.pause()
            detachPostedFeedPlayerObserver()
            player = nil
            trackedVideoId = nil
            trackedProjectId = nil
            trackedDurationMs = 0
            trackedMaxWatchMs = 0
            trackedDidComplete = false
            for prepared in postedFeedPlayerCache.values {
                prepared.pause()
            }
        }
        .fullScreenCover(item: $selectedCreatorRoute) { route in
            CreatorPublicPageView(
                client: client,
                creatorId: route.id,
                onSupportTap: onSupportTap
            )
        }
    }

    private var currentProject: FeedProjectSummary {
        let resolvedCreatorId = isCurrentUserVideo ? (creatorProfileOverride?.creator_user_id ?? projectContext.creatorId) : projectContext.creatorId
        let resolvedUsername = isCurrentUserVideo ? (creatorProfileOverride?.username ?? projectContext.username) : projectContext.username
        let resolvedAvatarURL = isCurrentUserVideo ? (creatorProfileOverride?.avatar_url ?? projectContext.creatorAvatarURL) : projectContext.creatorAvatarURL
        guard let videoId = currentVideoId else {
            return FeedProjectSummary(
                id: projectContext.id,
                creatorId: resolvedCreatorId,
                username: resolvedUsername,
                creatorAvatarURL: resolvedAvatarURL,
                caption: projectContext.caption,
                videoId: projectContext.videoId,
                playbackURL: projectContext.playbackURL,
                thumbnailURL: projectContext.thumbnailURL,
                minPlanPriceMinor: projectContext.minPlanPriceMinor,
                goalAmountMinor: projectContext.goalAmountMinor,
                fundedAmountMinor: projectContext.fundedAmountMinor,
                remainingDays: projectContext.remainingDays,
                likes: projectContext.likes,
                comments: projectContext.comments,
                isLikedByCurrentUser: projectContext.isLikedByCurrentUser,
                isSupportedByCurrentUser: projectContext.isSupportedByCurrentUser
            )
        }
        let engagement = engagementByVideoId[videoId]
        return FeedProjectSummary(
            id: projectContext.id,
            creatorId: resolvedCreatorId,
            username: resolvedUsername,
            creatorAvatarURL: resolvedAvatarURL,
            caption: projectContext.caption,
            videoId: videoId,
            playbackURL: projectContext.playbackURL,
            thumbnailURL: projectContext.thumbnailURL,
            minPlanPriceMinor: projectContext.minPlanPriceMinor,
            goalAmountMinor: projectContext.goalAmountMinor,
            fundedAmountMinor: projectContext.fundedAmountMinor,
            remainingDays: projectContext.remainingDays,
            likes: engagement?.likes ?? projectContext.likes,
            comments: engagement?.comments ?? projectContext.comments,
            isLikedByCurrentUser: engagement?.is_liked_by_current_user ?? projectContext.isLikedByCurrentUser,
            isSupportedByCurrentUser: projectContext.isSupportedByCurrentUser
        )
    }

    private var currentVideoId: UUID? {
        guard feedVideos.indices.contains(currentIndex) else { return nil }
        return feedVideos[currentIndex].video_id
    }

    private func feedPage(video: MyVideo, project: FeedProjectSummary, useLivePlayer: Bool) -> some View {
        ZStack(alignment: .bottom) {
            SlidingFeedPanelLayer(
                isPanelOpen: showFeedProjectPanel && useLivePlayer,
                cornerRadius: 0,
                dragOffsetX: useLivePlayer ? postedFeedPanelDragOffsetX : 0
            ) {
                feedVideoLayer(video: video, useLivePlayer: useLivePlayer)
            } panelLayer: { width in
                feedProjectPanel(project: project, width: width)
            }

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .opacity(showFeedProjectPanel ? 0.34 : 1.0)

            if useLivePlayer && !showFeedProjectPanel {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: min(72, max(52, geo.size.width * 0.14)))
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 48, pressing: { pressing in
                                setPostedFeedEdgeBoosting(pressing)
                            }, perform: {})

                        Color.clear
                            .contentShape(Rectangle())
                            .gesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        Task {
                                            await likeOnDoubleTapInPostedFeed(project: project)
                                        }
                                    }
                                    .exclusively(before: TapGesture(count: 1).onEnded {
                                        togglePostedFeedPlayback()
                                    })
                            )

                        Color.clear
                            .frame(width: min(72, max(52, geo.size.width * 0.14)))
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 48, pressing: { pressing in
                                setPostedFeedEdgeBoosting(pressing)
                            }, perform: {})
                    }
                    .padding(.horizontal, 84)
                    .padding(.top, 120)
                    .padding(.bottom, appBottomBarHeight + 140)
                }
            }

            if useLivePlayer && showPostedPauseIndicator {
                Image(systemName: "pause.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            VStack(spacing: 8) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        projectPrimaryAction(project: project)
                        Button("@\(project.username)") {
                            if isCurrentUserVideo {
                                dismiss()
                            } else {
                                selectedCreatorRoute = CreatorRoute(id: project.creatorId)
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)

                        Text(project.caption)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))

                        fundingMeta(project: project)
                    }

                    Spacer(minLength: 12)

                    rightRail(project: project)
                }

                FeedPageIndicatorDots(
                    currentIndex: showFeedProjectPanel ? (clampedFeedPanelPageIndex(for: project) + 1) : 0,
                    totalCount: feedPanelPageCount(for: project) + 1
                )
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, appBottomBarHeight - 14)
            .offset(y: 22)

            if useLivePlayer {
                FeedPlaybackScrubber(
                    progress: postedFeedPlaybackProgress,
                    onScrubBegan: {
                        isPostedFeedScrubbing = true
                    },
                    onScrubChanged: { progress in
                        postedFeedPlaybackProgress = progress
                        seekPostedFeedPlayer(toProgress: progress)
                    },
                    onScrubEnded: { progress in
                        postedFeedPlaybackProgress = progress
                        seekPostedFeedPlayer(toProgress: progress)
                        isPostedFeedScrubbing = false
                    }
                )
                .padding(.horizontal, 0)
                .padding(.bottom, -3)
            }
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
        let cachedDetail = feedProjectDetailsById[project.id]
        let isLoading = feedProjectDetailLoadingIds.contains(project.id)
        let errorText = feedProjectDetailErrorsById[project.id] ?? ""
        let plans = cachedDetail?.plans ?? []
        let pageCount = max(1, plans.count + 1)
        let panelPageSelection = Binding<Int>(
            get: { min(max(feedPanelPageIndex, 0), pageCount - 1) },
            set: { feedPanelPageIndex = min(max($0, 0), pageCount - 1) }
        )

        return VStack(alignment: .leading, spacing: 12) {
            InteractiveHorizontalPager(
                pageCount: pageCount,
                currentIndex: panelPageSelection,
                onSwipeBeyondLeadingEdge: {
                    closePostedFeedProjectPanel()
                },
                onLeadingEdgeDragChanged: { dx in
                    guard showFeedProjectPanel, feedPanelPageIndex == 0 else {
                        postedFeedPanelDragOffsetX = 0
                        return
                    }
                    postedFeedPanelDragOffsetX = max(0, dx)
                }
            ) { idx in
                let tappedPlan = idx > 0 ? plans[idx - 1] : nil
                VStack(alignment: .leading, spacing: 12) {
                    FeedPanelPageHeaderView(currentPage: idx, plansCount: plans.count, totalCount: feedPanelPageCount(for: project))
                    if idx == 0 {
                        FeedProjectOverviewPanelContentView(project: project, detail: cachedDetail, isLoading: isLoading)
                    } else {
                        FeedPlanPanelContentView(plan: plans[idx - 1])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .gesture(
                    TapGesture(count: 2)
                        .onEnded {
                            Task {
                                await likeOnDoubleTapInPostedFeed(project: project)
                            }
                        }
                        .exclusively(before: TapGesture(count: 1).onEnded {
                            guard !isCurrentUserVideo else { return }
                            Task {
                                await triggerSupportFromPanel(project: project, preferredPlanId: tappedPlan?.id)
                            }
                        })
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, feedPanelTopPadding)
        .padding(.bottom, 18)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.black.opacity(0.86))
    }


    private func feedPanelPageCount(for project: FeedProjectSummary) -> Int {
        1 + (feedProjectDetailsById[project.id]?.plans?.count ?? 0)
    }

    private func clampedFeedPanelPageIndex(for project: FeedProjectSummary) -> Int {
        min(max(feedPanelPageIndex, 0), max(feedPanelPageCount(for: project) - 1, 0))
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            FeedMetricButton(
                icon: project.isLikedByCurrentUser ? "heart.fill" : "heart",
                value: project.likes,
                isActive: project.isLikedByCurrentUser
            ) {
                Task {
                    await toggleLikeForCurrentVideo()
                }
            }
            Button {
                showComments = true
                pendingCommentBody = ""
                commentsError = ""
                Task {
                    await loadCommentsForCurrentVideo()
                }
            } label: {
                FeedMetricView(icon: "text.bubble.fill", value: project.comments)
            }
            Button {
                showShare = true
            } label: {
                FeedMetricView(icon: "square.and.arrow.up.fill", value: 0, labelOverride: "Share")
            }
            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
            }
            .padding(.vertical, 6)
            .accessibilityIdentifier("video-actions")
            Button {
                if isCurrentUserVideo {
                    dismiss()
                } else {
                    selectedCreatorRoute = CreatorRoute(id: project.creatorId)
                }
            } label: {
                FeedCreatorAvatarView(urlString: project.creatorAvatarURL, username: project.username)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private func projectPrimaryAction(project: FeedProjectSummary) -> some View {
        let isNeutralState = isCurrentUserVideo
        return FeedPrimaryActionButton(
            title: isNeutralState ? "Project" : (project.isSupportedByCurrentUser ? "Supported" : "Support"),
            isChecked: project.isSupportedByCurrentUser,
            isNeutral: isNeutralState
        ) {
            if isCurrentUserVideo {
                if !showFeedProjectPanel {
                    openPostedFeedProjectPanel(for: project)
                }
            } else {
                Task {
                    await triggerSupportFromPanel(project: project, preferredPlanId: nil)
                }
            }
        }
    }

    private func fundingMeta(project: FeedProjectSummary) -> some View {
        FeedFundingMetaView(project: project)
    }

    private var sortedComments: [FeedComment] {
        currentVideoComments.sorted { lhs, rhs in
            if lhs.isSupporter != rhs.isSupporter {
                return lhs.isSupporter && !rhs.isSupporter
            }
            if lhs.likes != rhs.likes {
                return lhs.likes > rhs.likes
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var currentVideoComments: [FeedComment] {
        guard let videoId = currentVideoId else { return [] }
        return commentsByVideoId[videoId] ?? []
    }

    private var commentsSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if commentsLoading && sortedComments.isEmpty {
                    ProgressView("Loading comments...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(sortedComments) { comment in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Button {
                                        guard let userId = comment.userId else { return }
                                        showComments = false
                                        DispatchQueue.main.async {
                                            if isCurrentUserVideo, userId == currentProject.creatorId {
                                                dismiss()
                                            } else {
                                                selectedCreatorRoute = CreatorRoute(id: userId)
                                            }
                                        }
                                    } label: {
                                        Text("@\(comment.username)")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .buttonStyle(.plain)
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
                            Button {
                                Task {
                                    await toggleLikeForComment(comment)
                                }
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: comment.isLikedByCurrentUser ? "heart.fill" : "heart")
                                    Text("\(comment.likes)")
                                        .font(.caption)
                                }
                                .foregroundStyle(comment.isLikedByCurrentUser ? Color.pink : Color.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !commentsError.isEmpty {
                    Text(commentsError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 12)
                        .padding(.top, 4)
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
                    TextField("Add comment...", text: $pendingCommentBody)
                        .textFieldStyle(.roundedBorder)
                    Button("Send") {
                        Task {
                            await submitCommentForCurrentVideo()
                        }
                    }
                    .disabled(commentsSubmitting || pendingCommentBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
        }
    }

    private func syncPlayerForCurrentIndex() {
        guard !feedVideos.isEmpty else {
            transitionTrackedVideo(to: nil, projectId: nil)
            setPostedFeedEdgeBoosting(false)
            player?.pause()
            detachPostedFeedPlayerObserver()
            player = nil
            postedFeedPlaybackProgress = 0
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
            transitionTrackedVideo(to: nil, projectId: nil)
            setPostedFeedEdgeBoosting(false)
            player?.pause()
            detachPostedFeedPlayerObserver()
            player = nil
            postedFeedPlaybackProgress = 0
            return
        }
        transitionTrackedVideo(to: feedVideos[currentIndex].video_id, projectId: isCurrentUserVideo ? nil : projectContext.id)

        let targetPlayer: AVPlayer
        if let cached = postedFeedPlayerCache[url] {
            targetPlayer = cached
        } else {
            let created = AVPlayer(url: url)
            created.actionAtItemEnd = .none
            postedFeedPlayerCache[url] = created
            targetPlayer = created
        }

        if player !== targetPlayer {
            player?.pause()
            player = targetPlayer
            attachPostedFeedPlayerObserver(to: targetPlayer)
        }

        if showFeedProjectPanel {
            targetPlayer.pause()
        } else {
            targetPlayer.play()
        }

        warmPostedFeedPlayerCache(around: currentIndex)
    }

    private func attachPostedFeedPlayerObserver(to targetPlayer: AVPlayer) {
        detachPostedFeedPlayerObserver()
        postedFeedPlaybackProgress = 0
        postedFeedObservedPlayer = targetPlayer
        postedFeedPlayerObserver = targetPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { _ in
            guard let currentItem = targetPlayer.currentItem else {
                if !isPostedFeedScrubbing {
                    postedFeedPlaybackProgress = 0
                }
                return
            }
            let duration = currentItem.duration.seconds
            guard duration.isFinite, duration > 0 else {
                if !isPostedFeedScrubbing {
                    postedFeedPlaybackProgress = 0
                }
                return
            }
            let durationMs = duration * 1000
            if durationMs.isFinite, durationMs >= 0 {
                trackedDurationMs = max(0, Int(durationMs))
            }
            let currentMs = targetPlayer.currentTime().seconds * 1000
            if currentMs.isFinite, currentMs >= 0 {
                trackedMaxWatchMs = max(trackedMaxWatchMs, Int(currentMs))
            }
            if !isPostedFeedScrubbing {
                postedFeedPlaybackProgress = min(max(targetPlayer.currentTime().seconds / duration, 0), 1)
            }
        }
    }

    private func detachPostedFeedPlayerObserver() {
        guard let targetPlayer = postedFeedObservedPlayer, let observer = postedFeedPlayerObserver else { return }
        targetPlayer.removeTimeObserver(observer)
        postedFeedPlayerObserver = nil
        postedFeedObservedPlayer = nil
    }

    private func seekPostedFeedPlayer(toProgress progress: Double) {
        guard let targetPlayer = player, let item = targetPlayer.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let target = CMTime(seconds: duration * min(max(progress, 0), 1), preferredTimescale: 600)
        targetPlayer.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func togglePostedFeedPlayback() {
        guard let targetPlayer = player else { return }
        if targetPlayer.timeControlStatus == .playing {
            targetPlayer.pause()
            showPostedPauseIndicatorTemporarily()
        } else if !showFeedProjectPanel {
            targetPlayer.play()
            if isPostedFeedEdgeBoosting {
                targetPlayer.rate = 2.0
            }
        }
    }

    private func showPostedPauseIndicatorTemporarily() {
        let token = UUID()
        postedPauseIndicatorToken = token
        withAnimation(.easeOut(duration: 0.12)) {
            showPostedPauseIndicator = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard postedPauseIndicatorToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showPostedPauseIndicator = false
            }
        }
    }

    private func setPostedFeedEdgeBoosting(_ boosting: Bool) {
        guard boosting != isPostedFeedEdgeBoosting else { return }
        isPostedFeedEdgeBoosting = boosting
        guard let targetPlayer = player else { return }
        guard targetPlayer.timeControlStatus == .playing else { return }
        targetPlayer.rate = boosting ? 2.0 : 1.0
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
                prepared.actionAtItemEnd = .none
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

    private func transitionTrackedVideo(to videoId: UUID?, projectId: UUID?) {
        guard trackedVideoId != videoId else { return }
        flushTrackedPlaybackProgress()
        trackedVideoId = videoId
        trackedProjectId = projectId
        trackedDurationMs = 0
        trackedMaxWatchMs = 0
        trackedDidComplete = false
        guard let videoId else { return }
        Task {
            await client.trackVideoPlayStarted(videoId: videoId, projectId: projectId)
        }
    }

    private func flushTrackedPlaybackProgress() {
        guard !trackedDidComplete else { return }
        guard let videoId = trackedVideoId else { return }
        let clampedWatchMs = max(0, min(trackedMaxWatchMs, trackedDurationMs))
        guard clampedWatchMs > 0, trackedDurationMs > 0 else { return }
        Task {
            await client.trackVideoWatchProgress(
                videoId: videoId,
                watchDurationMs: clampedWatchMs,
                videoDurationMs: trackedDurationMs,
                projectId: trackedProjectId
            )
        }
    }

    private func handlePostedFeedDragEnded(_ value: DragGesture.Value, project: FeedProjectSummary) {
        let dx = value.translation.width
        let dy = value.translation.height
        let threshold: CGFloat = 50

        if showFeedProjectPanel, abs(dx) > abs(dy), abs(dx) > threshold {
            if dx > 0, feedPanelPageIndex == 0 {
                closePostedFeedProjectPanel()
            }
            return
        }

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
            feedPanelPageIndex = 0
            postedFeedPanelDragOffsetX = 0
        }
        player?.pause()
        Task {
            await loadPostedFeedProjectDetail(for: project, forceRefresh: false)
        }
    }

    private func closePostedFeedProjectPanel() {
        guard showFeedProjectPanel else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showFeedProjectPanel = false
            feedPanelPageIndex = 0
            postedFeedPanelDragOffsetX = 0
        }
        syncPlayerForCurrentIndex()
    }

    private func closePostedFeedProjectPanelForVerticalMove() {
        guard showFeedProjectPanel else { return }
        showFeedProjectPanel = false
        postedFeedPanelDragOffsetX = 0
    }

    private func loadPostedFeedProjectDetail(for project: FeedProjectSummary, forceRefresh: Bool) async {
        if !forceRefresh, feedProjectDetailsById[project.id] != nil { return }
        if feedProjectDetailLoadingIds.contains(project.id) { return }

        await MainActor.run {
            feedProjectDetailLoadingIds.insert(project.id)
            feedProjectDetailErrorsById[project.id] = nil
        }
        do {
            let page = try await client.getCreatorPage(creatorUserId: project.creatorId)
            await MainActor.run {
                if let detail = page.project {
                    feedProjectDetailsById[project.id] = detail
                } else {
                    feedProjectDetailErrorsById[project.id] = "No project detail found."
                }
                feedProjectDetailLoadingIds.remove(project.id)
            }
        } catch {
            await MainActor.run {
                feedProjectDetailErrorsById[project.id] = error.localizedDescription
                feedProjectDetailLoadingIds.remove(project.id)
            }
        }
    }

    private var videoActionsSheet: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 56, height: 5)
                .padding(.top, 8)

            Text("Video actions")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            if isCurrentUserVideo {
                FeedActionSheetRow(
                    icon: "chart.bar.xaxis",
                    title: "Insights",
                    subtitle: "Coming soon"
                ) {
                    showActions = false
                }
                FeedActionSheetRow(
                    icon: "trash",
                    title: "Delete video",
                    subtitle: "This action cannot be undone",
                    destructive: true
                ) {
                    showActions = false
                    Task {
                        await deleteCurrentVideo()
                    }
                }
            } else {
                FeedActionSheetRow(icon: "eye.slash", title: "Not interested") {
                    showActions = false
                }
                FeedActionSheetRow(icon: "flag", title: "Report", destructive: true) {
                    showActions = false
                }
            }

            Button("Cancel") {
                showActions = false
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 4)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .presentationDetents([.height(isCurrentUserVideo ? 320 : 300)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
    }

    private var shareActionsSheet: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 56, height: 5)
                .padding(.top, 8)

            Text("Share")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            FeedActionSheetRow(icon: "link", title: "Copy link") {
                showShare = false
            }

            Button("Cancel") {
                showShare = false
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 4)
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .padding(.bottom, 12)
        .presentationDetents([.height(220)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
    }

    private func prefetchPostedFeedProjectDetails(around index: Int) async {
        guard !feedVideos.isEmpty else { return }
        let indices = [index - 1, index, index + 1].filter { $0 >= 0 && $0 < feedVideos.count }
        for idx in indices {
            let videoId = feedVideos[idx].video_id
            let context = resolvedProjectContext(for: videoId)
            await loadPostedFeedProjectDetail(for: context, forceRefresh: false)
        }
    }

    private func triggerSupportFromPanel(project: FeedProjectSummary, preferredPlanId: UUID?) async {
        guard !isCurrentUserVideo else { return }
        if let cached = feedProjectDetailsById[project.id] {
            await MainActor.run {
                onSupportTap(cached, preferredPlanId)
            }
            return
        }
        do {
            let page = try await client.getCreatorPage(creatorUserId: project.creatorId)
            if let detail = page.project {
                await MainActor.run {
                    feedProjectDetailsById[project.id] = detail
                    onSupportTap(detail, preferredPlanId)
                }
            } else {
                await MainActor.run {
                    deleteErrorText = "No active project to support."
                }
            }
        } catch {
            await MainActor.run {
                deleteErrorText = "Failed to load support plans: \(error.localizedDescription)"
            }
        }
    }

    private func resolvedProjectContext(for videoId: UUID) -> FeedProjectSummary {
        let resolvedCreatorId = isCurrentUserVideo ? (creatorProfileOverride?.creator_user_id ?? projectContext.creatorId) : projectContext.creatorId
        let resolvedUsername = isCurrentUserVideo ? (creatorProfileOverride?.username ?? projectContext.username) : projectContext.username
        let resolvedAvatarURL = isCurrentUserVideo ? (creatorProfileOverride?.avatar_url ?? projectContext.creatorAvatarURL) : projectContext.creatorAvatarURL
        let engagement = engagementByVideoId[videoId]
        return FeedProjectSummary(
            id: projectContext.id,
            creatorId: resolvedCreatorId,
            username: resolvedUsername,
            creatorAvatarURL: resolvedAvatarURL,
            caption: projectContext.caption,
            videoId: videoId,
            playbackURL: projectContext.playbackURL,
            thumbnailURL: projectContext.thumbnailURL,
            minPlanPriceMinor: projectContext.minPlanPriceMinor,
            goalAmountMinor: projectContext.goalAmountMinor,
            fundedAmountMinor: projectContext.fundedAmountMinor,
            remainingDays: projectContext.remainingDays,
            likes: engagement?.likes ?? projectContext.likes,
            comments: engagement?.comments ?? projectContext.comments,
            isLikedByCurrentUser: engagement?.is_liked_by_current_user ?? projectContext.isLikedByCurrentUser,
            isSupportedByCurrentUser: projectContext.isSupportedByCurrentUser
        )
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

    private func refreshCurrentVideoEngagement() async {
        guard let videoId = currentVideoId else { return }
        do {
            let engagement = try await client.getVideoEngagement(videoId: videoId)
            await MainActor.run {
                engagementByVideoId[videoId] = engagement
            }
        } catch {}
    }

    private func refreshOwnCreatorProfileIfNeeded() async {
        guard isCurrentUserVideo else { return }
        do {
            let profile = try await client.getMyProfile().profile
            await MainActor.run {
                creatorProfileOverride = profile
            }
        } catch {
            // Keep existing context when profile refresh fails.
        }
    }

    private func toggleLikeForCurrentVideo() async {
        guard let videoId = currentVideoId else { return }
        let previous = engagementByVideoId[videoId] ?? VideoEngagementResult(
            likes: projectContext.likes,
            comments: projectContext.comments,
            is_liked_by_current_user: projectContext.isLikedByCurrentUser
        )
        let optimistic = VideoEngagementResult(
            likes: max(0, previous.likes + (previous.is_liked_by_current_user ? -1 : 1)),
            comments: previous.comments,
            is_liked_by_current_user: !previous.is_liked_by_current_user
        )
        await MainActor.run {
            engagementByVideoId[videoId] = optimistic
        }
        do {
            let updated = previous.is_liked_by_current_user
                ? try await client.unlikeVideo(videoId: videoId)
                : try await client.likeVideo(videoId: videoId)
            await MainActor.run {
                engagementByVideoId[videoId] = updated
            }
        } catch {
            await MainActor.run {
                engagementByVideoId[videoId] = previous
                deleteErrorText = "Like failed: \(error.localizedDescription)"
            }
        }
    }

    private func likeOnDoubleTapInPostedFeed(project: FeedProjectSummary) async {
        guard let videoId = currentVideoId ?? project.videoId else { return }
        let previous = engagementByVideoId[videoId] ?? VideoEngagementResult(
            likes: project.likes,
            comments: project.comments,
            is_liked_by_current_user: project.isLikedByCurrentUser
        )
        guard !previous.is_liked_by_current_user else { return }

        let optimistic = VideoEngagementResult(
            likes: previous.likes + 1,
            comments: previous.comments,
            is_liked_by_current_user: true
        )
        await MainActor.run {
            engagementByVideoId[videoId] = optimistic
        }
        do {
            let updated = try await client.likeVideo(videoId: videoId)
            await MainActor.run {
                engagementByVideoId[videoId] = updated
            }
        } catch {
            await MainActor.run {
                engagementByVideoId[videoId] = previous
                deleteErrorText = "Like failed: \(error.localizedDescription)"
            }
        }
    }

    private func loadCommentsForCurrentVideo() async {
        guard let videoId = currentVideoId else { return }
        await MainActor.run {
            commentsLoading = true
            commentsError = ""
        }
        defer {
            Task { @MainActor in
                commentsLoading = false
            }
        }
        do {
            let rows = try await client.listVideoComments(videoId: videoId, limit: 80)
            await MainActor.run {
                commentsByVideoId[videoId] = rows.map(mapVideoCommentRow)
            }
            await refreshCurrentVideoEngagement()
        } catch {
            await MainActor.run {
                commentsError = error.localizedDescription
            }
        }
    }

    private func submitCommentForCurrentVideo() async {
        guard let videoId = currentVideoId else { return }
        let content = pendingCommentBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        await MainActor.run {
            commentsSubmitting = true
            commentsError = ""
        }
        defer {
            Task { @MainActor in
                commentsSubmitting = false
            }
        }
        do {
            let row = try await client.createVideoComment(videoId: videoId, body: content)
            await MainActor.run {
                var current = commentsByVideoId[videoId] ?? []
                current.insert(mapVideoCommentRow(row), at: 0)
                commentsByVideoId[videoId] = current
                pendingCommentBody = ""
            }
            await refreshCurrentVideoEngagement()
        } catch {
            await MainActor.run {
                commentsError = "Failed to send comment: \(error.localizedDescription)"
            }
        }
    }

    private func toggleLikeForComment(_ comment: FeedComment) async {
        guard let videoId = currentVideoId else { return }
        let optimistic = FeedComment(
            id: comment.id,
            userId: comment.userId,
            username: comment.username,
            body: comment.body,
            likes: max(0, comment.likes + (comment.isLikedByCurrentUser ? -1 : 1)),
            createdAt: comment.createdAt,
            isLikedByCurrentUser: !comment.isLikedByCurrentUser,
            isSupporter: comment.isSupporter
        )
        await MainActor.run {
            replaceComment(videoId: videoId, with: optimistic)
        }
        do {
            let engagement = comment.isLikedByCurrentUser
                ? try await client.unlikeVideoComment(videoId: videoId, commentId: comment.id)
                : try await client.likeVideoComment(videoId: videoId, commentId: comment.id)
            await MainActor.run {
                let resolved = FeedComment(
                    id: comment.id,
                    userId: comment.userId,
                    username: comment.username,
                    body: comment.body,
                    likes: engagement.likes,
                    createdAt: comment.createdAt,
                    isLikedByCurrentUser: engagement.is_liked_by_current_user,
                    isSupporter: comment.isSupporter
                )
                replaceComment(videoId: videoId, with: resolved)
            }
        } catch {
            await MainActor.run {
                replaceComment(videoId: videoId, with: comment)
                commentsError = "Failed to like comment: \(error.localizedDescription)"
            }
        }
    }

    private func mapVideoCommentRow(_ row: VideoCommentRow) -> FeedComment {
        let parsedDate = ISO8601DateFormatter().date(from: row.created_at) ?? .now
        return FeedComment(
            id: row.comment_id,
            userId: row.user_id,
            username: row.username,
            body: row.body,
            likes: row.likes,
            createdAt: parsedDate,
            isLikedByCurrentUser: row.is_liked_by_current_user,
            isSupporter: row.is_supporter
        )
    }

    private func replaceComment(videoId: UUID, with updated: FeedComment) {
        var list = commentsByVideoId[videoId] ?? []
        guard let index = list.firstIndex(where: { $0.id == updated.id }) else { return }
        list[index] = updated
        commentsByVideoId[videoId] = list
    }

    private var postedFeedCommentBar: some View {
        ZStack {
            Color.black
            Button {
                showComments = true
                pendingCommentBody = ""
                commentsError = ""
                Task {
                    await loadCommentsForCurrentVideo()
                }
            } label: {
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
            .buttonStyle(.plain)
        }
        .frame(height: appBottomBarHeight)
    }
}
