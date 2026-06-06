import Foundation

public struct HostCheck: Sendable {
    public let name: String
    public let passed: Bool
    public let message: String
    
    public init(name: String, passed: Bool, message: String) {
        self.name = name
        self.passed = passed
        self.message = message
    }
}

public struct HostDoctor: Sendable {
    public static let shared = HostDoctor()

    private init() {}

    public func runAllChecks() async -> [HostCheck] {
        await withTaskGroup(of: HostCheck.self) { group in
            group.addTask { await checkSIP() }
            group.addTask { await checkFreeDiskSpace() }
            group.addTask { await checkMemory() }
            group.addTask { await checkTailscale() }
            group.addTask { await checkRosetta() }

            var results: [HostCheck] = []
            for await check in group {
                results.append(check)
            }
            return results.sorted { $0.name < $1.name }
        }
    }

    public func checkSIP() async -> HostCheck {
        let (out, _, status) = shell("/usr/bin/csrutil", ["status"])
        let passed = status == 0 && out.contains("enabled")
        return HostCheck(
            name: "SIP",
            passed: passed,
            message: passed ? "System Integrity Protection is enabled" : "SIP is disabled or unknown"
        )
    }

    public func checkFreeDiskSpace() async -> HostCheck {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]),
              let free = values.volumeAvailableCapacity else {
            return HostCheck(name: "Disk", passed: false, message: "Unable to read disk capacity")
        }
        let freeGB = Double(free) / 1_073_741_824
        let passed = freeGB > 20
        return HostCheck(
            name: "Disk",
            passed: passed,
            message: String(format: "%.1f GB free", freeGB)
        )
    }

    public func checkMemory() async -> HostCheck {
        var size = UInt32(MemoryLayout<host_basic_info>.size / MemoryLayout<integer_t>.size)
        var info = host_basic_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_info(mach_host_self(), HOST_BASIC_INFO, $0, &size)
            }
        }
        guard result == KERN_SUCCESS else {
            return HostCheck(name: "Memory", passed: false, message: "Unable to query memory")
        }
        let totalGB = Double(info.max_mem) / 1_073_741_824
        let passed = totalGB >= 12
        return HostCheck(
            name: "Memory",
            passed: passed,
            message: String(format: "%.0f GB installed", totalGB)
        )
    }

    public func checkTailscale() async -> HostCheck {
        let setup = TailscaleSetup.shared
        guard setup.isInstalled else {
            return HostCheck(name: "Tailscale", passed: false, message: "Not installed")
        }
        guard setup.isRunning else {
            return HostCheck(name: "Tailscale", passed: false, message: "Installed but not running")
        }
        return HostCheck(name: "Tailscale", passed: true, message: setup.version ?? "Running")
    }

    public func checkRosetta() async -> HostCheck {
        let (_, _, status) = shell("/usr/bin/pgrep", ["-q", "-x", "oahd"])
        let passed = status == 0
        return HostCheck(
            name: "Rosetta",
            passed: passed,
            message: passed ? "Rosetta 2 is active" : "Rosetta 2 is not running"
        )
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
