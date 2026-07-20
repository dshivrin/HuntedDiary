import Testing
@testable import TheHuntedDiary

struct AppleVisionRecognizerTests {
    @Test func testAggregatesMultipleRecognizedLinesWithNewlines() {
        let result = AppleVisionRecognizer.result(
            from: [
                AppleVisionRecognizer.RecognizedLine(text: "The first line", confidence: 0.9),
                AppleVisionRecognizer.RecognizedLine(text: "answers back", confidence: 0.8)
            ]
        )

        #expect(result == RecognitionResult(text: "The first line\nanswers back", confidence: 0.8, source: .appleVision))
    }

    @Test func testUsesMinimumCandidateConfidence() {
        let result = AppleVisionRecognizer.result(
            from: [
                AppleVisionRecognizer.RecognizedLine(text: "Certain", confidence: 0.95),
                AppleVisionRecognizer.RecognizedLine(text: "Less certain", confidence: 0.62),
                AppleVisionRecognizer.RecognizedLine(text: "Steady", confidence: 0.8)
            ]
        )

        #expect(result.confidence == 0.62)
    }
}
