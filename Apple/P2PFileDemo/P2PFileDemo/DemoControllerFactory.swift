import Foundation
import P2PFileSharingSDK

enum DemoControllerFactory {
    static let localDisplayName = "P2P File Demo iPad"
    static let trustedStoreServiceName = "com.p2pfiles.demo.trusted"
    static let identityStoreServiceName = "com.p2pfiles.demo.identity"
    static let supportFolderName = "P2PFileDemo"
    static let transferRecordsFileName = "transfer-records.json"

    static func supportDirectoryURL(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    static func transferRecordFileURL(fileManager: FileManager = .default) -> URL {
        supportDirectoryURL(fileManager: fileManager)
            .appendingPathComponent(supportFolderName, isDirectory: true)
            .appendingPathComponent(transferRecordsFileName)
    }

    @MainActor
    static func make() -> P2PFileSharingBrowserController {
        return P2PFileSharingBrowserController(
            localDisplayName: localDisplayName,
            trustedStore: KeychainPairedDeviceStore(serviceName: trustedStoreServiceName),
            identityProvider: LocalDeviceIdentityStore(serviceName: identityStoreServiceName),
            transferRecordStore: JSONTransferRecordStore(fileURL: transferRecordFileURL()),
            destinationResolver: DemoLocalDocumentsDestinationResolver()
        )
    }
}
