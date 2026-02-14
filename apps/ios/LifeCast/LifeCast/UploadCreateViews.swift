import PhotosUI
import UniformTypeIdentifiers
import SwiftUI
struct UploadCreateView: View {
    let client: LifeCastAPIClient
    let isAuthenticated: Bool
    let onUploadReady: () -> Void
    let onOpenProjectTab: () -> Void
    let onOpenAuth: () -> Void

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

                if !isAuthenticated {
                    loggedOutSection
                } else if let myProject {
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
        guard isAuthenticated else {
            await MainActor.run {
                myProject = nil
                projectLoading = false
                projectErrorText = ""
            }
            return
        }
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
