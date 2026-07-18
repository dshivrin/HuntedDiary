import Combine
import Foundation
import UIKit

struct DiaryTurnFailure: Equatable {
    enum Stage: Equatable {
        case apiKey
        case canvasExport
        case recognition
        case openAI
    }

    var stage: Stage
    var error: AppError
}

enum DiaryTurnPhase: Equatable {
    case listening
    case recognizing
    case sending
    case streamingReply
    case awaitingShortcut
    case reconciling
    case completed
    case failed(DiaryTurnFailure)
}

@MainActor
final class DiaryTurnController: ObservableObject {
    static let requestLifetime: TimeInterval = 24 * 60 * 60

    typealias SettingsProvider = @MainActor () -> AppSettings
    typealias RequestIDProvider = @MainActor @Sendable () -> UUID
    typealias CapabilityProvider = @MainActor @Sendable (UUID) throws -> ShortcutSetupCapabilities

    @Published private(set) var phase: DiaryTurnPhase = .listening
    @Published private(set) var recognizedText = ""
    @Published private(set) var replyText = ""
    @Published private(set) var shouldPresentSettings = false
    @Published private(set) var historyWriteError: AppError?
    @Published private(set) var activeRequestID: UUID?

    private let settingsProvider: SettingsProvider
    private let historyStore: any IdempotentDiaryHistoryStoring
    private let recognizer: any HandwritingRecognizer
    private let pendingStore: PendingDiaryReplyStore
    private let launcher: any ShortcutReplyLaunching
    private let promptBuilder: DiaryPromptBuilder
    private let requestID: RequestIDProvider
    private let capabilities: CapabilityProvider

    private var retainedImage: UIImage?
    private var activeTask: Task<Void, Never>?
    private var currentSubmissionID: UUID?

    init(
        settingsProvider: @escaping SettingsProvider,
        historyStore: any IdempotentDiaryHistoryStoring,
        recognizer: any HandwritingRecognizer,
        pendingStore: PendingDiaryReplyStore,
        launcher: any ShortcutReplyLaunching,
        promptBuilder: DiaryPromptBuilder = DiaryPromptBuilder(),
        requestID: @escaping RequestIDProvider = UUID.init,
        capabilities: @escaping CapabilityProvider = DiaryTurnController.generateCapabilities
    ) {
        self.settingsProvider = settingsProvider
        self.historyStore = historyStore
        self.recognizer = recognizer
        self.pendingStore = pendingStore
        self.launcher = launcher
        self.promptBuilder = promptBuilder
        self.requestID = requestID
        self.capabilities = capabilities
    }

    convenience init(dependencies: DependencyContainer) {
        self.init(
            settingsProvider: { dependencies.settings },
            historyStore: dependencies.historyStore,
            recognizer: dependencies.appleVisionRecognizer,
            pendingStore: dependencies.pendingDiaryReplyStore,
            launcher: dependencies.shortcutReplyLauncher
        )
        dependencies.registerDiaryReplyReconciler(self)
    }

    // Kept until Task 9 removes the legacy transport tests and types.
    convenience init(
        settingsProvider: @escaping SettingsProvider,
        apiKeyStore _: any APIKeyLoading,
        historyStore: any DiaryHistoryStoring,
        recognizer: any HandwritingRecognizer,
        openAIClient _: any OpenAIReplyStreaming,
        promptBuilder: DiaryPromptBuilder = DiaryPromptBuilder()
    ) {
        let store = try! PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("LegacyDiaryTurnController-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        self.init(
            settingsProvider: settingsProvider,
            historyStore: LegacyIdempotentHistoryStore(historyStore),
            recognizer: recognizer,
            pendingStore: store,
            launcher: LegacyRejectedShortcutLauncher(),
            promptBuilder: promptBuilder
        )
    }

    var canRetry: Bool {
        if historyWriteError != nil { return true }
        if case .failed = phase { return true }
        return false
    }

    var activeRecovery: AppErrorRecovery? {
        if let historyWriteError {
            return historyWriteError.recovery
        }
        guard case let .failed(failure) = phase else { return nil }
        return failure.error.recovery
    }

    func submit(model: PencilCanvasModel, canvasSize: CGSize) {
        let image = model.exportImage(canvasSize: canvasSize)
        activeTask?.cancel()
        let submissionID = prepareSubmission(image: image)
        guard let image, let submissionID else {
            activeTask = nil
            return
        }
        activeTask = Task { [weak self] in
            await self?.recognizeAndLaunch(image: image, submissionID: submissionID, now: Date())
        }
    }

    func submit(image: UIImage?, now: Date = Date()) async {
        activeTask?.cancel()
        activeTask = nil
        guard let image, let submissionID = prepareSubmission(image: image) else { return }
        await recognizeAndLaunch(image: image, submissionID: submissionID, now: now)
    }

