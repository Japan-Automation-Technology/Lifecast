import SwiftUI
import AVKit
import PhotosUI
import UniformTypeIdentifiers
import UIKit

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

enum UploadFlowState: String {
    case idle
    case created
    case uploading
    case processing
    case ready
    case failed
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

struct CreatorRoute: Identifiable {
    let id: UUID
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
    @State private var selectedCreatorRoute: CreatorRoute? = nil

    @State private var supportEntryPoint: SupportEntryPoint = .feed
    @State private var supportStep: SupportStep = .planSelect
    @State private var showSupportFlow = false
    @State private var selectedPlan: SupportPlan? = nil
    @State private var supportResultStatus = "idle"
    @State private var supportResultMessage = ""
    @State private var liveSupportProject: MyProjectResult?
    @State private var supportTargetProject: MyProjectResult?
    @State private var myVideos: [MyVideo] = []
    @State private var myVideosError = ""

    @State private var errorText = ""

    private var realPlans: [SupportPlan] {
        guard let target = supportTargetProject ?? liveSupportProject else { return [] }
        return (target.plans ?? []).map {
            SupportPlan(id: $0.id, name: $0.name, priceMinor: $0.price_minor, rewardSummary: $0.reward_summary)
        }
    }

    private var currentProject: FeedProjectSummary {
        sampleProjects[max(0, min(currentFeedIndex, sampleProjects.count - 1))]
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            DiscoverSearchView(client: client) { project in
                supportEntryPoint = .feed
                supportTargetProject = project
                selectedPlan = nil
                supportStep = .planSelect
                showSupportFlow = true
            }
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
                .tag(1)

            UploadCreateView(client: client, onUploadReady: {
                Task {
                    await refreshMyVideos()
                }
            }, onOpenProjectTab: {
                selectedTab = 3
            })
                .tabItem { Label("Create", systemImage: "plus.square") }
                .tag(2)

            MeTabView(
                client: client,
                myVideos: myVideos,
                myVideosError: myVideosError,
                onRefreshVideos: {
                    Task {
                        await refreshMyVideos()
                    }
                },
                onProjectChanged: {
                    Task {
                        await refreshMyVideos()
                    }
                }
            )
            .tabItem { Label("Me", systemImage: "person") }
            .tag(3)
        }
        .sheet(isPresented: $showComments) {
            commentsSheet
        }
        .sheet(item: $selectedCreatorRoute) { route in
            NavigationStack {
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
        .task {
            await refreshMyVideos()
            await refreshLiveSupportProject()
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 3 {
                Task {
                    await refreshMyVideos()
                    await refreshLiveSupportProject()
                }
            }
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
                        selectedCreatorRoute = CreatorRoute(id: project.creatorId)
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
            Button((liveSupportProject == nil || realPlans.isEmpty) ? "Setup" : (project.isSupportedByCurrentUser ? "Supported" : "Support")) {
                supportEntryPoint = .feed
                supportTargetProject = liveSupportProject
                selectedPlan = nil
                supportStep = .planSelect
                showSupportFlow = true
            }
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background((liveSupportProject == nil || realPlans.isEmpty) ? Color.gray.opacity(0.9) : (project.isSupportedByCurrentUser ? Color.green.opacity(0.9) : Color.pink.opacity(0.9))
            )
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
               let refreshed = try? await client.getCreatorPage(creatorUserId: creatorId).project {
                supportTargetProject = refreshed
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

    private func formatDeliveryDate(from iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: iso8601) else { return iso8601 }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_US_POSIX")
        out.dateFormat = "yyyy-MM"
        return out.string(from: date)
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
                    Button("Follow") {}
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
    let client: LifeCastAPIClient
    let myVideos: [MyVideo]
    let myVideosError: String
    let onRefreshVideos: () -> Void
    let onProjectChanged: () -> Void

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
                    Text("Creator profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("ProfileTabs", selection: $selectedIndex) {
                    Text("Project").tag(0)
                    Text("Posts").tag(1)
                    Text("Liked").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .onChange(of: selectedIndex) { _, newValue in
                    if newValue == 1 {
                        onRefreshVideos()
                    }
                }

                Group {
                    if selectedIndex == 0 {
                        ProjectPageView(
                            client: client,
                            onProjectChanged: onProjectChanged
                        )
                    } else if selectedIndex == 1 {
                        PostedVideosListView(
                            videos: myVideos,
                            errorText: myVideosError,
                            onRefreshVideos: onRefreshVideos
                        )
                    } else {
                        VideoGridPlaceholder(title: "Liked videos")
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .navigationTitle("Me")
            .task {
                onRefreshVideos()
            }
        }
    }
}

struct ProjectPageView: View {
    let client: LifeCastAPIClient
    let onProjectChanged: () -> Void

    @State private var myProject: MyProjectResult?
    @State private var projectHistory: [MyProjectResult] = []
    @State private var projectLoading = false
    @State private var projectErrorText = ""
    @State private var projectTitle = ""
    @State private var projectSubtitle = ""
    @State private var projectImageSelection: SelectedProjectImage?
    @State private var projectCoverPickerItem: PhotosPickerItem?
    @State private var projectCategory = ""
    @State private var projectLocation = ""
    @State private var projectGoalMinor = "500000"
    @State private var projectDurationDays = "14"
    @State private var projectDescription = ""
    @State private var projectUrlDraft = ""
    @State private var projectUrls: [String] = []
    @State private var projectPlanDrafts: [ProjectPlanDraft] = [
        ProjectPlanDraft(name: "Early Support", priceMinorText: "1000", rewardSummary: "Prototype update + thank-you card")
    ]
    @State private var planImagePickerItems: [UUID: PhotosPickerItem] = [:]
    @State private var selectedPlanImages: [UUID: SelectedProjectImage] = [:]
    @State private var showEndConfirm = false
    @State private var projectCreateInFlight = false
    @State private var projectCreateStatusText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let myProject {
                    Text("Project page")
                        .font(.headline)
                    projectDetailsView(project: myProject)
                    if myProject.status == "stopped" {
                        Text("Ended project. Refund policy: full refund.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if myProject.status == "active" || myProject.status == "draft" {
                        if myProject.support_count_total == 0 {
                            Button("Delete Project", role: .destructive) {
                                Task {
                                    await deleteProject(projectId: myProject.id)
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button("End Project", role: .destructive) {
                                showEndConfirm = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    if myProject.status == "stopped" || myProject.status == "failed" || myProject.status == "succeeded" {
                        Divider().padding(.vertical, 4)
                        createProjectSection(buttonTitle: "Create New Project")
                    }
                } else {
                    createProjectSection(buttonTitle: "Create Project")
                }

                if !projectHistory.isEmpty {
                    Divider().padding(.top, 8)
                    Text("Past projects")
                        .font(.subheadline.weight(.semibold))
                    ForEach(projectHistory, id: \.id) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(project.title)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(project.status.uppercased())
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                            Text("Goal: \(project.goal_amount_minor) \(project.currency)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let category = project.category, !category.isEmpty {
                                Text("Category: \(category)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Created: \(project.created_at)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }

                if !projectErrorText.isEmpty {
                    Text(projectErrorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                if projectCreateInFlight {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView()
                        Text(projectCreateStatusText.isEmpty ? "Creating project..." : projectCreateStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .task {
            await loadMyProjects()
        }
        .alert("End this project?", isPresented: $showEndConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Project", role: .destructive) {
                guard let projectId = myProject?.id else { return }
                Task {
                    await endProject(projectId: projectId)
                }
            }
        } message: {
            Text("Project will be marked as ended. Refund policy is fixed to full refund.")
        }
        .onChange(of: projectCoverPickerItem) { _, newValue in
            Task {
                await loadProjectCover(from: newValue)
            }
        }
    }

    private func createProjectSection(buttonTitle: String) -> some View {
        Group {
            Text("Create your project")
                .font(.headline)

            labeledField("Project Title", isOptional: false) {
                TextField("", text: $projectTitle)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("Subtitle", isOptional: true) {
                TextField("", text: $projectSubtitle)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("Project Image", isOptional: true) {
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $projectCoverPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label(projectImageSelection == nil ? "Select Cover Image" : "Change Cover Image", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    if let projectImageSelection, let uiImage = UIImage(data: projectImageSelection.data) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text("No image selected. A default placeholder will be used.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            labeledField("Category", isOptional: true) {
                TextField("", text: $projectCategory)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("Location", isOptional: true) {
                TextField("", text: $projectLocation)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("Funding Goal (JPY)", isOptional: false) {
                TextField("", text: $projectGoalMinor)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            labeledField("Project Duration (days)", isOptional: false) {
                TextField("", text: $projectDurationDays)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
            }

            labeledField("Description", isOptional: true) {
                TextField("", text: $projectDescription, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            labeledField("URLs", isOptional: true) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("", text: $projectUrlDraft)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                        Button("Add") {
                            addProjectURL()
                        }
                        .buttonStyle(.bordered)
                        .disabled(projectUrls.count >= 3)
                    }
                    Text("Up to 3 URLs")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if !projectUrls.isEmpty {
                        ForEach(Array(projectUrls.enumerated()), id: \.offset) { index, url in
                            HStack {
                                Text(url)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    projectUrls.remove(at: index)
                                }
                                .font(.caption)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            Text("Plans & returns")
                .font(.subheadline.weight(.semibold))
            ForEach(Array(projectPlanDrafts.indices), id: \.self) { index in
                VStack(alignment: .leading, spacing: 6) {
                    labeledField("Plan Name", isOptional: false) {
                        TextField("", text: $projectPlanDrafts[index].name)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Price (JPY)", isOptional: false) {
                        TextField("", text: $projectPlanDrafts[index].priceMinorText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.numberPad)
                    }
                    labeledField("Reward Summary", isOptional: false) {
                        TextField("", text: $projectPlanDrafts[index].rewardSummary)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Plan Description", isOptional: true) {
                        TextField("", text: $projectPlanDrafts[index].description, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                    }
                    labeledField("Plan Image", isOptional: true) {
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: planPickerBinding(for: projectPlanDrafts[index].id), matching: .images, photoLibrary: .shared()) {
                                Label(selectedPlanImages[projectPlanDrafts[index].id] == nil ? "Select Plan Image" : "Change Plan Image", systemImage: "photo.on.rectangle")
                            }
                            .buttonStyle(.bordered)
                            if let selected = selectedPlanImages[projectPlanDrafts[index].id], let uiImage = UIImage(data: selected.data) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(height: 120)
                                    .frame(maxWidth: .infinity)
                                    .clipped()
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            } else {
                                Text("No image selected")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if index > 0 {
                        Button("Remove plan", role: .destructive) {
                            let planId = projectPlanDrafts[index].id
                            projectPlanDrafts.remove(at: index)
                            selectedPlanImages[planId] = nil
                            planImagePickerItems[planId] = nil
                        }
                        .font(.caption)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Button("Add plan") {
                let draft = ProjectPlanDraft(name: "", priceMinorText: "", rewardSummary: "")
                projectPlanDrafts.append(draft)
            }
            .buttonStyle(.bordered)

            Button(projectCreateInFlight ? "Creating..." : buttonTitle) {
                Task {
                    await createProject()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(projectCreateInFlight)
        }
    }

    private func projectDetailsView(project: MyProjectResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let funded = max(project.funded_amount_minor, 0)
            let goal = max(project.goal_amount_minor, 1)
            let progress = min(Double(funded) / Double(goal), 1.0)
            let percent = Int((Double(funded) / Double(goal)) * 100.0)

            if let imageURL = project.image_url, let url = URL(string: imageURL) {
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
                .tint(progress >= 1 ? .green : .blue)
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

            Text("Status: \(project.status.uppercased())")
                .font(.caption2)
                .foregroundStyle(project.status == "stopped" ? .orange : .secondary)
        }
    }

    @ViewBuilder
    private func labeledField<Content: View>(_ title: String, isOptional: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(isOptional ? "\(title) (optional)" : title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func addProjectURL() {
        let trimmed = projectUrlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard projectUrls.count < 3 else {
            projectErrorText = "You can add up to 3 URLs"
            return
        }
        guard let normalized = normalizeURLString(trimmed) else {
            projectErrorText = "URL format is invalid"
            return
        }
        if !projectUrls.contains(normalized) {
            projectUrls.append(normalized)
        }
        projectUrlDraft = ""
        projectErrorText = ""
    }

    private func normalizeURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: withScheme) else { return nil }
        guard let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = components.host, !host.isEmpty else { return nil }
        return components.url?.absoluteString
    }

    private func planPickerBinding(for planId: UUID) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { planImagePickerItems[planId] },
            set: { newValue in
                planImagePickerItems[planId] = newValue
                guard let newValue else {
                    selectedPlanImages[planId] = nil
                    return
                }
                Task {
                    await loadPlanImage(from: newValue, planId: planId)
                }
            }
        )
    }

    private func loadProjectCover(from pickerItem: PhotosPickerItem?) async {
        guard let pickerItem else {
            projectImageSelection = nil
            return
        }
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read selected image"])
            }
            let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "project-cover.jpg"
            let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
            await MainActor.run {
                projectImageSelection = SelectedProjectImage(data: data, fileName: fileName, contentType: contentType)
                projectErrorText = ""
            }
        } catch {
            await MainActor.run {
                projectImageSelection = nil
                projectErrorText = error.localizedDescription
            }
        }
    }

    private func loadPlanImage(from pickerItem: PhotosPickerItem, planId: UUID) async {
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read selected plan image"])
            }
            let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "plan-image.jpg"
            let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
            await MainActor.run {
                selectedPlanImages[planId] = SelectedProjectImage(data: data, fileName: fileName, contentType: contentType)
                projectErrorText = ""
            }
        } catch {
            await MainActor.run {
                selectedPlanImages[planId] = nil
                projectErrorText = error.localizedDescription
            }
        }
    }

    private func loadMyProjects() async {
        projectLoading = true
        defer { projectLoading = false }
        do {
            let projects = try await client.listMyProjects()
            await MainActor.run {
                myProject = projects.first(where: { $0.status == "active" || $0.status == "draft" })
                projectHistory = projects.filter { $0.status != "active" && $0.status != "draft" }
                projectErrorText = ""
            }
        } catch {
            await MainActor.run {
                myProject = nil
                projectHistory = []
            }
        }
    }

    private func createProject() async {
        projectErrorText = ""
        projectCreateInFlight = true
        projectCreateStatusText = "Validating input..."
        defer {
            projectCreateInFlight = false
            projectCreateStatusText = ""
        }
        do {
            guard !projectTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Project title is required"])
            }
            guard let goal = Int(projectGoalMinor), goal > 0 else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Goal amount must be positive"])
            }
            guard let days = Int(projectDurationDays), days >= 1 else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Duration must be at least 1 day"])
            }
            let normalizedUrls = try projectUrls.map { raw -> String in
                guard let normalized = normalizeURLString(raw) else {
                    throw NSError(
                        domain: "LifeCastProject",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "URL format is invalid: \(raw)"]
                    )
                }
                return normalized
            }
            var imageURL: String?
            if let cover = projectImageSelection {
                projectCreateStatusText = "Uploading project image..."
                imageURL = try await client.uploadProjectImage(
                    data: cover.data,
                    fileName: cover.fileName,
                    contentType: cover.contentType
                )
            }

            var uploadedImageMap: [UUID: String] = [:]
            var imageIndex = 0
            for draft in projectPlanDrafts {
                guard let selected = selectedPlanImages[draft.id] else { continue }
                imageIndex += 1
                projectCreateStatusText = "Uploading plan image \(imageIndex)..."
                let uploaded = try await client.uploadProjectImage(
                    data: selected.data,
                    fileName: selected.fileName,
                    contentType: selected.contentType
                )
                uploadedImageMap[draft.id] = uploaded
            }

            let parsedPlans = try projectPlanDrafts.map { draft -> CreateProjectRequest.Plan in
                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let reward = draft.rewardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Plan name is required"])
                }
                guard !reward.isEmpty else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Plan reward summary is required"])
                }
                guard let price = Int(draft.priceMinorText), price > 0 else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Plan price must be positive"])
                }
                    let desc = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
                    return .init(
                        name: name,
                        price_minor: price,
                        reward_summary: reward,
                        description: desc.isEmpty ? nil : desc,
                        image_url: uploadedImageMap[draft.id],
                        currency: "JPY"
                    )
            }

            projectCreateStatusText = "Creating project..."
            let project = try await client.createProject(
                title: projectTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                subtitle: projectSubtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : projectSubtitle.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURL: imageURL,
                category: projectCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : projectCategory.trimmingCharacters(in: .whitespacesAndNewlines),
                location: projectLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : projectLocation.trimmingCharacters(in: .whitespacesAndNewlines),
                goalAmountMinor: goal,
                currency: "JPY",
                projectDurationDays: days,
                deadlineAtISO8601: nil,
                description: projectDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : projectDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                urls: normalizedUrls,
                plans: parsedPlans
            )
            await MainActor.run {
                myProject = project
                projectHistory = projectHistory.filter { $0.id != project.id }
                projectErrorText = ""
                projectCreateStatusText = "Created"
                onProjectChanged()
            }
        } catch {
            await MainActor.run {
                projectErrorText = (error as NSError).localizedDescription
            }
        }
    }

    private func deleteProject(projectId: UUID) async {
        do {
            try await client.deleteProject(projectId: projectId)
            await MainActor.run {
                myProject = nil
                onProjectChanged()
            }
        } catch {
            await MainActor.run {
                projectErrorText = (error as NSError).localizedDescription
            }
        }
    }

    private func endProject(projectId: UUID) async {
        do {
            try await client.endProject(projectId: projectId, reason: "creator_manual_end")
            await loadMyProjects()
            await MainActor.run {
                projectErrorText = ""
                onProjectChanged()
            }
        } catch {
            await MainActor.run {
                projectErrorText = (error as NSError).localizedDescription
            }
        }
    }
}

struct PostedVideosListView: View {
    let videos: [MyVideo]
    let errorText: String
    let onRefreshVideos: () -> Void
    @State private var selectedVideo: MyVideo?
    @State private var thumbnailCacheBust = UUID().uuidString

    private var newestFirstVideos: [MyVideo] {
        videos.sorted { lhs, rhs in
            lhs.created_at > rhs.created_at
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Posted videos")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    thumbnailCacheBust = UUID().uuidString
                    onRefreshVideos()
                }
                .font(.caption)
            }
            .padding(.horizontal, 16)

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }

            if newestFirstVideos.isEmpty {
                Text("No uploaded videos yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 4) {
                        ForEach(Array(newestFirstVideos.enumerated()), id: \.element.video_id) { index, video in
                            Button {
                                selectedVideo = video
                            } label: {
                                ZStack(alignment: .bottomLeading) {
                                    if let thumbnail = video.thumbnail_url, let thumbnailURL = thumbnailURL(base: thumbnail) {
                                        AsyncImage(url: thumbnailURL) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            LinearGradient(
                                                colors: [Color.blue.opacity(0.5), Color.pink.opacity(0.6)],
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        }
                                    } else {
                                        Rectangle()
                                            .fill(
                                                LinearGradient(
                                                    colors: [Color.blue.opacity(0.5), Color.pink.opacity(0.6)],
                                                    startPoint: .top,
                                                    endPoint: .bottom
                                                )
                                            )
                                    }
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 28))
                                        .foregroundStyle(.white.opacity(0.9))
                                    LinearGradient(
                                        colors: [Color.black.opacity(0.0), Color.black.opacity(0.55)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                                .frame(maxWidth: .infinity)
                                .aspectRatio(9.0 / 16.0, contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("posted-grid-video-\(index)")
                            .accessibilityLabel("Open posted \(index)")
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            CreatorPostedFeedView(
                videos: newestFirstVideos,
                initialVideoId: video.video_id,
                client: LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!),
                isCurrentUserVideo: true,
                onVideoDeleted: {
                    onRefreshVideos()
                }
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
}

struct CreatorPostedFeedView: View {
    let videos: [MyVideo]
    let initialVideoId: UUID
    let client: LifeCastAPIClient
    let isCurrentUserVideo: Bool
    let onVideoDeleted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedVideos: [MyVideo]
    @State private var currentIndex: Int
    @State private var player: AVPlayer?
    @State private var showComments = false
    @State private var showShare = false
    @State private var showActions = false
    @State private var deleteErrorText = ""

    init(
        videos: [MyVideo],
        initialVideoId: UUID,
        client: LifeCastAPIClient,
        isCurrentUserVideo: Bool,
        onVideoDeleted: @escaping () -> Void
    ) {
        self.videos = videos
        self.initialVideoId = initialVideoId
        self.client = client
        self.isCurrentUserVideo = isCurrentUserVideo
        self.onVideoDeleted = onVideoDeleted
        let initial = videos.firstIndex(where: { $0.video_id == initialVideoId }) ?? 0
        _feedVideos = State(initialValue: videos)
        _currentIndex = State(initialValue: initial)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.ignoresSafeArea()

            if feedVideos.isEmpty {
                Text("No videos")
                    .foregroundStyle(.white)
            } else {
                feedPage(video: feedVideos[currentIndex], project: currentProject)
                    .accessibilityIdentifier("posted-feed-view")
                    .gesture(
                        DragGesture(minimumDistance: 24)
                            .onEnded { value in
                                if value.translation.height < -50 {
                                    showOlder()
                                } else if value.translation.height > 50 {
                                    showNewer()
                                }
                            }
                    )
            }

            HStack {
                Button {
                    dismiss()
                }
                label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .padding(10)
                        .background(Color.black.opacity(0.45))
                        .foregroundStyle(.white)
                        .clipShape(Circle())
                }
                .accessibilityIdentifier("posted-feed-back")

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
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
        .confirmationDialog("Video actions", isPresented: $showActions, titleVisibility: .visible) {
            Button("Insights (Coming Soon)") {}
            if isCurrentUserVideo {
                Button("Delete video", role: .destructive) {
                    Task {
                        await deleteCurrentVideo()
                    }
                }
            } else {
                Button("Not interested") {}
                Button("Report", role: .destructive) {}
            }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .top) {
            if !deleteErrorText.isEmpty {
                Text(deleteErrorText)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.75))
                    .clipShape(Capsule())
                    .padding(.top, 56)
            }
        }
        .onAppear {
            syncPlayerForCurrentIndex()
        }
        .onChange(of: currentIndex) { _, _ in
            syncPlayerForCurrentIndex()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private var currentProject: FeedProjectSummary {
        sampleProjects.first ?? FeedProjectSummary(
            id: UUID(),
            creatorId: UUID(),
            username: "lifecast_maker",
            caption: "Prototype update",
            minPlanPriceMinor: 1000,
            goalAmountMinor: 1_000_000,
            fundedAmountMinor: 1_120_000,
            remainingDays: 12,
            likes: 4500,
            comments: 173,
            isSupportedByCurrentUser: false
        )
    }

    private func feedPage(video: MyVideo, project: FeedProjectSummary) -> some View {
        ZStack(alignment: .bottom) {
            if let currentPlayer = player {
                VideoPlayer(player: currentPlayer)
                    .ignoresSafeArea()
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .ignoresSafeArea()
            }

            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.7)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("@\(project.username)")
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(project.caption)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                        .lineLimit(2)

                    fundingMeta(project: project)
                }

                Spacer(minLength: 12)

                rightRail(project: project)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
    }

    private func rightRail(project: FeedProjectSummary) -> some View {
        VStack(spacing: 16) {
            Text(project.isSupportedByCurrentUser ? "Supported" : "Support")
                .font(.caption.bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(project.isSupportedByCurrentUser ? Color.green.opacity(0.9) : Color.pink.opacity(0.9))
                .foregroundStyle(.white)
                .clipShape(Capsule())

            metricView(icon: "heart.fill", value: project.likes)
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
            Button {
                showActions = true
            } label: {
                Image(systemName: "ellipsis")
                    .font(.title2)
            }
            .accessibilityIdentifier("video-actions")
        }
        .foregroundStyle(.white)
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

    private func syncPlayerForCurrentIndex() {
        guard !feedVideos.isEmpty else {
            player?.pause()
            player = nil
            return
        }
        guard currentIndex >= 0 && currentIndex < feedVideos.count else {
            currentIndex = max(0, min(currentIndex, feedVideos.count - 1))
            return
        }
        guard let playbackUrl = feedVideos[currentIndex].playback_url, let url = URL(string: playbackUrl) else {
            player?.pause()
            player = nil
            return
        }
        let newPlayer = AVPlayer(url: url)
        newPlayer.play()
        player?.pause()
        player = newPlayer
    }

    private func showOlder() {
        guard currentIndex < feedVideos.count - 1 else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            currentIndex += 1
        }
    }

    private func showNewer() {
        guard currentIndex > 0 else { return }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            currentIndex -= 1
        }
    }

    private func deleteCurrentVideo() async {
        guard !feedVideos.isEmpty else { return }
        let target = feedVideos[currentIndex]
        do {
            try await client.deleteVideo(videoId: target.video_id)
            await MainActor.run {
                deleteErrorText = ""
                feedVideos.removeAll(where: { $0.video_id == target.video_id })
                if feedVideos.isEmpty {
                    onVideoDeleted()
                    dismiss()
                    return
                }
                currentIndex = min(currentIndex, feedVideos.count - 1)
                onVideoDeleted()
            }
        } catch {
            await MainActor.run {
                deleteErrorText = "Delete failed: \(error.localizedDescription)"
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
                        HStack(spacing: 10) {
                            Text(page.viewer_relationship.is_following ? "Following" : "Follow")
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.blue.opacity(0.12))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
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

                    Picker("CreatorTabs", selection: $selectedIndex) {
                        Text("Project").tag(0)
                        Text("Posts").tag(1)
                        Text("Liked").tag(2)
                    }
                    .pickerStyle(.segmented)
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
        .navigationTitle("Creator")
        .task {
            await load()
        }
    }

    private func creatorProjectSection(page: CreatorPublicPageResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let project = page.project {
                let funded = max(project.funded_amount_minor, 0)
                let goal = max(project.goal_amount_minor, 1)
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
                    .tint(progress >= 1 ? .green : .blue)
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

                Button("Support this project") {
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
}

struct UploadCreateView: View {
    let client: LifeCastAPIClient
    let onUploadReady: () -> Void
    let onOpenProjectTab: () -> Void

    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var selectedUploadVideo: SelectedUploadVideo?
    @State private var myProject: MyProjectResult?
    @State private var projectLoading = false
    @State private var projectErrorText = ""
    @State private var state: UploadFlowState = .idle
    @State private var uploadProgress: Double = 0
    @State private var uploadSessionId: UUID?
    @State private var videoId: String?
    @State private var statusText = "Not started"
    @State private var errorText = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create")
                    .font(.headline)

                if let myProject {
                    projectSummary(project: myProject)
                    uploadSection
                } else {
                    projectRequiredSection
                }

                Spacer()
            }
            .padding(16)
            .navigationTitle("Create")
            .task {
                await loadActiveProject()
            }
            .onChange(of: selectedPickerItem) { _, newValue in
                Task {
                    await loadSelectedVideo(from: newValue)
                }
            }
        }
    }

    private var projectRequiredSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Project required")
                .font(.subheadline.weight(.semibold))
            Text("Create a project in Me > Project tab before uploading videos.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Open Project Tab") {
                onOpenProjectTab()
            }
            .buttonStyle(.borderedProminent)

            if projectLoading {
                ProgressView("Checking project...")
                    .font(.caption)
            }

            if !projectErrorText.isEmpty {
                Text(projectErrorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

        }
    }

    private var uploadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(
                selection: $selectedPickerItem,
                matching: .videos,
                photoLibrary: .shared()
            ) {
                Label(selectedUploadVideo == nil ? "Select Video" : "Change Video", systemImage: "video.badge.plus")
            }
            .buttonStyle(.bordered)

            if let selectedUploadVideo {
                Text("Selected: \(selectedUploadVideo.fileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No video selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            statusPill

            ProgressView(value: uploadProgress, total: 1)
                .tint(state == .failed ? .red : .blue)

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let uploadSessionId {
                Text("Session: \(uploadSessionId.uuidString)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let videoId {
                Text("Video: \(videoId)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Start Upload") {
                    Task {
                        await startUploadFlow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(state == .uploading || state == .processing)

                Button("Retry") {
                    Task {
                        await retryOrResumeFlow()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(uploadSessionId == nil || (state != .failed && state != .processing))

                Button("Reset") {
                    reset()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func projectSummary(project: MyProjectResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(project.title)
                .font(.subheadline.weight(.semibold))
            Text("Goal: \(project.goal_amount_minor) \(project.currency)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let minimumPlan = project.minimum_plan {
                Text("Min plan: \(minimumPlan.name) / \(minimumPlan.price_minor) \(minimumPlan.currency)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusPill: some View {
        Text(state.rawValue.uppercased())
            .font(.caption.bold())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(stateColor.opacity(0.15))
            .foregroundStyle(stateColor)
            .clipShape(Capsule())
    }

    private var stateColor: Color {
        switch state {
        case .idle: return .secondary
        case .created: return .blue
        case .uploading: return .blue
        case .processing: return .orange
        case .ready: return .green
        case .failed: return .red
        }
    }

    private func startUploadFlow() async {
        errorText = ""
        uploadProgress = 0
        state = .created
        statusText = "Preparing selected video..."

        do {
            guard let selectedUploadVideo else {
                throw NSError(
                    domain: "LifeCastUpload",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Select a video first"]
                )
            }

            uploadProgress = 0.2
            statusText = "Creating upload session..."
            guard let myProject else {
                throw NSError(domain: "LifeCastUpload", code: -4, userInfo: [NSLocalizedDescriptionKey: "Project not created"])
            }
            let create = try await client.createUploadSession(
                projectId: myProject.id,
                fileName: selectedUploadVideo.fileName,
                contentType: selectedUploadVideo.contentType,
                fileSizeBytes: selectedUploadVideo.data.count,
                idempotencyKey: "ios-upload-create-\(UUID().uuidString)"
            )
            uploadSessionId = create.upload_session_id
            videoId = create.video_id
            state = .uploading
            statusText = "Uploading video..."
            uploadProgress = 0.45

            guard let uploadURLText = create.upload_url, let uploadURL = URL(string: uploadURLText) else {
                throw NSError(
                    domain: "LifeCastUpload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Upload URL missing from server response"]
                )
            }
            let uploadedStorageKey: String
            let uploadedHash: String
            if uploadURL.host == "localhost" || uploadURL.host == "127.0.0.1" {
                let uploaded = try await client.uploadBinary(
                    uploadURL: uploadURL,
                    data: selectedUploadVideo.data,
                    contentType: selectedUploadVideo.contentType
                )
                uploadedStorageKey = uploaded.storage_object_key
                uploadedHash = uploaded.content_hash_sha256
            } else {
                try await client.uploadBinaryDirect(
                    uploadURL: uploadURL,
                    data: selectedUploadVideo.data,
                    contentType: selectedUploadVideo.contentType
                )
                uploadedStorageKey = "cloudflare://direct-upload/\(create.upload_session_id.uuidString)"
                uploadedHash = uniquePseudoSha256()
            }
            uploadProgress = 0.85

            let complete = try await client.completeUploadSession(
                uploadSessionId: create.upload_session_id,
                storageObjectKey: uploadedStorageKey,
                contentHashSha256: uploadedHash,
                idempotencyKey: "ios-upload-complete-\(UUID().uuidString)"
            )
            videoId = complete.video_id
            state = .processing
            statusText = "Processing upload..."
            uploadProgress = 1

            await pollUploadStatus(uploadSessionId: create.upload_session_id)
        } catch {
            state = .failed
            statusText = "Upload failed"
            errorText = userFacingUploadErrorMessage(error, context: .upload)
        }
    }

    private func pollUploadStatus(uploadSessionId: UUID) async {
        for _ in 0..<25 {
            do {
                let session = try await client.getUploadSession(uploadSessionId: uploadSessionId)
                videoId = session.video_id

                if session.status == "ready" {
                    state = .ready
                    statusText = "Upload ready for playback"
                    onUploadReady()
                    return
                }
                if session.status == "failed" {
                    state = .failed
                    statusText = "Upload processing failed"
                    return
                }

                state = .processing
                statusText = "Processing upload..."
            } catch {
                state = .failed
                statusText = "Upload status check failed"
                errorText = userFacingUploadErrorMessage(error, context: .statusPoll)
                return
            }

            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        state = .processing
        statusText = "Still processing (timeout in demo poll window)"
    }

    private func retryOrResumeFlow() async {
        guard let uploadSessionId else {
            errorText = "No upload session to resume"
            return
        }

        do {
            let current = try await client.getUploadSession(uploadSessionId: uploadSessionId)
            videoId = current.video_id
            errorText = ""

            if current.status == "ready" {
                state = .ready
                statusText = "Upload already ready"
                uploadProgress = 1
                return
            }

            if current.status == "processing" {
                state = .processing
                statusText = "Resuming processing poll..."
                uploadProgress = 1
                await pollUploadStatus(uploadSessionId: uploadSessionId)
                return
            }

            if current.status == "created" || current.status == "uploading" {
                await startUploadFlow()
                return
            }

            state = .failed
            statusText = "Upload cannot be resumed"
        } catch {
            state = .failed
            statusText = "Retry failed"
            errorText = userFacingUploadErrorMessage(error, context: .retry)
        }
    }

    private func reset() {
        state = .idle
        uploadProgress = 0
        uploadSessionId = nil
        videoId = nil
        statusText = "Not started"
        errorText = ""
    }

    private func loadSelectedVideo(from pickerItem: PhotosPickerItem?) async {
        guard let pickerItem else { return }
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                throw NSError(
                    domain: "LifeCastUpload",
                    code: -3,
                    userInfo: [NSLocalizedDescriptionKey: "Could not read selected video data"]
                )
            }

            let fileName = pickerItem.itemIdentifier.map { "\($0).mov" } ?? "selected-video.mov"
            let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.movie.preferredMIMEType ?? "video/quicktime"

            await MainActor.run {
                selectedUploadVideo = SelectedUploadVideo(
                    data: data,
                    fileName: fileName,
                    contentType: contentType
                )
                state = .idle
                statusText = "Ready to upload selected video"
                errorText = ""
            }
        } catch {
            await MainActor.run {
                selectedUploadVideo = nil
                state = .failed
                statusText = "Video selection failed"
                errorText = error.localizedDescription
            }
        }
    }

    private func uniquePseudoSha256() -> String {
        let base = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return base + base
    }

    private func loadActiveProject() async {
        projectLoading = true
        defer { projectLoading = false }
        do {
            let project = try await client.getMyProject()
            await MainActor.run {
                myProject = project
                projectErrorText = ""
            }
        } catch {
            await MainActor.run {
                myProject = nil
                projectErrorText = ""
            }
        }
    }

    private enum UploadErrorContext {
        case upload
        case statusPoll
        case retry
    }

    private func userFacingUploadErrorMessage(_ error: Error, context: UploadErrorContext) -> String {
        let nsError = error as NSError
        let apiCode = (nsError.userInfo["code"] as? String)?.uppercased()
        let message = nsError.localizedDescription.lowercased()
        if apiCode == "STATE_CONFLICT" {
            return "Duplicate upload detected. Choose a different video."
        }
        if apiCode == "RESOURCE_NOT_FOUND" {
            return context == .statusPoll
                ? "Upload session not found. Start upload again."
                : "Resource not found. Please retry from the beginning."
        }
        if apiCode == "VALIDATION_ERROR" {
            return "Upload request is invalid. Check the selected video and retry."
        }
        if message.contains("timed out") || message.contains("network") || message.contains("offline") {
            return "Network issue. Check connection and retry."
        }
        if message.contains("resource_not_found") || message.contains("not found") {
            return context == .statusPoll
                ? "Upload session not found. Start upload again."
                : "Resource not found. Please retry from the beginning."
        }
        if message.contains("state_conflict") || message.contains("hash already exists") {
            return "Duplicate upload detected. Choose a different video."
        }
        if message.contains("direct upload failed") || message.contains("cloudflare") {
            return "Video upload service error. Retry in a moment."
        }
        if message.contains("could not read selected video data") || message.contains("select a video first") {
            return "Please select a video before uploading."
        }
        if message.contains("couldn’t be read because it isn’t in the correct format") || message.contains("correct format") {
            return "Server response format changed. Please retry."
        }
        return "Upload failed. Please retry."
    }
}

private struct SelectedUploadVideo {
    let data: Data
    let fileName: String
    let contentType: String
}

private struct ProjectPlanDraft: Identifiable {
    let id = UUID()
    var name: String
    var priceMinorText: String
    var rewardSummary: String
    var description: String = ""
}

private struct SelectedProjectImage {
    let data: Data
    let fileName: String
    let contentType: String
}

private let sampleProjects: [FeedProjectSummary] = [
    FeedProjectSummary(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        username: "tak_game_lab",
        caption: "Building our handheld game prototype. Today: thermal and battery test.",
        minPlanPriceMinor: 1000,
        goalAmountMinor: 1_000_000,
        fundedAmountMinor: 1_120_000,
        remainingDays: 12,
        likes: 4520,
        comments: 173,
        isSupportedByCurrentUser: false
    ),
    FeedProjectSummary(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        username: "lifecast_maker",
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
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        username: "tak_game_lab",
        caption: "Low-profile keyboard prototype: key feel tuning sprint.",
        minPlanPriceMinor: 1500,
        goalAmountMinor: 1_500_000,
        fundedAmountMinor: 910_000,
        remainingDays: 9,
        likes: 3380,
        comments: 129,
        isSupportedByCurrentUser: false
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
