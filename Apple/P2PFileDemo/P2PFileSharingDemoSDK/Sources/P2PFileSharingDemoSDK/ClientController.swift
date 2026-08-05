import Foundation
import Observation

@MainActor
@Observable
public final class P2PFileSharingBrowserController {
    enum DeviceRowActivity: Equatable, Sendable {
        case idle
        case connecting
        case authenticating
        case refreshingManifest
        case disconnecting
        case removingTrust

        var showsProgress: Bool {
            self != .idle
        }

        var title: String {
            switch self {
            case .idle:
                return ""
            case .connecting:
                return "Connecting"
            case .authenticating:
                return "Authenticating"
            case .refreshingManifest:
                return "Loading Files"
            case .disconnecting:
                return "Disconnecting"
            case .removingTrust:
                return "Removing Trust"
            }
        }
    }

    public enum ConnectionAttemptOutcome: Equatable, Sendable {
        case connected(PairedDevice)
        case reconfirmationRequired
        case failed
    }

    public enum DiscoveredDeviceSelectionOutcome: Equatable, Sendable {
        case connected(PairedDevice)
        case pairingRequired(DiscoveredDevice)
        case failed
    }

    public var connectionState: ConnectionState = .idle
    public var discoveredDevices: [DiscoveredDevice] = []
    public var trustedDevices: [PairedDevice] = []
    public var activeDevice: PairedDevice?
    public var manifestStatuses: [ManifestFileStatus] = []
    public var selectedFileIDs = Set<String>()
    public var bannerMessage = "Searching for nearby PCs."
    public var isBusy = false
    public let configuration: P2PFileSharingConfiguration

    public var displayedStatuses: [ManifestFileStatus] {
        manifestStatuses.map { status in
            if let override = fileStatusOverrides[status.file.id] {
                return ManifestFileStatus(file: status.file, status: override)
            }
            return status
        }
    }

    public var remoteFiles: [RemoteFile] {
        displayedStatuses.map(\.file)
    }

    public var pendingFiles: [RemoteFile] {
        displayedStatuses.compactMap { status in
            switch status.status {
            case .pending, .changedRemotely, .failed:
                return status.file
            default:
                return nil
            }
        }
    }

    public var availableFileServices: [DiscoveredDevice] {
        let trustedDeviceIDs = Set(trustedDevices.map(\.id))
        return discoveredDevices.filter { !trustedDeviceIDs.contains($0.id) }
    }

    private let localDisplayName: String
    private let trustedStore: any PairedDeviceStore
    private let recordStore: any TransferRecordStore
    private let destinationResolver: any LocalDestinationResolving
    private let transportFactory: @Sendable () -> any FileTransferTransport & PairingTransport
    private let discoveryFactory: @Sendable () -> any DeviceDiscovering
    private let comparator = ManifestComparator()

    private var discovery: any DeviceDiscovering
    private var pairingService: any DevicePairing
    private var transport: any FileTransferTransport & PairingTransport
    private var discoveryTask: Task<Void, Never>?
    private var fileStatusOverrides: [String: LocalFileStatus] = [:]
    private var currentManifest: RemoteFileManifest?
    private var autoConnectAttemptedDeviceIDs = Set<UUID>()
    private var reconciledSavedFileDeviceIDs = Set<UUID>()
    private var isActivating = false
    private var rowActivityState: DeviceSpecificActivityState = .idle

    private enum DeviceSpecificActivityState: Equatable, Sendable {
        case idle
        case refreshingManifest(UUID)
        case disconnecting(UUID)
        case removingTrust(UUID)
    }

    public convenience init(
        localDisplayName: String,
        trustedStore: any PairedDeviceStore,
        identityProvider: any LocalIdentityProviding,
        transferRecordStore: any TransferRecordStore,
        destinationResolver: any LocalDestinationResolving,
        configuration: P2PFileSharingConfiguration = .default
    ) {
        self.init(
            localDisplayName: localDisplayName,
            trustedStore: trustedStore,
            transferRecordStore: transferRecordStore,
            destinationResolver: destinationResolver,
            configuration: configuration,
            transportFactory: {
                TCPFileTransferTransport(identityStore: identityProvider)
            },
            discoveryFactory: {
                BonjourDeviceDiscovery(configuration: configuration)
            }
        )
    }