    func retry(now: Date = Date()) async {
        if historyWriteError != nil {
            await reconcile(now: now)
            return
        }
        switch phase {
        case .failed, .awaitingShortcut:
            break
        default:
            return
        }

        if let activeRequestID {
            phase = .sending
            await retryRequest(id: activeRequestID, now: now)
            return
        }

        guard let retainedImage else {
            fail(stage: .canvasExport, error: .emptyDrawing)
            return
        }
        let submissionID = UUID()
        currentSubmissionID = submissionID
        await recognizeAndLaunch(image: retainedImage, submissionID: submissionID, now: now)
    }

    func reconcile(now: Date = Date()) async {
        historyWriteError = nil
        if activeRequestID == nil {
            do {
                if let request = try await pendingStore.latestActiveDiaryRequest(now: now) {
                    activeRequestID = request.id
                    recognizedText = request.recognizedText
                    if let assistantText = request.assistantText {
                        replyText = assistantText
                    }
                }
            } catch {
                historyWriteError = .historyWriteFailed
                return
            }
        }
        let requests: [PendingDiaryReply]
        do {
            requests = try await pendingStore.reconcilableRequests(now: now)
        } catch {
            historyWriteError = .historyWriteFailed
            return
        }

        for request in requests {
            await reconcile(request, now: now)
        }
        await refreshActiveRequestState()
    }
}

private extension DiaryTurnController {
    func prepareSubmission(image: UIImage?) -> UUID? {
        currentSubmissionID = nil
        activeRequestID = nil
        recognizedText = ""
        replyText = ""
        shouldPresentSettings = false
        historyWriteError = nil
        retainedImage = image
        phase = .listening

        guard image != nil else {
            fail(stage: .canvasExport, error: .emptyDrawing)
            return nil
        }
        let submissionID = UUID()
        currentSubmissionID = submissionID
        return submissionID
    }

