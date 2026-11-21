#!/data/data/com.termux/files/usr/bin/bash
# shellcheck disable=SC2154
# Tailscale remote-access helpers for Termux-Fixer.
#
# Design notes:
# - Uses only features available on the Tailscale Personal (free) plan.
# - Never enables Funnel, exit nodes, or any paid add-on.
# - Password / keyboard-interactive SSH auth is disabled; keys only.
# - Android does not let apps bind only to the tun0 address, so sshd listens
#   on 0.0.0.0. Exposure is limited by key-only auth + Tailscale ACL/grants.

TF_SSH_DEFAULT_PORT="${TF_SSH_DEFAULT_PORT:-22022}"
TF_TS_STATE_DIR="${TF_LOG_DIR:-$HOME/.termux-fixer}"
TF_TS_DROPIN="$PREFIX/etc/ssh/sshd_config.d/99-tailscale-security.conf"
TF_TS_HOST_FILE="$TF_TS_STATE_DIR/tailscale-host"
TF_TS_PORT_FILE="$TF_TS_STATE_DIR/ssh-port"
TF_TS_ADDR_FILE="$TF_TS_STATE_DIR/ssh-address"
TF_TS_ADDR_MODE_FILE="$TF_TS_STATE_DIR/ssh-address-mode"
TF_TS_PID_FILE="$TF_TS_STATE_DIR/sshd.pid"
TF_SSH_AUTHORIZED_KEYS="$HOME/.ssh/authorized_keys"

tailscale_free_plan_notice() {
  say "${cyan}Cost check (Tailscale free plan):${reset}"
  say "  - Tailscale Personal is free: up to 3 users and 100 devices."
  say "  - No credit card, trial, or paid feature is required for this setup."
  say "  - Components used: WireGuard mesh, MagicDNS, ACL/grants, OpenSSH."
  say "  - NOT enabled: Funnel (public internet), exit nodes, paid relays, add-ons."
  say "  - Data used by your mobile/Wi-Fi connection is billed by your carrier, not Tailscale."
}

tailscale_installed() {
  have_cmd tailscale && return 0
  if have_cmd pm && pm list packages 2>/dev/null | grep -qx 'package:com.tailscale.ipn'; then
    return 0
  fi
  return 1
}

tailscale_ip() {
  local ip=""
  if have_cmd tailscale; then
    ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    [[ -n "$ip" ]] && { printf '%s\n' "$ip"; return 0; }
  fi
  ip="$(ifconfig tun0 2>/dev/null | awk '$1 == "inet" { print $2; exit }')"
  if [[ -z "$ip" ]]; then
    ip="$(ifconfig 2>/dev/null | awk '
      /^[[:alnum:]_.-]+:/ { iface=$1; sub(/:$/, "", iface); next }
      iface ~ /^tun/ && $1 == "inet" { print $2; exit }
    ')"
  fi
  [[ -n "$ip" ]] && printf '%s\n' "$ip"
}

tailscale_require_connected() {
  local ip
  ip="$(tailscale_ip || true)"
  if [[ -z "$ip" ]]; then
    err "Tailscale VPN interface was not found."
    warn "Open the Tailscale Android app, sign in, and turn the VPN on."
    return 1
  fi
  mkdir -p "$TF_TS_STATE_DIR"
  printf '%s\n' "$ip" > "$TF_TS_STATE_DIR/last-tailscale-ip"
  ok "Tailscale is active: $ip"
}

tailscale_hostname() {
  local h=""
  if [[ -f "$TF_TS_HOST_FILE" ]]; then
    h="$(head -n1 "$TF_TS_HOST_FILE" 2>/dev/null || true)"
  fi
  if [[ -z "$h" ]] && have_cmd tailscale; then
    h="$(tailscale status --json 2>/dev/null \
      | sed -n 's/.*"DNSName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      | head -n1 || true)"
  fi
  [[ -n "$h" ]] && printf '%s\n' "${h%.}"
}

tailscale_set_hostname() {
  local h="${1:-}"
  [[ -n "$h" ]] || return 0
  mkdir -p "$TF_TS_STATE_DIR"
  printf '%s\n' "$h" > "$TF_TS_HOST_FILE"
  chmod 600 "$TF_TS_HOST_FILE"
}

