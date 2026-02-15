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
                        VStack(spacing: 16) {
                            ProfileOverviewSection(
                                avatarURL: myProfile?.avatar_url,
                                displayName: currentDisplayName,
                                bioText: (myProfile?.bio?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? (myProfile?.bio ?? "") : "Tap to add bio",
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
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 146, height: 40)
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.gray.opacity(0.35), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .buttonStyle(.plain)
                            }
                            .padding(.top, 6)

                            ProfileTabIconStrip(selectedIndex: $selectedIndex)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
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

}

struct DevUserSwitcherSheet: View {
    let client: LifeCastAPIClient
    let onSwitched: () -> Void

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
            let rawRatio = Double(funded) / Double(goal)
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
