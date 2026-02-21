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
        .buttonStyle(.plain)
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

        return VStack(alignment: .leading, spacing: 8) {
            Text(row.project_title)
                .font(.subheadline.weight(.semibold))
            if let subtitle = row.project_subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Supported at \(formatSupportDate(row.supported_at))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("You: \(row.amount_minor.formatted()) \(row.currency)")
                    .font(.caption.weight(.semibold))
            }

            ProgressView(value: progress)
                .tint(fundingProgressTint(Double(funded) / Double(goal)))
            Text("\(percent)% funded (\(funded.formatted()) / \(goal.formatted()) \(row.project_currency))")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Supporters: \(row.project_supporter_count)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func formatSupportDate(_ iso: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        guard let date = isoFormatter.date(from: iso) else { return iso }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
