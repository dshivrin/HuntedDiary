import Foundation

struct RecognitionResult: Equatable {
    enum Source: String, Equatable {
        case appleVision
        case openAI
    }

    var text: String
    var confidence: Double?
    var source: Source
}
