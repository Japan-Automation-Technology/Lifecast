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
    let selectedIndexOverride: Int
    let selectedIndexOverrideNonce: Int
    let onProjectEditUnsavedChanged: (Bool) -> Void
    let projectEditDiscardRequest: Int

    @State private var selectedIndex = 0
    @State private var showNetwork = false
    @State private var selectedNetworkTab: CreatorNetworkTab = .following
    @State private var showUserSwitcher = false
    @State private var showEditProfile = false
    @State private var supportedProjects: [SupportedProjectRow] = []
    @State private var supportedProjectsLoading = false
    @State private var supportedProjectsError = ""
    @State private var hasUnsavedProjectEdits = false
    @State private var localProjectEditDiscardNonce = 0
    @State private var pendingMeAction: PendingMeAction?
    @State private var showDiscardProjectEditDialog = false
    @State private var selectedCreatorRoute: CreatorRoute? = nil
    
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
                                            onProjectChanged: onProjectChanged,
                                            discardSignal: localProjectEditDiscardNonce,
                                            onUnsavedChangesChanged: { hasUnsaved in
                                                hasUnsavedProjectEdits = hasUnsaved
                                                onProjectEditUnsavedChanged(hasUnsaved)
                                            }
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
                                            },
                                            onTapProject: { row in
                                                selectedCreatorRoute = CreatorRoute(id: row.creator_user_id)
                                            }
                                        )
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } header: {
                                ProfileTabIconStrip(selectedIndex: profileSectionBinding, style: .fullWidthUnderline)
                                    .background(Color.white)
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
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .font(.system(size: 46))
                                .foregroundStyle(.secondary)
                            Text("Sign in to use your profile")
                                .font(.headline)
                            Text("Follow creators, support projects, and manage your own posts after signing in.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                            MeInlineAuthView(client: client) {
                                onRefreshProfile()
                                onRefreshVideos()
                                onProjectChanged()
                            }
                            .padding(.top, 4)
                        }
                        .frame(maxWidth: 480)
                        .padding(.horizontal, 16)
                        .padding(.top, 36)
                        .padding(.bottom, 28)
                    }
                }
            }
            .task {
                guard isAuthenticated else { return }
                onRefreshProfile()
                onRefreshVideos()
                await loadMySupportedProjects()
            }
            .onChange(of: isAuthenticated) { _, newValue in
                if !newValue {
                    hasUnsavedProjectEdits = false
                    onProjectEditUnsavedChanged(false)
                }
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
            .navigationDestination(item: $selectedCreatorRoute) { route in
                CreatorPublicPageView(
                    client: client,
                    creatorId: route.id,
                    onSupportTap: { _ in }
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
                if isAuthenticated {
                    mePinnedHeader
                }
            }
        }
        .onAppear {
            selectedIndex = selectedIndexOverride
        }
        .onChange(of: selectedIndexOverrideNonce) { _, _ in
            requestMeAction(.switchSection(selectedIndexOverride))
        }
        .confirmationDialog("Discard changes?", isPresented: $showDiscardProjectEditDialog, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                discardProjectEditsAndContinue()
            }
            Button("Cancel", role: .cancel) {
                pendingMeAction = nil
            }
        } message: {
            Text("Your project edits are not saved.")
        }
        .onChange(of: projectEditDiscardRequest) { _, _ in
            localProjectEditDiscardNonce += 1
            hasUnsavedProjectEdits = false
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
                    requestMeAction(.openUserSwitcher)
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

    private var profileSectionBinding: Binding<Int> {
        Binding(
            get: { selectedIndex },
            set: { newValue in
                requestMeAction(.switchSection(newValue))
            }
        )
    }

    private func requestMeAction(_ action: PendingMeAction) {
        if hasUnsavedProjectEdits {
            pendingMeAction = action
            showDiscardProjectEditDialog = true
            return
        }
        applyMeAction(action)
    }

    private func discardProjectEditsAndContinue() {
        localProjectEditDiscardNonce += 1
        hasUnsavedProjectEdits = false
        onProjectEditUnsavedChanged(false)
        guard let pendingMeAction else { return }
        self.pendingMeAction = nil
        applyMeAction(pendingMeAction)
    }

    private func applyMeAction(_ action: PendingMeAction) {
        switch action {
        case .openUserSwitcher:
            showUserSwitcher = true
        case .switchSection(let index):
            guard selectedIndex != index else { return }
            selectedIndex = index
            if index == 1 {
                onRefreshVideos()
            } else if index == 2 {
                Task { await loadMySupportedProjects() }
            }
        }
    }

    private enum PendingMeAction {
        case switchSection(Int)
        case openUserSwitcher
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

private struct MeInlineAuthView: View {
    let client: LifeCastAPIClient
    let onAuthenticated: () -> Void

    @Environment(\.openURL) private var openURL

    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var displayName = ""
    @State private var isSignUp = false
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorText = ""
    
    private var isPrimaryDisabled: Bool {
        isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || password.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            titleSection
            modeSwitchSection
            fieldsSection
            primaryButtonSection
            googleButtonSection
            errorSection
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(.secondarySystemBackground), Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isLoading {
                ProgressView()
                    .padding(20)
                    .background(Color(.systemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .lifecastAuthSessionUpdated)) { _ in
            onAuthenticated()
        }
    }

    private var titleSection: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(isSignUp ? "Create your profile" : "Welcome back")
                    .font(.system(size: 20, weight: .bold))
                Text(isSignUp ? "Set up your account to start posting." : "Sign in to follow and support creators.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.indigo)
        }
    }

    private var modeSwitchSection: some View {
        HStack(spacing: 8) {
            Button("Sign in") {
                isSignUp = false
                errorText = ""
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSignUp ? Color.clear : Color.black)
            .foregroundStyle(isSignUp ? Color.secondary : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(isLoading)

            Button("Sign up") {
                isSignUp = true
                errorText = ""
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSignUp ? Color.black : Color.clear)
            .foregroundStyle(isSignUp ? Color.white : Color.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(isLoading)
        }
        .padding(4)
        .background(Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var fieldsSection: some View {
        VStack(spacing: 10) {
            iconTextField(symbol: "envelope", placeholder: "Email", text: $email, keyboardType: .emailAddress)
            iconSecureField(symbol: "lock", placeholder: "Password", text: $password, isVisible: $isPasswordVisible)

            if isSignUp {
                HStack(spacing: 10) {
                    Text("Password must be 10 to 72 characters and include at least one uppercase letter, one lowercase letter, one number, and one symbol. Spaces are not allowed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                    Button {
                        password = generateRandomPassword()
                        isPasswordVisible = true
                        errorText = ""
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.black.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .buttonStyle(.plain)
                }
                iconTextField(symbol: "at", placeholder: "Username (optional)", text: $username, capitalization: .never)
                iconTextField(symbol: "person", placeholder: "Display name (optional)", text: $displayName)
                Text("Username and Display name can be changed later from Edit Profile.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var primaryButtonSection: some View {
        Button {
            Task { await submitEmailAuth() }
        } label: {
            Text(isSignUp ? "Create account with Email" : "Sign in with Email")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(
                        colors: [Color.black, Color.indigo.opacity(0.85)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isPrimaryDisabled)
        .opacity(isPrimaryDisabled ? 0.6 : 1.0)
    }

    private var googleButtonSection: some View {
        Button {
            Task { await continueOAuth(provider: "google") }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "globe")
                Text("Continue with Google")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.9))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.14), lineWidth: 1))
            .foregroundStyle(.primary)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    @ViewBuilder
    private var errorSection: some View {
        if !errorText.isEmpty {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
                .padding(.top, 2)
        }
    }

    private func iconTextField(
        symbol: String,
        placeholder: String,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            TextField(placeholder, text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(capitalization)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func iconSecureField(symbol: String, placeholder: String, text: Binding<String>, isVisible: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
            if isVisible.wrappedValue {
                TextField(placeholder, text: text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
            } else {
                SecureField(placeholder, text: text)
            }
            Button(isVisible.wrappedValue ? "Hide" : "Show") {
                isVisible.wrappedValue.toggle()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.9))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func submitEmailAuth() async {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationError = validateAuthInput(
            email: normalizedEmail,
            password: normalizedPassword,
            username: normalizedUsername,
            displayName: normalizedDisplayName,
            isSignUp: isSignUp
        ) {
            await MainActor.run {
                errorText = validationError
            }
            return
        }

        await MainActor.run {
            isLoading = true
            errorText = ""
        }
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            if isSignUp {
                _ = try await client.signUpWithEmail(
                    email: normalizedEmail,
                    password: normalizedPassword,
                    username: normalizedUsername.isEmpty ? nil : normalizedUsername,
                    displayName: normalizedDisplayName.isEmpty ? nil : normalizedDisplayName
                )
            } else {
                _ = try await client.signInWithEmail(email: normalizedEmail, password: normalizedPassword)
            }
            await MainActor.run {
                onAuthenticated()
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
    }

    private func validateAuthInput(email: String, password: String, username: String, displayName: String, isSignUp: Bool) -> String? {
        let emailPattern = #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#
        if email.range(of: emailPattern, options: .regularExpression) == nil {
            return "Email format is invalid. Example: name@example.com"
        }
        if password.isEmpty {
            return "Password is required."
        }
        guard isSignUp else { return nil }

        if password.contains(where: \.isWhitespace) {
            return "Password must not include spaces."
        }
        if password.count < 10 {
            return "Password must be at least 10 characters."
        }
        if password.count > 72 {
            return "Password must be 72 characters or less."
        }
        let uppercaseSet = CharacterSet.uppercaseLetters
        let lowercaseSet = CharacterSet.lowercaseLetters
        let symbolSet = CharacterSet.punctuationCharacters.union(.symbols)
        let hasUppercase = password.rangeOfCharacter(from: uppercaseSet) != nil
        let hasLowercase = password.rangeOfCharacter(from: lowercaseSet) != nil
        let hasNumber = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSymbol = password.rangeOfCharacter(from: symbolSet) != nil
        if !hasUppercase || !hasLowercase || !hasNumber || !hasSymbol {
            return "Password must include uppercase/lowercase letters, a number, and a symbol."
        }
        if !username.isEmpty {
            if username.count < 3 || username.count > 40 {
                return "Username must be 3-40 characters."
            }
            let allowedUsernameChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
            if username.rangeOfCharacter(from: allowedUsernameChars.inverted) != nil {
                return "Username can only include letters, numbers, and underscore (_)."
            }
        }
        if displayName.count > 30 {
            return "Display name must be 30 characters or less."
        }
        return nil
    }

    private func generateRandomPassword(length: Int = 16) -> String {
        let upper = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let lower = Array("abcdefghijklmnopqrstuvwxyz")
        let digits = Array("0123456789")
        let symbols = Array("!@#$%^&*()-_=+[]{}<>?/|")
        let all = upper + lower + digits + symbols

        var chars: [Character] = [
            upper.randomElement()!,
            lower.randomElement()!,
            digits.randomElement()!,
            symbols.randomElement()!
        ]
        while chars.count < max(length, 10) {
            chars.append(all.randomElement()!)
        }
        return String(chars.shuffled())
    }

    private func continueOAuth(provider: String) async {
        await MainActor.run {
            isLoading = true
            errorText = ""
        }
        defer {
            Task { @MainActor in
                isLoading = false
            }
        }

        do {
            let url = try await client.oauthURL(provider: provider)
            await MainActor.run {
                openURL(url)
            }
        } catch {
            await MainActor.run {
                errorText = error.localizedDescription
            }
        }
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
                            Text("Use the sign-in form on the Me page.")
                                .font(.footnote)
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
        await client.signOut()
        errorText = ""
        isSignedIn = false
        signedInUserEmail = ""
        onSwitched()
        dismiss()
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
    @State private var username: String
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
        _username = State(initialValue: profile?.username ?? "")
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
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
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

            let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBio = bio.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalizedUsername.count < 3 || normalizedUsername.count > 40 {
                throw NSError(domain: "LifeCastProfile", code: 400, userInfo: [NSLocalizedDescriptionKey: "Username must be 3-40 characters"])
            }
            let allowedUsernameChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
            if normalizedUsername.rangeOfCharacter(from: allowedUsernameChars.inverted) != nil {
                throw NSError(domain: "LifeCastProfile", code: 400, userInfo: [NSLocalizedDescriptionKey: "Username can only include letters, numbers, and underscore (_)."])
            }
            if normalizedDisplayName.count > 30 {
                throw NSError(domain: "LifeCastProfile", code: 400, userInfo: [NSLocalizedDescriptionKey: "Display name must be 30 characters or less"])
            }
            if normalizedBio.count > 160 {
                throw NSError(domain: "LifeCastProfile", code: 400, userInfo: [NSLocalizedDescriptionKey: "Bio must be 160 characters or less"])
            }

            _ = try await client.updateMyProfile(
                username: normalizedUsername,
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
    let discardSignal: Int
    let onUnsavedChangesChanged: (Bool) -> Void

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
    @State private var isEditingProjectInline = false
    @State private var projectEditHasChanges = false
    @State private var projectCreateInFlight = false
    @State private var projectCreateStatusText = ""
    @State private var hasLoadedProjectsOnce = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 12) {
                if !hasLoadedProjectsOnce {
                    ProgressView("Loading project...")
                        .font(.caption)
                } else if let myProject {
                    if isEditingProjectInline && canEditProject(myProject) {
                        ProjectInlineEditView(
                            client: client,
                            project: myProject,
                            onCancel: {
                                isEditingProjectInline = false
                                projectEditHasChanges = false
                            },
                            onSaved: {
                                Task {
                                    await loadMyProjects()
                                    await MainActor.run {
                                        isEditingProjectInline = false
                                        projectEditHasChanges = false
                                        onProjectChanged()
                                    }
                                }
                            },
                            onDirtyChange: { hasChanges in
                                projectEditHasChanges = hasChanges
                            }
                        )
                    } else {
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
        .background(
            ProjectEditDismissKeyboardTapView {
                guard isEditingProjectInline else { return }
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        )
        .task {
            await loadMyProjects()
            publishUnsavedState()
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
        .onChange(of: isEditingProjectInline) { _, _ in
            publishUnsavedState()
        }
        .onChange(of: projectEditHasChanges) { _, _ in
            publishUnsavedState()
        }
        .onChange(of: discardSignal) { _, _ in
            if isEditingProjectInline {
                isEditingProjectInline = false
                projectEditHasChanges = false
            }
            publishUnsavedState()
        }
    }

    private func publishUnsavedState() {
        onUnsavedChangesChanged(isEditingProjectInline && projectEditHasChanges)
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
            onTapHeaderAction: canEditProject(project) ? { isEditingProjectInline = true } : nil
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

struct ProjectInlineEditView: View {
    let client: LifeCastAPIClient
    let project: MyProjectResult
    let onCancel: () -> Void
    let onSaved: () -> Void
    let onDirtyChange: (Bool) -> Void

    @State private var subtitleText: String
    @State private var descriptionText: String
    @State private var urlDraft = ""
    @State private var urls: [String]
    @State private var coverPickerItems: [PhotosPickerItem] = []
    @State private var projectImages: [EditableProjectImage]
    @State private var planDrafts: [EditablePlanDraft]
    @State private var selectedPlanImages: [UUID: SelectedProjectImage] = [:]
    @State private var planImagePickerTargetId: UUID?
    @State private var isPlanImagePickerPresented = false
    @State private var saving = false
    @State private var errorText = ""
    @FocusState private var focusedField: EditField?
    private let initialSnapshot: EditSnapshot

    init(
        client: LifeCastAPIClient,
        project: MyProjectResult,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () -> Void,
        onDirtyChange: @escaping (Bool) -> Void
    ) {
        self.client = client
        self.project = project
        self.onCancel = onCancel
        self.onSaved = onSaved
        self.onDirtyChange = onDirtyChange
        _subtitleText = State(initialValue: project.subtitle ?? "")
        _descriptionText = State(initialValue: project.description ?? "")
        _urls = State(initialValue: project.urls ?? [])
        var initialImages: [EditableProjectImage] = []
        if let imageUrls = project.image_urls, !imageUrls.isEmpty {
            for raw in imageUrls {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    initialImages.append(EditableProjectImage(existingURL: trimmed))
                }
            }
        } else if let raw = project.image_url?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            initialImages.append(EditableProjectImage(existingURL: raw))
        }
        _projectImages = State(initialValue: initialImages)
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
        self.initialSnapshot = EditSnapshot(
            subtitle: project.subtitle ?? "",
            description: project.description ?? "",
            urls: project.urls ?? [],
            projectImageURLs: initialImages.compactMap(\.existingURL),
            planDrafts: (project.plans ?? []).map {
                EditablePlanSnapshot(
                    id: $0.id,
                    isExisting: true,
                    name: $0.name,
                    priceMinorText: String($0.price_minor),
                    rewardSummary: $0.reward_summary,
                    description: $0.description ?? "",
                    currency: $0.currency
                )
            },
            selectedPlanImageIds: []
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerSection
            projectTitleSection
            subtitleSection
            projectImagesSection
            descriptionSection
            urlsSection
            plansSection
            saveSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(14)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
        .background(
            ProjectEditDismissKeyboardTapView {
                focusedField = nil
            }
        )
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedField = nil
            }
        )
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: coverPickerItems) { _, newValue in
            Task { await loadProjectCovers(from: newValue) }
        }
        .onAppear {
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: subtitleText) { _, _ in
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: descriptionText) { _, _ in
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: urls) { _, _ in
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: projectImages.map { image in
            "\(image.id.uuidString)|\(image.existingURL ?? "")|\(image.selectedImage == nil ? "0" : "1")"
        }) { _, _ in
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: planDrafts.map { draft in
            "\(draft.id.uuidString)|\(draft.isExisting)|\(draft.name)|\(draft.priceMinorText)|\(draft.rewardSummary)|\(draft.description)|\(draft.currency)"
        }) { _, _ in
            onDirtyChange(hasUnsavedChanges)
        }
        .onChange(of: selectedPlanImages.keys.map(\.uuidString).sorted()) { _, _ in
            onDirtyChange(hasUnsavedChanges)
        }
        .sheet(isPresented: $isPlanImagePickerPresented) {
            SingleImagePicker { selected in
                guard let selected, let targetId = planImagePickerTargetId else { return }
                selectedPlanImages[targetId] = selected
                planImagePickerTargetId = nil
                isPlanImagePickerPresented = false
                focusedField = nil
                onDirtyChange(hasUnsavedChanges)
            }
        }
    }

    private var headerSection: some View {
        HStack {
            Text("Edit Project")
                .font(.headline)
            Spacer()
            Button("Cancel") {
                onCancel()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
            .buttonStyle(.plain)
        }
    }

    private var projectTitleSection: some View {
        Text(project.title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private var subtitleSection: some View {
        Group {
            Text("Subtitle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $subtitleText)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .subtitle)
        }
    }

    @ViewBuilder
    private var projectImagesSection: some View {
        Text("Project Images")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        PhotosPicker(selection: $coverPickerItems, maxSelectionCount: 5, matching: .images, photoLibrary: .shared()) {
            Label("Add Project Images", systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .simultaneousGesture(
            TapGesture().onEnded {
                focusedField = nil
            }
        )
        if projectImages.isEmpty {
            Text("At least one image is required.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(projectImages) { image in
                        ZStack(alignment: .topTrailing) {
                            imageThumbnail(image)
                                .frame(width: 92, height: 92)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button {
                                removeProjectImage(image.id)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(projectImages.count <= 1 ? .gray : .white, .black.opacity(0.65))
                            }
                            .disabled(projectImages.count <= 1)
                            .offset(x: 6, y: -6)
                        }
                    }
                }
            }
        }
    }

    private var descriptionSection: some View {
        Group {
            Text("Description")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $descriptionText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .description)
        }
    }

    @ViewBuilder
    private var urlsSection: some View {
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

    @ViewBuilder
    private var plansSection: some View {
        Text("Plans")
            .font(.subheadline.weight(.semibold))
        ForEach(Array(planDrafts.indices), id: \.self) { index in
            planEditCard(index: index)
        }
        Button {
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
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Color.accentColor.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityLabel("Add new plan")
    }

    @ViewBuilder
    private var saveSection: some View {
        if !errorText.isEmpty {
            Text(errorText)
                .font(.caption)
                .foregroundStyle(.red)
        }
        HStack {
            Spacer()
            Button(saving ? "Saving..." : "Save Changes") {
                Task { await saveChanges() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .disabled(saving)
            .opacity(saving ? 0.75 : 1.0)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, 22)
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

            if let selected = selectedPlanImages[draft.id], let uiImage = UIImage(data: selected.data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 110)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
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
                .frame(maxWidth: .infinity)
                .frame(height: 110)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            Button {
                focusedField = nil
                planImagePickerTargetId = draft.id
                DispatchQueue.main.async {
                    isPlanImagePickerPresented = true
                }
            } label: {
                HStack(spacing: 6) {
                    Label(selectedPlanImages[draft.id] == nil ? "Select Plan Image" : "Change Plan Image", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.accentColor.opacity(0.12))
                        .clipShape(Capsule())
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("project-inline-plan-image-picker")

            if !draft.isExisting {
                Button("Remove new plan", role: .destructive) {
                    let planId = planDrafts[index].id
                    planDrafts.remove(at: index)
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

    private var hasUnsavedChanges: Bool {
        let currentSnapshot = EditSnapshot(
            subtitle: subtitleText,
            description: descriptionText,
            urls: urls,
            projectImageURLs: projectImages.compactMap(\.existingURL),
            planDrafts: planDrafts.map {
                EditablePlanSnapshot(
                    id: $0.id,
                    isExisting: $0.isExisting,
                    name: $0.name,
                    priceMinorText: $0.priceMinorText,
                    rewardSummary: $0.rewardSummary,
                    description: $0.description,
                    currency: $0.currency
                )
            },
            selectedPlanImageIds: selectedPlanImages.keys.map(\.uuidString)
        )
        return currentSnapshot != initialSnapshot
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

    private func loadProjectCovers(from pickerItems: [PhotosPickerItem]) async {
        if pickerItems.isEmpty {
            return
        }
        do {
            var additions: [EditableProjectImage] = []
            let room = max(0, 5 - projectImages.count)
            for pickerItem in pickerItems.prefix(room) {
                guard let data = try await pickerItem.loadTransferable(type: Data.self) else { continue }
                let fileName = pickerItem.itemIdentifier.map { "\($0).jpg" } ?? "project-cover.jpg"
                let contentType = pickerItem.supportedContentTypes.first?.preferredMIMEType ?? UTType.jpeg.preferredMIMEType ?? "image/jpeg"
                let selected = SelectedProjectImage(data: data, fileName: fileName, contentType: contentType)
                additions.append(EditableProjectImage(existingURL: nil, selectedImage: selected))
            }
            await MainActor.run {
                projectImages.append(contentsOf: additions)
                coverPickerItems = []
            }
        } catch {
            await MainActor.run {
                coverPickerItems = []
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

            guard !projectImages.isEmpty else {
                throw NSError(domain: "LifeCastProject", code: -1, userInfo: [NSLocalizedDescriptionKey: "At least one project image is required"])
            }

            var coverUrls: [String] = []
            for image in projectImages.prefix(5) {
                if let existingURL = image.existingURL {
                    coverUrls.append(existingURL)
                } else if let selected = image.selectedImage {
                    let uploaded = try await client.uploadProjectImage(
                        data: selected.data,
                        fileName: selected.fileName,
                        contentType: selected.contentType
                    )
                    coverUrls.append(uploaded)
                }
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
                onDirtyChange(false)
                onSaved()
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

    private struct EditablePlanSnapshot: Equatable {
        let id: UUID
        let isExisting: Bool
        let name: String
        let priceMinorText: String
        let rewardSummary: String
        let description: String
        let currency: String
    }

    private struct EditSnapshot: Equatable {
        let subtitle: String
        let description: String
        let urls: [String]
        let projectImageURLs: [String]
        let planDrafts: [EditablePlanSnapshot]
        let selectedPlanImageIds: [String]

        init(
            subtitle: String,
            description: String,
            urls: [String],
            projectImageURLs: [String],
            planDrafts: [EditablePlanSnapshot],
            selectedPlanImageIds: [String]
        ) {
            self.subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            self.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
            self.urls = urls.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            self.projectImageURLs = projectImageURLs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            self.planDrafts = planDrafts
            self.selectedPlanImageIds = selectedPlanImageIds.sorted()
        }
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

    @ViewBuilder
    private func imageThumbnail(_ image: EditableProjectImage) -> some View {
        if let selected = image.selectedImage, let uiImage = UIImage(data: selected.data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let raw = image.existingURL, let url = URL(string: raw) {
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
        } else {
            Rectangle().fill(Color.secondary.opacity(0.15))
        }
    }

    private func removeProjectImage(_ id: UUID) {
        guard projectImages.count > 1 else {
            errorText = "At least one image must remain"
            return
        }
        projectImages.removeAll { $0.id == id }
    }

    private struct EditableProjectImage: Identifiable {
        let id: UUID
        var existingURL: String?
        var selectedImage: SelectedProjectImage?

        init(existingURL: String?, selectedImage: SelectedProjectImage? = nil) {
            self.id = UUID()
            self.existingURL = existingURL
            self.selectedImage = selectedImage
        }
    }
}

private struct SingleImagePicker: UIViewControllerRepresentable {
    let onComplete: (SelectedProjectImage?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onComplete: (SelectedProjectImage?) -> Void

        init(onComplete: @escaping (SelectedProjectImage?) -> Void) {
            self.onComplete = onComplete
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard let first = results.first else {
                picker.dismiss(animated: true) {
                    self.onComplete(nil)
                }
                return
            }

            let provider = first.itemProvider
            let contentType = provider.registeredTypeIdentifiers.first.flatMap { UTType($0)?.preferredMIMEType } ?? "image/jpeg"
            let fileName = provider.suggestedName.map { "\($0).jpg" } ?? "plan-image.jpg"

            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async {
                    picker.dismiss(animated: true) {
                        guard let data else {
                            self.onComplete(nil)
                            return
                        }
                        self.onComplete(SelectedProjectImage(data: data, fileName: fileName, contentType: contentType))
                    }
                }
            }
        }
    }
}

private struct ProjectEditDismissKeyboardTapView: UIViewRepresentable {
    let onTap: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .clear
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        view.addGestureRecognizer(tap)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private let onTap: () -> Void

        init(onTap: @escaping () -> Void) {
            self.onTap = onTap
        }

        @objc func handleTap() {
            onTap()
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            if touch.view is UIControl {
                return false
            }
            return true
        }
    }
}
