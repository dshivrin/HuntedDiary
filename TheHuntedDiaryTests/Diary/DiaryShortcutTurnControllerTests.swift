import CryptoKit
import PencilKit
import Testing
import UIKit
@testable import TheHuntedDiary

@MainActor
struct DiaryShortcutTurnControllerTests {
    private let now = Date(timeIntervalSince1970: 1_800_100_000)
    private let firstID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let secondID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    @Test func submitFreezesPromptAndPersistsDiaryTurnBeforeLaunch() async throws {
        let history = Task8HistoryStore(recentTurns: [Self.priorTurn])
        let fixture = try makeFixture(history: history)

        await fixture.controller.submit(image: Self.makeImage(), now: now)

        let request = try #require(await fixture.store.load(id: firstID))
        #expect(request.kind == .diaryTurn)
        #expect(request.recognizedText == "New ink.")
        #expect(request.prompt.contains("Earlier ink."))
        #expect(request.prompt.contains("Earlier answer."))
        #expect(request.prompt.contains("New ink."))
        #expect(request.state == .readyToLaunch)
        #expect(fixture.launcher.requestsExistedBeforeLaunch == [true])
        #expect(fixture.controller.phase == .awaitingShortcut)
        #expect(history.appendedTurns.isEmpty)
    }

    @Test func retryReusesIDAndFrozenPromptWhileRotatingBothCapabilities() async throws {
        let history = Task8HistoryStore(recentTurns: [Self.priorTurn])
        let recognizer = Task8Recognizer(texts: ["Frozen words."])
        let fixture = try makeFixture(
            history: history,
            recognizer: recognizer,
            launchResults: [.failure(.handoffRejected), .success(())]
        )

        await fixture.controller.submit(image: Self.makeImage(), now: now)
        let original = try #require(await fixture.store.load(id: firstID))
        await fixture.controller.retry(now: now.addingTimeInterval(1))

        let retried = try #require(await fixture.store.load(id: firstID))
        #expect(fixture.launcher.launches.count == 2)
        #expect(try DiaryReplyCapability(handle: fixture.launcher.launches[0].handle).requestID == firstID)
        #expect(try DiaryReplyCapability(handle: fixture.launcher.launches[1].handle).requestID == firstID)
        #expect(fixture.launcher.launches[0].handle != fixture.launcher.launches[1].handle)
        #expect(fixture.launcher.launches[0].callbacks.cancelURL != fixture.launcher.launches[1].callbacks.cancelURL)
        #expect(retried.prompt == original.prompt)
        #expect(retried.recognizedText == original.recognizedText)
        #expect(retried.attemptCount == 2)
        #expect(recognizer.callCount == 1)
        #expect(history.loadRecentCount == 1)
        #expect(history.appendedTurns.isEmpty)
    }

    @Test func repeatedRetryTapsPrepareOnlyOneRetryAttempt() async throws {
        let fixture = try makeFixture(launchResults: [.failure(.handoffRejected), .success(())])
        await fixture.controller.submit(image: Self.makeImage(), now: now)

        async let first: Void = fixture.controller.retry(now: now.addingTimeInterval(1))
        async let second: Void = fixture.controller.retry(now: now.addingTimeInterval(1))
        _ = await (first, second)

        #expect(fixture.launcher.launches.count == 2)
        #expect(try await fixture.store.load(id: firstID)?.attemptCount == 2)
    }

    @Test func completionAppendsPrunesThenMarksHistoryExactlyOnce() async throws {
        let history = Task8HistoryStore()
        let fixture = try makeFixture(history: history)
        await fixture.controller.submit(image: Self.makeImage(), now: now)
        try await Self.complete(fixture.launcher.launches[0], in: fixture.store, text: "Returned ink.", now: now.addingTimeInterval(1))

        await fixture.controller.reconcile(now: now.addingTimeInterval(2))
        let reconstructed = makeController(
            history: history,
            recognizer: Task8Recognizer(),
            store: fixture.store,
            launcher: Task8Launcher(store: fixture.store),
            ids: Task8IDSequence([secondID]),
            capabilities: Task8CapabilitySequence()
        )
        await reconstructed.reconcile(now: now.addingTimeInterval(3))

        #expect(history.events == ["append", "prune"])
        #expect(history.appendedTurns.count == 1)
        #expect(history.appendedTurns[0].id == firstID.uuidString.lowercased())
        #expect(history.appendedTurns[0].userText == "New ink.")
        #expect(history.appendedTurns[0].assistantText == "Returned ink.")
        #expect(try await fixture.store.load(id: firstID)?.state == .historyCommitted)
        #expect(fixture.controller.replyText == "Returned ink.")
        #expect(fixture.controller.phase == .completed)
    }

