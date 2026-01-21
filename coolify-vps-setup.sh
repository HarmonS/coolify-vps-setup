#!/bin/bash
# universal-vps-setup-v5.sh - Coolify, Swap, UFW, & Optimized ClamAV

set -euo pipefail

# --- 0. ROOT CHECK ---
[[ $EUID -ne 0 ]] && echo "❌ Run as root." && exit 1

# --- 1. COLLECT INPUTS ---
echo "--- 🛠️  Universal VPS Setup (Coolify + Security) ---"
WANT_UPGRADE=$(read -p "Run system upgrade? (y/n) [y]: " res; echo "${res:-y}")
WANT_SWAP=$(read -p "Configure Swap? (y/n) [y]: " res; echo "${res:-y}")
SWAP_SIZE="2G"
[[ "$WANT_SWAP" == "y" ]] && read -p "  Swap size (e.g., 2G, 4G)? [2G]: " res && SWAP_SIZE="${res:-2G}"

WANT_CLAM=$(read -p "Install ClamAV? (y/n) [y]: " res; echo "${res:-y}")
WANT_COOLIFY=$(read -p "Install Coolify? (y/n) [y]: " res; echo "${res:-y}")

echo -e "\n🚀 Starting installation...\n"

# --- 2. APT LOCK & UPDATES ---
echo "--- Ensuring system is ready ---"
while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ; do sleep 5; done
apt update
[[ "$WANT_UPGRADE" == "y" ]] && DEBIAN_FRONTEND=noninteractive apt upgrade -y
apt install -y curl wget net-tools unattended-upgrades ufw fail2ban

# --- 3. SWAP (Universal dd Method) ---
if [[ "$WANT_SWAP" == "y" ]] && [ ! -f /swapfile ]; then
    echo "--- Creating $SWAP_SIZE Swap ---"
    dd if=/dev/zero of=/swapfile bs=1M count=$((${SWAP_SIZE//[!0-9]/} * 1024)) status=progress
    chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl vm.swappiness=10
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
fi

# --- 4. FIREWALL (UFW) ---
echo "--- Securing Network ---"
ufw default deny incoming
ufw default allow outgoing
for port in 22/tcp 80/tcp 443/tcp 443/udp 8000/tcp 6001/tcp 6002/udp; do ufw allow $port; done
ufw --force enable

# --- 5. CLAMAV (LOG-ONLY MODE) ---
CLAM_SCAN_CMD=""
if [[ "$WANT_CLAM" == "y" ]]; then
    echo "--- Configuring Antivirus ---"
    apt install -y clamav clamav-daemon
    systemctl stop clamav-freshclam || true
    freshclam || true
    systemctl start clamav-freshclam
    systemctl enable clamav-daemon && systemctl start clamav-daemon
    
    # Identify valid data targets (excludes virtual filesystems /sys /proc /dev)
    SCAN_TARGETS=""
    for dir in /etc /home /root /var/lib/docker/volumes; do
        [ -d "$dir" ] && SCAN_TARGETS="$SCAN_TARGETS $dir"
    done

    # LOG-ONLY SCAN: Cron at 3 AM. No --move, only logs hits.
    CLAM_SCAN_CMD="0 3 * * * /usr/bin/clamdscan --fdpass --no-summary -i $SCAN_TARGETS --log=/var/log/clamav/daily_scan.log"
    
    # Add alias to check results easily
    grep -q "alias check-virus" /root/.bashrc || echo "alias check-virus='grep \"FOUND\" /var/log/clamav/daily_scan.log || echo \"No threats found.\"'" >> /root/.bashrc
fi

# --- 6. MAINTENANCE CRON ---
echo "--- Setting up Maintenance ---"
CRON_MARKER="# VPS-MAINTENANCE"
(crontab -l 2>/dev/null | grep -v "$CRON_MARKER") > tmp_cron || true
{
    echo "$CRON_MARKER"
    [ -n "$CLAM_SCAN_CMD" ] && echo "$CLAM_SCAN_CMD"
    echo "0 4 * * 1 apt update && apt upgrade -y && apt autoremove -y"
    echo "0 5 * * 1 bash -c '[ -f /var/run/reboot-required ] && reboot'"
} >> tmp_cron
crontab tmp_cron && rm tmp_cron

# --- 7. COOLIFY ---
if [[ "$WANT_COOLIFY" == "y" ]]; then
    echo "--- Installing Coolify ---"
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
fi

# --- 8. FINISH ---
IP_ADDR=$(curl -s https://v4.ident.me || echo "YOUR_IP")
echo "--------------------------------------------------------"
echo "🎉 Setup Complete! Dashboard: http://$IP_ADDR:8000"
echo "Check virus logs: check-virus"
echo "--------------------------------------------------------"
sleep 10 && reboot
