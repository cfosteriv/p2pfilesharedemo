import Foundation
import Testing
@testable import P2PFileSharingSDK

struct P2PFileSharingSDKTests {

    @Test func configurationNormalizesServiceIdentityAndQRCodeScheme() {
        let configuration = P2PFileSharingConfiguration(
            serviceType: " WarehouseFiles._TCP.Local ",
            domain: "ignored",
            qrCodeScheme: "WarehouseFiles://pair"
        )

        #expect(configuration.serviceType == "_warehousefiles._tcp")
        #expect(configuration.domain == "local.")
        #expect(configuration.qrCodeScheme == "warehousefiles")
    }

    @Test func pairingPayloadRoundTripsQRCodeAndNormalizesFingerprint() throws {
        let expiresAt = Date(timeIntervalSince1970: 1_786_000_000)
        let configuration = P2PFileSharingConfiguration(qrCodeScheme: "WarehouseFiles")
        let payload = PairingPayload(
            deviceID: UUID(uuidString: "7ABDDCF2-9305-4097-BF79-2F21365A4932")!,
            serviceName: "studio-workstation",
            configuration: configuration,
            pairingToken: "abc123",
            serverFingerprint: "AA:BB:CC:DD",
            expiresAt: expiresAt,
            displayName: "Studio Workstation"
        )

        let qrCode = try payload.qrCodeString(configuration: configuration)
        let decoded = try PairingPayload(
            qrCodeString: "  \(qrCode)  ",
            configuration: configuration
        )

        #expect(decoded.serviceType == "_p2pfiles._tcp")
        #expect(decoded.domain == "local.")
        #expect(decoded.serverFingerprint == "aabbccdd")
        #expect(decoded.displayName == "Studio Workstation")
    }

    @Test func pairingPayloadRejectsExpiredOrUnsupportedPayloads() {
        let expiredPayload = PairingPayload(
            protocolVersion: Int(P2PFileSharingProtocolVersion.current.rawValue),
            deviceID: UUID(uuidString: "7ABDDCF2-9305-4097-BF79-2F21365A4932")!,
            serviceName: "studio-workstation",
            pairingToken: "abc123",
            serverFingerprint: "aa:bb:cc:dd",
            expiresAt: .distantPast
        )

        do {
            try expiredPayload.validate(now: .now)
            Issue.record("Expected expired payload validation to fail.")
        } catch let error as P2PFileSharingError {
            #expect(error == .expiredPairingToken)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        do {
            _ = try PairingPayload(qrCodeString: "https://example.com/pair")
            Issue.record("Expected unsupported QR scheme to fail.")
        } catch let error as P2PFileSharingError {
            #expect(error == .invalidPairingPayload)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func pairedDeviceRoundTripsJSONEncoding() throws {
        let device = PairedDevice(
            id: UUID(uuidString: "574CE7E1-F38E-4C89-A835-B50439F09BC7")!,
            displayName: "Studio Workstation",
            serviceName: "studio-workstation",
            serviceType: "_P2PFILES._TCP",
            domain: "LOCAL",
            serverFingerprint: "AA:BB:CC:DD",
            protocolVersion: 1,
            capabilities: ["manifest", "download"],
            pairedAt: Date(timeIntervalSince1970: 1_786_000_000),
            lastConnectedAt: Date(timeIntervalSince1970: 1_786_000_100)
        )

        let data = try JSONEncoder.p2p.encode(device)
        let decoded = try JSONDecoder.p2p.decode(PairedDevice.self, from: data)

        #expect(decoded == device)
        #expect(decoded.serverFingerprint == "aabbccdd")
        #expect(decoded.serviceType == "_p2pfiles._tcp")
        #expect(decoded.domain == "local.")
    }

    @Test func manifestComparatorReflectsPendingTransferredChangedAndUnavailableStates() throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let device = makeDevice()
        let now = Date(timeIntervalSince1970: 1_786_000_000)

        let transferredContents = Data("Granite".utf8)
        let changedContents = Data("Slate".utf8)

        let transferredFile = makeFile(
            id: "specs/granite.pdf",
            relativePath: "Specs/granite.pdf",
            name: "granite.pdf",
            modifiedAt: now,
            contents: transferredContents
        )
        let changedFile = makeFile(
            id: "specs/slate.pdf",
            relativePath: "Specs/slate.pdf",
            name: "slate.pdf",
            modifiedAt: now,
            contents: Data("Expected".utf8)
        )
        let pendingFile = makeFile(
            id: "photos/install.jpg",
            relativePath: "Photos/install.jpg",
            name: "install.jpg",
            modifiedAt: now,
            contents: Data("Photo".utf8)
        )
        let unavailableFile = RemoteFile(
            id: "offline/file.txt",
            relativePath: "Offline/file.txt",
            name: "file.txt",
            fileExtension: "txt",
            byteSize: 1,
            modifiedAt: now,
            contentHash: "abc",
            isEligible: false
        )

        let transferredURL = rootDirectory.appendingPathComponent("granite.pdf")
        let changedURL = rootDirectory.appendingPathComponent("slate.pdf")
        try transferredContents.write(to: transferredURL)
        try changedContents.write(to: changedURL)

        let statuses = ManifestComparator().compare(
            manifest: RemoteFileManifest(
                deviceID: device.id,
                generatedAt: now,
                files: [transferredFile, changedFile, pendingFile, unavailableFile]
            ),
            transferRecords: [
                TransferRecord(
                    remoteDeviceID: device.id,
                    remoteFileID: transferredFile.id,
                    relativePath: transferredFile.relativePath,
                    byteSize: transferredFile.byteSize,
                    modifiedAt: transferredFile.modifiedAt,
                    contentHash: transferredFile.contentHash,
                    localFilePath: transferredURL.path
                ),
                TransferRecord(
                    remoteDeviceID: device.id,
                    remoteFileID: changedFile.id,
                    relativePath: changedFile.relativePath,
                    byteSize: Int64(changedContents.count),
                    modifiedAt: changedFile.modifiedAt.addingTimeInterval(-60),
                    contentHash: sha256Hex(of: changedContents),
                    localFilePath: changedURL.path
                ),
            ]
        )

        #expect(statuses.count == 4)
        #expect(statuses[0].status == .transferred(transferredURL))
        #expect(statuses[1].status == .changedRemotely(changedURL))
        #expect(statuses[2].status == .pending)
        #expect(statuses[3].status == .unavailable)
    }

