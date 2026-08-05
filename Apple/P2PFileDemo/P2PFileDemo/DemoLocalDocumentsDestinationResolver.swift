import Foundation
import P2PFileSharingSDK

struct DemoLocalDocumentsDestinationResolver: LocalDestinationResolving {
    private let rootDirectory: URL

    init(
        rootDirectory: URL? = nil
    ) {
        self.rootDirectory = rootDirectory
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    func destinationURL(for device: PairedDevice, file: RemoteFile) throws -> URL {
        let baseDirectory = rootDirectory
            .appendingPathComponent(deviceFolderName(for: device), isDirectory: true)

        return try relativePathComponents(for: file.relativePath).reduce(baseDirectory) { partialURL, component in
            partialURL.appendingPathComponent(component, isDirectory: false)
        }
    }

    func candidateLocalFileURLs(
        for device: PairedDevice,
        file: RemoteFile,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        let preferredURL = try destinationURL(for: device, file: file)
        let relativeComponents = try relativePathComponents(for: file.relativePath)

        let topLevelDirectories = (try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        var candidates = [preferredURL]
        for directoryURL in topLevelDirectories {
            let isDirectory = (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
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

    func relativePathComponents(for relativePath: String) throws -> [String] {
        let normalized = relativePath.replacingOccurrences(of: "\\", with: "/")
        guard !normalized.isEmpty, !normalized.hasPrefix("/") else {
            throw P2PFileSharingError.pathTraversalDetected
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !components.isEmpty else {
            throw P2PFileSharingError.pathTraversalDetected
        }

        for component in components where component.isEmpty || component == "." || component == ".." {
            throw P2PFileSharingError.pathTraversalDetected
        }

        return components
    }

    func deviceFolderName(for device: PairedDevice) -> String {
        let sanitized = device.displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return sanitized.isEmpty ? device.id.uuidString : sanitized
    }
}
