import Combine
import Foundation

@MainActor
final class DependencyContainer: ObservableObject {
    @Published var settings: AppSettings
    let historyStore: PlainTextHistoryStore
    let apiKeyStore: APIKeyStore
    let appleVisionRecognizer: AppleVisionRecognizer
    let openAIImageRecognizer: OpenAIImageRecognizer
    let openAIClient: OpenAIClient

    init(
        settings: AppSettings? = nil,
        historyStore: PlainTextHistoryStore? = nil,
        apiKeyStore: APIKeyStore? = nil,
        appleVisionRecognizer: AppleVisionRecognizer? = nil,
        openAIImageRecognizer: OpenAIImageRecognizer? = nil,
        openAIClient: OpenAIClient? = nil
    ) {
        self.settings = settings ?? AppSettings()
        self.historyStore = historyStore ?? PlainTextHistoryStore()
        self.apiKeyStore = apiKeyStore ?? APIKeyStore()
        self.appleVisionRecognizer = appleVisionRecognizer ?? AppleVisionRecognizer()
        self.openAIImageRecognizer = openAIImageRecognizer ?? OpenAIImageRecognizer()
        self.openAIClient = openAIClient ?? OpenAIClient()
    }
}
