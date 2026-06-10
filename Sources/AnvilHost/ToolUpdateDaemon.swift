import Foundation

/// Background daemon that periodically checks for tool updates and applies them.
public actor ToolUpdateDaemon {
    public static let shared = ToolUpdateDaemon()

    private var timer: Timer?
    private let checkInterval: TimeInterval
    private let autoUpdateCritical: Bool
    private let notifyOnUpdate: Bool

    /// Creates the update daemon.
    /// - Parameters:
    ///   - checkInterval: How often to check for updates (default: 24 hours)
    ///   - autoUpdateCritical: Whether to auto-update critical tools (default: true)
    ///   - notifyOnUpdate: Whether to print/log when updates are available (default: true)
    public init(
        checkInterval: TimeInterval = 86400,
        autoUpdateCritical: Bool = true,
        notifyOnUpdate: Bool = true
    ) {
        self.checkInterval = checkInterval
        self.autoUpdateCritical = autoUpdateCritical
        self.notifyOnUpdate = notifyOnUpdate
    }

    /// Starts the background update checker.
    public func start() {
        Task {
            await stop()

            // Run immediately on start
            await performCheck()

            // Schedule periodic checks
            timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
                Task { [weak self] in
                    await self?.performCheck()
                }
            }
            timer?.tolerance = 3600 // 1 hour tolerance
            RunLoop.main.add(timer!, forMode: .common)

            if notifyOnUpdate {
                print("[ToolUpdateDaemon] Started. Checking every \(formatInterval(checkInterval))")
            }
        }
    }

    /// Stops the background update checker.
    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Performs a single update check.
    public func performCheck() async {
        guard notifyOnUpdate else { return }

        print("[ToolUpdateDaemon] Checking for tool updates...")

        let manager = ToolManager.shared
        let statuses = await manager.checkAll()

        var updatesAvailable: [ToolStatus] = []
        var criticalUpdates: [ToolStatus] = []

        for status in statuses {
            if status.updateAvailable {
                updatesAvailable.append(status)
                if status.tool.isCritical {
                    criticalUpdates.append(status)
                }
            }
        }

        if updatesAvailable.isEmpty {
            print("[ToolUpdateDaemon] All tools up to date.")
            return
        }

        print("[ToolUpdateDaemon] \(updatesAvailable.count) update(s) available:")
        for status in updatesAvailable {
            let critical = status.tool.isCritical ? " [CRITICAL]" : ""
            print(
                "  - \(status.tool.name): \(status.currentVersion ?? "unknown") → \(status.latestVersion ?? "unknown")\(critical)"
            )
        }

        // Auto-update critical tools if enabled
        if autoUpdateCritical, !criticalUpdates.isEmpty {
            print("[ToolUpdateDaemon] Auto-updating critical tools...")
            for status in criticalUpdates {
                do {
                    let result = try await manager.update(status.tool)
                    if result.updateAvailable {
                        print("  ✗ \(status.tool.name): update failed")
                    } else {
                        print("  ✓ \(status.tool.name): updated to \(result.currentVersion ?? "unknown")")
                    }
                } catch {
                    print("  ✗ \(status.tool.name): \(error)")
                }
            }
        }
    }

    /// Forces an immediate update check and returns results.
    public func forceCheck() async -> [ToolStatus] {
        let manager = ToolManager.shared
        return await manager.checkAll()
    }

    // MARK: - Private

    private func formatInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        if hours < 24 {
            return "\(hours) hour(s)"
        }
        let days = hours / 24
        return "\(days) day(s)"
    }
}
