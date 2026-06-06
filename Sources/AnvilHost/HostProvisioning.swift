import Foundation

public enum HostProvisioningError: Error, CustomStringConvertible {
    case launchAgentDirectoryCreationFailed(Error)
    case plistWriteFailed(Error)
    case launchctlLoadFailed(Int32, String)
    case launchctlUnloadFailed(Int32, String)
    case launchctlRemoveFailed(Int32, String)
    case agentNotFound

    public var description: String {
        switch self {
        case .launchAgentDirectoryCreationFailed(let error):
            return "Failed to create LaunchAgents directory: \(error.localizedDescription)"
        case .plistWriteFailed(let error):
            return "Failed to write plist: \(error.localizedDescription)"
        case .launchctlLoadFailed(let code, let msg):
            return "launchctl load failed (exit \(code)): \(msg)"
        case .launchctlUnloadFailed(let code, let msg):
            return "launchctl unload failed (exit \(code)): \(msg)"
        case .launchctlRemoveFailed(let code, let msg):
            return "launchctl remove failed (exit \(code)): \(msg)"
        case .agentNotFound:
            return "LaunchAgent plist not found"
        }
    }
}

public struct HostProvisioning: Sendable {
    public static let shared = HostProvisioning()

    private let label = "com.swiftanvil.anvil-runner"
    private var launchAgentsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
    }
    private var plistURL: URL {
        launchAgentsDir.appendingPathComponent("\(label).plist")
    }

    private init() {}

    public func install(agentPlistSource: URL) throws {
        let fm = FileManager.default
        try? fm.createDirectory(at: launchAgentsDir, withIntermediateDirectories: true)

        guard fm.fileExists(atPath: agentPlistSource.path) else {
            throw HostProvisioningError.agentNotFound
        }

        do {
            if fm.fileExists(atPath: plistURL.path) {
                try? fm.removeItem(at: plistURL)
            }
            try fm.copyItem(at: agentPlistSource, to: plistURL)
        } catch {
            throw HostProvisioningError.plistWriteFailed(error)
        }

        let (_, err, status) = shell("/bin/launchctl", ["load", "-w", plistURL.path])
        guard status == 0 else {
            throw HostProvisioningError.launchctlLoadFailed(status, err)
        }
    }

    public func remove() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistURL.path) else { return }

        let (_, err, status) = shell("/bin/launchctl", ["unload", "-w", plistURL.path])
        if status != 0 && !err.contains("Could not find specified service") {
            throw HostProvisioningError.launchctlUnloadFailed(status, err)
        }

        try? fm.removeItem(at: plistURL)

        let (_, err2, status2) = shell("/bin/launchctl", ["remove", label])
        if status2 != 0 && !err2.contains("Could not find specified service") {
            throw HostProvisioningError.launchctlRemoveFailed(status2, err2)
        }
    }

    public var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
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
