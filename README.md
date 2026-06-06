# swiftanvil-anvil-host

> **Launch your AI agent and say: "Set up this Mac as a CI worker."**
>
> That's it. The agent handles everything else — detecting state, installing tools, configuring the system, and asking you only for what's needed.

---

Kitchen-setup service that turns a Mac into a hands-off CI worker for SwiftAnvil.

## Overview

`anvil-host` provisions an M1 Mac mini (or any Apple-Silicon Mac) so it can run `anvil-runner` jobs without manual intervention:

- Installs a **LaunchAgent** that keeps `anvil-runner` alive across reboots and crashes.
- Verifies **Tailscale** is installed and running for remote access.
- Configures **power policy** (no sleep, auto-restart on power loss).
- Runs a lightweight **cleanup daemon** that frees disk space when the drive fills up.
- Provides **pre-flight checks** (`doctor`) to validate readiness before provisioning.

## Requirements

- macOS 14+
- Apple Silicon Mac (optimised for M1 Mac mini, 16 GB RAM, ~256 GB SSD)
- [Tailscale](https://tailscale.com) installed and logged in
- Xcode Command Line Tools

## Quick Start — AI Agent Mode (Recommended)

This repository is designed to be operated by an AI agent. You don't need to know commands.

**Step 1:** Clone this repository

```bash
git clone https://github.com/swiftanvil/swiftanvil-anvil-host.git
cd swiftanvil-anvil-host
```

**Step 2:** Launch your AI agent (Claude Code, Codex, Kimi, etc.)

**Step 3:** Paste this prompt:

```
Set up this Mac as a CI worker.
```

That's it. The agent reads the repository instructions, detects the machine state, and guides you through the rest — asking only for things it needs from you (like confirming sudo access).

## Quick Start — Manual Mode

If you prefer to run commands yourself:

### Option 1: Pre-built binary (fastest)

```bash
curl -sL https://raw.githubusercontent.com/swiftanvil/swiftanvil-anvil-host/main/Scripts/install.sh | bash
sudo anvil-host provision
```

This downloads the latest release binary from GitHub, installs it to `/usr/local/bin`, and is ready to run.

### Option 2: Build from source

```bash
git clone <repo> swiftanvil-anvil-host
cd swiftanvil-anvil-host
swift build -c release
sudo cp .build/release/anvil-host /usr/local/bin/
sudo anvil-host provision
```

## CLI

```bash
anvil-host provision    # Full setup
anvil-host doctor       # Readiness checks
anvil-host status       # Show host health
anvil-host uninstall    # Remove everything
```

## Project Structure

```
.
├── Package.swift
├── Sources
│   ├── AnvilHost           # Library
│   │   ├── HostProvisioning.swift
│   │   ├── TailscaleSetup.swift
│   │   ├── PowerPolicy.swift
│   │   ├── CleanupDaemon.swift
│   │   └── HostDoctor.swift
│   └── AnvilHostCLI        # Executable
│       └── main.swift
├── launchd
│   └── com.swiftanvil.anvil-host.plist
├── Scripts
│   └── install.sh
├── README.md
└── LICENSE
```

## License

MIT
