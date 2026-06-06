import Foundation

public enum TailscaleSetupError: Error, CustomStringConvertible {
    case notInstalled
    case notAuthenticated(String)
    case notRunning
    case versionCheckFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            return "Tailscale is not installed"
        case .notAuthenticated(let url):
            return "Tailscale is installed but not authenticated. Log in at: \(url)"
        case .notRunning:
            return "Tailscale is installed but not running"
        case .versionCheckFailed(let msg):
            return "Tailscale version check failed: \(msg)"
        }
    }
}

public struct TailscaleSetup: Sendable {
    public static let shared = TailscaleSetup()

    private let appPath = "/Applications/Tailscale.app"
    private let appCLIPath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    private init() {}

    /// Returns the first available Tailscale CLI path.
    private var resolvedCLIPath: String? {
        let candidates = [appCLIPath, "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    public var isInstalled: Bool {
        // Check both app bundle and Homebrew CLI installations
        FileManager.default.fileExists(atPath: appPath) ||
        FileManager.default.fileExists(atPath: "/opt/homebrew/bin/tailscale") ||
        FileManager.default.fileExists(atPath: "/usr/local/bin/tailscale")
    }

    public var isRunning: Bool {
        // Check for GUI app process or CLI daemon
        let (_, _, guiStatus) = shell("/usr/bin/pgrep", ["-x", "Tailscale"])
        if guiStatus == 0 { return true }
        guard let cli = resolvedCLIPath else { return false }
        let (_, _, status) = shell(cli, ["status"])
        return status == 0
    }

    public var isAuthenticated: Bool {
        guard let cli = resolvedCLIPath else { return false }
        let (_, _, status) = shell(cli, ["status"])
        return status == 0
    }

    /// If Tailscale is installed but not authenticated, returns the login URL
    /// printed by `tailscale up` so the caller can present it to the user.
    public var loginURL: String? {
        guard let cli = resolvedCLIPath else { return nil }
        let (out, _, _) = shell(cli, ["up"])
        // Extract URL from output like:
        // "Log in at: https://login.tailscale.com/a/xxxxxxxxxx"
        let pattern = "https://login.tailscale.com/a/[a-zA-Z0-9]+"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(out.startIndex..., in: out)
        if let match = regex.firstMatch(in: out, options: [], range: range) {
            return String(out[Range(match.range, in: out)!])
        }
        return nil
    }

    public var version: String? {
        // Try app bundle CLI first, then Homebrew CLI
        guard let cli = resolvedCLIPath else { return nil }
        let (out, _, status) = shell(cli, ["version"])
        guard status == 0 else { return nil }
        return out.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
    }

    /// Attempts to authenticate Tailscale using a pre-generated auth key.
    /// Set `TAILSCALE_AUTH_KEY` in the environment for unattended setup.
    @discardableResult
    public func authenticate() -> Bool {
        if isAuthenticated { return true }

        guard let cli = resolvedCLIPath else { return false }

        if let authKey = ProcessInfo.processInfo.environment["TAILSCALE_AUTH_KEY"] {
            let (_, err, status) = shell(cli, ["up", "--authkey", authKey, "--hostname", hostname])
            if status == 0 { return true }
            // Fall through to browser auth if the key failed.
            print("Tailscale auth key failed: \(err). Falling back to browser authentication.")
        }

        // Trigger browser-based login and capture the URL.
        let (_, _, status) = shell(cli, ["up"])
        return status == 0
    }

    public func verify(strict: Bool = false) throws {
        guard isInstalled else { throw TailscaleSetupError.notInstalled }

        if isAuthenticated {
            return
        }

        // Try to authenticate automatically if an auth key is available.
        if authenticate() {
            return
        }

        // If strict mode is off, we allow provisioning to continue with a warning.
        // The caller is responsible for surfacing the login URL.
        if let url = loginURL {
            throw TailscaleSetupError.notAuthenticated(url)
        }

        throw TailscaleSetupError.notRunning
    }

    // MARK: - Helpers

    private var hostname: String {
        ProcessInfo.processInfo.environment["TAILSCALE_HOSTNAME"]
            ?? Host.current().localizedName?
                .replacingOccurrences(of: " ", with: "-")
                .lowercased()
            ?? "anvil-host"
    }
}

private func shell(_ executable: String, _ args: [String]) -> (stdout: String, stderr: String, status: Int32) {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = args

    let outPipe = Pipe()
    let errPipe = Pipe()
    task.standardOutput = outPipe
    task.standardError = errPipe

    do {
        try task.run()
        task.waitUntilExit()
    } catch {
        return ("", error.localizedDescription, -1)
    }

    let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (out, err, task.terminationStatus)
}
