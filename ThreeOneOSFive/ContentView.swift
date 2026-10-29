import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var tabNavigation: AppTabNavigationState

    init() {
        _tabNavigation = State(initialValue: AppTabNavigationState())
    }

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(AppTheme.accent)
        .imageScale(.small)
        .onAppear {
            tabNavigation.reconcileSelection(with: featureVisibility)
        }
    }

    private var compactLayout: some View {
        TabView(selection: tabSelection) {
            ForEach(featureVisibility.visibleSections) { section in
                sectionContent(section)
                    .tabItem {
                        CompactTabLabel(
                            title: language.text(section.titleKey),
                            systemImage: section.systemImage
                        )
                    }
                    .tag(section.rawValue)
            }
        }
    }

    private var regularLayout: some View {
        NavigationSplitView {
            List {
                ForEach(featureVisibility.visibleSections) { section in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            tabNavigation.select(section.rawValue)
                        }
                    } label: {
                        Label(language.text(section.titleKey), systemImage: section.systemImage)
                            .fontWeight(section.rawValue == tabNavigation.selectedTab ? .semibold : .regular)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        section.rawValue == tabNavigation.selectedTab
                            ? AppTheme.accent.opacity(0.14)
                            : Color.clear
                    )
                    .accessibilityAddTraits(
                        section.rawValue == tabNavigation.selectedTab ? .isSelected : []
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppTheme.pageBackground)
            .navigationTitle("Raki")
            .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            sectionContent(selectedVisibleSection)
                .id(selectedVisibleSection.rawValue)
        }
        .navigationSplitViewStyle(.balanced)
    }

    @ViewBuilder
    private func sectionContent(_ section: AppSection) -> some View {
        switch section {
        case .home:
            DashboardView()
        }
    }

    private var tabSelection: Binding<Int> {
        Binding(
            get: { tabNavigation.selectedTab },
            set: { tabNavigation.select($0) }
        )
    }

    private var featureVisibility: FeatureVisibility {
        FeatureVisibility()
    }

    private var selectedVisibleSection: AppSection {
        guard let section = AppSection(rawValue: tabNavigation.selectedTab),
              featureVisibility.isVisible(section) else {
            return .home
        }
        return section
    }
}

private struct CompactTabLabel: View {
    let title: String
    let systemImage: String

    @ViewBuilder
    var body: some View {
        if let image = UIImage(
            systemName: systemImage,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        )?.withRenderingMode(.alwaysTemplate) {
            Image(uiImage: image)
        } else {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
        }
        Text(title)
    }
}

private extension AppSection {
    var titleKey: String {
        switch self {
        case .home: return "tab.home"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        }
    }
}

