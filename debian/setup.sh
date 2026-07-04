#!/usr/bin/env bash

set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive

PACKAGES=(
  ca-certificates
  curl
  wget
  git
  cron
  sudo
  vim
  htop
  tree
  unzip
  lsof
  ripgrep
  gnupg
  net-tools
  bind9-dnsutils
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
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run as root. Example: sudo ./setup.sh"
  fi
}

check_debian() {
  if [[ ! -r /etc/os-release ]]; then
    fail "/etc/os-release not found."
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID:-}" != "debian" ]]; then
    fail "This script is for Debian only. Detected: ${PRETTY_NAME:-unknown}"
  fi

  log "Detected ${PRETTY_NAME}"
}

check_systemd() {
  if ! command -v systemctl >/dev/null 2>&1; then
    fail "systemctl not found. This script expects a systemd-based Debian server."
  fi
}

wait_for_apt_locks() {
  log "Checking apt/dpkg locks..."

  local timeout=300
  local waited=0

  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 \
    || fuser /var/lib/dpkg/lock >/dev/null 2>&1 \
    || fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do

    if (( waited >= timeout )); then
      fail "Timed out waiting for apt/dpkg lock."
    fi

    log "Another apt/dpkg process is running. Waiting..."
    sleep 5
    waited=$((waited + 5))
  done
}

repair_dpkg() {
  log "Checking dpkg state..."
  dpkg --configure -a
}

update_apt() {
  log "Updating package lists..."
  apt-get update
}

install_packages() {
  log "Installing essential packages..."
  apt-get install -y --no-install-recommends "${PACKAGES[@]}"
}

service_exists() {
  systemctl list-unit-files \
    --type=service \
    "$1" \
    --no-legend 2>/dev/null \
    | grep -q "^$1"
}

enable_service() {
  local service="$1"

  if service_exists "$service"; then
    log "Enabling and starting ${service}..."

    if ! systemctl enable --now "$service" >/dev/null 2>&1; then
      warn "Could not enable/start ${service}."
    fi
  else
    warn "Service ${service} not found, skipping."
  fi
}

enable_services() {
  enable_service "cron.service"
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

  if (( failed != 0 )); then
    fail "One or more packages are missing."
  fi
}

verify_commands() {
  echo ""
  log "Command checks:"

  local commands=(
    git
    curl
    wget
    vim
    htop
    tree
    unzip
    lsof
    rg
    ifconfig
    dig
    nslookup
  )

  local cmd

  for cmd in "${commands[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      echo "OK: ${cmd}"
    else
      warn "${cmd} not found"
    fi
  done
}

verify_services() {
  echo ""
  log "Service status:"

  if systemctl is-active --quiet cron; then
    echo "OK: cron active"
  else
    fail "cron is not active"
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
  log "Debian server setup completed successfully."
}

main "$@"