    @Test func historyFailureLeavesReplyStoredForRelaunchRecovery() async throws {
        let history = Task8HistoryStore(appendFailuresRemaining: 1)
        let fixture = try makeFixture(history: history)
        await fixture.controller.submit(image: Self.makeImage(), now: now)
        try await Self.complete(fixture.launcher.launches[0], in: fixture.store, text: "Durable reply.", now: now.addingTimeInterval(1))

        await fixture.controller.reconcile(now: now.addingTimeInterval(2))
        #expect(try await fixture.store.load(id: firstID)?.state == .replyStored)
        #expect(fixture.controller.historyWriteError == .historyWriteFailed)

        let reconstructed = makeController(
            history: history,
            recognizer: Task8Recognizer(),
            store: fixture.store,
            launcher: Task8Launcher(store: fixture.store),
            ids: Task8IDSequence([secondID]),
            capabilities: Task8CapabilitySequence()
        )
        await reconstructed.reconcile(now: now.addingTimeInterval(3))

        #expect(history.appendedTurns.count == 1)
        #expect(try await fixture.store.load(id: firstID)?.state == .historyCommitted)
    }

    @Test func appendBeforePruneFailureIsIdempotentAfterReconstruction() async throws {
        let history = Task8HistoryStore(pruneFailuresRemaining: 1)
        let fixture = try makeFixture(history: history)
        await fixture.controller.submit(image: Self.makeImage(), now: now)
        try await Self.complete(fixture.launcher.launches[0], in: fixture.store, text: "One reply.", now: now.addingTimeInterval(1))

        await fixture.controller.reconcile(now: now.addingTimeInterval(2))
        #expect(history.appendedTurns.count == 1)
        #expect(try await fixture.store.load(id: firstID)?.state == .replyStored)

        let reconstructed = makeController(
            history: history,
            recognizer: Task8Recognizer(),
            store: fixture.store,
            launcher: Task8Launcher(store: fixture.store),
            ids: Task8IDSequence([secondID]),
            capabilities: Task8CapabilitySequence()
        )
        await reconstructed.reconcile(now: now.addingTimeInterval(3))

        #expect(history.appendedTurns.count == 1)
        #expect(history.events == ["append", "prune", "appendExisting", "prune"])
        #expect(try await fixture.store.load(id: firstID)?.state == .historyCommitted)
    }

    @Test func historyRecoveryRetryReconcilesTheAlreadyDurableReply() async throws {
        let history = Task8HistoryStore(appendFailuresRemaining: 1)
        let fixture = try makeFixture(history: history)
        await fixture.controller.submit(image: Self.makeImage(), now: now)
        try await Self.complete(fixture.launcher.launches[0], in: fixture.store, text: "Retry history.", now: now.addingTimeInterval(1))
        await fixture.controller.reconcile(now: now.addingTimeInterval(2))

        #expect(fixture.controller.historyWriteError == .historyWriteFailed)
        await fixture.controller.retry(now: now.addingTimeInterval(3))

        #expect(fixture.controller.historyWriteError == nil)
        #expect(history.appendedTurns.count == 1)
        #expect(try await fixture.store.load(id: firstID)?.state == .historyCommitted)
    }

    @Test func reconciliationProcessesTwoOutstandingTurnsAndLateOldCompletion() async throws {
        let history = Task8HistoryStore()
        let recognizer = Task8Recognizer(texts: ["Old words.", "New words."])
        let fixture = try makeFixture(history: history, recognizer: recognizer, ids: [firstID, secondID])
        await fixture.controller.submit(image: Self.makeImage(), now: now)
        await fixture.controller.submit(image: Self.makeImage(), now: now.addingTimeInterval(1))

        try await Self.complete(fixture.launcher.launches[0], in: fixture.store, text: "Old reply.", now: now.addingTimeInterval(2))
        await fixture.controller.reconcile(now: now.addingTimeInterval(3))
        #expect(history.appendedTurns.map(\.id) == [firstID.uuidString.lowercased()])
        #expect(fixture.controller.phase == .awaitingShortcut)
        #expect(fixture.controller.replyText.isEmpty)

        try await Self.complete(fixture.launcher.launches[1], in: fixture.store, text: "New reply.", now: now.addingTimeInterval(4))
        await fixture.controller.reconcile(now: now.addingTimeInterval(5))

        #expect(history.appendedTurns.map(\.id) == [firstID, secondID].map { $0.uuidString.lowercased() })
        #expect(fixture.controller.replyText == "New reply.")
        #expect(fixture.controller.phase == .completed)
    }

