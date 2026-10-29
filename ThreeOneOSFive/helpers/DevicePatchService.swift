import Foundation

enum DevicePatchService {
    static func apply(project: PatchProject) throws -> PatchTransactionReceipt {
        let bundleIDs = orderedBundleIdentifiers(in: project)
        if requiresPairingTunnel {
            let context = try pairingRemoteContext(bundleIDs: bundleIDs)
            return try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = context.roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                remoteWriter: pairingRemoteWriter(context: context),
                remoteReader: pairingRemoteReader(context: context)
            )
        }
        return try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.apply(
                project: project,
                backupRoot: try PatchProjectLibrary.backupRootURL(),
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func restore(receipt: PatchTransactionReceipt) throws {
        let bundleIDs = try PatchTransaction.requiredBundleIdentifiers(for: receipt)
        if requiresPairingTunnel {
            let context = try pairingRemoteContext(bundleIDs: bundleIDs)
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = context.roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                },
                remoteWriter: pairingRemoteWriter(context: context),
                remoteReader: pairingRemoteReader(context: context)
            )
            return
        }
        try withResolvedContainers(bundleIDs: bundleIDs) { roots in
            try PatchTransaction.restore(
                receipt: receipt,
                containerResolver: { bundleID in
                    guard let root = roots[bundleID] else {
                        throw PatchPackageError.targetAppUnavailable(bundleID)
                    }
                    return root
                }
            )
        }
    }

    static func latestReceipt(projectID: UUID) -> PatchTransactionReceipt? {
        guard let backupRoot = try? PatchProjectLibrary.backupRootURL() else { return nil }
        return PatchTransaction.latestReceipt(projectID: projectID, backupRoot: backupRoot)
    }

    private static func orderedBundleIdentifiers(in project: PatchProject) -> [String] {
        project.allBundleIdentifiers
    }

    static var requiresPairingTunnel: Bool {
        let version = AppInfo.versionTuple
        return ExploitSupportPolicy.requiresPairingTunnel(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            build: AppInfo.osBuild
        )
    }

    private struct PairingRemoteContext {
        let pairingFileURL: URL
        let roots: [String: URL]
        let containerPaths: [String: String]
    }

    private static func pairingRemoteContext(bundleIDs: [String]) throws -> PairingRemoteContext {
        guard LocalDevTunnelProbe.isConnected else {
            throw PatchPackageError.pairingTunnelRequired
        }
        let pairingFileURL = PairingController.pairingFileURL
        guard FileManager.default.fileExists(atPath: pairingFileURL.path) else {
            throw AppInfo.versionTuple.major >= 27
                ? PatchPackageError.pairingFileMissing
                : PatchPackageError.pairingFileImportRequired
        }

        var roots: [String: URL] = [:]
        var containerPaths: [String: String] = [:]
        for bundleID in bundleIDs {
            let path: String
            do {
                path = try FileReplacementService.remoteContainerPath(
                    pairingFileURL: pairingFileURL,
                    bundleID: bundleID
                )
            } catch {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            guard ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            containerPaths[bundleID] = path
            roots[bundleID] = PatchPathValidator.canonicalFileURL(
                URL(fileURLWithPath: path, isDirectory: true)
            )
            log("patch: Airlift resolved app container \(bundleID)")
        }
        return PairingRemoteContext(
            pairingFileURL: pairingFileURL,
            roots: roots,
            containerPaths: containerPaths
        )
    }

    private static func pairingRemoteWriter(
        context: PairingRemoteContext
    ) -> PatchTransaction.RemoteWriter {
        return { bundleID, relativePath, data in
            guard let remoteContainer = context.containerPaths[bundleID] else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            try FileReplacementService.writeRemoteFile(
                bundleID: bundleID,
                relativePath: relativePath,
                data: data,
                pairingFileURL: context.pairingFileURL,
                remoteContainerPath: remoteContainer
            )
        }
    }

    private static func pairingRemoteReader(
        context: PairingRemoteContext
    ) -> PatchTransaction.RemoteReader {
        return { bundleID, relativePath in
            guard let remoteContainer = context.containerPaths[bundleID] else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            return try FileReplacementService.readRemoteFile(
                bundleID: bundleID,
                relativePath: relativePath,
                pairingFileURL: context.pairingFileURL,
                remoteContainerPath: remoteContainer
            )
        }
    }

    private static func withResolvedContainers<T>(
        bundleIDs: [String],
        operation: ([String: URL]) throws -> T
    ) throws -> T {
        var roots: [String: URL] = [:]

        for bundleID in bundleIDs {
            guard let path = ContainerStore.resolveAppContainerPath(bundleID: bundleID),
                  ContainerStore.isApplicationContainerPath(path) else {
                throw PatchPackageError.targetAppUnavailable(bundleID)
            }
            roots[bundleID] = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
        }
        return try operation(roots)
    }
}
