#!/data/data/com.termux/files/usr/bin/bash
# shellcheck disable=SC2034
# Common utilities for Termux-Fixer

set -Eeuo pipefail

TF_VERSION="2.2.0"
TF_APP_NAME="Termux-Fixer"

# ---------- UI ----------
_color() { printf "\033[%sm" "$1"; }
reset="$(_color 0)"
bold="$(_color 1)"
red="$(_color 31)"; green="$(_color 32)"; yellow="$(_color 33)"; blue="$(_color 34)"; magenta="$(_color 35)"; cyan="$(_color 36)"; gray="$(_color 90)"

say()  { printf "%b\n" "$*"; }
info() { say "${cyan}[*]${reset} $*"; }
ok()   { say "${green}[✔]${reset} $*"; }
warn() { say "${yellow}[!]${reset} $*"; }
err()  { say "${red}[x]${reset} $*"; }

hr()   { say "${gray}------------------------------------------------------------${reset}"; }

# ---------- Environment ----------
require_termux() {
  if [[ "${PREFIX:-}" != *"com.termux"* && "${HOME:-}" != *"/data/data/com.termux"* ]]; then
    warn "This script is designed for Termux. It may not work elsewhere."
  fi
}

require_tools() {
  local missing=()
  for c in "$@"; do
    have_cmd "$c" || missing+=("$c")
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    warn "Missing required tools: ${missing[*]}"
    warn "Attempting to install…"
    pkg install -y "${missing[@]}" || true
  fi
}

