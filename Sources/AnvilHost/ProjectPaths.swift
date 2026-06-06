import Foundation

/// Resolves paths relative to the anvil-host project root.
///
/// This avoids hardcoding absolute paths (e.g., `/Users/vishalsingh/...`)
/// so the tool works on any machine where the repository is cloned.
public enum ProjectPaths {
    /// Returns the project root directory (the folder containing
    /// `Package.swift` and the `launchd/` directory).
    ///
    /// Resolution order:
    /// 1. `ANVIL_HOST_PROJECT_ROOT` environment variable.
    /// 2. Search upward from `#file` for a directory containing both
    ///    `Package.swift` and `launchd/com.swiftanvil.anvil-host.plist`.
    /// 3. Search upward from the current working directory.
    public static var projectRoot: String {
        if let envRoot = ProcessInfo.processInfo.environment["ANVIL_HOST_PROJECT_ROOT"],
           isProjectRoot(envRoot) {
            return envRoot
        }

        // Search upward from this source file.
        let sourceFile = URL(fileURLWithPath: #file)
        if let root = searchProjectRoot(from: sourceFile) {
            return root
        }

        // Fallback: search upward from the current working directory.
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let root = searchProjectRoot(from: cwd) {
            return root
        }

        // Last resort: assume the source file is inside the project.
        let sourceBased = sourceFile
            .deletingLastPathComponent() // Sources/AnvilHost
            .deletingLastPathComponent() // Sources
            .deletingLastPathComponent() // project root (in a simple checkout)
        return sourceBased.path
    }

    /// Path to the built binary.
    ///
    /// Checks both release and debug build directories so that `swift run`
    /// (debug) and `swift build -c release` (release) both work without
    /// requiring a rebuild.
    public static var releaseBinary: String {
        let candidates = [
            URL(fileURLWithPath: projectRoot).appendingPathComponent(".build/release/anvil-host").path,
            URL(fileURLWithPath: projectRoot).appendingPathComponent(".build/debug/anvil-host").path,
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
            ?? candidates[0]
    }

    /// Path to the LaunchAgent plist in the repository.
    public static var launchAgentPlist: URL {
        URL(fileURLWithPath: projectRoot)
            .appendingPathComponent("launchd/com.swiftanvil.anvil-host.plist")
    }

    // MARK: - Helpers

    private static func isProjectRoot(_ path: String) -> Bool {
        let fm = FileManager.default
        let packageSwift = URL(fileURLWithPath: path).appendingPathComponent("Package.swift").path
        let plist = URL(fileURLWithPath: path).appendingPathComponent("launchd/com.swiftanvil.anvil-host.plist").path
        return fm.fileExists(atPath: packageSwift) && fm.fileExists(atPath: plist)
    }

    private static func searchProjectRoot(from start: URL) -> String? {
        var current = start
        for _ in 0..<10 {
            if isProjectRoot(current.path) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }
}
