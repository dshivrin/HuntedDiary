import CryptoKit
import Foundation
import Testing
@testable import TheHuntedDiary

struct PendingDiaryReplyStoreTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func storesMultipleSimultaneousRequestsWithoutLostUpdates() async throws {
        let fixture = try StoreFixture()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        let requests = (0..<12).map { makeRequest(idByte: UInt8($0), prompt: "prompt-\($0)") }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for request in requests {
                group.addTask { try await store.create(request) }
            }
            try await group.waitForAll()
        }

        for request in requests {
            #expect(try await store.load(id: request.id) == request)
        }
        let reloaded = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        for request in requests {
            #expect(try await reloaded.load(id: request.id) == request)
        }
    }

    @Test func persistsAnExplicitVersionedCollectionAndDecodesIt() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.storeURL)) as? [String: Any])
        #expect(object["schemaVersion"] as? Int == PendingDiaryReplyStore.currentSchemaVersion)
        #expect((object["records"] as? [[String: Any]])?.first?["schemaVersion"] as? Int == PendingDiaryReply.currentSchemaVersion)

        let reloaded = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await reloaded.load(id: request.id) == request)
    }

    @Test func rejectsAStoreFromANewerSchemaWithoutQuarantiningIt() throws {
        let fixture = try StoreFixture()
        try Data("{\"schemaVersion\":999,\"records\":[]}".utf8).write(to: fixture.storeURL)

        #expect(throws: PendingDiaryReplyStore.StoreError.unsupportedSchemaVersion(999)) {
            _ = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.storeURL.path))
        #expect(try FileManager.default.contentsOfDirectory(at: fixture.directoryURL, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func rejectsANewerRecordSchemaWithoutQuarantiningIt() async throws {
        let fixture = try StoreFixture()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(makeRequest())
        try mutateStoredJSON(at: fixture.storeURL) { _, record in
            record["schemaVersion"] = 999
        }

        #expect(throws: PendingDiaryReplyStore.StoreError.unsupportedRequestSchemaVersion(999)) {
            _ = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        }
        #expect(FileManager.default.fileExists(atPath: fixture.storeURL.path))
        #expect(try FileManager.default.contentsOfDirectory(at: fixture.directoryURL, includingPropertiesForKeys: nil).count == 1)
    }

    @Test(arguments: ["negative-store", "negative-record", "digest", "date", "attempt", "reply-state"])
    func quarantinesSyntacticallyValidSemanticCorruption(_ variant: String) async throws {
        let fixture = try StoreFixture()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(makeRequest())
        try mutateStoredJSON(at: fixture.storeURL) { document, record in
            switch variant {
            case "negative-store": document["schemaVersion"] = -1
            case "negative-record": record["schemaVersion"] = -1
            case "digest": record["capabilityDigest"] = ""
            case "date": record["expiresAt"] = record["createdAt"]
            case "attempt": record["attemptCount"] = -1
            case "reply-state":
                record["state"] = DiaryReplyRequestState.replyStored.rawValue
                record.removeValue(forKey: "assistantText")
            default: Issue.record("Unknown corruption variant")
            }
        }

        let recovered = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await recovered.load(id: makeRequest().id) == nil)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directoryURL, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent.hasPrefix("PendingDiaryReplies.corrupt-") })
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func migratesVersionZeroDocumentsAndRecordsOnTheNextDurableTransition() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let initialStore = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await initialStore.create(request)
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.storeURL)) as? [String: Any])
        object["schemaVersion"] = 0
        var records = try #require(object["records"] as? [[String: Any]])
        records[0]["schemaVersion"] = 0
        object["records"] = records
        try JSONSerialization.data(withJSONObject: object).write(to: fixture.storeURL)

        let migratedStore = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await migratedStore.load(id: request.id)?.schemaVersion == PendingDiaryReply.currentSchemaVersion)
        try await migratedStore.create(makeRequest(idByte: 0x12))

        let migratedObject = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.storeURL)) as? [String: Any])
        #expect(migratedObject["schemaVersion"] as? Int == PendingDiaryReplyStore.currentSchemaVersion)
        let migratedRecords = try #require(migratedObject["records"] as? [[String: Any]])
        #expect(migratedRecords.allSatisfy { $0["schemaVersion"] as? Int == PendingDiaryReply.currentSchemaVersion })
    }

    @Test func expiresARequestDurablyAndRejectsPromptAccess() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(expiresAt: now.addingTimeInterval(1))
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        await expectStoreError(.requestExpired(request.prefix)) {
            _ = try await store.prompt(id: request.id, capability: requestCapability, now: now.addingTimeInterval(2))
        }
        #expect(try await store.load(id: request.id)?.state == .expired)
        #expect(try PendingDiaryReplyStore(fileURL: fixture.storeURL).fileURL == fixture.storeURL)
        let reloaded = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await reloaded.load(id: request.id)?.state == .expired)
    }

    @Test func expiryDiscoveredDuringReplyStorageIsPersisted() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(expiresAt: now.addingTimeInterval(1))
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        await expectStoreError(.requestExpired(request.prefix)) {
            try await store.storeReply(
                id: request.id,
                capability: requestCapability,
                text: "too late",
                now: now.addingTimeInterval(2)
            )
        }

        #expect(try await store.load(id: request.id)?.state == .expired)
        let reloaded = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await reloaded.load(id: request.id)?.state == .expired)
    }

    @Test func replyStoredBeforeExpiryRemainsReconcilableAndCommittableAfterExpiry() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(expiresAt: now.addingTimeInterval(1))
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        _ = try await store.prompt(id: request.id, capability: requestCapability, now: now)
        try await store.storeReply(id: request.id, capability: requestCapability, text: "arrived in time", now: now.addingTimeInterval(0.5))

        let afterExpiry = now.addingTimeInterval(2)
        await expectStoreError(.requestExpired(request.prefix)) {
            _ = try await store.prompt(
                id: request.id,
                capability: requestCapability,
                now: afterExpiry
            )
        }
        await expectStoreError(.requestExpired(request.prefix)) {
            try await store.storeReply(
                id: request.id,
                capability: requestCapability,
                text: "arrived in time",
                now: afterExpiry
            )
        }

        let completed = try #require(await store.load(id: request.id))
        #expect(completed.state == .replyStored)
        #expect(completed.assistantText == "arrived in time")
        #expect(try await store.reconcilableRequests(now: afterExpiry).map(\.id) == [request.id])
        try await store.markHistoryCommitted(id: request.id, now: afterExpiry)
        #expect(try await store.load(id: request.id)?.state == .historyCommitted)
    }

    @Test func completedSetupProbeRemainsLocallyLoadableAfterCapabilityExpiry() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(kind: .setupProbe, expiresAt: now.addingTimeInterval(1))
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        _ = try await store.prompt(id: request.id, capability: requestCapability, now: now)
        try await store.storeReply(id: request.id, capability: requestCapability, text: "probe-ok", now: now.addingTimeInterval(0.5))

        #expect(try await store.reconcilableRequests(now: now.addingTimeInterval(2)).isEmpty)
        let completed = try #require(await store.load(id: request.id))
        #expect(completed.state == .replyStored)
        #expect(completed.assistantText == "probe-ok")
    }

    @Test func rejectsWrongRequestAndCallbackCapabilities() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        await expectStoreError(.invalidCapability(request.prefix)) {
            _ = try await store.prompt(id: request.id, capability: wrongCapability, now: now)
        }
        await expectStoreError(.invalidCapability(request.prefix)) {
            try await store.markCancelled(id: request.id, capability: wrongCapability, now: now)
        }
        #expect(try await store.load(id: request.id) == request)
    }

    @Test func promptReplyAndHistoryTransitionsAreDurableAndIdempotent() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        #expect(try await store.prompt(id: request.id, capability: requestCapability, now: now) == request.prompt)
        #expect(try await store.load(id: request.id)?.state == .awaitingShortcut)
        try await store.storeReply(id: request.id, capability: requestCapability, text: "reply", now: now.addingTimeInterval(1))
        try await store.storeReply(id: request.id, capability: requestCapability, text: "reply", now: now.addingTimeInterval(2))
        #expect(try await store.load(id: request.id)?.assistantText == "reply")
        try await store.markHistoryCommitted(id: request.id, now: now.addingTimeInterval(3))
        try await store.markHistoryCommitted(id: request.id, now: now.addingTimeInterval(4))
        #expect(try await store.load(id: request.id)?.state == .historyCommitted)

        await expectStoreError(.invalidTransition(request.prefix, .historyCommitted, .replyStored)) {
            try await store.storeReply(id: request.id, capability: requestCapability, text: "reply", now: now.addingTimeInterval(5))
        }
        await expectStoreError(.invalidTransition(request.prefix, .historyCommitted, .awaitingShortcut)) {
            _ = try await store.prompt(id: request.id, capability: requestCapability, now: now.addingTimeInterval(5))
        }
    }

    @Test func rejectsConflictingSecondReplyButAcceptsByteIdenticalDelivery() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        _ = try await store.prompt(id: request.id, capability: requestCapability, now: now)
        try await store.storeReply(id: request.id, capability: requestCapability, text: "same\nbytes", now: now)
        try await store.storeReply(id: request.id, capability: requestCapability, text: "same\nbytes", now: now)

        await expectStoreError(.conflictingReply(request.prefix)) {
            try await store.storeReply(id: request.id, capability: requestCapability, text: "different", now: now)
        }
    }

    @Test func cancellationAndFailureCallbacksMakeValidDurableTerminalTransitions() async throws {
        let fixture = try StoreFixture()
        let cancelled = makeRequest(idByte: 0x31)
        let failed = makeRequest(idByte: 0x32)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(cancelled)
        try await store.create(failed)

        try await store.markCancelled(
            id: cancelled.id,
            capability: callbackCapability,
            now: now.addingTimeInterval(1)
        )
        try await store.markCancelled(
            id: cancelled.id,
            capability: callbackCapability,
            now: now.addingTimeInterval(2)
        )
        try await store.markFailed(
            id: failed.id,
            capability: callbackCapability,
            code: "shortcut_error",
            now: now.addingTimeInterval(1)
        )
        try await store.markFailed(
            id: failed.id,
            capability: callbackCapability,
            code: "shortcut_error",
            now: now.addingTimeInterval(2)
        )

        #expect(try await store.load(id: cancelled.id)?.state == .cancelled)
        #expect(try await store.load(id: failed.id)?.state == .failed)
        #expect(try await store.load(id: failed.id)?.terminalReasonCode == "shortcut_error")
        let reloaded = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await reloaded.load(id: cancelled.id)?.state == .cancelled)
        #expect(try await reloaded.load(id: failed.id)?.state == .failed)
    }

    @Test(arguments: [
        "",
        "unknown_code",
        "shortcut_error\nprivate diary text",
        "private diary text",
        String(repeating: "x", count: 65),
    ])
    func rejectsArbitraryFailureCodesWithoutPersistingThem(_ code: String) async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        await expectStoreError(.invalidFailureCode(request.prefix)) {
            try await store.markFailed(
                id: request.id,
                capability: callbackCapability,
                code: code,
                now: now.addingTimeInterval(1)
            )
        }

        #expect(try await store.load(id: request.id) == request)
        if !code.isEmpty {
            let storedText = try #require(String(data: Data(contentsOf: fixture.storeURL), encoding: .utf8))
            #expect(!storedText.contains(code))
        }
    }

    @Test(arguments: [DiaryReplyRequestState.cancelled, .failed])
    func retryPreservesIdentityAndContentWhileRotatingCapabilities(_ state: DiaryReplyRequestState) async throws {
        let fixture = try StoreFixture()
        var request = makeRequest(state: state, attemptCount: 2)
        request.assistantText = "retained assistant"
        request.historyCommittedAt = Date(timeIntervalSince1970: 42)
        request.terminalReasonCode = state == .failed ? "shortcut_error" : "shortcut_cancelled"
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        let newRequestDigest = digest(newRequestCapability)
        let newCallbackDigest = digest(newCallbackCapability)

        let prepared = try await store.prepareRetry(
            id: request.id,
            capabilityDigest: newRequestDigest,
            callbackCapabilityDigest: newCallbackDigest,
            now: now.addingTimeInterval(10)
        )

        #expect(prepared.id == request.id)
        #expect(prepared.kind == request.kind)
        #expect(prepared.prompt == request.prompt)
        #expect(prepared.recognizedText == request.recognizedText)
        #expect(prepared.recognitionSource == request.recognitionSource)
        #expect(prepared.assistantText == request.assistantText)
        #expect(prepared.historyCommittedAt == request.historyCommittedAt)
        #expect(prepared.capabilityDigest == newRequestDigest)
        #expect(prepared.callbackCapabilityDigest == newCallbackDigest)
        #expect(prepared.state == .readyToLaunch)
        #expect(prepared.attemptCount == 3)
        #expect(prepared.terminalReasonCode == nil)

        await expectStoreError(.invalidCapability(request.prefix)) {
            _ = try await store.prompt(id: request.id, capability: requestCapability, now: now.addingTimeInterval(11))
        }
        #expect(try await store.prompt(id: request.id, capability: newRequestCapability, now: now.addingTimeInterval(11)) == request.prompt)
    }

    @Test(arguments: [DiaryReplyRequestState.readyToLaunch, .awaitingShortcut])
    func activeRetryPreparationRemainsIdempotent(_ state: DiaryReplyRequestState) async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(state: state, attemptCount: 3)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        let prepared = try await store.prepareRetry(
            id: request.id,
            capabilityDigest: digest(newRequestCapability),
            callbackCapabilityDigest: digest(newCallbackCapability),
            now: now.addingTimeInterval(1)
        )

        #expect(prepared == request)
    }

    @Test func terminalRetryRejectsExactAndPartialCapabilityReuse() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(state: .cancelled)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        for pair in [
            (request.capabilityDigest, request.callbackCapabilityDigest),
            (request.capabilityDigest, digest(newCallbackCapability)),
            (digest(newRequestCapability), request.callbackCapabilityDigest),
        ] {
            await expectStoreError(.retryCapabilityReuse(request.prefix)) {
                _ = try await store.prepareRetry(
                    id: request.id,
                    capabilityDigest: pair.0,
                    callbackCapabilityDigest: pair.1,
                    now: now.addingTimeInterval(1)
                )
            }
        }
        #expect(try await store.load(id: request.id) == request)
    }

    @Test func concurrentDistinctRetryPairsPrepareExactlyOneAttempt() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(state: .cancelled, attemptCount: 1)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        let otherRequestCapability = Data(repeating: 0x55, count: 32)
        let otherCallbackCapability = Data(repeating: 0x66, count: 32)

        async let first = store.prepareRetry(
            id: request.id,
            capabilityDigest: digest(newRequestCapability),
            callbackCapabilityDigest: digest(newCallbackCapability),
            now: now.addingTimeInterval(1)
        )
        async let second = store.prepareRetry(
            id: request.id,
            capabilityDigest: digest(otherRequestCapability),
            callbackCapabilityDigest: digest(otherCallbackCapability),
            now: now.addingTimeInterval(1)
        )
        let prepared = try await [first, second]

        #expect(prepared[0] == prepared[1])
        #expect(prepared[0].attemptCount == 2)
        await expectStoreError(.invalidCapability(request.prefix)) {
            _ = try await store.prompt(id: request.id, capability: requestCapability, now: now.addingTimeInterval(2))
        }
        await expectStoreError(.invalidCapability(request.prefix)) {
            try await store.markCancelled(id: request.id, capability: callbackCapability, now: now.addingTimeInterval(2))
        }

        let winningRequest = prepared[0].capabilityDigest == digest(newRequestCapability) ? newRequestCapability : otherRequestCapability
        let winningCallback = prepared[0].callbackCapabilityDigest == digest(newCallbackCapability) ? newCallbackCapability : otherCallbackCapability
        _ = try await store.prompt(id: request.id, capability: winningRequest, now: now.addingTimeInterval(2))
        try await store.markCancelled(id: request.id, capability: winningCallback, now: now.addingTimeInterval(2))
    }

    @Test func nonretryableFailureCannotBePreparedForRetry() async throws {
        let fixture = try StoreFixture()
        var request = makeRequest(state: .failed)
        request.terminalReasonCode = DiaryReplyFailureCode.unsupportedDevice.rawValue
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        await expectStoreError(.failureNotRetryable(request.prefix)) {
            _ = try await store.prepareRetry(
                id: request.id,
                capabilityDigest: digest(newRequestCapability),
                callbackCapabilityDigest: digest(newCallbackCapability),
                now: now.addingTimeInterval(1)
            )
        }
    }

    @Test func rapidRetryPreparationWithTheSameAttemptIsIdempotent() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(state: .cancelled, attemptCount: 1)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        let requestDigest = digest(newRequestCapability)
        let callbackDigest = digest(newCallbackCapability)

        let first = try await store.prepareRetry(id: request.id, capabilityDigest: requestDigest, callbackCapabilityDigest: callbackDigest, now: now)
        let second = try await store.prepareRetry(id: request.id, capabilityDigest: requestDigest, callbackCapabilityDigest: callbackDigest, now: now.addingTimeInterval(1))

        #expect(first == second)
        #expect(second.attemptCount == 2)
    }

    @Test func duplicateRetryPreparationWhileAwaitingDoesNotIncrementTheAttempt() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(state: .awaitingShortcut, attemptCount: 4)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)

        let duplicate = try await store.prepareRetry(
            id: request.id,
            capabilityDigest: request.capabilityDigest,
            callbackCapabilityDigest: request.callbackCapabilityDigest,
            now: now.addingTimeInterval(1)
        )

        #expect(duplicate == request)
        #expect(duplicate.state == .awaitingShortcut)
        #expect(duplicate.attemptCount == 4)
    }

    @Test func setupProbeCompletesButNeverBecomesHistoryReconcilable() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(kind: .setupProbe)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(request)
        _ = try await store.prompt(id: request.id, capability: requestCapability, now: now)
        try await store.storeReply(id: request.id, capability: requestCapability, text: "probe-ok", now: now)

        #expect(try await store.load(id: request.id)?.state == .replyStored)
        #expect(try await store.reconcilableRequests(now: now).isEmpty)
    }

    @Test func reconciliationReturnsEveryDiaryReplyInStableOrder() async throws {
        let fixture = try StoreFixture()
        let first = makeRequest(idByte: 1, createdAt: now, state: .replyStored, assistantText: "one")
        let second = makeRequest(idByte: 2, createdAt: now.addingTimeInterval(1), state: .replyStored, assistantText: "two")
        let waiting = makeRequest(idByte: 3, createdAt: now.addingTimeInterval(2))
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await store.create(second)
        try await store.create(waiting)
        try await store.create(first)

        #expect(try await store.reconcilableRequests(now: now.addingTimeInterval(3)).map(\.id) == [first.id, second.id])
    }

    @Test func cleanupRemovesOnlyOldTerminalRecordsAndRetainsActiveWork() async throws {
        let fixture = try StoreFixture()
        let old = now.addingTimeInterval(-1_000)
        let active = makeRequest(
            idByte: 1,
            createdAt: old,
            expiresAt: now.addingTimeInterval(600),
            updatedAt: old
        )
        let committed = makeRequest(idByte: 2, createdAt: old, updatedAt: old, state: .historyCommitted, assistantText: "done", historyCommittedAt: old)
        let cancelled = makeRequest(idByte: 3, createdAt: old, updatedAt: old, state: .cancelled)
        let failed = makeRequest(idByte: 4, createdAt: old, updatedAt: old, state: .failed)
        let expired = makeRequest(idByte: 5, createdAt: old, expiresAt: old.addingTimeInterval(10), updatedAt: old, state: .expired)
        let probe = makeRequest(idByte: 6, kind: .setupProbe, createdAt: old, updatedAt: old, state: .replyStored, assistantText: "ok")
        let recentTerminal = makeRequest(idByte: 7, state: .cancelled)
        let overdueActive = makeRequest(idByte: 8, createdAt: old, expiresAt: old.addingTimeInterval(10), updatedAt: old)
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        for request in [active, committed, cancelled, failed, expired, probe, recentTerminal, overdueActive] {
            try await store.create(request)
        }

        try await store.removeExpiredAndCommitted(before: now.addingTimeInterval(-100))

        #expect(try await store.load(id: active.id) != nil)
        #expect(try await store.load(id: recentTerminal.id) != nil)
        for removed in [committed, cancelled, failed, expired, probe, overdueActive] {
            #expect(try await store.load(id: removed.id) == nil)
        }
    }

    @Test func corruptStorageIsQuarantinedWithABoundedNonContentName() throws {
        let fixture = try StoreFixture()
        let diarySecret = "private diary text must not leak"
        try Data(diarySecret.utf8).write(to: fixture.storeURL)

        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        let files = try FileManager.default.contentsOfDirectory(at: fixture.directoryURL, includingPropertiesForKeys: nil)
        let quarantined = try #require(files.first { $0.lastPathComponent.hasPrefix("PendingDiaryReplies.corrupt-") })

        #expect(store.fileURL == fixture.storeURL)
        #expect(quarantined.lastPathComponent.count < 80)
        #expect(!quarantined.lastPathComponent.contains(diarySecret))
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func durableWriteFailureLeavesActorMemoryAndDestinationUnchanged() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let persistence = PendingDiaryReplyPersistence { _, _ in throw PersistenceProbeError.expected }
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)

        await expectStoreError(.durableWriteFailed) {
            try await store.create(request)
        }

        #expect(try await store.load(id: request.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func cancellationBeforeMutationDoesNotCallPersistenceOrChangeMemory() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let probe = PersistenceCallProbe()
        let persistence = PendingDiaryReplyPersistence { _, _ in await probe.called() }
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await store.create(request)
        }
        do {
            try await task.value
            Issue.record("Expected cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await probe.callCount == 0)
        #expect(try await store.load(id: request.id) == nil)
    }

    @Test func cancellationAfterCommitStartsStillReturnsCommittedState() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let gate = PersistenceGate()
        let live = PendingDiaryReplyPersistence.live
        let persistence = PendingDiaryReplyPersistence { data, url in
            await gate.beginAndWait()
            try await live.write(data, url)
        }
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)
        let createTask = Task { try await store.create(request) }
        await gate.waitUntilStarted()

        createTask.cancel()
        await gate.release()
        try await createTask.value

        #expect(try await store.load(id: request.id) == request)
        #expect(try await PendingDiaryReplyStore(fileURL: fixture.storeURL).load(id: request.id) == request)
    }

    @Test func cancellationAfterEncodingButBeforeIOLeavesMemoryAndDiskUnchanged() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let gate = PersistenceGate()
        let probe = PersistenceCallProbe()
        let persistence = PendingDiaryReplyPersistence(
            beforeWrite: { await gate.beginAndWait() },
            write: { _, _ in await probe.called() }
        )
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)
        let task = Task { try await store.create(request) }
        await gate.waitUntilStarted()

        task.cancel()
        await gate.release()
        do {
            try await task.value
            Issue.record("Expected cancellation before persistence I/O")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(await probe.callCount == 0)
        #expect(try await store.load(id: request.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    @Test func directorySyncFailureAfterReplacementReportsCommittedState() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let persistence = PendingDiaryReplyPersistence { data, url in
            try data.write(to: url)
            throw PendingDiaryReplyPersistenceError.replacementCommittedButDirectorySyncFailed
        }
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)

        await expectStoreError(.directorySyncFailedAfterCommit) {
            try await store.create(request)
        }

        #expect(try await store.load(id: request.id) == request)
        let reloaded = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        #expect(try await reloaded.load(id: request.id) == request)
    }

    @Test func flushWaitsForAnInFlightCommitAndNoOpsAfterward() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest()
        let gate = PersistenceGate()
        let live = PendingDiaryReplyPersistence.live
        let persistence = PendingDiaryReplyPersistence { data, url in
            await gate.beginAndWait()
            try await live.write(data, url)
        }
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)
        let createTask = Task { try await store.create(request) }
        await gate.waitUntilStarted()
        let completion = CompletionProbe()
        let flushTask = Task {
            try await store.flush()
            await completion.markComplete()
        }
        for _ in 0..<20 { await Task.yield() }
        #expect(!(await completion.isComplete))

        await gate.release()
        try await createTask.value
        try await flushTask.value
        #expect(await completion.isComplete)
        try await store.flush()
    }

    @Test func callbackAuthorizationWaitsForAnInFlightCapabilityRotation() async throws {
        let fixture = try StoreFixture()
        let request = makeRequest(state: .cancelled)
        let initialStore = try PendingDiaryReplyStore(fileURL: fixture.storeURL)
        try await initialStore.create(request)

        let gate = PersistenceGate()
        let live = PendingDiaryReplyPersistence.live
        let persistence = PendingDiaryReplyPersistence { data, url in
            await gate.beginAndWait()
            try await live.write(data, url)
        }
        let store = try PendingDiaryReplyStore(
            fileURL: fixture.storeURL,
            persistence: persistence
        )
        let newRequestCapability = Data(repeating: 0x31, count: 32)
        let newCallbackCapability = Data(repeating: 0x32, count: 32)
        let retryTask = Task {
            try await store.prepareRetry(
                id: request.id,
                capabilityDigest: Data(SHA256.hash(data: newRequestCapability)),
                callbackCapabilityDigest: Data(SHA256.hash(data: newCallbackCapability)),
                now: now.addingTimeInterval(1)
            )
        }
        await gate.waitUntilStarted()

        let started = CompletionProbe()
        let completion = CompletionProbe()
        let authorizationTask = Task {
            await started.markComplete()
            do {
                let authorized = try await store.authorizedCallbackRequest(
                    id: request.id,
                    capability: newCallbackCapability
                )
                await completion.markComplete()
                return authorized
            } catch {
                await completion.markComplete()
                throw error
            }
        }
        while !(await started.isComplete) { await Task.yield() }
        for _ in 0..<20 { await Task.yield() }
        #expect(!(await completion.isComplete))

        await gate.release()
        let retried = try await retryTask.value
        let authorized = try await authorizationTask.value
        #expect(authorized == retried)
        #expect(await completion.isComplete)
    }

    @Test func aCancelledQueuedMutationHandsTheGateToTheNextWaiter() async throws {
        let fixture = try StoreFixture()
        let first = makeRequest(idByte: 0x21)
        let cancelled = makeRequest(idByte: 0x22)
        let final = makeRequest(idByte: 0x23)
        let gate = PersistenceGate()
        let live = PendingDiaryReplyPersistence.live
        let persistence = PendingDiaryReplyPersistence { data, url in
            await gate.beginAndWait()
            try await live.write(data, url)
        }
        let store = try PendingDiaryReplyStore(fileURL: fixture.storeURL, persistence: persistence)
        let firstTask = Task { try await store.create(first) }
        await gate.waitUntilStarted()
        let cancelledTask = Task { try await store.create(cancelled) }
        for _ in 0..<20 { await Task.yield() }
        let finalTask = Task { try await store.create(final) }
        cancelledTask.cancel()

        await gate.release()
        try await firstTask.value
        do {
            try await cancelledTask.value
            Issue.record("Expected queued mutation cancellation")
        } catch is CancellationError {
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
        try await finalTask.value

        #expect(try await store.load(id: first.id) == first)
        #expect(try await store.load(id: cancelled.id) == nil)
        #expect(try await store.load(id: final.id) == final)
    }

    private func makeRequest(
        idByte: UInt8 = 0x11,
        kind: DiaryReplyRequestKind = .diaryTurn,
        createdAt: Date? = nil,
        expiresAt: Date? = nil,
        updatedAt: Date? = nil,
        state: DiaryReplyRequestState = .readyToLaunch,
        attemptCount: Int = 1,
        assistantText: String? = nil,
        historyCommittedAt: Date? = nil,
        prompt: String = "frozen prompt"
    ) -> PendingDiaryReply {
        let id = UUID(uuid: (idByte, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, idByte))
        let createdAt = createdAt ?? now
        return PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: id,
            kind: kind,
            capabilityDigest: digest(requestCapability),
            callbackCapabilityDigest: digest(callbackCapability),
            recognizedText: "recognized words",
            recognitionSource: .appleVision,
            prompt: prompt,
            createdAt: createdAt,
            expiresAt: expiresAt ?? createdAt.addingTimeInterval(600),
            updatedAt: updatedAt ?? createdAt,
            state: state,
            attemptCount: attemptCount,
            lastLaunchAt: createdAt,
            assistantText: assistantText,
            historyCommittedAt: historyCommittedAt,
            terminalReasonCode: {
                switch state {
                case .cancelled: return "shortcut_cancelled"
                case .failed: return DiaryReplyFailureCode.shortcutError.rawValue
                case .expired: return "expired"
                default: return nil
                }
            }()
        )
    }
}

