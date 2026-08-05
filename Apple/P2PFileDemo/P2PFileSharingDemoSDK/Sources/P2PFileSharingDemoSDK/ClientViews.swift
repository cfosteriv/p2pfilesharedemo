import Observation
import SwiftUI
#if os(iOS)
import Vision
import VisionKit
#endif

public struct P2PFileSharingBrowserView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable private var controller: P2PFileSharingBrowserController

    public init(controller: P2PFileSharingBrowserController) {
        self.controller = controller
    }

    public var body: some View {
        NavigationSplitView {
            List {

                Section("Trusted PCs") {
                    if controller.trustedDevices.isEmpty {
                        Text("No trusted PCs yet. Use Pair New Device to confirm a Windows host.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.trustedDevices) { device in
                            TrustedDeviceRow(controller: controller, device: device)
                        }
                    }
                }
            }
            .navigationTitle("Available Devices")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    P2PFileSharingPairNewDeviceButton(controller: controller)
                }
            }
        } detail: {
            if let activeDevice = controller.activeDevice {
                FileBrowserView(controller: controller, device: activeDevice)
            } else {
                ContentUnavailableView(
                    "Choose a Trusted PC",
                    systemImage: "desktopcomputer.and.arrow.down",
                    description: Text("Use Pair New Device to find a Windows host, or reconnect to one you already trust.")
                )
            }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await controller.handleAppDidBecomeActive()
        }
    }
}

public struct P2PFileSharingPairNewDeviceButton: View {
    @Bindable private var controller: P2PFileSharingBrowserController
    @State private var isDevicePickerPresented = false

    public init(controller: P2PFileSharingBrowserController) {
        self.controller = controller
    }

    public var body: some View {
        Button("Pair New Device") {
            isDevicePickerPresented = true
        }
        .sheet(isPresented: $isDevicePickerPresented) {
            P2PFileSharingDevicePickerSheet(
                controller: controller,
                isPresented: $isDevicePickerPresented
            )
#if os(iOS)
            .presentationDetents([.medium, .large])
#endif
        }
    }
}

private struct P2PFileSharingDevicePickerSheet: View {
    @Bindable var controller: P2PFileSharingBrowserController
    @Binding var isPresented: Bool
    @State private var selectedDeviceID: UUID?
    @State private var pairingDevice: DiscoveredDevice?
    @State private var isCameraSheetPresented = false
    @State private var isSubmittingPairing = false
    @State private var alertTitle = "Pairing Failed"
    @State private var alertMessage: String?

