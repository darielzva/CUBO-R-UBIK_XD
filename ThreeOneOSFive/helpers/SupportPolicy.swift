import Foundation

enum ExploitSupportPolicy {
    struct VerifiedVersion: Identifiable {
        let major: Int
        let minor: Int
        let patch: Int
        let builds: [String]

        init(_ major: Int, _ minor: Int, _ patch: Int = 0, builds: [String]) {
            self.major = major
            self.minor = minor
            self.patch = patch
            self.builds = builds
        }

        var id: String { "\(major).\(minor).\(patch)" }
        var version: String {
            patch == 0 ? "\(major).\(minor)" : "\(major).\(minor).\(patch)"
        }
    }

    static let supportedMajorVersions = [17, 18, 26, 27]

    static func buildCount(forMajor major: Int) -> Int {
        verifiedVersions
            .filter { $0.major == major }
            .reduce(0) { $0 + $1.builds.count }
    }

    static let verifiedIOS27BetaBuilds: [(beta: Int, build: String)] = [
        (1, "24A5355q"),
        (2, "24A5370h"),
        (3, "24A5380h"),
        (4, "24A5390f"),
        (5, "24A5408d"),
        (6, "24A5418b"),
        (7, "24A5424a"),
        (8, "24A5430a")
    ]

    static let verifiedVersions: [VerifiedVersion] = [
        .init(17, 0, builds: ["21A329"]),
        .init(17, 0, 1, builds: ["21A340"]),
        .init(17, 0, 2, builds: ["21A350", "21A351"]),
        .init(17, 0, 3, builds: ["21A360"]),
        .init(17, 1, builds: ["21B74", "21B80"]),
        .init(17, 1, 1, builds: ["21B91"]),
        .init(17, 1, 2, builds: ["21B101"]),
        .init(17, 2, builds: ["21C62"]),
        .init(17, 2, 1, builds: ["21C66"]),
        .init(17, 3, builds: ["21D50"]),
        .init(17, 3, 1, builds: ["21D61"]),
        .init(17, 4, builds: ["21E219"]),
        .init(17, 4, 1, builds: ["21E236", "21E237"]),
        .init(17, 5, builds: ["21F79"]),
        .init(17, 5, 1, builds: ["21F90"]),
        .init(17, 6, builds: ["21G80"]),
        .init(17, 6, 1, builds: ["21G93", "21G101"]),
        .init(17, 7, builds: ["21H16"]),
        .init(17, 7, 1, builds: ["21H216"]),
        .init(17, 7, 2, builds: ["21H221"]),

        .init(18, 0, builds: ["22A3354"]),
        .init(18, 0, 1, builds: ["22A3370"]),
        .init(18, 1, builds: ["22B83"]),
        .init(18, 1, 1, builds: ["22B91"]),
        .init(18, 2, builds: ["22C152"]),
        .init(18, 2, 1, builds: ["22C161"]),
        .init(18, 3, builds: ["22D63"]),
        .init(18, 3, 1, builds: ["22D72"]),
        .init(18, 3, 2, builds: ["22D82"]),
        .init(18, 4, builds: ["22E240"]),
        .init(18, 4, 1, builds: ["22E252"]),
        .init(18, 5, builds: ["22F76"]),
        .init(18, 6, builds: ["22G86"]),
        .init(18, 6, 1, builds: ["22G90"]),
        .init(18, 6, 2, builds: ["22G100"]),
        .init(18, 7, builds: ["22H20"]),
        .init(18, 7, 1, builds: ["22H31"]),
        .init(18, 7, 2, builds: ["22H124"]),
        .init(18, 7, 3, builds: ["22H217"]),
        .init(18, 7, 4, builds: ["22H218"]),
        .init(18, 7, 5, builds: ["22H311"]),
        .init(18, 7, 6, builds: ["22H320"]),
        .init(18, 7, 7, builds: ["22H333", "22H340"]),
        .init(18, 7, 8, builds: ["22H352"]),
        .init(18, 7, 9, builds: ["22H355"]),
        .init(18, 7, 10, builds: ["22H374"]),

        .init(26, 0, builds: ["23A341", "23A345"]),
        .init(26, 0, 1, builds: ["23A355"]),
        .init(26, 1, builds: ["23B85"]),
        .init(26, 2, builds: ["23C55"]),
        .init(26, 2, 1, builds: ["23C71"]),
        .init(26, 3, builds: ["23D127"]),
        .init(26, 3, 1, builds: ["23D8133"]),
        .init(26, 4, builds: ["23E246"]),
        .init(26, 4, 1, builds: ["23E254"]),
        .init(26, 4, 2, builds: ["23E261"]),
        .init(26, 5, builds: ["23F77"]),
        .init(26, 5, 1, builds: ["23F81"]),
        .init(26, 5, 2, builds: ["23F84"]),
        .init(26, 6, builds: ["23G71"]),
        .init(26, 6, 1, builds: ["23G83"]),
        .init(26, 6, 2, builds: ["23G90"]),
        .init(26, 7, builds: ["23H24"]),

        .init(27, 0, builds: verifiedIOS27BetaBuilds.map { $0.build } + ["24A435", "24A437"]),
        .init(27, 2, builds: ["24B5084k", "24B5089g"])
    ]

    static func iOS27BetaNumber(for build: String) -> Int? {
        verifiedIOS27BetaBuilds.first { $0.build == build }?.beta
    }

    static func supportsKernelExploit(major: Int, minor: Int, patch: Int) -> Bool {
        guard minor >= 0, patch >= 0 else { return false }

        return major == 17 || major == 18
    }

    static func isSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        verifiedVersions.contains {
            $0.major == major && $0.minor == minor && $0.patch == patch && $0.builds.contains(build)
        }
    }

    static func requiresPairingTunnel(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        if major >= 27 {
            return true
        }

        return major == 18
            && minor == 7
            && (2...10).contains(patch)
            && isSupported(major: major, minor: minor, patch: patch, build: build)
    }

    static func isKernelExploitSupported(major: Int, minor: Int, patch: Int, build: String) -> Bool {
        guard isSupported(major: major, minor: minor, patch: patch, build: build) else { return false }

        if supportsKernelExploit(major: major, minor: minor, patch: patch) {
            return true
        }

        if major == 26 {
            return true
        }

        return major == 27 && minor == 0 && patch == 0 && iOS27BetaNumber(for: build) != nil
    }
}