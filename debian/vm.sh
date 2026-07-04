```bash
#!/usr/bin/env bash

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

PACKAGES=(
  git
  cron
  wget
  curl
  tree
  lsof
  ripgrep
  qemu-guest-agent
  ca-certificates
  gnupg
  sudo
  vim
  htop
  net-tools
  bind9-dnsutils
  unzip
)

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

warn() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARNING: $*" >&2
}

fail() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2
  exit 1
}

require_root() {
  [[ "${EUID}" -eq 0 ]] || fail "Run as root. Example: sudo ./setup.sh"
}

check_debian() {
  [[ -r /etc/os-release ]] || fail "/etc/os-release not found."

  # shellcheck disable=SC1091
  source /etc/os-release

  [[ "${ID:-}" == "debian" ]] || fail "This script is for Debian only. Detected: ${PRETTY_NAME:-unknown}"

  log "Detected ${PRETTY_NAME}"
}

check_systemd() {
  command -v systemctl >/dev/null 2>&1 || fail "systemctl not found. This script expects a systemd Debian VM."
}

wait_for_apt_locks() {
  log "Checking apt/dpkg locks..."

  local timeout=300
  local waited=0

  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
    || fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
    || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do

    (( waited < timeout )) || fail "Timed out waiting for apt/dpkg lock."

    log "Another apt/dpkg process is running. Waiting..."
    sleep 5
    waited=$((waited + 5))
  done
}

repair_dpkg() {
  log "Repairing dpkg state if needed..."
  dpkg --configure -a
}

update_apt() {
  log "Updating package lists..."
  apt-get update
}

install_packages() {
  log "Installing packages..."
  apt-get install -y --no-install-recommends "${PACKAGES[@]}"
}

service_exists() {
  systemctl list-unit-files --type=service "$1" --no-legend 2>/dev/null | grep -q "^$1"
}

enable_service() {
  local service="$1"

  if service_exists "$service"; then
    log "Enabling and starting ${service}..."
    systemctl enable --now "$service" >/dev/null 2>&1 || warn "Could not enable/start ${service}."
  else
    warn "Service ${service} not found, skipping."
  fi
}

enable_services() {
  enable_service "cron.service"
  enable_service "qemu-guest-agent.service"
}

verify_packages() {
  log "Verifying installed packages..."

  local failed=0

  for pkg in "${PACKAGES[@]}"; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
      echo "OK: ${pkg}"
    else
      echo "MISSING: ${pkg}"
      failed=1
    fi
  done

  (( failed == 0 )) || fail "One or more packages are missing."
}

verify_commands() {
  echo ""
  log "Command checks:"

  command -v git >/dev/null 2>&1 && git --version || warn "git missing"
  command -v wget >/dev/null 2>&1 && wget --version | head -n1 || warn "wget missing"
  command -v curl >/dev/null 2>&1 && curl --version | head -n1 || warn "curl missing"
  command -v rg >/dev/null 2>&1 && rg --version | head -n1 || warn "ripgrep missing"
  command -v tree >/dev/null 2>&1 && echo "OK: tree available" || warn "tree missing"
  command -v lsof >/dev/null 2>&1 && echo "OK: lsof available" || warn "lsof missing"
  command -v ifconfig >/dev/null 2>&1 && echo "OK: ifconfig available" || warn "ifconfig missing"
  command -v dig >/dev/null 2>&1 && echo "OK: dig available" || warn "dig missing"
  command -v nslookup >/dev/null 2>&1 && echo "OK: nslookup available" || warn "nslookup missing"
}

verify_services() {
  echo ""
  log "Service status:"

  systemctl is-active --quiet cron \
    && echo "OK: cron active" \
    || fail "cron is not active"

  if systemctl is-active --quiet qemu-guest-agent; then
    echo "OK: qemu-guest-agent active"
  else
    warn "qemu-guest-agent is installed but not active."
    warn "On Proxmox, enable it with: qm set <VMID> --agent enabled=1"
  fi
}

cleanup_apt() {
  log "Cleaning apt cache..."
  apt-get clean
}

main() {
  require_root
  check_debian
  check_systemd
  wait_for_apt_locks
  repair_dpkg
  update_apt
  install_packages
  enable_services
  verify_packages
  verify_commands
  verify_services
  cleanup_apt

  echo ""
  log "Debian VM setup completed successfully."
}

main "$@"
```