    init(
        localDisplayName: String,
        trustedStore: any PairedDeviceStore,
        transferRecordStore: any TransferRecordStore,
        destinationResolver: any LocalDestinationResolving,
        configuration: P2PFileSharingConfiguration = .default,
        transportFactory: @escaping @Sendable () -> any FileTransferTransport & PairingTransport,
        discoveryFactory: @escaping @Sendable () -> any DeviceDiscovering
    ) {
        self.localDisplayName = localDisplayName
        self.trustedStore = trustedStore
        recordStore = transferRecordStore
        self.destinationResolver = destinationResolver
        self.configuration = configuration
        self.transportFactory = transportFactory
        self.discoveryFactory = discoveryFactory

        let initialTransport = transportFactory()
        transport = initialTransport
        discovery = discoveryFactory()
        pairingService = P2PFileSharingDevicePairingService(
            store: trustedStore,
            transportFactory: { _ in initialTransport }
        )
    }

    public func handleAppDidBecomeActive() async {
        guard !isActivating else { return }
        isActivating = true
        defer { isActivating = false }

        await refreshTrustedDevices()
        reconciledSavedFileDeviceIDs.removeAll()

        if let activeDevice {
            autoConnectAttemptedDeviceIDs.removeAll()
            if case .connected = await connect(to: activeDevice) {
                return
            }
        }

        await startDiscoverySession(resetActiveDevice: true)
    }

    private func startDiscoverySession(resetActiveDevice: Bool) async {
        isBusy = true
        discoveryTask?.cancel()
        await discovery.stop()
        await transport.disconnect()

        let liveTransport = transportFactory()
        transport = liveTransport
        discovery = discoveryFactory()
        pairingService = P2PFileSharingDevicePairingService(
            store: trustedStore,
            transportFactory: { _ in liveTransport }
        )

        connectionState = .browsing
        discoveredDevices = []
        if resetActiveDevice {
            activeDevice = nil
        }
        currentManifest = nil
        manifestStatuses = []
        fileStatusOverrides = [:]
        selectedFileIDs = []
        autoConnectAttemptedDeviceIDs.removeAll()
        bannerMessage = trustedDevices.isEmpty ? "Searching for nearby PCs." : "Looking for your trusted PC."
        await beginDiscovery()
        isBusy = false
        await Task.yield()
        await attemptAutomaticReconnectIfNeeded(using: discoveredDevices)
    }

    private func beginDiscovery() async {
        let stream = await discovery.discoveredDevices()
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            for await snapshot in stream {
                self.discoveredDevices = snapshot
                self.pruneAutomaticReconnectCandidates(using: snapshot)
                await self.clearUnavailableActiveDeviceIfNeeded(using: snapshot)
                if snapshot.isEmpty {
                    if self.activeDevice == nil, !self.isBusy {
                        self.bannerMessage = self.trustedDevices.isEmpty ? "Searching for nearby PCs." : "Looking for your trusted PC."
                    }
                    continue
                }

                await self.attemptAutomaticReconnectIfNeeded(using: snapshot)
            }
        }

