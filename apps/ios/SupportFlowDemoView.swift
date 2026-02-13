import SwiftUI

struct SupportFlowDemoView: View {
    @State private var projectIdText = "11111111-1111-1111-1111-111111111111"
    @State private var planIdText = "22222222-2222-2222-2222-222222222221"
    @State private var supportIdText = ""
    @State private var statusText = "idle"
    @State private var errorText = ""

    private let client = LifeCastAPIClient(baseURL: URL(string: "http://localhost:8080")!)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LifeCast Support Flow Demo")
                .font(.headline)

            TextField("Project ID", text: $projectIdText)
                .textFieldStyle(.roundedBorder)
            TextField("Plan ID", text: $planIdText)
                .textFieldStyle(.roundedBorder)
            TextField("Support ID", text: $supportIdText)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Prepare") {
                    Task { await prepareSupport() }
                }
                Button("Confirm") {
                    Task { await confirmSupport() }
                }
                Button("Refresh Status") {
                    Task { await refreshSupportStatus() }
                }
            }

            Text("Status: \(statusText)")
                .font(.subheadline)
            if !errorText.isEmpty {
                Text(errorText)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .padding()
    }

    private func prepareSupport() async {
        errorText = ""
        do {
            let projectId = try parseUUID(projectIdText)
            let planId = try parseUUID(planIdText)
            let result = try await client.prepareSupport(
                projectId: projectId,
                planId: planId,
                quantity: 1,
                idempotencyKey: "ios-demo-prepare-\(UUID().uuidString)"
            )
            supportIdText = result.support_id.uuidString
            statusText = result.support_status
        } catch {
            errorText = "Prepare failed: \(error.localizedDescription)"
        }
    }

    private func confirmSupport() async {
        errorText = ""
        do {
            let supportId = try parseUUID(supportIdText)
            let result = try await client.confirmSupport(
                supportId: supportId,
                providerSessionId: "ios-demo-session-\(UUID().uuidString)",
                idempotencyKey: "ios-demo-confirm-\(UUID().uuidString)"
            )
            statusText = result.support_status
        } catch {
            errorText = "Confirm failed: \(error.localizedDescription)"
        }
    }

    private func refreshSupportStatus() async {
        errorText = ""
        do {
            let supportId = try parseUUID(supportIdText)
            let result = try await client.getSupport(supportId: supportId)
            statusText = result.support_status
        } catch {
            errorText = "Refresh failed: \(error.localizedDescription)"
        }
    }

    private func parseUUID(_ text: String) throws -> UUID {
        guard let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "SupportFlowDemoView", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid UUID"])
        }
        return uuid
    }
}

