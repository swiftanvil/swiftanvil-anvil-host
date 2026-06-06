import Foundation

/// Represents a managed tool that can be installed, checked, and updated.
public struct Tool: Sendable {
    public let name: String
    public let description: String
    public let checkCommand: (executable: String, args: [String])
    public let parseVersion: @Sendable (String) -> String?
    public let installMethod: InstallMethod
    public let updateMethod: UpdateMethod
    public let isCritical: Bool
    
    public init(
        name: String,
        description: String,
        checkCommand: (executable: String, args: [String]),
        parseVersion: @escaping @Sendable (String) -> String?,
        installMethod: InstallMethod,
        updateMethod: UpdateMethod,
        isCritical: Bool = false
    ) {
        self.name = name
        self.description = description
        self.checkCommand = checkCommand
        self.parseVersion = parseVersion
        self.installMethod = installMethod
        self.updateMethod = updateMethod
        self.isCritical = isCritical
    }
}

public enum InstallMethod: Sendable {
    case xcodeSelect
    case homebrew(formula: String)
    case homebrewCask(cask: String)
    case script(url: String, verifyCommand: String)
    case custom(install: @Sendable () async throws -> Void)
}

public enum UpdateMethod: Sendable {
    case homebrew
    case softwareupdate
    case none
    case custom(update: @Sendable () async throws -> Void)
}

public struct ToolStatus: Sendable {
    public let tool: Tool
    public let isInstalled: Bool
    public let currentVersion: String?
    public let latestVersion: String?
    public let updateAvailable: Bool
    public let lastChecked: Date
}

/// Registry of all tools managed by AnvilHost.
public struct ToolRegistry: Sendable {
    public static let `default` = ToolRegistry()
    
    public let tools: [Tool]
    
    private init() {
        self.tools = [
            Tool(
                name: "xcode-tools",
                description: "Xcode Command Line Tools",
                checkCommand: ("/usr/bin/xcode-select", ["-p"]),
                parseVersion: { _ in "installed" },
                installMethod: .xcodeSelect,
                updateMethod: .softwareupdate,
                isCritical: true
            ),
            Tool(
                name: "homebrew",
                description: "Homebrew package manager",
                checkCommand: ("/opt/homebrew/bin/brew", ["--version"]),
                parseVersion: { output in
                    output.split(separator: " ").dropFirst().first.map(String.init)
                },
                installMethod: .script(
                    url: "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh",
                    verifyCommand: "/opt/homebrew/bin/brew --version"
                ),
                updateMethod: .none,
                isCritical: true
            ),
            Tool(
                name: "git",
                description: "Git version control",
                checkCommand: ("/usr/bin/git", ["--version"]),
                parseVersion: { output in
                    // git version 2.39.3 (Apple Git-146)
                    let parts = output.split(separator: " ")
                    guard parts.count >= 3 else { return nil }
                    return String(parts[2])
                },
                installMethod: .homebrew(formula: "git"),
                updateMethod: .homebrew,
                isCritical: true
            ),
            Tool(
                name: "swift",
                description: "Swift toolchain",
                checkCommand: ("/usr/bin/swift", ["--version"]),
                parseVersion: { output in
                    // swift-driver version: 1.115.1 Apple Swift version 6.0.3 (swiftlang-6.0.3.1.10 clang-1600.0.30.1)
                    let lines = output.split(separator: "\n")
                    guard let firstLine = lines.first else { return nil }
                    let parts = firstLine.split(separator: " ")
                    // Find "version" and take the next element
                    if let versionIndex = parts.firstIndex(of: "version"), versionIndex + 1 < parts.count {
                        return String(parts[versionIndex + 1])
                    }
                    return nil
                },
                installMethod: .xcodeSelect,
                updateMethod: .softwareupdate,
                isCritical: true
            ),
            Tool(
                name: "tailscale",
                description: "Tailscale VPN",
                checkCommand: ("/opt/homebrew/bin/tailscale", ["version"]),
                parseVersion: { output in
                    output.trimmingCharacters(in: .whitespacesAndNewlines)
                        .split(separator: "\n").first.map(String.init)
                },
                installMethod: .homebrewCask(cask: "tailscale-app"),
                updateMethod: .homebrew,
                isCritical: true
            ),
            Tool(
                name: "rosetta",
                description: "Rosetta 2 for x64 compatibility",
                checkCommand: ("/usr/bin/pgrep", ["-q", "-x", "oahd"]),
                parseVersion: { _ in "installed" },
                installMethod: .script(
                    url: "",
                    verifyCommand: "/usr/bin/pgrep -q -x oahd"
                ),
                updateMethod: .none
            ),
        ]
    }
    
    public func tool(named name: String) -> Tool? {
        tools.first { $0.name == name }
    }
    
    public var criticalTools: [Tool] {
        tools.filter(\.isCritical)
    }
}
