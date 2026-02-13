import Foundation

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

struct UploadSessionResult: Decodable {
    let upload_session_id: UUID
    let status: String
    let upload_url: String?
    let expires_at: String?
    let video_id: UUID?
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

    func createUploadSession(fileName: String, fileSizeBytes: Int, idempotencyKey: String) async throws -> UploadSessionResult {
        let body = UploadCreateRequest(file_name: fileName, content_type: "video/mp4", file_size_bytes: fileSizeBytes)
        return try await send(path: "/v1/videos/uploads", method: "POST", body: body, idempotencyKey: idempotencyKey)
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
