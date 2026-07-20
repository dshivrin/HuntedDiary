import Foundation

struct HistoryPruner {
    var store: PlainTextHistoryStore

    func pruneOldestTurns(keepingMaximum maximumStoredTurns: Int) throws {
        try store.pruneOldestTurns(keepingMaximum: maximumStoredTurns)
    }
}