// MARK: - DashboardView
private struct DashboardView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var appState: AppState
    @State private var showSettings = false
    @State private var showLogs = false
    var body: some View {
        NavigationStack {
            VStack(spacing: 7) {
                deviceSection
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 12) {
                    FreeFireGameEntryView(game: .max)
                    FreeFireGameEntryView(game: .regular)
                    FreeFireGameEntryView(game: .capCut)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(AppTheme.pageBackground.ignoresSafeArea())
            .tint(AppTheme.accent)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showLogs = true } label: {
                        Image(systemName: "apple.terminal")
                    }
                    .accessibilityLabel(language.text("accessibility.open_logs"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(language.text("accessibility.open_settings"))
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showLogs) { LogView() }
        }
    }

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(language.text("common.device"))
                .font(.headline)
                .foregroundStyle(.secondary)
            LabeledContent(language.text("dashboard.hardware_model")) {
                Text(AppInfo.displayMachineName)
                    .font(.body.monospaced())
            }
            LabeledContent(language.text("settings.ios_version")) {
                Text("\(AppInfo.osVersion) (\(AppInfo.osBuild))")
                    .font(.body.monospaced())
            }
            HStack {
                Text(language.text("settings.exploit_compatibility"))
                Spacer()
                Text(language.text(appState.isSupported ? "settings.supported" : "settings.exploit_unverified"))
                    .foregroundStyle(appState.isSupported ? Color.green : Color.orange)
            }

            if appState.kernelExploitApplicable && AppInfo.versionTuple.major < 26 {
                HStack {
                    Text(language.text("dashboard.kernel_status"))
                    Spacer()
                    if appState.kernelExploitRunning {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(language.text("dashboard.kernel_running"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(language.text(appState.exploitStatus.isSuccess ? "dashboard.kernel_active" : "dashboard.kernel_inactive"))
                            .foregroundStyle(appState.exploitStatus.isSuccess ? Color.green : Color.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
    }
}

private extension FreeFireGame {
    var scheme: String {
        switch self {
        case .max: return "freefiremax"
        case .regular: return "freefire"
        case .capCut: return "com.googleusercontent.apps.753696289953-c71g0mbsqjtrtdgf1ov874fpru7f22g6"
        }
    }

    var titleKey: String {
        switch self {
        case .max: return "freefire.title"
        case .regular: return "freefire.title_regular"
        case .capCut: return "capcut.title"
        }
    }

    var artworkName: String {
        switch self {
        case .max: return "FreeFireMax"
        case .regular: return "FreeFire"
        case .capCut: return ""
        }
    }

    var logoURL: String {
        "https://play-lh.googleusercontent.com/M78HyakHaxKrjoeqYx41E9DXfVYYtx67nvc7Ks4G4zFQeaAJdGCi8gzzGSrHIwlrmnJS6zD9S4fAXqdEwfuHQAQ=w480-h960"
    }

    var aimProjectNames: [String] {
        switch self {
        case .max: return ["Aim Neck", "Aim Chest", "Aim Body", "Aim Drag", "Aim Magic", "Aim Đầu"]
        case .regular: return ["Aim Body Free Fire", "Aim Drag Free Fire", "Aim Neck Free Fire", "Aim Head Free Fire", "Aim Magic Free Fire", "Unlock FPS 144"]
        case .capCut: return ["CapCut Pro"]
        }
    }

    var locationProjectNames: [String] {
        switch self {
        case .max: return ["Súng Trắng", "Chạm Đỏ"]
        case .regular: return [
                "Chams + Holo tím",
                "Chams Không màu",
                "ChamsKhongMau",
                "Định vị blue",
                "DinhViBlue",
                "Định Vị"
            ]
        case .capCut: return []
        }
    }

    var skinProjectNames: [String] {
        switch self {
        case .max: return []
        case .regular: return ["Mod Skin Gojo"]
        case .capCut: return []
        }
    }

    var openGameKey: String {
        switch self {
        case .max: return "freefire.open_game"
        case .regular: return "freefire.open_game_regular"
        case .capCut: return "capcut.open"
        }
    }

    func canOpen() -> Bool {
        guard let url = URL(string: "\(scheme)://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}

// MARK: - FreeFireGameEntryView
private struct FreeFireGameEntryView: View {
    @Environment(\.appLanguage) private var language
    let game: FreeFireGame
    @State private var isAvailable: Bool
    @State private var showNotice = false
    @State private var navigateToPatch = false

    init(game: FreeFireGame) {
        self.game = game
        _isAvailable = State(initialValue: game.canOpen())
    }

    var body: some View {
        Button {
            if game == .max || game == .regular {
                showNotice = true
            } else {
                navigateToPatch = true
            }
        } label: {
            VStack(spacing: 10) {
                FreeFireArtwork(game: game, size: 68)
                Text(language.text(game.titleKey))
                    .font(.headline)
                    .foregroundStyle(isAvailable ? .primary : .secondary)
                if !isAvailable {
                    Text(language.text("dashboard.unavailable"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(
                isAvailable
                    ? Color(uiColor: .secondarySystemGroupedBackground)
                    : Color(uiColor: .secondarySystemFill),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .opacity(isAvailable ? 1 : 0.7)
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .navigationDestination(isPresented: $navigateToPatch) {
            FreeFirePatchView(game: game)
        }
        .alert(language.text("freefire.notice_title"), isPresented: $showNotice) {
            Button(language.text("freefire.notice_confirm")) {
                navigateToPatch = true
            }
        } message: {
            Text(language.text("freefire.notice_message"))
        }
        .tint(AppTheme.accent)
        .padding(.horizontal, 16)
        .padding(.top, 0)
        .onAppear {
            isAvailable = game.canOpen()
        }
    }
}

// MARK: - FreeFirePatchView
private struct FreeFirePatchView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.openURL) private var openURL
    let game: FreeFireGame
    @StateObject private var store: PatchProjectStore
    @State private var selectedSegment = 0
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var isGameAvailable: Bool

    init(game: FreeFireGame) {
        self.game = game
        _store = StateObject(wrappedValue: PatchProjectStore(game: game))
        _isGameAvailable = State(initialValue: game.canOpen())
    }

    // MARK: - Hàm lấy danh sách item
    private var aimItems: [PatchLibraryItem] {
        let names = game.aimProjectNames
        return names.compactMap { name in
            store.items.first { item in
                item.project?.name == name
            }
        }
    }

    private var locationItems: [PatchLibraryItem] {
        let names = game.locationProjectNames
        var seen: Set<UUID> = []
        return names.compactMap { name in
            guard let match = store.items.first(where: { item in
                let currentName = item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent
                let normalizedName = currentName.lowercased()
                let aliasSet = [name.lowercased(), name.replacingOccurrences(of: " ", with: "").lowercased()]
                return aliasSet.contains(normalizedName)
                    || normalizedName == name.lowercased().replacingOccurrences(of: " ", with: "")
                    || normalizedName == "chamskhongmau"
                    || normalizedName == "dinhviblue"
            }) else { return nil }
            if seen.insert(match.id).inserted { return match }
            return nil
        }
    }

    // MARK: - Display Name
    private func aimDisplayName(for item: PatchLibraryItem) -> String {
        switch item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent {
        case "Aim Neck": return language.text("freefire.aim_neck")
        case "Aim Chest": return language.text("freefire.aim_chest")
        case "Aim Body": return language.text("freefire.aim_body")
        case "Aim Drag": return language.text("freefire.aim_drag")
        case "Aim Magic": return language.text("freefire.aim_magic")
        case "Aim Đầu": return language.text("freefire.aim_head")
        case "Aim Neck Free Fire": return language.text("freefire.aim_neck")
        case "Aim Body Free Fire": return language.text("freefire.aim_body")
        case "Aim Drag Free Fire": return language.text("freefire.aim_drag")
        case "Aim Head Free Fire": return language.text("freefire.aim_head")
        case "Aim Magic Free Fire": return language.text("freefire.aim_magic")
        case "Unlock FPS 144": return language.text("freefire.unlock_fps_144")
        default: return item.project?.name ?? language.text("freefire.aim_file")
        }
    }

    private func locationDisplayName(for item: PatchLibraryItem) -> String {
        switch item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent {
        case "Súng Trắng": return language.text("freefire.white_gun")
        case "Chạm Đỏ": return language.text("freefire.red_touch")
        case "Chams + Holo tím": return language.text("freefire.chams_holo")
        case "Chams Không màu", "ChamsKhongMau": return language.text("freefire.chams_no_color")
        case "Định vị blue", "DinhViBlue": return language.text("freefire.blue_location")
        case "Định Vị": return language.text("freefire.location_main")
        default: return item.project?.name ?? language.text("freefire.location")
        }
    }

    private var skinItems: [PatchLibraryItem] {
        game.skinProjectNames.compactMap { name in
            store.items.first { $0.project?.name == name }
        }
    }

    private func skinDisplayName(for item: PatchLibraryItem) -> String {
        switch item.project?.name ?? item.packageURL.deletingPathExtension().lastPathComponent {
        case "Mod Skin Gojo": return language.text("freefire.gojo")
        default: return item.project?.name ?? language.text("freefire.mod_skin")
        }
    }

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text(language.text(game.titleKey))
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity)
                FreeFireArtwork(game: game, size: 112)
                Text(language.text(game.titleKey))
                    .font(.headline)

                if isLoading {
                    ProgressView(language.text("freefire.loading"))
                        .padding(.vertical, 40)
                } else if let error = loadError {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                } else {
                    // Nội dung chính
                    if let project = aimItems.first?.project {
                        Text(project.allBundleIdentifiers.joined(separator: ", "))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    if game != .capCut {
                        Picker(language.text("freefire.patch_type"), selection: $selectedSegment) {
                            Label(language.text("freefire.aim_file"), systemImage: "scope").tag(0)
                            Label(language.text("freefire.location"), systemImage: "location.fill").tag(1)
                            Label(language.text("freefire.mod_skin"), systemImage: "paintbrush.fill").tag(2)
                        }
                        .pickerStyle(.segmented)
                    }

                    if store.isBusy {
                        ProgressView(language.text("patch.operation_in_progress"))
                            .font(.footnote)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    if game == .capCut {
                        if let item = aimItems.first {
                            Toggle(isOn: Binding(
                                get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
                                set: { store.setEnabled($0, for: item, group: .capCut) }
                            )) {
                                Label(language.text("capcut.activate_pro"), systemImage: "crown.fill")
                            }
                            .padding()
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .disabled(store.isBusy)
                        }
                    } else if selectedSegment == 0 {
                        ForEach(aimItems) { item in
                            Toggle(isOn: Binding(
                                get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
                                set: { store.setEnabled($0, for: item, group: .aim) }
                            )) {
                                Label(aimDisplayName(for: item), systemImage: "scope")
                            }
                            .padding()
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .disabled(store.isBusy)
                        }
                    } else if selectedSegment == 1 {
                        ForEach(locationItems) { item in
                            Toggle(isOn: Binding(
                                get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
                                set: { store.setEnabled($0, for: item, group: .location) }
                            )) {
                                Label(locationDisplayName(for: item), systemImage: "location.fill")
                            }
                            .padding()
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .disabled(store.isBusy)
                        }
                    } else {
                        ForEach(skinItems) { item in
                            Toggle(isOn: Binding(
                                get: { DevicePatchService.latestReceipt(projectID: item.id) != nil },
                                set: { store.setEnabled($0, for: item, group: .skin) }
                            )) {
                                Label(skinDisplayName(for: item), systemImage: "tshirt.fill")
                            }
                            .padding()
                            .background(
                                Color(uiColor: .secondarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                            )
                            .disabled(store.isBusy)
                        }
                    }

                    Button {
                        guard let url = URL(string: "\(game.scheme)://") else { return }
                        if isGameAvailable {
                            openURL(url)
                        }
                    } label: {
                        Label(
                            isGameAvailable ? language.text(game.openGameKey) : language.text("dashboard.unavailable"),
                            systemImage: isGameAvailable ? "gamecontroller.fill" : "gamecontroller"
                        )
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .disabled(!isGameAvailable)
                    .background(
                        isGameAvailable ? AppTheme.accent : Color(uiColor: .systemGray4),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                }
            }
            .padding(16)
        }
        .navigationTitle(language.text(game.titleKey))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            isGameAvailable = game.canOpen()
        }
        .task {
            await loadPatchLibrary()
        }
        .alert(item: $store.alert) { alert in
            let title = Text(language.text(alert.titleKey))
            let message = Text(alert.message(language: language))
            if alert.messageKey == "patch.error.pairing_tunnel_required" {
                return Alert(
                    title: title,
                    message: message,
                    primaryButton: .default(Text(language.text("settings.open_localdevvpn"))) {
                        if let url = URL(string: "localdevvpn://") {
                            openURL(url)
                        }
                    },
                    secondaryButton: .cancel(Text(language.text("common.cancel")))
                )
            }
            return Alert(
                title: title,
                message: message,
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    // MARK: - Hàm tải patch (chạy background)
    private func loadPatchLibrary() async {
        // Chỉ tải một lần (dùng static flag)
        guard !Self.loadedGames.contains(game) else {
            // Nếu đã tải, chỉ cần reload store và tắt loading
            await MainActor.run {
                store.reload()
                isLoading = false
            }
            return
        }

        // Bắt đầu loading
        await MainActor.run {
            isLoading = true
            loadError = nil
        }

        // Chạy tác vụ nặng trong background
        await Task.detached(priority: .userInitiated) {
            do {
                // Gọi các hàm install (có thể là đồng bộ, nhưng chạy ở background)
                // Nếu các hàm này throw, catch sẽ bắt
                try await withCheckedThrowingContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        // Thực hiện cài đặt
                        for patch in game.bundledPatches {
                            if patch.resourceName.hasSuffix(".3105") {
                                PatchProjectLibrary.installBundledFileIfNeeded(
                                    filename: patch.resourceName,
                                    projectName: patch.projectName,
                                    password: patch.password
                                )
                            } else {
                                PatchProjectLibrary.installBundledPackageIfNeeded(
                                    resourceName: patch.resourceName,
                                    projectName: patch.projectName,
                                    password: patch.password
                                )
                            }
                        }

                        // Sau khi cài xong, reload store
                        DispatchQueue.main.async {
                            store.reload()
                            // Đánh dấu đã load
                            Self.loadedGames.insert(game)
                            continuation.resume()
                        }
                    }
                }
                // Cập nhật UI: tắt loading
                await MainActor.run {
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    loadError = "Failed to load patches: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }.value // chờ task hoàn thành
    }

    // Static flag để chỉ load một lần
    private static var loadedGames: Set<FreeFireGame> = []
}

// MARK: - FreeFireArtwork
private struct FreeFireArtwork: View {
    let game: FreeFireGame
    let size: CGFloat

    var body: some View {
        Group {
            if game == .capCut, let logoURL = URL(string: game.logoURL) {
                AsyncImage(url: logoURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallbackArtwork
                    }
                }
            } else if let image = UIImage(named: game.artworkName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                fallbackArtwork
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private var fallbackArtwork: some View {
        Image(systemName: game == .capCut ? "crown.fill" : "gamecontroller.fill")
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.accent)
    }
}