    @Test func setupProbeNeverEntersDiaryHistoryReconciliation() async throws {
        let history = Task8HistoryStore()
        let fixture = try makeFixture(history: history)
        let capability = try DiaryReplyCapability.generate(requestID: firstID)
        let callback = try DiaryReplyCapability.generate(requestID: firstID)
        try await fixture.store.create(Self.request(
            id: firstID,
            kind: .setupProbe,
            capability: capability,
            callback: callback,
            state: .replyStored,
            assistantText: "setup complete",
            now: now
        ))

        await fixture.controller.reconcile(now: now.addingTimeInterval(1))

        #expect(history.appendedTurns.isEmpty)
        #expect(try await fixture.store.load(id: firstID)?.state == .replyStored)
    }

    @Test func cancellationRacingCompletionStillProducesAtMostOneFinalHistoryTurn() async throws {
        let history = Task8HistoryStore()
        let fixture = try makeFixture(history: history)
        let flow = DiaryReplyFlow(store: fixture.store)
        await fixture.controller.submit(image: Self.makeImage(), now: now)
        let launch = fixture.launcher.launches[0]
        let authorization = try DiaryReplyCapability(handle: launch.handle)

        async let cancellation = flow.handle(launch.callbacks.cancelURL, now: now.addingTimeInterval(1))
        async let completion: Void = Self.storeReplyIgnoringRaceLoss(
            id: authorization.requestID,
            capability: authorization.capability,
            store: fixture.store,
            text: "Racing reply.",
            now: now.addingTimeInterval(1)
        )
        _ = await (cancellation, completion)

        await fixture.controller.reconcile(now: now.addingTimeInterval(2))
        if try await fixture.store.load(id: firstID)?.state == .cancelled {
            await fixture.controller.retry(now: now.addingTimeInterval(3))
            try await Self.complete(
                fixture.launcher.launches[1],
                in: fixture.store,
                text: "Racing reply.",
                now: now.addingTimeInterval(4)
            )
            await fixture.controller.reconcile(now: now.addingTimeInterval(5))
        }

        await fixture.controller.reconcile(now: now.addingTimeInterval(6))
        #expect(history.appendedTurns.count == 1)
        #expect(history.appendedTurns.first?.id == firstID.uuidString.lowercased())
        #expect(try await fixture.store.load(id: firstID)?.state == .historyCommitted)
    }

    @Test func suspendedOldLaunchFailureCannotOverwriteNewSubmissionPhase() async throws {
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("SuspendedDiaryLaunch-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let launcher = SuspendingFirstTask8Launcher(store: store)
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: Task8HistoryStore(),
            recognizer: Task8Recognizer(texts: ["Old submission.", "New submission."]),
            pendingStore: store,
            launcher: launcher,
            requestID: Task8IDSequence([firstID, secondID]).next,
            capabilities: Task8CapabilitySequence().next
        )
        let oldSubmission = Task {
            await controller.submit(image: Self.makeImage(), now: now)
        }
        try await Self.waitUntil { launcher.hasSuspendedFirstLaunch }

        await controller.submit(image: Self.makeImage(), now: now.addingTimeInterval(1))
        #expect(controller.activeRequestID == secondID)
        #expect(controller.phase == .awaitingShortcut)
        launcher.failFirstLaunch()
        await oldSubmission.value

        #expect(controller.activeRequestID == secondID)
        #expect(controller.recognizedText == "New submission.")
        #expect(controller.phase == .awaitingShortcut)
        #expect(try await store.load(id: firstID)?.state == .failed)
    }

