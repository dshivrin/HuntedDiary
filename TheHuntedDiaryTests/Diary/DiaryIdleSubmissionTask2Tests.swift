import PencilKit
import Testing
import UIKit
@testable import TheHuntedDiary

@MainActor
struct DiaryIdleSubmissionTask2Tests {
    @Test func idleCommitRoutesToSubmitAndPreservesMountedCanvasModel() async throws {
        let recognizer = IdleSubmissionRecognizer()
        let replyClient = IdleSubmissionReplyClient()
        let historyStore = IdleSubmissionHistoryStore()
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            apiKeyStore: IdleSubmissionAPIKeyStore(),
            historyStore: historyStore,
            recognizer: recognizer,
            openAIClient: replyClient
        )
        let model = PencilCanvasModel(drawing: Self.makeDrawing())
        let originalDrawing = model.drawing.dataRepresentation()
        let clock = IdleSubmissionClock()
        let committer = PencilCanvasIdleCommitter(
            delay: .milliseconds(2500),
            clock: clock
        )
        let route = DiaryPageView.idleSubmissionRoute(
            controller: controller,
            canvasSize: CGSize(width: 500, height: 700)
        )

        route.drawingDidChange(model, using: committer)
        await clock.waitForSleepers(count: 1)
        await clock.advance(by: .milliseconds(2499))
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(recognizer.callCount == 0)
        #expect(replyClient.callCount == 0)
        #expect(model.drawing.dataRepresentation() == originalDrawing)

        await clock.advance(by: .milliseconds(1))
        try await Self.waitUntil { controller.phase == .completed }

        #expect(recognizer.callCount == 1)
        #expect(replyClient.callCount == 1)
        #expect(historyStore.appendedTurns.count == 1)
        #expect(model.drawing.dataRepresentation() == originalDrawing)
    }

    @Test func emptyLocalRecognitionStopsWithoutNetworkFallback() async {
        let recognizer = IdleSubmissionRecognizer(text: "   ", confidence: nil)
        let replyClient = IdleSubmissionReplyClient()
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            apiKeyStore: IdleSubmissionAPIKeyStore(),
            historyStore: IdleSubmissionHistoryStore(),
            recognizer: recognizer,
            openAIClient: replyClient
        )

        await controller.submit(image: Self.makeImage())

        #expect(controller.phase == .failed(DiaryTurnFailure(stage: .recognition, error: .emptyRecognitionResult)))
        #expect(recognizer.callCount == 1)
        #expect(replyClient.callCount == 0)
    }

    @Test func lowConfidenceLocalRecognitionDoesNotUseImageFallback() async {
        let recognizer = IdleSubmissionRecognizer(text: "Faint but usable.", confidence: 0.12)
        let replyClient = IdleSubmissionReplyClient()
        let historyStore = IdleSubmissionHistoryStore()
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            apiKeyStore: IdleSubmissionAPIKeyStore(),
            historyStore: historyStore,
            recognizer: recognizer,
            openAIClient: replyClient
        )

        await controller.submit(image: Self.makeImage())

        #expect(controller.phase == .completed)
        #expect(recognizer.callCount == 1)
        #expect(historyStore.appendedTurns.first?.recognitionSource == .appleVision)
    }

    @Test func automaticSubmissionDoesNotCancelItsOwnRecognitionTask() async throws {
        let recognizer = CancellationAwareIdleSubmissionRecognizer()
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            apiKeyStore: IdleSubmissionAPIKeyStore(),
            historyStore: IdleSubmissionHistoryStore(),
            recognizer: recognizer,
            openAIClient: IdleSubmissionReplyClient()
        )
        let model = PencilCanvasModel(drawing: Self.makeDrawing())

        DiaryPageView.idleSubmissionRoute(
            controller: controller,
            canvasSize: CGSize(width: 500, height: 700)
        ).handler(model)
        try await Self.waitUntil {
            controller.phase == .completed || controller.activeRecovery != nil
        }

        #expect(controller.phase == .completed)
        #expect(recognizer.observedCancellation == false)
    }

    @Test func staleRecognitionCompletionCannotOverwriteNewerTurn() async throws {
        let recognizer = SuspendingIdleSubmissionRecognizer()
        let historyStore = IdleSubmissionHistoryStore()
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            apiKeyStore: IdleSubmissionAPIKeyStore(),
            historyStore: historyStore,
            recognizer: recognizer,
            openAIClient: IdleSubmissionReplyClient()
        )
        let model = PencilCanvasModel(drawing: Self.makeDrawing())
        let idleCommit = DiaryPageView.idleSubmissionRoute(
            controller: controller,
            canvasSize: CGSize(width: 500, height: 700)
        ).handler

        idleCommit(model)
        try await Self.waitUntil { recognizer.hasSuspendedFirstCall }

        idleCommit(model)
        try await Self.waitUntil { controller.phase == .completed }
        #expect(controller.recognizedText == "Newest local ink.")

        recognizer.resumeFirstCall()
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(controller.recognizedText == "Newest local ink.")
        #expect(historyStore.appendedTurns.map(\.userText) == ["Newest local ink."])
    }

    private static func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while condition() == false {
            guard clock.now < deadline else {
                throw IdleSubmissionTestError.timeout
            }
            await Task.yield()
        }
    }

    private static func makeDrawing() -> PKDrawing {
        let points = [
            PKStrokePoint(
                location: CGPoint(x: 100, y: 100),
                timeOffset: 0,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
            PKStrokePoint(
                location: CGPoint(x: 220, y: 160),
                timeOffset: 0.2,
                size: CGSize(width: 8, height: 8),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            ),
        ]
        let path = PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: 0))
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: path)])
    }

    private static func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

