# FAQ

## Storage permission keeps failing
- Run: `termux-setup-storage`
- If Android still refuses, check **App info → Permissions → Files and media** and allow it.

## `apt update` says “Release file is not valid yet”
- Your device date/time may be wrong. Enable **Automatic date & time** in Android settings.

## Signature / key errors
- In the menu choose **Fix repo keyring**.

## Termux from Play Store?
- The Play Store version is deprecated. Prefer the official releases from F-Droid/GitHub.
  (This project doesn't install Termux for you; it only helps fix common issues.)

## Does the Tailscale setup cost anything?
- No. It uses the free Tailscale Personal plan (3 users / 100 devices), ACLs/grants,
  MagicDNS, and OpenSSH. It does not enable Funnel, exit nodes, subnet routes, or any
  paid add-on. Carrier data charges still apply to your mobile/Wi-Fi connection.

## SSH says "Permission denied (publickey)"
- Password login is disabled by design. Add your client public key with
  `./fix.sh --tailscale --add-key <file>` (or `--generate-key`).
- Confirm the username is the Termux user (`whoami`, usually `u0_a282`) and the
  custom port, e.g. `ssh -p 22022 u0_a282@redmi-13c.tailxxxx.ts.net`.

## Can I still ping the phone?
- Android does not allow non-root apps to ignore ICMP. Use the free TCP-only
  Tailscale grant from `./tools/tailscale.sh --zero-trust`; root users can opt in
  to `--ping-root`.

## Is remote screen control included?
- No. This setup exposes shell-only SSH. Do not add VNC/scrcpy/RustDesk/TeamViewer.
  See the zero-click and screen/UI checklists in `docs/TAILSCALE.md`.
