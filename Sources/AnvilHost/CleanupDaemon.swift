import Foundation

public actor CleanupDaemon {
    public static let shared = CleanupDaemon()

    private var timer: Timer?
    private let thresholdPercent: Double
    private let checkInterval: TimeInterval

    public init(thresholdPercent: Double = 85.0, checkInterval: TimeInterval = 300) {
        self.thresholdPercent = thresholdPercent
        self.checkInterval = checkInterval
    }

    public func start() {
        Task {
            await stop()
            timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
                Task { [weak self] in
                    await self?.checkAndClean()
                }
            }
            timer?.tolerance = 30
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func checkAndClean() async {
        guard let usage = diskUsage() else { return }
        if usage.usedPercent >= thresholdPercent {
            await performCleanup()
        }
    }

    private func performCleanup() async {
        let commands: [[String]] = [
            ["/usr/bin/sudo", "/usr/sbin/purge"],
            ["/bin/rm", "-rf", "~/Library/Caches/*"],
            ["/bin/rm", "-rf", "/tmp/anvil-*"],
        ]

        for cmd in commands {
            let (_, _, _) = shell(cmd.first!, Array(cmd.dropFirst()))
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
