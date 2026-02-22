# Claude Briefing - sixnet-client

## What is this repo?

End-user client app for sixnet — a self-hosted VPN platform built on ZeroTier.
This client is the missing piece between the server-side sixnet stack and real users
who should never need a terminal.

## The Core Stack (~/projects/six.net)

sixnet runs ZeroTier as a self-hosted VPN controller, with Authentik for identity,
Caddy for reverse proxy, and dnsmasq for VPN-internal DNS. It is deployed as a
Docker stack, managed by an admin.

**What exists and works today:**

- ZeroTier network controller (self-hosted, not ZeroTier Central)
- Enrollment portal at `enroll.<domain>` — web-based, Authentik-authenticated
  Users visit it in a browser, paste their ZeroTier node address, get authorized
- Node DNS: authorized nodes get `<name>.<network>.zt` hostnames automatically
  e.g. `qnap-host.q1.zt → 10.147.20.169`
- `vpn/zt` — bash client wrapper (the reference implementation this app replaces)
- `vpn/zt-admin` — admin tooling (not relevant to this repo)

**How the client flow works today (bash):**

```
1. User installs ZeroTier (standard installer from zerotier.com)
2. echo "NETWORK_ID" > ~/.zt-network
3. zt join        → zerotier-cli join <nwid>, shows ZT address
4. User visits enrollment portal in browser, pastes address
5. Admin authorizes (zt-admin authorize <node>)
6. zt up          → sets allowDNS=1, allowManaged=1
                  → creates /etc/resolver/<domain> on macOS
                  → connects to VPN
7. zt down        → removes /etc/resolver/<domain>, leaves network
```

**Connection modes** (from `vpn/zt`):
- `up`       — ZeroTier devices only (10.147.20.x)
- `up lan`   — + LAN network access via gateway (13.3.24.x)
- `up exit`  — + route all internet through gateway

