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
    @Binding var selectedIndex: Int

    var body: some View {
        HStack(spacing: 0) {
            iconButton(index: 0, systemName: "folder")
            iconButton(index: 1, systemName: "square.grid.3x3")
            iconButton(index: 2, systemName: "heart")
        }
        .padding(4)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }

    private func iconButton(index: Int, systemName: String) -> some View {
        Button {
            selectedIndex = index
        } label: {
            Image(systemName: selectedIndex == index ? "\(systemName).fill" : systemName)
                .font(.system(size: 16, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(selectedIndex == index ? Color.white : Color.clear)
                .clipShape(Capsule())
                .foregroundStyle(.primary)
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

            actionContent

            Text(bioText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
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
