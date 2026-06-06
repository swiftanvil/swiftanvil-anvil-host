# Agent Instructions — AnvilHost

> **For AI Agents:** This file is your control program. Read it, then execute.

## Mission

Turn this Mac into a hands-off CI worker. Install LaunchAgent, configure power policy, verify Tailscale, start cleanup daemons, manage tools.

## What You Must Do First

```bash
swift build -c release 2>/dev/null || swift build
./.build/release/anvil-host
```

The binary will tell you the current state and what actions are available. Do not guess — always run this first.

## How to Execute Actions

```bash
./.build/release/anvil-host agent <action-id>
```

Available action IDs depend on current state. The binary lists them. Common ones:
- `doctor` — health checks
- `provision` — full setup (requires sudo, will prompt for confirmation)
- `status` — show host health
- `tools-update` — update managed tools

## Rules

- **Never** run `provision` without asking the user first. It requires sudo and changes system settings.
- **Always** run the binary with no args before making decisions. State changes after every action.
- **Do not** store tokens in this repo. Runner tokens belong in `swiftanvil-anvil-runner`.
- If `swiftanvil-anvil-runner` exists nearby, suggest moving there after host is provisioned.

## State Reference

| State | Meaning | What to do |
|-------|---------|-----------|
| `fresh-clone` | Not built | `swift build -c release` |
| `built` | Binary ready, not provisioned | `agent doctor`, then `agent provision` |
| `provisioned` | Host ready | `agent status`, or move to runner repo |
| `production-ready` | Installed system-wide | Same as provisioned |

## Handoff

After `provision` succeeds, report:
1. What was done (LaunchAgent, power policy, daemons)
2. Current state
3. Next step: set up runners in `swiftanvil-anvil-runner`
