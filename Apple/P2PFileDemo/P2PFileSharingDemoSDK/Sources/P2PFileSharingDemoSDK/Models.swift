import CryptoKit
import Foundation

public enum P2PFileSharingProtocolVersion: UInt8, Codable, CaseIterable, Sendable {
    case v1 = 1

    public static var current: Self { .v1 }
}

public enum P2PFileSharingError: Error, Sendable, LocalizedError, Equatable {
    case invalidPairingPayload
    case unsupportedProtocolVersion(Int)
    case expiredPairingToken
    case serviceDiscoveryFailed(String)
    case connectionFailed(String)
    case authenticationFailed
    case invalidFrame
    case invalidFrameSize
    case invalidManifest
    case invalidHash(expected: String, actual: String)
    case localFileMissing
    case localStorageUnavailable(String)
    case pathTraversalDetected
    case untrustedDevice
    case revokedDevice
    case notConnected
    case transferCancelled
    case fileUnavailable
    case timeout
    case protocolError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPairingPayload:
            return "The QR payload is invalid."
        case .unsupportedProtocolVersion(let version):
            return "The pairing payload requires unsupported protocol version \(version)."
        case .expiredPairingToken:
            return "The pairing token has expired."
        case .serviceDiscoveryFailed(let message):
            return "Service discovery failed: \(message)"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .authenticationFailed:
            return "The remote device rejected authentication."
        case .invalidFrame:
            return "The transport received an invalid frame."
        case .invalidFrameSize:
            return "The transport received a frame that exceeded the allowed size."
        case .invalidManifest:
            return "The remote manifest was invalid."
        case .invalidHash(let expected, let actual):
            return "The downloaded file did not match the expected hash. Expected \(expected), received \(actual)."
        case .localFileMissing:
            return "The local file no longer exists."
        case .localStorageUnavailable(let message):
            return "Local storage is unavailable: \(message)"
        case .pathTraversalDetected:
            return "The remote path was rejected because it escapes the allowed folder."
        case .untrustedDevice:
            return "The device is not trusted."
        case .revokedDevice:
            return "The device trust has been revoked."
        case .notConnected:
            return "The transport is not connected."
        case .transferCancelled:
            return "The transfer was cancelled."
        case .fileUnavailable:
            return "The requested file is unavailable."
        case .timeout:
            return "The operation timed out."
        case .protocolError(let message):
            return "Protocol error: \(message)"
        }
    }
}

public struct DiscoveredDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let displayName: String
    public let serviceName: String
    public let serviceType: String
    public let domain: String
    public let protocolVersion: Int
    public let capabilities: [String]
    public let pairingRequired: Bool
    public let isCompatible: Bool
    public let lastSeenAt: Date

    public init(
        id: UUID,
        displayName: String,
        serviceName: String,
        serviceType: String = "_p2pfiles._tcp",
        domain: String = "local.",
        protocolVersion: Int,
        capabilities: [String],
        pairingRequired: Bool,
        isCompatible: Bool,
        lastSeenAt: Date = .now
    ) {
        let configuration = P2PFileSharingConfiguration(serviceType: serviceType, domain: domain)
        self.id = id
        self.displayName = displayName
        self.serviceName = serviceName
        self.serviceType = configuration.serviceType
        self.domain = configuration.domain
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.pairingRequired = pairingRequired
        self.isCompatible = isCompatible
        self.lastSeenAt = lastSeenAt
    }
}

public struct PairingPayload: Codable, Hashable, Sendable {
    public let protocolVersion: Int
    public let deviceID: UUID
    public let serviceName: String
    public let serviceType: String
    public let domain: String
    public let pairingToken: String
    public let serverFingerprint: String
    public let expiresAt: Date
    public let displayName: String?
    public let verificationCode: String?

    public init(
        protocolVersion: Int = Int(P2PFileSharingProtocolVersion.current.rawValue),
        deviceID: UUID,
        serviceName: String,
        serviceType: String = "_p2pfiles._tcp",
        domain: String = "local.",
        pairingToken: String,
        serverFingerprint: String,
        expiresAt: Date,
        displayName: String? = nil,
        verificationCode: String? = nil
    ) {
        let configuration = P2PFileSharingConfiguration(serviceType: serviceType, domain: domain)
        self.protocolVersion = protocolVersion
        self.deviceID = deviceID
        self.serviceName = serviceName
        self.serviceType = configuration.serviceType
        self.domain = configuration.domain
        self.pairingToken = pairingToken
        self.serverFingerprint = normalizeCertificateFingerprint(serverFingerprint)
        self.expiresAt = expiresAt
        self.displayName = displayName
        self.verificationCode = verificationCode
    }