        do {
            try await discovery.start()
        } catch {
            connectionState = .failed(error.localizedDescription)
            bannerMessage = error.localizedDescription
        }
    }

    public func pairingPayload(fromQRCodeString qrCodeString: String) throws -> PairingPayload {
        try PairingPayload(qrCodeString: qrCodeString, configuration: configuration)
    }

    public func refreshTrustedDevices() async {
        do {
            trustedDevices = try await pairingService.trustedDevices()
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func pair(using payload: PairingPayload) async -> PairedDevice? {
        isBusy = true
        defer { isBusy = false }

        do {
            let device = try await pairingService.pair(using: payload, localDisplayName: localDisplayName)
            bannerMessage = "Paired with \(device.displayName)."
            await refreshTrustedDevices()
            autoConnectAttemptedDeviceIDs.removeAll()
            await connect(to: device)
            return device
        } catch {
            bannerMessage = error.localizedDescription
            return nil
        }
    }

    public func trustedDevice(for discoveredDevice: DiscoveredDevice) -> PairedDevice? {
        trustedDevices.first { $0.id == discoveredDevice.id }
    }

    public func isConnected(to device: PairedDevice) -> Bool {
        guard activeDevice?.id == device.id else { return false }
        guard discoveredDevices.contains(where: { $0.id == device.id }) else { return false }
        guard case .connected(let connectedID) = connectionState else { return false }
        return connectedID == device.id
    }

    func rowActivity(for device: PairedDevice) -> DeviceRowActivity {
        rowActivity(forDeviceID: device.id)
    }

    func rowActivity(for device: DiscoveredDevice) -> DeviceRowActivity {
        rowActivity(forDeviceID: device.id)
    }

    @discardableResult
    public func selectDiscoveredDevice(_ discoveredDevice: DiscoveredDevice) async -> DiscoveredDeviceSelectionOutcome {
        guard discoveredDevice.isCompatible else {
            bannerMessage = "\(discoveredDevice.displayName) uses an unsupported protocol version."
            return .failed
        }

        guard let trustedDevice = trustedDevice(for: discoveredDevice) else {
            bannerMessage = "Scan the QR code displayed on \(discoveredDevice.displayName) to confirm trust."
            return .pairingRequired(discoveredDevice)
        }

        switch await connect(to: trustedDevice) {
        case .connected(let device):
            return .connected(device)
        case .reconfirmationRequired:
            bannerMessage = "Trust for \(discoveredDevice.displayName) needs to be confirmed again. Scan the QR code on the PC."
            return .pairingRequired(discoveredDevice)
        case .failed:
            return .failed
        }
    }

    @discardableResult
    public func connect(to device: PairedDevice) async -> ConnectionAttemptOutcome {
        isBusy = true
        connectionState = .connecting(device.id)
        bannerMessage = "Connecting to \(device.displayName)…"
        defer { isBusy = false }

        do {
            try await transport.connect(to: device)
            let updatedDevice = device.withLastConnectedAt(.now)
            try await trustedStore.save(updatedDevice)
            connectionState = .connected(device.id)
            activeDevice = updatedDevice
            autoConnectAttemptedDeviceIDs.removeAll()
            bannerMessage = "Connected to \(device.displayName)."
            await refreshTrustedDevices()
            await refreshManifest()
            return .connected(updatedDevice)
        } catch {
            await transport.disconnect()
            activeDevice = nil
            currentManifest = nil
            manifestStatuses = []
            selectedFileIDs = []
            connectionState = .failed(error.localizedDescription)
            if Self.requiresReconfirmation(error) {
                bannerMessage = "Trust for \(device.displayName) needs to be confirmed again."
                return .reconfirmationRequired
            }
            bannerMessage = error.localizedDescription
            return .failed
        }
    }

    public func removeTrust(for device: PairedDevice) async {
        rowActivityState = .removingTrust(device.id)
        defer {
            if case .removingTrust(let currentID) = rowActivityState, currentID == device.id {
                rowActivityState = .idle
            }
        }

        do {
            try await pairingService.removeTrust(for: device.id)
            trustedDevices.removeAll { $0.id == device.id }
            autoConnectAttemptedDeviceIDs.remove(device.id)
            if activeDevice?.id == device.id {
                await transport.disconnect()
                activeDevice = nil
                manifestStatuses = []
                currentManifest = nil
                fileStatusOverrides = [:]
                selectedFileIDs = []
                connectionState = .browsing
            }
            bannerMessage = "Removed trust for \(device.displayName)."
            await refreshTrustedDevices()
        } catch {
            bannerMessage = error.localizedDescription
        }
    }

    public func refreshManifest() async {
        guard let activeDevice else { return }
        isBusy = true
        rowActivityState = .refreshingManifest(activeDevice.id)
        defer { isBusy = false }
        defer {
            if case .refreshingManifest(let currentID) = rowActivityState, currentID == activeDevice.id {
                rowActivityState = .idle
            }
        }

        do {
            let manifest = try await transport.fetchManifest()
            currentManifest = manifest
            let records: [TransferRecord]
            if reconciledSavedFileDeviceIDs.contains(activeDevice.id) {
                records = try await recordStore.loadAll()
            } else {
                records = try await P2PFileSharingSavedFileReconciler.reconcileTransferRecords(
                    for: activeDevice,
                    files: manifest.files,
                    recordStore: recordStore,
                    destinationResolver: destinationResolver
                )
                reconciledSavedFileDeviceIDs.insert(activeDevice.id)
            }
            manifestStatuses = comparator.compare(manifest: manifest, transferRecords: records)
            selectedFileIDs.formIntersection(Set(manifest.files.map(\.id)))
            connectionState = .connected(activeDevice.id)
            bannerMessage = "Loaded \(manifest.files.count) file(s) from \(activeDevice.displayName)."
        } catch {
            connectionState = .failed(error.localizedDescription)
            bannerMessage = error.localizedDescription
        }
    }

    public func transferSelectedFiles() async {
        let ids = selectedFileIDs.isEmpty ? Set(pendingFiles.map(\.id)) : selectedFileIDs
        for id in ids {
            await transfer(fileID: id)
        }
    }

    public func transfer(fileID: String) async {
        guard let activeDevice,
              let manifest = currentManifest,
              let file = manifest.files.first(where: { $0.id == fileID }) else {
            return
        }

        do {
            let destination = try destinationResolver.destinationURL(for: activeDevice, file: file)
            let stream = await transport.transfer(file: file, to: destination)
            fileStatusOverrides[file.id] = .transferring(progress: 0)

            for try await progress in stream {
                switch progress.state {
                case .queued, .transferring:
                    fileStatusOverrides[file.id] = .transferring(progress: progress.fractionCompleted)
                case .verifying:
                    fileStatusOverrides[file.id] = .transferring(progress: 1)
                case .completed:
                    fileStatusOverrides.removeValue(forKey: file.id)
                }
            }

            let record = TransferRecord(
                remoteDeviceID: manifest.deviceID,
                remoteFileID: file.id,
                relativePath: file.relativePath,
                byteSize: file.byteSize,
                modifiedAt: file.modifiedAt,
                contentHash: file.contentHash,
                localFilePath: destination.path
            )
            try await recordStore.save(record)
            bannerMessage = "Transferred \(file.name) to \(destination.lastPathComponent)."
            await refreshManifest()
        } catch {
            fileStatusOverrides[file.id] = .failed(error.localizedDescription)
            bannerMessage = error.localizedDescription
        }
    }

    public func cancelTransfer(fileID: String) async {
        await transport.cancelTransfer(for: fileID)
        fileStatusOverrides[fileID] = .failed("Cancelled")
    }

    public func localURL(for fileID: String) -> URL? {
        guard let status = displayedStatuses.first(where: { $0.file.id == fileID })?.status else {
            return nil
        }
        switch status {
        case .transferred(let url), .changedRemotely(let url):
            return url
        default:
            return nil
        }
    }

    public func localURL(for file: RemoteFile) -> URL? {
        localURL(for: file.id)
    }

    private func attemptAutomaticReconnectIfNeeded(using snapshot: [DiscoveredDevice]) async {
        guard activeDevice == nil, !isBusy else { return }
        guard let candidate = preferredAutomaticReconnectDevice(from: snapshot) else { return }
        guard !autoConnectAttemptedDeviceIDs.contains(candidate.id) else { return }

        autoConnectAttemptedDeviceIDs.insert(candidate.id)
        bannerMessage = "Reconnecting to \(candidate.displayName)…"

        switch await connect(to: candidate) {
        case .connected:
            return
        case .failed:
            await attemptAutomaticReconnectIfNeeded(using: snapshot)
        case .reconfirmationRequired:
            return
        }
    }

    private func preferredAutomaticReconnectDevice(from snapshot: [DiscoveredDevice]) -> PairedDevice? {
        let trustedByID = Dictionary(uniqueKeysWithValues: trustedDevices.map { ($0.id, $0) })

        return snapshot
            .compactMap { device in
                guard device.isCompatible else { return nil }
                return trustedByID[device.id]
            }
            .sorted(by: Self.preferMostRecentTrustedDevice)
            .first
    }

    private static func preferMostRecentTrustedDevice(_ lhs: PairedDevice, _ rhs: PairedDevice) -> Bool {
        let lhsDate = lhs.lastConnectedAt ?? lhs.pairedAt
        let rhsDate = rhs.lastConnectedAt ?? rhs.pairedAt

        if lhsDate != rhsDate {
            return lhsDate > rhsDate
        }

        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func clearUnavailableActiveDeviceIfNeeded(using snapshot: [DiscoveredDevice]) async {
        guard let activeDevice else { return }
        guard !snapshot.contains(where: { $0.id == activeDevice.id }) else { return }

        rowActivityState = .disconnecting(activeDevice.id)
        await transport.disconnect()
        if case .disconnecting(let currentID) = rowActivityState, currentID == activeDevice.id {
            rowActivityState = .idle
        }
        self.activeDevice = nil
        currentManifest = nil
        manifestStatuses = []
        fileStatusOverrides = [:]
        selectedFileIDs = []
        connectionState = .browsing
    }

    private func rowActivity(forDeviceID deviceID: UUID) -> DeviceRowActivity {
        switch rowActivityState {
        case .refreshingManifest(let currentID) where currentID == deviceID:
            return .refreshingManifest
        case .disconnecting(let currentID) where currentID == deviceID:
            return .disconnecting
        case .removingTrust(let currentID) where currentID == deviceID:
            return .removingTrust
        default:
            break
        }

        switch connectionState {
        case .connecting(let currentID) where currentID == deviceID:
            return .connecting
        case .authenticating(let currentID) where currentID == deviceID:
            return .authenticating
        default:
            return .idle
        }
    }

    private func pruneAutomaticReconnectCandidates(using snapshot: [DiscoveredDevice]) {
        autoConnectAttemptedDeviceIDs.formIntersection(Set(snapshot.map(\.id)))
    }

    private static func requiresReconfirmation(_ error: Error) -> Bool {
        guard let fileError = error as? P2PFileSharingError else {
            return false
        }

        switch fileError {
        case .revokedDevice, .untrustedDevice:
            return true
        case .protocolError(let message):
            let normalized = message.lowercased()
            return normalized.contains("not trusted") || normalized.contains("revoked")
        default:
            return false
        }
    }
}

public struct AppleDownloadDestinationResolver: LocalDestinationResolving {
    private let iCloud: UbiquitousContainerDestinationResolver

    public init(
        containerIdentifier: String? = nil,
        applicationFolderName: String,
        importedFolderName: String = "Imported Files"
    ) {
        iCloud = UbiquitousContainerDestinationResolver(
            containerIdentifier: containerIdentifier,
            applicationFolderName: applicationFolderName,
            importedFolderName: importedFolderName
        )
    }

    public func destinationURL(for device: PairedDevice, file: RemoteFile) throws -> URL {
        do {
            return try iCloud.destinationURL(for: device, file: file)
        } catch {
#if targetEnvironment(simulator)
            let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return try makeFlattenedDestinationURL(
                baseDirectoryURL: root,
                device: device,
                file: file
            )
#else
            throw error
#endif
        }
    }

    public func candidateLocalFileURLs(for device: PairedDevice, file: RemoteFile) throws -> [URL] {
        var candidates: [URL] = []

        if let iCloudCandidates = try? iCloud.candidateLocalFileURLs(for: device, file: file) {
            candidates.append(contentsOf: iCloudCandidates)
        }

        let localRoot = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if let localCandidates = try? candidateLocalFileURLsInRootDirectory(
            rootDirectory: localRoot,
            device: device,
            file: file
        ) {
            candidates.append(contentsOf: localCandidates)
        }

        if candidates.isEmpty {
            return [try destinationURL(for: device, file: file)]
        }

        var deduplicated = [URL]()
        var seenPaths = Set<String>()
        for candidate in candidates where seenPaths.insert(candidate.path).inserted {
            deduplicated.append(candidate)
        }

        return deduplicated
    }
}
