#!/bin/bash
# coolify-vps-setup.sh - Clean Stage-Based Setup

set -euo pipefail

# --- 0. PRE-FLIGHT ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ Run as root."
   exit 1
fi

# Install basic diagnostic tools immediately
apt update && apt install -y curl wget net-tools

# --- 1. COLLECT INPUTS ---
echo "--- 🛠️  Coolify Setup Configuration ---"
WANT_SWAP=$(read -p "Configure Swap? (y/n) [y]: " res; echo "${res:-y}")
SWAP_SIZE="2G"
[[ "$WANT_SWAP" == "y" ]] && read -p "  Swap size [2G]: " res && SWAP_SIZE="${res:-2G}"

WANT_FW=$(read -p "Configure Firewall & Fail2ban? (y/n) [y]: " res; echo "${res:-y}")
WANT_CLAM=$(read -p "Install ClamAV? (y/n) [y]: " res; echo "${res:-y}")
WANT_COOLIFY=$(read -p "Install Coolify? (y/n) [y]: " res; echo "${res:-y}")

echo "🚀 Starting unattended install..."

# --- 2. SWAP ---
if [[ "$WANT_SWAP" == "y" ]]; then
    fallocate -l "$SWAP_SIZE" /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

# --- 3. FIREWALL ---
if [[ "$WANT_FW" == "y" ]]; then
    apt install -y ufw fail2ban
    ufw default deny incoming
    ufw default allow outgoing
    for port in 22 80 443 8000 6001 6002; do ufw allow $port/tcp; done
    ufw --force enable
    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sed -i 's/^bantime  = 10m/bantime  = 24h/' /etc/fail2ban/jail.local
    systemctl restart fail2ban
fi

# --- 4. CLAMAV & MAINTENANCE ---
if [[ "$WANT_CLAM" == "y" ]]; then
    apt install -y clamav clamav-daemon
    systemctl stop clamav-freshclam || true
    freshclam || true
    systemctl start clamav-freshclam
fi
apt install -y unattended-upgrades
# Standard maintenance cron
(crontab -l 2>/dev/null | grep -v "# EXPERT-VPS-SETUP") > tmp_cron || true
echo "0 3 * * 1 apt update && apt upgrade -y" >> tmp_cron
crontab tmp_cron && rm tmp_cron

# --- 5. COOLIFY & POST-BOOT PATCH ---
if [[ "$WANT_COOLIFY" == "y" ]]; then
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
    wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    chmod +x /usr/local/bin/ufw-docker
    # Patch runs 30s after reboot to ensure Docker is up
    (crontab -l 2>/dev/null; echo "@reboot sleep 30 && /usr/local/bin/ufw-docker install && ufw reload && crontab -l | grep -v '/usr/local/bin/ufw-docker install' | crontab -") | crontab -
fi

IP_ADDR=$(curl -s https://v4.ident.me || echo "YOUR_IP")
echo "🎉 Done! URL: http://$IP_ADDR:8000"
sleep 5 && reboot