private final class IdleSubmissionRecognizer: HandwritingRecognizer {
    private let text: String
    private let confidence: Double?
    private(set) var callCount = 0

    init(text: String = "The local ink.", confidence: Double? = 0.42) {
        self.text = text
        self.confidence = confidence
    }

    func recognize(image _: UIImage) async throws -> RecognitionResult {
        callCount += 1
        return RecognitionResult(text: text, confidence: confidence, source: .appleVision)
    }
}

private final class CancellationAwareIdleSubmissionRecognizer: HandwritingRecognizer {
    private(set) var observedCancellation = false

    func recognize(image _: UIImage) async throws -> RecognitionResult {
        observedCancellation = Task.isCancelled
        try Task.checkCancellation()
        return RecognitionResult(text: "Cancellation-free ink.", confidence: 0.9, source: .appleVision)
    }
}

private final class SuspendingIdleSubmissionRecognizer: HandwritingRecognizer {
    private(set) var hasSuspendedFirstCall = false
    private var callCount = 0
    private var firstContinuation: CheckedContinuation<RecognitionResult, Never>?

    func recognize(image _: UIImage) async throws -> RecognitionResult {
        callCount += 1
        if callCount == 1 {
            hasSuspendedFirstCall = true
            return await withCheckedContinuation { continuation in
                firstContinuation = continuation
            }
        }

        return RecognitionResult(text: "Newest local ink.", confidence: 0.9, source: .appleVision)
    }

    func resumeFirstCall() {
        firstContinuation?.resume(
            returning: RecognitionResult(text: "Stale local ink.", confidence: 0.9, source: .appleVision)
        )
        firstContinuation = nil
    }
}

private final class IdleSubmissionReplyClient: OpenAIReplyStreaming {
    private(set) var callCount = 0

    func replyStream(
        apiKey _: String,
        prompt _: DiaryPromptBuilder.Prompt,
        settings _: AppSettings
    ) -> AsyncThrowingStream<String, Error> {
        callCount += 1
        return AsyncThrowingStream { continuation in
            continuation.yield("The reply.")
            continuation.finish()
        }
    }
}

private final class IdleSubmissionHistoryStore: DiaryHistoryStoring {
    private(set) var appendedTurns: [ConversationTurn] = []

    func loadRecent(limit _: Int) throws -> [ConversationTurn] { [] }
    func append(_ turn: ConversationTurn) throws { appendedTurns.append(turn) }
    func pruneOldestTurns(keepingMaximum _: Int) throws {}
}

private struct IdleSubmissionAPIKeyStore: APIKeyLoading {
    func load() throws -> String? { "sk-test" }
}

private enum IdleSubmissionTestError: Error {
    case timeout
}

private actor IdleSubmissionClock: PencilCanvasClock {
    private struct Sleeper {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private var elapsed: Duration = .zero
    private var sleepers: [Sleeper] = []
    private var sleeperWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    nonisolated func sleep(for duration: Duration) async throws {
        try await isolatedSleep(for: duration)
    }

    private func isolatedSleep(for duration: Duration) async throws {
        try await withCheckedThrowingContinuation { continuation in
            sleepers.append(Sleeper(deadline: elapsed + duration, continuation: continuation))
            resumeReadySleeperWaiters()
        }
    }

    func advance(by duration: Duration) {
        elapsed += duration
        let ready = sleepers.filter { $0.deadline <= elapsed }
        sleepers.removeAll { $0.deadline <= elapsed }
        for sleeper in ready {
            sleeper.continuation.resume()
        }
    }

    func waitForSleepers(count: Int) async {
        if sleepers.count >= count {
            return
        }

        await withCheckedContinuation { continuation in
            sleeperWaiters.append((count: count, continuation: continuation))
        }
    }

    private func resumeReadySleeperWaiters() {
        let ready = sleeperWaiters.filter { sleepers.count >= $0.count }
        sleeperWaiters.removeAll { sleepers.count >= $0.count }
        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}
