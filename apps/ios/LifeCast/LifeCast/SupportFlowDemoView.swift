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
    @State private var showFeedProjectPanel = false
    @State private var feedProjectDetail: MyProjectResult?
    @State private var feedProjectDetailLoading = false
    @State private var feedProjectDetailError = ""
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
        .ignoresSafeArea(.container, edges: .bottom)
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
                        onWillMove: {
                            homeFeedPlayer?.pause()
                            closeFeedProjectPanel()
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
            .ignoresSafeArea(edges: [.top, .bottom])
            .overlay(alignment: .top) {
                homeFeedHeader
            }
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
            SlidingFeedPanelLayer(isPanelOpen: showFeedProjectPanel, cornerRadius: 0) {
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
            .padding(.bottom, appBottomBarHeight + 20)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Project")
                .font(.headline)
                .foregroundStyle(.white)

            if feedProjectDetailLoading && feedProjectDetail?.id != project.id {
                ProgressView("Loading project...")
                    .tint(.white)
                    .foregroundStyle(.white.opacity(0.85))
            } else if let detail = feedProjectDetail, detail.id == project.id {
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
        .contentShape(Rectangle())
        .background(Color.black.opacity(0.86))
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            Button(project.isSupportedByCurrentUser ? "Supported" : "Support") {
                if project.isSupportedByCurrentUser { return }
                Task {
                    await presentSupportFlow(for: project)
                }
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(project.isSupportedByCurrentUser ? Color.green.opacity(0.9) : Color.pink.opacity(0.9))
            .foregroundStyle(.white)
            .clipShape(Capsule())

            metricButton(icon: "heart.fill", value: project.likes)
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
        }
        .foregroundStyle(.white)
    }

    private func metricButton(icon: String, value: Int) -> some View {
        Button {} label: {
            metricView(icon: icon, value: value)
        }
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
        let rows = (try? await client.listFeedProjects(limit: 20)) ?? []
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
            if let selected = updated[safe: currentFeedIndex] {
                feedProjectDetail = (feedProjectDetail?.id == selected.id) ? feedProjectDetail : nil
            } else {
                feedProjectDetail = nil
            }
            syncHomeFeedPlayer()
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
                        isSupportedByCurrentUser: row.is_supported_by_current_user
                    )
                )
            }
        }

        return expanded
    }

    private func syncHomeFeedPlayer() {
        guard selectedTab == 0 else {
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
            for player in homeFeedPlayerCache.values {
                player.pause()
            }
            return
        }

        guard !feedProjects.isEmpty else {
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
            for player in homeFeedPlayerCache.values {
                player.pause()
            }
            homeFeedPlayerCache.removeAll()
            return
        }

        let project = feedProjects[max(0, min(currentFeedIndex, feedProjects.count - 1))]
        guard let playbackURL = project.playbackURL, let url = URL(string: playbackURL) else {
            homeFeedPlayer?.pause()
            homeFeedPlayer = nil
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
        }

        if showFeedProjectPanel {
            player.pause()
        } else {
            player.play()
        }

        warmHomeFeedPlayerCache(around: currentFeedIndex)
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
            await loadFeedProjectDetail(for: project)
        }
    }

    private func closeFeedProjectPanel() {
        guard showFeedProjectPanel else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) {
            showFeedProjectPanel = false
        }
        syncHomeFeedPlayer()
    }

    private func loadFeedProjectDetail(for project: FeedProjectSummary) async {
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
                if currentProject?.id == project.id {
                    feedProjectDetail = page.project
                }
            }
        } catch {
            await MainActor.run {
                if currentProject?.id == project.id {
                    feedProjectDetailError = error.localizedDescription
                }
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
