import Observation
import P2PFileSharingSDK
import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UniformTypeIdentifiers
import UIKit
#endif

struct DemoBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var controller: P2PFileSharingBrowserController
    private let onControllerReset: @MainActor (String) -> Void
    @State private var selectedDevice: PairedDevice?
    @State private var devicePendingRemoval: PairedDevice?
#if DEBUG
    @State private var isDebugResetAlertPresented = false
    @State private var isPerformingDebugReset = false
#endif

    init(
        controller: P2PFileSharingBrowserController,
        onControllerReset: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.controller = controller
        self.onControllerReset = onControllerReset
    }

    var body: some View {
        NavigationStack {
            VStack {
                List {
                    Section("Trusted PCs") {
                        if controller.trustedDevices.isEmpty {
                            Text("No trusted PCs yet. Use Pair New Device to connect this Apple device to a Windows host.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(controller.trustedDevices) { device in
                                DemoTrustedDeviceRow(
                                    controller: controller,
                                    device: device,
                                    onSelect: {
                                        selectedDevice = device
                                        guard shouldReconnectOnSelection(for: device) else { return }
                                        Task { await controller.connect(to: device) }
                                    },
                                    onRemove: {
                                        devicePendingRemoval = device
                                    }
                                )
                            }
                        }
                    }
                }
#if DEBUG
                Spacer()
                
                Text("Debug:")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    Button(role: .destructive) {
                        isDebugResetAlertPresented = true
                    } label: {
                        HStack(spacing: 12) {
                            if isPerformingDebugReset {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            
                            VStack(spacing: 4) {
                                Text("Nuclear Reset Pairing State")
                                Text("Clears trusted devices, local pairing identity, and saved transfer history for this debug app install.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPerformingDebugReset)
                    .padding(.horizontal, 16)
                
#endif
            }
            .navigationTitle("My PCs")
            .frame(maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    P2PFileSharingPairNewDeviceButton(controller: controller)
                }
            }
            .navigationDestination(item: $selectedDevice) { device in
                DemoRemoteFilesView(controller: controller, device: device)
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await controller.handleAppDidBecomeActive()
        }
        .alert(
            "Remove Trusted Companion",
            isPresented: isRemoveAlertPresented,
            presenting: devicePendingRemoval,
            actions: { device in
                Button("Cancel", role: .cancel) {
                    devicePendingRemoval = nil
                }
                Button("Remove", role: .destructive) {
                    devicePendingRemoval = nil
                    Task { await controller.removeTrust(for: device) }
                }
            },
            message: { device in
                Text("Remove \(device.displayName) from trusted companions?")
            }
        )
#if DEBUG
        .alert(
            "Reset Demo Pairing State",
            isPresented: $isDebugResetAlertPresented,
            actions: {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task { await performDebugReset() }
                }
            },
            message: {
                Text("This debug-only action deletes the demo app's trusted-device keychain entries, local pairing identity, and transfer history so you can pair from scratch.")
            }
        )
#endif
    }

    private func shouldReconnectOnSelection(for device: PairedDevice) -> Bool {
        !isAttemptingConnection(to: device) && !controller.isConnected(to: device)
    }

    private var isRemoveAlertPresented: Binding<Bool> {
        Binding(
            get: { devicePendingRemoval != nil },
            set: { isPresented in
                if !isPresented {
                    devicePendingRemoval = nil
                }
            }
        )
    }

    private func isAttemptingConnection(to device: PairedDevice) -> Bool {
        if case .connecting(let id) = controller.connectionState {
            return id == device.id
        }
        if case .authenticating(let id) = controller.connectionState {
            return id == device.id
        }
        return false
    }

#if DEBUG
    @MainActor
    private func performDebugReset() async {
        guard !isPerformingDebugReset else { return }

        isPerformingDebugReset = true
        selectedDevice = nil
        devicePendingRemoval = nil
        defer { isPerformingDebugReset = false }

        do {
            try DemoDebugResetCoordinator.reset()
            onControllerReset("Debug pairing reset complete. Pair the Windows PC again.")
        } catch {
            controller.bannerMessage = error.localizedDescription
        }
    }
#endif
}

private struct DemoTrustedDeviceRow: View {
    @Bindable var controller: P2PFileSharingBrowserController
    let device: PairedDevice
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Text(device.displayName)
                    .font(.headline)

                Spacer(minLength: 12)

                if isAttemptingConnection {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if controller.isConnected(to: device) {
                    DemoBadge(title: "Connected", systemImage: "checkmark.circle.fill", tint: .green)
                } else {
                    DemoBadge(title: "Not Connected", systemImage: "circle", tint: .secondary)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var isAttemptingConnection: Bool {
        if case .connecting(let id) = controller.connectionState {
            return id == device.id
        }
        if case .authenticating(let id) = controller.connectionState {
            return id == device.id
        }
        return false
    }
}

private struct DemoRemoteFilesView: View {
    @Bindable var controller: P2PFileSharingBrowserController
    let device: PairedDevice

    var body: some View {
        VStack(spacing: 0) {

            if isShowingSelectedDevice {
                VStack(spacing: 0) {

                    if sortedStatuses.isEmpty {
                        ContentUnavailableView(
                            "No Files Yet",
                            systemImage: "folder",
                            description: Text("The PC file list will appear here after the manifest finishes loading.")
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(sortedStatuses, id: \.file.id) { status in
                                DemoRemoteFileRow(controller: controller, status: status)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            } else if isAttemptingConnection {
                ContentUnavailableView(
                    "Loading Files",
                    systemImage: "folder",
                    description: Text("Connecting to \(device.displayName) and loading its shared files.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Ready to Load Files",
                    systemImage: "desktopcomputer.and.arrow.down",
                    description: Text("Reconnect to \(device.displayName) to load its shared folder.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(device.displayName)
        .toolbar {
            if hasFilesToSave {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save All") {
                        Task { await controller.transferSelectedFiles() }
                    }
                    .disabled(controller.isBusy)
                }
            }
        }
        .task(id: device.id) {
            await loadFilesIfNeeded()
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var isShowingSelectedDevice: Bool {
        controller.activeDevice?.id == device.id
    }

    private var isAttemptingConnection: Bool {
        if case .connecting(let id) = controller.connectionState {
            return id == device.id
        }
        if case .authenticating(let id) = controller.connectionState {
            return id == device.id
        }
        return false
    }

    private var sortedStatuses: [ManifestFileStatus] {
        controller.displayedStatuses.sorted {
            $0.file.relativePath.localizedCaseInsensitiveCompare($1.file.relativePath) == .orderedAscending
        }
    }

    private var hasFilesToSave: Bool {
        controller.displayedStatuses.contains { $0.needsSaveAction }
    }

    private func loadFilesIfNeeded() async {
        if controller.isConnected(to: device) {
            await controller.refreshManifest()
            await DemoSavedFileReconciler.reconcile(controller: controller, device: device)
            return
        }

        guard !isAttemptingConnection else { return }
        let outcome = await controller.connect(to: device)
        if case .connected = outcome {
            await DemoSavedFileReconciler.reconcile(controller: controller, device: device)
        }
    }
}

private struct DemoRemoteFileRow: View {
    @Bindable var controller: P2PFileSharingBrowserController
    let status: ManifestFileStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(status.file.name)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                if case .transferring(_) = status.status {
                    Spacer()
                    
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 20)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(ByteCountFormatter.string(fromByteCount: status.file.byteSize, countStyle: .file))
                    Spacer()
                    Text("Modified \(status.file.modifiedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if case .transferring(let progress) = status.status {
                ProgressView(value: progress)
                    .tint(.blue)
            }

            HStack(alignment: .center, spacing: 12) {
                statusBadge

                Spacer(minLength: 12)

                rowActions
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status.status {
        case .pending:
            DemoBadge(title: "On PC", systemImage: "desktopcomputer", tint: .blue)
        case .transferred:
            DemoBadge(title: "Saved", systemImage: "checkmark.circle.fill", tint: .green)
        case .changedRemotely:
            DemoBadge(title: "Update Available", systemImage: "arrow.triangle.2.circlepath.circle.fill", tint: .orange)
        case .transferring(let progress):
            DemoBadge(title: "Saving \(Int(progress * 100))%", systemImage: "arrow.down.circle.fill", tint: .blue)
        case .failed:
            DemoBadge(title: "Save Failed", systemImage: "exclamationmark.circle.fill", tint: .red)
        case .unavailable:
            DemoBadge(title: "Unavailable", systemImage: "nosign", tint: .secondary)
        }
    }

    @ViewBuilder
    private var rowActions: some View {
        switch status.status {
        case .pending:
            Button("Save") {
                Task { await controller.transfer(fileID: status.file.id) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isBusy)

        case .changedRemotely:
            Button("Save Latest") {
                Task { await controller.transfer(fileID: status.file.id) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isBusy)

        case .failed:
            Button("Retry Save") {
                Task { await controller.transfer(fileID: status.file.id) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(controller.isBusy)

        case .transferring:
            Button("Cancel") {
                Task { await controller.cancelTransfer(fileID: status.file.id) }
            }
            .buttonStyle(.bordered)

        case .transferred:
            if let localURL = controller.localURL(for: status.file) {
                HStack(spacing: 10) {
                    DemoOpenInFilesButton(
                        fileURL: localURL,
                        onDismiss: {
                            Task {
                                await controller.refreshManifest()
                                if let activeDevice = controller.activeDevice {
                                    await DemoSavedFileReconciler.reconcile(controller: controller, device: activeDevice)
                                }
                            }
                        }
                    )

                    ShareLink(item: localURL) {
                        DemoRoundIconLabel(systemImage: "square.and.arrow.up", tint: .blue)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Share")
                }
            }

        case .unavailable:
            EmptyView()
        }
    }
}

private struct DemoStatusBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.blue.opacity(0.08))
    }
}

private struct DemoBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct DemoRoundIconLabel: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 36, height: 36)
            .background(tint.opacity(0.12))
            .clipShape(Circle())
    }
}

private struct DemoOpenInFilesButton: View {
    let fileURL: URL
    let onDismiss: () -> Void
#if os(iOS)
    @State private var isPresentingFilesBrowser = false
#endif

    var body: some View {
        Button(action: openSavedFile) {
#if os(macOS)
            DemoRoundIconLabel(systemImage: "folder", tint: .blue)
#else
            DemoRoundIconLabel(systemImage: "folder", tint: .blue)
#endif
        }
        .buttonStyle(.plain)
        .accessibilityLabel(openAccessibilityLabel)
#if os(iOS)
        .sheet(isPresented: $isPresentingFilesBrowser, onDismiss: onDismiss) {
            DemoFilesBrowserPresenter(
                fileURL: fileURL,
                isPresented: $isPresentingFilesBrowser
            )
            .ignoresSafeArea()
        }
#endif
    }

    private func openSavedFile() {
#if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
#else
        isPresentingFilesBrowser = true
#endif
    }

    private var openAccessibilityLabel: String {
#if os(macOS)
        "Reveal in Finder"
#else
        "Open in Files"
#endif
    }
}

#if os(iOS)
private struct DemoFilesBrowserPresenter: UIViewControllerRepresentable {
    let fileURL: URL
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let controller = UIDocumentPickerViewController(
            forOpeningContentTypes: [contentType(for: fileURL)],
            asCopy: false
        )
        controller.delegate = context.coordinator
        controller.directoryURL = fileURL.deletingLastPathComponent()
        controller.allowsMultipleSelection = false
        controller.shouldShowFileExtensions = true
        return controller
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    private func contentType(for fileURL: URL) -> UTType {
        (try? fileURL.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .item
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        @Binding private var isPresented: Bool

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            isPresented = false
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            isPresented = false
        }
    }
}
#endif

private extension ManifestFileStatus {
    var needsSaveAction: Bool {
        switch status {
        case .pending, .changedRemotely, .failed:
            return true
        case .transferred, .transferring, .unavailable:
            return false
        }
    }
}
