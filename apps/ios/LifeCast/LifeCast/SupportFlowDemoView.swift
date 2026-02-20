import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SupportFlowDemoView: View {
    private let client = LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!)

    @State private var selectedTab = 0
    @State private var feedMode: FeedMode = .forYou
    @State private var currentFeedIndex = 0
    @State private var homeFeedPlayer: AVPlayer? = nil
    @State private var homeFeedPlayerCache: [URL: AVPlayer] = [:]
    @State private var homeFeedPlayerObserver: Any?
    @State private var homeFeedObservedPlayer: AVPlayer?
    @State private var homeFeedPlaybackProgress: Double = 0
    @State private var isHomeFeedScrubbing = false
    @State private var showHomePauseIndicator = false
    @State private var homePauseIndicatorToken = UUID()
    @State private var isHomeFeedEdgeBoosting = false
    @State private var showFeedProjectPanel = false
    @State private var feedProjectDetailsById: [UUID: MyProjectResult] = [:]
    @State private var feedProjectDetailLoadingIds: Set<UUID> = []
    @State private var feedProjectDetailErrorsById: [UUID: String] = [:]
    @State private var showComments = false
    @State private var showShare = false
    @State private var selectedCreatorRoute: CreatorRoute? = nil

    @State private var supportEntryPoint: SupportEntryPoint = .feed
    @State private var supportStep: SupportStep = .planSelect
    @State private var showSupportFlow = false
    @State private var selectedPlan: SupportPlan? = nil
    @State private var supportResultStatus = "idle"
    @State private var supportResultMessage = ""
    @State private var liveSupportProject: MyProjectResult?
    @State private var supportTargetProject: MyProjectResult?
    @State private var feedProjects: [FeedProjectSummary] = []
    @State private var myProfile: CreatorPublicProfile?
    @State private var myProfileStats: CreatorProfileStats?
    @State private var myVideos: [MyVideo] = []
    @State private var myVideosError = ""
    @State private var isAuthenticated = false
    @State private var showAuthSheet = false
    @State private var commentsByVideoId: [UUID: [FeedComment]] = [:]
    @State private var commentsLoading = false
    @State private var commentsError = ""
    @State private var pendingCommentBody = ""
    @State private var commentsSubmitting = false
    @State private var showFeedActions = false

    @State private var errorText = ""

    private var realPlans: [SupportPlan] {
        guard let target = supportTargetProject ?? liveSupportProject else { return [] }
        return (target.plans ?? []).map {
            SupportPlan(id: $0.id, name: $0.name, priceMinor: $0.price_minor, rewardSummary: $0.reward_summary)
        }
    }

    private var currentProject: FeedProjectSummary? {
        guard !feedProjects.isEmpty else { return nil }
        return feedProjects[max(0, min(currentFeedIndex, feedProjects.count - 1))]
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                homeTab
                    .navigationDestination(item: $selectedCreatorRoute) { route in
                        CreatorPublicPageView(
                            client: client,
                            creatorId: route.id,
                            onSupportTap: { project in
                                supportEntryPoint = .feed
                                supportTargetProject = project
                                selectedPlan = nil
                                supportStep = .planSelect
                                showSupportFlow = true
                            }
                        )
                    }
            }
                .tabItem { Image(systemName: "house.fill") }
                .tag(0)

            DiscoverSearchView(client: client, onSupportTap: { project in
                supportEntryPoint = .feed
                supportTargetProject = project
                selectedPlan = nil
                supportStep = .planSelect
                showSupportFlow = true
            })
                .safeAreaPadding(.bottom, appBottomBarHeight)
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(1)

            UploadCreateView(client: client, isAuthenticated: isAuthenticated, onUploadReady: {
                Task {
                    await refreshMyVideos()
                }
            }, onOpenProjectTab: {
                selectedTab = 3
            }, onOpenAuth: {
                showAuthSheet = true
            })
                .safeAreaPadding(.bottom, appBottomBarHeight)
                .tabItem { Image(systemName: "plus.square.fill") }
                .tag(2)

            MeTabView(
                client: client,
                isAuthenticated: isAuthenticated,
                myProfile: myProfile,
                myProfileStats: myProfileStats,
                myVideos: myVideos,
                myVideosError: myVideosError,
                onRefreshProfile: {
                    Task {
                        await refreshMyProfile()
                    }
                },
                onRefreshVideos: {
                    Task {
                        await refreshMyVideos()
                    }
                },
                onProjectChanged: {
                    Task {
                        await refreshMyVideos()
                    }
                },
                onOpenAuth: {
                    showAuthSheet = true
                }
            )
            .safeAreaPadding(.bottom, appBottomBarHeight)
            .tabItem { Image(systemName: "person.fill") }
            .tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            appBottomBar
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
        .confirmationDialog("Video options", isPresented: $showFeedActions, titleVisibility: .visible) {
            Button("Not recommend like this") {
                errorText = "Preference saved."
            }
            Button("Report", role: .destructive) {
                errorText = "Thanks. We received your report."
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSupportFlow, onDismiss: handleSupportFlowDismiss) {
            supportFlowSheet
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthEntrySheet(client: client) {
                showAuthSheet = false
                Task {
                    await refreshAuthState()
                    await refreshMyProfile()
                    await refreshMyVideos()
                    await refreshLiveSupportProject()
                }
            }
        }
        .task {
            await refreshAuthState()
            await refreshMyVideos()
            await refreshLiveSupportProject()
            await refreshMyProfile()
            await refreshFeedProjectsFromAPI()
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 3 {
                setHomeFeedEdgeBoosting(false)
                homeFeedPlayer?.pause()
                homeFeedPlayer = nil
                Task {
                    await refreshAuthState()
                    await refreshMyVideos()
                    await refreshLiveSupportProject()
                    await refreshMyProfile()
                }
            } else if newValue == 0 {
                syncHomeFeedPlayer()
                Task {
                    await refreshFeedProjectsFromAPI()
                }
            } else {
                setHomeFeedEdgeBoosting(false)
                homeFeedPlayer?.pause()
                homeFeedPlayer = nil
                for player in homeFeedPlayerCache.values {
                    player.pause()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifecastAuthSessionUpdated)) { _ in
            Task {
                await refreshAuthState()
                await refreshMyProfile()
                await refreshMyVideos()
                await refreshLiveSupportProject()
            }
        }
        .onChange(of: currentFeedIndex) { _, _ in
            syncHomeFeedPlayer()
            Task {
                await prefetchFeedProjectDetails(around: currentFeedIndex)
                await refreshCurrentVideoEngagement()
            }
        }
        .onChange(of: feedMode) { _, _ in
            Task {
                await refreshFeedProjectsFromAPI()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let endedItem = note.object as? AVPlayerItem else { return }
            guard let current = homeFeedPlayer, current.currentItem === endedItem else { return }
            current.seek(to: .zero)
            if selectedTab == 0 && !showFeedProjectPanel {
                current.play()
            }
        }
    }

    private var homeTab: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ZStack(alignment: .bottomTrailing) {
                if !feedProjects.isEmpty {
                    InteractiveVerticalFeedPager(
                        items: feedProjects,
                        currentIndex: $currentFeedIndex,
                        verticalDragDisabled: false,
                        horizontalActionExclusionBottomInset: 28,
                        onWillMove: {
                            homeFeedPlayer?.pause()
                            closeFeedProjectPanelForVerticalMove()
                        },
                        onDidMove: {
                            syncHomeFeedPlayer()
                        },
                        onNonVerticalEnded: { value in
                            guard let project = currentProject else { return }
                            handleHomeFeedDragEnded(value, project: project)
                        },
                        content: { project, isActive in
                            feedCard(project: project, useLivePlayer: isActive)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "video.slash")
                                    .font(.system(size: 30))
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("No feed videos yet")
                                    .foregroundStyle(.white.opacity(0.9))
                                Text("Ask creators to upload videos")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .top)
            .overlay(alignment: .top) {
                homeFeedHeader
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: appBottomBarHeight)
        }
    }

    private var homeFeedHeader: some View {
        HStack(spacing: 24) {
            Button("For You") {
                feedMode = .forYou
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(feedMode == .forYou ? Color.white : Color.white.opacity(0.45))

            Button("Following") {
                feedMode = .following
            }
            .font(.headline.weight(.semibold))
            .foregroundStyle(feedMode == .following ? Color.white : Color.white.opacity(0.45))
        }
        .padding(.top, 10)
    }

    private func feedCard(project: FeedProjectSummary, useLivePlayer: Bool = true) -> some View {
        ZStack(alignment: .bottom) {
            SlidingFeedPanelLayer(isPanelOpen: showFeedProjectPanel && useLivePlayer, cornerRadius: 0) {
                feedVideoLayer(project: project, useLivePlayer: useLivePlayer)
            } panelLayer: { width in
                feedProjectPanel(project: project, width: width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )

            if useLivePlayer {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Color.clear
                            .frame(width: min(72, max(52, geo.size.width * 0.14)))
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 48, pressing: { pressing in
                                setHomeFeedEdgeBoosting(pressing)
                            }, perform: {})

                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                toggleHomeFeedPlayback()
                            }

                        Color.clear
                            .frame(width: min(72, max(52, geo.size.width * 0.14)))
                            .contentShape(Rectangle())
                            .onLongPressGesture(minimumDuration: 0.12, maximumDistance: 48, pressing: { pressing in
                                setHomeFeedEdgeBoosting(pressing)
                            }, perform: {})
                    }
                    .padding(.horizontal, 84)
                    .padding(.top, 120)
                    .padding(.bottom, appBottomBarHeight + 140)
                }
            }

            if useLivePlayer && showHomePauseIndicator {
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
                        Button("@\(project.username)") {
                            if project.creatorId == myProfile?.creator_user_id {
                                selectedTab = 3
                            } else {
                                selectedCreatorRoute = CreatorRoute(id: project.creatorId)
                            }
                        }
                        .font(.headline)
                        .foregroundStyle(.white)

                        Text(project.caption)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.9))

                        fundingMeta(project: project)
                    }

                    Spacer(minLength: 12)

                    rightRail(project: project)
                }

                FeedPageIndicatorDots(currentIndex: showFeedProjectPanel ? 1 : 0, totalCount: 2)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, appBottomBarHeight - 14)
            .offset(y: 22)

            if useLivePlayer {
                FeedPlaybackScrubber(
                    progress: homeFeedPlaybackProgress,
                    onScrubBegan: {
                        isHomeFeedScrubbing = true
                    },
                    onScrubChanged: { progress in
                        homeFeedPlaybackProgress = progress
                        seekHomeFeedPlayer(toProgress: progress)
                    },
                    onScrubEnded: { progress in
                        homeFeedPlaybackProgress = progress
                        seekHomeFeedPlayer(toProgress: progress)
                        isHomeFeedScrubbing = false
                    }
                )
                .padding(.horizontal, 0)
                .padding(.bottom, -3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appBottomBar: some View {
        HStack(spacing: 0) {
            bottomTabButton(icon: "house.fill", tab: 0)
            bottomTabButton(icon: "magnifyingglass", tab: 1)
            bottomTabButton(icon: "plus.square.fill", tab: 2)
            bottomTabButton(icon: "person.fill", tab: 3)
        }
        .frame(height: appBottomBarHeight)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.98).ignoresSafeArea(edges: .bottom))
    }

    private func bottomTabButton(icon: String, tab: Int) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selectedTab == tab ? .white : .gray.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func feedVideoLayer(project: FeedProjectSummary, useLivePlayer: Bool) -> some View {
        Group {
            if useLivePlayer, let player = homeFeedPlayer {
                FillVideoPlayerView(player: player)
            } else if let thumbnail = project.thumbnailURL, let thumbnailURL = URL(string: thumbnail) {
                AsyncImage(url: thumbnailURL) { phase in
                    switch phase {
                    case .empty:
                        LinearGradient(
                            colors: [Color.blue.opacity(0.35), Color.black.opacity(0.6), Color.pink.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        LinearGradient(
                            colors: [Color.blue.opacity(0.35), Color.black.opacity(0.6), Color.pink.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    @unknown default:
                        LinearGradient(
                            colors: [Color.blue.opacity(0.35), Color.black.opacity(0.6), Color.pink.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
            } else {
                LinearGradient(
                    colors: [Color.blue.opacity(0.35), Color.black.opacity(0.6), Color.pink.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func feedProjectPanel(project: FeedProjectSummary, width: CGFloat) -> some View {
        let cachedDetail = feedProjectDetailsById[project.id]
        let isLoading = feedProjectDetailLoadingIds.contains(project.id)
        let errorText = feedProjectDetailErrorsById[project.id] ?? ""

        return VStack(alignment: .leading, spacing: 12) {
            Text("Project")
                .font(.headline)
                .foregroundStyle(.white)

            if let detail = cachedDetail {
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
            } else if isLoading {
                ProgressView("Loading project...")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.85))
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

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 18)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .background(Color.black.opacity(0.86))
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            Button {
                if project.isSupportedByCurrentUser { return }
                Task {
                    await presentSupportFlow(for: project)
                }
            } label: {
                Image(systemName: project.isSupportedByCurrentUser ? "checkmark" : "suit.heart.fill")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(project.isSupportedByCurrentUser ? Color.green.opacity(0.9) : Color.pink.opacity(0.9))
                    .foregroundStyle(.white)
                    .clipShape(Circle())
            }
            .accessibilityLabel(project.isSupportedByCurrentUser ? "Supported" : "Support")

            metricButton(
                icon: project.isLikedByCurrentUser ? "heart.fill" : "heart",
                value: project.likes,
                isActive: project.isLikedByCurrentUser
            ) {
                Task {
                    await toggleLike(for: project)
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
                metricView(icon: "text.bubble.fill", value: project.comments)
            }
            Button {
                showShare = true
            } label: {
                metricView(icon: "square.and.arrow.up.fill", value: 0, labelOverride: "Share")
            }
            Button {
                showFeedActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
            }
            .padding(.vertical, 6)
            Button {
                if project.creatorId == myProfile?.creator_user_id {
                    selectedTab = 3
                } else {
                    selectedCreatorRoute = CreatorRoute(id: project.creatorId)
                }
            } label: {
                feedCreatorAvatar(urlString: project.creatorAvatarURL, username: project.username)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private func feedCreatorAvatar(urlString: String?, username: String) -> some View {
        Group {
            if let avatar = urlString, let url = URL(string: avatar) {
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
            if urlString == nil {
                Text(String(username.prefix(1)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(Circle())
    }

    private func metricButton(icon: String, value: Int, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            metricView(icon: icon, value: value)
        }
        .foregroundStyle(isActive ? Color.pink : Color.white)
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
                                            if userId == myProfile?.creator_user_id {
                                                selectedTab = 3
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

    private var supportFlowSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                switch supportStep {
                case .planSelect:
                    planSelectView
                case .confirm:
                    confirmCardView
                case .checkout:
                    checkoutView
                case .result:
                    resultView
                }

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle("Support")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Close") {
                        showSupportFlow = false
                    }
                }
            }
            .task {
                await refreshLiveSupportProject()
            }
        }
    }

    private var planSelectView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Select plan")
                .font(.headline)

            if liveSupportProject == nil || realPlans.isEmpty {
                Text("No active project/plans available for support yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(realPlans) { plan in
                    Button {
                        selectedPlan = plan
                        supportStep = .confirm
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(.subheadline.bold())
                            Text(formatJPY(plan.priceMinor))
                                .font(.subheadline)
                            Text(plan.rewardSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var confirmCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Confirm")
                .font(.headline)

            cardRow(title: "Goal", value: formatJPY((supportTargetProject ?? liveSupportProject)?.goal_amount_minor ?? 0))
            cardRow(title: "Delivery", value: (supportTargetProject ?? liveSupportProject).map { formatDeliveryDate(from: $0.deadline_at) } ?? "-")
            cardRow(title: "Prototype", value: "Available")

            if let plan = selectedPlan {
                cardRow(title: "Plan", value: "\(plan.name) / \(formatJPY(plan.priceMinor))")
            }

            Button("Go to checkout") {
                supportStep = .checkout
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedPlan == nil)
        }
    }

    private var checkoutView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("3. Checkout")
                .font(.headline)
            Text("WebView / Apple Pay handoff is represented as a single action in this demo.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Complete payment") {
                Task {
                    await performSupportRequest()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("4. Result")
                .font(.headline)
            Text("Status: \(supportResultStatus)")
                .font(.body)
            if !supportResultMessage.isEmpty {
                Text(supportResultMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button("Close") {
                showSupportFlow = false
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func cardRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }

    private func performSupportRequest() async {
        errorText = ""
        guard let plan = selectedPlan else {
            errorText = "Select plan first"
            return
        }
        guard let targetProject = supportTargetProject ?? liveSupportProject else {
            errorText = "No active project available for support"
            return
        }
        let projectId = targetProject.id

        do {
            let prepare = try await client.prepareSupport(
                projectId: projectId,
                planId: plan.id,
                quantity: 1,
                idempotencyKey: "ios-m1-prepare-\(UUID().uuidString)"
            )
            let confirmed = try await client.confirmSupport(
                supportId: prepare.support_id,
                providerSessionId: "ios-m1-session-\(UUID().uuidString)",
                idempotencyKey: "ios-m1-confirm-\(UUID().uuidString)"
            )
            let canonical = await pollCanonicalSupportStatus(supportId: confirmed.support_id)
            supportResultStatus = canonical?.support_status ?? confirmed.support_status
            supportResultMessage = "Support recorded: \(confirmed.support_id.uuidString)"
            await refreshLiveSupportProject()
            if let creatorId = supportTargetProject?.creator_user_id,
               creatorId != liveSupportProject?.creator_user_id,
               let refreshedPage = try? await client.getCreatorPage(creatorUserId: creatorId) {
                supportTargetProject = refreshedPage.project
                if let updatedProject = refreshedPage.project {
                    feedProjects = feedProjects.map { existing in
                        guard existing.creatorId == creatorId else { return existing }
                        return FeedProjectSummary(
                            id: existing.id,
                            creatorId: existing.creatorId,
                            username: existing.username,
                            creatorAvatarURL: existing.creatorAvatarURL,
                            caption: existing.caption,
                            videoId: existing.videoId,
                            playbackURL: existing.playbackURL,
                            thumbnailURL: existing.thumbnailURL,
                            minPlanPriceMinor: updatedProject.minimum_plan?.price_minor ?? existing.minPlanPriceMinor,
                            goalAmountMinor: updatedProject.goal_amount_minor,
                            fundedAmountMinor: updatedProject.funded_amount_minor,
                            remainingDays: existing.remainingDays,
                            likes: existing.likes,
                            comments: existing.comments,
                            isLikedByCurrentUser: existing.isLikedByCurrentUser,
                            isSupportedByCurrentUser: refreshedPage.viewer_relationship.is_supported
                        )
                    }
                }
                NotificationCenter.default.post(
                    name: .lifecastRelationshipChanged,
                    object: nil,
                    userInfo: ["creatorUserId": creatorId.uuidString]
                )
            }
        } catch {
            supportResultStatus = "failed"
            supportResultMessage = ""
            errorText = "Support failed: \(error.localizedDescription)"
        }

        supportStep = .result
    }

    private func pollCanonicalSupportStatus(supportId: UUID) async -> SupportStatusResult? {
        for _ in 0..<5 {
            if let status = try? await client.getSupport(supportId: supportId) {
                if status.support_status == "succeeded" || status.support_status == "refunded" {
                    return status
                }
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        return try? await client.getSupport(supportId: supportId)
    }

    private func handleSupportFlowDismiss() {
        if supportEntryPoint == .project {
            selectedTab = 3
        }
        supportStep = .planSelect
        selectedPlan = nil
        errorText = ""
        supportTargetProject = nil
    }

    private func refreshLiveSupportProject() async {
        guard client.hasAuthSession else {
            await MainActor.run {
                liveSupportProject = nil
            }
            return
        }
        do {
            let project = try await client.getMyProject()
            await MainActor.run {
                liveSupportProject = project
            }
        } catch {
            await MainActor.run {
                liveSupportProject = nil
            }
        }
    }

    private func refreshMyVideos() async {
        guard client.hasAuthSession else {
            await MainActor.run {
                myVideos = []
                myVideosError = ""
            }
            return
        }
        do {
            let rows = try await client.listMyVideos()
            await MainActor.run {
                myVideos = rows
                myVideosError = ""
            }
        } catch {
            await MainActor.run {
                myVideosError = error.localizedDescription
            }
        }
    }

    private func refreshMyProfile() async {
        guard client.hasAuthSession else {
            await MainActor.run {
                myProfile = nil
                myProfileStats = nil
                isAuthenticated = false
            }
            return
        }
        do {
            let profile = try await client.getMyProfile()
            await MainActor.run {
                myProfile = profile.profile
                myProfileStats = profile.profile_stats
                isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                myProfile = nil
                myProfileStats = nil
                isAuthenticated = client.hasAuthSession
            }
        }
    }

    private func refreshAuthState() async {
        if !client.hasAuthSession {
            await MainActor.run {
                isAuthenticated = false
            }
            return
        }
        do {
            _ = try await client.getAuthMe()
            await MainActor.run {
                isAuthenticated = true
            }
        } catch {
            await MainActor.run {
                isAuthenticated = false
            }
        }
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
        guard let videoId = currentProject?.videoId else { return [] }
        return commentsByVideoId[videoId] ?? []
    }

    private func nextFeed() {
        guard currentFeedIndex < feedProjects.count - 1 else { return }
        homeFeedPlayer?.pause()
        closeFeedProjectPanel()
        currentFeedIndex += 1
        syncHomeFeedPlayer()
    }

    private func previousFeed() {
        guard currentFeedIndex > 0 else { return }
        homeFeedPlayer?.pause()
        closeFeedProjectPanel()
        currentFeedIndex -= 1
        syncHomeFeedPlayer()
    }

    private func presentSupportFlow(for project: FeedProjectSummary) async {
        do {
            let page = try await client.getCreatorPage(creatorUserId: project.creatorId)
            guard let target = page.project, let plans = target.plans, !plans.isEmpty else {
                await MainActor.run {
                    errorText = "This creator has no support plans yet."
                }
                return
            }
            await MainActor.run {
                supportEntryPoint = .feed
                supportTargetProject = target
                selectedPlan = SupportPlan(
                    id: plans[0].id,
                    name: plans[0].name,
                    priceMinor: plans[0].price_minor,
                    rewardSummary: plans[0].reward_summary
                )
                supportStep = .planSelect
                showSupportFlow = true
            }
        } catch {
            await MainActor.run {
                errorText = "Failed to load support plans: \(error.localizedDescription)"
            }
        }
    }

    private func refreshFeedProjectsFromAPI() async {
        let baseRows = (try? await client.listFeedProjects(limit: 20)) ?? []
        let rows: [FeedProjectRow]
        switch feedMode {
        case .forYou:
            rows = baseRows
        case .following:
            let followingCreatorIds = await fetchFollowingCreatorIds()
            rows = baseRows.filter { followingCreatorIds.contains($0.creator_user_id) }
        }

        let updated = await buildExpandedFeedProjects(from: rows)
        await MainActor.run {
            let previousVideoId = feedProjects[safe: currentFeedIndex]?.videoId
            feedProjects = updated
            if let previousVideoId,
               let retained = updated.firstIndex(where: { $0.videoId == previousVideoId }) {
                currentFeedIndex = retained
            } else {
                currentFeedIndex = min(currentFeedIndex, max(0, updated.count - 1))
            }
            syncHomeFeedPlayer()
        }
        await prefetchFeedProjectDetails(around: currentFeedIndex)
        await refreshCurrentVideoEngagement()
    }

    private func fetchFollowingCreatorIds() async -> Set<UUID> {
        guard let network = try? await client.getMyNetwork(tab: .following, limit: 200) else { return [] }
        return Set(network.rows.map(\.creator_user_id))
    }

    private func prefetchFeedProjectDetails(around index: Int) async {
        guard !feedProjects.isEmpty else { return }
        let indices = [index - 1, index, index + 1].filter { $0 >= 0 && $0 < feedProjects.count }
        for idx in indices {
            await loadFeedProjectDetail(for: feedProjects[idx], forceRefresh: false)
        }
    }

    private func refreshCurrentVideoEngagement() async {
        guard let videoId = currentProject?.videoId else { return }
        do {
            let engagement = try await client.getVideoEngagement(videoId: videoId)
            await MainActor.run {
                applyVideoEngagement(videoId: videoId, engagement: engagement)
            }
        } catch {
            // Keep previous numbers on transient failures.
        }
    }

    private func buildExpandedFeedProjects(from rows: [FeedProjectRow]) async -> [FeedProjectSummary] {
        var expanded: [FeedProjectSummary] = []
        var seenVideoIds: Set<UUID> = []

        for row in rows {
            var appendedForCreator = false
            if let page = try? await client.getCreatorPage(creatorUserId: row.creator_user_id) {
                let playableVideos = page.videos
                    .filter { $0.playback_url != nil }
                    .sorted { $0.created_at > $1.created_at }

                for video in playableVideos {
                    if seenVideoIds.contains(video.video_id) { continue }
                    seenVideoIds.insert(video.video_id)
                    appendedForCreator = true
                    expanded.append(
                        FeedProjectSummary(
                            id: row.project_id,
                            creatorId: row.creator_user_id,
                            username: row.username,
                            creatorAvatarURL: page.profile.avatar_url ?? row.creator_avatar_url,
                            caption: row.caption,
                            videoId: video.video_id,
                            playbackURL: video.playback_url,
                            thumbnailURL: video.thumbnail_url ?? row.thumbnail_url,
                            minPlanPriceMinor: row.min_plan_price_minor,
                            goalAmountMinor: row.goal_amount_minor,
                            fundedAmountMinor: row.funded_amount_minor,
                            remainingDays: row.remaining_days,
                            likes: row.likes,
                            comments: row.comments,
                            isLikedByCurrentUser: row.is_liked_by_current_user,
                            isSupportedByCurrentUser: row.is_supported_by_current_user
                        )
                    )
                }
            }

            if !appendedForCreator {
                expanded.append(
                    FeedProjectSummary(
                        id: row.project_id,
                        creatorId: row.creator_user_id,
                        username: row.username,
                        creatorAvatarURL: row.creator_avatar_url,
                        caption: row.caption,
                        videoId: row.video_id,
                        playbackURL: row.playback_url,
                        thumbnailURL: row.thumbnail_url,
                        minPlanPriceMinor: row.min_plan_price_minor,
                        goalAmountMinor: row.goal_amount_minor,
                        fundedAmountMinor: row.funded_amount_minor,
                        remainingDays: row.remaining_days,
                        likes: row.likes,
                        comments: row.comments,
                        isLikedByCurrentUser: row.is_liked_by_current_user,
                        isSupportedByCurrentUser: row.is_supported_by_current_user
                    )
                )
            }
        }

        return expanded
    }

    private func toggleLike(for project: FeedProjectSummary) async {
        guard let videoId = project.videoId else { return }
        guard isAuthenticated else {
            await MainActor.run {
                showAuthSheet = true
            }
            return
        }
        let previous = VideoEngagementResult(
            likes: project.likes,
            comments: project.comments,
            is_liked_by_current_user: project.isLikedByCurrentUser
        )
        let optimistic = VideoEngagementResult(
            likes: max(0, previous.likes + (previous.is_liked_by_current_user ? -1 : 1)),
            comments: previous.comments,
            is_liked_by_current_user: !previous.is_liked_by_current_user
        )
        await MainActor.run {
            applyVideoEngagement(videoId: videoId, engagement: optimistic)
        }
        do {
            let engagement: VideoEngagementResult
            if previous.is_liked_by_current_user {
                engagement = try await client.unlikeVideo(videoId: videoId)
            } else {
                engagement = try await client.likeVideo(videoId: videoId)
            }
            await MainActor.run {
                applyVideoEngagement(videoId: videoId, engagement: engagement)
            }
        } catch {
            await MainActor.run {
                applyVideoEngagement(videoId: videoId, engagement: previous)
                errorText = "Failed to update like: \(error.localizedDescription)"
            }
        }
    }

    private func loadCommentsForCurrentVideo() async {
        guard let videoId = currentProject?.videoId else {
            await MainActor.run {
                commentsByVideoId = [:]
            }
            return
        }
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
        guard let videoId = currentProject?.videoId else { return }
        guard isAuthenticated else {
            await MainActor.run {
                showAuthSheet = true
            }
            return
        }
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
                var list = commentsByVideoId[videoId] ?? []
                list.insert(mapVideoCommentRow(row), at: 0)
                commentsByVideoId[videoId] = list
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
        guard let videoId = currentProject?.videoId else { return }
        guard isAuthenticated else {
            await MainActor.run {
                showAuthSheet = true
            }
            return
        }
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

    private func applyVideoEngagement(videoId: UUID, engagement: VideoEngagementResult) {
        feedProjects = feedProjects.map { item in
            guard item.videoId == videoId else { return item }
            return FeedProjectSummary(
                id: item.id,
                creatorId: item.creatorId,
                username: item.username,
                creatorAvatarURL: item.creatorAvatarURL,
                caption: item.caption,
                videoId: item.videoId,
                playbackURL: item.playbackURL,
                thumbnailURL: item.thumbnailURL,
                minPlanPriceMinor: item.minPlanPriceMinor,
                goalAmountMinor: item.goalAmountMinor,
                fundedAmountMinor: item.fundedAmountMinor,
                remainingDays: item.remainingDays,
                likes: engagement.likes,
                comments: engagement.comments,
                isLikedByCurrentUser: engagement.is_liked_by_current_user,
                isSupportedByCurrentUser: item.isSupportedByCurrentUser
            )
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

    private func syncHomeFeedPlayer() {
        guard selectedTab == 0 else {
            setHomeFeedEdgeBoosting(false)
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
            detachHomeFeedPlayerObserver()
            for player in homeFeedPlayerCache.values {
                player.pause()
            }
            return
        }

        guard !feedProjects.isEmpty else {
            setHomeFeedEdgeBoosting(false)
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
            detachHomeFeedPlayerObserver()
            homeFeedPlaybackProgress = 0
            for player in homeFeedPlayerCache.values {
                player.pause()
            }
            homeFeedPlayerCache.removeAll()
            return
        }

        let project = feedProjects[max(0, min(currentFeedIndex, feedProjects.count - 1))]
        guard let playbackURL = project.playbackURL, let url = URL(string: playbackURL) else {
            setHomeFeedEdgeBoosting(false)
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
            detachHomeFeedPlayerObserver()
            homeFeedPlaybackProgress = 0
            return
        }

        let player: AVPlayer
        if let cached = homeFeedPlayerCache[url] {
            player = cached
        } else {
            let created = AVPlayer(url: url)
            created.actionAtItemEnd = .none
            homeFeedPlayerCache[url] = created
            player = created
        }

        if homeFeedPlayer !== player {
            homeFeedPlayer?.pause()
            homeFeedPlayer = player
            attachHomeFeedPlayerObserver(to: player)
        }

        if showFeedProjectPanel {
            player.pause()
        } else {
            player.play()
        }

        warmHomeFeedPlayerCache(around: currentFeedIndex)
    }

    private func attachHomeFeedPlayerObserver(to player: AVPlayer) {
        detachHomeFeedPlayerObserver()
        homeFeedPlaybackProgress = 0
        homeFeedObservedPlayer = player
        homeFeedPlayerObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { _ in
            guard let currentItem = player.currentItem else {
                if !isHomeFeedScrubbing {
                    homeFeedPlaybackProgress = 0
                }
                return
            }
            let duration = currentItem.duration.seconds
            guard duration.isFinite, duration > 0 else {
                if !isHomeFeedScrubbing {
                    homeFeedPlaybackProgress = 0
                }
                return
            }
            if !isHomeFeedScrubbing {
                homeFeedPlaybackProgress = min(max(player.currentTime().seconds / duration, 0), 1)
            }
        }
    }

    private func detachHomeFeedPlayerObserver() {
        guard let player = homeFeedObservedPlayer, let observer = homeFeedPlayerObserver else { return }
        player.removeTimeObserver(observer)
        homeFeedPlayerObserver = nil
        homeFeedObservedPlayer = nil
    }

    private func seekHomeFeedPlayer(toProgress progress: Double) {
        guard let player = homeFeedPlayer, let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let target = CMTime(seconds: duration * min(max(progress, 0), 1), preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func toggleHomeFeedPlayback() {
        guard let player = homeFeedPlayer else { return }
        if player.timeControlStatus == .playing {
            player.pause()
            showHomePauseIndicatorTemporarily()
        } else if !showFeedProjectPanel {
            player.play()
            if isHomeFeedEdgeBoosting {
                player.rate = 2.0
            }
        }
    }

    private func showHomePauseIndicatorTemporarily() {
        let token = UUID()
        homePauseIndicatorToken = token
        withAnimation(.easeOut(duration: 0.12)) {
            showHomePauseIndicator = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard homePauseIndicatorToken == token else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                showHomePauseIndicator = false
            }
        }
    }

    private func setHomeFeedEdgeBoosting(_ boosting: Bool) {
        guard boosting != isHomeFeedEdgeBoosting else { return }
        isHomeFeedEdgeBoosting = boosting
        guard let player = homeFeedPlayer else { return }
        guard player.timeControlStatus == .playing else { return }
        player.rate = boosting ? 2.0 : 1.0
    }

    private func warmHomeFeedPlayerCache(around index: Int) {
        var keep: Set<URL> = []
        for neighbor in [index - 1, index, index + 1] {
            guard neighbor >= 0, neighbor < feedProjects.count else { continue }
            guard let playback = feedProjects[neighbor].playbackURL, let url = URL(string: playback) else { continue }
            keep.insert(url)
            if homeFeedPlayerCache[url] == nil {
                let prepared = AVPlayer(url: url)
                prepared.actionAtItemEnd = .none
                prepared.pause()
                homeFeedPlayerCache[url] = prepared
            }
        }

        let stale = homeFeedPlayerCache.keys.filter { !keep.contains($0) }
        for key in stale {
            homeFeedPlayerCache[key]?.pause()
            homeFeedPlayerCache.removeValue(forKey: key)
        }
    }

    private func handleHomeFeedDragEnded(_ value: DragGesture.Value, project: FeedProjectSummary) {
        let dx = value.translation.width
        let dy = value.translation.height
        let action = resolveFeedSwipeAction(
            dx: dx,
            dy: dy,
            isPanelOpen: showFeedProjectPanel,
            canMoveNext: currentFeedIndex < feedProjects.count - 1,
            canMovePrevious: currentFeedIndex > 0
        )

        switch action {
        case .openPanel:
            openFeedProjectPanel(for: project)
        case .closePanel:
            closeFeedProjectPanel()
        case .nextItem:
            nextFeed()
        case .previousItem:
            previousFeed()
        case .none:
            break
        }
    }

    private func openFeedProjectPanel(for project: FeedProjectSummary) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showFeedProjectPanel = true
        }
        homeFeedPlayer?.pause()
        Task {
            await loadFeedProjectDetail(for: project, forceRefresh: false)
        }
    }

    private func closeFeedProjectPanel() {
        guard showFeedProjectPanel else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showFeedProjectPanel = false
        }
        syncHomeFeedPlayer()
    }

    private func closeFeedProjectPanelForVerticalMove() {
        guard showFeedProjectPanel else { return }
        showFeedProjectPanel = false
    }

    private func loadFeedProjectDetail(for project: FeedProjectSummary, forceRefresh: Bool) async {
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
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else { return iso8601 }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM"
        return out.string(from: date)
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private struct AuthEntrySheet: View {
    let client: LifeCastAPIClient
    let onAuthenticated: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var isLoading = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $email)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                    SecureField("Password", text: $password)
                    if isSignUp {
                        TextField("Username (optional)", text: $username)
                            .textInputAutocapitalization(.never)
                        TextField("Display name (optional)", text: $displayName)
                    }
                }

                Section("Sign in options") {
                    Button(isSignUp ? "Create account" : "Sign in with Email") {
                        Task { await submitEmailAuth() }
                    }
                    .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty)

                    Button("Continue with Google") {
                        Task { await continueOAuth(provider: "google") }
                    }
                    .disabled(isLoading)

                    Button("Continue with Apple") {
                        Task { await continueOAuth(provider: "apple") }
                    }
                    .disabled(isLoading)
                }

                Section {
                    Button(isSignUp ? "Already have an account? Sign in" : "Need an account? Sign up") {
                        isSignUp.toggle()
                        errorText = ""
                    }
                    .font(.footnote)
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(isSignUp ? "Sign Up" : "Sign In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .padding(20)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .lifecastAuthSessionUpdated)) { _ in
                onAuthenticated()
                dismiss()
            }
        }
    }

    private func submitEmailAuth() async {
        await MainActor.run {
            isLoading = true
            errorText = ""
        }
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSignUp {
                let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                _ = try await client.signUpWithEmail(
                    email: normalizedEmail,
                    password: password,
                    username: normalizedUsername.isEmpty ? nil : normalizedUsername,
                    displayName: normalizedDisplayName.isEmpty ? nil : normalizedDisplayName
                )
            } else {
                _ = try await client.signInWithEmail(email: normalizedEmail, password: password)
            }
            await MainActor.run {
                onAuthenticated()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }

    private func continueOAuth(provider: String) async {
        await MainActor.run {
            isLoading = true
            errorText = ""
        }
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            let url = try await client.oauthURL(provider: provider)
            await MainActor.run {
                openURL(url)
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }
}
