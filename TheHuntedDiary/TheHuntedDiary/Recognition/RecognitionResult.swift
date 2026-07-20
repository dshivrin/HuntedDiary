import Foundation

struct RecognitionResult: Equatable {
    enum Source: String, Equatable {
        case appleVision
        // Retained only so existing on-disk history can still be decoded.
        case openAI
    }

    var text: String
    var confidence: Double?
    var source: Source
}
