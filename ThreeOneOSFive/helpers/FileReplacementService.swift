import Foundation
import Darwin
import UniformTypeIdentifiers
import AirliftFFI

private let patchAirliftLogCallback: ALLogCallback = { _, message in
    guard let message else { return }
    let line = String(cString: message).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return }
    log("Airlift: \(line)")
}

enum ReplacementPickerPolicy {
    static let allowedContentTypes: [UTType] = [.data]
    static let copiesSelectedDocument = true
    static let presentationDelay: TimeInterval = 0.35

    static func accepts(_ type: UTType) -> Bool {
        type.conforms(to: .data) && !type.conforms(to: .folder)
    }
}

struct FileReplacementSelection: Equatable {
    let targetURL: URL
    let targetName: String
    let sourceURL: URL
}

struct FileReplacementRequest: Identifiable, Equatable {
    let id: UUID
    let targetURL: URL
    let targetName: String

    init(id: UUID = UUID(), targetURL: URL, targetName: String) {
        self.id = id
        self.targetURL = targetURL
        self.targetName = targetName
    }

    func selection(from urls: [URL]) throws -> FileReplacementSelection {
        guard let sourceURL = urls.first else {
            throw FileReplacementError.sourceMissing
        }
        return FileReplacementSelection(
            targetURL: targetURL,
            targetName: targetName,
            sourceURL: sourceURL
        )
    }
}

enum FileReplacementError: Error, Equatable, LocalizedError {
    case targetMissing
    case sourceMissing
    case targetIsDirectory
    case sourceIsDirectory
    case sameFile
    case symbolicLinkUnsupported
    case sourceTooLarge
    case backupFailed
    case replacementFailed
    case pairingFileMissing
    case bundleIdentifierMissing
    case remotePathUnsafe
    case remoteContainerUnavailable
    case remoteReplacementFailed(String)

    var errorDescription: String? {
        switch self {
        case .targetMissing: return "The target file no longer exists."
        case .sourceMissing: return "The selected replacement file is unavailable."
        case .targetIsDirectory: return "Folders cannot be replaced with this action."
        case .sourceIsDirectory: return "Select a file, not a folder."
        case .sameFile: return "A file cannot replace itself."
        case .symbolicLinkUnsupported: return "Symbolic links are not supported."
        case .sourceTooLarge: return "The selected file is too large."
        case .backupFailed: return "The original file could not be backed up."
        case .replacementFailed: return "The file could not be replaced safely."
        case .pairingFileMissing: return "Import or create a pairing file before replacing this file."
        case .bundleIdentifierMissing: return "The app container could not be identified for remote replacement."
        case .remotePathUnsafe: return "The remote target path is invalid."
        case .remoteContainerUnavailable: return "The remote app container could not be resolved over the pairing tunnel."
        case .remoteReplacementFailed(let detail): return detail
        }
    }
}

struct FileReplacementResult: Equatable {
    let targetURL: URL
    let byteCount: Int64
    let backupURL: URL
}

enum FileReplacementService {
    private static let chunkSize = 1_024 * 1_024
    private static let maximumRemotePathBytes = 768

