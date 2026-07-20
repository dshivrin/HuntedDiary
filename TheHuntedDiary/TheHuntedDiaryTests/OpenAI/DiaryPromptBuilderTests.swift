import Foundation
import Testing
@testable import TheHuntedDiary

struct DiaryPromptBuilderTests {
    @Test func testIncludesTomRiddleDiaryInstructions() {
        let prompt = DiaryPromptBuilder().buildPrompt(
            recentTurns: [],
            currentUserText: "Are you there?",
            settings: AppSettings()
        )

        #expect(prompt.instructions.contains("Tom Riddle's spirit"))
        #expect(prompt.instructions.contains("Harry Potter books"))
        #expect(prompt.instructions.contains("haunted diary"))
        #expect(prompt.instructions.contains("ink is waking"))
    }

    @Test func testIncludesCopyrightAndAffiliationGuardrails() {
        let prompt = DiaryPromptBuilder().buildPrompt(
            recentTurns: [],
            currentUserText: "Tell me a secret.",
            settings: AppSettings()
        )

        #expect(prompt.instructions.contains("Do not quote from the books"))
        #expect(prompt.instructions.contains("reproduce scenes, spells, dialogue, or plot passages"))
        #expect(prompt.instructions.contains("Do not claim this app is official, licensed, endorsed, or affiliated"))
    }

    @Test func testRecentTurnsAreIncludedOldestFirst() {
        let prompt = DiaryPromptBuilder().buildPrompt(
            recentTurns: [
                makeTurn(id: "old", createdAt: date("2026-07-08T16:00:00Z"), userText: "Old question", assistantText: "Old answer"),
                makeTurn(id: "new", createdAt: date("2026-07-08T16:01:00Z"), userText: "New question", assistantText: "New answer")
            ],
            currentUserText: "Current question",
            settings: AppSettings()
        )

        #expect(prompt.inputMessages.map(\.role) == [.user, .assistant, .user, .assistant, .user])
        #expect(prompt.inputMessages.map(\.content) == [
            "Old question",
            "Old answer",
            "New question",
            "New answer",
            "Current question"
        ])
    }

    @Test func testCurrentRecognizedTextIsLastUserInput() throws {
        let prompt = DiaryPromptBuilder().buildPrompt(
            recentTurns: [
                makeTurn(userText: "Earlier question", assistantText: "Earlier answer")
            ],
            currentUserText: "The newest handwriting",
            settings: AppSettings()
        )

        let lastMessage = try #require(prompt.inputMessages.last)
        #expect(lastMessage.role == .user)
        #expect(lastMessage.content == "The newest handwriting")
    }

    @Test func testPromptIsEnglishOnlyForMVP() {
        let prompt = DiaryPromptBuilder().buildPrompt(
            recentTurns: [],
            currentUserText: "Answer in English.",
            settings: AppSettings()
        )

        #expect(prompt.instructions.contains("Reply in English"))
    }

    @Test func testPromptDoesNotContainImageData() {
        let prompt = DiaryPromptBuilder().buildPrompt(
            recentTurns: [
                makeTurn(userText: "Plain text only", assistantText: "No drawings here")
            ],
            currentUserText: "Still text",
            settings: AppSettings()
        )

        let combinedText = ([prompt.instructions] + prompt.inputMessages.map(\.content)).joined(separator: "\n")
        #expect(!combinedText.contains("data:image"))
        #expect(!combinedText.contains("base64"))
    }
}

private func makeTurn(
    id: String = "2026-07-08T16-30-00Z-8F3A",
    createdAt: Date = date("2026-07-08T16:30:00Z"),
    recognitionSource: RecognitionResult.Source = .appleVision,
    model: String = "gpt-5.5",
    openAIStoreEnabled: Bool = false,
    userText: String = "What did you write before?",
    assistantText: String = "I remember enough to know you are curious."
) -> ConversationTurn {
    ConversationTurn(
        id: id,
        createdAt: createdAt,
        recognitionSource: recognitionSource,
        model: model,
        openAIStoreEnabled: openAIStoreEnabled,
        userText: userText,
        assistantText: assistantText
    )
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter.history.date(from: value)!
}
