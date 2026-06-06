import Foundation

/// High-level orchestrator that executes host actions safely.
/// Designed for AI agent consumption — no CLI knowledge required.
public actor HostOrchestrator {
    public static let shared = HostOrchestrator()
    
    private let detector = HostStateDetector.shared
    private let discovery = HostActionDiscovery.shared
    
    private init() {}
    
    // MARK: - State & Discovery
    
    /// Returns the current state with all available actions.
    public func currentState() async -> HostStateSnapshot {
        let state = await detector.detect()
        let actions = discovery.availableActions(from: state)
        return HostStateSnapshot(state: state, availableActions: actions)
    }
    
    /// Returns a human-readable summary of what's possible right now.
    public func whatCanIDo() async -> String {
        let snapshot = await currentState()
        var lines: [String] = []
        
        lines.append("📍 Current State: \(snapshot.state.description)")
        lines.append("")
        lines.append("Available Actions:")
        
        for action in snapshot.availableActions {
            let confirm = action.requiresConfirmation ? " ⚠️" : ""
            let sudo = action.requiresSudo ? " (requires sudo)" : ""
            lines.append("  • \(action.name)\(confirm)\(sudo)")
            lines.append("    \(action.description)")
        }
        
        // Cross-repo detection: suggest runner setup if host is ready
        if snapshot.state == .provisioned || snapshot.state == .productionReady {
            let runnerNearby = await isRunnerRepoNearby()
            if runnerNearby {
                lines.append("")
                lines.append("🔗 Next Step: Set up runners")
                lines.append("   swiftanvil-anvil-runner detected nearby.")
                lines.append("   Run 'cd ../swiftanvil-anvil-runner' and start its agent.")
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Checks if swiftanvil-anvil-runner is cloned in a sibling directory.
    private func isRunnerRepoNearby() async -> Bool {
        let possiblePaths = [
            "../swiftanvil-anvil-runner",
            "../../swiftanvil-anvil-runner",
            "~/swiftanvil-anvil-runner",
            "~/Documents/swiftanvil-anvil-runner"
        ]
        let fm = FileManager.default
        for path in possiblePaths {
            let expanded = (path as NSString).expandingTildeInPath
            if fm.fileExists(atPath: expanded) {
                return true
            }
        }
        return false
    }
    
    // MARK: - Safe Execution
    
    /// Executes an action by ID, returning a structured result.
    /// This is the primary agent interface — no shell commands needed.
    public func execute(actionID: String, parameters: [String: String] = [:]) async -> HostActionResult {
        guard let action = discovery.action(id: actionID) else {
            return HostActionResult(
                actionID: actionID,
                success: false,
                message: "Unknown action: \(actionID)"
            )
        }
        
        let current = await detector.detect()
        guard action.availableFromStates.contains(current) else {
            return HostActionResult(
                actionID: actionID,
                success: false,
                message: "Action '\(action.name)' is not available from state '\(current.description)'. " +
                         "Available from: \(action.availableFromStates.map(\.description).joined(separator: ", "))"
            )
        }
        
        do {
            return try await executeAction(action, parameters: parameters)
        } catch {
            return HostActionResult(
                actionID: actionID,
                success: false,
                message: "Execution failed: \(error.localizedDescription)"
            )
        }
    }
    
    /// Executes an action with automatic state re-detection afterward.
    private func executeAction(_ action: HostAction, parameters: [String: String]) async throws -> HostActionResult {
        switch action.id {
        case "build":
            return try await executeBuild()
        case "doctor":
            return try await executeDoctor()
        case "tools-check":
            return try await executeToolsCheck()
        case "provision":
            return try await executeProvision()
        case "tools-install":
            return try await executeToolsInstall()
        case "tools-update":
            return try await executeToolsUpdate()
        case "install-system-wide":
            return try await executeInstallSystemWide()
        case "status":
            return try await executeStatus()
        case "uninstall":
            return try await executeUninstall()
        default:
            return HostActionResult(
                actionID: action.id,
                success: false,
                message: "Action '\(action.id)' is defined but not yet implemented"
            )
        }
    }
    
    // MARK: - Action Implementations
    
    private func executeBuild() async throws -> HostActionResult {
        let (out, err, status) = shell("/usr/bin/swift", ["build", "-c", "release"])
        let success = status == 0
        return HostActionResult(
            actionID: "build",
            success: success,
            message: success ? "Build completed successfully" : "Build failed: \(err)",
            details: ["stdout": out, "stderr": err],
            newState: success ? .built : nil
        )
    }
    
    private func executeDoctor() async throws -> HostActionResult {
        let checks = await HostDoctor.shared.runAllChecks()
        let toolStatuses = await ToolManager.shared.checkCritical()
        
        let allPass = checks.allSatisfy(\.passed) && toolStatuses.allSatisfy(\.isInstalled)
        var details: [String: String] = [:]
        for check in checks {
            details[check.name] = check.passed ? "✓ \(check.message)" : "✗ \(check.message)"
        }
        for status in toolStatuses {
            details["Tool: \(status.tool.name)"] = status.isInstalled
                ? "✓ \(status.currentVersion ?? "unknown")"
                : "✗ Not installed"
        }
        
        return HostActionResult(
            actionID: "doctor",
            success: allPass,
            message: allPass ? "All health checks passed" : "Some health checks failed",
            details: details
        )
    }
    
    private func executeToolsCheck() async throws -> HostActionResult {
        let statuses = await ToolManager.shared.checkAll()
        var details: [String: String] = [:]
        for status in statuses {
            let update = status.updateAvailable ? " → \(status.latestVersion ?? "?")" : ""
            details[status.tool.name] = "\(status.isInstalled ? "✓" : "✗") \(status.currentVersion ?? "not installed")\(update)"
        }
        
        return HostActionResult(
            actionID: "tools-check",
            success: true,
            message: "Checked \(statuses.count) tools",
            details: details
        )
    }
    
    private func executeProvision() async throws -> HostActionResult {
        var errors: [String] = []
        var details: [String: String] = [:]
        
        // Install critical tools
        do {
            let toolResults = try await ToolManager.shared.installAllCritical()
            details["tools"] = "\(toolResults.filter(\.isInstalled).count)/\(toolResults.count) ready"
        } catch {
            errors.append("Tools: \(error)")
        }
        
        // Verify Tailscale
        do {
            try TailscaleSetup.shared.verify()
            details["tailscale"] = "ok"
        } catch {
            errors.append("Tailscale: \(error)")
        }
        
        // Apply power policy
        do {
            try PowerPolicy.shared.apply()
            details["power_policy"] = "applied"
        } catch {
            errors.append("Power policy: \(error)")
        }
        
        // Install LaunchAgent
        let plist = URL(fileURLWithPath: "/Users/vishalsingh/Documents/v-i-s-h-a-l/swiftanvil/swiftanvil-anvil-host/launchd/com.swiftanvil.anvil-host.plist")
        do {
            try HostProvisioning.shared.install(agentPlistSource: plist)
            details["launchagent"] = "installed"
        } catch {
            errors.append("LaunchAgent: \(error)")
        }
        
        // Start daemons
        await CleanupDaemon.shared.start()
        details["cleanup_daemon"] = "started"
        
        await ToolUpdateDaemon.shared.start()
        details["update_daemon"] = "started"
        
        let success = errors.isEmpty
        return HostActionResult(
            actionID: "provision",
            success: success,
            message: success ? "Host provisioned successfully" : "Provisioned with errors: \(errors.joined(separator: ", "))",
            details: details,
            newState: success ? .provisioned : nil
        )
    }
    
    private func executeToolsInstall() async throws -> HostActionResult {
        let results = try await ToolManager.shared.installAllCritical()
        let allInstalled = results.allSatisfy(\.isInstalled)
        var details: [String: String] = [:]
        for result in results {
            details[result.tool.name] = result.isInstalled ? "✓ \(result.currentVersion ?? "ready")" : "✗ failed"
        }
        
        return HostActionResult(
            actionID: "tools-install",
            success: allInstalled,
            message: allInstalled ? "All critical tools installed" : "Some tools failed to install",
            details: details
        )
    }
    
    private func executeToolsUpdate() async throws -> HostActionResult {
        let results = try await ToolManager.shared.updateAll()
        var details: [String: String] = [:]
        for result in results {
            details[result.tool.name] = "\(result.isInstalled ? "✓" : "✗") \(result.currentVersion ?? "unknown")"
        }
        
        return HostActionResult(
            actionID: "tools-update",
            success: true,
            message: "Updated \(results.count) tools",
            details: details
        )
    }
    
    private func executeInstallSystemWide() async throws -> HostActionResult {
        let source = "/Users/vishalsingh/Documents/v-i-s-h-a-l/swiftanvil/swiftanvil-anvil-host/.build/release/anvil-host"
        let destination = "/usr/local/bin/anvil-host"
        
        let (_, mkdirErr, mkdirStatus) = shell("/bin/mkdir", ["-p", "/usr/local/bin"])
        guard mkdirStatus == 0 else {
            return HostActionResult(
                actionID: "install-system-wide",
                success: false,
                message: "Failed to create /usr/local/bin: \(mkdirErr)"
            )
        }
        
        let (_, cpErr, cpStatus) = shell("/bin/cp", [source, destination])
        guard cpStatus == 0 else {
            return HostActionResult(
                actionID: "install-system-wide",
                success: false,
                message: "Failed to copy binary: \(cpErr)"
            )
        }
        
        let (_, chmodErr, chmodStatus) = shell("/bin/chmod", ["+x", destination])
        guard chmodStatus == 0 else {
            return HostActionResult(
                actionID: "install-system-wide",
                success: false,
                message: "Failed to make binary executable: \(chmodErr)"
            )
        }
        
        return HostActionResult(
            actionID: "install-system-wide",
            success: true,
            message: "anvil-host installed to \(destination)",
            newState: .productionReady
        )
    }
    
    private func executeStatus() async throws -> HostActionResult {
        let power = PowerPolicy.shared.currentSettings
        let toolStatuses = await ToolManager.shared.checkAll()
        
        var details: [String: String] = [
            "launchagent": HostProvisioning.shared.isInstalled ? "installed" : "not installed",
            "tailscale": TailscaleSetup.shared.isRunning ? "running" : "not running"
        ]
        
        for status in toolStatuses {
            let update = status.updateAvailable ? " (update available)" : ""
            details["tool_\(status.tool.name)"] = "\(status.isInstalled ? "✓" : "✗") \(status.currentVersion ?? "not installed")\(update)"
        }
        
        if let sleep = power["sleep"] {
            details["sleep"] = sleep
        }
        
        let url = URL(fileURLWithPath: "/")
        if let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
           let total = values.volumeTotalCapacity,
           let free = values.volumeAvailableCapacity {
            let usedPercent = (Double(total - free) / Double(total)) * 100
            details["disk"] = String(format: "%.1f%% used", usedPercent)
        }
        
        return HostActionResult(
            actionID: "status",
            success: true,
            message: "Host status retrieved",
            details: details
        )
    }
    
    private func executeUninstall() async throws -> HostActionResult {
        var details: [String: String] = [:]
        
        do {
            try HostProvisioning.shared.remove()
            details["launchagent"] = "removed"
        } catch {
            details["launchagent"] = "error: \(error)"
        }
        
        do {
            try PowerPolicy.shared.reset()
            details["power_policy"] = "reset"
        } catch {
            details["power_policy"] = "error: \(error)"
        }
        
        await CleanupDaemon.shared.stop()
        details["cleanup_daemon"] = "stopped"
        
        await ToolUpdateDaemon.shared.stop()
        details["update_daemon"] = "stopped"
        
        return HostActionResult(
            actionID: "uninstall",
            success: true,
            message: "Host configuration removed",
            details: details,
            newState: .built
        )
    }
}

// MARK: - State Snapshot

public struct HostStateSnapshot: Sendable {
    public let state: HostState
    public let availableActions: [HostAction]
    
    public func toJSON() -> [String: Any] {
        [
            "state": state.toJSON(),
            "available_actions": availableActions.map { $0.toJSON() }
        ]
    }
}

// MARK: - Shell Helper

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
