import Combine
import Foundation

@MainActor
final class DependencyContainer: ObservableObject {
    @Published var settings: AppSettings {
        didSet { settings.persist(to: settingsDefaults) }
    }
    private let settingsDefaults: UserDefaults
    let historyStore: PlainTextHistoryStore
    let apiKeyStore: APIKeyStore
    let appleVisionRecognizer: AppleVisionRecognizer
    let openAIClient: OpenAIClient
    let pendingDiaryReplyStore: PendingDiaryReplyStore
    let shortcutReplyLauncher: any ShortcutReplyLaunching
    let diaryReplyFlow: DiaryReplyFlow
    lazy var shortcutSetupCoordinator = ShortcutSetupCoordinator(
        store: pendingDiaryReplyStore,
        launcher: shortcutReplyLauncher,
        settings: self
    )

    init(
        settings: AppSettings? = nil,
        settingsDefaults: UserDefaults = .standard,
        historyStore: PlainTextHistoryStore? = nil,
        apiKeyStore: APIKeyStore? = nil,
        appleVisionRecognizer: AppleVisionRecognizer? = nil,
        openAIClient: OpenAIClient? = nil,
        pendingDiaryReplyStore: PendingDiaryReplyStore? = nil,
        shortcutReplyLauncher: (any ShortcutReplyLaunching)? = nil,
        diaryReplyFlow: DiaryReplyFlow? = nil
    ) {
        self.settingsDefaults = settingsDefaults
        self.settings = settings ?? AppSettings(userDefaults: settingsDefaults)
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

    func updateReplyShortcutName(_ name: String) {
        settings.updateReplyShortcutName(name)
        shortcutSetupCoordinator.configuredShortcutNameDidChange()
    }
}

extension DependencyContainer: ShortcutSetupSettingsOwning {}
