#!/bin/bash
# coolify-vps-setup.sh - Interactive Questions First, then Unattended Install

set -euo pipefail

# --- 0. ROOT CHECK ---
if [[ $EUID -ne 0 ]]; then
   echo "❌ This script must be run as root."
   exit 1
fi

# --- 1. COLLECT ALL INPUTS FIRST ---
echo "--- 🛠️  Coolify Setup Configuration ---"
echo "Please answer the following questions to begin the unattended install."
echo ""

# Swap Setup
WANT_SWAP=$(read -p "Configure a Swap file? (y/n) [y]: " res; echo "${res:-y}")
SWAP_SIZE="2G"
if [[ "$WANT_SWAP" == "y" ]]; then
    read -p "  Enter Swap size (e.g., 2G, 4G) [2G]: " res
    SWAP_SIZE="${res:-2G}"
fi

# Firewall Setup
WANT_FW=$(read -p "Configure Firewall (UFW) & Fail2ban? (y/n) [y]: " res; echo "${res:-y}")

# ClamAV Setup
WANT_CLAM=$(read -p "Install ClamAV Malware Scanner? (y/n) [y]: " res; echo "${res:-y}")
CLAM_FREQ="1"
if [[ "$WANT_CLAM" == "y" ]]; then
    read -p "  Scan frequency? 1) Daily 2) Weekly [1]: " res
    CLAM_FREQ="${res:-1}"
fi

# Coolify Install
WANT_COOLIFY=$(read -p "Install Coolify now? (y/n) [y]: " res; echo "${res:-y}")

echo ""
echo "✅ All inputs received. Starting unattended installation..."
echo "--------------------------------------------------------"

# --- 2. SWAP ---
if [[ "$WANT_SWAP" == "y" ]]; then
    if [ ! -f /swapfile ]; then
        echo "--- Creating $SWAP_SIZE Swap File ---"
        fallocate -l "$SWAP_SIZE" /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        sysctl vm.swappiness=10
        echo 'vm.swappiness=10' >> /etc/sysctl.conf
    fi
fi

# --- 3. FIREWALL & FAIL2BAN ---
if [[ "$WANT_FW" == "y" ]]; then
    echo "--- Installing Security Tools ---"
    apt update && apt install -y ufw wget fail2ban
    ufw default deny incoming
    ufw default allow outgoing
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw allow 8000/tcp
    ufw allow 6001/tcp
    ufw allow 6002/tcp
    ufw --force enable

    cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sed -i 's/^bantime  = 10m/bantime  = 24h/' /etc/fail2ban/jail.local
    sed -i 's/^maxretry = 5/maxretry = 3/' /etc/fail2ban/jail.local
    systemctl restart fail2ban
fi

# --- 4. MAINTENANCE & CLAMAV ---
echo "--- Configuring Maintenance & Updates ---"
CLAM_CMD=""
if [[ "$WANT_CLAM" == "y" ]]; then
    apt install -y clamav clamav-daemon
    systemctl stop clamav-freshclam || true
    freshclam || true # || true in case of mirror timeouts
    systemctl start clamav-freshclam
    systemctl enable clamav-daemon
    systemctl start clamav-daemon
    
    CLAM_CRON="0 3 * * *"
    [[ "$CLAM_FREQ" == "2" ]] && CLAM_CRON="0 3 * * 1"
    CLAM_CMD="$CLAM_CRON /usr/bin/clamdscan --fdpass -r / --exclude-dir='^/sys|^/proc|^/dev|^/var/lib/docker' -i --log=/var/log/clamav/daily_scan.log"
fi

apt install -y unattended-upgrades update-notifier-common
CRON_MARKER="# EXPERT-VPS-SETUP"
tmpfile=$(mktemp)
crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$tmpfile" || true
{
    echo "$CRON_MARKER"
    [ -n "$CLAM_CMD" ] && echo "$CLAM_CMD"
    echo "0 3 * * 1 apt update && apt upgrade -y && apt autoremove -y && apt clean"
    echo "0 4 * * 1 bash -c '[ -f /var/run/reboot-required ] && reboot'"
} >> "$tmpfile"
crontab "$tmpfile"
rm -f "$tmpfile"

# --- 5. COOLIFY & POST-REBOOT DOCKER PATCH ---
if [[ "$WANT_COOLIFY" == "y" ]]; then
    echo "--- Installing Coolify ---"
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
    
    echo "--- Preparing Post-Reboot Docker Security Patch ---"
    wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    chmod +x /usr/local/bin/ufw-docker
    
    # Schedule the patch to run 30s after reboot, then remove itself from crontab
    (crontab -l 2>/dev/null; echo "@reboot sleep 30 && /usr/local/bin/ufw-docker install && ufw reload && crontab -l | grep -v '/usr/local/bin/ufw-docker install' | crontab -") | crontab -
fi

echo "--- Setup Finished! Rebooting in 10 seconds ---"
sleep 10
reboot
