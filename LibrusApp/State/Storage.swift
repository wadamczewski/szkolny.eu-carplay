import Foundation
import LibrusKit
import Security

/// Refresh tokens live only in the Keychain (this device, after first unlock).
enum KeychainStore {
    private static let service = "librus-ios.accounts"
    private static let key = "accounts"

    static func loadAccounts() -> [StoredAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return [] }
        return (try? JSONDecoder().decode([StoredAccount].self, from: data)) ?? []
    }

    static func saveAccounts(_ accounts: [StoredAccount]) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        guard let data = try? JSONEncoder().encode(accounts) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        if SecItemUpdate(base as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(base.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }
}

/// Last downloaded data per student, for instant start and offline viewing.
enum DataCache {
    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func file(for profileID: String) -> URL {
        directory.appendingPathComponent(profileID.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    static func load(_ profileID: String) -> StudentData? {
        guard let data = try? Data(contentsOf: file(for: profileID)) else { return nil }
        return try? JSONDecoder().decode(StudentData.self, from: data)
    }

    static func save(_ studentData: StudentData, for profileID: String) {
        guard let data = try? JSONEncoder().encode(studentData) else { return }
        try? data.write(to: file(for: profileID), options: [.atomic, .completeFileProtection])
    }

    static func remove(_ profileID: String) {
        try? FileManager.default.removeItem(at: file(for: profileID))
    }
}
