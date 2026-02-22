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
make build    # debug build
make release  # release build
make run      # build + launch
make clean    # remove build artifacts
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
    SixnetClientApp.swift   App entry point, MenuBarExtra setup
    MenuBarView.swift       Menu bar panel UI
    Info.plist              Bundle config (LSUIElement=YES, no Dock icon)
    SixnetClient.entitlements  No sandbox — needed for zerotier-cli calls
    Assets.xcassets/
Makefile                    xcodebuild wrapper
```

## Distribution

Distributed as a `.dmg`, outside the Mac App Store. The app is ad-hoc signed —
on first launch users will see an "unidentified developer" warning and need to
right-click → Open to allow it. This is a one-time step.

Notarization and Developer ID signing can be added later without code changes.

## Privileged operations

Calls to `zerotier-cli` and writes to `/etc/resolver/` require root. The app uses
`NSAppleScript` with `administrator privileges` — macOS shows its standard auth
dialog on connect. No privileged helper daemon, no Apple Developer account required.

## Related

- [sixnet](https://github.com/Mr-Chance-Productions-GmbH/sixnet) — the server-side stack
- `vpn/zt` in the sixnet repo — the bash reference implementation this app replaces
