import SwiftUI

enum FeedMode: String, CaseIterable {
    case forYou = "For You"
    case following = "Following"
}

enum SupportEntryPoint {
    case feed
    case project
}

enum SupportStep: Int {
    case planSelect
    case confirm
    case checkout
    case result
}

struct SupportPlan: Identifiable, Hashable {
    let id: UUID
    let name: String
    let priceMinor: Int
    let rewardSummary: String
}

struct FeedProjectSummary: Identifiable {
    let id: UUID
    let creatorId: UUID
    let username: String
    let caption: String
    let minPlanPriceMinor: Int
    let goalAmountMinor: Int
    let fundedAmountMinor: Int
    let remainingDays: Int
    let likes: Int
    let comments: Int
    let isSupportedByCurrentUser: Bool
}

struct FeedComment: Identifiable {
    let id: UUID
    let username: String
    let body: String
    let likes: Int
    let createdAt: Date
    let isSupporter: Bool
}

private struct NumberFormatterProvider {
    static let jpy: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

struct SupportFlowDemoView: View {
    private let client = LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!)

    @State private var selectedTab = 0
    @State private var feedMode: FeedMode = .forYou
    @State private var currentFeedIndex = 0
    @State private var showComments = false
    @State private var showShare = false
    @State private var selectedCreatorProfile: FeedProjectSummary? = nil

    @State private var supportEntryPoint: SupportEntryPoint = .feed
    @State private var supportStep: SupportStep = .planSelect
    @State private var showSupportFlow = false
    @State private var selectedPlan: SupportPlan? = nil
    @State private var supportResultStatus = "idle"
    @State private var supportResultMessage = ""

    @State private var errorText = ""

    private let plans: [SupportPlan] = [
        SupportPlan(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222221")!,
            name: "Early Support",
            priceMinor: 1000,
            rewardSummary: "Prototype update + thank-you card"
        ),
        SupportPlan(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            name: "Standard",
            priceMinor: 3000,
            rewardSummary: "1 product unit + supporter badge"
        ),
        SupportPlan(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222223")!,
            name: "Collector",
            priceMinor: 7000,
            rewardSummary: "Signed limited package"
        )
    ]

    private var currentProject: FeedProjectSummary {
        sampleProjects[max(0, min(currentFeedIndex, sampleProjects.count - 1))]
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            DiscoverPlaceholderView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
                .tag(1)

            CreatePlaceholderView()
                .tabItem { Label("Create", systemImage: "plus.square") }
                .tag(2)

            MeTabView(
                plans: plans,
                onProjectSupportTap: {
                    supportEntryPoint = .project
                    selectedPlan = nil
                    supportStep = .planSelect
                    showSupportFlow = true
                }
            )
            .tabItem { Label("Me", systemImage: "person") }
            .tag(3)
        }
        .sheet(isPresented: $showComments) {
            commentsSheet
        }
        .sheet(item: $selectedCreatorProfile) { profile in
            CreatorProfileView(profile: profile)
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
    }

    private var homeTab: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Picker("Feed", selection: $feedMode) {
                    ForEach(FeedMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 16)

                ZStack(alignment: .bottomTrailing) {
                    feedCard(project: currentProject)
                        .gesture(
                            DragGesture(minimumDistance: 24)
                                .onEnded { value in
                                    if value.translation.height < -50 {
                                        nextFeed()
                                    } else if value.translation.height > 50 {
                                        previousFeed()
                                    }
                                }
                        )

                    VStack(spacing: 8) {
                        ForEach(0..<sampleProjects.count, id: \.self) { idx in
                            Circle()
                                .fill(idx == currentFeedIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(width: 6, height: 6)
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 120)
                }
                .padding(.top, 8)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            }
        }
    }

    private func feedCard(project: FeedProjectSummary) -> some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color.blue.opacity(0.35), Color.black.opacity(0.6), Color.pink.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Button("@\(project.username)") {
                        selectedCreatorProfile = project
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
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            Button(project.isSupportedByCurrentUser ? "Supported" : "Support") {
                supportEntryPoint = .feed
                selectedPlan = nil
                supportStep = .planSelect
                showSupportFlow = true
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
        let isOverGoal = percentRaw >= 1
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
                        .fill(isOverGoal ? Color.green : Color.pink)
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
        }
    }

    private var planSelectView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Select plan")
                .font(.headline)