check_internet() {
  # Quick connectivity + DNS sanity check.
  # We avoid ping because Android/ISP may block ICMP.
  require_tools curl
  info "Checking internet connectivity…"
  if curl -fsSIL --max-time 8 https://packages.termux.dev >/dev/null 2>&1; then
    ok "Internet looks good."
    return 0
  fi
  warn "Internet check failed (DNS/captive portal/offline?)."
  warn "If you're on Wi‑Fi with a login page, open a browser and sign in, then retry."
  return 1
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

# ---------- Logging ----------
TF_LOG_DIR_DEFAULT="$HOME/.termux-fixer"
TF_LOG_DIR="${TF_LOG_DIR:-$TF_LOG_DIR_DEFAULT}"
TF_LOG_FILE=""

init_logging() {
  # Idempotent: the menu calls this before every action.
  if [[ -n "${TF_LOG_FILE:-}" && -f "$TF_LOG_FILE" ]]; then
    return 0
  fi
  mkdir -p "$TF_LOG_DIR"
  TF_LOG_FILE="$TF_LOG_DIR/termux-fixer-$(date +%Y%m%d-%H%M%S).log"
  export TF_LOG_DIR TF_LOG_FILE
  # Mirror stdout+stderr to logfile
  exec > >(tee -a "$TF_LOG_FILE") 2>&1
}

on_error() {
  local code=$?
  err "Something failed (exit code: $code)."
  err "Last command: ${BASH_COMMAND:-unknown}"
  err "Log saved to: ${TF_LOG_FILE:-$TF_LOG_DIR}"
  warn "Tip: Run 'Diagnose & create report' and attach it when asking for help."
  exit "$code"
}

trap 'on_error' ERR

# ---------- Package helpers ----------
pkg_update_upgrade() {
  check_internet || true
  info "Updating package lists…"
  pkg update -y || repo_repair_fallback
  info "Upgrading installed packages…"
  pkg upgrade -y
}

repo_repair_fallback() {
  # Common apt failures and safe remedies.
  warn "pkg update failed — attempting safe repo repair steps…"
  hash_sum_mismatch_fix || true
  lists_reset || true

  # Some users hit 'Release file is not valid yet/expired' due to device clock.
  if apt-get -o Acquire::Check-Valid-Until=false update >/dev/null 2>&1; then
    ok "Update succeeded with 'Check-Valid-Until=false'. Your device time may be wrong."
    warn "Fix: Enable automatic date & time in Android settings."
    return 0
  fi

  warn "Repo repair couldn't auto-resolve everything."
  warn "Next steps: run termux-change-repo (if available) and pick a mirror, then retry."
  return 1
}

pkg_install_list() {
  local pkgs=("$@")
  [[ ${#pkgs[@]} -eq 0 ]] && return 0
  info "Installing: ${pkgs[*]}"
  pkg install -y "${pkgs[@]}"
}

# ---------- Fixes ----------
setup_storage() {
  if [[ -d "$HOME/storage" ]]; then
    ok "Storage already linked ($HOME/storage)."
    return 0
  fi
  warn "Storage link not found. Running termux-setup-storage…"
  termux-setup-storage || true
  say "${yellow}→ If Android asks for permission, tap ALLOW.${reset}"
  sleep 2
  if [[ -d "$HOME/storage" ]]; then
    ok "Storage linked successfully."
  else
    warn "Storage link still not present. You can retry later from the menu."
  fi
}

fix_repo_keyring() {
  # Helps when apt complains about signatures/Release file issues.
  check_internet || true
  info "Refreshing Termux keyring and apt transport…"
  pkg install -y apt ca-certificates || true
  pkg reinstall -y termux-keyring 2>/dev/null || pkg install -y termux-keyring || true
  ok "Keyring refresh completed."
  info "Rebuilding package lists…"
  lists_reset || true
  apt update || true
}

fix_broken_packages() {
  info "Trying to fix broken packages…"
  apt --fix-broken install -y || true
  dpkg --configure -a || true
  ok "Broken-package routine completed (if issues remain, run Diagnose)."
}

clean_caches() {
  info "Cleaning apt/pkg caches…"
  apt clean || true
  rm -rf "$PREFIX/var/cache/apt/archives/partial" 2>/dev/null || true
  ok "Caches cleaned."
}

lists_reset() {
  info "Resetting apt lists (safe)…"
  rm -rf "$PREFIX/var/lib/apt/lists"/* 2>/dev/null || true
  mkdir -p "$PREFIX/var/lib/apt/lists/partial" 2>/dev/null || true
  ok "Apt lists reset."
}

hash_sum_mismatch_fix() {
  # Hash Sum mismatch / corrupted downloads are typically fixed by clearing caches and lists.
  info "Applying Hash Sum mismatch / corrupted cache fixes…"
  clean_caches || true
  lists_reset || true
  ok "Cache/list repair steps completed."
}

repo_status() {
  info "Checking Termux repo configuration…"
  local files=("$PREFIX/etc/apt/sources.list" "$PREFIX/etc/apt/sources.list.d"/*.list)
  local found=0
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    found=1
    say "${gray}•${reset} $f"
    sed -n '1,120p' "$f" | sed 's/^/    /'
  done
  if [[ $found -eq 0 ]]; then
    warn "No apt sources found where expected."
  fi

  # Heuristic warning for legacy Termux installs.
  if grep -Rqs "termux\\.net" "$PREFIX/etc/apt" 2>/dev/null; then
    warn "Your sources reference termux.net (legacy)."
    warn "Recommended: install Termux from F-Droid or GitHub releases, then run termux-change-repo."
  fi
}

optimize_termux() {
  info "Applying small quality-of-life tweaks…"

  # Safer default editor
  if ! grep -q "export EDITOR=" "$HOME/.bashrc" 2>/dev/null; then
    echo 'export EDITOR=nano' >> "$HOME/.bashrc"
  fi

  # Helpful aliases (non-destructive)
  if ! grep -q "# termux-fixer aliases" "$HOME/.bashrc" 2>/dev/null; then
    cat >> "$HOME/.bashrc" <<'BRC'

# termux-fixer aliases
alias ll='ls -la'
alias update='pkg update -y && pkg upgrade -y'
BRC
  fi

  ok "Tweaks added to ~/.bashrc (won't overwrite your existing settings)."
}

install_profiles() {
  local profile_file="$1"
  if [[ ! -f "$profile_file" ]]; then
    err "Profile not found: $profile_file"
    return 1
  fi
  mapfile -t pkgs < <(grep -vE '^(#|[[:space:]]*$)' "$profile_file")
  pkg_install_list "${pkgs[@]}"
}
