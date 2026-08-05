import Foundation

enum P2PFileSharingDefaults {
    static let serviceType = "_p2pfiles._tcp"
    static let domain = "local."
    static let qrCodeScheme = "p2pfiles"
}

public struct P2PFileSharingConfiguration: Hashable, Sendable {
    public let serviceType: String
    public let domain: String
    public let qrCodeScheme: String

    public static let `default` = Self()

    public init(
        serviceType: String = "_p2pfiles._tcp",
        domain: String = "local.",
        qrCodeScheme: String = "p2pfiles"
    ) {
        let normalized = Self.normalized(serviceType: serviceType, domain: domain)
        self.serviceType = normalized.serviceType
        self.domain = normalized.domain
        self.qrCodeScheme = Self.normalizedQRCodeScheme(qrCodeScheme)
    }

    static func normalized(
        serviceType rawServiceType: String,
        domain rawDomain: String = P2PFileSharingDefaults.domain
    ) -> (serviceType: String, domain: String) {
        let normalizedInput = normalizedString(rawServiceType)
        if let parsed = splitServiceTypeAndDomain(from: normalizedInput) {
            return (
                serviceType: normalizedServiceType(parsed.serviceType),
                domain: normalizedDomain(parsed.domain)
            )
        }

        let serviceType = normalizedInput.isEmpty ? P2PFileSharingDefaults.serviceType : normalizedInput
        return (
            serviceType: normalizedServiceType(serviceType),
            domain: normalizedDomain(rawDomain)
        )
    }

    private static func splitServiceTypeAndDomain(from value: String) -> (serviceType: String, domain: String)? {
        for token in ["._tcp.", "._udp."] {
            guard let range = value.range(of: token) else {
                continue
            }

            let domainSeparator = value.index(range.upperBound, offsetBy: -1)
            let serviceType = String(value[..<domainSeparator])
            let domain = String(value[value.index(after: domainSeparator)...])
            return (serviceType: serviceType, domain: domain)
        }

        return nil
    }

    private static func normalizedServiceType(_ value: String) -> String {
        let normalized = normalizedString(value)
        guard !normalized.isEmpty else {
            return P2PFileSharingDefaults.serviceType
        }

        return normalized.hasPrefix("_") ? normalized : "_" + normalized
    }

    private static func normalizedDomain(_ value: String) -> String {
        var normalized = normalizedString(value)
        if normalized.isEmpty || normalized == "." {
            normalized = P2PFileSharingDefaults.domain
        }

        if !normalized.hasSuffix(".") {
            normalized += "."
        }

        return normalized
    }

    private static func normalizedQRCodeScheme(_ value: String) -> String {
        let normalized = normalizedString(value)
        let schemeComponent = normalized.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? normalized
        let trimmed = schemeComponent.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty else {
            return P2PFileSharingDefaults.qrCodeScheme
        }

        return trimmed
    }

    private static func normalizedString(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
