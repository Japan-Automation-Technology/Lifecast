import Foundation
import CryptoKit

struct PrepareSupportRequest: Encodable {
    let plan_id: UUID
    let quantity: Int
}

struct PrepareSupportResult: Decodable {
    let support_id: UUID
    let support_status: String
    let checkout_url: String
}

struct ConfirmSupportRequest: Encodable {
    let provider: String
    let provider_session_id: String
    let return_status: String?
}

struct SupportStatusResult: Decodable {
    let support_id: UUID
    let support_status: String
    let amount_minor: Int
    let currency: String
    let project_id: UUID
    let plan_id: UUID
}

struct UploadCreateRequest: Encodable {
    let project_id: UUID
    let file_name: String
    let content_type: String
    let file_size_bytes: Int
}

struct UploadCompleteRequest: Encodable {
    let storage_object_key: String
    let content_hash_sha256: String
}

struct UploadSessionResult: Decodable {
    let upload_session_id: UUID
    let status: String
    let upload_url: String?
    let expires_at: String?
    let video_id: String?
    let storage_object_key: String?
}

struct UploadBinaryResult: Decodable {
    let upload_session_id: UUID
    let storage_object_key: String
    let bytes_stored: Int
    let content_hash_sha256: String
}

struct MyVideo: Decodable, Identifiable {
    let video_id: UUID
    let status: String
    let file_name: String
    let playback_url: String?
    let thumbnail_url: String?
    let created_at: String

    var id: UUID { video_id }
}

struct MyVideosResult: Decodable {
    let rows: [MyVideo]
}

struct ProjectPlanResult: Decodable {
    let id: UUID
    let name: String
    let price_minor: Int
    let reward_summary: String
    let description: String?
    let image_url: String?
    let currency: String
}

struct MyProjectResult: Decodable {
    let id: UUID
    let creator_user_id: UUID
    let title: String
    let subtitle: String?
    let image_url: String?
    let category: String?
    let location: String?
    let status: String
    let goal_amount_minor: Int
    let currency: String
    let duration_days: Int?
    let deadline_at: String
    let description: String?
    let urls: [String]?
    let funded_amount_minor: Int
    let supporter_count: Int
    let support_count_total: Int
    let created_at: String
    let minimum_plan: ProjectPlanResult?
    let plans: [ProjectPlanResult]?
}

struct MyProjectsResult: Decodable {
    let rows: [MyProjectResult]
}

struct DiscoverCreatorRow: Decodable, Identifiable {
    let creator_user_id: UUID
    let username: String
    let display_name: String?
    let project_title: String?

    var id: UUID { creator_user_id }
}

struct DiscoverCreatorsResult: Decodable {
    let rows: [DiscoverCreatorRow]
}

struct FeedProjectRow: Decodable, Identifiable {
    let project_id: UUID
    let creator_user_id: UUID
    let username: String
    let caption: String
    let min_plan_price_minor: Int
    let goal_amount_minor: Int
    let funded_amount_minor: Int
    let remaining_days: Int
    let likes: Int
    let comments: Int
    let is_supported_by_current_user: Bool

    var id: UUID { project_id }
}

struct FeedProjectsResult: Decodable {
    let rows: [FeedProjectRow]
}

enum CreatorNetworkTab: String, CaseIterable {
    case followers
    case following
    case support
}

struct CreatorNetworkRow: Decodable, Identifiable {
    let creator_user_id: UUID
    let username: String
    let display_name: String?
    let bio: String?
    let avatar_url: String?
    let project_title: String?
    let is_following: Bool
    let is_self: Bool?

    var id: UUID { creator_user_id }
}

struct CreatorNetworkResult: Decodable {
    let profile_stats: CreatorProfileStats
    let rows: [CreatorNetworkRow]
}

struct CreatorPublicProfile: Decodable {
    let creator_user_id: UUID
    let username: String
    let display_name: String?
    let bio: String?
    let avatar_url: String?
}

struct CreatorViewerRelationship: Decodable {
    let is_following: Bool
    let is_supported: Bool
}

struct CreatorProfileStats: Decodable {
    let following_count: Int
    let followers_count: Int
    let supported_project_count: Int
}

struct CreatorPublicVideo: Decodable, Identifiable {
    let video_id: UUID
    let status: String
    let file_name: String
    let playback_url: String?
    let thumbnail_url: String?
    let created_at: String

    var id: UUID { video_id }
}

struct CreatorPublicPageResult: Decodable {
    let profile: CreatorPublicProfile
    let viewer_relationship: CreatorViewerRelationship
    let profile_stats: CreatorProfileStats
    let project: MyProjectResult?
    let videos: [CreatorPublicVideo]
}

struct MyProfileResult: Decodable {
    let profile: CreatorPublicProfile
    let profile_stats: CreatorProfileStats
}

struct CreatorRelationshipResult: Decodable {
    let viewer_relationship: CreatorViewerRelationship
}