    @Test func savedFileReconcilerSynthesizesRecordsFromLegacyLocations() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }

        let device = makeDevice(displayName: "Surface Studio")
        let file = makeFile(
            id: "stone/specs/granite.txt",
            relativePath: "Stone/Specs/granite.txt",
            name: "granite.txt",
            modifiedAt: Date(timeIntervalSince1970: 1_786_000_000),
            contents: Data("Granite spec".utf8)
        )

        let preferredURL = rootDirectory
            .appendingPathComponent(device.displayName, isDirectory: true)
            .appendingPathComponent(file.relativePath, isDirectory: false)
        let legacyURL = rootDirectory
            .appendingPathComponent("Old Surface Name", isDirectory: true)
            .appendingPathComponent(file.relativePath, isDirectory: false)
        try FileManager.default.createDirectory(
            at: legacyURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("Granite spec".utf8).write(to: legacyURL)

        let resolver = TestDestinationResolver(
            preferredURL: preferredURL,
            candidateURLs: [preferredURL, legacyURL]
        )
        let store = MemoryTransferRecordStore()

        let records = try await P2PFileSharingSavedFileReconciler.reconcileTransferRecords(
            for: device,
            files: [file],
            recordStore: store,
            destinationResolver: resolver
        )

        #expect(records.count == 1)
        #expect(records[0].localFileURL == legacyURL)
        #expect(records[0].contentHash == file.contentHash)
    }

    @Test func normalizeRelativePathRejectsTraversalAndNormalizesSeparators() throws {
        let normalized = try normalizeRelativePath(#"Stone\Specs//granite.pdf"#)
        #expect(normalized == "Stone/Specs/granite.pdf")

        do {
            _ = try normalizeRelativePath("../secret.txt")
            Issue.record("Expected path traversal to be rejected.")
        } catch let error as P2PFileSharingError {
            #expect(error == .pathTraversalDetected)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func frameCodecRoundTripsMetadataAndBinary() throws {
        let metadata = FileChunkMetadata(
            fileID: "photos/install.jpg",
            chunkIndex: 2,
            bytesInChunk: 4,
            totalBytes: 12
        )
        let binary = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let encoded = try P2PFrameCodec.encode(type: .fileChunk, metadata: metadata, binary: binary)
        let decoded = try P2PFrameCodec.decode(encoded)
        let decodedMetadata = try JSONDecoder.p2p.decode(FileChunkMetadata.self, from: decoded.metadata)

        #expect(decoded.version == .current)
        #expect(decoded.type == .fileChunk)
        #expect(decoded.binary == binary)
        #expect(decodedMetadata.fileID == metadata.fileID)
        #expect(decodedMetadata.chunkIndex == metadata.chunkIndex)
        #expect(decodedMetadata.bytesInChunk == metadata.bytesInChunk)
        #expect(decodedMetadata.totalBytes == metadata.totalBytes)
    }

    @Test func frameCodecRejectsMalformedFrames() {
        var malformed = Data()
        malformed.appendUInt32(10)
        malformed.appendUInt8(P2PFileSharingProtocolVersion.current.rawValue)
        malformed.appendUInt8(WireMessageType.error.rawValue)
        malformed.appendUInt32(99)
        malformed.append(Data("oops".utf8))

        do {
            _ = try P2PFrameCodec.decode(malformed)
            Issue.record("Expected malformed frame to be rejected.")
        } catch let error as P2PFileSharingError {
            #expect(error == .invalidFrame)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }
    }

    @Test func mockTransportCancellationRemovesPartialFiles() async throws {
        let catalog = MockRemoteCatalog.sample(now: Date(timeIntervalSince1970: 1_786_000_000))
        let file = try #require(catalog.manifest.files.first)
        let transport = MockFileTransferTransport(
            catalog: catalog,
            faultPlan: MockTransportFaultPlan(chunkSize: 4, chunkLatency: .milliseconds(25))
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(file.name)
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        try await transport.connect(to: catalog.pairedDevice)
        var iterator = await transport.transfer(file: file, to: destination).makeAsyncIterator()

        while let progress = try await iterator.next() {
            if progress.state == .transferring {
                await transport.cancelTransfer(for: file.id)
                break
            }
        }

        do {
            while try await iterator.next() != nil {}
            Issue.record("Expected cancelled transfer to throw.")
        } catch let error as P2PFileSharingError {
            #expect(error == .transferCancelled)
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let partialFiles = try directoryContents(at: destination.deletingLastPathComponent())
            .filter { $0.pathExtension == "partial" }
        #expect(partialFiles.isEmpty)
    }

    @Test func mockTransportHashFailureRemovesPartialFiles() async throws {
        let catalog = MockRemoteCatalog.sample(now: Date(timeIntervalSince1970: 1_786_000_000))
        let file = try #require(catalog.manifest.files.first)
        let transport = MockFileTransferTransport(
            catalog: catalog,
            faultPlan: MockTransportFaultPlan(
                chunkSize: 4,
                chunkLatency: .milliseconds(1),
                invalidHashFileIDs: [file.id]
            )
        )
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(file.name)
        defer { try? FileManager.default.removeItem(at: destination.deletingLastPathComponent()) }

        try await transport.connect(to: catalog.pairedDevice)
        var iterator = await transport.transfer(file: file, to: destination).makeAsyncIterator()

        do {
            while try await iterator.next() != nil {}
            Issue.record("Expected invalid hash transfer to throw.")
        } catch let error as P2PFileSharingError {
            switch error {
            case .invalidHash:
                break
            default:
                Issue.record("Expected invalidHash, received \(error).")
            }
        } catch {
            Issue.record("Unexpected error: \(error.localizedDescription)")
        }

        #expect(!FileManager.default.fileExists(atPath: destination.path))
        let partialFiles = try directoryContents(at: destination.deletingLastPathComponent())
            .filter { $0.pathExtension == "partial" }
        #expect(partialFiles.isEmpty)
    }

    private func makeDevice(displayName: String = "Studio Workstation") -> PairedDevice {
        PairedDevice(
            id: UUID(uuidString: "574CE7E1-F38E-4C89-A835-B50439F09BC7")!,
            displayName: displayName,
            serviceName: "studio-workstation",
            serverFingerprint: "aa:bb:cc:dd",
            protocolVersion: 1,
            capabilities: ["manifest", "download"]
        )
    }

    private func makeFile(
        id: String,
        relativePath: String,
        name: String,
        modifiedAt: Date,
        contents: Data
    ) -> RemoteFile {
        RemoteFile(
            id: id,
            relativePath: relativePath,
            name: name,
            fileExtension: (name as NSString).pathExtension,
            byteSize: Int64(contents.count),
            modifiedAt: modifiedAt,
            contentHash: sha256Hex(of: contents)
        )
    }

    private func directoryContents(at directoryURL: URL) throws -> [URL] {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
    }
}

private struct TestDestinationResolver: LocalDestinationResolving {
    let preferredURL: URL
    let candidateURLs: [URL]

    func destinationURL(for device: PairedDevice, file: RemoteFile) throws -> URL {
        preferredURL
    }

    func candidateLocalFileURLs(for device: PairedDevice, file: RemoteFile) throws -> [URL] {
        candidateURLs
    }
}
