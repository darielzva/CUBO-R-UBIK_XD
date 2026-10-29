



import SwiftUI
import Darwin
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @AppStorage(AppLanguage.storageKey) private var languageCode = AppLanguage.english.rawValue
    @StateObject private var pairingController = PairingController()
    @State private var isPairingReady = false
    @State private var isTunnelConnected: Bool?
    @State private var isPairingImporterPresented = false
    @State private var isPairingImporting = false
    @State private var isPairingDeleteConfirmationPresented = false
    @State private var pairingImportErrorKey: String?
    @State private var pairingAlertTitleKey = "settings.pairing_import_error_title"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AppLogo()

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Support Patch").font(.headline)
                            Text(language.text("common.version", appVersion))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(language.text("settings.language")) {
                    Picker(language.text("settings.language"), selection: $languageCode) {
                        ForEach(AppLanguage.allCases) { option in
                            Text(option.displayName).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section(language.text("common.device")) {
                    LabeledContent(language.text("dashboard.hardware_model"), value: AppInfo.displayMachineName)
                    LabeledContent(language.text("settings.ios_version"), value: "\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                }

                if pairingSettingsVisible {
                    Section(language.text("settings.pairing_section")) {
                        VStack(alignment: .leading, spacing: 8) {
                            PairingStatusBadge(
                                title: language.text("settings.tunnel"),
                                status: language.text(tunnelStatusKey),
                                systemImage: tunnelStatusSymbol,
                                tint: tunnelStatusTint
                            )
                            PairingStatusBadge(
                                title: language.text("settings.pairing"),
                                status: language.text(isPairingReady ? "settings.pairing_ready" : "settings.pairing_missing"),
                                systemImage: isPairingReady ? "checkmark.circle.fill" : "exclamationmark.circle",
                                tint: isPairingReady ? .green : .secondary
                            )
                            if AppInfo.versionTuple.major >= 27 {
                                PairingStatusBadge(
                                    title: language.text("settings.direct_pairing"),
                                    status: language.text("settings.pairing_supported"),
                                    systemImage: "checkmark.seal.fill",
                                    tint: .green
                                )
                            }
                        }
                        Text(language.text("settings.pairing_direct_note"))
                            .font(.footnote)
                            .foregroundStyle(AppTheme.accent)
                        if DevicePatchService.requiresPairingTunnel,
                           AppInfo.versionTuple.major < 27 {
                            Button(action: openLocalDevVPN) {
                                Label(language.text("settings.open_localdevvpn"), systemImage: "network")
                            }
                        }
                        if AppInfo.versionTuple.major >= 27 {
                            Button {
                                if pairingController.isRunning {
                                    pairingController.cancel()
                                } else if isTunnelConnected == true {
                                    pairingController.start(
                                        pinNotificationTitle: language.text("settings.pairing_pin_notification_title"),
                                        pinNotificationBodyFormat: language.text("settings.pairing_pin_notification_body")
                                    )
                                } else {
                                    openLocalDevVPN()
                                }
                            } label: {
                                Label(
                                    pairingController.isRunning
                                        ? language.text("settings.stop_pairing")
                                        : isTunnelConnected == true
                                            ? language.text("settings.pair_on_this_iphone")
                                            : language.text("settings.open_localdevvpn"),
                                    systemImage: pairingController.isRunning
                                        ? "stop.circle"
                                        : isTunnelConnected == true ? "iphone.gen3" : "network"
                                )
                            }
                            if let pin = pairingController.pin {
                                Text(language.text("settings.pairing_pin", pin))
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(AppTheme.accent)
                            }
                            if pairingController.isRunning {
                                Text(pairingController.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if let error = pairingController.errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                        Button {
                            isPairingImporterPresented = true
                        } label: {
                            if isPairingImporting {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text(language.text("settings.pairing_importing"))
                                }
                            } else {
                                Label(language.text("settings.import_pairing"), systemImage: "square.and.arrow.down")
                            }
                        }
                        .disabled(isPairingImporting)
                        if isPairingReady {
                            Button(role: .destructive) {
                                isPairingDeleteConfirmationPresented = true
                            } label: {
                                Label(language.text("settings.delete_pairing"), systemImage: "trash")
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Text(language.text("settings.exploit_compatibility"))
                        Spacer()
                        Text(language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"))
                            .foregroundStyle(appState.isSupported ? Color.green : Color.orange)
                    }
                    ForEach(ExploitSupportPolicy.supportedMajorVersions, id: \.self) { major in
                        DisclosureGroup("iOS \(major)") {
                            ForEach(ExploitSupportPolicy.verifiedVersions.filter { $0.major == major }) { version in
                                LabeledContent("iOS \(version.version)") {
                                    Text(version.builds.joined(separator: ", "))
                                        .font(.caption.monospaced())
                                        .multilineTextAlignment(.trailing)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                } header: {
                    Text(language.text("settings.verified_versions"))
                } footer: {
                    Text(language.text("settings.supported_versions_footer"))
                }
                Section(language.text("settings.social_media")) {
                    creditsRow(
                        name: "Telegram",
                        role: language.text("social.github_role"),
                        url: "https://t.me/hole30601"
                    )
                    creditsRow(
                        name: "Cộng Đồng Cheat",
                        role: language.text("social.iosvn_role"),
                        url: "https://t.me/hackchetafree"
                    )
                }

                Section(language.text("settings.credits")) {
                    creditsRow(
                        name: "Hole30601",
                        role: language.text("credit.yangjiii"),
                        url: "https://t.me/hole30601"
                    )
                    creditsRow(
                        name: "0xjohnnydev",
                        role: language.text("credit.filzaslop"),
                        url: "https://github.com/0xjohnnydev/FilzaSlop"
                    )
                    creditsRow(
                        name: "LeminLimez",
                        role: language.text("credit.pocket_poster"),
                        url: "https://github.com/leminlimez/Pocket-Poster"
                    )
                    creditsRow(
                        name: "CrazyMind90",
                        role: language.text("credit.sandbox_escape"),
                        url: "https://github.com/CrazyMind90"
                    )
                    creditsRow(
                        name: "forcequitOS",
                        role: language.text("credit.forcequit"),
                        url: "https://github.com/forcequitOS"
                    )
                }
            }
            .tint(AppTheme.accent)
            .navigationTitle(language.text("settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(language.text("common.done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear { isPairingReady = PairingFileStore.isReady }
            .onReceive(pairingController.$status) { status in
                if status == "Pairing ready" {
                    isPairingReady = PairingFileStore.isReady
                }
            }
            .task {
                while !Task.isCancelled {
                    isTunnelConnected = await PairingTunnelProbe.isConnected
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
            .sheet(isPresented: $isPairingImporterPresented) {
                PairingDocumentPicker { url in
                    isPairingImporterPresented = false
                    importPairing(from: url)
                }
            }
            .confirmationDialog(
                language.text("settings.delete_pairing_confirm_title"),
                isPresented: $isPairingDeleteConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button(language.text("settings.delete_pairing"), role: .destructive) {
                    do {
                        try PairingFileStore.delete()
                        isPairingReady = false
                    } catch {
                        pairingAlertTitleKey = "settings.delete_pairing_error_title"
                        pairingImportErrorKey = "settings.delete_pairing_failed"
                    }
                }
                Button(language.text("common.cancel"), role: .cancel) {}
            } message: {
                Text(language.text("settings.delete_pairing_confirm_message"))
            }
            .alert(
                language.text(pairingAlertTitleKey),
                isPresented: Binding(
                    get: { pairingImportErrorKey != nil },
                    set: { if !$0 { pairingImportErrorKey = nil } }
                )
            ) {
                Button(language.text("common.ok"), role: .cancel) {
                    pairingImportErrorKey = nil
                }
            } message: {
                Text(language.text(pairingImportErrorKey ?? "settings.pairing_import_failed"))
            }
        }
    }

    private var pairingSettingsVisible: Bool {
        let version = AppInfo.versionTuple
        return appState.isSupported
            || version.major >= 27
            || (version.major == 18 && version.minor == 7 && version.patch == 10)
    }

    private var tunnelStatusKey: String {
        guard let isTunnelConnected else { return "settings.tunnel_checking" }
        return isTunnelConnected ? "settings.tunnel_connected" : "settings.tunnel_disconnected"
    }

    private var tunnelStatusSymbol: String {
        guard let isTunnelConnected else { return "arrow.triangle.2.circlepath" }
        return isTunnelConnected ? "checkmark.circle.fill" : "bolt.slash.circle"
    }

    private var tunnelStatusTint: Color {
        guard let isTunnelConnected else { return .secondary }
        return isTunnelConnected ? .green : .secondary
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "AppReleaseDisplayVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "1.0"
    }

    private func importPairing(from url: URL) {
        isPairingImporting = true
        pairingAlertTitleKey = "settings.pairing_import_error_title"
        pairingImportErrorKey = nil
        Task { @MainActor in
            do {
                let isReady = try await Task.detached(priority: .userInitiated) {
                    try PairingFileStore.importFile(from: url)
                    return PairingFileStore.isReady
                }.value
                isPairingReady = isReady
                isPairingImporting = false
            } catch PairingFileImportError.invalidPropertyList {
                pairingImportErrorKey = "settings.pairing_import_invalid"
                isPairingImporting = false
            } catch PairingFileImportError.fileTooLarge {
                pairingImportErrorKey = "settings.pairing_import_too_large"
                isPairingImporting = false
            } catch {
                pairingImportErrorKey = "settings.pairing_import_failed"
                isPairingImporting = false
            }
        }
    }

    private func openLocalDevVPN() {
        let appURL = URL(string: "localdevvpn://")!
        let appStoreURL = URL(string: "https://apps.apple.com/app/id6755608044")!
        UIApplication.shared.open(appURL) { opened in
            if !opened {
                UIApplication.shared.open(appStoreURL)
            }
        }
    }

    @ViewBuilder
    private func creditsRow(name: String, role: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28, height: 28)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel(language.text("accessibility.open_profile", name))
        }
    }
}

private struct PairingStatusBadge: View {
    let title: String
    let status: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(status)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint == .secondary ? Color.primary : tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            Color(uiColor: .tertiarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct PairingDocumentPicker: UIViewControllerRepresentable {
    let onSelection: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.data],
            asCopy: true
        )
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onSelection: (URL) -> Void

        init(onSelection: @escaping (URL) -> Void) {
            self.onSelection = onSelection
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            onSelection(url)
        }
    }
}

private enum PairingTunnelProbe {
    static var isConnected: Bool {
        let interfaces = ipv4Interfaces()
        guard let routeAddress = routeSource(to: "10.7.0.1") else { return false }
        return interfaces.contains {
            isTunnelInterface($0.name) && $0.address == routeAddress
        }
    }

    private static func ipv4Interfaces() -> [(name: String, address: String)] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else {
            return []
        }
        defer { freeifaddrs(addresses) }

        var interfaces: [(name: String, address: String)] = []
        var currentAddress: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = currentAddress {
            defer { currentAddress = address.pointee.ifa_next }
            guard let socketAddress = address.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == sa_family_t(AF_INET) else {
                continue
            }

            if let ipv4 = numericHost(socketAddress) {
                interfaces.append((String(cString: address.pointee.ifa_name), ipv4))
            }
        }
        return interfaces
    }

    private static func routeSource(to ipAddress: String) -> String? {
        var remoteAddress = sockaddr_in()
        remoteAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remoteAddress.sin_family = sa_family_t(AF_INET)
        remoteAddress.sin_port = in_port_t(UInt16(9).bigEndian)
        guard ipAddress.withCString({ inet_pton(AF_INET, $0, &remoteAddress.sin_addr) }) == 1 else {
            return nil
        }

        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else { return nil }
        defer { close(socketDescriptor) }

        let didConnect = withUnsafePointer(to: remoteAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard didConnect == 0 else { return nil }

        var localAddress = sockaddr_in()
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let didReadLocalAddress = withUnsafeMutablePointer(to: &localAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &addressLength)
            }
        }
        guard didReadLocalAddress == 0, localAddress.sin_addr.s_addr != 0 else { return nil }

        return withUnsafeMutablePointer(to: &localAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                numericHost($0)
            }
        }
    }

    private static func numericHost(_ address: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(
            address,
            socklen_t(MemoryLayout<sockaddr_in>.size),
            &host,
            socklen_t(host.count),
            nil,
            0,
            NI_NUMERICHOST
        ) == 0 else {
            return nil
        }
        return String(cString: host)
    }

    private static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec")
            || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }
}

private enum PairingFileImportError: Error {
    case invalidPropertyList
    case fileTooLarge
}

private enum PairingFileStore {
    private static let maximumFileSize = 10 * 1_024 * 1_024

    private static var pairingFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aircard_pairing.plist")
    }

    static var isReady: Bool {
        guard let data = try? Data(contentsOf: pairingFileURL),
              let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = propertyList as? [String: Any] else {
            return false
        }
        return !dictionary.isEmpty
    }

    static func delete() throws {
        try FileManager.default.removeItem(at: pairingFileURL)
    }

    static func importFile(from sourceURL: URL) throws {
        let didStartAccessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: sourceURL)
        guard data.count <= maximumFileSize else {
            throw PairingFileImportError.fileTooLarge
        }
        guard let propertyList = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = propertyList as? [String: Any],
              !dictionary.isEmpty else {
            throw PairingFileImportError.invalidPropertyList
        }

        try data.write(to: pairingFileURL, options: .atomic)
    }
}
