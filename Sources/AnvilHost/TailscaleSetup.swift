import Foundation

public enum TailscaleSetupError: Error, CustomStringConvertible {
    case notInstalled
    case notRunning
    case versionCheckFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            return "Tailscale is not installed (expected at /Applications/Tailscale.app)"
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
    private let cliPath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    private init() {}

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
        let (_, _, cliStatus) = shell("/opt/homebrew/bin/tailscale", ["status"])
        return cliStatus == 0
    }

    public var version: String? {
        // Try app bundle CLI first, then Homebrew CLI
        let paths = [cliPath, "/opt/homebrew/bin/tailscale", "/usr/local/bin/tailscale"]
        for path in paths {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let (out, _, status) = shell(path, ["version"])
            guard status == 0 else { continue }
            return out.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public func verify() throws {
        guard isInstalled else { throw TailscaleSetupError.notInstalled }
        guard isRunning else { throw TailscaleSetupError.notRunning }
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
