import CryptoKit
import Darwin
import Foundation

nonisolated struct PendingDiaryReplyPersistence: Sendable {
    let beforeWrite: @Sendable () async throws -> Void
    let write: @Sendable (Data, URL) async throws -> Void

    init(write: @escaping @Sendable (Data, URL) async throws -> Void) {
        self.beforeWrite = {}
        self.write = write
    }

    init(
        beforeWrite: @escaping @Sendable () async throws -> Void,
        write: @escaping @Sendable (Data, URL) async throws -> Void
    ) {
        self.beforeWrite = beforeWrite
        self.write = write
    }

    static let live = Self { data, destinationURL in
        try AtomicPendingReplyWriter.write(data, to: destinationURL)
    }
}

nonisolated enum PendingDiaryReplyPersistenceError: Error {
    case replacementCommittedButDirectorySyncFailed
}

actor PendingDiaryReplyStore: Sendable {
    static let currentSchemaVersion = 1
    static let defaultFileName = "PendingDiaryReplies.json"

    nonisolated let fileURL: URL

    private let persistence: PendingDiaryReplyPersistence
    private var records: [UUID: PendingDiaryReply]
    private var mutationInProgress = false
    private var mutationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        fileURL: URL? = nil,
        persistence: PendingDiaryReplyPersistence = .live,
        fileManager: FileManager = .default
    ) throws {
        let resolvedURL: URL
        if let fileURL {
            resolvedURL = fileURL
        } else {
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            resolvedURL = applicationSupport
                .appendingPathComponent("Tom's Diary", isDirectory: true)
                .appendingPathComponent(Self.defaultFileName)
        }

        self.fileURL = resolvedURL
        self.persistence = persistence
        try Self.prepareDirectory(for: resolvedURL, fileManager: fileManager)
        self.records = try Self.loadRecords(from: resolvedURL, fileManager: fileManager)
    }

    func create(_ request: PendingDiaryReply) async throws {
        try await mutate { candidate in
            try Self.validateRequest(request, requireCurrentSchema: true)
            guard candidate[request.id] == nil else {
                throw StoreError.duplicateRequest(requestPrefix(request.id))
            }
            candidate[request.id] = request
        }
    }

    func prepareRetry(
        id: UUID,
        capabilityDigest: Data,
        callbackCapabilityDigest: Data,
        now: Date
    ) async throws -> PendingDiaryReply {
        guard capabilityDigest.count == SHA256.byteCount,
              callbackCapabilityDigest.count == SHA256.byteCount else {
            throw StoreError.invalidRequest(requestPrefix(id))
        }

        return try await mutateRequest(id: id, now: now) { request in
            switch request.state {
            case .readyToLaunch, .awaitingShortcut:
                return request
            case .cancelled:
                break
            case .failed:
                guard let rawCode = request.terminalReasonCode,
                      let failureCode = DiaryReplyFailureCode(rawValue: rawCode),
                      failureCode.isRetryable else {
                    throw StoreError.failureNotRetryable(requestPrefix(id))
                }
            case .replyStored, .historyCommitted, .expired:
                throw StoreError.invalidTransition(
                    requestPrefix(id),
                    request.state,
                    .readyToLaunch
                )
            }

            guard !DiaryReplyCapability.constantTimeEqual(
                request.capabilityDigest,
                capabilityDigest
            ), !DiaryReplyCapability.constantTimeEqual(
                request.callbackCapabilityDigest,
                callbackCapabilityDigest
            ) else {
                throw StoreError.retryCapabilityReuse(requestPrefix(id))
            }

            request.capabilityDigest = capabilityDigest
            request.callbackCapabilityDigest = callbackCapabilityDigest
            request.state = .readyToLaunch
            request.attemptCount += 1
            request.lastLaunchAt = now
            request.updatedAt = now
            request.terminalReasonCode = nil
            return request
        }
    }

    func prompt(id: UUID, capability: Data, now: Date) async throws -> String {
        try await mutateRequest(id: id, now: now) { request in
            try validateRequestCapability(capability, for: request)
            guard request.expiresAt > now else {
                throw StoreError.requestExpired(requestPrefix(id))
            }
            switch request.state {
            case .readyToLaunch:
                request.state = .awaitingShortcut
                request.updatedAt = now
                return request.prompt
            case .awaitingShortcut, .replyStored:
                return request.prompt
            case .historyCommitted, .cancelled, .failed, .expired:
                throw StoreError.invalidTransition(
                    requestPrefix(id),
                    request.state,
                    .awaitingShortcut
                )
            }
        }
    }

    func storeReply(id: UUID, capability: Data, text: String, now: Date) async throws {
        try await mutateRequest(id: id, now: now) { request in
            try validateRequestCapability(capability, for: request)
            guard request.expiresAt > now else {
                throw StoreError.requestExpired(requestPrefix(id))
            }

            switch request.state {
            case .readyToLaunch, .awaitingShortcut:
                request.assistantText = text
                request.state = .replyStored
                request.updatedAt = now
            case .replyStored:
                guard request.assistantText == text else {
                    throw StoreError.conflictingReply(requestPrefix(id))
                }
            case .historyCommitted, .cancelled, .failed, .expired:
                throw StoreError.invalidTransition(
                    requestPrefix(id),
                    request.state,
                    .replyStored
                )
            }
        }
    }

    func markHistoryCommitted(id: UUID, now: Date) async throws {
        try await mutateRequest(id: id, now: now) { request in
            switch request.state {
            case .replyStored:
                guard request.kind == .diaryTurn, request.assistantText != nil else {
                    throw StoreError.invalidTransition(
                        requestPrefix(id),
                        request.state,
                        .historyCommitted
                    )
                }
                request.state = .historyCommitted
                request.historyCommittedAt = now
                request.updatedAt = now
            case .historyCommitted:
                return
            default:
                throw StoreError.invalidTransition(
                    requestPrefix(id),
                    request.state,
                    .historyCommitted
                )
            }
        }
    }

    func markCancelled(id: UUID, capability: Data, now: Date) async throws {
        try await mutateRequest(id: id, now: now) { request in
            try validateCallbackCapability(capability, for: request)
            switch request.state {
            case .readyToLaunch, .awaitingShortcut:
                request.state = .cancelled
                request.updatedAt = now
                request.terminalReasonCode = "shortcut_cancelled"
            case .cancelled:
                return
            default:
                throw StoreError.invalidTransition(
                    requestPrefix(id),
                    request.state,
                    .cancelled
                )
            }
        }
    }

    func markFailed(id: UUID, capability: Data, code: String, now: Date) async throws {
        try await mutateRequest(id: id, now: now) { request in
            try validateCallbackCapability(capability, for: request)
            guard let failureCode = DiaryReplyFailureCode(rawValue: code) else {
                throw StoreError.invalidFailureCode(requestPrefix(id))
            }
            switch request.state {
            case .readyToLaunch, .awaitingShortcut:
                request.state = .failed
                request.updatedAt = now
                request.terminalReasonCode = failureCode.rawValue
            case .failed where request.terminalReasonCode == failureCode.rawValue:
                return
            default:
                throw StoreError.invalidTransition(
                    requestPrefix(id),
                    request.state,
                    .failed
                )
            }
        }
    }

    func load(id: UUID) async throws -> PendingDiaryReply? {
        try await acquireMutation()
        defer { releaseMutation() }
        try Task.checkCancellation()
        return records[id]
    }

    func reconcilableRequests(now: Date) async throws -> [PendingDiaryReply] {
        try await mutate { candidate in
            for (id, var request) in candidate where expireIfNeeded(&request, now: now) {
                candidate[id] = request
            }
            return candidate.values
                .filter {
                    $0.kind == .diaryTurn &&
                    $0.state == .replyStored &&
                    $0.assistantText != nil
                }
                .sorted {
                    if $0.createdAt == $1.createdAt {
                        return $0.id.uuidString < $1.id.uuidString
                    }
                    return $0.createdAt < $1.createdAt
                }
        }
    }

    func removeExpiredAndCommitted(before: Date) async throws {
        try await mutate { candidate in
            candidate = candidate.filter { _, request in
                if request.expiresAt < before {
                    switch request.state {
                    case .readyToLaunch, .awaitingShortcut, .cancelled, .failed, .expired:
                        return false
                    case .replyStored where request.kind == .setupProbe:
                        return false
                    case .replyStored, .historyCommitted:
                        break
                    }
                }
                guard request.updatedAt < before else { return true }
                switch request.state {
                case .historyCommitted, .cancelled, .failed, .expired:
                    return false
                case .replyStored where request.kind == .setupProbe:
                    return false
                case .readyToLaunch, .awaitingShortcut, .replyStored:
                    return true
                }
            }
        }
    }

    func flush() async throws {
        try await acquireMutation()
        defer { releaseMutation() }
        try Task.checkCancellation()
    }
}

