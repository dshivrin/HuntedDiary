import Foundation
import Testing
@testable import TheHuntedDiary

struct LegacyCredentialMigrationTests {
    @Test func deletesLegacyCredentialOnceAndPersistsCompletion() throws {
        let defaults = try makeDefaults()
        let recorder = LegacyDeletionRecorder()
        let migration = LegacyCredentialMigration(
            userDefaults: defaults,
            deletion: LegacyCredentialDeletion { try recorder.delete() }
        )

        try migration.runIfNeeded()
        try migration.runIfNeeded()
        let reconstructed = LegacyCredentialMigration(
            userDefaults: defaults,
            deletion: LegacyCredentialDeletion { try recorder.delete() }
        )
        try reconstructed.runIfNeeded()

        #expect(recorder.deleteCount == 1)
        #expect(defaults.bool(forKey: LegacyCredentialMigration.completionKey))
    }

    @Test func failedDeletionIsNotMarkedCompleteAndRetriesLater() throws {
        let defaults = try makeDefaults()
        let recorder = LegacyDeletionRecorder(failuresRemaining: 1)
        let migration = LegacyCredentialMigration(
            userDefaults: defaults,
            deletion: LegacyCredentialDeletion { try recorder.delete() }
        )

        #expect(throws: LegacyDeletionTestError.self) {
            try migration.runIfNeeded()
        }
        #expect(!defaults.bool(forKey: LegacyCredentialMigration.completionKey))
        try migration.runIfNeeded()

        #expect(recorder.deleteCount == 2)
        #expect(defaults.bool(forKey: LegacyCredentialMigration.completionKey))
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "LegacyCredentialMigrationTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private final class LegacyDeletionRecorder {
    private(set) var deleteCount = 0
    private var failuresRemaining: Int

    init(failuresRemaining: Int = 0) {
        self.failuresRemaining = failuresRemaining
    }

    func delete() throws {
        deleteCount += 1
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw LegacyDeletionTestError.failed
        }
    }
}

private enum LegacyDeletionTestError: Error {
    case failed
}
