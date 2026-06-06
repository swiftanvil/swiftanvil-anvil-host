import Foundation

public enum PowerPolicyError: Error, CustomStringConvertible {
    case pmsetFailed(Int32, String)
    case sudoUnavailable(String)
    case caffeinateFailed(Int32, String)

    public var description: String {
        switch self {
        case .pmsetFailed(let code, let msg):
            return "pmset failed (exit \(code)): \(msg)"
        case .sudoUnavailable(let msg):
            return "sudo unavailable: \(msg)"
        case .caffeinateFailed(let code, let msg):
            return "caffeinate failed (exit \(code)): \(msg)"
        }
    }
}

public struct PowerPolicy: Sendable {
    public static let shared = PowerPolicy()

    private init() {}

    /// Prevent system sleep and enable auto-restart on power loss.
    public func apply() throws {
        let settings: [(String, String)] = [
            ("sleep", "0"),
            ("displaysleep", "10"),
            ("disksleep", "10"),
            ("womp", "1"),
            ("autorestart", "1"),
        ]

        for (key, value) in settings {
            let (_, err, status) = try runPMSet(key: key, value: value)
            guard status == 0 else {
                throw PowerPolicyError.pmsetFailed(status, err)
            }
        }
    }

    /// Restore conservative defaults.
    public func reset() throws {
        let settings: [(String, String)] = [
            ("sleep", "30"),
            ("displaysleep", "10"),
            ("disksleep", "10"),
            ("womp", "1"),
            ("autorestart", "0"),
        ]

        for (key, value) in settings {
            let (_, err, status) = try runPMSet(key: key, value: value)
            guard status == 0 else {
                throw PowerPolicyError.pmsetFailed(status, err)
            }
        }
    }

    public var currentSettings: [String: String] {
        let (out, _, status) = shell("/usr/bin/pmset", ["-g"])
        guard status == 0 else { return [:] }

        var result: [String: String] = [:]
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if parts.count == 2 {
                result[String(parts[0])] = String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    // MARK: - Helpers

    private func runPMSet(key: String, value: String) throws -> (stdout: String, stderr: String, status: Int32) {
        // First try without sudo (useful when already running as root or when
        // pmset does not require elevation on this macOS version).
        let direct = shell("/usr/bin/pmset", [key, value])
        if direct.status == 0 {
            return direct
        }

        // Fall back to sudo, which supports SUDO_PASSWORD in headless environments.
        guard SudoRunner.isAvailable else {
            throw PowerPolicyError.sudoUnavailable(
                "pmset requires root privileges. Run interactively with sudo or set SUDO_PASSWORD."
            )
        }

        return try SudoRunner.run("/usr/bin/pmset", arguments: [key, value])
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
