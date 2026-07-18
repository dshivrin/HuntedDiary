import CryptoKit
import Foundation
import Testing
@testable import TheHuntedDiary

@MainActor
struct ShortcutSetupCoordinatorTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let requestID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!

    @Test(arguments: ["", "  \n\t"])
    func blankShortcutNameCreatesNoProbeAndDoesNotLaunch(_ name: String) async throws {
        let fixture = try setupFixture(shortcutName: name)

        await fixture.coordinator.testShortcut(now: now)

        #expect(fixture.coordinator.state == .failed(.missingShortcutName))
        #expect(fixture.launcher.launches.isEmpty)
        #expect(fixture.settings.settings.activeSetupProbeID == nil)
        #expect(try await fixture.store.load(id: requestID) == nil)
    }

    @Test func acceptedLaunchCreatesDurableProbeButDoesNotVerifyShortcut() async throws {
        let fixture = try setupFixture()

        await fixture.coordinator.testShortcut(now: now)

        #expect(fixture.coordinator.state == .awaitingReply(requestID))
        #expect(fixture.launcher.launches.count == 1)
        #expect(fixture.launcher.launches[0].shortcutName == "Tom’s Diary Reply")
        let request = try #require(await fixture.store.load(id: requestID))
        #expect(request.kind == .setupProbe)
        #expect(request.state == .readyToLaunch)
        #expect(request.prompt == ShortcutSetupCoordinator.setupProbePrompt)
        #expect(request.recognizedText.isEmpty)
        #expect(fixture.settings.settings.lastVerifiedShortcutName == nil)
        #expect(fixture.settings.settings.lastVerifiedAt == nil)
        #expect(fixture.settings.settings.activeSetupProbeID == requestID)
        #expect(fixture.settings.settings.activeSetupLaunchAccepted)
    }

    @Test func acceptedLaunchWithoutCompletionExpiresInsteadOfWaitingForever() async throws {
        let fixture = try setupFixture()
        await fixture.coordinator.testShortcut(now: now)

        await fixture.coordinator.reconcile(
            now: now.addingTimeInterval(ShortcutSetupCoordinator.probeLifetime + 1)
        )

        #expect(fixture.coordinator.state == .failed(.requestUnavailable))
        #expect(try await fixture.store.load(id: requestID)?.state == .expired)
        #expect(fixture.settings.settings.lastVerifiedAt == nil)
    }

    @Test func completedProbeVerifiesExactNameWithoutBecomingHistoryReconcilable() async throws {
        let fixture = try setupFixture()
        await fixture.coordinator.testShortcut(now: now)
        let launch = try #require(fixture.launcher.launches.first)
        let capability = try DiaryReplyCapability(handle: launch.handle)
        try await fixture.store.storeReply(
            id: requestID,
            capability: capability.capability,
            text: "setup complete",
            now: now.addingTimeInterval(1)
        )

        await fixture.coordinator.reconcile(now: now.addingTimeInterval(2))

        #expect(fixture.coordinator.state == .verified(name: "Tom’s Diary Reply", at: now.addingTimeInterval(2)))
        #expect(fixture.settings.settings.lastVerifiedShortcutName == "Tom’s Diary Reply")
        #expect(fixture.settings.settings.lastVerifiedAt == now.addingTimeInterval(2))
        #expect(fixture.settings.settings.activeSetupProbeID == nil)
        #expect(try await fixture.store.reconcilableRequests(now: now.addingTimeInterval(2)).isEmpty)
        #expect(try await fixture.store.load(id: requestID)?.state == .replyStored)
    }

    @Test func duplicateCompletionAndRepeatedReconciliationRemainIdempotent() async throws {
        let fixture = try setupFixture()
        await fixture.coordinator.testShortcut(now: now)
        let launch = try #require(fixture.launcher.launches.first)
        let capability = try DiaryReplyCapability(handle: launch.handle)
        try await fixture.store.storeReply(
            id: requestID,
            capability: capability.capability,
            text: "same bytes",
            now: now.addingTimeInterval(1)
        )
        try await fixture.store.storeReply(
            id: requestID,
            capability: capability.capability,
            text: "same bytes",
            now: now.addingTimeInterval(1)
        )
        await fixture.coordinator.reconcile(now: now.addingTimeInterval(2))
        let verifiedAt = fixture.settings.settings.lastVerifiedAt

        await fixture.coordinator.reconcile(now: now.addingTimeInterval(3))

        #expect(fixture.settings.settings.lastVerifiedAt == verifiedAt)
        #expect(fixture.launcher.launches.count == 1)
        #expect(try await fixture.store.load(id: requestID)?.state == .replyStored)
    }

    @Test func cancellationAndShortcutErrorNeverVerifyTheProbe() async throws {
        for event in [DiaryReplyCallbackEvent.cancelled, .failed] {
            let fixture = try setupFixture()
            await fixture.coordinator.testShortcut(now: now)
            let launch = try #require(fixture.launcher.launches.first)
            let callbackURL = event == .cancelled ? launch.callbacks.cancelURL : launch.callbacks.errorURL
            let callbackResult = await fixture.flow.handle(callbackURL, now: now.addingTimeInterval(1))
            #expect(callbackResult.isHandled)

            await fixture.coordinator.reconcile(now: now.addingTimeInterval(2))

            let expectedFailure: ShortcutSetupFailure = event == .cancelled ? .cancelled : .shortcutFailed
            #expect(fixture.coordinator.state == .failed(expectedFailure))
            #expect(fixture.settings.settings.lastVerifiedAt == nil)
            #expect(fixture.settings.settings.activeSetupProbeID == requestID)
        }
    }

    @Test func cancellationRetryReusesIDAndRotatesBothCapabilities() async throws {
        let fixture = try setupFixture()
        await fixture.coordinator.testShortcut(now: now)
        let first = try #require(fixture.launcher.launches.first)
        _ = await fixture.flow.handle(first.callbacks.cancelURL, now: now.addingTimeInterval(1))
        await fixture.coordinator.reconcile(now: now.addingTimeInterval(2))

        await fixture.coordinator.testShortcut(now: now.addingTimeInterval(3))

        #expect(fixture.launcher.launches.count == 2)
        let second = fixture.launcher.launches[1]
        #expect(try DiaryReplyCapability(handle: first.handle).requestID == requestID)
        #expect(try DiaryReplyCapability(handle: second.handle).requestID == requestID)
        #expect(first.handle != second.handle)
        #expect(first.callbacks.cancelURL != second.callbacks.cancelURL)
        let request = try #require(await fixture.store.load(id: requestID))
        #expect(request.attemptCount == 2)
        #expect(request.state == .readyToLaunch)
    }

    @Test func retryableErrorRetryReusesTheSameProbeIdentity() async throws {
        let fixture = try setupFixture()
        await fixture.coordinator.testShortcut(now: now)
        let first = try #require(fixture.launcher.launches.first)
        _ = await fixture.flow.handle(first.callbacks.errorURL, now: now.addingTimeInterval(1))
        await fixture.coordinator.reconcile(now: now.addingTimeInterval(2))

        await fixture.coordinator.testShortcut(now: now.addingTimeInterval(3))

        #expect(fixture.launcher.launches.count == 2)
        #expect(try DiaryReplyCapability(handle: fixture.launcher.launches[1].handle).requestID == requestID)
        #expect(try await fixture.store.load(id: requestID)?.attemptCount == 2)
    }

    @Test func launchRejectionDoesNotVerifyAndRetryUsesSameProbe() async throws {
        let fixture = try setupFixture(launchResults: [.failure(.handoffRejected), .success(())])

        await fixture.coordinator.testShortcut(now: now)

        #expect(fixture.coordinator.state == .failed(.launchRejected))
        #expect(fixture.settings.settings.lastVerifiedAt == nil)
        #expect(try await fixture.store.load(id: requestID)?.terminalReasonCode == DiaryReplyFailureCode.launchRejected.rawValue)

        await fixture.coordinator.testShortcut(now: now.addingTimeInterval(1))

        #expect(fixture.launcher.launches.count == 2)
        #expect(try DiaryReplyCapability(handle: fixture.launcher.launches[1].handle).requestID == requestID)
        #expect(try await fixture.store.load(id: requestID)?.attemptCount == 2)
        #expect(fixture.settings.settings.lastVerifiedAt == nil)
    }

    @Test func renameDuringProbePreventsOldCompletionFromVerifyingNewName() async throws {
        let fixture = try setupFixture()
        await fixture.coordinator.testShortcut(now: now)
        let launch = try #require(fixture.launcher.launches.first)
        fixture.settings.updateReplyShortcutName("Renamed Shortcut")
        let capability = try DiaryReplyCapability(handle: launch.handle)
        try await fixture.store.storeReply(
            id: requestID,
            capability: capability.capability,
            text: "late old completion",
            now: now.addingTimeInterval(1)
        )

        await fixture.coordinator.reconcile(now: now.addingTimeInterval(2))

        #expect(fixture.settings.settings.replyShortcutName == "Renamed Shortcut")
        #expect(fixture.settings.settings.lastVerifiedShortcutName == nil)
        #expect(fixture.settings.settings.lastVerifiedAt == nil)
        #expect(fixture.coordinator.state == .idle)
    }

    @Test func reconstructionAfterTerminationVerifiesDurablyCompletedProbe() async throws {
        let defaults = try makeDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutSetupReconstruction-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent(PendingDiaryReplyStore.defaultFileName)
        let originalSettings = TestSettingsOwner(settings: AppSettings(), defaults: defaults)
        let launcher = RecordingSetupLauncher(results: [.success(())])
        let capabilities = CapabilitySequence()
        let firstStore = try PendingDiaryReplyStore(fileURL: fileURL)
        let first = ShortcutSetupCoordinator(
            store: firstStore,
            launcher: launcher,
            settings: originalSettings,
            requestID: { self.requestID },
            capabilities: capabilities.next
        )
        await first.testShortcut(now: now)
        let launch = try #require(launcher.launches.first)
        try await firstStore.storeReply(
            id: requestID,
            capability: try DiaryReplyCapability(handle: launch.handle).capability,
            text: "completed while app was away",
            now: now.addingTimeInterval(1)
        )

        let reconstructedSettings = TestSettingsOwner(
            settings: AppSettings(userDefaults: defaults),
            defaults: defaults
        )
        let reconstructedStore = try PendingDiaryReplyStore(fileURL: fileURL)
        let reconstructed = ShortcutSetupCoordinator(
            store: reconstructedStore,
            launcher: RecordingSetupLauncher(),
            settings: reconstructedSettings,
            requestID: UUID.init,
            capabilities: CapabilitySequence().next
        )
        await reconstructed.reconcile(now: now.addingTimeInterval(2))

        #expect(reconstructedSettings.settings.lastVerifiedShortcutName == "Tom’s Diary Reply")
        #expect(reconstructedSettings.settings.lastVerifiedAt == now.addingTimeInterval(2))
        #expect(reconstructed.state == .verified(name: "Tom’s Diary Reply", at: now.addingTimeInterval(2)))
    }

    @Test func reconstructionBeforeHandoffRecoversTheSameProbeWithRotatedCapabilities() async throws {
        let owner = TestSettingsOwner(settings: AppSettings())
        owner.settings.setActiveSetupProbe(
            id: requestID,
            shortcutName: owner.settings.replyShortcutName
        )
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShortcutSetupPreHandoff-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let oldCapabilities = try ShortcutSetupCapabilities(
            requestID: requestID,
            requestCapability: Data(repeating: 0x71, count: 32),
            callbackCapability: Data(repeating: 0x72, count: 32)
        )
        try await store.create(PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: requestID,
            kind: .setupProbe,
            capabilityDigest: oldCapabilities.requestAuthorization.capabilityDigest,
            callbackCapabilityDigest: oldCapabilities.callbacks.callbackCapabilityDigest,
            recognizedText: "",
            recognitionSource: .appleVision,
            prompt: ShortcutSetupCoordinator.setupProbePrompt,
            createdAt: now,
            expiresAt: now.addingTimeInterval(ShortcutSetupCoordinator.probeLifetime),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        ))
        let launcher = RecordingSetupLauncher(results: [.success(())])
        let coordinator = ShortcutSetupCoordinator(
            store: store,
            launcher: launcher,
            settings: owner,
            requestID: UUID.init,
            capabilities: CapabilitySequence().next
        )

        await coordinator.reconcile(now: now.addingTimeInterval(1))
        #expect(coordinator.state == .failed(.launchRejected))
        await coordinator.testShortcut(now: now.addingTimeInterval(2))

        let launch = try #require(launcher.launches.first)
        #expect(try DiaryReplyCapability(handle: launch.handle).requestID == requestID)
        #expect(launch.handle != oldCapabilities.requestAuthorization.handle)
        #expect(try await store.load(id: requestID)?.attemptCount == 2)
        #expect(owner.settings.activeSetupProbeID == requestID)
        #expect(owner.settings.activeSetupLaunchAccepted)
    }

    @Test func renamingImmediatelyClearsVerifiedAndAwaitingCoordinatorUIState() async throws {
        let awaiting = try setupFixture()
        await awaiting.coordinator.testShortcut(now: now)
        #expect(awaiting.coordinator.state == .awaitingReply(requestID))
        awaiting.settings.updateReplyShortcutName("Renamed Shortcut")
        awaiting.coordinator.configuredShortcutNameDidChange()
        #expect(awaiting.coordinator.state == .idle)

        let verified = try setupFixture()
        await verified.coordinator.testShortcut(now: now)
        let launch = try #require(verified.launcher.launches.first)
        try await verified.store.storeReply(
            id: requestID,
            capability: try DiaryReplyCapability(handle: launch.handle).capability,
            text: "setup complete",
            now: now.addingTimeInterval(1)
        )
        await verified.coordinator.reconcile(now: now.addingTimeInterval(2))
        #expect(verified.coordinator.state == .verified(
            name: "Tom’s Diary Reply",
            at: now.addingTimeInterval(2)
        ))
        verified.settings.updateReplyShortcutName("Renamed Shortcut")
        verified.coordinator.configuredShortcutNameDidChange()
        #expect(verified.coordinator.state == .idle)
    }

    @Test func setupCopyIsExactAndDoesNotClaimAccountOrCapabilityDetection() {
        #expect(ShortcutSetupCopy.replyShortcutNameLabel == "Reply Shortcut Name")
        #expect(ShortcutSetupCopy.testShortcutButton == "Test Shortcut")
        #expect(ShortcutSetupCopy.setupGuideLink == "Setup Guide")
        #expect(ShortcutSetupCopy.help.contains("Get Pending Diary Prompt"))
        #expect(ShortcutSetupCopy.help.contains("Use Model"))
        #expect(ShortcutSetupCopy.help.contains("Complete Diary Reply"))
        #expect(ShortcutSetupCopy.accountGuidance.contains("optional"))
        #expect(ShortcutSetupCopy.compatibilityGuidance.contains("iPad mini 6"))
        #expect(!ShortcutSetupCopy.accountGuidance.localizedCaseInsensitiveContains("subscription detected"))
        #expect(!ShortcutSetupCopy.accountGuidance.localizedCaseInsensitiveContains("account required"))
    }

    private func setupFixture(
        shortcutName: String = "Tom’s Diary Reply",
        launchResults: [Result<Void, ShortcutReplyLauncherError>] = [.success(())]
    ) throws -> SetupFixture {
        var settings = AppSettings()
        settings.updateReplyShortcutName(shortcutName)
        let owner = TestSettingsOwner(settings: settings)
        let store = try PendingDiaryReplyStore(
            fileURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("ShortcutSetupCoordinatorTests-\(UUID().uuidString).json"),
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let launcher = RecordingSetupLauncher(results: launchResults)
        let capabilities = CapabilitySequence()
        let coordinator = ShortcutSetupCoordinator(
            store: store,
            launcher: launcher,
            settings: owner,
            requestID: { self.requestID },
            capabilities: capabilities.next
        )
        return SetupFixture(
            settings: owner,
            store: store,
            launcher: launcher,
            flow: DiaryReplyFlow(store: store),
            coordinator: coordinator
        )
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ShortcutSetupCoordinatorTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

@MainActor
private struct SetupFixture {
    let settings: TestSettingsOwner
    let store: PendingDiaryReplyStore
    let launcher: RecordingSetupLauncher
    let flow: DiaryReplyFlow
    let coordinator: ShortcutSetupCoordinator
}

@MainActor
private final class TestSettingsOwner: ShortcutSetupSettingsOwning {
    var settings: AppSettings {
        didSet {
            if let defaults {
                settings.persist(to: defaults)
            }
        }
    }
    private let defaults: UserDefaults?

    init(settings: AppSettings, defaults: UserDefaults? = nil) {
        self.settings = settings
        self.defaults = defaults
    }

    func updateReplyShortcutName(_ name: String) {
        settings.updateReplyShortcutName(name)
    }
}

@MainActor
private final class RecordingSetupLauncher: ShortcutReplyLaunching {
    struct Launch {
        let shortcutName: String
        let handle: String
        let callbacks: ShortcutCallbacks
    }

    private var results: [Result<Void, ShortcutReplyLauncherError>]
    private(set) var launches: [Launch] = []

    init(results: [Result<Void, ShortcutReplyLauncherError>] = []) {
        self.results = results
    }

    func launch(shortcutName: String, handle: String, callbacks: ShortcutCallbacks) async throws {
        launches.append(Launch(shortcutName: shortcutName, handle: handle, callbacks: callbacks))
        guard !results.isEmpty else { return }
        try results.removeFirst().get()
    }
}

@MainActor
private final class CapabilitySequence {
    private var index: UInt8 = 0

    func next(_ requestID: UUID) throws -> ShortcutSetupCapabilities {
        index &+= 1
        return try ShortcutSetupCapabilities(
            requestID: requestID,
            requestCapability: Data(repeating: index, count: 32),
            callbackCapability: Data(repeating: index &+ 0x40, count: 32)
        )
    }
}

private extension DiaryReplyCallbackResult {
    var isHandled: Bool {
        if case .handled = self { return true }
        return false
    }
}