struct CreateProjectRequest: Encodable {
    struct Plan: Encodable {
        let name: String
        let price_minor: Int
        let reward_summary: String
        let description: String?
        let image_url: String?
        let currency: String
    }

    let title: String
    let subtitle: String?
    let image_url: String?
    let category: String?
    let location: String?
    let goal_amount_minor: Int
    let currency: String
    let project_duration_days: Int?
    let deadline_at: String?
    let description: String?
    let urls: [String]?
    let plans: [Plan]
}

struct UploadProjectImageRequest: Encodable {
    let file_name: String?
    let content_type: String
    let data_base64: String
}

struct UploadProjectImageResult: Decodable {
    let image_url: String
}

struct DevSampleVideo {
    let data: Data
    let fileName: String
    let contentType: String
}

struct APIEnvelope<T: Decodable>: Decodable {
    let request_id: String
    let server_time: String
    let result: T
}

final class LifeCastAPIClient {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func prepareSupport(projectId: UUID, planId: UUID, quantity: Int, idempotencyKey: String) async throws -> PrepareSupportResult {
        let body = PrepareSupportRequest(plan_id: planId, quantity: quantity)
        return try await send(
            path: "/v1/projects/\(projectId.uuidString)/supports/prepare",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func confirmSupport(supportId: UUID, providerSessionId: String, idempotencyKey: String) async throws -> SupportStatusResult {
        let body = ConfirmSupportRequest(provider: "stripe", provider_session_id: providerSessionId, return_status: "success")
        return try await send(
            path: "/v1/supports/\(supportId.uuidString)/confirm",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func getSupport(supportId: UUID) async throws -> SupportStatusResult {
        try await send(path: "/v1/supports/\(supportId.uuidString)", method: "GET", body: Optional<String>.none, idempotencyKey: nil)
    }

    func createUploadSession(projectId: UUID, fileName: String, contentType: String, fileSizeBytes: Int, idempotencyKey: String) async throws -> UploadSessionResult {
        let body = UploadCreateRequest(project_id: projectId, file_name: fileName, content_type: contentType, file_size_bytes: fileSizeBytes)
        return try await send(path: "/v1/videos/uploads", method: "POST", body: body, idempotencyKey: idempotencyKey)
    }

    func completeUploadSession(uploadSessionId: UUID, storageObjectKey: String, contentHashSha256: String, idempotencyKey: String) async throws -> UploadSessionResult {
        let body = UploadCompleteRequest(storage_object_key: storageObjectKey, content_hash_sha256: contentHashSha256)
        return try await send(
            path: "/v1/videos/uploads/\(uploadSessionId.uuidString)/complete",
            method: "POST",
            body: body,
            idempotencyKey: idempotencyKey
        )
    }

    func getUploadSession(uploadSessionId: UUID) async throws -> UploadSessionResult {
        try await send(
            path: "/v1/videos/uploads/\(uploadSessionId.uuidString)",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
    }

    func uploadBinary(uploadURL: URL, data: Data, contentType: String) async throws -> UploadBinaryResult {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (payload, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: payload, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPIClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: body])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<UploadBinaryResult>.self, from: payload)
        return envelope.result
    }

    func uploadBinaryDirect(uploadURL: URL, data: Data, contentType: String) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        let boundary = "LifeCastBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload.mov\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LifeCastAPIClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "direct upload failed"])
        }
    }