ssh_port_valid() {
  local port="${1:-}"
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  (( 10#$port >= 1024 && 10#$port <= 65535 ))
}

ssh_address_valid() {
  local addr="${1:-}"
  [[ -n "$addr" ]] || return 1
  [[ "$addr" =~ ^[A-Za-z0-9:.%_-]+$ ]]
}

tailscale_ssh_address() {
  local mode="" fixed=""
  [[ -f "$TF_TS_ADDR_MODE_FILE" ]] && mode="$(head -n1 "$TF_TS_ADDR_MODE_FILE" 2>/dev/null || true)"
  [[ -f "$TF_TS_ADDR_FILE" ]] && fixed="$(head -n1 "$TF_TS_ADDR_FILE" 2>/dev/null || true)"
  if [[ "$mode" == "fixed" && -n "$fixed" ]]; then
    printf '%s\n' "$fixed"
    return 0
  fi
  tailscale_ip
}

ssh_keys_present() {
  [[ -s "$TF_SSH_AUTHORIZED_KEYS" ]] \
    && grep -qE '^(ssh-|ecdsa-|sk-ssh-|sk-ecdsa-)' "$TF_SSH_AUTHORIZED_KEYS" 2>/dev/null
}

ssh_validate_pubkey() {
  local file="$1"
  [[ -s "$file" ]] || return 1
  ssh-keygen -l -f "$file" >/dev/null 2>&1
}

ssh_add_pubkey_file() {
  local src="$1" tmp=""
  [[ -n "$src" ]] || { err "No public key file given."; return 1; }

  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ "$src" == "-" ]]; then
    tmp="$(mktemp)"
    cat > "$tmp"
    src="$tmp"
  fi

  if ! ssh_validate_pubkey "$src"; then
    err "Not a valid SSH public key: $src"
    [[ -n "$tmp" ]] && rm -f "$tmp"
    return 1
  fi

  touch "$TF_SSH_AUTHORIZED_KEYS"
  chmod 600 "$TF_SSH_AUTHORIZED_KEYS"

  local line added=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    if grep -qF -- "$line" "$TF_SSH_AUTHORIZED_KEYS" 2>/dev/null; then
      ok "Public key already trusted."
    else
      printf '%s\n' "$line" >> "$TF_SSH_AUTHORIZED_KEYS"
      added=1
    fi
  done < "$src"

  [[ -n "$tmp" ]] && rm -f "$tmp"
  [[ $added -eq 1 ]] && ok "Public key added to $TF_SSH_AUTHORIZED_KEYS."
  return 0
}

ssh_generate_keypair() {
  local key="$HOME/.ssh/id_ed25519_tailscale"
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"

  if [[ ! -f "$key" ]]; then
    ssh-keygen -t ed25519 -a 100 -N '' \
      -C "termux-tailscale@$(hostname 2>/dev/null || echo termux)" \
      -f "$key"
  else
    warn "Reusing existing key: $key"
  fi

  ssh_add_pubkey_file "$key.pub" || return 1
  say "Private key: ${bold}$key${reset}"
  warn "Move that private key to your client securely, or replace it with the client's own public key."
}

