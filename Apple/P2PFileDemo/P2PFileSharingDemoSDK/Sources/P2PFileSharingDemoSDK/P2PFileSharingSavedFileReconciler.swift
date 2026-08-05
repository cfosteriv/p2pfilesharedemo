import Foundation

enum P2PFileSharingSavedFileReconciler {
    static func reconcileTransferRecords(
        for device: PairedDevice,
        files: [RemoteFile],
        recordStore: any TransferRecordStore,
        destinationResolver: any LocalDestinationResolving
    ) async throws -> [TransferRecord] {
        let existingRecords = try await recordStore.loadAll()
        let existingRecordMap = Dictionary(
            uniqueKeysWithValues: existingRecords.map { ("\($0.remoteDeviceID.uuidString)::\($0.remoteFileID)", $0) }
        )

        for file in files where file.isEligible {
            let key = "\(device.id.uuidString)::\(file.id)"
            let existingRecord = existingRecordMap[key]

            if let synthesizedRecord = try synthesizeTransferRecord(
                for: device,
                file: file,
                existingRecord: existingRecord,
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
        existingRecord: TransferRecord?,
        destinationResolver: any LocalDestinationResolving
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
                        localFilePath: candidate.path,
                        completedAt: existingRecord?.completedAt ?? .now
                    )
                }

                fallbackRecord = TransferRecord(
                    remoteDeviceID: device.id,
                    remoteFileID: file.id,
                    relativePath: file.relativePath,
                    byteSize: localMetadata.byteSize,
                    modifiedAt: localMetadata.modifiedAt,
                    contentHash: localHash,
                    localFilePath: candidate.path,
                    completedAt: existingRecord?.completedAt ?? .now
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
                    localFilePath: candidate.path,
                    completedAt: existingRecord?.completedAt ?? .now
                )
            }
        }

        return fallbackRecord
    }
}
