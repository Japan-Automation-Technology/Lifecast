import Foundation
import CryptoKit

enum LifeCastRuntimeConfig {
    // Cloud Run URL; can be overridden via Info.plist key LIFECAST_API_BASE_URL.
    private static let fallbackAPIBaseURL = "https://lifecast-backend-850272145975.us-west1.run.app"

    static var apiBaseURL: URL {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "LIFECAST_API_BASE_URL") as? String,
           !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let url = URL(string: raw) {
            return url
        }
        return URL(string: fallbackAPIBaseURL)!
    }
}

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
    let play_count: Int?
    let watch_completed_count: Int?
    let watch_time_total_ms: Int?
    let created_at: String

    var id: UUID { video_id }
}

struct MyVideosResult: Decodable {
    let rows: [MyVideo]
}

struct ProjectPlanResult: Decodable, Identifiable {
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
    let image_urls: [String]?
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

struct DiscoverVideoRow: Decodable, Identifiable {
    let video_id: UUID
    let creator_user_id: UUID
    let username: String
    let display_name: String?
    let file_name: String
    let project_title: String?
    let playback_url: String?
    let thumbnail_url: String?
    let created_at: String

    var id: UUID { video_id }
}

struct DiscoverVideosResult: Decodable {
    let rows: [DiscoverVideoRow]
}

struct FeedProjectRow: Decodable, Identifiable {
    let project_id: UUID
    let creator_user_id: UUID
    let username: String
    let creator_avatar_url: String?
    let caption: String
    let video_id: UUID?
    let playback_url: String?
    let thumbnail_url: String?
    let min_plan_price_minor: Int
    let goal_amount_minor: Int
    let funded_amount_minor: Int
    let remaining_days: Int
    let likes: Int
    let comments: Int
    let is_liked_by_current_user: Bool
    let is_supported_by_current_user: Bool

    var id: UUID { project_id }
}

struct FeedProjectsResult: Decodable {
    let rows: [FeedProjectRow]
}

struct VideoEngagementResult: Decodable {
    let likes: Int
    let comments: Int
    let is_liked_by_current_user: Bool
}

struct VideoCommentRow: Decodable, Identifiable {
    let comment_id: UUID
    let user_id: UUID
    let username: String
    let display_name: String?
    let body: String
    let created_at: String
    let likes: Int
    let is_liked_by_current_user: Bool
    let is_supporter: Bool

    var id: UUID { comment_id }
}

struct VideoCommentsResult: Decodable {
    let rows: [VideoCommentRow]
}

struct CreateVideoCommentRequest: Encodable {
    let body: String
}

struct CreateVideoCommentResult: Decodable {
    let comment: VideoCommentRow
}

struct CommentEngagementResult: Decodable {
    let likes: Int
    let is_liked_by_current_user: Bool
}

struct AnalyticsEventAttributes: Encodable {
    let video_id: String
    let project_id: String?
    let watch_duration_ms: Int?
    let video_duration_ms: Int?
}

struct AnalyticsEventPayload: Encodable {
    let event_name: String
    let event_id: String
    let event_time: String
    let user_id: String?
    let anonymous_id: String?
    let session_id: String
    let client_platform: String
    let app_version: String
    let attributes: AnalyticsEventAttributes
}

struct AnalyticsIngestRequest: Encodable {
    let events: [AnalyticsEventPayload]
}

struct AnalyticsIngestResult: Decodable {
    let accepted: Int
    let rejected: Int
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

struct SupportedProjectRow: Decodable, Identifiable {
    let support_id: UUID
    let project_id: UUID
    let supported_at: String
    let amount_minor: Int
    let currency: String
    let project_title: String
    let project_subtitle: String?
    let project_image_url: String?
    let project_goal_amount_minor: Int
    let project_funded_amount_minor: Int
    let project_currency: String
    let project_supporter_count: Int
    let creator_user_id: UUID
    let creator_username: String
    let creator_display_name: String?

