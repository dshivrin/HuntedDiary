import Testing
@testable import TheHuntedDiary

@MainActor
struct AppErrorTests {
    @Test func testRecognitionFailureMessageMentionsRetryWithoutLosingDrawing() {
        let recovery = AppError.recognitionFailed.recovery

        #expect(recovery.message == "I could not read that. Your drawing is still here.")
        #expect(recovery.actionTitle == "Try Again")
        #expect(recovery.action == .retryDrawing)
    }

    @Test func testShortcutFailureMessageMentionsRetryWithoutLosingText() {
        let recovery = AppError.shortcutReplyFailed.recovery

        #expect(recovery.message == "The diary could not answer. Your words are still here.")
        #expect(recovery.actionTitle == "Try Again")
        #expect(recovery.action == .retryReply)
    }

    @Test func testHistoryWriteFailureMessageIsNonBlocking() {
        let recovery = AppError.historyWriteFailed.recovery

        #expect(recovery.message == "Reply shown, but history was not saved.")
        #expect(recovery.actionTitle == nil)
        #expect(recovery.action == .none)
    }
}
