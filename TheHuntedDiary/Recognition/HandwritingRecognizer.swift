import UIKit

protocol HandwritingRecognizer {
    func recognize(image: UIImage) async throws -> RecognitionResult
}
