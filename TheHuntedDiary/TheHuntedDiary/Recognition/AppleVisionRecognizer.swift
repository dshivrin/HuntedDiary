import ImageIO
import UIKit
@preconcurrency import Vision

struct AppleVisionRecognizer: HandwritingRecognizer {
    struct RecognizedLine: Equatable {
        var text: String
        var confidence: Double
    }

    func recognize(image: UIImage) async throws -> RecognitionResult {
        guard let cgImage = image.cgImage else {
            return RecognitionResult(text: "", confidence: nil, source: .appleVision)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation -> RecognizedLine? in
                    guard let candidate = observation.topCandidates(1).first else {
                        return nil
                    }

                    return RecognizedLine(
                        text: candidate.string,
                        confidence: Double(candidate.confidence)
                    )
                }

                continuation.resume(returning: Self.result(from: lines))
            }
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(
                cgImage: cgImage,
                orientation: CGImagePropertyOrientation(image.imageOrientation),
                options: [:]
            )

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func result(from lines: [RecognizedLine]) -> RecognitionResult {
        RecognitionResult(
            text: lines.map(\.text).joined(separator: "\n"),
            confidence: lines.map(\.confidence).min(),
            source: .appleVision
        )
    }
}

private extension CGImagePropertyOrientation {
    init(_ imageOrientation: UIImage.Orientation) {
        switch imageOrientation {
        case .up:
            self = .up
        case .upMirrored:
            self = .upMirrored
        case .down:
            self = .down
        case .downMirrored:
            self = .downMirrored
        case .left:
            self = .left
        case .leftMirrored:
            self = .leftMirrored
        case .right:
            self = .right
        case .rightMirrored:
            self = .rightMirrored
        @unknown default:
            self = .up
        }
    }
}
