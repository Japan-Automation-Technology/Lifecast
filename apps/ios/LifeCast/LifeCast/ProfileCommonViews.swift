import SwiftUI

struct ProfileCenteredLoadingView: View {
    let title: String?

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            if let title, !title.isEmpty {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 180)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

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
        .frame(maxWidth: .infinity, alignment: .center)
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
    var onTapProject: ((SupportedProjectRow) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            if isLoading {
                ProfileCenteredLoadingView(title: "Loading supports...")
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

        return Button {
            onTapProject?(row)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
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
        }
        .buttonStyle(.plain)
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
    var onTapSupport: ((UUID?) -> Void)? = nil
    var headerActionTitle: String? = nil
    var onTapHeaderAction: (() -> Void)? = nil

    @State private var selectedPlan: ProjectPlanResult?
    @State private var showHeroVideo = false
    private let horizontalInset: CGFloat = 16
    private let progressBarHeight: CGFloat = 32
    private var contentColumnWidth: CGFloat {
        max(UIScreen.main.bounds.width - (horizontalInset * 2), 0)
    }

    private var galleryURLs: [String] {
        if let images = project.image_urls, !images.isEmpty {
            return images.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let cover = project.image_url?.trimmingCharacters(in: .whitespacesAndNewlines), !cover.isEmpty {
            return [cover]
        }
        return []
    }

    private var heroImageURL: String? {
        galleryURLs.first
    }

    private var projectDetailContents: [ProjectDetailBlock] {
        if let blocks = project.detail_blocks {
            let mapped = blocks.compactMap { block -> ProjectDetailBlock? in
                switch block.type {
                case "heading":
                    guard let text = block.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                    return .heading(text)
                case "text":
                    guard let text = block.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                    return .text(text)
                case "quote":
                    guard let text = block.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
                    return .quote(text)
                case "image":
                    return .image(block.image_url)
                case "bullets":
                    guard let items = block.items?.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }),
                          !items.isEmpty else { return nil }
                    return .bullets(items)
                default:
                    return nil
                }
            }
            if !mapped.isEmpty {
                return mapped
            }
        }

        var fallback: [ProjectDetailBlock] = [.heading("ストーリー")]
        if let description = project.description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            fallback.append(.text(description))
        }
        if let firstImage = heroImageURL {
            fallback.append(.image(firstImage))
        }
        if let secondaryImage = galleryURLs.dropFirst().first {
            fallback.append(.image(secondaryImage))
        }
        return fallback
    }

    private var progressPercentText: String {
        guard project.goal_amount_minor > 0 else { return "0%" }
        let rawPercent = (Double(project.funded_amount_minor) / Double(project.goal_amount_minor)) * 100
        return "\(Int(rawPercent.rounded()))%"
    }

    private var rawProgressRatio: Double {
        guard project.goal_amount_minor > 0 else { return 0 }
        return Double(project.funded_amount_minor) / Double(project.goal_amount_minor)
    }

    private var progressFillRatio: Double {
        min(max(rawProgressRatio, 0), 1)
    }

    private var progressFillColor: Color {
        rawProgressRatio >= 1
            ? Color(red: 0.83, green: 0.69, blue: 0.22)
            : .green
    }