ssh_harden_config() {
  local port="$1"
  local dir bak="" errfile
  dir="$(dirname "$TF_TS_DROPIN")"
  errfile="$TF_TS_STATE_DIR/sshd-test.err"
  mkdir -p "$dir" "$TF_TS_STATE_DIR"

  if [[ -f "$TF_TS_DROPIN" ]]; then
    bak="$TF_TS_DROPIN.bak.$(date +%Y%m%d-%H%M%S)"
    cp -a "$TF_TS_DROPIN" "$bak"
  fi

  cat > "$TF_TS_DROPIN" <<EOF
# Managed by Termux-Fixer -- Tailscale-only SSH.
# Password and keyboard-interactive auth are disabled; public keys only.
Port $port
AddressFamily inet
# Loopback is safe. The custom Tailnet address is added at start time with
# "sshd -o ListenAddress=<addr>" so this never exposes the LAN interface.
ListenAddress 127.0.0.1
PidFile $TF_TS_PID_FILE
PubkeyAuthentication yes
AuthenticationMethods publickey
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitEmptyPasswords no
PermitRootLogin no
AllowUsers $(whoami)
MaxAuthTries 3
MaxSessions 2
MaxStartups 5:30:10
PerSourceMaxStartups 2
PerSourcePenalties crash:90s authfail:5m noauth:1m invaliduser:5m grace-exceeded:1m refuseconnection:1m max:10m min:15s
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2
PermitUserEnvironment no
HostbasedAuthentication no
IgnoreRhosts yes
DisableForwarding yes
AllowAgentForwarding no
AllowTcpForwarding no
X11Forwarding no
PermitTunnel no
GatewayPorts no
UseDNS no
PrintMotd no
PrintLastLog no
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr
LogLevel VERBOSE
EOF
  chmod 600 "$TF_TS_DROPIN"

  if ! sshd -t 2>"$errfile"; then
    err "sshd rejected the hardened config; rolling back."
    sed 's/^/    /' "$errfile" 2>/dev/null || true
    rm -f "$TF_TS_DROPIN"
    [[ -n "$bak" ]] && cp -a "$bak" "$TF_TS_DROPIN"
    return 1
  fi

  printf '%s\n' "$port" > "$TF_TS_PORT_FILE"
  ok "Hardened sshd config written: $TF_TS_DROPIN"
  ok "Custom SSH port: $port (password auth disabled)."
}

sshd_managed_pid() {
  local pid="" cmd=""
  [[ -f "$TF_TS_PID_FILE" ]] && pid="$(head -n1 "$TF_TS_PID_FILE" 2>/dev/null || true)"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
  if [[ -n "$cmd" ]] && [[ "$cmd" != *sshd* ]]; then
    return 1
  fi
  printf '%s\n' "$pid"
}

ssh_stop_managed() {
  local pid
  pid="$(sshd_managed_pid || true)"
  if [[ -n "$pid" ]]; then
    info "Stopping managed sshd (pid $pid)…"
    kill "$pid" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -9 "$pid" 2>/dev/null || true
  fi
  rm -f "$TF_TS_PID_FILE"
}

ssh_read_banner() {
  local host="$1" port="$2"
  [[ "$host" =~ ^[A-Za-z0-9:.%_-]+$ ]] || return 1
  [[ "$port" =~ ^[0-9]+$ ]] || return 1
  timeout 4 bash -c \
    'exec 3<>/dev/tcp/'"$host"'/'"$port"' 2>/dev/null; IFS= read -r -t 2 line <&3; printf "%s" "$line"' \
    2>/dev/null || true
}

ssh_selftest() {
  local port="$1" ip="${2:-}" banner rc=0

  banner="$(ssh_read_banner 127.0.0.1 "$port")"
  if [[ "$banner" == SSH-2.0-* ]]; then
    ok "Loopback SSH check passed (127.0.0.1:$port)."
  else
    warn "Loopback SSH check failed on port $port."
    rc=1
  fi

  if [[ -n "$ip" ]]; then
    banner="$(ssh_read_banner "$ip" "$port")"
    if [[ "$banner" == SSH-2.0-* ]]; then
      ok "Tailscale SSH check passed ($ip:$port)."
    else
      warn "Tailscale SSH check failed ($ip:$port)."
      rc=1
    fi
  fi
  return "$rc"
}

ssh_start_managed() {
  local port="$1" addr="${2:-}"
  mkdir -p "$PREFIX/var/run" "$TF_TS_STATE_DIR"
  ssh_stop_managed

  if [[ -n "$(ssh_read_banner 127.0.0.1 "$port")" ]]; then
    err "Port $port is already in use by another service on loopback."
    warn "Pick a different custom port with --port <1024-65535>."
    return 1
  fi
  if [[ -n "$addr" && "$addr" != "127.0.0.1" && -n "$(ssh_read_banner "$addr" "$port")" ]]; then
    err "Port $port is already in use on $addr."
    warn "Pick a different custom port with --port <1024-65535>."
    return 1
  fi

  local -a args=()
  [[ -n "$addr" ]] && args+=(-o "ListenAddress=$addr")

  if ! sshd "${args[@]}" 2>"$TF_TS_STATE_DIR/sshd-start.err"; then
    err "sshd failed to start."
    sed 's/^/    /' "$TF_TS_STATE_DIR/sshd-start.err" 2>/dev/null || true
    return 1
  fi

  for _ in 1 2 3 4 5; do
    [[ -n "$(sshd_managed_pid || true)" ]] && break
    sleep 1
  done
  if [[ -z "$(sshd_managed_pid || true)" ]]; then
    err "sshd did not stay running."
    sed 's/^/    /' "$TF_TS_STATE_DIR/sshd-start.err" 2>/dev/null || true
    return 1
  fi

  ok "sshd is running on port $port (pid $(sshd_managed_pid))."
  [[ -n "$addr" ]] && ok "Listening only on 127.0.0.1 and $addr."
}

