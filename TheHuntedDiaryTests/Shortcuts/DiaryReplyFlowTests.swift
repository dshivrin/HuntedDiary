import CryptoKit
import Foundation
import Testing
@testable import TheHuntedDiary

struct DiaryReplyFlowTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func authenticatedCancelMarksTheMatchingRequestCancelled() async throws {
        let fixture = try await FlowFixture(now: now)
        let result = await fixture.flow.handle(fixture.callbacks.cancelURL, now: now)

        #expect(result == .handled(requestID: fixture.requestID, event: .cancelled))
        let stored = try #require(await fixture.store.load(id: fixture.requestID))
        #expect(stored.state == .cancelled)
        #expect(stored.terminalReasonCode == "shortcut_cancelled")
    }

    @Test func authenticatedErrorMapsBoundedExternalFieldsToClosedFailureCode() async throws {
        let fixture = try await FlowFixture(now: now)
        let externalMessage = "private arbitrary external failure detail"
        let url = try callbackURL(
            host: "shortcut-error",
            requestID: fixture.requestID,
            token: fixture.callbackToken,
            extraItems: [
                URLQueryItem(name: "errorCode", value: "anything-external"),
                URLQueryItem(name: "errorMessage", value: externalMessage),
            ]
        )

        let result = await fixture.flow.handle(url, now: now)

        #expect(result == .handled(requestID: fixture.requestID, event: .failed))
        let stored = try #require(await fixture.store.load(id: fixture.requestID))
        #expect(stored.state == .failed)
        #expect(stored.terminalReasonCode == DiaryReplyFailureCode.shortcutError.rawValue)
        #expect(stored.terminalReasonCode != externalMessage)
    }

    @Test func forgedTokenAndUnknownRequestAreRejectedWithoutMutation() async throws {
        let fixture = try await FlowFixture(now: now)
        let forgedToken = try token(for: Data(repeating: 0xEE, count: 32), requestID: fixture.requestID)
        let forgedURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: fixture.requestID,
            token: forgedToken
        )
        #expect(await fixture.flow.handle(forgedURL, now: now) == .rejected(.requestUnauthorized))

        let unknownID = UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
        let unknownURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: unknownID,
            token: fixture.callbackToken
        )
        #expect(await fixture.flow.handle(unknownURL, now: now) == .rejected(.requestUnauthorized))
        #expect(try await fixture.store.load(id: fixture.requestID)?.state == .readyToLaunch)
    }

    @Test func forgedTokenCannotProbeExpiredOrCompletedRequestState() async throws {
        let expired = try await FlowFixture(now: now)
        let expiredForgedToken = try token(
            for: Data(repeating: 0xEE, count: 32),
            requestID: expired.requestID
        )
        let expiredForgedURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: expired.requestID,
            token: expiredForgedToken
        )
        #expect(
            await expired.flow.handle(
                expiredForgedURL,
                now: now.addingTimeInterval(601)
            ) == .rejected(.requestUnauthorized)
        )

        let completed = try await FlowFixture(now: now, idByte: 0x45)
        try await completed.store.storeReply(
            id: completed.requestID,
            capability: completed.requestCapability,
            text: "stored reply",
            now: now
        )
        let completedForgedToken = try token(
            for: Data(repeating: 0xEF, count: 32),
            requestID: completed.requestID
        )
        let completedForgedURL = try callbackURL(
            host: "shortcut-error",
            requestID: completed.requestID,
            token: completedForgedToken
        )
        #expect(
            await completed.flow.handle(completedForgedURL, now: now)
                == .rejected(.requestUnauthorized)
        )

        let historyCommitted = try await FlowFixture(now: now, idByte: 0x46)
        try await historyCommitted.store.storeReply(
            id: historyCommitted.requestID,
            capability: historyCommitted.requestCapability,
            text: "stored reply",
            now: now
        )
        try await historyCommitted.store.markHistoryCommitted(
            id: historyCommitted.requestID,
            now: now
        )
        let historyForgedURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: historyCommitted.requestID,
            token: try token(
                for: Data(repeating: 0xED, count: 32),
                requestID: historyCommitted.requestID
            )
        )
        #expect(
            await historyCommitted.flow.handle(historyForgedURL, now: now)
                == .rejected(.requestUnauthorized)
        )

        let cancelled = try await FlowFixture(now: now, idByte: 0x47)
        #expect(await cancelled.flow.handle(cancelled.callbacks.cancelURL, now: now).isHandled)
        let cancelledForgedURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: cancelled.requestID,
            token: try token(
                for: Data(repeating: 0xEC, count: 32),
                requestID: cancelled.requestID
            )
        )
        #expect(
            await cancelled.flow.handle(cancelledForgedURL, now: now)
                == .rejected(.requestUnauthorized)
        )

        let failed = try await FlowFixture(now: now, idByte: 0x48)
        #expect(await failed.flow.handle(failed.callbacks.errorURL, now: now).isHandled)
        let failedForgedURL = try callbackURL(
            host: "shortcut-error",
            requestID: failed.requestID,
            token: try token(
                for: Data(repeating: 0xEB, count: 32),
                requestID: failed.requestID
            )
        )
        #expect(
            await failed.flow.handle(failedForgedURL, now: now)
                == .rejected(.requestUnauthorized)
        )

        let terminallyExpired = try await FlowFixture(now: now, idByte: 0x49)
        _ = try await terminallyExpired.store.reconcilableRequests(
            now: now.addingTimeInterval(601)
        )
        let terminallyExpiredForgedURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: terminallyExpired.requestID,
            token: try token(
                for: Data(repeating: 0xEA, count: 32),
                requestID: terminallyExpired.requestID
            )
        )
        #expect(
            await terminallyExpired.flow.handle(
                terminallyExpiredForgedURL,
                now: now.addingTimeInterval(602)
            ) == .rejected(.requestUnauthorized)
        )
    }

    @Test func replayAndCallbacksAfterReplyCompletionAreRejected() async throws {
        let fixture = try await FlowFixture(now: now)
        #expect(await fixture.flow.handle(fixture.callbacks.cancelURL, now: now).isHandled)
        #expect(await fixture.flow.handle(fixture.callbacks.cancelURL, now: now) == .rejected(.requestAlreadyCompleted))

        let completed = try await FlowFixture(now: now, idByte: 0x44)
        try await completed.store.storeReply(
            id: completed.requestID,
            capability: completed.requestCapability,
            text: "stored reply",
            now: now
        )
        #expect(await completed.flow.handle(completed.callbacks.errorURL, now: now) == .rejected(.requestAlreadyCompleted))
        #expect(try await completed.store.load(id: completed.requestID)?.assistantText == "stored reply")
    }

    @Test func oldCallbackCapabilityIsRejectedAfterRetryRotation() async throws {
        let fixture = try await FlowFixture(now: now)
        #expect(await fixture.flow.handle(fixture.callbacks.cancelURL, now: now).isHandled)

        let newRequestCapability = Data(repeating: 0x33, count: 32)
        let newCallbackCapability = Data(repeating: 0x44, count: 32)
        _ = try await fixture.store.prepareRetry(
            id: fixture.requestID,
            capabilityDigest: Data(SHA256.hash(data: newRequestCapability)),
            callbackCapabilityDigest: Data(SHA256.hash(data: newCallbackCapability)),
            now: now.addingTimeInterval(1)
        )

        #expect(
            await fixture.flow.handle(
                fixture.callbacks.cancelURL,
                now: now.addingTimeInterval(2)
            ) == .rejected(.requestUnauthorized)
        )

        let currentCallbacks = try ShortcutCallbacks(
            requestID: fixture.requestID,
            callbackCapability: newCallbackCapability
        )
        #expect(
            await fixture.flow.handle(
                currentCallbacks.cancelURL,
                now: now.addingTimeInterval(2)
            ) == .handled(requestID: fixture.requestID, event: .cancelled)
        )
        #expect(try await fixture.store.load(id: fixture.requestID)?.attemptCount == 2)
    }

    @Test func expiredCallbackIsRejectedWithoutAcceptingItsBearerCapability() async throws {
        let fixture = try await FlowFixture(now: now)
        let result = await fixture.flow.handle(
            fixture.callbacks.cancelURL,
            now: now.addingTimeInterval(601)
        )

        #expect(result == .rejected(.requestExpired))
        #expect(try await fixture.store.load(id: fixture.requestID)?.state == .readyToLaunch)
    }

    @Test func rejectsMalformedCallbackURLShapesAndQueries() async throws {
        let fixture = try await FlowFixture(now: now)
        let id = fixture.requestID.uuidString.lowercased()
        let token = fixture.callbackToken
        let malformed = [
            "wrong-scheme://shortcut-cancel?id=\(id)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://wrong-host?id=\(id)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel/path?id=\(id)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://user@shortcut-cancel?id=\(id)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel:123?id=\(id)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id)&token=\(token)#fragment",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id)&id=\(id)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id)&token=\(token)&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id)&token=\(token)&unknown=value",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id.uppercased())&token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?token=\(token)",
            "\(ShortcutCallbacks.callbackScheme)://shortcut-cancel?id=\(id)&token=",
        ]

        for value in malformed {
            let url = try #require(URL(string: value))
            #expect(await fixture.flow.handle(url, now: now) == .rejected(.invalidURL))
        }
        #expect(try await fixture.store.load(id: fixture.requestID)?.state == .readyToLaunch)
    }

    @Test func rejectsOversizedURLTokenAndExternalErrorFields() async throws {
        let fixture = try await FlowFixture(now: now)
        let oversizedURL = try #require(URL(string:
            "\(ShortcutCallbacks.callbackScheme)://shortcut-error?id=\(fixture.requestID.uuidString.lowercased())&token=\(fixture.callbackToken)&errorMessage=\(String(repeating: "a", count: DiaryReplyFlow.maximumURLUTF8Length))"
        ))
        #expect(await fixture.flow.handle(oversizedURL, now: now) == .rejected(.invalidURL))

        let oversizedTokenURL = try callbackURL(
            host: "shortcut-cancel",
            requestID: fixture.requestID,
            token: fixture.callbackToken + "a"
        )
        #expect(await fixture.flow.handle(oversizedTokenURL, now: now) == .rejected(.invalidURL))

        let oversizedCodeURL = try callbackURL(
            host: "shortcut-error",
            requestID: fixture.requestID,
            token: fixture.callbackToken,
            extraItems: [URLQueryItem(
                name: "errorCode",
                value: String(repeating: "a", count: DiaryReplyFlow.maximumExternalErrorCodeUTF8Length + 1)
            )]
        )
        #expect(await fixture.flow.handle(oversizedCodeURL, now: now) == .rejected(.invalidURL))

        let oversizedMessageURL = try callbackURL(
            host: "shortcut-error",
            requestID: fixture.requestID,
            token: fixture.callbackToken,
            extraItems: [URLQueryItem(
                name: "errorMessage",
                value: String(repeating: "a", count: DiaryReplyFlow.maximumExternalErrorMessageUTF8Length + 1)
            )]
        )
        #expect(await fixture.flow.handle(oversizedMessageURL, now: now) == .rejected(.invalidURL))
        #expect(try await fixture.store.load(id: fixture.requestID)?.state == .readyToLaunch)
    }

    @Test func rejectsDuplicateExternalErrorFieldsAndFieldsOnCancelHost() async throws {
        let fixture = try await FlowFixture(now: now)
        let duplicateError = try callbackURL(
            host: "shortcut-error",
            requestID: fixture.requestID,
            token: fixture.callbackToken,
            extraItems: [
                URLQueryItem(name: "errorCode", value: "one"),
                URLQueryItem(name: "errorCode", value: "two"),
            ]
        )
        #expect(await fixture.flow.handle(duplicateError, now: now) == .rejected(.invalidURL))

        let cancelWithError = try callbackURL(
            host: "shortcut-cancel",
            requestID: fixture.requestID,
            token: fixture.callbackToken,
            extraItems: [URLQueryItem(name: "errorMessage", value: "must be rejected")]
        )
        #expect(await fixture.flow.handle(cancelWithError, now: now) == .rejected(.invalidURL))
    }

    @Test func reconstructedFlowHandlesDeliveryWithoutActiveInMemoryRequestOrSceneState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryReplyFlowReconstruction-\(UUID().uuidString)", isDirectory: true)
        let fileURL = directory.appendingPathComponent(PendingDiaryReplyStore.defaultFileName)
        let initial = try await FlowFixture(now: now, fileURL: fileURL, persistence: .live)
        let reconstructedStore = try PendingDiaryReplyStore(fileURL: fileURL)
        let reconstructedFlow = DiaryReplyFlow(store: reconstructedStore)

        let result = await reconstructedFlow.handle(initial.callbacks.cancelURL, now: now)

        #expect(result == .handled(requestID: initial.requestID, event: .cancelled))
        #expect(try await reconstructedStore.load(id: initial.requestID)?.state == .cancelled)
    }

    @Test func appBundleRegistersOnlyTheStrictCallbackSchemeForThisURLType() throws {
        let urlTypes = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        let callbackType = try #require(urlTypes.first { $0["CFBundleURLName"] as? String == "com.TheHuntedDiary.shortcut-callback" })
        #expect(callbackType["CFBundleTypeRole"] as? String == "Editor")
        #expect(callbackType["CFBundleURLSchemes"] as? [String] == [ShortcutCallbacks.callbackScheme])
    }

    @Test func callbackDiagnosticsAreBoundedAndContainNoURLCapabilityOrExternalText() async throws {
        let fixture = try await FlowFixture(now: now)
        for rejection in DiaryReplyCallbackRejection.allCases {
            #expect(rejection.description.count < 128)
            #expect(!rejection.description.contains(fixture.callbackToken))
            #expect(!rejection.description.contains("external failure"))
            #expect(!rejection.description.contains("diary text"))
        }
        let rejected = DiaryReplyCallbackResult.rejected(.invalidURL)
        #expect(!String(reflecting: rejected).contains(fixture.callbackToken))
    }

    private func callbackURL(
        host: String,
        requestID: UUID,
        token: String,
        extraItems: [URLQueryItem] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = ShortcutCallbacks.callbackScheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: "id", value: requestID.uuidString.lowercased()),
            URLQueryItem(name: "token", value: token),
        ] + extraItems
        return try #require(components.url)
    }

    private func token(for capability: Data, requestID: UUID) throws -> String {
        let handle = try DiaryReplyCapability(requestID: requestID, capability: capability).handle
        return String(handle.suffix(DiaryReplyCapability.encodedCapabilityLength))
    }
}

