import Foundation
import Testing
@testable import TheHuntedDiary

struct PlainTextHistoryIdempotencyTests {
    @Test func appendIfAbsentUsesStableRequestIdentityAndNeverDuplicatesHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainTextHistoryIdempotency-\(UUID().uuidString)", isDirectory: true)
        let store = PlainTextHistoryStore(directoryURL: directory)
        let requestID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        let turn = ConversationTurn(
            id: requestID.uuidString.lowercased(),
            createdAt: Date(timeIntervalSince1970: 1_800_100_000),
            recognitionSource: .appleVision,
            model: "legacy",
            openAIStoreEnabled: false,
            userText: "One identity.",
            assistantText: "One history turn."
        )

        #expect(try store.appendIfAbsent(turn))
        #expect(try !store.appendIfAbsent(turn))
        #expect(try store.loadAll() == [turn])
    }
}
