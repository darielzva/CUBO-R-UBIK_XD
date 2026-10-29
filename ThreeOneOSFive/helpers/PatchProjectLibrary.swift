import Foundation

struct PatchLibraryItem: Identifiable {
    let summary: PatchPackageSummary
    var project: PatchProject?
    var contentKey: Data?
    var packageURL: URL

    var id: UUID { summary.packageID }
    var isLocked: Bool { project == nil }
    var workspaceURL: URL? {
        PatchWorkspaceService.workspaceURL(projectID: id)
    }
}

struct PatchPasswordRequest: Identifiable {
    let summary: PatchPackageSummary
    var id: UUID { summary.packageID }
}

enum PatchProjectLibrary {
    private static let bundledProjectIDs: [String: UUID] = [
        "Aim Neck": UUID(uuidString: "8B0E5B4A-DBE7-4B61-9F1A-2F1C4A8E7D10")!,
        "Chạm Đỏ": UUID(uuidString: "D3A67C21-4F8B-46E2-8A0C-91B5E7D2C634")!
    ]
    private static let bundledProjectNames: Set<String> = [
        "Aim Neck", "Aim Chest", "Aim Body", "Aim Drag", "Aim Magic", "Aim Đầu",
        "Súng Trắng", "Chạm Đỏ", "Aim Neck Free Fire", "Aim Body Free Fire",
        "Aim Drag Free Fire", "Aim Head Free Fire", "Aim Magic Free Fire", "Unlock FPS 144",
        "Chams + Holo tím", "Chams Không màu", "ChamsKhongMau",
        "Định vị blue", "DinhViBlue", "Định Vị", "Mod Skin Gojo", "CapCut Pro"
    ]

    static func isBundledProject(_ project: PatchProject) -> Bool {
        bundledProjectNames.contains(project.name)
    }

    static func removeBundledPackage(named projectName: String, fileManager: FileManager = .default) {
        guard let root = try? packageRootURL(fileManager: fileManager) else { return }
        let destination = root.appendingPathComponent("\(projectName).3105")
        try? fileManager.removeItem(at: destination)
    }

    static func installBundledPackageIfNeeded(
        resourceName: String,
        projectName: String? = nil,
        password: String? = "nmkiosvn",
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
          guard let asset = NSDataAsset(name: resourceName, bundle: bundle),
              let sourceData = try? Data(asset.data),
              let sourceSummary = try? PatchPackageCodec.inspect(sourceData),
              let root = try? packageRootURL(fileManager: fileManager) else { return }

        let packageName = projectName ?? resourceName
        let destination = root.appendingPathComponent("\(packageName).3105")
        if fileManager.fileExists(atPath: destination.path) {
            if let existingData = try? readPackage(at: destination),
               let existingSummary = try? PatchPackageCodec.inspect(existingData),
               existingSummary.isPasswordProtected,
               let keyResult = try? PatchKeyStore.load(for: existingSummary),
               let existingDecoded = try? PatchPackageCodec.decode(existingData, contentKey: keyResult),
               existingDecoded.project.name == packageName {
                if let expectedID = bundledProjectIDs[packageName], existingDecoded.project.id != expectedID {
                    try? PatchKeyStore.delete(for: existingSummary)
                    try? PatchWorkspaceService.deleteWorkspace(
                        projectID: existingDecoded.project.id,
                        fileManager: fileManager
                    )
                    try? fileManager.removeItem(at: destination)
                } else {
                    if isBundledProject(existingDecoded.project) {
                        try? PatchWorkspaceService.deleteWorkspace(
                            projectID: existingDecoded.project.id,
                            fileManager: fileManager
                        )
                    }
                    return
                }
            }
            try? fileManager.removeItem(at: destination)
        }

        let decoded: DecodedPatchPackage?
        if let current = try? PatchPackageCodec.decode(sourceData, password: password) {
            decoded = current
        } else if password != "YaBao",
                  let legacy = try? PatchPackageCodec.decode(sourceData, password: "YaBao") {
            decoded = legacy
        } else if !sourceSummary.isPasswordProtected,
                  let unprotected = try? PatchPackageCodec.decode(sourceData, password: nil) {
            decoded = unprotected
        } else {
            decoded = nil
        }
        guard let decoded else { return }

        var normalizedProject = decoded.project
        normalizedProject.name = packageName
        if let bundledProjectID = bundledProjectIDs[packageName] {
            normalizedProject.id = bundledProjectID
        }
        guard let encoded = try? PatchPackageCodec.encodeNew(
            project: normalizedProject,
            password: password
        ), let summary = try? PatchPackageCodec.inspect(encoded.data) else { return }

        do {
            try PatchKeyStore.store(encoded.contentKey, for: summary)
            let savedURL = try save(
                data: encoded.data,
                projectName: packageName,
                fileManager: fileManager
            )
            try installImportedPackage(
                data: encoded.data,
                decoded: DecodedPatchPackage(project: normalizedProject, contentKey: encoded.contentKey),
                summary: summary,
                existingURL: savedURL,
                createWorkspace: false,
                fileManager: fileManager
            )
            if savedURL != destination {
                try? fileManager.moveItem(at: savedURL, to: destination)
            }
        } catch {
            log("patch: bundled package unavailable")
        }
    }