private struct FlowFixture {
    let now: Date
    let requestID: UUID
    let requestCapability: Data
    let callbackCapability: Data
    let callbackToken: String
    let callbacks: ShortcutCallbacks
    let store: PendingDiaryReplyStore
    let flow: DiaryReplyFlow

    init(
        now: Date,
        idByte: UInt8 = 0x01,
        fileURL: URL? = nil,
        persistence: PendingDiaryReplyPersistence = PendingDiaryReplyPersistence { _, _ in }
    ) async throws {
        self.now = now
        requestID = UUID(uuid: (idByte, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16))
        requestCapability = Data(repeating: 0x11, count: 32)
        callbackCapability = Data(repeating: 0x22, count: 32)
        let requestAuthorization = try DiaryReplyCapability(
            requestID: requestID,
            capability: requestCapability
        )
        callbacks = try ShortcutCallbacks(
            requestID: requestID,
            callbackCapability: callbackCapability
        )
        let callbackHandle = try DiaryReplyCapability(
            requestID: requestID,
            capability: callbackCapability
        ).handle
        callbackToken = String(callbackHandle.suffix(DiaryReplyCapability.encodedCapabilityLength))
        let resolvedURL = fileURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("DiaryReplyFlowTests-\(UUID().uuidString).json")
        store = try PendingDiaryReplyStore(fileURL: resolvedURL, persistence: persistence)
        flow = DiaryReplyFlow(store: store)
        try await store.create(PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: requestID,
            kind: .diaryTurn,
            capabilityDigest: requestAuthorization.capabilityDigest,
            callbackCapabilityDigest: callbacks.callbackCapabilityDigest,
            recognizedText: "private recognized diary text",
            recognitionSource: .appleVision,
            prompt: "private frozen prompt",
            createdAt: now,
            expiresAt: now.addingTimeInterval(600),
            updatedAt: now,
            state: .readyToLaunch,
            attemptCount: 1,
            lastLaunchAt: now,
            assistantText: nil,
            historyCommittedAt: nil,
            terminalReasonCode: nil
        ))
    }
}

private extension DiaryReplyCallbackResult {
    var isHandled: Bool {
        if case .handled = self { return true }
        return false
    }
}
