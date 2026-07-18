import Foundation

nonisolated enum DiaryReplyIntentError: Error, Equatable, CaseIterable, CustomStringConvertible, LocalizedError {
    case invalidRequestHandle
    case requestUnavailable
    case requestExpired
    case requestUnauthorized
    case requestStateInvalid
    case emptyReply
    case replyTooLong
    case conflictingReply
    case storageUnavailable

    var description: String {
        switch self {
        case .invalidRequestHandle:
            return "The diary reply request handle is invalid."
        case .requestUnavailable:
            return "The diary reply request is no longer available."
        case .requestExpired:
            return "The diary reply request has expired."
        case .requestUnauthorized:
            return "The diary reply request is not authorized."
        case .requestStateInvalid:
            return "The diary reply request cannot be used in its current state."
        case .emptyReply:
            return "The reply is empty."
        case .replyTooLong:
            return "The reply is too long."
        case .conflictingReply:
            return "A different reply was already stored for this request."
        case .storageUnavailable:
            return "The diary reply could not be stored."
        }
    }

    var errorDescription: String? { description }

    static func map(_ error: Error) -> Self {
        guard let storeError = error as? PendingDiaryReplyStore.StoreError else {
            return .storageUnavailable
        }
        switch storeError {
        case .unknownRequest:
            return .requestUnavailable
        case .requestExpired:
            return .requestExpired
        case .invalidCapability:
            return .requestUnauthorized
        case .conflictingReply:
            return .conflictingReply
        case .invalidTransition:
            return .requestStateInvalid
        case .durableWriteFailed, .directorySyncFailedAfterCommit:
            return .storageUnavailable
        case .duplicateRequest, .unsupportedSchemaVersion,
             .unsupportedRequestSchemaVersion, .invalidRequest,
             .invalidFailureCode, .retryCapabilityReuse, .failureNotRetryable:
            return .requestStateInvalid
        }
    }
}