    var id: UUID { support_id }
}

struct SupportedProjectsResult: Decodable {
    let rows: [SupportedProjectRow]
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
    let image_urls: [String]?
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

struct UpdateProjectRequest: Encodable {
    struct Plan: Encodable {
        let id: UUID?
        let name: String?
        let price_minor: Int?
        let reward_summary: String?
        let description: String?
        let image_url: String?
        let currency: String?
    }

    let subtitle: String?
    let description: String?
    let image_url: String?
    let image_urls: [String]?
    let urls: [String]?
    let plans: [Plan]?
}

struct UploadProjectImageRequest: Encodable {
    let file_name: String?
    let content_type: String
    let data_base64: String
}

struct UploadProjectImageResult: Decodable {
    let image_url: String
}

struct UpdateMyProfileRequest: Encodable {
    let username: String?
    let display_name: String?
    let bio: String?
    let avatar_url: String?
}

struct AuthMeResult: Decodable {
    let user_id: UUID
    let auth_source: String
    let profile: CreatorPublicProfile?
}

struct DevAuthUser: Decodable, Identifiable {
    let user_id: UUID
    let username: String
    let display_name: String?
    let is_creator: Bool

    var id: UUID { user_id }
}

struct DevAuthUsersResult: Decodable {
    let rows: [DevAuthUser]
}

struct DevSwitchUserRequest: Encodable {
    let user_id: UUID
}

struct DevSwitchUserResult: Decodable {
    let user_id: UUID
    let header_name: String
    let header_value: String
    let switched: Bool
}

struct EmailSignInRequest: Encodable {
    let email: String
    let password: String
}

struct EmailSignUpRequest: Encodable {
    let email: String
    let password: String
    let username: String?
    let display_name: String?
}

struct RefreshTokenRequest: Encodable {
    let refresh_token: String
}

struct AuthSessionResult: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Int?
    let token_type: String?
    let user: AuthUser?
}

struct AuthUser: Decodable {
    let id: UUID
    let email: String?
}

struct OAuthURLResult: Decodable {
    let provider: String
    let redirect_to: String
    let authorize_url: String
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
    private static let actingUserIdKey = "lifecast.acting_user_id"
    private static let accessTokenKey = "lifecast.auth.access_token"
    private static let refreshTokenKey = "lifecast.auth.refresh_token"
    private static let analyticsAnonymousIdKey = "lifecast.analytics.anonymous_id"

    private let baseURL: URL
    private let session: URLSession
    private let analyticsSessionId = UUID().uuidString
    private var actingUserId: UUID?
    private var accessToken: String?
    private var refreshToken: String?

    init(baseURL: URL, session: URLSession = .shared, actingUserId: UUID? = nil) {
        self.baseURL = baseURL
        self.session = session
        self.actingUserId = actingUserId ?? Self.loadPersistedActingUserId()
        self.accessToken = UserDefaults.standard.string(forKey: Self.accessTokenKey)
        self.refreshToken = UserDefaults.standard.string(forKey: Self.refreshTokenKey)
    }

    func setActingUserId(_ userId: UUID?) {
        actingUserId = userId
        if let userId {
            UserDefaults.standard.set(userId.uuidString, forKey: Self.actingUserIdKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.actingUserIdKey)
        }
    }

    private func setAuthTokens(accessToken: String?, refreshToken: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        if let accessToken {
            UserDefaults.standard.set(accessToken, forKey: Self.accessTokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.accessTokenKey)
        }
        if let refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: Self.refreshTokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.refreshTokenKey)
        }
    }

