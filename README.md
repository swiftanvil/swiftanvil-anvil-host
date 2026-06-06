# swiftanvil-anvil-host

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

## Quick Start

```bash
git clone <repo> swiftanvil-anvil-host
cd swiftanvil-anvil-host
./Scripts/install.sh
```

The install script builds the release binary, copies it to `/usr/local/bin`, and runs `anvil-host provision`.

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