extension PendingDiaryReplyStore {
    enum StoreError: Error, Equatable, CustomStringConvertible, LocalizedError {
        case duplicateRequest(String)
        case unknownRequest(String)
        case unsupportedSchemaVersion(Int)
        case unsupportedRequestSchemaVersion(Int)
        case invalidRequest(String)
        case requestExpired(String)
        case invalidCapability(String)
        case invalidTransition(String, DiaryReplyRequestState, DiaryReplyRequestState)
        case conflictingReply(String)
        case retryCapabilityReuse(String)
        case failureNotRetryable(String)
        case invalidFailureCode(String)
        case durableWriteFailed
        case directorySyncFailedAfterCommit

        var description: String {
            switch self {
            case let .duplicateRequest(prefix):
                return "Diary reply request \(prefix)… already exists."
            case let .unknownRequest(prefix):
                return "Diary reply request \(prefix)… was not found."
            case let .unsupportedSchemaVersion(version):
                return "Pending diary reply store version \(version) is unsupported."
            case let .unsupportedRequestSchemaVersion(version):
                return "Pending diary reply request version \(version) is unsupported."
            case let .invalidRequest(prefix):
                return "Diary reply request \(prefix)… is invalid."
            case let .requestExpired(prefix):
                return "Diary reply request \(prefix)… expired."
            case let .invalidCapability(prefix):
                return "Diary reply request \(prefix)… is not authorized."
            case let .invalidTransition(prefix, from, to):
                return "Diary reply request \(prefix)… cannot move from \(from.rawValue) to \(to.rawValue)."
            case let .conflictingReply(prefix):
                return "Diary reply request \(prefix)… already has a different reply."
            case let .retryCapabilityReuse(prefix):
                return "Diary reply request \(prefix)… retry capabilities must both rotate."
            case let .failureNotRetryable(prefix):
                return "Diary reply request \(prefix)… failure is not retryable."
            case let .invalidFailureCode(prefix):
                return "Diary reply request \(prefix)… failure code is invalid."
            case .durableWriteFailed:
                return "Pending diary reply storage could not be updated."
            case .directorySyncFailedAfterCommit:
                return "Pending diary reply storage was replaced but directory synchronization failed."
            }
        }

