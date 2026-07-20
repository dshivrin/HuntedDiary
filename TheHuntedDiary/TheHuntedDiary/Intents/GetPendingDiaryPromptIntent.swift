import AppIntents
import Foundation

struct GetPendingDiaryPromptIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Pending Diary Prompt"
    static let description = IntentDescription("Gets the prepared prompt for an authorized Tom’s Diary request.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Request Handle")
    var requestHandle: String

    @AppDependency private var dependencyStore: PendingDiaryReplyStore

    private var injectedStore: PendingDiaryReplyStore?
    private var nowProvider: @Sendable () -> Date

    init() {
        injectedStore = nil
        nowProvider = Date.init
    }

    init(
        requestHandle: String,
        store: PendingDiaryReplyStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        injectedStore = store
        nowProvider = now
        self.requestHandle = requestHandle
    }

    func perform() async throws -> IntentResultContainer<String, Never, Never, Never> {
        let capability: DiaryReplyCapability
        do {
            capability = try DiaryReplyCapability(handle: requestHandle)
        } catch {
            throw DiaryReplyIntentError.invalidRequestHandle
        }

        do {
            let prompt = try await store.prompt(
                id: capability.requestID,
                capability: capability.capability,
                now: nowProvider()
            )
            return .result(value: prompt)
        } catch {
            throw DiaryReplyIntentError.map(error)
        }
    }

    private var store: PendingDiaryReplyStore {
        injectedStore ?? dependencyStore
    }
}