    static func writeRemoteFile(
        bundleID: String,
        relativePath rawRelativePath: String,
        data: Data,
        pairingFileURL: URL,
        remoteContainerPath: String
    ) throws {
        let relativePath: String
        do {
            relativePath = try PatchPathValidator.canonicalRelativePath(rawRelativePath)
        } catch {
            throw PatchPackageError.unsafeTargetPath
        }
          let leafName = (relativePath as NSString).lastPathComponent
          guard remoteContainerPath.hasPrefix("/var/mobile/Containers/Data/Application/"),
              !leafName.hasPrefix(".") else {
            throw PatchPackageError.unsafeTargetPath
        }

        let remoteTarget = URL(fileURLWithPath: remoteContainerPath, isDirectory: true)
            .appendingPathComponent(relativePath)
        let sourceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("3105-patch-remote-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: sourceDirectory) }
            try data.write(to: sourceDirectory.appendingPathComponent(remoteTarget.lastPathComponent), options: .atomic)

            var errorPointer: UnsafeMutablePointer<CChar>?
            let returnCode = pairingFileURL.path.withCString { pairingPath in
                sourceDirectory.path.withCString { sourcePath in
                    remoteTarget.deletingLastPathComponent().path.withCString { targetDirectory in
                        al_exploit_write_dir(pairingPath, sourcePath, targetDirectory, nil, nil, &errorPointer)
                    }
                }
            }
            defer {
                if let errorPointer { al_string_free(errorPointer) }
            }
            guard returnCode == 0 else {
                let detail = errorPointer.map { String(cString: $0) }
                    ?? "Remote file write failed (\(returnCode))."
                throw PatchPackageError.remoteReplacementFailed(detail)
            }
            log("patch: Airlift wrote \(bundleID)/\(relativePath) bytes=\(data.count)")
        } catch let error as PatchPackageError {
            throw error
        } catch {
            throw PatchPackageError.remoteReplacementFailed(error.localizedDescription)
        }
    }

    static func readRemoteFile(
        bundleID: String,
        relativePath rawRelativePath: String,
        pairingFileURL: URL,
        remoteContainerPath: String
    ) throws -> Data {
        let relativePath: String
        do {
            relativePath = try PatchPathValidator.canonicalRelativePath(rawRelativePath)
        } catch {
            throw PatchPackageError.unsafeTargetPath
        }
        guard remoteContainerPath.hasPrefix("/var/mobile/Containers/Data/Application/"),
              (remoteContainerPath + "/" + relativePath).utf8.count <= maximumRemotePathBytes else {
            throw PatchPackageError.unsafeTargetPath
        }

        let remoteTarget = URL(fileURLWithPath: remoteContainerPath, isDirectory: true)
            .appendingPathComponent(relativePath)
        _ = try validatedRemoteTargetURL(remoteTarget.path)
        log("patch: Airlift remote read started \(bundleID)/\(relativePath)")
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("3105-remote-read-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        var errorPointer: UnsafeMutablePointer<CChar>?
        let returnCode = pairingFileURL.path.withCString { pairingPath in
            remoteTarget.path.withCString { targetPath in
                outputURL.path.withCString { outputPath in
                    al_exploit_read_file(
                        pairingPath,
                        targetPath,
                        outputPath,
                        patchAirliftLogCallback,
                        nil,
                        &errorPointer
                    )
                }
            }
        }
        let remoteError = errorPointer.map { String(cString: $0) }
        if let errorPointer { al_string_free(errorPointer) }
        guard returnCode == 0 else {
            let detail = remoteError ?? "Remote file read failed (\(returnCode))."
            log("patch: Airlift remote read failed \(bundleID)/\(relativePath) rc=\(returnCode) detail=\(detail)")
            throw PatchPackageError.remoteReplacementFailed(detail)
        }
        let data: Data
        do {
            data = try Data(contentsOf: outputURL, options: .mappedIfSafe)
        } catch {
            throw PatchPackageError.remoteReplacementFailed("Remote file backup could not be loaded.")
        }
        guard data.count <= 32 * 1_024 * 1_024 else {
            throw PatchPackageError.sizeLimitExceeded
        }
        log("patch: Airlift read \(bundleID)/\(relativePath) bytes=\(data.count)")
        return data
    }

    static func replaceOverPairing(
        target targetURL: URL,
        with sourceURL: URL,
        bundleID: String,
        containerRoot: URL,
        pairingFileURL: URL,
        fileManager: FileManager = .default
    ) throws -> FileReplacementResult {
        guard fileManager.fileExists(atPath: pairingFileURL.path) else {
            throw FileReplacementError.pairingFileMissing
        }

        let targetValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        let sourceValues = try values(
            for: sourceURL,
            missingError: .sourceMissing,
            fileManager: fileManager
        )
        guard targetValues.isSymbolicLink != true,
              sourceValues.isSymbolicLink != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard targetValues.isDirectory != true else {
            throw FileReplacementError.targetIsDirectory
        }
        guard sourceValues.isDirectory != true else {
            throw FileReplacementError.sourceIsDirectory
        }
        guard targetURL.standardizedFileURL.resolvingSymlinksInPath()
                != sourceURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FileReplacementError.sameFile
        }

        let rootPath = PatchPathValidator.canonicalFileURL(containerRoot).path
        let targetPath = PatchPathValidator.canonicalFileURL(targetURL).path
        guard targetPath.hasPrefix(rootPath + "/") else {
            throw FileReplacementError.remotePathUnsafe
        }
        let rawRelativePath = String(targetPath.dropFirst(rootPath.count + 1))
        guard let relativePath = try? PatchPathValidator.canonicalRelativePath(rawRelativePath) else {
            throw FileReplacementError.remotePathUnsafe
        }

        let remoteContainer = try remoteContainerPath(
            pairingFileURL: pairingFileURL,
            bundleID: bundleID
        )
        let remoteTarget = URL(fileURLWithPath: remoteContainer, isDirectory: true)
            .appendingPathComponent(relativePath)
        return try replaceOverPairing(
            target: targetURL,
            with: sourceURL,
            remoteTarget: remoteTarget,
            pairingFileURL: pairingFileURL,
            fileManager: fileManager
        )
    }