        var errorDescription: String? { description }
    }
}

private extension PendingDiaryReplyStore {
    struct Document: Codable, Sendable {
        let schemaVersion: Int
        let records: [PendingDiaryReply]
    }

    func mutate<Result: Sendable>(
        _ operation: (inout [UUID: PendingDiaryReply]) throws -> Result
    ) async throws -> Result {
        try await acquireMutation()
        defer { releaseMutation() }
        try Task.checkCancellation()

        var candidate = records
        let result = try operation(&candidate)
        guard candidate != records else { return result }

        try Task.checkCancellation()
        try await commit(candidate)
        return result
    }

    func acquireMutation() async throws {
        try Task.checkCancellation()
        guard mutationInProgress else {
            mutationInProgress = true
            return
        }
        await withCheckedContinuation { mutationWaiters.append($0) }
        if Task.isCancelled {
            releaseMutation()
            throw CancellationError()
        }
    }

    func releaseMutation() {
        guard !mutationWaiters.isEmpty else {
            mutationInProgress = false
            return
        }
        mutationInProgress = true
        mutationWaiters.removeFirst().resume()
    }

    func mutateRequest<Result: Sendable>(
        id: UUID,
        now: Date,
        _ operation: (inout PendingDiaryReply) throws -> Result
    ) async throws -> Result {
        try await acquireMutation()
        defer { releaseMutation() }
        try Task.checkCancellation()

        guard var request = records[id] else {
            throw StoreError.unknownRequest(requestPrefix(id))
        }
        if request.state == .expired || expireIfNeeded(&request, now: now) {
            if records[id] != request {
                var candidate = records
                candidate[id] = request
                try Task.checkCancellation()
                try await commit(candidate)
            }
            throw StoreError.requestExpired(requestPrefix(id))
        }

        let result = try operation(&request)
        guard records[id] != request else { return result }
        var candidate = records
        candidate[id] = request
        try Task.checkCancellation()
        try await commit(candidate)
        return result
    }

    enum CommitOutcome: Equatable {
        case durable
        case replacementCommittedButDirectorySyncFailed
    }

    func commit(_ candidate: [UUID: PendingDiaryReply]) async throws {
        let outcome = try await persist(candidate)
        records = candidate
        if outcome == .replacementCommittedButDirectorySyncFailed {
            throw StoreError.directorySyncFailedAfterCommit
        }
    }

