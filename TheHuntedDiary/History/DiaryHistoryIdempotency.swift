import Foundation

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
            return false
        }
        try append(turn)
        return true
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
