import Foundation

nonisolated enum DiaryHistoryIdempotencyError: Error, Equatable {
    case conflictingTurn(String)
}

protocol IdempotentDiaryHistoryStoring: DiaryHistoryStoring {
    @discardableResult
    func appendIfAbsent(_ turn: ConversationTurn) throws -> Bool
}

extension PlainTextHistoryStore: IdempotentDiaryHistoryStoring {
    @discardableResult
    func appendIfAbsent(_ turn: ConversationTurn) throws -> Bool {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let destination = directoryURL
            .appendingPathComponent(turn.id, isDirectory: false)
            .appendingPathExtension("md")
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            let existing = try loadAll().first { $0.id == turn.id }
            guard existing.map({ Self.serializedEquivalent($0, turn) }) == true else {
                throw DiaryHistoryIdempotencyError.conflictingTurn(turn.id)
            }
            return false
        }
        try append(turn)
        return true
    }

    private static func serializedEquivalent(
        _ lhs: ConversationTurn,
        _ rhs: ConversationTurn
    ) -> Bool {
        lhs.id == rhs.id &&
        ISO8601DateFormatter.history.string(from: lhs.createdAt) ==
            ISO8601DateFormatter.history.string(from: rhs.createdAt) &&
        lhs.recognitionSource == rhs.recognitionSource &&
        lhs.generationProvider == rhs.generationProvider &&
        normalizeLineEndings(lhs.userText) == normalizeLineEndings(rhs.userText) &&
        normalizeLineEndings(lhs.assistantText) == normalizeLineEndings(rhs.assistantText)
    }

    private static func normalizeLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}

final class LegacyIdempotentHistoryStore: IdempotentDiaryHistoryStoring {
    private let base: any DiaryHistoryStoring

    init(_ base: any DiaryHistoryStoring) {
        self.base = base
    }

    func loadRecent(limit: Int) throws -> [ConversationTurn] {
        try base.loadRecent(limit: limit)
    }

    func append(_ turn: ConversationTurn) throws {
        try base.append(turn)
    }

    func appendIfAbsent(_ turn: ConversationTurn) throws -> Bool {
        try base.append(turn)
        return true
    }

    func pruneOldestTurns(keepingMaximum maximumStoredTurns: Int) throws {
        try base.pruneOldestTurns(keepingMaximum: maximumStoredTurns)
    }
}
