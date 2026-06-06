import Foundation

/// Errors that can occur when running commands with elevated privileges.
public enum SudoError: Error, CustomStringConvertible {
    case passwordRequired
    case invalidPassword
    case commandFailed(Int32, String)
    case unavailable(String)

    public var description: String {
        switch self {
        case .passwordRequired:
            return "sudo requires a password but none was provided and no TTY is available"
        case .invalidPassword:
            return "the provided sudo password was rejected"
        case .commandFailed(let code, let msg):
            return "sudo command failed with exit code \(code): \(msg)"
        case .unavailable(let msg):
            return "sudo unavailable: \(msg)"
        }
    }
}

/// Runs commands with elevated privileges, with support for non-TTY environments.
///
/// In headless or AI-agent sessions, `sudo` normally fails because it cannot prompt
/// for a password. This helper supports:
///
/// 1. `SUDO_PASSWORD` environment variable — passed to `sudo -S` via stdin.
/// 2. Pre-authorized sudo — if the user has recently run `sudo -v`, the credential
///    cache is used automatically.
/// 3. Graceful degradation — operations that require root can be skipped with a
///    warning instead of failing the entire provisioning flow.
public enum SudoRunner {
    /// Returns `true` if the current process can run `sudo` without a password
    /// (either via credential cache or `SUDO_PASSWORD` env var).
    public static var isAvailable: Bool {
        canUseSudoWithoutPassword() || sudoPassword != nil
    }

    /// Reads the sudo password from the `SUDO_PASSWORD` environment variable.
    public static var sudoPassword: String? {
        ProcessInfo.processInfo.environment["SUDO_PASSWORD"]
    }

    /// Runs a command with `sudo`, using the configured password if needed.
    ///
    /// - Parameters:
    ///   - executable: Absolute path to the executable.
    ///   - arguments: Arguments to pass to the executable.
    ///   - captureOutput: If `true`, stdout and stderr are captured and returned.
    /// - Returns: A tuple of `(stdout, stderr, exitCode)`.
    /// - Throws: `SudoError` if sudo cannot be executed.
    @discardableResult
    public static func run(
        _ executable: String,
        arguments: [String],
        captureOutput: Bool = true
    ) throws -> (stdout: String, stderr: String, status: Int32) {
        let usePassword = sudoPassword != nil && !canUseSudoWithoutPassword()

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")

        if usePassword {
            task.arguments = ["-S", "-k", executable] + arguments
        } else {
            task.arguments = [executable] + arguments
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()

        if captureOutput {
            task.standardOutput = outPipe
            task.standardError = errPipe
        }

        if usePassword {
            task.standardInput = inPipe
        }

        do {
            try task.run()
        } catch {
            throw SudoError.unavailable(error.localizedDescription)
        }

        if usePassword, let password = sudoPassword {
            let passwordData = (password + "\n").data(using: .utf8)!
            inPipe.fileHandleForWriting.write(passwordData)
            inPipe.fileHandleForWriting.closeFile()
        }

        task.waitUntilExit()

        let out = captureOutput
            ? String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            : ""
        let err = captureOutput
            ? String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            : ""

        if task.terminationStatus != 0 {
            let lower = err.lowercased()
            if lower.contains("incorrect password") || lower.contains("sorry, try again") {
                throw SudoError.invalidPassword
            }
            if lower.contains("a terminal is required") || lower.contains("no tty present") {
                throw SudoError.passwordRequired
            }
        }

        return (out, err, task.terminationStatus)
    }

    /// Runs a command as the original user (not root), even if the current
    /// process is running under `sudo`. Use this for Homebrew, which refuses
    /// to run as root.
    @discardableResult
    public static func runAsOriginalUser(
        _ executable: String,
        arguments: [String],
        captureOutput: Bool = true
    ) -> (stdout: String, stderr: String, status: Int32) {
        let task = Process()

        // When running under sudo, SUDO_USER is the original user.
        if let sudoUser = ProcessInfo.processInfo.environment["SUDO_USER"] {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
            task.arguments = ["-u", sudoUser, executable] + arguments
        } else {
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        if captureOutput {
            task.standardOutput = outPipe
            task.standardError = errPipe
        }

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ("", error.localizedDescription, -1)
        }

        let out = captureOutput
            ? String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            : ""
        let err = captureOutput
            ? String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            : ""

        return (out, err, task.terminationStatus)
    }

    // MARK: - Helpers

    private static func canUseSudoWithoutPassword() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        task.arguments = ["-n", "/bin/true"]
        let pipe = Pipe()
        task.standardError = pipe
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        return task.terminationStatus == 0
    }
}
