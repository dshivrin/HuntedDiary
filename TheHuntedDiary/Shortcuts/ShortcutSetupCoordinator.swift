import Combine
import Foundation

@MainActor
protocol ShortcutSetupSettingsOwning: AnyObject {
    var settings: AppSettings { get set }
}

nonisolated struct ShortcutSetupCapabilities: Sendable, CustomStringConvertible, CustomReflectable {
    let requestAuthorization: DiaryReplyCapability
    let callbacks: ShortcutCallbacks
    let callbackCapability: Data

    init(
        requestID: UUID,
        requestCapability: Data,
        callbackCapability: Data
    ) throws {
        requestAuthorization = try DiaryReplyCapability(
            requestID: requestID,
            capability: requestCapability
        )
        callbacks = try ShortcutCallbacks(
            requestID: requestID,
            callbackCapability: callbackCapability
        )
        self.callbackCapability = callbackCapability
    }

    var description: String {
        "ShortcutSetupCapabilities(request: \(requestPrefix)…)"
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["request": "\(requestPrefix)…"],
            displayStyle: .struct
        )
    }

    private var requestPrefix: String {
        String(requestAuthorization.requestID.uuidString.lowercased().prefix(8))
    }
}

nonisolated enum ShortcutSetupFailure: Error, Equatable, CustomStringConvertible, LocalizedError {
    case missingShortcutName
    case invalidShortcutName
    case launchRejected
    case cancelled
    case shortcutFailed
    case requestUnavailable
    case storageUnavailable

    var description: String {
        switch self {
        case .missingShortcutName:
            return "Enter the Reply Shortcut Name before testing."
        case .invalidShortcutName:
            return "The Reply Shortcut Name is invalid."
        case .launchRejected:
            return "The Shortcut could not be started. Check its exact name and try again."
        case .cancelled:
            return "The Shortcut test was cancelled."
        case .shortcutFailed:
            return "The Shortcut test did not complete. Check its actions and try again."
        case .requestUnavailable:
            return "The Shortcut test is no longer available. Start a new test."
        case .storageUnavailable:
            return "The Shortcut test could not be saved."
        }
    }

    var errorDescription: String? { description }
}

nonisolated enum ShortcutSetupState: Equatable, Sendable {
    case idle
    case preparing
    case awaitingReply(UUID)
    case verified(name: String, at: Date)
    case failed(ShortcutSetupFailure)

    var isBusy: Bool {
        switch self {
        case .preparing:
            return true
        case .idle, .awaitingReply, .verified, .failed:
            return false
        }
    }
}

@MainActor
final class ShortcutSetupCoordinator: ObservableObject {
    static let setupProbePrompt = "Reply with exactly: Tom’s Diary setup complete."
    static let probeLifetime: TimeInterval = 600

    typealias RequestIDProvider = @MainActor @Sendable () -> UUID
    typealias CapabilityProvider = @MainActor @Sendable (UUID) throws -> ShortcutSetupCapabilities

    @Published private(set) var state: ShortcutSetupState

    private let store: PendingDiaryReplyStore
    private let launcher: any ShortcutReplyLaunching
    private unowned let settingsOwner: any ShortcutSetupSettingsOwning
    private let requestID: RequestIDProvider
    private let capabilities: CapabilityProvider

    init(
        store: PendingDiaryReplyStore,
        launcher: any ShortcutReplyLaunching,
        settings: any ShortcutSetupSettingsOwning,
        requestID: @escaping RequestIDProvider = UUID.init,
        capabilities: @escaping CapabilityProvider = ShortcutSetupCoordinator.generateCapabilities
    ) {
        self.store = store
        self.launcher = launcher
        self.settingsOwner = settings
        self.requestID = requestID
        self.capabilities = capabilities
        if let name = settings.settings.lastVerifiedShortcutName,
           let date = settings.settings.lastVerifiedAt,
           name == settings.settings.replyShortcutName {
            state = .verified(name: name, at: date)
        } else {
            state = .idle
        }
    }

    func testShortcut(now: Date = Date()) async {
        guard !state.isBusy else { return }
        let shortcutName = settingsOwner.settings.replyShortcutName
        guard !shortcutName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .failed(.missingShortcutName)
            return
        }
        guard shortcutName.utf8.count <= ShortcutReplyLauncher.maximumShortcutNameUTF8Length else {
            state = .failed(.invalidShortcutName)
            return
        }

