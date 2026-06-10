import Foundation

public enum TailscaleSetupError: Error, CustomStringConvertible {
    case notInstalled
    case notRunning
    case versionCheckFailed(String)

    public var description: String {
        switch self {
        case .notInstalled:
            "Tailscale is not installed (expected at /Applications/Tailscale.app)"
        case .notRunning:
            "Tailscale is installed but not running"
        case let .versionCheckFailed(msg):
            "Tailscale version check failed: \(msg)"
        }
    }
}

public struct TailscaleSetup: Sendable {
    public static let shared = TailscaleSetup()

    private let appPath = "/Applications/Tailscale.app"
    private let cliPath = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    private init() { }

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: appPath)
    }

    public var isRunning: Bool {
        let (_, _, status) = shell("/usr/bin/pgrep", ["-x", "Tailscale"])
        return status == 0
    }

    public var version: String? {
        let (out, _, status) = shell(cliPath, ["version"])
        guard status == 0 else { return nil }
        return out.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces)
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
