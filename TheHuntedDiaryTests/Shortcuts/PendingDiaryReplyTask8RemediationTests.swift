import Foundation
import Testing
@testable import TheHuntedDiary

struct PendingDiaryReplyTask8RemediationTests {
    private let now = Date(timeIntervalSince1970: 1_800_200_000)
    private let id = UUID(uuidString: "30000000-0000-0000-0000-000000000003")!

    @Test func readyDiaryRetryAtomicallyAdoptsBothRotatedCapabilities() async throws {
        let store = try makeStore()
        try await store.create(request())
        let requestDigest = Data(repeating: 0x31, count: 32)
        let callbackDigest = Data(repeating: 0x32, count: 32)

        let retried = try await store.prepareRetry(
            id: id,
            capabilityDigest: requestDigest,
            callbackCapabilityDigest: callbackDigest,
            now: now.addingTimeInterval(1)
        )

        #expect(retried.capabilityDigest == requestDigest)
        #expect(retried.callbackCapabilityDigest == callbackDigest)
        #expect(retried.attemptCount == 2)
        #expect(try await store.load(id: id) == retried)
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