    @Test func supersededSubmissionSuspendedDuringCreateIsPersistedButNeverLaunched() async throws {
        let gate = SuspendingFirstTask8PersistenceGate()
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("SuspendedDiaryCreate-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence(
                beforeWrite: { await gate.beforeWrite() },
                write: { _, _ in }
            )
        )
        let launcher = Task8Launcher(store: store, results: [.success(())])
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: Task8HistoryStore(),
            recognizer: Task8Recognizer(texts: ["Old submission.", "New submission."]),
            pendingStore: store,
            launcher: launcher,
            requestID: Task8IDSequence([firstID, secondID]).next,
            capabilities: Task8CapabilitySequence().next
        )

        let oldSubmission = Task {
            await controller.submit(image: Self.makeImage(), now: now)
        }
        await gate.waitUntilSuspended()
        let newSubmission = Task {
            await controller.submit(image: Self.makeImage(), now: now.addingTimeInterval(1))
        }
        try await Self.waitUntil { controller.recognizedText == "New submission." }
        await gate.releaseFirstWrite()
        await oldSubmission.value
        await newSubmission.value

        #expect(launcher.launches.count == 1)
        #expect(try DiaryReplyCapability(handle: launcher.launches[0].handle).requestID == secondID)
        #expect(try await store.load(id: firstID)?.launchAcceptedAt == nil)
        #expect(controller.activeRequestID == secondID)
        #expect(controller.phase == .awaitingShortcut)
    }

    @Test func reconstructedPreHandoffRequestRetriesSameIdentityAndFrozenPrompt() async throws {
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("PreHandoffDiary-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let original = Self.pendingDiaryRequest(id: firstID, now: now)
        try await store.create(original)
        let launcher = Task8Launcher(store: store)
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: Task8HistoryStore(),
            recognizer: Task8Recognizer(),
            pendingStore: store,
            launcher: launcher,
            requestID: Task8IDSequence([secondID]).next,
            capabilities: Task8CapabilitySequence().next
        )

        await controller.reconcile(now: now.addingTimeInterval(1))
        #expect(controller.activeRequestID == firstID)
        #expect(controller.phase == .failed(DiaryTurnFailure(stage: .shortcut, error: .shortcutReplyFailed)))
        await controller.retry(now: now.addingTimeInterval(2))

        let retried = try #require(await store.load(id: firstID))
        #expect(launcher.launches.count == 1)
        #expect(try DiaryReplyCapability(handle: launcher.launches[0].handle).requestID == firstID)
        #expect(retried.prompt == original.prompt)
        #expect(retried.recognizedText == original.recognizedText)
        #expect(retried.attemptCount == 2)
        #expect(retried.launchAcceptedAt != nil)
    }

    @Test func reconstructedAcceptedRequestWaitsAndExplicitRetryKeepsIdentity() async throws {
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AcceptedDiary-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        try await store.create(Self.pendingDiaryRequest(id: firstID, now: now))
        try await store.markLaunchAccepted(id: firstID, now: now.addingTimeInterval(1))
        let launcher = Task8Launcher(store: store)
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: Task8HistoryStore(),
            recognizer: Task8Recognizer(),
            pendingStore: store,
            launcher: launcher,
            requestID: Task8IDSequence([secondID]).next,
            capabilities: Task8CapabilitySequence().next
        )

        await controller.reconcile(now: now.addingTimeInterval(2))
        #expect(controller.activeRequestID == firstID)
        #expect(controller.phase == .awaitingShortcut)
        #expect(launcher.launches.isEmpty)

        await controller.retry(now: now.addingTimeInterval(3))
        #expect(launcher.launches.isEmpty)
        #expect(try await store.load(id: firstID)?.attemptCount == 1)
        #expect(controller.phase == .awaitingShortcut)
    }

    @Test func markHistoryCommitFailureReconstructsWithoutDuplicateAppend() async throws {
        let gate = Task8PersistenceGate(failingWrite: 4)
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("MarkHistoryFailure-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence(
                beforeWrite: { try await gate.beforeWrite() },
                write: { _, _ in }
            )
        )
        let history = Task8HistoryStore()
        let launcher = Task8Launcher(store: store)
        let first = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: history,
            recognizer: Task8Recognizer(),
            pendingStore: store,
            launcher: launcher,
            requestID: Task8IDSequence([firstID]).next,
            capabilities: Task8CapabilitySequence().next
        )
        await first.submit(image: Self.makeImage(), now: now)
        try await Self.complete(launcher.launches[0], in: store, text: "Committed once.", now: now.addingTimeInterval(1))
        await first.reconcile(now: now.addingTimeInterval(2))

        #expect(history.appendedTurns.count == 1)
        #expect(try await store.load(id: firstID)?.state == .replyStored)
        let reconstructed = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: history,
            recognizer: Task8Recognizer(),
            pendingStore: store,
            launcher: Task8Launcher(store: store),
            requestID: Task8IDSequence([secondID]).next,
            capabilities: Task8CapabilitySequence().next
        )
        await reconstructed.reconcile(now: now.addingTimeInterval(3))

        #expect(history.appendedTurns.count == 1)
        #expect(try await store.load(id: firstID)?.state == .historyCommitted)
    }

    @Test func retryAfterMarkFailedPersistenceFailureAdoptsRotatedCapabilitiesBeforeLaunch() async throws {
        let gate = Task8PersistenceGate(failingWrite: 2)
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("MarkFailedFailure-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence(
                beforeWrite: { try await gate.beforeWrite() },
                write: { _, _ in }
            )
        )
        let launcher = Task8Launcher(
            store: store,
            results: [.failure(.handoffRejected), .success(())]
        )
        let controller = DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: Task8HistoryStore(),
            recognizer: Task8Recognizer(),
            pendingStore: store,
            launcher: launcher,
            requestID: Task8IDSequence([firstID]).next,
            capabilities: Task8CapabilitySequence().next
        )

        await controller.submit(image: Self.makeImage(), now: now)
        #expect(try await store.load(id: firstID)?.state == .readyToLaunch)
        await controller.retry(now: now.addingTimeInterval(1))

        let retried = try #require(await store.load(id: firstID))
        let launchedRequest = try DiaryReplyCapability(handle: launcher.launches[1].handle)
        #expect(retried.attemptCount == 2)
        #expect(retried.capabilityDigest == launchedRequest.capabilityDigest)
        #expect(retried.callbackCapabilityDigest == launcher.launches[1].callbacks.callbackCapabilityDigest)
        #expect(retried.launchAcceptedAt != nil)
        #expect(controller.phase == .awaitingShortcut)
    }

    @Test func canvasDrawingRemainsUnchangedAcrossLaunchFailureRetryAndCompletion() async throws {
        let fixture = try makeFixture(launchResults: [.failure(.handoffRejected), .success(())])
        let model = PencilCanvasModel(drawing: Self.makeDrawing())
        let original = model.drawing.dataRepresentation()

        await fixture.controller.submit(image: model.exportImage(canvasSize: CGSize(width: 300, height: 400)), now: now)
        #expect(model.drawing.dataRepresentation() == original)
        await fixture.controller.retry(now: now.addingTimeInterval(1))
        #expect(model.drawing.dataRepresentation() == original)
        try await Self.complete(fixture.launcher.launches[1], in: fixture.store, text: "Still mounted.", now: now.addingTimeInterval(2))
        await fixture.controller.reconcile(now: now.addingTimeInterval(3))

        #expect(model.drawing.dataRepresentation() == original)
        #expect(fixture.controller.replyText == "Still mounted.")
    }

    private func makeFixture(
        history: Task8HistoryStore? = nil,
        recognizer: Task8Recognizer? = nil,
        launchResults: [Result<Void, ShortcutReplyLauncherError>] = [.success(())],
        ids: [UUID]? = nil
    ) throws -> Task8Fixture {
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("DiaryShortcutTurn-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let launcher = Task8Launcher(store: store, results: launchResults)
        let idSequence = Task8IDSequence(ids ?? [firstID])
        let capabilitySequence = Task8CapabilitySequence()
        let resolvedHistory = history ?? Task8HistoryStore()
        let resolvedRecognizer = recognizer ?? Task8Recognizer()
        return Task8Fixture(
            controller: makeController(
                history: resolvedHistory,
                recognizer: resolvedRecognizer,
                store: store,
                launcher: launcher,
                ids: idSequence,
                capabilities: capabilitySequence
            ),
            store: store,
            launcher: launcher
        )
    }

    private func makeController(
        history: Task8HistoryStore,
        recognizer: Task8Recognizer,
        store: PendingDiaryReplyStore,
        launcher: Task8Launcher,
        ids: Task8IDSequence,
        capabilities: Task8CapabilitySequence
    ) -> DiaryTurnController {
        DiaryTurnController(
            settingsProvider: { AppSettings() },
            historyStore: history,
            recognizer: recognizer,
            pendingStore: store,
            launcher: launcher,
            requestID: ids.next,
            capabilities: capabilities.next
        )
    }

    private static func complete(
        _ launch: Task8Launcher.Launch,
        in store: PendingDiaryReplyStore,
        text: String,
        now: Date
    ) async throws {
        let authorization = try DiaryReplyCapability(handle: launch.handle)
        try await store.storeReply(id: authorization.requestID, capability: authorization.capability, text: text, now: now)
    }

    private static func storeReplyIgnoringRaceLoss(
        id: UUID,
        capability: Data,
        store: PendingDiaryReplyStore,
        text: String,
        now: Date
    ) async {
        try? await store.storeReply(id: id, capability: capability, text: text, now: now)
    }

    private static func request(
        id: UUID,
        kind: DiaryReplyRequestKind,
        capability: DiaryReplyCapability,
        callback: DiaryReplyCapability,
        state: DiaryReplyRequestState,
        assistantText: String?,
        now: Date
    ) -> PendingDiaryReply {
        PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: kind,
            capabilityDigest: capability.capabilityDigest,
            callbackCapabilityDigest: callback.capabilityDigest,
            recognizedText: "",
            recognitionSource: .appleVision,
            prompt: "setup",
            createdAt: now,
            expiresAt: now.addingTimeInterval(600),
            updatedAt: now,
            state: state,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: assistantText,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        )
    }

    private static func pendingDiaryRequest(id: UUID, now: Date) -> PendingDiaryReply {
        PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: .diaryTurn,
            capabilityDigest: Data(repeating: 0x51, count: 32),
            callbackCapabilityDigest: Data(repeating: 0x52, count: 32),
            recognizedText: "Persisted recognized words.",
            recognitionSource: .appleVision,
            prompt: "Persisted frozen prompt.",
            createdAt: now,
            expiresAt: now.addingTimeInterval(3_600),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        )
    }

    private static func waitUntil(
        timeout: Duration = .seconds(2),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else { throw Task8Error.timeout }
            await Task.yield()
        }
    }

    private static var priorTurn: ConversationTurn {
        ConversationTurn(
            id: "prior",
            createdAt: Date(timeIntervalSince1970: 1),
            recognitionSource: .appleVision,
            model: "legacy",
            openAIStoreEnabled: false,
            userText: "Earlier ink.",
            assistantText: "Earlier answer."
        )
    }

    private static func makeImage() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    private static func makeDrawing() -> PKDrawing {
        let points = [
            PKStrokePoint(location: CGPoint(x: 10, y: 10), timeOffset: 0, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
            PKStrokePoint(location: CGPoint(x: 40, y: 40), timeOffset: 0.1, size: CGSize(width: 4, height: 4), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2),
        ]
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
    }
}

