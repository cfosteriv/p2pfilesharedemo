#if DEBUG
import Foundation
import Security

enum DemoDebugResetCoordinator {
    static let firstLaunchResetCompletionKey =
        "com.p2pfilesharing.did-complete-first-launch-keychain-reset"

    static let defaultServiceNames = [
        DemoControllerFactory.trustedStoreServiceName,
        DemoControllerFactory.identityStoreServiceName,
        "com.p2pfilesharing.trusted-devices",
        "com.p2pfilesharing.identity",
    ]

    static func reset(
        serviceNames: [String] = defaultServiceNames,
        transferRecordFileURL: URL = DemoControllerFactory.transferRecordFileURL(),
        userDefaults: UserDefaults = .standard,
        deleteKeychainItems: (String) -> OSStatus = deleteAllKeychainItems(serviceName:)
    ) throws {
        for serviceName in serviceNames {
            let status = deleteKeychainItems(serviceName)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw DemoDebugResetError.keychainDeleteFailed(serviceName: serviceName, status: status)
            }
        }

        if FileManager.default.fileExists(atPath: transferRecordFileURL.path) {
            try FileManager.default.removeItem(at: transferRecordFileURL)
        }

        userDefaults.removeObject(forKey: firstLaunchResetCompletionKey)
    }

    private static func deleteAllKeychainItems(serviceName: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        return SecItemDelete(query as CFDictionary)
    }
}

private enum DemoDebugResetError: LocalizedError {
    case keychainDeleteFailed(serviceName: String, status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychainDeleteFailed(let serviceName, let status):
            return "Could not clear debug pairing state for \(serviceName) (status \(status))."
        }
    }
}
#endif
