import Foundation

nonisolated enum DiaryReplyRequestKind: String, Codable, Sendable {
    case diaryTurn
    case setupProbe
}

nonisolated enum DiaryReplyRequestState: String, Codable, Sendable {
    case readyToLaunch
    case awaitingShortcut
    case replyStored
    case historyCommitted
    case cancelled
    case failed
    case expired
}

nonisolated enum DiaryReplyFailureCode: String, Codable, Sendable {
    case shortcutError = "shortcut_error"
    case shortcutUnavailable = "shortcut_unavailable"
    case launchRejected = "launch_rejected"
    case invalidShortcutConfiguration = "invalid_shortcut_configuration"
    case unsupportedDevice = "unsupported_device"
    case extensionUnavailable = "extension_unavailable"
    case internalError = "internal_error"

    var isRetryable: Bool {
        switch self {
        case .shortcutError, .shortcutUnavailable, .launchRejected:
            return true
        case .invalidShortcutConfiguration, .unsupportedDevice, .extensionUnavailable, .internalError:
            return false
        }
    }
}

nonisolated struct PendingDiaryReply: Codable, Equatable, Sendable, Identifiable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let id: UUID
    let kind: DiaryReplyRequestKind
    var capabilityDigest: Data
    var callbackCapabilityDigest: Data
    let recognizedText: String
    let recognitionSource: RecognitionResult.Source
    let prompt: String
    let createdAt: Date
    let expiresAt: Date
    var updatedAt: Date
    var state: DiaryReplyRequestState
    var attemptCount: Int
    var lastLaunchAt: Date?
    var assistantText: String?
    var historyCommittedAt: Date?
    var terminalReasonCode: String?
}

extension RecognitionResult.Source: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard let source = Self(rawValue: value) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown recognition source."
            )
        }
        self = source
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension RecognitionResult.Source: @unchecked Sendable {}