    static func replaceOverPairing(
        target targetURL: URL,
        with sourceURL: URL,
        remoteTargetPath: String,
        pairingFileURL: URL,
        fileManager: FileManager = .default
    ) throws -> FileReplacementResult {
        guard fileManager.fileExists(atPath: pairingFileURL.path) else {
            throw FileReplacementError.pairingFileMissing
        }
        let remoteTarget = try validatedRemoteTargetURL(remoteTargetPath)
        return try replaceOverPairing(
            target: targetURL,
            with: sourceURL,
            remoteTarget: remoteTarget,
            pairingFileURL: pairingFileURL,
            fileManager: fileManager
        )
    }

    private static func replaceOverPairing(
        target targetURL: URL,
        with sourceURL: URL,
        remoteTarget: URL,
        pairingFileURL: URL,
        fileManager: FileManager
    ) throws -> FileReplacementResult {
        guard remoteTarget.lastPathComponent == targetURL.lastPathComponent else {
            throw FileReplacementError.remotePathUnsafe
        }
        let targetValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        let sourceValues = try values(
            for: sourceURL,
            missingError: .sourceMissing,
            fileManager: fileManager
        )
        guard targetValues.isSymbolicLink != true,
              sourceValues.isSymbolicLink != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard targetValues.isDirectory != true else {
            throw FileReplacementError.targetIsDirectory
        }
        guard sourceValues.isDirectory != true else {
            throw FileReplacementError.sourceIsDirectory
        }
        guard targetURL.standardizedFileURL.resolvingSymlinksInPath()
                != sourceURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FileReplacementError.sameFile
        }
        guard fileManager.fileExists(atPath: pairingFileURL.path) else {
            throw FileReplacementError.pairingFileMissing
        }

        let remoteParentPath = remoteTarget.deletingLastPathComponent().path
        let backupURL = try backupOriginalFile(at: targetURL, fileManager: fileManager)

        let stagingDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("3105-remote-replacement-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let stagedSource = stagingDirectory.appendingPathComponent(targetURL.lastPathComponent)
        do {
            try fileManager.copyItem(at: sourceURL, to: stagedSource)
        } catch {
            throw FileReplacementError.replacementFailed
        }

        var outError: UnsafeMutablePointer<CChar>?
        let returnCode = pairingFileURL.path.withCString { pairingPath in
            stagingDirectory.path.withCString { sourceDirectory in
                remoteParentPath.withCString { targetDirectory in
                    al_exploit_write_dir(
                        pairingPath,
                        sourceDirectory,
                        targetDirectory,
                        nil,
                        nil,
                        &outError
                    )
                }
            }
        }
        let remoteError = outError.map { String(cString: $0) }
        if let outError {
            al_string_free(outError)
        }
        guard returnCode == 0 else {
            throw FileReplacementError.remoteReplacementFailed(
                remoteError ?? "The remote file write failed (\(returnCode))."
            )
        }

        let replacedValues = try values(
            for: sourceURL,
            missingError: .sourceMissing,
            fileManager: fileManager
        )
        let byteCount = Int64(replacedValues.fileSize ?? 0)
        log("file replacement: remote target=\(remoteTarget.path) backup=\(backupURL.path)")
        return FileReplacementResult(targetURL: targetURL, byteCount: byteCount, backupURL: backupURL)
    }

