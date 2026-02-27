import PhotosUI
import UniformTypeIdentifiers
import AVKit
import SwiftUI
struct UploadCreateView: View {
    let client: LifeCastAPIClient
    let isAuthenticated: Bool
    let autoOpenPickerNonce: Int
    let onUploadReady: () -> Void
    let onOpenAuth: () -> Void
    let onAutoOpenPickerCancelled: () -> Void
    let onFullscreenPreviewChanged: (Bool) -> Void

    @State private var isVideoPickerPresented = false
    @State private var selectedPickerItem: PhotosPickerItem?
    @State private var selectedUploadVideo: SelectedUploadVideo?
    @State private var awaitingAutoOpenedPickerResult = false
    @State private var composerStep: CreateComposerStep = .pick
    @State private var previewURL: URL?
    @State private var previewPlayer: AVPlayer?
    @State private var previewPlaybackObserver: NSObjectProtocol?
    @State private var myProject: MyProjectResult?
    @State private var state: UploadFlowState = .idle
    @State private var uploadProgress: Double = 0
    @State private var uploadSessionId: UUID?
    @State private var videoId: String?
    @State private var statusText = "Not started"
    @State private var errorText = ""
    @State private var descriptionText = ""
    @State private var tagsText = ""
    @State private var linkText = ""
    @FocusState private var focusedField: CreateInputField?