    public init(
        protocolVersion: Int = Int(P2PFileSharingProtocolVersion.current.rawValue),
        deviceID: UUID,
        serviceName: String,
        configuration: P2PFileSharingConfiguration,
        pairingToken: String,
        serverFingerprint: String,
        expiresAt: Date,
        displayName: String? = nil,
        verificationCode: String? = nil
    ) {
        self.init(
            protocolVersion: protocolVersion,
            deviceID: deviceID,
            serviceName: serviceName,
            serviceType: configuration.serviceType,
            domain: configuration.domain,
            pairingToken: pairingToken,
            serverFingerprint: serverFingerprint,
            expiresAt: expiresAt,
            displayName: displayName,
            verificationCode: verificationCode
        )
    }

    public init(qrCodeString: String) throws {
        try self.init(qrCodeString: qrCodeString, configuration: .default)
    }

    public init(qrCodeString: String, configuration: P2PFileSharingConfiguration = .default) throws {
        let trimmed = qrCodeString.trimmingCharacters(in: .whitespacesAndNewlines)
        let compacted = String(trimmed.filter { !$0.isWhitespace })
        P2PFileSharingDebugLog.log("PairingPayload.init received QR input with trimmedLength=\(trimmed.count) compactedLength=\(compacted.count)")
        let payloadData: Data
        if compacted.lowercased().hasPrefix("\(configuration.qrCodeScheme):") {
            let segments = compacted
                .split(separator: "/", omittingEmptySubsequences: true)
                .map(String.init)
            guard let lastSegment = segments.last,
                  lastSegment.caseInsensitiveCompare("pair") != .orderedSame else {
                throw P2PFileSharingError.invalidPairingPayload
            }
            let encoded = lastSegment.removingPercentEncoding ?? lastSegment
            guard let decoded = Data(base64URLEncoded: encoded) else {
                throw P2PFileSharingError.invalidPairingPayload
            }
            payloadData = decoded
        } else if compacted.contains("://") {
            P2PFileSharingDebugLog.log("PairingPayload.init rejected unsupported QR scheme.")
            throw P2PFileSharingError.invalidPairingPayload
        } else if let data = Data(base64URLEncoded: compacted) {
            payloadData = data
        } else if let data = trimmed.data(using: .utf8) {
            payloadData = data
        } else {
            P2PFileSharingDebugLog.log("PairingPayload.init could not derive payload data from scanned input.")
            throw P2PFileSharingError.invalidPairingPayload
        }

        let decoder = JSONDecoder.p2p
        let payload: Self
        do {
            payload = try decoder.decode(Self.self, from: payloadData)
        } catch {
            P2PFileSharingDebugLog.log(error: error, context: "Failed to decode pairing payload JSON", rawValue: trimmed, data: payloadData)
            throw error
        }

        do {
            try payload.validate()
        } catch {
            P2PFileSharingDebugLog.log(error: error, context: "Pairing payload validation failed", rawValue: trimmed, data: payloadData)
            P2PFileSharingDebugLog.log("Decoded pairing payload before validation failure: \(P2PFileSharingDebugLog.describe(payload))")
            throw error
        }

        P2PFileSharingDebugLog.log("Decoded pairing payload: \(P2PFileSharingDebugLog.describe(payload))")
        self = payload.normalized()
    }

    public func validate(now: Date = .now) throws {
        guard protocolVersion == Int(P2PFileSharingProtocolVersion.current.rawValue) else {
            throw P2PFileSharingError.unsupportedProtocolVersion(protocolVersion)
        }
        guard expiresAt > now else {
            throw P2PFileSharingError.expiredPairingToken
        }
        guard !pairingToken.isEmpty, !serviceName.isEmpty, !serverFingerprint.isEmpty else {
            throw P2PFileSharingError.invalidPairingPayload
        }
    }

    public func qrCodeString() throws -> String {
        try qrCodeString(configuration: .default)
    }