tailscale_install_boot_hook() {
  local bootdir="$HOME/.termux/boot"
  local script="$bootdir/50-sshd.sh"

  if ! have_cmd pm || ! pm list packages 2>/dev/null | grep -qx 'package:com.termux.boot'; then
    warn "Termux:Boot is not installed."
    warn "SSH stops when Termux is fully closed/rebooted. Install Termux:Boot (free, F-Droid), open it once, then re-run this option."
    return 0
  fi

  mkdir -p "$bootdir"
  cat > "$script" <<'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Managed by Termux-Fixer. Bind SSH to the current Tailscale address only.
STATE="$HOME/.termux-fixer"
if [ -f "$STATE/sshd.pid" ] && kill -0 "$(head -n1 "$STATE/sshd.pid" 2>/dev/null)" 2>/dev/null; then
  exit 0
fi

addr=""
mode=""
fixed=""
[ -f "$STATE/ssh-address-mode" ] && mode="$(head -n1 "$STATE/ssh-address-mode" 2>/dev/null)"
[ -f "$STATE/ssh-address" ] && fixed="$(head -n1 "$STATE/ssh-address" 2>/dev/null)"

i=0
while [ "$i" -lt 30 ]; do
  if [ "$mode" = "fixed" ] && [ -n "$fixed" ]; then
    addr="$fixed"
  else
    addr="$(ifconfig 2>/dev/null | awk '
      /^[[:alnum:]_.-]+:/ { iface=$1; sub(/:$/, "", iface); next }
      iface ~ /^tun/ && $1 == "inet" { print $2; exit }
    ')"
  fi
  [ -n "$addr" ] && break
  sleep 2
  i=$((i + 1))
done

if [ -n "$addr" ]; then
  sshd -o "ListenAddress=$addr" && exit 0
fi
sshd
EOF
  chmod +x "$script"
  ok "Boot hook installed: $script"
}

ping_hardening() {
  info "Reducing ICMP/ping exposure…"
  local k path applied=0
  for k in net.ipv4.icmp_echo_ignore_all net.ipv4.icmp_echo_ignore_broadcasts; do
    path="/proc/sys/${k//./\/}"
    if printf '1\n' > "$path" 2>/dev/null; then
      applied=1
    fi
  done

  if [[ $applied -eq 1 ]]; then
    ok "ICMP echo ignored at the kernel level."
  else
    warn "Android blocks ICMP sysctl for non-root apps."
    warn "Use the free Tailscale grant below (TCP-only) to stop tailnet pings."
  fi

  if [[ "${TF_PING_ROOT:-0}" == "1" ]]; then
    if have_cmd su; then
      info "Applying kernel ICMP hardening with root (opt-in)…"
      su -c 'sysctl -w net.ipv4.icmp_echo_ignore_all=1 >/dev/null 2>&1; sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 >/dev/null 2>&1' \
        || warn "Root ICMP command failed."
    else
      warn "su not found; cannot apply root ICMP hardening."
    fi
  fi
}

