import PencilKit
import Testing
import UIKit
@testable import TheHuntedDiary

@MainActor
struct DiaryIdleSubmissionTask2Tests {
    @Test func idleCommitRoutesToSubmitAndPreservesMountedCanvasModel() async throws {
        let recognizer = IdleSubmissionRecognizer()
        let historyStore = IdleSubmissionHistoryStore()
        let fixture = try makeController(recognizer: recognizer, historyStore: historyStore)
        let controller = fixture.controller
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
        #expect(fixture.launcher.callCount == 0)
        #expect(model.drawing.dataRepresentation() == originalDrawing)

        await clock.advance(by: .milliseconds(1))
        try await Self.waitUntil { controller.phase == .awaitingShortcut }
        await controller.reconcile()

        #expect(recognizer.callCount == 1)
        #expect(fixture.launcher.callCount == 1)
        #expect(historyStore.appendedTurns.count == 1)
        #expect(model.drawing.dataRepresentation() == originalDrawing)
    }

    @Test func emptyLocalRecognitionStopsWithoutNetworkFallback() async throws {
        let recognizer = IdleSubmissionRecognizer(text: "   ", confidence: nil)
        let fixture = try makeController(recognizer: recognizer)
        let controller = fixture.controller

        await controller.submit(image: Self.makeImage())

        #expect(controller.phase == .failed(DiaryTurnFailure(stage: .recognition, error: .emptyRecognitionResult)))
        #expect(recognizer.callCount == 1)
        #expect(fixture.launcher.callCount == 0)
    }

    @Test func lowConfidenceLocalRecognitionDoesNotUseImageFallback() async throws {
        let recognizer = IdleSubmissionRecognizer(text: "Faint but usable.", confidence: 0.12)
        let historyStore = IdleSubmissionHistoryStore()
        let fixture = try makeController(recognizer: recognizer, historyStore: historyStore)
        let controller = fixture.controller

        await controller.submit(image: Self.makeImage())

        #expect(controller.phase == .awaitingShortcut)
        await controller.reconcile()
        #expect(controller.phase == .completed)
        #expect(recognizer.callCount == 1)
        #expect(historyStore.appendedTurns.first?.recognitionSource == .appleVision)
    }

    @Test func automaticSubmissionDoesNotCancelItsOwnRecognitionTask() async throws {
        let recognizer = CancellationAwareIdleSubmissionRecognizer()
        let fixture = try makeController(recognizer: recognizer)
        let controller = fixture.controller
        let model = PencilCanvasModel(drawing: Self.makeDrawing())

        DiaryPageView.idleSubmissionRoute(
            controller: controller,
            canvasSize: CGSize(width: 500, height: 700)
        ).handler(model)
        try await Self.waitUntil {
            controller.phase == .awaitingShortcut || controller.activeRecovery != nil
        }
        await controller.reconcile()
        #expect(controller.phase == .completed)
        #expect(recognizer.observedCancellation == false)
    }

    @Test func staleRecognitionCompletionCannotOverwriteNewerTurn() async throws {
        let recognizer = SuspendingIdleSubmissionRecognizer()
        let historyStore = IdleSubmissionHistoryStore()
        let fixture = try makeController(recognizer: recognizer, historyStore: historyStore)
        let controller = fixture.controller
        let model = PencilCanvasModel(drawing: Self.makeDrawing())
        let idleCommit = DiaryPageView.idleSubmissionRoute(
            controller: controller,
            canvasSize: CGSize(width: 500, height: 700)
        ).handler

        idleCommit(model)
        try await Self.waitUntil { recognizer.hasSuspendedFirstCall }

        idleCommit(model)
        try await Self.waitUntil { controller.phase == .awaitingShortcut }
        await controller.reconcile()
        #expect(controller.recognizedText == "Newest local ink.")

        recognizer.resumeFirstCall()
        for _ in 0 ..< 100 {
            await Task.yield()
        }

        #expect(controller.recognizedText == "Newest local ink.")
        #expect(historyStore.appendedTurns.map(\.userText) == ["Newest local ink."])
    }

    private func makeController(
        recognizer: any HandwritingRecognizer,
        historyStore: IdleSubmissionHistoryStore? = nil
    ) throws -> (controller: DiaryTurnController, launcher: IdleSubmissionLauncher) {
        let resolvedHistoryStore = historyStore ?? IdleSubmissionHistoryStore()
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("IdleSubmission-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let launcher = IdleSubmissionLauncher(store: store)
        return (
            DiaryTurnController(
                settingsProvider: { AppSettings() },
                historyStore: resolvedHistoryStore,
                recognizer: recognizer,
                pendingStore: store,
                launcher: launcher
            ),
            launcher
        )
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

private final class IdleSubmissionLauncher: ShortcutReplyLaunching {
    let store: PendingDiaryReplyStore
    private(set) var callCount = 0

    init(store: PendingDiaryReplyStore) {
        self.store = store
    }

    func launch(shortcutName _: String, handle: String, callbacks _: ShortcutCallbacks) async throws {
        callCount += 1
        let authorization = try DiaryReplyCapability(handle: handle)
        try await store.storeReply(
            id: authorization.requestID,
            capability: authorization.capability,
            text: "The reply.",
            now: Date()
        )
    }
}

private final class IdleSubmissionHistoryStore: IdempotentDiaryHistoryStoring {
    private(set) var appendedTurns: [ConversationTurn] = []

    func loadRecent(limit _: Int) throws -> [ConversationTurn] { [] }
    func append(_ turn: ConversationTurn) throws { appendedTurns.append(turn) }
    func appendIfAbsent(_ turn: ConversationTurn) throws -> Bool {
        guard !appendedTurns.contains(where: { $0.id == turn.id }) else { return false }
        appendedTurns.append(turn)
        return true
    }
    func pruneOldestTurns(keepingMaximum _: Int) throws {}
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
