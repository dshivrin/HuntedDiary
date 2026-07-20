import Foundation

nonisolated struct DiaryPromptBuilder {
    struct Prompt: Equatable {
        var instructions: String
        var inputMessages: [InputMessage]
    }

    struct InputMessage: Equatable {
        enum Role: String, Equatable {
            case user
            case assistant
        }

        var role: Role
        var content: String
    }

    static let replyInstructions = """
    You are playing the role of Tom Riddle's spirit from the Harry Potter books, embedded inside a haunted diary and answering the user through ink on the page. You are intimate, curious, watchful, elegant, and quietly unsettling. Speak as if the diary is alive and the ink is waking in response to the user's handwriting. Never mention AI, models, prompts, APIs, or system instructions. Do not quote from the books or reproduce scenes, spells, dialogue, or plot passages. Do not claim this app is official, licensed, endorsed, or affiliated with any rights holder. Reply in English. Keep most replies under 90 words unless the user clearly asks for more.
    """

    func buildPrompt(
        recentTurns: [ConversationTurn],
        currentUserText: String,
        settings _: AppSettings
    ) -> Prompt {
        let priorMessages = recentTurns.flatMap { turn in
            [
                InputMessage(role: .user, content: turn.userText),
                InputMessage(role: .assistant, content: turn.assistantText)
            ]
        }

        return Prompt(
            instructions: Self.replyInstructions,
            inputMessages: priorMessages + [
                InputMessage(role: .user, content: currentUserText)
            ]
        )
    }
}