zero_click_advice() {
  info "Zero-click attack hardening (Android / messaging layer):"
  say "  - Install Android security updates and reboot; check Settings > About > Android version."
  say "  - Update Tailscale, Termux, OpenSSH, and all messaging apps."
  say "  - Disable auto-download for photos/audio/video/documents in WhatsApp, Telegram, Signal, etc."
  say "  - Disable link previews, MMS auto-retrieve, and RCS if you do not need them."
  say "  - Use an end-to-end encrypted messenger; block unknown senders and unknown group invites."
  say "  - Keep Bluetooth, NFC, Nearby/Quick Share, and Wi-Fi auto-connect off when idle."
  say "  - Enable Google Play Protect; never sideload APKs or run scripts from chat links."
  say "  - In Termux: never run 'curl | bash', pasted tokens, or one-line scripts from messages."
  say "  - No remote shell setup can stop a baseband/messaging exploit; patching is the real fix."

  local patch
  patch="$(getprop ro.build.version.security_patch 2>/dev/null || true)"
  if [[ -n "$patch" ]]; then
    say "  - Android security patch level reported: $patch"
  else
    warn "Could not read the Android security patch level; check Settings manually."
  fi
}

tailscale_exposure_notice() {
  say "${cyan}Scanner / IP exposure:${reset}"
  say "  - sshd binds to loopback + the Tailscale address only (not 0.0.0.0)."
  say "  - LAN and public scanners cannot reach the SSH port."
  say "  - Tailscale IPs are private to your tailnet; nothing is port-forwarded."
  say "  - No Funnel, no subnet routes, no exit node: the device is not advertised publicly."
  say "  - A TCP-only grant also stops tailnet ICMP/ping from other nodes."
  say "  - key-only auth + MaxAuthTries 3 + PerSourcePenalties blunt netcat/brute-force probing."
  say "  - Forwarding, agent, X11, and tunnels are disabled, so a shell cannot be reused as a pivot."
}

ui_attack_advice() {
  info "Screen/UI attack hardening (Android-level; Termux cannot change these):"
  say "  - Use a strong lock screen PIN/password and a short auto-lock timeout."
  say "  - Hide sensitive notification content on the lock screen."
  say "  - Remove 'Display over other apps' permission from untrusted apps (tapjacking/overlays)."
  say "  - Disable accessibility services you do not recognize."
  say "  - Turn off USB debugging and Wireless debugging when not needed."
  say "  - Do not use VNC/scrcpy/RustDesk/TeamViewer for this setup; it is shell-only."
  say "  - Keep 'Install unknown apps' disabled for browsers and messaging apps."

  local dbg wd
  dbg="$(getprop ro.debuggable 2>/dev/null || true)"
  [[ "$dbg" == "1" ]] && warn "ro.debuggable=1: this is a debug build; treat it as less trustworthy."
  wd="$(getprop service.adb.tcp.port 2>/dev/null || true)"
  if [[ -n "$wd" && "$wd" != "-1" ]]; then
    warn "Wireless ADB appears enabled on port $wd. Disable it when not in use."
  fi
  if have_cmd pm && pm list packages 2>/dev/null \
      | grep -qiE 'com\.teamviewer|com\.anydesk|com\.rustdesk|com\.vmlite|com\.genymotion|scrcpy'; then
    warn "A remote-desktop/automation app is installed. Review whether it can view or control the screen."
  fi
}

tailscale_print_policy_example() {
  local host="${1:-}" port="${2:-$TF_SSH_DEFAULT_PORT}" ip="${3:-}"
  [[ -n "$ip" ]] || ip="$(tailscale_ip || true)"
  ip="${ip:-100.x.y.z}"
  mkdir -p "$TF_TS_STATE_DIR"

  local out="$TF_TS_STATE_DIR/tailscale-zero-trust.json"
  cat > "$out" <<EOF
// Tailscale zero-trust policy -- free plan (grants/ACLs are included).
// Admin console -> Access controls -> replace the allow-all policy, then Save.
// WARNING: any "grants" section makes the tailnet deny-by-default.
// Add grants for any other device/service you still need. Never add "* -> *".
{
  "hosts": {
    "phone": "$ip"
  },
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["phone"],
      "ip": ["tcp:$port"]
    }
  ],
  // Tighten src to "you@example.com" or "group:admins" if your tailnet has other users.
  // Optional tests: replace you@example.com with your Tailscale login and uncomment.
  // "tests": [
  //   { "src": "you@example.com", "accept": ["phone:$port"] },
  //   { "src": "you@example.com", "proto": "icmp", "deny": ["phone:0"] }
  // ]
}
EOF

  cat "$out"
  say ""
  ok "Zero-trust policy saved: $out"
  say "Device: ${host:-phone} ($ip). Only TCP/$port is granted; ICMP, UDP, and all other ports are denied."
  say "This policy uses free features only (Tailscale Personal, ACLs/grants, MagicDNS)."
}

