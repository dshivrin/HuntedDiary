import Foundation
import Testing
@testable import TheHuntedDiary

struct PlainTextHistoryStoreTests {
    @Test func testAppendCreatesOneMarkdownFilePerTurn() throws {
        let fixture = try HistoryStoreFixture()
        let turn = makeTurn(id: "2026-07-08T16-30-00Z-8F3A")

        try fixture.store.append(turn)

        let files = try fixture.markdownFiles()
        #expect(files.map(\.lastPathComponent) == ["2026-07-08T16-30-00Z-8F3A.md"])

        let contents = try String(contentsOf: files[0], encoding: .utf8)
        #expect(contents.contains("id: 2026-07-08T16-30-00Z-8F3A"))
        #expect(contents.contains("createdAt: 2026-07-08T16:30:00Z"))
        #expect(contents.contains("recognition: appleVision"))
        #expect(contents.contains("generationProvider: chatGPTExtensionShortcut"))
        #expect(!contents.contains("model:"))
        #expect(!contents.contains("openAIStoreEnabled:"))
        #expect(contents.contains("\nUser:\nWhat did you write before?\n\nAssistant:\nI remember enough to know you are curious.\n"))
    }

    @Test func testLoadRecentReturnsOldestFirstWithinLimit() throws {
        let fixture = try HistoryStoreFixture()
        try fixture.store.append(makeTurn(id: "old", createdAt: date("2026-07-08T16:00:00Z")))
        try fixture.store.append(makeTurn(id: "newest", createdAt: date("2026-07-08T16:02:00Z")))
        try fixture.store.append(makeTurn(id: "middle", createdAt: date("2026-07-08T16:01:00Z")))

        let turns = try fixture.store.loadRecent(limit: 2)

        #expect(turns.map(\.id) == ["middle", "newest"])
    }

    @Test func testDeleteOneRemovesOnlyMatchingTurn() throws {
        let fixture = try HistoryStoreFixture()
        let kept = makeTurn(id: "kept")
        let removed = makeTurn(id: "removed")
        try fixture.store.append(kept)
        try fixture.store.append(removed)

        try fixture.store.deleteTurn(id: removed.id)

        #expect(try fixture.store.loadAll().map(\.id) == [kept.id])
        #expect(try fixture.markdownFiles().map(\.lastPathComponent) == ["kept.md"])
    }

    @Test func testDeleteAllRemovesAllTurnFiles() throws {
        let fixture = try HistoryStoreFixture()
        try fixture.store.append(makeTurn(id: "one"))
        try fixture.store.append(makeTurn(id: "two"))

        try fixture.store.deleteAll()

        #expect(try fixture.store.loadAll().isEmpty)
        #expect(try fixture.markdownFiles().isEmpty)
    }

    @Test func testPruneOldestTurnsKeepsMaximumStoredTurns() throws {
        let fixture = try HistoryStoreFixture()
        try fixture.store.append(makeTurn(id: "one", createdAt: date("2026-07-08T16:00:00Z")))
        try fixture.store.append(makeTurn(id: "two", createdAt: date("2026-07-08T16:01:00Z")))
        try fixture.store.append(makeTurn(id: "three", createdAt: date("2026-07-08T16:02:00Z")))

        let pruner = HistoryPruner(store: fixture.store)
        try pruner.pruneOldestTurns(keepingMaximum: 2)

        #expect(try fixture.store.loadAll().map(\.id) == ["two", "three"])
        #expect(try fixture.markdownFiles().map(\.lastPathComponent) == ["three.md", "two.md"])
    }

    @Test func testRoundTripPreservesBodyMarkersAndFrontMatterDelimiters() throws {
        let fixture = try HistoryStoreFixture()
        let turn = makeTurn(
            id: "markers",
            userText: """
            First line
            ---
            User:
            Assistant:
            Last line
            """,
            assistantText: """
            The page remembers this:
            ---
            User:
            Assistant:
            """
        )

        try fixture.store.append(turn)
        let loaded = try #require(fixture.store.loadAll().first)

        #expect(loaded.userText == turn.userText)
        #expect(loaded.assistantText == turn.assistantText)
    }

    @Test func testLoadsLegacyRecognitionModelAndStoreFlagWithoutRewritingUserText() throws {
        let fixture = try HistoryStoreFixture()
        let legacyURL = fixture.directoryURL.appendingPathComponent("metadata.md")
        let legacyText = """
        ---
        id: metadata
        createdAt: 2026-07-08T16:30:00Z
        recognition: openAI
        model: gpt-5-mini
        openAIStoreEnabled: true
        ---

        User:
        Original legacy user text.

        Assistant:
        Original legacy reply.
        """ + "\n"
        try legacyText.write(to: legacyURL, atomically: true, encoding: .utf8)
        let loaded = try #require(fixture.store.loadAll().first)

        #expect(loaded.recognitionSource == .openAI)
        #expect(loaded.generationProvider == .legacyOpenAI(model: "gpt-5-mini", storeEnabled: true))
        #expect(loaded.userText == "Original legacy user text.")
        #expect(try String(contentsOf: legacyURL, encoding: .utf8) == legacyText)
    }
}

private struct HistoryStoreFixture {
    let directoryURL: URL
    let store: PlainTextHistoryStore

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlainTextHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        store = PlainTextHistoryStore(directoryURL: directoryURL)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func markdownFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "md" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

private func makeTurn(
    id: String = "2026-07-08T16-30-00Z-8F3A",
    createdAt: Date = date("2026-07-08T16:30:00Z"),
    recognitionSource: RecognitionResult.Source = .appleVision,
    generationProvider: ConversationTurn.GenerationProvider = .chatGPTExtensionShortcut,
    userText: String = "What did you write before?",
    assistantText: String = "I remember enough to know you are curious."
) -> ConversationTurn {
    ConversationTurn(
        id: id,
        createdAt: createdAt,
        recognitionSource: recognitionSource,
        generationProvider: generationProvider,
        userText: userText,
        assistantText: assistantText
    )
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter.history.date(from: value)!
}
