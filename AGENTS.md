# Agent Instructions — AnvilHost

> **For AI Agents:** This file is your primary guide. Read it fully before taking action. It contains state detection, progressive workflows, safety rules, and handoff patterns.

## What This Repository Does

AnvilHost turns a Mac into a hands-off CI worker. It installs a LaunchAgent to keep `anvil-runner` alive across reboots, configures power policy (no sleep, auto-restart), verifies Tailscale, and runs a background cleanup daemon.

**It does NOT:**
- Download or configure GitHub Actions runners (that's `swiftanvil-anvil-runner`)
- Build or test code
- Manage runner tokens or repository registration

**Prerequisites:**
- macOS 14+ on Apple Silicon
- Xcode Command Line Tools installed
- Tailscale installed and logged in
- `swiftanvil-anvil-runner` cloned nearby (sibling directory)

## Current State Detection

When you open this repository, detect the current state:

```bash
# Check if binary is built
ls .build/release/anvil-host 2>/dev/null && echo "built" || echo "not built"

# Check if installed system-wide
ls /usr/local/bin/anvil-host 2>/dev/null && echo "installed" || echo "not installed"

# Check LaunchAgent status
ls ~/Library/LaunchAgents/com.swiftanvil.anvil-runner.plist 2>/dev/null && echo "launchagent installed" || echo "no launchagent"
launchctl list | grep com.swiftanvil.anvil-runner && echo "launchagent loaded" || echo "launchagent not loaded"

# Check Tailscale
/Applications/Tailscale.app/Contents/MacOS/Tailscale status 2>/dev/null && echo "tailscale ok" || echo "tailscale not running"

# Check power policy
pmset -g | grep -E "sleep|autorestart" | head -5

# Check disk usage
df -h / | tail -1 | awk '{print "Disk: " $5 " used"}'
```

## What You Can Do Here — Progressive Options

### State: Fresh Clone (nothing built)

**Option 1: Build the project**
> "Build anvil-host"
```bash
swift build -c release
```

**Option 2: Run health checks without installing**
> "Check if this Mac is ready"
```bash
swift run anvil-host doctor
```

**Option 3: See what would change (dry run)**
> "Show me what provisioning would do"
```bash
swift run anvil-host status
```

---

### State: Built (binary exists)

**Option 1: Full provision (one-time setup)**
> "Set up this Mac as a CI worker"
> ⚠️ Requires: `sudo` for power policy changes
```bash
sudo .build/release/anvil-host provision
```
> This installs the LaunchAgent, configures power policy, verifies Tailscale, and starts the cleanup daemon.

**Option 2: Run health checks**
> "Is this Mac ready for CI?"
```bash
.build/release/anvil-host doctor
```

**Option 3: Install system-wide**
> "Install anvil-host to /usr/local/bin"
```bash
sudo mkdir -p /usr/local/bin
sudo cp .build/release/anvil-host /usr/local/bin/
sudo chmod +x /usr/local/bin/anvil-host
```

---

### State: Provisioned (LaunchAgent installed)

**Option 1: Check status**
> "Is everything running?"
```bash
anvil-host status
```

**Option 2: Re-provision (idempotent)**
> "Re-run provisioning"
```bash
sudo anvil-host provision
```

**Option 3: Uninstall**
> "Remove all host configuration"
```bash
sudo anvil-host uninstall
```

---

### State: Installed + Provisioned (production ready)

**Option 1: Set up runners**
> "Now install anvil-runner"
> This delegates to `swiftanvil-anvil-runner`
```bash
cd ../swiftanvil-anvil-runner
swift build -c release
export ANVIL_RUNNER_TOKEN=<token>
.build/release/anvil-runner setup --repo https://github.com/<org>/<repo> --count 2
.build/release/anvil-runner start --count 2
```

**Option 2: Verify auto-start works**
> "Test reboot recovery"
```bash
# Simulate: the LaunchAgent will restart anvil-runner on boot
# Verify it's configured:
launchctl list | grep com.swiftanvil.anvil-runner
```

**Option 3: Monitor disk**
> "Check if cleanup daemon is working"
```bash
anvil-host status
# Look for disk usage and daemon state
```

---

## Common Workflows

### Workflow: New Mac Mini Setup (Physical Access)
```bash
# 1. Clone both repositories
git clone https://github.com/swiftanvil/swiftanvil-anvil-host.git
git clone https://github.com/swiftanvil/swiftanvil-anvil-runner.git

# 2. Build and provision host
cd swiftanvil-anvil-host
swift build -c release
sudo .build/release/anvil-host provision

# 3. Build and set up runner
cd ../swiftanvil-anvil-runner
swift build -c release
export ANVIL_RUNNER_TOKEN=<token>
.build/release/anvil-runner setup --repo https://github.com/<org>/<repo> --count 2
.build/release/anvil-runner start --count 2

# 4. Verify
.build/release/anvil-runner status --count 2

# 5. Walk away. Machine will survive reboots.
```

### Workflow: Remote Health Check (After Physical Setup)
```bash
# SSH via Tailscale
ssh user@macmini-tailscale-name

# Check host status
anvil-host status

# Check runner status
cd ~/swiftanvil-anvil-runner
.build/release/anvil-runner status --count 2
```

### Workflow: Disk Emergency
```bash
# If disk is full, cleanup daemon should trigger automatically
# Manual intervention:
anvil-host status
sudo anvil-host provision  # re-applies everything, restarts daemon
cd ~/swiftanvil-anvil-runner
.build/release/anvil-runner clean --aggressive
```

---

## Handoff Notes

After any action, report:
1. **What was done** (commands executed, outputs)
2. **Current state** (provisioned? running? disk usage?)
3. **Next options** (based on new state)

Example handoff after provisioning:
> ✅ Host provisioned successfully.
>
> **What was done:**
> - LaunchAgent installed at `~/Library/LaunchAgents/com.swiftanvil.anvil-runner.plist`
> - Power policy: sleep disabled, auto-restart on power loss enabled
> - Cleanup daemon: running, triggers at 85% disk usage
> - Tailscale: verified running
>
> **Current state:** Host is ready. No runners configured yet.
>
> **Next options:**
> 1. **Set up anvil-runner** — Configure GitHub Actions runners (requires token)
> 2. **Reboot test** — Verify auto-start works after restart
> 3. **Check status anytime** — `anvil-host status`

Example handoff after runner setup:
> ✅ Runners configured and running.
>
> **What was done:**
> - 2 runners registered with GitHub for `org/repo`
> - Runners are processing jobs
>
> **Current state:** Fully operational CI worker.
>
> **Next options:**
> 1. **Monitor remotely** — SSH via Tailscale, run `anvil-host status`
> 2. **Add more runners** — `anvil-runner setup --count 4`
> 3. **Set up another Mac** — Clone repos, run `anvil-host provision`

---

## Safety Rules

- **Provisioning requires `sudo`** for power policy changes. Never run with sudo unless necessary.
- **LaunchAgent runs as the current user** — do not require root for normal operation.
- **Cleanup daemon never deletes protected paths** — see `anvil-runner` safety policy.
- **Idempotence** — `provision` can be run multiple times safely.
- **Uninstall reverses all changes** — removes LaunchAgent, resets power policy, stops daemon.
- **Do not store tokens in this repository** — runner tokens belong in `swiftanvil-anvil-runner`.
- **Tailscale is assumed pre-installed** — do not attempt to install Tailscale; verify only.

## Related Repositories

| Repository | Role | When to Use |
|------------|------|-------------|
| `swiftanvil-anvil-runner` | Runner lifecycle | Download, configure, start, stop, clean runners |
| `swiftanvil-anvil-host` | Host provisioning | This repo — auto-start, power, cleanup, Tailscale |
| `swiftanvil-anvil-fleet` | Multi-machine (future) | Orchestrate many hosts |

## Review Focus

Every substantive change should be reviewed for:
- LaunchAgent correctness (plist syntax, paths, permissions)
- Power policy safety (does not brick the machine)
- Cleanup daemon boundedness (cannot runaway)
- Idempotence of provision/uninstall cycles
- Separation from runner lifecycle concerns