    private static func loadPersistedActingUserId() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: Self.actingUserIdKey) else { return nil }
        return UUID(uuidString: raw)
    }

    private func analyticsAnonymousId() -> String {
        if let existing = UserDefaults.standard.string(forKey: Self.analyticsAnonymousIdKey), !existing.isEmpty {
            return existing
        }
        let generated = "anon-\(UUID().uuidString.lowercased())"
        UserDefaults.standard.set(generated, forKey: Self.analyticsAnonymousIdKey)
        return generated
    }

    private func analyticsAppVersion() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        if let short, let build, !short.isEmpty, !build.isEmpty {
            return "\(short)+\(build)"
        }
        if let short, !short.isEmpty {
            return short
        }
        return "ios-unknown"
    }

    private func applyAuthHeaders(_ request: inout URLRequest) {
        if accessToken == nil {
            accessToken = UserDefaults.standard.string(forKey: Self.accessTokenKey)
        }
        if refreshToken == nil {
            refreshToken = UserDefaults.standard.string(forKey: Self.refreshTokenKey)
        }
        if let actingUserId {
            request.setValue(actingUserId.uuidString, forHTTPHeaderField: "x-lifecast-user-id")
        }
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    var hasAuthSession: Bool {
        if let accessToken, !accessToken.isEmpty { return true }
        let persisted = UserDefaults.standard.string(forKey: Self.accessTokenKey)
        return persisted?.isEmpty == false
    }

    static func handleOAuthCallback(url: URL) -> Bool {
        guard url.scheme?.lowercased() == "lifecast" else { return false }
        guard url.host?.lowercased() == "auth" else { return false }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        guard path == "callback" else { return false }

        var pairs: [String: String] = [:]
        if let query = url.query {
            pairs.merge(parseURLEncodedPairs(query)) { _, new in new }
        }
        if let fragment = url.fragment {
            pairs.merge(parseURLEncodedPairs(fragment)) { _, new in new }
        }

        let accessToken = pairs["access_token"]
        let refreshToken = pairs["refresh_token"]
        guard accessToken != nil || refreshToken != nil else { return false }

        if let accessToken {
            UserDefaults.standard.set(accessToken, forKey: accessTokenKey)
        }
        if let refreshToken {
            UserDefaults.standard.set(refreshToken, forKey: refreshTokenKey)
        }
        if let userId = jwtSubject(accessToken), UUID(uuidString: userId) != nil {
            UserDefaults.standard.set(userId, forKey: actingUserIdKey)
        }
        NotificationCenter.default.post(name: .lifecastAuthSessionUpdated, object: nil)
        return true
    }

    private static func parseURLEncodedPairs(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for chunk in text.split(separator: "&", omittingEmptySubsequences: true) {
            let parts = chunk.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first, !rawKey.isEmpty else { continue }
            let rawValue = parts.count > 1 ? String(parts[1]) : ""
            let key = String(rawKey).removingPercentEncoding ?? String(rawKey)
            let value = rawValue.removingPercentEncoding ?? rawValue
            result[key] = value
        }
        return result
    }

    private static func jwtSubject(_ token: String?) -> String? {
        guard let token else { return nil }
        let segments = token.split(separator: ".")
        guard segments.count >= 2 else { return nil }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = payload.count % 4
        if padding > 0 {
            payload += String(repeating: "=", count: 4 - padding)
        }
        guard let payloadData = Data(base64Encoded: payload) else { return nil }
        guard
            let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
            let sub = json["sub"] as? String
        else {
            return nil
        }
        return sub
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
        applyAuthHeaders(&request)

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
        applyAuthHeaders(&request)

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
        applyAuthHeaders(&request)
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

    func discoverVideos(query: String) async throws -> [DiscoverVideoRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/discover/videos"),
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
            URLQueryItem(name: "limit", value: "36")
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
        applyAuthHeaders(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<DiscoverVideosResult>.self, from: data)
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
        applyAuthHeaders(&request)
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

    func getVideoEngagement(videoId: UUID) async throws -> VideoEngagementResult {
        try await send(
            path: "/v1/videos/\(videoId.uuidString)/engagement",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
    }

    func likeVideo(videoId: UUID) async throws -> VideoEngagementResult {
        try await send(
            path: "/v1/videos/\(videoId.uuidString)/like",
            method: "PUT",
            body: Optional<String>.none,
            idempotencyKey: "ios-like-video-\(videoId.uuidString)"
        )
    }

    func unlikeVideo(videoId: UUID) async throws -> VideoEngagementResult {
        try await send(
            path: "/v1/videos/\(videoId.uuidString)/like",
            method: "DELETE",
            body: Optional<String>.none,
            idempotencyKey: "ios-unlike-video-\(videoId.uuidString)"
        )
    }

    func listVideoComments(videoId: UUID, limit: Int = 50) async throws -> [VideoCommentRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/videos/\(videoId.uuidString)/comments"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid comments URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 100)))")
        ]
        guard let url = components.url else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid comments URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeaders(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<VideoCommentsResult>.self, from: data)
        return envelope.result.rows
    }

    func createVideoComment(videoId: UUID, body: String) async throws -> VideoCommentRow {
        let result: CreateVideoCommentResult = try await send(
            path: "/v1/videos/\(videoId.uuidString)/comments",
            method: "POST",
            body: CreateVideoCommentRequest(body: body),
            idempotencyKey: "ios-comment-video-\(videoId.uuidString)-\(UUID().uuidString)"
        )
        return result.comment
    }

    func likeVideoComment(videoId: UUID, commentId: UUID) async throws -> CommentEngagementResult {
        try await send(
            path: "/v1/videos/\(videoId.uuidString)/comments/\(commentId.uuidString)/like",
            method: "PUT",
            body: Optional<String>.none,
            idempotencyKey: "ios-like-comment-\(commentId.uuidString)"
        )
    }

    func unlikeVideoComment(videoId: UUID, commentId: UUID) async throws -> CommentEngagementResult {
        try await send(
            path: "/v1/videos/\(videoId.uuidString)/comments/\(commentId.uuidString)/like",
            method: "DELETE",
            body: Optional<String>.none,
            idempotencyKey: "ios-unlike-comment-\(commentId.uuidString)"
        )
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
        applyAuthHeaders(&request)
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
        applyAuthHeaders(&request)
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

    func getCreatorSupportedProjects(creatorUserId: UUID, limit: Int = 30) async throws -> [SupportedProjectRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/creators/\(creatorUserId.uuidString)/supported-projects"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid supported-projects URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 100)))")
        ]
        guard let url = components.url else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid supported-projects URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeaders(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<SupportedProjectsResult>.self, from: data)
        return envelope.result.rows
    }

    func getMySupportedProjects(limit: Int = 30) async throws -> [SupportedProjectRow] {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/me/supported-projects"),
            resolvingAgainstBaseURL: false
        ) else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid my supported-projects URL"])
        }
        components.queryItems = [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 100)))")
        ]
        guard let url = components.url else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid my supported-projects URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeaders(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payloadText = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPI", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payloadText])
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<SupportedProjectsResult>.self, from: data)
        return envelope.result.rows
    }

    func getMyProfile() async throws -> MyProfileResult {
        let result: MyProfileResult = try await send(
            path: "/v1/me/profile",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
        if actingUserId == nil {
            setActingUserId(result.profile.creator_user_id)
        }
        return result
    }

    func getAuthMe() async throws -> AuthMeResult {
        let result: AuthMeResult = try await send(
            path: "/v1/auth/me",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
        if actingUserId == nil || actingUserId != result.user_id {
            setActingUserId(result.user_id)
        }
        return result
    }

    func signUpWithEmail(email: String, password: String, username: String?, displayName: String?) async throws -> AuthSessionResult {
        let result: AuthSessionResult = try await send(
            path: "/v1/auth/email/sign-up",
            method: "POST",
            body: EmailSignUpRequest(email: email, password: password, username: username, display_name: displayName),
            idempotencyKey: "ios-auth-signup-\(UUID().uuidString)"
        )
        if let userId = result.user?.id {
            setActingUserId(userId)
        }
        if result.access_token != nil || result.refresh_token != nil {
            setAuthTokens(accessToken: result.access_token, refreshToken: result.refresh_token)
        }
        return result
    }

    func signInWithEmail(email: String, password: String) async throws -> AuthSessionResult {
        let result: AuthSessionResult = try await send(
            path: "/v1/auth/email/sign-in",
            method: "POST",
            body: EmailSignInRequest(email: email, password: password),
            idempotencyKey: "ios-auth-signin-\(UUID().uuidString)"
        )
        if let userId = result.user?.id {
            setActingUserId(userId)
        }
        setAuthTokens(accessToken: result.access_token, refreshToken: result.refresh_token)
        return result
    }

    func refreshAuthSession() async throws -> AuthSessionResult {
        guard let refreshToken, !refreshToken.isEmpty else {
            throw NSError(domain: "LifeCastAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "No refresh token"])
        }
        let result: AuthSessionResult = try await send(
            path: "/v1/auth/token/refresh",
            method: "POST",
            body: RefreshTokenRequest(refresh_token: refreshToken),
            idempotencyKey: "ios-auth-refresh-\(UUID().uuidString)"
        )
        if let userId = result.user?.id {
            setActingUserId(userId)
        }
        setAuthTokens(accessToken: result.access_token, refreshToken: result.refresh_token ?? refreshToken)
        return result
    }

    func signOut() async {
        struct SignOutResult: Decodable { let signed_out: Bool }
        _ = try? await send(
            path: "/v1/auth/sign-out",
            method: "POST",
            body: Optional<String>.none,
            idempotencyKey: "ios-auth-signout-\(UUID().uuidString)"
        ) as SignOutResult
        setAuthTokens(accessToken: nil, refreshToken: nil)
        setActingUserId(nil)
        NotificationCenter.default.post(name: .lifecastAuthSessionUpdated, object: nil)
    }

    func oauthURL(provider: String, redirectTo: String? = nil) async throws -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/auth/oauth/url"),
            resolvingAgainstBaseURL: false
        )!
        var queryItems = [URLQueryItem(name: "provider", value: provider)]
        if let redirectTo {
            queryItems.append(URLQueryItem(name: "redirect_to", value: redirectTo))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NSError(domain: "LifeCastAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid OAuth URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuthHeaders(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAuth", code: (response as? HTTPURLResponse)?.statusCode ?? -1, userInfo: [NSLocalizedDescriptionKey: text])
        }
        let envelope = try JSONDecoder().decode(APIEnvelope<OAuthURLResult>.self, from: data)
        guard let authorizeURL = URL(string: envelope.result.authorize_url) else {
            throw NSError(domain: "LifeCastAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid authorize URL"])
        }
        return authorizeURL
    }

    func listDevAuthUsers() async throws -> [DevAuthUser] {
        let result: DevAuthUsersResult = try await send(
            path: "/v1/auth/dev/users",
            method: "GET",
            body: Optional<String>.none,
            idempotencyKey: nil
        )
        return result.rows
    }

    func switchDevUser(userId: UUID) async throws {
        let _: DevSwitchUserResult = try await send(
            path: "/v1/auth/dev/switch",
            method: "POST",
            body: DevSwitchUserRequest(user_id: userId),
            idempotencyKey: "ios-dev-switch-\(UUID().uuidString)"
        )
        setActingUserId(userId)
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
        imageURLs: [String]?,
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
            image_url: imageURLs?.first ?? imageURL,
            image_urls: imageURLs,
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

    func updateProject(
        projectId: UUID,
        subtitle: String?,
        description: String?,
        imageURL: String?,
        imageURLs: [String]?,
        urls: [String]?,
        plans: [UpdateProjectRequest.Plan]?
    ) async throws -> MyProjectResult {
        let body = UpdateProjectRequest(
            subtitle: subtitle,
            description: description,
            image_url: imageURLs?.first ?? imageURL,
            image_urls: imageURLs,
            urls: urls,
            plans: plans
        )
        return try await send(
            path: "/v1/projects/\(projectId.uuidString)",
            method: "PATCH",
            body: body,
            idempotencyKey: "ios-project-update-\(UUID().uuidString)"
        )
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

    func uploadProfileImage(data: Data, fileName: String?, contentType: String) async throws -> String {
        let body = UploadProjectImageRequest(
            file_name: fileName,
            content_type: contentType,
            data_base64: data.base64EncodedString()
        )
        let result: UploadProjectImageResult = try await send(
            path: "/v1/profiles/images",
            method: "POST",
            body: body,
            idempotencyKey: "ios-profile-image-\(UUID().uuidString)"
        )
        return result.image_url
    }

    func updateMyProfile(username: String?, displayName: String?, bio: String?, avatarURL: String?) async throws -> MyProfileResult {
        try await send(
            path: "/v1/me/profile",
            method: "PATCH",
            body: UpdateMyProfileRequest(username: username, display_name: displayName, bio: bio, avatar_url: avatarURL),
            idempotencyKey: "ios-profile-update-\(UUID().uuidString)"
        )
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
        applyAuthHeaders(&request)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "LifeCastAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "failed to fetch sample video"])
        }
        let fileName = http.value(forHTTPHeaderField: "X-LifeCast-File-Name") ?? "video.mov"
        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? "video/quicktime"
        return DevSampleVideo(data: data, fileName: fileName, contentType: contentType)
    }

    @discardableResult
    func ingestAnalyticsEvents(_ events: [AnalyticsEventPayload]) async throws -> AnalyticsIngestResult {
        guard !events.isEmpty else {
            return AnalyticsIngestResult(accepted: 0, rejected: 0)
        }
        return try await send(
            path: "/v1/events/ingest",
            method: "POST",
            body: AnalyticsIngestRequest(events: events),
            idempotencyKey: nil
        )
    }

    func trackVideoPlayStarted(videoId: UUID, projectId: UUID?) async {
        let payload = AnalyticsEventPayload(
            event_name: "video_play_started",
            event_id: UUID().uuidString,
            event_time: ISO8601DateFormatter().string(from: Date()),
            user_id: actingUserId?.uuidString,
            anonymous_id: actingUserId == nil ? analyticsAnonymousId() : nil,
            session_id: analyticsSessionId,
            client_platform: "ios",
            app_version: analyticsAppVersion(),
            attributes: AnalyticsEventAttributes(
                video_id: videoId.uuidString,
                project_id: projectId?.uuidString,
                watch_duration_ms: nil,
                video_duration_ms: nil
            )
        )
        _ = try? await ingestAnalyticsEvents([payload])
    }

    func trackVideoWatchProgress(videoId: UUID, watchDurationMs: Int, videoDurationMs: Int, projectId: UUID?) async {
        guard watchDurationMs > 0, videoDurationMs > 0 else { return }
        let payload = AnalyticsEventPayload(
            event_name: "video_watch_progress",
            event_id: UUID().uuidString,
            event_time: ISO8601DateFormatter().string(from: Date()),
            user_id: actingUserId?.uuidString,
            anonymous_id: actingUserId == nil ? analyticsAnonymousId() : nil,
            session_id: analyticsSessionId,
            client_platform: "ios",
            app_version: analyticsAppVersion(),
            attributes: AnalyticsEventAttributes(
                video_id: videoId.uuidString,
                project_id: projectId?.uuidString,
                watch_duration_ms: watchDurationMs,
                video_duration_ms: videoDurationMs
            )
        )
        _ = try? await ingestAnalyticsEvents([payload])
    }

    func trackVideoWatchCompleted(videoId: UUID, projectId: UUID, watchDurationMs: Int, videoDurationMs: Int) async {
        guard watchDurationMs > 0, videoDurationMs > 0 else { return }
        let payload = AnalyticsEventPayload(
            event_name: "video_watch_completed",
            event_id: UUID().uuidString,
            event_time: ISO8601DateFormatter().string(from: Date()),
            user_id: actingUserId?.uuidString,
            anonymous_id: actingUserId == nil ? analyticsAnonymousId() : nil,
            session_id: analyticsSessionId,
            client_platform: "ios",
            app_version: analyticsAppVersion(),
            attributes: AnalyticsEventAttributes(
                video_id: videoId.uuidString,
                project_id: projectId.uuidString,
                watch_duration_ms: watchDurationMs,
                video_duration_ms: videoDurationMs
            )
        )
        _ = try? await ingestAnalyticsEvents([payload])
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
        applyAuthHeaders(&request)
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

extension Notification.Name {
    static let lifecastAuthSessionUpdated = Notification.Name("lifecast.auth.session.updated")
}
