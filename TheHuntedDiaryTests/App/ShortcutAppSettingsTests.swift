import Foundation
import Testing
@testable import TheHuntedDiary

struct ShortcutAppSettingsTests {
    @Test func defaultsToTheDocumentedReplyShortcutName() {
        let settings = AppSettings()

        #expect(settings.replyShortcutName == "Tom’s Diary Reply")
        #expect(settings.lastVerifiedShortcutName == nil)
        #expect(settings.lastVerifiedAt == nil)
        #expect(settings.activeSetupProbeID == nil)
        #expect(settings.activeSetupShortcutName == nil)
    }

    @Test func persistsConfiguredNameVerificationAndActiveProbeMetadata() throws {
        let defaults = try makeDefaults()
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let probeID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        var settings = AppSettings()
        settings.updateReplyShortcutName("Exact Custom Name")
        settings.markShortcutVerified(name: "Exact Custom Name", at: verifiedAt)
        settings.setActiveSetupProbe(id: probeID, shortcutName: "Exact Custom Name")
        settings.persist(to: defaults)

        let reconstructed = AppSettings(userDefaults: defaults)

        #expect(reconstructed.replyShortcutName == "Exact Custom Name")
        #expect(reconstructed.lastVerifiedShortcutName == "Exact Custom Name")
        #expect(reconstructed.lastVerifiedAt == verifiedAt)
        #expect(reconstructed.activeSetupProbeID == probeID)
        #expect(reconstructed.activeSetupShortcutName == "Exact Custom Name")
    }

    @Test func renamingConfiguredShortcutInvalidatesVerificationAndActiveProbe() {
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let probeID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        var settings = AppSettings()
        settings.markShortcutVerified(name: settings.replyShortcutName, at: verifiedAt)
        settings.setActiveSetupProbe(id: probeID, shortcutName: settings.replyShortcutName)

        settings.updateReplyShortcutName("Renamed Shortcut")

        #expect(settings.replyShortcutName == "Renamed Shortcut")
        #expect(settings.lastVerifiedShortcutName == nil)
        #expect(settings.lastVerifiedAt == nil)
        #expect(settings.activeSetupProbeID == nil)
        #expect(settings.activeSetupShortcutName == nil)
    }

    @Test func assigningTheSameExactNamePreservesVerificationAndProbe() {
        let verifiedAt = Date(timeIntervalSince1970: 1_800_000_100)
        let probeID = UUID(uuidString: "01234567-89ab-cdef-0123-456789abcdef")!
        var settings = AppSettings()
        settings.markShortcutVerified(name: settings.replyShortcutName, at: verifiedAt)
        settings.setActiveSetupProbe(id: probeID, shortcutName: settings.replyShortcutName)

        settings.updateReplyShortcutName(settings.replyShortcutName)

        #expect(settings.lastVerifiedAt == verifiedAt)
        #expect(settings.activeSetupProbeID == probeID)
    }

    @Test func reconstructionRejectsMismatchedOrPartialVerificationMetadata() throws {
        let defaults = try makeDefaults()
        defaults.set("Configured", forKey: AppSettings.PersistenceKey.replyShortcutName)
        defaults.set("Different", forKey: AppSettings.PersistenceKey.lastVerifiedShortcutName)
        defaults.set(Date(timeIntervalSince1970: 1_800_000_100), forKey: AppSettings.PersistenceKey.lastVerifiedAt)
        defaults.set(UUID().uuidString, forKey: AppSettings.PersistenceKey.activeSetupProbeID)

        let reconstructed = AppSettings(userDefaults: defaults)

        #expect(reconstructed.replyShortcutName == "Configured")
        #expect(reconstructed.lastVerifiedShortcutName == nil)
        #expect(reconstructed.lastVerifiedAt == nil)
        #expect(reconstructed.activeSetupProbeID == nil)
        #expect(reconstructed.activeSetupShortcutName == nil)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "ShortcutAppSettingsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