    public func qrCodeString(configuration: P2PFileSharingConfiguration = .default) throws -> String {
        let data = try JSONEncoder.p2p.encode(self)
        return "\(configuration.qrCodeScheme)://pair/\(data.base64URLEncodedString())"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
            deviceID: try container.decode(UUID.self, forKey: .deviceID),
            serviceName: try container.decode(String.self, forKey: .serviceName),
            serviceType: try container.decode(String.self, forKey: .serviceType),
            domain: try container.decode(String.self, forKey: .domain),
            pairingToken: try container.decode(String.self, forKey: .pairingToken),
            serverFingerprint: try container.decode(String.self, forKey: .serverFingerprint),
            expiresAt: try container.decode(Date.self, forKey: .expiresAt),
            displayName: try container.decodeIfPresent(String.self, forKey: .displayName),
            verificationCode: try container.decodeIfPresent(String.self, forKey: .verificationCode)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case protocolVersion
        case deviceID
        case serviceName
        case serviceType
        case domain
        case pairingToken
        case serverFingerprint
        case expiresAt
        case displayName
        case verificationCode
    }

    private func normalized() -> Self {
        Self(
            protocolVersion: protocolVersion,
            deviceID: deviceID,
            serviceName: serviceName,
            serviceType: serviceType,
            domain: domain,
            pairingToken: pairingToken,
            serverFingerprint: serverFingerprint,
            expiresAt: expiresAt,
            displayName: displayName,
            verificationCode: verificationCode
        )
    }
}

public struct PairedDevice: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let displayName: String
    public let serviceName: String
    public let serviceType: String
    public let domain: String
    public let serverFingerprint: String
    public let protocolVersion: Int
    public let capabilities: [String]
    public let pairedAt: Date
    public let lastConnectedAt: Date?

    public init(
        id: UUID,
        displayName: String,
        serviceName: String,
        serviceType: String = "_p2pfiles._tcp",
        domain: String = "local.",
        serverFingerprint: String,
        protocolVersion: Int,
        capabilities: [String],
        pairedAt: Date = .now,
        lastConnectedAt: Date? = nil
    ) {
        let configuration = P2PFileSharingConfiguration(serviceType: serviceType, domain: domain)
        self.id = id
        self.displayName = displayName
        self.serviceName = serviceName
        self.serviceType = configuration.serviceType
        self.domain = configuration.domain
        self.serverFingerprint = normalizeCertificateFingerprint(serverFingerprint)
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.pairedAt = pairedAt
        self.lastConnectedAt = lastConnectedAt
    }

    public func withLastConnectedAt(_ date: Date?) -> Self {
        Self(
            id: id,
            displayName: displayName,
            serviceName: serviceName,
            serviceType: serviceType,
            domain: domain,
            serverFingerprint: serverFingerprint,
            protocolVersion: protocolVersion,
            capabilities: capabilities,
            pairedAt: pairedAt,
            lastConnectedAt: date
        )
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            displayName: try container.decode(String.self, forKey: .displayName),
            serviceName: try container.decode(String.self, forKey: .serviceName),
            serviceType: try container.decode(String.self, forKey: .serviceType),
            domain: try container.decode(String.self, forKey: .domain),
            serverFingerprint: try container.decode(String.self, forKey: .serverFingerprint),
            protocolVersion: try container.decode(Int.self, forKey: .protocolVersion),
            capabilities: try container.decode([String].self, forKey: .capabilities),
            pairedAt: try container.decode(Date.self, forKey: .pairedAt),
            lastConnectedAt: try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case serviceName
        case serviceType
        case domain
        case serverFingerprint
        case protocolVersion
        case capabilities
        case pairedAt
        case lastConnectedAt
    }
}

public struct LocalDeviceIdentity: Hashable, Codable, Sendable {
    public let deviceID: UUID
    public let displayName: String
    public let publicKeyRepresentation: Data

    public init(deviceID: UUID, displayName: String, publicKeyRepresentation: Data) {
        self.deviceID = deviceID
        self.displayName = displayName
        self.publicKeyRepresentation = publicKeyRepresentation
    }
}

public struct RemoteFile: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let relativePath: String
    public let name: String
    public let fileExtension: String?
    public let byteSize: Int64
    public let createdAt: Date?
    public let modifiedAt: Date
    public let contentHash: String
    public let mimeType: String?
    public let isEligible: Bool
    public let logicalGrouping: String?

    public init(
        id: String,
        relativePath: String,
        name: String,
        fileExtension: String? = nil,
        byteSize: Int64,
        createdAt: Date? = nil,
        modifiedAt: Date,
        contentHash: String,
        mimeType: String? = nil,
        isEligible: Bool = true,
        logicalGrouping: String? = nil
    ) {
        self.id = id
        self.relativePath = relativePath
        self.name = name
        self.fileExtension = fileExtension
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
        self.mimeType = mimeType
        self.isEligible = isEligible
        self.logicalGrouping = logicalGrouping
    }

    public var relativeDirectory: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}