    private static func validatedRemoteTargetURL(_ rawPath: String) throws -> URL {
        guard rawPath.utf8.count <= maximumRemotePathBytes,
              !rawPath.contains("\\"),
              !rawPath.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw FileReplacementError.remotePathUnsafe
        }

        let path: String
        if rawPath.hasPrefix("/private/var/mobile/") {
            path = String(rawPath.dropFirst("/private".count))
        } else if rawPath.hasPrefix("/var/mobile/") {
            path = rawPath
        } else {
            throw FileReplacementError.remotePathUnsafe
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.first == "",
              components.dropFirst().allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components.count > 3 else {
            throw FileReplacementError.remotePathUnsafe
        }
        return URL(fileURLWithPath: path, isDirectory: false)
    }

    static func remoteContainerPath(pairingFileURL: URL, bundleID: String) throws -> String {
        var containerPointer: UnsafeMutablePointer<CChar>?
        var errorPointer: UnsafeMutablePointer<CChar>?
        let returnCode = pairingFileURL.path.withCString { pairingPath in
            bundleID.withCString { bundleIdentifier in
                al_find_app_container(
                    pairingPath,
                    bundleIdentifier,
                    nil,
                    nil,
                    &containerPointer,
                    &errorPointer
                )
            }
        }
        defer {
            if let containerPointer { al_string_free(containerPointer) }
            if let errorPointer { al_string_free(errorPointer) }
        }
        guard returnCode == 0,
              let containerPointer,
              let containerPath = String(validatingUTF8: containerPointer),
              containerPath.hasPrefix("/var/mobile/Containers/Data/Application/") else {
            throw FileReplacementError.remoteContainerUnavailable
        }
        return containerPath
    }

    static func replace(
        target targetURL: URL,
        with sourceURL: URL,
        fileManager: FileManager = .default
    ) throws -> FileReplacementResult {
        let targetValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        let sourceValues = try values(
            for: sourceURL,
            missingError: .sourceMissing,
            fileManager: fileManager
        )
        guard targetValues.isSymbolicLink != true,
              sourceValues.isSymbolicLink != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard targetValues.isDirectory != true else {
            throw FileReplacementError.targetIsDirectory
        }
        guard sourceValues.isDirectory != true else {
            throw FileReplacementError.sourceIsDirectory
        }
        guard targetURL.standardizedFileURL.resolvingSymlinksInPath()
                != sourceURL.standardizedFileURL.resolvingSymlinksInPath() else {
            throw FileReplacementError.sameFile
        }
        let targetAttributes = try fileManager.attributesOfItem(atPath: targetURL.path)
        let backupURL = try backupOriginalFile(
            at: targetURL,
            fileManager: fileManager
        )
        let stagingURL = targetURL.deletingLastPathComponent()
            .appendingPathComponent(".3105-replacement-\(UUID().uuidString)")
        let stagingAttributes = retainedAttributes(from: targetAttributes)
        guard fileManager.createFile(
            atPath: stagingURL.path,
            contents: nil,
            attributes: stagingAttributes
        ) else {
            throw FileReplacementError.replacementFailed
        }
        defer { try? fileManager.removeItem(at: stagingURL) }

        var copied: Int64 = 0
        do {
            let source = try FileHandle(forReadingFrom: sourceURL)
            let staging = try FileHandle(forWritingTo: stagingURL)
            defer {
                try? source.close()
                try? staging.close()
            }
            while let data = try source.read(upToCount: chunkSize), !data.isEmpty {
                let (nextCount, overflow) = copied.addingReportingOverflow(Int64(data.count))
                guard !overflow else {
                    throw FileReplacementError.sourceTooLarge
                }
                copied = nextCount
                try staging.write(contentsOf: data)
            }
            try staging.synchronize()
        } catch let error as FileReplacementError {
            throw error
        } catch {
            throw FileReplacementError.replacementFailed
        }

        let currentValues = try values(
            for: targetURL,
            missingError: .targetMissing,
            fileManager: fileManager
        )
        guard currentValues.isSymbolicLink != true,
              currentValues.isDirectory != true else {
            throw FileReplacementError.symbolicLinkUnsupported
        }
        guard rename(stagingURL.path, targetURL.path) == 0 else {
            throw FileReplacementError.replacementFailed
        }
        return FileReplacementResult(
            targetURL: targetURL,
            byteCount: copied,
            backupURL: backupURL
        )
    }

