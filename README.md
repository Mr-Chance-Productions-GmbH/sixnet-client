# sixnet-client

Native macOS menu bar app for [sixnet](https://github.com/Mr-Chance-Productions-GmbH/sixnet) —
a self-hosted VPN platform built on ZeroTier.

The client replaces a bash wrapper script with a proper menu bar app. Users connect,
disconnect, and check status without ever opening a terminal.

## Installation

**Stable channel:**
```bash
brew install --cask Mr-Chance-Productions-GmbH/sixnet/sixnet-client
```

**Dev channel** (latest features, may be unstable):
```bash
brew install --cask Mr-Chance-Productions-GmbH/sixnet/sixnet-client-dev
```

Both install `SixnetClient.app` and the sixnetd daemon in one command. They are
co-installable — dev installs as `SixnetClient Dev.app`. The app is not notarized;
notarization would mean submitting to Apple for approval, which contradicts the
self-hosted design of this project. The cask handles Gatekeeper automatically.

On first launch the app will ask for an admin password once to start the background
service.

**Upgrade:**
```bash
brew upgrade --cask sixnet-client        # stable
brew upgrade --cask sixnet-client-dev    # dev
```

**Uninstall:**
```bash
brew uninstall --cask sixnet-client && brew uninstall sixnetd
# or
brew uninstall --cask sixnet-client-dev && brew uninstall sixnetd
```

No root required. The running sixnetd process exits on next reboot or can be
killed manually (`pkill sixnetd`). No traces left in system directories.

## Releases

**Dev builds** run automatically on every push to `main`. No action needed —
pushing triggers a build, updates the `dev` pre-release on GitHub, and updates
the `sixnet-client-dev` cask. Dev builds are versioned by timestamp (`YYYY.MM.DD.N`).

**Stable releases** are triggered by pushing a version tag:
```bash
git tag v0.2.0
git push github v0.2.0
```

This builds the release DMG, creates a GitHub release, and updates the
`sixnet-client` cask automatically. The Homebrew tap is never edited manually.

## Local development

**Prerequisites:** macOS 13+, Xcode, ZeroTier ([zerotier.com/download](https://www.zerotier.com/download/))

```bash
make build                   # debug build
make release                 # release build (no packaging)
make dist VERSION=x.y.z      # release build + DMG (local validation before tagging)
make dist-dev                # dev build + DMG with patched bundle ID and display name
make run                     # build debug + launch
make clean                   # remove build artifacts
```

### Build artifacts

`build/` must not live on a cloud-synced filesystem (Google Drive, iCloud, Dropbox).
Use a symlink to a local path:

```bash
mkdir-nosync build   # creates ~/.nosync/projects/sixnet-client/build and symlinks it
```

## Project structure

```
app/
  SixnetClient.xcodeproj/   Xcode project
  SixnetClient/             Swift source files
    SixnetClientApp.swift   App entry point, AppDelegate, daemon lifecycle
    DaemonClient.swift      Unix socket client, multi-network state, polling
    MenuBarView.swift       Menu bar popup: networks, mode switcher, about/quit
    AddNetworkView.swift    Modal: URL → fetch client.json → save network
    EnrollView.swift        PKCE enrollment flow (Mode 2)
    PKCEEnrollment.swift    OIDC/PKCE implementation
    Info.plist              Bundle config (LSUIElement=YES, no Dock icon)
.github/workflows/
  release.yml               Stable release pipeline (triggered by v* tag)
  release-dev.yml           Dev release pipeline (triggered by push to main)
scripts/
  write-cask.sh             Generates sixnet-client.rb for the Homebrew tap
  write-cask-dev.sh         Generates sixnet-client-dev.rb for the Homebrew tap
```

## Privileged operations

All privileged operations (ZeroTier CLI, DNS resolver writes) go through
[sixnetd](https://github.com/Mr-Chance-Productions-GmbH/sixnetd) — a background
daemon that runs as root. The Swift app is entirely unprivileged and communicates
with sixnetd via a Unix socket. No repeated auth dialogs after first launch.

## Related

- [sixnet](https://github.com/Mr-Chance-Productions-GmbH/sixnet) — the server-side stack
- [sixnetd](https://github.com/Mr-Chance-Productions-GmbH/sixnetd) — the privileged daemon
- `vpn/zt` in the sixnet repo — the bash reference implementation this app replaces
