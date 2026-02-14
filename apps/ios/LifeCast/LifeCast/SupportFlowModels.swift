import SwiftUI

enum FeedMode: String, CaseIterable {
    case forYou = "For You"
    case following = "Following"
}

enum SupportEntryPoint {
    case feed
    case project
}

enum SupportStep: Int {
    case planSelect
    case confirm
    case checkout
    case result
}

enum UploadFlowState: String {
    case idle
    case created
    case uploading
    case processing
    case ready
    case failed
}

struct SupportPlan: Identifiable, Hashable {
    let id: UUID
    let name: String
    let priceMinor: Int
    let rewardSummary: String
}

struct FeedProjectSummary: Identifiable {
    let id: UUID
    let creatorId: UUID
    let username: String
    let caption: String
    let minPlanPriceMinor: Int
    let goalAmountMinor: Int
    let fundedAmountMinor: Int
    let remainingDays: Int
    let likes: Int
    let comments: Int
    let isSupportedByCurrentUser: Bool
}

struct FeedComment: Identifiable {
    let id: UUID
    let username: String
    let body: String
    let likes: Int
    let createdAt: Date
    let isSupporter: Bool
}

struct CreatorRoute: Identifiable, Hashable {
    let id: UUID
}

struct NumberFormatterProvider {
    static let jpy: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "JPY"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

func fundingProgressTint(_ percentRaw: Double) -> Color {
    if percentRaw >= 2.0 {
        return Color(red: 0.83, green: 0.69, blue: 0.22)
    }
    if percentRaw > 1.0 {
        return Color(red: 0.76, green: 0.76, blue: 0.80)
    }
    return .green
}

extension Notification.Name {
    static let lifecastRelationshipChanged = Notification.Name("lifecast.relationship.changed")
}

let sampleProjects: [FeedProjectSummary] = [
    FeedProjectSummary(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!,
        username: "tak_game_lab",
        caption: "Building our handheld game prototype. Today: thermal and battery test.",
        minPlanPriceMinor: 1000,
        goalAmountMinor: 1_000_000,
        fundedAmountMinor: 1_120_000,
        remainingDays: 12,
        likes: 4520,
        comments: 173,
        isSupportedByCurrentUser: false
    ),
    FeedProjectSummary(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000005")!,
        username: "boardcraft_studio",
        caption: "Week 3: tuning tactile switches with community feedback.",
        minPlanPriceMinor: 1200,
        goalAmountMinor: 800_000,
        fundedAmountMinor: 460_000,
        remainingDays: 9,
        likes: 3210,
        comments: 108,
        isSupportedByCurrentUser: false
    ),
    FeedProjectSummary(
        id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
        creatorId: UUID(uuidString: "00000000-0000-0000-0000-000000000006")!,
        username: "mini_console_lab",
        caption: "Prototype shell test print. Need your vote on materials.",
        minPlanPriceMinor: 1500,
        goalAmountMinor: 1_500_000,
        fundedAmountMinor: 320_000,
        remainingDays: 18,
        likes: 2890,
        comments: 94,
        isSupportedByCurrentUser: false
    )
]

let sampleComments: [FeedComment] = [
    FeedComment(id: UUID(), username: "pixel_rena", body: "Make the shell matte black please", likes: 420, createdAt: .now.addingTimeInterval(-3600), isSupporter: true),
    FeedComment(id: UUID(), username: "retro_haru", body: "Thermal test looked promising!", likes: 210, createdAt: .now.addingTimeInterval(-7200), isSupporter: true),
    FeedComment(id: UUID(), username: "kei_dev", body: "Can you share battery life at 60fps?", likes: 180, createdAt: .now.addingTimeInterval(-8600), isSupporter: false)
]
