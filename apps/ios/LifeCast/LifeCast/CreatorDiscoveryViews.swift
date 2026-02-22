import SwiftUI

private struct DiscoverSearchHistoryEntry: Codable, Identifiable, Hashable {
    let query: String

    var id: String { query.lowercased() }
}

private struct DiscoverSearchResultsDestination: Identifiable, Hashable {
    let id = UUID()
    let query: String
}

private struct DiscoverCreatorDestination: Identifiable, Hashable {
    let id: UUID
}

struct DiscoverSearchView: View {
    let client: LifeCastAPIClient
    let onSupportTap: (MyProjectResult, UUID?) -> Void

    @State private var query = ""
    @State private var searchHistory: [DiscoverSearchHistoryEntry] = []
    @State private var destination: DiscoverSearchResultsDestination?
    @FocusState private var isSearchFieldFocused: Bool

    private static let historyKey = "discover.search.history.v1"
    private let historyLimit = 10

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search creators", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .focused($isSearchFieldFocused)
                        .submitLabel(.search)
                        .onSubmit {
                            submitSearch()
                        }
                    Button("Search") {
                        submitSearch()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)

                if !searchHistory.isEmpty {
                    HStack {
                        Spacer()
                        Button("Clear History") {
                            clearSearchHistory()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                }

                historySection
            }
            .navigationTitle("Discover")
            .navigationDestination(item: $destination) { target in
                DiscoverSearchResultsView(
                    client: client,
                    onSupportTap: onSupportTap,
                    query: target.query,
                    onRememberQuery: { value in
                        rememberQuery(value)
                    }
                )
            }
            .task {
                loadSearchHistory()
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if isSearchFieldFocused {
                    isSearchFieldFocused = false
                }
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if searchHistory.isEmpty {
            ContentUnavailableView(
                "No recent searches",
                systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                description: Text("Your recent creator searches will appear here")
            )
            .padding(.horizontal, 16)
        } else {
            List {
                Section {
                    ForEach(searchHistory) { entry in
                        HStack(spacing: 10) {
                            Image(systemName: "clock")
                                .foregroundStyle(.secondary)

                            Button {
                                query = entry.query
                                submitSearch()
                            } label: {
                                Text(entry.query)
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)

                            Button {
                                removeSearchHistoryEntry(entry)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Delete \(entry.query) from search history")
                        }
                    }
                } header: {
                    HStack {
                        Text("Recent searches")
                        Spacer()
                        Button("Clear") {
                            clearSearchHistory()
                        }
                        .font(.caption)
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    private func loadSearchHistory() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.historyKey),
            let decoded = try? JSONDecoder().decode([DiscoverSearchHistoryEntry].self, from: data)
        else {
            searchHistory = []
            return
        }
        searchHistory = decoded
    }

    private func submitSearch() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        destination = DiscoverSearchResultsDestination(query: trimmed)
    }

    private func rememberQuery(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let entry = DiscoverSearchHistoryEntry(query: trimmed)
        var values = searchHistory.filter { $0.id != entry.id }
        values.insert(entry, at: 0)
        if values.count > historyLimit { values = Array(values.prefix(historyLimit)) }
        searchHistory = values
        persistSearchHistory(values)
    }

    private func removeSearchHistoryEntry(_ entry: DiscoverSearchHistoryEntry) {
        searchHistory.removeAll { $0.id == entry.id }
        persistSearchHistory(searchHistory)
    }

    private func persistSearchHistory(_ values: [DiscoverSearchHistoryEntry]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        UserDefaults.standard.set(data, forKey: Self.historyKey)
    }

    private func clearSearchHistory() {
        searchHistory = []
        UserDefaults.standard.removeObject(forKey: Self.historyKey)
    }
}

private enum DiscoverSearchTab: String, CaseIterable {
    case recommended = "Recommended"
    case accounts = "Accounts"
    case videos = "Videos"
}

private struct DiscoverSearchResultsView: View {
    let client: LifeCastAPIClient
    let onSupportTap: (MyProjectResult, UUID?) -> Void
    let query: String
    let onRememberQuery: (String) -> Void

    @State private var selectedTab: DiscoverSearchTab = .recommended
    @State private var creators: [DiscoverCreatorRow] = []
    @State private var videos: [DiscoverVideoRow] = []
    @State private var loading = false
    @State private var errorText = ""
    @State private var destination: DiscoverCreatorDestination?

    private let gridColumns: [GridItem] = [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                tabStrip

                if loading {
                    ProgressView("Searching...")
                        .font(.caption)
                } else if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                } else if creators.isEmpty && videos.isEmpty {
                    ContentUnavailableView(
                        "No results",
                        systemImage: "magnifyingglass",
                        description: Text("Try another keyword")
                    )
                    .padding(.horizontal, 16)
                } else {
                    contentForSelectedTab
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
        }
        .navigationTitle("\"\(query)\"")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $destination) { target in
            CreatorPublicPageView(
                client: client,
                creatorId: target.id,
                onSupportTap: onSupportTap
            )
        }
        .task(id: query) {
            onRememberQuery(query)
            await loadResults()
        }
        .refreshable {
            await loadResults()
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 6) {
            ForEach(DiscoverSearchTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? Color.white : Color.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(selectedTab == tab ? Color.black : Color.gray.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var contentForSelectedTab: some View {
        switch selectedTab {
        case .recommended:
            VStack(alignment: .leading, spacing: 14) {
                if !creators.isEmpty {
                    Text("Accounts")
                        .font(.headline)
                        .padding(.horizontal, 16)
                    VStack(spacing: 0) {
                        ForEach(creators) { creator in
                            accountRow(creator)
                        }
                    }
                }

                if !videos.isEmpty {
                    Text("Videos")
                        .font(.headline)
                        .padding(.horizontal, 16)
                    videosGrid(videos)
                }
            }
        case .accounts:
            VStack(spacing: 0) {
                ForEach(creators) { creator in
                    accountRow(creator)
                }
            }
        case .videos:
            videosGrid(videos)
        }
    }

    private func accountRow(_ creator: DiscoverCreatorRow) -> some View {
        Button {
            destination = DiscoverCreatorDestination(id: creator.creator_user_id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 28))
                VStack(alignment: .leading, spacing: 4) {
                    Text("@\(creator.username)")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if let displayName = creator.display_name, !displayName.isEmpty {
                        Text(displayName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let projectTitle = creator.project_title, !projectTitle.isEmpty {
                        Text(projectTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
    }

    private func videosGrid(_ rows: [DiscoverVideoRow]) -> some View {
        LazyVGrid(columns: gridColumns, spacing: 0) {
            ForEach(rows) { video in
                Button {
                    destination = DiscoverCreatorDestination(id: video.creator_user_id)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        Group {
                            if let thumbnail = video.thumbnail_url, let url = URL(string: thumbnail) {
                                AsyncImage(url: url) { phase in
                                    switch phase {
                                    case .empty:
                                        RoundedRectangle(cornerRadius: 0).fill(Color.gray.opacity(0.15))
                                    case .success(let image):
                                        image.resizable().scaledToFill()
                                    case .failure:
                                        RoundedRectangle(cornerRadius: 0).fill(Color.gray.opacity(0.22))
                                    @unknown default:
                                        RoundedRectangle(cornerRadius: 0).fill(Color.gray.opacity(0.15))
                                    }
                                }
                            } else {
                                RoundedRectangle(cornerRadius: 0).fill(Color.gray.opacity(0.15))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .clipped()

                        LinearGradient(colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 50)

                        Text("@\(video.username)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 0)
    }

    private func loadResults() async {
        await MainActor.run {
            loading = true
            errorText = ""
        }
        defer {
            Task { @MainActor in
                loading = false
            }
        }
        do {
            async let creatorResult = client.discoverCreators(query: query)
            async let videoResult = client.discoverVideos(query: query)
            let (nextCreators, nextVideos) = try await (creatorResult, videoResult)
            await MainActor.run {
                creators = nextCreators
                videos = nextVideos
                errorText = ""
            }
        } catch {
            await MainActor.run {
                creators = []
                videos = []
                errorText = error.localizedDescription
            }
        }
    }
}

struct CreatorPublicPageView: View {
    let client: LifeCastAPIClient
    let creatorId: UUID
    let onRequireAuth: () -> Void
    let onSupportTap: (MyProjectResult, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var page: CreatorPublicPageResult?
    @State private var loading = false
    @State private var errorText = ""
    @State private var selectedIndex = 0
    @State private var selectedVideo: CreatorPublicVideo?
    @State private var thumbnailCacheBust = UUID().uuidString
    @State private var showNetwork = false
    @State private var selectedNetworkTab: CreatorNetworkTab = .following
    @State private var isViewingSelfProfile: Bool? = nil
    @State private var viewerContextResolved = false
    @State private var supportedProjects: [SupportedProjectRow] = []
    @State private var supportedProjectsLoading = false
    @State private var supportedProjectsError = ""
    @State private var selectedCreatorRoute: CreatorRoute? = nil

    init(
        client: LifeCastAPIClient,
        creatorId: UUID,
        onRequireAuth: @escaping () -> Void = {},
        onSupportTap: @escaping (MyProjectResult, UUID?) -> Void
    ) {
        self.client = client
        self.creatorId = creatorId
        self.onRequireAuth = onRequireAuth
        self.onSupportTap = onSupportTap
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                if let page {
                    VStack(spacing: 8) {
                        ProfileOverviewSection(
                            avatarURL: page.profile.avatar_url,
                            displayName: creatorDisplayName(profile: page.profile),
                            bioText: creatorBioText(profile: page.profile),
                            followingCount: page.profile_stats.following_count,
                            followersCount: page.profile_stats.followers_count,
                            supportCount: page.profile_stats.supported_project_count,
                            onTapFollowing: {
                                selectedNetworkTab = .following
                                showNetwork = true
                            },
                            onTapFollowers: {
                                selectedNetworkTab = .followers
                                showNetwork = true
                            },
                            onTapSupport: {
                                selectedNetworkTab = .support
                                showNetwork = true
                            }
                        ) {
                            if viewerContextResolved && isViewingSelfProfile == false {
                                HStack(spacing: 10) {
                                    Button(page.viewer_relationship.is_following ? "Following" : "Follow") {
                                        guard client.hasAuthSession else {
                                            onRequireAuth()
                                            return
                                        }
                                        Task {
                                            await toggleFollow()
                                        }
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color.black.opacity(page.viewer_relationship.is_following ? 0.9 : 0.82))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(page.viewer_relationship.is_following ? Color.gray.opacity(0.28) : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                page.viewer_relationship.is_following ? Color.clear : Color.black.opacity(0.82),
                                                lineWidth: page.viewer_relationship.is_following ? 0 : 1.4
                                            )
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .buttonStyle(.plain)

                                    Button(page.viewer_relationship.is_supported ? "Supported" : "Support") {
                                        guard !page.viewer_relationship.is_supported else { return }
                                        guard client.hasAuthSession else {
                                            onRequireAuth()
                                            return
                                        }
                                        guard let project = page.project else {
                                            errorText = "No active project to support"
                                            return
                                        }
                                        onSupportTap(project, nil)
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(page.viewer_relationship.is_supported ? Color.primary : Color.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 34)
                                    .background(page.viewer_relationship.is_supported ? Color.gray.opacity(0.28) : Color.green)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .buttonStyle(.plain)
                                    .disabled(!page.viewer_relationship.is_supported && page.project == nil)
                                }
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                    .padding(.top, 6)

                    Section {
                        Group {
                            if selectedIndex == 0 {
                                creatorProjectSection(page: page)
                            } else if selectedIndex == 1 {
                                creatorPostsSection(page: page)
                            } else {
                                SupportedProjectsListView(
                                    rows: supportedProjects,
                                    isLoading: supportedProjectsLoading,
                                    errorText: supportedProjectsError,
                                    emptyText: "No supported projects yet",
                                    onRefresh: {
                                        Task { await loadSupportedProjects() }
                                    },
                                    onTapProject: { row in
                                        if row.creator_user_id == creatorId {
                                            selectedIndex = 0
                                        } else {
                                            selectedCreatorRoute = CreatorRoute(id: row.creator_user_id)
                                        }
                                    }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } header: {
                        ProfileTabIconStrip(selectedIndex: $selectedIndex, style: .fullWidthUnderline)
                            .background(Color.white)
                    }
                } else if loading {
                    ProfileCenteredLoadingView(title: nil)
                } else if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: appBottomBarHeight + 20)
        }
        .refreshable {
            await load()
            if selectedIndex == 2 {
                await loadSupportedProjects()
            }
        }
        .task(id: creatorId) {
            await MainActor.run {
                isViewingSelfProfile = nil
                viewerContextResolved = false
                supportedProjects = []
                supportedProjectsError = ""
            }
            await refreshViewerContext()
            await load()
            await loadSupportedProjects()
        }
        .onChange(of: selectedIndex) { _, newValue in
            if newValue == 2 {
                Task { await loadSupportedProjects() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifecastRelationshipChanged)) { notification in
            guard let creatorUserId = notification.userInfo?["creatorUserId"] as? String else { return }
            guard creatorUserId.lowercased() == creatorId.uuidString.lowercased() else { return }
            Task {
                await load()
            }
        }
        .navigationDestination(isPresented: $showNetwork) {
            if let page {
                CreatorNetworkView(
                    client: client,
                    creatorUserId: page.profile.creator_user_id,
                    creatorUsername: page.profile.username,
                    initialTab: selectedNetworkTab
                )
            } else {
                Text("Creator not loaded")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationDestination(item: $selectedCreatorRoute) { route in
            CreatorPublicPageView(
                client: client,
                creatorId: route.id,
                onRequireAuth: onRequireAuth,
                onSupportTap: onSupportTap
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            creatorPinnedHeader
        }
    }

    private var creatorPinnedHeader: some View {
        ZStack {
            Text(page.map { "@\($0.profile.username)" } ?? "")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 56)

            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                Spacer()
                Color.clear.frame(width: 28, height: 28)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(Color.white)
    }

    private func creatorDisplayName(profile: CreatorPublicProfile) -> String {
        let name = (profile.display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? profile.username : name
    }

    private func creatorBioText(profile: CreatorPublicProfile) -> String {
        let bio = (profile.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return bio
    }

    private func creatorProjectSection(page: CreatorPublicPageResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project = page.project {
                ProfileProjectDetailView(
                    project: project,
                    supportButtonTitle: viewerContextResolved && isViewingSelfProfile == false
                        ? (page.viewer_relationship.is_supported ? "Supported" : "Support")
                        : nil,
                    supportButtonDisabled: page.viewer_relationship.is_supported,
                    onTapSupport: { preferredPlanId in
                        if page.viewer_relationship.is_supported { return }
                        onSupportTap(project, preferredPlanId)
                    }
                )
            } else {
                Text("No active project")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
    }

    private func creatorPostsSection(page: CreatorPublicPageResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if page.videos.isEmpty {
                Text("No videos yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0), GridItem(.flexible(), spacing: 0)], spacing: 0) {
                    ForEach(Array(page.videos.enumerated()), id: \.element.video_id) { index, video in
                        Button {
                            selectedVideo = video
                        } label: {
                            Group {
                                if let thumbnail = video.thumbnail_url, let url = thumbnailURL(base: thumbnail) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .empty:
                                            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        case .failure:
                                            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2))
                                        @unknown default:
                                            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                                        }
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .aspectRatio(9.0 / 16.0, contentMode: .fit)
                            .clipped()
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("creator-posted-grid-video-\(index)")
                        .accessibilityLabel("Open creator posted \(index)")
                    }
                }
            }
        }
        .padding(.top, -16)
        .padding(.horizontal, 0)
        .fullScreenCover(item: $selectedVideo) { video in
            CreatorPostedFeedView(
                videos: convertCreatorVideosToMyVideos(page.videos),
                initialVideoId: video.video_id,
                client: client,
                projectContext: makeCreatorFeedProject(page),
                isCurrentUserVideo: isViewingSelfProfile == true,
                onSupportTap: onSupportTap,
                onVideoDeleted: {}
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

    private func convertCreatorVideosToMyVideos(_ videos: [CreatorPublicVideo]) -> [MyVideo] {
        videos.map { video in
            MyVideo(
                video_id: video.video_id,
                status: video.status,
                file_name: video.file_name,
                playback_url: video.playback_url,
                thumbnail_url: video.thumbnail_url,
                play_count: nil,
                watch_completed_count: nil,
                watch_time_total_ms: nil,
                created_at: video.created_at
            )
        }
    }

    private func makeCreatorFeedProject(_ page: CreatorPublicPageResult) -> FeedProjectSummary {
        let latestVideo = page.videos.sorted { $0.created_at > $1.created_at }.first
        if let project = page.project {
            let minPlanPrice = project.minimum_plan?.price_minor ?? project.plans?.first?.price_minor ?? 1000
            let remainingDays = max(0, daysUntil(iso: project.deadline_at))
            let trimmedDescription = project.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let caption = trimmedDescription.isEmpty ? (project.subtitle ?? project.title) : trimmedDescription
            return FeedProjectSummary(
                id: project.id,
                creatorId: project.creator_user_id,
                username: page.profile.username,
                creatorAvatarURL: page.profile.avatar_url,
                caption: caption,
                videoId: latestVideo?.video_id,
                playbackURL: latestVideo?.playback_url,
                thumbnailURL: latestVideo?.thumbnail_url,
                minPlanPriceMinor: minPlanPrice,
                goalAmountMinor: max(project.goal_amount_minor, 1),
                fundedAmountMinor: max(project.funded_amount_minor, 0),
                remainingDays: remainingDays,
                likes: 0,
                comments: 0,
                isLikedByCurrentUser: false,
                isSupportedByCurrentUser: page.viewer_relationship.is_supported
            )
        }

        return FeedProjectSummary(
            id: UUID(),
            creatorId: page.profile.creator_user_id,
            username: page.profile.username,
            creatorAvatarURL: page.profile.avatar_url,
            caption: page.profile.bio ?? "Creator update",
            videoId: latestVideo?.video_id,
            playbackURL: latestVideo?.playback_url,
            thumbnailURL: latestVideo?.thumbnail_url,
            minPlanPriceMinor: 1000,
            goalAmountMinor: 1,
            fundedAmountMinor: 0,
            remainingDays: 0,
            likes: 0,
            comments: 0,
            isLikedByCurrentUser: false,
            isSupportedByCurrentUser: page.viewer_relationship.is_supported
        )
    }

    private func daysUntil(iso: String) -> Int {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso) else { return 0 }
        let seconds = date.timeIntervalSinceNow
        if seconds <= 0 { return 0 }
        return Int(ceil(seconds / 86_400))
    }

    private func refreshViewerContext() async {
        do {
            let session = try await client.getAuthMe()
            let isSelf = session.profile?.creator_user_id == creatorId
            await MainActor.run {
                isViewingSelfProfile = isSelf
                viewerContextResolved = true
            }
        } catch {
            await MainActor.run {
                isViewingSelfProfile = false
                viewerContextResolved = true
            }
        }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await client.getCreatorPage(creatorUserId: creatorId)
            await MainActor.run {
                page = result
                errorText = ""
            }
        } catch {
            await MainActor.run {
                page = nil
                errorText = error.localizedDescription
            }
        }
    }

    private func loadSupportedProjects() async {
        await MainActor.run { supportedProjectsLoading = true }
        defer {
            Task { @MainActor in
                supportedProjectsLoading = false
            }
        }
        do {
            let rows = try await client.getCreatorSupportedProjects(creatorUserId: creatorId, limit: 50)
            await MainActor.run {
                supportedProjects = rows
                supportedProjectsError = ""
            }
        } catch {
            await MainActor.run {
                supportedProjects = []
                supportedProjectsError = error.localizedDescription
            }
        }
    }

    private func toggleFollow() async {
        guard let current = page else { return }
        guard client.hasAuthSession else {
            await MainActor.run {
                onRequireAuth()
            }
            return
        }
        do {
            let relationship: CreatorViewerRelationship
            if current.viewer_relationship.is_following {
                relationship = try await client.unfollowCreator(creatorUserId: creatorId)
            } else {
                relationship = try await client.followCreator(creatorUserId: creatorId)
            }
            await MainActor.run {
                let followers = current.profile_stats.followers_count + (current.viewer_relationship.is_following ? -1 : 1)
                page = CreatorPublicPageResult(
                    profile: current.profile,
                    viewer_relationship: relationship,
                    profile_stats: CreatorProfileStats(
                        following_count: current.profile_stats.following_count,
                        followers_count: max(0, followers),
                        supported_project_count: current.profile_stats.supported_project_count
                    ),
                    project: current.project,
                    videos: current.videos
                )
                errorText = ""
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }
}
