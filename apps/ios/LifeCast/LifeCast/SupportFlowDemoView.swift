import SwiftUI
import AVFoundation
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct SupportFlowDemoView: View {
    private let client = LifeCastAPIClient(baseURL: LifeCastRuntimeConfig.apiBaseURL)

    @State private var selectedTab = 0
    @State private var feedMode: FeedMode = .forYou
    @State private var currentFeedIndex = 0
    @State private var isHomeFeedVisible = false
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
    @State private var homeFeedPanelPageIndex = 0
    @State private var homeFeedPanelDragOffsetX: CGFloat = 0
    @State private var feedProjectDetailsById: [UUID: MyProjectResult] = [:]
    @State private var feedProjectDetailLoadingIds: Set<UUID> = []
    @State private var feedProjectDetailErrorsById: [UUID: String] = [:]
    @State private var creatorPageCacheById: [UUID: CreatorPublicPageResult] = [:]
    @State private var creatorPageLoadingIds: Set<UUID> = []
    @State private var showComments = false
    @State private var showShare = false
    @State private var selectedCreatorRoute: CreatorRoute? = nil

    @State private var supportEntryPoint: SupportEntryPoint = .feed
    @State private var supportStep: SupportStep = .planSelect
    @State private var showSupportFlow = false
    @State private var selectedPlan: SupportPlan? = nil
    @State private var supportResultStatus = "idle"
    @State private var supportResultMessage = ""
    @State private var supportResultAmountMinor: Int? = nil
    @State private var supportResultCurrency: String? = nil
    @State private var liveSupportProject: MyProjectResult?
    @State private var supportTargetProject: MyProjectResult?
    @State private var feedProjects: [FeedProjectSummary] = []
    @State private var supportedAmountByProjectId: [UUID: Int] = [:]
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
    @State private var trackedHomeVideoId: UUID?
    @State private var trackedHomeProjectId: UUID?
    @State private var trackedHomeDurationMs = 0
    @State private var trackedHomeMaxWatchMs = 0
    @State private var trackedHomeDidComplete = false

    @State private var errorText = ""
    @State private var isKeyboardVisible = false
    @State private var meHasUnsavedProjectEdits = false
    @State private var meProjectEditDiscardRequest = 0
    @State private var meTabSectionOverride = 0
    @State private var meTabSectionOverrideNonce = 0
    @State private var createPickerAutoOpenNonce = 0
    @State private var tabBeforeCreate = 0
    @State private var isCreateFullscreenPreview = false
    @State private var pendingAppTabAfterDiscard: Int?
    @State private var showDiscardProjectEditDialog = false

    private var bottomBarInset: CGFloat {
        isKeyboardVisible ? 0 : appBottomBarHeight
    }

    private var realPlans: [SupportPlan] {
        guard let target = supportTargetProject ?? liveSupportProject else { return [] }
        return (target.plans ?? []).map {
            SupportPlan(
                id: $0.id,
                name: $0.name,
                priceMinor: $0.price_minor,
                currency: $0.currency,
                rewardSummary: $0.reward_summary,
                detailDescription: $0.description,
                imageURL: $0.image_url
            )
        }
    }

    private var currentProject: FeedProjectSummary? {
        guard !feedProjects.isEmpty else { return nil }
        return feedProjects[max(0, min(currentFeedIndex, feedProjects.count - 1))]
    }

    private var isHomeProfileSwipeTransitioning: Bool {
        showFeedProjectPanel || homeFeedPanelDragOffsetX < 0
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                homeTab
                    .navigationDestination(item: $selectedCreatorRoute) { route in
                        CreatorPublicPageView(
                            client: client,
                            creatorId: route.id,
                            onRequireAuth: {
                                showAuthSheet = true
                            },
                            onSupportTap: { project, preferredPlanId in
                                guard isAuthenticated else {
                                    showAuthSheet = true
                                    return
                                }
                                Task {
                                    await refreshSupportedAmountFallbacks()
                                    await MainActor.run {
                                        openSupportFlowIfEligible(
                                            target: project,
                                            preferredPlanId: preferredPlanId,
                                            startAtConfirm: preferredPlanId != nil
                                        )
                                    }
                                }
                            },
                            initialPage: creatorPageCacheById[route.id],
                            onPageLoaded: { page in
                                cacheCreatorPage(page)
                            }
                        )
                    }
            }
                .tabItem { Image(systemName: "house.fill") }
                .tag(0)

            DiscoverSearchView(client: client, onSupportTap: { project, preferredPlanId in
                guard isAuthenticated else {
                    showAuthSheet = true
                    return
                }
                Task {
                    await refreshSupportedAmountFallbacks()
                    await MainActor.run {
                        openSupportFlowIfEligible(
                            target: project,
                            preferredPlanId: preferredPlanId,
                            startAtConfirm: preferredPlanId != nil
                        )
                    }
                }
            })
                .safeAreaPadding(.bottom, bottomBarInset)
                .tabItem { Image(systemName: "magnifyingglass") }
                .tag(1)

            UploadCreateView(
                client: client,
                isAuthenticated: isAuthenticated,
                autoOpenPickerNonce: createPickerAutoOpenNonce,
                onUploadReady: {
                Task {
                    await refreshMyVideos()
                }
                meTabSectionOverride = 1
                meTabSectionOverrideNonce += 1
                selectedTab = 3
            }, onOpenAuth: {
                showAuthSheet = true
            }, onAutoOpenPickerCancelled: {
                let fallbackTab = 0
                selectedTab = (tabBeforeCreate == 2) ? fallbackTab : tabBeforeCreate
            }, onPreviewBackToPreviousTab: {
                let fallbackTab = 0
                selectedTab = (tabBeforeCreate == 2) ? fallbackTab : tabBeforeCreate
            }, onFullscreenPreviewChanged: { isFullscreen in
                isCreateFullscreenPreview = isFullscreen
            })
                .safeAreaPadding(.bottom, isCreateFullscreenPreview ? 0 : bottomBarInset)
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
                selectedIndexOverride: meTabSectionOverride,
                selectedIndexOverrideNonce: meTabSectionOverrideNonce,
                onProjectEditUnsavedChanged: { hasUnsaved in
                    meHasUnsavedProjectEdits = hasUnsaved
                },
                projectEditDiscardRequest: meProjectEditDiscardRequest
            )
            .safeAreaPadding(.bottom, bottomBarInset)
            .tabItem { Image(systemName: "person.fill") }
            .tag(3)
        }
        .toolbar(.hidden, for: .tabBar)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .bottom) {
            if !isKeyboardVisible && !isCreateFullscreenPreview {
                appBottomBar
            }
        }
        .sheet(isPresented: $showComments) {
            commentsSheet
        }
        .sheet(isPresented: $showShare) {
            homeShareActionsSheet
        }
        .sheet(isPresented: $showFeedActions) {
            homeVideoOptionsSheet
        }
        .confirmationDialog("Discard changes?", isPresented: $showDiscardProjectEditDialog, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                guard let nextTab = pendingAppTabAfterDiscard else { return }
                pendingAppTabAfterDiscard = nil
                meHasUnsavedProjectEdits = false
                meProjectEditDiscardRequest += 1
                selectedTab = nextTab
            }
            Button("Cancel", role: .cancel) {
                pendingAppTabAfterDiscard = nil
            }
        } message: {
            Text("Your project edits are not saved.")
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
            async let feedTask: Void = refreshFeedProjectsFromAPI()
            async let authTask: Void = refreshAuthState()
            async let videosTask: Void = refreshMyVideos()
            async let supportTask: Void = refreshLiveSupportProject()
            async let profileTask: Void = refreshMyProfile()
            await feedTask
            _ = await (authTask, videosTask, supportTask, profileTask)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 2 {
                createPickerAutoOpenNonce += 1
                transitionHomeTrackedVideo(to: nil, projectId: nil)
                setHomeFeedEdgeBoosting(false)
                homeFeedPlayer?.pause()
                homeFeedPlayer = nil
                for player in homeFeedPlayerCache.values {
                    player.pause()
                }
            } else if newValue == 3 {
                transitionHomeTrackedVideo(to: nil, projectId: nil)
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
                isCreateFullscreenPreview = false
                transitionHomeTrackedVideo(to: nil, projectId: nil)
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
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            isKeyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
            isKeyboardVisible = false
        }
        .onChange(of: currentFeedIndex) { _, _ in
            syncHomeFeedPlayer()
            Task {
                await prefetchCreatorPages(around: currentFeedIndex)
                await prefetchFeedProjectDetails(around: currentFeedIndex)
                await refreshCurrentVideoEngagement()
            }
        }
        .onChange(of: feedMode) { _, _ in
            Task {
                await refreshFeedProjectsFromAPI()
            }
        }
        .onChange(of: selectedCreatorRoute) { _, newValue in
            if newValue != nil {
                homeFeedPlayer?.pause()
            } else if selectedTab == 0 && !showFeedProjectPanel {
                homeFeedPanelDragOffsetX = 0
                syncHomeFeedPlayer()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { note in
            guard let endedItem = note.object as? AVPlayerItem else { return }
            guard let current = homeFeedPlayer, current.currentItem === endedItem else { return }
            trackedHomeDidComplete = true
            trackedHomeMaxWatchMs = max(trackedHomeMaxWatchMs, trackedHomeDurationMs)
            if let videoId = trackedHomeVideoId, let projectId = trackedHomeProjectId, trackedHomeDurationMs > 0 {
                Task {
                    await client.trackVideoWatchCompleted(
                        videoId: videoId,
                        projectId: projectId,
                        watchDurationMs: trackedHomeDurationMs,
                        videoDurationMs: trackedHomeDurationMs
                    )
                }
            }
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
                        verticalDragDisabled: showFeedProjectPanel,
                        allowHorizontalChildDrag: showFeedProjectPanel,
                        horizontalActionExclusionBottomInset: 28,
                        onWillMove: {
                            homeFeedPlayer?.pause()
                            closeFeedProjectPanelForVerticalMove()
                        },
                        onDidMove: {
                            syncHomeFeedPlayer()
                        },
                        onHorizontalDragChanged: { dx in
                            if showFeedProjectPanel {
                                guard homeFeedPanelPageIndex == 0 else {
                                    homeFeedPanelDragOffsetX = 0
                                    return
                                }
                                homeFeedPanelDragOffsetX = max(0, dx)
                                return
                            }
                            homeFeedPanelDragOffsetX = min(0, dx)
                            if dx < 0, let project = currentProject {
                                Task {
                                    await prefetchCreatorPage(for: project.creatorId)
                                }
                            }
                        },
                        onNonVerticalEnded: { value in
                            handleHomeFeedDragEnded(value)
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
                if !isHomeProfileSwipeTransitioning {
                    homeFeedHeader
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: appBottomBarHeight)
        }
        .onAppear {
            isHomeFeedVisible = true
            syncHomeFeedPlayer()
        }
        .onDisappear {
            isHomeFeedVisible = false
            flushHomeTrackedPlaybackProgress()
            homeFeedPlayer?.pause()
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
        let isProfilePanelPresented = useLivePlayer && showFeedProjectPanel
        let isProfileSwipeTransition = useLivePlayer && homeFeedPanelDragOffsetX < 0
        let shouldHideFeedChrome = isProfilePanelPresented || isProfileSwipeTransition

        return ZStack(alignment: .bottom) {
            SlidingFeedPanelLayer(
                isPanelOpen: showFeedProjectPanel && useLivePlayer,
                cornerRadius: 0,
                dragOffsetX: useLivePlayer ? homeFeedPanelDragOffsetX : 0
            ) {
                feedVideoLayer(project: project, useLivePlayer: useLivePlayer)
            } panelLayer: { width in
                feedCreatorProfilePanel(
                    project: project,
                    width: width,
                    isActive: useLivePlayer && (showFeedProjectPanel || homeFeedPanelDragOffsetX < 0)
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !shouldHideFeedChrome {
                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }

            if useLivePlayer && !shouldHideFeedChrome {
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
                            .gesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        Task {
                                            await likeOnDoubleTap(for: project)
                                        }
                                    }
                                    .exclusively(before: TapGesture(count: 1).onEnded {
                                        toggleHomeFeedPlayback()
                                    })
                            )

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

            if useLivePlayer && showHomePauseIndicator && !shouldHideFeedChrome {
                Image(systemName: "pause.fill")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .transition(.opacity)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            if !shouldHideFeedChrome {
                VStack(spacing: 8) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 10) {
                            let cachedProject = creatorPageCacheById[project.creatorId]?.project
                            let fallbackCommittedMinor = supportedAmountByProjectId[project.id] ?? 0
                            let committedSupportMinor = cachedProject?.viewer_committed_support_amount_minor
                                ?? project.viewerCommittedSupportAmountMinor
                                ?? fallbackCommittedMinor
                            let supportedPlanPriceMinor = cachedProject?.viewer_supported_plan_price_minor
                                ?? project.viewerSupportedPlanPriceMinor
                                ?? fallbackCommittedMinor
                            let committedBaselineMinor = max(max(committedSupportMinor, supportedPlanPriceMinor), fallbackCommittedMinor)
                            let canUpgrade = (cachedProject?.viewer_has_upgradeable_plan == true)
                                || project.viewerHasUpgradeablePlan
                                || (
                                    committedBaselineMinor > 0
                                        && (cachedProject?.plans ?? []).contains(where: { $0.price_minor > committedBaselineMinor })
                                )
                            let isSupported = committedBaselineMinor > 0 || project.isSupportedByCurrentUser
                            FeedPrimaryActionButton(
                                title: canUpgrade ? "Upgrade" : (isSupported ? "Supported" : "Support"),
                                isChecked: !canUpgrade && isSupported,
                                isNeutral: false
                            ) {
                                if !canUpgrade && isSupported { return }
                                Task {
                                    await presentSupportFlow(for: project)
                                }
                            }

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

                    FeedPageIndicatorDots(
                        currentIndex: 0,
                        totalCount: 1
                    )
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, appBottomBarHeight - 14)
                .offset(y: 22)
            }

            if useLivePlayer && !shouldHideFeedChrome {
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
            requestAppTabSelection(tab)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(selectedTab == tab ? .white : .gray.opacity(0.85))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func requestAppTabSelection(_ tab: Int) {
        if tab == 0 {
            resetHomeTabToFeedRoot()
        }
        if tab == 2 && selectedTab == 2 {
            createPickerAutoOpenNonce += 1
            return
        }
        if selectedTab == tab {
            return
        }
        if tab == 2 && !isAuthenticated {
            showAuthSheet = true
            return
        }
        if selectedTab == 3 && meHasUnsavedProjectEdits && tab != 3 {
            pendingAppTabAfterDiscard = tab
            showDiscardProjectEditDialog = true
            return
        }
        if tab == 2 {
            tabBeforeCreate = selectedTab
        }
        selectedTab = tab
    }

    private func resetHomeTabToFeedRoot() {
        selectedCreatorRoute = nil
        closeFeedProjectPanel()
        showComments = false
        showShare = false
        showFeedActions = false
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
        let plans = cachedDetail?.plans ?? []
        let pageCount = max(1, plans.count + 1)
        let panelPageSelection = Binding<Int>(
            get: { min(max(homeFeedPanelPageIndex, 0), pageCount - 1) },
            set: { homeFeedPanelPageIndex = min(max($0, 0), pageCount - 1) }
        )

        return VStack(alignment: .leading, spacing: 12) {
            InteractiveHorizontalPager(
                pageCount: pageCount,
                currentIndex: panelPageSelection,
                onSwipeBeyondLeadingEdge: {
                    closeFeedProjectPanel()
                },
                onLeadingEdgeDragChanged: { dx in
                    guard showFeedProjectPanel, homeFeedPanelPageIndex == 0 else {
                        homeFeedPanelDragOffsetX = 0
                        return
                    }
                    homeFeedPanelDragOffsetX = max(0, dx)
                }
            ) { idx in
                let tappedPlan = idx > 0 ? plans[idx - 1] : nil
                VStack(alignment: .leading, spacing: 12) {
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
                                await likeOnDoubleTap(for: project)
                            }
                        }
                        .exclusively(before: TapGesture(count: 1).onEnded {
                            Task {
                                await presentSupportFlow(
                                    for: project,
                                    prefetchedDetail: cachedDetail,
                                    preferredPlanId: tappedPlan?.id,
                                    startAtConfirm: tappedPlan != nil
                                )
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
        .contentShape(Rectangle())
        .background(FeedProjectPanelBackground())
    }

    private func feedCreatorProfilePanel(project: FeedProjectSummary, width: CGFloat, isActive: Bool) -> some View {
        let cachedPage = creatorPageCacheById[project.creatorId]

        return Group {
            if isActive {
                CreatorPublicPageView(
                    client: client,
                    creatorId: project.creatorId,
                    onRequireAuth: {
                        showAuthSheet = true
                    },
                    onSupportTap: { project, preferredPlanId in
                        guard isAuthenticated else {
                            showAuthSheet = true
                            return
                        }
                        openSupportFlowIfEligible(
                            target: project,
                            preferredPlanId: preferredPlanId,
                            startAtConfirm: preferredPlanId != nil
                        )
                    },
                    onBackTap: {
                        closeFeedProjectPanel()
                    },
                    initialPage: cachedPage,
                    onPageLoaded: { page in
                        cacheCreatorPage(page)
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                Color.white
            }
        }
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }


    private func homeFeedPanelPageCount(for project: FeedProjectSummary) -> Int {
        1 + (feedProjectDetailsById[project.id]?.plans?.count ?? 0)
    }

    private func clampedHomeFeedPanelPageIndex(for project: FeedProjectSummary) -> Int {
        min(max(homeFeedPanelPageIndex, 0), max(homeFeedPanelPageCount(for: project) - 1, 0))
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            FeedMetricButton(
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
                FeedMetricView(icon: "text.bubble.fill", value: project.comments)
            }
            Button {
                showShare = true
            } label: {
                FeedMetricView(icon: "square.and.arrow.up.fill", value: 0, labelOverride: "Share")
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
                FeedCreatorAvatarView(urlString: project.creatorAvatarURL, username: project.username)
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
    }

    private var homeShareActionsSheet: some View {
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

    private var homeVideoOptionsSheet: some View {
        VStack(spacing: 12) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 56, height: 5)
                .padding(.top, 8)

            Text("Video options")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            FeedActionSheetRow(icon: "eye.slash", title: "Not recommend like this") {
                showFeedActions = false
                errorText = "Preference saved."
            }
            FeedActionSheetRow(icon: "flag", title: "Report", destructive: true) {
                showFeedActions = false
                errorText = "Thanks. We received your report."
            }

            Button("Cancel") {
                showFeedActions = false
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
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.ultraThinMaterial)
    }

    private func fundingMeta(project: FeedProjectSummary) -> some View {
        FeedFundingMetaView(project: project)
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
                    if isAuthenticated {
                        TextField("Add comment...", text: $pendingCommentBody)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Button {
                            showAuthSheet = true
                        } label: {
                            HStack {
                                Text("Add comment...")
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.35), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
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

                if !errorText.isEmpty && supportStep != .result {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Spacer(minLength: 0)
            }
            .padding(16)
            .navigationTitle(supportFlowTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let previousStep = previousSupportStep {
                        Button {
                            supportStep = previousStep
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    }
                }
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
        VStack(alignment: .leading, spacing: 14) {
            if (supportTargetProject ?? liveSupportProject) == nil || realPlans.isEmpty {
                Text("No active project/plans available for support yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose a plan")
                    .font(.headline)
                Text("You can review details before checkout.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(realPlans) { plan in
                    let isSelected = selectedPlan?.id == plan.id
                    let additionalPaymentMinor = payableAmount(for: plan)
                    let isEligible = additionalPaymentMinor > 0
                    Button {
                        if !isEligible {
                            errorText = "Already supported at this tier. Choose a higher plan to upgrade."
                            return
                        }
                        errorText = ""
                        if isSelected {
                            supportStep = .confirm
                        } else {
                            selectedPlan = plan
                        }
                    } label: {
                        HStack(spacing: 12) {
                            supportPlanThumbnail(plan: plan, width: 104, height: 72)

                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Text(plan.name)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.subheadline)
                                            .foregroundStyle(.blue)
                                    }
                                }
                                Text(supportPlanPrice(plan))
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(.blue)
                                    .monospacedDigit()
                                if currentCommittedSupportMinor > 0 {
                                    Text("Pay now \(supportMinorPrice(additionalPaymentMinor, currency: plan.currency))")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(isEligible ? .green : .secondary)
                                }
                                Text(plan.rewardSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background((isSelected ? Color.blue.opacity(0.1) : Color.white).opacity(isEligible ? 1.0 : 0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var confirmCardView: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let plan = selectedPlan {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Review your support")
                        .font(.headline)

                    supportPlanHeroImage(plan: plan)

                    Text(plan.name)
                        .font(.title2.weight(.bold))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    Label(plan.rewardSummary, systemImage: "gift.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = planSummaryDescription(plan) {
                        Text(description)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Divider()

                    HStack(alignment: .firstTextBaseline) {
                        Text("Plan Amount")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(supportPlanPrice(plan))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    if currentCommittedSupportMinor > 0 {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Already Supported")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(supportMinorPrice(currentCommittedSupportMinor, currency: plan.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack(alignment: .firstTextBaseline) {
                            Text("Pay Now")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(supportMinorPrice(selectedPlanPayableMinor, currency: plan.currency))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
            }

            Button("Go to checkout") {
                supportStep = .checkout
            }
            .buttonStyle(.plain)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.58, blue: 1.0), Color(red: 0.00, green: 0.47, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.00, green: 0.47, blue: 0.95).opacity(0.32), radius: 12, x: 0, y: 6)
            .disabled(selectedPlan == nil || selectedPlanPayableMinor <= 0)
            .opacity((selectedPlan == nil || selectedPlanPayableMinor <= 0) ? 0.55 : 1.0)
        }
    }

    private var checkoutView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review your order and continue to secure payment.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let plan = selectedPlan {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        supportPlanThumbnail(plan: plan, width: 96, height: 68)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(plan.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(2)
                            Text(plan.rewardSummary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    HStack {
                        Text(currentCommittedSupportMinor > 0 ? "Selected plan value" : "Total")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(supportPlanPrice(plan))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.blue)
                            .monospacedDigit()
                    }
                    if currentCommittedSupportMinor > 0 {
                        HStack {
                            Text("Already supported")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(supportMinorPrice(currentCommittedSupportMinor, currency: plan.currency))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack {
                            Text("Charge now")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(supportMinorPrice(selectedPlanPayableMinor, currency: plan.currency))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.green)
                                .monospacedDigit()
                        }
                    }
                }
                .padding(14)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            }

            VStack(alignment: .leading, spacing: 10) {
                Label("Payment method", systemImage: "creditcard.fill")
                    .font(.subheadline.weight(.semibold))
                Text("Apple Pay / Card (will be connected in the next step)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Label("Your payment will be processed on a secure provider page.", systemImage: "lock.shield.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button("Continue to payment") {
                Task {
                    await performSupportRequest()
                }
            }
            .buttonStyle(.plain)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.58, blue: 1.0), Color(red: 0.00, green: 0.47, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.00, green: 0.47, blue: 0.95).opacity(0.32), radius: 12, x: 0, y: 6)
            .disabled(selectedPlan == nil || selectedPlanPayableMinor <= 0)
            .opacity((selectedPlan == nil || selectedPlanPayableMinor <= 0) ? 0.55 : 1.0)
        }
    }

    private var resultView: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Payment result")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: supportResultSymbolName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(supportResultTint)
                        .frame(width: 34, height: 34)
                        .background(supportResultTint.opacity(0.14))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(supportResultHeadline)
                            .font(.headline)
                        Text("Status: \(supportResultStatus)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                if let plan = selectedPlan {
                    let resultAmountMinor = supportResultAmountMinor ?? selectedPlanPayableMinor
                    let resultCurrency = supportResultCurrency ?? plan.currency
                    summaryRow(title: "Plan", value: plan.name)
                    summaryRow(
                        title: "Amount",
                        value: supportMinorPrice(resultAmountMinor, currency: resultCurrency),
                        isEmphasized: true
                    )
                }

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .lineLimit(nil)
                }
            }
            .padding(14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)

            if supportResultStatus == "failed" {
                Button("Back to checkout") {
                    supportStep = .checkout
                }
                .buttonStyle(.plain)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.gray.opacity(0.24), lineWidth: 1)
                )
            }

            Button("Close") {
                showSupportFlow = false
            }
            .buttonStyle(.plain)
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [Color(red: 0.10, green: 0.58, blue: 1.0), Color(red: 0.00, green: 0.47, blue: 0.95)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: Color(red: 0.00, green: 0.47, blue: 0.95).opacity(0.32), radius: 12, x: 0, y: 6)
        }
    }

    private var supportResultSymbolName: String {
        switch supportResultStatus {
        case "succeeded":
            return "checkmark.circle.fill"
        case "refunded":
            return "arrow.uturn.backward.circle.fill"
        case "pending_confirmation":
            return "clock.badge.checkmark.fill"
        case "failed":
            return "xmark.octagon.fill"
        default:
            return "info.circle.fill"
        }
    }

    private var supportResultHeadline: String {
        switch supportResultStatus {
        case "succeeded":
            return "Support completed"
        case "refunded":
            return "Support refunded"
        case "pending_confirmation":
            return "Payment processing"
        case "failed":
            return "Payment failed"
        default:
            return "Support updated"
        }
    }

    private var supportResultTint: Color {
        switch supportResultStatus {
        case "succeeded":
            return .green
        case "refunded":
            return .orange
        case "pending_confirmation":
            return .blue
        case "failed":
            return .red
        default:
            return .secondary
        }
    }

    private var supportFlowTitle: String {
        switch supportStep {
        case .planSelect:
            return currentCommittedSupportMinor > 0 ? "Select Upgrade Plan" : "Select Plan"
        case .confirm:
            return currentCommittedSupportMinor > 0 ? "Confirm Upgrade" : "Confirm"
        case .checkout:
            return "Checkout"
        case .result:
            return "Payment Result"
        }
    }

    private var previousSupportStep: SupportStep? {
        switch supportStep {
        case .planSelect:
            return nil
        case .confirm:
            return .planSelect
        case .checkout:
            return .confirm
        case .result:
            return .checkout
        }
    }

    private var currentCommittedSupportMinor: Int {
        let committed = supportTargetProject?.viewer_committed_support_amount_minor ?? 0
        let supportedPlanPrice = supportTargetProject?.viewer_supported_plan_price_minor ?? 0
        return max(0, max(committed, supportedPlanPrice))
    }

    private var selectedPlanPayableMinor: Int {
        guard let plan = selectedPlan else { return 0 }
        return payableAmount(for: plan)
    }

    private func payableAmount(for plan: SupportPlan) -> Int {
        if currentCommittedSupportMinor <= 0 {
            return plan.priceMinor
        }
        return max(plan.priceMinor - currentCommittedSupportMinor, 0)
    }

    private func supportPlanPrice(_ plan: SupportPlan) -> String {
        supportMinorPrice(plan.priceMinor, currency: plan.currency)
    }

    private func supportMinorPrice(_ amountMinor: Int, currency: String) -> String {
        if currency.uppercased() == "JPY" {
            return feedFormatJPY(amountMinor)
        }
        return "\(amountMinor.formatted()) \(currency.uppercased())"
    }

    private func planSummaryDescription(_ plan: SupportPlan) -> String? {
        guard let value = plan.detailDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func supportPlanThumbnail(plan: SupportPlan, width: CGFloat, height: CGFloat) -> some View {
        supportPlanImageContent(plan: plan)
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func supportPlanHeroImage(plan: SupportPlan) -> some View {
        supportPlanImageContent(plan: plan)
            .frame(maxWidth: .infinity)
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func supportPlanImageContent(plan: SupportPlan) -> some View {
        Group {
            if let raw = plan.imageURL, let url = URL(string: raw) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholderThumbnail
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        placeholderThumbnail
                    @unknown default:
                        placeholderThumbnail
                    }
                }
            } else {
                placeholderThumbnail
            }
        }
    }

    private var placeholderThumbnail: some View {
        LinearGradient(
            colors: [Color.gray.opacity(0.25), Color.gray.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "photo")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryRow(title: String, value: String, isEmphasized: Bool = false) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
                .fontWeight(isEmphasized ? .semibold : .regular)
        }
        .font(.subheadline)
    }

    private func performSupportRequest() async {
        errorText = ""
        supportResultAmountMinor = nil
        supportResultCurrency = nil
        guard let plan = selectedPlan else {
            errorText = "Select plan first"
            return
        }
        guard selectedPlanPayableMinor > 0 else {
            errorText = "Choose a higher plan to upgrade."
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
            let settledCurrency = canonical?.currency ?? confirmed.currency ?? plan.currency
            let chargedMinor = prepare.amount_minor ?? selectedPlanPayableMinor
            supportResultAmountMinor = chargedMinor
            supportResultCurrency = settledCurrency
            let chargedText = supportMinorPrice(chargedMinor, currency: settledCurrency)
            supportResultMessage = "Payment recorded: \(chargedText) (\(confirmed.support_id.uuidString))"
            await refreshLiveSupportProject()
            await refreshSupportedAmountFallbacks()
            if let creatorId = supportTargetProject?.creator_user_id,
               creatorId != liveSupportProject?.creator_user_id,
               let refreshedPage = try? await client.getCreatorPage(creatorUserId: creatorId) {
                await MainActor.run {
                    cacheCreatorPage(refreshedPage)
                }
                supportTargetProject = refreshedPage.project
                if let updatedProject = refreshedPage.project {
                    feedProjects = feedProjects.map { existing in
                        guard existing.creatorId == creatorId else { return existing }
                        let fallbackSupportMinor = supportedAmountByProjectId[updatedProject.id] ?? 0
                        let committedBaselineMinor = max(
                            max(updatedProject.viewer_committed_support_amount_minor ?? 0, updatedProject.viewer_supported_plan_price_minor ?? 0),
                            fallbackSupportMinor
                        )
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
                            isSupportedByCurrentUser: committedBaselineMinor > 0,
                            viewerCommittedSupportAmountMinor: updatedProject.viewer_committed_support_amount_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                            viewerSupportedPlanPriceMinor: updatedProject.viewer_supported_plan_price_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                            viewerHasUpgradeablePlan: (updatedProject.viewer_has_upgradeable_plan == true)
                                || (committedBaselineMinor > 0 && (updatedProject.plans ?? []).contains(where: { $0.price_minor > committedBaselineMinor }))
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
            supportResultAmountMinor = nil
            supportResultCurrency = nil
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
        supportResultAmountMinor = nil
        supportResultCurrency = nil
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
                supportedAmountByProjectId = [:]
            }
            return
        }
        do {
            _ = try await client.getAuthMe()
            await MainActor.run {
                isAuthenticated = true
            }
            await refreshSupportedAmountFallbacks()
        } catch {
            await MainActor.run {
                isAuthenticated = false
                supportedAmountByProjectId = [:]
            }
        }
    }

    private func refreshSupportedAmountFallbacks() async {
        guard client.hasAuthSession else {
            await MainActor.run {
                supportedAmountByProjectId = [:]
            }
            return
        }
        do {
            let rows = try await client.getMySupportedProjects(limit: 100)
            var mapped: [UUID: Int] = [:]
            for row in rows {
                mapped[row.project_id, default: 0] += row.amount_minor
            }
            await MainActor.run {
                supportedAmountByProjectId = mapped
            }
        } catch {
            // Keep existing cache on transient failures.
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

    private func presentSupportFlow(
        for project: FeedProjectSummary,
        prefetchedDetail: MyProjectResult? = nil,
        preferredPlanId: UUID? = nil,
        startAtConfirm: Bool = false
    ) async {
        guard isAuthenticated else {
            await MainActor.run {
                showAuthSheet = true
            }
            return
        }
        await refreshSupportedAmountFallbacks()

        if let detail = prefetchedDetail {
            await MainActor.run {
                openSupportFlowIfEligible(
                    target: detail,
                    preferredPlanId: preferredPlanId,
                    startAtConfirm: startAtConfirm
                )
            }
            return
        }

        do {
            let page = try await client.getCreatorPage(creatorUserId: project.creatorId)
            guard let target = page.project else {
                await MainActor.run {
                    errorText = "This creator has no support plans yet."
                }
                return
            }
            await MainActor.run {
                cacheCreatorPage(page)
                openSupportFlowIfEligible(
                    target: target,
                    preferredPlanId: preferredPlanId,
                    startAtConfirm: startAtConfirm
                )
            }
        } catch {
            await MainActor.run {
                errorText = "Failed to load support plans: \(error.localizedDescription)"
            }
        }
    }

    private func openSupportFlowIfEligible(
        target: MyProjectResult,
        preferredPlanId: UUID?,
        startAtConfirm: Bool
    ) {
        var resolvedTarget = target
        let plans = target.plans ?? []
        guard !plans.isEmpty else {
            errorText = "This creator has no support plans yet."
            return
        }

        let fallbackSupportMinor = supportedAmountByProjectId[target.id] ?? 0
        if fallbackSupportMinor > 0 {
            if (resolvedTarget.viewer_committed_support_amount_minor ?? 0) <= 0 {
                resolvedTarget.viewer_committed_support_amount_minor = fallbackSupportMinor
            }
            if (resolvedTarget.viewer_supported_plan_price_minor ?? 0) <= 0 {
                resolvedTarget.viewer_supported_plan_price_minor = fallbackSupportMinor
            }
        }

        let committedSupportMinor = max(
            resolvedTarget.viewer_committed_support_amount_minor ?? 0,
            resolvedTarget.viewer_supported_plan_price_minor ?? 0
        )
        let canUpgrade = (resolvedTarget.viewer_has_upgradeable_plan == true)
            || (committedSupportMinor > 0 && plans.contains(where: { $0.price_minor > committedSupportMinor }))
        if resolvedTarget.viewer_has_upgradeable_plan == nil {
            resolvedTarget.viewer_has_upgradeable_plan = canUpgrade
        }
        if committedSupportMinor > 0 && !canUpgrade {
            errorText = "Already supported at the highest available tier."
            return
        }

        let eligiblePlans = plans.filter { plan in
            committedSupportMinor <= 0 || plan.price_minor > committedSupportMinor
        }
        guard !eligiblePlans.isEmpty else {
            errorText = "No higher plan available to upgrade."
            return
        }

        supportEntryPoint = .feed
        supportTargetProject = resolvedTarget
        let chosen = plans.first(where: { $0.id == preferredPlanId && (committedSupportMinor <= 0 || $0.price_minor > committedSupportMinor) })
            ?? eligiblePlans[0]
        selectedPlan = SupportPlan(
            id: chosen.id,
            name: chosen.name,
            priceMinor: chosen.price_minor,
            currency: chosen.currency,
            rewardSummary: chosen.reward_summary,
            detailDescription: chosen.description,
            imageURL: chosen.image_url
        )
        supportStep = startAtConfirm ? .confirm : .planSelect
        showSupportFlow = true
        errorText = ""
    }

    private func refreshFeedProjectsFromAPI() async {
        await refreshSupportedAmountFallbacks()
        let baseRows = (try? await client.listFeedProjects(limit: 20)) ?? []
        let rows: [FeedProjectRow]
        switch feedMode {
        case .forYou:
            rows = baseRows
        case .following:
            let followingCreatorIds = await fetchFollowingCreatorIds()
            rows = baseRows.filter { followingCreatorIds.contains($0.creator_user_id) }
        }

        let quick = buildFastFeedProjects(from: rows)
        await MainActor.run {
            let previousVideoId = feedProjects[safe: currentFeedIndex]?.videoId
            feedProjects = quick
            if let previousVideoId,
               let retained = quick.firstIndex(where: { $0.videoId == previousVideoId }) {
                currentFeedIndex = retained
            } else {
                currentFeedIndex = min(currentFeedIndex, max(0, quick.count - 1))
            }
            syncHomeFeedPlayer()
        }

        let updated = await buildExpandedFeedProjects(from: rows)
        await MainActor.run {
            let previousVideoId = feedProjects[safe: currentFeedIndex]?.videoId
            if !updated.isEmpty || quick.isEmpty {
                feedProjects = updated
            }
            if let previousVideoId,
               let retained = feedProjects.firstIndex(where: { $0.videoId == previousVideoId }) {
                currentFeedIndex = retained
            } else {
                currentFeedIndex = min(currentFeedIndex, max(0, feedProjects.count - 1))
            }
            syncHomeFeedPlayer()
        }
        await prefetchCreatorPages(around: currentFeedIndex)
        await prefetchFeedProjectDetails(around: currentFeedIndex)
        await refreshCurrentVideoEngagement()
    }

    private func buildFastFeedProjects(from rows: [FeedProjectRow]) -> [FeedProjectSummary] {
        rows.compactMap { row in
            guard row.playback_url != nil else { return nil }
            let fallbackSupportMinor = supportedAmountByProjectId[row.project_id] ?? 0
            let committedSupportMinor = max(
                row.viewer_committed_support_amount_minor ?? 0,
                max(row.viewer_supported_plan_price_minor ?? 0, fallbackSupportMinor)
            )
            return FeedProjectSummary(
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
                isSupportedByCurrentUser: committedSupportMinor > 0 || row.is_supported_by_current_user,
                viewerCommittedSupportAmountMinor: row.viewer_committed_support_amount_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                viewerSupportedPlanPriceMinor: row.viewer_supported_plan_price_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                viewerHasUpgradeablePlan: row.viewer_has_upgradeable_plan ?? false
            )
        }
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

    private func prefetchCreatorPages(around index: Int) async {
        guard !feedProjects.isEmpty else { return }
        let indices = [index - 1, index, index + 1].filter { $0 >= 0 && $0 < feedProjects.count }
        for idx in indices {
            await prefetchCreatorPage(for: feedProjects[idx].creatorId)
        }
    }

    private func prefetchCreatorPage(for creatorId: UUID) async {
        let shouldSkip = await MainActor.run {
            creatorPageCacheById[creatorId] != nil || creatorPageLoadingIds.contains(creatorId)
        }
        if shouldSkip { return }

        await MainActor.run {
            _ = creatorPageLoadingIds.insert(creatorId)
        }

        do {
            let page = try await client.getCreatorPage(creatorUserId: creatorId)
            await MainActor.run {
                cacheCreatorPage(page)
                _ = creatorPageLoadingIds.remove(creatorId)
            }
        } catch {
            await MainActor.run {
                _ = creatorPageLoadingIds.remove(creatorId)
            }
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
                await MainActor.run {
                    cacheCreatorPage(page)
                }
                let playableVideos = page.videos
                    .filter { $0.playback_url != nil }
                    .sorted { $0.created_at > $1.created_at }

                for video in playableVideos {
                    if seenVideoIds.contains(video.video_id) { continue }
                    seenVideoIds.insert(video.video_id)
                    appendedForCreator = true
                    let isRowPrimaryVideo = row.video_id == video.video_id
                    let fallbackSupportMinor = supportedAmountByProjectId[row.project_id] ?? 0
                    let resolvedCommittedSupportMinor = max(
                        page.project?.viewer_committed_support_amount_minor
                            ?? row.viewer_committed_support_amount_minor
                            ?? 0,
                        page.project?.viewer_supported_plan_price_minor
                            ?? row.viewer_supported_plan_price_minor
                            ?? fallbackSupportMinor
                    )
                    let resolvedCanUpgrade = (page.project?.viewer_has_upgradeable_plan == true)
                        || (row.viewer_has_upgradeable_plan == true)
                        || (
                            resolvedCommittedSupportMinor > 0
                                && (page.project?.plans ?? []).contains(where: { $0.price_minor > resolvedCommittedSupportMinor })
                        )
                    let resolvedSupported = resolvedCommittedSupportMinor > 0
                        || row.is_supported_by_current_user
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
                            likes: isRowPrimaryVideo ? row.likes : 0,
                            comments: isRowPrimaryVideo ? row.comments : 0,
                            isLikedByCurrentUser: isRowPrimaryVideo ? row.is_liked_by_current_user : false,
                            isSupportedByCurrentUser: resolvedSupported,
                            viewerCommittedSupportAmountMinor: page.project?.viewer_committed_support_amount_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                            viewerSupportedPlanPriceMinor: page.project?.viewer_supported_plan_price_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                            viewerHasUpgradeablePlan: resolvedCanUpgrade
                        )
                    )
                }
            }

            if !appendedForCreator {
                let fallbackSupportMinor = supportedAmountByProjectId[row.project_id] ?? 0
                let resolvedCommittedSupportMinor = max(
                    row.viewer_committed_support_amount_minor ?? 0,
                    max(row.viewer_supported_plan_price_minor ?? 0, fallbackSupportMinor)
                )
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
                            isSupportedByCurrentUser: resolvedCommittedSupportMinor > 0 || row.is_supported_by_current_user,
                            viewerCommittedSupportAmountMinor: row.viewer_committed_support_amount_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                            viewerSupportedPlanPriceMinor: row.viewer_supported_plan_price_minor ?? (fallbackSupportMinor > 0 ? fallbackSupportMinor : nil),
                            viewerHasUpgradeablePlan: row.viewer_has_upgradeable_plan ?? false
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

    private func likeOnDoubleTap(for project: FeedProjectSummary) async {
        guard let videoId = project.videoId else { return }
        guard isAuthenticated else {
            await MainActor.run {
                showAuthSheet = true
            }
            return
        }

        let latest = feedProjects.first(where: { $0.videoId == videoId }) ?? project
        guard !latest.isLikedByCurrentUser else { return }

        let previous = VideoEngagementResult(
            likes: latest.likes,
            comments: latest.comments,
            is_liked_by_current_user: latest.isLikedByCurrentUser
        )
        let optimistic = VideoEngagementResult(
            likes: previous.likes + 1,
            comments: previous.comments,
            is_liked_by_current_user: true
        )

        await MainActor.run {
            applyVideoEngagement(videoId: videoId, engagement: optimistic)
        }
        do {
            let updated = try await client.likeVideo(videoId: videoId)
            await MainActor.run {
                applyVideoEngagement(videoId: videoId, engagement: updated)
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
                isSupportedByCurrentUser: item.isSupportedByCurrentUser,
                viewerCommittedSupportAmountMinor: item.viewerCommittedSupportAmountMinor,
                viewerSupportedPlanPriceMinor: item.viewerSupportedPlanPriceMinor,
                viewerHasUpgradeablePlan: item.viewerHasUpgradeablePlan
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
        guard selectedTab == 0, isHomeFeedVisible else {
            transitionHomeTrackedVideo(to: nil, projectId: nil)
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
            transitionHomeTrackedVideo(to: nil, projectId: nil)
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
            transitionHomeTrackedVideo(to: nil, projectId: nil)
            setHomeFeedEdgeBoosting(false)
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
            detachHomeFeedPlayerObserver()
            homeFeedPlaybackProgress = 0
            return
        }
        transitionHomeTrackedVideo(to: project.videoId, projectId: project.id)

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
            let durationMs = duration * 1000
            if durationMs.isFinite, durationMs >= 0 {
                trackedHomeDurationMs = max(0, Int(durationMs))
            }
            let currentMs = player.currentTime().seconds * 1000
            if currentMs.isFinite, currentMs >= 0 {
                trackedHomeMaxWatchMs = max(trackedHomeMaxWatchMs, Int(currentMs))
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

    private func transitionHomeTrackedVideo(to videoId: UUID?, projectId: UUID?) {
        guard trackedHomeVideoId != videoId else { return }
        flushHomeTrackedPlaybackProgress()
        trackedHomeVideoId = videoId
        trackedHomeProjectId = projectId
        trackedHomeDurationMs = 0
        trackedHomeMaxWatchMs = 0
        trackedHomeDidComplete = false
        guard let videoId else { return }
        Task {
            await client.trackVideoPlayStarted(videoId: videoId, projectId: projectId)
        }
    }

    private func flushHomeTrackedPlaybackProgress() {
        guard !trackedHomeDidComplete else { return }
        guard let videoId = trackedHomeVideoId else { return }
        let clampedWatchMs = max(0, min(trackedHomeMaxWatchMs, trackedHomeDurationMs))
        guard clampedWatchMs > 0, trackedHomeDurationMs > 0 else { return }
        Task {
            await client.trackVideoWatchProgress(
                videoId: videoId,
                watchDurationMs: clampedWatchMs,
                videoDurationMs: trackedHomeDurationMs,
                projectId: trackedHomeProjectId
            )
        }
    }

    private func handleHomeFeedDragEnded(_ value: DragGesture.Value) {
        let dx = value.translation.width
        let dy = value.translation.height
        let threshold: CGFloat = 50

        if showFeedProjectPanel {
            if abs(dx) > abs(dy), abs(dx) > threshold, dx > 0, homeFeedPanelPageIndex == 0 {
                closeFeedProjectPanel()
            } else {
                withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                    homeFeedPanelDragOffsetX = 0
                }
            }
            return
        }

        let action = resolveFeedSwipeAction(
            dx: dx,
            dy: dy,
            isPanelOpen: showFeedProjectPanel,
            canMoveNext: currentFeedIndex < feedProjects.count - 1,
            canMovePrevious: currentFeedIndex > 0
        )

        switch action {
        case .openPanel:
            openFeedProjectPanel()
        case .closePanel:
            closeFeedProjectPanel()
        case .nextItem:
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                homeFeedPanelDragOffsetX = 0
            }
            nextFeed()
        case .previousItem:
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                homeFeedPanelDragOffsetX = 0
            }
            previousFeed()
        case .none:
            withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.9)) {
                homeFeedPanelDragOffsetX = 0
            }
        }
    }

    private func openFeedProjectPanel() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            showFeedProjectPanel = true
            homeFeedPanelPageIndex = 0
            homeFeedPanelDragOffsetX = 0
        }
        homeFeedPlayer?.pause()
    }

    private func closeFeedProjectPanel() {
        guard showFeedProjectPanel else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showFeedProjectPanel = false
            homeFeedPanelPageIndex = 0
            homeFeedPanelDragOffsetX = 0
        }
        syncHomeFeedPlayer()
    }

    private func closeFeedProjectPanelForVerticalMove() {
        guard showFeedProjectPanel else { return }
        showFeedProjectPanel = false
        homeFeedPanelDragOffsetX = 0
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
                cacheCreatorPage(page)
                if let detail = page.project {
                    var resolvedDetail = detail
                    let fallbackSupportMinor = supportedAmountByProjectId[detail.id] ?? 0
                    if fallbackSupportMinor > 0 {
                        if (resolvedDetail.viewer_committed_support_amount_minor ?? 0) <= 0 {
                            resolvedDetail.viewer_committed_support_amount_minor = fallbackSupportMinor
                        }
                        if (resolvedDetail.viewer_supported_plan_price_minor ?? 0) <= 0 {
                            resolvedDetail.viewer_supported_plan_price_minor = fallbackSupportMinor
                        }
                    }
                    let baselineMinor = max(
                        resolvedDetail.viewer_committed_support_amount_minor ?? 0,
                        resolvedDetail.viewer_supported_plan_price_minor ?? 0
                    )
                    if resolvedDetail.viewer_has_upgradeable_plan == nil {
                        resolvedDetail.viewer_has_upgradeable_plan = baselineMinor > 0
                            && (resolvedDetail.plans ?? []).contains(where: { $0.price_minor > baselineMinor })
                    }
                    feedProjectDetailsById[project.id] = resolvedDetail
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

    private func cacheCreatorPage(_ page: CreatorPublicPageResult) {
        var resolvedPage = page
        if var project = page.project {
            let fallbackSupportMinor = supportedAmountByProjectId[project.id] ?? 0
            if fallbackSupportMinor > 0 {
                if (project.viewer_committed_support_amount_minor ?? 0) <= 0 {
                    project.viewer_committed_support_amount_minor = fallbackSupportMinor
                }
                if (project.viewer_supported_plan_price_minor ?? 0) <= 0 {
                    project.viewer_supported_plan_price_minor = fallbackSupportMinor
                }
            }
            let baselineMinor = max(
                project.viewer_committed_support_amount_minor ?? 0,
                project.viewer_supported_plan_price_minor ?? 0
            )
            if project.viewer_has_upgradeable_plan == nil {
                project.viewer_has_upgradeable_plan = baselineMinor > 0
                    && (project.plans ?? []).contains(where: { $0.price_minor > baselineMinor })
            }
            resolvedPage = CreatorPublicPageResult(
                profile: page.profile,
                viewer_relationship: page.viewer_relationship,
                profile_stats: page.profile_stats,
                project: project,
                videos: page.videos
            )
        }
        creatorPageCacheById[page.profile.creator_user_id] = resolvedPage
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
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorText = ""
    
    private var isPrimaryDisabled: Bool {
        isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(isSignUp ? "Create your profile" : "Welcome back")
                                    .font(.system(size: 20, weight: .bold))
                                Text(isSignUp ? "Set up your account to start posting." : "Sign in to continue in Lifecast.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Color.indigo)
                        }

                        HStack(spacing: 8) {
                            Button("Sign in") {
                                isSignUp = false
                                errorText = ""
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSignUp ? Color.clear : Color.black)
                            .foregroundStyle(isSignUp ? Color.secondary : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .disabled(isLoading)

                            Button("Sign up") {
                                isSignUp = true
                                errorText = ""
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(isSignUp ? Color.black : Color.clear)
                            .foregroundStyle(isSignUp ? Color.white : Color.secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .disabled(isLoading)
                        }
                        .padding(4)
                        .background(Color.black.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                        VStack(spacing: 10) {
                            authIconTextField(symbol: "envelope", placeholder: "Email", text: $email, keyboardType: .emailAddress, capitalization: .never)
                            authIconSecureField(symbol: "lock", placeholder: "Password", text: $password, isVisible: $isPasswordVisible)
                            if isSignUp {
                                HStack(spacing: 10) {
                                    Text("Password must be 10 to 72 characters and include at least one uppercase letter, one lowercase letter, one number, and one symbol. Spaces are not allowed.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                                    Button {
                                        password = generateRandomPassword()
                                        isPasswordVisible = true
                                        errorText = ""
                                    } label: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.black.opacity(0.08))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(Color.black.opacity(0.16), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                    .buttonStyle(.plain)
                                }
                                authIconTextField(symbol: "at", placeholder: "Username (optional)", text: $username, capitalization: .never)
                                authIconTextField(symbol: "person", placeholder: "Display name (optional)", text: $displayName)
                                Text("Username and Display name can be changed later from Edit Profile.")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        Button {
                            Task { await submitEmailAuth() }
                        } label: {
                            Text(isSignUp ? "Create account with Email" : "Sign in with Email")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(
                                    LinearGradient(
                                        colors: [Color.black, Color.indigo.opacity(0.85)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPrimaryDisabled)
                        .opacity(isPrimaryDisabled ? 0.6 : 1.0)

                        Button {
                            Task { await continueOAuth(provider: "google") }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "globe")
                                Text("Continue with Google")
                            }
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Color.white.opacity(0.9))
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.14), lineWidth: 1))
                            .foregroundStyle(.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(isLoading)

                        if !errorText.isEmpty {
                            Text(errorText)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.top, 2)
                        }
                    }
                    .padding(16)
                    .background(
                        LinearGradient(
                            colors: [Color(.secondarySystemBackground), Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                }
            }
            .navigationTitle("Sign In")
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

    private func authIconTextField(
        symbol: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalization)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func authIconSecureField(symbol: String, placeholder: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            if isVisible.wrappedValue {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } else {
                SecureField(placeholder, text: text)
            }
            Button(isVisible.wrappedValue ? "Hide" : "Show") {
                isVisible.wrappedValue.toggle()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func submitEmailAuth() async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationError = validateAuthInput(
            email: normalizedEmail,
            password: normalizedPassword,
            username: normalizedUsername,
            displayName: normalizedDisplayName,
            isSignUp: isSignUp
        ) {
            await MainActor.run {
                errorText = validationError
            }
            return
        }

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
            if isSignUp {
                _ = try await client.signUpWithEmail(
                    email: normalizedEmail,
                    password: normalizedPassword,
                    username: normalizedUsername.isEmpty ? nil : normalizedUsername,
                    displayName: normalizedDisplayName.isEmpty ? nil : normalizedDisplayName
                )
            } else {
                _ = try await client.signInWithEmail(email: normalizedEmail, password: normalizedPassword)
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

    private func validateAuthInput(email: String, password: String, username: String, displayName: String, isSignUp: Bool) -> String? {
        let emailPattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        if email.range(of: emailPattern, options: .regularExpression) == nil {
            return "Email format is invalid. Example: name@example.com"
        }
        if password.isEmpty {
            return "Password is required."
        }
        guard isSignUp else { return nil }

        if password.contains(where: \.isWhitespace) {
            return "Password must not include spaces."
        }
        if password.count < 10 {
            return "Password must be at least 10 characters."
        }
        if password.count > 72 {
            return "Password must be 72 characters or less."
        }
        let uppercaseSet = CharacterSet.uppercaseLetters
        let lowercaseSet = CharacterSet.lowercaseLetters
        let numberSet = CharacterSet.decimalDigits
        let symbolSet = CharacterSet.punctuationCharacters.union(.symbols)
        let hasUppercase = password.rangeOfCharacter(from: uppercaseSet) != nil
        let hasLowercase = password.rangeOfCharacter(from: lowercaseSet) != nil
        let hasNumber = password.rangeOfCharacter(from: numberSet) != nil
        let hasSymbol = password.rangeOfCharacter(from: symbolSet) != nil
        if !hasUppercase || !hasLowercase || !hasNumber || !hasSymbol {
            return "Password must include uppercase/lowercase letters, a number, and a symbol."
        }
        if !username.isEmpty {
            if username.count < 3 || username.count > 40 {
                return "Username must be 3-40 characters."
            }
            let allowedUsernameChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
            if username.rangeOfCharacter(from: allowedUsernameChars.inverted) != nil {
                return "Username can only include letters, numbers, and underscore (_)."
            }
        }
        if displayName.count > 30 {
            return "Display name must be 30 characters or less."
        }
        return nil
    }

    private func generateRandomPassword(length: Int = 16) -> String {
        let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let lower = Array("abcdefghijklmnopqrstuvwxyz")
        let digits = Array("0123456789")
        let symbols = Array("!@#$%^&*()-_=+[]{}<>?/|")
        let all = upper + lower + digits + symbols

        var chars: [Character] = [
            upper.randomElement()!,
            lower.randomElement()!,
            digits.randomElement()!,
            symbols.randomElement()!
        ]
        while chars.count < max(length, 10) {
            chars.append(all.randomElement()!)
        }
        return String(chars.shuffled())
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
