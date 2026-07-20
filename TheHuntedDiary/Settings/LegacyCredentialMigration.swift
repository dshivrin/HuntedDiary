import Foundation
import Security

nonisolated struct LegacyCredentialDeletion {
    let perform: () throws -> Void

    init(_ perform: @escaping () throws -> Void) {
        self.perform = perform
    }

    static let keychain = Self {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.TheHuntedDiary.TheHuntedDiary.openai",
            kSecAttrAccount as String: "OpenAIAPIKey"
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LegacyCredentialMigrationError.keychainStatus(status)
        }
    }
}

nonisolated struct LegacyCredentialMigration {
    static let completionKey = "didDeleteLegacyOpenAICredential"

    let userDefaults: UserDefaults
    let deletion: LegacyCredentialDeletion

    init(
        userDefaults: UserDefaults = .standard,
        deletion: LegacyCredentialDeletion = .keychain
    ) {
        self.userDefaults = userDefaults
        self.deletion = deletion
    }

    func runIfNeeded() throws {
        guard !userDefaults.bool(forKey: Self.completionKey) else { return }
        try deletion.perform()
        userDefaults.set(true, forKey: Self.completionKey)
    }
}

nonisolated enum LegacyCredentialMigrationError: Error, Equatable {
    case keychainStatus(OSStatus)
}
