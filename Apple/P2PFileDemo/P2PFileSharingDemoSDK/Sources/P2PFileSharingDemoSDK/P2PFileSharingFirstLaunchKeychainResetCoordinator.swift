import Foundation
import Security

final class P2PFileSharingFirstLaunchKeychainResetCoordinator: @unchecked Sendable {
    static let defaultCompletionKey = "com.p2pfilesharing.did-complete-first-launch-keychain-reset"
    static let shared = P2PFileSharingFirstLaunchKeychainResetCoordinator()

    private let userDefaults: UserDefaults
    private let completionKey: String
    private let deleteKeychainItems: (String) -> OSStatus
    private let lock = NSLock()

    init(
        userDefaults: UserDefaults = .standard,
        completionKey: String = defaultCompletionKey,
        deleteKeychainItems: ((String) -> OSStatus)? = nil
    ) {
        self.userDefaults = userDefaults
        self.completionKey = completionKey
        self.deleteKeychainItems = deleteKeychainItems ?? Self.deleteAllItems(serviceName:)
    }

    func performIfNeeded(serviceNames: [String]) {
        lock.lock()
        defer { lock.unlock() }

        guard !userDefaults.bool(forKey: completionKey) else {
            return
        }

        let normalizedServiceNames = Array(
            Set(
                serviceNames.compactMap { serviceName in
                    let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
                    return trimmed.isEmpty ? nil : trimmed
                }
            )
        ).sorted()

        var encounteredFailure = false

        for serviceName in normalizedServiceNames {
            let status = deleteKeychainItems(serviceName)
            switch status {
            case errSecSuccess, errSecItemNotFound:
                continue
            default:
                encounteredFailure = true
                P2PFileSharingDebugLog.log(
                    "First-launch keychain cleanup failed for service '\(serviceName)' with status \(status)."
                )
            }
        }

        guard !encounteredFailure else {
            return
        }

        userDefaults.set(true, forKey: completionKey)
    }

    private static func deleteAllItems(serviceName: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName
        ]
        return SecItemDelete(query as CFDictionary)
    }
}