private let requestCapability = Data(repeating: 0x11, count: 32)
private let callbackCapability = Data(repeating: 0x22, count: 32)
private let newRequestCapability = Data(repeating: 0x33, count: 32)
private let newCallbackCapability = Data(repeating: 0x44, count: 32)
private let wrongCapability = Data(repeating: 0xFF, count: 32)

private func digest(_ capability: Data) -> Data {
    try! DiaryReplyCapability(requestID: UUID(), capability: capability).capabilityDigest
}

private func mutateStoredJSON(
    at url: URL,
    mutation: (inout [String: Any], inout [String: Any]) -> Void
) throws {
    var document = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    var records = try #require(document["records"] as? [[String: Any]])
    var record = try #require(records.first)
    mutation(&document, &record)
    records[0] = record
    document["records"] = records
    try JSONSerialization.data(withJSONObject: document).write(to: url)
}

private extension PendingDiaryReply {
    var prefix: String { String(id.uuidString.lowercased().prefix(8)) }
}

private func expectStoreError(
    _ expected: PendingDiaryReplyStore.StoreError,
    operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("Expected store error \(expected)")
    } catch let error as PendingDiaryReplyStore.StoreError {
        #expect(error == expected)
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

private struct StoreFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingDiaryReplyStoreTests-\(UUID().uuidString)", isDirectory: true)
        storeURL = directoryURL.appendingPathComponent("PendingDiaryReplies.json")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

private enum PersistenceProbeError: Error {
    case expected
}

private actor PersistenceCallProbe {
    private(set) var callCount = 0
    func called() { callCount += 1 }
}

private actor CompletionProbe {
    private(set) var isComplete = false
    func markComplete() { isComplete = true }
}

private actor PersistenceGate {
    private var started = false
    private var released = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func beginAndWait() async {
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}
