import Foundation
import Network
import Security

public actor BonjourDeviceDiscovery: DeviceDiscovering {
    private let serviceType: String
    private let domain: String
    private let queue = DispatchQueue(label: "com.p2pfilesharing.bonjour")
    private var browser: NWBrowser?
    private var continuation: AsyncStream<[DiscoveredDevice]>.Continuation?
    private var devices: [UUID: DiscoveredDevice] = [:]

    public init(configuration: P2PFileSharingConfiguration = .default) {
        P2PFileSharingHostAppConfigurationValidator.fatalErrorIfMisconfigured(serviceType: configuration.serviceType)
        serviceType = configuration.serviceType
        domain = configuration.domain
    }

    public init(
        serviceType: String = "_p2pfiles._tcp",
        domain: String = "local."
    ) {
        let configuration = P2PFileSharingConfiguration(serviceType: serviceType, domain: domain)
        P2PFileSharingHostAppConfigurationValidator.fatalErrorIfMisconfigured(serviceType: configuration.serviceType)
        self.serviceType = configuration.serviceType
        self.domain = configuration.domain
    }

    public func discoveredDevices() async -> AsyncStream<[DiscoveredDevice]> {
        AsyncStream { continuation in
            self.continuation = continuation
            continuation.yield(Array(self.devices.values).sorted(by: { $0.displayName < $1.displayName }))
        }
    }

    public func start() async throws {
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: domain), using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { await self?.handleState(state) }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { await self?.updateDevices(from: results) }
        }
        self.browser = browser
        browser.start(queue: queue)
    }

    public func stop() async {
        browser?.cancel()
        browser = nil
        continuation?.finish()
        continuation = nil
    }

    private func handleState(_ state: NWBrowser.State) {
        if case .failed(let error) = state {
            continuation?.finish()
            continuation = nil
            browser?.cancel()
            browser = nil
            devices.removeAll()
            print("BonjourDeviceDiscovery failed: \(error)")
        }
    }

    private func updateDevices(from results: Set<NWBrowser.Result>) {
        var updated: [UUID: DiscoveredDevice] = [:]
        for result in results {
            guard case let .service(name, type, domain, _) = result.endpoint else { continue }
            guard case let .bonjour(txtRecord) = result.metadata else { continue }
            let dictionary = txtRecord.dictionary
            guard let idString = dictionary["deviceID"],
                  let deviceID = UUID(uuidString: idString) else { continue }
            let protocolVersion = Int(dictionary["protocolVersion"] ?? "0") ?? 0
            let capabilities = dictionary["capabilities"]?
                .split(separator: ",")
                .map { String($0) } ?? []
            let displayName = dictionary["displayName"] ?? name
            let pairingRequired = (dictionary["pairingRequired"] ?? "true") == "true"
            updated[deviceID] = DiscoveredDevice(
                id: deviceID,
                displayName: displayName,
                serviceName: name,
                serviceType: type,
                domain: domain,
                protocolVersion: protocolVersion,
                capabilities: capabilities,
                pairingRequired: pairingRequired,
                isCompatible: protocolVersion == Int(P2PFileSharingProtocolVersion.current.rawValue)
            )
        }
        devices = updated
        continuation?.yield(updated.values.sorted(by: { $0.displayName < $1.displayName }))
    }
}