    func recognizeAndLaunch(image: UIImage, submissionID: UUID, now: Date) async {
        guard isCurrentSubmission(submissionID) else { return }
        do {
            phase = .recognizing
            let recognition = try await recognizer.recognize(image: image)
            guard isCurrentSubmission(submissionID) else { return }
            let text = recognition.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                fail(stage: .recognition, error: .emptyRecognitionResult)
                return
            }

            recognizedText = text
            let normalized = RecognitionResult(
                text: text,
                confidence: recognition.confidence,
                source: recognition.source
            )
            try await createAndLaunch(recognition: normalized, submissionID: submissionID, now: now)
        } catch {
            if isCurrentSubmission(submissionID) {
                fail(stage: .recognition, error: .recognitionFailed)
            }
        }
    }

    func createAndLaunch(
        recognition: RecognitionResult,
        submissionID: UUID,
        now: Date
    ) async throws {
        guard isCurrentSubmission(submissionID) else { return }
        let settings = settingsProvider()
        phase = .sending
        let recentTurns = try historyStore.loadRecent(limit: settings.recentHistoryLimit)
        let frozenPrompt = Self.render(
            promptBuilder.buildPrompt(
                recentTurns: recentTurns,
                currentUserText: recognition.text,
                settings: settings
            )
        )
        let id = requestID()
        let authorization = try capabilities(id)
        let request = PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: .diaryTurn,
            capabilityDigest: authorization.requestAuthorization.capabilityDigest,
            callbackCapabilityDigest: authorization.callbacks.callbackCapabilityDigest,
            recognizedText: recognition.text,
            recognitionSource: recognition.source,
            prompt: frozenPrompt,
            createdAt: now,
            expiresAt: now.addingTimeInterval(Self.requestLifetime),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        )
        try await pendingStore.create(request)
        guard isCurrentSubmission(submissionID) else { return }
        activeRequestID = id
        await launch(
            authorization,
            shortcutName: settings.replyShortcutName,
            now: now,
            submissionID: submissionID
        )
    }

    func retryRequest(id: UUID, now: Date) async {
        let settings = settingsProvider()
        let authorization: ShortcutSetupCapabilities
        do {
            authorization = try capabilities(id)
            let adopted = try await pendingStore.prepareRetry(
                id: id,
                capabilityDigest: authorization.requestAuthorization.capabilityDigest,
                callbackCapabilityDigest: authorization.callbacks.callbackCapabilityDigest,
                now: now
            )
            guard DiaryReplyCapability.constantTimeEqual(
                adopted.capabilityDigest,
                authorization.requestAuthorization.capabilityDigest
            ), DiaryReplyCapability.constantTimeEqual(
                adopted.callbackCapabilityDigest,
                authorization.callbacks.callbackCapabilityDigest
            ) else {
                throw PendingDiaryReplyStore.StoreError.invalidCapability(
                    String(id.uuidString.lowercased().prefix(8))
                )
            }
        } catch {
            fail(stage: .openAI, error: .openAIReplyFailed)
            return
        }
        await launch(authorization, shortcutName: settings.replyShortcutName, now: now)
    }

    func launch(
        _ authorization: ShortcutSetupCapabilities,
        shortcutName: String,
        now: Date,
        submissionID: UUID? = nil
    ) async {
        let requestID = authorization.requestAuthorization.requestID
        do {
            try await launcher.launch(
                shortcutName: shortcutName,
                handle: authorization.requestAuthorization.handle,
                callbacks: authorization.callbacks
            )
        } catch {
            do {
                try await pendingStore.markFailed(
                    id: requestID,
                    capability: authorization.callbackCapability,
                    code: DiaryReplyFailureCode.launchRejected.rawValue,
                    now: now
                )
            } catch {
                // The request remains durable and can be reconciled or retried after relaunch.
            }
            if ownsUI(requestID: requestID, submissionID: submissionID) {
                fail(stage: .openAI, error: .openAIReplyFailed)
            }
            return
        }

        do {
            try await pendingStore.markLaunchAccepted(id: requestID, now: now)
        } catch {
            if ownsUI(requestID: requestID, submissionID: submissionID) {
                fail(stage: .openAI, error: .openAIReplyFailed)
            }
            return
        }
        if ownsUI(requestID: requestID, submissionID: submissionID) {
            phase = .awaitingShortcut
        }
    }

    func reconcile(_ request: PendingDiaryReply, now: Date) async {
        guard request.kind == .diaryTurn, let assistantText = request.assistantText else { return }
        let settings = settingsProvider()
        let turn = ConversationTurn(
            id: request.id.uuidString.lowercased(),
            createdAt: request.createdAt,
            recognitionSource: request.recognitionSource,
            model: settings.replyModel,
            openAIStoreEnabled: settings.openAIStoreEnabled,
            userText: request.recognizedText,
            assistantText: assistantText
        )

        if request.id == activeRequestID {
            phase = .reconciling
            recognizedText = request.recognizedText
            replyText = assistantText
        }

        do {
            _ = try historyStore.appendIfAbsent(turn)
            try historyStore.pruneOldestTurns(keepingMaximum: settings.maximumStoredTurns)
            try await pendingStore.markHistoryCommitted(id: request.id, now: now)
            if request.id == activeRequestID {
                phase = .completed
            }
        } catch {
            historyWriteError = .historyWriteFailed
            if request.id == activeRequestID {
                phase = .completed
            }
        }
    }

    func refreshActiveRequestState() async {
        guard let activeRequestID else { return }
        guard let request = try? await pendingStore.load(id: activeRequestID) else { return }
        switch request.state {
        case .readyToLaunch, .awaitingShortcut:
            if request.launchAcceptedAt == nil {
                fail(stage: .openAI, error: .openAIReplyFailed)
            } else {
                phase = .awaitingShortcut
            }
        case .cancelled, .failed, .expired:
            fail(stage: .openAI, error: .openAIReplyFailed)
        case .replyStored:
            if request.assistantText != nil, historyWriteError != nil {
                phase = .completed
            }
        case .historyCommitted:
            if let assistantText = request.assistantText {
                recognizedText = request.recognizedText
                replyText = assistantText
            }
            phase = .completed
        }
    }

    func isCurrentSubmission(_ id: UUID) -> Bool {
        currentSubmissionID == id && !Task.isCancelled
    }

    func ownsUI(requestID: UUID, submissionID: UUID?) -> Bool {
        guard activeRequestID == requestID else { return false }
        guard let submissionID else { return true }
        return currentSubmissionID == submissionID
    }

    func fail(stage: DiaryTurnFailure.Stage, error: AppError) {
        phase = .failed(DiaryTurnFailure(stage: stage, error: error))
    }

    static func render(_ prompt: DiaryPromptBuilder.Prompt) -> String {
        let transcript = prompt.inputMessages.map { message in
            let role = message.role == .user ? "User" : "Assistant"
            return "\(role):\n\(message.content)"
        }.joined(separator: "\n\n")
        return prompt.instructions + "\n\n" + transcript
    }

    static func generateCapabilities(_ id: UUID) throws -> ShortcutSetupCapabilities {
        let request = try DiaryReplyCapability.generate(requestID: id)
        let callback = try DiaryReplyCapability.generate(requestID: id)
        return try ShortcutSetupCapabilities(
            requestID: id,
            requestCapability: request.capability,
            callbackCapability: callback.capability
        )
    }
}

extension DiaryTurnController: DiaryReplyReconciling {}

@MainActor
private struct LegacyRejectedShortcutLauncher: ShortcutReplyLaunching {
    func launch(shortcutName _: String, handle _: String, callbacks _: ShortcutCallbacks) async throws {
        throw ShortcutReplyLauncherError.handoffRejected
    }
}
