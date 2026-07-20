import AppIntents
import Foundation

struct CompleteDiaryReplyIntent: AppIntent {
    static let title: LocalizedStringResource = "Complete Diary Reply"
    static let description = IntentDescription("Stores the reply for an authorized Tom’s Diary request.")
    static let supportedModes: IntentModes = [.background, .foreground(.deferred)]
    static let maximumReplyUTF8Length = 65_536

    @Parameter(title: "Request Handle")
    var requestHandle: String

    @Parameter(title: "Reply")
    var reply: String

    @AppDependency private var dependencyStore: PendingDiaryReplyStore

    private var injectedStore: PendingDiaryReplyStore?
    private var nowProvider: @Sendable () -> Date
    private var injectedForegroundContinuation: (@Sendable () async throws -> Void)?

    init() {
        injectedStore = nil
        nowProvider = Date.init
        injectedForegroundContinuation = nil
    }

    init(
        requestHandle: String,
        reply: String,
        store: PendingDiaryReplyStore,
        now: @escaping @Sendable () -> Date = Date.init,
        continueInForeground: @escaping @Sendable () async throws -> Void
    ) {
        injectedStore = store
        nowProvider = now
        injectedForegroundContinuation = continueInForeground
        self.requestHandle = requestHandle
        self.reply = reply
    }

    func perform() async throws -> IntentResultContainer<Never, Never, Never, Never> {
        guard !reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DiaryReplyIntentError.emptyReply
        }
        guard reply.utf8.count <= Self.maximumReplyUTF8Length else {
            throw DiaryReplyIntentError.replyTooLong
        }

        let capability: DiaryReplyCapability
        do {
            capability = try DiaryReplyCapability(handle: requestHandle)
        } catch {
            throw DiaryReplyIntentError.invalidRequestHandle
        }

        do {
            try await store.storeReply(
                id: capability.requestID,
                capability: capability.capability,
                text: reply,
                now: nowProvider()
            )
        } catch {
            throw DiaryReplyIntentError.map(error)
        }

        if let injectedForegroundContinuation {
            try await injectedForegroundContinuation()
        } else {
            try await continueInForeground(alwaysConfirm: false)
        }
        return .result()
    }

    private var store: PendingDiaryReplyStore {
        injectedStore ?? dependencyStore
    }
}
