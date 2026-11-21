#!/data/data/com.termux/files/usr/bin/bash
# Secure remote SSH over Tailscale (free plan only).
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/tailscale.sh
source "$SCRIPT_DIR/lib/tailscale.sh"

PORT="$TF_SSH_DEFAULT_PORT"
HOST=""
ADDR=""
KEY=""
GENERATE=0
ROOT_PING=0
ACTION=""

usage() {
  cat <<USAGE
$TF_APP_NAME v$TF_VERSION -- Tailscale secure SSH

Usage:
  ./tools/tailscale.sh                       # interactive setup
  ./tools/tailscale.sh --status              # show security status
  ./tools/tailscale.sh --zero-trust          # generate free zero-trust policy
  ./tools/tailscale.sh --zero-click          # zero-click attack checklist
  ./tools/tailscale.sh --screen-ui           # screen/UI attack checklist
  ./tools/tailscale.sh --free-plan           # print cost/free-plan check

Setup options:
  --port <1024-65535>     Custom SSH port (default: $TF_SSH_DEFAULT_PORT)
  --address <addr|auto>   Listen address (default: detected Tailscale IP)
  --hostname <name>       MagicDNS name, e.g. redmi-13c.tailxxxx.ts.net
  --add-key <file|->      Add a client SSH public key ("-" reads stdin)
  --generate-key          Generate an ed25519 keypair on this device
  --ping-root             Also try kernel ICMP hardening with root (opt-in)

Security defaults:
  Password and keyboard-interactive auth are disabled.
  sshd listens only on 127.0.0.1 and the Tailscale address.
  Forwarding, X11, agent, tunnels, and root login are disabled.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --status|--audit) ACTION=status; shift ;;
    --policy-example|--zero-trust) ACTION=policy; shift ;;
    --free-plan|--cost-check) ACTION=free; shift ;;
    --zero-click) ACTION=zero_click; shift ;;
    --screen-ui) ACTION=ui; shift ;;
    --setup) ACTION=setup; shift ;;
    --interactive) ACTION=interactive; shift ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --address) ADDR="${2:-}"; shift 2 ;;
    --hostname) HOST="${2:-}"; shift 2 ;;
    --add-key) KEY="${2:-}"; shift 2 ;;
    --generate-key) GENERATE=1; shift ;;
    --ping-root) ROOT_PING=1; shift ;;
    *) err "Unknown option: $1"; usage; exit 2 ;;
  esac
done

if [[ -z "${TF_LOG_FILE:-}" ]]; then
  init_logging
fi
require_termux

if [[ -z "$ACTION" ]]; then
  if [[ -t 0 ]]; then
    ACTION=interactive
  else
    ACTION=setup
  fi
fi

case "$ACTION" in
  status)
    tailscale_status
    ;;
  policy)
    if [[ -z "$HOST" ]]; then
      HOST="$(tailscale_hostname || true)"
    fi
    tailscale_print_policy_example "$HOST" "$PORT" "$(tailscale_ip || true)"
    ;;
  free)
    tailscale_free_plan_notice
    ;;
  zero_click)
    zero_click_advice
    ;;
  ui)
    ui_attack_advice
    ;;
  interactive)
    tailscale_interactive
    ;;
  setup)
    tailscale_secure_setup "$PORT" "$HOST" "$KEY" "$GENERATE" "$ROOT_PING" "$ADDR"
    ;;
esac
