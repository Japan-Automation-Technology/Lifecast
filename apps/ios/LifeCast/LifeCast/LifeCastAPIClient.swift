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
    let created_at: String

    var id: UUID { video_id }
}

struct MyVideosResult: Decodable {
    let rows: [MyVideo]
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

    func createUploadSession(fileName: String, contentType: String, fileSizeBytes: Int, idempotencyKey: String) async throws -> UploadSessionResult {
        let body = UploadCreateRequest(file_name: fileName, content_type: contentType, file_size_bytes: fileSizeBytes)
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "LifeCastAPIClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "invalid response"])
        }
        guard (200..<300).contains(http.statusCode) else {
            let payload = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "LifeCastAPIClient", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: payload])
        }

        let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
        return envelope.result
    }
}
