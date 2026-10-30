import SwiftUI

// MARK: - Modelo de parche local

struct LocalPatch: Identifiable {
    let id: UUID
    let name: String
    let icon: String          // SF Symbol
    let category: PatchCategory
    let fileName: String      // nombre del .3105 en Patches/

    init(name: String, icon: String, category: PatchCategory, fileName: String) {
        self.id = UUID()
        self.name = name
        self.icon = icon
        self.category = category
        self.fileName = fileName
    }
}

enum PatchCategory: String, CaseIterable, Identifiable {
    case aims      = "Aims"
    case holoArmas = "Holo Armas"
    case holosPJ   = "Holos PJ"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .aims:      return "scope"
        case .holoArmas: return "cube"
        case .holosPJ:   return "figure.stand"
        }
    }
}

// MARK: - Catálogo de parches

extension LocalPatch {
    static let catalog: [LocalPatch] = [
        // Aims
        LocalPatch(name: "Aimbot Cabeza",   icon: "scope",          category: .aims,      fileName: "AimHeadFreeFire"),
        LocalPatch(name: "Aimbot Pecho",    icon: "scope",          category: .aims,      fileName: "AimChest"),
        LocalPatch(name: "Aimbot Cuello",   icon: "scope",          category: .aims,      fileName: "AimNeck"),
        LocalPatch(name: "Aimbot Drag",     icon: "scope",          category: .aims,      fileName: "AimDrag"),
        LocalPatch(name: "Balas mágicas",   icon: "sparkles",       category: .aims,      fileName: "AimMagic"),
        LocalPatch(name: "Aimbot Dau",      icon: "scope",          category: .aims,      fileName: "AimDau"),
        // Holo Armas
        LocalPatch(name: "ESP FF TH",       icon: "cube",           category: .holoArmas, fileName: "ESPFREEFIRETH"),
        LocalPatch(name: "Chams Holo Tim",  icon: "cube",           category: .holoArmas, fileName: "ChamsHoloTim"),
        LocalPatch(name: "Chams Rojo",      icon: "cube",           category: .holoArmas, fileName: "ChamDo"),
        LocalPatch(name: "Chams Sin Mau",   icon: "cube",           category: .holoArmas, fileName: "ChamsKhongMau"),
        // Holos PJ
        LocalPatch(name: "Mod Skin Gojo",   icon: "figure.stand",   category: .holosPJ,   fileName: "ModSkinGojo"),
        LocalPatch(name: "DinhVi",          icon: "location.fill",  category: .holosPJ,   fileName: "DinhVi"),
        LocalPatch(name: "SungTrang",       icon: "moon.fill",      category: .holosPJ,   fileName: "SungTrang"),
        LocalPatch(name: "Unlock FPS 144",  icon: "gauge.high",     category: .holosPJ,   fileName: "UnlockFPS144"),
        LocalPatch(name: "CapCut Pro",      icon: "film",           category: .holosPJ,   fileName: "capcutpro"),
    ]
}

// MARK: - Estado global de parches

final class PatchActivationStore: ObservableObject {
    @Published private(set) var active: Set<UUID> = []

    var activeCount: Int { active.count }

    func isActive(_ patch: LocalPatch) -> Bool {
        active.contains(patch.id)
    }

    func toggle(_ patch: LocalPatch, appState: AppState) {
        if active.contains(patch.id) {
            deactivate(patch)
        } else {
            activate(patch, appState: appState)
        }
    }

    private func activate(_ patch: LocalPatch, appState: AppState) {
        guard appState.exploitStatus.isSuccess else {
            log("patch: exploit not ready — cannot apply \(patch.fileName)")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let url = try Self.resolveURL(fileName: patch.fileName)
                let project = try PatchProjectLibrary.load(from: url)
                let _ = try DevicePatchService.apply(project: project)
                DispatchQueue.main.async { self.active.insert(patch.id) }
                log("patch: applied \(patch.fileName)")
            } catch {
                log("patch: failed to apply \(patch.fileName) — \(error)")
            }
        }
    }

    private func deactivate(_ patch: LocalPatch) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let receipt = DevicePatchService.latestReceipt(projectID: patch.id) else {
                    DispatchQueue.main.async { self.active.remove(patch.id) }
                    return
                }
                try DevicePatchService.restore(receipt: receipt)
                DispatchQueue.main.async { self.active.remove(patch.id) }
                log("patch: restored \(patch.fileName)")
            } catch {
                log("patch: failed to restore \(patch.fileName) — \(error)")
                DispatchQueue.main.async { self.active.remove(patch.id) }
            }
        }
    }

    private static func resolveURL(fileName: String) throws -> URL {
        if let url = Bundle.main.url(forResource: fileName, withExtension: "3105") {
            return url
        }
        if let url = Bundle.main.url(forResource: fileName, withExtension: nil) {
            return url
        }
        throw PatchPackageError.resourceNotFound(fileName)
    }
}

// MARK: - HomeView principal

