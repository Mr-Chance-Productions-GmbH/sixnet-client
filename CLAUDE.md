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

**Distribution — .dmg, no App Store.**
Ad-hoc signed (no Apple Developer Program). Users allow "unidentified developer"
on first launch. Notarization / Developer ID can be added later without code changes.

**Privileged operations — NSAppleScript with administrator privileges.**
No SMAppService helper daemon (requires paid Apple enrollment + Team ID).
Standard macOS auth dialog on connect. Simple, battle-tested, works without a
Developer account.

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
