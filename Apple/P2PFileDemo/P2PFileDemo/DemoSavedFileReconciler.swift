import CryptoKit
import Foundation
import P2PFileSharingSDK

enum DemoSavedFileReconciler {
    @MainActor
    static func reconcile(
        controller: P2PFileSharingBrowserController,
        device: PairedDevice,
        recordStore: (any TransferRecordStore)? = nil,
        destinationResolver: DemoLocalDocumentsDestinationResolver = DemoLocalDocumentsDestinationResolver()
    ) async {
        guard controller.activeDevice?.id == device.id else { return }

        let files = controller.manifestStatuses.map(\.file)
        guard !files.isEmpty else { return }
        let activeRecordStore = recordStore
            ?? JSONTransferRecordStore(fileURL: DemoControllerFactory.transferRecordFileURL())

        do {
            let records = try await reconcileTransferRecords(
                for: device,
                files: files,
                recordStore: activeRecordStore,
                destinationResolver: destinationResolver
            )

            let manifest = RemoteFileManifest(deviceID: device.id, files: files)
            controller.manifestStatuses = ManifestComparator().compare(
                manifest: manifest,
                transferRecords: records
            )
        } catch {
            controller.bannerMessage = error.localizedDescription
        }
    }

    static func reconcileTransferRecords(
        for device: PairedDevice,
        files: [RemoteFile],
        recordStore: any TransferRecordStore,
        destinationResolver: DemoLocalDocumentsDestinationResolver
    ) async throws -> [TransferRecord] {
        let existingRecords = try await recordStore.loadAll()
        let existingRecordMap = Dictionary(
            uniqueKeysWithValues: existingRecords.map { ("\($0.remoteDeviceID.uuidString)::\($0.remoteFileID)", $0) }
        )

        for file in files where file.isEligible {
            let key = "\(device.id.uuidString)::\(file.id)"
            if let record = existingRecordMap[key],
               FileManager.default.fileExists(atPath: record.localFileURL.path) {
                continue
            }

            if let synthesizedRecord = try synthesizeTransferRecord(
                for: device,
                file: file,
                destinationResolver: destinationResolver
            ) {
                try await recordStore.save(synthesizedRecord)
            }
        }

        return try await recordStore.loadAll()
    }

    private static func synthesizeTransferRecord(
        for device: PairedDevice,
        file: RemoteFile,
        destinationResolver: DemoLocalDocumentsDestinationResolver
    ) throws -> TransferRecord? {
        let candidates = try destinationResolver.candidateLocalFileURLs(for: device, file: file)
        var fallbackRecord: TransferRecord?

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            let localMetadata = try localFileMetadata(for: candidate)

            if localMetadata.byteSize == file.byteSize {
                let localHash = try sha256Hex(for: candidate)
                if localHash == file.contentHash {
                    return TransferRecord(
                        remoteDeviceID: device.id,
                        remoteFileID: file.id,
                        relativePath: file.relativePath,
                        byteSize: file.byteSize,
                        modifiedAt: file.modifiedAt,
                        contentHash: file.contentHash,
                        localFilePath: candidate.path
                    )
                }

                fallbackRecord = TransferRecord(
                    remoteDeviceID: device.id,
                    remoteFileID: file.id,
                    relativePath: file.relativePath,
                    byteSize: localMetadata.byteSize,
                    modifiedAt: localMetadata.modifiedAt,
                    contentHash: localHash,
                    localFilePath: candidate.path
                )
                continue
            }

            if fallbackRecord == nil {
                fallbackRecord = TransferRecord(
                    remoteDeviceID: device.id,
                    remoteFileID: file.id,
                    relativePath: file.relativePath,
                    byteSize: localMetadata.byteSize,
                    modifiedAt: localMetadata.modifiedAt,
                    contentHash: try sha256Hex(for: candidate),
                    localFilePath: candidate.path
                )
            }
        }

        return fallbackRecord
    }

    private static func localFileMetadata(for fileURL: URL) throws -> (byteSize: Int64, modifiedAt: Date) {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
        return (byteSize, modifiedAt)
    }

    private static func sha256Hex(for fileURL: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        while true {
            let data = try fileHandle.read(upToCount: 64 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
