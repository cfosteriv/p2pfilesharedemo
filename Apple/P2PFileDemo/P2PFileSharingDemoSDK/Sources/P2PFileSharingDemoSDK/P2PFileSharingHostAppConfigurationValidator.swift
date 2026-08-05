import Foundation

struct P2PFileSharingHostAppConfigurationValidator {
    enum ValidationError: LocalizedError, Equatable {
        case missingLocalNetworkUsageDescription
        case missingBonjourService(expected: String)
        case missingLocalNetworkUsageDescriptionAndBonjourService(expected: String)

        var errorDescription: String? {
            switch self {
            case .missingLocalNetworkUsageDescription:
                return """
                P2PFileSharingSDK misconfiguration: missing NSLocalNetworkUsageDescription in the host app Info.plist. Add a user-facing local-network permission reason, for example:
                <key>NSLocalNetworkUsageDescription</key>
                <string>P2P file sharing uses your local network to discover and connect to nearby devices.</string>
                """
            case .missingBonjourService(let expected):
                return """
                P2PFileSharingSDK misconfiguration: missing Bonjour service '\(expected)' in the host app Info.plist. Add it under NSBonjourServices, for example:
                <key>NSBonjourServices</key>
                <array>
                    <string>\(expected)</string>
                </array>
                """
            case .missingLocalNetworkUsageDescriptionAndBonjourService(let expected):
                return """
                P2PFileSharingSDK misconfiguration: missing required local-network Info.plist entries for file sharing. Add both:
                <key>NSLocalNetworkUsageDescription</key>
                <string>P2P file sharing uses your local network to discover and connect to nearby devices.</string>
                <key>NSBonjourServices</key>
                <array>
                    <string>\(expected)</string>
                </array>
                """
            }
        }
    }

    private let bundleInfoDictionaryProvider: () -> [String: Any]

    init(bundle: Bundle = .main) {
        bundleInfoDictionaryProvider = {
            bundle.infoDictionary ?? [:]
        }
    }

    init(bundleInfoDictionaryProvider: @escaping () -> [String: Any]) {
        self.bundleInfoDictionaryProvider = bundleInfoDictionaryProvider
    }

    func validateHostAppConfiguration(serviceType: String) throws {
        let expectedServiceType = P2PFileSharingConfiguration(serviceType: serviceType).serviceType
        let hasLocalNetworkUsageDescription = localNetworkUsageDescription() != nil
        let registeredBonjourServices = registeredBonjourServices()
        let hasBonjourService = registeredBonjourServices.contains(expectedServiceType.lowercased())

        switch (hasLocalNetworkUsageDescription, hasBonjourService) {
        case (true, true):
            return
        case (false, false):
            throw ValidationError.missingLocalNetworkUsageDescriptionAndBonjourService(expected: expectedServiceType)
        case (false, true):
            throw ValidationError.missingLocalNetworkUsageDescription
        case (true, false):
            throw ValidationError.missingBonjourService(expected: expectedServiceType)
        }
    }

    static func fatalErrorIfMisconfigured(
        serviceType: String,
        bundle: Bundle = .main,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        do {
            try Self(bundle: bundle).validateHostAppConfiguration(serviceType: serviceType)
        } catch let error as ValidationError {
            fatalError(error.localizedDescription, file: file, line: line)
        } catch {
            fatalError(error.localizedDescription, file: file, line: line)
        }
    }

    private func localNetworkUsageDescription() -> String? {
        stringValue(forKey: "NSLocalNetworkUsageDescription")
    }

    private func registeredBonjourServices() -> Set<String> {
        let infoDictionary = bundleInfoDictionaryProvider()
        guard let services = infoDictionary["NSBonjourServices"] as? [String] else {
            return []
        }

        return Set(
            services.compactMap { service in
                normalizedString(service)
            }
        )
    }

    private func stringValue(forKey key: String) -> String? {
        let infoDictionary = bundleInfoDictionaryProvider()
        guard let value = infoDictionary[key] as? String else {
            return nil
        }

        return normalizedString(value)
    }

    private func normalizedString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        return trimmed.lowercased()
    }
}
