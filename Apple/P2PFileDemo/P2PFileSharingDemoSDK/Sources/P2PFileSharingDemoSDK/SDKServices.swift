import Foundation

public actor P2PFileSharingDevicePairingService: DevicePairing {
    private let store: PairedDeviceStore
    private let transportFactory: @Sendable (PairingPayload) -> any PairingTransport

    public init(
        store: PairedDeviceStore,
        transportFactory: @escaping @Sendable (PairingPayload) -> any PairingTransport
    ) {
        self.store = store
        self.transportFactory = transportFactory
    }

    public func pair(using payload: PairingPayload, localDisplayName: String?) async throws -> PairedDevice {
        P2PFileSharingDebugLog.log("Starting SDK pairing with payload: \(P2PFileSharingDebugLog.describe(payload)) localDisplayName=\(localDisplayName ?? "<nil>")")
        do {
            try payload.validate()
            let device = try await transportFactory(payload).bootstrapPairing(using: payload, localDisplayName: localDisplayName)
            try await store.save(device)
            P2PFileSharingDebugLog.log("SDK pairing succeeded with paired device: \(P2PFileSharingDebugLog.describe(device))")
            return device
        } catch {
            P2PFileSharingDebugLog.log(error: error, context: "SDK pairing failed")
            throw error
        }
    }

    public func trustedDevices() async throws -> [PairedDevice] {
        try await store.loadAll()
    }

    public func removeTrust(for deviceID: UUID) async throws {
        try await store.remove(deviceID: deviceID)
    }
}

public actor MockDeviceDiscovery: DeviceDiscovering {
    private var snapshotsContinuation: AsyncStream<[DiscoveredDevice]>.Continuation?
    private var devices: [DiscoveredDevice]

    public init(devices: [DiscoveredDevice]) {
        self.devices = devices
    }

    public func discoveredDevices() async -> AsyncStream<[DiscoveredDevice]> {
        AsyncStream { continuation in
            snapshotsContinuation = continuation
            continuation.yield(devices)
        }
    }

    public func start() async throws {
        snapshotsContinuation?.yield(devices)
    }

    public func stop() async {
        snapshotsContinuation?.finish()
        snapshotsContinuation = nil
    }

    public func updateDevices(_ devices: [DiscoveredDevice]) async {
        self.devices = devices
        snapshotsContinuation?.yield(devices)
    }
}

public struct MockTransportFaultPlan: Sendable {
    public var chunkSize: Int
    public var chunkLatency: Duration
    public var disconnectAfterBytes: [String: Int64]
    public var invalidHashFileIDs: Set<String>
    public var revokedDeviceIDs: Set<UUID>

    public init(
        chunkSize: Int = 32 * 1024,
        chunkLatency: Duration = .milliseconds(10),
        disconnectAfterBytes: [String: Int64] = [:],
        invalidHashFileIDs: Set<String> = [],
        revokedDeviceIDs: Set<UUID> = []
    ) {
        self.chunkSize = chunkSize
        self.chunkLatency = chunkLatency
        self.disconnectAfterBytes = disconnectAfterBytes
        self.invalidHashFileIDs = invalidHashFileIDs
        self.revokedDeviceIDs = revokedDeviceIDs
    }
}

public struct MockRemoteCatalog: Sendable {
    public let discoveredDevice: DiscoveredDevice
    public let pairedDevice: PairedDevice
    public let manifest: RemoteFileManifest
    public let fileContents: [String: Data]
    public let activePairingToken: String

    public init(
        discoveredDevice: DiscoveredDevice,
        pairedDevice: PairedDevice,
        manifest: RemoteFileManifest,
        fileContents: [String: Data],
        activePairingToken: String
    ) {
        self.discoveredDevice = discoveredDevice
        self.pairedDevice = pairedDevice
        self.manifest = manifest
        self.fileContents = fileContents
        self.activePairingToken = activePairingToken
    }

    public static func sample(now: Date = .now) -> MockRemoteCatalog {
        let deviceID = UUID(uuidString: "1A340DA0-CEB8-47F6-8EAB-74B140A3BB31")!
        let discovered = DiscoveredDevice(
            id: deviceID,
            displayName: "Studio Workstation",
            serviceName: "studio-workstation",
            protocolVersion: 1,
            capabilities: ["manifest", "download", "hash-sha256"],
            pairingRequired: true,
            isCompatible: true
        )
        let contentsA = Data("Quartz slab specification".utf8)
        let contentsB = Data("Installation photography".utf8)
        let fileA = RemoteFile(
            id: "catalog/specs/quartz.txt",
            relativePath: "Specifications/Quartz/quartz.txt",
            name: "quartz.txt",
            fileExtension: "txt",
            byteSize: Int64(contentsA.count),
            modifiedAt: now,
            contentHash: sha256Hex(of: contentsA),
            mimeType: "text/plain",
            logicalGrouping: "Specifications"
        )
        let fileB = RemoteFile(
            id: "catalog/photos/install.jpg",
            relativePath: "Photos/install.jpg",
            name: "install.jpg",
            fileExtension: "jpg",
            byteSize: Int64(contentsB.count),
            modifiedAt: now,
            contentHash: sha256Hex(of: contentsB),
            mimeType: "image/jpeg",
            logicalGrouping: "Photos"
        )
        let manifest = RemoteFileManifest(deviceID: deviceID, generatedAt: now, files: [fileA, fileB])
        let paired = PairedDevice(
            id: deviceID,
            displayName: discovered.displayName,
            serviceName: discovered.serviceName,
            serverFingerprint: "mock-server-fingerprint",
            protocolVersion: 1,
            capabilities: discovered.capabilities
        )
        return MockRemoteCatalog(
            discoveredDevice: discovered,
            pairedDevice: paired,
            manifest: manifest,
            fileContents: [fileA.id: contentsA, fileB.id: contentsB],
            activePairingToken: "pair-token-\(deviceID.uuidString.prefix(8))"
        )
    }
}