            ForEach(plans) { plan in
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

    private var confirmCardView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2. Confirm")
                .font(.headline)

            cardRow(title: "Goal", value: formatJPY(1_000_000))
            cardRow(title: "Delivery", value: "2026-08")
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

        let project = currentProject

        do {
            let prepare = try await client.prepareSupport(
                projectId: project.id,
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
        guard currentFeedIndex < sampleProjects.count - 1 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            currentFeedIndex += 1
        }
    }

    private func previousFeed() {
        guard currentFeedIndex > 0 else { return }
        withAnimation(.spring(response: 0.28, dampingFraction: 0.92)) {
            currentFeedIndex -= 1
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
}

struct CreatorProfileView: View {
    let profile: FeedProjectSummary

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 88, height: 88)

                Text("@\(profile.username)")
                    .font(.title3.bold())

                HStack(spacing: 12) {
                    Button("Following") {}
                        .buttonStyle(.bordered)
                    if profile.isSupportedByCurrentUser {
                        Label("Supported", systemImage: "checkmark.seal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    } else {
                        Button("Support") {}
                            .buttonStyle(.borderedProminent)
                    }
                }

                Text("Current project progress")
                    .font(.subheadline.weight(.semibold))
                ProgressView(value: min(Double(profile.fundedAmountMinor) / Double(profile.goalAmountMinor), 1))
                    .tint(Double(profile.fundedAmountMinor) >= Double(profile.goalAmountMinor) ? .green : .pink)
                    .padding(.horizontal, 24)

                Spacer()
            }
            .padding(20)
            .navigationTitle("Creator")
        }
    }
}

struct MeTabView: View {
    let plans: [SupportPlan]
    let onProjectSupportTap: () -> Void

    @State private var selectedIndex = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                VStack(spacing: 8) {
                    Circle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 90, height: 90)
                    Text("@lifecast_maker")
                        .font(.headline)
                    Text("Supported by 218 users")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("ProfileTabs", selection: $selectedIndex) {
                    Text("Posted").tag(0)
                    Text("Liked").tag(1)
                    Text("Project").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)

                Group {
                    if selectedIndex == 0 {
                        VideoGridPlaceholder(title: "Posted videos")
                    } else if selectedIndex == 1 {
                        VideoGridPlaceholder(title: "Liked videos")
                    } else {
                        ProjectPageView(plans: plans, onProjectSupportTap: onProjectSupportTap)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Me")
        }
    }
}

struct ProjectPageView: View {
    let plans: [SupportPlan]
    let onProjectSupportTap: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Project page")
                    .font(.headline)
                Text("Portable game console - Gen2 prototype in progress")
                ProgressView(value: 1.0)
                    .tint(.green)
                Text("100%+ funded")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Milestones")
                    .font(.subheadline.weight(.semibold))
                milestoneRow("Prototype finished")
                milestoneRow("Thermal test complete")
                milestoneRow("Mold preparation in progress")

                if let first = plans.first {
                    Text("Min plan: \(first.name) / \(first.priceMinor) JPY")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Support") {
                    onProjectSupportTap()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
    }

    private func milestoneRow(_ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(title)
                .font(.subheadline)
        }
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

struct DiscoverPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Discover (M1 placeholder)")
                .foregroundStyle(.secondary)
                .navigationTitle("Discover")
        }
    }
}

struct CreatePlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Create (M1 placeholder)")
                .foregroundStyle(.secondary)
                .navigationTitle("Create")
        }
    }
}

private let sampleProjects: [FeedProjectSummary] = [
    FeedProjectSummary(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        username: "tak_game_lab",
        caption: "Building our handheld game prototype. Today: thermal and battery test.",
        minPlanPriceMinor: 1000,
        goalAmountMinor: 1_000_000,
        fundedAmountMinor: 1_120_000,
        remainingDays: 12,
        likes: 4520,
        comments: 173,
        isSupportedByCurrentUser: true
    ),
    FeedProjectSummary(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        username: "neo_arcade",
        caption: "Arcade stick case redesign with fan voting feedback.",
        minPlanPriceMinor: 2000,
        goalAmountMinor: 800_000,
        fundedAmountMinor: 360_000,
        remainingDays: 21,
        likes: 2180,
        comments: 84,
        isSupportedByCurrentUser: false
    ),
    FeedProjectSummary(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111113")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        username: "pixel_hardware",
        caption: "Low-profile keyboard prototype: key feel tuning sprint.",
        minPlanPriceMinor: 1500,
        goalAmountMinor: 1_500_000,
        fundedAmountMinor: 910_000,
        remainingDays: 9,
        likes: 3380,
        comments: 129,
        isSupportedByCurrentUser: true
    )
]

private let sampleComments: [FeedComment] = [
    FeedComment(id: UUID(), username: "supporter_anna", body: "Make the shoulder buttons larger.", likes: 148, createdAt: Date(), isSupporter: true),
    FeedComment(id: UUID(), username: "maker_kai", body: "Heat profile looks much better this week.", likes: 120, createdAt: Date().addingTimeInterval(-5000), isSupporter: true),
    FeedComment(id: UUID(), username: "viewer_mio", body: "Looks awesome. Following this.", likes: 36, createdAt: Date().addingTimeInterval(-1000), isSupporter: false),
    FeedComment(id: UUID(), username: "viewer_dan", body: "Can you test dock mode too?", likes: 30, createdAt: Date().addingTimeInterval(-300), isSupporter: false)
]

#Preview {
    SupportFlowDemoView()
}