@MainActor
private struct Task8Fixture {
    let controller: DiaryTurnController
    let store: PendingDiaryReplyStore
    let launcher: Task8Launcher
}

@MainActor
private final class Task8HistoryStore: IdempotentDiaryHistoryStoring {
    var recentTurns: [ConversationTurn]
    var appendedTurns: [ConversationTurn] = []
    var events: [String] = []
    var appendFailuresRemaining: Int
    var pruneFailuresRemaining: Int
    private(set) var loadRecentCount = 0

    init(recentTurns: [ConversationTurn] = [], appendFailuresRemaining: Int = 0, pruneFailuresRemaining: Int = 0) {
        self.recentTurns = recentTurns
        self.appendFailuresRemaining = appendFailuresRemaining
        self.pruneFailuresRemaining = pruneFailuresRemaining
    }

    func loadRecent(limit _: Int) throws -> [ConversationTurn] {
        loadRecentCount += 1
        return recentTurns
    }

    func append(_ turn: ConversationTurn) throws {
        _ = try appendIfAbsent(turn)
    }

    func appendIfAbsent(_ turn: ConversationTurn) throws -> Bool {
        if appendedTurns.contains(where: { $0.id == turn.id }) {
            events.append("appendExisting")
            return false
        }
        events.append("append")
        if appendFailuresRemaining > 0 {
            appendFailuresRemaining -= 1
            throw Task8Error.history
        }
        appendedTurns.append(turn)
        return true
    }

