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

    init(
        settings: AppSettings? = nil,
        historyStore: PlainTextHistoryStore? = nil,
        apiKeyStore: APIKeyStore? = nil,
        appleVisionRecognizer: AppleVisionRecognizer? = nil,
        openAIClient: OpenAIClient? = nil,
        pendingDiaryReplyStore: PendingDiaryReplyStore? = nil
    ) {
        self.settings = settings ?? AppSettings()
        self.historyStore = historyStore ?? PlainTextHistoryStore()
        self.apiKeyStore = apiKeyStore ?? APIKeyStore()
        self.appleVisionRecognizer = appleVisionRecognizer ?? AppleVisionRecognizer()
        self.openAIClient = openAIClient ?? OpenAIClient()
        if let pendingDiaryReplyStore {
            self.pendingDiaryReplyStore = pendingDiaryReplyStore
        } else {
            do {
                self.pendingDiaryReplyStore = try PendingDiaryReplyStore()
            } catch {
                preconditionFailure("Unable to initialize pending diary reply storage.")
            }
        }
    }
}