public actor MockFileTransferTransport: FileTransferTransport, PairingTransport {
    private let catalog: MockRemoteCatalog
    private let faultPlan: MockTransportFaultPlan
    private var connectedDevice: PairedDevice?
    private var cancelledFileIDs = Set<String>()

    public init(catalog: MockRemoteCatalog = .sample(), faultPlan: MockTransportFaultPlan = .init()) {
        self.catalog = catalog
        self.faultPlan = faultPlan
    }

    public func bootstrapPairing(using payload: PairingPayload, localDisplayName: String?) async throws -> PairedDevice {
        try payload.validate()
        guard payload.deviceID == catalog.pairedDevice.id,
              payload.pairingToken == catalog.activePairingToken else {
            throw P2PFileSharingError.authenticationFailed
        }
        return catalog.pairedDevice
    }

    public func connect(to device: PairedDevice) async throws {
        guard !faultPlan.revokedDeviceIDs.contains(device.id) else {
            throw P2PFileSharingError.revokedDevice
        }
        connectedDevice = device
    }

    public func disconnect() async {
        connectedDevice = nil
    }

    public func fetchManifest() async throws -> RemoteFileManifest {
        guard connectedDevice?.id == catalog.manifest.deviceID else {
            throw P2PFileSharingError.notConnected
        }
        return catalog.manifest
    }

    public func transfer(file: RemoteFile, to destination: URL) async -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard connectedDevice?.id == catalog.pairedDevice.id else {
                        throw P2PFileSharingError.notConnected
                    }
                    guard let contents = catalog.fileContents[file.id] else {
                        throw P2PFileSharingError.fileUnavailable
                    }

                    continuation.yield(TransferProgress(fileID: file.id, state: .queued, bytesTransferred: 0, totalBytes: file.byteSize))
                    var writer = try AtomicVerifiedFileWriter(destinationURL: destination)
                    var shouldDiscardPartial = true
                    defer {
                        if shouldDiscardPartial {
                            writer.discard()
                        }
                    }
                    var offset = 0
                    var totalTransferred: Int64 = 0
                    let disconnectThreshold = faultPlan.disconnectAfterBytes[file.id]

                    while offset < contents.count {
                        if await self.isTransferCancelled(file.id) || Task.isCancelled {
                            await self.clearCancelledTransfer(file.id)
                            throw P2PFileSharingError.transferCancelled
                        }

                        let end = min(contents.count, offset + faultPlan.chunkSize)
                        var chunk = contents.subdata(in: offset ..< end)
                        if faultPlan.invalidHashFileIDs.contains(file.id), end == contents.count, !chunk.isEmpty {
                            chunk[chunk.startIndex] ^= 0xFF
                        }
                        try writer.append(chunk)
                        offset = end
                        totalTransferred += Int64(chunk.count)
                        continuation.yield(
                            TransferProgress(
                                fileID: file.id,
                                state: .transferring,
                                bytesTransferred: totalTransferred,
                                totalBytes: file.byteSize
                            )
                        )

                        if let threshold = disconnectThreshold, totalTransferred >= threshold {
                            throw P2PFileSharingError.connectionFailed("The mock connection dropped mid-transfer.")
                        }
                        try await Task.sleep(for: faultPlan.chunkLatency)
                    }

                    continuation.yield(TransferProgress(fileID: file.id, state: .verifying, bytesTransferred: file.byteSize, totalBytes: file.byteSize))
                    try writer.complete(expectedSize: file.byteSize, expectedHash: file.contentHash)
                    shouldDiscardPartial = false
                    continuation.yield(TransferProgress(fileID: file.id, state: .completed, bytesTransferred: file.byteSize, totalBytes: file.byteSize))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancelTransfer(for fileID: String) async {
        cancelledFileIDs.insert(fileID)
    }

    private func isTransferCancelled(_ fileID: String) async -> Bool {
        cancelledFileIDs.contains(fileID)
    }

    private func clearCancelledTransfer(_ fileID: String) async {
        cancelledFileIDs.remove(fileID)
    }
}