    func persist(_ candidate: [UUID: PendingDiaryReply]) async throws -> CommitOutcome {
        let document = Document(
            schemaVersion: Self.currentSchemaVersion,
            records: candidate.values.sorted { $0.id.uuidString < $1.id.uuidString }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(document)
        } catch {
            throw StoreError.durableWriteFailed
        }

        let persistence = self.persistence
        let fileURL = self.fileURL
        do {
            try await persistence.beforeWrite()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw StoreError.durableWriteFailed
        }
        try Task.checkCancellation()
        let commit = Task.detached(priority: .utility) {
            try await persistence.write(data, fileURL)
        }
        do {
            try await commit.value
            return .durable
        } catch PendingDiaryReplyPersistenceError.replacementCommittedButDirectorySyncFailed {
            return .replacementCommittedButDirectorySyncFailed
        } catch {
            throw StoreError.durableWriteFailed
        }
    }

    func validateRequestCapability(
        _ capability: Data,
        for request: PendingDiaryReply
    ) throws {
        let actualDigest = Data(SHA256.hash(data: capability))
        guard DiaryReplyCapability.constantTimeEqual(actualDigest, request.capabilityDigest) else {
            throw StoreError.invalidCapability(requestPrefix(request.id))
        }
    }

    func validateCallbackCapability(
        _ capability: Data,
        for request: PendingDiaryReply
    ) throws {
        let actualDigest = Data(SHA256.hash(data: capability))
        guard DiaryReplyCapability.constantTimeEqual(
            actualDigest,
            request.callbackCapabilityDigest
        ) else {
            throw StoreError.invalidCapability(requestPrefix(request.id))
        }
    }

    func expireIfNeeded(_ request: inout PendingDiaryReply, now: Date) -> Bool {
        guard request.expiresAt <= now else { return false }
        switch request.state {
        case .readyToLaunch, .awaitingShortcut, .cancelled:
            break
        case .failed:
            guard let rawCode = request.terminalReasonCode,
                  DiaryReplyFailureCode(rawValue: rawCode)?.isRetryable == true else {
                return false
            }
        case .replyStored, .historyCommitted, .expired:
            return false
        }
        request.state = .expired
        request.updatedAt = now
        request.terminalReasonCode = "expired"
        return true
    }

    nonisolated func requestPrefix(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    static func prepareDirectory(for fileURL: URL, fileManager: FileManager) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directoryURL.path
        )
    }

    static func loadRecords(from fileURL: URL, fileManager: FileManager) throws -> [UUID: PendingDiaryReply] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [:] }
        let data = try Data(contentsOf: fileURL)

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let version = object["schemaVersion"] as? Int,
           version > currentSchemaVersion {
            throw StoreError.unsupportedSchemaVersion(version)
        }

        do {
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.schemaVersion >= 0 else {
                throw SemanticCorruption()
            }
            guard document.schemaVersion <= currentSchemaVersion else {
                throw StoreError.unsupportedSchemaVersion(document.schemaVersion)
            }
            var loaded: [UUID: PendingDiaryReply] = [:]
            for decodedRequest in document.records {
                guard decodedRequest.schemaVersion >= 0 else {
                    throw SemanticCorruption()
                }
                guard decodedRequest.schemaVersion <= PendingDiaryReply.currentSchemaVersion else {
                    throw StoreError.unsupportedRequestSchemaVersion(decodedRequest.schemaVersion)
                }
                let request = migrateToCurrentSchema(decodedRequest)
                try validateRequest(request, requireCurrentSchema: true)
                guard loaded.updateValue(request, forKey: request.id) == nil else {
                    throw StoreError.duplicateRequest(requestPrefixStatic(request.id))
                }
            }
            return loaded
        } catch let error as StoreError {
            switch error {
            case .unsupportedSchemaVersion, .unsupportedRequestSchemaVersion:
                throw error
            default:
                try quarantine(fileURL, fileManager: fileManager)
                return [:]
            }
        } catch {
            try quarantine(fileURL, fileManager: fileManager)
            return [:]
        }
    }

    static func quarantine(_ fileURL: URL, fileManager: FileManager) throws {
        let suffix = String(UUID().uuidString.lowercased().prefix(12))
        let quarantineURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent("PendingDiaryReplies.corrupt-\(suffix).json")
        try fileManager.moveItem(at: fileURL, to: quarantineURL)
    }

    static func requestPrefixStatic(_ id: UUID) -> String {
        String(id.uuidString.lowercased().prefix(8))
    }

    static func validateRequest(
        _ request: PendingDiaryReply,
        requireCurrentSchema: Bool
    ) throws {
        if requireCurrentSchema,
           request.schemaVersion != PendingDiaryReply.currentSchemaVersion {
            throw StoreError.unsupportedRequestSchemaVersion(request.schemaVersion)
        }
        guard request.capabilityDigest.count == SHA256.byteCount,
              request.callbackCapabilityDigest.count == SHA256.byteCount,
              request.expiresAt > request.createdAt,
              request.updatedAt >= request.createdAt,
              request.attemptCount >= 0 else {
            throw StoreError.invalidRequest(requestPrefixStatic(request.id))
        }

        switch request.state {
        case .replyStored:
            guard request.assistantText != nil else {
                throw StoreError.invalidRequest(requestPrefixStatic(request.id))
            }
        case .historyCommitted:
            guard request.kind == .diaryTurn,
                  request.assistantText != nil,
                  request.historyCommittedAt != nil else {
                throw StoreError.invalidRequest(requestPrefixStatic(request.id))
            }
        case .cancelled:
            guard request.terminalReasonCode == "shortcut_cancelled" else {
                throw StoreError.invalidRequest(requestPrefixStatic(request.id))
            }
        case .failed:
            guard let rawCode = request.terminalReasonCode,
                  DiaryReplyFailureCode(rawValue: rawCode) != nil else {
                throw StoreError.invalidRequest(requestPrefixStatic(request.id))
            }
        case .expired:
            guard request.terminalReasonCode == "expired" else {
                throw StoreError.invalidRequest(requestPrefixStatic(request.id))
            }
        case .readyToLaunch, .awaitingShortcut:
            break
        }
    }

    static func migrateToCurrentSchema(_ request: PendingDiaryReply) -> PendingDiaryReply {
        guard request.schemaVersion < PendingDiaryReply.currentSchemaVersion else { return request }
        return PendingDiaryReply(
            schemaVersion: PendingDiaryReply.currentSchemaVersion,
            id: request.id,
            kind: request.kind,
            capabilityDigest: request.capabilityDigest,
            callbackCapabilityDigest: request.callbackCapabilityDigest,
            recognizedText: request.recognizedText,
            recognitionSource: request.recognitionSource,
            prompt: request.prompt,
            createdAt: request.createdAt,
            expiresAt: request.expiresAt,
            updatedAt: request.updatedAt,
            state: request.state,
            attemptCount: request.attemptCount,
            lastLaunchAt: request.lastLaunchAt,
            assistantText: request.assistantText,
            historyCommittedAt: request.historyCommittedAt,
            terminalReasonCode: request.terminalReasonCode
        )
    }
}

