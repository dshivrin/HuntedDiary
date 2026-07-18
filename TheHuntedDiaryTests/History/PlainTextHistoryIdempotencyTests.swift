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

    @Test func appendIfAbsentRejectsConflictingContentForAnExistingRequestIdentity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainTextHistoryConflict-\(UUID().uuidString)", isDirectory: true)
        let store = PlainTextHistoryStore(directoryURL: directory)
        let original = Self.turn(assistantText: "Original reply.")
        let conflicting = Self.turn(assistantText: "Conflicting reply.")
        #expect(try store.appendIfAbsent(original))

        #expect(throws: DiaryHistoryIdempotencyError.conflictingTurn(original.id)) {
            try store.appendIfAbsent(conflicting)
        }
        #expect(try store.loadAll() == [original])
    }

    @Test func appendIfAbsentMatchesFractionalTimestampAfterCrashBoundaryReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainTextHistoryFractional-\(UUID().uuidString)", isDirectory: true)
        let store = PlainTextHistoryStore(directoryURL: directory)
        var turn = Self.turn(assistantText: "Exactly once after reload.")
        turn.createdAt = Date(timeIntervalSince1970: 1_800_100_000.987_654)

        #expect(try store.appendIfAbsent(turn))
        let reconstructed = PlainTextHistoryStore(directoryURL: directory)
        #expect(try !reconstructed.appendIfAbsent(turn))
        #expect(try reconstructed.loadAll().count == 1)
    }

    private static func turn(assistantText: String) -> ConversationTurn {
        ConversationTurn(
            id: "10000000-0000-0000-0000-000000000001",
            createdAt: Date(timeIntervalSince1970: 1_800_100_000),
            recognitionSource: .appleVision,
            model: "legacy",
            openAIStoreEnabled: false,
            userText: "Same request.",
            assistantText: assistantText
        )
    }
}
