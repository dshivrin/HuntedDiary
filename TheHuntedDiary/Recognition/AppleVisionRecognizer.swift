import UIKit

struct AppleVisionRecognizer: HandwritingRecognizer {
    func recognize(image: UIImage) async throws -> RecognitionResult {
        RecognitionResult(text: "", confidence: nil, source: .appleVision)
    }
}
