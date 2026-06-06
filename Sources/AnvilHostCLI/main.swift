import Foundation
import AnvilHost

@main
struct AnvilHostCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        let jsonMode = args.contains("--json")
        let cleanArgs = args.filter { $0 != "--json" }

        guard let command = cleanArgs.first else {
            printUsage()
            exit(1)
        }

        switch command {
        case "provision":
            await runProvision(json: jsonMode)
        case "doctor":
            await runDoctor(json: jsonMode)
        case "status":
            await runStatus(json: jsonMode)
        case "uninstall":
            await runUninstall(json: jsonMode)
        case "tools":
            await runTools(args: Array(cleanArgs.dropFirst()), json: jsonMode)
        case "help", "--help", "-h":
            printUsage()
        default:
            print("Unknown command: \(command)")
            printUsage()
            exit(1)
        }
    }

    private static func printUsage() {
        print("""
        anvil-host <command> [--json]

        Commands:
          provision    Full setup (LaunchAgent, Tailscale, power policy, tools)
          doctor       Run readiness checks
          status       Show host health
          tools        Manage required tools (see below)
          uninstall    Remove everything
          help         Show this message

        Tool Management:
          tools check              Check all tool statuses
          tools install            Install missing critical tools
          tools install-all        Install all missing tools
          tools update             Update tools with available updates
          tools update-critical    Update only critical tools

        Options:
          --json       Output machine-readable JSON for agent consumption
        """)
    }

    private static func runProvision(json: Bool) async {
        var results: [String: Any] = [:]
        var errors: [String] = []

        // Step 1: Install/check critical tools
        print("Checking and installing critical tools...")
        do {
            let toolResults = try await ToolManager.shared.installAllCritical()
            results["tools"] = toolResults.map { [
                "name": $0.tool.name,
                "installed": $0.isInstalled,
                "version": $0.currentVersion ?? "unknown"
            ] as [String: Any] }
            print("  Tools: \(toolResults.filter(\.isInstalled).count)/\(toolResults.count) ready")
        } catch {
            errors.append("Tools: \(error)")
        }

        // Step 2: Verify Tailscale
        do {
            try TailscaleSetup.shared.verify()
            results["tailscale"] = "ok"
        } catch {
            results["tailscale"] = "failed"
            errors.append("Tailscale: \(error)")
        }

        // Step 3: Apply power policy
        do {
            try PowerPolicy.shared.apply()
            results["power_policy"] = "applied"
        } catch {
            results["power_policy"] = "failed"
            errors.append("Power policy: \(error)")
        }

        // Step 4: Install LaunchAgent
        let plist = URL(fileURLWithPath: "/Users/vishalsingh/Documents/v-i-s-h-a-l/swiftanvil/swiftanvil-anvil-host/launchd/com.swiftanvil.anvil-host.plist")

        do {
            try HostProvisioning.shared.install(agentPlistSource: plist)
            results["launchagent"] = "installed"
        } catch {
            results["launchagent"] = "failed"
            errors.append("LaunchAgent: \(error)")
        }

        // Step 5: Start daemons
        await CleanupDaemon.shared.start()
        results["cleanup_daemon"] = "started"
        
        await ToolUpdateDaemon.shared.start()
        results["update_daemon"] = "started"

        results["errors"] = errors
        results["success"] = errors.isEmpty

        if json {
            printJSON(results)
        } else {
            if errors.isEmpty {
                print("✅ Host provisioned successfully.")
            } else {
                print("⚠️  Host provisioned with errors:")
                for error in errors { print("  - \(error)") }
            }
        }

        exit(errors.isEmpty ? 0 : 1)
    }

    private static func runDoctor(json: Bool) async {
        let checks = await HostDoctor.shared.runAllChecks()
        
        // Also check tools
        let toolStatuses = await ToolManager.shared.checkCritical()
        let allToolChecks = toolStatuses.map { status -> HostCheck in
            HostCheck(
                name: "Tool: \(status.tool.name)",
                passed: status.isInstalled,
                message: status.isInstalled 
                    ? "\(status.currentVersion ?? "unknown")"
                    : "Not installed"
            )
        }
        
        let allChecks = checks + allToolChecks

        if json {
            let checkDicts = allChecks.map { [
                "name": $0.name,
                "passed": $0.passed,
                "message": $0.message
            ] as [String: Any] }
            printJSON([
                "checks": checkDicts,
                "all_passed": allChecks.allSatisfy { $0.passed }
            ])
        } else {
            for check in allChecks {
                let symbol = check.passed ? "✓" : "✗"
                print("  \(symbol) \(check.name): \(check.message)")
            }
        }

        let failed = !allChecks.allSatisfy { $0.passed }
        exit(failed ? 1 : 0)
    }

    private static func runStatus(json: Bool) async {
        let power = PowerPolicy.shared.currentSettings
        let usage = diskUsage()
        let toolStatuses = await ToolManager.shared.checkAll()

        if json {
            var status: [String: Any] = [
                "launchagent": HostProvisioning.shared.isInstalled,
                "tailscale_running": TailscaleSetup.shared.isRunning,
                "tailscale_version": TailscaleSetup.shared.version ?? "unknown",
                "power_settings": power,
                "tools": toolStatuses.map { [
                    "name": $0.tool.name,
                    "installed": $0.isInstalled,
                    "version": $0.currentVersion ?? "unknown",
                    "update_available": $0.updateAvailable
                ] as [String: Any] }
            ]
            if let usage = usage {
                status["disk"] = [
                    "total_gb": usage.total / 1_073_741_824,
                    "free_gb": usage.free / 1_073_741_824,
                    "used_percent": usage.usedPercent
                ]
            }
            printJSON(status)
        } else {
            print("Anvil Host Status")
            print("  LaunchAgent: \(HostProvisioning.shared.isInstalled ? "installed" : "not installed")")
            print("  Tailscale: \(TailscaleSetup.shared.isRunning ? "running" : "not running")")
            
            print("  Tools:")
            for toolStatus in toolStatuses {
                let update = toolStatus.updateAvailable ? " (update available)" : ""
                print("    \(toolStatus.isInstalled ? "✓" : "✗") \(toolStatus.tool.name): \(toolStatus.currentVersion ?? "not installed")\(update)")
            }

            if let sleep = power["sleep"] {
                print("  Sleep: \(sleep)")
            }

            if let usage = usage {
                print(String(format: "  Disk: %.1f%% used", usage.usedPercent))
            }
        }
    }

    private static func runUninstall(json: Bool) async {
        var results: [String: String] = [:]

        do {
            try HostProvisioning.shared.remove()
            results["launchagent"] = "removed"
        } catch {
            results["launchagent"] = "error: \(error)"
        }

        do {
            try PowerPolicy.shared.reset()
            results["power_policy"] = "reset"
        } catch {
            results["power_policy"] = "error: \(error)"
        }

        await CleanupDaemon.shared.stop()
        results["cleanup_daemon"] = "stopped"
        
        await ToolUpdateDaemon.shared.stop()
        results["update_daemon"] = "stopped"

        if json {
            printJSON(results)
        } else {
            print("Uninstalled.")
            for (key, value) in results {
                print("  \(key): \(value)")
            }
        }
    }

    private static func runTools(args: [String], json: Bool) async {
        guard let subcommand = args.first else {
            print("Usage: anvil-host tools <check|install|install-all|update|update-critical>")
            exit(1)
        }
        
        let manager = ToolManager.shared
        
        switch subcommand {
        case "check":
            let statuses = await manager.checkAll()
            if json {
                printJSON(statuses.map { [
                    "name": $0.tool.name,
                    "installed": $0.isInstalled,
                    "current_version": $0.currentVersion ?? "unknown",
                    "latest_version": $0.latestVersion ?? "unknown",
                    "update_available": $0.updateAvailable
                ] as [String: Any] })
            } else {
                print("Tool Status:")
                for status in statuses {
                    let update = status.updateAvailable ? " → \(status.latestVersion ?? "?")" : ""
                    print("  \(status.isInstalled ? "✓" : "✗") \(status.tool.name): \(status.currentVersion ?? "not installed")\(update)")
                }
            }
            
        case "install":
            print("Installing missing critical tools...")
            do {
                let results = try await manager.installAllCritical()
                if json {
                    printJSON(results.map { [
                        "name": $0.tool.name,
                        "installed": $0.isInstalled,
                        "version": $0.currentVersion ?? "unknown"
                    ] as [String: Any] })
                } else {
                    for result in results {
                        print("  \(result.isInstalled ? "✓" : "✗") \(result.tool.name): \(result.currentVersion ?? "failed")")
                    }
                }
            } catch {
                print("Error: \(error)")
                exit(1)
            }
            
        case "install-all":
            print("Installing all missing tools...")
            do {
                let results = try await manager.installAll()
                if json {
                    printJSON(results.map { [
                        "name": $0.tool.name,
                        "installed": $0.isInstalled,
                        "version": $0.currentVersion ?? "unknown"
                    ] as [String: Any] })
                } else {
                    for result in results {
                        print("  \(result.isInstalled ? "✓" : "✗") \(result.tool.name): \(result.currentVersion ?? "failed")")
                    }
                }
            } catch {
                print("Error: \(error)")
                exit(1)
            }
            
        case "update":
            print("Updating all tools...")
            do {
                let results = try await manager.updateAll()
                if json {
                    printJSON(results.map { [
                        "name": $0.tool.name,
                        "installed": $0.isInstalled,
                        "version": $0.currentVersion ?? "unknown"
                    ] as [String: Any] })
                } else {
                    for result in results {
                        print("  \(result.isInstalled ? "✓" : "✗") \(result.tool.name): \(result.currentVersion ?? "failed")")
                    }
                }
            } catch {
                print("Error: \(error)")
                exit(1)
            }
            
        case "update-critical":
            print("Updating critical tools...")
            do {
                let results = try await manager.updateCritical()
                if json {
                    printJSON(results.map { [
                        "name": $0.tool.name,
                        "installed": $0.isInstalled,
                        "version": $0.currentVersion ?? "unknown"
                    ] as [String: Any] })
                } else {
                    for result in results {
                        print("  \(result.isInstalled ? "✓" : "✗") \(result.tool.name): \(result.currentVersion ?? "failed")")
                    }
                }
            } catch {
                print("Error: \(error)")
                exit(1)
            }
            
        default:
            print("Unknown tools subcommand: \(subcommand)")
            print("Usage: anvil-host tools <check|install|install-all|update|update-critical>")
            exit(1)
        }
    }

    private static func printJSON(_ object: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            print("{\"error\": \"failed to serialize JSON\"}")
            return
        }
        print(string)
    }
}

private func diskUsage() -> (total: UInt64, free: UInt64, usedPercent: Double)? {
    let url = URL(fileURLWithPath: "/")
    guard let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey]),
          let total = values.volumeTotalCapacity,
          let free = values.volumeAvailableCapacity else {
        return nil
    }
    let used = total - free
    let percent = (Double(used) / Double(total)) * 100
    return (UInt64(total), UInt64(free), percent)
}