    func listMyVideos() async throws -> [MyVideo] {
        let result: MyVideosResult = try await send(
            path: "/v1/videos/mine",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
        return result.rows
    }

    func getMyProject() async throws -> MyProjectResult {
        try await send(path: "/v1/me/project", method: "GET", body: Optional<String>.none, idempotencyKey: nil)
    }

    func listMyProjects() async throws -> [MyProjectResult] {
        let result: MyProjectsResult = try await send(
            path: "/v1/me/projects",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
        return result.rows
    }

    func discoverCreators(query: String) async throws -> [DiscoverCreatorRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/discover/creators"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(
                domain: "LifeCastAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "invalid discover URL"]
            )
        }
        components.queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "limit", value: "20")
        ]
        guard let url = components.url else {
            throw NSError(
                domain: "LifeCastAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "invalid discover URL"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<DiscoverCreatorsResult>.self, from: data)
        return envelope.result.rows
    }

    func listFeedProjects(limit: Int = 20) async throws -> [FeedProjectRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/feed/projects"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(
                domain: "LifeCastAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "invalid feed URL"]
            )
        }
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 50)))")
        ]
        guard let url = components.url else {
            throw NSError(
                domain: "LifeCastAPI",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "invalid feed URL"]
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<FeedProjectsResult>.self, from: data)
        return envelope.result.rows
    }

    func getCreatorPage(creatorUserId: UUID) async throws -> CreatorPublicPageResult {
        try await send(
            path: "/v1/creators/\(creatorUserId.uuidString)",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
    }

    func getCreatorNetwork(creatorUserId: UUID, tab: CreatorNetworkTab, limit: Int = 100) async throws -> CreatorNetworkResult {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/creators/\(creatorUserId.uuidString)/network"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid network URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "tab", value: tab.rawValue),
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 100)))")
        ]
        guard let url = components.url else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid network URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<CreatorNetworkResult>.self, from: data)
        return envelope.result
    }

    func getMyNetwork(tab: CreatorNetworkTab, limit: Int = 100) async throws -> CreatorNetworkResult {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/me/network"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid me network URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "tab", value: tab.rawValue),
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 100)))")
        ]
        guard let url = components.url else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid me network URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<CreatorNetworkResult>.self, from: data)
        return envelope.result
    }

    func getMyProfile() async throws -> MyProfileResult {
        try await send(
            path: "/v1/me/profile",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
    }

    func followCreator(creatorUserId: UUID) async throws -> CreatorViewerRelationship {
        let result: CreatorRelationshipResult = try await send(
            path: "/v1/creators/\(creatorUserId.uuidString)/follow",
            method: "POST",
            body: Optional<String>.none,
            idempotencyKey: "ios-follow-\(UUID().uuidString)"
        )
        return result.viewer_relationship
    }

    func unfollowCreator(creatorUserId: UUID) async throws -> CreatorViewerRelationship {
        let result: CreatorRelationshipResult = try await send(
            path: "/v1/creators/\(creatorUserId.uuidString)/follow",
            method: "DELETE",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
        return result.viewer_relationship
    }

    func createProject(
        title: String,
        subtitle: String?,
        imageURL: String?,
        category: String?,
        location: String?,
        goalAmountMinor: Int,
        currency: String,
        projectDurationDays: Int?,
        deadlineAtISO8601: String?,
        description: String?,
        urls: [String],
        plans: [CreateProjectRequest.Plan]
    ) async throws -> MyProjectResult {
        let body = CreateProjectRequest(
            title: title,
            subtitle: subtitle,
            image_url: imageURL,
            category: category,
            location: location,
            goal_amount_minor: goalAmountMinor,
            currency: currency,
            project_duration_days: projectDurationDays,
            deadline_at: deadlineAtISO8601,
            description: description,
            urls: urls,
            plans: plans
        )
        return try await send(path: "/v1/projects", method: "POST", body: body, idempotencyKey: "ios-project-create-\(UUID().uuidString)")
    }

    func uploadProjectImage(data: Data, fileName: String?, contentType: String) async throws -> String {
        let body = UploadProjectImageRequest(
            file_name: fileName,
            content_type: contentType,
            data_base64: data.base64EncodedString()
        )
        let result: UploadProjectImageResult = try await send(
            path: "/v1/projects/images",
            method: "POST",
            body: body,
            idempotencyKey: "ios-project-image-\(UUID().uuidString)"
        )
        return result.image_url
    }

    func deleteProject(projectId: UUID) async throws {
        struct DeleteProjectResult: Decodable {
            let project_id: String
            let status: String
        }
        _ = try await send(path: "/v1/projects/\(projectId.uuidString)", method: "DELETE", body: Optional<String>.none, idempotencyKey: nil) as DeleteProjectResult
    }

    func endProject(projectId: UUID, reason: String?) async throws {
        struct EndProjectRequest: Encodable {
            let reason: String?
        }
        struct EndProjectResult: Decodable {
            let project_id: String
            let status: String
            let refund_policy: String
        }
        _ = try await send(
            path: "/v1/projects/\(projectId.uuidString)/end",
            method: "POST",
            body: EndProjectRequest(reason: reason),
            idempotencyKey: "ios-project-end-\(UUID().uuidString)"
        ) as EndProjectResult
    }

    func deleteVideo(videoId: UUID) async throws {
        struct DeleteResult: Decodable {
            let video_id: String
            let status: String
        }

        _ = try await send(
            path: "/v1/videos/\(videoId.uuidString)",
            method: "DELETE",
            body: Optional<String>.none,
            idempotencyKey: nil
        ) as DeleteResult
    }

    func downloadDevSampleVideo() async throws -> DevSampleVideo {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/dev/sample-video"))
        request.httpMethod = "GET"
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LifeCastAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "failed to fetch sample video"])
        }
        let fileName = http.value(forHTTPHeaderField: "X-LifeCast-File-Name") ?? "video.mov"
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "video/quicktime"
        return DevSampleVideo(data: data, fileName: fileName, contentType: contentType)
    }

    func sha256Hex(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func send<T: Decodable, B: Encodable>(
        path: String,
        method: String,
        body: B?,
        idempotencyKey: String?
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let error = object["error"] as? [String: Any] {
                    let code = (error["code"] as? String) ?? "UNKNOWN"
                    let message = (error["message"] as? String) ?? payloadText
                    throw NSError(
                        domain: "LifeCastAPI",
                        code: http.statusCode,
                        userInfo: [
                            NSLocalizedDescriptionKey: message,
                            "code": code
                        ]
                    )
                }
                if let message = object["message"] as? String {
                    throw NSError(
                        domain: "LifeCastAPI",
                        code: http.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: message]
                    )
                }
            }
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        return envelope.result
    }
}