public actor TCPFileTransferTransport: FileTransferTransport, PairingTransport {
    public static let maximumFrameSize = 8 * 1024 * 1024

    private let identityStore: LocalIdentityProviding
    private let queue = DispatchQueue(label: "com.p2pfilesharing.transport")
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var connectedDevice: PairedDevice?
    private var activeFileID: String?

    public init(identityStore: LocalIdentityProviding) {
        self.identityStore = identityStore
    }

    public func bootstrapPairing(using payload: PairingPayload, localDisplayName: String?) async throws -> PairedDevice {
        P2PFileSharingDebugLog.log("Transport bootstrapPairing starting for payload: \(P2PFileSharingDebugLog.describe(payload))")
        do {
            let identity = try await identityStore.currentIdentity(displayName: localDisplayName)
            P2PFileSharingDebugLog.log("Transport pairing using local identity deviceID=\(identity.deviceID.uuidString) displayName=\(identity.displayName) publicKeyBytes=\(identity.publicKeyRepresentation.count)")

            try await connect(
                serviceName: payload.serviceName,
                serviceType: payload.serviceType,
                domain: payload.domain,
                pinnedFingerprint: payload.serverFingerprint
            )
            P2PFileSharingDebugLog.log("Transport pairing connected to Bonjour endpoint \(payload.serviceName).\(payload.serviceType)\(payload.domain)")

            let response = try await sendHello(identity: identity)
            P2PFileSharingDebugLog.log("Transport pairing received hello ack acceptedVersion=\(response.acceptedVersion) serverDeviceID=\(response.serverDeviceID.uuidString) displayName=\(response.displayName) capabilities=\(response.capabilities.joined(separator: ",")) challengeBytes=\(response.challenge.count)")

            let signature = try await identityStore.sign(response.challenge)
            let request = PairRequest(
                pairingToken: payload.pairingToken,
                clientDeviceID: identity.deviceID,
                clientDisplayName: identity.displayName,
                clientPublicKey: identity.publicKeyRepresentation,
                challengeSignature: signature
            )
            P2PFileSharingDebugLog.log("Transport pairing sending pair request tokenPrefix=\(String(payload.pairingToken.prefix(8)))... signatureBytes=\(signature.count)")
            try await send(type: .pairRequest, metadata: request)

            let pairResponse: PairResponse = try await receive(type: .pairResponse, decodeAs: PairResponse.self)
            P2PFileSharingDebugLog.log("Transport pairing received pair response deviceID=\(pairResponse.deviceID.uuidString) displayName=\(pairResponse.displayName) capabilities=\(pairResponse.capabilities.joined(separator: ","))")

            let device = PairedDevice(
                id: pairResponse.deviceID,
                displayName: pairResponse.displayName,
                serviceName: payload.serviceName,
                serviceType: payload.serviceType,
                domain: payload.domain,
                serverFingerprint: payload.serverFingerprint,
                protocolVersion: response.acceptedVersion,
                capabilities: pairResponse.capabilities,
                pairedAt: .now,
                lastConnectedAt: .now
            )
            connectedDevice = device
            return device
        } catch {
            P2PFileSharingDebugLog.log(error: error, context: "Transport bootstrapPairing failed")
            throw error
        }
    }

    public func connect(to device: PairedDevice) async throws {
        let identity = try await identityStore.currentIdentity(displayName: nil)
        try await connect(
            serviceName: device.serviceName,
            serviceType: device.serviceType,
            domain: device.domain,
            pinnedFingerprint: device.serverFingerprint
        )
        let response = try await sendHello(identity: identity)
        let signature = try await identityStore.sign(response.challenge)
        try await send(
            type: .authenticateRequest,
            metadata: AuthenticateRequest(clientDeviceID: identity.deviceID, challengeSignature: signature)
        )
        let auth: AuthenticateResponse = try await receive(type: .authenticateResponse, decodeAs: AuthenticateResponse.self)
        guard auth.accepted else {
            throw auth.revoked ? P2PFileSharingError.revokedDevice : P2PFileSharingError.authenticationFailed
        }
        connectedDevice = device.withLastConnectedAt(.now)
    }

    public func disconnect() async {
        connection?.cancel()
        connection = nil
        receiveBuffer = Data()
        activeFileID = nil
        connectedDevice = nil
    }

    public func fetchManifest() async throws -> RemoteFileManifest {
        guard connectedDevice != nil else {
            throw P2PFileSharingError.notConnected
        }
        try await send(type: .manifestRequest, metadata: ManifestRequest())
        return try await receive(type: .manifestResponse, decodeAs: RemoteFileManifest.self)
    }

    public func transfer(file: RemoteFile, to destination: URL) async -> AsyncThrowingStream<TransferProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    guard connectedDevice != nil else {
                        throw P2PFileSharingError.notConnected
                    }
                    activeFileID = file.id
                    try await send(type: .fileRequest, metadata: FileRequest(fileID: file.id))
                    var writer = try AtomicVerifiedFileWriter(destinationURL: destination)
                    var shouldDiscardPartial = true
                    defer {
                        if shouldDiscardPartial {
                            writer.discard()
                        }
                    }
                    var transferred: Int64 = 0
                    continuation.yield(.init(fileID: file.id, state: .queued, bytesTransferred: 0, totalBytes: file.byteSize))

                    while true {
                        let frame = try await receiveFrame()
                        switch frame.type {
                        case .fileChunk:
                            let chunk = try JSONDecoder.p2p.decode(FileChunkMetadata.self, from: frame.metadata)
                            try writer.append(frame.binary)
                            transferred += Int64(frame.binary.count)
                            continuation.yield(
                                .init(
                                    fileID: chunk.fileID,
                                    state: .transferring,
                                    bytesTransferred: transferred,
                                    totalBytes: chunk.totalBytes
                                )
                            )
                        case .transferComplete:
                            let metadata = try JSONDecoder.p2p.decode(TransferCompleteMetadata.self, from: frame.metadata)
                            continuation.yield(.init(fileID: metadata.fileID, state: .verifying, bytesTransferred: metadata.totalBytes, totalBytes: metadata.totalBytes))
                            try writer.complete(expectedSize: metadata.totalBytes, expectedHash: metadata.contentHash)
                            shouldDiscardPartial = false
                            continuation.yield(.init(fileID: metadata.fileID, state: .completed, bytesTransferred: metadata.totalBytes, totalBytes: metadata.totalBytes))
                            activeFileID = nil
                            continuation.finish()
                            return
                        case .error:
                            let error = try JSONDecoder.p2p.decode(ErrorMetadata.self, from: frame.metadata)
                            throw P2PFileSharingError.protocolError(error.message)
                        default:
                            throw P2PFileSharingError.invalidFrame
                        }
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func cancelTransfer(for fileID: String) async {
        guard activeFileID == fileID else { return }
        try? await send(type: .cancelTransfer, metadata: FileRequest(fileID: fileID))
        activeFileID = nil
    }

    private func sendHello(identity: LocalDeviceIdentity) async throws -> HelloResponse {
        let request = HelloRequest(
            deviceID: identity.deviceID,
            displayName: identity.displayName,
            requestedVersion: Int(P2PFileSharingProtocolVersion.current.rawValue)
        )
        try await send(type: .hello, metadata: request)
        return try await receive(type: .helloAck, decodeAs: HelloResponse.self)
    }

    private func connect(
        serviceName: String,
        serviceType: String,
        domain: String,
        pinnedFingerprint: String
    ) async throws {
        let configuration = P2PFileSharingConfiguration(serviceType: serviceType, domain: domain)
        P2PFileSharingHostAppConfigurationValidator.fatalErrorIfMisconfigured(serviceType: configuration.serviceType)
        await disconnect()
        let parameters = NWParameters(tls: makeTLSOptions(pinnedFingerprint: pinnedFingerprint), tcp: NWProtocolTCP.Options())
        parameters.includePeerToPeer = true
        let endpoint = NWEndpoint.service(
            name: serviceName,
            type: configuration.serviceType,
            domain: configuration.domain,
            interface: nil
        )
        let connection = NWConnection(to: endpoint, using: parameters)
        self.connection = connection
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let gate = ContinuationGate()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    gate.resume {
                        continuation.resume()
                    }
                case .failed(let error):
                    gate.resume {
                        continuation.resume(throwing: P2PFileSharingError.connectionFailed(error.debugDescription))
                    }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    private func makeTLSOptions(pinnedFingerprint: String) -> NWProtocolTLS.Options {
        let options = NWProtocolTLS.Options()
        sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
        sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, trust, complete in
            let secTrust = sec_trust_copy_ref(trust).takeRetainedValue()
            guard let certificate = (SecTrustCopyCertificateChain(secTrust) as? [SecCertificate])?.first else {
                complete(false)
                return
            }
            let data = SecCertificateCopyData(certificate) as Data
            let fingerprint = normalizeCertificateFingerprint(sha256Hex(of: data))
            complete(fingerprint == normalizeCertificateFingerprint(pinnedFingerprint))
        }, queue)
        return options
    }

    private func send<T: Encodable>(type: WireMessageType, metadata: T, binary: Data = Data()) async throws {
        let frameData = try P2PFrameCodec.encode(
            type: type,
            metadata: metadata,
            binary: binary,
            maximumFrameSize: Self.maximumFrameSize
        )
        try await sendRaw(frameData)
    }

    private func sendRaw(_ data: Data) async throws {
        guard let connection else {
            throw P2PFileSharingError.notConnected
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: P2PFileSharingError.connectionFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    private func receive<T: Decodable>(type: WireMessageType, decodeAs: T.Type) async throws -> T {
        let frame = try await receiveFrame()
        guard frame.type == type else {
            if frame.type == .error {
                do {
                    let error = try JSONDecoder.p2p.decode(ErrorMetadata.self, from: frame.metadata)
                    P2PFileSharingDebugLog.log("Transport receive saw protocol error while waiting for \(type): code=\(error.code) message=\(error.message)")
                    throw P2PFileSharingError.protocolError(error.message)
                } catch {
                    P2PFileSharingDebugLog.log(error: error, context: "Failed to decode protocol error metadata while waiting for \(type)", data: frame.metadata)
                    throw error
                }
            }
            P2PFileSharingDebugLog.log("Transport receive expected frame type \(type) but got \(frame.type). Metadata preview: \(P2PFileSharingDebugLog.preview(frame.metadata))")
            throw P2PFileSharingError.invalidFrame
        }

        do {
            return try JSONDecoder.p2p.decode(T.self, from: frame.metadata)
        } catch {
            P2PFileSharingDebugLog.log(error: error, context: "Failed to decode \(T.self) from frame type \(frame.type)", data: frame.metadata)
            throw error
        }
    }

    private func receiveFrame() async throws -> P2PFrame {
        let header = try await readExact(byteCount: 10)
        let totalByteCount = try P2PFrameCodec.expectedEncodedByteCount(
            fromHeader: header,
            maximumFrameSize: Self.maximumFrameSize
        )
        let remaining = try await readExact(byteCount: totalByteCount - P2PFrameCodec.headerLength)
        var encodedFrame = Data()
        encodedFrame.append(header)
        encodedFrame.append(remaining)
        return try P2PFrameCodec.decode(encodedFrame, maximumFrameSize: Self.maximumFrameSize)
    }

    private func readExact(byteCount: Int) async throws -> Data {
        guard byteCount >= 0 else { throw P2PFileSharingError.invalidFrame }
        while receiveBuffer.count < byteCount {
            receiveBuffer.append(try await receiveMore())
        }
        let data = receiveBuffer.prefix(byteCount)
        receiveBuffer.removeFirst(byteCount)
        return Data(data)
    }

    private func receiveMore() async throws -> Data {
        guard let connection else {
            throw P2PFileSharingError.notConnected
        }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maximumFrameSize) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: P2PFileSharingError.connectionFailed(error.localizedDescription))
                    return
                }
                if let content, !content.isEmpty {
                    continuation.resume(returning: content)
                    return
                }
                if isComplete {
                    continuation.resume(throwing: P2PFileSharingError.connectionFailed("The remote connection closed unexpectedly."))
                    return
                }
                continuation.resume(throwing: P2PFileSharingError.connectionFailed("No content was received."))
            }
        }
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ action: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        action()
    }
}
