import Combine
import Foundation

@MainActor
final class DependencyContainer: ObservableObject {
    @Published var settings: AppSettings
    let historyStore: PlainTextHistoryStore
    let apiKeyStore: APIKeyStore
    let appleVisionRecognizer: AppleVisionRecognizer
    let openAIClient: OpenAIClient
    let pendingDiaryReplyStore: PendingDiaryReplyStore
    let shortcutReplyLauncher: any ShortcutReplyLaunching
    let diaryReplyFlow: DiaryReplyFlow

    init(
        settings: AppSettings? = nil,
        historyStore: PlainTextHistoryStore? = nil,
        apiKeyStore: APIKeyStore? = nil,
        appleVisionRecognizer: AppleVisionRecognizer? = nil,
        openAIClient: OpenAIClient? = nil,
        pendingDiaryReplyStore: PendingDiaryReplyStore? = nil,
        shortcutReplyLauncher: (any ShortcutReplyLaunching)? = nil,
        diaryReplyFlow: DiaryReplyFlow? = nil
    ) {
        self.settings = settings ?? AppSettings()
        self.historyStore = historyStore ?? PlainTextHistoryStore()
        self.apiKeyStore = apiKeyStore ?? APIKeyStore()
        self.appleVisionRecognizer = appleVisionRecognizer ?? AppleVisionRecognizer()
        self.openAIClient = openAIClient ?? OpenAIClient()
        let store: PendingDiaryReplyStore
        if let pendingDiaryReplyStore {
            store = pendingDiaryReplyStore
        } else {
            do {
                store = try PendingDiaryReplyStore()
            } catch {
                preconditionFailure("Unable to initialize pending diary reply storage.")
            }
        }
        self.pendingDiaryReplyStore = store
        self.shortcutReplyLauncher = shortcutReplyLauncher ?? ShortcutReplyLauncher()
        self.diaryReplyFlow = diaryReplyFlow ?? DiaryReplyFlow(store: store)
    }
}