    static func installBundledFileIfNeeded(
        filename: String,
        projectName: String,
        password: String? = nil,
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        let filenameWithoutExtension = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        guard let sourceURL = bundle.url(forResource: filename, withExtension: nil)
            ?? bundle.url(forResource: filenameWithoutExtension, withExtension: "3105"),
              let sourceData = try? Data(contentsOf: sourceURL),
              let sourceSummary = try? PatchPackageCodec.inspect(sourceData),
              let root = try? packageRootURL(fileManager: fileManager) else { return }

        let destination = root.appendingPathComponent("\(projectName).3105")
        if fileManager.fileExists(atPath: destination.path) {
            if let existingData = try? readPackage(at: destination),
               let existingSummary = try? PatchPackageCodec.inspect(existingData),
               let key = try? PatchKeyStore.load(for: existingSummary),
               let existingDecoded = try? PatchPackageCodec.decode(existingData, contentKey: key),
               existingDecoded.project.name == projectName {
                return
            }
            try? fileManager.removeItem(at: destination)
        }

          guard let decoded = try? PatchPackageCodec.decode(sourceData, password: password) else { return }

        do {
            var normalizedProject = decoded.project
            normalizedProject.name = projectName
            let normalizedData = try PatchPackageCodec.encodeNew(
                project: normalizedProject,
                password: password
            )
            let normalizedSummary = try PatchPackageCodec.inspect(normalizedData.data)
            try PatchKeyStore.store(normalizedData.contentKey, for: normalizedSummary)
            try installImportedPackage(
                data: normalizedData.data,
                decoded: DecodedPatchPackage(project: normalizedProject, contentKey: normalizedData.contentKey),
                summary: normalizedSummary,
                existingURL: destination,
                createWorkspace: false,
                fileManager: fileManager
            )
        } catch {
            log("patch: bundled file unavailable")
        }
    }

