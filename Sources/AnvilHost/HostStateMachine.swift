import Foundation

// MARK: - State Machine

/// Represents the current provisioning state of the host.
public enum HostState: String, Sendable, CaseIterable {
    case freshClone      = "fresh-clone"
    case built           = "built"
    case provisioned     = "provisioned"
    case productionReady = "production-ready"
    
    public var description: String {
        switch self {
        case .freshClone:
            return "Repository cloned but not built"
        case .built:
            return "Binary built but host not provisioned"
        case .provisioned:
            return "Host provisioned (LaunchAgent, power policy, daemons)"
        case .productionReady:
            return "Fully operational — runners can be configured"
        }
    }
}

/// Detects the current state of the host by inspecting the filesystem and system.
public struct HostStateDetector: Sendable {
    public static let shared = HostStateDetector()
    
    private init() {}
    
    public func detect() async -> HostState {
        // Check if binary is built
        let binaryBuilt = FileManager.default.fileExists(
            atPath: "/Users/vishalsingh/Documents/v-i-s-h-a-l/swiftanvil/swiftanvil-anvil-host/.build/release/anvil-host"
        )
        
        // Check if installed system-wide
        let systemWide = FileManager.default.fileExists(atPath: "/usr/local/bin/anvil-host")
        
        // Check LaunchAgent
        let launchAgentPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.swiftanvil.anvil-runner.plist")
        let launchAgentInstalled = FileManager.default.fileExists(atPath: launchAgentPath.path)
        
        // Check power policy (sleep disabled = provisioned)
        let powerProvisioned = await isPowerProvisioned()
        
        if !binaryBuilt {
            return .freshClone
        }
        
        if !launchAgentInstalled || !powerProvisioned {
            return .built
        }
        
        if systemWide {
            return .productionReady
        }
        
        return .provisioned
    }
    
    private func isPowerProvisioned() async -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["-g"]
        
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return false
        }
        
        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard task.terminationStatus == 0 else { return false }
        // Sleep disabled means sleep=0 in active profile
        return out.contains("sleep\t\t0") || out.contains("sleep 0")
    }
}

// MARK: - Action Discovery

/// An action that can be performed from a given state.
public struct HostAction: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String
    public let requiresConfirmation: Bool
    public let requiresSudo: Bool
    public let parameters: [HostActionParameter]
    public let availableFromStates: [HostState]
    
    public init(
        id: String,
        name: String,
        description: String,
        requiresConfirmation: Bool = false,
        requiresSudo: Bool = false,
        parameters: [HostActionParameter] = [],
        availableFromStates: [HostState]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.requiresConfirmation = requiresConfirmation
        self.requiresSudo = requiresSudo
        self.parameters = parameters
        self.availableFromStates = availableFromStates
    }
}

/// A parameter required by an action.
public struct HostActionParameter: Sendable {
    public let name: String
    public let type: ParameterType
    public let description: String
    public let required: Bool
    public let defaultValue: String?
    
    public enum ParameterType: String, Sendable {
        case string
        case boolean
        case integer
        case path
        case url
    }
    
    public init(
        name: String,
        type: ParameterType,
        description: String,
        required: Bool = true,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
        self.defaultValue = defaultValue
    }
}

/// Discovers all available actions from the current state.
public struct HostActionDiscovery: Sendable {
    public static let shared = HostActionDiscovery()
    
    private let allActions: [HostAction] = [
        HostAction(
            id: "build",
            name: "Build anvil-host",
            description: "Compile the release binary",
            availableFromStates: [.freshClone]
        ),
        HostAction(
            id: "doctor",
            name: "Run health checks",
            description: "Check if this Mac is ready for CI without installing anything",
            availableFromStates: [.freshClone, .built, .provisioned, .productionReady]
        ),
        HostAction(
            id: "tools-check",
            name: "Check tool status",
            description: "Show which tools are installed and which need updates",
            availableFromStates: [.freshClone, .built, .provisioned, .productionReady]
        ),
        HostAction(
            id: "provision",
            name: "Provision host",
            description: "Full setup: LaunchAgent, power policy, Tailscale, cleanup daemon, tool updates",
            requiresConfirmation: true,
            requiresSudo: true,
            availableFromStates: [.freshClone, .built, .provisioned]
        ),
        HostAction(
            id: "tools-install",
            name: "Install missing critical tools",
            description: "Install Xcode CLT, Homebrew, Git, Swift, Tailscale if missing",
            requiresConfirmation: true,
            availableFromStates: [.built, .provisioned]
        ),
        HostAction(
            id: "tools-update",
            name: "Update all tools",
            description: "Update all managed tools to their latest versions",
            requiresConfirmation: true,
            availableFromStates: [.built, .provisioned, .productionReady]
        ),
        HostAction(
            id: "install-system-wide",
            name: "Install system-wide",
            description: "Copy anvil-host binary to /usr/local/bin",
            requiresConfirmation: true,
            requiresSudo: true,
            availableFromStates: [.built, .provisioned]
        ),
        HostAction(
            id: "status",
            name: "Check host status",
            description: "Show current host health, LaunchAgent state, tools, disk usage",
            availableFromStates: [.provisioned, .productionReady]
        ),
        HostAction(
            id: "uninstall",
            name: "Uninstall host configuration",
            description: "Remove LaunchAgent, reset power policy, stop daemons",
            requiresConfirmation: true,
            requiresSudo: true,
            availableFromStates: [.provisioned, .productionReady]
        ),
    ]
    
    private init() {}
    
    /// Returns all actions available from the given state.
    public func availableActions(from state: HostState) -> [HostAction] {
        allActions.filter { $0.availableFromStates.contains(state) }
    }
    
    /// Returns all possible actions (for documentation).
    public func allActionsList() -> [HostAction] { allActions }
    
    /// Finds an action by ID.
    public func action(id: String) -> HostAction? {
        allActions.first { $0.id == id }
    }
}

// MARK: - Execution Result

/// The result of executing a host action.
public struct HostActionResult: Sendable {
    public let actionID: String
    public let success: Bool
    public let message: String
    public let details: [String: String]
    public let newState: HostState?
    
    public init(
        actionID: String,
        success: Bool,
        message: String,
        details: [String: String] = [:],
        newState: HostState? = nil
    ) {
        self.actionID = actionID
        self.success = success
        self.message = message
        self.details = details
        self.newState = newState
    }
}

// MARK: - JSON Serialization

extension HostState {
    public func toJSON() -> [String: Any] {
        [
            "state": rawValue,
            "description": description,
            "possible_actions": HostActionDiscovery.shared.availableActions(from: self).map { $0.toJSON() }
        ]
    }
}

extension HostAction {
    public func toJSON() -> [String: Any] {
        [
            "id": id,
            "name": name,
            "description": description,
            "requires_confirmation": requiresConfirmation,
            "requires_sudo": requiresSudo,
            "parameters": parameters.map { $0.toJSON() }
        ]
    }
}

extension HostActionParameter {
    public func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "type": type.rawValue,
            "description": description,
            "required": required
        ]
        if let defaultValue {
            dict["default_value"] = defaultValue
        }
        return dict
    }
}

extension HostActionResult {
    public func toJSON() -> [String: Any] {
        var dict: [String: Any] = [
            "action_id": actionID,
            "success": success,
            "message": message,
            "details": details
        ]
        if let newState {
            dict["new_state"] = newState.rawValue
        }
        return dict
    }
}
