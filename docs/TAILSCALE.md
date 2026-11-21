# Secure remote SSH with Tailscale (free plan)

This guide turns Termux into a private SSH host reachable only through your
Tailscale tailnet. It uses the **Tailscale Personal (free) plan** and no paid
features.

## Cost check: no hidden charges

- Tailscale Personal is free for up to **3 users / 100 devices**.
- No credit card or trial is required for this setup.
- ACLs/grants, MagicDNS, and WireGuard mesh are included on the free plan.
- This setup does **not** enable Funnel (public internet), exit nodes, subnet
  routes, paid relays, or any add-on.
- Mobile/Wi-Fi data used by your SSH session is billed by your carrier, not
  Tailscale.

## Requirements

1. Official **Tailscale** app (Play Store/F-Droid), signed in and VPN enabled.
2. Termux with `openssh` (installed by the Minimal profile).
3. Optional: **Termux:Boot** (free, F-Droid) to start sshd after reboot.
4. A public key from the device you will connect from.

## Get the client public key

On the client (laptop/other phone), run:

```bash
ssh-keygen -t ed25519 -C "my-client"
cat ~/.ssh/id_ed25519.pub
```

Copy the whole `ssh-ed25519 ...` line.

## Run the setup

```bash
./fix.sh --tailscale \
  --ssh-port 22022 \
  --ssh-hostname redmi-13c.tail505ac8.ts.net \
  --add-key /path/to/client.pub
```

Or use the menu: **15) Secure remote SSH over Tailscale (free)**.

If you do not have a client key yet, `--generate-key` creates one on the phone:

```bash
./fix.sh --tailscale --ssh-port 22022 --ssh-hostname redmi-13c.tail505ac8.ts.net --generate-key
```

Then move the private key (`~/.ssh/id_ed25519_tailscale`) to the client
securely, or replace it with the client's own public key later.

### Custom port and address

- Default port: **22022** (configurable with `--ssh-port`).
- Default listen address: the detected Tailscale IP (configurable with
  `--ssh-address`). `auto` follows the current Tailscale IP.
- sshd always also listens on `127.0.0.1` for local testing.
- It never binds `0.0.0.0`; LAN and public scanners cannot reach the SSH port.

If the Tailscale IP changes (reinstalling/re-auth), re-run the setup or use
`--ssh-address auto`.

## What gets hardened

Written to `$PREFIX/etc/ssh/sshd_config.d/99-tailscale-security.conf`:

- Password and keyboard-interactive auth: **disabled**.
- Public-key auth only (`AuthenticationMethods publickey`).
- Root login: **disabled**.
- Custom port + loopback/Tailscale-only listen address.
- `MaxAuthTries 3`, `MaxStartups 5:30:10`, `PerSourceMaxStartups 2`.
- `PerSourcePenalties` (built-in brute-force/netcat throttling).
- `DisableForwarding yes` (no TCP/agent/X11/tunnel pivoting).
- `MaxSessions 2`, short `LoginGraceTime`, keepalive limits.
- Modern MACs/ciphers; no weak legacy algorithms.

## Connect

From another Tailscale device:

```bash
ssh -p 22022 u0_a282@redmi-13c.tail505ac8.ts.net
```

If MagicDNS is not available on the client, use the Tailscale IP:

```bash
ssh -p 22022 u0_a282@100.100.148.50
```

Password login is disabled, so the matching private key must be on the client.

## Zero-trust policy (free)

Generate a deny-by-default policy:

```bash
./tools/tailscale.sh --zero-trust --port 22022 \
  --hostname redmi-13c.tail505ac8.ts.net
```

The file is saved to `~/.termux-fixer/tailscale-zero-trust.json`. Paste it into
**Tailscale admin console → Access controls**, replacing the default allow-all
policy, then **Save**.

The policy:

- Defines the phone by its Tailscale IP under `hosts`.
- Grants only `TCP/22022` from tailnet members to the phone.
- Does not grant ICMP, UDP, or any other port.
- Keeps you on free features only.

Warning: adding a `grants` section makes the tailnet deny-by-default. Add
grants for other devices/services you still need. Never add `* -> *`; broader
rules override narrower ones.

## Ping / ICMP

Android does not let normal apps ignore ICMP. The practical free fix is the
TCP-only grant above, which stops tailnet pings to the phone. Rooted devices
can opt in to kernel hardening:

```bash
./tools/tailscale.sh --setup --ping-root
```

## Netcat / scanner / brute-force probing

- Only keys are accepted; there is no password prompt to attack.
- The port is not exposed on LAN/public interfaces.
- Per-source penalties and low `MaxAuthTries` throttle probing.
- Forwarding and tunnels are disabled, so a shell cannot be used as a pivot.
- No Funnel or port forwarding means there is no public IP/port to scan.

## Screen/UI and zero-click attacks

Termux cannot change Android app permissions or baseband/messaging behavior.
Use the built-in checklist:

```bash
./tools/tailscale.sh --zero-click
./tools/tailscale.sh --screen-ui
```

Key points:

- Install Android security updates; keep Tailscale, Termux, OpenSSH, and
  messaging apps updated.
- Disable auto-download/link previews in messaging apps; disable MMS
  auto-retrieve and RCS if unused.
- Remove "Display over other apps" from untrusted apps; disable unknown
  accessibility services.
- Turn off Bluetooth/NFC/Nearby/Quick Share when idle.
- Disable USB debugging and Wireless debugging when not needed.
- Never run `curl | bash`, pasted tokens, or scripts received in chat.
- This SSH setup is shell-only; do not add VNC/scrcpy/RustDesk/TeamViewer.

No script can prevent a zero-click baseband or messaging exploit. Patching is
the real mitigation.

## Status and troubleshooting

```bash
./tools/tailscale.sh --status
./fix.sh --tailscale-status
```

- **Tailscale VPN is not connected**: open the app, sign in, enable VPN.
- **No keys**: add a client public key or use `--generate-key`.
- **Port in use**: choose another port with `--ssh-port`.
- **MagicDNS name fails on client**: use the Tailscale IP.
- **SSH stops after reboot**: install Termux:Boot, open it once, re-run setup.
- **Battery optimization kills Tailscale/Termux**: exempt both apps from
  Android battery optimization.

## Files

- Hardened config: `$PREFIX/etc/ssh/sshd_config.d/99-tailscale-security.conf`
- State: `~/.termux-fixer/` (`ssh-port`, `ssh-address`, `sshd.pid`, policy)
- Boot hook: `~/.termux/boot/50-sshd.sh` (only with Termux:Boot)
