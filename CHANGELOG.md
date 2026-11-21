# Changelog

## 2.2.0
- Added free Tailscale remote SSH setup: custom port, Tailscale-only listen
  address, key-only auth, no password login.
- Hardened sshd: per-source penalties, MaxStartups/MaxAuthTries limits,
  forwarding/agent/X11/tunnel disabled, modern MACs/ciphers.
- Added zero-trust Tailscale policy generator (TCP-only grant, deny ICMP/UDP).
- Added scanner/IP exposure, ping, netcat/brute-force, screen/UI, and zero-click
  hardening guidance.
- `init_logging` is now idempotent; cleaned profile installation.
- New flags: `--tailscale`, `--tailscale-status`, `--zero-trust`, `--zero-click`.
- Docs: added `docs/TAILSCALE.md`.

## 2.1.0
- Smarter update flow: internet check + repo repair fallback when `pkg update` fails
- Added safe apt list reset + Hash Sum mismatch recovery steps
- Added `--diagnose` and `--repo-status` CLI flags
- Expanded diagnose report (Android/device info, HTTP check, recent logs)
- Menu expanded with repo status + cache/list repair utilities

## 2.0.0
- New interactive menu + non-destructive fixes
- Proper storage detection (`$HOME/storage`)
- Keyring repair, broken-package routine, cache cleanup
- Install profiles (minimal/full)
- Diagnostics report generator
- Backup/restore helpers
- Logging to `~/.termux-fixer/`
