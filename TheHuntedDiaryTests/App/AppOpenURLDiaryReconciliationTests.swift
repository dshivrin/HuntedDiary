import Foundation
import Testing
@testable import TheHuntedDiary

@MainActor
struct AppOpenURLDiaryReconciliationTests {
    @Test func authenticatedCallbackMutationPrecedesRegisteredDiaryReconciliation() async throws {
        let now = Date(timeIntervalSince1970: 1_800_200_000)
        let id = UUID(uuidString: "40000000-0000-0000-0000-000000000004")!
        let requestCapability = try DiaryReplyCapability.generate(requestID: id)
        let callbackCapability = try DiaryReplyCapability.generate(requestID: id)
        let callbacks = try ShortcutCallbacks(
            requestID: id,
            callbackCapability: callbackCapability.capability
        )
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("AppOpenURLDiary-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        try await store.create(PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: .diaryTurn,
            capabilityDigest: requestCapability.capabilityDigest,
            callbackCapabilityDigest: callbackCapability.capabilityDigest,
            recognizedText: "callback words",
            recognitionSource: .appleVision,
            prompt: "callback prompt",
            createdAt: now,
            expiresAt: now.addingTimeInterval(600),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        ))
        let dependencies = DependencyContainer(
            pendingDiaryReplyStore: store,
            diaryReplyFlow: DiaryReplyFlow(store: store)
        )
        let reconciler = CallbackOrderingReconciler(store: store, id: id)
        dependencies.registerDiaryReplyReconciler(reconciler)

        await dependencies.handleOpenURL(callbacks.cancelURL, now: now.addingTimeInterval(1))

        #expect(reconciler.statesObservedAtReconciliation == [.cancelled])
    }
}

@MainActor
private final class CallbackOrderingReconciler: DiaryReplyReconciling {
    let store: PendingDiaryReplyStore
    let id: UUID
    private(set) var statesObservedAtReconciliation: [DiaryReplyRequestState] = []

    init(store: PendingDiaryReplyStore, id: UUID) {
        self.store = store
        self.id = id
    }

    func reconcile(now _: Date) async {
        if let state = try? await store.load(id: id)?.state {
            statesObservedAtReconciliation.append(state)
        }
    }
}
