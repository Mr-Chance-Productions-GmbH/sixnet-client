# sixnet-client

Native macOS menu bar app for [sixnet](https://github.com/Mr-Chance-Productions-GmbH/sixnet) —
a self-hosted VPN platform built on ZeroTier.

The client replaces a bash wrapper script with a proper menu bar app. Users connect,
disconnect, and check status without ever opening a terminal.

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools: `xcode-select --install`
- ZeroTier installed on the machine (from [zerotier.com/download](https://www.zerotier.com/download/))

## Build

```bash
make build                   # debug build
make release                 # release build
make dist VERSION=x.y.z      # release build + package DMG (local validation)
make run                     # build + launch
make clean                   # remove build artifacts
```

### Build artifacts

`build/` must not live on a cloud-synced filesystem (Google Drive, iCloud, Dropbox).
It should be a symlink to a local path. If you use the `mkdir-nosync` convention:

```bash
mkdir-nosync build   # creates ~/.nosync/projects/sixnet-client/build and symlinks it
```

After `make clean`, recreate the symlink before building again.

## Project structure

```
app/
  SixnetClient.xcodeproj/   Xcode project (committed, no generator tool)
  SixnetClient/             Swift source files
    SixnetClientApp.swift   App entry point, AppDelegate, daemon lifecycle
    DaemonClient.swift      Unix socket client, multi-network state, polling
    MenuBarView.swift       Per-network rows: status, connect/disconnect
    AddNetworkView.swift    Modal sheet: URL → fetch client.json → save
    Info.plist              Bundle config (LSUIElement=YES, no Dock icon)
    SixnetClient.entitlements  No sandbox
    Assets.xcassets/
Makefile                    xcodebuild wrapper
```

## Installation

```bash
brew install --cask Mr-Chance-Productions-GmbH/sixnet/sixnet-client
```

This installs the app and the sixnetd daemon in one command. The app is not
notarized — notarization would mean submitting to Apple for approval, which
contradicts the self-hosted design of this project. The cask handles Gatekeeper
automatically by stripping the quarantine attribute after install.

On first launch the app will ask for an admin password once to start the
background service.

**Uninstall:**
```bash
brew uninstall --cask sixnet-client && brew uninstall sixnetd
```

No root required. The running sixnetd process exits on next reboot or can be
killed manually (`pkill sixnetd`). No traces left in system directories.

## Privileged operations

All privileged operations (ZeroTier CLI, DNS resolver writes) go through
[sixnetd](https://github.com/Mr-Chance-Productions-GmbH/sixnetd) — a background
daemon that runs as root. The Swift app is entirely unprivileged and communicates
with sixnetd via a Unix socket. No repeated auth dialogs after first launch.

## Related

- [sixnet](https://github.com/Mr-Chance-Productions-GmbH/sixnet) — the server-side stack
- `vpn/zt` in the sixnet repo — the bash reference implementation this app replaces
