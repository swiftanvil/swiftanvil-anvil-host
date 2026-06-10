import Foundation

/// Manages installation, checking, and updating of required tools.
public actor ToolManager {
    public static let shared = ToolManager()

    private let registry = ToolRegistry.default
    private let fileManager = FileManager.default

    private init() { }

    // MARK: - Check

    /// Checks the status of a single tool.
    public func check(_ tool: Tool) async -> ToolStatus {
        let (installed, version) = await checkInstalled(tool)
        let latest = await fetchLatestVersion(tool)

        return ToolStatus(
            tool: tool,
            isInstalled: installed,
            currentVersion: version,
            latestVersion: latest,
            updateAvailable: latest != nil && version != nil && latest != version,
            lastChecked: Date()
        )
    }

    /// Checks all registered tools.
    public func checkAll() async -> [ToolStatus] {
        var results: [ToolStatus] = []
        for tool in registry.tools {
            await results.append(check(tool))
        }
        return results
    }

    /// Checks only critical tools.
    public func checkCritical() async -> [ToolStatus] {
        var results: [ToolStatus] = []
        for tool in registry.criticalTools {
            await results.append(check(tool))
        }
        return results
    }

    // MARK: - Install

    /// Installs a tool if not already present.
    @discardableResult
    public func install(_ tool: Tool) async throws -> ToolStatus {
        let status = await check(tool)
        guard !status.isInstalled else {
            return status
        }

        switch tool.installMethod {
        case .xcodeSelect:
            try await installXcodeTools()
        case let .homebrew(formula):
            try await installViaHomebrew(formula: formula)
        case let .homebrewCask(cask):
            try await installViaHomebrewCask(cask: cask)
        case let .script(url, _):
            try await installViaScript(url: url)
        case let .custom(install):
            try await install()
        }

        return await check(tool)
    }

    /// Installs all missing critical tools.
    public func installAllCritical() async throws -> [ToolStatus] {
        var results: [ToolStatus] = []
        for tool in registry.criticalTools {
            try await results.append(install(tool))
        }
        return results
    }

    /// Installs all missing tools.
    public func installAll() async throws -> [ToolStatus] {
        var results: [ToolStatus] = []
        for tool in registry.tools {
            try await results.append(install(tool))
        }
        return results
    }

    // MARK: - Update

    /// Updates a tool if an update is available.
    @discardableResult
    public func update(_ tool: Tool) async throws -> ToolStatus {
        let status = await check(tool)
        guard status.isInstalled, status.updateAvailable else {
            return status
        }

        switch tool.updateMethod {
        case .homebrew:
            try await updateViaHomebrew(tool: tool)
        case .softwareupdate:
            try await updateViaSoftwareUpdate(tool: tool)
        case .none:
            break
        case let .custom(update):
            try await update()
        }

        return await check(tool)
    }

    /// Updates all tools with available updates.
    public func updateAll() async throws -> [ToolStatus] {
        let statuses = await checkAll()
        var results: [ToolStatus] = []

        for status in statuses where status.updateAvailable {
            try await results.append(update(status.tool))
        }

        return results
    }

    /// Updates only critical tools.
    public func updateCritical() async throws -> [ToolStatus] {
        let statuses = await checkCritical()
        var results: [ToolStatus] = []

        for status in statuses where status.updateAvailable {
            try await results.append(update(status.tool))
        }

        return results
    }

    // MARK: - Private

    private func checkInstalled(_ tool: Tool) async -> (installed: Bool, version: String?) {
        let (out, _, status) = shell(tool.checkCommand.executable, tool.checkCommand.args)
        guard status == 0 else {
            return (false, nil)
        }
        let version = tool.parseVersion(out)
        return (true, version)
    }

    private func fetchLatestVersion(_ tool: Tool) async -> String? {
        switch tool.updateMethod {
        case .homebrew:
            await fetchHomebrewLatestVersion(tool: tool)
        case .softwareupdate:
            await fetchSoftwareUpdateLatestVersion(tool: tool)
        default:
            nil
        }
    }

    private func installXcodeTools() async throws {
        let (_, _, status) = shell("/usr/bin/xcode-select", ["-p"])
        guard status != 0 else { return }

        let (out, err, installStatus) = shell("/usr/bin/xcode-select", ["--install"])
        if installStatus != 0, !out.contains("already installed"), !err.contains("already installed") {
            throw ToolError.installFailed("xcode-tools", "xcode-select --install failed: \(err)")
        }

        // Wait for installation to complete
        var attempts = 0
        while attempts < 60 {
            let (_, _, checkStatus) = shell("/usr/bin/xcode-select", ["-p"])
            if checkStatus == 0 { return }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            attempts += 1
        }
        throw ToolError.installFailed("xcode-tools", "Timeout waiting for installation")
    }

    private func installViaHomebrew(formula: String) async throws {
        let (_, err, status) = shell("/opt/homebrew/bin/brew", ["install", formula])
        guard status == 0 else {
            throw ToolError.installFailed(formula, err)
        }
    }

    private func installViaHomebrewCask(cask: String) async throws {
        let (_, err, status) = shell("/opt/homebrew/bin/brew", ["install", "--cask", cask])
        guard status == 0 else {
            throw ToolError.installFailed(cask, err)
        }
    }

    private func installViaScript(url: String) async throws {
        guard !url.isEmpty else {
            // For Rosetta, use softwareupdate
            let (_, err, status) = shell("/usr/sbin/softwareupdate", ["--install-rosetta", "--agree-to-license"])
            guard status == 0 else {
                throw ToolError.installFailed("rosetta", err)
            }
            return
        }

        let tempScript = "/tmp/anvil-install-\(Int.random(in: 1000 ... 9999)).sh"
        let (_, downloadErr, downloadStatus) = shell("/usr/bin/curl", ["-fsSL", "-o", tempScript, url])
        guard downloadStatus == 0 else {
            throw ToolError.installFailed("script", "Download failed: \(downloadErr)")
        }

        let (_, installErr, installStatus) = shell("/bin/bash", [tempScript])
        try? fileManager.removeItem(atPath: tempScript)

        guard installStatus == 0 else {
            throw ToolError.installFailed("script", "Install failed: \(installErr)")
        }
    }

    private func updateViaHomebrew(tool: Tool) async throws {
        let formula = tool.name
        let (_, err, status) = shell("/opt/homebrew/bin/brew", ["upgrade", formula])
        guard status == 0 else {
            throw ToolError.updateFailed(formula, err)
        }
    }

    private func updateViaSoftwareUpdate(tool: Tool) async throws {
        // Software update handles all system tools together
        let (_, err, status) = shell("/usr/sbin/softwareupdate", ["-ia", "--agree-to-license"])
        guard status == 0 else {
            throw ToolError.updateFailed(tool.name, err)
        }
    }

    private func fetchHomebrewLatestVersion(tool: Tool) async -> String? {
        let formula: String
        switch tool.installMethod {
        case let .homebrew(f): formula = f
        case let .homebrewCask(c): formula = c
        default: return nil
        }

        let (out, _, status) = shell("/opt/homebrew/bin/brew", ["info", "--json", formula])
        guard status == 0 else { return nil }

        // Simple JSON parsing for version
        if
            let data = out.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let first = json.first,
            let versions = first["versions"] as? [String: Any],
            let stable = versions["stable"] as? String
        {
            return stable
        }
        return nil
    }

    private func fetchSoftwareUpdateLatestVersion(tool: Tool) async -> String? {
        // For Xcode tools, we can't easily get latest version without checking
        // Return current version to avoid false positives
        let (_, version) = await checkInstalled(tool)
        return version
    }
}

public enum ToolError: Error, CustomStringConvertible {
    case installFailed(String, String)
    case updateFailed(String, String)
    case notInstalled(String)

    public var description: String {
        switch self {
        case let .installFailed(tool, reason):
            "Failed to install \(tool): \(reason)"
        case let .updateFailed(tool, reason):
            "Failed to update \(tool): \(reason)"
        case let .notInstalled(tool):
            "\(tool) is not installed"
        }
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
