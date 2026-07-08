import Foundation

enum AppError: Error, Equatable {
    case missingAPIKey
    case emptyRecognitionResult
}