    var body: some View {
        NavigationStack {
            List {

                if controller.availableFileServices.isEmpty {
                    Section("Available PCs") {
                        Text("Active services appear here automatically when they are available.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("Available File Services") {
                        ForEach(controller.availableFileServices) { device in
                            let activity = controller.rowActivity(for: device)
                            Button {
                                select(device)
                            } label: {
                                DevicePickerRow(
                                    device: device,
                                    isTrusted: controller.trustedDevice(for: device) != nil,
                                    activity: activity,
                                    isBusy: selectedDeviceID == device.id || activity.showsProgress
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedDeviceID != nil || !device.isCompatible)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        isPresented = false
                    }
                    .disabled(isSubmittingPairing)
                }
            }
        }
        .disabled(isSubmittingPairing)
        .overlay {
            if isSubmittingPairing {
                PairingProgressOverlay(deviceName: pairingDevice?.displayName)
            }
        }
#if os(iOS)
        .sheet(isPresented: $isCameraSheetPresented) {
            P2PFileSharingQRScannerSheet { scannedValue in
                Task { @MainActor in
                    await handleScannedPayload(scannedValue)
                }
            }
        }
#endif
        .alert(alertTitle, isPresented: isAlertPresented, actions: {
            Button("OK") {
                alertMessage = nil
            }
        }, message: {
            Text(alertMessage ?? "")
        })
    }

    private func select(_ device: DiscoveredDevice) {
        guard selectedDeviceID == nil, !isSubmittingPairing else { return }
        selectedDeviceID = device.id

        Task {
            let outcome = await controller.selectDiscoveredDevice(device)
            await MainActor.run {
                selectedDeviceID = nil
                switch outcome {
                case .connected:
                    isPresented = false
                case .pairingRequired(let discoveredDevice):
                    beginQRCodePairing(for: discoveredDevice)
                case .failed:
                    presentAlert(title: "Connection Failed", message: controller.bannerMessage)
                }
            }
        }
    }

    @MainActor
    private func handleScannedPayload(_ scannedValue: String) async {
        guard let pairingDevice else { return }

        isSubmittingPairing = true
        defer { isSubmittingPairing = false }

        do {
            let payload = try controller.pairingPayload(fromQRCodeString: scannedValue)
            guard payload.deviceID == pairingDevice.id else {
                presentAlert(
                    title: "Wrong QR Code",
                    message: "This QR code belongs to \(payload.displayName ?? payload.serviceName), not \(pairingDevice.displayName)."
                )
                return
            }

            if await controller.pair(using: payload) != nil {
                self.pairingDevice = nil
                isPresented = false
                return
            }

            presentAlert(title: "Pairing Failed", message: controller.bannerMessage)
        } catch {
            presentAlert(title: "Pairing Failed", message: error.localizedDescription)
        }
    }

    @MainActor
    private func beginQRCodePairing(for device: DiscoveredDevice) {
        pairingDevice = device
#if os(iOS)
        guard DataScannerViewController.isSupported, DataScannerViewController.isAvailable else {
            presentAlert(
                title: "Scanner Unavailable",
                message: "This device cannot open the QR camera scanner right now."
            )
            return
        }

        isCameraSheetPresented = true
#else
        presentAlert(
            title: "Scanner Unavailable",
            message: "QR camera scanning is only available on iOS."
        )
#endif
    }

    private func presentAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
    }

    private var isAlertPresented: Binding<Bool> {
        Binding(
            get: { alertMessage != nil },
            set: { newValue in
                if !newValue {
                    alertMessage = nil
                }
            }
        )
    }
}

private struct PairingProgressOverlay: View {
    let deviceName: String?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.2))
                .ignoresSafeArea()

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Pairing with \(deviceName ?? "Windows PC")…")
                    .font(.headline)
                Text("Confirming trust and connecting now.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .transition(.opacity)
        .allowsHitTesting(true)
    }
}

private struct TrustedDeviceRow: View {
    @Bindable var controller: P2PFileSharingBrowserController
    let device: PairedDevice