public struct RemoteFileManifest: Hashable, Codable, Sendable {
    public let deviceID: UUID
    public let generatedAt: Date
    public let files: [RemoteFile]

    public init(deviceID: UUID, generatedAt: Date = .now, files: [RemoteFile]) {
        self.deviceID = deviceID
        self.generatedAt = generatedAt
        self.files = files
    }
}

public struct TransferRecord: Hashable, Codable, Sendable {
    public let remoteDeviceID: UUID
    public let remoteFileID: String
    public let relativePath: String
    public let byteSize: Int64
    public let modifiedAt: Date
    public let contentHash: String
    public let localFilePath: String
    public let completedAt: Date

    public init(
        remoteDeviceID: UUID,
        remoteFileID: String,
        relativePath: String,
        byteSize: Int64,
        modifiedAt: Date,
        contentHash: String,
        localFilePath: String,
        completedAt: Date = .now
    ) {
        self.remoteDeviceID = remoteDeviceID
        self.remoteFileID = remoteFileID
        self.relativePath = relativePath
        self.byteSize = byteSize
        self.modifiedAt = modifiedAt
        self.contentHash = contentHash
        self.localFilePath = localFilePath
        self.completedAt = completedAt
    }

    public var localFileURL: URL {
        URL(fileURLWithPath: localFilePath)
    }
}

public enum LocalFileStatus: Equatable, Sendable {
    case pending
    case transferred(URL)
    case changedRemotely(URL)
    case transferring(progress: Double)
    case failed(String)
    case unavailable
}

public struct ManifestFileStatus: Sendable {
    public let file: RemoteFile
    public let status: LocalFileStatus

    public init(file: RemoteFile, status: LocalFileStatus) {
        self.file = file
        self.status = status
    }
}

public struct TransferProgress: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case queued
        case transferring
        case verifying
        case completed
    }

    public let fileID: String
    public let state: State
    public let bytesTransferred: Int64
    public let totalBytes: Int64

    public init(fileID: String, state: State, bytesTransferred: Int64, totalBytes: Int64) {
        self.fileID = fileID
        self.state = state
        self.bytesTransferred = bytesTransferred
        self.totalBytes = totalBytes
    }

    public var fractionCompleted: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesTransferred) / Double(totalBytes)
    }
}

public enum ConnectionState: Equatable, Sendable {
    case idle
    case browsing
    case connecting(UUID)
    case authenticating(UUID)
    case connected(UUID)
    case failed(String)
}

public protocol DeviceDiscovering: Sendable {
    func discoveredDevices() async -> AsyncStream<[DiscoveredDevice]>
    func start() async throws
    func stop() async
}

public protocol FileTransferTransport: Sendable {
    func connect(to device: PairedDevice) async throws
    func disconnect() async
    func fetchManifest() async throws -> RemoteFileManifest
    func transfer(file: RemoteFile, to destination: URL) async -> AsyncThrowingStream<TransferProgress, Error>
    func cancelTransfer(for fileID: String) async
}

public protocol PairingTransport: Sendable {
    func bootstrapPairing(using payload: PairingPayload, localDisplayName: String?) async throws -> PairedDevice
}

public protocol DevicePairing: Sendable {
    func pair(using payload: PairingPayload, localDisplayName: String?) async throws -> PairedDevice
    func trustedDevices() async throws -> [PairedDevice]
    func removeTrust(for deviceID: UUID) async throws
}

public protocol PairedDeviceStore: Sendable {
    func save(_ device: PairedDevice) async throws
    func loadAll() async throws -> [PairedDevice]
    func remove(deviceID: UUID) async throws
}

public protocol TransferRecordStore: Sendable {
    func save(_ record: TransferRecord) async throws
    func loadAll() async throws -> [TransferRecord]
}

public protocol LocalDestinationResolving: Sendable {
    func destinationURL(for device: PairedDevice, file: RemoteFile) throws -> URL
    func candidateLocalFileURLs(for device: PairedDevice, file: RemoteFile) throws -> [URL]
}

public extension LocalDestinationResolving {
    func candidateLocalFileURLs(for device: PairedDevice, file: RemoteFile) throws -> [URL] {
        [try destinationURL(for: device, file: file)]
    }
}

enum WireMessageType: UInt8, Sendable {
    case hello = 1
    case helloAck = 2
    case pairRequest = 3
    case pairResponse = 4
    case authenticateRequest = 5
    case authenticateResponse = 6
    case manifestRequest = 7
    case manifestResponse = 8
    case fileRequest = 9
    case fileChunk = 10
    case transferComplete = 11
    case cancelTransfer = 12
    case error = 13
    case keepalive = 14
}