    func pruneOldestTurns(keepingMaximum _: Int) throws {
        events.append("prune")
        if pruneFailuresRemaining > 0 {
            pruneFailuresRemaining -= 1
            throw Task8Error.history
        }
    }
}

@MainActor
private final class Task8Recognizer: HandwritingRecognizer {
    private var texts: [String]
    private(set) var callCount = 0

    init(texts: [String] = ["New ink."]) {
        self.texts = texts
    }

    func recognize(image _: UIImage) async throws -> RecognitionResult {
        callCount += 1
        return RecognitionResult(text: texts.removeFirst(), confidence: 0.9, source: .appleVision)
    }
}

@MainActor
private final class Task8Launcher: ShortcutReplyLaunching {
    struct Launch {
        let shortcutName: String
        let handle: String
        let callbacks: ShortcutCallbacks
    }

    let store: PendingDiaryReplyStore
    var results: [Result<Void, ShortcutReplyLauncherError>]
    private(set) var launches: [Launch] = []
    private(set) var requestsExistedBeforeLaunch: [Bool] = []

    init(store: PendingDiaryReplyStore, results: [Result<Void, ShortcutReplyLauncherError>] = [.success(())]) {
        self.store = store
        self.results = results
    }

    func launch(shortcutName: String, handle: String, callbacks: ShortcutCallbacks) async throws {
        let id = try DiaryReplyCapability(handle: handle).requestID
        requestsExistedBeforeLaunch.append((try? await store.load(id: id)) != nil)
        launches.append(Launch(shortcutName: shortcutName, handle: handle, callbacks: callbacks))
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
    }
}