    var body: some View {
        let activity = controller.rowActivity(for: device)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.displayName)
                        .font(.headline)
                    Text(device.serviceName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if activity.showsProgress {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(activity.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if controller.isConnected(to: device) {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }

            HStack {
                Button("Reconnect") {
                    Task { await controller.connect(to: device) }
                }
                .buttonStyle(.borderedProminent)

                Button("Remove Trust", role: .destructive) {
                    Task { await controller.removeTrust(for: device) }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct DevicePickerRow: View {
    let device: DiscoveredDevice
    let isTrusted: Bool
    let activity: P2PFileSharingBrowserController.DeviceRowActivity
    let isBusy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(device.displayName)
                    .font(.headline)
                Spacer()
                if isBusy {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        if !activity.title.isEmpty {
                            Text(activity.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(statusLabel)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.14))
                        .clipShape(Capsule())
                }
            }

            Text(statusDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("\(device.serviceType) • Protocol \(device.protocolVersion)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(device.capabilities.joined(separator: ", "))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var statusLabel: String {
        if !device.isCompatible {
            return "Unsupported"
        }
        return isTrusted ? "Trusted" : "Scan QR"
    }

    private var statusDescription: String {
        if !device.isCompatible {
            return "This PC is advertising an unsupported protocol version."
        }
        return isTrusted ? "Reconnect without rescanning." : "Confirm this PC with its QR code."
    }

    private var statusColor: Color {
        if !device.isCompatible {
            return .orange
        }
        return isTrusted ? .green : .blue
    }
}

private struct FileBrowserView: View {
    @Bindable var controller: P2PFileSharingBrowserController
    let device: PairedDevice

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(device.displayName)
                        .font(.largeTitle.weight(.semibold))
                    Text(device.serviceName)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button("Transfer Pending") {
                    Task { await controller.transferSelectedFiles() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)

            if controller.displayedStatuses.isEmpty {
                ContentUnavailableView(
                    "No Manifest Loaded",
                    systemImage: "folder",
                    description: Text("The manifest will load automatically after the device connects.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $controller.selectedFileIDs) {
                    ForEach(controller.displayedStatuses, id: \.file.id) { status in
                        FileRow(controller: controller, status: status)
                    }
                }
            }
        }
        .navigationTitle("File Browser")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

private struct FileRow: View {
    @Bindable var controller: P2PFileSharingBrowserController
    let status: ManifestFileStatus

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(status.file.name)
                    .font(.headline)
                Text(status.file.relativeDirectory.isEmpty ? "/" : status.file.relativeDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: status.file.byteSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                switch status.status {
                case .transferring(let progress):
                    ProgressView(value: progress)
                        .frame(maxWidth: 220)
                default:
                    EmptyView()
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text(statusText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(iconColor)

                switch status.status {
                case .pending, .changedRemotely, .failed:
                    Button(actionTitle) {
                        Task { await controller.transfer(fileID: status.file.id) }
                    }
                    .buttonStyle(.borderedProminent)
                case .transferring:
                    Button("Cancel") {
                        Task { await controller.cancelTransfer(fileID: status.file.id) }
                    }
                    .buttonStyle(.bordered)
                case .transferred:
                    if let url = controller.localURL(for: status.file.id) {
                        ShareLink(item: url) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.bordered)
                    }
                case .unavailable:
                    EmptyView()
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var iconName: String {
        switch status.status {
        case .pending:
            return "tray.and.arrow.down"
        case .transferred:
            return "checkmark.circle.fill"
        case .changedRemotely:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .transferring:
            return "arrow.down.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .unavailable:
            return "nosign"
        }
    }

    private var iconColor: Color {
        switch status.status {
        case .pending:
            return .blue
        case .transferred:
            return .green
        case .changedRemotely:
            return .orange
        case .transferring:
            return .blue
        case .failed:
            return .red
        case .unavailable:
            return .secondary
        }
    }

    private var statusText: String {
        switch status.status {
        case .pending:
            return "Available"
        case .transferred:
            return "Transferred"
        case .changedRemotely:
            return "Changed Remotely"
        case .transferring(let progress):
            return "\(Int(progress * 100))%"
        case .failed(let reason):
            return reason
        case .unavailable:
            return "Unavailable"
        }
    }

    private var actionTitle: String {
        switch status.status {
        case .failed:
            return "Retry"
        default:
            return "Transfer"
        }
    }
}

#if os(iOS)
public struct P2PFileSharingQRScannerSheet: View {
    private let onScannedCode: @MainActor (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var failureMessage: String?

    public init(onScannedCode: @escaping @MainActor (String) -> Void) {
        self.onScannedCode = onScannedCode
    }

    public var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    ScannerView(
                        onScannedCode: { value in
                            onScannedCode(value)
                            dismiss()
                        },
                        onFailure: { error in
                            failureMessage = error
                        }
                    )
                } else {
                    ContentUnavailableView(
                        "Scanner Unavailable",
                        systemImage: "camera.metering.unknown",
                        description: Text("Use the manual payload field if the simulator or device cannot provide camera scanning.")
                    )
                }
            }
            .navigationTitle("Scan QR Code")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Scanner Error", isPresented: .constant(failureMessage != nil), actions: {
                Button("OK") { failureMessage = nil }
            }, message: {
                Text(failureMessage ?? "")
            })
        }
    }
}

private struct ScannerView: UIViewControllerRepresentable {
    let onScannedCode: @MainActor @Sendable (String) -> Void
    let onFailure: @MainActor @Sendable (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScannedCode: onScannedCode, onFailure: onFailure)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScannedCode: @MainActor (String) -> Void
        private let onFailure: @MainActor (String) -> Void
        private var hasCompleted = false

        init(
            onScannedCode: @escaping @MainActor (String) -> Void,
            onFailure: @escaping @MainActor (String) -> Void
        ) {
            self.onScannedCode = onScannedCode
            self.onFailure = onFailure
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !hasCompleted else { return }
            for item in addedItems {
                guard case let .barcode(barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }
                hasCompleted = true
                Task { @MainActor in
                    onScannedCode(payload)
                }
                return
            }
        }

        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            Task { @MainActor in
                onFailure(error.localizedDescription)
            }
        }
    }
}
#endif
