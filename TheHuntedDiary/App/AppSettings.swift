import Foundation

nonisolated struct AppSettings: Equatable {
    var replyShortcutName: String = "Tom’s Diary Reply"
    var lastVerifiedShortcutName: String?
    var lastVerifiedAt: Date?
    var activeSetupProbeID: UUID?
    var activeSetupShortcutName: String?
    var activeSetupLaunchAccepted = false
    var selectedFontName: String = "Dancing Script"
    var recentHistoryLimit: Int = 12
    var maximumStoredTurns: Int = 100

    enum PersistenceKey {
        static let replyShortcutName = "replyShortcutName"
        static let lastVerifiedShortcutName = "lastVerifiedShortcutName"
        static let lastVerifiedAt = "lastVerifiedAt"
        static let activeSetupProbeID = "activeSetupProbeID"
        static let activeSetupShortcutName = "activeSetupShortcutName"
        static let activeSetupLaunchAccepted = "activeSetupLaunchAccepted"
    }

    init() {}

    init(userDefaults: UserDefaults) {
        self.init()
        if let storedName = userDefaults.string(forKey: PersistenceKey.replyShortcutName) {
            replyShortcutName = storedName
        }

        let verifiedName = userDefaults.string(forKey: PersistenceKey.lastVerifiedShortcutName)
        let verifiedAt = userDefaults.object(forKey: PersistenceKey.lastVerifiedAt) as? Date
        if verifiedName == replyShortcutName, let verifiedAt {
            lastVerifiedShortcutName = verifiedName
            lastVerifiedAt = verifiedAt
        }

        let probeID = userDefaults.string(forKey: PersistenceKey.activeSetupProbeID)
            .flatMap(UUID.init(uuidString:))
        let probeName = userDefaults.string(forKey: PersistenceKey.activeSetupShortcutName)
        if probeName == replyShortcutName, let probeID {
            activeSetupProbeID = probeID
            activeSetupShortcutName = probeName
            activeSetupLaunchAccepted = userDefaults.bool(
                forKey: PersistenceKey.activeSetupLaunchAccepted
            )
        }
    }

    mutating func updateReplyShortcutName(_ name: String) {
        guard name != replyShortcutName else { return }
        replyShortcutName = name
        lastVerifiedShortcutName = nil
        lastVerifiedAt = nil
        activeSetupProbeID = nil
        activeSetupShortcutName = nil
        activeSetupLaunchAccepted = false
    }

    mutating func markShortcutVerified(name: String, at date: Date) {
        guard name == replyShortcutName else { return }
        lastVerifiedShortcutName = name
        lastVerifiedAt = date
        activeSetupProbeID = nil
        activeSetupShortcutName = nil
        activeSetupLaunchAccepted = false
    }

    mutating func setActiveSetupProbe(id: UUID, shortcutName: String) {
        guard shortcutName == replyShortcutName else { return }
        activeSetupProbeID = id
        activeSetupShortcutName = shortcutName
        activeSetupLaunchAccepted = false
    }

    mutating func markActiveSetupLaunchAccepted(id: UUID) {
        guard activeSetupProbeID == id else { return }
        activeSetupLaunchAccepted = true
    }

    mutating func clearActiveSetupProbe() {
        activeSetupProbeID = nil
        activeSetupShortcutName = nil
        activeSetupLaunchAccepted = false
    }

    func persist(to userDefaults: UserDefaults) {
        userDefaults.set(replyShortcutName, forKey: PersistenceKey.replyShortcutName)
        if let lastVerifiedShortcutName, let lastVerifiedAt {
            userDefaults.set(lastVerifiedShortcutName, forKey: PersistenceKey.lastVerifiedShortcutName)
            userDefaults.set(lastVerifiedAt, forKey: PersistenceKey.lastVerifiedAt)
        } else {
            userDefaults.removeObject(forKey: PersistenceKey.lastVerifiedShortcutName)
            userDefaults.removeObject(forKey: PersistenceKey.lastVerifiedAt)
        }

        if let activeSetupProbeID, let activeSetupShortcutName {
            userDefaults.set(activeSetupProbeID.uuidString.lowercased(), forKey: PersistenceKey.activeSetupProbeID)
            userDefaults.set(activeSetupShortcutName, forKey: PersistenceKey.activeSetupShortcutName)
            userDefaults.set(
                activeSetupLaunchAccepted,
                forKey: PersistenceKey.activeSetupLaunchAccepted
            )
        } else {
            userDefaults.removeObject(forKey: PersistenceKey.activeSetupProbeID)
            userDefaults.removeObject(forKey: PersistenceKey.activeSetupShortcutName)
            userDefaults.removeObject(forKey: PersistenceKey.activeSetupLaunchAccepted)
        }
    }
}
