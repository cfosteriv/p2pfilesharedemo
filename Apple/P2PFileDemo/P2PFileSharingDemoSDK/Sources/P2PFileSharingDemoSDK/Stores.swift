import CryptoKit
import Foundation
import Security

public actor MemoryPairedDeviceStore: PairedDeviceStore {
    private var devices: [UUID: PairedDevice]

    public init(initialDevices: [PairedDevice] = []) {
        self.devices = Dictionary(uniqueKeysWithValues: initialDevices.map { ($0.id, $0) })
    }

    public func save(_ device: PairedDevice) async throws {
        devices[device.id] = device
    }

    public func loadAll() async throws -> [PairedDevice] {
        devices.values.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func remove(deviceID: UUID) async throws {
        devices.removeValue(forKey: deviceID)
    }
}

public actor MemoryTransferRecordStore: TransferRecordStore {
    private var records: [TransferRecord]

    public init(initialRecords: [TransferRecord] = []) {
        self.records = initialRecords
    }

    public func save(_ record: TransferRecord) async throws {
        records.removeAll { $0.remoteDeviceID == record.remoteDeviceID && $0.remoteFileID == record.remoteFileID }
        records.append(record)
    }

    public func loadAll() async throws -> [TransferRecord] {
        records
    }
}

public actor JSONTransferRecordStore: TransferRecordStore {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ record: TransferRecord) async throws {
        var records = try loadAll()
        records.removeAll { $0.remoteDeviceID == record.remoteDeviceID && $0.remoteFileID == record.remoteFileID }
        records.append(record)
        try persist(records.sorted { $0.completedAt > $1.completedAt })
    }

    public func loadAll() throws -> [TransferRecord] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.p2p.decode([TransferRecord].self, from: data)
    }

    private func persist(_ records: [TransferRecord]) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder.p2p.encode(records)
        try data.write(to: fileURL, options: [.atomic])
    }
}

public actor KeychainPairedDeviceStore: PairedDeviceStore {
    static let defaultServiceName = "com.p2pfilesharing.trusted-devices"
    private let serviceName: String

    public init(serviceName: String = "com.p2pfilesharing.trusted-devices") {
        P2PFileSharingFirstLaunchKeychainResetCoordinator.shared.performIfNeeded(
            serviceNames: [
                KeychainPairedDeviceStore.defaultServiceName,
                LocalDeviceIdentityStore.defaultServiceName
            ]
        )
        self.serviceName = serviceName
    }

    public func save(_ device: PairedDevice) async throws {
        let data = try JSONEncoder.p2p.encode(device)
        let baseQuery = keychainQuery(account: device.id.uuidString)
        SecItemDelete(baseQuery as CFDictionary)
        var insert = baseQuery
        insert[kSecValueData as String] = data
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw P2PFileSharingError.localStorageUnavailable("Keychain save failed with status \(status).")
        }
    }

    public func loadAll() async throws -> [PairedDevice] {
        var query = keychainQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw P2PFileSharingError.localStorageUnavailable("Keychain read failed with status \(status).")
        }
        guard let array = result as? [[String: Any]] else {
            return []
        }
        return try array.compactMap { item in
            guard let data = item[kSecValueData as String] as? Data else { return nil }
            return try JSONDecoder.p2p.decode(PairedDevice.self, from: data)
        }.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func remove(deviceID: UUID) async throws {
        let status = SecItemDelete(keychainQuery(account: deviceID.uuidString) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw P2PFileSharingError.localStorageUnavailable("Keychain delete failed with status \(status).")
        }
    }

    private func keychainQuery(account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
        ]
        if let account {
            query[kSecAttrAccount as String] = account
        }
        return query
    }
}

public protocol LocalIdentityProviding: Sendable {
    func currentIdentity(displayName: String?) async throws -> LocalDeviceIdentity
    func sign(_ payload: Data) async throws -> Data
}

