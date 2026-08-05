import Foundation

struct P2PFrameCodec {
    static let headerLength = 10

    static func encode<T: Encodable>(
        type: WireMessageType,
        metadata: T,
        binary: Data = Data(),
        maximumFrameSize: Int = TCPFileTransferTransport.maximumFrameSize
    ) throws -> Data {
        let metadataData = try JSONEncoder.p2p.encode(metadata)
        return try encode(
            type: type,
            metadata: metadataData,
            binary: binary,
            maximumFrameSize: maximumFrameSize
        )
    }

    static func encode(
        type: WireMessageType,
        metadata: Data,
        binary: Data = Data(),
        maximumFrameSize: Int = TCPFileTransferTransport.maximumFrameSize
    ) throws -> Data {
        let frameLength = 1 + 1 + 4 + metadata.count + binary.count
        guard frameLength >= 6, frameLength <= maximumFrameSize else {
            throw P2PFileSharingError.invalidFrameSize
        }

        var frameData = Data()
        frameData.appendUInt32(UInt32(frameLength))
        frameData.appendUInt8(P2PFileSharingProtocolVersion.current.rawValue)
        frameData.appendUInt8(type.rawValue)
        frameData.appendUInt32(UInt32(metadata.count))
        frameData.append(metadata)
        frameData.append(binary)
        return frameData
    }

    static func expectedEncodedByteCount(
        fromHeader header: Data,
        maximumFrameSize: Int = TCPFileTransferTransport.maximumFrameSize
    ) throws -> Int {
        guard header.count == headerLength else {
            throw P2PFileSharingError.invalidFrame
        }

        let frameLength = Int(try decodeBigEndianUInt32(from: header[0..<4]))
        guard frameLength >= 6, frameLength <= maximumFrameSize else {
            throw P2PFileSharingError.invalidFrameSize
        }

        return frameLength + 4
    }

    static func decode(
        _ encodedFrame: Data,
        maximumFrameSize: Int = TCPFileTransferTransport.maximumFrameSize
    ) throws -> P2PFrame {
        guard encodedFrame.count >= headerLength else {
            throw P2PFileSharingError.invalidFrame
        }

        let frameLength = Int(try decodeBigEndianUInt32(from: encodedFrame[0..<4]))
        guard frameLength >= 6, frameLength <= maximumFrameSize else {
            throw P2PFileSharingError.invalidFrameSize
        }
        guard encodedFrame.count == frameLength + 4 else {
            throw P2PFileSharingError.invalidFrame
        }

        let versionByte = encodedFrame[4]
        guard let version = P2PFileSharingProtocolVersion(rawValue: versionByte),
              version == P2PFileSharingProtocolVersion.current else {
            throw P2PFileSharingError.invalidFrame
        }

        guard let type = WireMessageType(rawValue: encodedFrame[5]) else {
            throw P2PFileSharingError.invalidFrame
        }

        let metadataLength = Int(try decodeBigEndianUInt32(from: encodedFrame[6..<10]))
        let payload = encodedFrame.dropFirst(headerLength)
        guard metadataLength <= payload.count else {
            throw P2PFileSharingError.invalidFrame
        }

        return P2PFrame(
            version: version,
            type: type,
            metadata: Data(payload.prefix(metadataLength)),
            binary: Data(payload.dropFirst(metadataLength))
        )
    }

    private static func decodeBigEndianUInt32<C: Collection>(from bytes: C) throws -> UInt32
    where C.Element == UInt8 {
        guard bytes.count == 4 else {
            throw P2PFileSharingError.invalidFrame
        }

        return bytes.reduce(0) { partial, byte in
            (partial << 8) | UInt32(byte)
        }
    }
}