private struct SemanticCorruption: Error {}

nonisolated private enum AtomicPendingReplyWriter {
    static func write(_ data: Data, to destinationURL: URL) throws {
        let directoryURL = destinationURL.deletingLastPathComponent()
        let temporaryURL = directoryURL.appendingPathComponent(
            ".\(destinationURL.lastPathComponent).\(UUID().uuidString).tmp"
        )
        let descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else { throw POSIXWriteError(code: errno) }

        var isClosed = false
        defer {
            if !isClosed { _ = Darwin.close(descriptor) }
            _ = Darwin.unlink(temporaryURL.path)
        }

        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: temporaryURL.path
        )

        try data.withUnsafeBytes { bytes in
            var remaining = bytes.count
            var pointer = bytes.baseAddress
            while remaining > 0 {
                let count = Darwin.write(descriptor, pointer, remaining)
                guard count > 0 else { throw POSIXWriteError(code: errno) }
                remaining -= count
                pointer = pointer?.advanced(by: count)
            }
        }
        guard Darwin.fsync(descriptor) == 0 else { throw POSIXWriteError(code: errno) }
        guard Darwin.close(descriptor) == 0 else { throw POSIXWriteError(code: errno) }
        isClosed = true

        let directoryDescriptor = Darwin.open(directoryURL.path, O_RDONLY)
        guard directoryDescriptor >= 0 else { throw POSIXWriteError(code: errno) }
        var isDirectoryClosed = false
        defer {
            if !isDirectoryClosed { _ = Darwin.close(directoryDescriptor) }
        }

        guard Darwin.rename(temporaryURL.path, destinationURL.path) == 0 else {
            throw POSIXWriteError(code: errno)
        }

        let directorySyncSucceeded = Darwin.fsync(directoryDescriptor) == 0
        let directoryCloseSucceeded = Darwin.close(directoryDescriptor) == 0
        isDirectoryClosed = true
        guard directorySyncSucceeded, directoryCloseSucceeded else {
            throw PendingDiaryReplyPersistenceError.replacementCommittedButDirectorySyncFailed
        }
    }

    private struct POSIXWriteError: Error {
        let code: Int32
    }
}
