import CryptoKit
import Foundation
import P2PFileSharingSDK
import Security
import Testing
@testable import P2PFileDemo

struct P2PFileTests {

    @Test func localResolverBuildsNestedDestinationPath() throws {
        let rootDirectory = URL(fileURLWithPath: "/tmp/p2p-demo-tests", isDirectory: true)
        let resolver = DemoLocalDocumentsDestinationResolver(rootDirectory: rootDirectory)
        let device = PairedDevice(
            id: UUID(uuidString: "D7843322-A482-4B11-8670-B24477BB1F79")!,
            displayName: "Studio Workstation",
            serviceName: "studio-workstation",
            serverFingerprint: "fingerprint",
            protocolVersion: 1,
            capabilities: ["manifest", "download"]
        )
        let file = RemoteFile(
            id: "stone/specs/granite.pdf",
            relativePath: "Stone/Specs/granite.pdf",
            name: "granite.pdf",
            fileExtension: "pdf",
            byteSize: 1024,
            modifiedAt: Date(timeIntervalSince1970: 1_754_352_000),
            contentHash: "abc123"
        )

        let destination = try resolver.destinationURL(for: device, file: file)

        #expect(
            destination.path
                == "/tmp/p2p-demo-tests/Studio Workstation/Stone/Specs/granite.pdf"
        )
    }

    @Test func localResolverRejectsPathTraversal() throws {
        let rootDirectory = URL(fileURLWithPath: "/tmp/p2p-demo-tests", isDirectory: true)
        let resolver = DemoLocalDocumentsDestinationResolver(rootDirectory: rootDirectory)
        let device = PairedDevice(
            id: UUID(uuidString: "D7843322-A482-4B11-8670-B24477BB1F79")!,
            displayName: "Studio/Workstation",
            serviceName: "studio-workstation",
            serverFingerprint: "fingerprint",
            protocolVersion: 1,
            capabilities: ["manifest", "download"]
        )
        let file = RemoteFile(
            id: "secret",
            relativePath: "../secret.txt",
            name: "secret.txt",
            fileExtension: "txt",
            byteSize: 32,
            modifiedAt: Date(timeIntervalSince1970: 1_754_352_000),
            contentHash: "def456"
        )

        do {
            _ = try resolver.destinationURL(for: device, file: file)
            Issue.record("Expected path traversal to be rejected.")
        } catch let error as P2PFileSharingError {
            #expect(error == .pathTraversalDetected)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func reconcilerRecoversSavedStatusFromExistingLocalFileWithoutTransferRecord() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = DemoLocalDocumentsDestinationResolver(rootDirectory: rootDirectory)
        let recordStore = MemoryTransferRecordStore()
        let device = PairedDevice(
            id: UUID(uuidString: "D7843322-A482-4B11-8670-B24477BB1F79")!,
            displayName: "Surface Studio",
            serviceName: "surface-studio",
            serverFingerprint: "fingerprint",
            protocolVersion: 1,
            capabilities: ["manifest", "download"]
        )
        let contents = Data("Granite spec".utf8)
        let file = RemoteFile(
            id: "stone/specs/granite.txt",
            relativePath: "Stone/Specs/granite.txt",
            name: "granite.txt",
            fileExtension: "txt",
            byteSize: Int64(contents.count),
            modifiedAt: Date(timeIntervalSince1970: 1_754_352_000),
            contentHash: sha256Hex(of: contents)
        )

        let legacyDeviceFolder = rootDirectory.appendingPathComponent("Old Surface Name", isDirectory: true)
        let legacyDestination = try resolver.relativePathComponents(for: file.relativePath).reduce(legacyDeviceFolder) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }
        try FileManager.default.createDirectory(
            at: legacyDestination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: legacyDestination.path, contents: contents)

        let records = try await DemoSavedFileReconciler.reconcileTransferRecords(
            for: device,
            files: [file],
            recordStore: recordStore,
            destinationResolver: resolver
        )
        let statuses = ManifestComparator().compare(
            manifest: RemoteFileManifest(deviceID: device.id, files: [file]),
            transferRecords: records
        )

        #expect(statuses.count == 1)
        switch statuses[0].status {
        case .transferred(let url):
            #expect(url == legacyDestination)
        default:
            Issue.record("Expected existing local file to be recognized as saved.")
        }
    }

    @Test func reconcilerMarksMismatchedLocalFileAsChangedRemotelyWithoutTransferRecord() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let resolver = DemoLocalDocumentsDestinationResolver(rootDirectory: rootDirectory)
        let recordStore = MemoryTransferRecordStore()
        let device = PairedDevice(
            id: UUID(uuidString: "D7843322-A482-4B11-8670-B24477BB1F79")!,
            displayName: "Surface Studio",
            serviceName: "surface-studio",
            serverFingerprint: "fingerprint",
            protocolVersion: 1,
            capabilities: ["manifest", "download"]
        )
        let remoteContents = Data("Granite spec".utf8)
        let localContents = Data("Updated slate".utf8)
        let file = RemoteFile(
            id: "stone/specs/granite.txt",
            relativePath: "Stone/Specs/granite.txt",
            name: "granite.txt",
            fileExtension: "txt",
            byteSize: Int64(remoteContents.count),
            modifiedAt: Date(timeIntervalSince1970: 1_754_352_000),
            contentHash: sha256Hex(of: remoteContents)
        )

        let destination = try resolver.destinationURL(for: device, file: file)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: destination.path, contents: localContents)

        let records = try await DemoSavedFileReconciler.reconcileTransferRecords(
            for: device,
            files: [file],
            recordStore: recordStore,
            destinationResolver: resolver
        )
        let statuses = ManifestComparator().compare(
            manifest: RemoteFileManifest(deviceID: device.id, files: [file]),
            transferRecords: records
        )

        #expect(statuses.count == 1)
        switch statuses[0].status {
        case .changedRemotely(let url):
            #expect(url == destination)
        default:
            Issue.record("Expected mismatched local file to be marked as changed remotely.")
        }
    }

#if DEBUG
    @Test func debugResetClearsStoredPairingArtifacts() throws {
        let defaultsSuiteName = "P2PFileTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: defaultsSuiteName) else {
            Issue.record("Could not create isolated user defaults suite.")
            return
        }

        let transferRecordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("transfer-records.json")

        try FileManager.default.createDirectory(
            at: transferRecordURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("[]".utf8).write(to: transferRecordURL)
        defaults.set(true, forKey: DemoDebugResetCoordinator.firstLaunchResetCompletionKey)

        var deletedServiceNames: [String] = []

        try DemoDebugResetCoordinator.reset(
            serviceNames: ["trusted", "identity"],
            transferRecordFileURL: transferRecordURL,
            userDefaults: defaults,
            deleteKeychainItems: { serviceName in
                deletedServiceNames.append(serviceName)
                return errSecSuccess
            }
        )

        #expect(deletedServiceNames == ["trusted", "identity"])
        #expect(!FileManager.default.fileExists(atPath: transferRecordURL.path))
        #expect(defaults.object(forKey: DemoDebugResetCoordinator.firstLaunchResetCompletionKey) == nil)

        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }
#endif

}

private func sha256Hex(of data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