public actor LocalDeviceIdentityStore: LocalIdentityProviding {
    static let defaultServiceName = "com.p2pfilesharing.identity"
    private let serviceName: String
    private let account = "local-device-identity"

    public init(serviceName: String = "com.p2pfilesharing.identity") {
        P2PFileSharingFirstLaunchKeychainResetCoordinator.shared.performIfNeeded(
            serviceNames: [
                KeychainPairedDeviceStore.defaultServiceName,
                LocalDeviceIdentityStore.defaultServiceName
            ]
        )
        self.serviceName = serviceName
    }

    public func currentIdentity(displayName: String?) async throws -> LocalDeviceIdentity {
        let state = try loadOrCreateState(displayName: displayName)
        return LocalDeviceIdentity(
            deviceID: state.deviceID,
            displayName: state.displayName,
            publicKeyRepresentation: normalizedPublicKeyRepresentation(for: state.privateKey.publicKey.rawRepresentation)
        )
    }

    public func sign(_ payload: Data) async throws -> Data {
        let state = try loadOrCreateState(displayName: nil)
        return try state.privateKey.signature(for: payload).rawRepresentation
    }

    private func loadOrCreateState(displayName: String?) throws -> IdentityState {
        if let existing = try loadState() {
            return existing.displayName == (displayName ?? existing.displayName)
                ? existing
                : try updateDisplayName(existing, displayName: displayName ?? existing.displayName)
        }

        let privateKey = P256.Signing.PrivateKey()
        let state = IdentityState(
            deviceID: UUID(),
            displayName: displayName ?? "P2P File Sharing Device",
            privateKey: privateKey
        )
        try save(state: state)
        return state
    }

    private func loadState() throws -> IdentityState? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw P2PFileSharingError.localStorageUnavailable("Identity read failed with status \(status).")
        }
        let payload = try JSONDecoder.p2p.decode(IdentityPayload.self, from: data)
        return try IdentityState(payload: payload)
    }

    private func updateDisplayName(_ state: IdentityState, displayName: String) throws -> IdentityState {
        let updated = IdentityState(deviceID: state.deviceID, displayName: displayName, privateKey: state.privateKey)
        try save(state: updated)
        return updated
    }

    private func save(state: IdentityState) throws {
        let data = try JSONEncoder.p2p.encode(IdentityPayload(from: state))
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw P2PFileSharingError.localStorageUnavailable("Identity save failed with status \(status).")
        }
    }

    private func normalizedPublicKeyRepresentation(for rawRepresentation: Data) -> Data {
        if rawRepresentation.count == 65, rawRepresentation.first == 0x04 {
            return rawRepresentation
        }

        if rawRepresentation.count == 64 {
            return Data([0x04]) + rawRepresentation
        }

        return rawRepresentation
    }

    private struct IdentityPayload: Codable {
        let deviceID: UUID
        let displayName: String
        let privateKey: Data

        init(from state: IdentityState) {
            deviceID = state.deviceID
            displayName = state.displayName
            privateKey = state.privateKey.rawRepresentation
        }
    }

    private struct IdentityState {
        let deviceID: UUID
        let displayName: String
        let privateKey: P256.Signing.PrivateKey

        init(deviceID: UUID, displayName: String, privateKey: P256.Signing.PrivateKey) {
            self.deviceID = deviceID
            self.displayName = displayName
            self.privateKey = privateKey
        }

        init(payload: IdentityPayload) throws {
            deviceID = payload.deviceID
            displayName = payload.displayName
            privateKey = try P256.Signing.PrivateKey(rawRepresentation: payload.privateKey)
        }
    }
}

public struct UbiquitousContainerDestinationResolver: LocalDestinationResolving {
    private let containerIdentifier: String?

    public init(
        containerIdentifier: String? = nil,
        applicationFolderName: String,
        importedFolderName: String = "Imported Files"
    ) {
        self.containerIdentifier = containerIdentifier
    }

    public func destinationURL(for device: PairedDevice, file: RemoteFile) throws -> URL {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw P2PFileSharingError.localStorageUnavailable("The iCloud ubiquitous container is unavailable.")
        }
        let documentsRoot = root.appendingPathComponent("Documents", isDirectory: true)
        return try makeFlattenedDestinationURL(
            baseDirectoryURL: documentsRoot,
            device: device,
            file: file
        )
    }

    public func candidateLocalFileURLs(for device: PairedDevice, file: RemoteFile) throws -> [URL] {
        guard let root = FileManager.default.url(forUbiquityContainerIdentifier: containerIdentifier) else {
            throw P2PFileSharingError.localStorageUnavailable("The iCloud ubiquitous container is unavailable.")
        }
        let documentsRoot = root.appendingPathComponent("Documents", isDirectory: true)
        return try candidateLocalFileURLsInRootDirectory(
            rootDirectory: documentsRoot,
            device: device,
            file: file
        )
    }
}