    private var remainingDaysText: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallbackFormatter = ISO8601DateFormatter()
        fallbackFormatter.formatOptions = [.withInternetDateTime]
        let date = formatter.date(from: project.deadline_at) ?? fallbackFormatter.date(from: project.deadline_at)
        guard let deadline = date else { return "-" }
        let days = max(Int(ceil(deadline.timeIntervalSinceNow / 86_400)), 0)
        return "\(days)日"
    }

    private func formatMinorAmount(_ minor: Int, currency: String) -> String {
        let upperCurrency = currency.uppercased()
        let divisor = upperCurrency == "JPY" ? 1.0 : 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = upperCurrency
        formatter.locale = Locale(identifier: upperCurrency == "JPY" ? "ja_JP" : "en_US_POSIX")
        formatter.maximumFractionDigits = upperCurrency == "JPY" ? 0 : 2
        formatter.minimumFractionDigits = upperCurrency == "JPY" ? 0 : 2
        return formatter.string(from: NSNumber(value: Double(minor) / divisor))
            ?? "\(minor.formatted()) \(upperCurrency)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                if let headerActionTitle, let onTapHeaderAction {
                    Button(headerActionTitle) {
                        onTapHeaderAction()
                    }
                    .accessibilityIdentifier("profile-project-header-action")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.08))
                    .clipShape(Capsule())
                    .buttonStyle(.plain)
                }
            }

            Button {
                showHeroVideo = true
            } label: {
                ZStack(alignment: .center) {
                    projectImage(urlString: heroImageURL, height: 292)

                    LinearGradient(
                        colors: [Color.clear, Color.black.opacity(0.65)],
                        startPoint: .center,
                        endPoint: .bottom
                    )

                    Image(systemName: "play.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 88, height: 88)
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(0.85), lineWidth: 1.5)
                        )
                }
                .frame(width: contentColumnWidth, height: 292, alignment: .center)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, horizontalInset)

            VStack(alignment: .leading, spacing: 16) {
                Text(project.title)
                    .font(.title.weight(.heavy))
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .frame(width: contentColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.28))
                            if progressFillRatio > 0 {
                                Rectangle()
                                    .fill(progressFillColor)
                                    .frame(width: geometry.size.width * progressFillRatio)
                            }
                            Text(progressPercentText)
                                .font(.headline.weight(.black))
                                .foregroundStyle(Color.black.opacity(0.78))
                                .padding(.leading, 16)
                        }
                        .clipShape(Capsule())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: progressBarHeight)

                    VStack(spacing: 6) {
                        Text("応援購入総額")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(formatMinorAmount(project.funded_amount_minor, currency: project.currency))
                            .font(.system(size: 38, weight: .black, design: .rounded))
                            .minimumScaleFactor(0.82)
                            .lineLimit(1)
                        Text("目標金額 \(formatMinorAmount(project.goal_amount_minor, currency: project.currency))")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .frame(width: contentColumnWidth, alignment: .leading)

                HStack(spacing: 0) {
                    statsCard(icon: "person.2", title: "サポーター", value: "\(project.supporter_count.formatted())人")
                        .frame(maxWidth: .infinity, alignment: .center)
                    statsCard(icon: "clock", title: "残り", value: remainingDaysText)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(width: contentColumnWidth, alignment: .leading)

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(projectDetailContents.enumerated()), id: \.offset) { _, block in
                        flexibleBlockView(block)
                    }
                }
                .padding(.top, 4)
                .frame(width: contentColumnWidth, alignment: .leading)

                Text("リターン")
                    .font(.title3.weight(.bold))
                    .frame(width: contentColumnWidth, alignment: .leading)
                plansCarousel
                    .frame(width: contentColumnWidth, alignment: .leading)

                if let supportButtonTitle, let onTapSupport {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.title3.weight(.semibold))
                        Image(systemName: "heart")
                            .font(.title3.weight(.semibold))
                        Button(supportButtonTitle) {
                            onTapSupport(nil)
                        }
                        .font(.title3.weight(.black))
                        .foregroundStyle(Color.black.opacity(0.84))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(red: 0.99, green: 0.82, blue: 0.0))
                        .clipShape(Capsule())
                        .disabled(supportButtonDisabled)
                        .opacity(supportButtonDisabled ? 0.6 : 1.0)
                    }
                    .padding(.top, 2)
                    .frame(width: contentColumnWidth, alignment: .leading)
                }
            }
            .padding(.horizontal, horizontalInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fullScreenCover(isPresented: $showHeroVideo) {
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    projectImage(urlString: heroImageURL, height: 720)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .padding(.horizontal, 18)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Close") {
                            showHeroVideo = false
                        }
                        .foregroundStyle(.white)
                    }
                }
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
                    if let supportButtonTitle, let onTapSupport {
                        Button(supportButtonTitle) {
                            selectedPlan = nil
                            DispatchQueue.main.async {
                                onTapSupport(plan.id)
                            }
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
                    }
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
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(project.plans ?? [], id: \.id) { plan in
                    planCard(plan: plan, width: 180)
                }
            }
        }
        .frame(height: 188)
        .frame(width: contentColumnWidth, alignment: .leading)
    }

    @ViewBuilder
    private func projectImage(urlString: String?, height: CGFloat) -> some View {
        if let raw = urlString, let url = URL(string: raw) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    Rectangle().fill(Color.black.opacity(0.12))
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    Rectangle().fill(Color.black.opacity(0.12))
                @unknown default:
                    Rectangle().fill(Color.black.opacity(0.12))
                }
            }
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .clipped()
        } else {
            LinearGradient(
                colors: [Color.black.opacity(0.8), Color.black.opacity(0.45), Color.gray.opacity(0.35)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .frame(height: height)
        }
    }

    private func statsCard(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.heavy))
            }
        }
        .padding(.vertical, 8)
    }

    private func planCard(plan: ProjectPlanResult, width: CGFloat) -> some View {
        Button {
            selectedPlan = plan
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                projectImage(urlString: plan.image_url, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(plan.name)
                    .font(.subheadline.weight(.black))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text("\(plan.price_minor.formatted()) \(plan.currency)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(plan.reward_summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(10)
            .frame(width: width, alignment: .leading)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func flexibleBlockView(_ block: ProjectDetailBlock) -> some View {
        switch block {
        case .heading(let title):
            Text(title)
                .font(.title3.weight(.heavy))
                .foregroundStyle(.primary)
                .padding(.top, 8)
                .frame(width: contentColumnWidth, alignment: .leading)
        case .text(let body):
            Text(body)
                .font(.body.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: contentColumnWidth, alignment: .leading)
        case .bullets(let items):
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color(red: 0.97, green: 0.78, blue: 0.08))
                            .frame(width: 8, height: 8)
                            .padding(.top, 5)
                        Text(item)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(width: contentColumnWidth, alignment: .leading)
        case .quote(let quote):
            Text("“\(quote)”")
                .font(.body.weight(.semibold))
                .italic()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .frame(width: contentColumnWidth, alignment: .leading)
        case .image(let url):
            projectImage(urlString: url, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .frame(width: contentColumnWidth, alignment: .leading)
        }
    }

    private enum ProjectDetailBlock {
        case heading(String)
        case text(String)
        case bullets([String])
        case quote(String)
        case image(String?)
    }
}
