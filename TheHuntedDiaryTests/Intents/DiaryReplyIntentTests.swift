import AppIntents
import Foundation
import Testing
@testable import TheHuntedDiary

struct DiaryReplyIntentTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func promptIntentReturnsFrozenPromptWithInjectedStore() async throws {
        let fixture = try await IntentFixture(now: now)
        let result = try await GetPendingDiaryPromptIntent(
            requestHandle: fixture.handle,
            store: fixture.store,
            now: { fixture.now }
        ).perform()

        #expect(result.value == "frozen prompt")
        #expect(try await fixture.store.load(id: fixture.requestID)?.state == .awaitingShortcut)
    }

    @Test func completionStoresReplyBeforeForegroundContinuation() async throws {
        let fixture = try await IntentFixture(now: now)
        let probe = ForegroundProbe(store: fixture.store, requestID: fixture.requestID)

        _ = try await CompleteDiaryReplyIntent(
            requestHandle: fixture.handle,
            reply: "assistant reply",
            store: fixture.store,
            now: { fixture.now },
            continueInForeground: { try await probe.continueAfterCheckingStorage() }
        ).perform()

        #expect(await probe.callCount == 1)
        #expect(try await fixture.store.load(id: fixture.requestID)?.assistantText == "assistant reply")
    }

    @Test func identicalDuplicateCompletionSucceedsButConflictFails() async throws {
        let fixture = try await IntentFixture(now: now)
        let first = CompleteDiaryReplyIntent(
            requestHandle: fixture.handle,
            reply: "same bytes",
            store: fixture.store,
            now: { fixture.now },
            continueInForeground: {}
        )
        _ = try await first.perform()
        _ = try await first.perform()

        await expectIntentError(.conflictingReply) {
            _ = try await CompleteDiaryReplyIntent(
                requestHandle: fixture.handle,
                reply: "different",
                store: fixture.store,
                now: { fixture.now },
                continueInForeground: {}
            ).perform()
        }
    }

    @Test(arguments: ["", "   \n\t"])
    func completionRejectsBlankReplies(_ reply: String) async throws {
        let fixture = try await IntentFixture(now: now)
        await expectIntentError(.emptyReply) {
            _ = try await CompleteDiaryReplyIntent(
                requestHandle: fixture.handle,
                reply: reply,
                store: fixture.store,
                now: { fixture.now },
                continueInForeground: {}
            ).perform()
        }
    }

    @Test func completionRejectsOversizedReplyWithoutPersistingIt() async throws {
        let fixture = try await IntentFixture(now: now)
        let reply = String(repeating: "a", count: CompleteDiaryReplyIntent.maximumReplyUTF8Length + 1)
        await expectIntentError(.replyTooLong) {
            _ = try await CompleteDiaryReplyIntent(
                requestHandle: fixture.handle,
                reply: reply,
                store: fixture.store,
                now: { fixture.now },
                continueInForeground: {}
            ).perform()
        }
        #expect(try await fixture.store.load(id: fixture.requestID)?.assistantText == nil)
    }

    @Test func malformedUnknownWrongAndExpiredHandlesAreRejectedWithoutSecrets() async throws {
        let fixture = try await IntentFixture(now: now)

        await expectIntentError(.invalidRequestHandle) {
            _ = try await GetPendingDiaryPromptIntent(
                requestHandle: "not-a-handle",
                store: fixture.store,
                now: { fixture.now }
            ).perform()
        }

        let unknown = try DiaryReplyCapability.generate()
        await expectIntentError(.requestUnavailable) {
            _ = try await GetPendingDiaryPromptIntent(
                requestHandle: unknown.handle,
                store: fixture.store,
                now: { fixture.now }
            ).perform()
        }

        let wrong = try DiaryReplyCapability(
            requestID: fixture.requestID,
            capability: Data(repeating: 0xEE, count: 32)
        )
        await expectIntentError(.requestUnauthorized) {
            _ = try await GetPendingDiaryPromptIntent(
                requestHandle: wrong.handle,
                store: fixture.store,
                now: { fixture.now }
            ).perform()
        }

        await expectIntentError(.requestExpired) {
            _ = try await GetPendingDiaryPromptIntent(
                requestHandle: fixture.handle,
                store: fixture.store,
                now: { fixture.now.addingTimeInterval(601) }
            ).perform()
        }

        for error in DiaryReplyIntentError.allCases {
            #expect(!error.description.contains(fixture.handle))
            #expect(!error.description.contains("frozen prompt"))
            #expect(error.description.count < 128)
        }
    }

    @Test func completionRejectsMalformedUnknownWrongAndExpiredHandlesBeforeForegrounding() async throws {
        let fixture = try await IntentFixture(now: now)
        let unknown = try DiaryReplyCapability.generate()
        let wrong = try DiaryReplyCapability(
            requestID: fixture.requestID,
            capability: Data(repeating: 0xEE, count: 32)
        )
        let cases: [(String, Date, DiaryReplyIntentError)] = [
            ("not-a-handle", fixture.now, .invalidRequestHandle),
            (unknown.handle, fixture.now, .requestUnavailable),
            (wrong.handle, fixture.now, .requestUnauthorized),
            (fixture.handle, fixture.now.addingTimeInterval(601), .requestExpired),
        ]

        for (handle, date, expected) in cases {
            await expectIntentError(expected) {
                _ = try await CompleteDiaryReplyIntent(
                    requestHandle: handle,
                    reply: "must not be stored",
                    store: fixture.store,
                    now: { date },
                    continueInForeground: {
                        Issue.record("Foreground continuation must follow durable storage only")
                    }
                ).perform()
            }
        }
        #expect(try await fixture.store.load(id: fixture.requestID)?.assistantText == nil)
    }

    @Test func intentsUseOnlyCurrentIOS26ExecutionModes() {
        #expect(GetPendingDiaryPromptIntent.supportedModes == .background)
        #expect(CompleteDiaryReplyIntent.supportedModes.contains(.background))
        #expect(CompleteDiaryReplyIntent.supportedModes.contains(.foreground(.deferred)))
    }
}

private struct IntentFixture {
    let now: Date
    let requestID: UUID
    let handle: String
    let store: PendingDiaryReplyStore

    init(now: Date) async throws {
        self.now = now
        requestID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        let capability = try DiaryReplyCapability(
            requestID: requestID,
            capability: Data(repeating: 0x11, count: 32)
        )
        handle = capability.handle
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryReplyIntentTests-\(UUID().uuidString).json")
        store = try PendingDiaryReplyStore(
            fileURL: fileURL,
            persistence: PendingDiaryReplyPersistence { _, _ in }
        )
        let request = PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: requestID,
            kind: .diaryTurn,
            capabilityDigest: capability.capabilityDigest,
            callbackCapabilityDigest: Data(repeating: 0x22, count: 32),
            recognizedText: "recognized",
            recognitionSource: .appleVision,
            prompt: "frozen prompt",
            createdAt: now,
            expiresAt: now.addingTimeInterval(600),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        )
        try await store.create(request)
    }
}

private actor ForegroundProbe {
    let store: PendingDiaryReplyStore
    let requestID: UUID
    private(set) var callCount = 0

    init(store: PendingDiaryReplyStore, requestID: UUID) {
        self.store = store
        self.requestID = requestID
    }

    func continueAfterCheckingStorage() async throws {
        #expect(try await store.load(id: requestID)?.state == .replyStored)
        callCount += 1
    }
}

private func expectIntentError(
    _ expected: DiaryReplyIntentError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected intent error \(expected)")
    } catch let error as DiaryReplyIntentError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
