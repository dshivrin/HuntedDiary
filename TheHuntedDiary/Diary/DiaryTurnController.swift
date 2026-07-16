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
    case completed
    case failed(DiaryTurnFailure)
}

@MainActor
final class DiaryTurnController: ObservableObject {
    typealias SettingsProvider = @MainActor () -> AppSettings

    @Published private(set) var phase: DiaryTurnPhase = .listening
    @Published private(set) var recognizedText = ""
    @Published private(set) var replyText = ""
    @Published private(set) var shouldPresentSettings = false
    @Published private(set) var historyWriteError: AppError?

    private let settingsProvider: SettingsProvider
    private let apiKeyStore: any APIKeyLoading
    private let historyStore: any DiaryHistoryStoring
    private let recognizer: any HandwritingRecognizer
    private let openAIClient: any OpenAIReplyStreaming
    private let promptBuilder: DiaryPromptBuilder

    private var retainedImage: UIImage?
    private var retainedRecognition: RecognitionResult?
    private var activeTask: Task<Void, Never>?
    private var activeTurnID: UUID?

    init(
        settingsProvider: @escaping SettingsProvider,
        apiKeyStore: any APIKeyLoading,
        historyStore: any DiaryHistoryStoring,
        recognizer: any HandwritingRecognizer,
        openAIClient: any OpenAIReplyStreaming,
        promptBuilder: DiaryPromptBuilder = DiaryPromptBuilder()
    ) {
        self.settingsProvider = settingsProvider
        self.apiKeyStore = apiKeyStore
        self.historyStore = historyStore
        self.recognizer = recognizer
        self.openAIClient = openAIClient
        self.promptBuilder = promptBuilder
    }

    convenience init(dependencies: DependencyContainer) {
        self.init(
            settingsProvider: { dependencies.settings },
            apiKeyStore: dependencies.apiKeyStore,
            historyStore: dependencies.historyStore,
            recognizer: dependencies.appleVisionRecognizer,
            openAIClient: dependencies.openAIClient
        )
    }

    var canRetry: Bool {
        switch phase {
        case let .failed(failure):
            return failure.stage != .apiKey
        case .listening, .recognizing, .sending, .streamingReply, .completed:
            return false
        }
    }

    var activeRecovery: AppErrorRecovery? {
        if let historyWriteError {
            return historyWriteError.recovery
        }

        guard case let .failed(failure) = phase else {
            return nil
        }

        return failure.error.recovery
    }

    func submit(model: PencilCanvasModel, canvasSize: CGSize) {
        let image = model.exportImage(canvasSize: canvasSize)
        activeTask?.cancel()
        guard let turnID = prepareTurn(image: image), let image else {
            activeTask = nil
            return
        }
        activeTask = Task { [weak self] in
            await self?.runStartingWithRecognition(image: image, turnID: turnID)
        }
    }

    func submit(image: UIImage?) async {
        activeTask?.cancel()
        activeTask = nil
        guard let turnID = prepareTurn(image: image), let image else {
            return
        }
        await runStartingWithRecognition(image: image, turnID: turnID)
    }

    func retry() async {
        guard case let .failed(failure) = phase, let turnID = activeTurnID else {
            return
        }

        switch failure.stage {
        case .recognition, .canvasExport:
            guard let retainedImage else {
                fail(stage: .canvasExport, error: .emptyDrawing)
                return
            }
            await runStartingWithRecognition(image: retainedImage, turnID: turnID)
        case .openAI:
            guard let retainedRecognition else {
                guard let retainedImage else {
                    fail(stage: .canvasExport, error: .emptyDrawing)
                    return
                }
                await runStartingWithRecognition(image: retainedImage, turnID: turnID)
                return
            }
            await runReply(for: retainedRecognition, turnID: turnID)
        case .apiKey:
            shouldPresentSettings = true
        }
    }
}

private extension DiaryTurnController {
    func prepareTurn(image: UIImage?) -> UUID? {
        activeTurnID = nil
        resetTurnState()

        guard let image else {
            fail(stage: .canvasExport, error: .emptyDrawing)
            return nil
        }

        let turnID = UUID()
        activeTurnID = turnID
        retainedImage = image
        return turnID
    }

    func resetTurnState() {
        phase = .listening
        recognizedText = ""
        replyText = ""
        shouldPresentSettings = false
        historyWriteError = nil
        retainedImage = nil
        retainedRecognition = nil
    }

    func runStartingWithRecognition(image: UIImage, turnID: UUID) async {
        guard isCurrentTurn(turnID) else {
            return
        }

        guard loadedAPIKey() != nil else {
            shouldPresentSettings = true
            fail(stage: .apiKey, error: .missingAPIKey)
            return
        }

        do {
            phase = .recognizing
            let recognition = try await recognizer.recognize(image: image)
            guard isCurrentTurn(turnID) else {
                return
            }
            let trimmedText = recognition.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard trimmedText.isEmpty == false else {
                fail(stage: .recognition, error: .emptyRecognitionResult)
                return
            }

            let normalizedRecognition = RecognitionResult(
                text: trimmedText,
                confidence: recognition.confidence,
                source: recognition.source
            )
            retainedRecognition = normalizedRecognition
            recognizedText = trimmedText
            await runReply(for: normalizedRecognition, turnID: turnID)
        } catch {
            if isCurrentTurn(turnID) {
                fail(stage: .recognition, error: .recognitionFailed)
            }
        }
    }

    func runReply(for recognition: RecognitionResult, turnID: UUID) async {
        guard isCurrentTurn(turnID) else {
            return
        }

        guard let apiKey = loadedAPIKey() else {
            shouldPresentSettings = true
            fail(stage: .apiKey, error: .missingAPIKey)
            return
        }

        let settings = settingsProvider()

        do {
            phase = .sending
            let recentTurns = try historyStore.loadRecent(limit: settings.recentHistoryLimit)
            let prompt = promptBuilder.buildPrompt(
                recentTurns: recentTurns,
                currentUserText: recognition.text,
                settings: settings
            )

            replyText = ""
            phase = .streamingReply
            for try await delta in openAIClient.replyStream(
                apiKey: apiKey,
                prompt: prompt,
                settings: settings
            ) {
                guard isCurrentTurn(turnID) else {
                    return
                }
                replyText += delta
            }

            guard isCurrentTurn(turnID) else {
                return
            }
            appendHistory(for: recognition, settings: settings)
            phase = .completed
        } catch {
            if isCurrentTurn(turnID) {
                fail(stage: .openAI, error: .openAIReplyFailed)
            }
        }
    }

    func isCurrentTurn(_ turnID: UUID) -> Bool {
        activeTurnID == turnID && Task.isCancelled == false
    }

    func appendHistory(for recognition: RecognitionResult, settings: AppSettings) {
        do {
            let turn = ConversationTurn(
                recognitionSource: recognition.source,
                model: settings.replyModel,
                openAIStoreEnabled: settings.openAIStoreEnabled,
                userText: recognition.text,
                assistantText: replyText
            )
            try historyStore.append(turn)
            try historyStore.pruneOldestTurns(keepingMaximum: settings.maximumStoredTurns)
        } catch {
            historyWriteError = .historyWriteFailed
        }
    }

    func loadedAPIKey() -> String? {
        do {
            let apiKey = try apiKeyStore.load()?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let apiKey, apiKey.isEmpty == false else {
                return nil
            }
            return apiKey
        } catch {
            return nil
        }
    }

    func fail(stage: DiaryTurnFailure.Stage, error: AppError) {
        phase = .failed(DiaryTurnFailure(stage: stage, error: error))
    }
}
