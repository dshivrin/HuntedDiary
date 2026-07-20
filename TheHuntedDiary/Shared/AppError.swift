import Foundation

struct AppErrorRecovery: Equatable {
    enum Action: Equatable {
        case none
        case openSettings
        case retryDrawing
        case retryReply
    }

    var message: String
    var actionTitle: String?
    var action: Action
}

enum AppError: Error, Equatable {
    case emptyDrawing
    case emptyRecognitionResult
    case recognitionFailed
    case shortcutReplyFailed
    case historyWriteFailed
}

extension AppError {
    var recovery: AppErrorRecovery {
        switch self {
        case .emptyDrawing:
            return AppErrorRecovery(
                message: "Write something first.",
                actionTitle: nil,
                action: .none
            )
        case .emptyRecognitionResult, .recognitionFailed:
            return AppErrorRecovery(
                message: "I could not read that. Your drawing is still here.",
                actionTitle: "Try Again",
                action: .retryDrawing
            )
        case .shortcutReplyFailed:
            return AppErrorRecovery(
                message: "The diary could not answer. Your words are still here.",
                actionTitle: "Try Again",
                action: .retryReply
            )
        case .historyWriteFailed:
            return AppErrorRecovery(
                message: "Reply shown, but history was not saved.",
                actionTitle: nil,
                action: .none
            )
        }
    }
}
