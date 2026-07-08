import UIKit

struct OpenAIImageRecognizer: HandwritingRecognizer {
    func recognize(image: UIImage) async throws -> RecognitionResult {
        RecognitionResult(text: "", confidence: nil, source: .openAI)
    }
}
