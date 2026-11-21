# 🛠️ Termux-Fixer

One script to fix common Termux headaches: storage permissions, repo/key issues, broken updates, and essential setup.

> **Version:** 2.2.0

## ✅ What it can do

### Fix & repair
- **Storage setup** (`termux-setup-storage`) with correct detection.
- **Repo/keyring repair** for common signature / GPG issues.
- **Repo repair fallback** for common update failures (cache/list reset + clock validity workaround).
- **Apt lists reset** (safe) and **Hash Sum mismatch** recovery.
- **Broken packages** routine (`apt --fix-broken`, `dpkg --configure -a`).
- **Cache cleanup** to recover from stuck installs.

### Setup & convenience
- **Install profiles** (Minimal / Full) for a clean baseline.
- **Quality-of-life tweaks** (safe `.bashrc` additions only).
- **Diagnostics report** you can attach to GitHub issues.
- **Repo status** helper (prints your current sources so others can help faster).
- **Backup/restore** helpers for your Termux config.
- **Tailscale remote SSH** (free plan): custom port + Tailscale-only address,
  key-only auth, brute-force/netcat throttling, ping/scanner hardening, and a
  zero-trust policy generator.

## ⚠️ Safety notes
- This project avoids destructive operations by default.
- It does **not** delete your files.
- Always read the prompts—Android may request storage permission.

## 🚀 Quick install

```bash
pkg update -y && pkg install git -y

git clone https://github.com/Niranj-coder/Termux-fixer
cd Termux-fixer
chmod +x fix.sh
./fix.sh
```

## 🧰 CLI usage

```bash
./fix.sh --auto                  # Full Auto Fix
./fix.sh --profile minimal       # Run fixes then install Minimal profile
./fix.sh --profile full          # Run fixes then install Full profile
./fix.sh --no-tweaks             # Skip bashrc tweaks
./fix.sh --repo-status           # Print repo sources and exit
./fix.sh --diagnose              # Create report and exit
./fix.sh --tailscale             # Secure SSH over Tailscale (free plan)
./fix.sh --tailscale-status      # Tailscale SSH security status
./fix.sh --zero-trust            # Generate free zero-trust Tailscale policy
./fix.sh --zero-click            # Zero-click / screen-UI checklist
```

## 🔐 Secure remote access (Tailscale, free)

Use only the free Tailscale Personal plan; no Funnel, port forwarding, paid
relay, or add-on is enabled. Password auth is disabled and SSH is bound to the
Tailscale address only.

```bash
# On the client: copy the public key
cat ~/.ssh/id_ed25519.pub

# On the phone:
./fix.sh --tailscale --ssh-port 22022 \
  --ssh-hostname redmi-13c.tail505ac8.ts.net \
  --add-key /path/to/client.pub
```

Full guide: `docs/TAILSCALE.md`.

## 📄 Logs & reports
- Logs: `~/.termux-fixer/termux-fixer-*.log`
- Reports: `~/.termux-fixer/diagnose-*.txt`

## 📚 Docs
- `docs/QUICKSTART.md`
- `docs/FAQ.md`
- `docs/TAILSCALE.md`

## License
MIT (see `LICENSE`).