tailscale_next_steps() {
  local ip="${1:-}" host="${2:-}" port="${3:-$TF_SSH_DEFAULT_PORT}"
  local user; user="$(whoami)"
  local target="${host:-<magicdns-name>}"

  say ""
  say "${bold}Connect from another Tailscale device:${reset}"
  say "  ssh -p $port $user@$target"
  [[ -n "$ip" ]] && say "  ssh -p $port $user@$ip"
  say ""
  say "Only installed public keys can log in. Password login is disabled."
  say "Free-plan reminder: no Funnel, no port forwarding, no paid relay."
  say "Ping hardening: run './tools/tailscale.sh --policy-example' and add the grant in the Tailscale admin console."
  say "Status: ./tools/tailscale.sh --status"
  say ""
  tailscale_exposure_notice
}

tailscale_secure_setup() {
  local port="${1:-$TF_SSH_DEFAULT_PORT}"
  local host="${2:-}"
  local key="${3:-}"
  local generate="${4:-0}"
  local root_ping="${5:-0}"
  local addr="${6:-}"

  tailscale_free_plan_notice
  if ! tailscale_installed; then
    err "Tailscale is not installed."
    warn "Install the official Tailscale app (free) from Play Store or F-Droid, sign in, then retry."
    return 1
  fi
  tailscale_require_connected || return 1

  if ! ssh_port_valid "$port"; then
    err "Invalid port: $port (use 1024-65535)."
    return 1
  fi

  mkdir -p "$TF_TS_STATE_DIR"
  if [[ -n "$addr" && "$addr" != "auto" ]]; then
    if ! ssh_address_valid "$addr"; then
      err "Invalid listen address: $addr"
      return 1
    fi
    printf '%s\n' "$addr" > "$TF_TS_ADDR_FILE"
    printf 'fixed\n' > "$TF_TS_ADDR_MODE_FILE"
  else
    addr="$(tailscale_ip || true)"
    printf 'auto\n' > "$TF_TS_ADDR_MODE_FILE"
    if [[ -n "$addr" ]]; then
      printf '%s\n' "$addr" > "$TF_TS_ADDR_FILE"
    else
      rm -f "$TF_TS_ADDR_FILE"
      warn "No Tailscale IPv4 address found; sshd will bind loopback only."
    fi
  fi

  tailscale_set_hostname "$host"

  [[ -n "$key" ]] && { ssh_add_pubkey_file "$key" || return 1; }
  [[ "$generate" == "1" ]] && { ssh_generate_keypair || return 1; }

  if ! ssh_keys_present; then
    err "No SSH public key in $TF_SSH_AUTHORIZED_KEYS."
    err "Password auth will be disabled, so a key is mandatory."
    err "Add one: ./tools/tailscale.sh --add-key <file>   (or --generate-key)"
    return 1
  fi

  ssh_harden_config "$port" || return 1
  ssh_start_managed "$port" "$addr" || return 1
  ssh_selftest "$port" "$addr" || return 1

  tailscale_install_boot_hook
  if [[ "$root_ping" == "1" ]]; then
    TF_PING_ROOT=1 ping_hardening
  else
    ping_hardening
  fi

  ui_attack_advice
  zero_click_advice
  tailscale_next_steps "$addr" "$host" "$port"
  ok "Secure Tailscale SSH is ready."
}

