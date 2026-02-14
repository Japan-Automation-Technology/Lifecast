import SwiftUI

struct DiscoverSearchView: View {
    let client: LifeCastAPIClient
    let onSupportTap: (MyProjectResult) -> Void

    @State private var query = ""
    @State private var rows: [DiscoverCreatorRow] = []
    @State private var loading = false
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search creators", text: $query)
                        .textFieldStyle(.roundedBorder)
                    Button("Search") {
                        Task { await search() }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 16)

                if loading {
                    ProgressView("Searching...")
                        .font(.caption)
                }

                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                List(rows) { creator in
                    NavigationLink {
                        CreatorPublicPageView(
                            client: client,
                            creatorId: creator.creator_user_id,
                            onSupportTap: onSupportTap
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("@\(creator.username)")
                                .font(.headline)
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
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Discover")
            .task {
                await search()
            }
        }
    }

    private func search() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await client.discoverCreators(query: query)
            await MainActor.run {
                rows = result
                errorText = ""
            }
        } catch {
            await MainActor.run {
                rows = []
                errorText = error.localizedDescription
            }
        }
    }
}

struct CreatorPublicPageView: View {
    let client: LifeCastAPIClient
    let creatorId: UUID
    let onSupportTap: (MyProjectResult) -> Void

    @State private var page: CreatorPublicPageResult?
    @State private var loading = false
    @State private var errorText = ""
    @State private var selectedIndex = 0
    @State private var selectedVideo: CreatorPublicVideo?
    @State private var thumbnailCacheBust = UUID().uuidString

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let page {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 90, height: 90)
                        Text("@\(page.profile.username)")
                            .font(.headline)
                        if let displayName = page.profile.display_name, !displayName.isEmpty {
                            Text(displayName)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    if let bio = page.profile.bio, !bio.isEmpty {
                        Text(bio)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                        HStack(spacing: 28) {
                            profileStatItem(value: page.profile_stats.following_count, label: "Following")
                            profileStatItem(value: page.profile_stats.followers_count, label: "Followers")
                            profileStatItem(value: page.profile_stats.supported_project_count, label: "Support")
                        }
                        HStack(spacing: 10) {
                            Button(page.viewer_relationship.is_following ? "Following" : "Follow") {
                                Task {
                                    await toggleFollow()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(page.viewer_relationship.is_following ? .gray : .blue)
                            if page.viewer_relationship.is_supported {
                                Label("Supported", systemImage: "checkmark.seal.fill")
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .padding(.top, 8)

                    ProfileTabIconStrip(selectedIndex: $selectedIndex)
                    .padding(.horizontal, 16)

                    Group {
                        if selectedIndex == 0 {
                            creatorProjectSection(page: page)
                        } else if selectedIndex == 1 {
                            creatorPostsSection(page: page)
                        } else {
                            VideoGridPlaceholder(title: "Liked videos")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if loading {
                    ProgressView("Loading creator...")
                        .padding(.top, 20)
                } else if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }
            }
        }
        .task {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifecastRelationshipChanged)) { notification in
            guard let creatorUserId = notification.userInfo?["creatorUserId"] as? String else { return }
            guard creatorUserId.lowercased() == creatorId.uuidString.lowercased() else { return }
            Task {
                await load()
            }
        }
    }

    private func profileStatItem(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.headline.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func creatorProjectSection(page: CreatorPublicPageResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project = page.project {
                let funded = max(project.funded_amount_minor, 0)
                let goal = max(project.goal_amount_minor, 1)
                let rawRatio = Double(funded) / Double(goal)
                let progress = min(Double(funded) / Double(goal), 1.0)
                let percent = Int((Double(funded) / Double(goal)) * 100.0)

                Text("Project page")
                    .font(.headline)
                if let imageUrl = project.image_url, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(Color.secondary.opacity(0.15))
                    }
                    .frame(height: 180)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                Text(project.title)
                    .font(.title3.weight(.semibold))
                if let subtitle = project.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progress)
                    .tint(fundingProgressTint(rawRatio))
                Text("\(percent)% funded (\(funded.formatted()) / \(goal.formatted()) \(project.currency))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("Supporters: \(project.supporter_count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Goal: \(project.goal_amount_minor.formatted()) \(project.currency)")
                    .font(.footnote)
                if let days = project.duration_days {
                    Text("Duration: \(days) days")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Text("Deadline: \(project.deadline_at)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let category = project.category, !category.isEmpty {
                    Text("Category: \(category)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let location = project.location, !location.isEmpty {
                    Text("Location: \(location)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let description = project.description, !description.isEmpty {
                    Text(description)
                        .font(.footnote)
                }
                if let urls = project.urls, !urls.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("URLs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        ForEach(urls, id: \.self) { raw in
                            if let url = URL(string: raw) {
                                Link(raw, destination: url)
                                    .font(.caption)
                                    .lineLimit(1)
                            } else {
                                Text(raw)
                                    .font(.caption)
                            }
                        }
                    }
                }
                Text("Plans")
                    .font(.subheadline.weight(.semibold))
                ForEach(project.plans ?? [], id: \.id) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        if let image = plan.image_url, let url = URL(string: image) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .empty:
                                    Rectangle().fill(Color.secondary.opacity(0.15))
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                case .failure:
                                    Rectangle().fill(Color.secondary.opacity(0.15))
                                @unknown default:
                                    Rectangle().fill(Color.secondary.opacity(0.15))
                                }
                            }
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.gray.opacity(0.25))
                                Image(systemName: "photo")
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.gray.opacity(0.9))
                            }
                            .frame(height: 120)
                            .frame(maxWidth: .infinity)
                        }
                        Text(plan.name)
                            .font(.subheadline.weight(.semibold))
                        Text("\(plan.price_minor.formatted()) \(plan.currency)")
                            .font(.caption)
                        Text(plan.reward_summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let description = plan.description, !description.isEmpty {
                            Text(description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }

                Button(page.viewer_relationship.is_supported ? "Supported" : "Support this project") {
                    if page.viewer_relationship.is_supported { return }
                    onSupportTap(project)
                }
                .buttonStyle(.borderedProminent)
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
            HStack {
                Text("Posted videos")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    thumbnailCacheBust = UUID().uuidString
                    Task { await load() }
                }
                .font(.caption)
            }
            if page.videos.isEmpty {
                Text("No videos yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
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
                            .frame(height: 150)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("creator-posted-grid-video-\(index)")
                        .accessibilityLabel("Open creator posted \(index)")
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .fullScreenCover(item: $selectedVideo) { video in
            CreatorPostedFeedView(
                videos: convertCreatorVideosToMyVideos(page.videos),
                initialVideoId: video.video_id,
                client: client,
                projectContext: makeCreatorFeedProject(page),
                isCurrentUserVideo: false,
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
                created_at: video.created_at
            )
        }
    }

    private func makeCreatorFeedProject(_ page: CreatorPublicPageResult) -> FeedProjectSummary {
        if let project = page.project {
            let minPlanPrice = project.minimum_plan?.price_minor ?? project.plans?.first?.price_minor ?? 1000
            let remainingDays = max(0, daysUntil(iso: project.deadline_at))
            let trimmedDescription = project.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let caption = trimmedDescription.isEmpty ? (project.subtitle ?? project.title) : trimmedDescription
            return FeedProjectSummary(
                id: project.id,
                creatorId: project.creator_user_id,
                username: page.profile.username,
                caption: caption,
                minPlanPriceMinor: minPlanPrice,
                goalAmountMinor: max(project.goal_amount_minor, 1),
                fundedAmountMinor: max(project.funded_amount_minor, 0),
                remainingDays: remainingDays,
                likes: 4500,
                comments: 173,
                isSupportedByCurrentUser: page.viewer_relationship.is_supported
            )
        }

        return FeedProjectSummary(
            id: UUID(),
            creatorId: page.profile.creator_user_id,
            username: page.profile.username,
            caption: page.profile.bio ?? "Creator update",
            minPlanPriceMinor: 1000,
            goalAmountMinor: 1,
            fundedAmountMinor: 0,
            remainingDays: 0,
            likes: 4500,
            comments: 173,
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

    private func toggleFollow() async {
        guard let current = page else { return }
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