struct P2PFrame: Sendable, Equatable {
    let version: P2PFileSharingProtocolVersion
    let type: WireMessageType
    let metadata: Data
    let binary: Data
}

struct HelloRequest: Codable, Sendable {
    let deviceID: UUID
    let displayName: String
    let requestedVersion: Int
}

struct HelloResponse: Codable, Sendable {
    let acceptedVersion: Int
    let serverDeviceID: UUID
    let displayName: String
    let capabilities: [String]
    let challenge: Data
}

struct PairRequest: Codable, Sendable {
    let pairingToken: String
    let clientDeviceID: UUID
    let clientDisplayName: String
    let clientPublicKey: Data
    let challengeSignature: Data
}

struct PairResponse: Codable, Sendable {
    let deviceID: UUID
    let displayName: String
    let capabilities: [String]
}

struct AuthenticateRequest: Codable, Sendable {
    let clientDeviceID: UUID
    let challengeSignature: Data
}

struct AuthenticateResponse: Codable, Sendable {
    let accepted: Bool
    let revoked: Bool
}

struct ManifestRequest: Codable, Sendable {}

struct FileRequest: Codable, Sendable {
    let fileID: String
}

struct FileChunkMetadata: Codable, Sendable {
    let fileID: String
    let chunkIndex: Int
    let bytesInChunk: Int
    let totalBytes: Int64
}

struct TransferCompleteMetadata: Codable, Sendable {
    let fileID: String
    let totalBytes: Int64
    let contentHash: String
}

struct ErrorMetadata: Codable, Sendable {
    let code: String
    let message: String
}

extension JSONEncoder {
    static var p2p: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .custom { codingPath in
            let key = codingPath.last?.stringValue ?? ""
            return P2PJSONCodingKey(stringValue: P2PJSONKeyTransform.encode(key))!
        }
        return encoder
    }
}

extension JSONDecoder {
    static var p2p: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .custom { codingPath in
            let key = codingPath.last?.stringValue ?? ""
            return P2PJSONCodingKey(stringValue: P2PJSONKeyTransform.decode(key))!
        }
        return decoder
    }
}

private enum P2PJSONKeyTransform {
    static func encode(_ key: String) -> String {
        guard key.hasSuffix("ID") else {
            return key
        }

        return String(key.dropLast(2)) + "Id"
    }

    static func decode(_ key: String) -> String {
        guard key.hasSuffix("Id") else {
            return key
        }

        return String(key.dropLast(2)) + "ID"
    }
}

private struct P2PJSONCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = base64.count % 4
        if padding > 0 {
            base64 += String(repeating: "=", count: 4 - padding)
        }
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    mutating func appendUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { bytes in
            append(bytes.bindMemory(to: UInt8.self))
        }
    }

    mutating func appendUInt8(_ value: UInt8) {
        append(contentsOf: [value])
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    fileprivate var sanitizedRelativePath: String {
        replacingOccurrences(of: "\\", with: "/")
    }
}

func normalizeRelativePath(_ relativePath: String) throws -> String {
    let path = relativePath.sanitizedRelativePath
    let components = path.split(separator: "/")
    var normalized: [Substring] = []
    for component in components {
        if component == "." || component.isEmpty {
            continue
        }
        if component == ".." {
            throw P2PFileSharingError.pathTraversalDetected
        }
        normalized.append(component)
    }
    return normalized.joined(separator: "/")
}

func normalizeCertificateFingerprint(_ fingerprint: String) -> String {
    fingerprint
        .unicodeScalars
        .filter { scalar in
            scalar != ":" && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        .map(String.init)
        .joined()
        .lowercased()
}

func makeFlattenedDestinationURL(
    baseDirectoryURL: URL,
    device: PairedDevice,
    file: RemoteFile
) throws -> URL {
    let normalized = try normalizeRelativePath(file.relativePath)
    return baseDirectoryURL
        .appendingPathComponent(device.displayName, isDirectory: true)
        .appendingPathComponent(normalized, isDirectory: false)
}

func sha256Hex(of data: Data) -> String {
    Data(SHA256.hash(data: data)).hexString
}

func sha256Hex(for fileURL: URL) throws -> String {
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

    return Data(hasher.finalize()).hexString
}

func localFileMetadata(for fileURL: URL) throws -> (byteSize: Int64, modifiedAt: Date) {
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let byteSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
    let modifiedAt = attributes[.modificationDate] as? Date ?? .distantPast
    return (byteSize, modifiedAt)
}
