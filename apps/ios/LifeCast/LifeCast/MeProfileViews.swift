import PhotosUI
import UniformTypeIdentifiers
import UIKit
import SwiftUI
struct MeTabView: View {
    let client: LifeCastAPIClient
    let isAuthenticated: Bool
    let myProfile: CreatorPublicProfile?
    let myProfileStats: CreatorProfileStats?
    let myVideos: [MyVideo]
    let myVideosError: String
    let onRefreshProfile: () -> Void
    let onRefreshVideos: () -> Void
    let onProjectChanged: () -> Void
    let onOpenAuth: () -> Void

    @State private var selectedIndex = 0
    @State private var showNetwork = false
    @State private var selectedNetworkTab: CreatorNetworkTab = .following
    @State private var showUserSwitcher = false
    @State private var showEditProfile = false
    @State private var supportedProjects: [SupportedProjectRow] = []
    @State private var supportedProjectsLoading = false
    @State private var supportedProjectsError = ""
    
    private var currentUsername: String {
        myProfile?.username ?? "lifecast_maker"
    }
    
    private var currentDisplayName: String {
        let name = (myProfile?.display_name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? currentUsername : name
    }

    var body: some View {
        NavigationStack {
            Group {
                if isAuthenticated {
                    ScrollView {
                        LazyVStack(spacing: 16, pinnedViews: [.sectionHeaders]) {
                            ProfileOverviewSection(
                                avatarURL: myProfile?.avatar_url,
                                displayName: currentDisplayName,
                                bioText: myProfile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                                followingCount: myProfileStats?.following_count ?? 0,
                                followersCount: myProfileStats?.followers_count ?? 0,
                                supportCount: myProfileStats?.supported_project_count ?? 0,
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
                                Button("Edit Profile") {
                                    showEditProfile = true
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 136, height: 36)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 6)

                            Section {
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
                                            onRefreshVideos: onRefreshVideos,
                                            creatorProfile: myProfile
                                        )
                                    } else {
                                        SupportedProjectsListView(
                                            rows: supportedProjects,
                                            isLoading: supportedProjectsLoading,
                                            errorText: supportedProjectsError,
                                            emptyText: "No supported projects yet",
                                            onRefresh: {
                                                Task { await loadMySupportedProjects() }
                                            }
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } header: {
                                ProfileTabIconStrip(selectedIndex: $selectedIndex, style: .fullWidthUnderline)
                                    .background(Color.white)
                                    .onChange(of: selectedIndex) { _, newValue in
                                        if newValue == 1 {
                                            onRefreshVideos()
                                        } else if newValue == 2 {
                                            Task { await loadMySupportedProjects() }
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .background(
                        ScrollBounceConfigurator(disabled: false)
                    )
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: appBottomBarHeight + 20)
                    }
                    .refreshable {
                        onRefreshProfile()
                        switch selectedIndex {
                        case 1:
                            onRefreshVideos()
                        case 2:
                            await loadMySupportedProjects()
                        default:
                            break
                        }
                    }
                } else {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 46))
                            .foregroundStyle(.secondary)
                        Text("Sign in to use your profile")
                            .font(.headline)
                        Text("Follow creators, support projects, and manage your own posts after signing in.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                        Button("Sign In / Sign Up") {
                            onOpenAuth()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
            }
            .task {
                guard isAuthenticated else { return }
                onRefreshProfile()
                onRefreshVideos()
                await loadMySupportedProjects()
            }
            .navigationDestination(isPresented: $showNetwork) {
                if let profile = myProfile {
                    CreatorNetworkView(
                        client: client,
                        creatorUserId: profile.creator_user_id,
                        creatorUsername: profile.username,
                        initialTab: selectedNetworkTab,
                        useMyNetworkEndpoint: true
                    )
                } else {
                    Text("Profile not loaded")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationDestination(isPresented: $showUserSwitcher) {
                DevUserSwitcherSheet(
                    client: client,
                    onSwitched: {
                        onRefreshProfile()
                        onRefreshVideos()
                        onProjectChanged()
                    },
                    onOpenAuth: {
                        onOpenAuth()
                    }
                )
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView(
                    client: client,
                    profile: myProfile,
                    onSaved: {
                        onRefreshProfile()
                    }
                )
            }
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                mePinnedHeader
            }
        }
    }

    private var mePinnedHeader: some View {
        ZStack {
            Text("@\(currentUsername)")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 56)

            HStack {
                Spacer()
                Button {
                    showUserSwitcher = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 2)
        .background(Color.white)
    }

    private func loadMySupportedProjects() async {
        guard isAuthenticated else {
            await MainActor.run {
                supportedProjects = []
                supportedProjectsError = ""
                supportedProjectsLoading = false
            }
            return
        }
        await MainActor.run { supportedProjectsLoading = true }
        defer {
            Task { @MainActor in
                supportedProjectsLoading = false
            }
        }
        do {
            let rows = try await client.getMySupportedProjects(limit: 50)
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

}

private struct ScrollBounceConfigurator: UIViewRepresentable {
    let disabled: Bool

    func makeUIView(context: Context) -> UIView {
        UIView(frame: .zero)
    }

    func updateUIView(_ view: UIView, context: Context) {
        let apply = {
            if let scrollView = findNearestScrollView(from: view) ?? view.window.flatMap(findFirstScrollView(in:)) {
                scrollView.bounces = !disabled
                scrollView.alwaysBounceVertical = !disabled
                scrollView.alwaysBounceHorizontal = false
                scrollView.showsHorizontalScrollIndicator = false
            }
        }
        DispatchQueue.main.async(execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: apply)
    }

    private func findNearestScrollView(from view: UIView) -> UIScrollView? {
        var current: UIView? = view
        while let node = current {
            if let scroll = node as? UIScrollView {
                return scroll
            }
            if let childScroll = findFirstScrollView(in: node) {
                return childScroll
            }
            current = node.superview
        }
        return nil
    }

    private func findFirstScrollView(in root: UIView) -> UIScrollView? {
        if let scroll = root as? UIScrollView {
            return scroll
        }
        for child in root.subviews {
            if let scroll = findFirstScrollView(in: child) {
                return scroll
            }
        }
        return nil
    }
}

struct DevUserSwitcherSheet: View {
    let client: LifeCastAPIClient
    let onSwitched: () -> Void
    let onOpenAuth: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [DevAuthUser] = []
    @State private var loading = false
    @State private var errorText = ""
    @State private var signedInUserEmail = ""
    @State private var isSignedIn = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("設定")
                        .font(.headline)
                    Spacer()
                    Color.clear.frame(width: 18, height: 18)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)

                List {
                    Section("Account") {
                        if isSignedIn {
                            if !signedInUserEmail.isEmpty {
                                Text(signedInUserEmail)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Button("Sign Out", role: .destructive) {
                                Task { await signOut() }
                            }
                        } else {
                            Text("Not signed in")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("Sign In / Sign Up") {
                                dismiss()
                                onOpenAuth()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    Section("Dev User Switch") {
                        ForEach(rows) { row in
                            Button {
                                Task {
                                    await switchUser(row.user_id)
                                }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("@\(row.username)")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        if let displayName = row.display_name, !displayName.isEmpty {
                                            Text(displayName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if row.is_creator {
                                        Text("Creator")
                                            .font(.caption2.bold())
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.green.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .overlay {
                if loading {
                    ProgressView("Switching user...")
                        .padding(20)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if rows.isEmpty && errorText.isEmpty {
                    ContentUnavailableView("No users", systemImage: "person.3")
                }
            }
            .navigationTitle("設定")
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) {
                if !errorText.isEmpty {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.thinMaterial)
                }
            }
            .task {
                await loadUsers()
                await refreshSessionState()
            }
            .refreshable {
                await loadUsers()
                await refreshSessionState()
            }
        }
    }

    private func loadUsers() async {
        loading = true
        defer { loading = false }
        do {
            rows = try await client.listDevAuthUsers()
            errorText = ""
        } catch {
            rows = []
            errorText = error.localizedDescription
        }
    }

    private func switchUser(_ userId: UUID) async {
        loading = true
        defer { loading = false }
        do {
            try await client.switchDevUser(userId: userId)
            errorText = ""
            await refreshSessionState()
            onSwitched()
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func signOut() async {
        loading = true
        defer { loading = false }
        do {
            try await client.signOut()
            errorText = ""
            isSignedIn = false
            signedInUserEmail = ""
            onSwitched()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refreshSessionState() async {
        guard client.hasAuthSession else {
            isSignedIn = false
            signedInUserEmail = ""
            return
        }
        do {
            let session = try await client.getAuthMe()
            isSignedIn = true
            signedInUserEmail = session.profile?.display_name ?? ""
        } catch {
            isSignedIn = false
            signedInUserEmail = ""
        }
    }

}

struct EditProfileView: View {
    let client: LifeCastAPIClient
    let profile: CreatorPublicProfile?
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var displayName: String
    @State private var bio: String
    @State private var avatarURL: String?
    @State private var avatarPickerItem: PhotosPickerItem?
    @State private var avatarSelection: SelectedProjectImage?
    @State private var saving = false
    @State private var errorText = ""

    init(client: LifeCastAPIClient, profile: CreatorPublicProfile?, onSaved: @escaping () -> Void) {
        self.client = client
        self.profile = profile
        self.onSaved = onSaved
        _displayName = State(initialValue: profile?.display_name ?? "")
        _bio = State(initialValue: profile?.bio ?? "")
        _avatarURL = State(initialValue: profile?.avatar_url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    HStack {
                        Spacer()
                        avatarPreview
                        Spacer()
                    }
                    PhotosPicker(selection: $avatarPickerItem, matching: .images, photoLibrary: .shared()) {
                        Label(avatarSelection == nil ? "Select Profile Image" : "Change Profile Image", systemImage: "photo")
                    }
                    TextField("Display name", text: $displayName)
                    TextField("Bio", text: $bio, axis: .vertical)
                        .lineLimit(3...5)
                }

                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving..." : "Save") {
                        Task { await saveProfile() }
                    }
                    .disabled(saving)
                }
            }
            .onChange(of: avatarPickerItem) { _, newValue in
                Task { await loadAvatar(from: newValue) }
            }
        }
    }

    @ViewBuilder
    private var avatarPreview: some View {
        if let avatarSelection, let uiImage = UIImage(data: avatarSelection.data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
        } else if let avatarURL, let url = URL(string: avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Circle().fill(Color.gray.opacity(0.3))
                }
            }
            .frame(width: 96, height: 96)
            .clipShape(Circle())
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 96, height: 96)
        }
    }

    private func loadAvatar(from pickerItem: PhotosPickerItem?) async {
        guard let pickerItem else {
            await MainActor.run {
                avatarSelection = nil
            }
            return
        }
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                throw NSError(domain: "LifeCastProfile", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read selected image"])
            }
            let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "profile-avatar.jpg"
            let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
            await MainActor.run {
                avatarSelection = SelectedProjectImage(data: data, fileName: fileName, contentType: contentType)
                errorText = ""
            }
        } catch {
            await MainActor.run {
                avatarSelection = nil
                errorText = error.localizedDescription
            }
        }
    }

    private func saveProfile() async {
        await MainActor.run {
            saving = true
            errorText = ""
        }
        defer {
            Task { @MainActor in
                saving = false
            }
        }

        do {
            var nextAvatarURL = avatarURL
            if let avatarSelection {
                nextAvatarURL = try await client.uploadProfileImage(
                    data: avatarSelection.data,
                    fileName: avatarSelection.fileName,
                    contentType: avatarSelection.contentType
                )
            }

            let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedDisplayName.count > 30 {
                throw NSError(domain: "LifeCastProfile", code: 400, userInfo: [NSLocalizedDescriptionKey: "Display name must be 30 characters or less"])
            }
            if normalizedBio.count > 160 {
                throw NSError(domain: "LifeCastProfile", code: 400, userInfo: [NSLocalizedDescriptionKey: "Bio must be 160 characters or less"])
            }

            _ = try await client.updateMyProfile(
                displayName: normalizedDisplayName.isEmpty ? nil : normalizedDisplayName,
                bio: normalizedBio.isEmpty ? nil : normalizedBio,
                avatarURL: nextAvatarURL
            )

            await MainActor.run {
                onSaved()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
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
    @State private var projectImageSelections: [SelectedProjectImage] = []
    @State private var projectCoverPickerItems: [PhotosPickerItem] = []
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
    @State private var showEditProjectSheet = false
    @State private var projectCreateInFlight = false
    @State private var projectCreateStatusText = ""
    @State private var hasLoadedProjectsOnce = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !hasLoadedProjectsOnce {
                ProgressView("Loading project...")
                    .font(.caption)
            } else if let myProject {
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
        .task {
            await loadMyProjects()
        }
        .sheet(isPresented: $showEditProjectSheet) {
            if let current = myProject {
                ProjectEditSheetView(
                    client: client,
                    project: current,
                    onSaved: {
                        Task {
                            await loadMyProjects()
                            onProjectChanged()
                        }
                    }
                )
            }
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
        .onChange(of: projectCoverPickerItems) { _, newValue in
            Task {
                await loadProjectCovers(from: newValue)
            }
        }
    }

    private func canEditProject(_ project: MyProjectResult) -> Bool {
        !["stopped", "failed", "succeeded"].contains(project.status)
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

            labeledField("Project Images", isOptional: false) {
                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $projectCoverPickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                        Label(projectImageSelections.isEmpty ? "Select Project Images" : "Change Project Images", systemImage: "photo")
                    }
                    .buttonStyle(.bordered)
                    Text("Up to 5 images. At least 1 image is required.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if projectImageSelections.isEmpty {
                        Text("No image selected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(Array(projectImageSelections.enumerated()), id: \.offset) { _, selection in
                                    if let uiImage = UIImage(data: selection.data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 96, height: 96)
                                            .clipped()
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
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
        ProfileProjectDetailView(
            project: project,
            headerActionTitle: canEditProject(project) ? "Edit" : nil,
            onTapHeaderAction: canEditProject(project) ? { showEditProjectSheet = true } : nil
        )
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

    private func loadProjectCovers(from pickerItems: [PhotosPickerItem]) async {
        if pickerItems.isEmpty {
            await MainActor.run {
                projectImageSelections = []
            }
            return
        }
        do {
            var nextSelections: [SelectedProjectImage] = []
            for pickerItem in pickerItems.prefix(5) {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not read selected image"])
                }
                let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "project-cover.jpg"
                let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
                nextSelections.append(SelectedProjectImage(data: data, fileName: fileName, contentType: contentType))
            }
            await MainActor.run {
                projectImageSelections = nextSelections
                projectErrorText = ""
            }
        } catch {
            await MainActor.run {
                projectImageSelections = []
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
                hasLoadedProjectsOnce = true
            }
        } catch {
            await MainActor.run {
                myProject = nil
                projectHistory = []
                hasLoadedProjectsOnce = true
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
            guard !projectImageSelections.isEmpty else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "At least one project image is required"])
            }

            var projectImageURLs: [String] = []
            var projectImageIndex = 0
            for cover in projectImageSelections.prefix(5) {
                projectImageIndex += 1
                projectCreateStatusText = "Uploading project image \(projectImageIndex)..."
                let uploadedURL = try await client.uploadProjectImage(
                    data: cover.data,
                    fileName: cover.fileName,
                    contentType: cover.contentType
                )
                projectImageURLs.append(uploadedURL)
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
                imageURL: projectImageURLs.first,
                imageURLs: projectImageURLs,
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

struct ProjectEditSheetView: View {
    let client: LifeCastAPIClient
    let project: MyProjectResult
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var subtitleText: String
    @State private var descriptionText: String
    @State private var urlDraft = ""
    @State private var urls: [String]
    @State private var coverPickerItems: [PhotosPickerItem] = []
    @State private var coverSelections: [SelectedProjectImage] = []
    @State private var planDrafts: [EditablePlanDraft]
    @State private var planPickerItems: [UUID: PhotosPickerItem] = [:]
    @State private var selectedPlanImages: [UUID: SelectedProjectImage] = [:]
    @State private var saving = false
    @State private var errorText = ""
    @FocusState private var focusedField: EditField?

    init(client: LifeCastAPIClient, project: MyProjectResult, onSaved: @escaping () -> Void) {
        self.client = client
        self.project = project
        self.onSaved = onSaved
        _subtitleText = State(initialValue: project.subtitle ?? "")
        _descriptionText = State(initialValue: project.description ?? "")
        _urls = State(initialValue: project.urls ?? [])
        _planDrafts = State(
            initialValue: (project.plans ?? []).map {
                EditablePlanDraft(
                    existingPlanId: $0.id,
                    name: $0.name,
                    priceMinorText: String($0.price_minor),
                    rewardSummary: $0.reward_summary,
                    description: $0.description ?? "",
                    currency: $0.currency
                )
            }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(project.title)
                        .font(.headline)

                    Group {
                        Text("Subtitle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("", text: $subtitleText)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .subtitle)
                    }

                    Group {
                        Text("Description")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        TextField("", text: $descriptionText, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .focused($focusedField, equals: .description)
                    }

                    Group {
                        Text("Project Images")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        PhotosPicker(selection: $coverPickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
                            Label(coverSelections.isEmpty ? "Select Project Images" : "Change Project Images", systemImage: "photo")
                        }
                        .buttonStyle(.bordered)
                        if !coverSelections.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(coverSelections.enumerated()), id: \.offset) { _, selection in
                                        if let uiImage = UIImage(data: selection.data) {
                                            Image(uiImage: uiImage)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 92, height: 92)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Group {
                        Text("URLs")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("", text: $urlDraft)
                                .textFieldStyle(.roundedBorder)
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .focused($focusedField, equals: .urlDraft)
                            Button("Add") { addURL() }
                                .buttonStyle(.bordered)
                                .disabled(urls.count >= 10)
                        }
                        ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                            HStack {
                                Text(url)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    urls.remove(at: index)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    Text("Plans")
                        .font(.subheadline.weight(.semibold))
                    ForEach(Array(planDrafts.indices), id: \.self) { index in
                        planEditCard(index: index)
                    }
                    Button("Add new plan") {
                        planDrafts.append(
                            EditablePlanDraft(
                                existingPlanId: nil,
                                name: "",
                                priceMinorText: "",
                                rewardSummary: "",
                                description: "",
                                currency: project.currency
                            )
                        )
                    }
                    .buttonStyle(.bordered)

                    if !errorText.isEmpty {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    Button(saving ? "Saving..." : "Save Changes") {
                        Task { await saveChanges() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saving)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded {
                    focusedField = nil
                }
            )
            .navigationTitle("Edit Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onChange(of: coverPickerItems) { _, newValue in
                Task { await loadProjectCovers(from: newValue) }
            }
        }
    }

    @ViewBuilder
    private func planEditCard(index: Int) -> some View {
        let draft = planDrafts[index]
        VStack(alignment: .leading, spacing: 8) {
            if draft.isExisting {
                Text("\(draft.name) · \(draft.priceMinorText) \(draft.currency)")
                    .font(.subheadline.weight(.semibold))
                Text(draft.rewardSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("New Plan")
                    .font(.subheadline.weight(.semibold))
                TextField("Plan name", text: $planDrafts[index].name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .planName(draft.id))
                TextField("Price (JPY)", text: $planDrafts[index].priceMinorText)
                    .textFieldStyle(.roundedBorder)
                    .keyboardType(.numberPad)
                    .focused($focusedField, equals: .planPrice(draft.id))
                TextField("Reward summary", text: $planDrafts[index].rewardSummary)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .planReward(draft.id))
            }

            TextField("Description", text: $planDrafts[index].description, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .planDescription(draft.id))

            PhotosPicker(selection: planPickerBinding(for: draft.id), matching: .images, photoLibrary: .shared()) {
                Label(selectedPlanImages[draft.id] == nil ? "Select Plan Image" : "Change Plan Image", systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)
            if let selected = selectedPlanImages[draft.id], let uiImage = UIImage(data: selected.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 110)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if let existingPlanId = draft.existingPlanId,
                      let existing = project.plans?.first(where: { $0.id == existingPlanId }),
                      let raw = existing.image_url,
                      let url = URL(string: raw) {
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
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if !draft.isExisting {
                Button("Remove new plan", role: .destructive) {
                    let planId = planDrafts[index].id
                    planDrafts.remove(at: index)
                    planPickerItems[planId] = nil
                    selectedPlanImages[planId] = nil
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func addURL() {
        let trimmed = urlDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard urls.count < 10 else {
            errorText = "You can add up to 10 URLs"
            return
        }
        guard let normalized = normalizeURLString(trimmed) else {
            errorText = "URL format is invalid"
            return
        }
        if !urls.contains(normalized) {
            urls.append(normalized)
        }
        urlDraft = ""
        errorText = ""
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

    private func planPickerBinding(for localPlanId: UUID) -> Binding<PhotosPickerItem?> {
        Binding(
            get: { planPickerItems[localPlanId] },
            set: { newValue in
                planPickerItems[localPlanId] = newValue
                guard let newValue else {
                    selectedPlanImages[localPlanId] = nil
                    return
                }
                Task { await loadPlanImage(from: newValue, localPlanId: localPlanId) }
            }
        )
    }

    private func loadProjectCovers(from pickerItems: [PhotosPickerItem]) async {
        if pickerItems.isEmpty {
            await MainActor.run { coverSelections = [] }
            return
        }
        do {
            var nextSelections: [SelectedProjectImage] = []
            for pickerItem in pickerItems.prefix(5) {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else { continue }
                let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "project-cover.jpg"
                let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
                nextSelections.append(SelectedProjectImage(data: data, fileName: fileName, contentType: contentType))
            }
            await MainActor.run { coverSelections = nextSelections }
        } catch {
            await MainActor.run { coverSelections = [] }
        }
    }

    private func loadPlanImage(from pickerItem: PhotosPickerItem, localPlanId: UUID) async {
        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else { return }
            let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "plan-image.jpg"
            let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
            await MainActor.run {
                selectedPlanImages[localPlanId] = SelectedProjectImage(data: data, fileName: fileName, contentType: contentType)
            }
        } catch {
            await MainActor.run {
                selectedPlanImages[localPlanId] = nil
            }
        }
    }

    private func saveChanges() async {
        if ["stopped", "failed", "succeeded"].contains(project.status) {
            errorText = "This project cannot be edited."
            return
        }

        saving = true
        errorText = ""
        defer { saving = false }

        do {
            let normalizedUrls = try urls.map { raw -> String in
                guard let normalized = normalizeURLString(raw) else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL: \(raw)"])
                }
                return normalized
            }

            var coverUrls: [String] = []
            for cover in coverSelections.prefix(5) {
                let uploaded = try await client.uploadProjectImage(data: cover.data, fileName: cover.fileName, contentType: cover.contentType)
                coverUrls.append(uploaded)
            }

            var uploadedPlanImageMap: [UUID: String] = [:]
            for draft in planDrafts {
                guard let selected = selectedPlanImages[draft.id] else { continue }
                let uploaded = try await client.uploadProjectImage(
                    data: selected.data,
                    fileName: selected.fileName,
                    contentType: selected.contentType
                )
                uploadedPlanImageMap[draft.id] = uploaded
            }

            let existingMinPrice = planDrafts
                .filter { $0.isExisting }
                .compactMap { Int($0.priceMinorText) }
                .min()

            var planPayloads: [UpdateProjectRequest.Plan] = []
            for draft in planDrafts {
                let trimmedDescription = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
                if let existingPlanId = draft.existingPlanId {
                    planPayloads.append(
                        .init(
                            id: existingPlanId,
                            name: nil,
                            price_minor: nil,
                            reward_summary: nil,
                            description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                            image_url: uploadedPlanImageMap[draft.id],
                            currency: nil
                        )
                    )
                    continue
                }

                let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let reward = draft.rewardSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !reward.isEmpty else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "New plan name and reward are required"])
                }
                guard let price = Int(draft.priceMinorText), price > 0 else {
                    throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "New plan price must be positive"])
                }
                if let existingMinPrice, price < existingMinPrice {
                    throw NSError(
                        domain: "LifeCastProject",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "New plans cannot be cheaper than existing plans"]
                    )
                }
                planPayloads.append(
                    .init(
                        id: nil,
                        name: name,
                        price_minor: price,
                        reward_summary: reward,
                        description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                        image_url: uploadedPlanImageMap[draft.id],
                        currency: draft.currency
                    )
                )
            }

            _ = try await client.updateProject(
                projectId: project.id,
                subtitle: subtitleText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : subtitleText.trimmingCharacters(in: .whitespacesAndNewlines),
                description: descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? nil
                    : descriptionText.trimmingCharacters(in: .whitespacesAndNewlines),
                imageURL: coverUrls.first,
                imageURLs: coverUrls.isEmpty ? nil : coverUrls,
                urls: normalizedUrls,
                plans: planPayloads.isEmpty ? nil : planPayloads
            )
            await MainActor.run {
                onSaved()
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorText = (error as NSError).localizedDescription
            }
        }
    }

    private struct EditablePlanDraft: Identifiable {
        let id: UUID
        let existingPlanId: UUID?
        var name: String
        var priceMinorText: String
        var rewardSummary: String
        var description: String
        var currency: String

        init(existingPlanId: UUID?, name: String, priceMinorText: String, rewardSummary: String, description: String, currency: String) {
            self.id = existingPlanId ?? UUID()
            self.existingPlanId = existingPlanId
            self.name = name
            self.priceMinorText = priceMinorText
            self.rewardSummary = rewardSummary
            self.description = description
            self.currency = currency
        }

        var isExisting: Bool { existingPlanId != nil }
    }

    private enum EditField: Hashable {
        case subtitle
        case description
        case urlDraft
        case planName(UUID)
        case planPrice(UUID)
        case planReward(UUID)
        case planDescription(UUID)
    }
}
