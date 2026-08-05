import Foundation
import SwiftData

@Model
final class SwiftDataTransferRecordEntity {
    @Attribute(.unique) var recordKey: String
    var remoteDeviceID: UUID
    var remoteFileID: String
    var relativePath: String
    var byteSize: Int64
    var modifiedAt: Date
    var contentHash: String
    var localFilePath: String
    var completedAt: Date

    init(record: TransferRecord) {
        recordKey = Self.recordKey(remoteDeviceID: record.remoteDeviceID, remoteFileID: record.remoteFileID)
        remoteDeviceID = record.remoteDeviceID
        remoteFileID = record.remoteFileID
        relativePath = record.relativePath
        byteSize = record.byteSize
        modifiedAt = record.modifiedAt
        contentHash = record.contentHash
        localFilePath = record.localFilePath
        completedAt = record.completedAt
    }

    func update(with record: TransferRecord) {
        recordKey = Self.recordKey(remoteDeviceID: record.remoteDeviceID, remoteFileID: record.remoteFileID)
        remoteDeviceID = record.remoteDeviceID
        remoteFileID = record.remoteFileID
        relativePath = record.relativePath
        byteSize = record.byteSize
        modifiedAt = record.modifiedAt
        contentHash = record.contentHash
        localFilePath = record.localFilePath
        completedAt = record.completedAt
    }

    func transferRecord() -> TransferRecord {
        TransferRecord(
            remoteDeviceID: remoteDeviceID,
            remoteFileID: remoteFileID,
            relativePath: relativePath,
            byteSize: byteSize,
            modifiedAt: modifiedAt,
            contentHash: contentHash,
            localFilePath: localFilePath,
            completedAt: completedAt
        )
    }

    static func recordKey(remoteDeviceID: UUID, remoteFileID: String) -> String {
        "\(remoteDeviceID.uuidString)::\(remoteFileID)"
    }
}

public actor SwiftDataTransferRecordStore: TransferRecordStore {
    private let container: ModelContainer

    public init(
        fileURL: URL? = nil,
        isStoredInMemoryOnly: Bool = false,
        fileManager: FileManager = .default
    ) throws {
        let configuration: ModelConfiguration
        if isStoredInMemoryOnly {
            configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        } else {
            let resolvedURL = fileURL ?? Self.defaultStoreURL(fileManager: fileManager)
            try fileManager.createDirectory(
                at: resolvedURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            configuration = ModelConfiguration(url: resolvedURL)
        }

        container = try ModelContainer(
            for: SwiftDataTransferRecordEntity.self,
            configurations: configuration
        )
    }

    public func save(_ record: TransferRecord) throws {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SwiftDataTransferRecordEntity>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        let existing = try context.fetch(descriptor).first {
            $0.remoteDeviceID == record.remoteDeviceID && $0.remoteFileID == record.remoteFileID
        }

        if let existing {
            existing.update(with: record)
        } else {
            context.insert(SwiftDataTransferRecordEntity(record: record))
        }

        try context.save()
    }

    public func loadAll() throws -> [TransferRecord] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<SwiftDataTransferRecordEntity>(
            sortBy: [SortDescriptor(\.completedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { $0.transferRecord() }
    }

    private static func defaultStoreURL(fileManager: FileManager) -> URL {
        let baseDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseDirectory
            .appendingPathComponent("P2PFileSharingSDK", isDirectory: true)
            .appendingPathComponent("TransferRecords.store")
    }
}