        state = .preparing
        if let activeID = settingsOwner.settings.activeSetupProbeID,
           settingsOwner.settings.activeSetupShortcutName == shortcutName {
            await resumeOrRetry(
                id: activeID,
                shortcutName: shortcutName,
                now: now
            )
        } else {
            await createAndLaunch(shortcutName: shortcutName, now: now)
        }
    }

    func reconcile(now: Date = Date()) async {
        guard let id = settingsOwner.settings.activeSetupProbeID,
              let shortcutName = settingsOwner.settings.activeSetupShortcutName else {
            if let name = settingsOwner.settings.lastVerifiedShortcutName,
               let date = settingsOwner.settings.lastVerifiedAt,
               name == settingsOwner.settings.replyShortcutName {
                state = .verified(name: name, at: date)
            } else {
                switch state {
                case .preparing, .awaitingReply, .verified:
                    state = .idle
                case .idle, .failed:
                    break
                }
            }
            return
        }
        guard shortcutName == settingsOwner.settings.replyShortcutName else {
            clearActiveProbe()
            state = .idle
            return
        }

        let request: PendingDiaryReply
        do {
            guard let stored = try await store.load(id: id) else {
                clearActiveProbe()
                state = .failed(.requestUnavailable)
                return
            }
            request = stored
        } catch {
            state = .failed(.storageUnavailable)
            return
        }

        guard request.kind == .setupProbe else {
            clearActiveProbe()
            state = .failed(.requestUnavailable)
            return
        }
        switch request.state {
        case .replyStored where request.assistantText != nil:
            var settings = settingsOwner.settings
            settings.markShortcutVerified(name: shortcutName, at: now)
            settingsOwner.settings = settings
            state = .verified(name: shortcutName, at: now)
        case .readyToLaunch, .awaitingShortcut:
            state = .awaitingReply(id)
        case .cancelled:
            state = .failed(.cancelled)
        case .failed:
            if request.terminalReasonCode == DiaryReplyFailureCode.launchRejected.rawValue {
                state = .failed(.launchRejected)
            } else {
                state = .failed(.shortcutFailed)
            }
        case .expired, .historyCommitted, .replyStored:
            state = .failed(.requestUnavailable)
        }
    }

    private func createAndLaunch(shortcutName: String, now: Date) async {
        let id = requestID()
        let authorization: ShortcutSetupCapabilities
        do {
            authorization = try capabilities(id)
        } catch {
            state = .failed(.storageUnavailable)
            return
        }

        var settings = settingsOwner.settings
        settings.setActiveSetupProbe(id: id, shortcutName: shortcutName)
        settingsOwner.settings = settings

        let request = PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: .setupProbe,
            capabilityDigest: authorization.requestAuthorization.capabilityDigest,
            callbackCapabilityDigest: authorization.callbacks.callbackCapabilityDigest,
            recognizedText: "",
            recognitionSource: .appleVision,
            prompt: Self.setupProbePrompt,
            createdAt: now,
            expiresAt: now.addingTimeInterval(Self.probeLifetime),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        )
        do {
            try await store.create(request)
        } catch {
            clearActiveProbe()
            state = .failed(.storageUnavailable)
            return
        }
        await launch(
            shortcutName: shortcutName,
            authorization: authorization,
            now: now
        )
    }

    private func resumeOrRetry(id: UUID, shortcutName: String, now: Date) async {
        let request: PendingDiaryReply
        do {
            guard let stored = try await store.load(id: id), stored.kind == .setupProbe else {
                clearActiveProbe()
                state = .failed(.requestUnavailable)
                return
            }
            request = stored
        } catch {
            state = .failed(.storageUnavailable)
            return
        }

        switch request.state {
        case .readyToLaunch, .awaitingShortcut:
            state = .awaitingReply(id)
        case .replyStored:
            await reconcile(now: now)
        case .cancelled, .failed:
            await retry(id: id, shortcutName: shortcutName, now: now)
        case .expired, .historyCommitted:
            clearActiveProbe()
            await createAndLaunch(shortcutName: shortcutName, now: now)
        }
    }

    private func retry(id: UUID, shortcutName: String, now: Date) async {
        let authorization: ShortcutSetupCapabilities
        do {
            authorization = try capabilities(id)
            _ = try await store.prepareRetry(
                id: id,
                capabilityDigest: authorization.requestAuthorization.capabilityDigest,
                callbackCapabilityDigest: authorization.callbacks.callbackCapabilityDigest,
                now: now
            )
        } catch let error as PendingDiaryReplyStore.StoreError {
            if case .failureNotRetryable = error {
                clearActiveProbe()
                await createAndLaunch(shortcutName: shortcutName, now: now)
            } else {
                state = .failed(.storageUnavailable)
            }
            return
        } catch {
            state = .failed(.storageUnavailable)
            return
        }
        await launch(
            shortcutName: shortcutName,
            authorization: authorization,
            now: now
        )
    }

    private func launch(
        shortcutName: String,
        authorization: ShortcutSetupCapabilities,
        now: Date
    ) async {
        do {
            try await launcher.launch(
                shortcutName: shortcutName,
                handle: authorization.requestAuthorization.handle,
                callbacks: authorization.callbacks
            )
            state = .awaitingReply(authorization.requestAuthorization.requestID)
        } catch {
            do {
                try await store.markFailed(
                    id: authorization.requestAuthorization.requestID,
                    capability: authorization.callbackCapability,
                    code: DiaryReplyFailureCode.launchRejected.rawValue,
                    now: now
                )
                state = .failed(.launchRejected)
            } catch {
                state = .failed(.storageUnavailable)
            }
        }
    }

    private func clearActiveProbe() {
        var settings = settingsOwner.settings
        settings.clearActiveSetupProbe()
        settingsOwner.settings = settings
    }

    private static func generateCapabilities(_ requestID: UUID) throws -> ShortcutSetupCapabilities {
        let request = try DiaryReplyCapability.generate(requestID: requestID)
        let callback = try DiaryReplyCapability.generate(requestID: requestID)
        return try ShortcutSetupCapabilities(
            requestID: requestID,
            requestCapability: request.capability,
            callbackCapability: callback.capability
        )
    }
}
