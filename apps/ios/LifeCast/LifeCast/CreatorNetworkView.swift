import SwiftUI

struct CreatorNetworkView: View {
    let client: LifeCastAPIClient
    let creatorUserId: UUID
    let creatorUsername: String
    let initialTab: CreatorNetworkTab
    let useMyNetworkEndpoint: Bool

    @State private var selectedTab: CreatorNetworkTab
    @State private var followersRows: [CreatorNetworkRow] = []
    @State private var followingRows: [CreatorNetworkRow] = []
    @State private var supportRows: [CreatorNetworkRow] = []
    @State private var profileStats = CreatorProfileStats(following_count: 0, followers_count: 0, supported_project_count: 0)
    @State private var loading = false
    @State private var errorText = ""
    @State private var searchText = ""
    @State private var selectedCreatorForNavigation: UUID?
    @State private var currentViewerUserId: UUID?

    init(
        client: LifeCastAPIClient,
        creatorUserId: UUID,
        creatorUsername: String,
        initialTab: CreatorNetworkTab,
        useMyNetworkEndpoint: Bool = false
    ) {
        self.client = client
        self.creatorUserId = creatorUserId
        self.creatorUsername = creatorUsername
        self.initialTab = initialTab
        self.useMyNetworkEndpoint = useMyNetworkEndpoint
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                tabButton(tab: .following, count: profileStats.following_count, label: "Following")
                tabButton(tab: .followers, count: profileStats.followers_count, label: "Followers")
                tabButton(tab: .support, count: profileStats.supported_project_count, label: "Support")
            }
            .padding(.horizontal, 12)

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)

            if loading {
                ProgressView("Loading...")
                    .font(.caption)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            TabView(selection: $selectedTab) {
                rowsListView(rows: filteredRows(for: .following))
                    .tag(CreatorNetworkTab.following)
                rowsListView(rows: filteredRows(for: .followers))
                    .tag(CreatorNetworkTab.followers)
                rowsListView(rows: filteredRows(for: .support))
                    .tag(CreatorNetworkTab.support)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationTitle("@\(creatorUsername)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAllTabs()
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedCreatorForNavigation != nil },
            set: { if !$0 { selectedCreatorForNavigation = nil } }
        )) {
            if let creatorId = selectedCreatorForNavigation {
                CreatorPublicPageView(
                    client: client,
                    creatorId: creatorId,
                    onSupportTap: { _, _ in }
                )
            } else {
                Text("Creator not selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tabButton(tab: CreatorNetworkTab, count: Int, label: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                Text("\(count) \(label)")
                    .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                    .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                Rectangle()
                    .fill(selectedTab == tab ? Color.primary : Color.clear)
                    .frame(height: 2)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func rowsListView(rows: [CreatorNetworkRow]) -> some View {
        if rows.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "person.2")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("No users")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            List(rows) { row in
                HStack(spacing: 12) {
                    Button {
                        selectedCreatorForNavigation = row.creator_user_id
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 46, height: 46)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("@\(row.username)")
                                    .font(.subheadline.weight(.semibold))
                                if let displayName = row.display_name, !displayName.isEmpty {
                                    Text(displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if let title = row.project_title, !title.isEmpty {
                                    Text(title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if row.creator_user_id != creatorUserId
                        && row.creator_user_id != currentViewerUserId
                        && row.is_self != true {
                        Button(row.is_following ? "Following" : "Follow") {
                            Task {
                                await toggleFollow(for: row)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(row.is_following ? .gray : .blue)
                        .controlSize(.small)
                    }
                }
                .listRowSeparator(.visible)
            }
            .listStyle(.plain)
            .refreshable {
                await loadAllTabs()
            }
        }
    }

    private func filteredRows(for tab: CreatorNetworkTab) -> [CreatorNetworkRow] {
        let base: [CreatorNetworkRow]
        switch tab {
        case .followers:
            base = followersRows
        case .following:
            base = followingRows
        case .support:
            base = supportRows
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return base }
        return base.filter {
            $0.username.lowercased().contains(q)
                || ($0.display_name?.lowercased().contains(q) ?? false)
                || ($0.project_title?.lowercased().contains(q) ?? false)
        }
    }

    private func setRows(_ rows: [CreatorNetworkRow], for tab: CreatorNetworkTab) {
        switch tab {
        case .followers:
            followersRows = rows
        case .following:
            followingRows = rows
        case .support:
            supportRows = rows
        }
    }

    private func loadAllTabs() async {
        loading = true
        defer { loading = false }

        do {
            async let followingResult = fetchNetwork(tab: .following)
            async let followersResult = fetchNetwork(tab: .followers)
            async let supportResult = fetchNetwork(tab: .support)
            async let myProfileResult = client.getMyProfile()

            let f2 = try await followingResult
            let f1 = try await followersResult
            let f3 = try await supportResult
            let me = try? await myProfileResult

            await MainActor.run {
                followingRows = f2.rows
                followersRows = f1.rows
                supportRows = f3.rows
                profileStats = f2.profile_stats
                currentViewerUserId = me?.profile.creator_user_id
                errorText = ""
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }

    private func refreshCurrentTab() async {
        do {
            let result = try await fetchNetwork(tab: selectedTab)
            await MainActor.run {
                setRows(result.rows, for: selectedTab)
                profileStats = result.profile_stats
                errorText = ""
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }

    private func fetchNetwork(tab: CreatorNetworkTab) async throws -> CreatorNetworkResult {
        if useMyNetworkEndpoint {
            return try await client.getMyNetwork(tab: tab)
        }
        return try await client.getCreatorNetwork(creatorUserId: creatorUserId, tab: tab)
    }

    private func toggleFollow(for row: CreatorNetworkRow) async {
        do {
            if row.is_following {
                _ = try await client.unfollowCreator(creatorUserId: row.creator_user_id)
            } else {
                _ = try await client.followCreator(creatorUserId: row.creator_user_id)
            }
            await MainActor.run {
                applyLocalFollowState(creatorUserId: row.creator_user_id, isFollowing: !row.is_following)
                errorText = ""
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }

    private func applyLocalFollowState(creatorUserId: UUID, isFollowing: Bool) {
        let sourceRow = (followersRows.first { $0.creator_user_id == creatorUserId })
            ?? (supportRows.first { $0.creator_user_id == creatorUserId })
            ?? (followingRows.first { $0.creator_user_id == creatorUserId })

        let wasFollowingBefore = followingRows.contains { $0.creator_user_id == creatorUserId }

        followersRows = followersRows.map { current in
            guard current.creator_user_id == creatorUserId else { return current }
            return CreatorNetworkRow(
                creator_user_id: current.creator_user_id,
                username: current.username,
                display_name: current.display_name,
                bio: current.bio,
                avatar_url: current.avatar_url,
                project_title: current.project_title,
                is_following: isFollowing,
                is_self: current.is_self
            )
        }
        followingRows = followingRows.map { current in
            guard current.creator_user_id == creatorUserId else { return current }
            return CreatorNetworkRow(
                creator_user_id: current.creator_user_id,
                username: current.username,
                display_name: current.display_name,
                bio: current.bio,
                avatar_url: current.avatar_url,
                project_title: current.project_title,
                is_following: isFollowing,
                is_self: current.is_self
            )
        }
        if isFollowing && !wasFollowingBefore, let row = sourceRow {
            let appended = CreatorNetworkRow(
                creator_user_id: row.creator_user_id,
                username: row.username,
                display_name: row.display_name,
                bio: row.bio,
                avatar_url: row.avatar_url,
                project_title: row.project_title,
                is_following: true,
                is_self: row.is_self
            )
            followingRows.append(appended)
            followingRows.sort { $0.username.localizedCaseInsensitiveCompare($1.username) == .orderedAscending }
        }
        supportRows = supportRows.map { current in
            guard current.creator_user_id == creatorUserId else { return current }
            return CreatorNetworkRow(
                creator_user_id: current.creator_user_id,
                username: current.username,
                display_name: current.display_name,
                bio: current.bio,
                avatar_url: current.avatar_url,
                project_title: current.project_title,
                is_following: isFollowing,
                is_self: current.is_self
            )
        }

        if useMyNetworkEndpoint {
            var following = profileStats.following_count
            if isFollowing && !wasFollowingBefore {
                following += 1
            } else if !isFollowing && wasFollowingBefore {
                following = max(0, following - 1)
            }
            profileStats = CreatorProfileStats(
                following_count: following,
                followers_count: profileStats.followers_count,
                supported_project_count: profileStats.supported_project_count
            )
        }
    }
}
