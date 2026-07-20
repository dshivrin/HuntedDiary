import Foundation

nonisolated enum DiaryReplyCallbackEvent: Sendable, Equatable {
    case cancelled
    case failed
}

nonisolated enum DiaryReplyCallbackRejection: Error, Sendable, Equatable, CaseIterable, CustomStringConvertible, LocalizedError {
    case invalidURL
    case requestUnavailable
    case requestUnauthorized
    case requestExpired
    case requestAlreadyCompleted
    case storageUnavailable

    var description: String {
        switch self {
        case .invalidURL:
            return "The Shortcut callback URL is invalid."
        case .requestUnavailable:
            return "The diary reply request is no longer available."
        case .requestUnauthorized:
            return "The Shortcut callback is not authorized."
        case .requestExpired:
            return "The Shortcut callback has expired."
        case .requestAlreadyCompleted:
            return "The diary reply request no longer accepts callbacks."
        case .storageUnavailable:
            return "The Shortcut callback could not be stored."
        }
    }

    var errorDescription: String? { description }
}

nonisolated enum DiaryReplyCallbackResult: Sendable, Equatable {
    case handled(requestID: UUID, event: DiaryReplyCallbackEvent)
    case rejected(DiaryReplyCallbackRejection)
}

actor DiaryReplyFlow: Sendable {
    static let maximumURLUTF8Length = 2_048
    static let maximumExternalErrorCodeUTF8Length = 64
    static let maximumExternalErrorMessageUTF8Length = 512

    private let store: PendingDiaryReplyStore
    private var callbackInProgress = false
    private var callbackWaiters: [CheckedContinuation<Void, Never>] = []

    init(store: PendingDiaryReplyStore) {
        self.store = store
    }

    func handle(_ url: URL, now: Date = Date()) async -> DiaryReplyCallbackResult {
        let callback: ParsedCallback
        do {
            callback = try Self.parse(url)
        } catch {
            return .rejected(.invalidURL)
        }

        await acquireCallbackGate()
        defer { releaseCallbackGate() }

        let request: PendingDiaryReply
        do {
            request = try await store.authorizedCallbackRequest(
                id: callback.authorization.requestID,
                capability: callback.authorization.capability
            )
        } catch let error as PendingDiaryReplyStore.StoreError {
            return .rejected(Self.map(error))
        } catch {
            return .rejected(.storageUnavailable)
        }

        guard request.expiresAt > now else {
            return .rejected(.requestExpired)
        }
        switch request.state {
        case .readyToLaunch, .awaitingShortcut:
            break
        case .replyStored, .historyCommitted, .cancelled, .failed, .expired:
            return .rejected(.requestAlreadyCompleted)
        }

        do {
            switch callback.kind {
            case .cancel:
                try await store.markCancelled(
                    id: callback.authorization.requestID,
                    capability: callback.authorization.capability,
                    now: now
                )
                return .handled(
                    requestID: callback.authorization.requestID,
                    event: .cancelled
                )
            case .error:
                try await store.markFailed(
                    id: callback.authorization.requestID,
                    capability: callback.authorization.capability,
                    code: DiaryReplyFailureCode.shortcutError.rawValue,
                    now: now
                )
                return .handled(
                    requestID: callback.authorization.requestID,
                    event: .failed
                )
            }
        } catch let error as PendingDiaryReplyStore.StoreError {
            return .rejected(Self.map(error))
        } catch {
            return .rejected(.storageUnavailable)
        }
    }

    private func acquireCallbackGate() async {
        guard callbackInProgress else {
            callbackInProgress = true
            return
        }
        await withCheckedContinuation { callbackWaiters.append($0) }
    }

    private func releaseCallbackGate() {
        guard !callbackWaiters.isEmpty else {
            callbackInProgress = false
            return
        }
        callbackWaiters.removeFirst().resume()
    }
}

private extension DiaryReplyFlow {
    enum CallbackKind: Sendable {
        case cancel
        case error
    }

    struct ParsedCallback: Sendable {
        let kind: CallbackKind
        let authorization: DiaryReplyCapability
    }

    nonisolated static func parse(_ url: URL) throws -> ParsedCallback {
        guard url.baseURL == nil,
              url.absoluteString.utf8.count <= maximumURLUTF8Length,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == ShortcutCallbacks.callbackScheme,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.fragment == nil,
              components.path.isEmpty,
              components.percentEncodedPath.isEmpty else {
            throw DiaryReplyCallbackRejection.invalidURL
        }

        let kind: CallbackKind
        let allowedKeys: Set<String>
        switch components.host {
        case "shortcut-cancel":
            kind = .cancel
            allowedKeys = ["id", "token"]
        case "shortcut-error":
            kind = .error
            allowedKeys = ["id", "token", "errorCode", "errorMessage"]
        default:
            throw DiaryReplyCallbackRejection.invalidURL
        }

        guard let queryItems = components.queryItems else {
            throw DiaryReplyCallbackRejection.invalidURL
        }
        var values: [String: String] = [:]
        for item in queryItems {
            guard allowedKeys.contains(item.name),
                  values[item.name] == nil,
                  let value = item.value else {
                throw DiaryReplyCallbackRejection.invalidURL
            }
            values[item.name] = value
        }
        guard let id = values["id"],
              let token = values["token"],
              values.keys.contains("id"),
              values.keys.contains("token"),
              Set(values.keys).isSubset(of: allowedKeys),
              id.utf8.count == 36,
              let requestID = UUID(uuidString: id),
              id == requestID.uuidString.lowercased(),
              token.utf8.count == DiaryReplyCapability.encodedCapabilityLength else {
            throw DiaryReplyCallbackRejection.invalidURL
        }

        if kind == .cancel, Set(values.keys) != allowedKeys {
            throw DiaryReplyCallbackRejection.invalidURL
        }
        if let errorCode = values["errorCode"],
           errorCode.utf8.count > maximumExternalErrorCodeUTF8Length {
            throw DiaryReplyCallbackRejection.invalidURL
        }
        if let errorMessage = values["errorMessage"],
           errorMessage.utf8.count > maximumExternalErrorMessageUTF8Length {
            throw DiaryReplyCallbackRejection.invalidURL
        }

        let authorization: DiaryReplyCapability
        do {
            authorization = try DiaryReplyCapability(handle: "\(id).\(token)")
        } catch {
            throw DiaryReplyCallbackRejection.invalidURL
        }
        return ParsedCallback(kind: kind, authorization: authorization)
    }

    nonisolated static func map(
        _ error: PendingDiaryReplyStore.StoreError
    ) -> DiaryReplyCallbackRejection {
        switch error {
        case .unknownRequest:
            return .requestUnavailable
        case .invalidCapability:
            return .requestUnauthorized
        case .requestExpired:
            return .requestExpired
        case .invalidTransition:
            return .requestAlreadyCompleted
        case .durableWriteFailed, .directorySyncFailedAfterCommit:
            return .storageUnavailable
        case .duplicateRequest, .unsupportedSchemaVersion,
             .unsupportedRequestSchemaVersion, .invalidRequest,
             .conflictingReply, .retryCapabilityReuse,
             .failureNotRetryable, .invalidFailureCode:
            return .storageUnavailable
        }
    }
}