    var body: some View {
        NavigationStack {
            Group {
                if !isAuthenticated {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            loggedOutSection
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .padding(.bottom, 36)
                    }
                    .navigationTitle("Create")
                } else if composerStep == .preview, selectedUploadVideo != nil {
                    previewComposerSection
                        .toolbar(.hidden, for: .navigationBar)
                        .ignoresSafeArea(edges: .top)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if selectedUploadVideo == nil {
                                chooseVideoSection
                            } else {
                                uploadDetailsSection
                            }
                            uploadStatusSection
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .padding(.bottom, 36)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        focusedField = nil
                    }
                    .navigationTitle("Create")
                }
            }
            .task {
                await loadActiveProject()
            }
            .onChange(of: selectedPickerItem) { _, newValue in
                Task {
                    await loadSelectedVideo(from: newValue)
                }
            }
            .onChange(of: autoOpenPickerNonce) { _, _ in
                presentPickerIfEligible(triggeredByAutoOpen: true)
            }
            .onChange(of: isVideoPickerPresented) { wasPresented, isPresented in
                guard wasPresented, !isPresented else { return }
                guard awaitingAutoOpenedPickerResult else { return }
                awaitingAutoOpenedPickerResult = false
                if selectedPickerItem == nil && selectedUploadVideo == nil {
                    onAutoOpenPickerCancelled()
                }
            }
            .onAppear {
                onFullscreenPreviewChanged(isFullscreenPreviewActive)
            }
            .photosPicker(
                isPresented: $isVideoPickerPresented,
                selection: $selectedPickerItem,
                matching: .videos,
                photoLibrary: .shared()
            )
            .onDisappear {
                onFullscreenPreviewChanged(false)
                if let observer = previewPlaybackObserver {
                    NotificationCenter.default.removeObserver(observer)
                    previewPlaybackObserver = nil
                }
                previewPlayer?.pause()
                previewPlayer = nil
            }
        }
    }

    private var loggedOutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sign in required")
                .font(.subheadline.weight(.semibold))
            Text("Create and upload are available after signing in.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Sign In / Sign Up") {
                onOpenAuth()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var chooseVideoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upload")
                .font(.subheadline.weight(.semibold))
            Text("Pick a video to open the preview composer.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Choose Video") {
                isVideoPickerPresented = true
            }
            .buttonStyle(.bordered)
        }
    }

    private var previewComposerSection: some View {
        GeometryReader { proxy in
            let topInset = proxy.safeAreaInsets.top
            let footerTotalHeight = appBottomBarHeight
            let fullscreenContentHeight = proxy.size.height + topInset
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        if let previewPlayer {
                            FullscreenVideoPlayer(player: previewPlayer)
                                .onAppear {
                                    previewPlayer.play()
                                }
                        } else {
                            Color.gray.opacity(0.3)
                        }

                        Button {
                            resetSelectedVideoAndReturnToPicker()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.3))
                                .clipShape(Circle())
                        }
                        .padding(.leading, 16)
                        .padding(.top, topInset + 70)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: max(0, fullscreenContentHeight - footerTotalHeight))
                    .clipped()

                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 1)
                        HStack {
                            Button {
                                Task {
                                    await startUploadFlow()
                                }
                            } label: {
                                Text(state == .uploading || state == .processing ? "投稿中..." : "投稿")
                                    .font(.headline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 40)
                                    .background(Color(red: 0.98, green: 0.19, blue: 0.40))
                                    .clipShape(Capsule())
                            }
                        .disabled(state == .uploading || state == .processing)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: appBottomBarHeight)
                    }
                    .frame(height: footerTotalHeight)
                    .background(Color.black.opacity(0.96).ignoresSafeArea(edges: .bottom))
                }
                .frame(height: fullscreenContentHeight, alignment: .top)
                .offset(y: -topInset)
            }
        }
    }

    private var uploadDetailsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Upload details")
                .font(.subheadline.weight(.semibold))
            if let selectedUploadVideo {
                Text("Selected: \(selectedUploadVideo.fileName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Button("Preview") {
                    composerStep = .preview
                    previewPlayer?.play()
                }
                .buttonStyle(.bordered)

                Button("Choose Another Video") {
                    resetSelectedVideoAndReturnToPicker()
                    presentPickerIfEligible(triggeredByAutoOpen: false)
                }
                .buttonStyle(.bordered)
            }

            Text("Description")
                .font(.caption.weight(.semibold))
            TextEditor(text: $descriptionText)
                .frame(minHeight: 88, maxHeight: 120)
                .padding(8)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($focusedField, equals: .description)

            TextField("Tags (comma separated)", text: $tagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($focusedField, equals: .tags)

            TextField("Link (optional)", text: $linkText)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(Color.gray.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .focused($focusedField, equals: .link)

            Button("Publish") {
                Task {
                    await startUploadFlow()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(state == .uploading || state == .processing)
        }
    }

    private var uploadStatusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if state != .idle || !errorText.isEmpty {
                statusPill

                ProgressView(value: uploadProgress, total: 1)
                    .tint(state == .failed ? .red : .blue)

                Text(statusText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if state == .failed {
                Button("Retry Last Upload") {
                    Task {
                        await retryOrResumeFlow()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(uploadSessionId == nil)
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
                    statusText = "Upload complete. Opening Me > Posts..."
                    resetSelectedVideoAndReturnToPicker()
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
        composerStep = .pick
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
                previewURL = writePreviewFile(data: data, fileName: fileName)
                configurePreviewPlayer(with: previewURL)
                composerStep = .preview
                state = .idle
                statusText = "Ready to publish"
                errorText = ""
                onFullscreenPreviewChanged(true)
            }
        } catch {
            await MainActor.run {
                selectedUploadVideo = nil
                previewURL = nil
                composerStep = .pick
                state = .failed
                statusText = "Video selection failed"
                errorText = error.localizedDescription
                onFullscreenPreviewChanged(false)
            }
        }
    }

    private func presentPickerIfEligible(triggeredByAutoOpen: Bool) {
        guard isAuthenticated else { return }
        guard !isVideoPickerPresented else { return }
        guard selectedUploadVideo == nil else { return }
        guard state != .uploading && state != .processing else { return }
        awaitingAutoOpenedPickerResult = triggeredByAutoOpen
        isVideoPickerPresented = true
    }

    private func resetSelectedVideoAndReturnToPicker() {
        selectedPickerItem = nil
        selectedUploadVideo = nil
        previewURL = nil
        composerStep = .pick
        if let observer = previewPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            previewPlaybackObserver = nil
        }
        previewPlayer?.pause()
        previewPlayer = nil
        onFullscreenPreviewChanged(false)
    }

    private func configurePreviewPlayer(with url: URL?) {
        if let observer = previewPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            previewPlaybackObserver = nil
        }
        previewPlayer?.pause()
        guard let url else {
            previewPlayer = nil
            return
        }
        let player = AVPlayer(url: url)
        player.actionAtItemEnd = .none
        previewPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            player.seek(to: .zero)
            player.play()
        }
        previewPlayer = player
        player.play()
    }

    private func uniquePseudoSha256() -> String {
        let base = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return base + base
    }

    private func loadActiveProject() async {
        guard isAuthenticated else {
            await MainActor.run {
                myProject = nil
            }
            return
        }
        do {
            let project = try await client.getMyProject()
            await MainActor.run {
                myProject = project
            }
        } catch {
            await MainActor.run {
                myProject = nil
            }
        }
    }

    private func writePreviewFile(data: Data, fileName: String) -> URL? {
        let ext = (fileName as NSString).pathExtension.isEmpty ? "mov" : (fileName as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lifecast-preview-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
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

    private var isFullscreenPreviewActive: Bool {
        isAuthenticated && composerStep == .preview && selectedUploadVideo != nil
    }
}

private enum CreateInputField: Hashable {
    case description
    case tags
    case link
}

private enum CreateComposerStep {
    case pick
    case preview
    case details
}

private struct SelectedUploadVideo {
    let data: Data
    let fileName: String
    let contentType: String
}

private struct FullscreenVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspectFill
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
        controller.videoGravity = .resizeAspectFill
    }
}

struct ProjectPlanDraft: Identifiable {
    let id = UUID()
    var name: String
    var priceMinorText: String
    var rewardSummary: String
    var description: String = ""
}

struct SelectedProjectImage {
    let data: Data
    let fileName: String
    let contentType: String
}