tailscale_interactive() {
  tailscale_free_plan_notice
  tailscale_installed || {
    warn "Install the official Tailscale app (free) and sign in first."
    return 1
  }

  local port addr host key gen=0 detected saved_host yn
  read -r -p "Custom SSH port [$TF_SSH_DEFAULT_PORT]: " port
  port="${port:-$TF_SSH_DEFAULT_PORT}"
  if ! ssh_port_valid "$port"; then
    err "Invalid port: $port (use 1024-65535)."
    return 1
  fi

  detected="$(tailscale_ip || true)"
  read -r -p "Listen address (Tailscale IP) [${detected:-auto}]: " addr
  addr="${addr:-${detected:-auto}}"

  saved_host="$(tailscale_hostname || true)"
  read -r -p "MagicDNS name (e.g. redmi-13c.tailxxxx.ts.net) [$saved_host]: " host
  host="${host:-$saved_host}"

  if ! ssh_keys_present; then
    read -r -p "Path to client public key (leave empty to generate a keypair here): " key
    [[ -z "$key" ]] && gen=1
  fi

  read -r -p "Disable password auth and start sshd now? [y/N] " yn
  if [[ ! "$yn" =~ ^[Yy]$ ]]; then
    warn "Cancelled; nothing changed."
    return 0
  fi

  tailscale_secure_setup "$port" "$host" "$key" "$gen" 0 "$addr"
}

tailscale_status() {
  local ip="" host="" port="" addr="" mode="" key_count="0"
  tailscale_free_plan_notice
  hr
  if tailscale_installed; then
    ok "Tailscale app/CLI detected."
  else
    warn "Tailscale not detected."
  fi

  ip="$(tailscale_ip || true)"
  host="$(tailscale_hostname || true)"
  [[ -n "$ip" ]] && ok "Tailscale IP: $ip" || warn "Tailscale VPN is not connected."
  [[ -n "$host" ]] && ok "MagicDNS name: $host" || warn "MagicDNS name not saved (run setup with --hostname)."

  if [[ -f "$TF_TS_PORT_FILE" ]]; then
    port="$(head -n1 "$TF_TS_PORT_FILE" 2>/dev/null || true)"
  fi
  port="${port:-$TF_SSH_DEFAULT_PORT}"

  [[ -f "$TF_TS_ADDR_FILE" ]] && addr="$(head -n1 "$TF_TS_ADDR_FILE" 2>/dev/null || true)"
  [[ -f "$TF_TS_ADDR_MODE_FILE" ]] && mode="$(head -n1 "$TF_TS_ADDR_MODE_FILE" 2>/dev/null || true)"
  if [[ -n "$addr" ]]; then
    ok "SSH listen address: $addr (mode: ${mode:-unknown}) + 127.0.0.1"
  else
    warn "No saved SSH listen address; sshd would bind loopback only."
  fi

  if [[ -n "$(sshd_managed_pid || true)" ]]; then
    ok "sshd running (pid $(sshd_managed_pid)) on port $port."
  else
    warn "Managed sshd is not running."
  fi

  if ssh_keys_present; then
    key_count="$(grep -cE '^(ssh-|ecdsa-|sk-ssh-|sk-ecdsa-)' "$TF_SSH_AUTHORIZED_KEYS" 2>/dev/null || true)"
    key_count="${key_count:-0}"
    ok "Authorized keys installed: $key_count"
  else
    warn "No authorized public keys installed."
  fi

  if [[ -f "$TF_TS_DROPIN" ]]; then
    ok "Hardened config: $TF_TS_DROPIN"
    say "${gray}Effective sshd settings:${reset}"
    sshd -T 2>/dev/null | awk '
      {
        k = tolower($1)
        if (k == "port" || k == "listenaddress" || k == "passwordauthentication" ||
            k == "kbdinteractiveauthentication" || k == "pubkeyauthentication" ||
            k == "authenticationmethods" || k == "permitrootlogin" || k == "allowusers" ||
            k == "maxauthtries" || k == "maxstartups" || k == "persourcemaxstartups" ||
            k == "persourcepenalties" || k == "disableforwarding" || k == "allowtcpforwarding" ||
            k == "x11forwarding" || k == "permittunnel") {
          print "  " $0
        }
      }'
  else
    warn "Hardened config not found; run setup first."
  fi

  say ""
  tailscale_exposure_notice
  say ""
  say "Ping/ICMP: ${yellow}Android cannot ignore ICMP without root.${reset}"
  say "Use a TCP-only Tailscale grant: ./tools/tailscale.sh --policy-example"
  say ""
  ui_attack_advice
  say ""
  zero_click_advice
}