**DNS mechanics:**
- ZeroTier network has `dns.domain=q1.zt`, `dns.servers=[10.147.20.60]` pushed from controller
- Client sets `allowDNS=true` via zerotier-cli
- On macOS: client creates `/etc/resolver/q1.zt` (ZeroTier homebrew daemon doesn't do this)
- macOS resolves via mDNSResponder — `dig` won't show it, but ping/ssh/dns-sd work
- The network name (`q1`) comes from the deployment, configured once by admin

**Key ZeroTier CLI operations the client wraps:**
```bash
sudo zerotier-cli join <nwid>
sudo zerotier-cli leave <nwid>
sudo zerotier-cli set <nwid> allowDNS=true
sudo zerotier-cli set <nwid> allowManaged=true
sudo zerotier-cli set <nwid> allowGlobal=true      # for lan mode
sudo zerotier-cli set <nwid> allowDefault=true     # for exit mode
sudo zerotier-cli listnetworks
sudo zerotier-cli info
```

Local ZeroTier API (HTTP on port 9993, authtoken at `/var/lib/zerotier-one/authtoken.secret`):
- `GET /network/<nwid>` — full network state including DNS config, assigned IP, status

## Client Scope

**What the client does (generic, not Q1-specific):**

1. **Prerequisites check** — is ZeroTier installed? is the daemon running?
   Guide user to install if not (zerotier.com/download, standard installer)

2. **Onboarding** — network ID configuration (the one deployment-specific input),
   join network, open enrollment portal in browser, show ZT address to copy

3. **Connection management** — up/down, mode selection (VPN / LAN / exit),
   DNS resolver setup, status display

4. **State awareness** — authorized yet? connected? which mode? assigned IP?

**What it does NOT do:**
- Wrap the ZeroTier installer (users install ZeroTier themselves)
- Admin operations (that's zt-admin in the core repo)
- Anything deployment-specific beyond knowing the network ID + enrollment URL

**Configuration** (minimal, provided by admin to user):
- Network ID (e.g. `31655f6ec3a15f6d`)
- Enrollment URL (e.g. `https://enroll.v1.vertamob.com`)
- Optionally: network name for display (e.g. "Q1 Office VPN")

## Decisions

**Tech stack — Swift/SwiftUI, native macOS menu bar app.**
Chose native over cross-platform (Tauri, Wails, KMP) to avoid integration friction
with the menu bar. Swift is close enough to Kotlin to be learnable without pain.
Cross-platform (Linux, Windows) explicitly deferred — would be a separate effort.

**Form factor — menu bar app (MenuBarExtra, .window style).**
Status visible at a glance, connect/disconnect without opening a full window.

**Distribution — Homebrew Cask.**
`brew install --cask Mr-Chance-Productions-GmbH/sixnet/sixnet-client`
This installs the .app and the sixnetd daemon (as a formula dependency) in one
command. Homebrew Cask bypasses Gatekeeper automatically — no "unidentified
developer" dialog. No Apple Developer account required.

Uninstall is equally clean: `brew uninstall --cask sixnet-client && brew uninstall sixnetd`.

**Privileged operations — via sixnetd daemon.**
The Swift app never calls zerotier-cli directly. All privileged operations and
ZeroTier state reading go through the sixnetd daemon over a Unix socket.

**Daemon architecture — sixnetd, written in Go, separate repo.**
See `~/projects/sixnetd` and https://github.com/Mr-Chance-Productions-GmbH/sixnetd

The layer stack:
```
ZeroTier daemon
    ↓
zerotier-cli + ZeroTier HTTP API on :9993   ← ZeroTier layer
    ↓
sixnetd (Go daemon, Unix socket)            ← all business logic + sudo
    /var/run/sixnetd.sock
    ↓
SixnetClient Swift app                      ← pure UI, no privileged ops
```

sixnetd is the single source of truth for all ZeroTier operations:
- Reads authtoken at startup (runs as root, no repeated auth dialogs)
- Manages join/leave, DNS resolver setup, connection modes
- Exposes a JSON protocol over a Unix socket
- vpn/zt bash wrapper will eventually be rewritten to talk to sixnetd too

sixnetd is independent of macOS — same Go binary runs on Linux (different
packaging). The macOS LaunchDaemon install is macOS-specific; the code is not.

**Daemon packaging — Homebrew formula, not bundled in the .app.**
The sixnetd binary is installed separately by Homebrew as a formula dependency
of the sixnet-client cask. The Swift app does not bundle or install sixnetd itself.

**First-launch flow:**
1. App checks if `/var/run/sixnetd.sock` is alive (daemon running)
2. If not: show one-time setup screen, explain what's happening
3. Run `brew services start sixnetd` via NSAppleScript — one admin dialog, ever
4. Daemon starts and is registered to auto-start at every boot
5. Normal app flow continues

**Mobile — future, additive, not a replacement.**
The sixnet server stack and enrollment flow are unchanged on any platform.
iOS would use a Network Extension, Android a VPNService — platform-specific
wrappers around the same concepts. sixnetd serves as the reference implementation
and protocol spec for any future platform daemon equivalent.

**Build artifacts — never on synced filesystems.**
`build/` in the project should be a symlink outside any cloud sync scope.
Convention: `mkdir-nosync build` (personal tooling, not part of this repo)
creates `~/.nosync/projects/sixnet-client/build` and symlinks it.
The Makefile uses `BUILD_DIR = build` and has no opinion on the machine layout.

## Immediate Driver

Enroll a small group of real users on Q1 deployment to access hosted apps
(Authentik, OpenProject, Jellyfin). They should not need a terminal.
This is the first real-world validation of the enrollment + client flow.

## Reference

Core repo: `~/projects/six.net`
- Client bash reference: `vpn/zt`
- Enrollment portal: `core/enroll/`
- Node docs: `vpn/NODES.md`
- Architecture: `docs/architecture/`