public struct ManifestComparator: Sendable {
    public init() {}

    public func compare(
        manifest: RemoteFileManifest,
        transferRecords: [TransferRecord]
    ) -> [ManifestFileStatus] {
        let recordMap = Dictionary(
            uniqueKeysWithValues: transferRecords.map { ("\($0.remoteDeviceID.uuidString)::\($0.remoteFileID)", $0) }
        )

        return manifest.files.map { file in
            guard file.isEligible else {
                return ManifestFileStatus(file: file, status: .unavailable)
            }

            let key = "\(manifest.deviceID.uuidString)::\(file.id)"
            guard let record = recordMap[key] else {
                return ManifestFileStatus(file: file, status: .pending)
            }

            let url = record.localFileURL
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ManifestFileStatus(file: file, status: .pending)
            }

            if record.contentHash == file.contentHash,
               record.byteSize == file.byteSize,
               record.modifiedAt == file.modifiedAt {
                return ManifestFileStatus(file: file, status: .transferred(url))
            }

            return ManifestFileStatus(file: file, status: .changedRemotely(url))
        }
    }
}

struct AtomicVerifiedFileWriter {
    private let destinationURL: URL
    private let temporaryURL: URL
    private let fileHandle: FileHandle
    private var hasher = SHA256()
    private var bytesWritten: Int64 = 0
    private var isClosed = false
    private var isCommitted = false

    init(destinationURL: URL, fileManager: FileManager = .default) throws {
        self.destinationURL = destinationURL
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        temporaryURL = destinationURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("partial")
        fileManager.createFile(atPath: temporaryURL.path, contents: nil)
        fileHandle = try FileHandle(forWritingTo: temporaryURL)
    }

    mutating func append(_ data: Data) throws {
        try fileHandle.write(contentsOf: data)
        hasher.update(data: data)
        bytesWritten += Int64(data.count)
    }

    mutating func complete(expectedSize: Int64, expectedHash: String, fileManager: FileManager = .default) throws {
        try closeIfNeeded()
        let actualHash = Data(hasher.finalize()).hexString
        guard bytesWritten == expectedSize else {
            try? fileManager.removeItem(at: temporaryURL)
            throw P2PFileSharingError.invalidHash(expected: "\(expectedSize)", actual: "\(bytesWritten)")
        }
        guard actualHash == expectedHash else {
            try? fileManager.removeItem(at: temporaryURL)
            throw P2PFileSharingError.invalidHash(expected: expectedHash, actual: actualHash)
        }
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
        isCommitted = true
    }

    mutating func discard(fileManager: FileManager = .default) {
        try? closeIfNeeded()
        guard !isCommitted else { return }
        guard fileManager.fileExists(atPath: temporaryURL.path) else { return }
        try? fileManager.removeItem(at: temporaryURL)
    }

    private mutating func closeIfNeeded() throws {
        guard !isClosed else { return }
        try fileHandle.close()
        isClosed = true
    }
}

func candidateLocalFileURLsInRootDirectory(
    rootDirectory: URL,
    device: PairedDevice,
    file: RemoteFile,
    fileManager: FileManager = .default
) throws -> [URL] {
    let preferredURL = try makeFlattenedDestinationURL(
        baseDirectoryURL: rootDirectory,
        device: device,
        file: file
    )
    let normalizedRelativePath = try normalizeRelativePath(file.relativePath)
    let relativeComponents = normalizedRelativePath.split(separator: "/").map(String.init)

    guard fileManager.fileExists(atPath: rootDirectory.path) else {
        return [preferredURL]
    }

    let topLevelDirectories = try fileManager.contentsOfDirectory(
        at: rootDirectory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )

    var candidates = [preferredURL]
    for directoryURL in topLevelDirectories {
        let isDirectory = try directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory ?? false
        guard isDirectory else { continue }

        let candidateURL = relativeComponents.reduce(directoryURL) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }

        if candidateURL != preferredURL {
            candidates.append(candidateURL)
        }
    }

    return candidates
}
