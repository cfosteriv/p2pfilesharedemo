import Foundation

enum P2PFileSharingDebugLog {
    static func log(_ message: @autoclosure () -> String) {
        print("[P2PFileSharingSDK] \(timestamp()) \(message())")
    }

    static func log(error: Error, context: String, rawValue: String? = nil, data: Data? = nil) {
        log("\(context): \(describe(error))")
        if let rawValue {
            log("\(context) raw preview: \(preview(rawValue))")
        }
        if let data {
            log("\(context) data preview: \(preview(data))")
        }
    }

    static func describe(_ payload: PairingPayload) -> String {
        "deviceID=\(payload.deviceID.uuidString) displayName=\(payload.displayName ?? "<nil>") service=\(payload.serviceName) type=\(payload.serviceType) domain=\(payload.domain) protocolVersion=\(payload.protocolVersion) tokenPrefix=\(redact(payload.pairingToken)) fingerprintPrefix=\(redact(payload.serverFingerprint)) expiresAt=\(payload.expiresAt.ISO8601Format())"
    }

    static func describe(_ device: PairedDevice) -> String {
        "deviceID=\(device.id.uuidString) displayName=\(device.displayName) service=\(device.serviceName) type=\(device.serviceType) domain=\(device.domain) protocolVersion=\(device.protocolVersion) fingerprintPrefix=\(redact(device.serverFingerprint))"
    }

    static func preview(_ value: String, limit: Int = 240) -> String {
        let normalized = value
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
        if normalized.count <= limit {
            return "\"\(normalized)\""
        }

        return "\"\(normalized.prefix(limit))...\" (\(normalized.count) chars)"
    }

    static func preview(_ data: Data, limit: Int = 240) -> String {
        if let string = String(data: data, encoding: .utf8) {
            return "\(preview(string, limit: limit)) [utf8, \(data.count) bytes]"
        }

        let hex = data.prefix(limit).map { String(format: "%02x", $0) }.joined()
        if data.count <= limit {
            return "\(hex) [hex, \(data.count) bytes]"
        }

        return "\(hex)... [hex, \(data.count) bytes]"
    }

    static func describe(_ error: Error) -> String {
        if let decodingError = error as? DecodingError {
            return describe(decodingError)
        }

        return "\(type(of: error)): \(error.localizedDescription)"
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .typeMismatch(let type, let context):
            return "DecodingError.typeMismatch(\(type), path=\(codingPath(context.codingPath)), description=\(context.debugDescription))"
        case .valueNotFound(let type, let context):
            return "DecodingError.valueNotFound(\(type), path=\(codingPath(context.codingPath)), description=\(context.debugDescription))"
        case .keyNotFound(let key, let context):
            return "DecodingError.keyNotFound(\(key.stringValue), path=\(codingPath(context.codingPath)), description=\(context.debugDescription))"
        case .dataCorrupted(let context):
            return "DecodingError.dataCorrupted(path=\(codingPath(context.codingPath)), description=\(context.debugDescription))"
        @unknown default:
            return "DecodingError.unknown"
        }
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        guard !path.isEmpty else {
            return "<root>"
        }

        return path.map(\.stringValue).joined(separator: ".")
    }

    private static func redact(_ value: String, keep: Int = 12) -> String {
        guard value.count > keep else {
            return value
        }

        return "\(value.prefix(keep))..."
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}
