import SwiftUI

struct VideoGridPlaceholder: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 16)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 2) {
                ForEach(0..<9, id: \.self) { idx in
                    Rectangle()
                        .fill(idx % 2 == 0 ? Color.blue.opacity(0.3) : Color.pink.opacity(0.3))
                        .aspectRatio(9 / 16, contentMode: .fit)
                        .overlay {
                            Text("#\(idx + 1)")
                                .font(.caption2)
                        }
                }
            }
            Spacer()
        }
    }
}

struct ProfileTabIconStrip: View {
    private enum TabIconType {
        case projectRocket
        case system(normal: String, selected: String)
    }

    enum Style {
        case capsule
        case fullWidthUnderline
    }

    @Binding var selectedIndex: Int
    var style: Style = .capsule

    private var isFullWidthUnderline: Bool {
        style == .fullWidthUnderline
    }

    var body: some View {
        if isFullWidthUnderline {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    iconButton(index: 0, icon: .projectRocket)
                    iconButton(index: 1, icon: .system(normal: "square.grid.3x3", selected: "square.grid.3x3.fill"))
                    iconButton(index: 2, icon: .system(normal: "checkmark.seal", selected: "checkmark.seal.fill"))
                }
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(selectedIndex == 0 ? Color.primary : Color.secondary.opacity(0.28))
                    Rectangle()
                        .fill(selectedIndex == 1 ? Color.primary : Color.secondary.opacity(0.28))
                    Rectangle()
                        .fill(selectedIndex == 2 ? Color.primary : Color.secondary.opacity(0.28))
                }
                .frame(height: 1)
            }
            .frame(maxWidth: .infinity)
        } else {
            HStack(spacing: 0) {
                iconButton(index: 0, icon: .projectRocket)
                iconButton(index: 1, icon: .system(normal: "square.grid.3x3", selected: "square.grid.3x3.fill"))
                iconButton(index: 2, icon: .system(normal: "checkmark.seal", selected: "checkmark.seal.fill"))
            }
            .padding(4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
        }
    }

    private func iconButton(index: Int, icon: TabIconType) -> some View {
        Button {
            selectedIndex = index
        } label: {
            VStack(spacing: isFullWidthUnderline ? 0 : 6) {
                switch icon {
                case .projectRocket:
                    Image(selectedIndex == index ? "ProjectRocketBlack" : "ProjectRocketWhite")
                        .resizable()
                        .scaledToFit()
                        .frame(width: isFullWidthUnderline ? 19 : 20, height: isFullWidthUnderline ? 19 : 20)
                case .system(let normal, let selected):
                    Image(systemName: selectedIndex == index ? selected : normal)
                        .font(.system(size: isFullWidthUnderline ? 15 : 16, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, isFullWidthUnderline ? 6 : 10)
            .background(selectedIndex == index && !isFullWidthUnderline ? Color.white : Color.clear)
            .clipShape(Capsule())
        }
        .accessibilityIdentifier(tabAccessibilityIdentifier(index: index))
        .buttonStyle(.plain)
    }

    private func tabAccessibilityIdentifier(index: Int) -> String {
        switch index {
        case 0:
            return "profile-tab-project"
        case 1:
            return "profile-tab-posts"
        case 2:
            return "profile-tab-support"
        default:
            return "profile-tab-\(index)"
        }
    }
}

struct ProfileOverviewSection<ActionContent: View>: View {
    let avatarURL: String?
    let displayName: String
    let bioText: String
    let followingCount: Int
    let followersCount: Int
    let supportCount: Int
    let onTapFollowing: () -> Void
    let onTapFollowers: () -> Void
    let onTapSupport: () -> Void
    let actionContent: ActionContent

    init(
        avatarURL: String?,
        displayName: String,
        bioText: String,
        followingCount: Int,
        followersCount: Int,
        supportCount: Int,
        onTapFollowing: @escaping () -> Void,
        onTapFollowers: @escaping () -> Void,
        onTapSupport: @escaping () -> Void,
        @ViewBuilder actionContent: () -> ActionContent
    ) {
        self.avatarURL = avatarURL
        self.displayName = displayName
        self.bioText = bioText
        self.followingCount = followingCount
        self.followersCount = followersCount
        self.supportCount = supportCount
        self.onTapFollowing = onTapFollowing
        self.onTapFollowers = onTapFollowers
        self.onTapSupport = onTapSupport
        self.actionContent = actionContent()
    }

    var body: some View {
        VStack(spacing: 8) {
            profileAvatar(urlString: avatarURL, size: 90)

            Text(displayName)
                .font(.headline)

            HStack(spacing: 28) {
                profileStatButton(value: followingCount, label: "Following", action: onTapFollowing)
                profileStatButton(value: followersCount, label: "Followers", action: onTapFollowers)
                profileStatButton(value: supportCount, label: "Support", action: onTapSupport)
            }

            if !bioText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(bioText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            actionContent
        }
    }

    private func profileStatButton(value: Int, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(value.formatted())
                    .font(.headline.weight(.semibold))
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func profileAvatar(urlString: String?, size: CGFloat) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Circle().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: size, height: size)
        }
    }
}

struct SupportedProjectsListView: View {
    let rows: [SupportedProjectRow]
    let isLoading: Bool
    let errorText: String
    let emptyText: String
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            if isLoading {
                ProgressView("Loading supports...")
                    .font(.caption)
                    .padding(.horizontal, 16)
            } else if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            } else if rows.isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(rows) { row in
                        supportedProjectCard(row: row)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func supportedProjectCard(row: SupportedProjectRow) -> some View {
        let goal = max(row.project_goal_amount_minor, 1)
        let funded = max(row.project_funded_amount_minor, 0)
        let progress = min(Double(funded) / Double(goal), 1.0)
        let percent = Int((Double(funded) / Double(goal)) * 100.0)
        let trimmedCreatorDisplayName = (row.creator_display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let creatorName = trimmedCreatorDisplayName.isEmpty ? "@\(row.creator_username)" : trimmedCreatorDisplayName
        let supportAmountText = "\(row.amount_minor.formatted()) \(row.currency)"

        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                if let raw = row.project_image_url,
                   let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            Rectangle().fill(Color.secondary.opacity(0.12))
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                        case .failure:
                            Rectangle().fill(Color.secondary.opacity(0.12))
                        @unknown default:
                            Rectangle().fill(Color.secondary.opacity(0.12))
                        }
                    }
                } else {
                    LinearGradient(
                        colors: [Color.secondary.opacity(0.22), Color.secondary.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [Color.black.opacity(0.0), Color.black.opacity(0.36)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                HStack {
                    Text("\(percent)% funded")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.38))
                        .clipShape(Capsule())
                    Spacer()
                    Text("You: \(supportAmountText)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.38))
                        .clipShape(Capsule())
                }
                .padding(10)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 146)
            .clipped()

            VStack(alignment: .leading, spacing: 9) {
                Text(row.project_title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "person.crop.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(creatorName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatSupportDate(row.supported_at))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progress)
                    .tint(fundingProgressTint(Double(funded) / Double(goal)))
                HStack {
                    Text("\(funded.formatted()) / \(goal.formatted()) \(row.project_currency)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(row.project_supporter_count) supporters")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, y: 3)
    }

    private func formatSupportDate(_ iso: String) -> String {
        let primaryISOFormatter = ISO8601DateFormatter()
        primaryISOFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackISOFormatter = ISO8601DateFormatter()
        fallbackISOFormatter.formatOptions = [.withInternetDateTime]
        guard let date = primaryISOFormatter.date(from: iso) ?? fallbackISOFormatter.date(from: iso) else {
            return iso
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}

struct ProfileProjectDetailView: View {
    let project: MyProjectResult
    var supportButtonTitle: String?
    var supportButtonDisabled: Bool = false
    var onTapSupport: (() -> Void)? = nil
    var headerActionTitle: String? = nil
    var onTapHeaderAction: (() -> Void)? = nil

    @State private var selectedPlan: ProjectPlanResult?

    private var funded: Int { max(project.funded_amount_minor, 0) }
    private var goal: Int { max(project.goal_amount_minor, 1) }
    private var progressRatio: Double { Double(funded) / Double(goal) }
    private var progressClamped: Double { min(progressRatio, 1.0) }
    private var progressPercent: Int { Int(progressRatio * 100.0) }

    private var galleryURLs: [String] {
        if let images = project.image_urls, !images.isEmpty {
            return images.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let cover = project.image_url?.trimmingCharacters(in: .whitespacesAndNewlines), !cover.isEmpty {
            return [cover]
        }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text(project.title)
                    .font(.title3.weight(.semibold))
                Spacer(minLength: 8)
                if let headerActionTitle, let onTapHeaderAction {
                    Button(headerActionTitle) {
                        onTapHeaderAction()
                    }
                    .accessibilityIdentifier("profile-project-header-action")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }

            if let subtitle = project.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progressClamped)
                .tint(fundingProgressTint(progressRatio))
            Text("\(progressPercent)% (\(funded.formatted()) / \(goal.formatted()) \(project.currency))")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(project.supporter_count) supporters")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !galleryURLs.isEmpty {
                TabView {
                    ForEach(galleryURLs, id: \.self) { raw in
                        if let url = URL(string: raw) {
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
                            .frame(maxWidth: .infinity)
                            .frame(height: 210)
                            .clipped()
                        }
                    }
                }
                .frame(height: 210)
                .tabViewStyle(.page(indexDisplayMode: .automatic))
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
            plansCarousel

            if let category = project.category, !category.isEmpty {
                Text("Category: \(category)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text(deadlineDurationLine(deadlineISO: project.deadline_at, durationDays: project.duration_days))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let location = project.location, !location.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(location)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let supportButtonTitle, let onTapSupport {
                Button(supportButtonTitle) {
                    onTapSupport()
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.78, blue: 0.42), Color(red: 0.11, green: 0.66, blue: 0.32)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                .disabled(supportButtonDisabled)
                .opacity(supportButtonDisabled ? 0.6 : 1.0)
                .padding(.top, 2)
            }
        }
        .sheet(item: $selectedPlan) { plan in
            NavigationStack {
                VStack(alignment: .leading, spacing: 14) {
                    if let raw = plan.image_url, let url = URL(string: raw) {
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
                        .frame(height: 200)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    Text(plan.name)
                        .font(.title3.weight(.semibold))
                    Text("\(plan.price_minor.formatted()) \(plan.currency)")
                        .font(.headline)
                    Text(plan.reward_summary)
                        .font(.body)
                    if let description = plan.description, !description.isEmpty {
                        Text(description)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                    Button("Support (Coming soon)") {}
                        .buttonStyle(.borderedProminent)
                        .disabled(true)
                }
                .padding(16)
                .navigationTitle("Plan details")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Close") {
                            selectedPlan = nil
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var plansCarousel: some View {
        GeometryReader { proxy in
            let cardWidth = max((proxy.size.width - 12) / 2, 140)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(project.plans ?? [], id: \.id) { plan in
                        Button {
                            selectedPlan = plan
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                if let raw = plan.image_url, let url = URL(string: raw) {
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
                                    .frame(height: 96)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                } else {
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.15))
                                        .frame(height: 96)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                Text(plan.name)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text("\(plan.price_minor.formatted()) \(plan.currency)")
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                Text(plan.reward_summary)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(10)
                            .frame(width: cardWidth, alignment: .leading)
                            .background(Color.secondary.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(height: 188)
    }

    private func deadlineDurationLine(deadlineISO: String, durationDays: Int?) -> String {
        let formatter = ISO8601DateFormatter()
        guard let deadline = formatter.date(from: deadlineISO) else {
            if let durationDays {
                return "残り-、期間\(durationDays)日"
            }
            return "残り-"
        }

        let now = Date()
        if deadline <= now {
            if let durationDays {
                return "残り0日0時間、期間\(durationDays)日"
            }
            return "残り0日0時間"
        }

        let comps = Calendar.current.dateComponents([.day, .hour], from: now, to: deadline)
        let days = max(0, comps.day ?? 0)
        let hours = max(0, comps.hour ?? 0) % 24
        if let durationDays {
            return "残り\(days)日\(hours)時間、期間\(durationDays)日"
        }
        return "残り\(days)日\(hours)時間"
    }
}
