#!/bin/bash
# expert-vps-setup-interactive.sh - Modular Security & Maintenance

set -euo pipefail

# --- HELPER FUNCTIONS ---
get_input() {
    local prompt=$1
    local default=$2
    read -p "$prompt [$default]: " val
    echo "${val:-$default}"
}

# --- 1. SWAP CONFIGURATION ---
setup_swap() {
    echo "--- Swap Configuration ---"
    local swap_size=$(get_input "How much Swap do you want? (e.g., 2G, 4G)" "2G")
    
    if [ -f /swapfile ]; then
        echo "Swapfile already exists. Skipping creation."
    else
        sudo fallocate -l "$swap_size" /swapfile
        sudo chmod 600 /swapfile
        sudo mkswap /swapfile
        sudo swapon /swapfile
        echo '/swapfile swap swap defaults 0 0' | sudo tee -a /etc/fstab
        sudo sysctl vm.swappiness=10
        echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
        echo "✅ $swap_size Swap enabled."
    fi
}

# --- 2. FIREWALL & DOCKER SECURITY ---
setup_ufw_docker() {
    echo "--- Installing ufw-docker & Configuring Rules ---"
    # Install the ufw-docker patch to stop Docker from bypassing UFW
    sudo wget -O /usr/local/bin/ufw-docker https://github.com/chaifeng/ufw-docker/raw/master/ufw-docker
    sudo chmod +x /usr/local/bin/ufw-docker
    sudo ufw-docker install
    
    # Strict Default Policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow Essential Ports
    sudo ufw allow 22/tcp      # SSH
    sudo ufw allow 80/tcp      # HTTP
    sudo ufw allow 443/tcp     # HTTPS
    sudo ufw allow 8000/tcp    # Coolify UI
    sudo ufw allow 6001/tcp    # Coolify Real-time
    sudo ufw allow 6002/tcp    # Coolify Terminal
    
    sudo ufw --force enable
    echo "✅ Firewall secured with ufw-docker and strict default policies."
}

# --- 3. MAINTENANCE & SCANS (WITH CRON MARKER) ---
setup_maintenance_cron() {
    echo "--- Configuring Maintenance & ClamAV ---"
    
    local freq_choice=$(get_input "ClamAV Frequency? 1) Daily 2) Weekly" "1")
    local clam_cron="0 3 * * *"
    [[ "$freq_choice" == "2" ]] && clam_cron="0 3 * * 1"

    # Optimized ClamAV Scan Command
    local clam_cmd="/usr/bin/clamscan -r / --exclude-dir='^/sys|^/proc|^/dev|^/var/lib/docker' -i --log=/var/log/clamav/daily_scan.log"
    
    # Cron Marker Logic
    CRON_MARKER="# EXPERT-VPS-SETUP"
    tmpfile=$(mktemp)
    
    # Remove old entries with the same marker to prevent duplicates
    crontab -l 2>/dev/null | grep -v "$CRON_MARKER" > "$tmpfile" || true

    # Append new clean entries
    {
        echo "$CRON_MARKER"
        echo "$clam_cron $clam_cmd"
        echo "0 3 * * 1 sudo apt update && sudo apt upgrade -y && sudo apt autoremove -y && sudo apt clean"
        echo "0 4 * * 1 sudo bash -c '[ -f /var/run/reboot-required ] && reboot'"
    } >> "$tmpfile"

    crontab "$tmpfile"
    rm -f "$tmpfile"

    echo "✅ Maintenance and Optimized ClamAV scheduled with duplicate protection."
}

# --- MAIN EXECUTION ---
echo "--- Welcome to the Expert VPS Wizard ---"
setup_swap
setup_ufw_docker
setup_maintenance_cron

read -p "Install Coolify now? (y/n): " install_cool
if [[ "$install_cool" == "y" ]]; then
    curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
fi

echo "--- Setup Finished! System will reboot in 10 seconds ---"
sleep 10
sudo reboot