    static func packageRootURL(fileManager: FileManager = .default) throws -> URL {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = base.appendingPathComponent("PatchProjects", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func backupRootURL(fileManager: FileManager = .default) throws -> URL {
        let root = try packageRootURL(fileManager: fileManager)
            .appendingPathComponent("Backups", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func load(fileManager: FileManager = .default) -> [PatchLibraryItem] {
        guard let root = try? packageRootURL(fileManager: fileManager),
              let urls = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
              ) else { return [] }

        var byID: [UUID: PatchLibraryItem] = [:]
        for url in urls where url.pathExtension.lowercased() == "3105" {
            do {
                let data = try readPackage(at: url)
                let summary = try PatchPackageCodec.inspect(data)
                let decoded: DecodedPatchPackage?
                if let contentKey = try PatchKeyStore.load(for: summary) {
                    decoded = try PatchPackageCodec.decode(data, contentKey: contentKey)
                } else if summary.isPasswordProtected {
                    decoded = nil
                } else {
                    decoded = try PatchPackageCodec.decode(data, password: nil)
                }
                let item = PatchLibraryItem(
                    summary: summary,
                    project: decoded?.project,
                    contentKey: decoded?.contentKey,
                    packageURL: url
                )
                     if summary.schemaVersion >= 2,
                         let project = decoded?.project,
                         !isBundledProject(project) {
                    do {
                        _ = try PatchWorkspaceService.ensureWorkspace(for: project)
                    } catch {
                        log("patch: workspace unavailable for \(project.id.uuidString)")
                    }
                }
                byID[summary.packageID] = item
            } catch {
                log("patch: skipped invalid local package \(url.lastPathComponent)")
            }
        }
        return byID.values.sorted {
            ($0.project?.updatedAt ?? .distantPast) > ($1.project?.updatedAt ?? .distantPast)
        }
    }

    static func readPackage(at url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isDirectory != true,
              values.isSymbolicLink != true,
              values.isRegularFile == true else {
            throw PatchPackageError.invalidProject
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    static func save(
        data: Data,
        projectName: String,
        existingURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let destination: URL
        if let existingURL {
            destination = existingURL
        } else {
            let root = try packageRootURL(fileManager: fileManager)
            let baseName = sanitizedFilename(projectName)
            var candidate = root.appendingPathComponent(baseName).appendingPathExtension("3105")
            var suffix = 2
            while fileManager.fileExists(atPath: candidate.path) {
                candidate = root.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("3105")
                suffix += 1
            }
            destination = candidate
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        return destination
    }

    static func installImportedPackage(
        data: Data,
        decoded: DecodedPatchPackage,
        summary: PatchPackageSummary,
        existingURL: URL?,
        createWorkspace: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        let previousData = try existingURL.map { try readPackage(at: $0) }
        var savedURL: URL?
        do {
            savedURL = try save(
                data: data,
                projectName: decoded.project.name,
                existingURL: existingURL,
                fileManager: fileManager
            )
            if summary.schemaVersion >= 2, createWorkspace {
                _ = try PatchWorkspaceService.replaceWorkspace(
                    with: decoded.project,
                    fileManager: fileManager
                )
            } else if summary.schemaVersion >= 2 {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            } else {
                try? PatchWorkspaceService.deleteWorkspace(
                    projectID: decoded.project.id,
                    fileManager: fileManager
                )
            }
        } catch {
            if let previousData, let existingURL {
                try? previousData.write(
                    to: existingURL,
                    options: [.atomic, .completeFileProtection]
                )
            } else if let savedURL, fileManager.fileExists(atPath: savedURL.path) {
                try? fileManager.removeItem(at: savedURL)
            }
            throw error
        }
    }

    static func delete(_ item: PatchLibraryItem, fileManager: FileManager = .default) throws {
        if fileManager.fileExists(atPath: item.packageURL.path) {
            try fileManager.removeItem(at: item.packageURL)
        }
        try? PatchWorkspaceService.deleteWorkspace(projectID: item.id, fileManager: fileManager)
        try? PatchKeyStore.delete(for: item.summary)
    }

    static func synchronizeWorkspace(
        item: PatchLibraryItem,
        fileManager: FileManager = .default
    ) throws -> PatchProject {
        guard item.summary.schemaVersion >= 2,
              let baseProject = item.project,
              let contentKey = item.contentKey else {
            throw PatchPackageError.invalidProject
        }
        guard !isBundledProject(baseProject) else { return baseProject }
        let workspace = try PatchWorkspaceService.ensureWorkspace(for: baseProject, fileManager: fileManager)
        let project = try PatchWorkspaceService.snapshot(
            baseProject: baseProject,
            workspaceURL: workspace,
            fileManager: fileManager
        )
        let original = try readPackage(at: item.packageURL)
        let updated = try PatchPackageCodec.update(
            original,
            project: project,
            contentKey: contentKey,
            schemaVersion: PatchPackageCodec.latestSchemaVersion
        )
        _ = try save(
            data: updated,
            projectName: project.name,
            existingURL: item.packageURL,
            fileManager: fileManager
        )
        return project
    }

    private static func sanitizedFilename(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" }
        let result = String(scalars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(80)
        return result.isEmpty ? "Patch" : String(result)
    }
}