struct HomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var patchStore: PatchActivationStore
    @State private var selectedCategory: PatchCategory = .aims

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                Color(.systemGroupedBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    headerSection
                    categoryPicker
                    patchList
                }
            }
            .navigationBarHidden(true)
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 12) {
                // Avatar
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 52, height: 52)
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary)
                }
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))

                VStack(alignment: .leading, spacing: 2) {
                    Text("HOME")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                        .tracking(1.2)

                    Text("DarielModz")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }

                Spacer()

                // Badge LIVE
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
            }

            // Subtítulo explotit status
            Text(exploitStatusText)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.leading, 64)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: Category Picker

    private var categoryPicker: some View {
        HStack {
            HStack {
                Text(selectedCategory.rawValue.uppercased())
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .tracking(0.8)
                Spacer()
                Text("\(activeInCategory)/\(patchesInCategory.count) activos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    // MARK: Patch List

    private var patchList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(patchesInCategory) { patch in
                    PatchRow(
                        patch: patch,
                        isActive: patchStore.isActive(patch),
                        exploitReady: appState.exploitStatus.isSuccess
                    ) {
                        patchStore.toggle(patch, appState: appState)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 100)
        }
    }

    // MARK: Helpers

    private var patchesInCategory: [LocalPatch] {
        LocalPatch.catalog.filter { $0.category == selectedCategory }
    }

    private var activeInCategory: Int {
        patchesInCategory.filter { patchStore.isActive($0) }.count
    }

    private var exploitStatusText: String {
        switch appState.exploitStatus {
        case .notStarted:    return "Iniciando exploit..."
        case .success:       return "Acceso activo"
        case .failed:        return "Exploit fallido — reinicia la app"
        case .unsupported:   return "iOS no compatible"
        }
    }
}

// MARK: - PatchRow

struct PatchRow: View {
    let patch: LocalPatch
    let isActive: Bool
    let exploitReady: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icono
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(isActive ? 0.18 : 0.10))
                    .frame(width: 44, height: 44)
                Image(systemName: patch.icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.accentColor)
            }

            // Nombre + estado
            VStack(alignment: .leading, spacing: 3) {
                Text(patch.name)
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                HStack(spacing: 4) {
                    Circle()
                        .fill(isActive ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(isActive ? "Activo" : "Inactivo")
                        .font(.caption)
                        .foregroundColor(isActive ? .green : .secondary)
                }
            }

            Spacer()

            // Toggle
            Toggle("", isOn: Binding(
                get: { isActive },
                set: { _ in
                    guard exploitReady else { return }
                    onToggle()
                }
            ))
            .labelsHidden()
            .disabled(!exploitReady)
            .opacity(exploitReady ? 1 : 0.4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}

// MARK: - RootTabView

struct RootTabView: View {
    @EnvironmentObject private var patchStore: PatchActivationStore
    @State private var selectedTab: PatchCategory = .aims

    var body: some View {
        VStack(spacing: 0) {
            // Contenido de la tab seleccionada
            TabContentView(selectedCategory: $selectedTab)

            Divider()

            // Tab bar custom
            HStack(spacing: 0) {
                ForEach(PatchCategory.allCases) { category in
                    Button {
                        selectedTab = category
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: category.systemImage)
                                .font(.system(size: 20, weight: .medium))
                            Text(category.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(selectedTab == category ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(.keyboard)
    }
}

struct TabContentView: View {
    @Binding var selectedCategory: PatchCategory
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var patchStore: PatchActivationStore

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()
                VStack(spacing: 0) {
                    headerSection
                    categoryLabel
                    patchScrollView
                }
            }
            .navigationBarHidden(true)
        }
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(.systemGray5))
                    .frame(width: 52, height: 52)
                Image(systemName: "person.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.secondary)
            }
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))

            VStack(alignment: .leading, spacing: 2) {
                Text("HOME")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
                    .tracking(1.2)
                Text("DarielModz")
                    .font(.title2)
                    .fontWeight(.bold)
            }

            Spacer()

            LiveBadge()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }

    private var categoryLabel: some View {
        HStack {
            Text(selectedCategory.rawValue.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(0.8)
                .foregroundColor(.primary)
            Spacer()
            Text("\(activeCount)/\(patches.count) activos")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var patchScrollView: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(patches) { patch in
                    PatchRow(
                        patch: patch,
                        isActive: patchStore.isActive(patch),
                        exploitReady: appState.exploitStatus.isSuccess
                    ) {
                        patchStore.toggle(patch, appState: appState)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
    }

    private var patches: [LocalPatch] {
        LocalPatch.catalog.filter { $0.category == selectedCategory }
    }

    private var activeCount: Int {
        patches.filter { patchStore.isActive($0) }.count
    }
}

// MARK: - Componentes reutilizables

struct LiveBadge: View {
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color.accentColor).frame(width: 7, height: 7)
            Text("LIVE")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Error type para recursos no encontrados

extension PatchPackageError {
    static func resourceNotFound(_ name: String) -> PatchPackageError {
        .targetAppUnavailable(name)
    }
}