    private static func backupOriginalFile(
        at targetURL: URL,
        fileManager: FileManager
    ) throws -> URL {
        do {
            let root = AppPaths.backupsURL
                .appendingPathComponent("replacements", isDirectory: true)
            try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
            let pathLabel = targetURL.path
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "/", with: "__")
            let timestamp = ISO8601DateFormatter().string(from: Date())
                .replacingOccurrences(of: ":", with: "-")
            let backupURL = root.appendingPathComponent(
                "\(timestamp)-\(pathLabel)-\(UUID().uuidString)",
                isDirectory: false
            )
            try fileManager.copyItem(at: targetURL, to: backupURL)
            log("file replacement: backup created \(backupURL.path) from \(targetURL.path)")
            return backupURL
        } catch {
            throw FileReplacementError.backupFailed
        }
    }

    private static func values(
        for url: URL,
        missingError: FileReplacementError,
        fileManager: FileManager
    ) throws -> URLResourceValues {
        guard fileManager.fileExists(atPath: url.path) else { throw missingError }
        do {
            return try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        } catch {
            throw missingError
        }
    }

    private static func retainedAttributes(
        from attributes: [FileAttributeKey: Any]
    ) -> [FileAttributeKey: Any] {
        var result: [FileAttributeKey: Any] = [:]
        if let permissions = attributes[.posixPermissions] {
            result[.posixPermissions] = permissions
        }
        if let protection = attributes[.protectionKey] {
            result[.protectionKey] = protection
        }
        return result
    }
}

enum LocalDevTunnelProbe {
    static var isConnected: Bool {
        let interfaces = ipv4Interfaces()
        guard let routeAddress = routeSource(to: "10.7.0.1") else { return false }
        return interfaces.contains {
            isTunnelInterface($0.name) && $0.address == routeAddress
        }
    }

    private static func ipv4Interfaces() -> [(name: String, address: String)] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let firstAddress = addresses else { return [] }
        defer { freeifaddrs(addresses) }

        var result: [(name: String, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            guard let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET),
                  let ipv4 = numericHost(address) else { continue }
            result.append((String(cString: interface.pointee.ifa_name), ipv4))
        }
        return result
    }

    private static func routeSource(to ipAddress: String) -> String? {
        var remote = sockaddr_in()
        remote.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        remote.sin_family = sa_family_t(AF_INET)
        remote.sin_port = in_port_t(UInt16(9).bigEndian)
        guard ipAddress.withCString({ inet_pton(AF_INET, $0, &remote.sin_addr) }) == 1 else { return nil }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        let connected = withUnsafePointer(to: remote) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return nil }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard read == 0, local.sin_addr.s_addr != 0 else { return nil }
        return withUnsafeMutablePointer(to: &local) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1, numericHost)
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
        ) == 0 else { return nil }
        return String(cString: host)
    }

    private static func isTunnelInterface(_ name: String) -> Bool {
        name.hasPrefix("utun") || name.hasPrefix("ipsec")
            || name.hasPrefix("tap") || name.hasPrefix("ppp")
    }
}