@MainActor
private final class SuspendingFirstTask8Launcher: ShortcutReplyLaunching {
    let store: PendingDiaryReplyStore
    private var continuation: CheckedContinuation<Void, Error>?
    private(set) var hasSuspendedFirstLaunch = false
    private var launchCount = 0

    init(store: PendingDiaryReplyStore) {
        self.store = store
    }

    func launch(shortcutName _: String, handle: String, callbacks _: ShortcutCallbacks) async throws {
        launchCount += 1
        let id = try DiaryReplyCapability(handle: handle).requestID
        _ = try await store.load(id: id)
        guard launchCount == 1 else { return }
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            hasSuspendedFirstLaunch = true
        }
    }

    func failFirstLaunch() {
        continuation?.resume(throwing: ShortcutReplyLauncherError.handoffRejected)
        continuation = nil
    }
}

private actor Task8PersistenceGate {
    let failingWrite: Int
    private var writeCount = 0

    init(failingWrite: Int) {
        self.failingWrite = failingWrite
    }

    func beforeWrite() throws {
        writeCount += 1
        if writeCount == failingWrite { throw Task8Error.persistence }
    }
}

private actor SuspendingFirstTask8PersistenceGate {
    private var hasSuspended = false
    private var suspensionWaiters: [CheckedContinuation<Void, Never>] = []
    private var writeContinuation: CheckedContinuation<Void, Never>?

    func beforeWrite() async {
        guard !hasSuspended else { return }
        hasSuspended = true
        suspensionWaiters.forEach { $0.resume() }
        suspensionWaiters.removeAll()
        await withCheckedContinuation { writeContinuation = $0 }
    }

    func waitUntilSuspended() async {
        guard !hasSuspended else { return }
        await withCheckedContinuation { suspensionWaiters.append($0) }
    }

    func releaseFirstWrite() {
        writeContinuation?.resume()
        writeContinuation = nil
    }
}

@MainActor
private final class Task8IDSequence {
    private var values: [UUID]
    init(_ values: [UUID]) { self.values = values }
    func next() -> UUID { values.removeFirst() }
}

@MainActor
private final class Task8CapabilitySequence {
    private var index: UInt8 = 0
    func next(_ id: UUID) throws -> ShortcutSetupCapabilities {
        index &+= 1
        return try ShortcutSetupCapabilities(
            requestID: id,
            requestCapability: Data(repeating: index, count: 32),
            callbackCapability: Data(repeating: index &+ 64, count: 32)
        )
    }
}

private enum Task8Error: Error { case history, persistence, timeout }
