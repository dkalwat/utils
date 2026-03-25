#!/usr/bin/env bash
set -euo pipefail

# ── colors ──────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[bootstrap]${NC} $*"; }
warn() { echo -e "${YELLOW}[bootstrap]${NC} $*"; }
die()  { echo -e "${RED}[bootstrap]${NC} $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] && die "Run as root or via sudo"

DEPLOY_USER="${SUDO_USER:-$(logname 2>/dev/null || echo ubuntu)}"
log "Deploying for user: $DEPLOY_USER"

# ── system update ────────────────────────────────────────────
log "Updating system..."
apt-get update -qq
apt-get upgrade -y -qq
apt-get install -y -qq \
  curl wget git vim htop tmux \
  net-tools dnsutils nmap \
  ca-certificates gnupg lsb-release \
  unattended-upgrades apt-transport-https

# ── sudoers NOPASSWD ─────────────────────────────────────────
log "Configuring sudoers for $DEPLOY_USER..."
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-${DEPLOY_USER}-nopasswd
chmod 0440 /etc/sudoers.d/90-${DEPLOY_USER}-nopasswd
visudo -cf /etc/sudoers.d/90-${DEPLOY_USER}-nopasswd || die "sudoers syntax error"

# ── docker ───────────────────────────────────────────────────
log "Installing Docker..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

systemctl enable --now docker

usermod -aG docker "$DEPLOY_USER"
log "Added $DEPLOY_USER to docker group"

# ── optional: unattended upgrades (security only) ───────────
log "Enabling unattended security upgrades..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# ── optional: basic sysctl hardening ────────────────────────
log "Applying sysctl hardening..."
cat > /etc/sysctl.d/99-bootstrap-hardening.conf <<'EOF'
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
kernel.dmesg_restrict = 1
EOF
sysctl -p /etc/sysctl.d/99-bootstrap-hardening.conf -q

# ── done ─────────────────────────────────────────────────────
log "Bootstrap complete. Log out and back in (or newgrp docker) for group changes."
log "Installed: docker $(docker --version | awk '{print $3}' | tr -d ',')"
