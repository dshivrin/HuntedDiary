import Testing
@testable import TheHuntedDiary

struct LocalRecognitionTask2Tests {
    @Test func emptyVisionResultStaysLocal() {
        let result = AppleVisionRecognizer.result(from: [])

        #expect(result.text.isEmpty)
        #expect(result.confidence == nil)
        #expect(result.source == .appleVision)
    }

    @Test func lowConfidenceVisionResultStaysLocal() {
        let result = AppleVisionRecognizer.result(
            from: [AppleVisionRecognizer.RecognizedLine(text: "Faint ink", confidence: 0.12)]
        )

        #expect(result.text == "Faint ink")
        #expect(result.confidence == 0.12)
        #expect(result.source == .appleVision)
    }
}
