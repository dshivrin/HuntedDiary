import Foundation
import Testing
@testable import TheHuntedDiary

struct PendingDiaryReplyTask8RemediationTests {
    private let now = Date(timeIntervalSince1970: 1_800_200_000)
    private let id = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    @Test func strandedReadyDiaryRecoveryAtomicallyAdoptsBothRotatedCapabilities() async throws {
        let store = try makeStore()
        try await store.create(request())
        let requestDigest = Data(repeating: 0x31, count: 32)
        let callbackDigest = Data(repeating: 0x32, count: 32)

        let retried = try await store.recoverDiaryLaunch(
            id: id,
            expectedAttemptCount: 1,
            capabilityDigest: requestDigest,
            callbackCapabilityDigest: callbackDigest,
            now: now.addingTimeInterval(1)
        )

        #expect(retried.capabilityDigest == requestDigest)
        #expect(retried.callbackCapabilityDigest == callbackDigest)
        #expect(retried.attemptCount == 2)
        #expect(try await store.load(id: id) == retried)
    }

    @Test func concurrentDistinctTimeRecoveryPreparesExactlyOneAttempt() async throws {
        let store = try makeStore()
        try await store.create(request())

        async let first = store.recoverDiaryLaunch(
            id: id,
            expectedAttemptCount: 1,
            capabilityDigest: Data(repeating: 0x31, count: 32),
            callbackCapabilityDigest: Data(repeating: 0x32, count: 32),
            now: now.addingTimeInterval(1)
        )
        async let second = store.recoverDiaryLaunch(
            id: id,
            expectedAttemptCount: 1,
            capabilityDigest: Data(repeating: 0x41, count: 32),
            callbackCapabilityDigest: Data(repeating: 0x42, count: 32),
            now: now.addingTimeInterval(2)
        )
        let recovered = try await [first, second]

        #expect(recovered[0] == recovered[1])
        #expect(recovered[0].attemptCount == 2)
        #expect(try await store.load(id: id) == recovered[0])
    }

    @Test func acceptedAwaitingRequestCannotBeRotatedByEitherRetryPath() async throws {
        let store = try makeStore()
        var awaiting = request()
        awaiting.state = .awaitingShortcut
        awaiting.launchAcceptedAt = now.addingTimeInterval(1)
        awaiting.updatedAt = now.addingTimeInterval(1)
        try await store.create(awaiting)

        let prepared = try await store.prepareRetry(
            id: id,
            capabilityDigest: Data(repeating: 0x31, count: 32),
            callbackCapabilityDigest: Data(repeating: 0x32, count: 32),
            now: now.addingTimeInterval(2)
        )
        #expect(prepared == awaiting)
        await #expect(throws: PendingDiaryReplyStore.StoreError.self) {
            _ = try await store.recoverDiaryLaunch(
                id: id,
                expectedAttemptCount: 1,
                capabilityDigest: Data(repeating: 0x41, count: 32),
                callbackCapabilityDigest: Data(repeating: 0x42, count: 32),
                now: now.addingTimeInterval(3)
            )
        }
        #expect(try await store.load(id: id) == awaiting)
    }

    @Test func acceptedLaunchAndLatestActiveDiaryRequestAreDurableStoreFacts() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingDiaryTask8-\(UUID().uuidString).json")
        let store = try PendingDiaryReplyStore(fileURL: fileURL)
        try await store.create(request())
        try await store.markLaunchAccepted(id: id, now: now.addingTimeInterval(1))

        let reconstructed = try PendingDiaryReplyStore(fileURL: fileURL)
        let active = try await reconstructed.latestActiveDiaryRequest(now: now.addingTimeInterval(2))

        #expect(active?.id == id)
        #expect(active?.launchAcceptedAt == now.addingTimeInterval(1))
        #expect(active?.prompt == "frozen diary prompt")
    }

    private func makeStore() throws -> PendingDiaryReplyStore {
        try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("PendingDiaryTask8-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
    }

    private func request() -> PendingDiaryReply {
        PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: .diaryTurn,
            capabilityDigest: Data(repeating: 0x11, count: 32),
            callbackCapabilityDigest: Data(repeating: 0x12, count: 32),
            recognizedText: "durable words",
            recognitionSource: .appleVision,
            prompt: "frozen diary prompt",
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
}
