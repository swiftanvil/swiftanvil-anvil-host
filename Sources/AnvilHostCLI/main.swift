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
          provision    Full setup (LaunchAgent, Tailscale, power policy)
          doctor       Run readiness checks
          status       Show host health
          uninstall    Remove everything
          help         Show this message

        Options:
          --json       Output machine-readable JSON for agent consumption
        """)
    }

    private static func runProvision(json: Bool) async {
        var results: [String: Any] = [:]
        var errors: [String] = []

        do {
            try TailscaleSetup.shared.verify()
            results["tailscale"] = "ok"
        } catch {
            results["tailscale"] = "failed"
            errors.append("Tailscale: \(error)")
        }

        do {
            try PowerPolicy.shared.apply()
            results["power_policy"] = "applied"
        } catch {
            results["power_policy"] = "failed"
            errors.append("Power policy: \(error)")
        }

        let plist = URL(fileURLWithPath: "/Users/vishalsingh/Documents/v-i-s-h-a-l/swiftanvil/swiftanvil-anvil-host/launchd/com.swiftanvil.anvil-host.plist")

        do {
            try HostProvisioning.shared.install(agentPlistSource: plist)
            results["launchagent"] = "installed"
        } catch {
            results["launchagent"] = "failed"
            errors.append("LaunchAgent: \(error)")
        }

        await CleanupDaemon.shared.start()
        results["cleanup_daemon"] = "started"

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

        if json {
            let checkDicts = checks.map { [
                "name": $0.name,
                "passed": $0.passed,
                "message": $0.message
            ] as [String: Any] }
            printJSON([
                "checks": checkDicts,
                "all_passed": checks.allSatisfy(\.passed)
            ])
        } else {
            for check in checks {
                let symbol = check.passed ? "✓" : "✗"
                print("  \(symbol) \(check.name): \(check.message)")
            }
        }

        let failed = !checks.allSatisfy(\.passed)
        exit(failed ? 1 : 0)
    }

    private static func runStatus(json: Bool) async {
        let power = PowerPolicy.shared.currentSettings
        let usage = diskUsage()

        if json {
            var status: [String: Any] = [
                "launchagent": HostProvisioning.shared.isInstalled,
                "tailscale_running": TailscaleSetup.shared.isRunning,
                "tailscale_version": TailscaleSetup.shared.version ?? "unknown",
                "power_settings": power
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

        if json {
            printJSON(results)
        } else {
            print("Uninstalled.")
            for (key, value) in results {
                print("  \(key): \(value)")
            }
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
